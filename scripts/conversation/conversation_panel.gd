class_name PalConversationPanel
extends VBoxContainer
## A persistent conversation view. Hosts only move it; navigation belongs to the app.

signal presentation_changed(display_name: String, state: String, preview: String)
signal bubbles_changed(dialogue: String, description: String, index: int, total: int)
signal reveal_requested
signal navigation_requested(page_id: String, profile_id: String, context: Dictionary)
signal speech_requested(text: String)
signal user_activity(profile_id: String)
signal dialogue_enable_requested

const DIALOGUE_PAGES := preload("res://scripts/conversation/dialogue_pages.gd")
const IMAGE_ATTACHMENTS := preload("res://scripts/conversation/chat_image_attachments.gd")

var service: Node
var performance: PalPerformanceQueue
var _profiles: Dictionary = {}
var _profile_id := ""
var _session_id := ""
var _drafts: Dictionary = {}
var _reading: Dictionary = {}
var _scroll_revision := 0
var _restoring_scroll := false
var _submitted: Dictionary = {}
var _restoring_input := false
var _scroll: ScrollContainer
var _messages: VBoxContainer
var _empty: Label
var _input: TextEdit
var _composer: VBoxContainer
var _send_button: Button
var _action_button: Button
var _image_button: Button
var _images: IMAGE_ATTACHMENTS
var _stop_button: Button
var _retry_button: Button
var _save_retry: Button
var _connect_button: Button
var _status: Label
var _storage_status: Label
var _counter: Label
var _new_messages: Button
var _message_views: Dictionary = {}
var _rendered_ids: Array[String] = []
var _busy := false
var _dialogue_enabled := true
var _dialogue_notice: HFlowContainer
var _mobile_compact := false
var _context_status: Label
var _composer_actions: HFlowContainer
var _composer_more: MenuButton
var _composer_frame: PanelContainer
var _composer_column: VBoxContainer
var _composer_toolbar: HBoxContainer
var _desktop_compact := false
var _retry_queued := false
var _retry_error := ""
var _bubble_pages: Array[Dictionary] = []
var _bubble_message_id := ""
var _bubble_source := ""
var _bubble_index := 0
var _bubble_remaining := 0.0
var _bubble_live := false
var _bubble_displayed := ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_scroll = PalDialogueScroll.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = 60
	add_child(_scroll)
	_messages = VBoxContainer.new()
	_messages.mouse_filter = Control.MOUSE_FILTER_PASS
	_messages.add_theme_constant_override("separation", 12)
	_messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var timeline := VBoxContainer.new()
	timeline.mouse_filter = Control.MOUSE_FILTER_PASS
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(timeline)
	timeline.add_child(_messages)
	_scroll.resized.connect(_resize_messages)
	_new_messages = PalUi.button("有新消息 ↓", self, func() -> void:
		_scroll_to_end()
		_new_messages.hide()
	)
	_new_messages.hide()
	_empty = PalUi.hint("", self)
	_composer = VBoxContainer.new()
	_composer.add_theme_constant_override("separation", 6)
	add_child(_composer)
	_storage_status = PalUi.hint("", _composer)
	_storage_status.add_theme_color_override("font_color", PalUi.ERROR)
	_storage_status.max_lines_visible = 2
	_storage_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dialogue_notice = HFlowContainer.new()
	_dialogue_notice.add_theme_constant_override("h_separation", 10)
	_composer.add_child(_dialogue_notice)
	PalUi.label("对话已关闭 · 当前只读", _dialogue_notice, 12, true)
	PalUi.button("启用对话", _dialogue_notice, func() -> void: dialogue_enable_requested.emit()).add_theme_font_size_override("font_size", 12)
	_dialogue_notice.hide()
	_images = IMAGE_ATTACHMENTS.new()
	_images.service = service
	_composer.add_child(_images)
	_images.changed.connect(_update_send_button)
	_images.notice.connect(func(message: String) -> void: _status.text = message; _status.show())
	_input = TextEdit.new()
	_input.custom_minimum_size.y = 72
	_input.placeholder_text = "想和你说……（留空可继续）"
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_composer.add_child(_input)
	_input.gui_input.connect(_on_input_event)
	if not PalUi.is_mobile():
		var input_menu := _input.get_menu()
		input_menu.add_separator()
		input_menu.add_item("粘贴图片", 1001)
		input_menu.id_pressed.connect(func(id: int) -> void:
			if id == 1001 and not _images.paste_image():
				_status.text = "剪贴板中没有图片，可粘贴截图或通过图片按钮选取文件。"
				_status.show())
	_input.text_changed.connect(func() -> void:
		_counter.text = "%d / 4000" % _input.text.length()
		if not _restoring_input and not _session_id.is_empty():
			_drafts[_draft_key()] = _input.text
			user_activity.emit(_profile_id)
		_update_send_button()
	)
	var actions := HFlowContainer.new()
	_composer_actions = actions
	actions.add_theme_constant_override("h_separation", 8)
	_composer.add_child(actions)
	_counter = PalUi.label("0 / 4000", actions, 12, true)
	_counter.custom_minimum_size.x = 82
	_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_connect_button = PalUi.button("接入模型", actions, open_settings)
	_save_retry = PalUi.button("保存重试", actions, _retry_save)
	_retry_button = PalUi.button("重试回复", actions, _retry)
	_image_button = PalUi.button("图片", actions, func() -> void: _images.pick_images())
	_image_button.focus_mode = Control.FOCUS_NONE
	_image_button.tooltip_text = "添加图片（每条最多 4 张）" + ("" if PalUi.is_mobile() else " · Ctrl + V 粘贴截图")
	_action_button = PalUi.button("动作" if PalUi.is_mobile() else "输入动作", actions, _insert_action)
	_action_button.focus_mode = Control.FOCUS_NONE
	_action_button.tooltip_text = "插入（），接下来在括号内输入动作；选中文字也可直接放入括号。"
	if PalUi.is_mobile():
		PalUi.button("朗读", actions, _read_last_reply)
	_stop_button = PalUi.button("停止", actions, _stop)
	_send_button = PalUi.button("发送", actions, _send, true)
	_send_button.tooltip_text = "Ctrl + Enter 发送 · Enter 换行"
	_status = PalUi.hint("", _composer)
	_context_status = PalUi.hint("", _composer)
	_status.max_lines_visible = 2
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if PalUi.is_mobile():
		_scroll.custom_minimum_size.y = 24
		for state: String in ["normal", "focus", "read_only"]:
			_input.add_theme_stylebox_override(state, PalUi.glass(0.35, 12, 8))
		_counter.hide()
		var input_row := HBoxContainer.new()
		_composer.add_child(input_row)
		_composer.move_child(input_row, 1)
		_input.reparent(input_row, false)
		_input.custom_minimum_size.y = 56
		_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_action_button.reparent(input_row, false)
		input_row.move_child(_action_button, 0)
		_image_button.reparent(input_row, false)
		input_row.move_child(_image_button, 0)
		_image_button.custom_minimum_size = Vector2(44, 48)
		_composer.move_child(_images, 1)
		_send_button.reparent(input_row, false)
		_stop_button.reparent(input_row, false)
		_send_button.tooltip_text = "发送消息"
	else:
		_build_desktop_composer()
	service.connect("ConversationChanged", _on_changed)
	service.connect("SettingsChanged", _refresh)
	get_viewport().gui_focus_changed.connect(func(_control: Control) -> void: _refresh_message_tools())
	_refresh()


