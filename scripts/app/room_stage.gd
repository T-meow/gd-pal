class_name PalRoomStage
extends Control
## Owns only the room backdrop. Character and conversation have separate hosts.

const CATALOG_PATH := "res://assets/rooms/catalog.json"
var rooms: Array[Dictionary] = []
var current_id := ""
var _background: Control
var _scene_viewport: SubViewport


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if catalog is Dictionary:
		var seen := {}
		for entry: Variant in catalog.get("rooms", []):
			if not entry is Dictionary:
				continue
			var id := str(entry.get("id", ""))
			if id.is_empty() or seen.has(id) or str(entry.get("kind", "")) not in ["image", "scene3d"]:
				continue
			if not ResourceLoader.exists(str(entry.get("resource", ""))):
				continue
			seen[id] = true
			rooms.append(entry.duplicate(true))
	if rooms.is_empty():
		rooms.append({"id": "night-study", "name": "夜间书房", "kind": "image", "resource": "res://assets/rooms/night-study.svg", "thumbnail": "res://assets/rooms/night-study.svg", "caption": "今天也陪着你。", "description": "一盏灯，一段还没说完的话。", "mood": "安静 · 阅读"})
	visibility_changed.connect(_sync_rendering)


func find_room(id: String) -> Dictionary:
	for room: Dictionary in rooms:
		if str(room.id) == id:
			return room
	return {}


func select_room(id: String) -> String:
	var room := find_room(id)
	if room.is_empty():
		return "没有找到这个房间，请选择另一个房间。"
	if current_id == id and is_instance_valid(_background):
		return ""
	var resource := load(str(room.resource))
	var candidate: Control
	var viewport: SubViewport
	if str(room.kind) == "image":
		if not resource is Texture2D:
			return "房间背景无法读取，已保留原房间。"
		var picture := TextureRect.new()
		picture.texture = resource
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		candidate = picture
	elif str(room.kind) == "scene3d":
		if not resource is PackedScene:
			return "房间场景无法读取，已保留原房间。"
		var scene := (resource as PackedScene).instantiate()
		if not scene is Node3D:
			scene.free()
			return "3D 房间需要包含相机的 Node3D 场景。"
		var cameras := scene.find_children("*", "Camera3D", true, false)
		if scene is Camera3D:
			cameras.append(scene)
		if cameras.is_empty():
			scene.free()
			return "3D 房间缺少相机，已保留原房间。"
		var host := SubViewportContainer.new()
		host.stretch = true
		viewport = SubViewport.new()
		viewport.own_world_3d = true
		viewport.world_3d = World3D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		host.add_child(viewport)
		viewport.add_child(scene)
		(cameras[0] as Camera3D).current = true
		candidate = host
	candidate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	candidate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(candidate)
	if is_instance_valid(_background):
		remove_child(_background)
		_background.queue_free()
	_background = candidate
	_scene_viewport = viewport
	current_id = id
	_sync_rendering()
	return ""


func _sync_rendering() -> void:
	if is_instance_valid(_scene_viewport):
		_scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
