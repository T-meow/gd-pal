class_name PalManualContextPanel
extends VBoxContainer

signal summary_requested(profile_id: String)

var service: Node
var field := "memory"
var caption := "记忆"
var help_text := "写下希望伙伴记住的称呼、偏好和经历。"
var documents: Array[Dictionary] = []
var _profile_id := ""
var _editor: TextEdit
var _notice: Label
var _baseline := ""
var _editors: Dictionary = {}
var _baselines: Dictionary = {}
var _captions: Dictionary = {}
var _paths: Dictionary = {}
var _tabs: TabContainer
var _save_button: Button
var _file_button: Button
var _file_error := ""


func _ready() -> void:
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 820)
	set_meta("preferred_height", 640)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	PalUi.label(caption, self, 22)
	PalUi.hint(help_text + "各文件独立保存，发送消息时读取最新内容并组合。", self)
	if documents.is_empty():
		documents.append({"field": field, "caption": caption, "help": help_text})
	if documents.size() > 1:
		_tabs = TabContainer.new()
		_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_tabs.use_hidden_tabs_for_min_size = false
		add_child(_tabs)
	for document: Dictionary in documents:
		var parent: Control = self
		if _tabs != null:
			var page := VBoxContainer.new()
			page.name = str(document.caption)
			page.set_meta("context_field", str(document.field))
			_tabs.add_child(page)
			PalUi.hint(str(document.help), page)
			parent = page
		var editor := TextEdit.new()
		editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
		editor.custom_minimum_size.y = 240
		editor.placeholder_text = str(document.help)
		parent.add_child(editor)
		_editors[str(document.field)] = editor
		_captions[str(document.field)] = str(document.caption)
		editor.text_changed.connect(_update_count)
	_editor = _editors[field]
	var actions := HFlowContainer.new()
	add_child(actions)
	_save_button = PalUi.button("保存" + caption, actions, _save, true)
	PalUi.button("AI 整理", actions, func() -> void: summary_requested.emit(_profile_id))
	PalUi.button("还原未保存编辑", actions, func() -> void:
		for key: String in _editors:
			(_editors[key] as TextEdit).text = str(_baselines.get(key, ""))
		_notice.text = "已还原未保存编辑。")
	_file_button = PalUi.button("打开当前文件", actions, _open_file)
	_file_button.visible = not PalUi.is_mobile()
	var reload := PalUi.button("从文件重新载入", actions, func() -> void: open_profile(_profile_id))
	reload.tooltip_text = "读取磁盘上的最新内容，放弃当前未保存的编辑。"
	_notice = PalUi.hint("", self)
	if _tabs != null:
		_tabs.tab_changed.connect(func(_index: int) -> void: _select_editor())


func open_profile(profile_id: String) -> void:
	_profile_id = profile_id
	var data: Dictionary = JSON.parse_string(service.call("GetManualContext", profile_id))
	_paths = data.get("paths", {})
	_file_error = str(data.get("file_error", ""))
	for key: String in _editors:
		var editor: TextEdit = _editors[key]
		editor.text = str(data.get(key, ""))
		editor.editable = _file_error.is_empty()
		_baselines[key] = editor.text
	_save_button.disabled = not _file_error.is_empty()
	_select_editor()
	if _file_error.is_empty():
		_notice.text = "各文档分别保存；外部编辑后可重新载入，下次聊天也会读取最新内容。"


func _select_editor() -> void:
	if _tabs != null:
		field = str(_tabs.get_current_tab_control().get_meta("context_field"))
	_editor = _editors[field]
	_baseline = str(_baselines.get(field, ""))
	_file_button.disabled = str(_paths.get(field, "")).is_empty()
	_file_button.tooltip_text = str(_paths.get(field, ""))
	_update_count()


func _update_count() -> void:
	if _notice == null or _editor == null:
		return
	_notice.text = "%s · %d / 16000 字" % [str(_captions.get(field, caption)), _editor.text.length()] if _file_error.is_empty() else "文件读取失败：" + _file_error
	_notice.tooltip_text = str(_paths.get(field, ""))
	_notice.add_theme_color_override("font_color", PalUi.MUTED if _file_error.is_empty() else PalUi.ERROR)


func _open_file() -> void:
	var path := str(_paths.get(field, ""))
	if path.is_empty() or OS.shell_open(path) != OK:
		_notice.text = "未能打开文件：" + path


func is_dirty() -> bool:
	for key: String in _editors:
		if (_editors[key] as TextEdit).text != str(_baselines.get(key, "")):
			return true
	return false


func _save() -> void:
	var changes: Dictionary = {}
	for key: String in _editors:
		var text := (_editors[key] as TextEdit).text
		if text != str(_baselines.get(key, "")):
			changes[key] = text
	var error: String = service.call("SaveManualContexts", _profile_id, JSON.stringify(changes), JSON.stringify(_baselines))
	if error.is_empty():
		open_profile(_profile_id)
	_notice.text = "已保存，下次回复生效。" if error.is_empty() else error
	_notice.add_theme_color_override("font_color", PalUi.ACCENT if error.is_empty() else PalUi.ERROR)
