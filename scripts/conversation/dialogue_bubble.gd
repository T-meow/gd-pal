class_name PalDialogueBubble
extends PanelContainer

signal page_requested(direction: int)

var _body: RichTextLabel
var _scroll: PalDialogueScroll
var _text := ""
var _description := false
var _previous: Button
var _next: Button
var _page_pressed := false
var _page_press_position := Vector2.ZERO


func _ready() -> void:
	set_meta("pal_fixed_palette", true)
	add_to_group("pal_bubbles")
	add_theme_stylebox_override("panel", PalUi.overlay_panel(16, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_previous = _arrow("‹", -1, row)
	_scroll = PalDialogueScroll.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_scroll)
	_scroll.gui_input.connect(_on_page_input)
	gui_input.connect(_on_page_input)
	_body = RichTextLabel.new()
	_body.fit_content = true
	_body.scroll_active = false
	_body.selection_enabled = false
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("normal_font_size", 16)
	_scroll.add_child(_body)
	_next = _arrow("›", 1, row)
	set_navigation(0, 0)
	refresh_overlay()
	hide()


func _arrow(caption: String, direction: int, parent: Control) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(30, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta("pal_fixed_palette", true)
	button.add_theme_font_size_override("font_size", 26)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, PalUi.panel(Color(1, 1, 1, 0.10 if state in ["hover", "pressed"] else 0.0), 8, 0))
		button.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", Color(PalUi.OVERLAY_TEXT, 0.25 if state == "disabled" else 1.0))
	parent.add_child(button)
	button.pressed.connect(func() -> void: page_requested.emit(direction))
	return button


func set_navigation(index: int, total: int) -> void:
	_previous.visible = total > 0
	_next.visible = total > 0
	_previous.disabled = index <= 0
	_next.disabled = index + 1 >= total
	_previous.tooltip_text = "上一句 · %d / %d" % [index + 1, total]
	_next.tooltip_text = "下一句 · %d / %d" % [index + 1, total]
	_scroll.tooltip_text = "第 %d / %d 段%s" % [index + 1, total, " · 点击继续" if not _next.disabled else ""] if total > 0 else ""
	_scroll.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _next.disabled else Control.CURSOR_ARROW


func _on_page_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_page_pressed = true
		_page_press_position = get_global_mouse_position()
	else:
		var clicked := _page_pressed and get_global_mouse_position().distance_to(_page_press_position) < 6.0
		_page_pressed = false
		if clicked and not _next.disabled:
			page_requested.emit(1)
	accept_event()


func set_text(value: String, description: bool = false) -> void:
	_description = description
	refresh_overlay()
	if value == _text:
		return
	_text = value
	_body.text = value
	PalUi.overlay_text(_body, description)
	_body.add_theme_font_size_override("normal_font_size", 14 if description else 16)
	_scroll.scroll_vertical = 0


func fit(width: float, height: float) -> void:
	size = Vector2(width, clampf(_body.get_content_height() + 26.0, 68.0, maxf(68.0, height)))


func has_text() -> bool:
	return not _text.is_empty()


func is_enabled() -> bool:
	return PalUi.description_bubbles if _description else PalUi.dialogue_bubbles


func refresh_overlay() -> void:
	add_theme_stylebox_override("panel", PalUi.overlay_panel(16, 12))
	if _body != null:
		PalUi.overlay_text(_body, _description)
	if not is_enabled():
		hide()
