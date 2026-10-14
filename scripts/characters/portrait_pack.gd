class_name PalPortraitPack
extends RefCounted
## Static character data is shared by both hosts; textures load only when used.

const DEFAULT_MANIFEST := "res://assets/characters/blue_whale/manifest.json"
var manifest: Dictionary = {}
var visual: Dictionary = {}
var base_path := ""
var error := ""
var _textures: Dictionary = {}


func open(path: String) -> bool:
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK:
		return _fail("无法读取 2D 角色包清单：" + path)
	if not json.data is Dictionary:
		return _fail("2D 角色包清单必须是 JSON 对象。")
	manifest = json.data
	if manifest.get("schema_version") != 1 or not manifest.get("visuals") is Dictionary:
		return _fail("不支持的 2D 角色包格式。")
	var selected: Variant = manifest.visuals.get(str(manifest.get("default_visual", "portrait2d")))
	if not selected is Dictionary or selected.get("type") != "portrait2d":
		return _fail("角色包缺少静态 2D 外观。")
	visual = selected
	base_path = path.get_base_dir()
	for key: String in ["poses", "views", "actions", "expressions"]:
		if not visual.get(key) is Dictionary or visual[key].is_empty():
			return _fail("角色包缺少有效的 " + key + "。")
	for id: String in visual.poses:
		var pose: Variant = visual.poses[id]
		if not pose is Dictionary:
			return _fail("无效立绘：" + id)
		var file := str(pose.get("file", "")).replace("\\", "/")
		if file.is_empty() or file.is_absolute_path() or file.contains(":") or ".." in file.split("/") or file.get_extension().to_lower() not in ["png", "webp"]:
			return _fail("立绘路径必须是包内 PNG/WebP：" + id)
		if not _numbers(pose.get("canvas_size"), 2) or not _numbers(pose.get("anchor"), 2) or not _numbers(pose.get("alpha_bounds"), 4):
			return _fail("立绘缺少画布、锚点或边界：" + id)
		if float(pose.canvas_size[0]) <= 0 or float(pose.canvas_size[1]) <= 0:
			return _fail("无效立绘画布：" + id)
		if not FileAccess.file_exists(base_path.path_join(file)) and not ResourceLoader.exists(base_path.path_join(file), "Texture2D"):
			return _fail("找不到立绘：" + file)
	for view: String in ["full_body", "call"]:
		var entry: Variant = visual.views.get(view)
		if not entry is Dictionary or not visual.poses.has(str(entry.get("default_pose", ""))):
			return _fail("缺少视图默认立绘：" + view)
	for group: String in ["actions", "expressions"]:
		for id: String in visual[group]:
			var entry: Variant = visual[group][id]
			if not entry is Dictionary or not entry.get("views") is Dictionary:
				return _fail("无效动作或表情映射：" + id)
			for view: String in entry.views:
				var pose_id := str(entry.views[view])
				if not visual.poses.has(pose_id) or str(visual.poses[pose_id].get("view")) != view:
					return _fail("动作或表情引用了错误视图：" + id)
			for outfit_id: String in entry.get("outfits", {}):
				for view: String in entry.outfits[outfit_id]:
					var pose_id := str(entry.outfits[outfit_id][view])
					if not visual.poses.has(pose_id) or str(visual.poses[pose_id].get("view")) != view or str(visual.poses[pose_id].get("outfit", "maid")) != outfit_id:
						return _fail("衣装引用了错误立绘：" + id)
	for outfit_id: String in outfits():
		for view: String in ["full_body", "call"]:
			var pose_id := default_pose(view, outfit_id)
			if not visual.poses.has(pose_id) or str(visual.poses[pose_id].get("view")) != view or str(visual.poses[pose_id].get("outfit", "maid")) != outfit_id:
				return _fail("衣装缺少默认立绘：" + outfit_id)
	return true


func default_pose(view: String, outfit_id := "maid") -> String:
	return str(visual.get("outfits", {}).get(outfit_id, {}).get("defaults", {}).get(view, visual.views[view].default_pose))


func outfits() -> Dictionary:
	return visual.get("outfits", {"maid": {"label": "普通衣装"}})


func resolve_pose(entry: Dictionary, view: String, outfit_id: String) -> String:
	var pose_id := str(entry.get("outfits", {}).get(outfit_id, {}).get(view, ""))
	if pose_id.is_empty():
		pose_id = str(entry.get("views", {}).get(view, ""))
	if not visual.poses.has(pose_id) or str(visual.poses[pose_id].get("outfit", "maid")) != outfit_id:
		return ""
	return pose_id


func texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := base_path.path_join(str(visual.poses[id].file))
	var result: Texture2D
	if path.begins_with("res://"):
		result = load(path) as Texture2D
	else:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			result = ImageTexture.create_from_image(image)
	if result != null:
		_textures[id] = result
	return result


func definitions(group: String, view: String, include_internal := false, adult_mode := false, outfit_id := "maid") -> Dictionary:
	var result: Dictionary = {}
	for id: String in visual[group]:
		var entry: Dictionary = visual[group][id]
		if bool(entry.get("adult_only", false)) and not adult_mode:
			continue
		if not resolve_pose(entry, view, outfit_id).is_empty() and (include_internal or not bool(entry.get("internal", false))):
			result[id] = entry
	return result


func _fail(message: String) -> bool:
	error = message
	return false


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number: Variant in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
	return true
