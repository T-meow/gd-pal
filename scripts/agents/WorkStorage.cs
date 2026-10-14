using System;
using System.IO;
using System.Text.Json.Nodes;

namespace GdPal.Agents;

internal static class WorkStorage
{
    public static string Within(string root, string relative)
    {
        string path = Path.GetFullPath(Path.Combine(root, relative));
        string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (Path.IsPathRooted(relative) || !path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("路径超出目录。");
        return path;
    }
    public static string ValidateRoot(string directory, string managed)
    {
        if (!Path.IsPathFullyQualified(directory) || !Directory.Exists(directory)) throw new ArgumentException("请选择存在的工作目录。");
        string root = Path.GetFullPath(directory).TrimEnd(Path.DirectorySeparatorChar);
        string data = Path.GetFullPath(managed).TrimEnd(Path.DirectorySeparatorChar);
        if (root == data || root.StartsWith(data + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || data.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("工作目录不能覆盖桌宠数据目录。");
        for (var entry = new DirectoryInfo(root); entry is not null; entry = entry.Parent)
            if (entry.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new ArgumentException("请选择真实目录，不使用目录链接。");
        return root;
    }
}
internal static class WorkJson
{
    public static string String(this JsonNode? node, string key, string fallback = "") => node?[key] is JsonValue value && value.TryGetValue<string>(out var text) ? text : fallback;
}
