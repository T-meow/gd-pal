class_name PalChatWindow
extends Window
## Focusable bubble shell; the same conversation component moves into the hall.

signal scene_requested
signal read_requested

var panel: PalConversationPanel
var preferences: PalUiPreferences
var profile_id := ""
var display_mode := "hidden"
var bridge: Node
var desktop: PalDesktopWindow
var collapsed := true
var unread := 0
var _frame: PanelContainer
var _expanded: VBoxContainer
var _compact_row: HBoxContainer
var _compact: Button
var _compact_settings: Button
var _heading: Label
var _tail: Control
var _resize: Button
var _expanded_size := Vector2i(360, 460)
var _preview := "今天也陪着你。"
var _display_name := "伙伴"
var _on_left := true
var _region_time := 0.0
var _last_regions: Array[Rect2] = []
var _region_window_id := -1
var _sizing := false
var _size_save: Timer


func _ready() -> void:
	if PalUi.is_mobile():
		# A parked conversation holder; Android never creates native chat windows.
		force_native = false
		_expanded = VBoxContainer.new()
		add_child(_expanded)
		_expanded.add_child(panel)
		set_process(false)
		return
	if preferences != null:
		display_mode = str(preferences.get_value("desktop/" + profile_id, "bubble_mode", "hidden"))
		var saved_size: Variant = preferences.get_value("desktop/" + profile_id, "bubble_size", _expanded_size)
		if saved_size is Vector2i and saved_size.x >= 320 and saved_size.y >= 330:
			_expanded_size = saved_size
	_size_save = Timer.new()
	_size_save.one_shot = true
	_size_save.wait_time = 0.4
	_size_save.timeout.connect(_save_dimensions)
	add_child(_size_save)
	title = "和伙伴聊一会儿 · GD Pal"
	force_native = true
	borderless = true
	transparent = true
	transparent_bg = true
	unfocusable = false
	transient = false
	world_2d = World2D.new()
	PalUi.fit_window(self, _expanded_size, Vector2i(320, 330))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	_frame = PanelContainer.new()
	var style := PalUi.glass(0.58, 16, 10)
	style.shadow_color = Color(0.015, 0.025, 0.04, 0.25)
	style.shadow_size = 6
	_frame.add_theme_stylebox_override("panel", style)
	margin.add_child(_frame)
	_expanded = VBoxContainer.new()
	_expanded.add_theme_constant_override("separation", 6)
	_frame.add_child(_expanded)
	var header := HBoxContainer.new()
	_expanded.add_child(header)
	_heading = PalUi.label("伙伴 · 陪着你", header, 14)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_heading.mouse_filter = Control.MOUSE_FILTER_STOP
	_heading.gui_input.connect(_drag_header)
	PalUi.button("通话", header, func() -> void: scene_requested.emit()).add_theme_font_size_override("font_size", 13)
	PalUi.button("−", header, func() -> void: set_collapsed(true)).tooltip_text = "收起聊天"
	PalUi.icon_button("", "close", header, func() -> void: set_display_mode("hidden")).tooltip_text = "隐藏气泡，安静陪伴"
	panel.make_more_button(header)
	for control: Node in header.get_children():
		if control is Button:
			PalUi.dense(control, 28)
			control.custom_minimum_size.x = 28
	_expanded.add_child(panel)
	panel.presentation_changed.connect(_on_presentation)
	panel.reveal_requested.connect(func() -> void:
		if panel.get_parent() == _expanded:
			open_chat(true)
	)
	panel.service.connect("ReplyFinished", _on_reply)
	_compact_row = HBoxContainer.new()
	_compact_row.add_theme_constant_override("separation", 4)
	_frame.add_child(_compact_row)
	_compact = Button.new()
	_compact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compact.clip_text = true
	_compact.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var compact_style := PalUi.panel(Color.TRANSPARENT, 10, 2)
	compact_style.set_border_width_all(0)
	_compact.add_theme_stylebox_override("normal", compact_style)
	_compact.tooltip_text = "展开聊天记录"
	_compact_row.add_child(_compact)
	_compact.pressed.connect(func() -> void: open_chat(true))
	_compact_settings = PalUi.icon_button("", "settings", _compact_row, panel.open_settings)
	_compact_settings.tooltip_text = "在主窗口打开连接设置"
	PalUi.icon_button("", "close", _compact_row, func() -> void: set_display_mode("hidden")).tooltip_text = "隐藏气泡"
	_compact_row.hide()
	_tail = Control.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.draw.connect(_draw_tail)
	add_child(_tail)
	_resize = Button.new()
	_resize.text = "◢"
	_resize.flat = true
	_resize.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize.tooltip_text = "调整聊天窗口大小"
	_resize.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and DisplayServer.get_name() != "headless":
			DisplayServer.window_start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, get_window_id())
	)
	add_child(_resize)
	size_changed.connect(_on_size_changed)
	visibility_changed.connect(func() -> void: _last_regions.clear())
	close_requested.connect(func() -> void: set_display_mode("hidden"))
	focus_entered.connect(func() -> void:
		if not collapsed:
			unread = 0
			read_requested.emit()
			_refresh_compact()
	)
	_on_size_changed()
	panel._refresh()


func attach_panel() -> void:
	panel.restore_composer()
	panel.set_desktop_compact(is_instance_valid(desktop))
	if panel.get_parent() != _expanded:
		panel.reparent(_expanded, false)
	panel.show()
	panel._refresh()
	panel.restore_view_state()


func open_chat(focus: bool = false) -> void:
	set_display_mode("expanded")
	unread = 0
	read_requested.emit()
	show()
	if DisplayServer.get_name() != "headless":
		if focus:
			grab_focus()
			panel.focus_input()


