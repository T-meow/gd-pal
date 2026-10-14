class_name PalUi
extends RefCounted

static var PAPER := Color("10151d")
static var SURFACE := Color("192332")
static var BLUE := Color("243347")
static var MINT := Color("30445d")
static var TEXT := Color("edf2f8")
static var MUTED := Color("95a7bc")
static var ACCENT := Color("acc9e7")
static var BORDER := Color("c5d9f21a")
static var ERROR := Color("f1a4a8")
static var YELLOW := Color("dfc39f")
static var SKY := Color("a7c8e8")
static var PRIMARY := Color("acc9e7")
static var ON_ACCENT := Color("10151d")
static var appearance_mode := "dark"
static var theme_color := Color("acc9e7")
static var _appearance_configured := false
static var overlay_opacity := 0.25
static var dialogue_bubbles := true
static var description_bubbles := true
static var show_touch_regions := false
static var dialogue_autoplay := false
const OVERLAY_TEXT := Color("f6f8fc")
const OVERLAY_MUTED := Color("e0e6ef")


static func is_light() -> bool:
	return appearance_mode == "light"


static func configure_appearance(mode: String, color: Color) -> void:
	appearance_mode = "light" if mode == "light" else "dark"
	theme_color = Color(color.r, color.g, color.b, 1.0)
	_appearance_configured = true
	_configure_palette()


static func _configure_palette() -> void:
	if not _appearance_configured:
		appearance_mode = "light" if is_mobile() else "dark"
		theme_color = Color("2468b5") if is_mobile() else Color("acc9e7")
	var colors: Array = ["f4f9ff", "ffffff", "e5f2ff", "d6efff", "223750", "536b84", "2468b5", "cbdfef", "ac344d", "976514", "256884"] if is_light() else ["10151d", "192332", "243347", "30445d", "edf2f8", "95a7bc", "acc9e7", "c5d9f21a", "f1a4a8", "dfc39f", "a7c8e8"]
	PAPER = Color(colors[0])
	SURFACE = Color(colors[1])
	BLUE = Color(colors[2])
	MINT = Color(colors[3])
	TEXT = Color(colors[4])
	MUTED = Color(colors[5])
	ACCENT = Color(colors[6])
	BORDER = Color(colors[7])
	ERROR = Color(colors[8])
	YELLOW = Color(colors[9])
	SKY = Color(colors[10])
	PRIMARY = theme_color
	ON_ACCENT = contrast_text(theme_color)
	ACCENT = theme_color
	while is_light() and ACCENT.srgb_to_linear().get_luminance() > 0.18:
		ACCENT = ACCENT.darkened(0.12)
	while not is_light() and ACCENT.srgb_to_linear().get_luminance() < 0.35:
		ACCENT = ACCENT.lightened(0.14)
	BLUE = Color("edf2f8").lerp(theme_color, 0.15) if is_light() else Color("202b3a").lerp(theme_color, 0.12)
	MINT = BLUE.lerp(theme_color, 0.18)


static func is_mobile() -> bool:
	return OS.has_feature("android") or "--mobile-ui" in OS.get_cmdline_user_args() or OS.get_environment("GD_PAL_MOBILE_PREVIEW") == "1"


static func mobile_rect(control: Control, include_keyboard: bool = true) -> Rect2:
	var area := Rect2(Vector2.ZERO, control.size)
	if OS.has_feature("android") and DisplayServer.get_name() != "headless":
		var transform := control.get_viewport().get_screen_transform().affine_inverse()
		area = area.intersection(transform * Rect2(DisplayServer.get_display_safe_area()))
		if include_keyboard:
			var keyboard := DisplayServer.virtual_keyboard_get_height()
			if keyboard > 0:
				var bottom := transform * Vector2(0, DisplayServer.screen_get_size().y - keyboard)
				area.size.y = maxf(0, minf(area.end.y, bottom.y) - area.position.y)
	# The same geometry is exercised by the headless mobile regression test.
	if include_keyboard and control.has_meta("mobile_test_rect"):
		area = control.get_meta("mobile_test_rect")
	return area


static func keyboard_height() -> int:
	return DisplayServer.virtual_keyboard_get_height() if OS.has_feature("android") and DisplayServer.get_name() != "headless" else 0


