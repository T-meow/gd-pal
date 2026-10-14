extends PalPresenter
## Body motions for default DS and the retained source rig; fallback for other VRMs.

var avatar: Node3D
var skeleton: Skeleton3D
var _camera: Camera3D
var _rig: Node3D
var _profile: PalProfile
var _bounds: AABB
var _surface_size := Vector2i(320, 420)
var _bones: Dictionary = {}
var _expressions: Dictionary = {}
var _blend_targets: Array[Dictionary] = []
var _elapsed := 0.0
var _action := "idle"
var _action_time := 0.0
var _look := Vector2.ZERO
var _look_target := Vector2.ZERO
var _blink_wait := 2.2
var _blink_time := -1.0
var _rng := RandomNumberGenerator.new()
var _motion_compatible := false
var _uses_ds_motions := false
var _motion_player: AnimationPlayer
var _motion_clip: Dictionary = {}
var _secondary_nodes: Array[Node] = []
var _dialogue_expression := ""
var _surface_attached := false
var _edge_bounds := AABB()
var _foot_floor_offset := 0.0
var _walk_direction := 0.0
var _camera_yaw := 0.0
var _camera_focus := Vector3.ZERO
var _camera_distance := 4.0


func prepare(profile: PalProfile) -> String:
	_profile = profile
	var result := PalVrmLoader.load_avatar(profile.avatar_path)
	if not result.get("error", "").is_empty():
		return result.error
	avatar = result.avatar
	_motion_compatible = PalMotionLibrary.matches_avatar(profile.avatar_path)
	_uses_ds_motions = PalMotionLibrary.is_ds_avatar(profile.avatar_path)
	return ""


