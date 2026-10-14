class_name PalAgentPanel
extends VBoxContainer

var service: Node
var _profile_id := ""
var _configuration: Dictionary = {}
var _task: Dictionary = {}
var _requests: Dictionary = {}
var _workspace: OptionButton
var _agent: OptionButton
var _tasks: OptionButton
var _prompt: TextEdit
var _result: TextEdit
var _activity: TextEdit
var _notice: Label
var _grant_status: Label
var _permissions: HFlowContainer
var _permission_text: TextEdit
var _permission_signature := ""
var _timer: Timer
var _agent_edit: OptionButton
var _agent_name: LineEdit
var _executable: LineEdit
var _arguments: TextEdit
var _environment: TextEdit
var _secret_name: LineEdit
var _secret_value: LineEdit
var _secret_status: Label
var _workspace_edit: OptionButton
var _workspace_name: LineEdit
var _directory: LineEdit
var _selected_task := ""
var _drafts: Dictionary = {}
var _agent_baseline := ""
var _workspace_baseline := ""


func _ready() -> void:
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 1120)
	set_meta("preferred_height", 810)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	var tasks := _tab(tabs, "Agent 任务")
	PalUi.hint("选择已配置的 Agent 和目录后发送任务。任务与普通聊天独立，可同时进行。", tasks)
	var selection := HBoxContainer.new()
	tasks.add_child(selection)
	_workspace = _choice(selection)
	_agent = _choice(selection)
	for choice: OptionButton in [_workspace, _agent]:
		choice.item_selected.connect(func(_index: int) -> void: _refresh_grant())
	_grant_status = PalUi.hint("", tasks)
	var authorization := HFlowContainer.new()
	tasks.add_child(authorization)
	PalUi.button("授权所选 Agent 与目录", authorization, func() -> void: _grant(true))
	PalUi.button("撤销授权", authorization, func() -> void: _grant(false))
	PalUi.button("测试 Agent 连接", authorization, func() -> void: _command("probe", _selection()))
	_tasks = _choice(tasks)
	_tasks.item_selected.connect(func(_index: int) -> void: _selected_task = _id(_tasks); _details())
	var output := TabContainer.new()
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tasks.add_child(output)
	_result = _editor(output, 150)
	_result.name = "任务对话"
	_result.editable = false
	_activity = _editor(output, 150)
	_activity.name = "工具活动"
	_activity.editable = false
	_permission_text = _editor(tasks, 70)
	_permission_text.editable = false
	_permission_text.hide()
	_permissions = HFlowContainer.new()
	tasks.add_child(_permissions)
	_prompt = _editor(tasks, 70)
	_prompt.placeholder_text = "描述新任务，或输入要继续处理的内容…"
	var actions := HFlowContainer.new()
	tasks.add_child(actions)
	PalUi.button("新任务", actions, _create, true)
	PalUi.button("继续所选任务", actions, _continue_task)
	PalUi.button("取消所选任务", actions, func() -> void: _command("cancel", {"task_id": _selected_task}))
	var agents := _tab(tabs, "Agent 配置")
	PalUi.hint("配置本机已安装的 ACP Agent。选择实际程序；脚本入口请选解释器，再逐行填写固定参数。", agents)
	_agent_edit = _choice(agents)
	_agent_edit.item_selected.connect(_edit_agent)
	_agent_name = PalUi.field("名称", agents)
	_executable = PalUi.field("程序绝对路径", agents)
	PalUi.button("选择程序", agents, func() -> void: _browse(_executable, false))
	PalUi.label("启动参数（每行一个）", agents, 14)
	_arguments = _editor(agents, 65)
	_arguments.placeholder_text = "例如 DeepSeek Harness：\n--profile\nacp"
	PalUi.label("普通环境变量（每行 NAME=VALUE）", agents, 14)
	_environment = _editor(agents, 65)
	_secret_name = PalUi.field("私密环境变量名称（可选）", agents, "例如 API_KEY")
	_secret_value = PalUi.field("私密值", agents, "不填名称保持现有；填写名称且值留空可删除该项")
	_secret_value.secret = true
	_secret_status = PalUi.hint("", agents)
	PalUi.button("保存 Agent", agents, _save_agent, true)
	var workspaces := _tab(tabs, "工作目录")
	_workspace_edit = _choice(workspaces)
	_workspace_edit.item_selected.connect(_edit_workspace)
	_workspace_name = PalUi.field("名称", workspaces)
	_directory = PalUi.field("目录绝对路径", workspaces)
	PalUi.button("选择目录", workspaces, func() -> void: _browse(_directory, true))
	PalUi.hint("目录是 Agent 的工作位置。文件、终端和网络能力由 Agent 自身管理；它的额外权限请求会显示在任务页。修改配置后需要重新授权。", workspaces)
	PalUi.button("保存工作目录", workspaces, _save_workspace, true)
	_notice = PalUi.hint("", self)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.3
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	service.connect("WorkChanged", func(id: String) -> void:
		if id == _profile_id and is_visible_in_tree() and _timer.is_stopped():
			_timer.start())
	service.connect("WorkCommandFinished", _on_result)


