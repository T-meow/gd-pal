class_name PalDialogueScroll
extends ScrollContainer

var _dragging := false
var _drag_origin := Vector2.ZERO
var _drag_scroll := 0


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = 6


func _gui_input(event: InputEvent) -> void:
	if PalUi.is_mobile():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_origin = get_global_mouse_position()
		_drag_scroll = scroll_vertical


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if not is_visible_in_tree():
		_dragging = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	elif event is InputEventMouseMotion:
		var distance := get_global_mouse_position().y - _drag_origin.y
		if absf(distance) >= 6:
			scroll_vertical = _drag_scroll - roundi(distance)
			get_viewport().set_input_as_handled()
