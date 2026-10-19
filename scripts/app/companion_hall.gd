class_name PalCompanionHall
extends Control

signal profile_selected(profile_id: String)
signal page_requested(page_id: String)
signal desktop_requested
signal action_requested(action: String)
signal close_requested
signal chat_width_changed(value: float)
signal character_pressed(position: Vector2)
signal room_changed(room_id: String)
signal history_visibility_changed(value: bool)
signal view_changed(view_id: String)
signal voice_requested
signal desktop_preference_requested(key: String, value: Variant)
signal visual_requested(visual_id: String)
signal portrait_framing_requested(mode: String)
signal touch_regions_requested(value: bool)

const TOUCH_REGIONS := preload("res://scripts/app/touch_regions.gd")

# Shared fields are retained for the mobile host, which supplies its own layout.
var surface: SubViewportContainer
var history_visible := false
var overlay_history := false
var panel: PalConversationPanel
var _header: HBoxContainer
var _rail: PanelContainer
var _partners: VBoxContainer
var _add_button: Button
var _nav: VBoxContainer
var _sidebar: PanelContainer
var _history_slot: VBoxContainer
var _footer: PanelContainer
var _footer_column: VBoxContainer
var _composer_slot: VBoxContainer
var _name: Label
var _state: Label
var _subtitle: Label
var _full_text: Button
var _desktop_button: Button
var _interactions: Button
var _character_wheel: PalCharacterWheel
var _character_pet: PalPetInstance
var motion_actions := PackedStringArray()
var motion_definitions: Dictionary = {}
var _connection: Button
var _close_button: Button
var _empty: PanelContainer
var _empty_title: Label
var _empty_text: Label
var _empty_action: Button
var _notice: Label
var _buttons: Dictionary = {}
var _empty_mode := "empty"
var _history_focus: Control
var chat_width := 360.0
var _reply_row: HBoxContainer
var _resize_grip: Control
var _resizing := false

var current_view := "call"
var _history_preferred := true
var _room_stage: PalRoomStage
var _rooms_page: PalRoomsPage
var _desktop_page: PalDesktopPage
var _monitor_page: Control
var _top_background: Panel
var _tabs: HBoxContainer
var _tab_buttons: Dictionary = {}
var _brand_hint: Label
var _stage_kicker: Label
var _stage_caption: Label
var _stage_location: Label
var _stage_shade: TextureRect
var _chat_toggle: Button
var _voice: Button
var _focus: Button
var _context: Button
var _roster_menu: MenuButton
var _roster_ids: Array[String] = []
var _window_resize: Button
var _display_controls: HBoxContainer
var _display_buttons: Dictionary = {}
var _selected_visual := "sprite2d"
var _portrait_framing := "call"
var _display_available := false
var pomodoro: PalPomodoroPanel
var _pomodoro_button: Button
var _dialogue_bubble: PalDialogueBubble
var _description_bubble: PalDialogueBubble
var _bubble_area := Rect2()
var _touch_regions: Control
var _touch_toggle: Button
var _touch_pressed := false
var _touch_press_position := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = PalUi.PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_room_stage = PalRoomStage.new()
	add_child(_room_stage)
	_stage_shade = TextureRect.new()
	_stage_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var shade_texture := GradientTexture2D.new()
	shade_texture.gradient = Gradient.new()
	shade_texture.gradient.colors = PackedColorArray([Color(0.04, 0.06, 0.1, 0.1), Color(0.04, 0.06, 0.1, 0.0), Color(0.04, 0.06, 0.1, 0.7)])
	shade_texture.gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	shade_texture.fill_from = Vector2(0, 0)
	shade_texture.fill_to = Vector2(0, 1)
	_stage_shade.texture = shade_texture
	add_child(_stage_shade)
	surface = SubViewportContainer.new()
	surface.stretch = true
	surface.clip_contents = true
	surface.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	surface.gui_input.connect(_touch_character)
	add_child(surface)
	_build_touch_regions()
	_build_bubbles()
	_build_header()
	_build_rail()
	_build_stage()
	_build_sidebar()
	_rooms_page = PalRoomsPage.new()
	add_child(_rooms_page)
	_rooms_page.configure(_room_stage.rooms, "")
	_rooms_page.room_selected.connect(select_room)
	_rooms_page.return_requested.connect(func() -> void: show_view("call"))
	_desktop_page = PalDesktopPage.new()
	add_child(_desktop_page)
	_desktop_page.desktop_requested.connect(func() -> void: desktop_requested.emit())
	_desktop_page.page_requested.connect(func(page: String) -> void: page_requested.emit(page))
	_desktop_page.profile_selected.connect(func(id: String) -> void: profile_selected.emit(id))
	_desktop_page.preference_requested.connect(func(key: String, value: Variant) -> void: desktop_preference_requested.emit(key, value))
	_desktop_page.return_requested.connect(func() -> void: show_view("call"))
	if OS.get_name() == "Windows":
		_monitor_page = preload("res://scripts/monitoring/PcMonitorPanel.cs").new()
		add_child(_monitor_page)
		_monitor_page.hide()
	_notice = PalUi.hint("", self)
	_notice.add_theme_color_override("font_color", PalUi.ERROR)
	_notice.add_theme_font_size_override("font_size", 12)
	_notice.max_lines_visible = 2
	_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_notice.hide()
	_window_resize = Button.new()
	_window_resize.text = "◢"
	_window_resize.flat = true
	_window_resize.focus_mode = Control.FOCUS_NONE
	_window_resize.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_window_resize.tooltip_text = "调整窗口大小"
	_window_resize.add_theme_font_size_override("font_size", 11)
	_window_resize.modulate.a = 0.45
	_window_resize.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and DisplayServer.get_name() != "headless":
			DisplayServer.window_start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, get_window().get_window_id())
	)
	add_child(_window_resize)
	_build_pomodoro()
	select_room(str(_room_stage.rooms[0].id), false)
	resized.connect(_layout)
	_layout()
	add_to_group("pal_overlay_hosts")
	refresh_overlay()


