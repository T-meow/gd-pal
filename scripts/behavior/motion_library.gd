class_name PalMotionLibrary
extends RefCounted
## Checked humanoid rigs only. DS shares the normalized rest rotations; its hips
## offset and absent eye bones are adapted without loading the old source avatar.

const CATALOG := preload("res://assets/motions/npc/catalog.gd")
const LIBRARY: AnimationLibrary = preload("res://assets/motions/npc/npc_motions.tres")
const DS_DESKTOP_LIBRARY: AnimationLibrary = preload("res://assets/motions/ds_desktop/desktop_motions.tres")
const DS_AVATAR_SHA256 := "824292bb9998efaa11d26bfc5a505ed39926c438334d54f61d5f902d146a78ed"
# Imported normalized hips rest / motion_scale, captured from the two checked rigs.
const SOURCE_HIPS_REST := Vector3(0.0, 0.982297420501709, 0.027977)
const SOURCE_MOTION_SCALE := 0.982297420501709
const DS_HIPS_REST := Vector3(-0.00015, 0.97010612487793, 0.010381)
const DS_MOTION_SCALE := 0.97010612487793
static var _ds_source_library: AnimationLibrary
const DESKTOP_CLIPS := {
	"desktop_wave": {"id": "desktop_wave", "label": "挥手招呼", "mode": "once", "seconds": 3.6, "expressions": {"preset": "happy", "weight": 0.3}},
	"desktop_pickup": {"id": "desktop_pickup", "label": "悬空提起", "mode": "loop", "seconds": 3.0},
	"edge_rest": {"id": "edge_rest", "label": "趴在边缘", "mode": "hold", "seconds": 1.0, "expressions": {"preset": "relaxed", "weight": 0.25}},
}
const INTERACTION_BODIES := {
	"idle": "idle_breathe",
	"greet": "desktop_wave",
	"greet_wave": "desktop_wave",
	"head_pat": "react_nod",
	"happy": "clap",
	"surprised": "photo_stand_04",
	"drag": "desktop_pickup",
}


static func matches_avatar(path: String) -> bool:
	return is_ds_avatar(path)


static func is_ds_avatar(path: String) -> bool:
	return FileAccess.get_sha256(path) == DS_AVATAR_SHA256


static func source_library(for_ds: bool = false) -> AnimationLibrary:
	if not for_ds:
		return LIBRARY
	if _ds_source_library != null:
		return _ds_source_library
	_ds_source_library = AnimationLibrary.new()
	var hips_offset := DS_HIPS_REST / DS_MOTION_SCALE - SOURCE_HIPS_REST / SOURCE_MOTION_SCALE
	for id: String in LIBRARY.get_animation_list():
		var animation := LIBRARY.get_animation(id).duplicate() as Animation
		for track: int in range(animation.get_track_count() - 1, -1, -1):
			var bone := str(animation.track_get_path(track).get_subname(0))
			if bone in ["LeftEye", "RightEye"]:
				animation.remove_track(track)
			elif bone == "Hips" and animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
				for key: int in animation.track_get_key_count(track):
					var position: Vector3 = animation.track_get_key_value(track, key)
					animation.track_set_key_value(track, key, position + hips_offset)
		_ds_source_library.add_animation(id, animation)
	return _ds_source_library


static func clip(id: String) -> Dictionary:
	if DESKTOP_CLIPS.has(id):
		return DESKTOP_CLIPS[id]
	for entry: Dictionary in CATALOG.CLIPS:
		if entry.id == id:
			return entry
	return {}


static func playback_library(for_ds: bool = false) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var source := source_library(for_ds)
	var desktop := DS_DESKTOP_LIBRARY
	for id: String in source.get_animation_list():
		library.add_animation(id, source.get_animation(id))
	for id: String in desktop.get_animation_list():
		library.add_animation(id, desktop.get_animation(id))
	return library


static func action_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Dictionary in CATALOG.CLIPS:
		result.append(entry.id)
	result.append("edge_rest")
	return result


static func body_clip(action: String) -> String:
	if INTERACTION_BODIES.has(action):
		return INTERACTION_BODIES[action]
	return action if LIBRARY.has_animation(action) or DS_DESKTOP_LIBRARY.has_animation(action) else ""
