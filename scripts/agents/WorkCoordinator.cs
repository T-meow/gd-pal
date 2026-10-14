// Adapted from Yumo (MIT); see licenses/yumo/PORTING.md.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using GdPal.Conversation;

namespace GdPal.Agents;

/// <summary>Human work records never enter conversation journals or memory source discovery.</summary>
public sealed class WorkCoordinator : IDisposable
{
    private readonly object _gate = new();
    private readonly string _root, _managedRoot;
    private readonly IAgentConnector _agent;
    private readonly WorkOptions _options;
    private readonly Action<WorkEvent> _publish;
    private readonly WorkConfiguration _configuration;
    private readonly Dictionary<string, WorkTask> _tasks = new();
    private readonly Dictionary<string, CancellationTokenSource> _running = new();
    private readonly Dictionary<string, TaskCompletionSource<string?>> _permissions = new();
    private readonly Channel<string> _queue = Channel.CreateUnbounded<string>(new() { SingleReader = true });
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Task _worker;
    private bool _disposed;
    private readonly HashSet<string> _removedProfiles = new();
    public bool HasActiveTasks { get { lock (_gate) return _tasks.Values.Any(t => t.Unfinished); } }
    public WorkCoordinator(string dataRoot, IAgentConnector agent, Action<WorkEvent> publish, WorkOptions? options = null)
    {
        _managedRoot = Path.GetFullPath(dataRoot); _root = Path.Combine(_managedRoot, "work");
        _agent = agent; _publish = publish; _options = options ?? new();
        _configuration = File.Exists(ConfigPath) ? LocalFiles.Read<WorkConfiguration>(ConfigPath) : new();
        if (_configuration.SchemaVersion != 1) throw new InvalidDataException("工作配置版本无效。");
        string directory = Path.Combine(_root, "tasks");
        if (Directory.Exists(directory)) foreach (string file in Directory.EnumerateFiles(directory, "*.json"))
        {
            var task = LocalFiles.Read<WorkTask>(file);
            if (!PackageCodec.ValidId(task.Id) || task.SchemaVersion != 1) throw new InvalidDataException("工作记录无效。");
            _tasks.Add(task.Id, task);
            if (task.Unfinished) { task.Status = "interrupted"; task.Permission = null; task.Error = "上次执行已中断，请确认后继续；已产生的文件修改会保留。"; Save(task); }
        }
        _worker = Task.Run(RunAsync);
    }
    private string ConfigPath => Path.Combine(_root, "config.json");
    private string TaskPath(string id) => WorkStorage.Within(_root, "tasks/" + id + ".json");
    private static T Copy<T>(T value) => JsonSerializer.Deserialize<T>(ChatJson.Encode(value), ChatJson.Options)!;
    private void Save(WorkTask task)
    { task.Revision++; task.UpdatedAt = ChatJson.Now(); LocalFiles.Write(TaskPath(task.Id), ChatJson.Encode(task)); }
    private void SaveConfiguration() => LocalFiles.Write(ConfigPath, ChatJson.Encode(_configuration));
    private void Alive() { if (_disposed) throw new ObjectDisposedException(nameof(WorkCoordinator)); }
    private void Notify(WorkTask task, string kind = "changed", JsonNode? data = null) => _publish(new(task.Id, task.ProfileId, kind, data));
    public WorkConfiguration Configuration(string profileId)
    {
        lock (_gate) { var result = Copy(_configuration); result.Grants.RemoveAll(g => g.ProfileId != profileId); return result; }
    }
    public WorkWorkspace SaveWorkspace(WorkWorkspace value)
    {
        lock (_gate)
        {
            Alive(); value = Copy(value); value.Directory = WorkStorage.ValidateRoot(value.Directory, _managedRoot);
            value.Name = value.Name.Trim(); if (value.Name.Length is < 1 or > 80) throw new ArgumentException("工作区名称需要 1～80 字。");
            var old = _configuration.Workspaces.SingleOrDefault(w => w.Id == value.Id);
            if (old is null && value.Id.Length > 0) throw new ArgumentException("工作区已不存在。");
            if (old is not null && old.Revision != value.Revision) throw new InvalidOperationException("工作区已变化，请刷新。");
            value.Id = old?.Id ?? ChatJson.Id(); value.Revision = (old?.Revision ?? 0) + 1;
            _configuration.Workspaces.RemoveAll(w => w.Id == value.Id); _configuration.Workspaces.Add(value);
            _configuration.Grants.RemoveAll(g => g.WorkspaceId == value.Id); SaveConfiguration();
            CancelWhere(t => t.WorkspaceId == value.Id); return Copy(value);
        }
    }
    public WorkAgent SaveAgent(WorkAgent value)
    {
        lock (_gate)
        {
            Alive(); value = Copy(value);
            if (value.Name.Trim().Length is < 1 or > 80 || !Path.IsPathFullyQualified(value.Executable) || !File.Exists(value.Executable)) throw new ArgumentException("请选择 Agent 的实际程序路径并填写名称。");
            if (value.Arguments.Length > 40 || value.Arguments.Any(a => a.Length > 4000 || a.Contains('\0')) || value.Environment.Count + value.SecretEnvironmentNames.Length > 40 ||
                value.Environment.Keys.Concat(value.SecretEnvironmentNames).Any(k => k.Length == 0 || k.Contains('=') || k.Any(char.IsControl))) throw new ArgumentException("Agent 参数或环境变量无效。");
            var old = _configuration.Agents.SingleOrDefault(a => a.Id == value.Id);
            if (old is null && value.Id.Length > 0) throw new ArgumentException("Agent 已不存在。");
            if (old is not null && old.Revision != value.Revision) throw new InvalidOperationException("Agent 配置已变化，请刷新。");
            value.Id = old?.Id ?? ChatJson.Id(); value.Revision = (old?.Revision ?? 0) + 1;
            _configuration.Agents.RemoveAll(a => a.Id == value.Id); _configuration.Agents.Add(value);
            _configuration.Grants.RemoveAll(g => g.ExecutorId == value.Id); SaveConfiguration();
            CancelWhere(t => t.ExecutorId == value.Id); return Copy(value);
        }
    }
    public void Grant(string profileId, string workspaceId, string executorId, bool allow, long workspaceRevision, long agentRevision)
    {
        lock (_gate)
        {
            Alive(); var workspace = _configuration.Workspaces.Single(w => w.Id == workspaceId);
            var agent = _configuration.Agents.Single(a => a.Id == executorId);
            if (workspace.Revision != workspaceRevision || (agent?.Revision ?? 0) != agentRevision) throw new InvalidOperationException("配置已变化，请重新核对授权。");
            _configuration.Grants.RemoveAll(g => g.ProfileId == profileId && g.WorkspaceId == workspaceId && g.ExecutorId == executorId);
            if (allow) _configuration.Grants.Add(new() { ProfileId = profileId, WorkspaceId = workspaceId, WorkspaceRevision = workspace.Revision, ExecutorId = executorId, AgentRevision = agent?.Revision ?? 0 });
            SaveConfiguration();
            if (!allow) CancelWhere(t => t.ProfileId == profileId && t.WorkspaceId == workspaceId && t.ExecutorId == executorId);
        }
    }
    private (WorkWorkspace Workspace, WorkAgent? Agent) Authorized(WorkTask task)
    {
        if (_removedProfiles.Contains(task.ProfileId)) throw new InvalidOperationException("伙伴已移除，任务已停止。");
        Alive(); var workspace = _configuration.Workspaces.SingleOrDefault(w => w.Id == task.WorkspaceId);
        var agent = _configuration.Agents.SingleOrDefault(a => a.Id == task.ExecutorId);
        if (workspace is null || workspace.Revision != task.WorkspaceRevision || agent is null || agent.Revision != task.AgentRevision ||
            !_configuration.Grants.Any(g => g.ProfileId == task.ProfileId && g.WorkspaceId == task.WorkspaceId && g.WorkspaceRevision == task.WorkspaceRevision && g.ExecutorId == task.ExecutorId && g.AgentRevision == task.AgentRevision))
            throw new UnauthorizedAccessException("当前角色尚未授权这个工作区与执行者，或授权配置已经变化。");
        return (workspace, agent);
    }
    public WorkTask Create(string profileId, string chatSessionId, string workspaceId, string executorId, string prompt)
    {
        lock (_gate)
        {
            Alive(); ValidatePrompt(prompt);
            var workspace = _configuration.Workspaces.Single(w => w.Id == workspaceId);
            var agent = _configuration.Agents.Single(a => a.Id == executorId);
            var task = new WorkTask { ProfileId = profileId, ChatSessionId = chatSessionId, WorkspaceId = workspaceId, WorkspaceRevision = workspace.Revision,
                ExecutorId = executorId, AgentRevision = agent.Revision, Title = agent.Name + " 委托", Messages = [new("user", prompt.Trim(), ChatJson.Now())] };
            _ = Authorized(task); Save(task); _tasks.Add(task.Id, task); return Copy(task);
        }
    }
    private static void ValidatePrompt(string prompt) { if (ChatJson.Length(prompt.Trim()) is < 1 or > 16000) throw new ArgumentException("工作内容需要 1～16000 字。"); }
    public void Enqueue(string taskId) { lock (_gate) { Alive(); if (_tasks[taskId].Status != "queued") throw new InvalidOperationException("任务状态已变化。"); _queue.Writer.TryWrite(taskId); Notify(_tasks[taskId]); } }
    private WorkTask Owned(string profileId, string taskId)
    {
        if (!_tasks.TryGetValue(taskId, out var task) || task.ProfileId != profileId) throw new UnauthorizedAccessException("任务不属于当前伙伴。"); return task;
    }
    public WorkTask Get(string profileId, string taskId) { lock (_gate) return Copy(Owned(profileId, taskId)); }
    public object[] List(string profileId, string? sessionId = null)
    {
        lock (_gate) return _tasks.Values.Where(t => t.ProfileId == profileId && (sessionId is null || t.ChatSessionId == sessionId)).OrderBy(t => t.CreatedAt).TakeLast(100)
            .Select(t => (object)new { t.Id, t.Title, t.Status, t.Revision, t.Attempt, t.CreatedAt, t.UpdatedAt, t.WorkspaceId, t.ExecutorId, t.Permission }).ToArray();
    }
    public void Continue(string profileId, string taskId, long expectedRevision, string prompt)
    {
        lock (_gate)
        {
            ValidatePrompt(prompt); var task = Owned(profileId, taskId); _ = Authorized(task);
            if (task.Unfinished || _running.ContainsKey(task.Id) || task.Revision != expectedRevision) throw new InvalidOperationException("任务正在运行或已经变化，请刷新后继续。");
            task.Messages.Add(new("user", prompt.Trim(), ChatJson.Now())); task.Status = "queued"; task.Result = ""; task.Error = ""; task.Permission = null; task.Attempt++;
            Save(task); _queue.Writer.TryWrite(task.Id); Notify(task);
        }
    }
    public void Cancel(string profileId, string taskId) { lock (_gate) CancelTask(Owned(profileId, taskId)); }
    public void CancelProfile(string profileId) { lock (_gate) { _removedProfiles.Add(profileId); CancelWhere(t => t.ProfileId == profileId); } }
    private void CancelWhere(Func<WorkTask, bool> predicate) { foreach (var task in _tasks.Values.Where(t => t.Unfinished && predicate(t)).ToArray()) CancelTask(task); }
    private void CancelTask(WorkTask task)
    {
        if (!task.Unfinished) return;
        task.Status = "cancelled"; task.Permission = null; Save(task);
        if (_permissions.Remove(task.Id, out var answer)) answer.TrySetResult(null);
        if (_running.TryGetValue(task.Id, out var cancellation)) cancellation.Cancel();
        Notify(task);
    }
    public void DecidePermission(string profileId, string taskId, string permissionId, string optionId)
    {
        lock (_gate)
        {
            var task = Owned(profileId, taskId); _ = Authorized(task);
            if (task.Status != "awaiting_permission" || task.Permission?.Id != permissionId || !_permissions.TryGetValue(task.Id, out var answer)) throw new InvalidOperationException("这项授权请求已结束。");
            if (!task.Permission.Options.Any(o => o.Id == optionId)) throw new ArgumentException("授权选项无效。");
            task.Permission = null; task.Status = "running"; Save(task); _permissions.Remove(task.Id); answer.TrySetResult(optionId); Notify(task);
        }
    }
    private async Task<string?> PermissionAsync(WorkTask task, int attempt, WorkPermission permission, CancellationToken cancellation)
    {
        TaskCompletionSource<string?> answer;
        lock (_gate)
        {
            Active(task, attempt, cancellation); if (_permissions.ContainsKey(task.Id)) throw new InvalidOperationException("Agent 重复请求授权。");
            answer = new(TaskCreationOptions.RunContinuationsAsynchronously); _permissions[task.Id] = answer;
            task.Permission = permission; task.Status = "awaiting_permission"; Save(task); Notify(task);
        }
        try { return await answer.Task.WaitAsync(cancellation).ConfigureAwait(false); }
        finally
        {
            lock (_gate)
            {
                if (_permissions.GetValueOrDefault(task.Id) == answer)
                { _permissions.Remove(task.Id); task.Permission = null; if (task.Status == "awaiting_permission") task.Status = "running"; Save(task); Notify(task); }
            }
        }
    }
    private void Active(WorkTask task, int attempt, CancellationToken token)
    { token.ThrowIfCancellationRequested(); _ = Authorized(task); if (task.Attempt != attempt || task.Status is not ("running" or "awaiting_permission")) throw new OperationCanceledException(); }
    private Task Report(WorkTask task, int attempt, string kind, JsonNode? data, CancellationToken token)
    {
        lock (_gate)
        {
            Active(task, attempt, token);
            if (kind == "agent_update" && data.String("sessionUpdate") == "agent_message_chunk" && data?["content"].String("type") == "text")
                task.Result += data?["content"].String("text");
            if (kind == "agent_session") task.AgentSessionId = data!.GetValue<string>();
            else
            {
                string logPath = WorkStorage.Within(_root, "logs/" + task.Id + ".jsonl"); Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
                File.AppendAllText(logPath, JsonSerializer.Serialize(new { at = ChatJson.Now(), attempt, kind, data }, new JsonSerializerOptions(ChatJson.Options) { WriteIndented = false }) + "\n");
            }
            Save(task); if (kind is not ("checkpoint" or "delta")) Notify(task); return Task.CompletedTask;
        }
    }
    public string ReadLog(string profileId, string taskId)
    {
        lock (_gate)
        {
            _ = Owned(profileId, taskId); string path = WorkStorage.Within(_root, "logs/" + taskId + ".jsonl");
            if (!File.Exists(path)) return "";
            using var file = File.OpenRead(path); if (file.Length > 100000) file.Seek(-100000, SeekOrigin.End);
            using var reader = new StreamReader(file); if (file.Position > 0) _ = reader.ReadLine(); return reader.ReadToEnd();
        }
    }
    public async Task<AgentProbe> ProbeAsync(string profileId, string workspaceId, string executorId, CancellationToken token)
    {
        WorkAgent agent; string directory;
        lock (_gate)
        {
            var workspace = _configuration.Workspaces.Single(w => w.Id == workspaceId); agent = Copy(_configuration.Agents.Single(a => a.Id == executorId));
            _ = Authorized(new() { ProfileId = profileId, WorkspaceId = workspaceId, WorkspaceRevision = workspace.Revision, ExecutorId = executorId, AgentRevision = agent.Revision }); directory = workspace.Directory;
        }
        return await _agent.ProbeAsync(agent, directory, token).ConfigureAwait(false);
    }
    private async Task RunAsync()
    {
        try
        {
            await foreach (string id in _queue.Reader.ReadAllAsync(_lifetime.Token).ConfigureAwait(false))
            {
                WorkTask task; WorkExecutionContext context; int attempt;
                using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token); cancellation.CancelAfter(_options.TaskTimeout);
                var token = cancellation.Token;
                lock (_gate)
                {
                    task = _tasks[id]; if (task.Status != "queued") continue; attempt = task.Attempt;
                    try
                    {
                        var (workspace, agent) = Authorized(task);
                        task.Status = "running"; Save(task); _running[id] = cancellation;
                        context = new() { Task = Copy(task), Workspace = Copy(workspace), Agent = agent is null ? null : Copy(agent),
                            CheckAuthorization = () => { lock (_gate) Active(task, attempt, token); },
                            Report = (kind, data) => Report(task, attempt, kind, data, token), RequestPermission = (request, ct) => PermissionAsync(task, attempt, request, ct) };
                        Notify(task);
                    }
                    catch (Exception ex) { task.Status = "failed"; task.Error = ex.Message; Save(task); Notify(task); continue; }
                }
                try
                {
                    var result = await _agent.ExecuteAsync(context, token).ConfigureAwait(false);
                    lock (_gate)
                    {
                        Active(task, attempt, token); task.Result = result.Text; task.Status = result.Status is "completed" or "cancelled" ? result.Status : "failed"; task.Error = result.Reason;
                        task.Messages.Add(new("agent", result.Text, ChatJson.Now())); Save(task); Notify(task);
                    }
                }
                catch (Exception ex)
                {
                    lock (_gate)
                    {
                        if (task.Unfinished && task.Attempt == attempt)
                        {
                            task.Status = _lifetime.IsCancellationRequested ? "interrupted" : token.IsCancellationRequested ? "cancelled" : "failed";
                            task.Error = token.IsCancellationRequested ? "执行已停止；已经发生的文件操作会保留。" : ex.Message; Save(task); Notify(task);
                        }
                    }
                }
                finally { lock (_gate) { _running.Remove(id); if (_permissions.Remove(id, out var answer)) answer.TrySetResult(null); task.Permission = null; } }
            }
        }
        catch (OperationCanceledException) { }
    }
    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            foreach (var task in _tasks.Values.Where(t => t.Unfinished)) { task.Status = "interrupted"; task.Permission = null; Save(task); }
            _disposed = true; _lifetime.Cancel(); _queue.Writer.TryComplete();
            foreach (var answer in _permissions.Values) answer.TrySetResult(null); _permissions.Clear();
        }
        _agent.DisposeAsync().AsTask().GetAwaiter().GetResult();
        try { _worker.Wait(TimeSpan.FromSeconds(2)); } catch (AggregateException) { }
    }
}
