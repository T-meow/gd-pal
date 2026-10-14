// Adapted from Yumo (MIT); see licenses/yumo/PORTING.md.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using GdPal.Conversation;

namespace GdPal.Agents;

/// <summary>Text ACP v1 over stdio. Only explicitly registered programs are started.</summary>
public sealed class AcpAgentConnector(Func<WorkAgent, IReadOnlyDictionary<string, string>>? secrets = null, WorkOptions? options = null) : IAgentConnector
{
    private readonly WorkOptions _options = options ?? new();
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly Dictionary<string, Connection> _connections = new();
    private readonly HashSet<Connection> _probes = new();
    private readonly CancellationTokenSource _shutdown = new();
    private bool _disposed;
    private async Task<Connection> ConnectionAsync(WorkAgent agent, string directory, string key, CancellationToken token)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_connections.TryGetValue(key, out var found) && found.Alive) return found;
            if (found is not null) await found.DisposeAsync().ConfigureAwait(false);
            var connection = new Connection(agent, directory, secrets?.Invoke(agent) ?? new Dictionary<string, string>(), _options);
            try { await connection.InitializeAsync(token).ConfigureAwait(false); }
            catch { await connection.DisposeAsync().ConfigureAwait(false); throw; }
            _connections[key] = connection; return connection;
        }
        finally { _gate.Release(); }
    }
    public async Task<AgentProbe> ProbeAsync(WorkAgent agent, string directory, CancellationToken cancellation)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _shutdown.Token);
        Connection connection;
        await _gate.WaitAsync(linked.Token).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            connection = new(agent, directory, secrets?.Invoke(agent) ?? new Dictionary<string, string>(), _options); _probes.Add(connection);
        }
        finally { _gate.Release(); }
        try { await connection.InitializeAsync(linked.Token).ConfigureAwait(false); return connection.Probe; }
        finally
        {
            await connection.DisposeAsync().ConfigureAwait(false);
            await _gate.WaitAsync().ConfigureAwait(false); try { _probes.Remove(connection); } finally { _gate.Release(); }
        }
    }
    public async Task<WorkResult> ExecuteAsync(WorkExecutionContext context, CancellationToken cancellation)
    {
        context.CheckAuthorization(); var agent = context.Agent ?? throw new ArgumentException("Missing Agent configuration.");
        string key = $"{agent.Id}/{agent.Revision}/{context.Task.ProfileId}/{context.Workspace.Id}/{context.Workspace.Revision}";
        var connection = await ConnectionAsync(agent, context.Workspace.Directory, key, cancellation).ConfigureAwait(false);
        context.CheckAuthorization();
        try { return await connection.RunAsync(context, cancellation).ConfigureAwait(false); }
        catch { await connection.DisposeAsync().ConfigureAwait(false); throw; }
    }
    public async ValueTask DisposeAsync()
    {
        _shutdown.Cancel();
        await _gate.WaitAsync().ConfigureAwait(false);
        try { _disposed = true; foreach (var connection in _connections.Values.Concat(_probes).Distinct()) await connection.DisposeAsync().ConfigureAwait(false); _connections.Clear(); _probes.Clear(); }
        finally { _gate.Release(); }
    }
    private sealed class Connection : IAsyncDisposable
    {
        private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);
        private readonly Process _process;
        private readonly WorkOptions _options;
        private readonly SemaphoreSlim _writer = new(1, 1);
        private readonly CancellationTokenSource _lifetime = new();
        private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonNode>> _pending = new();
        private readonly HashSet<string> _sessions = new();
        private readonly Task _pump, _errors;
        private readonly object _errorGate = new();
        private string _errorTail = "";
        private long _request;
        private Run? _run;
        private bool _closed, _canClose, _canLoad;
        public AgentProbe Probe { get; private set; } = new("ACP Agent", "", false);
        public bool Alive => !_closed && !_pump.IsCompleted && !_process.HasExited;
        private sealed class Run(WorkExecutionContext context, string sessionId, CancellationToken token)
        {
            public WorkExecutionContext Context { get; } = context;
            public string SessionId { get; } = sessionId;
            public CancellationToken Token { get; } = token;
            public StringBuilder Text { get; } = new();
            public Dictionary<string, JsonObject> Tools { get; } = new();
            public bool Active = true;
        }
        public Connection(WorkAgent agent, string directory, IReadOnlyDictionary<string, string> secrets, WorkOptions options)
        {
            _options = options;
            if (!Path.IsPathFullyQualified(agent.Executable) || !File.Exists(agent.Executable)) throw new FileNotFoundException("Agent 程序已移动，请重新配置。");
            if (Path.GetExtension(agent.Executable).ToLowerInvariant() is ".cmd" or ".bat" or ".ps1") throw new ArgumentException("请选择实际可执行程序；脚本请使用解释器路径和固定参数启动。");
            var start = new ProcessStartInfo(agent.Executable) { WorkingDirectory = directory, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
            foreach (string argument in agent.Arguments) start.ArgumentList.Add(argument);
            // Avoid handing Yumo's ambient provider credentials to an unrelated executable.
            foreach (string name in start.Environment.Keys.Where(k => k.Contains("TOKEN", StringComparison.OrdinalIgnoreCase) || k.Contains("SECRET", StringComparison.OrdinalIgnoreCase) || k.Contains("PASSWORD", StringComparison.OrdinalIgnoreCase) || k.EndsWith("_KEY", StringComparison.OrdinalIgnoreCase)).ToArray()) start.Environment.Remove(name);
            foreach (var pair in agent.Environment.Concat(secrets)) start.Environment[pair.Key] = pair.Value;
            _process = Process.Start(start) ?? throw new IOException("Agent 未能启动。");
            _pump = Task.Run(PumpAsync); _errors = Task.Run(ErrorsAsync);
        }
        public async Task InitializeAsync(CancellationToken cancellation)
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _lifetime.Token); timeout.CancelAfter(_options.HandshakeTimeout);
            var result = await RequestAsync("initialize", new { protocolVersion = 1, clientCapabilities = new { }, clientInfo = new { name = "gd-pal", version = "1.0" } }, timeout.Token).ConfigureAwait(false);
            if (result["protocolVersion"]?.GetValue<int>() != 1) throw new IOException("Agent 未提供兼容的 ACP v1 协议。");
            var caps = result["agentCapabilities"]; var sessions = caps?["sessionCapabilities"];
            Probe = new(result["agentInfo"].String("name", "ACP Agent"), result["agentInfo"].String("version"), sessions?["resume"] is not null);
            _canClose = sessions?["close"] is not null; _canLoad = caps?["loadSession"]?.GetValue<bool>() == true;
        }
        public async Task<WorkResult> RunAsync(WorkExecutionContext context, CancellationToken cancellation)
        {
            string sessionId = context.Task.AgentSessionId;
            if (sessionId.Length > 0 && !_sessions.Contains(sessionId))
            {
                string method = Probe.CanResume ? "session/resume" : _canLoad ? "session/load" : "";
                if (method.Length == 0) throw new InvalidOperationException("此 Agent 不支持恢复已关闭的会话，请新建工作任务。");
                await RequestAsync(method, new { sessionId, cwd = context.Workspace.Directory, mcpServers = Array.Empty<object>() }, cancellation).ConfigureAwait(false);
                _sessions.Add(sessionId);
            }
            if (sessionId.Length == 0)
            {
                var session = await RequestAsync("session/new", new { cwd = context.Workspace.Directory, mcpServers = Array.Empty<object>() }, cancellation).ConfigureAwait(false);
                sessionId = session.String("sessionId"); if (sessionId.Length == 0) throw new IOException("Agent 没有返回会话标识。");
                _sessions.Add(sessionId); await context.Report("agent_session", JsonValue.Create(sessionId)).ConfigureAwait(false);
            }
            context.CheckAuthorization();
            var run = new Run(context, sessionId, cancellation); _run = run;
            var prompt = RequestAsync("session/prompt", new { sessionId, prompt = new[] { new { type = "text", text = context.Task.Messages.Last(m => m.Role == "user").Text } } }, _lifetime.Token);
            try
            {
                var result = await prompt.WaitAsync(cancellation).ConfigureAwait(false);
                context.CheckAuthorization(); string reason = result.String("stopReason");
                if (_canClose && Probe.CanResume)
                {
                    await RequestAsync("session/close", new { sessionId }, cancellation).WaitAsync(_options.CancelGrace, cancellation).ConfigureAwait(false); _sessions.Remove(sessionId);
                }
                return new(run.Text.ToString(), reason == "end_turn" ? "completed" : reason == "cancelled" ? "cancelled" : "failed", reason == "end_turn" ? "" : "Agent 结束原因：" + reason, "agent");
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                run.Active = false;
                try
                {
                    using var grace = new CancellationTokenSource(_options.CancelGrace);
                    await WriteAsync(new { jsonrpc = "2.0", method = "session/cancel", @params = new { sessionId } }, grace.Token).ConfigureAwait(false);
                    await prompt.WaitAsync(grace.Token).ConfigureAwait(false);
                    if (!_canClose) throw new IOException("Agent does not support closing sessions.");
                    await RequestAsync("session/close", new { sessionId }, grace.Token).ConfigureAwait(false); _sessions.Remove(sessionId);
                }
                catch { await DisposeAsync().ConfigureAwait(false); }
                throw;
            }
            catch { await DisposeAsync().ConfigureAwait(false); throw; }
            finally { run.Active = false; if (ReferenceEquals(_run, run)) _run = null; }
        }
        private async Task<JsonNode> RequestAsync(string method, object parameters, CancellationToken token)
        {
            long id = Interlocked.Increment(ref _request); string key = id.ToString(System.Globalization.CultureInfo.InvariantCulture);
            var answer = new TaskCompletionSource<JsonNode>(TaskCreationOptions.RunContinuationsAsynchronously); _pending[key] = answer;
            try
            {
                await WriteAsync(new { jsonrpc = "2.0", id, method, @params = parameters }, token).ConfigureAwait(false);
                return await answer.Task.WaitAsync(token).ConfigureAwait(false);
            }
            finally { _pending.TryRemove(key, out _); }
        }
        private async Task WriteAsync(object value, CancellationToken token)
        {
            string line = JsonSerializer.Serialize(value, WireJson);
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
            await _writer.WaitAsync(linked.Token).ConfigureAwait(false);
            try
            {
                ObjectDisposedException.ThrowIf(_closed, this); linked.Token.ThrowIfCancellationRequested();
                await _process.StandardInput.WriteLineAsync(line.AsMemory(), linked.Token).ConfigureAwait(false);
                await _process.StandardInput.FlushAsync(linked.Token).ConfigureAwait(false);
            }
            finally { _writer.Release(); }
        }
        private async Task PumpAsync()
        {
            try
            {
                var buffer = new char[4096]; var line = new StringBuilder();
                while (true)
                {
                    int count = await _process.StandardOutput.ReadAsync(buffer.AsMemory(), _lifetime.Token).ConfigureAwait(false); if (count == 0) break;
                    for (int i = 0; i < count; i++)
                    {
                        if (buffer[i] != '\n') { line.Append(buffer[i]); if (line.Length > 2 * 1024 * 1024) throw new IOException("ACP 消息过大。"); continue; }
                        string text = line.ToString().Trim(); line.Clear(); if (text.Length == 0) continue;
                        var frame = JsonNode.Parse(text)!.AsObject();
                        if (frame["id"] is { } id && (frame.ContainsKey("result") || frame.ContainsKey("error")))
                        {
                            if (_pending.TryGetValue(id.ToJsonString(), out var completion))
                            {
                                if (frame["error"] is { } error) completion.TrySetException(new IOException("ACP：" + error.String("message", "请求失败")));
                                else completion.TrySetResult(frame["result"]?.DeepClone() ?? new JsonObject());
                            }
                        }
                        else if (frame.String("method") == "session/request_permission" && frame["id"] is not null)
                            _ = HandlePermissionAsync(frame);
                        else if (frame["id"] is not null)
                            await WriteAsync(new { jsonrpc = "2.0", id = frame["id"], error = new { code = -32601, message = "GD Pal does not provide client filesystem or terminal execution." } }, _lifetime.Token).ConfigureAwait(false);
                        else if (frame.String("method") == "session/update") await UpdateAsync(frame["params"]!).ConfigureAwait(false);
                    }
                }
                throw new IOException("ACP 进程已退出。" + ErrorTail());
            }
            catch (Exception ex) { foreach (var pending in _pending.Values) pending.TrySetException(ex is OperationCanceledException ? new IOException("ACP 连接已关闭。") : ex); }
        }
        private string ErrorTail() { lock (_errorGate) return _errorTail; }
        private async Task ErrorsAsync()
        {
            try
            {
                char[] buffer = new char[1024]; int count;
                while ((count = await _process.StandardError.ReadAsync(buffer.AsMemory(), _lifetime.Token).ConfigureAwait(false)) > 0)
                    lock (_errorGate) { _errorTail += new string(buffer, 0, count); if (_errorTail.Length > 4000) _errorTail = _errorTail[^4000..]; }
            }
            catch (Exception ex) when (ex is IOException or OperationCanceledException or ObjectDisposedException) { }
        }
        private async Task UpdateAsync(JsonNode parameters)
        {
            var run = _run;
            if (run is null || !run.Active || run.Token.IsCancellationRequested || parameters.String("sessionId") != run.SessionId) return;
            try
            {
                run.Context.CheckAuthorization(); var update = parameters["update"]!;
                if (update.String("sessionUpdate") is "tool_call" or "tool_call_update" && update.String("toolCallId").Length > 0)
                {
                    lock (run.Tools)
                    {
                        string id = update.String("toolCallId");
                        if (!run.Tools.TryGetValue(id, out var known)) run.Tools[id] = known = new();
                        foreach (var pair in update.AsObject()) known[pair.Key] = pair.Value?.DeepClone();
                    }
                }
                if (update.String("sessionUpdate") == "agent_message_chunk" && update["content"].String("type") == "text")
                { if (run.Text.Length > 128000) throw new IOException("Agent 回复过长。"); run.Text.Append(update["content"].String("text")); }
                await run.Context.Report("agent_update", update).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { }
        }
        private async Task HandlePermissionAsync(JsonObject frame)
        {
            string? selected = null; var run = _run;
            try
            {
                var parameters = frame["params"]!;
                if (run is { Active: true } && !run.Token.IsCancellationRequested && parameters.String("sessionId") == run.SessionId)
                {
                    var options = (parameters["options"] as JsonArray ?? []).Where(o => o.String("kind") is "allow_once" or "reject_once")
                        .Select(o => new WorkPermissionOption(o.String("optionId"), o.String("name"), o.String("kind"))).ToArray();
                    if (options.Length > 0)
                    {
                        var call = parameters["toolCall"]?.DeepClone().AsObject() ?? new();
                        lock (run.Tools)
                            if (run.Tools.TryGetValue(call.String("toolCallId"), out var known))
                                foreach (var pair in known) if (call[pair.Key] is null) call[pair.Key] = pair.Value?.DeepClone();
                        string description = call.String("title", "Agent 请求额外权限") + "\n" + call.ToJsonString(new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
                        selected = await run.Context.RequestPermission(new(ChatJson.Id(), ChatJson.Clip(description, 4000), options), run.Token).ConfigureAwait(false);
                        run.Context.CheckAuthorization();
                        if (!run.Active || !ReferenceEquals(_run, run) || run.Token.IsCancellationRequested || !options.Any(o => o.Id == selected)) selected = null;
                    }
                }
            }
            catch { selected = null; }
            try
            {
                object outcome = selected is null ? new { outcome = "cancelled" } : new { outcome = "selected", optionId = selected };
                await WriteAsync(new { jsonrpc = "2.0", id = frame["id"], result = new { outcome } }, _lifetime.Token).ConfigureAwait(false);
            }
            catch (Exception ex) when (ex is IOException or OperationCanceledException or ObjectDisposedException or InvalidOperationException) { }
        }
        private readonly object _disposeGate = new();
        private Task? _disposeTask;
        public ValueTask DisposeAsync() { lock (_disposeGate) return new(_disposeTask ??= DisposeCoreAsync()); }
        private async Task DisposeCoreAsync()
        {
            if (_closed) return; _closed = true; if (_run is { } run) run.Active = false;
            _lifetime.Cancel();
            if (await _writer.WaitAsync(_options.CancelGrace).ConfigureAwait(false))
            {
                try { _process.StandardInput.Close(); } catch (Exception ex) when (ex is IOException or InvalidOperationException) { }
                finally { _writer.Release(); }
            }
            try { await _process.WaitForExitAsync().WaitAsync(_options.CancelGrace).ConfigureAwait(false); }
            catch (TimeoutException) { try { _process.Kill(entireProcessTree: true); await _process.WaitForExitAsync().WaitAsync(_options.CancelGrace).ConfigureAwait(false); } catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or TimeoutException) { } }
            try { await Task.WhenAll(_pump, _errors).WaitAsync(_options.CancelGrace).ConfigureAwait(false); } catch (Exception ex) when (ex is IOException or OperationCanceledException or TimeoutException) { }
            _process.Dispose();
        }
    }
}