func _build_desktop_composer() -> void:
	var frame := PanelContainer.new()
	_composer_frame = frame
	frame.add_theme_stylebox_override("panel", PalUi.glass(0.55, 12, 10))
	_composer.add_child(frame)
	_composer.move_child(frame, 2)
	var column := VBoxContainer.new()
	_composer_column = column
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)
	_images.reparent(column, false)
	_input.reparent(column, false)
	_input.placeholder_text = "把此刻的心情，说给我听…（留空可继续）"
	_input.custom_minimum_size.y = 76
	_input.add_theme_font_size_override("font_size", 14)
	for state: String in ["normal", "focus", "read_only"]:
		var style := StyleBoxEmpty.new()
		style.set_content_margin_all(4)
		_input.add_theme_stylebox_override(state, style)
	_input.focus_entered.connect(func() -> void:
		var focused := PalUi.glass(0.66, 12, 6 if _desktop_compact else 10)
		focused.border_color = Color(PalUi.ACCENT, 0.6)
		frame.add_theme_stylebox_override("panel", focused)
	)
	_input.focus_exited.connect(func() -> void: frame.add_theme_stylebox_override("panel", PalUi.glass(0.55, 12, 6 if _desktop_compact else 10)))
	var toolbar := HBoxContainer.new()
	_composer_toolbar = toolbar
	toolbar.add_theme_constant_override("separation", 6)
	column.add_child(toolbar)
	_composer_more = MenuButton.new()
	_composer_more.text = "···"
	_composer_more.tooltip_text = "对话选项"
	_composer_more.custom_minimum_size = Vector2(32, 32)
	toolbar.add_child(_composer_more)
	PalUi.quiet(_composer_more)
	_image_button.reparent(toolbar, false)
	_image_button.custom_minimum_size = Vector2(48, 32)
	_image_button.add_theme_font_size_override("font_size", 12)
	PalUi.quiet(_image_button)
	_action_button.reparent(toolbar, false)
	_action_button.custom_minimum_size = Vector2(64, 32)
	_action_button.add_theme_font_size_override("font_size", 12)
	PalUi.quiet(_action_button)
	var menu := _composer_more.get_popup()
	for caption: String in ["朗读最近的回复", "历史会话", "打开记录文件", "手动记忆", "世界设定"]:
		menu.add_item(caption)
	menu.add_item("AI 整理", 5)
	if OS.get_name() == "Windows":
		menu.add_item("Agent 任务", 6)
	menu.add_item("导出当前对话 ZIP", 7)
	menu.add_item("导入数据包", 8)
	menu.id_pressed.connect(func(id: int) -> void:
		match id:
			0: _read_last_reply()
			1: _navigate("sessions")
			2: _open_markdown()
			3: _open_memory()
			4: _open_world()
			5: _navigate("summary")
			6: _navigate("agent")
			7: _export_records()
			8: _navigate("packages")
	)
	_counter.reparent(toolbar, false)
	_counter.custom_minimum_size.x = 0
	_counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_counter.add_theme_font_size_override("font_size", 10)
	for button: Button in [_stop_button, _send_button]:
		button.reparent(toolbar, false)
		button.custom_minimum_size = Vector2(70, 34)
		button.add_theme_font_size_override("font_size", 12)
		button.icon = load("res://assets/ui/icons/stop.svg" if button == _stop_button else "res://assets/ui/icons/send.svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 16)
		for state: String in ["normal", "hover", "pressed"]:
			button.add_theme_color_override("icon_" + state + "_color", PalUi.ON_ACCENT if button == _send_button else PalUi.ACCENT)
	for button: Button in [_connect_button, _save_retry, _retry_button]:
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size.y = 32
	_status.add_theme_font_size_override("font_size", 11)
	_context_status.add_theme_font_size_override("font_size", 11)
	_context_status.hide()
	_empty.add_theme_font_size_override("font_size", 13)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_messages.add_theme_constant_override("separation", 20)
	_input.text_changed.connect(_fit_compact_input)
	_input.resized.connect(_fit_compact_input)


func set_desktop_compact(value: bool) -> void:
	if PalUi.is_mobile() or _composer_frame == null or _desktop_compact == value:
		return
	_desktop_compact = value
	_composer.add_theme_constant_override("separation", 3 if value else 6)
	_composer_column.add_theme_constant_override("separation", 2 if value else 6)
	_composer_frame.add_theme_stylebox_override("panel", PalUi.glass(0.55, 12, 6 if value else 10))
	_retry_button.reparent(_composer_toolbar if value else _composer_actions, false)
	if value:
		_composer_toolbar.move_child(_retry_button, maxi(0, _composer_toolbar.get_child_count() - 2))
	for button: Control in [_composer_more, _image_button, _action_button, _send_button, _stop_button, _retry_button, _connect_button, _save_retry]:
		PalUi.dense(button, 26 if value else 32)
	_send_button.custom_minimum_size.x = 58 if value else 70
	_stop_button.custom_minimum_size.x = 58 if value else 70
	_status.max_lines_visible = 1 if value else 2
	_fit_compact_input()
	_refresh()


func _fit_compact_input() -> void:
	if not _desktop_compact:
		if _composer_frame != null:
			_input.custom_minimum_size.y = 76
		return
	var rows := 0
	for line: int in _input.get_line_count():
		rows += 1 + _input.get_line_wrap_count(line)
		if rows >= 5:
			break
	_input.custom_minimum_size.y = clampf(rows * 19.0 + 8.0, 40.0, 100.0)


func refresh_theme() -> void:
	for view: Dictionary in _message_views.values():
		view.erase("body_signature")
	_refresh()


func _read_last_reply() -> void:
	if not _dialogue_enabled:
		return
	var snapshot: Dictionary = JSON.parse_string(service.call("GetSnapshot", _profile_id))
	var messages: Array = snapshot.get("messages", [])
	for index: int in range(messages.size() - 1, -1, -1):
		var message: Dictionary = messages[index]
		if message.get("role") == "assistant" and message.get("status") != "superseded":
			var spoken := PackedStringArray()
			for page: Dictionary in DIALOGUE_PAGES.parse(str(message.get("content", ""))):
				if not str(page.dialogue).is_empty():
					spoken.append(str(page.dialogue))
			if not spoken.is_empty():
				speech_requested.emit("\n".join(spoken))
			return


func make_more_button(parent: Node) -> MenuButton:
	var button := MenuButton.new()
	button.text = "···"
	button.tooltip_text = "对话、档案与设置"
	button.custom_minimum_size = Vector2(36, 36)
	parent.add_child(button)
	var menu := button.get_popup()
	for caption: String in ["历史会话", "新对话", "伙伴档案", "手动记忆", "世界设定", "连接设置", "打开记录文件", "主题与外观"]:
		menu.add_item(caption)
	menu.add_item("AI 整理", 8)
	if OS.get_name() == "Windows":
		menu.add_item("Agent 任务", 9)
	menu.add_item("导入数据包", 10)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 6:
			_open_markdown()
		elif id == 7:
			_navigate("appearance")
		elif id == 8:
			_navigate("summary")
		elif id == 9:
			_navigate("agent")
		elif id == 10:
			_navigate("packages")
		else:
			_navigate(["sessions", "new", "profile", "memory", "world", "settings"][id])
	)
	return button


