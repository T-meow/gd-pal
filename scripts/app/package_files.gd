class_name PalPackageFiles
extends Node

var _service: Node
var _request := ""
var _finished: Callable
var _export_path := ""


static func export_package(parent: Node, service: Node, profile_id: String, kind: String, session_id: String, draft: Dictionary, memory: bool, world: bool, finished: Callable) -> void:
	var job := PalPackageFiles.new()
	job._service = service
	job._request = Crypto.new().generate_random_bytes(16).hex_encode()
	job._finished = finished
	parent.add_child(job)
	service.connect("PackageFinished", job._on_export)
	service.call("ExportPackage", profile_id, job._request, kind, session_id, JSON.stringify(draft), memory, world)


func _on_export(_profile: String, request_id: String, json: String) -> void:
	if request_id != _request:
		return
	_service.disconnect("PackageFinished", _on_export)
	_request = ""
	var data: Dictionary = JSON.parse_string(json)
	if data.has("error"):
		_finish(str(data.error))
		return
	_export_path = str(data.path)
	PalMobileFiles.export_file(self, _export_path, str(data.filename), "导出数据包", "*.zip ; GD Pal 数据包 ; application/zip", _finish)


func _finish(message: String) -> void:
	if not _export_path.is_empty():
		var error: String = _service.call("ReleaseExportPackage", _export_path)
		if not error.is_empty():
			message += " 临时包可手动清理：" + _export_path
		_export_path = ""
	if _finished.is_valid():
		_finished.call(message)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_service) and not _request.is_empty():
		_service.call("CancelPackage", _request)
	if is_instance_valid(_service) and not _export_path.is_empty():
		_service.call("ReleaseExportPackage", _export_path)


static func pick_import(parent: Node, service: Node, finished: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.title = "选择人设或对话记录包"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.zip ; GD Pal 数据包 ; application/zip"])
	dialog.use_native_dialog = true
	parent.add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		var result := PalMobileFiles.copy_into_app(path, str(service.call("GetPackageImportDirectory")), ".zip", 64 * 1024 * 1024)
		finished.call(result)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)
