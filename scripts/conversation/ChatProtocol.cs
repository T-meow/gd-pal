using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace GdPal.Conversation;

internal sealed record SummaryResponse(string Content, string Reasoning, string FinishReason)
{
    public string Notice => FinishReason == "length" ? "服务端结束了本次输出，已保留完整返回；可查看返回值并继续整理剩余素材。"
        : Content.Length == 0 && Reasoning.Length > 0 ? "本次返回了思考过程，暂无可追加的正文条目；可查看完整返回值。"
        : FinishReason.Length > 0 && FinishReason != "stop" ? "模型结束原因：" + FinishReason + "。已保留返回内容。"
        : Content.Length == 0 ? "已保存模型返回值，本次没有可提取的文本条目。" : "";
}
internal sealed record ChatStreamPart(string Text = "", bool Done = false, string FinishReason = "", string? FullText = null);

internal static class ChatProtocol
{
    public static HttpRequestMessage CreateRequest(ChatSettings settings, string key, object messages, bool stream)
    {
        string format = ChatProviders.Format(settings);
        bool gateway = ChatProviders.IsOpenCode(settings) || ChatProviders.IsOpenRouter(settings);
        var request = new HttpRequestMessage(HttpMethod.Post, Endpoint(settings, stream));
        request.Content = new StringContent(ChatJson.Encode(Payload(settings, messages, stream)), Encoding.UTF8, "application/json");
        if (key.Length > 0)
        {
            if (format == "anthropic" && !gateway) request.Headers.Add("x-api-key", key);
            else if (format == "gemini" && !gateway) request.Headers.Add("x-goog-api-key", key);
            else request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        }
        if (format == "anthropic") request.Headers.Add("anthropic-version", "2023-06-01");
        return request;
    }

    public static string Endpoint(ChatSettings settings, bool stream)
    {
        string format = ChatProviders.Format(settings), url = settings.BaseUrl.TrimEnd('/');
        foreach (string suffix in new[] { "/chat/completions", "/responses", "/messages" })
            if (url.EndsWith(suffix, StringComparison.OrdinalIgnoreCase)) { url = url[..^suffix.Length]; break; }
        if (format == "gemini")
        {
            int modelPath = url.IndexOf("/models/", StringComparison.OrdinalIgnoreCase);
            if (modelPath >= 0) url = url[..modelPath];
        }
        if (ChatProviders.IsOpenCode(settings) && (url.EndsWith("/inference/v1") || url.EndsWith("/inference")))
        {
            if (url.EndsWith("/v1")) url = url[..^3];
            url += format switch { "anthropic" => "/anthropic/v1", "gemini" => "/google/v1beta", _ => "/openai/v1" };
        }
        if (format == "gemini")
        {
            string model = ChatProviders.Model(settings);
            if (model.StartsWith("models/")) model = model[7..];
            return url + "/models/" + Uri.EscapeDataString(model) + (stream ? ":streamGenerateContent?alt=sse" : ":generateContent");
        }
        return url + (format switch { "responses" => "/responses", "anthropic" => "/messages", _ => "/chat/completions" });
    }

    public static Dictionary<string, object> Payload(ChatSettings settings, object messages, bool stream)
    {
        string format = ChatProviders.Format(settings), model = ChatProviders.Model(settings), effort = settings.ReasoningEffort;
        var input = JsonSerializer.SerializeToElement(messages, ChatJson.Options).EnumerateArray().ToArray();
        string system = string.Join("\n\n", input.Where(m => Field(m, "role") is "system" or "developer").Select(m => Field(m, "content")));
        var dialogue = input.Where(m => Field(m, "role") is "user" or "assistant").ToArray();
        var payload = new Dictionary<string, object> { ["model"] = model, ["stream"] = stream };
        if (format == "gemini")
        {
            payload.Clear();
            payload["contents"] = dialogue.Select(m => new { role = Field(m, "role") == "assistant" ? "model" : "user", parts = ContentParts(m, format) }).ToArray();
            if (system.Length > 0) payload["systemInstruction"] = new { parts = new[] { new { text = system } } };
            if (effort != "auto")
            {
                var thinking = new Dictionary<string, object>();
                if (model.StartsWith("gemini-2.5", StringComparison.OrdinalIgnoreCase))
                    thinking["thinkingBudget"] = effort switch { "none" => 0, "minimal" or "low" => 1024, "medium" => 4096, _ => 8192 };
                else thinking["thinkingLevel"] = effort;
                payload["generationConfig"] = new Dictionary<string, object> { ["thinkingConfig"] = thinking };
            }
        }
        else if (format == "responses")
        {
            payload["input"] = dialogue.Select(m => WireMessage(m, format)).ToArray();
            payload["store"] = false;
            if (system.Length > 0) payload["instructions"] = system;
            if (effort != "auto") payload["reasoning"] = new { effort };
        }
        else if (format == "anthropic")
        {
            payload["messages"] = dialogue.Select(m => WireMessage(m, format)).ToArray();
            if (system.Length > 0) payload["system"] = system;
            // Messages requires this field; the other protocols retain the service's output budget.
            payload["max_tokens"] = settings.MessageMaxTokens;
            if (effort == "none") payload["thinking"] = new { type = "disabled" };
            else if (effort != "auto")
            {
                if (ChatProviders.AdaptiveThinking(model))
                {
                    payload["thinking"] = new { type = "adaptive" };
                    payload["output_config"] = new { effort };
                }
                else
                {
                    int budget = effort switch { "minimal" or "low" => 1024, "medium" => 4096, _ => 16384 };
                    payload["thinking"] = new { type = "enabled", budget_tokens = Math.Min(budget, settings.MessageMaxTokens - 1024) };
                    if (model.StartsWith("claude-opus-4-5", StringComparison.OrdinalIgnoreCase) || ChatProviders.IsDeepSeek(settings)) payload["output_config"] = new { effort };
                }
            }
        }
        else
        {
            payload["messages"] = input.Select(m => WireMessage(m, format)).ToArray();
            if (effort != "auto")
            {
                if (ChatProviders.IsOpenRouter(settings)) payload["reasoning"] = effort == "none" ? (object)new { enabled = false } : new { effort };
                else
                {
                    payload["reasoning_effort"] = effort;
                    if (ChatProviders.IsDeepSeek(settings)) payload["thinking"] = new { type = effort == "none" ? "disabled" : "enabled" };
                }
            }
        }
        return payload;
    }

