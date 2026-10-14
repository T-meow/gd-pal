using System;
using System.Linq;
using System.Text.RegularExpressions;

namespace GdPal.Conversation;

internal sealed record ChatProviderPreset(string Id, string Name, string BaseUrl, string Model, string Hint);

internal static class ChatProviders
{
    public static readonly ChatProviderPreset[] Presets =
    {
        new("deepseek", "DeepSeek", "https://api.deepseek.com", "deepseek-flash", "填写 DeepSeek API Key；可改用该服务的其他模型。"),
        new("opencode", "OpenCode Console / Zen", "https://opencode.ai/inference/v1", "", "使用 OpenCode Console API Key，填写模型 ID；自动匹配 GPT、Claude、Gemini 与开放模型的接口。"),
        new("opencode_go", "OpenCode Go", "https://opencode.ai/inference/go/v1", "", "使用 OpenCode Go API Key，填写 Go 套餐支持的模型 ID。"),
        new("openrouter", "OpenRouter", "https://openrouter.ai/api/v1", "", "填写完整模型 ID，包括该服务要求的提供商前缀。"),
        new("openai_official", "OpenAI", "https://api.openai.com/v1", "", "填写 OpenAI API Key 和模型 ID，默认使用 Responses 接口。"),
        new("anthropic", "Anthropic / Claude", "https://api.anthropic.com/v1", "", "使用 Anthropic API Key；Messages 接口的输出额度可在高级设置调整。"),
        new("gemini", "Google Gemini", "https://generativelanguage.googleapis.com/v1beta", "", "使用 Google AI Studio API Key 和 Gemini 模型 ID。"),
        new("openai", "自定义兼容 API", "", "", "填写服务的基础地址和模型 ID；可在高级设置选择 API 格式。")
    };
    public static readonly string[] Formats = { "auto", "chat_completions", "responses", "anthropic", "gemini" };
    public static readonly string[] Efforts = { "auto", "none", "minimal", "low", "medium", "high", "xhigh", "max" };

    private static bool Host(ChatSettings settings, string host) => Uri.TryCreate(settings.BaseUrl, UriKind.Absolute, out var uri) && uri.Host.Equals(host, StringComparison.OrdinalIgnoreCase);
    public static bool IsOpenCode(ChatSettings s) => s.Provider is "opencode" or "opencode_go" || Host(s, "opencode.ai");
    public static bool IsOpenRouter(ChatSettings s) => s.Provider == "openrouter" || Host(s, "openrouter.ai");
    public static bool IsDeepSeek(ChatSettings s) => s.Provider == "deepseek" || Host(s, "api.deepseek.com") || Model(s).StartsWith("deepseek", StringComparison.OrdinalIgnoreCase);
    public static string Model(ChatSettings s)
    {
        string model = s.Model.Trim();
        if (IsOpenCode(s))
            foreach (string prefix in new[] { "opencode/", "opencode-go/" })
                if (model.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return model[prefix.Length..];
        return model;
    }
    public static string Format(ChatSettings s)
    {
        if (s.ApiFormat != "auto" && Formats.Contains(s.ApiFormat)) return s.ApiFormat;
        string url = s.BaseUrl.TrimEnd('/').ToLowerInvariant();
        if (url.EndsWith("/chat/completions")) return "chat_completions";
        if (url.EndsWith("/responses")) return "responses";
        if (url.EndsWith("/messages")) return "anthropic";
        if (url.Contains(":generatecontent") || url.Contains(":streamgeneratecontent")) return "gemini";
        if (IsOpenRouter(s)) return "chat_completions";
        if (IsOpenCode(s))
        {
            // OpenCode documents model-specific routes; the explicit format can override these defaults.
            string model = Model(s).ToLowerInvariant();
            bool go = s.Provider == "opencode_go" || url.Contains("/go/");
            if (model.StartsWith("gpt-") || model.StartsWith("grok-") || model.StartsWith("muse-")) return "responses";
            if (model.StartsWith("gemini-")) return "gemini";
            if (model.StartsWith("claude-") || (model.StartsWith("qwen") && (go || model != "qwen3.8-max")) || (go && model.StartsWith("minimax-"))) return "anthropic";
            return "chat_completions";
        }
        if (s.Provider == "anthropic" || Host(s, "api.anthropic.com")) return "anthropic";
        if (s.Provider == "gemini" || Host(s, "generativelanguage.googleapis.com")) return "gemini";
        if (s.Provider == "openai_official" || Host(s, "api.openai.com")) return "responses";
        return "chat_completions";
    }
    public static bool AdaptiveThinking(string model) => Regex.IsMatch(model, @"^claude-(?:(?:opus|sonnet)-(?:4-[6-9]|[5-9](?:-|$))|haiku-[5-9](?:-|$)|(?:fable|mythos)-)", RegexOptions.IgnoreCase);
    public static string[] ReasoningLevels(ChatSettings s)
    {
        string format = Format(s), model = Model(s).ToLowerInvariant();
        if (format == "gemini") return model.StartsWith("gemini-3-pro") ? new[] { "auto", "low", "high" } : new[] { "auto", "low", "medium", "high" };
        if (IsDeepSeek(s) && !IsOpenRouter(s)) return new[] { "auto", "none", "low", "high", "max" };
        if (format == "anthropic")
        {
            if (!AdaptiveThinking(model)) return new[] { "auto", "none", "low", "medium", "high" };
            if (model.StartsWith("claude-fable-") || model.StartsWith("claude-mythos-") || Regex.IsMatch(model, @"^claude-(?:opus|sonnet|haiku)-5-5")) return new[] { "auto", "low", "medium", "high", "xhigh", "max" };
            if (model.StartsWith("claude-opus-4-6") || model.StartsWith("claude-sonnet-4-6")) return new[] { "auto", "none", "low", "medium", "high", "max" };
            return new[] { "auto", "none", "low", "medium", "high", "xhigh", "max" };
        }
        if (model.StartsWith("gpt-6")) return new[] { "auto", "low", "medium", "high", "xhigh", "max" };
        return Efforts;
    }
    public static void Normalize(ChatSettings s)
    {
        s.Provider = s.Provider.Trim().ToLowerInvariant();
        s.Model = Model(s);
        s.ApiFormat = s.ApiFormat.Trim().ToLowerInvariant();
        s.ReasoningEffort = s.ReasoningEffort.Trim().ToLowerInvariant();
        if (!Formats.Contains(s.ApiFormat)) throw new ArgumentException("请选择有效的 API 格式。");
        if (!Efforts.Contains(s.ReasoningEffort)) throw new ArgumentException("请选择有效的思考强度。");
        s.MessageMaxTokens = Math.Clamp(s.MessageMaxTokens, 2048, 262144);
    }
}
