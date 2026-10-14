extends Control
## The same circles drive hit testing and the optional visual overlay.

var surface: SubViewportContainer
var _regions: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	add_to_group("pal_touch_regions")
	refresh()


static func regions_for(bounds: Rect2, close_up: bool) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	if bounds.size.x < 8 or bounds.size.y < 16:
		return regions
	var radius := minf(52.0, minf(bounds.size.x * 0.13, bounds.size.y * 0.065))
	var locations := PackedVector2Array([Vector2(0.5, 0.18), Vector2(0.62, 0.43), Vector2(0.42, 0.76)]) if close_up else PackedVector2Array([Vector2(0.5, 0.12), Vector2(0.62, 0.31), Vector2(0.42, 0.58)])
	var names := ["upper", "middle", "lower"]
	for index: int in locations.size():
		var center := bounds.position + bounds.size * locations[index]
		regions.append({"region": names[index], "center": center, "radius": radius})
	return regions


func refresh() -> void:
	var next: Array[Dictionary] = []
	if is_instance_valid(surface) and surface.is_visible_in_tree():
		global_position = surface.global_position
		size = surface.size
		for child: Node in surface.get_children():
			if child is PalPetInstance and child.presenter != null:
				var factor := surface.size / Vector2(child.size).max(Vector2.ONE)
				var bounds: Rect2 = child.presenter.get_interaction_rect()
				bounds = Rect2(bounds.position * factor, bounds.size * factor).intersection(Rect2(Vector2.ZERO, surface.size))
				next = regions_for(bounds, child.presentation_mode == "call")
				break
	if next != _regions:
		_regions = next
		queue_redraw()
	visible = PalUi.show_touch_regions and not _regions.is_empty()


func region_at(point: Vector2) -> String:
	refresh()
	for region: Dictionary in _regions:
		if point.distance_squared_to(region.center) <= float(region.radius) * float(region.radius):
			return str(region.region)
	return ""


func _process(_delta: float) -> void:
	if PalUi.show_touch_regions or visible:
		refresh()


func _draw() -> void:
	for region: Dictionary in _regions:
		draw_circle(region.center, float(region.radius), Color(0.80, 0.92, 1.0, 0.16))
		draw_arc(region.center, float(region.radius), 0, TAU, 64, Color(0.65, 0.84, 1.0, 0.65), 1.5, true)