func _build_touch_regions() -> void:
	_touch_regions = TOUCH_REGIONS.new()
	_touch_regions.surface = surface
	add_child(_touch_regions)
	add_to_group("pal_touch_hosts")


func touch_region_at(point: Vector2, nearest: bool = false) -> String:
	return _touch_regions.region_at(point, nearest) if _touch_regions != null else ""


func refresh_touch_regions() -> void:
	if _touch_toggle != null:
		_touch_toggle.set_pressed_no_signal(PalUi.show_touch_regions)
	if _touch_regions != null:
		_touch_regions.refresh()


func _build_bubbles() -> void:
	_dialogue_bubble = PalDialogueBubble.new()
	add_child(_dialogue_bubble)
	_description_bubble = PalDialogueBubble.new()
	add_child(_description_bubble)
	for bubble: PalDialogueBubble in [_dialogue_bubble, _description_bubble]:
		bubble.page_requested.connect(func(direction: int) -> void:
			if is_instance_valid(panel):
				panel.navigate_bubbles(direction))


func _on_bubbles(dialogue: String, description: String, index: int = 0, total: int = 0) -> void:
	_dialogue_bubble.set_text(dialogue)
	_description_bubble.set_text(description, true)
	_dialogue_bubble.set_navigation(index, total)
	_description_bubble.set_navigation(index, total)
	_layout_bubbles()


func _layout_bubbles() -> void:
	if _dialogue_bubble == null:
		return
	var dialogue_enabled := _character_pet != null and _character_pet.profile.desktop_dialogue_enabled
	var available := dialogue_enabled and _empty_mode == "hall" and current_view in ["call", "performance"] and surface.visible and _bubble_area.size.y >= 150
	_dialogue_bubble.visible = available and _dialogue_bubble.has_text() and _dialogue_bubble.is_enabled()
	_description_bubble.visible = available and _description_bubble.has_text() and _description_bubble.is_enabled()
	if not available:
		return
	if current_view == "performance":
		_dialogue_bubble.fit(_bubble_area.size.x, minf(150, _bubble_area.size.y * 0.3))
		_description_bubble.fit(_bubble_area.size.x, minf(110, _bubble_area.size.y * 0.2))
		_dialogue_bubble.position = _bubble_area.position
		_description_bubble.position = Vector2(_bubble_area.position.x, _bubble_area.end.y - _description_bubble.size.y)
		return
	var character := Rect2(surface.position, surface.size)
	var close_up := _portrait_framing == "call" or _selected_visual == "vrm3d"
	for child: Node in surface.get_children():
		if child is PalPetInstance and child.presenter != null:
			close_up = child.presentation_mode == "call"
			var bounds: Rect2 = child.presenter.get_interaction_rect()
			var factor := surface.size / Vector2(child.size).max(Vector2.ONE)
			character = Rect2(surface.position + bounds.position * factor, bounds.size * factor)
			break
	var center := character.get_center().x
	_dialogue_bubble.fit(minf(440, _bubble_area.size.x), minf(132, _bubble_area.size.y * 0.25))
	_description_bubble.fit(minf(400, _bubble_area.size.x), minf(100, _bubble_area.size.y * 0.20))
	var upper := _bubble_area.position.y
	var lower := _bubble_area.end.y
	_dialogue_bubble.position = Vector2(
		clampf(center - _dialogue_bubble.size.x * 0.5, _bubble_area.position.x, _bubble_area.end.x - _dialogue_bubble.size.x),
		clampf(character.position.y - _dialogue_bubble.size.y - 12 if close_up else character.position.y + 12, upper, lower - _dialogue_bubble.size.y))
	_description_bubble.position = Vector2(
		clampf(center - _description_bubble.size.x * 0.5, _bubble_area.position.x, _bubble_area.end.x - _description_bubble.size.x),
		clampf(character.end.y - _description_bubble.size.y - 12, upper, lower - _description_bubble.size.y))


