class_name PalHistoryPanel
extends VBoxContainer

signal session_requested(profile_id: String, session_id: String)
signal new_requested(profile_id: String)
signal record_requested(profile_id: String, session_id: String)
signal delete_requested(profile_id: String, session_id: String, title: String)
signal import_requested(profile_id: String)

var service: Node
var preferences: PalUiPreferences
var _profile_id := ""
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _row_buttons: Dictionary = {}
var _selection := ""
var _search: LineEdit
var _refresh_button: Button
var _history_group: VBoxContainer
var _new_group: VBoxContainer
var _notice: Label
var _feedback: Label
var _more: Button
var _continue_button: Button
var _record_button: Button
var _delete_button: Button
var _debounce: Timer
var _request_id := ""
var _entries: Array = []
var _busy := false
var _deleting: Dictionary = {}
var _export: Button
var _export_all: Button
var _exporting := false


func _ready() -> void:
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 900)
	set_meta("preferred_height", 680)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_history_group = VBoxContainer.new()
	_history_group.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_group.add_theme_constant_override("separation", 12)
	add_child(_history_group)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	_history_group.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索标题或对话内容"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 48 if PalUi.is_mobile() else 40
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(_search)
	_refresh_button = PalUi.button("刷新", search_row, func() -> void: _query(true))
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.3
	_debounce.timeout.connect(func() -> void: _query(true))
	add_child(_debounce)
	_search.text_changed.connect(func(_text: String) -> void:
		_request_id = ""
		_debounce.start()
		_busy = true
		_more.disabled = true
		_feedback.hide()
		_update_actions()
	)
	PalUi.hint("按最近对话时间排列 · 选择后继续聊天" if PalUi.is_mobile() else "按最近对话时间排列 · 双击卡片继续聊天", _history_group)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_history_group.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 10)
	_scroll.add_child(_rows)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	_history_group.add_child(actions)
	_continue_button = PalUi.button("继续对话", actions, _continue, true)
	_record_button = PalUi.button("导出记录" if PalUi.is_mobile() else "打开记录文件", actions, _open_record)
	_record_button.tooltip_text = "含图片的会话导出 ZIP，纯文字会话导出 Markdown。" if PalUi.is_mobile() else "打开本地 Markdown 记录"
	_export = PalUi.button("导出本段 ZIP", actions, func() -> void: _export_records(false))
	_export_all = PalUi.button("导出全部 ZIP", actions, func() -> void: _export_records(true))
	PalUi.button("导入记录包", actions, func() -> void: import_requested.emit(_profile_id))
	_delete_button = PalUi.button("删除会话", actions, _request_delete)
	PalUi.danger(_delete_button)
	_more = PalUi.button("加载更早记录", actions, func() -> void: _query(_entries.is_empty()))
	_new_group = VBoxContainer.new()
	_new_group.add_theme_constant_override("separation", 14)
	add_child(_new_group)
	PalUi.label("开始一个新话题", _new_group, 22)
	PalUi.hint("旧对话保留，人设、手动记忆和世界设定继续沿用。", _new_group)
	PalUi.button("开始新对话", _new_group, func() -> void: new_requested.emit(_profile_id), true)
	_notice = PalUi.hint("", self)
	_feedback = PalUi.hint("", self)
	_feedback.hide()
	service.connect("HistoryQueryFinished", _on_result)
	service.connect("ConversationChanged", func(id: String) -> void:
		if id == _profile_id and is_visible_in_tree():
			_update_actions()
	)
	if preferences != null:
		preferences.changed.connect(func() -> void:
			if is_visible_in_tree():
				_render_entries()
		)


func open_profile(profile_id: String, new_mode: bool = false) -> void:
	before_close()
	_profile_id = profile_id
	_history_group.visible = not new_mode
	_new_group.visible = new_mode
	_search.text = ""
	_debounce.stop()
	_entries.clear()
	_selection = ""
	_busy = false
	_feedback.hide()
	_notice.text = ""
	if not new_mode:
		_render_entries()
		_query(true)