func _tab(tabs: TabContainer, caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _choice(parent: Node) -> OptionButton:
	var choice := OptionButton.new()
	choice.fit_to_longest_item = false
	choice.custom_minimum_size.x = 160
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(choice)
	return choice


func _editor(parent: Node, height: int) -> TextEdit:
	var editor := TextEdit.new()
	editor.custom_minimum_size.y = height
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(editor)
	return editor


func _id(choice: OptionButton) -> String:
	return str(choice.get_selected_metadata()) if choice.item_count > 0 and choice.selected >= 0 else ""


func _populate(choice: OptionButton, records: Array, selected: String, create: bool = false) -> void:
	choice.clear()
	if create:
		choice.add_item("新增配置")
		choice.set_item_metadata(0, "")
	for record: Dictionary in records:
		choice.add_item(str(record.get("name", record.get("title", ""))))
		choice.set_item_metadata(choice.item_count - 1, str(record.id))
		if str(record.id) == selected:
			choice.select(choice.item_count - 1)


func open_profile(profile_id: String) -> void:
	if not _profile_id.is_empty():
		_drafts[_profile_id] = _prompt.text
	_profile_id = profile_id
	_prompt.text = str(_drafts.get(profile_id, ""))
	_selected_task = ""
	_notice.text = ""
	_refresh()
	_edit_agent(_agent_edit.selected)
	_edit_workspace(_workspace_edit.selected)


func _refresh() -> void:
	if _profile_id.is_empty():
		return
	var snapshot: Dictionary = JSON.parse_string(service.call("GetWorkSnapshot", _profile_id))
	if snapshot.has("error"):
		_notice.text = str(snapshot.error)
		return
	_configuration = snapshot.configuration
	_populate(_workspace, _configuration.workspaces, _id(_workspace))
	_populate(_agent, _configuration.agents, _id(_agent))
	_populate(_workspace_edit, _configuration.workspaces, _id(_workspace_edit), true)
	_populate(_agent_edit, _configuration.agents, _id(_agent_edit), true)
	_populate(_tasks, snapshot.tasks, _selected_task)
	_selected_task = _id(_tasks)
	_refresh_grant()
	_details()


func _find(records: Array, id: String) -> Dictionary:
	for record: Dictionary in records:
		if str(record.id) == id:
			return record
	return {}


func _selection() -> Dictionary:
	var workspace := _find(_configuration.get("workspaces", []), _id(_workspace))
	var agent := _find(_configuration.get("agents", []), _id(_agent))
	return {"workspace_id": str(workspace.get("id", "")), "agent_id": str(agent.get("id", "")), "workspace_revision": int(workspace.get("revision", 0)), "agent_revision": int(agent.get("revision", 0))}


func _refresh_grant() -> void:
	var workspace := _find(_configuration.get("workspaces", []), _id(_workspace))
	var agent := _find(_configuration.get("agents", []), _id(_agent))
	var authorized := false
	for grant: Dictionary in _configuration.get("grants", []):
		if grant.workspace_id == _id(_workspace) and grant.executor_id == _id(_agent):
			authorized = true
	_grant_status.text = ("已授权" if authorized else "尚未授权") + " · " + str(agent.get("executable", "请先配置 Agent")) + "\n目录：" + str(workspace.get("directory", "请先配置工作目录"))


func _grant(allow: bool) -> void:
	var data := _selection()
	data.allow = allow
	_command("grant", data)


func _create() -> void:
	var data := _selection()
	data.prompt = _prompt.text
	_command("create", data)


func _continue_task() -> void:
	_command("continue", {"task_id": _selected_task, "revision": int(_task.get("revision", 0)), "prompt": _prompt.text})


func _command(command: String, data: Dictionary) -> void:
	if not _requests.is_empty() and command != "permission" and command != "cancel":
		_notice.text = "上一项操作尚未结束，请稍候。"
		return
	var request := Crypto.new().generate_random_bytes(16).hex_encode()
	_requests[request] = {"command": command, "prompt": _prompt.text}
	_notice.text = "正在处理…"
	service.call("WorkCommand", _profile_id, request, command, JSON.stringify(data))


func _on_result(profile_id: String, request_id: String, json: String) -> void:
	if not _requests.has(request_id):
		return
	var request: Dictionary = _requests[request_id]
	_requests.erase(request_id)
	if profile_id != _profile_id:
		return
	var data: Dictionary = JSON.parse_string(json)
	_notice.text = str(data.get("error", data.get("notice", "操作完成。")))
	if data.has("probe"):
		_notice.text = "连接成功：%s %s" % [str(data.probe.name), str(data.probe.version)]
	if data.has("task_id"):
		_selected_task = str(data.task_id)
		if _prompt.text == str(request.prompt):
			_prompt.clear()
	_refresh()
	if data.has("agent"):
		_select_id(_agent_edit, str(data.agent.id))
		_select_id(_agent, str(data.agent.id))
		_edit_agent(_agent_edit.selected)
	if data.has("workspace"):
		_select_id(_workspace_edit, str(data.workspace.id))
		_select_id(_workspace, str(data.workspace.id))
		_edit_workspace(_workspace_edit.selected)
	_refresh_grant()


func _select_id(choice: OptionButton, id: String) -> void:
	for index: int in choice.item_count:
		if str(choice.get_item_metadata(index)) == id:
			choice.select(index)
			return


func _details() -> void:
	if _selected_task.is_empty():
		_task.clear()
		_result.text = "还没有任务。配置并授权 Agent 后，可以开始委托。"
		_activity.text = ""
		_permission_text.hide()
		PalUi.clear_children(_permissions)
		_permission_signature = ""
		return
	var details: Dictionary = JSON.parse_string(service.call("GetWorkDetails", _profile_id, _selected_task))
	if details.has("error"):
		_notice.text = str(details.error)
		return
	_task = details.task
	var states := {"queued": "排队中", "running": "执行中", "awaiting_permission": "等待权限选择", "completed": "已完成", "cancelled": "已取消", "failed": "失败", "interrupted": "已中断，可继续"}
	var text := str(states.get(_task.status, _task.status)) + "\n" + str(_task.get("error", "")) + "\n"
	for message: Dictionary in _task.get("messages", []):
		text += "\n" + ("你" if message.role == "user" else "Agent") + "：\n" + str(message.text) + "\n"
	if bool(_task.get("unfinished", false)):
		text += "\nAgent：\n" + str(_task.get("result", ""))
	if _result.text != text:
		_result.text = text
	var activities := PackedStringArray()
	for line: String in str(details.get("log", "")).split("\n", false):
		var entry: Variant = JSON.parse_string(line)
		if entry is Dictionary and entry.get("data") is Dictionary:
			var event: Dictionary = entry.data
			if str(event.get("sessionUpdate", "")) in ["tool_call", "tool_call_update", "plan"]:
				activities.append(str(event.get("title", event.get("toolCallId", "计划"))) + " · " + str(event.get("status", "")) + "\n" + JSON.stringify(event, "  "))
	_activity.text = "\n\n".join(activities) if not activities.is_empty() else "尚无工具活动。"
	var permission: Dictionary = _task.get("permission") if _task.get("permission") is Dictionary else {}
	var signature := JSON.stringify(permission)
	if signature != _permission_signature:
		_permission_signature = signature
		PalUi.clear_children(_permissions)
		_permission_text.visible = not permission.is_empty()
		_permission_text.text = str(permission.get("description", ""))
		for option: Dictionary in permission.get("options", []):
			var task_id := _selected_task
			PalUi.button(str(option.name), _permissions, func() -> void:
				_command("permission", {"task_id": task_id, "permission_id": permission.id, "option_id": option.id}))


func _edit_agent(_index: int) -> void:
	var agent := _find(_configuration.get("agents", []), _id(_agent_edit))
	_agent_name.text = str(agent.get("name", ""))
	_executable.text = str(agent.get("executable", ""))
	_arguments.text = "\n".join(agent.get("arguments", []))
	var environment := PackedStringArray()
	for key: String in agent.get("environment", {}):
		environment.append(key + "=" + str(agent.environment[key]))
	_environment.text = "\n".join(environment)
	_secret_name.clear()
	_secret_value.clear()
	_secret_status.text = "已保存的私密变量：" + ", ".join(agent.get("secret_environment_names", []))
	_agent_baseline = _agent_signature()


func _save_agent() -> void:
	var agent := _find(_configuration.get("agents", []), _id(_agent_edit)).duplicate(true)
	agent.name = _agent_name.text
	agent.executable = _executable.text.strip_edges()
	agent.arguments = Array(_arguments.text.split("\n", false))
	agent.environment = {}
	for line: String in _environment.text.split("\n", false):
		var separator := line.find("=")
		if separator <= 0:
			_notice.text = "环境变量每行填写 NAME=VALUE。"
			return
		agent.environment[line.left(separator).strip_edges()] = line.substr(separator + 1)
	agent.secrets = {}
	if not _secret_name.text.strip_edges().is_empty():
		agent.secrets[_secret_name.text.strip_edges()] = _secret_value.text
	_command("agent.save", agent)


func _edit_workspace(_index: int) -> void:
	var workspace := _find(_configuration.get("workspaces", []), _id(_workspace_edit))
	_workspace_name.text = str(workspace.get("name", ""))
	_directory.text = str(workspace.get("directory", ""))
	_workspace_baseline = JSON.stringify([_workspace_name.text, _directory.text])


func _save_workspace() -> void:
	var workspace := _find(_configuration.get("workspaces", []), _id(_workspace_edit)).duplicate(true)
	workspace.name = _workspace_name.text
	workspace.directory = _directory.text.strip_edges()
	_command("workspace.save", workspace)


func _browse(field: LineEdit, directory: bool) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if directory else FileDialog.FILE_MODE_OPEN_FILE
	dialog.use_native_dialog = true
	add_child(dialog)
	var selected := func(path: String) -> void: field.text = path; dialog.queue_free()
	if directory:
		dialog.dir_selected.connect(selected)
	else:
		dialog.file_selected.connect(selected)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)


func before_close() -> void:
	_drafts[_profile_id] = _prompt.text
	_secret_value.clear()
	_timer.stop()


func _agent_signature() -> String:
	return JSON.stringify([_agent_name.text, _executable.text, _arguments.text, _environment.text])


func is_dirty() -> bool:
	return _agent_signature() != _agent_baseline or JSON.stringify([_workspace_name.text, _directory.text]) != _workspace_baseline or not _secret_name.text.is_empty() or not _secret_value.text.is_empty()
