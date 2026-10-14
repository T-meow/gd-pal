using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace GdPal.Conversation;

internal sealed record ImageHeader(string MimeType, int Width, int Height, int Orientation = 1);

internal static class ChatImages
{
    public const int MaxPerMessage = 4;
    public const int MaxSourceBytes = 20 * 1024 * 1024;
    public const int MaxPixels = 32_000_000;
    public const int MaxEdge = 1600;
    public const int MaxBytes = 2 * 1024 * 1024;

    public static string PathFor(string directory, string file)
    {
        if (!Regex.IsMatch(file, "^[a-f0-9]{32}\\.(jpg|png)$")) throw new InvalidDataException("图片文件标识无效。");
        return LocalFiles.Within(Path.Combine(directory, "images"), file);
    }
    public static string ThumbnailPath(string directory, string file) => PathFor(directory, file) + ".thumb.jpg";
    public static void Validate(ChatImage image)
    {
        _ = PathFor(".", image.File);
        if (image.MimeType != (image.File.EndsWith(".png") ? "image/png" : "image/jpeg") ||
            image.Width is < 1 or > MaxEdge || image.Height is < 1 or > MaxEdge || image.Bytes is < 1 or > MaxBytes)
            throw new InvalidDataException("图片附件信息无效或超过大小限制。");
    }
    public static void ValidateBytes(ChatImage image, byte[] bytes)
    {
        Validate(image);
        var header = Inspect(bytes);
        if (bytes.Length != image.Bytes || header.MimeType != image.MimeType || header.Width != image.Width || header.Height != image.Height)
            throw new InvalidDataException("图片文件与附件信息不一致。");
    }
    public static byte[] Read(string directory, ChatImage image)
    {
        Validate(image);
        string path = PathFor(directory, image.File);
        if (!System.IO.File.Exists(path)) throw new IOException("找不到聊天图片，请重新附图或重新导入包含图片的对话包。");
        if (new FileInfo(path).Length != image.Bytes) throw new IOException("聊天图片大小发生变化，请重新附图。");
        byte[] bytes = System.IO.File.ReadAllBytes(path);
        ValidateBytes(image, bytes);
        return bytes;
    }

    public static List<ChatPromptMessage> ModelHistory(List<ChatMessage> history, bool continuation, string directory)
    {
        // Include complete image groups, newest first. Four normalized images stay below inline request limits.
        var selected = new HashSet<ChatMessage>();
        int remaining = MaxPerMessage;
        foreach (var message in history.AsEnumerable().Reverse())
        {
            if (message.Images.Count == 0) continue;
            if (message.Images.Count > remaining) break;
            selected.Add(message); remaining -= message.Images.Count;
        }
        return ChatTurns.ModelHistory(history, continuation, message =>
        {
            if (message.Images.Count == 0) return new(message.Role, message.Content);
            if (!selected.Contains(message)) return new(message.Role, message.Content + "\n[此条消息的图片未随本次请求附带；需要重新查看时，请用户再次附图。]");
            var images = message.Images.Select(image => new ChatPromptImage(image.MimeType, Convert.ToBase64String(Read(directory, image)))).ToList();
            return new(message.Role, message.Content, images);
        });
    }

