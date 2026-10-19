extends PalPresenter

var _pack: PalPortraitPack
var _sprite: Sprite2D
var _surface_size := Vector2i(320, 320)
var _action := "idle"
var _expression := ""
var _pose_id := ""
var _bounds := Rect2()
var _support_anchor := Vector2.ZERO
var _profile: PalProfile
var _surface_attached := false
var _walk_direction := 1.0


func prepare(profile: PalProfile) -> String:
	_profile = profile
	_pack = PalPortraitPack.new()
	if not _pack.open(profile.portrait_pack_path):
		return _pack.error
	for view: String in ["full_body", "call"]:
		if _pack.texture(_pack.default_pose(view)) == null:
			return "无法加载 2D 默认立绘：" + view
	return ""


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Portrait"
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)
	_refresh_pose()


func _view() -> String:
	return "call" if presentation_mode == "call" else "full_body"


func set_presentation_mode(value: String) -> void:
	if value != presentation_mode:
		_expression = ""
		_surface_attached = false
	presentation_mode = value
	_refresh_pose()


func set_outfit(value: String) -> void:
	super.set_outfit(value)
	_refresh_pose()


func set_walk_direction(value: float) -> void:
	if not is_zero_approx(value):
		_walk_direction = value
	if _action == "walk":
		_refresh_pose()


func set_surface_attachment(value: bool) -> void:
	_surface_attached = value
	_refresh_pose()


func set_adult_mode(value: bool) -> void:
	super.set_adult_mode(value)
	_refresh_pose()


func configure_surface(surface_size: Vector2i) -> void:
	_surface_size = surface_size
	_layout()


func play_action(action: String) -> void:
	_action = action
	_refresh_pose()


func set_expression(expression: String) -> void:
	_expression = expression
	_refresh_pose()


func _refresh_pose() -> void:
	if _pack == null or _sprite == null:
		return
	var view := _view()
	var action_id := _action
	if _surface_attached and view == "full_body" and _action in ["idle", "edge_rest", "sit", "prone", "sit_edge"]:
		action_id = _profile.edge_posture
	elif _action == "walk":
		action_id = "walk_left" if _walk_direction < 0 else "walk_right"
	var action: Dictionary = _pack.visual.actions.get(action_id, {})
	var expression: Dictionary = _pack.visual.expressions.get(_expression, {})
	if bool(action.get("adult_only", false)) and not adult_mode:
		action = {}
	if bool(expression.get("adult_only", false)) and not adult_mode:
		expression = {}
	var pose := _pack.resolve_pose(action, view, outfit)
	if pose.is_empty():
		pose = _pack.default_pose(view, outfit)
	# Whole-image expressions must not make a cup, snack or book disappear.
	var expression_pose := _pack.resolve_pose(expression, view, outfit)
	if not bool(action.get("preserve_activity", false)) and not expression_pose.is_empty():
		pose = expression_pose
	var texture := _pack.texture(pose)
	if texture == null:
		pose = _pack.default_pose(view, outfit)
		texture = _pack.texture(pose)
	_pose_id = pose
	_sprite.texture = texture
	_layout()


func _layout() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var pose: Dictionary = _pack.visual.poses[_pose_id]
	var canvas := Vector2(float(pose.canvas_size[0]), float(pose.canvas_size[1]))
	var anchor := Vector2(float(pose.anchor[0]), float(pose.anchor[1])) * canvas
	var bounds: Array = pose.alpha_bounds
	var local_bounds := Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
	var surface := Vector2(_surface_size)
	var scale_factor: float
	var close_up := _view() == "call"
	# Normalize call bounds by canvas height so higher-resolution poses do not
	# shrink the other portraits. Keep a shared frame across expressions.
	var half_width := 0.001
	var above := 0.001
	var below := 0.0
	for data: Dictionary in _pack.visual.poses.values():
		if str(data.view) != _view() or str(data.get("outfit", "maid")) != outfit or bool(data.get("landscape", false)) != bool(pose.get("landscape", false)):
			continue
		var dimensions := Vector2(float(data.canvas_size[0]), float(data.canvas_size[1]))
		var origin := Vector2(float(data.anchor[0]), float(data.anchor[1])) * dimensions
		var rect: Array = data.alpha_bounds
		var units := 1.0 / dimensions.y
		half_width = maxf(half_width, maxf(origin.x - float(rect[0]), float(rect[0]) + float(rect[2]) - origin.x) * units)
		above = maxf(above, (origin.y - float(rect[1])) * units)
		below = maxf(below, (float(rect[1]) + float(rect[3]) - origin.y) * units)
	if close_up:
		# Fill the available height; a narrow viewport may crop the sides.
		scale_factor = maxf(1.0, surface.y - 8.0) / ((above + below) * canvas.y)
		_sprite.position = Vector2(surface.x * 0.5, surface.y - 4.0 - below * canvas.y * scale_factor) - anchor * scale_factor
	else:
		scale_factor = minf(maxf(1.0, surface.x - 8.0) / (half_width * 2.0 * canvas.y), maxf(1.0, surface.y - 8.0) / ((above + below) * canvas.y))
		_sprite.position = Vector2(surface.x * 0.5, surface.y - 4.0 - below * canvas.y * scale_factor) - anchor * scale_factor
	_sprite.scale = Vector2.ONE * scale_factor
	_bounds = Rect2(_sprite.position + local_bounds.position * scale_factor, local_bounds.size * scale_factor).intersection(Rect2(Vector2.ZERO, surface))
	_support_anchor = _sprite.position + anchor * scale_factor


func get_capabilities() -> Dictionary:
	if _pack == null:
		return {}
	var actions := _pack.definitions("actions", _view(), false, adult_mode, outfit)
	var expressions := _pack.definitions("expressions", _view(), false, adult_mode, outfit)
	return {"dimension": "2d", "placeholder": false, "can_wander": _view() == "full_body" and actions.has("walk_left") and actions.has("walk_right"),
		"outfits": _pack.outfits(), "outfit": outfit, "landscape": bool(_pack.visual.poses.get(_pose_id, {}).get("landscape", false)),
		"pack_name": str(_pack.manifest.name), "actions": PackedStringArray(actions.keys()),
		"motion_actions": PackedStringArray(_pack.definitions("actions", _view(), true, adult_mode, outfit).keys()), "action_details": _pack.definitions("actions", _view(), true, adult_mode, outfit),
		"expressions": PackedStringArray(expressions.keys()), "expression_details": expressions}


func get_portrait_texture() -> Texture2D:
	return _pack.texture(_pack.default_pose("call", outfit)) if _pack != null else null


func get_interaction_rect() -> Rect2:
	return _bounds


func get_support_anchor() -> Vector2:
	return _support_anchor