func set_mobile_compact(value: bool) -> void:
	if _mobile_compact == value:
		return
	_mobile_compact = value
	_input.custom_minimum_size.y = 48 if value else 56
	_status.max_lines_visible = 1 if value else 2
	_refresh()


func move_composer(destination: Node) -> void:
	if _composer.get_parent() != destination:
		_composer.reparent(destination, false)


func restore_composer() -> void:
	move_composer(self)
	move_child(_composer, -1)


func focus_input() -> void:
	_input.grab_focus()


func set_profiles(profiles: Dictionary) -> void:
	_profiles = profiles


func open_profile(profile_id: String) -> void:
	if _profile_id != profile_id:
		save_view_state()
		_profile_id = profile_id
		_session_id = ""
	_refresh()


func _draft_key() -> String:
	return _profile_id + ":" + _session_id


func save_view_state() -> void:
	if _input == null or _session_id.is_empty():
		return
	var bar := _scroll.get_v_scroll_bar()
	_drafts[_draft_key()] = _input.text
	if not _restoring_scroll:
		_reading[_draft_key()] = {"scroll": _scroll.scroll_vertical, "end": bar.value >= bar.max_value - bar.page - 48}
		for id: String in _rendered_ids if PalUi.is_mobile() else []:
			var card: Control = _message_views[id].card
			if card.get_global_rect().end.y >= _scroll.global_position.y:
				_reading[_draft_key()]["anchor"] = id
				_reading[_draft_key()]["offset"] = card.global_position.y - _scroll.global_position.y
				break


