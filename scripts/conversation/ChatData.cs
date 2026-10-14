using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Unicode;

namespace GdPal.Conversation;

public interface IChatCredentialStore
{
    string Read(string endpoint);
    void Write(string endpoint, string value);
    void Delete(string endpoint);
}

internal static class ChatJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        Encoder = JavaScriptEncoder.Create(UnicodeRanges.All),
        WriteIndented = true
    };
    public static string Encode<T>(T value) => JsonSerializer.Serialize(value, Options);
    public static T Decode<T>(string json) where T : new() => JsonSerializer.Deserialize<T>(json, Options) ?? new T();
    public static string Id() => Guid.NewGuid().ToString("N");
    public static string Now() => DateTimeOffset.Now.ToString("O");
    public static int Length(string text) => text.Length;
    public static string Clip(string text, int length) => text[..Math.Min(text.Length, length)];
}

internal static class LocalFiles
{
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    public static string Hash(byte[] value) => Convert.ToHexString(SHA256.HashData(value));
    public static string Within(string directory, string filename)
    {
        if (string.IsNullOrWhiteSpace(filename) || filename != Path.GetFileName(filename) || filename is "." or "..")
            throw new ArgumentException("文件名无效。");
        return Path.Combine(directory, filename);
    }
    public static void Write(string path, string text)
        => WriteBytes(path, Encoding.UTF8.GetBytes(text));
    public static void WriteBytes(string path, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        string temporary = path + ".writing";
        using (var file = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            file.Write(bytes);
            file.Flush(true);
        }
        File.Move(temporary, path, true);
    }
    public static T Read<T>(string path) where T : new() => File.Exists(path) ? ChatJson.Decode<T>(File.ReadAllText(path)) : new T();
    public static void DeleteOrStage(string path, string directory)
    {
        if (!File.Exists(path)) return;
        try { File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            string pending = Path.Combine(directory, "_pending_delete");
            Directory.CreateDirectory(pending);
            File.Move(path, Path.Combine(pending, Guid.NewGuid().ToString("N") + "-" + Path.GetFileName(path)));
        }
    }
}

internal sealed class ChatSettings
{
    public int SchemaVersion { get; set; } = 1;
    public string Provider { get; set; } = "deepseek";
    public string BaseUrl { get; set; } = "https://api.deepseek.com";
    public string Model { get; set; } = "deepseek-flash";
    public string ReasoningEffort { get; set; } = "high";
    public string ApiFormat { get; set; } = "auto";
    public int MessageMaxTokens { get; set; } = 32768;
    public bool RememberKey { get; set; }
}

internal sealed class SpeechSettings
{
    public int SchemaVersion { get; set; } = 1;
    public bool Enabled { get; set; }
    public string BaseUrl { get; set; } = "http://127.0.0.1:8000/v1";
    public string Model { get; set; } = "tts-1";
    public string Voice { get; set; } = "alloy";
    public bool RememberKey { get; set; }
}

internal sealed class ManualProfile
{
    public int SchemaVersion { get; set; } = 1;
    public string DisplayName { get; set; } = "伙伴";
    public bool AdultMode { get; set; }
    public string Persona { get; set; } = "";
    public string? PersonaBeforeSummary { get; set; }
    public string Memory { get; set; } = "";
    public string ActiveMemory { get; set; } = "";
    public string World { get; set; } = "";
    public bool AutoSpeak { get; set; }
    public string ActiveSessionId { get; set; } = "";
}

internal sealed class ChatSession
{
    public string ImportFingerprint { get; set; } = "";
    public int SchemaVersion { get; set; } = 1;
    public string SessionId { get; set; } = Guid.NewGuid().ToString("N");
    public string CreatedAt { get; set; } = DateTimeOffset.Now.ToString("O");
    public string UpdatedAt { get; set; } = DateTimeOffset.Now.ToString("O");
    public List<ChatMessage> Messages { get; set; } = new();
    public bool HasContent() => Messages.Exists(message => message.HasContent());
    public string Title() => (Messages.Find(message => message.Role == "user" && message.HasContent())
        ?? Messages.Find(message => message.HasContent()))?.Preview() ?? "新对话";
}

internal sealed class ChatMessage
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string TurnId { get; set; } = Guid.NewGuid().ToString("N");
    public string Role { get; set; } = "user";
    public bool IsContinuation { get; set; }
    public string Content { get; set; } = "";
    public string Status { get; set; } = "complete";
    public string Error { get; set; } = "";
    public List<DialogueSegment> Segments { get; set; } = new();
    public List<ChatImage> Images { get; set; } = new();
    public bool HasContent() => !string.IsNullOrWhiteSpace(Content) || Images.Count > 0;
    public string Preview() => string.IsNullOrWhiteSpace(Content) && Images.Count > 0 ? $"[图片 × {Images.Count}]" : Content;
}

internal sealed class ChatImage
{
    public string File { get; set; } = "";
    public string MimeType { get; set; } = "image/jpeg";
    public int Width { get; set; }
    public int Height { get; set; }
    public long Bytes { get; set; }
}

internal sealed class DialogueSegment
{
    public string? Say { get; set; }
    public string? Aside { get; set; }
    public string DisplayText { get; set; } = "";
}
