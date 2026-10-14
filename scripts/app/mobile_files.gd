class_name PalMobileFiles
extends RefCounted
## File picker grants may expire; imported models live in private app storage.

static func copy_into_app(source: String, directory: String, extension: String, limit: int) -> Dictionary:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null:
		return {"error": "无法读取所选文件，请重新选择。"}
	var length := input.get_length()
	if length <= 0 or length > limit:
		return {"error": "文件为空或过大，请选择较小的文件。"}
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return {"error": "无法创建导入目录，请检查存储空间。"}
	var path := directory.path_join(Crypto.new().generate_random_bytes(16).hex_encode() + extension)
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return {"error": "无法保存导入文件，请检查存储空间。"}
	var copied := 0
	while copied < length:
		var block := input.get_buffer(mini(262144, length - copied))
		if block.is_empty():
			break
		output.store_buffer(block)
		copied += block.size()
	output.flush()
	var failed := output.get_error() != OK or copied != length
	output.close()
	input.close()
	if failed:
		DirAccess.remove_absolute(path)
		return {"error": "文件未完整保存，请检查存储空间后重试。"}
	return {"path": path}


static func import_avatar(source: String) -> Dictionary:
	var result := copy_into_app(source, "user://imports/avatars", ".vrm", 128 * 1024 * 1024)
	if result.has("error"):
		return result
	var file := FileAccess.open(str(result.path), FileAccess.READ)
	var valid := file != null and file.get_length() >= 20
	if valid:
		valid = file.get_32() == 0x46546c67 and file.get_32() == 2 and file.get_32() == file.get_length()
	if file != null:
		file.close()
	if not valid:
		DirAccess.remove_absolute(str(result.path))
		return {"error": "所选文件不是有效的 VRM / GLB 模型。"}
	return result


static func export_record(parent: Node, source: String, finished: Callable) -> void:
	export_file(parent, source, source.get_file(), "导出对话记录", "*.md ; Markdown 记录 ; text/markdown,text/plain", finished)


static func export_file(parent: Node, source: String, filename: String, title: String, filter: String, finished: Callable) -> void:
	if not FileAccess.file_exists(source):
		finished.call("导出文件不存在，请重新导出。")
		return
	var dialog := FileDialog.new()
	dialog.title = title
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray([filter])
	dialog.current_file = filename
	parent.add_child(dialog)
	dialog.canceled.connect(func() -> void:
		finished.call("已取消导出。")
		dialog.queue_free()
	)
	dialog.file_selected.connect(func(destination: String) -> void:
		if not destination.begins_with("content://") and destination.get_extension().is_empty():
			destination += "." + filename.get_extension()
		if ProjectSettings.globalize_path(destination).simplify_path() == ProjectSettings.globalize_path(source).simplify_path():
			finished.call("所选位置就是原记录，文件已保留。")
			dialog.queue_free()
			return
		var input := FileAccess.open(source, FileAccess.READ)
		var output := FileAccess.open(destination, FileAccess.WRITE) if input != null else null
		var error := input == null or output == null
		if not error:
			while input.get_position() < input.get_length():
				var bytes := input.get_buffer(262144)
				if bytes.is_empty():
					error = true
					break
				output.store_buffer(bytes)
			output.flush()
			error = error or output.get_error() != OK
		if input != null:
			input.close()
		if output != null:
			output.close()
		finished.call("文件已导出。" if not error else "导出失败，请检查目标位置是否可写。")
		dialog.queue_free()
	)
	dialog.popup_centered_ratio(0.8)
