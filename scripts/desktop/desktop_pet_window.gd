class_name PalDesktopWindow
extends Window
## A native transparent host; the same pet viewport moves between here and the hall.

signal return_requested(instance_id: String)
signal chat_requested(instance_id: String)
signal scene_requested(instance_id: String)
signal navigation_requested(page_id: String, instance_id: String)
signal settings_changed
signal dialogue_enabled_changed(value: bool)
signal monitor_mode_changed
signal framing_requested(mode: String)
signal touch_requested(instance_id: String, region: String)
signal bubble_page_requested(direction: int)
signal touch_regions_requested(value: bool)

const TASKBAR_SNAP_DISTANCE := 160.0
const EDGE_DETACH_DISTANCE := 90.0
const TOUCH_REGIONS := preload("res://scripts/app/touch_regions.gd")

var pet: PalPetInstance
var bridge: Node
var pc_monitor: Node
var _monitor_window: Window
var _minimal_background: Panel
var _minimal_scroll: ScrollContainer
var _minimal_panel: Control
var _minimal_divider: ColorRect
var _minimal_menu: PopupMenu
var surface: SubViewportContainer
var _overlay: Control
var _toolbar: HFlowContainer
var _chat_button: Button
var _performance_button: Button
var _menu_chat: Button
var _dialogue_toggle: CheckButton
var _unread_count := 0
var _bubble: PalDialogueBubble
var _description_bubble: PalDialogueBubble
var _reply_dialogue := ""
var _reply_index := 0
var _reply_total := 0
var _bubble_timer := 0.0
var _system_notice := false
var _menu: PanelContainer
var _pressing := false
var _dragging := false
var _lifted_from_edge := false
var _press_cursor := Vector2.ZERO
var _press_position := Vector2i.ZERO
var _press_local_position := Vector2.ZERO
var _touch_regions: Control
var _touch_toggle: CheckButton
var _region_time := 0.0
var _last_regions: Array[Rect2] = []
var _wander_time := 0.0
var _wander_direction := 1.0
var _walking_on_desktop := false
var _position_x := 0.0
var _rng := RandomNumberGenerator.new()
var _unread_button: Button
var _toolbar_timeout := 0.0
var _silent_greeting := false
var _attachment: Dictionary = {}
var _attachment_ratio := 0.5
var _attachment_time := 0.0
var _edge_button: Button
var _release_button: Button
var _framing_button: Button
var _wheel: PalCharacterWheel


func _ready() -> void:
	_rng.randomize()
	name = "Desktop_" + pet.instance_id
	title = pet.profile.display_name + " · GD Pal"
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	unfocusable = true
	transient = false
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	content_scale_size = Vector2i.ZERO
	world_2d = World2D.new()
	_minimal_background = Panel.new()
	_minimal_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimal_background)
	surface = SubViewportContainer.new()
	surface.stretch = true
	surface.clip_contents = true
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	pet.reparent(surface, false)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.theme = theme
	add_child(_overlay)
	_build_controls()
	_build_minimal_monitor()
	if pc_monitor != null:
		_monitor_window = preload("res://scripts/monitoring/PcMonitorWindow.cs").new()
		_monitor_window.visible = false
		_monitor_window.force_native = true
		_monitor_window.call("Configure", pc_monitor, self, pet.profile.profile_id)
		_monitor_window.call("ConfigureTheme", PalUi.PAPER, PalUi.SURFACE, PalUi.TEXT, PalUi.MUTED, PalUi.ACCENT, PalUi.BORDER)
		_monitor_window.connect("HallRequested", func() -> void: navigation_requested.emit("performance", pet.instance_id))
		add_child(_monitor_window)
		pc_monitor.connect("SettingsChanged", refresh_monitor_controls)
		refresh_monitor_controls()
	add_to_group("pal_touch_hosts")
	add_to_group("pal_overlay_hosts")
	refresh_overlay()
	if pet.profile.desktop_position.x != -100000:
		position = pet.profile.desktop_position
	resize_pet(display_scale(), false)
	var area := current_work_area()
	if pet.profile.desktop_position.x == -100000:
		position = area.end - size - Vector2i(32 + 36 * get_index(), 12)
	else:
		position = clamp_position(pet.profile.desktop_position, size, area)
	_position_x = position.x
	window_input.connect(_on_window_input)
	visibility_changed.connect(_sync_window_render_size, CONNECT_DEFERRED)
	close_requested.connect(func() -> void: return_requested.emit(pet.instance_id))
	pet.behavior.action_requested.connect(_on_action)
	pet.visual_changed.connect(_on_visual_changed)
	pet.wardrobe_changed.connect(_on_wardrobe_changed)
	if DisplayServer.get_name() != "headless":
		show()
	_silent_greeting = true
	pet.behavior.request_action("greet")
	_silent_greeting = false


func _sync_window_render_size() -> void:
	if not visible:
		return
	# Apply the size after the native window exists; its render target can otherwise
	# remain at 4x4 even though the window and the character viewport have full size.
	set_size(size)
	_layout_character_surface()
	_last_regions.clear()
	_region_time = 0.0


