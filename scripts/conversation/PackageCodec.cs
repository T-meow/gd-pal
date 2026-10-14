// Adapted from Yumo ConversationPackage and ChatEngine.Export (MIT).
// See licenses/yumo/PORTING.md. Archives are read in memory, never extracted by entry path.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;

namespace GdPal.Conversation;

internal sealed class PersonaDocument
{
    public int SchemaVersion { get; set; } = 1;
    public string DisplayName { get; set; } = "";
    public string Persona { get; set; } = "";
    public string? Memory { get; set; }
    public string? ActiveMemory { get; set; }
    public string? World { get; set; }
}
internal sealed class PackageManifest
{
    public int SchemaVersion { get; set; } = 1;
    public string PackageType { get; set; } = "";
    public string ProfileId { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public int SessionCount { get; set; }
    public int MessageCount { get; set; }
    public List<PackageFile> Files { get; set; } = new();
}
internal sealed class PackageFile
{
    public string Path { get; set; } = "";
    public long Bytes { get; set; }
    public string Sha256 { get; set; } = "";
}
internal sealed class PortablePackage
{
    public PackageManifest Manifest { get; set; } = new();
    public PersonaDocument? Persona { get; set; }
    public List<ChatSession> Sessions { get; set; } = new();
    public Dictionary<string, byte[]> Images { get; set; } = new();
}
internal static class PackageCodec
{
    internal static void ValidatePersona(PersonaDocument p)
    {
        if (p.SchemaVersion != 1 || string.IsNullOrWhiteSpace(p.DisplayName) || p.DisplayName.Length > 40 || p.Persona is null || p.Persona.Length > 4000 ||
            p.Memory?.Length > 16000 || p.ActiveMemory?.Length > 16000 || p.World?.Length > 16000) throw new InvalidDataException("人设包内容无效或超过长度限制。");
    }
    internal static string Markdown(ChatSession session, string name) => "# " + name + "\n\n" +
        string.Join("\n\n", session.Messages.Select(m => "## " + (m.Role == "user" ? "你" : name) + "\n\n" + m.Content +
            string.Concat(m.Images.Select(image => "\n\n![聊天图片](../images/" + image.File + ")"))));
    internal static void Write(string path, PortablePackage package, CancellationToken token, string imageDirectory = "")
    {
        var files = new Dictionary<string, byte[]>();
        void AddText(string name, string text) => files[name] = Encoding.UTF8.GetBytes(text);
        var manifest = package.Manifest;
        if (package.Persona is { } p)
        {
            ValidatePersona(p); AddText("persona.json", ChatJson.Encode(p));
            AddText("persona.md", "# " + p.DisplayName + "\n\n" + p.Persona);
            if (p.Memory is not null) AddText("memory_long_term.md", p.Memory);
            if (p.ActiveMemory is not null) AddText("memory_active.md", p.ActiveMemory);
            if (p.World is not null) AddText("world.md", p.World);
        }
        else
        {
            if (package.Sessions.Count == 0) throw new ArgumentException("没有可导出的对话。");
            manifest.SessionCount = package.Sessions.Count;
            manifest.MessageCount = package.Sessions.Sum(s => s.Messages.Count);
            AddText("conversations/index.json", ChatJson.Encode(package.Sessions.Select(s => new { session_id = s.SessionId })));
            foreach (var session in package.Sessions)
            {
                AddText("conversations/" + session.SessionId + ".json", ChatJson.Encode(session));
                AddText("conversations/" + session.SessionId + ".md", Markdown(session, manifest.DisplayName));
                foreach (var image in session.Messages.SelectMany(m => m.Images))
                {
                    token.ThrowIfCancellationRequested();
                    string name = "images/" + image.File;
                    if (files.ContainsKey(name)) continue;
                    byte[] bytes = package.Images.TryGetValue(image.File, out var embedded) ? embedded : ChatImages.Read(imageDirectory, image);
                    ChatImages.ValidateBytes(image, bytes);
                    files[name] = bytes;
                    if (files.Sum(f => (long)f.Value.Length) > 128 * 1024 * 1024) throw new InvalidDataException("记录及图片过多，请分段导出。");
                }
            }
        }
        manifest.Files = files.Select(f => new PackageFile { Path = f.Key, Bytes = f.Value.Length, Sha256 = LocalFiles.Hash(f.Value) }).ToList();
        AddText("manifest.json", ChatJson.Encode(manifest));
        if (files.Count > 4004 || files.Any(f => f.Value.Length > 32 * 1024 * 1024) || files.Sum(f => (long)f.Value.Length) > 128 * 1024 * 1024)
            throw new InvalidDataException("记录过多，请分段导出。");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        try
        {
            using (var archive = ZipFile.Open(path, ZipArchiveMode.Create))
                foreach (var file in files)
                {
                    token.ThrowIfCancellationRequested();
                    using var writer = archive.CreateEntry(file.Key).Open(); writer.Write(file.Value);
                }
            if (new FileInfo(path).Length > 64 * 1024 * 1024) throw new InvalidDataException("记录包超过 64 MB，请分段导出。");
        }
        catch { LocalFiles.DeleteOrStage(path, Path.GetDirectoryName(path)!); throw; }
    }
    internal static PortablePackage Read(string path, CancellationToken token)
    {
        using var file = File.OpenRead(path);
        if (file.Length is <= 0 or > 64 * 1024 * 1024) throw new InvalidDataException("请选择 64 MB 以内的 ZIP 包。");
        using var archive = new ZipArchive(file, ZipArchiveMode.Read);
        if (archive.Entries.Count is < 3 or > 4004) throw new InvalidDataException("包内文件数量无效。");
        var documents = new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
        string TextFile(string name) => new UTF8Encoding(false, true).GetString(documents[name]);
        long total = 0;
        foreach (var entry in archive.Entries)
        {
            token.ThrowIfCancellationRequested(); string name = entry.FullName;
            if (string.IsNullOrEmpty(name) || name.Contains('\\') || name.Contains(':') || name.Split('/').Any(p => p is "" or "." or ".." || p.Any(char.IsControl)) || documents.ContainsKey(name))
                throw new InvalidDataException("包内含无效或重复的文件路径。");
            total += entry.Length;
            if (entry.Length > 32 * 1024 * 1024 || total > 128 * 1024 * 1024) throw new InvalidDataException("解压后的内容过大。");
            using var input = entry.Open(); using var output = new MemoryStream(); byte[] buffer = new byte[65536]; int count;
            while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                token.ThrowIfCancellationRequested();
                if (output.Length + count > entry.Length) throw new InvalidDataException("包内文件长度无效。");
                output.Write(buffer, 0, count);
            }
            if (output.Length != entry.Length) throw new InvalidDataException("包内文件不完整。");
            documents.Add(name, output.ToArray());
        }
        if (!documents.ContainsKey("manifest.json")) throw new InvalidDataException("缺少 manifest.json。");
        var manifest = ChatJson.Decode<PackageManifest>(TextFile("manifest.json"));
        if (manifest.SchemaVersion != 1 || manifest.PackageType is not ("persona" or "conversations") || manifest.Files.Count != documents.Count - 1)
            throw new InvalidDataException("请选择轻量版导出的 v1 人设包或对话包。");
        var verified = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in manifest.Files)
            if (entry.Path == "manifest.json" || !verified.Add(entry.Path) || !documents.TryGetValue(entry.Path, out var bytes) || bytes.Length != entry.Bytes || LocalFiles.Hash(bytes) != entry.Sha256)
                throw new InvalidDataException("数据包完整性校验失败。");
        var package = new PortablePackage { Manifest = manifest };
        if (manifest.PackageType == "persona")
        {
            using var raw = JsonDocument.Parse(TextFile("persona.json"));
            if (!raw.RootElement.TryGetProperty("persona", out var body) || body.ValueKind != JsonValueKind.String)
                throw new InvalidDataException("请选择轻量版人设包，旧版人设结构不直接导入。");
            package.Persona = ChatJson.Decode<PersonaDocument>(TextFile("persona.json")); ValidatePersona(package.Persona);
        }
        else
        {
            using var index = JsonDocument.Parse(TextFile("conversations/index.json"));
            if (index.RootElement.ValueKind != JsonValueKind.Array || manifest.SessionCount is < 1 or > 2000 || index.RootElement.GetArrayLength() != manifest.SessionCount)
                throw new InvalidDataException("对话目录无效。");
            var ids = new HashSet<string>(); int messages = 0;
            foreach (var item in index.RootElement.EnumerateArray())
            {
                token.ThrowIfCancellationRequested();
                string id = item.GetProperty("session_id").GetString() ?? "";
                if (!ValidId(id) || !ids.Add(id)) throw new InvalidDataException("会话标识无效。");
                string text = TextFile("conversations/" + id + ".json");
                var session = ChatJson.Decode<ChatSession>(text);
                if (session.SchemaVersion != 1 || session.SessionId != id || session.Messages is null || !DateTimeOffset.TryParse(session.CreatedAt, out _) || !DateTimeOffset.TryParse(session.UpdatedAt, out _))
                    throw new InvalidDataException("会话内容无效。");
                var messageIds = new HashSet<string>();
                foreach (var message in session.Messages)
                {
                    if (!ValidId(message.Id) || !messageIds.Add(message.Id) || message.Role is not ("user" or "assistant") || message.Content is null || message.Content.Length > 1000000 ||
                        message.Status is not ("complete" or "streaming" or "truncated" or "stopped" or "failed" or "interrupted") ||
                        !ValidId(message.TurnId) || message.Segments is null || message.Segments.Count > 4096 || message.Segments.Any(s => s is null) ||
                        message.Images is null || message.Images.Count > ChatImages.MaxPerMessage || (message.Role != "user" && message.Images.Count > 0)) throw new InvalidDataException("消息内容无效。");
                    foreach (var image in message.Images)
                    {
                        if (image is null || !documents.TryGetValue("images/" + image.File, out var bytes)) throw new InvalidDataException("对话包缺少图片附件。");
                        ChatImages.ValidateBytes(image, bytes);
                        package.Images[image.File] = bytes;
                    }
                }
                messages += session.Messages.Count;
                if (messages > 100000) throw new InvalidDataException("消息超过 10 万条，请分段导入。");
                if (session.ImportFingerprint.Length != 64 || !session.ImportFingerprint.All(Uri.IsHexDigit))
                    session.ImportFingerprint = LocalFiles.Hash(manifest.ProfileId + ":" + id + ":" + text);
                package.Sessions.Add(session);
            }
            if (messages != manifest.MessageCount) throw new InvalidDataException("消息数量与清单不一致。");
        }
        return package;
    }
    internal static bool ValidId(string id) => !string.IsNullOrEmpty(id) && id.Length <= 80 && id.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-');
}
