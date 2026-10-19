class_name PalCharacterWheel
extends Control
## One paged ring shared by the call host and the native desktop host.

signal action_requested(action: String)
signal mode_requested(mode: String)
signal more_requested

const INTIMACY_CATEGORY := "sexsual"

var pet: PalPetInstance
var desktop := false
var _entries: Array[Dictionary] = []
var _section := "root"
var _page := 0
var _hover := -1
var _center_text := "关闭"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	resized.connect(queue_redraw)
	mouse_exited.connect(func() -> void: _hover = -1; queue_redraw())
	hide()


func open_for(target: PalPetInstance, center: Vector2, on_desktop := false) -> void:
	if target == null or target.presenter == null:
		return
	if is_instance_valid(pet) and pet.capabilities_changed.is_connected(_on_capabilities_changed):
		pet.capabilities_changed.disconnect(_on_capabilities_changed)
	pet = target
	pet.capabilities_changed.connect(_on_capabilities_changed)
	desktop = on_desktop
	var available := (get_parent() as Control).size
	var side := minf(336.0, minf(available.x, available.y) - 12.0)
	size = Vector2.ONE * maxf(180.0, side)
	position = (center - size * 0.5).clamp(Vector2.ZERO, (available - size).max(Vector2.ZERO))
	_section = "root"
	_page = 0
	_rebuild()
	show()


func _on_capabilities_changed() -> void:
	if visible:
		_rebuild()


func _has_intimacy_actions() -> bool:
	if not pet.profile.adult_mode:
		return false
	for definition: Dictionary in pet.behavior.action_definitions.values():
		if str(definition.get("category", "")) == INTIMACY_CATEGORY and not bool(definition.get("internal", false)):
			return true
	return false


func _rebuild() -> void:
	_entries.clear()
	if not is_instance_valid(pet):
		hide()
		return
	var capabilities := pet.presenter.get_capabilities()
	var has_intimacy := _has_intimacy_actions()
	if _section == INTIMACY_CATEGORY and not has_intimacy:
		_section = "root"
		_page = 0
	_center_text = "关闭" if _section == "root" else "返回"
	if _section == "outfits":
		for id: String in capabilities.get("outfits", {}):
			_entries.append({"id": "outfit:" + id, "label": str(capabilities.outfits[id].label), "selected": id == pet.profile.outfit})
		_entries.append({"id": "allow", "label": "AI 换装\n" + ("开启" if pet.profile.allow_model_outfit else "关闭"), "selected": pet.profile.allow_model_outfit})
		_entries.append({"id": "lock", "label": "用户锁定\n" + ("已锁定" if pet.profile.outfit_override else "未锁定"), "selected": pet.profile.outfit_override})
	elif _section in ["actions", INTIMACY_CATEGORY]:
		var actions: Array[Dictionary] = []
		for id: String in pet.behavior.action_definitions:
			var definition: Dictionary = pet.behavior.action_definitions[id]
			if bool(definition.get("internal", false)) or (bool(definition.get("adult_only", false)) and not pet.profile.adult_mode):
				continue
			if (str(definition.get("category", "")) == INTIMACY_CATEGORY) != (_section == INTIMACY_CATEGORY):
				continue
			actions.append({"id": "action:" + id, "label": str(definition.get("label", id)), "selected": id == pet.behavior.current_action})
		if _section == "actions" and pet.behavior.action_definitions.is_empty():
			for id: String in pet.behavior.motion_actions:
				actions.append({"id": "action:" + id, "label": str(PalMotionLibrary.clip(id).get("label", id))})
		var pages := maxi(1, ceili(actions.size() / 6.0))
		_page = clampi(_page, 0, pages - 1)
		for entry: Dictionary in actions.slice(_page * 6, _page * 6 + 6):
			_entries.append(entry)
		if pages > 1:
			_entries.append({"id": "previous", "label": "上一页", "disabled": _page == 0})
			_entries.append({"id": "next", "label": "下一页", "disabled": _page == pages - 1})
		_center_text = "返回\n%d / %d" % [_page + 1, pages]
	else:
		_entries.append({"id": "actions", "label": "切换动作"})
		_entries.append({"id": "outfits", "label": "切换衣装", "disabled": capabilities.get("outfits", {}).is_empty()})
		if has_intimacy:
			_entries.append({"id": INTIMACY_CATEGORY, "label": "亲密动作"})
		if desktop:
			_entries.append({"id": "action:sit", "label": "坐下", "disabled": not pet.behavior.action_definitions.has("sit")})
			_entries.append({"id": "action:prone", "label": "趴下", "disabled": not pet.behavior.motion_actions.has("edge_rest") and not pet.behavior.action_definitions.has("prone")})
			if pet.profile.visual_id == "sprite2d":
				_entries.append({"id": "mode", "label": "桌宠模式" if pet.profile.desktop_mode == "call" else "2D 聊天"})
			_entries.append({"id": "more", "label": "更多设置"})
	_hover = -1
	queue_redraw()