func _build_controls() -> void:
	_touch_regions = TOUCH_REGIONS.new()
	_touch_regions.surface = surface
	_overlay.add_child(_touch_regions)
	_bubble = PalDialogueBubble.new()
	_overlay.add_child(_bubble)
	_description_bubble = PalDialogueBubble.new()
	_overlay.add_child(_description_bubble)
	_bubble.page_requested.connect(bubble_page_requested.emit)
	_description_bubble.page_requested.connect(bubble_page_requested.emit)
	_toolbar = HFlowContainer.new()
	_toolbar.alignment = FlowContainer.ALIGNMENT_CENTER
	_toolbar.add_theme_constant_override("h_separation", 5)
	_toolbar.add_theme_constant_override("v_separation", 5)
	_toolbar.resized.connect(_position_toolbar)
	_overlay.add_child(_toolbar)
	_chat_button = PalUi.button("聊天", _toolbar, _request_chat)
	PalUi.button("菜单", _toolbar, _toggle_menu)
	if pc_monitor != null:
		_performance_button = PalUi.button("性能", _toolbar, func() -> void: pc_monitor.call("SetDesktopVisibleFor", pet.profile.profile_id, not pc_monitor.call("IsDesktopVisibleFor", pet.profile.profile_id)))
		_performance_button.toggle_mode = true
		_performance_button.tooltip_text = "打开或关闭此伙伴的性能面板"
	PalUi.button("大厅", _toolbar, func() -> void: return_requested.emit(pet.instance_id), true)
	_toolbar.hide()
	_unread_button = PalUi.button("", _overlay, _request_chat, true)
	_unread_button.tooltip_text = "有新回复，点击打开聊天"
	_unread_button.hide()
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 16, 10))
	_overlay.add_child(_menu)
	var menu_items := VBoxContainer.new()
	menu_items.add_theme_constant_override("separation", 6)
	var menu_scroll := ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu.add_child(menu_scroll)
	menu_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_scroll.add_child(menu_items)
	_dialogue_toggle = CheckButton.new()
	_dialogue_toggle.text = "启用对话"
	_dialogue_toggle.tooltip_text = "关闭当前伙伴在大厅与桌面的对话；点击仍会切换立绘，也可拖动、换装和查看记录。"
	_dialogue_toggle.set_pressed_no_signal(pet.profile.desktop_dialogue_enabled)
	menu_items.add_child(_dialogue_toggle)
	_dialogue_toggle.toggled.connect(dialogue_enabled_changed.emit)
	_touch_toggle = CheckButton.new()
	_touch_toggle.text = "显示触控范围"
	_touch_toggle.set_pressed_no_signal(PalUi.show_touch_regions)
	_touch_toggle.toggled.connect(touch_regions_requested.emit)
	menu_items.add_child(_touch_toggle)
	_menu_chat = PalUi.button("和伙伴聊天", menu_items, func() -> void:
		_menu.hide()
		_request_chat()
	)
	PalUi.button("摸摸头", menu_items, func() -> void:
		pet.behavior.request_action("head_pat")
		_menu.hide()
	)
	PalUi.button("动作与衣装", menu_items, _toggle_menu)
	_framing_button = PalUi.button("", menu_items, func() -> void:
		_menu.hide()
		framing_requested.emit("full_body" if _is_phone() else "call"))
	_edge_button = PalUi.button("趴在任务栏", menu_items, func() -> void:
		_menu.hide()
		if not _try_attach(true):
			say("这里没有足够宽、可见的任务栏上沿。"))
	_release_button = PalUi.button("离开边缘", menu_items, func() -> void:
		_menu.hide()
		_release_attachment(true))
	_edge_button.tooltip_text = "在环形菜单选择坐下或趴下。拖近任务栏或窗口上沿松手吸附，横向拖动可滑动，上下拖离则起身。"
	_refresh_edge_controls()
	PalUi.button("回到陪伴大厅", menu_items, func() -> void: scene_requested.emit(pet.instance_id))
	for entry: Array in [["伙伴档案", "profile"], ["手动记忆", "memory"], ["世界设定", "world"], ["AI 整理", "summary"], ["Agent 任务", "agent"], ["主题与外观", "appearance"], ["连接设置", "settings"]]:
		var page: String = entry[1]
		PalUi.button(entry[0], menu_items, func() -> void:
			_menu.hide()
			navigation_requested.emit(page, pet.instance_id)
		)
	_menu.hide()
	_wheel = PalCharacterWheel.new()
	_overlay.add_child(_wheel)
	_wheel.action_requested.connect(_play_portrait_or_motion)
	_wheel.mode_requested.connect(framing_requested.emit)
	_wheel.more_requested.connect(func() -> void: _refresh_edge_controls(); _menu.show(); _region_time = 0.0)
	refresh_dialogue_controls()


func _request_chat() -> void:
	chat_requested.emit(pet.instance_id)


