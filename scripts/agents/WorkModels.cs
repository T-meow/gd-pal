// Adapted from Yumo (MIT); see licenses/yumo/PORTING.md.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json.Nodes;
using GdPal.Conversation;

namespace GdPal.Agents;

public sealed class WorkWorkspace
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Directory { get; set; } = "";
    public long Revision { get; set; }
}
public sealed class WorkAgent
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Executable { get; set; } = "";
    public string[] Arguments { get; set; } = [];
    public Dictionary<string, string> Environment { get; set; } = new();
    public string[] SecretEnvironmentNames { get; set; } = [];
    public long Revision { get; set; }
}
public sealed class WorkGrant
{
    public string ProfileId { get; set; } = "";
    public string WorkspaceId { get; set; } = "";
    public long WorkspaceRevision { get; set; }
    public string ExecutorId { get; set; } = "";
    public long AgentRevision { get; set; }
}
public sealed class WorkConfiguration
{
    public int SchemaVersion { get; set; } = 1;
    public List<WorkWorkspace> Workspaces { get; set; } = [];
    public List<WorkAgent> Agents { get; set; } = [];
    public List<WorkGrant> Grants { get; set; } = [];
}
public sealed class WorkTask
{
    public int SchemaVersion { get; set; } = 1;
    public string Id { get; set; } = ChatJson.Id();
    public string ProfileId { get; set; } = "";
    public string ChatSessionId { get; set; } = "";
    public string WorkspaceId { get; set; } = "";
    public long WorkspaceRevision { get; set; }
    public string ExecutorId { get; set; } = "";
    public long AgentRevision { get; set; }
    public string Title { get; set; } = "工作任务";
    public string Status { get; set; } = "queued";
    public long Revision { get; set; } = 1;
    public int Attempt { get; set; } = 1;
    public string CreatedAt { get; set; } = ChatJson.Now();
    public string UpdatedAt { get; set; } = ChatJson.Now();
    public string Result { get; set; } = "";
    public string Error { get; set; } = "";
    public string AgentSessionId { get; set; } = "";
    public List<WorkMessage> Messages { get; set; } = [];
    public WorkPermission? Permission { get; set; }
    public bool Unfinished => Status is "queued" or "running" or "awaiting_permission";
}
public sealed record WorkMessage(string Role, string Text, string At);
public sealed record WorkPermissionOption(string Id, string Name, string Kind);
public sealed record WorkPermission(string Id, string Description, WorkPermissionOption[] Options);
public sealed record WorkResult(string Text, string Status = "completed", string Reason = "", string Origin = "agent");
public sealed record WorkEvent(string TaskId, string ProfileId, string Kind, JsonNode? Data);
public sealed record AgentProbe(string Name, string Version, bool CanResume);
public sealed class WorkOptions
{
    public TimeSpan TaskTimeout { get; set; } = TimeSpan.FromMinutes(30);
    public TimeSpan HandshakeTimeout { get; set; } = TimeSpan.FromSeconds(30);
    public TimeSpan CancelGrace { get; set; } = TimeSpan.FromSeconds(5);
}
public interface IWorkExecutor
{
    Task<WorkResult> ExecuteAsync(WorkExecutionContext context, CancellationToken cancellation);
}
public interface IAgentConnector : IWorkExecutor, IAsyncDisposable
{
    Task<AgentProbe> ProbeAsync(WorkAgent agent, string directory, CancellationToken cancellation);
}
public sealed class WorkExecutionContext
{
    public required WorkTask Task { get; init; }
    public required WorkWorkspace Workspace { get; init; }
    public WorkAgent? Agent { get; init; }
    public required Func<string, JsonNode?, Task> Report { get; init; }
    public required Func<WorkPermission, CancellationToken, Task<string?>> RequestPermission { get; init; }
    public required Action CheckAuthorization { get; init; }
}