func restore_view_state() -> void:
	var key := _draft_key()
	_scroll_revision += 1
	var revision := _scroll_revision
	_restoring_scroll = true
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or key != _draft_key() or revision != _scroll_revision:
		return
	var position_state: Dictionary = _reading.get(key, {"scroll": 0, "end": true})
	if position_state.end:
		_scroll_to_end()
	else:
		_scroll.scroll_vertical = int(position_state.scroll)
		var anchor := str(position_state.get("anchor", ""))
		if PalUi.is_mobile() and _message_views.has(anchor):
			var card: Control = _message_views[anchor].card
			_scroll.scroll_vertical = roundi(card.position.y - float(position_state.get("offset", 0)))
	_restoring_scroll = false


func forget_session_view(profile_id: String, session_id: String) -> void:
	# Refresh first so save_view_state cannot put the deleted draft back into the cache.
	if _profile_id == profile_id:
		_refresh()
	var key := profile_id + ":" + session_id
	_drafts.erase(key)
	_reading.erase(key)
	_submitted.erase(key)
	_images.forget(profile_id, session_id)


func _on_changed(profile_id: String) -> void:
	if profile_id == _profile_id:
		_refresh()


func _snapshot() -> Dictionary:
	var value: Variant = JSON.parse_string(service.call("GetSnapshot", _profile_id))
	if value is Dictionary:
		for message: Dictionary in value.get("messages", []):
			if message.has("display_content"):
				message["content"] = message.display_content
				message["segments"] = message.get("display_segments", [])
	return value if value is Dictionary else {}