func _layout_character_surface(stage: Rect2) -> void:
	# Floating bubbles overlay the character instead of reducing its height.
	surface.position = stage.position
	surface.size = stage.size


func _process(_delta: float) -> void:
	_layout_bubbles()


func _build_header() -> void:
	_top_background = Panel.new()
	_top_background.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 0, 0))
	_top_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_background)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 12)
	add_child(_header)
	var mark := TextureRect.new()
	mark.texture = preload("res://assets/ui/pal_mark.svg")
	mark.custom_minimum_size = Vector2(28, 28)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header.add_child(mark)
	var brand := PalUi.label("GD PAL", _header, 17)
	brand.mouse_filter = Control.MOUSE_FILTER_STOP
	brand.gui_input.connect(_drag_window)
	_brand_hint = PalUi.label("属于你们的片刻", _header, 11, true)
	_brand_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_brand_hint.gui_input.connect(_drag_window)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_STOP
	spacer.gui_input.connect(_drag_window)
	_header.add_child(spacer)
	_pomodoro_button = PalUi.button("番茄钟", _header, toggle_pomodoro)
	_pomodoro_button.add_theme_font_size_override("font_size", 11)
	_pomodoro_button.tooltip_text = "打开番茄钟与挂机陪伴"
	PalUi.quiet(_pomodoro_button)
	_connection = PalUi.icon_button("模型", "connection", _header, func() -> void: page_requested.emit("settings"))
	_connection.add_theme_font_size_override("font_size", 11)
	PalUi.quiet(_connection)
	var minimize := PalUi.button("—", _header, func() -> void: get_window().mode = Window.MODE_MINIMIZED)
	minimize.tooltip_text = "最小化，继续陪伴"
	PalUi.quiet(minimize)
	var maximize := PalUi.button("□", _header, func() -> void: get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_MAXIMIZED else Window.MODE_MAXIMIZED)
	maximize.tooltip_text = "最大化 / 还原"
	PalUi.quiet(maximize)
	_close_button = PalUi.icon_button("", "close", _header, func() -> void: close_requested.emit())
	_close_button.tooltip_text = "退出 GD Pal"
	PalUi.quiet(_close_button)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 4)
	add_child(_tabs)
	var tabs: Array = [["call", "通话", "call"], ["rooms", "房间", "room"], ["desktop", "桌宠", "desktop"]]
	if OS.get_name() == "Windows":
		tabs.append(["performance", "性能", "performance"])
	for item: Array in tabs:
		var id: String = item[0]
		var button := PalUi.icon_button(item[1], item[2], _tabs, func() -> void: show_view(id))
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size = Vector2(86, 34)
		_tab_buttons[id] = button


func _build_pomodoro() -> void:
	pomodoro = PalPomodoroPanel.new()
	add_child(pomodoro)
	pomodoro.status_changed.connect(func(text: String) -> void:
		if _pomodoro_button != null:
			_pomodoro_button.text = text)


func toggle_pomodoro() -> void:
	if pomodoro == null:
		return
	pomodoro.visible = not pomodoro.visible
	_layout_pomodoro()


func _layout_pomodoro() -> void:
	if pomodoro == null:
		return
	var area := PalUi.mobile_rect(self) if PalUi.is_mobile() else Rect2(Vector2.ZERO, size)
	pomodoro.size = Vector2(minf(360, area.size.x - 24), minf(465, area.size.y - 88))
	pomodoro.position = Vector2(area.end.x - pomodoro.size.x - 12, area.position.y + 68)


func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 0, 7))
	add_child(_rail)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_rail.add_child(column)
	_partners = VBoxContainer.new()
	column.add_child(_partners)
	_roster_menu = MenuButton.new()
	_roster_menu.icon = preload("res://assets/ui/pal_mark.svg")
	_roster_menu.expand_icon = true
	_roster_menu.add_theme_constant_override("icon_max_width", 34)
	_roster_menu.custom_minimum_size = Vector2(48, 50)
	_roster_menu.tooltip_text = "切换伙伴"
	_partners.add_child(_roster_menu)
	_roster_menu.get_popup().id_pressed.connect(func(id: int) -> void:
		if id == 100:
			page_requested.emit("add")
		elif id == 101:
			page_requested.emit("recall_all")
		elif id >= 0 and id < _roster_ids.size():
			profile_selected.emit(_roster_ids[id])
	)
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 8)
	column.add_child(_nav)
	for item: Array in [["history", "对话", "chat"], ["profile", "角色", "profile"], ["world", "剧情", "world"], ["memory", "回忆", "memory"]]:
		var page: String = item[0]
		var button := _rail_button(item[1], item[2], _nav, func() -> void: page_requested.emit(page))
		_buttons[page] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	_add_button = _rail_button("添加", "add", column, func() -> void: page_requested.emit("add"))
	_rail_button("主题", "spark", column, func() -> void: page_requested.emit("appearance"))
	if OS.get_name() == "Windows":
		_rail_button("Agent", "desktop", column, func() -> void: page_requested.emit("agent"))
	_rail_button("设置", "settings", column, func() -> void: page_requested.emit("settings"))


