using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GdPal.Conversation;

public partial class ChatService
{
    public string GetSettings() => ChatJson.Encode(new { settings = _settings, has_key = _key.Length > 0,
        notice = _startupError, testing = _test is not null, connection_state = _connectionState, last_test_message = _testMessage });
    public string GetChatProviders() => ChatJson.Encode(ChatProviders.Presets);
    public string GetChatOptions(string json)
    {
        var settings = ChatJson.Decode<ChatSettings>(json);
        string format = ChatProviders.Format(settings);
        return ChatJson.Encode(new { format, efforts = ChatProviders.ReasoningLevels(settings), needs_output_limit = format == "anthropic",
            note = ChatProviders.IsDeepSeek(settings) && !ChatProviders.IsOpenRouter(settings)
                ? "默认由服务决定；可关闭思考，或选择低、高、最高强度。"
                : "默认由服务决定。低强度通常更快，高强度思考更充分；具体档位以所选模型支持情况为准。" });
    }
    private static string NormalizeUrl(string url)
    {
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https") || uri.UserInfo.Length > 0 || uri.Query.Length > 0 || uri.Fragment.Length > 0)
            throw new ArgumentException("请输入有效的 HTTP 或 HTTPS 服务地址。");
        return uri.AbsoluteUri.TrimEnd('/');
    }
    private static string Endpoint(string baseUrl, string suffix) => baseUrl.EndsWith("/" + suffix, StringComparison.OrdinalIgnoreCase) ? baseUrl : baseUrl + "/" + suffix;
    private string UpdateKey(string endpoint, bool remember, string supplied, string previous)
    {
        string key = supplied.Trim().Length > 0 ? supplied.Trim() : previous;
        if (remember) _credentials.Write(endpoint, key); else _credentials.Delete(endpoint);
        return key;
    }
    public string SaveSettings(string json, string key) => Guard(() =>
    {
        var settings = ChatJson.Decode<ChatSettings>(json);
        settings.BaseUrl = NormalizeUrl(settings.BaseUrl); ChatProviders.Normalize(settings);
        if (settings.Model.Length == 0) throw new ArgumentException("请填写模型名称。");
        string previous = settings.BaseUrl == _settings.BaseUrl ? _key : (settings.RememberKey ? _credentials.Read(settings.BaseUrl) : "");
        string value = UpdateKey(settings.BaseUrl, settings.RememberKey, key, previous);
        LocalFiles.Write(Path.Combine(_root, "connection.json"), ChatJson.Encode(settings));
        CancelConnectionTest(); _settings = settings; _key = value; _startupError = "";
        _connectionState = _key.Length > 0 ? "configured" : "unconfigured";
        EmitSignal(SignalName.SettingsChanged);
        foreach (string id in _companions.Keys) Changed(id);
    });
    public string ForgetKey() => Guard(() =>
    {
        _credentials.Delete(_settings.BaseUrl);
        CancelConnectionTest(); _key = ""; _settings.RememberKey = false; _connectionState = "unconfigured";
        LocalFiles.Write(Path.Combine(_root, "connection.json"), ChatJson.Encode(_settings));
        EmitSignal(SignalName.SettingsChanged);
        foreach (string id in _companions.Keys) Changed(id);
    });
    private static HttpRequestMessage Request(string endpoint, string key, object body)
    {
        var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Content = new StringContent(ChatJson.Encode(body), Encoding.UTF8, "application/json");
        if (key.Length > 0) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        return request;
    }
    private static HttpRequestMessage ChatRequest(ChatSettings settings, string key, object messages, bool stream) => ChatProtocol.CreateRequest(settings, key, messages, stream);
    private static string ServiceError(string message, string key) => ChatJson.Clip(key.Length > 0 ? message.Replace(key, "[REDACTED]", StringComparison.Ordinal) : message, 1200);
    private static void RequireSuccess(HttpResponseMessage response, string body = "", string key = "")
    {
        if (response.IsSuccessStatusCode) return;
        string detail = "";
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.TryGetProperty("error", out var error))
                detail = error.ValueKind == JsonValueKind.Object && error.TryGetProperty("message", out var message) ? message.ToString() : error.ToString();
        }
        catch (JsonException) { }
        throw new HttpRequestException("服务返回 HTTP " + (int)response.StatusCode + (detail.Length > 0 ? "：" + ServiceError(detail, key) : "，请检查地址、模型、凭据或服务额度。"));
    }
    public string TestConnection()
    {
        if (_key.Length == 0) return "请先填写 API Key。";
        CancelConnectionTest();
        var cancellation = new CancellationTokenSource(); _test = cancellation;
        _connectionState = "testing"; EmitSignal(SignalName.SettingsChanged);
        _ = TestAsync(_settings, _key, cancellation);
        return "";
    }
    private async Task TestAsync(ChatSettings settings, string key, CancellationTokenSource cancellation)
    {
        string result = "连接成功。", state = "verified";
        try
        {
            using var request = ChatRequest(settings, key, new[] { new { role = "user", content = "请回复：你好" } }, false);
            using var response = await _http.SendAsync(request, cancellation.Token).ConfigureAwait(false);
            string body = await response.Content.ReadAsStringAsync(cancellation.Token).ConfigureAwait(false);
            RequireSuccess(response, body, key);
            var reply = ChatProtocol.ReadSummary(body, true);
            if (reply.Content.Length == 0 && reply.Reasoning.Length == 0) throw new IOException("响应中没有聊天结果。");
        }
        catch (Exception ex) { result = "连接失败：" + ServiceError(ex.Message, key); state = "failed"; }
        _pending.Enqueue(() =>
        {
            if (_test != cancellation) return;
            _test = null; cancellation.Dispose(); _connectionState = state; _testMessage = result;
            EmitSignal(SignalName.ConnectionTestFinished, result); EmitSignal(SignalName.SettingsChanged);
        });
    }
    public void CancelConnectionTest()
    {
        if (_test is not { } cancellation) return;
        _test = null; cancellation.Cancel(); cancellation.Dispose();
        _connectionState = _key.Length > 0 ? "configured" : "unconfigured";
    }
    public string GetSpeechSettings() => ChatJson.Encode(_speechSettings);
    public string SaveSpeechSettings(string json, string key) => Guard(() =>
    {
        var settings = ChatJson.Decode<SpeechSettings>(json);
        settings.BaseUrl = NormalizeUrl(settings.BaseUrl);
        if (settings.Enabled && (string.IsNullOrWhiteSpace(settings.Model) || string.IsNullOrWhiteSpace(settings.Voice))) throw new ArgumentException("请填写语音模型和音色。");
        string previous = settings.BaseUrl == _speechSettings.BaseUrl ? _speechKey : (settings.RememberKey ? _credentials.Read("speech:" + settings.BaseUrl) : "");
        string value = UpdateKey("speech:" + settings.BaseUrl, settings.RememberKey, key, previous);
        LocalFiles.Write(Path.Combine(_root, "speech.json"), ChatJson.Encode(settings));
        foreach (string id in _speech.Keys.ToArray()) CancelSpeech(id);
        _speechSettings = settings; _speechKey = value;
    });
    public void RequestSpeech(string id, string requestId, string text)
    {
        CancelSpeech(id);
        if (!_speechSettings.Enabled)
        { _pending.Enqueue(() => EmitSignal(SignalName.SpeechReady, id, requestId, Array.Empty<byte>(), "请先在连接设置中启用语音服务。")); return; }
        var cancellation = new CancellationTokenSource(); _speech[id] = cancellation;
        _ = SpeakAsync(id, requestId, text, _speechSettings, _speechKey, cancellation);
    }
    private async Task SpeakAsync(string id, string requestId, string text, SpeechSettings settings, string key, CancellationTokenSource cancellation)
    {
        byte[] wav = Array.Empty<byte>(); string error = "";
        try
        {
            using var request = Request(Endpoint(settings.BaseUrl, "audio/speech"), key,
                new { model = settings.Model, voice = settings.Voice, input = text, response_format = "wav" });
            using var response = await _http.SendAsync(request, cancellation.Token).ConfigureAwait(false);
            RequireSuccess(response);
            wav = await response.Content.ReadAsByteArrayAsync(cancellation.Token).ConfigureAwait(false);
            if (wav.Length < 12 || Encoding.ASCII.GetString(wav, 0, 4) != "RIFF" || Encoding.ASCII.GetString(wav, 8, 4) != "WAVE") throw new IOException("语音服务未返回 WAV 音频。");
        }
        catch (Exception ex) { error = "朗读失败：" + ex.Message; }
        _pending.Enqueue(() =>
        {
            if (!_speech.TryGetValue(id, out var current) || current != cancellation) return;
            _speech.Remove(id); cancellation.Dispose();
            EmitSignal(SignalName.SpeechReady, id, requestId, wav, error);
        });
    }
    public void CancelSpeech(string id)
    {
        if (_speech.Remove(id, out var cancellation)) { cancellation.Cancel(); cancellation.Dispose(); }
    }
}