func _refresh() -> void:
	if _input == null:
		return
	var data := _snapshot()
	if data.is_empty():
		_dialogue_notice.hide()
		_images.set_context("", "")
		_image_button.disabled = true
		_render_messages([], true)
		_empty.text = "添加一位伙伴，就可以开始聊天。"
		_empty.show()
		_input.editable = false
		_send_button.disabled = true
		_action_button.disabled = true
		_stop_button.hide()
		_retry_button.hide()
		_storage_status.hide()
		_save_retry.hide()
		_connect_button.hide()
		_composer_actions.hide()
		_context_status.text = ""
		_update_bubbles({})
		return
	var changed_session := _session_id != str(data.session_id)
	if changed_session:
		_retry_error = ""
		save_view_state()
		_session_id = str(data.session_id)
	_images.set_context(_profile_id, _session_id)
	_dialogue_enabled = bool(data.get("dialogue_enabled", true))
	_input.editable = _dialogue_enabled
	_input.placeholder_text = "想和你说……（留空可继续）" if _dialogue_enabled else "当前伙伴已关闭对话，启用后即可输入。"
	_dialogue_notice.visible = not _dialogue_enabled
	_busy = bool(data.busy)
	var waiting_display: bool = not data.messages.is_empty() and bool(data.messages[-1].get("display_waiting", false))
	if changed_session:
		_restoring_input = true
		_input.text = str(_drafts.get(_draft_key(), ""))
		_restoring_input = false
	_restore_failed_draft(data)
	var bar := _scroll.get_v_scroll_bar()
	var follow_end := bar.value >= bar.max_value - bar.page - 48
	var old_count := _rendered_ids.size()
	_render_messages(data.messages, changed_session)
	if changed_session:
		restore_view_state()
	elif follow_end and not _restoring_scroll:
		_scroll_to_end.call_deferred()
	elif old_count != _rendered_ids.size() or _busy:
		_new_messages.show()
	_empty.visible = data.messages.is_empty() and not _mobile_compact
	_empty.text = "从一句你好开始，今天也一起度过吧。" if data.has_key else "点击「接入模型」，开启你们的第一段对话。"
	_connect_button.visible = _dialogue_enabled and not bool(data.has_key)
	_storage_status.text = str(data.storage_error)
	_storage_status.tooltip_text = _storage_status.text
	_storage_status.visible = not _storage_status.text.is_empty()
	_save_retry.visible = _storage_status.visible
	_stop_button.visible = _dialogue_enabled and (_busy or waiting_display)
	_stop_button.text = "停止" if _busy else "显示全文"
	_stop_button.tooltip_text = "停止当前回复" if _busy else "停止表演并立即显示已生成的文字"
	_send_button.visible = not _busy
	_retry_button.visible = _dialogue_enabled and not _busy and not waiting_display and not data.messages.is_empty() and str(data.messages[-1].status) in ["failed", "interrupted", "stopped", "truncated"]
	_retry_button.disabled = not _dialogue_enabled or _busy
	if not PalUi.is_mobile():
		_composer_actions.visible = _connect_button.visible or _save_retry.visible or (_retry_button.visible and not _desktop_compact)
	_update_send_button()
	_status.text = "正在回复，可以先写下一句话。" if _busy else ("" if PalUi.is_mobile() else "Enter 换行 · Ctrl + Enter 发送")
	if not _dialogue_enabled:
		_status.text = "当前只读；恢复窗口或切换模式不会自动开启对话。"
	if not str(data.notice).is_empty():
		_status.text = str(data.notice)
	if int(data.total_messages) > 200:
		_status.text += " · 最近 200 条，完整内容见记录文件"
	if not _retry_error.is_empty():
		_status.text = _retry_error
	_status.add_theme_color_override("font_color", PalUi.ERROR if not _retry_error.is_empty() else PalUi.MUTED)
	_status.tooltip_text = _status.text
	_status.visible = (not _desktop_compact and not _status.text.is_empty()) or not _retry_error.is_empty()
	if _composer_frame != null:
		_composer_frame.tooltip_text = _status.text
	_context_status.text = ""
	if _composer_more != null:
		_composer_more.tooltip_text = "对话选项"
	var preview := "今天也陪着你。想聊些什么？"
	var state := "陪伴中"
	if _busy:
		state = "正在回复…"
	var bubble_message: Dictionary = {}
	for index: int in range(data.messages.size() - 1, -1, -1):
		var message: Dictionary = data.messages[index]
		if str(message.role) == "assistant" and str(message.status) != "superseded":
			bubble_message = message
			preview = str(message.content) if not str(message.content).is_empty() else ("正在想怎么回答你…" if _busy else "这次回复没有生成内容。")
			if bool(message.get("display_waiting", false)):
				state = "正在表演…" if message.get("presentation_status") == "ready" else ("正在回复…" if _busy else "正在准备表演…")
				if str(message.content).is_empty():
					preview = state
			if str(message.status) in ["failed", "interrupted"]:
				state = "回复失败"
				if str(message.content).is_empty():
					preview = "这次回复没有完成，可以重试。"
			elif str(message.status) == "stopped":
				state = "已停止回复"
			elif str(message.status) == "truncated":
				state = "已达到回复长度"
			break
	if not _dialogue_enabled:
		state = "安静陪伴 · 对话已关闭"
		preview = "可以查看历史记录，启用对话后再聊天。"
		_bubble_live = false
		_update_bubbles({})
	else:
		_update_bubbles(bubble_message)
	presentation_changed.emit(str(data.display_name), state, preview)
	_status.visible = not _status.text.is_empty()


func _update_bubbles(message: Dictionary) -> void:
	var id := _session_id + ":" + str(message.get("id", "")) if not message.is_empty() else ""
	var streaming := str(message.get("status", "")) == "streaming"
	if id != _bubble_message_id:
		_bubble_live = streaming or (not _bubble_message_id.is_empty() and _bubble_message_id.begins_with(_session_id + ":"))
		_bubble_message_id = id
		_bubble_index = 0
		_bubble_source = ""
		_bubble_displayed = ""
		if is_instance_valid(performance):
			performance.cancel()
	if str(message.get("status", "")) in ["stopped", "failed", "interrupted"]:
		_bubble_live = false
	var text := str(message.get("content", ""))
	var source := JSON.stringify([text, streaming, PalUi.dialogue_bubbles, PalUi.description_bubbles])
	if source != _bubble_source:
		_bubble_source = source
		_bubble_pages.clear()
		for page: Dictionary in DIALOGUE_PAGES.parse(text, not streaming):
			if (not PalUi.dialogue_bubbles and not PalUi.description_bubbles) or (PalUi.dialogue_bubbles and not str(page.dialogue).is_empty()) or (PalUi.description_bubbles and not str(page.description).is_empty()):
				_bubble_pages.append(page)
		_bubble_index = clampi(_bubble_index, 0, maxi(0, _bubble_pages.size() - 1))
	_publish_bubble_page(_bubble_live)


func _publish_bubble_page(play: bool = false) -> void:
	if _bubble_pages.is_empty():
		bubbles_changed.emit("", "", 0, 0)
		return
	var page: Dictionary = _bubble_pages[_bubble_index]
	var signature := str(_bubble_index) + JSON.stringify(page)
	if signature != _bubble_displayed:
		_bubble_displayed = signature
		_bubble_remaining = clampf(float(str(page.dialogue).length() + str(page.description).length()) / 6.0, 2.8, 18.0)
		if play and is_instance_valid(performance):
			performance.present_segment(str(page.dialogue), str(page.description))
	bubbles_changed.emit(str(page.dialogue), str(page.description), _bubble_index, _bubble_pages.size())


func navigate_bubbles(direction: int) -> void:
	if not _dialogue_enabled:
		return
	var next := _bubble_index + direction
	if next < 0 or next >= _bubble_pages.size():
		return
	_bubble_live = true
	_bubble_index = next
	_publish_bubble_page(true)
	user_activity.emit(_profile_id)