func _ready() -> void:
	_rng.randomize()
	_camera = $Camera
	_rig = $Rig
	if avatar == null:
		return
	_rig.add_child(avatar)
	skeleton = avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for bone_name: String in ["Head", "Neck", "Spine", "Chest", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg"]:
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var parent_index := skeleton.get_bone_parent(index)
		var parent_basis := skeleton.get_bone_global_rest(parent_index).basis if parent_index >= 0 else Basis.IDENTITY
		_bones[bone_name] = {"index": index, "base": skeleton.get_bone_pose_rotation(index), "parent_inverse": parent_basis.inverse()}
	var first := true
	for node: Node in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local_bounds: AABB = avatar.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		_bounds = local_bounds if first else _bounds.merge(local_bounds)
		first = false
	_cache_expressions()
	_setup_motions()
	var foot := skeleton.find_bone("LeftFoot")
	if foot >= 0:
		_foot_floor_offset = (avatar.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin).y - _bounds.position.y
	configure_surface(_surface_size)
	var metadata: Resource = avatar.get("vrm_meta")
	if metadata != null and _profile.display_name.begins_with("伙伴"):
		_profile.display_name = metadata.get("title")


func _setup_motions() -> void:
	if not _motion_compatible:
		return
	# Validate the real imported hierarchy and bones before exposing the library.
	var library := PalMotionLibrary.playback_library(_uses_ds_motions)
	var animation := library.get_animation("idle_breathe")
	for track: int in animation.get_track_count():
		var path := animation.track_get_path(track)
		if avatar.get_node_or_null(NodePath(path.get_concatenated_names())) != skeleton or skeleton.find_bone(path.get_subname(0)) < 0:
			return
	_motion_player = AnimationPlayer.new()
	_motion_player.name = "NPCMotions"
	avatar.add_child(_motion_player)
	_motion_player.root_node = NodePath("..")
	_motion_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_motion_player.add_animation_library("npc", library)
	_motion_player.animation_finished.connect(_on_motion_finished)
	_motion_player.play("npc/edge_rest", 0.0)
	_motion_player.seek(0.0, true)
	var first := true
	for bone_name: String in ["Hips", "Head", "LeftFoot", "RightFoot", "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm", "LeftLowerLeg", "RightLowerLeg"]:
		var point := skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin
		point = avatar.global_transform.affine_inverse() * skeleton.global_transform * point
		_edge_bounds = AABB(point, Vector3.ZERO) if first else _edge_bounds.expand(point)
		first = false
	_edge_bounds = _edge_bounds.grow(0.22)
	# Tails, ears and hair can extend above the relaxed body pose. The same
	# bounds frame the camera and clip the native window, so include accessory
	# bones in its top edge and leave room for their meshes and spring motion.
	var edge_top := _edge_bounds.end.y
	var skeleton_to_avatar := avatar.global_transform.affine_inverse() * skeleton.global_transform
	for bone: int in skeleton.get_bone_count():
		var point := skeleton_to_avatar * skeleton.get_bone_global_pose(bone).origin
		edge_top = maxf(edge_top, point.y + 0.22)
	_edge_bounds.size.y = edge_top - _edge_bounds.position.y + _bounds.size.y * 0.10
	_motion_player.stop()
	for node: Node in avatar.find_children("*", "Node", true, false):
		if node.has_method("tick_spring_bones"):
			_secondary_nodes.append(node)
	play_action("idle")


func _on_motion_finished(_animation: StringName) -> void:
	if _motion_clip.get("mode") == "once":
		action_finished.emit(_action)
	# hold clips keep the last pose until a new action is requested.


func _reset_secondary() -> void:
	for node: Node in _secondary_nodes:
		node.update_centers(skeleton.global_transform)
		for index: int in node.spring_bones_internal.size():
			node.spring_bones_internal[index].setup(node.center_transforms_inv[node.springs_centers[index]], true)


func _cache_expressions() -> void:
	var players := avatar.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	player.stop()
	var animation_root := player.get_node(player.root_node)
	for animation_name: String in player.get_animation_list():
		var animation := player.get_animation(animation_name)
		var binds: Array[Dictionary] = []
		for track: int in animation.get_track_count():
			if animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE or animation.track_get_key_count(track) == 0:
				continue
			var path := animation.track_get_path(track)
			var mesh := animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) as MeshInstance3D
			if mesh == null or path.get_subname_count() == 0:
				continue
			var index := mesh.find_blend_shape_by_name(path.get_subname(0))
			if index < 0:
				continue
			var bind := {"mesh": mesh, "index": index, "weight": float(animation.track_get_key_value(track, animation.track_get_key_count(track) - 1))}
			binds.append(bind)
			_blend_targets.append(bind)
		_expressions[animation_name] = binds


func configure_surface(surface_size: Vector2i) -> void:
	_surface_size = surface_size
	if _camera == null or _bounds.size.y <= 0:
		return
	var aspect := float(surface_size.x) / maxf(surface_size.y, 1.0)
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.rotation = Vector3.ZERO
	_camera.size = maxf(_bounds.size.y * 1.06, _bounds.size.x / aspect * 1.04)
	_camera.position = Vector3(_bounds.get_center().x, _bounds.get_center().y, _bounds.end.z + 4.0)
	if _surface_attached and presentation_mode == "full_body":
		_camera_yaw = 0.0
		# Put the actual support plane near the viewport bottom, not the standing feet.
		var support_ratio := 1.0 - 12.0 / maxf(surface_size.y, 1.0)
		_camera.size = maxf((_edge_bounds.end.y + 0.08) / support_ratio, _edge_bounds.size.x / aspect * 1.12)
		_camera.position = Vector3(_edge_bounds.get_center().x, _camera.size * (support_ratio - 0.5), _edge_bounds.end.z + 4.0)
		return
	# Framing belongs to the host, so starting/ending a clip cannot move the camera.
	if presentation_mode == "portrait":
		# Include the full mesh top (ears/accessories), with extra room above the head.
		var bottom := _bounds.position.y + _bounds.size.y * 0.38
		var top := _bounds.end.y + _bounds.size.y * 0.08
		_camera.size = maxf((top - bottom) * 1.08, _bounds.size.x / aspect * 1.10)
		_camera.position.y = (top + bottom) * 0.5
	elif presentation_mode == "call":
		# Close framing fills the stage; bubbles do not reserve camera headroom.
		var top := _bounds.end.y + _bounds.size.y * 0.025
		_camera.size = _bounds.size.y * 0.66
		_camera.position.y = top - _camera.size * 0.5
	_camera_focus = Vector3(_bounds.get_center().x, _camera.position.y, _bounds.get_center().z)
	_camera_distance = _camera.position.z - _camera_focus.z
	_apply_walk_camera()


