using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using HttpClient = System.Net.Http.HttpClient;
using Environment = System.Environment;

namespace GdPal.Conversation;

/// <summary>Local v1 files, manual context and one chat request per turn.</summary>
[GlobalClass]
public partial class ChatService : Node
{
    [Signal] public delegate void ConversationChangedEventHandler(string profileId);
    [Signal] public delegate void ReplyFinishedEventHandler(string profileId, string text);
    [Signal] public delegate void OutfitRequestedEventHandler(string profileId, string outfit);
    [Signal] public delegate void SettingsChangedEventHandler();
    [Signal] public delegate void ConnectionTestFinishedEventHandler(string text);
    [Signal] public delegate void HistoryQueryFinishedEventHandler(string profileId, string requestId, string result);
    [Signal] public delegate void HistoryDeleteFinishedEventHandler(string profileId, string requestId, string result);
    [Signal] public delegate void SegmentReadyEventHandler(string profileId, string json);
    [Signal] public delegate void PerformanceCancelledEventHandler(string profileId);
    [Signal] public delegate void SpeechReadyEventHandler(string profileId, string requestId, byte[] wav, string error);

    private sealed class Companion
    {
        public ManualProfile Profile = new();
        public ChatSession Session = new();
        public CancellationTokenSource? Reply;
        public string StorageError = "";
        public bool LoadFailed;
        public string Outfit = "maid";
        public string[] AvailableOutfits = Array.Empty<string>();
        public bool AllowOutfit, OutfitLocked;
    }

