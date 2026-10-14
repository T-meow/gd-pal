@tool
extends EditorPlugin

var _export_plugin: EditorExportPlugin


class PalExportPlugin extends EditorExportPlugin:
	func _get_name() -> String:
		return "GD Pal VRM source"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		# The imported scene is exported normally. FileAccess validation and the
		# motion-library fingerprint also need the original GLB/VRM bytes.
		for avatar: String in [PalVrmLoader.DEFAULT_AVATAR]:
			add_file(avatar, FileAccess.get_file_as_bytes(avatar), false)
		for notice: String in ["res://LICENSE", "res://THIRD_PARTY_NOTICES.md", "res://licenses/yumo/LICENSE", "res://licenses/yumo/PORTING.md", "res://addons/vrm/LICENSE", "res://addons/Godot-MToon-Shader/LICENSE", "res://addons/godot_mcp/LICENSE"]:
			add_file(notice, FileAccess.get_file_as_bytes(notice), false)


func _enter_tree() -> void:
	_export_plugin = PalExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
