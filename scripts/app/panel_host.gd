class_name PalPanelHost
extends Control
## One in-window management surface and a separate, keyboard-modal confirmation.

signal close_requested

var content: VBoxContainer
var active_view: Control
var page_id := ""
var _shade: ColorRect
var _sheet: PanelContainer
var _heading: Label
var _scroll: ScrollContainer
var _confirm_shade: ColorRect
var _confirm_sheet: PanelContainer
var _confirm_title: Label
var _confirm_text: Label
var _confirm_scroll: ScrollContainer
var _confirm_yes: Button
var _confirm_no: Button
var _confirm_alt: Button
var _accept := Callable()
var _alternate := Callable()
var _previous_focus: Control
var _confirm_focus: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade = _make_shade(Color(0.10, 0.20, 0.32, 0.35) if PalUi.is_mobile() else Color(0.025, 0.04, 0.065, 0.72))
	_sheet = PanelContainer.new()
	_sheet.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 12, 24))
	if PalUi.is_mobile():
		_sheet.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 0, 12))
	add_child(_sheet)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_sheet.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_heading = PalUi.label("", header, 24)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	PalUi.icon_button("" if PalUi.is_mobile() else "关闭", "close", header, func() -> void: close_requested.emit()).tooltip_text = "关闭页面"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_confirm_shade = _make_shade(Color(0.08, 0.17, 0.28, 0.5) if PalUi.is_mobile() else Color(0.025, 0.04, 0.065, 0.8))
	_confirm_sheet = PanelContainer.new()
	_confirm_sheet.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 12, 24))
	add_child(_confirm_sheet)
	var confirmation := VBoxContainer.new()
	confirmation.add_theme_constant_override("separation", 18)
	_confirm_sheet.add_child(confirmation)
	_confirm_title = PalUi.label("", confirmation, 22)
	_confirm_title.max_lines_visible = 2
	_confirm_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_confirm_scroll = ScrollContainer.new()
	_confirm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_confirm_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_confirm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_scroll.custom_minimum_size.y = 64
	confirmation.add_child(_confirm_scroll)
	_confirm_text = PalUi.hint("", _confirm_scroll)
	_confirm_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_text.add_theme_font_size_override("font_size", 16)
	var actions := HBoxContainer.new()
	confirmation.add_child(actions)
	_confirm_no = PalUi.button("取消", actions, cancel_confirmation)
	_confirm_alt = PalUi.button("", actions, func() -> void: _finish_confirmation(true))
	_confirm_yes = PalUi.button("继续", actions, func() -> void: _finish_confirmation(), true)
	for button: Button in [_confirm_no, _confirm_alt, _confirm_yes]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resized.connect(_layout)
	hide_panel()
	_confirm_shade.hide()
	_confirm_sheet.hide()
	_layout()


func _make_shade(color: Color) -> ColorRect:
	var shade := ColorRect.new()
	shade.color = color
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.focus_mode = Control.FOCUS_ALL
	add_child(shade)
	return shade


func _layout() -> void:
	if _sheet == null:
		return
	var dimensions := size
	if PalUi.is_mobile():
		var area := PalUi.mobile_rect(self)
		_sheet.position = area.position
		_sheet.size = area.size
		_confirm_sheet.size = Vector2(minf(560, area.size.x - 24), minf(320, area.size.y - 24))
		_confirm_sheet.position = area.get_center() - _confirm_sheet.size * 0.5
		return
	var preferred_width := float(active_view.get_meta("preferred_width", 940)) if is_instance_valid(active_view) else 940.0
	var preferred_height := float(active_view.get_meta("preferred_height", dimensions.y - 64)) if is_instance_valid(active_view) else dimensions.y - 64
	_sheet.size = Vector2(minf(preferred_width, dimensions.x - 64), maxf(240, minf(preferred_height, dimensions.y - 64)))
	_sheet.position = (dimensions - _sheet.size) * 0.5
	# Do not derive the outer height from text before wrapping has settled.
	# A restored tray window may still have stale child widths on this frame.
	_confirm_sheet.size = Vector2(minf(560, dimensions.x - 48), minf(300, dimensions.y - 48))
	_confirm_sheet.position = (dimensions - _confirm_sheet.size) * 0.5