func _rail_button(caption: String, icon_name: String, parent: Node, callback: Callable) -> Button:
	var button := PalUi.button("", parent, callback)
	button.custom_minimum_size = Vector2(48, 56)
	button.tooltip_text = caption
	PalUi.quiet(button)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 7
	column.offset_bottom = -5
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	var image := TextureRect.new()
	image.texture = load("res://assets/ui/icons/" + icon_name + ".svg")
	image.custom_minimum_size = Vector2(20, 20)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.modulate = PalUi.ACCENT
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(image)
	var label := PalUi.label(caption, column, 10, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button


func _build_stage() -> void:
	_stage_kicker = PalUi.label("● 此刻，与你", self, 11, true)
	_name = PalUi.label("今天，想和谁相见？", self, 29)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_state = PalUi.label("", self, 12, true)
	_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stage_caption = PalUi.label("", self, 12, true)
	_stage_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_stage_location = PalUi.label("", self, 12, true)
	_stage_location.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_focus = PalUi.icon_button("", "panel", self, func() -> void: set_history_visible(not history_visible))
	_focus.tooltip_text = "展开角色画面 / 恢复对话"
	PalUi.quiet(_focus)
	_display_controls = HBoxContainer.new()
	_display_controls.add_theme_constant_override("separation", 5)
	add_child(_display_controls)
	for entry: Array in [["sprite2d", "2D"], ["vrm3d", "3D"], ["full_body", "全身"], ["call", "通话近景"]]:
		var id: String = entry[0]
		var button := PalUi.button(entry[1], _display_controls, func() -> void:
			if id in ["sprite2d", "vrm3d"]:
				visual_requested.emit(id)
			else:
				portrait_framing_requested.emit(id)
		)
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size.y = 32
		_display_buttons[id] = button
	_touch_toggle = PalUi.button("触控范围", _display_controls, func() -> void: touch_regions_requested.emit(_touch_toggle.button_pressed))
	_touch_toggle.toggle_mode = true
	_touch_toggle.set_pressed_no_signal(PalUi.show_touch_regions)
	_touch_toggle.custom_minimum_size.y = 32
	_touch_toggle.add_theme_font_size_override("font_size", 12)
	_touch_toggle.tooltip_text = "显示角色附近的触控圆圈；圈外点击播放下一条已解析对话。"
	_footer = PanelContainer.new()
	_footer.add_theme_stylebox_override("panel", PalUi.glass(0.88, 14, 8))
	add_child(_footer)
	_footer_column = VBoxContainer.new()
	_footer.add_child(_footer_column)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer_column.add_child(controls)
	_interactions = Button.new()
	_interactions.text = "动作 / 衣装"
	_interactions.tooltip_text = "触控仅限头部、肩部和手边的小圆区；圈外点击继续对话。可用「触控范围」开关显示圆圈。"
	_interactions.icon = preload("res://assets/ui/icons/spark.svg")
	_interactions.expand_icon = true
	_interactions.add_theme_constant_override("icon_max_width", 18)
	_interactions.add_theme_font_size_override("font_size", 12)
	_interactions.custom_minimum_size.y = 46
	controls.add_child(_interactions)
	PalUi.quiet(_interactions)
	_interactions.pressed.connect(_open_character_wheel)
	_voice = PalUi.icon_button("", "muted", controls, func() -> void: voice_requested.emit())
	_voice.tooltip_text = "开关当前伙伴的自动朗读；语音服务在连接设置中配置"
	var room_button := PalUi.icon_button("房间", "room", controls, func() -> void: show_view("rooms"))
	_desktop_button = PalUi.icon_button("桌面", "desktop", controls, func() -> void: desktop_requested.emit())
	_chat_toggle = PalUi.icon_button("", "chat", controls, func() -> void: set_history_visible(not history_visible))
	for button: Button in [_voice, room_button, _desktop_button, _chat_toggle]:
		button.add_theme_font_size_override("font_size", 12)
		button.custom_minimum_size.y = 46
		PalUi.quiet(button)
	_full_text = _chat_toggle
	_subtitle = PalUi.label("", self, 12, true)
	_subtitle.hide()
	_composer_slot = VBoxContainer.new()
	_composer_slot.hide()
	add_child(_composer_slot)
	_empty = PanelContainer.new()
	_empty.add_theme_stylebox_override("panel", PalUi.glass(0.84, 14, 26))
	add_child(_empty)
	var empty_column := VBoxContainer.new()
	empty_column.add_theme_constant_override("separation", 15)
	_empty.add_child(empty_column)
	_empty_title = PalUi.label("让陪伴从这里开始", empty_column, 24)
	_empty_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_text = PalUi.hint("添加一位伙伴，一起度过今天。", empty_column)
	_empty_action = PalUi.icon_button("添加伙伴", "add", empty_column, func() -> void:
		if _empty_mode == "desktop":
			desktop_requested.emit()
		else:
			page_requested.emit("add")
	, true)


func _build_sidebar() -> void:
	_sidebar = PanelContainer.new()
	_sidebar.add_theme_stylebox_override("panel", PalUi.glass(0.5, 0, 20))
	add_child(_sidebar)
	_history_slot = VBoxContainer.new()
	_history_slot.add_theme_constant_override("separation", 14)
	_sidebar.add_child(_history_slot)
	PalUi.label("A MOMENT TOGETHER", _history_slot, 9, true)
	var heading := HBoxContainer.new()
	_history_slot.add_child(heading)
	PalUi.label("完整对话", heading, 18).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: Array in [["history", "sessions", "历史会话"], ["add", "new", "新对话"], ["panel", "collapse", "收起对话栏"]]:
		var page: String = item[1]
		var button := PalUi.icon_button("", item[0], heading, func() -> void:
			if page == "collapse":
				set_history_visible(false)
			else:
				page_requested.emit(page)
		)
		button.custom_minimum_size = Vector2(28, 30)
		button.tooltip_text = item[2]
		button.add_theme_constant_override("icon_max_width", 16)
		PalUi.quiet(button)
	_context = PalUi.icon_button("", "world", _history_slot, func() -> void: page_requested.emit("world"))
	_context.custom_minimum_size.y = 51
	_context.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_context.add_theme_font_size_override("font_size", 12)
	_context.clip_text = true
	_context.add_theme_stylebox_override("normal", PalUi.panel(Color(PalUi.YELLOW, 0.06), 9, 10))
	_context.add_theme_color_override("font_color", PalUi.YELLOW)
	_context.add_theme_color_override("icon_normal_color", PalUi.YELLOW)
	_resize_grip = Control.new()
	_resize_grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_resize_grip.tooltip_text = "拖动调整对话栏宽度"
	_resize_grip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_resizing = event.pressed
			if not _resizing:
				chat_width_changed.emit(chat_width)
			_resize_grip.accept_event()
	)
	add_child(_resize_grip)


