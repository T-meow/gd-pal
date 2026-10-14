extends VBoxContainer
## Drafts follow their conversation even while a native picker or decoder is open.

signal changed
signal notice(message: String)

var service: Node
var _profile := ""
var _session := ""
var _drafts: Dictionary = {}
var _pending: Dictionary = {}
var _picker: FileDialog
var _picker_key := ""
var _preview: AcceptDialog


func _ready() -> void:
	service.connect("ChatImageImported", _on_imported)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hide()


func _key() -> String:
	return _profile + ":" + _session


func set_context(profile: String, session: String) -> void:
	if _profile == profile and _session == session:
		return
	_profile = profile
	_session = session
	_refresh()


func images() -> Array:
	return _drafts.get(_key(), []).duplicate(true)


func _pending_count(key: String) -> int:
	var count := 0
	for entry: Dictionary in _pending.values():
		if str(entry.key) == key and not bool(entry.get("discard", false)):
			count += 1
	return count


func is_importing() -> bool:
	return _pending_count(_key()) > 0


func can_add() -> bool:
	return not _profile.is_empty() and not _session.is_empty() and images().size() + _pending_count(_key()) < 4


func clear_after_send() -> void:
	_drafts.erase(_key())
	_refresh()


func restore_images(value: Array) -> void:
	_drafts[_key()] = value.duplicate(true)
	_refresh()


func forget(profile: String, session: String) -> void:
	var key := profile + ":" + session
	if key == _picker_key and is_instance_valid(_picker):
		_picker.queue_free()
	for attachment: Dictionary in _drafts.get(key, []):
		service.call("DiscardChatImage", profile, str(attachment.file))
	_drafts.erase(key)
	for entry: Dictionary in _pending.values():
		if str(entry.key) == key:
			entry["discard"] = true
	_refresh()


func pick_images() -> void:
	if not can_add():
		notice.emit("每条消息最多附带 4 张图片。")
		return
	if is_instance_valid(_picker):
		return
	var profile := _profile
	var key := _key()
	var dialog := FileDialog.new()
	_picker = dialog
	_picker_key = key
	dialog.title = "选择聊天图片"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片 ; image/png,image/jpeg,image/webp"])
	dialog.use_native_dialog = true
	add_child(dialog)
	dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		for path: String in paths:
			if _drafts.get(key, []).size() + _pending_count(key) >= 4:
				notice.emit("每条消息最多附带 4 张图片，其余图片未加入。")
				break
			_start_import(profile, key, path, false)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.8)


func paste_image() -> bool:
	if PalUi.is_mobile() or not DisplayServer.clipboard_has_image():
		return false
	if not can_add():
		notice.emit("每条消息最多附带 4 张图片。")
		return true
	_start_import(_profile, _key(), "", true)
	return true


func _start_import(profile: String, key: String, path: String, clipboard: bool) -> void:
	var request := Crypto.new().generate_random_bytes(16).hex_encode()
	_pending[request] = {"profile": profile, "key": key}
	if clipboard:
		service.call("ImportClipboardImage", profile, request)
	else:
		service.call("ImportChatImage", profile, request, path)
	_refresh()


func _on_imported(profile: String, request: String, json: String) -> void:
	if not _pending.has(request):
		return
	var entry: Dictionary = _pending[request]
	_pending.erase(request)
	var result: Dictionary = JSON.parse_string(json)
	var error := str(result.get("error", ""))
	if error.is_empty():
		var attachment: Dictionary = result.image
		if bool(entry.get("discard", false)):
			service.call("DiscardChatImage", profile, str(attachment.file))
		else:
			var draft: Array = _drafts.get(str(entry.key), [])
			draft.append(attachment)
			_drafts[str(entry.key)] = draft
	_refresh()
	if not error.is_empty() and str(entry.key) == _key():
		notice.emit(error)


func _remove_image(file: String) -> void:
	var draft := images()
	for index: int in range(draft.size() - 1, -1, -1):
		if str(draft[index].file) == file:
			draft.remove_at(index)
	_drafts[_key()] = draft
	var error: String = service.call("DiscardChatImage", _profile, file)
	_refresh()
	if not error.is_empty():
		notice.emit(error)


func _refresh() -> void:
	# The file dialog and preview are Windows, not controls in the thumbnail strip.
	for child: Node in get_children():
		if child is Control:
			remove_child(child)
			child.queue_free()
	var draft := images()
	visible = not draft.is_empty() or is_importing()
	if not draft.is_empty():
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = 86
		add_child(scroll)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		scroll.add_child(row)
		for attachment: Dictionary in draft:
			var tile := Control.new()
			tile.custom_minimum_size = Vector2(88, 72)
			row.add_child(tile)
			var button := _thumbnail(tile, _profile, str(attachment.file), Vector2(88, 72))
			button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var remove := Button.new()
			remove.text = "×"
			remove.tooltip_text = "移除图片"
			remove.custom_minimum_size = Vector2(32, 32)
			remove.position = Vector2(56, 0)
			tile.add_child(remove)
			var file := str(attachment.file)
			remove.pressed.connect(func() -> void: _remove_image.call_deferred(file))
	if is_importing():
		PalUi.hint("正在处理图片…", self)
	elif not draft.is_empty():
		PalUi.hint("%d / 4 张 · 请使用支持识图的模型" % draft.size(), self)
	changed.emit()


func add_message_images(parent: Node, profile: String, attachments: Array) -> void:
	if attachments.is_empty():
		return
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	parent.add_child(row)
	for attachment: Dictionary in attachments:
		_thumbnail(row, profile, str(attachment.file), Vector2(128, 96))


func _thumbnail(parent: Node, profile: String, file: String, dimensions: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = dimensions
	button.tooltip_text = "点击查看图片"
	parent.add_child(button)
	var path: String = service.call("GetChatImagePath", profile, file, true)
	var texture := _texture(path)
	if texture == null:
		button.text = "图片缺失"
		button.disabled = true
	else:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(picture)
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.pressed.connect(func() -> void: _show_image(profile, file))
	return button


func _texture(path: String) -> ImageTexture:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


func _show_image(profile: String, file: String) -> void:
	var path: String = service.call("GetChatImagePath", profile, file, false)
	var texture := _texture(path)
	if texture == null:
		notice.emit("图片文件缺失，无法打开。")
		return
	if is_instance_valid(_preview):
		_preview.queue_free()
	var dialog := AcceptDialog.new()
	_preview = dialog
	dialog.title = "聊天图片"
	dialog.ok_button_text = "关闭"
	dialog.exclusive = true
	add_child(dialog)
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(200, 160)
	dialog.add_child(picture)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.85)