func refresh_bubble_preferences() -> void:
	_bubble_remaining = maxf(_bubble_remaining, 2.8)
	if PalUi.dialogue_autoplay and not _bubble_pages.is_empty():
		_bubble_live = true
	_refresh()


func _process(delta: float) -> void:
	if not _dialogue_enabled or not PalUi.dialogue_autoplay or not _bubble_live or _bubble_pages.is_empty():
		return
	if is_instance_valid(performance) and performance.pet.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	_bubble_remaining = maxf(0.0, _bubble_remaining - delta)
	if _bubble_remaining > 0.0 or (is_instance_valid(performance) and performance.is_playing()):
		return
	if _bubble_index + 1 < _bubble_pages.size():
		_bubble_index += 1
		_publish_bubble_page(true)


func _render_messages(messages: Array, reset: bool) -> void:
	var ids: Array[String] = []
	for message: Dictionary in messages:
		ids.append(str(message.id))
	if reset or ids != _rendered_ids:
		for child: Node in _messages.get_children():
			_messages.remove_child(child)
			child.queue_free()
		_message_views.clear()
		_rendered_ids = ids
		for message: Dictionary in messages:
			var card := PanelContainer.new()
			var is_user := str(message.role) == "user"
			var style := PalUi.panel(Color(PalUi.BLUE if is_user else PalUi.SURFACE, 0.35), 12, 12)
			if not PalUi.is_mobile():
				style = PalUi.panel(Color(PalUi.ACCENT, 0.12) if is_user else Color(PalUi.SURFACE, 0.2), 12, 12)
				style.set_border_width_all(0)
			card.add_theme_stylebox_override("panel", style)
			card.mouse_filter = Control.MOUSE_FILTER_PASS
			card.size_flags_horizontal = Control.SIZE_SHRINK_END if is_user else Control.SIZE_FILL
			_messages.add_child(card)
			var column := VBoxContainer.new()
			column.mouse_filter = Control.MOUSE_FILTER_PASS
			column.add_theme_constant_override("separation", 8)
			card.add_child(column)
			var heading_row := HBoxContainer.new()
			heading_row.mouse_filter = Control.MOUSE_FILTER_PASS
			column.add_child(heading_row)
			var heading := PalUi.label("", heading_row, 12, true)
			heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			heading.max_lines_visible = 1
			heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			var body := RichTextLabel.new()
			body.bbcode_enabled = false
			body.fit_content = true
			body.scroll_active = false
			body.selection_enabled = false
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_font_size_override("normal_font_size", 16)
			body.custom_minimum_size.x = 80
			column.add_child(body)
			_images.add_message_images(column, _profile_id, message.get("images", []))
			var cue := PalUi.label("", column, 12)
			cue.add_theme_color_override("font_color", PalUi.MUTED)
			cue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var error := PalUi.label("", column, 13)
			error.add_theme_color_override("font_color", PalUi.ERROR)
			error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_message_views[str(message.id)] = {"heading": heading, "body": body, "cue": cue, "error": error, "card": card, "is_user": is_user}
			var tools_row := HBoxContainer.new()
			tools_row.custom_minimum_size.y = 28
			heading_row.add_child(tools_row)
			_message_views[str(message.id)].tools = tools_row
			var copy_id: String = str(message.id)
			var copy := PalUi.compact_button("复制", tools_row, func() -> void: _copy_message(copy_id))
			copy.tooltip_text = "复制这条消息"
			copy.disabled = str(message.content).is_empty()
			_message_views[str(message.id)].copy = copy
			card.mouse_entered.connect(_refresh_message_tools)
			card.mouse_exited.connect(_refresh_message_tools.call_deferred)
			if is_user:
				var source_id := str(message.id)
				var remember := Button.new()
				remember.text = "记住"
				remember.disabled = str(message.content).is_empty()
				remember.tooltip_text = "图片内容可在伙伴识图回复后通过 AI 整理保存。" if remember.disabled else "记住这条消息"
				if PalUi.is_mobile():
					remember.custom_minimum_size = Vector2(48, 48)
				remember.flat = true
				remember.add_theme_font_size_override("font_size", 12)
				remember.add_theme_stylebox_override("normal", PalUi.panel(Color.TRANSPARENT, 6, 3))
				tools_row.add_child(remember)
				remember.pressed.connect(func() -> void: _remember_message(source_id))
			else:
				var retry := PalUi.button("重试回复", column, _retry) if PalUi.is_mobile() else PalUi.compact_button("重新回应", tools_row, _retry)
				_message_views[str(message.id)].retry = retry
		_resize_messages()
		_refresh_message_tools()
	var states := {"streaming": "正在回复…", "complete": "", "truncated": "达到回复长度上限", "stopped": "已停止", "failed": "请求失败", "interrupted": "回复中断"}
	for message: Dictionary in messages:
		var view: Dictionary = _message_views[str(message.id)]
		view.heading.text = "你" if str(message.role) == "user" else str(_profiles.get(_profile_id, "伙伴")) + "  " + str(states.get(message.status, ""))
		_render_body(view, message)
		view.copy.disabled = str(message.content).is_empty()
		view.body.visible = not str(message.content).is_empty()
		var cues: PackedStringArray = []
		for segment: Dictionary in message.get("segments", []):
			var action := str(segment.get("act", "")) if segment.get("act") != null else ""
			if not action.is_empty():
				cues.append(str(PalMotionLibrary.clip(PalMotionLibrary.body_clip(action)).get("label", action)))
		view.cue.text = ("表演提示：" if PalUi.is_mobile() else "↳ ") + "、".join(cues)
		view.cue.visible = not cues.is_empty()
		view.error.text = str(message.error)
		view.error.visible = not str(message.error).is_empty()
		if view.has("retry"):
			view.retry.visible = message == messages[-1] and str(message.status) in ["complete", "truncated", "stopped", "failed", "interrupted"]
			view.retry.disabled = _busy or message != messages[-1]


