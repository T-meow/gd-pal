extends SceneTree
## Bake desktop-specific bodies for the default DS VRM. Run after sync-motions.mjs.
## Source animations and their license evidence remain in assets/motions/npc.

const OUTPUT := "res://assets/motions/ds_desktop/"
var _skeleton: Skeleton3D
var _source: AnimationPlayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result := PalVrmLoader.load_avatar(PalVrmLoader.DEFAULT_AVATAR)
	if not result.get("error", "").is_empty():
		push_error(result.error)
		quit(1)
		return
	var avatar: Node3D = result.avatar
	root.add_child(avatar)
	_skeleton = avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_source = AnimationPlayer.new()
	avatar.add_child(_source)
	_source.root_node = NodePath("..")
	_source.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_source.add_animation_library("", PalMotionLibrary.source_library(true))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var library := AnimationLibrary.new()
	for id: String in ["desktop_wave", "desktop_pickup", "edge_rest"]:
		var animation := _bake(id)
		var error := ResourceSaver.save(animation, OUTPUT + id + ".tres")
		if error != OK:
			push_error("Could not save " + id)
			quit(1)
			return
		library.add_animation(id, animation)
	ResourceSaver.save(library, OUTPUT + "desktop_motions.tres")
	avatar.free()
	print("Baked desktop wave, suspended pickup and edge-rest bodies.")
	quit()


func _bake(id: String) -> Animation:
	var base := _source.get_animation("photo_lying_f7710610" if id == "edge_rest" else "idle_breathe")
	var animation := base.duplicate() as Animation
	animation.resource_name = id
	animation.length = 3.6 if id == "desktop_wave" else 3.0 if id == "desktop_pickup" else 1.0
	animation.loop_mode = Animation.LOOP_LINEAR if id == "desktop_pickup" else Animation.LOOP_NONE
	for track: int in animation.get_track_count():
		while animation.track_get_key_count(track) > 0:
			animation.track_remove_key(track, 0)
	var frame_count := roundi(animation.length * 30.0) if id != "edge_rest" else 1
	for frame: int in frame_count + 1:
		var time := animation.length * frame / frame_count
		_source.play("photo_lying_f7710610" if id == "edge_rest" else "idle_breathe", 0.0)
		_source.seek(fmod(time, base.length), true)
		if id == "desktop_wave":
			var weight := smoothstep(0.0, 0.65, time) * (1.0 - smoothstep(2.85, 3.6, time))
			_aim("RightUpperArm", "RightLowerArm", Vector3(-0.80, -0.52, 0.30), weight)
			_aim("RightLowerArm", "RightHand", Vector3(-0.12, 0.96, 0.25), weight)
			_face_palm("Right", Vector3(sin(time * TAU * 1.6) * 0.32, 1.0, 0.04).normalized(), weight)
		elif id == "desktop_pickup":
			# Let the legs hang at different bends; the body is supported from above.
			_aim("LeftUpperArm", "LeftLowerArm", Vector3(0.35, -0.93, 0.12), 1.0)
			_aim("RightUpperArm", "RightLowerArm", Vector3(-0.42, -0.88, 0.20), 1.0)
			_aim("LeftLowerArm", "LeftHand", Vector3(0.18, -0.85, 0.45), 1.0)
			_aim("RightLowerArm", "RightHand", Vector3(-0.12, -0.94, 0.32), 1.0)
			var sway := sin(time * TAU / 3.0) * 0.035
			_aim("LeftUpperLeg", "LeftLowerLeg", Vector3(0.12, -0.94, 0.32 + sway), 1.0)
			_aim("RightUpperLeg", "RightLowerLeg", Vector3(-0.15, -0.98, 0.12 - sway), 1.0)
			_aim("LeftLowerLeg", "LeftFoot", Vector3(0.05, -0.75, -0.66), 1.0)
			_aim("RightLowerLeg", "RightFoot", Vector3(-0.05, -0.90, -0.43), 1.0)
		else:
			# Rest the thighs along the ledge. The original photo pose lifts one
			# ankle above the head; keep only a small, relaxed bend at each knee.
			_aim("LeftUpperLeg", "LeftLowerLeg", Vector3(-0.12, -0.08, 1.0), 1.0)
			_aim("RightUpperLeg", "RightLowerLeg", Vector3(0.12, -0.05, 1.0), 1.0)
			_aim("LeftLowerLeg", "LeftFoot", Vector3(-0.03, 0.18, 1.0), 1.0)
			_aim("RightLowerLeg", "RightFoot", Vector3(0.03, 0.26, 1.0), 1.0)
			_aim("LeftFoot", "LeftToes", Vector3(0.0, -0.18, 1.0), 1.0)
			_aim("RightFoot", "RightToes", Vector3(0.0, -0.18, 1.0), 1.0)
			# Turn the library's prone pose into a readable three-quarter side view.
			var hips := _skeleton.find_bone("Hips")
			var turn := Quaternion(Vector3.UP, deg_to_rad(120.0))
			_skeleton.set_bone_pose_rotation(hips, turn * _skeleton.get_bone_pose_rotation(hips))
			_skeleton.set_bone_pose_position(hips, turn * _skeleton.get_bone_pose_position(hips))
		for track: int in animation.get_track_count():
			var bone := _skeleton.find_bone(animation.track_get_path(track).get_subname(0))
			if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				animation.rotation_track_insert_key(track, time, _skeleton.get_bone_pose_rotation(bone).normalized())
			elif animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
				animation.position_track_insert_key(track, time, _skeleton.get_bone_pose_position(bone) / _skeleton.motion_scale)
	return animation


func _aim(name: String, child_name: String, direction: Vector3, weight: float) -> void:
	var bone := _skeleton.find_bone(name)
	var child := _skeleton.find_bone(child_name)
	var transform := _skeleton.get_bone_global_pose(bone)
	var current := (_skeleton.get_bone_global_pose(child).origin - transform.origin).normalized()
	var rotation := Quaternion(current, direction.normalized())
	_set_global_rotation(bone, Basis(rotation) * transform.basis, weight)


func _face_palm(side: String, fingers: Vector3, weight: float) -> void:
	var hand := _skeleton.find_bone(side + "Hand")
	var index := _skeleton.find_bone(side + "IndexProximal")
	var little := _skeleton.find_bone(side + "LittleProximal")
	var rest := _skeleton.get_bone_global_rest(hand)
	var a := _skeleton.get_bone_global_rest(index).origin - rest.origin
	var b := _skeleton.get_bone_global_rest(little).origin - rest.origin
	var normal := a.cross(b).normalized()
	# In this avatar's T-pose the palm faces down; derive its actual local axes.
	if normal.dot(Vector3.DOWN) < 0.0:
		normal = -normal
	var local_fingers := (rest.basis.inverse() * (a + b)).normalized()
	var local_normal := (rest.basis.inverse() * normal).normalized()
	var local_frame := Basis(local_fingers.cross(local_normal).normalized(), local_fingers, local_normal).orthonormalized()
	var front := (Vector3.BACK - fingers * Vector3.BACK.dot(fingers)).normalized()
	var target_frame := Basis(fingers.cross(front).normalized(), fingers, front)
	_set_global_rotation(hand, target_frame * local_frame.inverse(), weight)


func _set_global_rotation(bone: int, basis: Basis, weight: float) -> void:
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var target := (parent_basis.inverse() * basis).get_rotation_quaternion().normalized()
	_skeleton.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(bone).slerp(target, weight))