func _build_minimal_monitor() -> void:
	_minimal_divider = ColorRect.new()
	_minimal_divider.name = "MinimalMonitorDivider"
	_minimal_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimal_divider.visible = false
	_overlay.add_child(_minimal_divider)
	_minimal_scroll = ScrollContainer.new()
	_minimal_scroll.name = "MinimalMonitorData"
	_minimal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_minimal_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_overlay.add_child(_minimal_scroll)
	_minimal_panel = preload("res://scripts/monitoring/PcMonitorPanel.cs").new()
	_minimal_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimal_panel.call("SetProfileId", pet.profile.profile_id)
	if pc_monitor != null:
		_minimal_panel.call("Configure", pc_monitor, 3)
	_minimal_scroll.add_child(_minimal_panel)
	_minimal_menu = PopupMenu.new()
	_minimal_menu.name = "MinimalMonitorMenu"
	_minimal_menu.add_item("监控详情与温度设置", 0)
	_minimal_menu.add_item("切换为 2D 聊天", 1)
	_minimal_menu.add_item("返回大厅", 2)
	_minimal_menu.add_item("选择显示的硬盘…", 3)
	_minimal_menu.add_separator("玻璃外观")
	_minimal_menu.add_radio_check_item("跟随应用主题", 10)
	_minimal_menu.add_radio_check_item("亮色玻璃", 11)
	_minimal_menu.add_radio_check_item("暗色玻璃", 12)
	_minimal_menu.id_pressed.connect(func(id: int) -> void:
		if id in [10, 11, 12] and pc_monitor != null:
			pc_monitor.call("SetMinimalAppearance", ["follow", "light", "dark"][id - 10], pc_monitor.call("GetMinimalOpacity"))
			return
		match id:
			0:
				navigation_requested.emit("performance", pet.instance_id)
			1:
				framing_requested.emit("call")
			2:
				return_requested.emit(pet.instance_id)
			3:
				_minimal_panel.call_deferred("OpenDiskPicker")
	)
	add_child(_minimal_menu)
	_sync_minimal_mode()


func _sync_minimal_mode() -> void:
	var minimal := is_minimal_mode()
	var changed := pet.monitor_only != minimal
	pet.monitor_only = minimal
	_minimal_background.visible = minimal
	if _minimal_divider != null:
		_minimal_divider.visible = minimal
	if _minimal_scroll != null:
		_minimal_scroll.visible = minimal
		_minimal_panel.call("SetHostActive", minimal)
	_touch_regions.overlay_enabled = not minimal
	_touch_regions.refresh()
	_menu.hide()
	_wheel.hide()
	_toolbar.hide()
	if _performance_button != null:
		_performance_button.visible = not is_chat_mode()
	if _minimal_menu != null:
		_minimal_menu.hide()
	if minimal:
		_unread_button.hide()
	if is_instance_valid(_monitor_window):
		_monitor_window.call("UpdatePlacement")
	if changed:
		monitor_mode_changed.emit()


func refresh_monitor_controls() -> void:
	if _performance_button != null and pc_monitor != null:
		_performance_button.set_pressed_no_signal(bool(pc_monitor.call("IsDesktopVisibleFor", pet.profile.profile_id)))
	_refresh_minimal_glass()


func _refresh_minimal_glass() -> void:
	if _minimal_panel == null or _minimal_background == null:
		return
	var selected := str(pc_monitor.call("GetMinimalTheme")) if pc_monitor != null else "follow"
	var light := selected == "light" or (selected == "follow" and PalUi.is_light())
	var opacity := float(pc_monitor.call("GetMinimalOpacity")) if pc_monitor != null else 0.12
	var paper := Color("eef6ff") if light else Color("09121f")
	var text := Color("182d45") if light else Color("f1f6ff")
	var muted := Color("314a64") if light else Color("c8d8eb")
	var accent := Color("205a9c") if light else Color("b8d9ff")
	var border := Color(1, 1, 1, 0.48 if light else 0.24)
	var glass := PalUi.panel(Color(paper, opacity), 14, 0)
	glass.border_color = border
	glass.shadow_color = Color(0, 0, 0, 0.07)
	glass.shadow_size = 3
	_minimal_background.add_theme_stylebox_override("panel", glass)
	if _minimal_divider != null:
		_minimal_divider.color = Color(text, 0.14)
	_minimal_panel.call("ConfigureTheme", paper, paper, text, muted, accent, Color(text, 0.14))
	if _minimal_menu != null:
		for index: int in range(3):
			_minimal_menu.set_item_checked(_minimal_menu.get_item_index(10 + index), selected == ["follow", "light", "dark"][index])
		var menu_style := PalUi.panel(Color(paper, 0.96), 12, 10)
		menu_style.border_color = Color(text, 0.18)
		_minimal_menu.add_theme_stylebox_override("panel", menu_style)
		_minimal_menu.add_theme_color_override("font_color", text)
		_minimal_menu.add_theme_color_override("font_hover_color", text)
		_minimal_menu.add_theme_stylebox_override("hover", PalUi.panel(Color(accent, 0.18), 8, 6))


func refresh_dialogue_controls() -> void:
	var enabled := pet.profile.desktop_dialogue_enabled
	_chat_button.visible = true
	_chat_button.text = "聊天" if enabled else "记录"
	_chat_button.tooltip_text = "打开对话窗口" if enabled else "查看对话记录；当前已关闭对话"
	_menu_chat.disabled = false
	_menu_chat.text = "和伙伴聊天" if enabled else "查看对话记录"
	_dialogue_toggle.set_pressed_no_signal(enabled)
	_unread_button.visible = enabled and not is_minimal_mode() and _unread_count > 0
	_layout_dialogue()
	_position_toolbar.call_deferred()
	_region_time = 0.0