    private static object WireMessage(JsonElement message, string format)
    {
        bool images = message.TryGetProperty("images", out var items) && items.ValueKind == JsonValueKind.Array && items.GetArrayLength() > 0;
        return new { role = Field(message, "role"), content = images ? (object)ContentParts(message, format) : Field(message, "content") };
    }

    private static object[] ContentParts(JsonElement message, string format)
    {
        var parts = new List<object>();
        string text = Field(message, "content");
        if (message.TryGetProperty("images", out var images) && images.ValueKind == JsonValueKind.Array)
            foreach (var image in images.EnumerateArray())
            {
                string mime = Field(image, "mime_type"), data = Field(image, "data");
                string url = "data:" + mime + ";base64," + data;
                parts.Add(format switch
                {
                    "responses" => new { type = "input_image", image_url = url },
                    "anthropic" => new { type = "image", source = new { type = "base64", media_type = mime, data } },
                    "gemini" => (object)new Dictionary<string, object> { ["inlineData"] = new Dictionary<string, object> { ["mimeType"] = mime, ["data"] = data } },
                    _ => new { type = "image_url", image_url = new { url } }
                });
            }
        if (text.Length > 0 || parts.Count == 0)
            parts.Add(format == "gemini" ? (object)new { text } : new { type = format == "responses" ? "input_text" : "text", text });
        return parts.ToArray();
    }