func set_collapsed(value: bool) -> void:
	set_display_mode("compact" if value else "expanded")


func set_display_mode(value: String, persist: bool = true) -> void:
	if value not in ["hidden", "compact", "expanded"]:
		value = "hidden"
	if not collapsed and display_mode != value:
		_save_dimensions()
	display_mode = value
	collapsed = value != "expanded"
	_sizing = true
	_expanded.visible = not collapsed
	_compact_row.visible = value == "compact"
	_resize.visible = not collapsed
	PalUi.set_window_minimum(self, Vector2i(280, 108) if collapsed else Vector2i(320, 330))
	size = Vector2i(Vector2(Vector2i(300, 108) if collapsed else _expanded_size) * content_scale_factor)
	visible = value != "hidden" and is_instance_valid(desktop)
	if not collapsed:
		PalUi.reveal(_expanded)
	_refresh_compact()
	follow_pet()
	_sizing = false
	if persist and preferences != null:
		preferences.put("desktop/" + profile_id, "bubble_mode", display_mode)
	_last_regions.clear()


func apply_saved_mode() -> void:
	set_display_mode(display_mode, false)


func _save_dimensions() -> void:
	if collapsed or _sizing:
		return
	_expanded_size = Vector2i(Vector2(size) / content_scale_factor).max(Vector2i(320, 330))
	if preferences != null:
		preferences.put("desktop/" + profile_id, "bubble_size", _expanded_size)


func bind_desktop(host: PalDesktopWindow) -> void:
	if host == null:
		_save_dimensions()
	if is_instance_valid(desktop) and panel.bubbles_changed.is_connected(desktop.set_dialogue):
		panel.bubbles_changed.disconnect(desktop.set_dialogue)
	if is_instance_valid(desktop) and desktop.bubble_page_requested.is_connected(panel.navigate_bubbles):
		desktop.bubble_page_requested.disconnect(panel.navigate_bubbles)
	desktop = host
	if is_instance_valid(desktop):
		panel.bubbles_changed.connect(desktop.set_dialogue)
		desktop.bubble_page_requested.connect(panel.navigate_bubbles)
		panel._refresh()
	panel.set_desktop_compact(is_instance_valid(host))
	always_on_top = is_instance_valid(host)
	follow_pet()


func follow_pet() -> void:
	if not is_instance_valid(desktop):
		return
	var area := desktop.current_work_area()
	var available := (area.size - Vector2i(16, 16)).max(Vector2i.ONE)
	min_size = Vector2i(Vector2(Vector2i(280, 108) if collapsed else Vector2i(320, 330)) * content_scale_factor).min(available)
	size = size.min(available)
	var left_space := desktop.position.x - area.position.x
	var right_space := area.end.x - desktop.position.x - desktop.size.x
	_on_left = left_space >= size.x + 12 or left_space >= right_space
	var x := desktop.position.x - size.x - 8 if _on_left else desktop.position.x + desktop.size.x + 8
	var desired := Vector2i(x, desktop.position.y + int(desktop.size.y * 0.16))
	position = PalDesktopWindow.clamp_position(desired, size, area)
	_tail.queue_redraw()


func _process(delta: float) -> void:
	follow_pet()
	_region_time -= delta
	if _region_time <= 0.0:
		_region_time = 0.15
		PalUi.sync_window_scale(self)
		if visible and bridge != null and DisplayServer.get_name() != "headless":
			var dimensions := get_visible_rect().size
			var transform := get_stretch_transform()
			var regions: Array[Rect2] = [transform * _frame.get_global_rect().grow(6), transform * Rect2(8, dimensions.y - 22, dimensions.x - 16, 20)]
			var native_id := get_window_id()
			if regions != _last_regions or native_id != _region_window_id:
				if bridge.call("SetInputRegions", native_id, regions):
					_last_regions = regions
					_region_window_id = native_id


func _drag_header(event: InputEvent) -> void:
	if not is_instance_valid(desktop) and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and DisplayServer.get_name() != "headless":
		DisplayServer.window_start_drag(get_window_id())


func _on_size_changed() -> void:
	if not _sizing and not collapsed and is_instance_valid(desktop) and _size_save != null:
		_size_save.start()
	if _resize != null:
		_resize.position = get_visible_rect().size - Vector2(33, 42)
		_resize.size = Vector2(22, 22)
	if _tail != null:
		_tail.queue_redraw()
	_region_time = 0.0


func _draw_tail() -> void:
	var dimensions := get_visible_rect().size
	var x := dimensions.x - 24 if _on_left else 24.0
	var direction := 1.0 if _on_left else -1.0
	var y := dimensions.y - 19
	_tail.draw_colored_polygon(PackedVector2Array([Vector2(x - direction * 24, y), Vector2(x, y), Vector2(x + direction * 6, y + 13)]), PalUi.glass(0.9).bg_color)


func _on_presentation(display_name: String, state: String, preview: String) -> void:
	_display_name = display_name
	_preview = preview
	_heading.text = display_name + " · " + ("陪着你" if state == "陪伴中" else state)
	title = display_name + " · GD Pal"
	_refresh_compact()


func _on_reply(profile_id: String, _text: String) -> void:
	var reading := visible and not collapsed and (DisplayServer.get_name() == "headless" or has_focus())
	if profile_id == panel._profile_id and not reading and is_instance_valid(desktop):
		unread += 1
		_refresh_compact()


func _refresh_compact() -> void:
	if _compact == null:
		return
	var badge := "  · %d 条新消息" % unread if unread > 0 else "  · 点击展开"
	_compact.text = _display_name + badge + "\n" + _preview.replace("\n", " ").left(26)