    private readonly Dictionary<string, Companion> _companions = new();
    private readonly Dictionary<string, CancellationTokenSource> _speech = new();
    private readonly ConcurrentQueue<Action> _pending = new();
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromMinutes(10) };
    private IChatCredentialStore _credentials = null!;
    private ChatSettings _settings = new();
    private SpeechSettings _speechSettings = new();
    private CancellationTokenSource? _test;
    private string _root = "", _key = "", _speechKey = "", _startupError = "";
    private string _connectionState = "unconfigured", _testMessage = "";
    private bool _closed;
    private string _defaultPersona = "", _adultPersona = "";

    public override void _Ready()
    {
        _root = ProjectSettings.GlobalizePath("user://companion");
        if (OS.GetEnvironment("GD_PAL_TEST") == "1") _root = Path.Combine(_root, "tests", Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(_root);
            _credentials = OperatingSystem.IsWindows() && OS.GetEnvironment("GD_PAL_TEST") != "1"
                ? new WindowsCredentialStore() : new LocalCredentialStore(Path.Combine(_root, "credentials"));
            _settings = LocalFiles.Read<ChatSettings>(Path.Combine(_root, "connection.json"));
            _speechSettings = LocalFiles.Read<SpeechSettings>(Path.Combine(_root, "speech.json"));
            if (_settings.RememberKey) _key = _credentials.Read(_settings.BaseUrl);
            if (_speechSettings.RememberKey) _speechKey = _credentials.Read("speech:" + _speechSettings.BaseUrl);
            _connectionState = _key.Length > 0 ? "configured" : "unconfigured";
        }
        catch (Exception ex) { _startupError = "本地设置读取失败：" + ex.Message; }
    }

    public override void _Process(double delta)
    {
        // Only the main thread mutates state, writes files and emits Godot signals.
        for (int count = 0; count < 128 && _pending.TryDequeue(out var action); count++)
            if (!_closed) action();
    }

    private string DirectoryFor(string id) => LocalFiles.Within(_root, id);
    private string ProfilePath(string id) => Path.Combine(DirectoryFor(id), "profile.json");
    private string SessionPath(string id, string session) => LocalFiles.Within(Path.Combine(DirectoryFor(id), "conversations"), session + ".json");
    private void Changed(string id) => _pending.Enqueue(() => EmitSignal(SignalName.ConversationChanged, id));
    private static string Guard(Action action)
    {
        try { action(); return ""; }
        catch (Exception ex) { return ex.Message; }
    }
    private string SaveProfile(string id, ManualProfile profile) => Guard(() => ProfileDocuments.SaveMetadata(DirectoryFor(id), profile));
    private void ReloadContext(string id) => ProfileDocuments.Reload(DirectoryFor(id), _companions[id].Profile);

    public void RegisterProfile(string id, string displayName, string persona, bool adultMode = false)
    {
        if (_companions.ContainsKey(id)) return;
        var c = new Companion(); _companions.Add(id, c);
        try
        {
            if (File.Exists(ProfilePath(id))) c.Profile = ProfileDocuments.Load(DirectoryFor(id));
            else
            {
                c.Profile = new ManualProfile { DisplayName = displayName, AdultMode = adultMode, Persona = persona, PersonaBeforeSummary = persona };
                ProfileDocuments.Create(DirectoryFor(id), c.Profile);
            }
            string active = c.Profile.ActiveSessionId;
            if (active.Length > 0 && File.Exists(SessionPath(id, active))) c.Session = LocalFiles.Read<ChatSession>(SessionPath(id, active));
            foreach (var message in c.Session.Messages.Where(m => m.Status == "streaming")) message.Status = "interrupted";
            c.Profile.ActiveSessionId = c.Session.HasContent() ? c.Session.SessionId : "";
            c.StorageError = SaveProfile(id, c.Profile);
        }
        catch (Exception ex) { c.LoadFailed = true; c.StorageError = "角色资料读取失败，请恢复文件后重启：" + ex.Message; }
    }

    public string GetStartupError() => _startupError;
    public string GetSnapshot(string id)
    {
        if (!_companions.TryGetValue(id, out var c)) return "{}";
        return ChatJson.Encode(new {
            profile_id = id, session_id = c.Session.SessionId, display_name = c.Profile.DisplayName, persona = c.Profile.Persona,
            messages = c.Session.Messages.TakeLast(200), total_messages = c.Session.Messages.Count,
            busy = c.Reply is not null, has_key = _key.Length > 0, storage_error = c.StorageError, notice = "",
            path = Path.ChangeExtension(SessionPath(id, c.Session.SessionId), ".md"), model = _settings.Model,
            has_images = c.Session.Messages.Any(m => m.Images.Count > 0)
        });
    }
    public string GetRole(string id)
    {
        if (!_companions.TryGetValue(id, out var c)) return "{}";
        string error = Guard(() => ReloadContext(id));
        return ChatJson.Encode(new { profile = c.Profile, file_error = error });
    }
    public string GetManualContext(string id)
    {
        if (!_companions.TryGetValue(id, out var c)) return "{}";
        string error = Guard(() => ReloadContext(id));
        return ChatJson.Encode(new { persona = c.Profile.Persona, memory = c.Profile.Memory,
            active_memory = c.Profile.ActiveMemory, world = c.Profile.World, paths = ProfileDocuments.Paths(DirectoryFor(id)), file_error = error });
    }
    private string EditProfile(string id, Action<ManualProfile> edit)
    {
        if (!_companions.TryGetValue(id, out var c)) return "伙伴不存在。";
        if (c.LoadFailed) return c.StorageError;
        return Guard(() =>
        {
            ReloadContext(id);
            var candidate = ChatJson.Decode<ManualProfile>(ChatJson.Encode(c.Profile));
            edit(candidate);
            ProfileDocuments.SaveChanges(DirectoryFor(id), c.Profile, candidate);
            c.Profile = candidate; Changed(id);
        });
    }
    private static void SetManualField(ManualProfile candidate, string field, string text)
    {
        if (text.Length > (field == "persona" ? 4000 : 16000)) throw new ArgumentException("内容过长，请精简后保存。");
        switch (field)
        {
            case "persona":
                if (candidate.Persona != text.Trim()) candidate.PersonaBeforeSummary = text.Trim();
                candidate.Persona = text.Trim(); break;
            case "memory": candidate.Memory = text.Trim(); break;
            case "active_memory": candidate.ActiveMemory = text.Trim(); break;
            case "world": candidate.World = text.Trim(); break;
            default: throw new ArgumentException("未知设定。");
        }
    }
    public string SaveManualContext(string id, string field, string text) => EditProfile(id, candidate => SetManualField(candidate, field, text));
    public string SaveManualContexts(string id, string json, string baselinesJson) => EditProfile(id, candidate =>
    {
        var baselines = ChatJson.Decode<Dictionary<string, string>>(baselinesJson);
        foreach (var (field, text) in ChatJson.Decode<Dictionary<string, string>>(json))
        {
            string current = ContextText(candidate, field);
            if (!baselines.TryGetValue(field, out var baseline) || (current.Trim() != baseline.Trim() && current.Trim() != text.Trim()))
                throw new IOException(SummaryTargetName(field) + "文件已在其他位置修改，请先从文件重新载入。");
            SetManualField(candidate, field, text);
        }
    });
    public string SetPersona(string id, string persona) => SaveManualContext(id, "persona", persona);
    public string SaveProfileSettings(string id, string name, bool adultMode, string persona, bool updatePersona, string baseline) => EditProfile(id, candidate =>
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 40) throw new ArgumentException("名字需要 1～40 字。");
        if (updatePersona)
        {
            if (candidate.Persona.Trim() != baseline.Trim() && candidate.Persona.Trim() != persona.Trim())
                throw new IOException("人设文件已在其他位置修改，请先从文件重新载入，再保存你的编辑。");
            SetManualField(candidate, "persona", persona);
        }
        candidate.DisplayName = name.Trim();
        candidate.AdultMode = adultMode;
    });
    public string SetAutoSpeak(string id, bool enabled) => EditProfile(id, candidate => candidate.AutoSpeak = enabled);

    public void ConfigurePersonaPresets(string defaultPersona, string adultPersona)
    {
        _defaultPersona = defaultPersona; _adultPersona = adultPersona;
    }

    private string EffectivePersona(ManualProfile profile) => !profile.AdultMode && _adultPersona.Length > 0 && profile.Persona.Trim() == _adultPersona
        ? _defaultPersona : profile.Persona;

    private string SystemPrompt(ManualProfile p) =>
        $"你是桌面伙伴「{p.DisplayName}」。按以下用户手写设定自然交流。回复使用纯文本。不要声称执行了现实操作或已经自动保存记忆。\n\n" +
        $"【人设】\n{EffectivePersona(p)}\n\n【世界设定】\n{p.World}\n\n【长期记忆】\n{p.Memory}\n\n【活跃记忆】\n{p.ActiveMemory}\n\n" + ChatTurns.DialogueConvention;

    public string SendMessage(string id, string text) => StartReply(id, text, false, string.IsNullOrWhiteSpace(text));
    public void SetOutfitState(string id, string current, string[] available, bool allowed, bool locked)
    {
        if (!_companions.TryGetValue(id, out var c)) return;
        c.Outfit = current;
        c.AvailableOutfits = available;
        c.AllowOutfit = allowed;
        c.OutfitLocked = locked;
    }
    public string SendImageMessage(string id, string text, string imagesJson)
    {
        try
        {
            var images = ChatJson.Decode<List<ChatImage>>(imagesJson);
            if (images.Count > ChatImages.MaxPerMessage || images.Select(i => i.File).Distinct().Count() != images.Count) return "每条消息最多附带 4 张不同的图片。";
            foreach (var image in images) ChatImages.Validate(image);
            return StartReply(id, text, false, string.IsNullOrWhiteSpace(text) && images.Count == 0, images);
        }
        catch (Exception ex) { return ex.Message; }
    }
    public string ContinueMessage(string id) => StartReply(id, "", false, true);
    public string RetryMessage(string id) => StartReply(id, "", true);
    private string StartReply(string id, string text, bool retry, bool continuation = false, List<ChatImage>? images = null)
    {
        if (!_companions.TryGetValue(id, out var c)) return "伙伴不存在。";
        if (c.Reply is not null) return "请先停止当前回复。";
        if (_key.Length == 0) return "请先在连接设置中填写 API Key。";
        if (c.StorageError.Length > 0) return "请先重试保存或恢复本地资料：" + c.StorageError;
        string contextError = Guard(() => ReloadContext(id));
        if (contextError.Length > 0) return "设定文件读取失败：" + contextError;
        text = text.Trim();
        if (!retry && !continuation && ((text.Length == 0 && (images is null || images.Count == 0)) || text.Length > 4000)) return "请填写消息或附上图片，文字最多 4000 字。";
        var before = new List<ChatMessage>(c.Session.Messages);
        ChatTurn turn;
        try { turn = ChatTurns.Begin(c.Session.Messages, text, retry, continuation, images); }
        catch (ArgumentException ex) { return ex.Message; }
        // Limit recent dialogue; compose the separately stored context documents for each request.
        var history = new List<ChatMessage>();
        int remaining = 24000;
        foreach (var message in c.Session.Messages.AsEnumerable().Reverse().Take(40))
        {
            if (!message.HasContent() || message.Status is "failed" or "interrupted" or "stopped") continue;
            if (message.Content.Length > remaining) break;
            remaining -= message.Content.Length; history.Insert(0, message);
        }
        List<ChatPromptMessage> messages;
        try { messages = ChatImages.ModelHistory(history, turn.IsContinuation, DirectoryFor(id)); }
        catch (Exception ex) { c.Session.Messages = before; return ex.Message; }
        messages.Insert(0, new("system", SystemPrompt(c.Profile) + OutfitCommands.Prompt(c.Outfit, c.AvailableOutfits, c.AllowOutfit, c.OutfitLocked)));
        var reply = new ChatMessage { Role = "assistant", Status = "streaming", TurnId = turn.TurnId, IsContinuation = turn.IsContinuation };
        c.Session.Messages.Add(reply);
        string error = SaveConversation(id);
        if (error.Length > 0) { c.Session.Messages = before; return error; }
        if (images is not null) CommitChatImages(id, images);
        CancelPerformance(id);
        var cancellation = new CancellationTokenSource(); c.Reply = cancellation; Changed(id);
        _ = GenerateReply(id, c, c.Session.SessionId, reply, messages, _settings, _key, cancellation);
        return "";
    }

    private async Task GenerateReply(string id, Companion c, string session, ChatMessage reply, object messages, ChatSettings settings, string key, CancellationTokenSource cancellation)
    {
        var token = cancellation.Token;
        var text = new StringBuilder();
        string finish = "complete", error = "";
        bool completed = false;
        try
        {
            using var request = ChatRequest(settings, key, messages, true);
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
            RequireSuccess(response, response.IsSuccessStatusCode ? "" : await response.Content.ReadAsStringAsync(token).ConfigureAwait(false), key);
            if (response.Content.Headers.ContentType?.MediaType?.Contains("json", StringComparison.OrdinalIgnoreCase) == true)
            {
                var completion = ChatProtocol.ReadSummary(await response.Content.ReadAsStringAsync(token).ConfigureAwait(false), true);
                text.Append(completion.Content);
                finish = completion.FinishReason == "length" ? "truncated" : "complete";
                completed = true;
            }
            else
            {
                using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
                long lastUpdate = Environment.TickCount64;
                await foreach (string data in ChatProtocol.ReadEvents(stream, token).ConfigureAwait(false))
                {
                    var part = ChatProtocol.ReadStreamPart(data);
                    if (!string.IsNullOrEmpty(part.FullText)) { text.Clear(); text.Append(part.FullText); }
                    else text.Append(part.Text);
                    completed = part.Done;
                    if (part.FinishReason == "length") finish = "truncated";
                    if (Environment.TickCount64 - lastUpdate >= 60)
                    {
                        string partial = text.ToString(); lastUpdate = Environment.TickCount64;
                        _pending.Enqueue(() => { if (IsCurrent(c, session, cancellation)) { SetText(reply, partial); Changed(id); } });
                    }
                    if (completed) break;
                }
            }
            if (!completed) throw new IOException("连接提前断开，已保留收到的文字，可以重试。");
            if (text.Length == 0) throw new IOException("模型没有返回正文，请检查模型设置或重试。");
        }
        catch (OperationCanceledException) { finish = "interrupted"; error = "请求超时，请重试。"; }
        catch (Exception ex)
        {
            finish = "failed"; error = ServiceError(ex.Message, key);
            if (messages is List<ChatPromptMessage> prompt && prompt.Any(m => m.Images?.Count > 0))
                error += "\n本次包含图片，请确认所选模型和服务支持图片输入。";
        }
        string result = text.ToString();
        _pending.Enqueue(() =>
        {
            if (!IsCurrent(c, session, cancellation)) return;
            c.Reply = null; cancellation.Dispose();
            SetText(reply, result); reply.Status = finish; reply.Error = error;
            SaveConversation(id); Changed(id);
            if (finish is "complete" or "truncated")
            {
                string requested = OutfitCommands.Requested(result, c.AvailableOutfits);
                // Recheck the live override: a user may have locked or changed clothes
                // while this model response was in flight.
                if (requested.Length > 0 && c.AllowOutfit && !c.OutfitLocked)
                    EmitSignal(SignalName.OutfitRequested, id, requested);
                EmitSignal(SignalName.ReplyFinished, id, reply.Content);
                foreach (var segment in reply.Segments)
                    EmitSignal(SignalName.SegmentReady, id, ChatJson.Encode(new { session_id = session, turn_id = reply.TurnId,
                        segment_id = Guid.NewGuid().ToString("N"), data = segment }));
            }
        });
    }
    private static bool IsCurrent(Companion c, string session, CancellationTokenSource cancellation) => c.Reply == cancellation && c.Session.SessionId == session;
    private static void SetText(ChatMessage message, string text)
    {
        message.Content = OutfitCommands.DisplayText(text);
        message.Segments = ChatTurns.ParseSegments(message.Content);
    }
    public void StopReply(string id)
    {
        if (!_companions.TryGetValue(id, out var c)) return;
        if (c.Reply is { } cancellation)
        {
            c.Reply = null; cancellation.Cancel(); cancellation.Dispose();
            if (c.Session.Messages.LastOrDefault() is { Status: "streaming" } reply) reply.Status = "stopped";
            SaveConversation(id); Changed(id);
        }
        CancelPerformance(id);
    }
    public void CancelPerformance(string id)
    {
        CancelSpeech(id);
        _pending.Enqueue(() => EmitSignal(SignalName.PerformanceCancelled, id));
    }

    public string SaveConversation(string id)
    {
        if (!_companions.TryGetValue(id, out var c)) return "伙伴不存在。";
        if (c.LoadFailed) return c.StorageError;
        c.StorageError = Guard(() =>
        {
            if (!c.Session.HasContent())
            {
                string emptyPath = SessionPath(id, c.Session.SessionId);
                LocalFiles.DeleteOrStage(emptyPath, DirectoryFor(id));
                LocalFiles.DeleteOrStage(Path.ChangeExtension(emptyPath, ".md"), DirectoryFor(id));
                if (c.Profile.ActiveSessionId == c.Session.SessionId) c.Profile.ActiveSessionId = "";
                ProfileDocuments.SaveMetadata(DirectoryFor(id), c.Profile);
                return;
            }
            c.Session.UpdatedAt = DateTimeOffset.Now.ToString("O");
            c.Profile.ActiveSessionId = c.Session.SessionId;
            ProfileDocuments.SaveMetadata(DirectoryFor(id), c.Profile);
            LocalFiles.Write(SessionPath(id, c.Session.SessionId), ChatJson.Encode(c.Session));
            LocalFiles.Write(Path.ChangeExtension(SessionPath(id, c.Session.SessionId), ".md"), PackageCodec.Markdown(c.Session, c.Profile.DisplayName));
        });
        return c.StorageError;
    }
    public string GetActiveSessionId(string id) => _companions.TryGetValue(id, out var c) ? c.Session.SessionId : "";
    public string NewConversation(string id)
    {
        if (!_companions.TryGetValue(id, out var c)) return "伙伴不存在。";
        StopReply(id);
        string error = SaveConversation(id);
        return error.Length > 0 ? error : SelectSession(id, c, new ChatSession());
    }
    private string SelectSession(string id, Companion c, ChatSession session)
    {
        if (c.LoadFailed) return c.StorageError;
        var candidate = ChatJson.Decode<ManualProfile>(ChatJson.Encode(c.Profile));
        if (session.HasContent()) candidate.ActiveSessionId = session.SessionId;
        string error = session.HasContent() ? Guard(() => LocalFiles.Write(SessionPath(id, session.SessionId), ChatJson.Encode(session))) : "";
        if (error.Length == 0) error = SaveProfile(id, candidate);
        if (error.Length == 0) { c.Profile = candidate; c.Session = session; Changed(id); }
        return error;
    }
    public string SelectConversation(string id, string sessionId)
    {
        if (!_companions.TryGetValue(id, out var c)) return "伙伴不存在。";
        if (c.Session.SessionId == sessionId) return "";
        return Guard(() =>
        {
            string path = SessionPath(id, sessionId);
            if (!File.Exists(path)) throw new IOException("没有找到这段对话。");
            var session = LocalFiles.Read<ChatSession>(path);
            foreach (var message in session.Messages.Where(m => m.Status == "streaming")) message.Status = "interrupted";
            StopReply(id);
            string error = SaveConversation(id);
            if (error.Length == 0) error = SelectSession(id, c, session);
            if (error.Length > 0) throw new IOException(error);
        });
    }
    public string GetHistoryRecord(string id, string sessionId)
    {
        string path = SessionPath(id, sessionId);
        return ChatJson.Encode(new { path = Path.ChangeExtension(path, ".md"), has_images = LocalFiles.Read<ChatSession>(path).Messages.Any(m => m.Images.Count > 0) });
    }
    public void QueryHistory(string id, string requestId, string query, int offset, int limit)
    {
        string result;
        try
        {
            var sessions = new List<ChatSession>();
            string directory = Path.Combine(DirectoryFor(id), "conversations");
            if (Directory.Exists(directory))
                foreach (string path in Directory.EnumerateFiles(directory, "*.json")) sessions.Add(LocalFiles.Read<ChatSession>(path));
            query = query.Trim();
            var filtered = sessions.Where(s => s.HasContent() && (query.Length == 0 || s.Messages.Any(m => m.Content.Contains(query, StringComparison.OrdinalIgnoreCase))))
                .OrderByDescending(s => s.UpdatedAt).ToList();
            var items = filtered.Skip(Math.Max(0, offset)).Take(Math.Clamp(limit, 1, 100)).Select(s => {
                string title = s.Title();
                return new { session_id = s.SessionId, title = title[..Math.Min(50, title.Length)],
                    preview = s.Messages.LastOrDefault(m => m.HasContent())?.Preview() ?? "尚未发送消息", message_count = s.Messages.Count,
                    local_date = DateTimeOffset.Parse(s.UpdatedAt).ToLocalTime().ToString("yyyy-MM-dd"), local_time = DateTimeOffset.Parse(s.UpdatedAt).ToLocalTime().ToString("HH:mm") };
            });
            result = ChatJson.Encode(new { items, total = filtered.Count, has_more = offset + limit < filtered.Count });
        }
        catch (Exception ex) { result = ChatJson.Encode(new { error = "读取历史失败：" + ex.Message }); }
        _pending.Enqueue(() => EmitSignal(SignalName.HistoryQueryFinished, id, requestId, result));
    }
    public void DeleteHistory(string id, string requestId, string sessionId)
    {
        string error = Guard(() =>
        {
            if (!_companions.TryGetValue(id, out var c)) throw new ArgumentException("伙伴不存在。");
            if (c.Reply is not null) throw new InvalidOperationException("请先停止回复。");
            if (c.Session.SessionId == sessionId)
            {
                string changed = SelectSession(id, c, new ChatSession());
                if (changed.Length > 0) throw new IOException(changed);
                CancelPerformance(id);
            }
            if (c.Profile.ActiveSessionId == sessionId)
            {
                c.Profile.ActiveSessionId = "";
                string saved = SaveProfile(id, c.Profile);
                if (saved.Length > 0) throw new IOException(saved);
            }
            string path = SessionPath(id, sessionId);
            var deleted = LocalFiles.Read<ChatSession>(path);
            LocalFiles.DeleteOrStage(path, DirectoryFor(id));
            LocalFiles.DeleteOrStage(Path.ChangeExtension(path, ".md"), DirectoryFor(id));
            DeleteSessionImages(id, deleted);
        });
        string result = ChatJson.Encode(new { deleted = error.Length == 0, error });
        _pending.Enqueue(() => EmitSignal(SignalName.HistoryDeleteFinished, id, requestId, result));
    }
    public void RemoveProfile(string id)
    {
        StopReply(id); CancelSummary(id); _drafts.Remove(id); _work?.CancelProfile(id); _companions.Remove(id);
    }
    public void Shutdown()
    {
        if (_closed) return;
        CloseImageImports();
        foreach (string id in _summaryJobs.Keys.ToArray()) CancelSummary(id);
        foreach (var job in _packageJobs.Values) job.Cancel();
        _workLifetime.Cancel(); _work?.Dispose();
        foreach (string id in _companions.Keys) { StopReply(id); SaveConversation(id); }
        CancelConnectionTest();
        foreach (string id in _speech.Keys.ToArray()) CancelSpeech(id);
        _closed = true; _http.Dispose();
        while (_pending.TryDequeue(out _)) { }
    }
    public override void _ExitTree() => Shutdown();
}
