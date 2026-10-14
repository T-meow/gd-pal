using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using GdPal.Agents;

namespace GdPal.Conversation;

public partial class ChatService
{
    [Signal] public delegate void WorkChangedEventHandler(string profileId);
    [Signal] public delegate void WorkCommandFinishedEventHandler(string profileId, string requestId, string json);
    private WorkCoordinator? _work;
    private readonly CancellationTokenSource _workLifetime = new();
    private static string AgentSecret(string id, string name) => "GD-Pal-Agent/" + id + "/" + name;
    public bool HasBackgroundWork() => _summaryJobs.Count > 0 || _packageJobs.Count > 0 || (_work?.HasActiveTasks ?? false);
    private WorkCoordinator Work()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Agent 任务仅在 Windows 提供。");
        if (_work is not null) return _work;
        var connector = new AcpAgentConnector(agent => agent.SecretEnvironmentNames.ToDictionary(name => name, name => _credentials.Read(AgentSecret(agent.Id, name))));
        _work = new WorkCoordinator(_root, connector, change => _pending.Enqueue(() => EmitSignal(SignalName.WorkChanged, change.ProfileId)));
        return _work;
    }
    public string GetWorkSnapshot(string id)
    {
        try { return ChatJson.Encode(new { configuration = Work().Configuration(id), tasks = Work().List(id) }); }
        catch (Exception ex) { return ChatJson.Encode(new { error = ex.Message }); }
    }
    public string GetWorkDetails(string id, string taskId)
    {
        try { return ChatJson.Encode(new { task = Work().Get(id, taskId), log = Work().ReadLog(id, taskId) }); }
        catch (Exception ex) { return ChatJson.Encode(new { error = ex.Message }); }
    }
    public void WorkCommand(string id, string requestId, string command, string json)
    {
        WorkCoordinator work;
        try
        {
            if (!_companions.ContainsKey(id)) throw new ArgumentException("伙伴不存在。");
            work = Work();
        }
        catch (Exception ex) { _pending.Enqueue(() => EmitSignal(SignalName.WorkCommandFinished, id, requestId, ChatJson.Encode(new { error = ex.Message }))); return; }
        string session = GetActiveSessionId(id);
        _ = Task.Run(async () =>
        {
            string result;
            try
            {
                var input = JsonNode.Parse(json)?.AsObject() ?? throw new ArgumentException("操作参数无效。");
                string taskId = input.String("task_id"), workspaceId = input.String("workspace_id"), agentId = input.String("agent_id");
                object output;
                switch (command)
                {
                    case "workspace.save": output = new { workspace = work.SaveWorkspace(input.Deserialize<WorkWorkspace>(ChatJson.Options)!) }; break;
                    case "agent.save":
                    {
                        var agent = input.Deserialize<WorkAgent>(ChatJson.Options)!;
                        var changes = input["secrets"]?.Deserialize<Dictionary<string, string>>() ?? new();
                        if (agent.Id.Length > 0)
                            agent.SecretEnvironmentNames = work.Configuration(id).Agents.Single(a => a.Id == agent.Id).SecretEnvironmentNames;
                        var names = agent.SecretEnvironmentNames.ToHashSet();
                        foreach (var change in changes) { if (change.Value.Length == 0) names.Remove(change.Key); else names.Add(change.Key); }
                        agent.SecretEnvironmentNames = names.ToArray();
                        agent = work.SaveAgent(agent);
                        foreach (var change in changes)
                        { if (change.Value.Length == 0) _credentials.Delete(AgentSecret(agent.Id, change.Key)); else _credentials.Write(AgentSecret(agent.Id, change.Key), change.Value); }
                        output = new { agent }; break;
                    }
                    case "grant":
                        work.Grant(id, workspaceId, agentId, input["allow"]?.GetValue<bool>() == true,
                            input["workspace_revision"]!.GetValue<long>(), input["agent_revision"]!.GetValue<long>()); output = new { notice = "授权已更新。" }; break;
                    case "probe": output = new { probe = await work.ProbeAsync(id, workspaceId, agentId, _workLifetime.Token).ConfigureAwait(false) }; break;
                    case "create":
                        var task = work.Create(id, session, workspaceId, agentId, input.String("prompt")); work.Enqueue(task.Id); output = new { task_id = task.Id }; break;
                    case "continue": work.Continue(id, taskId, input["revision"]!.GetValue<long>(), input.String("prompt")); output = new { task_id = taskId }; break;
                    case "cancel": work.Cancel(id, taskId); output = new { notice = "已请求取消。" }; break;
                    case "permission": work.DecidePermission(id, taskId, input.String("permission_id"), input.String("option_id")); output = new { notice = "权限选择已提交。" }; break;
                    default: throw new ArgumentException("未知 Agent 操作。");
                }
                result = ChatJson.Encode(output);
            }
            catch (Exception ex) { result = ChatJson.Encode(new { error = ex.Message }); }
            _pending.Enqueue(() =>
            {
                EmitSignal(SignalName.WorkCommandFinished, id, requestId, result);
                EmitSignal(SignalName.WorkChanged, id);
            });
        });
    }
}
