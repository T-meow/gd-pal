class_name PalMobileHall
extends PalCompanionHall
## A single foreground stage. Rotation only rearranges the existing conversation.

signal framing_changed(mode: String)

var _safe := Rect2()
var _portrait := true
var _top: PanelContainer
var _bottom: HBoxContainer
var _drawer_header: HBoxContainer
var _roster_shade: ColorRect
var _roster_sheet: PanelContainer
var _roster_list: VBoxContainer
var _more: MenuButton
var _partner_button: Button
var _chat_button: Button
var _scope: Label
var _last_geometry := ""
var _orientation_locked := false
var _framing_toggle: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var room := TextureRect.new()
	room.texture = preload("res://assets/ui/afternoon_study.svg")
	room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(room)
	surface = SubViewportContainer.new()
	surface.stretch = true
	surface.clip_contents = true
	surface.gui_input.connect(_touch_character)
	add_child(surface)
	_build_touch_regions()
	_build_bubbles()
	_top = _card(self, 8)
	_header = HBoxContainer.new()
	_top.add_child(_header)
	_close_button = PalUi.button("‹", _header, func() -> void: show_partners(true))
	_close_button.tooltip_text = "我的伙伴"
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(title)
	_name = PalUi.label("GD Pal", title, 20)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_state = PalUi.label("陪你度过今天", title, 12, true)
	_state.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_framing_toggle = PalUi.button("全身", _header, func() -> void:
		portrait_framing_requested.emit("full_body" if _portrait_framing == "call" else "call"))
	_framing_toggle.add_theme_font_size_override("font_size", 12)
	_partner_button = PalUi.icon_button("", "profile", _header, func() -> void: show_partners(true))
	_partner_button.tooltip_text = "切换伙伴"
	_more = MenuButton.new()
	_more.text = "···"
	_more.custom_minimum_size = Vector2(48, 48)
	_more.tooltip_text = "更多功能"
	_header.add_child(_more)
	var menu := _more.get_popup()
	for caption: String in ["伙伴档案", "手动记忆", "世界设定", "历史会话", "连接设置", "锁定 / 解锁旋转", "主题与外观", "番茄钟 / 挂机"]:
		menu.add_item(caption)
	menu.add_item("AI 整理", 8)
	menu.add_item("导入数据包", 9)
	menu.add_check_item("显示触控范围", 10)
	menu.about_to_popup.connect(func() -> void: menu.set_item_checked(menu.get_item_index(10), PalUi.show_touch_regions))
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 5:
			_orientation_locked = not _orientation_locked
			if OS.has_feature("android"):
				DisplayServer.screen_set_orientation((DisplayServer.SCREEN_PORTRAIT if _portrait else DisplayServer.SCREEN_LANDSCAPE) if _orientation_locked else DisplayServer.SCREEN_SENSOR)
			set_notice("已锁定当前方向" if _orientation_locked else "已恢复自动旋转")
		elif id == 6:
			page_requested.emit("appearance")
		elif id == 7:
			toggle_pomodoro()
		elif id == 8:
			page_requested.emit("summary")
		elif id == 9:
			page_requested.emit("packages")
		elif id == 10:
			touch_regions_requested.emit(not PalUi.show_touch_regions)
		else:
			page_requested.emit(["profile", "memory", "world", "sessions", "settings"][id])
	)
	_scope = PalUi.label("日常陪伴", self, 13, true)
	_scope.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav = VBoxContainer.new()
	add_child(_nav)
	for item: Array in [["profile", "伙伴档案"], ["memory", "手动记忆"], ["world", "世界设定"]]:
		var page: String = item[0]
		var button := PalUi.icon_button("", page, _nav, func() -> void: page_requested.emit(page))
		button.tooltip_text = str(item[1])
		_buttons[page] = button
	_subtitle = PalUi.label("", self, 16)
	_subtitle.hide()
	_bottom = HBoxContainer.new()
	_bottom.add_theme_constant_override("separation", 12)
	add_child(_bottom)
	var text_button := PalUi.icon_button("文字", "chat", _bottom, func() -> void:
		set_history_visible(true)
		if panel != null:
			panel.focus_input()
	)
	text_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_interactions = Button.new()
	_interactions.text = "动作 / 衣装"
	_interactions.custom_minimum_size = Vector2(64, 56)
	_interactions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom.add_child(_interactions)
	_interactions.pressed.connect(_open_character_wheel)
	_chat_button = PalUi.button("完整对话", _bottom, func() -> void: set_history_visible(not history_visible), true)
	_chat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var end := PalUi.button("结束", _bottom, func() -> void: page_requested.emit("end"))
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PalUi.danger(end)
	PalUi.overlay_controls(_bottom)
	add_to_group("pal_overlay_hosts")
	_sidebar = _card(self, 10)
	_sidebar.add_theme_stylebox_override("panel", PalUi.glass(0.5, 20, 10))
	_history_slot = VBoxContainer.new()
	_sidebar.add_child(_history_slot)
	_drawer_header = HBoxContainer.new()
	_history_slot.add_child(_drawer_header)
	PalUi.label("完整对话", _drawer_header, 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PalUi.icon_button("", "history", _drawer_header, func() -> void: page_requested.emit("sessions")).tooltip_text = "历史会话"
	PalUi.icon_button("", "add", _drawer_header, func() -> void: page_requested.emit("new")).tooltip_text = "新对话"
	PalUi.icon_button("", "close", _drawer_header, func() -> void: set_history_visible(false)).tooltip_text = "收起对话"
	_empty = _card(self, 18)
	var empty_column := VBoxContainer.new()
	_empty.add_child(empty_column)
	_empty_title = PalUi.label("今天，想和谁一起？", empty_column, 21)
	_empty_text = PalUi.hint("选择伙伴，开始安静陪伴或文字聊天。", empty_column)
	_empty_action = PalUi.button("选择伙伴", empty_column, func() -> void: show_partners(true), true)
	_notice = PalUi.hint("", self)
	_notice.add_theme_stylebox_override("normal", PalUi.panel(PalUi.PAPER, 8, 8))
	_notice.hide()
	_roster_shade = ColorRect.new()
	_roster_shade.color = Color(0.1, 0.2, 0.32, 0.35)
	_roster_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_roster_shade)
	_roster_shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			show_partners(false)
			_roster_shade.accept_event()
	)
	_roster_sheet = _card(self, 16)
	var roster_column := VBoxContainer.new()
	_roster_sheet.add_child(roster_column)
	var roster_header := HBoxContainer.new()
	roster_column.add_child(roster_header)
	PalUi.label("我的伙伴", roster_header, 22).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PalUi.icon_button("", "close", roster_header, func() -> void: show_partners(false))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_column.add_child(scroll)
	_roster_list = VBoxContainer.new()
	_roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_list)
	_add_button = PalUi.button("添加伙伴", roster_column, func() -> void:
		show_partners(false)
		page_requested.emit("add")
	, true)
	_connection = PalUi.button("连接设置", roster_column, func() -> void:
		show_partners(false)
		page_requested.emit("settings")
	)
	_build_pomodoro()
	show_partners(false)
	resized.connect(_layout)
	_layout()