    // Inspect dimensions before decoding to bound memory use on phones. File extensions and picker MIME types are only hints.
    public static ImageHeader Inspect(byte[] bytes)
    {
        var data = bytes.AsSpan();
        if (data.Length >= 24 && data[..8].SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }) && data.Slice(12, 4).SequenceEqual("IHDR"u8))
            return Checked("image/png", BinaryPrimitives.ReadInt32BigEndian(data[16..]), BinaryPrimitives.ReadInt32BigEndian(data[20..]));
        if (data.Length >= 12 && data[..4].SequenceEqual("RIFF"u8) && data.Slice(8, 4).SequenceEqual("WEBP"u8))
        {
            for (int p = 12; p + 8 <= data.Length;)
            {
                uint size = BinaryPrimitives.ReadUInt32LittleEndian(data[(p + 4)..]);
                if (size > data.Length - p - 8) break;
                var chunk = data.Slice(p + 8, (int)size);
                if (data.Slice(p, 4).SequenceEqual("VP8X"u8) && chunk.Length >= 10)
                    return Checked("image/webp", 1 + U24(chunk[4..]), 1 + U24(chunk[7..]));
                if (data.Slice(p, 4).SequenceEqual("VP8L"u8) && chunk.Length >= 5 && chunk[0] == 0x2f)
                {
                    uint bits = BinaryPrimitives.ReadUInt32LittleEndian(chunk[1..]);
                    return Checked("image/webp", 1 + (int)(bits & 0x3fff), 1 + (int)((bits >> 14) & 0x3fff));
                }
                if (data.Slice(p, 4).SequenceEqual("VP8 "u8) && chunk.Length >= 10 && chunk.Slice(3, 3).SequenceEqual(new byte[] { 0x9d, 1, 0x2a }))
                    return Checked("image/webp", BinaryPrimitives.ReadUInt16LittleEndian(chunk[6..]) & 0x3fff, BinaryPrimitives.ReadUInt16LittleEndian(chunk[8..]) & 0x3fff);
                p += 8 + (int)size + ((int)size & 1);
            }
        }
        if (data.Length >= 4 && data[0] == 0xff && data[1] == 0xd8)
        {
            int width = 0, height = 0, orientation = 1;
            for (int p = 2; p + 4 <= data.Length;)
            {
                if (data[p++] != 0xff) break;
                while (p < data.Length && data[p] == 0xff) p++;
                if (p >= data.Length) break;
                byte marker = data[p++];
                if (marker is 0xda or 0xd9) break;
                if (marker is 0x01 or >= 0xd0 and <= 0xd7) continue;
                if (p + 2 > data.Length) break;
                int size = BinaryPrimitives.ReadUInt16BigEndian(data[p..]);
                if (size < 2 || size > data.Length - p) break;
                var chunk = data.Slice(p + 2, size - 2);
                if (marker == 0xe1 && chunk.Length >= 14 && chunk[..6].SequenceEqual("Exif\0\0"u8)) orientation = ExifOrientation(chunk[6..]);
                if (marker is >= 0xc0 and <= 0xcf && marker is not (0xc4 or 0xc8 or 0xcc) && chunk.Length >= 5)
                {
                    height = BinaryPrimitives.ReadUInt16BigEndian(chunk[1..]);
                    width = BinaryPrimitives.ReadUInt16BigEndian(chunk[3..]);
                }
                p += size;
            }
            if (width > 0 && height > 0) return Checked("image/jpeg", width, height, orientation);
        }
        throw new InvalidDataException("请选择有效的 PNG、JPEG 或 WebP 图片。");
    }
    private static int U24(ReadOnlySpan<byte> data) => data[0] | data[1] << 8 | data[2] << 16;
    private static ImageHeader Checked(string mime, int width, int height, int orientation = 1)
    {
        if (width < 1 || height < 1 || (long)width * height > MaxPixels || width > 32768 || height > 32768)
            throw new InvalidDataException("图片分辨率过大，请选择不超过 3200 万像素的图片。");
        return new(mime, width, height, orientation);
    }
    private static int ExifOrientation(ReadOnlySpan<byte> tiff)
    {
        bool little = tiff[..2].SequenceEqual("II"u8);
        if (!little && !tiff[..2].SequenceEqual("MM"u8)) return 1;
        uint offset = U32(tiff[4..], little);
        if (offset > tiff.Length - 2) return 1;
        int count = U16(tiff[(int)offset..], little), start = (int)offset + 2;
        for (int i = 0; i < count && start + 12 <= tiff.Length; i++, start += 12)
        {
            var entry = tiff[start..];
            if (U16(entry, little) != 0x112 || U16(entry[2..], little) != 3 || U32(entry[4..], little) != 1) continue;
            int value = U16(entry[8..], little);
            return value is >= 1 and <= 8 ? value : 1;
        }
        return 1;
    }
    private static ushort U16(ReadOnlySpan<byte> data, bool little) => little ? BinaryPrimitives.ReadUInt16LittleEndian(data) : BinaryPrimitives.ReadUInt16BigEndian(data);
    private static uint U32(ReadOnlySpan<byte> data, bool little) => little ? BinaryPrimitives.ReadUInt32LittleEndian(data) : BinaryPrimitives.ReadUInt32BigEndian(data);
}