func configure_preferences(room_id: String, chat_open: bool) -> void:
	_history_preferred = chat_open
	var chosen := room_id if not _room_stage.find_room(room_id).is_empty() else str(_room_stage.rooms[0].id)
	select_room(chosen, false)


func select_room(id: String, notify: bool = true) -> void:
	var error := _room_stage.select_room(id)
	if not error.is_empty():
		set_notice(error)
		return
	var room := _room_stage.find_room(id)
	_stage_caption.text = str(room.get("caption", "今天也陪着你。"))
	_stage_location.text = "☾  " + str(room.name)
	_rooms_page.set_current(id)
	_refresh_context()
	if notify:
		room_changed.emit(id)


func show_view(id: String) -> void:
	if id not in ["call", "rooms", "desktop", "performance"] or (id == "performance" and _monitor_page == null):
		return
	if is_instance_valid(panel):
		panel.save_view_state()
	current_view = id
	_layout()
	if id == "call" and is_instance_valid(panel) and history_visible:
		panel.restore_view_state()
	view_changed.emit(id)


func is_reading_conversation() -> bool:
	return current_view == "call" and history_visible and is_instance_valid(panel) and _empty_mode == "hall"


func set_desktop_preferences(profile: PalProfile) -> void:
	if is_instance_valid(_desktop_page):
		_desktop_page.set_preferences(profile)