func set_presentation_mode(value: String) -> void:
	presentation_mode = value
	if value != "full_body":
		_walk_direction = 0.0
		_camera_yaw = 0.0
	configure_surface(_surface_size)


func set_walk_direction(direction: float) -> void:
	_walk_direction = signf(direction)


func _update_walk_camera(delta: float) -> void:
	if _surface_attached:
		return
	# The model walks along +Z. Viewing from -X makes that project to screen-right.
	var target := -_walk_direction * deg_to_rad(75.0) if _action == "walk" and presentation_mode == "full_body" else 0.0
	var next := move_toward(_camera_yaw, target, deg_to_rad(360.0) * delta)
	if not is_equal_approx(next, _camera_yaw):
		_camera_yaw = next
		_apply_walk_camera()


func _apply_walk_camera() -> void:
	if _camera == null:
		return
	_camera.rotation = Vector3(0.0, _camera_yaw, 0.0)
	_camera.position = _camera_focus + Vector3(sin(_camera_yaw), 0.0, cos(_camera_yaw)) * _camera_distance


func apply_render_settings(settings: Dictionary) -> void:
	var key_light: DirectionalLight3D = $KeyLight
	key_light.light_energy = settings.key_energy
	key_light.light_color = Color.html(settings.key_color)
	key_light.rotation_degrees = Vector3(settings.key_pitch, settings.key_yaw, 0)
	key_light.shadow_enabled = settings.shadows
	var fill_light: DirectionalLight3D = $FillLight
	fill_light.light_energy = settings.fill_energy
	fill_light.light_color = Color.html(settings.fill_color)
	fill_light.rotation_degrees = Vector3(settings.fill_pitch, settings.fill_yaw, 0)
	var environment: Environment = $WorldEnvironment.environment
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	environment.ambient_light_energy = settings.ambient_energy
	environment.ambient_light_color = Color.html(settings.ambient_color)