func open_view(id: String, caption: String, view: Control) -> void:
	if not is_open():
		_previous_focus = get_viewport().gui_get_focus_owner()
	for child: Control in content.get_children():
		child.hide()
	page_id = id
	active_view = view
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if view.get_meta("self_scrolling", false) else ScrollContainer.SCROLL_MODE_AUTO
	_heading.text = caption
	view.show()
	_shade.show()
	_sheet.show()
	_shade.grab_focus()
	_scroll.scroll_vertical = 0
	PalUi.reveal(_sheet)
	_layout()


func is_open() -> bool:
	return _sheet != null and _sheet.visible


func set_return_focus(control: Control) -> void:
	_previous_focus = control


func is_confirming() -> bool:
	return _confirm_sheet != null and _confirm_sheet.visible


func is_dirty() -> bool:
	return is_open() and is_instance_valid(active_view) and active_view.has_method("is_dirty") and active_view.call("is_dirty")


func hide_panel() -> void:
	var was_open := is_open()
	if is_instance_valid(active_view):
		if active_view.has_method("before_close"):
			active_view.call("before_close")
		active_view.hide()
	active_view = null
	page_id = ""
	_sheet.hide()
	_shade.hide()
	if was_open:
		_restore_focus(_previous_focus)
	_previous_focus = null


func confirm(caption: String, message: String, accept_text: String, callback: Callable, alternate_text: String = "", alternate: Callable = Callable()) -> void:
	if is_confirming():
		return
	_confirm_focus = get_viewport().gui_get_focus_owner()
	_confirm_title.text = caption
	_confirm_text.text = message
	_confirm_yes.text = accept_text
	var destructive := "删除" in accept_text or "清除" in accept_text or "移除" in accept_text or "忘记" in accept_text or "放弃" in accept_text
	for state: String in ["normal", "hover", "pressed"]:
		var danger_color := PalUi.SURFACE.lerp(PalUi.ERROR, 0.15)
		_confirm_yes.add_theme_stylebox_override(state, PalUi.panel(danger_color if destructive else PalUi.PRIMARY, 8, 10))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_confirm_yes.add_theme_color_override(key, PalUi.ERROR if destructive else PalUi.ON_ACCENT)
	_confirm_alt.text = alternate_text
	_confirm_alt.visible = not alternate_text.is_empty()
	_accept = callback
	_alternate = alternate
	_confirm_scroll.scroll_vertical = 0
	_confirm_sheet.modulate = Color.WHITE
	_layout()
	_confirm_shade.show()
	_confirm_sheet.show()
	_confirm_no.grab_focus()
	_layout.call_deferred()


func cancel_confirmation() -> void:
	_confirm_shade.hide()
	_confirm_sheet.hide()
	_accept = Callable()
	_alternate = Callable()
	_restore_focus(_confirm_focus)


func _finish_confirmation(use_alternate: bool = false) -> void:
	var callback := _alternate if use_alternate else _accept
	cancel_confirmation()
	if callback.is_valid():
		callback.call()


func _restore_focus(control: Control) -> void:
	if is_instance_valid(control) and control.is_visible_in_tree():
		if DisplayServer.get_name() != "headless":
			control.get_window().grab_focus()
		control.grab_focus()


func _input(event: InputEvent) -> void:
	if PalUi.is_mobile() and event is InputEventKey and event.keycode == KEY_ESCAPE:
		return # The coordinator handles keyboard, detail, sheet and stage in order.
	if not is_open() and not is_confirming():
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			var owner := get_viewport().gui_get_focus_owner()
			if is_instance_valid(owner) and owner.has_method("has_ime_text") and owner.call("has_ime_text"):
				return
			if is_confirming():
				cancel_confirmation()
			else:
				close_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			# Keep keyboard focus inside the topmost sheet.
			var surface := _confirm_sheet if is_confirming() else _sheet
			var owner := get_viewport().gui_get_focus_owner()
			var next: Control = null
			if is_instance_valid(owner):
				next = owner.find_prev_valid_focus() if event.shift_pressed else owner.find_next_valid_focus()
			if next == null or not surface.is_ancestor_of(next):
				var candidates := surface.find_children("*", "Control", true, false)
				if event.shift_pressed:
					candidates.reverse()
				for candidate: Control in candidates:
					if candidate is BaseButton and candidate.disabled:
						continue
					if candidate.is_visible_in_tree() and candidate.focus_mode == Control.FOCUS_ALL:
						candidate.grab_focus()
						break
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if PalUi.is_mobile() and (is_open() or is_confirming()):
		_layout()