func _card(parent: Node, margin: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", PalUi.glass(0.96, 20, margin))
	parent.add_child(card)
	return card


func show_partners(value: bool) -> void:
	_roster_shade.visible = value
	_roster_sheet.visible = value
	_layout()


func update_roster(entries: Array, selected_id: String, can_add: bool) -> void:
	for child: Node in _roster_list.get_children():
		_roster_list.remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries:
		var id := str(entry.id)
		var row := HBoxContainer.new()
		_roster_list.add_child(row)
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(48, 48)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = entry.get("portrait") if entry.get("portrait") != null else preload("res://icon.svg")
		row.add_child(portrait)
		var button := PalUi.button(str(entry.name), row, func() -> void:
			show_partners(false)
			profile_selected.emit(id)
		, id == selected_id)
		button.clip_text = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(entry.name)
		var status := "陪伴中" if id == selected_id and _empty_mode == "hall" else "休息中"
		var count := int(entry.get("unread", 0))
		PalUi.label(status + (" · %d 条未读" % count if count > 0 else ""), row, 12, true)
		if id == selected_id:
			_chat_button.text = "对话 · %d" % count if count > 0 else "完整对话"
	_add_button.disabled = not can_add


func attach_conversation(conversation: PalConversationPanel) -> void:
	if is_instance_valid(panel) and panel != conversation:
		detach_conversation()
	panel = conversation
	panel.reparent(_history_slot, false)
	panel.restore_composer()
	panel.show()
	if not panel.presentation_changed.is_connected(_on_presentation):
		panel.presentation_changed.connect(_on_presentation)
	if not panel.bubbles_changed.is_connected(_on_bubbles):
		panel.bubbles_changed.connect(_on_bubbles)
	panel._refresh()
	show_presence("hall")


func detach_conversation() -> void:
	if is_instance_valid(panel):
		panel.save_view_state()
		if panel.presentation_changed.is_connected(_on_presentation):
			panel.presentation_changed.disconnect(_on_presentation)
		if panel.bubbles_changed.is_connected(_on_bubbles):
			panel.bubbles_changed.disconnect(_on_bubbles)
	panel = null
	_on_bubbles("", "")
	set_history_visible(false)


func show_presence(mode: String, _display_name: String = "") -> void:
	_empty_mode = mode
	_empty.visible = mode != "hall"
	_bottom.visible = mode == "hall"
	_nav.visible = mode == "hall" and not _portrait
	if mode != "hall":
		set_history_visible(false)
		_name.text = "GD Pal"
		_state.text = "选择一位伙伴"
	_layout()


func set_history_visible(value: bool) -> void:
	if is_instance_valid(panel):
		panel.save_view_state()
	history_visible = value and is_instance_valid(panel)
	if not history_visible:
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus) and panel != null and panel.is_ancestor_of(focus):
			focus.release_focus()
		DisplayServer.virtual_keyboard_hide()
	_layout()
	if history_visible:
		panel.restore_view_state()
	history_visibility_changed.emit(history_visible)