func _position_toolbar() -> void:
	if _toolbar == null:
		return
	_toolbar.size.y = _toolbar.get_combined_minimum_size().y
	var bottom := float(size.y) if _attachment.is_empty() else minf(size.y, pet.presenter.get_support_anchor().y - 8.0)
	_toolbar.position = Vector2((size.x - _toolbar.size.x) * 0.5, maxf(8, bottom - _toolbar.size.y - 8))
	_region_time = 0.0


func resize_pet(scale_value: float, preserve_feet: bool = true) -> void:
	var feet := position + Vector2i(size.x / 2, size.y)
	var available := current_work_area().size - Vector2i(16, 16)
	var base_size := Vector2(360, 610) if _is_phone() else Vector2(380, 540)
	if is_minimal_mode():
		base_size = Vector2(560, 340)
	if not _is_phone() and pet.profile.visual_id == "sprite2d" and bool(pet.presenter.get_capabilities().get("landscape", false)):
		base_size = Vector2(640, 430)
	var largest := minf(1.5, minf(available.x / base_size.x, available.y / base_size.y))
	var applied_scale := clampf(scale_value, minf(0.65, largest), largest)
	if is_minimal_mode():
		pet.profile.minimal_monitor_scale = applied_scale
	else:
		pet.profile.desktop_scale = applied_scale
	size = Vector2i(base_size * applied_scale)
	_layout_character_surface()
	title = pet.profile.display_name + " · GD Pal"
	if is_minimal_mode():
		title = pet.profile.display_name + " · 极简监控 · GD Pal"
	elif is_chat_mode():
		title = pet.profile.display_name + " · 2D 聊天 · GD Pal"
	_framing_button.visible = pet.profile.visual_id == "sprite2d"
	_framing_button.text = "切换为全身桌宠" if _is_phone() else "切换为 2D 聊天"
	_layout_dialogue()
	_toolbar.size = Vector2(minf(344, maxf(120, size.x - 16)), 0)
	_position_toolbar.call_deferred()
	_unread_button.position = Vector2(size.x - 68, 80)
	_unread_button.size = Vector2(54, 38)
	var menu_height := minf(404, size.y - 16)
	_menu.position = Vector2(maxf(size.x - 220, 0), maxf(size.y - menu_height - 8, 8))
	_menu.size = Vector2(210, menu_height)
	if preserve_feet:
		if not _attachment.is_empty():
			pet.presenter.configure_surface(size)
			if not _place_on_surface(_attachment, _attachment_ratio):
				_release_attachment(true)
		else:
			position = clamp_position(feet - Vector2i(size.x / 2, size.y), size, current_work_area())
		pet.profile.desktop_position = position
		settings_changed.emit()
	_layout_attachment_controls()
	_last_regions.clear()


func _process(delta: float) -> void:
	if not is_instance_valid(pet):
		return
	var cursor: Vector2 = bridge.call("GetGlobalCursorPosition")
	var local_cursor := cursor - Vector2(position)
	_update_toolbar(delta, local_cursor)
	pet.set_look_target((local_cursor - Vector2(size) * 0.5) / (Vector2(size) * 0.5))
	if _pressing:
		if not bridge.call("IsPrimaryButtonDown"):
			_finish_press(local_cursor)
		elif cursor.distance_to(_press_cursor) > 5.0 or _dragging:
			_drag_to(cursor)
	elif not _attachment.is_empty():
		_attachment_time -= delta
		if _attachment_time <= 0.0:
			_attachment_time = 0.15
			_update_attachment()
	elif pet.profile.wander and not is_minimal_mode() and not _menu.visible and not _wheel.visible:
		_wander(delta)
	if _pressing or _menu.visible or _wheel.visible or not pet.profile.wander or not _attachment.is_empty():
		_stop_wandering()
	if _bubble_timer > 0.0:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_system_notice = false
			_bubble.set_text(_reply_dialogue)
			_bubble.set_navigation(_reply_index, _reply_total)
	_layout_dialogue()
	_region_time -= delta
	if _region_time <= 0.0:
		_region_time = 0.10
		_update_regions()


func _on_window_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var cursor := Vector2(event.position)
	if is_minimal_mode() and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_minimal_menu.position = position + Vector2i(cursor)
		_minimal_menu.popup()
		set_input_as_handled()
		return
	if is_minimal_mode() and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _minimal_scroll.get_rect().has_point(cursor):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _pressing:
		_finish_press(cursor)
		return
	if _over_controls(cursor):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_toggle_menu()
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		resize_pet(display_scale() + 0.08)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		resize_pet(display_scale() - 0.08)
	elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if is_minimal_mode() and _minimal_scroll.get_v_scroll_bar().visible and _minimal_scroll.get_v_scroll_bar().get_global_rect().has_point(cursor):
			return
		if is_minimal_mode() and _over_minimal_control(cursor):
			return
		if _wheel.visible:
			_wheel.hide()
			return
		if _menu.visible:
			_menu.hide()
			return
		_pressing = true
		_dragging = false
		_lifted_from_edge = false
		_press_cursor = bridge.call("GetGlobalCursorPosition")
		_press_position = position
		_press_local_position = cursor


