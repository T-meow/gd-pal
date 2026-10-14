class_name PalPetInstance
extends SubViewport
## A preview surface with isolated rendering state and a persistent character identity.

signal visual_changed(visual_id: String)
signal capabilities_changed
signal load_failed(message: String)
signal wardrobe_changed

const PRESENTERS: Dictionary = {
	"sprite2d": preload("res://scenes/presenters/sprite_2d.tscn"),
	"vrm3d": preload("res://scenes/presenters/vrm_3d.tscn"),
}
var instance_id: String = ""
var profile: PalProfile
var behavior: PalBehavior
var presenter: PalPresenter
var last_error: String = ""
var presentation_mode := "full_body"


func _ready() -> void:
	world_2d = World2D.new()
	own_world_3d = true
	if profile == null:
		profile = PalProfile.new()
	if PalUi.is_mobile():
		profile.visual_id = "sprite2d"
	behavior = PalBehavior.new()
	behavior.name = "Behavior"
	add_child(behavior)
	behavior.action_requested.connect(_on_action_requested)
	size_changed.connect(_configure_presenter)
	switch_visual(profile.visual_id)


func switch_visual(visual_id: String) -> bool:
	if PalUi.is_mobile() and visual_id != "sprite2d":
		last_error = "安卓版仅支持 2D 立绘。"
		return false
	if not PRESENTERS.has(visual_id):
		return false
	var scene: PackedScene = PRESENTERS[visual_id]
	var candidate := scene.instantiate() as PalPresenter
	if candidate == null:
		return false
	last_error = candidate.prepare(profile)
	if not last_error.is_empty():
		candidate.free()
		load_failed.emit(last_error)
		return false
	install_presenter(candidate, visual_id, profile.avatar_path)
	return true


func install_presenter(candidate: PalPresenter, visual_id: String, avatar_path: String) -> void:
	if PalUi.is_mobile() and visual_id != "sprite2d":
		candidate.free()
		last_error = "安卓版仅支持 2D 立绘。"
		return
	# The candidate has already prepared successfully; commit it in one step.
	candidate.name = "Presenter"
	if presenter != null:
		remove_child(presenter)
		presenter.queue_free()
	presenter = candidate
	disable_3d = visual_id == "sprite2d"
	presenter.set_adult_mode(profile.adult_mode)
	var outfits: Dictionary = presenter.get_capabilities().get("outfits", {})
	if visual_id == "sprite2d" and not outfits.has(profile.outfit):
		profile.outfit = "maid"
	presenter.set_outfit(profile.outfit)
	add_child(presenter)
	presenter.set_presentation_mode(presentation_mode)
	presenter.configure_surface(size)
	profile.visual_id = visual_id
	profile.avatar_path = avatar_path
	apply_render_settings()
	_sync_capabilities()
	presenter.action_finished.connect(behavior.complete_action)
	behavior.request_action("idle")
	visual_changed.emit(visual_id)


func load_vrm(path: String) -> bool:
	var previous_path := profile.avatar_path
	profile.avatar_path = path
	if switch_visual("vrm3d"):
		return true
	profile.avatar_path = previous_path
	return false


func apply_render_settings() -> void:
	profile.render_settings = PalRenderSettings.normalize(profile.render_settings)
	var settings := profile.render_settings
	var is_3d := profile.visual_id == "vrm3d"
	var renderer := RenderingServer.get_current_rendering_method()
	msaa_3d = settings.msaa if is_3d else Viewport.MSAA_DISABLED
	screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if is_3d and settings.fxaa and renderer != "gl_compatibility" else Viewport.SCREEN_SPACE_AA_DISABLED
	scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	scaling_3d_scale = settings.render_scale if is_3d else 1.0
	use_debanding = is_3d and settings.debanding and renderer != "gl_compatibility"
	if presenter != null:
		presenter.apply_render_settings(settings)


func set_look_target(target: Vector2) -> void:
	if presenter != null:
		presenter.set_look_target(target if profile.look_at_mouse else Vector2.ZERO)


func set_adult_mode(value: bool) -> void:
	profile.adult_mode = value
	if presenter != null:
		presenter.set_adult_mode(value)
		_sync_capabilities()


func set_presentation_mode(value: String) -> void:
	presentation_mode = value
	if presenter != null:
		presenter.set_presentation_mode(value)
		_sync_capabilities()


func set_outfit(value: String, origin := "user") -> bool:
	if presenter == null or profile.visual_id != "sprite2d":
		return false
	if origin == "model" and (not profile.allow_model_outfit or profile.outfit_override):
		return false
	if not presenter.get_capabilities().get("outfits", {}).has(value):
		return false
	if origin == "user":
		profile.outfit_override = true
	profile.outfit = value
	presenter.set_outfit(value)
	_sync_capabilities()
	wardrobe_changed.emit()
	return true


func set_outfit_control(key: String, value: bool) -> void:
	if key == "allow_model_outfit":
		profile.allow_model_outfit = value
	elif key == "outfit_override":
		profile.outfit_override = value
	else:
		return
	wardrobe_changed.emit()


func _sync_capabilities() -> void:
	var available := presenter.get_capabilities()
	behavior.motion_actions = available.get("motion_actions", PackedStringArray())
	behavior.action_definitions = available.get("action_details", {})
	if not behavior.action_definitions.is_empty() and not behavior.action_definitions.has(behavior.current_action):
		behavior.request_action("idle", "system")
	capabilities_changed.emit()


func _on_action_requested(action: String) -> void:
	if presenter != null:
		presenter.play_action(action)


func _configure_presenter() -> void:
	if presenter != null:
		presenter.configure_surface(size)
