class_name PalPhoneFrame
extends Control
## Reusable phone bezel. The existing character viewport occupies screen_rect().


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


static func fit_rect(area: Rect2) -> Rect2:
	var height := maxf(100.0, minf(area.size.y, area.size.x / 0.59))
	var dimensions := Vector2(height * 0.59, height)
	return Rect2(area.get_center() - dimensions * 0.5, dimensions)


func screen_rect() -> Rect2:
	var unit := size.x / 360.0
	return Rect2(Vector2(13, 57) * unit, Vector2(maxf(1, size.x - 26 * unit), maxf(1, size.y - 105 * unit)))


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var unit := size.x / 360.0
	var body := StyleBoxFlat.new()
	body.bg_color = PalUi.PAPER
	body.border_color = PalUi.MUTED
	body.set_border_width_all(maxi(1, roundi(2 * unit)))
	body.set_corner_radius_all(roundi(35 * unit))
	draw_style_box(body, Rect2(Vector2(2, 2), size - Vector2(4, 4)))
	var screen := StyleBoxFlat.new()
	screen.bg_color = PalUi.BLUE
	screen.set_corner_radius_all(roundi(22 * unit))
	draw_style_box(screen, Rect2(Vector2(10, 44) * unit, size - Vector2(20, 79) * unit))
	var speaker := StyleBoxFlat.new()
	speaker.bg_color = Color("030810")
	speaker.set_corner_radius_all(roundi(8 * unit))
	draw_style_box(speaker, Rect2(Vector2(size.x * 0.5 - 28 * unit, 18 * unit), Vector2(56, 8) * unit))
	draw_circle(Vector2(size.x * 0.5 + 42 * unit, 22 * unit), 4 * unit, PalUi.ACCENT)
	var home_bar := StyleBoxFlat.new()
	home_bar.bg_color = PalUi.MUTED
	home_bar.set_corner_radius_all(roundi(3 * unit))
	draw_style_box(home_bar, Rect2(Vector2(size.x * 0.5 - 43 * unit, size.y - 17 * unit), Vector2(86, 4) * unit))
	draw_string(get_theme_default_font(), Vector2(0, size.y - 38 * unit), "陪伴通话", HORIZONTAL_ALIGNMENT_CENTER, size.x, maxi(10, roundi(12 * unit)), PalUi.TEXT)
