class_name PalDesktopPage
extends ScrollContainer
## Desktop controls use the coordinator's real companion hosts.

signal desktop_requested
signal page_requested(page_id: String)
signal preference_requested(key: String, value: Variant)
signal profile_selected(profile_id: String)
signal return_requested

var _name: Label
var _presence: Label
var _portrait: TextureRect
var _primary: Button
var _chat: Button
var _restore_call: Button
var _look: CheckButton
var _wander: CheckButton
var _dialogue: CheckButton
var _scale: HSlider
var _scale_label: Label
var _partners: HFlowContainer
var _has_profile := false
var _presence_mode := "empty"
var _mode: OptionButton
var _edge: OptionButton
var _allow_outfit: CheckButton
var _outfit_lock: CheckButton


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 12)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	PalUi.label("A LITTLE CLOSER", titles, 10, true)
	PalUi.label("让陪伴，留在桌面。", titles, 28)
	PalUi.hint("忙你的就好。伙伴会在一个小小的角落，陪着你。", titles)
	var back := PalUi.icon_button("返回通话", "call", header, func() -> void: return_requested.emit())
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var companion := PanelContainer.new()
	companion.add_theme_stylebox_override("panel", PalUi.glass(0.88, 14, 24))
	column.add_child(companion)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	companion.add_child(row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(180, 230)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_portrait)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 14)
	row.add_child(details)
	PalUi.label("此刻的伙伴", details, 11, true)
	_name = PalUi.label("还没有伙伴", details, 26)
	_presence = PalUi.hint("添加一位伙伴，开始桌面陪伴。", details)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	details.add_child(actions)
	_primary = PalUi.icon_button("放到桌面", "desktop", actions, func() -> void: desktop_requested.emit(), true)
	_restore_call = PalUi.icon_button("2D 聊天", "call", actions, func() -> void: page_requested.emit("floating_call"))
	_restore_call.name = "Open2DChat"
	_restore_call.tooltip_text = "打开近景角色和聊天窗口；保持当前对话开关，不会自动发送消息。"
	_chat = PalUi.icon_button("查看对话", "chat", actions, func() -> void: page_requested.emit("desktop_chat"))
	PalUi.icon_button("伙伴档案", "profile", actions, func() -> void: page_requested.emit("profile"))
	PalUi.hint("拖动角色调整位置，滚轮缩放；右键可以互动。新回复只显示未读提示。", details)
	var preferences := HBoxContainer.new()
	preferences.add_theme_constant_override("separation", 28)
	column.add_child(preferences)
	var behavior := VBoxContainer.new()
	behavior.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	behavior.add_theme_constant_override("separation", 10)
	preferences.add_child(behavior)
	PalUi.label("陪伴的方式", behavior, 17)
	_dialogue = CheckButton.new()
	_dialogue.text = "启用对话"
	_dialogue.tooltip_text = "当前伙伴在大厅和桌面共用此开关。关闭后点击仍会随机切换对应立绘，不发送或朗读对话；也可查看历史记录。"
	behavior.add_child(_dialogue)
	_dialogue.toggled.connect(func(value: bool) -> void: preference_requested.emit("desktop_dialogue_enabled", value))
	_look = CheckButton.new()
	_look.text = "看向鼠标"
	behavior.add_child(_look)
	_look.toggled.connect(func(value: bool) -> void: preference_requested.emit("look_at_mouse", value))
	_wander = CheckButton.new()
	_wander.text = "沿桌面底边散步"
	behavior.add_child(_wander)
	_wander.toggled.connect(func(value: bool) -> void: preference_requested.emit("wander", value))
	PalUi.label("2D 桌面模式", behavior, 13)
	_mode = OptionButton.new()
	_mode.add_item("桌宠 · 全身与坐趴")
	_mode.add_item("2D 聊天 · 近景与对话")
	_mode.add_item("极简监控 · 从性能页开启")
	_mode.set_item_disabled(2, true)
	behavior.add_child(_mode)
	_mode.item_selected.connect(func(index: int) -> void: preference_requested.emit("desktop_mode", "call" if index == 1 else "full_body"))
	PalUi.hint("2D 聊天显示近景角色和对话窗口；极简监控显示角色与性能数据，可从性能页开启。", behavior)
	PalUi.label("任务栏 / 窗口边缘姿势", behavior, 13)
	_edge = OptionButton.new()
	_edge.add_item("坐下")
	_edge.add_item("趴下")
	behavior.add_child(_edge)
	_edge.item_selected.connect(func(index: int) -> void: preference_requested.emit("edge_posture", "prone" if index == 1 else "sit"))
	_allow_outfit = CheckButton.new()
	_allow_outfit.text = "允许 AI 选择衣装"
	behavior.add_child(_allow_outfit)
	_allow_outfit.toggled.connect(func(value: bool) -> void: preference_requested.emit("allow_model_outfit", value))
	_outfit_lock = CheckButton.new()
	_outfit_lock.text = "用户锁定当前衣装"
	behavior.add_child(_outfit_lock)
	_outfit_lock.toggled.connect(func(value: bool) -> void: preference_requested.emit("outfit_override", value))
	PalUi.hint("手动换装会自动锁定。解除锁定后，AI 才能再次换装。", behavior)
	var scale_column := VBoxContainer.new()
	scale_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_column.add_theme_constant_override("separation", 15)
	preferences.add_child(scale_column)
	_scale_label = PalUi.label("桌宠大小", scale_column, 17)
	_scale = HSlider.new()
	_scale.min_value = 0.5
	_scale.max_value = 2.0
	_scale.step = 0.05
	_scale.custom_minimum_size = Vector2(220, 28)
	scale_column.add_child(_scale)
	_scale.value_changed.connect(func(value: float) -> void:
		_scale_label.text = "桌宠大小 · %d%%" % roundi(value * 100)
		preference_requested.emit("desktop_scale", value)
	)
	PalUi.hint("桌宠可吸附任务栏与窗口上沿；右键环形菜单可切换坐下、趴下、动作和衣装。通话构图独立保存。", scale_column)
	var partners_header := HBoxContainer.new()
	column.add_child(partners_header)
	PalUi.label("我的伙伴", partners_header, 17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PalUi.icon_button("全部召回", "back", partners_header, func() -> void: page_requested.emit("recall_all"))
	_partners = HFlowContainer.new()
	_partners.add_theme_constant_override("h_separation", 12)
	_partners.add_theme_constant_override("v_separation", 12)
	column.add_child(_partners)


func update_roster(entries: Array, selected: String) -> void:
	for child: Node in _partners.get_children():
		_partners.remove_child(child)
		child.queue_free()
	_has_profile = false
	for entry: Dictionary in entries:
		var id := str(entry.id)
		var button := PalUi.button(str(entry.name) + " · " + str(entry.status), _partners, func() -> void: profile_selected.emit(id), id == selected)
		button.tooltip_text = "选择伙伴并召回通话"
		button.add_theme_font_size_override("font_size", 13)
		if id == selected:
			_has_profile = true
			_name.text = str(entry.name)
			_portrait.texture = entry.get("portrait") if entry.get("portrait") != null else preload("res://assets/ui/pal_mark.svg")
	_primary.disabled = not _has_profile
	_chat.disabled = not _has_profile
	_restore_call.disabled = not _has_profile
	_look.disabled = not _has_profile
	_wander.disabled = not _has_profile
	_dialogue.disabled = not _has_profile
	_scale.editable = _has_profile
	for control: BaseButton in [_mode, _edge, _allow_outfit, _outfit_lock]:
		control.disabled = not _has_profile
	if not _has_profile:
		_name.text = "还没有伙伴"
		_portrait.texture = preload("res://assets/ui/pal_mark.svg")
		_presence.text = "从左侧添加伙伴，开始桌面陪伴。"


func set_presence(mode: String) -> void:
	_presence_mode = mode
	_chat.disabled = not _has_profile
	_primary.text = "召回通话" if mode == "desktop" else "放到桌面"
	_presence.text = "● 正在桌面陪伴你" if mode == "desktop" else "当前在通话中，随时可以去桌面陪伴。"
	if mode == "empty":
		_presence.text = "添加一位伙伴，开始桌面陪伴。"


func set_preferences(profile: PalProfile) -> void:
	if profile == null:
		return
	_restore_call.visible = profile.visual_id == "sprite2d"
	_look.set_pressed_no_signal(profile.look_at_mouse)
	_wander.set_pressed_no_signal(profile.wander)
	_dialogue.set_pressed_no_signal(profile.desktop_dialogue_enabled)
	_chat.disabled = not _has_profile
	var scale_value := profile.minimal_monitor_scale if profile.desktop_mode == "minimal" else profile.desktop_scale
	_scale.set_value_no_signal(scale_value)
	_scale_label.text = "桌宠大小 · %d%%" % roundi(scale_value * 100)
	_mode.select(2 if profile.desktop_mode == "minimal" else (1 if profile.desktop_mode == "call" else 0))
	_edge.select(1 if profile.edge_posture == "prone" else 0)
	_allow_outfit.set_pressed_no_signal(profile.allow_model_outfit)
	_outfit_lock.set_pressed_no_signal(profile.outfit_override)
	for control: BaseButton in [_mode, _edge, _allow_outfit, _outfit_lock]:
		control.disabled = profile.visual_id != "sprite2d"