func _process(delta: float) -> void:
	if skeleton == null:
		return
	_elapsed += delta
	_action_time += delta
	_update_walk_camera(delta)
	_look = _look.lerp(_look_target, 1.0 - exp(-delta * 6.0))
	if _motion_player != null:
		# Advance first, then layer only idle head tracking and facial expressions.
		# No procedural arm/leg/spine writes may overwrite the baked body tracks.
		_motion_player.advance(delta)
		_rig.position = Vector3.ZERO
		_rig.rotation = Vector3.ZERO
		if _action == "idle" and _bones.has("Head"):
			var head: int = _bones.Head.index
			var offset := Quaternion.from_euler(Vector3(-_look.y * 0.16, -_look.x * 0.28, 0.0))
			skeleton.set_bone_pose_rotation(head, offset * skeleton.get_bone_pose_rotation(head))
		_update_expressions(delta)
		return
	var active := _action != "idle"
	var envelope := minf(_action_time * 4.0, 1.0) if active else 0.0
	_rig.position.y = sin(_elapsed * 2.1) * 0.004
	_rig.rotation.z = sin(_elapsed * 1.4) * 0.012
	_pose("Spine", Vector3.FORWARD, sin(_elapsed * 1.4) * 0.016, delta)
	# Compose the entire head target each frame, without accumulating offsets.
	if _bones.has("Head"):
		var bone: Dictionary = _bones.Head
		var tilt := -0.13 * envelope if _action == "head_pat" else 0.0
		var target: Quaternion = Quaternion.from_euler(Vector3(-_look.y * 0.16, -_look.x * 0.28, tilt)) * bone.base
		skeleton.set_bone_pose_rotation(bone.index, skeleton.get_bone_pose_rotation(bone.index).slerp(target, 1.0 - exp(-delta * 10.0)))
	_pose("LeftUpperArm", Vector3.BACK, deg_to_rad(-70.0), delta)
	_pose("RightUpperArm", Vector3.BACK, deg_to_rad(70.0 - 60.0 * envelope if _action == "greet" else 70.0), delta)
	_pose("LeftLowerArm", Vector3.UP, -0.10, delta)
	_pose("RightLowerArm", Vector3.BACK, deg_to_rad(-115.0) * envelope if _action == "greet" else 0.0, delta)
	_pose("RightHand", Vector3.BACK, sin(_action_time * 13.0) * 0.25 * envelope if _action == "greet" else 0.0, delta)
	var stride := sin(_elapsed * 7.0) * 0.18 if _action == "walk" else 0.0
	_pose("LeftUpperLeg", Vector3.RIGHT, stride, delta)
	_pose("RightUpperLeg", Vector3.RIGHT, -stride, delta)
	_pose("LeftLowerLeg", Vector3.RIGHT, -0.65 if _action == "drag" else 0.0, delta)
	_pose("RightLowerLeg", Vector3.RIGHT, -0.38 if _action == "drag" else 0.0, delta)
	if _action == "drag":
		_pose("LeftUpperLeg", Vector3.RIGHT, 0.25, delta)
		_pose("RightUpperLeg", Vector3.RIGHT, 0.12, delta)
		_rig.rotation.z = sin(_elapsed * 2.5) * 0.025
	_update_expressions(delta)


func _pose(bone_name: String, axis: Vector3, angle: float, delta: float) -> void:
	if not _bones.has(bone_name):
		return
	var bone: Dictionary = _bones[bone_name]
	var local_axis: Vector3 = (bone.parent_inverse * axis).normalized()
	var target: Quaternion = Quaternion(local_axis, angle) * bone.base
	var current := skeleton.get_bone_pose_rotation(bone.index)
	skeleton.set_bone_pose_rotation(bone.index, current.slerp(target, 1.0 - exp(-delta * 10.0)))


func _update_expressions(delta: float) -> void:
	for bind: Dictionary in _blend_targets:
		bind.mesh.set_blend_shape_value(bind.index, 0.0)
	var expression_config: Dictionary = _motion_clip.get("expressions", {})
	_blink_wait -= delta
	if expression_config.get("blink", true) and _blink_wait <= 0.0 and _blink_time < 0.0:
		_blink_time = 0.0
		_blink_wait = _rng.randf_range(2.5, 5.0)
	if _blink_time >= 0.0:
		_blink_time += delta
		_apply_expression("blink", sin(clampf(_blink_time / 0.18, 0.0, 1.0) * PI))
		if _blink_time >= 0.18:
			_blink_time = -1.0
	if not _dialogue_expression.is_empty():
		_apply_expression(_dialogue_expression, 0.85)
	elif _action in ["happy", "head_pat"] or (_action == "greet" and _motion_player == null):
		_apply_expression("happy", 0.75)
	elif _action in ["surprised", "drag"]:
		_apply_expression("surprised", 0.8)
	elif not expression_config.is_empty():
		_apply_expression(str(expression_config.get("preset", "")), float(expression_config.get("weight", 0.0)))
		var closed := float(expression_config.get("closedEyes", 0.0))
		if expression_config.get("wakeEyes", false):
			closed = maxf(closed, 0.8 * pow(maxf(0.0, 1.0 - _action_time / 1.2), 2))
		_apply_expression("blink", closed)
	else:
		_apply_expression("relaxed", 0.12)
	_apply_expression("lookDown" if _look.y > 0 else "lookUp", absf(_look.y) * 0.35)


