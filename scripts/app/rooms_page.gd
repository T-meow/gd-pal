class_name PalRoomsPage
extends ScrollContainer

signal room_selected(room_id: String)
signal return_requested

var _column: VBoxContainer
var _grid: GridContainer
var _cards: Dictionary = {}
var _selected_name: Label
var _rooms: Array[Dictionary] = []


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 26)
	margin.add_child(_column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 24)
	_column.add_child(heading)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 12)
	heading.add_child(words)
	PalUi.label("PLACES WE CALL OURS", words, 10, true)
	PalUi.label("让故事，换一个背景。", words, 28)
	PalUi.hint("同一个人，不同的日常。今天想在哪里相见？", words)
	var back := PalUi.icon_button("回到通话", "back", heading, func() -> void: return_requested.emit())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PalUi.label("我们的房间", _column, 15)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 20)
	_column.add_child(_grid)
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", PalUi.glass(0.8, 12, 22))
	_column.add_child(footer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	footer.add_child(row)
	var selection := VBoxContainer.new()
	selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(selection)
	PalUi.label("此刻停留", selection, 11, true)
	_selected_name = PalUi.label("", selection, 19)
	PalUi.hint("换一个房间，接着说刚才的故事。", selection)
	var return_button := PalUi.icon_button("回到伙伴身边", "arrow", row, func() -> void: return_requested.emit(), true)
	return_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PalUi.label("每一处风景，都可以成为新的开始。", _column, 12, true)
	resized.connect(_resize_cards)


func configure(rooms: Array[Dictionary], selected: String) -> void:
	_rooms = rooms
	for room: Dictionary in rooms:
		var id := str(room.id)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size.x = 190
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.focus_mode = Control.FOCUS_ALL
		card.gui_input.connect(func(event: InputEvent) -> void:
			if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]):
				room_selected.emit(id)
				card.accept_event()
		)
		_grid.add_child(card)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 0)
		card.add_child(body)
		var image := TextureRect.new()
		image.custom_minimum_size.y = 215
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.clip_contents = true
		var thumbnail := str(room.get("thumbnail", ""))
		if ResourceLoader.exists(thumbnail):
			image.texture = load(thumbnail) as Texture2D
		body.add_child(image)
		var padding := MarginContainer.new()
		for side: String in ["left", "right", "top", "bottom"]:
			padding.add_theme_constant_override("margin_" + side, 18)
		body.add_child(padding)
		var details := VBoxContainer.new()
		details.add_theme_constant_override("separation", 12)
		padding.add_child(details)
		PalUi.label(str(room.get("english", "YOUR SPACE")), details, 10, true)
		PalUi.label(str(room.name), details, 23)
		var description := PalUi.hint(str(room.get("description", "")), details)
		description.custom_minimum_size.y = 48
		PalUi.label(str(room.get("mood", "")), details, 12, true)
		var state_label := PalUi.label("", details, 12)
		state_label.add_theme_color_override("font_color", PalUi.ACCENT)
		for child: Control in card.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards[id] = {"card": card, "image": image, "state": state_label}
	set_current(selected)
	_resize_cards()


func set_current(id: String) -> void:
	for room: Dictionary in _rooms:
		var view: Dictionary = _cards[str(room.id)]
		var active := str(room.id) == id
		var style := PalUi.panel(PalUi.SURFACE, 12, 0)
		style.border_color = PalUi.ACCENT if active else PalUi.BORDER
		style.set_border_width_all(2 if active else 1)
		view.card.add_theme_stylebox_override("panel", style)
		view.state.text = "● 正在停留" if active else "选择这个房间  →"
		if active:
			_selected_name.text = str(room.name)


func _resize_cards() -> void:
	for view: Dictionary in _cards.values():
		view.image.custom_minimum_size.y = clampf((size.x - 100.0) / 3.0 * 0.62, 150, 270)
