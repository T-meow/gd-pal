class_name PalMotionMenu
extends RefCounted


static func populate(popup: PopupMenu, available: PackedStringArray, requested: Callable, definitions: Dictionary = {}) -> void:
	popup.clear(true)
	for entry: Array in [["挥挥手", "greet"], ["摸摸头", "head_pat"], ["开心一下", "happy"], ["小小惊喜", "surprised"], ["返回待机", "idle"]]:
		popup.add_item(entry[0])
		popup.set_item_metadata(popup.item_count - 1, entry[1])
	# Populate can be called again after changing avatars; keep one handler per menu.
	if not popup.has_meta("motion_handler"):
		popup.id_pressed.connect(func(id: int) -> void:
			requested.call(str(popup.get_item_metadata(popup.get_item_index(id)))))
		popup.set_meta("motion_handler", true)
	if available.is_empty():
		return
	if not definitions.is_empty():
		_populate_portraits(popup, available, requested, definitions)
		return
	popup.add_separator("动作库")
	var categories: Dictionary = {}
	for clip: Dictionary in PalMotionLibrary.CATALOG.CLIPS:
		if not available.has(clip.id):
			continue
		if not categories.has(clip.category):
			var submenu := PopupMenu.new()
			submenu.name = clip.category
			popup.add_child(submenu)
			popup.add_submenu_item(clip.category_label, submenu.name)
			submenu.id_pressed.connect(func(id: int) -> void:
				requested.call(str(submenu.get_item_metadata(submenu.get_item_index(id)))))
			categories[clip.category] = submenu
		var menu: PopupMenu = categories[clip.category]
		var mode_label: String = {"loop": "循环", "once": "单次", "hold": "保持"}[clip.mode]
		menu.add_item(clip.label + " · " + mode_label)
		var index := menu.item_count - 1
		menu.set_item_metadata(index, clip.id)
		var support: String = clip.support.get("type", "none")
		if support in ["chair", "bed"]:
			menu.set_item_tooltip(index, "适合搭配椅子" if support == "chair" else "适合搭配床面")
		elif support == "floor":
			menu.set_item_tooltip(index, "地面姿势，建议放到桌面查看全身；可选择“返回待机”结束")


static func _populate_portraits(popup: PopupMenu, available: PackedStringArray, requested: Callable, definitions: Dictionary) -> void:
	popup.add_separator("立绘互动")
	var categories: Dictionary = {}
	for action: String in available:
		if action in ["idle", "greet", "head_pat", "happy", "surprised"] or not definitions.has(action):
			continue
		var entry: Dictionary = definitions[action]
		if bool(entry.get("internal", false)):
			continue
		var category := str(entry.get("category", "日常"))
		if not categories.has(category):
			var submenu := PopupMenu.new()
			submenu.name = "Portraits" + str(categories.size())
			popup.add_child(submenu)
			popup.add_submenu_item(str(entry.get("category_label", category)), submenu.name)
			submenu.id_pressed.connect(func(id: int) -> void: requested.call(str(submenu.get_item_metadata(submenu.get_item_index(id)))))
			categories[category] = submenu
		var menu: PopupMenu = categories[category]
		var suffix := " · 保持" if str(entry.get("mode")) == "hold" else ""
		menu.add_item(str(entry.get("label", action)) + suffix)
		menu.set_item_metadata(menu.item_count - 1, action)