func _over_controls(cursor: Vector2) -> bool:
	for control: Control in [_bubble, _description_bubble, _toolbar, _menu, _unread_button, _wheel]:
		if control.visible and control.get_rect().has_point(cursor):
			return true
	return false


func _over_minimal_control(cursor: Vector2) -> bool:
	if _minimal_scroll == null or not _minimal_scroll.visible:
		return false
	if not _minimal_scroll.get_global_rect().has_point(cursor):
		return false
	return _has_button_at(_minimal_scroll, cursor)


func _has_button_at(node: Node, cursor: Vector2) -> bool:
	for child in node.get_children():
		if not child is Control:
			continue
		var control: Control = child
		if not control.is_visible_in_tree():
			continue
		if control is BaseButton and control.get_global_rect().has_point(cursor):
			return true
		if _has_button_at(control, cursor):
			return true
	return false


func _drag_to(cursor: Vector2) -> void:
	if not _attachment.is_empty():
		_update_attachment()
		var vertical_pull := absf(cursor.y - _press_cursor.y)
		if not _attachment.is_empty() and vertical_pull <= EDGE_DETACH_DISTANCE * maxf(1.0, pet.profile.desktop_scale):
			var anchor := pet.presenter.get_support_anchor()
			var desired_x := _press_position.x + cursor.x - _press_cursor.x + anchor.x
			var ratio := (desired_x - float(_attachment.source_left)) / float(_attachment.source_width)
			if _place_on_surface(_attachment, ratio):
				_dragging = true
				# Save the clamped position, so releasing near the end of a ledge
				# cannot jump to another fragment on the next attachment update.
				_attachment_ratio = (position.x + anchor.x - float(_attachment.source_left)) / float(_attachment.source_width)
				pet.profile.desktop_position = position
				return
		# Rebase the free drag at the current position: horizontal sliding may
		# already have moved the window or reached the end of the support.
		_lifted_from_edge = true
		_release_attachment(false)
		_press_position = position
		_press_cursor = cursor
		_dragging = true
		pet.behavior.request_action("drag")
	elif not _dragging:
		_dragging = true
		if not _is_phone():
			pet.behavior.request_action("drag")
	position = _press_position + Vector2i(cursor - _press_cursor)


func _finish_press(cursor: Vector2) -> void:
	_pressing = false
	if _dragging:
		if _is_phone():
			position = clamp_position(position, size, current_work_area())
		elif _attachment.is_empty():
			# An intentional lift must not immediately snap back into the enlarged
			# taskbar zone on release. A new drag can attach again normally.
			if _lifted_from_edge or not _try_attach():
				position = clamp_position(position, size, current_work_area())
				pet.behavior.request_action("idle")
				say("就待在这里吧。")
		pet.profile.desktop_position = position
		_position_x = position.x
		settings_changed.emit()
	elif cursor.distance_to(_press_local_position) < 6.0 and not _over_controls(cursor):
		var region: String = _touch_regions.region_at(cursor - surface.position, is_minimal_mode() or not pet.profile.desktop_dialogue_enabled)
		if not region.is_empty():
			touch_requested.emit(pet.instance_id, region)
		elif pet.profile.desktop_dialogue_enabled and not is_minimal_mode():
			bubble_page_requested.emit(1)
	_dragging = false
	_lifted_from_edge = false


func _can_attach() -> bool:
	return pet != null and not _is_phone() and pet.behavior.motion_actions.has(_edge_action()) and bridge.has_method("GetDesktopSurfaces")


func _edge_action() -> String:
	return pet.profile.edge_posture if pet.profile.visual_id == "sprite2d" else "edge_rest"


func _refresh_edge_controls() -> void:
	if _edge_button == null:
		return
	_edge_button.disabled = not _can_attach()
	_edge_button.text = "坐在任务栏" if _edge_action() == "sit" else "趴在任务栏"
	_release_button.disabled = _attachment.is_empty()
	_layout_attachment_controls()


func _layout_attachment_controls() -> void:
	if _toolbar == null:
		return
	var bottom := float(size.y) if _attachment.is_empty() else pet.presenter.get_support_anchor().y - 8.0
	_position_toolbar()
	_menu.position.y = maxf(8.0, bottom - _menu.size.y - 8.0)