func _render_body(view: Dictionary, message: Dictionary) -> void:
	var content := str(message.content)
	var segments: Array = message.get("segments", [])
	var signature := content + JSON.stringify(segments)
	if view.get("body_signature", "") == signature:
		return
	view.body_signature = signature
	var body: RichTextLabel = view.body
	if PalUi.is_mobile() or view.is_user or segments.is_empty():
		body.text = content
		return
	var parts := PackedStringArray()
	for segment: Dictionary in segments:
		parts.append(str(segment.get("display_text", "")))
	# Presentation metadata may arrive after the prose. It must reproduce the
	# original text exactly; never rebuild the reply from synthesized speech text.
	if "".join(parts) != content:
		body.text = content
		return
	body.clear()
	for index: int in range(segments.size()):
		var aside: bool = segments[index].get("say") == null
		body.push_color(PalUi.MUTED if aside else PalUi.TEXT)
		body.push_font_size(14 if aside else 16)
		body.add_text(parts[index])
		body.pop()
		body.pop()


func _resize_messages() -> void:
	if _scroll == null:
		return
	var width := maxf(120, _scroll.size.x - _scroll.get_v_scroll_bar().size.x - 2)
	for view: Dictionary in _message_views.values():
		view.card.custom_minimum_size.x = width * 0.88 if view.is_user else 0.0


func _scroll_to_end() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
		_new_messages.hide()


func _update_send_button() -> void:
	if _send_button != null:
		var continuation: bool = _input.text.strip_edges().is_empty() and _images.images().is_empty()
		_send_button.disabled = not _dialogue_enabled or _profile_id.is_empty() or _busy or _input.text.length() > 4000 or _images.is_importing()
		_send_button.text = ("继续" if continuation else "发送") if _dialogue_enabled else "已关闭"
		_send_button.tooltip_text = ("无需输入，让角色继续当前场景" if continuation else "发送当前对白或动作") + ("" if PalUi.is_mobile() else " · Ctrl + Enter 提交 · Enter 换行")
	if _action_button != null:
		_action_button.disabled = _profile_id.is_empty() or not _input.editable
	if _image_button != null:
		_image_button.disabled = not _images.can_add() or not _input.editable


func _insert_action() -> void:
	if not _input.editable:
		return
	_input.apply_ime()
	if _input.text.length() + 2 > 4000:
		_status.text = "加入动作括号后会超过 4000 字，请先缩短内容。"
		_status.show()
		return
	var selected := _input.get_selected_text()
	_input.begin_complex_operation()
	if _input.has_selection():
		_input.delete_selection()
	_input.insert_text_at_caret("（" + selected + "）")
	_input.set_caret_column(_input.get_caret_column() - 1)
	_input.end_complex_operation()
	_input.grab_focus()


func _on_input_event(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_V and _input.editable:
		if _images.paste_image():
			_input.accept_event()
			return
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed) and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if _input.has_ime_text():
			return
		_input.accept_event()
		if not _send_button.disabled:
			_send()


func _send() -> void:
	if not _dialogue_enabled or _images.is_importing():
		return
	user_activity.emit(_profile_id)
	_retry_error = ""
	var draft := _input.text
	var attachments: Array = _images.images()
	var error: String = service.call("SendImageMessage", _profile_id, draft, JSON.stringify(attachments))
	if error.is_empty():
		var data := _snapshot()
		_submitted[_profile_id + ":" + str(data.session_id)] = {"reply_id": str(data.messages[-1].id), "text": draft, "images": attachments}
		_input.text = ""
		_drafts.erase(_draft_key())
		_images.clear_after_send()
		_refresh()
	else:
		_status.text = error
		if not bool(_snapshot().get("has_key", false)):
			open_settings()
		_status.show()


func _restore_failed_draft(data: Dictionary) -> void:
	var key := _draft_key()
	if not _submitted.has(key) or bool(data.busy) or data.messages.is_empty():
		return
	var attempt: Dictionary = _submitted[key]
	var reply: Dictionary = data.messages[-1]
	if str(reply.id) != str(attempt.reply_id):
		_submitted.erase(key)
		return
	if str(reply.status) in ["failed", "interrupted"] and _input.text.is_empty() and _images.images().is_empty() and not _images.is_importing():
		_input.text = str(attempt.text)
		_drafts[key] = _input.text
		_images.restore_images(attempt.get("images", []))
	_submitted.erase(key)


