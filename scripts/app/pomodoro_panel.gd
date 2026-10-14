class_name PalPomodoroPanel
extends PanelContainer

signal settings_changed(settings: Dictionary)
signal running_changed(running: bool)
signal status_changed(text: String)
signal idle_actions_changed(enabled: bool)
var running := false
var phase := "focus"
var completed := 0
var remaining := 25 * 60
var _deadline := 0
var _elapsed := 0.0
var _focus_minutes: SpinBox
var _rest_minutes: SpinBox
var _automatic: CheckButton
var _idle_actions: CheckButton
var _clock_label: Label
var _phase_label: Label
var _rounds: Label
var _start: Button
var _opening := false


func _ready() -> void:
	add_theme_stylebox_override("panel", PalUi.panel(PalUi.SURFACE, 16, 16))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	PalUi.label("番茄钟 · 专注陪伴", header, 17).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PalUi.compact_button("×", header, hide).tooltip_text = "收起面板，计时继续"
	_phase_label = PalUi.label("准备专注", column, 13, true)
	_clock_label = PalUi.label("25:00", column, 36)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var durations := HBoxContainer.new()
	durations.add_theme_constant_override("separation", 12)
	column.add_child(durations)
	_focus_minutes = _duration("专注（分钟）", 25, durations, 120)
	_rest_minutes = _duration("休息（分钟）", 5, durations, 60)
	_automatic = CheckButton.new()
	_automatic.text = "自动继续专注与休息"
	_automatic.button_pressed = true
	column.add_child(_automatic)
	_idle_actions = CheckButton.new()
	_idle_actions.text = "允许待机小动作"
	_idle_actions.button_pressed = true
	column.add_child(_idle_actions)
	_idle_actions.toggled.connect(func(value: bool) -> void: idle_actions_changed.emit(value))
	_automatic.toggled.connect(func(_value: bool) -> void: _save_settings())
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_start = PalUi.button("开始挂机", actions, toggle_running, true)
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PalUi.button("重置", actions, reset)
	_rounds = PalUi.label("已完成 0 轮专注", column, 12, true)
	PalUi.hint("挂机时可以继续闲聊。角色的小动作由本地计时触发，不请求模型。", column)
	hide()


func _duration(caption: String, initial: int, parent: Node, maximum: int) -> SpinBox:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	PalUi.label(caption, column, 12, true)
	var number := SpinBox.new()
	number.min_value = 1
	number.max_value = maximum
	number.value = initial
	column.add_child(number)
	number.value_changed.connect(func(_value: float) -> void:
		if not running:
			remaining = _phase_seconds()
			_refresh()
		_save_settings())
	return number


func configure(settings: Dictionary, idle_enabled: bool) -> void:
	_opening = true
	_focus_minutes.value = clampi(int(settings.get("focus_minutes", 25)), 1, 120)
	_rest_minutes.value = clampi(int(settings.get("rest_minutes", 5)), 1, 60)
	_automatic.set_pressed_no_signal(bool(settings.get("automatic", true)))
	_idle_actions.set_pressed_no_signal(idle_enabled)
	remaining = _phase_seconds()
	_opening = false
	_refresh()


func toggle_running() -> void:
	if running:
		_update_clock()
		running = false
	else:
		running = true
		_deadline = Time.get_ticks_msec() + maxi(1, remaining) * 1000
	running_changed.emit(running)
	_refresh()


func reset() -> void:
	running = false
	phase = "focus"
	remaining = _phase_seconds()
	running_changed.emit(false)
	_refresh()


func _phase_seconds() -> int:
	return int(_focus_minutes.value if phase == "focus" else _rest_minutes.value) * 60


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	if running:
		_update_clock()


func _update_clock() -> void:
	remaining = maxi(0, ceili((_deadline - Time.get_ticks_msec()) / 1000.0))
	if remaining == 0:
		if phase == "focus":
			completed += 1
		phase = "rest" if phase == "focus" else "focus"
		remaining = _phase_seconds()
		running = _automatic.button_pressed
		_deadline = Time.get_ticks_msec() + remaining * 1000
		running_changed.emit(running)
	_refresh()


func _refresh() -> void:
	if _clock_label == null:
		return
	var label := "专注" if phase == "focus" else "休息"
	var clock := "%02d:%02d" % [remaining / 60, remaining % 60]
	_clock_label.text = clock
	_phase_label.text = label + ("中 · 可以继续聊天" if running else "已暂停")
	_start.text = "暂停" if running else "开始 / 继续"
	_rounds.text = "已完成 %d 轮专注" % completed
	status_changed.emit(label + " " + clock if running else "番茄钟")


func _save_settings() -> void:
	if not _opening and _focus_minutes != null and _rest_minutes != null and _automatic != null:
		settings_changed.emit({"focus_minutes": int(_focus_minutes.value), "rest_minutes": int(_rest_minutes.value), "automatic": _automatic.button_pressed})
