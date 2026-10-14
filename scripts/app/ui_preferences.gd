class_name PalUiPreferences
extends RefCounted
## Display preferences never change character or memory identities.

signal changed

var path := "user://ui_state.cfg"
var persistent := true
var _config := ConfigFile.new()


func load_preferences() -> void:
	if persistent:
		_config.load(path)


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	return _config.get_value(section, key, fallback)


func put(section: String, key: String, value: Variant) -> Error:
	_config.set_value(section, key, value)
	var error := _config.save(path) if persistent else OK
	changed.emit()
	return error


func put_values(section: String, values: Dictionary) -> Error:
	for key: String in values:
		_config.set_value(section, key, values[key])
	var error := _config.save(path) if persistent else OK
	changed.emit()
	return error


func scope_name(profile_id: String, scope_id: String, initial_id: String = "") -> String:
	var section := "memory/" + profile_id
	var id := scope_id if not scope_id.is_empty() else initial_id
	if id.is_empty():
		return "初始存档"
	if _config.has_section_key(section, id):
		return str(_config.get_value(section, id))
	var caption := "初始存档"
	if id != initial_id:
		var number := int(_config.get_value("scope_numbers", profile_id, 0)) + 1
		_config.set_value("scope_numbers", profile_id, number)
		caption = "独立存档 %d" % number
	# Lazy names do not emit changed while a list is being rendered.
	_config.set_value(section, id, caption)
	if persistent:
		_config.save(path)
	return caption


func rename_scope(profile_id: String, scope_id: String, caption: String) -> Error:
	return put("memory/" + profile_id, scope_id, caption.strip_edges().left(40))
