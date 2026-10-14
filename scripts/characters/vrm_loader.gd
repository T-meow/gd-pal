class_name PalVrmLoader
extends RefCounted
## Editor plug-ins do not register glTF extensions in a running game.

const DEFAULT_AVATAR := "res://assets/DS-desktop.vrm"
const MAX_FILE_BYTES := 128 * 1024 * 1024
static var _extensions: Array[GLTFDocumentExtension] = []


static func load_avatar(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "vrm" or not FileAccess.file_exists(path):
		return {"error": "找不到 VRM 文件。"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 20 or file.get_length() > MAX_FILE_BYTES:
		return {"error": "模型无法读取，或大于 128 MB。"}
	if file.get_32() != 0x46546c67 or file.get_32() != 2:
		return {"error": "文件不是有效的 VRM / GLB 2.0。"}
	if file.get_32() != file.get_length():
		return {"error": "模型文件不完整。"}
	var json_length := file.get_32()
	if file.get_32() != 0x4e4f534a or json_length > 8 * 1024 * 1024 or json_length > file.get_length() - 20:
		return {"error": "模型清单无效。"}
	var parsed: Variant = JSON.parse_string(file.get_buffer(json_length).get_string_from_utf8())
	file.close()
	if not parsed is Dictionary:
		return {"error": "模型清单无法解析。"}
	if not parsed.get("extensions", {}) is Dictionary:
		return {"error": "模型扩展清单无效。"}
	var extensions: Dictionary = parsed.get("extensions", {})
	if not extensions.has("VRM") and not extensions.has("VRMC_vrm"):
		return {"error": "文件缺少 VRM 角色信息。"}
	for collection: String in ["buffers", "images"]:
		if not parsed.get(collection, []) is Array:
			return {"error": "模型资源清单无效。"}
		for entry: Variant in parsed.get(collection, []):
			if not entry is Dictionary or not entry.get("uri", "") is String:
				return {"error": "模型资源引用无效。"}
			var uri: String = entry.get("uri", "")
			if not uri.is_empty() and not uri.begins_with("data:"):
				return {"error": "请使用包含全部贴图的单文件 VRM。"}
	var avatar: Node3D
	if path.begins_with("res://") and ResourceLoader.exists(path, "PackedScene"):
		var packed := load(path) as PackedScene
		if packed != null:
			avatar = packed.instantiate() as Node3D
	else:
		_register_extensions()
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
		state.set_additional_data("vrm/head_hiding_method", 0)
		var error := document.append_from_file(path, state, GLTFDocument.IMPORT_FLAG_USE_NAMED_SKIN_BINDS)
		if error != OK:
			return {"error": "VRM 导入失败（%d）。" % error}
		avatar = document.generate_scene(state) as Node3D
	if avatar == null:
		return {"error": "无法生成角色场景。"}
	if avatar.find_children("*", "Skeleton3D", true, false).is_empty():
		avatar.free()
		return {"error": "这个角色缺少可用的人形骨骼。"}
	return {"avatar": avatar, "error": ""}


static func _register_extensions() -> void:
	if not _extensions.is_empty():
		return
	var script_paths: Array[String] = [
		"res://addons/vrm/vrm_extension.gd",
		"res://addons/vrm/1.0/VRMC_vrm.gd",
		"res://addons/vrm/1.0/VRMC_node_constraint.gd",
		"res://addons/vrm/1.0/VRMC_springBone.gd",
		"res://addons/vrm/1.0/VRMC_materials_hdr_emissiveMultiplier.gd",
		"res://addons/vrm/1.0/VRMC_materials_mtoon.gd",
	]
	# VRM retargeting and expression extraction require ImporterMesh nodes.
	# Place these ahead of Godot's built-in converter, preserving plug-in order.
	script_paths.reverse()
	for script_path: String in script_paths:
		var extension: GLTFDocumentExtension = load(script_path).new()
		_extensions.append(extension)
		GLTFDocument.register_gltf_document_extension(extension, true)
