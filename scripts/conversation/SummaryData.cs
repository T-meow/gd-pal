using System.Collections.Generic;

namespace GdPal.Conversation;

internal sealed class SummarySource
{
    public string SessionId { get; set; } = "";
    public string MessageId { get; set; } = "";
}
internal sealed class SummaryEntry
{
    public string Id { get; set; } = ChatJson.Id();
    public string Target { get; set; } = "active_memory";
    public string Title { get; set; } = "";
    public string Text { get; set; } = "";
    public string Reason { get; set; } = "";
    public string Status { get; set; } = "pending";
    public bool Selected { get; set; }
}
internal sealed class SummaryDraft
{
    public int SchemaVersion { get; set; } = 1;
    public string Instructions { get; set; } = "";
    public bool ConsolidateExisting { get; set; }
    public bool ConsolidatePreference { get; set; }
    public string Phase { get; set; } = "extract";
    public string MergeStatus { get; set; } = "none";
    public Dictionary<string, string> MergedDocuments { get; set; } = new();
    public string MergeNotes { get; set; } = "";
    public List<string> MergeConflicts { get; set; } = new();
    public string MemoryBackupPath { get; set; } = "";
    public Dictionary<string, string> Originals { get; set; } = new();
    public string SourceText { get; set; } = "";
    public List<SummaryEntry> Entries { get; set; } = new();
    public string RawText { get; set; } = "";
    public string ResponseNotice { get; set; } = "";
    public string Status { get; set; } = "empty";
    public string Error { get; set; } = "";
    public string ResponsePath { get; set; } = "";
    public int CompletedBatches { get; set; }
    public int TotalBatches { get; set; }
    public List<SummarySource> Sources { get; set; } = new();
    public bool HasPendingReview() => Entries.Exists(entry => entry.Status == "pending") || MergeStatus == "ready";
    public bool ReviewComplete() => Entries.TrueForAll(entry => entry.Status != "pending") && (!ConsolidateExisting || MergeStatus == "applied");
}
