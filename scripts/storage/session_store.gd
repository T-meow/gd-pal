class_name PalSessionStore
extends RefCounted

const DEFAULT_PATH := "user://pal_session.json"


static func save_profiles(profiles: Array[PalProfile], path: String = DEFAULT_PATH) -> Error:
	var previous := _read_session(path)
	if previous.status == "invalid" and not _read_session(path + ".bak").valid:
		return ERR_FILE_CORRUPT
	var records: Array[Dictionary] = []
	for profile: PalProfile in profiles:
		var record := {"id": profile.profile_id, "name": profile.display_name,
			"visual": profile.visual_id, "avatar": profile.avatar_path, "portrait_pack": profile.portrait_pack_path,
			"portrait_framing": profile.portrait_framing,
			"desktop_mode": profile.desktop_mode, "outfit": profile.outfit,
			"allow_model_outfit": profile.allow_model_outfit, "outfit_override": profile.outfit_override,
			"edge_posture": profile.edge_posture,
			"look_at_mouse": profile.look_at_mouse, "scale": profile.desktop_scale,
			"position": [profile.desktop_position.x, profile.desktop_position.y],
			"wander": profile.wander,
			"render_settings": PalRenderSettings.normalize(profile.render_settings)}
		records.append(record)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema_version": 1, "profiles": records}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return error
	if previous.valid:
		# Finish the backup before replacing the current file.
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak.tmp"))
		if error != OK:
			return error
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".bak.tmp"), ProjectSettings.globalize_path(path + ".bak"))
		if error != OK:
			return error
	elif previous.status == "invalid":
		# Keep the damaged original as well as the known-good recovery backup.
		var retained_path := path + ".corrupt-" + Crypto.new().generate_random_bytes(8).hex_encode()
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(retained_path))
		if error != OK:
			return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))


static func load_profiles(path: String = DEFAULT_PATH) -> Array[PalProfile]:
	return load_session(path).profiles


static func load_session(path: String = DEFAULT_PATH) -> Dictionary:
	var current := _read_session(path)
	if current.valid:
		return current
	var backup := _read_session(path + ".bak")
	if backup.valid:
		backup.status = "recovered"
		return backup
	return _empty_session("missing" if current.status == "missing" and backup.status == "missing" else "invalid")


static func _empty_session(status: String) -> Dictionary:
	var profiles: Array[PalProfile] = []
	return {"valid": false, "status": status, "profiles": profiles}


static func _read_session(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _empty_session("missing")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024:
		return _empty_session("invalid")
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	var json := JSON.new()
	if error != OK or json.parse(text) != OK:
		return _empty_session("invalid")
	var data: Variant = json.data
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("profiles") is Array:
		return _empty_session("invalid")
	if data.profiles.size() > 4:
		return _empty_session("invalid")
	var profiles: Array[PalProfile] = []
	var ids: Dictionary = {}
	var id_pattern := RegEx.new()
	id_pattern.compile("^[a-zA-Z0-9_-]{1,80}$")
	for entry: Variant in data.profiles:
		if not entry is Dictionary:
			return _empty_session("invalid")
		if not entry.get("id") is String or id_pattern.search(entry.id) == null or ids.has(entry.id):
			return _empty_session("invalid")
		var profile := PalProfile.new()
		profile.profile_id = entry.id
		ids[entry.id] = true
		profile.display_name = str(entry.get("name", PalProfile.DEFAULT_NAME)).left(40)
		profile.portrait_pack_path = str(entry.get("portrait_pack", PalPortraitPack.DEFAULT_MANIFEST))
		profile.portrait_framing = "full_body" if entry.get("portrait_framing") == "full_body" else "call"
		profile.desktop_mode = "call" if entry.get("desktop_mode") == "call" else "full_body"
		profile.outfit = str(entry.get("outfit", "maid"))
		profile.allow_model_outfit = bool(entry.get("allow_model_outfit", true))
		profile.outfit_override = bool(entry.get("outfit_override", false))
		profile.edge_posture = "prone" if entry.get("edge_posture") == "prone" else "sit"
		profile.avatar_path = str(entry.get("avatar", PalVrmLoader.DEFAULT_AVATAR))
		profile.visual_id = "vrm3d" if entry.get("visual") == "vrm3d" else "sprite2d"
		if PalUi.is_mobile():
			profile.visual_id = "sprite2d"
		profile.look_at_mouse = bool(entry.get("look_at_mouse", true))
		profile.wander = bool(entry.get("wander", false))
		var scale_value: Variant = entry.get("scale", 1.0)
		if scale_value is float or scale_value is int:
			profile.desktop_scale = clampf(float(scale_value), 0.65, 1.5) if is_finite(float(scale_value)) else 1.0
		var position_value: Variant = entry.get("position", [])
		if position_value is Array and position_value.size() == 2 and (position_value[0] is float or position_value[0] is int) and (position_value[1] is float or position_value[1] is int):
			profile.desktop_position = Vector2i(int(position_value[0]), int(position_value[1]))
		profile.render_settings = PalRenderSettings.normalize(entry.get("render_settings"))
		profiles.append(profile)
	return {"valid": true, "status": "ok", "profiles": profiles}
