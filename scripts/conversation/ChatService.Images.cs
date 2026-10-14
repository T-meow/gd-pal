using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Godot;

namespace GdPal.Conversation;

public partial class ChatService
{
    [Signal] public delegate void ChatImageImportedEventHandler(string profileId, string requestId, string json);
    private readonly SemaphoreSlim _imageDecoder = new(1, 1);
    private readonly CancellationTokenSource _imageLifetime = new();
    private readonly ConcurrentDictionary<string, string> _draftChatImages = new();

    public void ImportChatImage(string id, string requestId, string source) => ImportImage(id, requestId, source, null);
    public void ImportClipboardImage(string id, string requestId)
    {
        if (OS.GetName() is "Android" or "iOS") return;
        ImportImage(id, requestId, "", DisplayServer.ClipboardGetImage());
    }
    private void ImportImage(string id, string requestId, string source, Image? clipboard)
    {
        if (!_companions.ContainsKey(id) || _closed) { clipboard?.Dispose(); return; }
        string directory = DirectoryFor(id);
        var cancellation = _imageLifetime.Token;
        _ = Task.Run(async () =>
        {
            ChatImage? attachment = null;
            string error = "";
            bool entered = false;
            try
            {
                await _imageDecoder.WaitAsync(cancellation).ConfigureAwait(false); entered = true;
                using var image = clipboard ?? LoadPickedImage(source);
                if (image.IsEmpty()) throw new IOException("剪贴板中没有可读取的图片。");
                if ((long)image.GetWidth() * image.GetHeight() > ChatImages.MaxPixels) throw new IOException("图片分辨率过大，请先缩小图片。");
                ShrinkImage(image, ChatImages.MaxEdge);
                bool alpha = image.DetectAlpha() != Image.AlphaMode.None;
                image.Convert(alpha ? Image.Format.Rgba8 : Image.Format.Rgb8);
                byte[] bytes;
                do
                {
                    cancellation.ThrowIfCancellationRequested();
                    bytes = alpha ? image.SavePngToBuffer() : image.SaveJpgToBuffer(0.88f);
                    if (bytes.Length <= ChatImages.MaxBytes) break;
                    ShrinkImage(image, Math.Max(1, (int)(Math.Max(image.GetWidth(), image.GetHeight()) * 0.8)));
                } while (Math.Max(image.GetWidth(), image.GetHeight()) > 1);
                if (bytes.Length == 0) throw new IOException("无法编码所选图片。");
                attachment = new ChatImage { File = ChatJson.Id() + (alpha ? ".png" : ".jpg"), MimeType = alpha ? "image/png" : "image/jpeg",
                    Width = image.GetWidth(), Height = image.GetHeight(), Bytes = bytes.Length };
                string path = ChatImages.PathFor(directory, attachment.File);
                _draftChatImages[path] = directory;
                LocalFiles.WriteBytes(path, bytes);
                ShrinkImage(image, 240);
                LocalFiles.WriteBytes(ChatImages.ThumbnailPath(directory, attachment.File), image.SaveJpgToBuffer(0.8f));
                cancellation.ThrowIfCancellationRequested();
            }
            catch (Exception ex)
            {
                error = ex is OperationCanceledException ? "已取消图片导入。" : ex.Message;
                if (attachment is not null)
                {
                    string cleanup = Guard(() => DiscardImageFiles(directory, attachment.File));
                    if (cleanup.Length > 0) error += " 图片临时文件清理失败：" + cleanup;
                }
            }
            finally
            {
                if (entered) _imageDecoder.Release();
                else clipboard?.Dispose();
            }
            if (cancellation.IsCancellationRequested) return;
            _pending.Enqueue(() =>
            {
                if (!_companions.ContainsKey(id)) { if (attachment is not null) DiscardImageFiles(directory, attachment.File); return; }
                EmitSignal(SignalName.ChatImageImported, id, requestId, ChatJson.Encode(new { image = error.Length == 0 ? attachment : null, error }));
            });
        });
    }
    private static Image LoadPickedImage(string source)
    {
        // Android SAF returns content:// URIs. Godot FileAccess resolves these; System.IO does not.
        using var input = Godot.FileAccess.Open(source, Godot.FileAccess.ModeFlags.Read);
        if (input is null) throw new IOException("无法读取所选图片，请重新选择。");
        ulong length = input.GetLength();
        if (length is 0 or > ChatImages.MaxSourceBytes) throw new IOException("请选择 20 MB 以内的图片。");
        byte[] bytes = input.GetBuffer((long)length);
        if ((ulong)bytes.Length != length) throw new IOException("图片没有读取完整，请重新选择。");
        var header = ChatImages.Inspect(bytes);
        var image = new Image();
        Error loaded = header.MimeType switch
        {
            "image/png" => image.LoadPngFromBuffer(bytes),
            "image/jpeg" => image.LoadJpgFromBuffer(bytes),
            _ => image.LoadWebpFromBuffer(bytes)
        };
        if (loaded != Error.Ok) { image.Dispose(); throw new IOException("图片无法解码，请选择静态 PNG、JPEG 或 WebP 图片。"); }
        ShrinkImage(image, ChatImages.MaxEdge);
        switch (header.Orientation)
        {
            case 2: image.FlipX(); break;
            case 3: image.FlipX(); image.FlipY(); break;
            case 4: image.FlipY(); break;
            case 5: image.FlipX(); image.Rotate90(ClockDirection.Counterclockwise); break;
            case 6: image.Rotate90(ClockDirection.Clockwise); break;
            case 7: image.FlipX(); image.Rotate90(ClockDirection.Clockwise); break;
            case 8: image.Rotate90(ClockDirection.Counterclockwise); break;
        }
        return image;
    }
    private static void ShrinkImage(Image image, int edge)
    {
        int longest = Math.Max(image.GetWidth(), image.GetHeight());
        if (longest <= edge) return;
        double ratio = (double)edge / longest;
        image.Resize(Math.Max(1, (int)Math.Round(image.GetWidth() * ratio)), Math.Max(1, (int)Math.Round(image.GetHeight() * ratio)), Image.Interpolation.Lanczos);
    }
    public string GetChatImagePath(string id, string file, bool thumbnail = false)
    {
        try
        {
            string directory = DirectoryFor(id), path = ChatImages.PathFor(directory, file);
            string small = ChatImages.ThumbnailPath(directory, file);
            return thumbnail && File.Exists(small) ? small : path;
        }
        catch { return ""; }
    }
    public string DiscardChatImage(string id, string file) => Guard(() =>
    {
        string directory = DirectoryFor(id), path = ChatImages.PathFor(directory, file);
        if (_draftChatImages.ContainsKey(path)) DiscardImageFiles(directory, file);
    });
    private void DiscardImageFiles(string directory, string file)
    {
        string path = ChatImages.PathFor(directory, file);
        LocalFiles.DeleteOrStage(path, directory);
        LocalFiles.DeleteOrStage(ChatImages.ThumbnailPath(directory, file), directory);
        _draftChatImages.TryRemove(path, out _);
    }
    private void CommitChatImages(string id, IEnumerable<ChatImage> images)
    {
        foreach (var image in images) _draftChatImages.TryRemove(ChatImages.PathFor(DirectoryFor(id), image.File), out _);
    }
    private void DeleteSessionImages(string id, ChatSession session)
    {
        var referenced = Sessions(id).SelectMany(s => s.Messages).SelectMany(m => m.Images).Select(i => i.File).ToHashSet();
        foreach (var file in session.Messages.SelectMany(m => m.Images).Select(i => i.File).Distinct())
            if (!referenced.Contains(file)) DiscardImageFiles(DirectoryFor(id), file);
    }
    private List<string> ImportSessionImages(string id, ChatSession session, Dictionary<string, byte[]> contents, CancellationToken cancellation)
    {
        string directory = DirectoryFor(id);
        var mapped = new Dictionary<string, string>();
        try
        {
            foreach (var attachment in session.Messages.SelectMany(m => m.Images))
            {
                cancellation.ThrowIfCancellationRequested();
                if (!mapped.TryGetValue(attachment.File, out string? file))
                {
                    byte[] bytes = contents[attachment.File];
                    ChatImages.ValidateBytes(attachment, bytes);
                    file = ChatJson.Id() + Path.GetExtension(attachment.File);
                    mapped[attachment.File] = file;
                    using var image = new Image();
                    Error result = attachment.MimeType == "image/png" ? image.LoadPngFromBuffer(bytes) : image.LoadJpgFromBuffer(bytes);
                    if (result != Error.Ok) throw new IOException("对话包中的图片无法解码。");
                    LocalFiles.WriteBytes(ChatImages.PathFor(directory, file), bytes);
                    ShrinkImage(image, 240);
                    LocalFiles.WriteBytes(ChatImages.ThumbnailPath(directory, file), image.SaveJpgToBuffer(0.8f));
                }
                attachment.File = file;
            }
            return mapped.Values.ToList();
        }
        catch
        {
            foreach (string file in mapped.Values) Guard(() => DiscardImageFiles(directory, file));
            throw;
        }
    }
    private void CloseImageImports()
    {
        _imageLifetime.Cancel();
        foreach (var pair in _draftChatImages)
            Guard(() => DiscardImageFiles(pair.Value, Path.GetFileName(pair.Key)));
    }
}
