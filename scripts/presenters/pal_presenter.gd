class_name PalPresenter
extends Node
## Shared presentation boundary for sprite and VRM implementations.

signal action_finished(action: String)

var presentation_mode := "full_body"
var adult_mode := false
var outfit := "maid"


func set_outfit(value: String) -> void:
	outfit = value


func set_adult_mode(value: bool) -> void:
	adult_mode = value


func set_presentation_mode(value: String) -> void:
	presentation_mode = value

func configure_surface(_surface_size: Vector2i) -> void:
	pass


func apply_render_settings(_settings: Dictionary) -> void:
	pass


func play_action(_action: String) -> void:
	pass


func set_expression(_expression: String) -> void:
	pass


func get_capabilities() -> Dictionary:
	return {}


func get_portrait_texture() -> Texture2D:
	return null


func prepare(_profile: PalProfile) -> String:
	return ""


func set_look_target(_target: Vector2) -> void:
	pass


func set_walk_direction(_direction: float) -> void:
	pass


func get_interaction_rect() -> Rect2:
	return Rect2(Vector2(48, 24), Vector2(224, 280))


func set_surface_attachment(_enabled: bool) -> void:
	pass


func get_support_anchor() -> Vector2:
	var rect := get_interaction_rect()
	return Vector2(rect.get_center().x, rect.end.y)
