class_name PalRenderSettingsControls
extends RefCounted
signal changed
## Profile editor controls; changes join the existing save/discard transaction.

var _controls: Dictionary = {}
var _preset: OptionButton
var _bodies: Array[VBoxContainer] = []
var _notices: Array[Label] = []
var _loading := false


func build(lighting: VBoxContainer, quality: VBoxContainer) -> void:
	for parent: VBoxContainer in [lighting, quality]:
		_notices.append(PalUi.hint("这些设置用于 3D 角色，请先在「外观」中选择 3D。", parent))
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 12)
		parent.add_child(body)
		_bodies.append(body)
	var lights := _bodies[0]
	PalUi.hint("实时预览外观，保存后应用到伙伴。亮度设为 0 可关闭对应光源。" if PalUi.is_mobile() else "左侧实时预览，保存后应用到大厅与桌面。亮度设为 0 可关闭对应光源。", lights)
	_light(lights, "key", "主光")
	_light(lights, "fill", "补光")
	_color(lights, "ambient_color", "环境光")
	_slider(lights, "ambient_energy", "亮度", 0.05)
	PalUi.hint("环境光照亮背光面；主光与补光的水平、俯仰角度控制照射方向。", lights)
	PalUi.button("恢复默认光照", lights, _reset_lighting)
	var graphics := _bodies[1]
	PalUi.label("画质预设", graphics, 16)
	_preset = OptionButton.new()
	for caption: String in PalRenderSettings.PRESET_NAMES:
		_preset.add_item(caption)
	_preset.add_item("自定义")
	graphics.add_child(_preset)
	_preset.item_selected.connect(_select_preset)
	var advanced_toggle := CheckButton.new()
	advanced_toggle.text = "高级画质参数"
	graphics.add_child(advanced_toggle)
	var advanced := VBoxContainer.new()
	advanced.add_theme_constant_override("separation", 12)
	graphics.add_child(advanced)
	advanced.hide()
	advanced_toggle.toggled.connect(func(value: bool) -> void: advanced.visible = value)
	graphics = advanced
	PalUi.label("多重采样抗锯齿 · MSAA", graphics, 14)
	var msaa := OptionButton.new()
	for caption: String in ["关闭", "2×", "4×", "8×"]:
		msaa.add_item(caption)
	graphics.add_child(msaa)
	_controls.msaa = msaa
	msaa.item_selected.connect(func(_index: int) -> void: _update_preset())
	_toggle(graphics, "fxaa", "快速抗锯齿 · FXAA")
	PalUi.hint("MSAA 平滑模型轮廓；FXAA 还会柔化画面细节，可单独启用或叠加使用。", graphics)
	_slider(graphics, "render_scale", "渲染分辨率", 0.05, true)
	PalUi.hint("100% 为原始分辨率；降低可节省性能，提高可改善细节。只影响角色画面。", graphics)
	_toggle(graphics, "shadows", "主光阴影")
	_toggle(graphics, "debanding", "色带平滑")
	PalUi.hint("更高采样、分辨率和阴影会增加显卡负载，多位桌宠时可选「省电」或「均衡」。保存档案后生效。", graphics)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		(_controls.fxaa as CheckButton).disabled = true
		(_controls.debanding as CheckButton).disabled = true
		PalUi.hint("当前设备模式不支持 FXAA 和色带平滑，这两项暂不生效。", graphics)
	set_settings(PalRenderSettings.DEFAULTS)


func _light(parent: VBoxContainer, prefix: String, caption: String) -> void:
	_color(parent, prefix + "_color", caption)
	_slider(parent, prefix + "_energy", "亮度", 0.05)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	for axis: Array in [["yaw", "水平"], ["pitch", "俯仰"]]:
		PalUi.label(axis[1], row, 14)
		var field := SpinBox.new()
		var key := prefix + "_" + str(axis[0])
		var limits: Vector2 = PalRenderSettings.LIMITS[key]
		field.min_value = limits.x
		field.max_value = limits.y
		field.step = 1.0
		field.suffix = "°"
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(field)
		_controls[key] = field
		field.value_changed.connect(func(_value: float) -> void: _notify_changed())


func _color(parent: VBoxContainer, key: String, caption: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	PalUi.label(caption, row, 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picker := ColorPickerButton.new()
	picker.edit_alpha = false
	picker.custom_minimum_size = Vector2(100, 48 if PalUi.is_mobile() else 32)
	picker.tooltip_text = caption + "颜色"
	row.add_child(picker)
	_controls[key] = picker
	picker.color_changed.connect(func(_value: Color) -> void: _notify_changed())


func _slider(parent: VBoxContainer, key: String, caption: String, step: float, percentage: bool = false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	PalUi.label(caption, row, 14).custom_minimum_size.x = 72 if PalUi.is_mobile() else 100
	var slider := HSlider.new()
	var limits: Vector2 = PalRenderSettings.LIMITS[key]
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(72, 48) if PalUi.is_mobile() else Vector2(100, 32)
	row.add_child(slider)
	var number := PalUi.label("", row, 14)
	number.custom_minimum_size.x = 56
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var update_number := func(value: float) -> void:
		number.text = "%d%%" % roundi(value * 100) if percentage else "%.2f" % value
	slider.value_changed.connect(update_number)
	update_number.call(slider.value)
	if key in PalRenderSettings.QUALITY_KEYS:
		slider.value_changed.connect(func(_value: float) -> void: _update_preset())
	_controls[key] = slider
	slider.value_changed.connect(func(_value: float) -> void: _notify_changed())


func _toggle(parent: VBoxContainer, key: String, caption: String) -> void:
	var toggle := CheckButton.new()
	toggle.text = caption
	parent.add_child(toggle)
	toggle.toggled.connect(func(_pressed: bool) -> void: _update_preset())
	_controls[key] = toggle


func set_available(enabled: bool) -> void:
	for body: VBoxContainer in _bodies:
		body.visible = enabled
	for notice: Label in _notices:
		notice.visible = not enabled


func set_settings(value: Dictionary) -> void:
	_set_values(PalRenderSettings.normalize(value))


func _set_values(settings: Dictionary) -> void:
	_loading = true
	for key: String in settings:
		var control: Control = _controls[key]
		if control is ColorPickerButton:
			control.color = Color.html(settings[key])
		elif control is OptionButton:
			control.select(int(settings[key]))
		elif control is CheckButton:
			control.set_pressed_no_signal(bool(settings[key]))
		elif control is Range:
			control.value = float(settings[key])
	_loading = false
	_update_preset()


func get_settings() -> Dictionary:
	var settings := {}
	for key: String in _controls:
		var control: Control = _controls[key]
		if control is ColorPickerButton:
			settings[key] = "#" + control.color.to_html(false)
		elif control is OptionButton:
			settings[key] = control.selected
		elif control is CheckButton:
			settings[key] = control.button_pressed
		elif control is Range:
			settings[key] = control.value
	return PalRenderSettings.normalize(settings)


func _select_preset(index: int) -> void:
	if index < PalRenderSettings.PRESETS.size():
		_set_values(PalRenderSettings.PRESETS[index])


func _update_preset() -> void:
	_preset.select(PalRenderSettings.preset_index(get_settings()))
	_notify_changed()


func _notify_changed() -> void:
	if not _loading:
		changed.emit()


func _reset_lighting() -> void:
	var lights := PalRenderSettings.DEFAULTS.duplicate()
	for key: String in PalRenderSettings.QUALITY_KEYS:
		lights.erase(key)
	_set_values(lights)
