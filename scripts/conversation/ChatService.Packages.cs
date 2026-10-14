using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace GdPal.Conversation;

internal sealed record PackageExportResult(string Path, string Filename);

public partial class ChatService
{
    [Signal] public delegate void PackageFinishedEventHandler(string profileId, string requestId, string json);
    private readonly Dictionary<string, PortablePackage> _packagePreviews = new();
    private readonly Dictionary<string, CancellationTokenSource> _packageJobs = new();
    private readonly HashSet<string> _importingProfiles = new();
    public string GetPackageImportDirectory() => Path.Combine(_root, "imports");
    public string DiscardPackageImport(string path) => Guard(() =>
    {
        string local = ProjectSettings.GlobalizePath(path);
        string expected = LocalFiles.Within(GetPackageImportDirectory(), Path.GetFileName(local));
        if (!Path.GetFullPath(local).Equals(Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("导入路径无效。");
        LocalFiles.DeleteOrStage(local, GetPackageImportDirectory());
    });
    private void PackageError(string id, string requestId, string error) => _pending.Enqueue(() => EmitSignal(SignalName.PackageFinished, id, requestId, ChatJson.Encode(new { error })));
    private void PackageJob(string id, string requestId, Func<CancellationToken, object> operation, Action<object>? accept = null)
    {
        if (_packageJobs.ContainsKey(requestId)) { PackageError(id, requestId, "请求正在处理。"); return; }
        var cancellation = new CancellationTokenSource(); _packageJobs[requestId] = cancellation;
        _ = Task.Run(() =>
        {
            object? result = null; string error = "";
            try { result = operation(cancellation.Token); }
            catch (Exception ex) { error = ex is OperationCanceledException ? "已取消操作。" : ex.Message; }
            _pending.Enqueue(() =>
            {
                if (!_packageJobs.Remove(requestId)) { cancellation.Dispose(); return; }
                if (cancellation.IsCancellationRequested)
                {
                    if (result is PackageExportResult exported) ReleaseExportPackage(exported.Path);
                    error = "已取消操作。";
                }
                cancellation.Dispose();
                if (error.Length == 0 && result is not null)
                {
                    try { accept?.Invoke(result); }
                    catch (Exception ex) { error = ex.Message; }
                }
                EmitSignal(SignalName.PackageFinished, id, requestId, error.Length == 0 ? ChatJson.Encode(result) : ChatJson.Encode(new { error }));
            });
        });
    }
    public void ExportPackage(string id, string requestId, string kind, string sessionId, string draftJson, bool includeMemory, bool includeWorld)
    {
        try
        {
            if (!_companions.TryGetValue(id, out var c) || c.LoadFailed) throw new InvalidOperationException("无法读取伙伴资料。");
            var package = new PortablePackage { Manifest = new() { PackageType = kind, ProfileId = id, DisplayName = c.Profile.DisplayName } };
            if (kind == "persona")
            {
                ReloadContext(id);
                using var draft = JsonDocument.Parse(draftJson);
                var p = new PersonaDocument { DisplayName = c.Profile.DisplayName, Persona = c.Profile.Persona,
                    Memory = includeMemory ? c.Profile.Memory : null, ActiveMemory = includeMemory ? c.Profile.ActiveMemory : null, World = includeWorld ? c.Profile.World : null };
                if (draft.RootElement.TryGetProperty("name", out var name)) p.DisplayName = name.GetString() ?? "";
                if (draft.RootElement.TryGetProperty("persona", out var persona)) p.Persona = persona.GetString() ?? "";
                package.Persona = p; package.Manifest.DisplayName = p.DisplayName; PackageCodec.ValidatePersona(p);
            }
            else if (kind == "conversations")
            {
                var sessions = Sessions(id).Where(s => sessionId.Length == 0 || s.SessionId == sessionId).ToList();
                if (sessions.Count == 0) throw new InvalidOperationException("没有有内容的会话可导出。");
                package.Sessions = ChatJson.Decode<List<ChatSession>>(ChatJson.Encode(sessions));
            }
            else throw new ArgumentException("未知导出类型。");
            PackageJob(id, requestId, token =>
            {
                string path = Path.Combine(_root, "exports", Guid.NewGuid().ToString("N") + ".zip");
                PackageCodec.Write(path, package, token, DirectoryFor(id));
                return new PackageExportResult(path, "GD-Pal-" + kind + "-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".zip");
            });
        }
        catch (Exception ex) { PackageError(id, requestId, ex.Message); }
    }
    public string ReleaseExportPackage(string path) => Guard(() =>
    {
        string expected = LocalFiles.Within(Path.Combine(_root, "exports"), Path.GetFileName(path));
        if (!Path.GetFullPath(path).Equals(Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("导出路径无效。");
        LocalFiles.DeleteOrStage(path, Path.Combine(_root, "exports"));
    });
    public void PreviewPackage(string id, string requestId, string path)
    {
        string local = ProjectSettings.GlobalizePath(path), tokenId = Guid.NewGuid().ToString("N");
        PortablePackage? package = null;
        PackageJob(id, requestId, cancellation =>
        {
            string expected = LocalFiles.Within(Path.Combine(_root, "imports"), Path.GetFileName(local));
            if (!Path.GetFullPath(local).Equals(Path.GetFullPath(expected), StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("请通过文件选择器重新选择数据包。");
            try { package = PackageCodec.Read(local, cancellation); }
            finally { LocalFiles.DeleteOrStage(local, Path.Combine(_root, "imports")); }
            return new { token = tokenId, kind = package.Manifest.PackageType, persona = package.Persona,
                session_count = package.Manifest.SessionCount, message_count = package.Manifest.MessageCount, display_name = package.Manifest.DisplayName };
        }, _ => _packagePreviews[tokenId] = package!);
    }
    public void ReleasePackagePreview(string token) => _packagePreviews.Remove(token);
    public string ApplyPersonaPackage(string id, string token, string fieldsJson)
    {
        if (!_packagePreviews.TryGetValue(token, out var package) || package.Persona is not { } p) return "预览已失效，请重新选择文件。";
        return EditProfile(id, candidate =>
        {
            var fields = ChatJson.Decode<List<string>>(fieldsJson);
            if (fields.Count == 0) throw new ArgumentException("请至少选择一个导入字段。");
            PackageCodec.ValidatePersona(p);
            if (fields.Contains("name")) candidate.DisplayName = p.DisplayName;
            if (fields.Contains("persona")) { candidate.Persona = p.Persona; candidate.PersonaBeforeSummary = p.Persona; }
            if (fields.Contains("memory") && p.Memory is not null) candidate.Memory = p.Memory;
            if (fields.Contains("active_memory") && p.ActiveMemory is not null) candidate.ActiveMemory = p.ActiveMemory;
            if (fields.Contains("world") && p.World is not null) candidate.World = p.World;
        });
    }
    public void ImportConversationPackage(string id, string requestId, string previewToken)
    {
        if (!_companions.ContainsKey(id) || !_packagePreviews.TryGetValue(previewToken, out var package) || package.Manifest.PackageType != "conversations")
        { PackageError(id, requestId, "预览已失效，请重新选择文件。"); return; }
        if (!_importingProfiles.Add(id)) { PackageError(id, requestId, "正在导入这位伙伴的记录。"); return; }
        HashSet<string> imported;
        try { imported = Sessions(id).SelectMany(s => new[] { s.ImportFingerprint, LocalFiles.Hash(id + ":" + s.SessionId + ":" + ChatJson.Encode(s)) }).Where(s => s.Length > 0).ToHashSet(); }
        catch (Exception ex) { _importingProfiles.Remove(id); PackageError(id, requestId, ex.Message); return; }
        var records = ChatJson.Decode<List<ChatSession>>(ChatJson.Encode(package.Sessions));
        PackageJob(id, requestId, cancellation =>
        {
            int added = 0, skipped = 0;
            try
            {
                foreach (var session in records)
                {
                    cancellation.ThrowIfCancellationRequested();
                    if (!imported.Add(session.ImportFingerprint)) { skipped++; continue; }
                    session.SessionId = Guid.NewGuid().ToString("N");
                    var turns = new Dictionary<string, string>();
                    foreach (var message in session.Messages)
                    {
                        message.Id = Guid.NewGuid().ToString("N");
                        if (!turns.ContainsKey(message.TurnId)) turns[message.TurnId] = Guid.NewGuid().ToString("N");
                        message.TurnId = turns[message.TurnId];
                        if (message.Status == "streaming") message.Status = "interrupted";
                    }
                    string path = SessionPath(id, session.SessionId);
                    var imageFiles = ImportSessionImages(id, session, package.Images, cancellation);
                    try
                    {
                        LocalFiles.Write(Path.ChangeExtension(path, ".md"), PackageCodec.Markdown(session, package.Manifest.DisplayName));
                        LocalFiles.Write(path, ChatJson.Encode(session)); added++;
                    }
                    catch
                    {
                        foreach (string file in imageFiles) DiscardImageFiles(DirectoryFor(id), file);
                        throw;
                    }
                }
                return new { imported = added, skipped, notice = $"已导入 {added} 段，跳过 {skipped} 段重复记录。" };
            }
            catch (Exception ex) { throw new IOException($"已导入 {added} 段，剩余未完成，可重新导入以继续：" + ex.Message, ex); }
        }, _ => Changed(id));
        // Completion owns release even when the operation fails.
        void Completed(string profile, string request, string result)
        {
            if (request != requestId) return;
            _importingProfiles.Remove(id); PackageFinished -= Completed;
        }
        PackageFinished += Completed;
    }
    public void CancelPackage(string requestId)
    {
        if (_packageJobs.TryGetValue(requestId, out var cancellation)) cancellation.Cancel();
    }
}