func set_character_display(visual: String, framing: String, available: bool) -> void:
	_selected_visual = visual
	_portrait_framing = framing
	_display_available = available
	for id: String in _display_buttons:
		var button: Button = _display_buttons[id]
		button.disabled = not available
		button.visible = id in ["sprite2d", "vrm3d"] or visual == "sprite2d"
		PalUi.quiet(button, id == visual or (visual == "sprite2d" and id == framing))
	if _desktop_button != null and _empty_mode != "desktop":
		var desktop_mode := _character_pet.profile.desktop_mode if _character_pet != null and visual == "sprite2d" else "full_body"
		match desktop_mode:
			"call":
				_desktop_button.text = "2D 聊天"
				_desktop_button.tooltip_text = "打开近景角色和聊天窗口"
			"minimal":
				_desktop_button.text = "极简监控"
				_desktop_button.tooltip_text = "打开角色与性能数据；聊天模式可在桌面页单独开启"
			_:
				_desktop_button.text = "桌宠"
				_desktop_button.tooltip_text = "打开全身桌宠；右键可选择动作、衣装和坐趴姿势"
	_layout()


func set_character_pet(value: PalPetInstance) -> void:
	if _character_pet != value and _character_wheel != null:
		_character_wheel.hide()
	_character_pet = value


func _open_character_wheel() -> void:
	if _character_wheel == null:
		_character_wheel = PalCharacterWheel.new()
		add_child(_character_wheel)
		_character_wheel.action_requested.connect(action_requested.emit)
	_character_wheel.open_for(_character_pet, _interactions.get_global_rect().get_center() - global_position - Vector2(0, 130))


func set_voice_enabled(enabled: bool) -> void:
	if _voice == null:
		return
	_voice.icon = load("res://assets/ui/icons/volume.svg" if enabled else "res://assets/ui/icons/muted.svg")
	_voice.tooltip_text = ("自动朗读已开启 · 点击关闭" if enabled else "自动朗读已关闭 · 点击开启") + "\n语音服务在连接设置中配置"
	PalUi.quiet(_voice, enabled)


func update_roster(entries: Array, selected: String, can_add: bool) -> void:
	var menu := _roster_menu.get_popup()
	menu.clear()
	_roster_ids.clear()
	_roster_menu.icon = preload("res://assets/ui/pal_mark.svg")
	_roster_menu.tooltip_text = "切换 / 添加伙伴"
	_roster_menu.text = ""
	for entry: Dictionary in entries:
		var index := _roster_ids.size()
		var id := str(entry.id)
		_roster_ids.append(id)
		var unread := int(entry.get("unread", 0))
		var caption := str(entry.name) + " · " + str(entry.status)
		if unread > 0:
			caption += " · %d 条未读" % unread
		menu.add_radio_check_item(caption, index)
		menu.set_item_checked(index, id == selected)
		if id == selected:
			_roster_menu.icon = entry.get("portrait") if entry.get("portrait") != null else preload("res://assets/ui/pal_mark.svg")
			_roster_menu.tooltip_text = caption + "\n点击切换伙伴"
			_roster_menu.text = str(unread) if unread > 0 else ""
	menu.add_separator()
	menu.add_item("添加伙伴", 100)
	menu.set_item_disabled(menu.get_item_index(100), not can_add)
	menu.add_item("全部召回", 101)
	_add_button.disabled = not can_add
	_add_button.tooltip_text = "最多同时陪伴四位伙伴" if entries.size() >= 4 else "添加 2D / 3D 伙伴"
	if _empty_mode == "empty":
		_empty_action.disabled = not can_add
	_desktop_page.update_roster(entries, selected)
	_desktop_page.set_presence(_empty_mode)


func attach_conversation(conversation: PalConversationPanel) -> void:
	if is_instance_valid(panel) and panel != conversation:
		detach_conversation()
	panel = conversation
	panel.set_desktop_compact(false)
	panel.reparent(_history_slot, false)
	panel.restore_composer()
	panel.show()
	if not panel.presentation_changed.is_connected(_on_presentation):
		panel.presentation_changed.connect(_on_presentation)
	if not panel.bubbles_changed.is_connected(_on_bubbles):
		panel.bubbles_changed.connect(_on_bubbles)
	panel._refresh()
	show_presence("hall")
	_layout.call_deferred()


func detach_conversation() -> void:
	if is_instance_valid(panel):
		if panel.presentation_changed.is_connected(_on_presentation):
			panel.presentation_changed.disconnect(_on_presentation)
		if panel.bubbles_changed.is_connected(_on_bubbles):
			panel.bubbles_changed.disconnect(_on_bubbles)
		panel.save_view_state()
		panel.restore_composer()
	panel = null
	_on_bubbles("", "")
	history_visible = false
	_layout()


