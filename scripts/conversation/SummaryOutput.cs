using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace GdPal.Conversation;

/// <summary>Keep free-form output intact; recognizable headings or optional JSON become reviewable entries.</summary>
internal static class SummaryOutput
{
    private const string Categories = @"人设|角色设定|长期记忆|活跃记忆|短期记忆|近期记忆|临时记忆|记忆|回忆|世界设定|世界观|persona|active_memory|long_term_memory|memory|world";
    private static string? Target(string value)
    {
        if (Regex.IsMatch(value, @"人设|角色设定|\bpersona\b", RegexOptions.IgnoreCase)) return "persona";
        if (Regex.IsMatch(value, @"世界设定|世界观|\bworld\b", RegexOptions.IgnoreCase)) return "world";
        if (Regex.IsMatch(value, @"活跃记忆|短期记忆|近期记忆|临时记忆|\bactive_memory\b", RegexOptions.IgnoreCase)) return "active_memory";
        if (Regex.IsMatch(value, @"记忆|回忆|\b(?:long_term_memory|memory)\b", RegexOptions.IgnoreCase)) return "memory";
        return null;
    }
    private static string String(JsonElement item, string name) => item.ValueKind == JsonValueKind.Object && item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
    private static string Strip(string value) => value.Trim().Trim('*', '#', ' ', '\t');
    private static string EntryTitle(string value) => value.Split('\n').Select(Strip).FirstOrDefault(s => s.Length is > 0 and < 120) ?? "整理内容（待核对）";

    public static List<SummaryEntry> Parse(string response)
    {
        if (string.IsNullOrWhiteSpace(response)) return new();
        string text = response.Trim();
        string json = text;
        if (json.StartsWith("```", StringComparison.Ordinal))
        {
            int start = json.IndexOf('\n'), end = json.LastIndexOf("```", StringComparison.Ordinal);
            if (start >= 0 && end > start) json = json[(start + 1)..end].Trim();
        }
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            JsonElement array = default;
            if (root.ValueKind == JsonValueKind.Array) array = root;
            else if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("entries", out var entries)) array = entries;
            if (array.ValueKind == JsonValueKind.Array)
            {
                var parsed = new List<SummaryEntry>();
                bool complete = true;
                foreach (var item in array.EnumerateArray())
                {
                    string body = String(item, "text");
                    if (body.Length == 0) body = String(item, "content");
                    if (body.Length == 0) { complete = false; break; }
                    string title = String(item, "title");
                    string? target = Target(String(item, "target")) ?? Target(title);
                    parsed.Add(new SummaryEntry { Target = target ?? "active_memory", Title = title.Length > 0 ? title : EntryTitle(body), Text = body,
                        Reason = String(item, "reason") + (target is null ? "（未明确归属，暂列活跃记忆，请核对。）" : "") });
                }
                if (complete) return parsed;
            }
        }
        catch (JsonException) { } // Natural language is an ordinary result, not a parse failure.

        if (Regex.IsMatch(text, @"^(?:本次)?(?:没有|无|暂无)(?:需要追加的)?(?:新增)?(?:条目|内容)[。.!！]?$")) return new();
        var result = new List<SummaryEntry>();
        string section = "active_memory", targetId = "active_memory", titleText = "";
        bool explicitTarget = false, headingEntry = false;
        int listIndent = 0;
        var bodyText = new StringBuilder();
        void Flush()
        {
            bool noAddition = Regex.IsMatch(titleText.Trim(), @"^(?:本次)?(?:无|没有|暂无)(?:新增)?(?:条目|内容)?[。.!！]?$", RegexOptions.IgnoreCase);
            if (!noAddition && !string.IsNullOrWhiteSpace(bodyText.ToString()))
                result.Add(new SummaryEntry { Target = targetId, Title = titleText.Length > 0 ? titleText : EntryTitle(bodyText.ToString()), Text = bodyText.ToString().Trim(),
                    Reason = explicitTarget ? "从模型的自然语言整理结果提取。" : "未明确归属，暂列活跃记忆，请核对后再加入。" });
            bodyText.Clear(); titleText = ""; headingEntry = false;
        }
        foreach (string line in text.Replace("\r\n", "\n").Split('\n'))
        {
            var heading = Regex.Match(line, @"^\s{0,3}(#{1,6})\s+(.+)$");
            if (heading.Success)
            {
                string caption = Strip(heading.Groups[2].Value);
                string? inferred = Target(caption);
                // Keep introductory prose in RawText, without presenting it as a new memory.
                if (inferred is not null && result.Count == 0 && titleText.Length == 0 && !explicitTarget) bodyText.Clear();
                Flush();
                if (inferred is not null && Regex.IsMatch(caption, @"^(?:[一二三四五六七八九十\d]+[、.．)）]\s*)?(?:" + Categories + @")(?:\s*[（(].*[)）])?[:：]?$", RegexOptions.IgnoreCase))
                { section = inferred; targetId = section; explicitTarget = true; continue; }
                if (heading.Groups[1].Length == 1 && inferred is null) continue;
                targetId = inferred ?? section;
                explicitTarget = inferred is not null || section != "active_memory" || explicitTarget;
                titleText = Regex.Replace(caption, @"^[\[【](?:" + Categories + @")[\]】]\s*", "", RegexOptions.IgnoreCase);
                headingEntry = true;
                continue;
            }
            var bullet = Regex.Match(line, @"^(\s*)(?:[-*+] |\d+[.、)]\s+)(.+)$");
            if (bullet.Success && !headingEntry && (bodyText.Length == 0 || bullet.Groups[1].Length <= listIndent))
            {
                Flush(); listIndent = bullet.Groups[1].Length;
                string content = Strip(bullet.Groups[2].Value);
                var split = Regex.Match(content, @"^(?:\*\*)?(.+?)(?:\*\*)?[:：]\s*(.+)$");
                targetId = Target(content) ?? section;
                if (split.Success) { titleText = Strip(split.Groups[1].Value); bodyText.AppendLine(split.Groups[2].Value); }
                else { titleText = EntryTitle(content); bodyText.AppendLine(content); }
                continue;
            }
            bodyText.AppendLine(line);
        }
        Flush();
        if (result.Count == 0) result.Add(new SummaryEntry { Title = "整理内容（待核对）", Text = response, Reason = "按自然语言保留，请核对归属与正文。" });
        return result;
    }
}
