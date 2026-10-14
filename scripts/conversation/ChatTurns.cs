using System;
using System.Collections.Generic;

namespace GdPal.Conversation;

internal sealed record ChatTurn(string TurnId, bool IsContinuation);
internal sealed record ChatPromptImage(string MimeType, string Data);
internal sealed record ChatPromptMessage(string Role, string Content, List<ChatPromptImage>? Images = null);

internal static class ChatTurns
{
    public const string DialogueConvention = "【对白与动作约定】\n无论用户还是角色，中文圆括号（…）和英文圆括号 (…) 中的内容都属于动作、神态、心理或场景旁白，不是说出口的对白。不要当作任何人的台词，也不要把这些内容复述成对方说过的话。括号外的文字才是对白；你的对白写在括号外，动作和旁白写在括号内。";
    public const string ContinuationPrompt = "（继续指令：请延续当前场景和上一条角色回复，继续你的对白或动作；若尚未开始对话，就按人设自然开场。这是操作指令，不是用户台词，也不代表用户新增了动作或决定。不要代替用户发言，不要重复上一条回复。）";

    public static ChatTurn Begin(List<ChatMessage> messages, string text, bool retry, bool continuation, List<ChatImage>? images = null)
    {
        if (retry)
        {
            int lastUser = messages.FindLastIndex(m => m.Role == "user");
            int lastReply = messages.FindLastIndex(m => m.Role == "assistant");
            if (lastReply > lastUser)
            {
                var previous = messages[lastReply];
                messages.RemoveRange(lastReply, messages.Count - lastReply);
                return new(previous.TurnId, previous.IsContinuation);
            }
            if (lastUser < 0) throw new ArgumentException("还没有可以重试的消息。");
            string turn = messages[lastUser].TurnId;
            messages.RemoveRange(lastUser + 1, messages.Count - lastUser - 1);
            return new(turn, false);
        }
        if (continuation) return new(ChatJson.Id(), true);
        var user = new ChatMessage { Content = text, Segments = ParseSegments(text), Images = images ?? new() };
        messages.Add(user);
        return new(user.TurnId, false);
    }

    public static List<ChatPromptMessage> ModelHistory(IEnumerable<ChatMessage> history, bool continuation, Func<ChatMessage, ChatPromptMessage>? compose = null)
    {
        var result = new List<ChatPromptMessage>();
        foreach (var message in history)
        {
            // Replay the control operation for providers requiring a user turn before an assistant turn.
            // These instructions are request-only; they are never stored as user dialogue.
            if (message.Role == "assistant" && (message.IsContinuation || result.Count == 0))
                result.Add(new("user", ContinuationPrompt));
            result.Add(compose is null ? new(message.Role, message.Content) : compose(message));
        }
        if (continuation) result.Add(new("user", ContinuationPrompt));
        return result;
    }

    public static List<DialogueSegment> ParseSegments(string text)
    {
        var segments = new List<DialogueSegment>();
        void Add(int from, int to, bool aside)
        {
            if (to <= from) return;
            string part = text[from..to];
            segments.Add(aside ? new() { Aside = part, DisplayText = part } : new() { Say = part, DisplayText = part });
        }
        int start = 0, depth = 0;
        for (int index = 0; index < text.Length; index++)
        {
            if (text[index] is '（' or '(')
            {
                if (depth == 0) { Add(start, index, false); start = index; }
                depth++;
            }
            else if ((text[index] is '）' or ')') && depth > 0)
            {
                depth--;
                if (depth == 0) { Add(start, index + 1, true); start = index + 1; }
            }
        }
        Add(start, text.Length, depth > 0);
        return segments;
    }
}