func show_presence(mode: String, display_name: String = "") -> void:
	_empty_mode = mode
	_interactions.disabled = mode != "hall"
	_voice.disabled = mode == "empty"
	_desktop_button.disabled = mode == "empty"
	_desktop_button.text = "召回" if mode == "desktop" else "桌面"
	_desktop_button.tooltip_text = "召回通话" if mode == "desktop" else "放到桌面安静陪伴"
	_chat_toggle.disabled = mode != "hall"
	_focus.disabled = mode != "hall"
	for page: String in _buttons:
		_buttons[page].disabled = mode == "empty" and page != "profile"
	history_visible = _history_preferred and is_instance_valid(panel) and mode == "hall"
	if mode != "hall":
		_name.text = display_name if not display_name.is_empty() else "今天，想和谁相见？"
		_state.text = "桌面陪伴中" if mode == "desktop" else "等待伙伴"
		_empty_title.text = display_name + "正在桌面等你" if mode == "desktop" else "让陪伴从这里开始"
		_empty_text.text = "桌面窗口可以拖动、缩放，聊天会继续。" if mode == "desktop" else "选择熟悉的角色，让今天多一点陪伴。"
		_empty_action.text = "召回通话" if mode == "desktop" else "添加伙伴"
		_empty_action.disabled = false
	_desktop_page.set_presence(mode)
	_layout.call_deferred()


func set_history_visible(value: bool) -> void:
	var was_visible := history_visible
	if is_instance_valid(panel):
		panel.save_view_state()
	_history_preferred = value
	history_visible = value and is_instance_valid(panel)
	if value:
		current_view = "call"
	_layout()
	if history_visible and not was_visible:
		_history_focus = get_viewport().gui_get_focus_owner()
		panel.restore_view_state()
	elif not history_visible:
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus) and _sidebar.is_ancestor_of(focus):
			_chat_toggle.grab_focus()
	history_visibility_changed.emit(value)
	view_changed.emit(current_view)


func set_connection(configured: bool, state: String = "configured") -> void:
	var names := {"configured": "已配置", "testing": "测试中", "verified": "已连接", "failed": "连接失败"}
	_connection.text = str(names.get(state, "已配置")) if configured else "接入模型"
	_connection.tooltip_text = "打开连接设置 · " + _connection.text


func set_notice(message: String) -> void:
	_notice.text = message
	_notice.tooltip_text = message
	_notice.visible = not message.is_empty()
	_layout()


func _on_presentation(display_name: String, state: String, preview: String) -> void:
	_name.text = display_name
	_state.text = "● " + state
	_subtitle.text = preview
	_refresh_context()


func _refresh_context() -> void:
	if _context == null or _room_stage.current_id.is_empty():
		return
	var room := _room_stage.find_room(_room_stage.current_id)
	_context.text = "日常陪伴 · " + str(room.get("name", ""))
	_context.tooltip_text = "编辑世界设定。换房间只更换画面背景，对话会继续。"