func _query(reset: bool) -> void:
	if not is_visible_in_tree() or not _history_group.visible or _deleting.has(_profile_id):
		_update_actions()
		return
	_debounce.stop()
	_busy = true
	if reset:
		_entries.clear()
		_scroll.scroll_vertical = 0
		_render_entries()
	_request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_more.disabled = true
	_notice.text = "正在搜索…" if not _search.text.strip_edges().is_empty() else "正在读取历史会话…"
	_update_actions()
	service.call("QueryHistory", _profile_id, _request_id, _search.text, 0 if reset else _entries.size(), 50)


func _on_result(profile_id: String, request_id: String, result: String) -> void:
	if not is_visible_in_tree() or profile_id != _profile_id or request_id != _request_id:
		return
	_request_id = ""
	_busy = false
	_more.disabled = false
	var data: Variant = JSON.parse_string(result)
	if not data is Dictionary or data.has("error"):
		_notice.text = str(data.get("error", "无法读取历史会话。")) if data is Dictionary else "无法读取历史会话。"
		_more.text = "重试加载"
		_more.show()
		_render_entries()
		return
	_entries.append_array(data.get("items", []))
	_more.visible = bool(data.get("has_more", false))
	_more.text = "加载更多结果" if not _search.text.strip_edges().is_empty() else "加载更早记录"
	_notice.text = "已显示 %d / %d 段对话" % [_entries.size(), int(data.get("total", 0))]
	_render_entries()


func _selected_id() -> String:
	return _selection


func _render_entries() -> void:
	_row_buttons.clear()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var current: String = service.call("GetActiveSessionId", _profile_id)
	var ids := _entries.map(func(entry: Dictionary) -> String: return str(entry.session_id))
	if not ids.has(_selection):
		_selection = current if ids.has(current) else ""
	if _entries.is_empty():
		var empty := VBoxContainer.new()
		empty.custom_minimum_size.y = 150
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		_rows.add_child(empty)
		var title := PalUi.label("正在读取…" if _busy else ("没有匹配的对话" if not _search.text.is_empty() else "这里还没有对话"), empty, 20)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var help := PalUi.hint("" if _busy else ("试试其他关键词，或清空搜索。" if not _search.text.is_empty() else "开始聊天后，可以在这里找到记录。"), empty)
		help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var date := "__first__"
	for entry: Dictionary in _entries:
		var entry_date := str(entry.get("local_date", str(entry.get("created_at", "")).left(10)))
		if entry_date != date:
			date = entry_date
			var date_label := PalUi.label(date if not date.is_empty() else "日期未知", _rows, 13)
			date_label.add_theme_color_override("font_color", PalUi.MUTED)
			date_label.custom_minimum_size.y = 24
		_make_card(entry, current)
	_update_actions()


func _make_card(entry: Dictionary, current: String) -> void:
	var id := str(entry.session_id)
	var card := Button.new()
	card.custom_minimum_size.y = 132 if PalUi.is_mobile() else 112
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = str(entry.title) + "\n" + str(entry.get("preview", ""))
	_rows.add_child(card)
	_row_buttons[id] = card
	var margin := MarginContainer.new()
	card.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14 if side in ["left", "right"] else 10)
	margin.minimum_size_changed.connect(func() -> void:
		card.custom_minimum_size.y = maxf(132 if PalUi.is_mobile() else 112, margin.get_combined_minimum_size().y)
	)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	body.add_child(heading)
	var title := PalUi.label(str(entry.title), heading, 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if id == current:
		var badge := PalUi.label("当前", heading, 12)
		badge.add_theme_color_override("font_color", PalUi.ACCENT)
	var time_label := PalUi.label(str(entry.get("local_time", "")), heading, 12)
	time_label.add_theme_color_override("font_color", PalUi.MUTED)
	var metadata := PalUi.label("%d 条消息" % int(entry.get("message_count", 0)), body, 12)
	metadata.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	metadata.add_theme_color_override("font_color", PalUi.MUTED)
	var error := str(entry.get("error", ""))
	var preview := PalUi.label(error if not error.is_empty() else str(entry.get("preview", "尚未发送消息")), body, 13)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.max_lines_visible = 2
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview.add_theme_color_override("font_color", PalUi.ERROR if not error.is_empty() else PalUi.MUTED)
	_ignore_mouse(margin)
	card.pressed.connect(func() -> void: _select_entry(id))
	card.focus_entered.connect(func() -> void: _select_entry(id))
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
			_select_entry(id)
			_continue.call_deferred()
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_select_entry(id)
			_continue.call_deferred()
			card.accept_event()
	)
	_style_card(id)


