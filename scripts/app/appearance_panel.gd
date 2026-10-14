class_name PalAppearancePanel
extends VBoxContainer

signal appearance_requested(mode: String, accent: Color)
signal overlay_requested(opacity: float, dialogue: bool, description: bool, autoplay: bool)
signal touch_regions_requested(value: bool)
var _mode: OptionButton
var _color: ColorPickerButton
var _status: Label
var _debounce: Timer
var _opening := false
var _opacity: HSlider
var _opacity_caption: Label
var _dialogue: CheckButton
var _description: CheckButton
var _playback: OptionButton
var _touch_regions: CheckButton


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	set_meta("preferred_width", 640)
	set_meta("preferred_height", 760)
	PalUi.label("让界面更合你的心意", self, 23)
	PalUi.hint("立即应用到大厅、聊天、管理面板和桌面悬浮窗，保留当前对话与草稿。", self)
	PalUi.label("显示模式", self, 14)
	_mode = OptionButton.new()
	_mode.add_item("暗色模式")
	_mode.add_item("亮色模式")
	add_child(_mode)
	_mode.item_selected.connect(func(_index: int) -> void: _apply())
	PalUi.label("主题色", self, 14)
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.custom_minimum_size = Vector2(120, 42)
	_color.tooltip_text = "选择任意颜色，也可在取色器中输入十六进制颜色值"
	add_child(_color)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.15
	add_child(_debounce)
	_debounce.timeout.connect(_apply)
	_color.color_changed.connect(func(_value: Color) -> void:
		if not _opening:
			_debounce.start())
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 8)
	add_child(presets)
	for hex: String in ["6b9fd4", "4bada4", "a88bd1", "d88fa1", "cf9c50", "acc9e7"]:
		var swatch := Button.new()
		var tint := Color(hex)
		swatch.custom_minimum_size = Vector2(48, 36)
		swatch.tooltip_text = "#" + hex
		swatch.set_meta("pal_fixed_palette", true)
		for state: String in ["normal", "hover", "pressed"]:
			swatch.add_theme_stylebox_override(state, PalUi.panel(tint, 8, 0))
		presets.add_child(swatch)
		swatch.pressed.connect(func() -> void: _color.color = tint; _apply())
	PalUi.button("恢复默认外观", self, func() -> void:
		_mode.select(1 if PalUi.is_mobile() else 0)
		_color.color = Color("2468b5") if PalUi.is_mobile() else Color("acc9e7")
		_apply())
	_opacity_caption = PalUi.label("浮层透明度 · 75%", self, 16)
	_opacity = HSlider.new()
	_opacity.min_value = 50
	_opacity.max_value = 90
	_opacity.step = 5
	add_child(_opacity)
	_opacity.value_changed.connect(func(_value: float) -> void: _apply_overlay())
	_dialogue = CheckButton.new()
	_dialogue.text = "显示对白气泡"
	add_child(_dialogue)
	_description = CheckButton.new()
	_description.text = "显示旁白气泡"
	add_child(_description)
	for toggle: CheckButton in [_dialogue, _description]:
		toggle.toggled.connect(func(_value: bool) -> void: _apply_overlay())
	PalUi.hint("应用于人物上的气泡和操作条。关闭气泡后，仍可在完整对话中阅读。", self)
	PalUi.label("对白播放方式", self, 16)
	_playback = OptionButton.new()
	_playback.add_item("点击继续")
	_playback.add_item("自动播放")
	add_child(_playback)
	_playback.item_selected.connect(func(_index: int) -> void: _apply_overlay())
	PalUi.hint("点击角色触控区以外的画面、气泡或右箭头继续，左箭头回看。自动播放按文字长度切换；开启朗读时，会等当前句读完。", self)
	_touch_regions = CheckButton.new()
	_touch_regions.text = "显示触控范围"
	add_child(_touch_regions)
	_touch_regions.toggled.connect(func(value: bool) -> void:
		if not _opening:
			touch_regions_requested.emit(value))
	PalUi.hint("用浅色透明圆圈标出头部、肩部与手边的触控区域。", self)
	_status = PalUi.hint("", self)
	open_current()


func open_current() -> void:
	_opening = true
	_mode.select(1 if PalUi.is_light() else 0)
	_color.color = PalUi.theme_color
	_opacity.value = roundf((1.0 - PalUi.overlay_opacity) * 100)
	_opacity_caption.text = "浮层透明度 · %d%%" % int(_opacity.value)
	_dialogue.set_pressed_no_signal(PalUi.dialogue_bubbles)
	_description.set_pressed_no_signal(PalUi.description_bubbles)
	_playback.select(1 if PalUi.dialogue_autoplay else 0)
	sync_touch_regions()
	_status.text = "外观设置会自动保存。"
	_opening = false


func sync_touch_regions() -> void:
	_touch_regions.set_pressed_no_signal(PalUi.show_touch_regions)


func _apply() -> void:
	if _opening:
		return
	_debounce.stop()
	appearance_requested.emit("light" if _mode.selected == 1 else "dark", _color.color)


func before_close() -> void:
	if not _debounce.is_stopped():
		_apply()


func _apply_overlay() -> void:
	if _opening or _description == null:
		return
	_opacity_caption.text = "浮层透明度 · %d%%" % int(_opacity.value)
	overlay_requested.emit(1.0 - _opacity.value / 100.0, _dialogue.button_pressed, _description.button_pressed, _playback.selected == 1)