func _try_attach(taskbar_only: bool = false) -> bool:
	if not _can_attach():
		return false
	var anchor := Vector2(position) + pet.presenter.get_support_anchor()
	var candidates: Array = bridge.call("GetDesktopSurfaces")
	var previous_position := position
	var previous_attachment := _attachment.duplicate()
	var best: Dictionary = {}
	var best_distance := INF
	var best_ratio := 0.5
	pet.presenter.set_surface_attachment(true)
	if pet.profile.visual_id == "sprite2d":
		resize_pet(display_scale(), false)
	for candidate: Dictionary in candidates:
		if taskbar_only and candidate.kind != "taskbar":
			continue
		var distance := absf(anchor.y - float(candidate.y))
		var snap_distance := TASKBAR_SNAP_DISTANCE * maxf(1.0, pet.profile.desktop_scale) if candidate.kind == "taskbar" else 54.0 * pet.profile.desktop_scale
		if not taskbar_only and distance > snap_distance:
			continue
		# Manual taskbar placement is confined to the current monitor/workspace.
		var area := current_work_area()
		if taskbar_only and (candidate.right <= area.position.x or candidate.left >= area.end.x or absf(float(candidate.y) - area.end.y) > 80.0):
			continue
		var ratio := clampf((anchor.x - float(candidate.source_left)) / maxf(float(candidate.source_width), 1.0), 0.0, 1.0)
		if not taskbar_only and (anchor.x < candidate.left or anchor.x > candidate.right):
			continue
		if distance >= best_distance or not _place_on_surface(candidate, ratio, false):
			continue
		best = candidate
		best_ratio = ratio
		best_distance = distance
	position = previous_position
	if best.is_empty():
		pet.presenter.set_surface_attachment(not previous_attachment.is_empty())
		if pet.profile.visual_id == "sprite2d":
			resize_pet(display_scale(), false)
		return false
	# Cancel any active dialogue performance before installing the attachment:
	# cancellation can emit idle, which otherwise immediately releases this edge.
	pet.behavior.request_action(_edge_action())
	pet.presenter.set_surface_attachment(true)
	_attachment = best.duplicate()
	_attachment_ratio = best_ratio
	_place_on_surface(_attachment, _attachment_ratio)
	_attachment_ratio = (position.x + pet.presenter.get_support_anchor().x - float(_attachment.source_left)) / float(_attachment.source_width)
	_attachment_time = 0.0
	pet.presenter.set_expression("")
	_refresh_edge_controls()
	_last_regions.clear()
	pet.profile.desktop_position = position
	settings_changed.emit()
	say("坐在这里陪你。" if _edge_action() == "sit" else "趴在这里陪你。")
	return true


func _place_on_surface(candidate: Dictionary, ratio: float, move_window: bool = true) -> bool:
	var anchor := pet.presenter.get_support_anchor()
	var rect := pet.presenter.get_interaction_rect()
	var left_extent := anchor.x - rect.position.x
	var right_extent := rect.end.x - anchor.x
	var minimum := float(candidate.left) + left_extent + 6.0
	var maximum := float(candidate.right) - right_extent - 6.0
	if minimum > maximum:
		return false
	var desired_x := float(candidate.source_left) + float(candidate.source_width) * ratio
	var x := clampf(desired_x, minimum, maximum)
	var desired := Vector2(x, float(candidate.y)) - anchor
	var visible_rect := Rect2(desired + rect.position, rect.size)
	# An upper border at the screen top has no room for a character above it.
	var fits := false
	if DisplayServer.get_name() == "headless":
		fits = Rect2(0, 0, 1920, 1080).encloses(visible_rect)
	else:
		for screen: int in DisplayServer.get_screen_count():
			var screen_rect := Rect2(Vector2(DisplayServer.screen_get_position(screen)), Vector2(DisplayServer.screen_get_size(screen)))
			if screen_rect.encloses(visible_rect):
				fits = true
				break
	if not fits:
		return false
	if move_window:
		position = Vector2i(desired.round())
	return true


func _update_attachment() -> void:
	if not _can_attach():
		_release_attachment(true)
		return
	var candidates: Array = bridge.call("GetDesktopSurfaces")
	for candidate: Dictionary in candidates:
		if candidate.id != _attachment.id:
			continue
		var desired_x := float(candidate.source_left) + float(candidate.source_width) * _attachment_ratio
		# Do not jump to another visible fragment when the current spot is covered.
		if desired_x < candidate.left or desired_x > candidate.right:
			continue
		if _place_on_surface(candidate, _attachment_ratio):
			_attachment = candidate.duplicate()
			pet.profile.desktop_position = position
			return
	_release_attachment(true)


func _release_attachment(return_to_idle: bool) -> void:
	if _attachment.is_empty():
		return
	_attachment.clear()
	pet.presenter.set_surface_attachment(false)
	pet.presenter.set_expression("")
	if return_to_idle:
		pet.behavior.request_action("idle")
		position = clamp_position(position, size, current_work_area())
		pet.profile.desktop_position = position
		settings_changed.emit()
	_position_x = position.x
	_last_regions.clear()
	_refresh_edge_controls()


func _on_visual_changed(_visual: String) -> void:
	_release_attachment(true)
	refresh_presentation()
	_refresh_edge_controls()


func _is_phone() -> bool:
	return is_chat_mode() or is_minimal_mode()


func is_chat_mode() -> bool:
	return pet != null and pet.profile.visual_id == "sprite2d" and pet.profile.desktop_mode == "call"


func is_minimal_mode() -> bool:
	return pet != null and pet.profile.visual_id == "sprite2d" and pet.profile.desktop_mode == "minimal"


func display_scale() -> float:
	return pet.profile.minimal_monitor_scale if is_minimal_mode() else pet.profile.desktop_scale


func refresh_presentation() -> void:
	_stop_wandering()
	_release_attachment(true)
	pet.behavior.request_action("idle", "system")
	pet.set_presentation_mode("call" if _is_phone() else "full_body")
	_sync_minimal_mode()
	resize_pet(display_scale())
	_refresh_edge_controls()