func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		if child is Control:
			_ignore_mouse(child)


func _style_card(id: String) -> void:
	var card: Button = _row_buttons[id]
	var selected := id == _selection
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var tint := 0.13 if selected else (0.07 if state in ["hover", "pressed"] else 0.0)
		var box := PalUi.panel(PalUi.SURFACE.lerp(PalUi.ACCENT, tint), 12, 0)
		box.border_color = PalUi.ACCENT if selected else PalUi.BORDER
		box.set_border_width_all(2 if selected else 1)
		card.add_theme_stylebox_override(state, box)
	var focus := PalUi.panel(Color.TRANSPARENT, 12, 0)
	focus.border_color = PalUi.ACCENT
	focus.set_border_width_all(2)
	card.add_theme_stylebox_override("focus", focus)


func _select_entry(id: String) -> void:
	if _busy or _deleting.has(_profile_id):
		return
	_selection = id
	for key: String in _row_buttons:
		_style_card(key)
	_update_actions()


func _update_actions() -> void:
	if _continue_button == null:
		return
	var deleting := _deleting.has(_profile_id)
	_search.editable = not deleting
	_refresh_button.disabled = deleting
	_record_button.disabled = _busy or deleting or _selection.is_empty()
	_export.disabled = _record_button.disabled or _exporting
	_export_all.disabled = deleting or _exporting or _profile_id.is_empty()
	_continue_button.disabled = _record_button.disabled
	_delete_button.disabled = _record_button.disabled
	_delete_button.text = "正在删除…" if deleting else "删除会话"
	var snapshot: Variant = JSON.parse_string(service.call("GetSnapshot", _profile_id))
	if snapshot is Dictionary and bool(snapshot.get("busy", false)):
		_delete_button.disabled = true
		_delete_button.tooltip_text = "请先停止回复。"
	else:
		_delete_button.tooltip_text = "删除选中会话的记录；手动记忆仍然保留。"
	for entry: Dictionary in _entries:
		if str(entry.session_id) == _selection and not str(entry.get("error", "")).is_empty():
			_continue_button.disabled = true


func _continue() -> void:
	if not _continue_button.disabled:
		session_requested.emit(_profile_id, _selected_id())


func _open_record() -> void:
	if not _record_button.disabled:
		record_requested.emit(_profile_id, _selected_id())


func _request_delete() -> void:
	if _delete_button.disabled:
		return
	for entry: Dictionary in _entries:
		if str(entry.session_id) == _selection:
			delete_requested.emit(_profile_id, _selection, str(entry.title))
			return


func begin_delete(profile_id: String) -> void:
	_deleting[profile_id] = true
	if profile_id == _profile_id:
		before_close()
		_busy = false
		_more.disabled = true
		_notice.text = "正在删除会话…"
		_feedback.hide()
		_update_actions()


func complete_delete(profile_id: String, result: Dictionary) -> void:
	_deleting.erase(profile_id)
	if profile_id != _profile_id or not is_visible_in_tree():
		return
	_feedback.text = str(result.get("error", result.get("warning", "")))
	if bool(result.get("deleted", false)):
		_selection = ""
		if _feedback.text.is_empty():
			_feedback.text = "会话已删除，手动记忆保留。"
		_query(true)
	else:
		_notice.text = "删除未完成，原会话保留。"
		_more.disabled = false
		_update_actions()
	_feedback.visible = not _feedback.text.is_empty()


func _export_records(all_sessions: bool) -> void:
	var profile := _profile_id
	_exporting = true
	_update_actions()
	_notice.text = "正在打包…"
	PalPackageFiles.export_package(self, service, profile, "conversations", "" if all_sessions else _selection, {}, false, false, func(message: String) -> void:
		_exporting = false
		if profile == _profile_id:
			_notice.text = message
		_update_actions())


func before_close() -> void:
	_request_id = ""
	if _debounce != null:
		_debounce.stop()