func _apply_expression(expression: String, weight: float) -> void:
	for bind: Dictionary in _expressions.get(expression, []):
		var mesh: MeshInstance3D = bind.mesh
		mesh.set_blend_shape_value(bind.index, maxf(mesh.get_blend_shape_value(bind.index), bind.weight * weight))


func play_action(action: String) -> void:
	_action = action
	if action != "walk":
		_walk_direction = 0.0
	_action_time = 0.0
	if _motion_player != null:
		var id := PalMotionLibrary.body_clip(action)
		if id.is_empty():
			id = "idle_breathe"
		_motion_clip = PalMotionLibrary.clip(id)
		var animation_name := "npc/" + id
		# Restart an explicitly repeated gesture/pose as well as blend between clips.
		if _motion_player.assigned_animation == animation_name:
			_motion_player.seek(0.0, true)
		_motion_player.play(animation_name, minf(0.22, float(_motion_clip.seconds) * 0.25))
		_motion_player.advance(0.0)
		_reset_secondary()


func set_look_target(target: Vector2) -> void:
	_look_target = target.clamp(Vector2(-1, -1), Vector2.ONE)


func set_expression(expression: String) -> void:
	_dialogue_expression = expression if _expressions.has(expression) else ""


func get_interaction_rect() -> Rect2:
	if _camera == null or avatar == null:
		return super.get_interaction_rect()
	var result := Rect2()
	var bounds := _edge_bounds if _surface_attached else _bounds
	for corner: int in 8:
		var point := _camera.unproject_position(avatar.global_transform * bounds.get_endpoint(corner))
		result = Rect2(point, Vector2.ZERO) if corner == 0 else result.expand(point)
	result = result.grow(12.0).intersection(Rect2(Vector2.ZERO, Vector2(_surface_size)))
	if _surface_attached:
		# The support is at y=0; leave the underlying taskbar/window clickable below it.
		result.size.y = minf(result.end.y, get_support_anchor().y) - result.position.y
	return result


func set_surface_attachment(enabled: bool) -> void:
	_surface_attached = enabled and _motion_player != null
	configure_surface(_surface_size)


func get_support_anchor() -> Vector2:
	if _camera == null or avatar == null:
		return super.get_support_anchor()
	var point := Vector3(_edge_bounds.get_center().x, 0.0, _edge_bounds.get_center().z) if _surface_attached else Vector3(_bounds.get_center().x, _bounds.position.y, _bounds.get_center().z)
	if _action == "drag" and not _surface_attached:
		var left := skeleton.find_bone("LeftFoot")
		var right := skeleton.find_bone("RightFoot")
		if left >= 0 and right >= 0:
			var local_skeleton := avatar.global_transform.affine_inverse() * skeleton.global_transform
			point.y = minf((local_skeleton * skeleton.get_bone_global_pose(left).origin).y, (local_skeleton * skeleton.get_bone_global_pose(right).origin).y) - _foot_floor_offset
	return _camera.unproject_position(avatar.global_transform * point)


func get_capabilities() -> Dictionary:
	var metadata: Resource = avatar.get("vrm_meta") if avatar != null else null
	var motion_actions := PalMotionLibrary.action_ids() if _motion_player != null else PackedStringArray()
	var actions := PalBehavior.ACTIONS.duplicate()
	for action: String in motion_actions:
		if action != "edge_rest" and not actions.has(action):
			actions.append(action)
	return {"dimension": "3d", "placeholder": false, "runtime_vrm_import": true,
		"loaded": avatar != null, "actions": actions, "motion_actions": motion_actions,
		"expressions": _expressions.keys(), "bone_count": skeleton.get_bone_count() if skeleton != null else 0,
		"author": metadata.get("author") if metadata != null else ""}


func get_portrait_texture() -> Texture2D:
	var metadata: Resource = avatar.get("vrm_meta") if avatar != null else null
	return metadata.get("thumbnail_image") as Texture2D if metadata != null else null