func _index_at(point: Vector2) -> int:
	var offset := point - size * 0.5
	if offset.length() < size.x * 0.16 or offset.length() > size.x * 0.49 or _entries.is_empty():
		return -1
	var angle := fposmod(offset.angle() + PI * 0.5 + PI / _entries.size(), TAU)
	return mini(_entries.size() - 1, int(angle / TAU * _entries.size()))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _index_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			hide()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.distance_to(size * 0.5) < size.x * 0.16:
				if _section == "root":
					hide()
				else:
					_section = "root"
					_rebuild()
			else:
				var index := _index_at(event.position)
				if index >= 0 and not bool(_entries[index].get("disabled", false)):
					_choose(str(_entries[index].id))


func _choose(id: String) -> void:
	if id in ["actions", "outfits", INTIMACY_CATEGORY]:
		_section = id
		_page = 0
	elif id in ["next", "previous"]:
		_page += 1 if id == "next" else -1
	elif id.begins_with("outfit:"):
		pet.set_outfit(id.trim_prefix("outfit:"))
	elif id == "allow":
		pet.set_outfit_control("allow_model_outfit", not pet.profile.allow_model_outfit)
	elif id == "lock":
		pet.set_outfit_control("outfit_override", not pet.profile.outfit_override)
	elif id.begins_with("action:"):
		hide()
		action_requested.emit(id.trim_prefix("action:"))
		return
	elif id == "mode":
		hide()
		mode_requested.emit("full_body" if pet.profile.desktop_mode == "call" else "call")
		return
	elif id == "more":
		hide()
		more_requested.emit()
		return
	_rebuild()


func _draw() -> void:
	var center := size * 0.5
	var inner := size.x * 0.17
	var outer := size.x * 0.48
	var font := get_theme_default_font()
	var font_size := 13 if size.x >= 280 else 11
	for index: int in _entries.size():
		var entry := _entries[index]
		var angle := -PI * 0.5 + TAU * index / _entries.size()
		var half := PI / _entries.size() - 0.025
		var polygon := PackedVector2Array()
		for step: int in 17:
			polygon.append(center + Vector2.from_angle(angle - half + half * 2 * step / 16.0) * outer)
		for step: int in range(16, -1, -1):
			polygon.append(center + Vector2.from_angle(angle - half + half * 2 * step / 16.0) * inner)
		var color := Color("25384deb")
		if bool(entry.get("selected", false)):
			color = Color("326b91f5")
		if index == _hover and not bool(entry.get("disabled", false)):
			color = color.lightened(0.18)
		draw_colored_polygon(polygon, color)
		var caption := str(entry.label)
		if not caption.contains("\n") and caption.length() > 5:
			caption = caption.substr(0, 4) + "\n" + caption.substr(4, 5)
		_draw_caption(caption, center + Vector2.from_angle(angle) * (inner + outer) * 0.5, font, font_size, Color("8c99a8") if bool(entry.get("disabled", false)) else Color.WHITE)
	draw_circle(center, inner - 3, Color("192a3bf5"))
	_draw_caption(_center_text, center, font, font_size, Color.WHITE)


func _draw_caption(text: String, center: Vector2, font: Font, font_size: int, color: Color) -> void:
	var lines := text.split("\n")
	for index: int in lines.size():
		var width := font.get_string_size(lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var y := center.y + (index - (lines.size() - 1) * 0.5) * (font_size + 5) + font_size * 0.35
		draw_string(font, Vector2(center.x - width * 0.5, y), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
