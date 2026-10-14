using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace GdPal.Conversation;

internal static class OutfitCommands
{
    private const string Prefix = "[outfit:";
    private static readonly Regex Command = new(@"\[outfit:([^\]\r\n]*)\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public static string Prompt(string current, IReadOnlyCollection<string> available, bool allowed, bool locked)
    {
        if (available.Count == 0) return "";
        string state = $"\n\n【当前衣装】{current}。衣装列表：{string.Join(", ", available)}（maid=女仆装，nightdress=睡衣）。";
        if (!allowed || locked) return state + "用户已锁定衣装或关闭 AI 换装。保持当前衣装，不输出换装指令，也不要声称已换装。";
        return state + "允许你根据场景选择衣装。需要换装时，在回复末尾另起一行输出 [outfit:衣装ID]，例如 [outfit:nightdress]。只能使用列表中的 ID；不换装则不输出。这个标记由应用执行并隐藏，不能替代对白，也不要向用户讲解标记。用户随时可以锁定并覆盖你的选择。";
    }

    public static string Requested(string text, IEnumerable<string> available)
    {
        var allowed = new HashSet<string>(available, StringComparer.Ordinal);
        string requested = "";
        foreach (Match match in Command.Matches(text))
        {
            string id = match.Groups[1].Value.Trim();
            if (allowed.Contains(id)) requested = id;
        }
        return requested;
    }

    public static string DisplayText(string text)
    {
        string clean = Command.Replace(text, "");
        // A command can arrive across several streamed chunks. Keep its unfinished
        // suffix out of dialogue, speech and history until the closing bracket arrives.
        int start = clean.LastIndexOf('[');
        if (start >= 0)
        {
            string suffix = clean[start..];
            if (Prefix.StartsWith(suffix, StringComparison.OrdinalIgnoreCase) || suffix.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase))
                clean = clean[..start];
        }
        return clean.TrimEnd();
    }
}
