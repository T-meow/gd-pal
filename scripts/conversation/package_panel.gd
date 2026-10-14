class_name PalPackagePanel
extends VBoxContainer

signal new_persona_requested(token: String, fields: Array, persona: Dictionary)
var service: Node
var _profile_id := ""
var _preview: Dictionary = {}
var _request := ""
var _generation := 0
var _notice: Label
var _text: TextEdit
var _mode: OptionButton
var _fields: Dictionary = {}
var _apply: Button
var _pick: Button


func _ready() -> void:
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 850)
	set_meta("preferred_height", 700)
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	PalUi.hint("导入轻量版 v1 ZIP 人设包或对话记录包，确认预览后再应用。", self)
	_pick = PalUi.button("选择 ZIP 文件", self, _choose)
	_mode = OptionButton.new()
	_mode.add_item("创建新伙伴")
	_mode.add_item("覆盖当前伙伴的勾选字段")
	add_child(_mode)
	var fields := HFlowContainer.new()
	add_child(fields)
	for item: Array in [["name", "名字"], ["persona", "人设"], ["world", "世界设定"], ["memory", "长期记忆"], ["active_memory", "活跃记忆"]]:
		var check := CheckBox.new()
		check.text = str(item[1])
		check.button_pressed = true
		fields.add_child(check)
		_fields[item[0]] = check
	_text = TextEdit.new()
	_text.editable = false
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.y = 260
	add_child(_text)
	_apply = PalUi.button("确认导入", self, _import, true)
	_notice = PalUi.hint("", self)
	service.connect("PackageFinished", _on_result)


func open_profile(profile_id: String) -> void:
	before_close()
	_profile_id = profile_id
	_mode.select(0)
	_preview.clear()
	_text.text = ""
	_notice.text = "人设包默认创建新伙伴；对话包会追加到当前伙伴，重复记录自动跳过。"
	_sync()


func _choose() -> void:
	var generation := _generation
	PalPackageFiles.pick_import(self, service, func(data: Dictionary) -> void:
		if generation != _generation:
			if data.has("path"):
				service.call("DiscardPackageImport", str(data.path))
			return
		if data.has("error"):
			_notice.text = str(data.error)
			return
		_release_preview()
		_request = Crypto.new().generate_random_bytes(16).hex_encode()
		_notice.text = "正在读取并校验数据包…"
		service.call("PreviewPackage", _profile_id, _request, str(data.path))
		_sync())


func _on_result(profile_id: String, request_id: String, json: String) -> void:
	if profile_id != _profile_id or request_id != _request:
		return
	_request = ""
	var data: Dictionary = JSON.parse_string(json)
	if data.has("error"):
		_notice.text = str(data.error)
	elif data.has("token"):
		_preview = data
		if data.kind == "persona":
			var p: Dictionary = data.persona
			_text.text = "名字：%s\n\n人设\n%s\n\n世界设定\n%s\n\n长期记忆\n%s\n\n活跃记忆\n%s" % [str(p.display_name), str(p.persona), str(p.world) if p.world != null else "（未包含）", str(p.memory) if p.memory != null else "（未包含）", str(p.active_memory) if p.get("active_memory") != null else "（未包含）"]
		else:
			_text.text = "来源伙伴：%s\n会话：%d 段\n消息：%d 条\n\n追加到当前伙伴，当前聊天继续保持。" % [str(data.display_name), int(data.session_count), int(data.message_count)]
		_notice.text = "校验通过，请确认导入方式和内容。"
	else:
		_notice.text = str(data.get("notice", "导入完成。"))
		_release_preview()
	_sync()


func _sync() -> void:
	var persona: bool = _preview.get("kind") == "persona"
	_mode.visible = persona
	_mode.set_item_disabled(1, _profile_id.is_empty())
	for field: String in _fields:
		var included := field in ["name", "persona"] or (persona and _preview.persona.get(field) != null)
		_fields[field].visible = persona
		_fields[field].disabled = not included
	_apply.disabled = _preview.is_empty() or not _request.is_empty() or (not persona and _profile_id.is_empty())
	_pick.disabled = not _request.is_empty()


func _import() -> void:
	if _preview.get("kind") == "persona":
		var fields: Array = []
		for field: String in _fields:
			if not _fields[field].disabled and _fields[field].button_pressed:
				fields.append(field)
		if fields.is_empty():
			_notice.text = "请至少选择一个字段。"
			return
		if _mode.selected == 0:
			new_persona_requested.emit(str(_preview.token), fields, _preview.persona)
		else:
			complete(str(service.call("ApplyPersonaPackage", _profile_id, str(_preview.token), JSON.stringify(fields))))
	else:
		_request = Crypto.new().generate_random_bytes(16).hex_encode()
		_notice.text = "正在追加对话记录…"
		service.call("ImportConversationPackage", _profile_id, _request, str(_preview.token))
		_sync()


func complete(error: String) -> void:
	_notice.text = "导入完成，下次回复采用新设定。" if error.is_empty() else error
	if error.is_empty():
		_release_preview()
	_sync()


func _release_preview() -> void:
	if _preview.has("token"):
		service.call("ReleasePackagePreview", str(_preview.token))
	_preview.clear()


func before_close() -> void:
	_generation += 1
	if not _request.is_empty():
		service.call("CancelPackage", _request)
	_request = ""
	_release_preview()