func _on_wardrobe_changed() -> void:
	resize_pet(display_scale())
	_refresh_edge_controls()


func _wander(delta: float) -> void:
	if not bool(pet.presenter.get_capabilities().get("can_wander", true)):
		_stop_wandering()
		return
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = _rng.randf_range(4.0, 8.0)
		_wander_direction = [-1.0, 0.0, 1.0][_rng.randi_range(0, 2)]
	if pet.behavior.current_action not in ["idle", "walk"]:
		_stop_wandering()
		return
	var area := current_work_area()
	if _wander_direction == 0:
		_stop_wandering()
		if pet.behavior.current_action == "walk":
			pet.behavior.request_action("idle")
		return
	if pet.behavior.current_action != "walk":
		_position_x = position.x
		pet.behavior.request_action("walk")
	_walking_on_desktop = true
	_position_x += _wander_direction * 22.0 * delta
	var desired := Vector2i(roundi(_position_x), area.end.y - size.y - 8)
	position = clamp_position(desired, size, area)
	if position.x != desired.x:
		_wander_direction *= -1.0
		_position_x = position.x
	pet.presenter.set_walk_direction(_wander_direction)
	pet.profile.desktop_position = position


func _play_portrait_or_motion(action: String) -> void:
	_menu.hide()
	if action in ["sit", "sit_edge", "prone", "edge_rest"]:
		pet.profile.edge_posture = "sit" if action in ["sit", "sit_edge"] else "prone"
		pet.behavior.request_action(_edge_action())
		if _attachment.is_empty():
			_try_attach(true)
		else:
			pet.presenter.set_surface_attachment(true)
			resize_pet(display_scale())
			_update_attachment()
		settings_changed.emit()
	elif action in ["walk_left", "walk_right"]:
		pet.profile.wander = true
		_wander_direction = -1.0 if action == "walk_left" else 1.0
		_wander_time = 8.0
		pet.behavior.request_action("walk")
		pet.presenter.set_walk_direction(_wander_direction)
		settings_changed.emit()
	else:
		pet.behavior.request_action(action)


func _stop_wandering() -> void:
	if not _walking_on_desktop:
		return
	_walking_on_desktop = false
	pet.presenter.set_walk_direction(0.0)
	if pet.behavior.current_action == "walk":
		pet.behavior.request_action("idle", "system")


func _update_regions() -> void:
	if DisplayServer.get_name() == "headless" or pet.presenter == null:
		return
	var regions: Array[Rect2] = input_regions()
	if regions == _last_regions:
		return
	if bridge.call("SetInputRegions", get_window_id(), regions):
		_last_regions = regions


func input_regions() -> Array[Rect2]:
	var character_rect := Rect2(Vector2.ZERO, Vector2(size)) if _is_phone() else Rect2(surface.position + pet.presenter.get_interaction_rect().position, pet.presenter.get_interaction_rect().size)
	var regions: Array[Rect2] = [character_rect]
	if _toolbar.visible:
		regions.append(_toolbar.get_rect().grow(6))
	if _unread_button.visible:
		regions.append(_unread_button.get_rect().grow(3))
	if _bubble.visible:
		regions.append(_bubble.get_rect().grow(3))
	if _description_bubble.visible:
		regions.append(_description_bubble.get_rect().grow(3))
	if _menu.visible:
		regions.append(_menu.get_rect().grow(3))
	if _wheel.visible:
		regions.append(_wheel.get_rect().grow(3))
	return regions


func set_unread_count(count: int) -> void:
	_unread_count = count
	_unread_button.text = str(count) if count < 100 else "99+"
	_unread_button.visible = count > 0 and pet.profile.desktop_dialogue_enabled and not is_minimal_mode()
	_region_time = 0.0


func _update_toolbar(delta: float, cursor: Vector2) -> void:
	if is_minimal_mode():
		_toolbar.hide()
		return
	if pet.presenter == null:
		return
	var character_rect := Rect2(Vector2.ZERO, Vector2(size)) if _is_phone() else Rect2(surface.position + pet.presenter.get_interaction_rect().position, pet.presenter.get_interaction_rect().size)
	var hovered := character_rect.has_point(cursor) or (_toolbar.visible and _toolbar.get_rect().grow(10).has_point(cursor))
	if hovered or _menu.visible or _wheel.visible:
		_toolbar_timeout = 0.6
	else:
		_toolbar_timeout = maxf(0, _toolbar_timeout - delta)
	var should_show := _toolbar_timeout > 0
	if _toolbar.visible != should_show:
		_toolbar.visible = should_show
		_region_time = 0.0


func _toggle_menu() -> void:
	_refresh_edge_controls()
	_menu.hide()
	if _wheel.visible:
		_wheel.hide()
	else:
		_wheel.open_for(pet, Vector2(size) * 0.5, true)
	_region_time = 0.0