static func configure_mobile_window(window: Window) -> void:
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	window.min_size = Vector2i.ZERO
	window.max_size = Vector2i.ZERO
	if OS.has_feature("android"):
		window.content_scale_factor = clampf(DisplayServer.screen_get_dpi() / 160.0, 1.0, 4.0)
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
	else:
		window.content_scale_factor = 1.0
		window.size = Vector2i(393, 852)


static func contrast_text(background: Color) -> Color:
	return Color.BLACK if background.srgb_to_linear().get_luminance() > 0.179 else Color.WHITE


static func make_theme() -> Theme:
	_configure_palette()
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans SC", "sans-serif"] if is_mobile() else ["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	result.default_font = font
	result.default_font_size = 16
	for control: String in ["Label", "Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "RichTextLabel", "PopupMenu", "ItemList", "Tree", "TabContainer"]:
		for key: String in ["font_color", "font_hover_color", "font_hovered_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "default_color"]:
			result.set_color(key, control, TEXT)
		result.set_color("font_disabled_color", control, MUTED)
		result.set_color("font_placeholder_color", control, MUTED)
		result.set_color("font_selected_color", control, TEXT)
		result.set_color("selection_color", control, MINT)
		result.set_color("caret_color", control, ACCENT)
	for control: String in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		result.set_stylebox("normal", control, panel(SURFACE, 8, 10))
		result.set_stylebox("hover", control, panel(BLUE, 8, 10))
		result.set_stylebox("pressed", control, panel(MINT, 8, 10))
		result.set_stylebox("hover_pressed", control, panel(MINT, 8, 10))
		result.set_stylebox("disabled", control, panel(PAPER, 8, 10))
		var focus := panel(Color.TRANSPARENT, 8, 10)
		focus.border_color = ACCENT
		focus.set_border_width_all(2)
		result.set_stylebox("focus", control, focus)
	for control: String in ["LineEdit", "TextEdit", "ItemList", "Tree"]:
		result.set_stylebox("normal", control, panel(SURFACE, 12, 10))
		result.set_stylebox("read_only", control, panel(PAPER, 12, 10))
		result.set_stylebox("focus", control, panel(BLUE, 12, 10))
	result.set_color("font_readonly_color", "TextEdit", TEXT)
	result.set_color("font_uneditable_color", "LineEdit", TEXT)
	for control: String in ["ItemList", "Tree"]:
		result.set_stylebox("panel", control, panel(SURFACE, 12, 10))
	result.set_stylebox("panel", "PopupMenu", panel(PAPER, 12, 10))
	result.set_stylebox("hover", "PopupMenu", panel(BLUE, 8, 6))
	result.set_stylebox("panel", "AcceptDialog", panel(PAPER, 20, 16))
	result.set_stylebox("panel", "TooltipPanel", panel(Color("15202bef"), 8, 10))
	result.set_color("font_color", "TooltipLabel", OVERLAY_TEXT)
	result.set_color("title_color", "Window", TEXT)
	for control: String in ["LineEdit", "TextEdit", "RichTextLabel", "ItemList", "Tree"]:
		result.set_color("font_selected_color", control, ON_ACCENT)
		result.set_color("selection_color", control, PRIMARY)
	for control: String in ["ItemList", "Tree"]:
		result.set_stylebox("selected", control, panel(PRIMARY, 6, 6))
		result.set_stylebox("selected_focus", control, panel(PRIMARY, 6, 6))
		result.set_stylebox("hovered", control, panel(BLUE, 6, 6))
	result.set_constant("v_separation", "ItemList", 10)
	result.set_constant("h_separation", "Button", 8)
	result.set_constant("line_spacing", "RichTextLabel", 5)
	result.set_stylebox("panel", "TabContainer", panel(SURFACE, 8, 0))
	result.set_stylebox("tab_selected", "TabContainer", panel(BLUE, 6, 12))
	result.set_stylebox("tab_unselected", "TabContainer", panel(PAPER, 6, 12))
	result.set_stylebox("tab_hovered", "TabContainer", panel(MINT, 6, 12))
	result.set_color("font_selected_color", "TabContainer", TEXT)
	result.set_color("font_hovered_color", "TabContainer", TEXT)
	result.set_color("font_unselected_color", "TabContainer", MUTED)
	if not is_mobile():
		for control: String in ["VScrollBar", "HScrollBar"]:
			var track := panel(Color.TRANSPARENT, 4, 0)
			track.set_border_width_all(0)
			result.set_stylebox("scroll", control, track)
			for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
				var grabber := panel(Color("63799180"), 4, 3)
				grabber.set_border_width_all(0)
				result.set_stylebox(state, control, grabber)
		result.set_constant("outline_size", "Label", 0)
		result.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	if is_mobile():
		for control: String in ["OptionButton", "CheckButton", "CheckBox", "LineEdit"]:
			for state: String in ["normal", "hover", "pressed", "focus"]:
				var box := panel(BLUE if state in ["hover", "focus"] else SURFACE, 8, 10)
				box.content_margin_top = 14
				box.content_margin_bottom = 14
				result.set_stylebox(state, control, box)
		result.set_constant("v_separation", "PopupMenu", 24)
	return result


static func panel(color: Color, radius: int = 16, margin: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box


static func button(caption: String, parent: Node, callback: Callable, accent: bool = false) -> Button:
	var result := Button.new()
	result.text = caption
	result.custom_minimum_size = Vector2(48, 48) if is_mobile() else Vector2(0, 38)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if accent:
		result.set_meta("pal_accent", true)
		_style_accent(result)
	parent.add_child(result)
	result.pressed.connect(callback)
	return result


static func icon_button(caption: String, icon_name: String, parent: Node, callback: Callable, accent: bool = false) -> Button:
	var result := button(caption, parent, callback, accent)
	if caption.is_empty():
		result.custom_minimum_size.x = 48 if is_mobile() else 40
	result.icon = load("res://assets/ui/icons/" + icon_name + ".svg")
	var tint := ON_ACCENT if accent else ACCENT
	result.add_theme_color_override("icon_normal_color", tint)
	result.add_theme_color_override("icon_hover_color", tint)
	result.add_theme_color_override("icon_pressed_color", tint)
	result.expand_icon = true
	result.add_theme_constant_override("icon_max_width", 20)
	return result


static func danger(button_control: Button) -> void:
	button_control.set_meta("pal_danger", true)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button_control.add_theme_color_override(key, ERROR)
	button_control.add_theme_stylebox_override("hover", panel(SURFACE.lerp(ERROR, 0.15), 8, 10))


static func glass(opacity: float = 0.76, radius: int = 12, margin: int = 16) -> StyleBoxFlat:
	return panel(Color(SURFACE, opacity), radius, margin)


static func overlay_panel(radius: int = 14, margin: int = 8) -> StyleBoxFlat:
	var box := panel(Color(0.04, 0.06, 0.09, overlay_opacity), radius, margin)
	box.border_color = Color(1, 1, 1, 0.16)
	return box


static func overlay_text(control: Control, muted: bool = false) -> void:
	control.set_meta("pal_fixed_palette", true)
	var color := OVERLAY_MUTED if muted else OVERLAY_TEXT
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "default_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		control.add_theme_color_override(key, color)
	control.add_theme_color_override("font_outline_color", Color("080d14e6"))
	control.add_theme_constant_override("outline_size", 2)
	control.add_theme_color_override("font_shadow_color", Color("00000099"))
	control.add_theme_constant_override("shadow_offset_x", 1)
	control.add_theme_constant_override("shadow_offset_y", 1)


static func overlay_controls(root: Control, on_panel: bool = false) -> void:
	root.set_meta("pal_fixed_palette", true)
	on_panel = on_panel or bool(root.get_meta("pal_overlay_on_panel", false))
	if root is PanelContainer:
		root.add_theme_stylebox_override("panel", overlay_panel())
		on_panel = true
	if root is Button:
		root.set_meta("pal_overlay_button", true)
		root.set_meta("pal_overlay_on_panel", on_panel)
		overlay_text(root)
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := overlay_panel(8, 8)
			box.bg_color.a = (0.0 if on_panel else overlay_opacity) if state == "normal" else (0.15 if on_panel else minf(0.65, overlay_opacity + 0.15))
			box.set_border_width_all(0)
			root.add_theme_stylebox_override(state, box)
	elif root is Label:
		overlay_text(root)
	for child: Node in root.get_children():
		if child is Control:
			overlay_controls(child, on_panel)


static func quiet(button_control: Button, selected: bool = false) -> void:
	if button_control.get_meta("pal_overlay_button", false):
		overlay_controls(button_control)
		return
	button_control.set_meta("pal_quiet", selected)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var box := panel(BLUE if selected or state != "normal" else Color.TRANSPARENT, 8, 8)
		box.set_border_width_all(0)
		button_control.add_theme_stylebox_override(state, box)
	button_control.add_theme_color_override("font_color", TEXT if selected else MUTED)
	button_control.add_theme_color_override("icon_normal_color", TEXT if selected else MUTED)
	for key: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_hover_color", "icon_pressed_color"]:
		button_control.add_theme_color_override(key, TEXT)
	if button_control.has_meta("pal_dense"):
		dense(button_control, int(button_control.get_meta("pal_dense")))


static func dense(control: Control, height: int = 28) -> void:
	control.set_meta("pal_dense", height)
	control.custom_minimum_size.y = height
	control.add_theme_font_size_override("font_size", 12)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := control.get_theme_stylebox(state).duplicate() as StyleBox
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		box.content_margin_left = 7
		box.content_margin_right = 7
		control.add_theme_stylebox_override(state, box)


static func _style_accent(control: Button) -> void:
	var backgrounds := {"normal": PRIMARY, "hover": PRIMARY.lightened(0.1), "pressed": PRIMARY.darkened(0.1), "hover_pressed": PRIMARY.darkened(0.1)}
	for state: String in backgrounds:
		var background: Color = backgrounds[state]
		control.add_theme_stylebox_override(state, panel(background, 8, 10))
		control.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", contrast_text(background))
		if state in ["normal", "hover", "pressed"]:
			control.add_theme_color_override("icon_" + state + "_color", contrast_text(background))
	control.add_theme_color_override("font_focus_color", ON_ACCENT)


static func palette() -> Array[Color]:
	return [PAPER, SURFACE, BLUE, MINT, TEXT, MUTED, ACCENT, BORDER, ERROR, YELLOW, SKY, PRIMARY, ON_ACCENT]


static func apply_appearance(root: Control, mode: String, color: Color) -> void:
	var previous := palette()
	var old_theme := root.theme
	configure_appearance(mode, color)
	var next := palette()
	var new_theme := make_theme()
	_retheme(root, old_theme, new_theme, previous, next, {})
	root.theme = new_theme


static func _map_color(value: Color, previous: Array[Color], next: Array[Color]) -> Color:
	if value.a == 0:
		return value
	for index: int in previous.size():
		if value.is_equal_approx(previous[index]):
			return next[index]
	for index: int in previous.size():
		if Vector3(value.r, value.g, value.b).is_equal_approx(Vector3(previous[index].r, previous[index].g, previous[index].b)):
			return Color(next[index], value.a)
	return value


static func _retheme(node: Node, old_theme: Theme, new_theme: Theme, previous: Array[Color], next: Array[Color], styled: Dictionary) -> void:
	if node is Control or node is Window:
		if node.get("theme") == old_theme:
			node.set("theme", new_theme)
	if node is Control and not node.has_meta("pal_fixed_palette"):
		for property: Dictionary in node.get_property_list():
			var name := str(property.name)
			if name.begins_with("theme_override_colors/"):
				var value: Variant = node.get(name)
				if value is Color:
					node.set(name, _map_color(value, previous, next))
			elif name.begins_with("theme_override_styles/"):
				var box := node.get(name) as StyleBoxFlat
				if box != null and not styled.has(box.get_instance_id()):
					styled[box.get_instance_id()] = true
					box.bg_color = _map_color(box.bg_color, previous, next)
					box.border_color = _map_color(box.border_color, previous, next)
		if node is ColorRect:
			node.color = _map_color(node.color, previous, next)
		if node.modulate != Color.WHITE:
			node.modulate = _map_color(node.modulate, previous, next)
		if node is Button:
			if node.get_meta("pal_accent", false):
				_style_accent(node)
			if node.has_meta("pal_quiet"):
				quiet(node, bool(node.get_meta("pal_quiet")))
			if node.get_meta("pal_danger", false):
				danger(node)
		if node.has_meta("pal_dense"):
			dense(node, int(node.get_meta("pal_dense")))
	if node is CanvasItem:
		node.queue_redraw()
	for child: Node in node.get_children():
		_retheme(child, old_theme, new_theme, previous, next, styled)


static func compact_button(caption: String, parent: Node, callback: Callable) -> Button:
	var result := button(caption, parent, callback)
	result.custom_minimum_size.y = 48 if is_mobile() else 28
	result.add_theme_font_size_override("font_size", 12)
	for state: String in ["normal", "hover", "pressed"]:
		result.add_theme_stylebox_override(state, panel(Color.TRANSPARENT if state == "normal" else BLUE, 6, 4))
	return result


static func hint(caption: String, parent: Node) -> Label:
	var result := label(caption, parent, 13, true)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func card(parent: Node, color: Color = Color.TRANSPARENT, padding: int = 18) -> VBoxContainer:
	var surface := PanelContainer.new()
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.add_theme_stylebox_override("panel", panel(SURFACE if color == Color.TRANSPARENT else color, 10, padding))
	parent.add_child(surface)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	surface.add_child(column)
	return column


static func badge(caption: String, parent: Node, tint: Color) -> Label:
	var result := label(caption, parent, 12)
	result.add_theme_color_override("font_color", tint)
	result.add_theme_stylebox_override("normal", panel(BLUE, 6, 7))
	return result


static func clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


static func field(caption: String, parent: Node, placeholder: String = "") -> LineEdit:
	label(caption, parent, 14)
	var result := LineEdit.new()
	result.placeholder_text = placeholder
	result.custom_minimum_size.y = 48 if is_mobile() else 40
	parent.add_child(result)
	return result


static func work_area(window: Window) -> Rect2i:
	if DisplayServer.get_name() == "headless":
		return Rect2i(0, 0, 1920, 1040)
	return DisplayServer.screen_get_usable_rect(window.current_screen)


static func fit_window(window: Window, desired: Vector2i, minimum: Vector2i) -> void:
	if is_mobile():
		if window == window.get_tree().root:
			configure_mobile_window(window)
		return
	# The editor owns the embedded game's rectangle and input transform.
	if is_editor_preview(window):
		return
	var area := work_area(window)
	window.set_meta("pal_minimum", minimum)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_size = Vector2i.ZERO
	window.content_scale_factor = 1.0
	window.size = desired
	apply_window_scale(window, screen_scale(window), area)
	window.position = area.position + (area.size - window.size) / 2


static func screen_scale(window: Window) -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	return clampf(DisplayServer.screen_get_dpi(window.current_screen) / 96.0, 1.0, 4.0)


static func set_window_minimum(window: Window, logical_minimum: Vector2i) -> void:
	window.set_meta("pal_minimum", logical_minimum)
	window.min_size = Vector2i(Vector2(logical_minimum) * window.content_scale_factor)


static func apply_window_scale(window: Window, factor: float, area: Rect2i) -> void:
	var logical_size := Vector2(window.size) / window.content_scale_factor
	var minimum: Vector2i = window.get_meta("pal_minimum", Vector2i.ONE)
	var available := (area.size - Vector2i(24, 48)).max(Vector2i.ONE)
	# On a small work area, keep every control reachable even at a large OS scale.
	factor = minf(factor, minf(float(available.x) / maxi(minimum.x, 1), float(available.y) / maxi(minimum.y, 1)))
	window.content_scale_factor = maxf(0.01, factor)
	window.max_size = Vector2i.ZERO
	window.min_size = Vector2i(Vector2(minimum) * factor).min(available)
	window.max_size = available
	window.size = Vector2i(logical_size * factor).max(window.min_size).min(available)
	window.position = Vector2i(clampi(window.position.x, area.position.x, area.end.x - window.size.x), clampi(window.position.y, area.position.y, area.end.y - window.size.y))


static func sync_window_scale(window: Window) -> void:
	if is_mobile():
		return
	if DisplayServer.get_name() == "headless" or is_editor_preview(window):
		return
	var area := work_area(window)
	var signature := "%s:%s:%s" % [window.current_screen, DisplayServer.screen_get_dpi(window.current_screen), area]
	if window.get_meta("pal_screen", "") == signature:
		return
	window.set_meta("pal_screen", signature)
	apply_window_scale(window, screen_scale(window), area)


static func is_editor_preview(window: Window) -> bool:
	return Engine.is_embedded_in_editor() and window.is_inside_tree() and window == window.get_tree().root


static func reveal(control: Control) -> void:
	control.modulate.a = 0.0
	control.create_tween().tween_property(control, "modulate:a", 1.0, 0.18)


static func label(caption: String, parent: Node, font_size: int = 15, muted: bool = false) -> Label:
	var result := Label.new()
	result.text = caption
	result.add_theme_font_size_override("font_size", font_size)
	if muted:
		result.add_theme_color_override("font_color", MUTED)
	parent.add_child(result)
	return result