func set_connection(configured: bool, state: String = "configured") -> void:
	_connection.text = "连接设置 · " + (str({"verified": "测试成功", "testing": "测试中", "failed": "测试失败"}.get(state, "已配置")) if configured else "未配置")


func _on_presentation(display_name: String, state: String, preview: String) -> void:
	_name.text = display_name
	_state.text = state
	_subtitle.text = preview if not preview.is_empty() else "今天也陪着你。"
	_scope.text = "日常陪伴"


func refresh_overlay() -> void:
	if _bottom != null:
		PalUi.overlay_controls(_bottom)
	_layout_bubbles()


func character_mode() -> String:
	return _portrait_framing


func back() -> bool:
	if _roster_sheet.visible:
		show_partners(false)
		return true
	if history_visible:
		set_history_visible(false)
		return true
	return false


func _layout() -> void:
	if _roster_sheet == null:
		return
	_layout_pomodoro()
	var area := PalUi.mobile_rect(self)
	var portrait := size.y >= size.x
	if OS.has_feature("android"):
		# adjustResize may make a portrait window shorter than it is wide.
		# Physical display orientation remains stable while the IME is open.
		var display := DisplayServer.screen_get_size()
		portrait = display.y >= display.x
	var keyboard := PalUi.keyboard_height() > 0 or area.size.y < PalUi.mobile_rect(self, false).size.y - 40
	var signature := str([area, portrait, history_visible, keyboard, _empty_mode, _portrait_framing, PalUi.dialogue_bubbles])
	if signature == _last_geometry:
		return
	_last_geometry = signature
	if panel != null:
		panel.save_view_state()
	_safe = area
	var changed := _portrait != portrait
	_portrait = portrait
	var inset := area.grow(-12)
	_top.position = inset.position
	_top.size = Vector2(inset.size.x, 64)
	_top.visible = not (keyboard and not portrait and history_visible)
	_framing_toggle.text = "全身" if _portrait_framing == "call" else "近景"
	_framing_toggle.tooltip_text = "切换为全身立绘" if _portrait_framing == "call" else "切换为通话近景"
	_framing_toggle.disabled = not _display_available
	_scope.position = inset.position + Vector2(8, 72)
	_scope.size = Vector2(inset.size.x - 16, 22)
	_scope.visible = _top.visible
	_sidebar.visible = history_visible
	if portrait:
		var top: float = inset.position.y + (76.0 if keyboard else maxf(220, inset.size.y * 0.58))
		_sidebar.position = Vector2(inset.position.x, top)
		_sidebar.size = Vector2(inset.size.x, maxf(150, inset.end.y - top))
	elif keyboard:
		_sidebar.position = inset.position
		_sidebar.size = inset.size
	else:
		var width := clampf(inset.size.x * 0.40, 300, 340)
		_sidebar.position = Vector2(inset.end.x - width, inset.position.y + 76)
		_sidebar.size = Vector2(width, inset.size.y - 76)
	var stage := Rect2(inset.position, inset.size)
	if history_visible and not portrait and not keyboard:
		stage.size.x -= clampf(inset.size.x * 0.40, 300, 340) + 12
	var bubble_bottom := _sidebar.position.y - 8 if history_visible and portrait else inset.end.y - 68
	_bubble_area = Rect2(stage.position + Vector2(0, 100), Vector2(stage.size.x, maxf(0, bubble_bottom - stage.position.y - 100)))
	_layout_character_surface(stage)
	surface.visible = _empty_mode == "hall" and stage.size.y >= 150 and not (keyboard and not portrait)
	_bottom.position = Vector2(inset.position.x, inset.end.y - 56)
	_bottom.size = Vector2(stage.size.x, 56)
	_bottom.visible = not history_visible and _empty_mode == "hall"
	_nav.position = inset.position + Vector2(0, 100)
	_nav.size = Vector2(48, 160)
	_nav.visible = not portrait and not keyboard and _empty_mode == "hall"
	_empty.size = Vector2(minf(340, inset.size.x), 180)
	_empty.position = area.get_center() - _empty.size * 0.5
	_notice.position = inset.position + Vector2(0, 94)
	_notice.size = Vector2(inset.size.x, 44)
	_roster_sheet.size = Vector2(minf(440, inset.size.x), minf(560, inset.size.y))
	_roster_sheet.position = area.get_center() - _roster_sheet.size * 0.5
	if changed:
		framing_changed.emit(character_mode())
	if panel != null and history_visible:
		panel.set_mobile_compact(keyboard and not portrait)
		panel.restore_view_state()


func _process(_delta: float) -> void:
	_layout()
	_layout_bubbles()


func _touch_character(event: InputEvent) -> void:
	super._touch_character(event)


func _input(_event: InputEvent) -> void:
	pass


func _unhandled_key_input(_event: InputEvent) -> void:
	pass