func _on_action(action: String) -> void:
	if action != "walk":
		_walking_on_desktop = false
		pet.presenter.set_walk_direction(0.0)
	if action not in ["edge_rest", "sit", "prone", "sit_edge"] and pet.behavior.current_origin != "touch" and not _attachment.is_empty():
		_release_attachment(false)
	if pet.profile.visual_id == "sprite2d":
		resize_pet(display_scale())
	if _silent_greeting:
		return
	if pet.behavior.current_origin in ["touch", "ambient"]:
		return
	var phrases := {"greet": "嗨，今天也一起加油！", "head_pat": "嘿嘿，好舒服。", "happy": "和你在一起很开心！", "surprised": "欸？发生什么啦？", "drag": "要搬家了吗？"}
	if phrases.has(action):
		say(phrases[action])


func set_dialogue(dialogue: String, description: String, index: int = 0, total: int = 0) -> void:
	_reply_dialogue = dialogue
	_reply_index = index
	_reply_total = total
	_bubble_timer = 0.0
	_system_notice = false
	_bubble.set_text(dialogue)
	_description_bubble.set_text(description, true)
	_bubble.set_navigation(index, total)
	_description_bubble.set_navigation(index, total)
	_layout_dialogue()
	_region_time = 0.0


func _layout_dialogue() -> void:
	_bubble.visible = not is_minimal_mode() and (pet.profile.desktop_dialogue_enabled or _system_notice) and _bubble.has_text() and _bubble.is_enabled()
	_description_bubble.visible = not is_minimal_mode() and pet.profile.desktop_dialogue_enabled and _description_bubble.has_text() and _description_bubble.is_enabled()
	_bubble.fit(maxf(100, size.x - 28), minf(110, size.y * 0.2) if _is_phone() else 110)
	_description_bubble.fit(maxf(100, size.x - 28), 80)
	_bubble.position = Vector2(14, 10)
	_description_bubble.position = Vector2(14, size.y - _description_bubble.size.y - maxf(54, _toolbar.size.y + 16))
	if _is_phone():
		_layout_character_surface()


func _layout_character_surface() -> void:
	var area := Rect2(Vector2.ZERO, Vector2(size))
	if is_minimal_mode():
		var portrait_width := maxf(96, size.x * 0.34)
		area = Rect2(4, 4, portrait_width - 4, size.y - 8)
		_minimal_background.size = Vector2(size)
		if _minimal_divider != null:
			_minimal_divider.position = Vector2(portrait_width, 16)
			_minimal_divider.size = Vector2(1, maxf(0, size.y - 32))
		if _minimal_scroll != null:
			_minimal_scroll.position = Vector2(portrait_width + 6, 4)
			_minimal_scroll.size = Vector2(size.x - portrait_width - 10, size.y - 8)
	elif _is_phone() and _bubble != null and _toolbar != null:
		var upper := _bubble.size.y + 22 if _bubble.visible else 8.0
		var lower := maxf(54, _toolbar.size.y + 16)
		if _description_bubble.visible:
			lower += _description_bubble.size.y + 12
		area.position.y = upper
		area.size.y = maxf(80, size.y - upper - lower)
	if surface.position == area.position and surface.size == area.size:
		return
	surface.position = area.position
	surface.size = area.size
	if pet != null and pet.presenter != null:
		pet.presenter.configure_surface(Vector2i(area.size))


func say(message: String, system_notice: bool = false) -> void:
	if not pet.profile.desktop_dialogue_enabled and not system_notice:
		return
	_system_notice = system_notice
	_bubble.set_text(message)
	_bubble.set_navigation(0, 0)
	_bubble.visible = _bubble.is_enabled()
	_bubble_timer = 4.0
	_region_time = 0.0


func refresh_touch_regions() -> void:
	_touch_toggle.set_pressed_no_signal(PalUi.show_touch_regions)
	_touch_regions.refresh()


func refresh_overlay() -> void:
	if _monitor_window != null:
		_monitor_window.theme = theme
		_monitor_window.call("ConfigureTheme", PalUi.PAPER, PalUi.SURFACE, PalUi.TEXT, PalUi.MUTED, PalUi.ACCENT, PalUi.BORDER)
	_refresh_minimal_glass()
	PalUi.overlay_controls(_toolbar)
	_layout_character_surface()
	_layout_dialogue()
	_region_time = 0.0


func detach_pet(destination: Node) -> void:
	_stop_wandering()
	_release_attachment(false)
	var was_monitor_only := pet.monitor_only
	pet.monitor_only = false
	pet.profile.desktop_position = position
	pet.behavior.action_requested.disconnect(_on_action)
	pet.visual_changed.disconnect(_on_visual_changed)
	pet.wardrobe_changed.disconnect(_on_wardrobe_changed)
	pet.behavior.request_action("idle")
	pet.reparent(destination, false)
	hide()
	if was_monitor_only:
		monitor_mode_changed.emit()


func current_work_area() -> Rect2i:
	if DisplayServer.get_name() == "headless":
		return Rect2i(0, 0, 1920, 1040)
	var center := position + size / 2
	for screen: int in DisplayServer.get_screen_count():
		var area := DisplayServer.screen_get_usable_rect(screen)
		if area.has_point(center):
			return area
	return DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())


static func clamp_position(candidate: Vector2i, window_size: Vector2i, area: Rect2i) -> Vector2i:
	return Vector2i(clampi(candidate.x, area.position.x, maxi(area.position.x, area.end.x - window_size.x)),
		clampi(candidate.y, area.position.y, maxi(area.position.y, area.end.y - window_size.y)))