    private static string Text(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.String) return value.GetString() ?? "";
        if (value.ValueKind == JsonValueKind.Array)
            return string.Concat(value.EnumerateArray().Select(part => part.ValueKind == JsonValueKind.String ? part.GetString()
                : part.ValueKind == JsonValueKind.Object && part.TryGetProperty("text", out var text) ? Text(text) : ""));
        return "";
    }
    private static string Field(JsonElement value, string name) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var field) ? Text(field) : "";
    private static string Finish(string value) => value switch
    {
        "end_turn" or "stop_sequence" or "STOP" or "completed" => "stop",
        "max_tokens" or "max_output_tokens" or "MAX_TOKENS" or "incomplete" => "length",
        _ => value
    };
    private static void CheckError(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object && value.TryGetProperty("error", out var error) && error.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined))
            throw new IOException("模型服务返回错误：" + (Field(error, "message") is { Length: > 0 } message ? message : error.ToString()));
    }
    private static string Blocks(JsonElement blocks, bool reasoning = false)
    {
        if (blocks.ValueKind != JsonValueKind.Array) return Text(blocks);
        var text = new StringBuilder();
        foreach (var block in blocks.EnumerateArray())
        {
            string type = Field(block, "type");
            bool thought = type is "thinking" or "redacted_thinking" or "reasoning_text" or "summary_text" ||
                (block.ValueKind == JsonValueKind.Object && block.TryGetProperty("thought", out var flag) && flag.ValueKind == JsonValueKind.True);
            if (thought != reasoning) continue;
            if (type == "refusal") text.Append(Field(block, "refusal"));
            else text.Append(Field(block, "text") is { Length: > 0 } content ? content : Field(block, "thinking"));
        }
        return text.ToString();
    }
    private static SummaryResponse ReadResponse(JsonElement root, string fallback, bool requireEnvelope)
    {
        CheckError(root);
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("choices", out var choices))
        {
            if (choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0) return new("", "", "");
            var choice = choices[0];
            if (!choice.TryGetProperty("message", out var message)) return new("", "", Field(choice, "finish_reason"));
            return new(Field(message, "content"), Field(message, "reasoning_content") + Field(message, "reasoning"), Finish(Field(choice, "finish_reason")));
        }
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("output", out var output) && output.ValueKind == JsonValueKind.Array)
        {
            var content = new StringBuilder(); var reasoning = new StringBuilder();
            foreach (var item in output.EnumerateArray())
            {
                if (Field(item, "type") == "message" && item.TryGetProperty("content", out var parts)) content.Append(Blocks(parts));
                if (Field(item, "type") == "reasoning" && item.TryGetProperty("summary", out var summary)) reasoning.Append(Blocks(summary, true));
            }
            if (Field(root, "status") == "failed") throw new IOException("模型未能完成本次回复。");
            return new(content.ToString(), reasoning.ToString(), Finish(Field(root, "status")));
        }
        if (root.ValueKind == JsonValueKind.Object && Field(root, "type") == "message" && root.TryGetProperty("content", out var blocks))
            return new(Blocks(blocks), Blocks(blocks, true), Finish(Field(root, "stop_reason")));
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("candidates", out var candidates) && candidates.ValueKind == JsonValueKind.Array)
        {
            if (candidates.GetArrayLength() == 0) return new("", "", "");
            var candidate = candidates[0];
            if (!candidate.TryGetProperty("content", out var content) || !content.TryGetProperty("parts", out var parts)) return new("", "", Finish(Field(candidate, "finishReason")));
            return new(Blocks(parts), Blocks(parts, true), Finish(Field(candidate, "finishReason")));
        }
        if (requireEnvelope) throw new IOException("响应格式不匹配，请检查模型名称和高级设置中的 API 格式。");
        return new(root.ValueKind == JsonValueKind.String ? root.GetString() ?? "" : fallback, "", "");
    }

    public static SummaryResponse ReadSummary(string response, bool requireEnvelope = false)
    {
        JsonDocument document;
        try { document = JsonDocument.Parse(response); }
        catch (JsonException) when (!requireEnvelope) { return new SummaryResponse(response, "", ""); }
        using (document)
            return ReadResponse(document.RootElement, response, requireEnvelope);
    }

    public static ChatStreamPart ReadStreamPart(string data)
    {
        if (data.Trim() == "[DONE]") return new(Done: true);
        using var document = JsonDocument.Parse(data);
        var root = document.RootElement;
        CheckError(root);
        string type = Field(root, "type");
        if (type is "response.output_text.delta" or "response.refusal.delta") return new(Field(root, "delta"));
        if (type is "response.completed" or "response.incomplete" or "response.failed")
        {
            var response = ReadResponse(root.GetProperty("response"), "", true);
            return new(Done: true, FinishReason: response.FinishReason, FullText: response.Content);
        }
        if (type == "content_block_delta" && root.TryGetProperty("delta", out var delta))
            return Field(delta, "type") == "text_delta" ? new(Field(delta, "text")) : new();
        if (type == "content_block_start" && root.TryGetProperty("content_block", out var block))
            return Field(block, "type") == "text" ? new(Field(block, "text")) : new();
        if (type == "message_delta" && root.TryGetProperty("delta", out var messageDelta))
            return new(Done: Field(messageDelta, "stop_reason").Length > 0, FinishReason: Finish(Field(messageDelta, "stop_reason")));
        if (type == "message_stop") return new(Done: true);
        if (root.TryGetProperty("choices", out var choices) && choices.ValueKind == JsonValueKind.Array && choices.GetArrayLength() > 0)
        {
            var choice = choices[0];
            string finish = Finish(Field(choice, "finish_reason"));
            return new(choice.TryGetProperty("delta", out var chunk) ? Field(chunk, "content") : "", finish.Length > 0, finish);
        }
        if (root.TryGetProperty("candidates", out _))
        {
            var response = ReadResponse(root, "", true);
            return new(response.Content, response.FinishReason.Length > 0, response.FinishReason);
        }
        return new();
    }

    public static async IAsyncEnumerable<string> ReadEvents(Stream stream, [EnumeratorCancellation] CancellationToken cancellation)
    {
        using var reader = new StreamReader(stream);
        var data = new StringBuilder();
        while (await reader.ReadLineAsync(cancellation).ConfigureAwait(false) is { } line)
        {
            if (line.Length == 0)
            {
                if (data.Length == 0) continue;
                yield return data.ToString(); data.Clear();
            }
            else if (line.StartsWith("data:", StringComparison.Ordinal))
            {
                if (data.Length > 0) data.Append('\n');
                data.Append(line[5..].TrimStart(' '));
            }
        }
        if (data.Length > 0) yield return data.ToString();
    }
}