func _layout() -> void:
	if _desktop_page == null or _notice == null:
		return
	var dimensions := size
	var call_visible := current_view == "call"
	var monitor_portrait := current_view == "performance" and _empty_mode == "hall"
	var show_chat := call_visible and history_visible and is_instance_valid(panel)
	var width := clampf(chat_width, 320.0, minf(480.0, dimensions.x - 464.0))
	var hero_width := dimensions.x - 64.0 - (width if show_chat else 0.0)
	var hero_height := dimensions.y - 56.0
	overlay_history = false
	_top_background.position = Vector2.ZERO
	_top_background.size = Vector2(dimensions.x, 56)
	_header.position = Vector2(17, 9)
	_header.size = Vector2(dimensions.x - 34, 38)
	_brand_hint.visible = dimensions.x >= 1140
	var tab_width := float(_tab_buttons.size() * 90 - 4)
	_tabs.position = Vector2(maxf(150, minf(dimensions.x * 0.5 - tab_width * 0.5, dimensions.x - 397 - tab_width)), 10)
	_tabs.size = Vector2(tab_width, 36)
	for id: String in _tab_buttons:
		PalUi.quiet(_tab_buttons[id], id == current_view)
	_rail.position = Vector2(0, 56)
	_rail.size = Vector2(64, maxf(0, hero_height))
	_room_stage.position = Vector2(64, 56)
	_room_stage.size = Vector2(dimensions.x - 64, hero_height)
	_room_stage.visible = call_visible
	_stage_shade.position = _room_stage.position
	_stage_shade.size = _room_stage.size
	_stage_shade.visible = call_visible
	# Use the full stage height for both portrait and 3D call framing.
	var stage_rect := Rect2(Vector2(64, 56), Vector2(maxf(120, hero_width), maxf(100, hero_height)))
	if monitor_portrait:
		stage_rect = Rect2(Vector2(dimensions.x - 276, 180), Vector2(256, maxf(180, hero_height - 210)))
	_bubble_area = Rect2(Vector2(84, 220), Vector2(maxf(100, hero_width - 40), maxf(100, dimensions.y - 326)))
	if monitor_portrait:
		_bubble_area = Rect2(Vector2(dimensions.x - 270, 158), Vector2(248, maxf(160, dimensions.y - 202)))
	_layout_character_surface(stage_rect)
	surface.visible = (call_visible or monitor_portrait) and _empty_mode == "hall"
	_display_controls.position = Vector2(96, 180)
	_display_controls.size = Vector2(maxf(100, hero_width - 64), 32)
	_display_controls.visible = call_visible
	_stage_kicker.position = Vector2(96, 77)
	_stage_kicker.size = Vector2(180, 20)
	_name.position = Vector2(96, 104)
	_name.size = Vector2(maxf(100, hero_width - 172), 39)
	_state.position = Vector2(64 + hero_width - 193, 79)
	_state.size = Vector2(130, 22)
	_stage_caption.position = Vector2(96, 148)
	_stage_caption.size = Vector2(maxf(100, hero_width - 85), 23)
	_focus.position = Vector2(64 + hero_width - 54, 77)
	_focus.size = Vector2(32, 32)
	_stage_location.position = Vector2(84, dimensions.y - 121)
	_stage_location.size = Vector2(maxf(0, hero_width - 40), 23)
	var footer_width := minf(426, hero_width - 36)
	_footer.position = Vector2(64 + (hero_width - footer_width) * 0.5, dimensions.y - 86)
	_footer.size = Vector2(footer_width, 64)
	for control: Control in [_stage_kicker, _name, _state, _stage_caption, _focus, _stage_location, _footer]:
		control.visible = call_visible
	if monitor_portrait:
		_name.visible = true
		_name.position = Vector2(dimensions.x - 260, 102)
		_name.size = Vector2(232, 39)
	_sidebar.visible = show_chat
	_sidebar.position = Vector2(dimensions.x - width, 56)
	_sidebar.size = Vector2(width, hero_height)
	_resize_grip.visible = show_chat
	_resize_grip.position = _sidebar.position - Vector2(7, 0)
	_resize_grip.size = Vector2(7, hero_height)
	_chat_toggle.tooltip_text = "收起对话栏" if history_visible else "展开对话栏"
	PalUi.quiet(_chat_toggle, history_visible)
	PalUi.quiet(_buttons.history, call_visible and history_visible)
	_empty.visible = call_visible and _empty_mode != "hall"
	_empty.size = Vector2(minf(430, hero_width - 64), 0)
	_empty.position = Vector2(64 + (hero_width - _empty.size.x) * 0.5, 56 + maxf(150, (hero_height - 220) * 0.5))
	_rooms_page.visible = current_view == "rooms"
	_desktop_page.visible = current_view == "desktop"
	for page: Control in [_rooms_page, _desktop_page]:
		page.position = Vector2(64, 56)
		page.size = Vector2(dimensions.x - 64, hero_height)
	if _monitor_page != null:
		_monitor_page.visible = current_view == "performance"
		_monitor_page.position = Vector2(64, 56)
		_monitor_page.size = Vector2(dimensions.x - 64 - (290 if monitor_portrait else 0), hero_height - 12)
	_notice.position = Vector2(84, dimensions.y - 45)
	_notice.size = Vector2(dimensions.x - 108, 36)
	_window_resize.visible = not PalUi.is_editor_preview(get_window()) and get_window().mode != Window.MODE_MAXIMIZED
	_window_resize.position = dimensions - Vector2(20, 20)
	_window_resize.size = Vector2(20, 20)
	_layout_pomodoro()
	_layout_bubbles()


func refresh_overlay() -> void:
	if _monitor_page != null:
		_monitor_page.call("ConfigureTheme", PalUi.PAPER, PalUi.SURFACE, PalUi.TEXT, PalUi.MUTED, PalUi.ACCENT, PalUi.BORDER)
	if _footer != null:
		PalUi.overlay_controls(_footer)
	if _display_controls != null:
		PalUi.overlay_controls(_display_controls)
	if _stage_location != null:
		PalUi.overlay_text(_stage_location)
	_layout()


func _drag_window(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and DisplayServer.get_name() != "headless" and not PalUi.is_editor_preview(get_window()):
		DisplayServer.window_start_drag(get_window().get_window_id())


func _touch_character(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_touch_pressed = true
		_touch_press_position = event.position
	else:
		var clicked: bool = _touch_pressed and event.position.distance_to(_touch_press_position) < 6.0
		_touch_pressed = false
		if clicked:
			character_pressed.emit(event.position)
	surface.accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var focus := get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus) and focus.has_method("has_ime_text") and focus.call("has_ime_text"):
			return
		if current_view != "call":
			show_view("call")
		elif history_visible:
			set_history_visible(false)
		else:
			return
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _resizing and event is InputEventMouseMotion:
		chat_width = clampf(size.x - get_local_mouse_position().x, 320, minf(480, size.x - 464))
		_layout()
		get_viewport().set_input_as_handled()
	elif _resizing and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_resizing = false
		chat_width_changed.emit(chat_width)