func _stop() -> void:
	service.call("StopReply", _profile_id)
	_refresh()


func _retry() -> void:
	if not _dialogue_enabled:
		return
	user_activity.emit(_profile_id)
	if _retry_queued or _busy or _profile_id.is_empty():
		return
	_retry_queued = true
	_retry_error = ""
	_retry_button.disabled = true
	# Rebuilding the timeline from a button's input callback can remove the
	# focused sender mid-dispatch. Commit the retry on the next idle frame.
	_retry_deferred.call_deferred(_profile_id, _session_id)


func _retry_deferred(profile_id: String, session_id: String) -> void:
	_retry_queued = false
	if not _dialogue_enabled or profile_id != _profile_id or session_id != _session_id or _busy:
		return
	var draft := _input.text
	var last_user := ""
	var last_images: Array = []
	var previous: Array = _snapshot().get("messages", [])
	var continuation: bool = not previous.is_empty() and bool(previous[-1].get("is_continuation", false))
	for message: Dictionary in previous:
		if str(message.role) == "user":
			last_user = str(message.content)
			last_images = message.get("images", [])
	var result: Variant = service.call("RetryMessage", _profile_id)
	var error := str(result) if result is String else "重试未能开始，聊天服务没有返回有效结果。请稍后再试。"
	if error.is_empty():
		var data := _snapshot()
		if not data.get("messages", []).is_empty():
			_submitted[_draft_key()] = {"reply_id": str(data.messages[-1].id), "text": "" if continuation else last_user, "images": [] if continuation else last_images}
		if not continuation and draft.strip_edges() == last_user and _images.images() == last_images and not _images.is_importing():
			_input.text = ""
			_drafts.erase(_draft_key())
			_images.clear_after_send()
	_retry_error = error
	_refresh()
	_retry_button.disabled = not _dialogue_enabled or _busy
	if not error.is_empty():
		_status.text = error
		_status.show()


func _retry_save() -> void:
	var error: String = service.call("SaveConversation", _profile_id)
	_refresh()
	_status.text = "对话已保存。" if error.is_empty() else error


func _copy_message(message_id: String) -> void:
	for message: Dictionary in _snapshot().get("messages", []):
		if str(message.id) == message_id:
			DisplayServer.clipboard_set(str(message.content))
			if _message_views.has(message_id):
				var button: Button = _message_views[message_id].copy
				button.text = "已复制"
				await get_tree().create_timer(1.2).timeout
				if is_instance_valid(button):
					button.text = "复制"
			return


func _refresh_message_tools() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	for view: Dictionary in _message_views.values():
		var card: Control = view.card
		var tools_row: Control = view.tools
		var active := PalUi.is_mobile() or card.get_global_rect().has_point(card.get_global_mouse_position()) or (is_instance_valid(focused) and card.is_ancestor_of(focused))
		tools_row.modulate.a = 1.0 if active else 0.0
		for button: Control in tools_row.get_children():
			button.mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE


func _remember_message(message_id: String) -> void:
	var snapshot := _snapshot()
	for message: Dictionary in snapshot.get("messages", []):
		if str(message.id) == message_id:
			_navigate("memory", {"session_id": str(snapshot.session_id), "message_id": message_id, "text": str(message.content)})
			return


func _show_memory_source(_id: String, session_id: String, message_id: String) -> void:
	var error: String = service.call("SelectConversation", _profile_id, session_id)
	if not error.is_empty():
		_status.text = error
		return
	_refresh()
	reveal_requested.emit()
	_scroll_revision += 1
	var revision := _scroll_revision
	_restoring_scroll = true
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _scroll_revision or session_id != _session_id:
		return
	if _message_views.has(message_id):
		_scroll.ensure_control_visible(_message_views[message_id].body)
	else:
		_status.text = "来源在较早的消息中，请打开完整记录查看。"
	_restoring_scroll = false
	save_view_state()


func open_settings() -> void:
	_navigate("settings")


func _new_conversation() -> void:
	_navigate("new")


func _open_memory() -> void:
	_navigate("memory")


func _open_world() -> void:
	_navigate("world")


func _navigate(page_id: String, context: Dictionary = {}) -> void:
	context["return_focus"] = get_viewport().gui_get_focus_owner()
	navigation_requested.emit(page_id, _profile_id, context)


func _export_records() -> void:
	var profile := _profile_id
	PalPackageFiles.export_package(self, service, profile, "conversations", _session_id, {}, false, false, func(message: String) -> void:
		if _profile_id == profile:
			_status.text = message
			_status.show())


func _open_markdown() -> void:
	var data := _snapshot()
	if data.is_empty():
		return
	var error: String = service.call("SaveConversation", _profile_id)
	if not error.is_empty():
		_status.text = error
		return
	if PalUi.is_mobile():
		if bool(data.get("has_images", false)):
			_export_records()
		else:
			PalMobileFiles.export_record(self, str(data.path), func(message: String) -> void: _status.text = message; _status.show())
	elif DisplayServer.get_name() != "headless":
		OS.shell_open(str(data.path))
