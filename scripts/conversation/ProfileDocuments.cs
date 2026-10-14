using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace GdPal.Conversation;

internal sealed class ProfileMetadata
{
    public int SchemaVersion { get; set; } = 1;
    public string DisplayName { get; set; } = "伙伴";
    public bool AdultMode { get; set; }
    public bool AutoSpeak { get; set; }
    public string ActiveSessionId { get; set; } = "";
}

internal static class ProfileDocuments
{
    private static readonly Dictionary<string, string> Filenames = new()
    {
        ["persona"] = "persona.md", ["memory"] = "memory_long_term.md",
        ["active_memory"] = "memory_active.md", ["world"] = "world.md"
    };
    private static string RestorePath(string directory) => Path.Combine(directory, "persona_before_summary.md");
    public static Dictionary<string, string> Paths(string directory) => Filenames.ToDictionary(entry => entry.Key, entry => Path.Combine(directory, entry.Value));
    private static ProfileMetadata Metadata(ManualProfile profile) => new()
    {
        DisplayName = profile.DisplayName, AdultMode = profile.AdultMode,
        AutoSpeak = profile.AutoSpeak, ActiveSessionId = profile.ActiveSessionId
    };
    private static Dictionary<string, string?> Contents(ManualProfile profile) => new()
    {
        ["persona.md"] = profile.Persona, ["memory_long_term.md"] = profile.Memory,
        ["memory_active.md"] = profile.ActiveMemory, ["world.md"] = profile.World,
        ["persona_before_summary.md"] = profile.PersonaBeforeSummary
    };
    public static ManualProfile Load(string directory)
    {
        var metadata = LocalFiles.Read<ProfileMetadata>(Path.Combine(directory, "profile.json"));
        if (metadata.SchemaVersion != 1) throw new InvalidDataException("不支持的角色资料版本。");
        var profile = new ManualProfile
        {
            DisplayName = metadata.DisplayName, AdultMode = metadata.AdultMode,
            AutoSpeak = metadata.AutoSpeak, ActiveSessionId = metadata.ActiveSessionId
        };
        Reload(directory, profile);
        return profile;
    }
    public static void Create(string directory, ManualProfile profile)
    {
        foreach (var (filename, text) in Contents(profile))
            if (text is not null && !File.Exists(Path.Combine(directory, filename))) LocalFiles.Write(Path.Combine(directory, filename), text);
        Reload(directory, profile);
        SaveMetadata(directory, profile);
    }
    public static void Reload(string directory, ManualProfile profile)
    {
        // Read everything first; a missing or inaccessible file must not partially replace the in-memory context.
        var values = Paths(directory).ToDictionary(entry => entry.Key, entry => File.ReadAllText(entry.Value));
        string? restore = File.Exists(RestorePath(directory)) ? File.ReadAllText(RestorePath(directory)) : null;
        profile.Persona = values["persona"]; profile.Memory = values["memory"];
        profile.ActiveMemory = values["active_memory"]; profile.World = values["world"];
        profile.PersonaBeforeSummary = restore;
    }
    public static void SaveMetadata(string directory, ManualProfile profile) => LocalFiles.Write(Path.Combine(directory, "profile.json"), ChatJson.Encode(Metadata(profile)));

    public static void SaveChanges(string directory, ManualProfile before, ManualProfile after)
    {
        var previous = Contents(before);
        var changed = Contents(after).Where(entry => entry.Value != previous[entry.Key]).ToArray();
        foreach (var (filename, _) in changed)
        {
            string file = Path.Combine(directory, filename);
            string? current = File.Exists(file) ? File.ReadAllText(file) : null;
            if (current != previous[filename]) throw new IOException(filename + " 已在其他位置修改，请重新载入后保存。");
        }
        var writes = changed.ToDictionary(entry => Path.Combine(directory, entry.Key), entry => entry.Value);
        writes[Path.Combine(directory, "profile.json")] = ChatJson.Encode(Metadata(after));
        var originals = writes.Keys.ToDictionary(file => file, file => File.Exists(file) ? File.ReadAllText(file) : null);
        var committed = new List<string>();
        try
        {
            foreach (var (file, text) in writes)
            {
                if (text is null) LocalFiles.DeleteOrStage(file, directory);
                else LocalFiles.Write(file, text);
                committed.Add(file);
            }
        }
        catch
        {
            foreach (string file in committed.AsEnumerable().Reverse())
            {
                if (originals[file] is { } original) LocalFiles.Write(file, original);
                else LocalFiles.DeleteOrStage(file, directory);
            }
            throw;
        }
    }
}
