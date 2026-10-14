class_name PalProfilePanel
extends VBoxContainer

signal save_requested(profile_id: String, data: Dictionary)
signal remove_requested(profile_id: String)
signal close_requested
signal summary_requested(profile_id: String)
signal import_requested(profile_id: String)

var _profile_id := ""
var _name: LineEdit
var _visual: OptionButton
var _avatar: LineEdit
var _avatar_row: VBoxContainer
var _persona: TextEdit
var _adult_mode: CheckButton
var _persona_preset: OptionButton
var _persona_description: Label
var _hidden_persona := ""
var _changing_persona := false
var _original_persona := ""
var _submitted_persona := ""
var _persona_file: Button
var _persona_reload: Button
var _look: CheckButton
var _wander: CheckButton
var _scale: HSlider
var _scale_text: Label
var _credit: Label
var _status: Label
var _save: Button
var _remove: Button
var _file: FileDialog
var _baseline := ""
var _submitted_signature := ""
var _generation := 0
var _browse_generation := 0
var _render_controls := PalRenderSettingsControls.new()
var _preview_surface: SubViewportContainer
var _preview: PalPetInstance
var _preview_source: PalProfile
var _preview_caption: Label
var _preview_queued := false
var _opening := false
var _attempted_visual := ""
var _body_layout: BoxContainer
var _preview_card: PanelContainer
var _form_scroll: ScrollContainer
var service: Node
var _summary: Button
var _restore_persona: Button
var _tabs: TabContainer
var _export: Button
var _include_world: CheckBox
var _include_memory: CheckBox


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 1184)
	set_meta("preferred_height", 790)
	var body := BoxContainer.new()
	_body_layout = body
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var preview_card := PanelContainer.new()
	_preview_card = preview_card
	preview_card.custom_minimum_size.x = 260
	preview_card.add_theme_stylebox_override("panel", PalUi.panel(PalUi.BLUE, 12, 12))
	body.add_child(preview_card)
	var preview_column := VBoxContainer.new()
	preview_card.add_child(preview_column)
	PalUi.label("外观预览", preview_column, 18)
	_preview_surface = SubViewportContainer.new()
	_preview_surface.stretch = true
	_preview_surface.custom_minimum_size = Vector2(230, 240)
	_preview_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(_preview_surface)
	_preview_caption = PalUi.hint("调整只作用于预览，保存后生效。", preview_column)
	var scroll := ScrollContainer.new()
	_form_scroll = scroll
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 260
	body.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 12)
	scroll.add_child(form)
	_name = PalUi.field("伙伴的名字", form, "给这段陪伴一个名字")
	_name.max_length = 40
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.use_hidden_tabs_for_min_size = false
	form.add_child(tabs)
	var appearance := _tab("外观", tabs)
	PalUi.label("表现形式", appearance, 14)
	_visual = OptionButton.new()
	_visual.add_item("2D · 静态立绘（默认）")
	if not PalUi.is_mobile():
		_visual.add_item("3D · VRM 角色")
	appearance.add_child(_visual)
	_visual.item_selected.connect(_on_visual_selected)
	_avatar_row = VBoxContainer.new()
	_avatar_row.add_theme_constant_override("separation", 10)
	appearance.add_child(_avatar_row)
	_avatar = PalUi.field("VRM 文件", _avatar_row)
	_avatar.editable = false
	PalUi.icon_button("选择 VRM 文件", "profile", _avatar_row, func() -> void:
		_browse_generation = _generation
		_file.popup_centered_ratio(0.75)
	)
	_credit = PalUi.hint("", appearance)
	PalUi.hint("保存时应用外观。模型加载失败会保留原伙伴，聊天和记忆继续关联同一个身份。", appearance)
	var lighting := _tab("光照", tabs)
	var quality := _tab("画质", tabs)
	_render_controls.build(lighting, quality)
	if PalUi.is_mobile():
		tabs.set_tab_hidden(1, true)
		tabs.set_tab_hidden(2, true)
	_render_controls.changed.connect(_queue_preview)
	_avatar.text_changed.connect(func(_text: String) -> void: _queue_preview())
	var personality := _tab("人设", tabs)
	_adult_mode = CheckButton.new()
	_adult_mode.text = "成人模式"
	personality.add_child(_adult_mode)
	PalUi.hint("开启后显示亲密动作和第二个人设，并切换触碰区域。仅对此角色生效，保存伙伴档案后应用。", personality)
	_adult_mode.toggled.connect(func(_enabled: bool) -> void:
		if not _opening:
			refresh_persona_presets()
			_queue_preview())
	PalUi.label("内置人设", personality, 18)
	_persona_preset = OptionButton.new()
	_persona_preset.allow_reselect = true
	personality.add_child(_persona_preset)
	_persona_preset.item_selected.connect(_on_persona_selected)
	_persona_description = PalUi.hint("", personality)
	PalUi.hint("选择内置人设后可在下方调整，最多 4000 字。保存后从下一次回复生效。", personality)
	_persona = TextEdit.new()
	_persona.custom_minimum_size.y = 210
	_persona.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_persona.placeholder_text = "例如：温柔、好奇，喜欢听我分享日常……"
	personality.add_child(_persona)
	_persona.text_changed.connect(_on_persona_edited)
	var persona_actions := HFlowContainer.new()
	personality.add_child(persona_actions)
	_summary = PalUi.button("AI 整理", persona_actions, func() -> void: summary_requested.emit(_profile_id))
	_restore_persona = PalUi.button("还原人设", persona_actions, restore_persona)
	_restore_persona.tooltip_text = "还原到 AI 追加前的手写人设，保存后生效。"
	_persona_file = PalUi.button("打开人设文件", persona_actions, _open_persona_file)
	_persona_file.visible = not PalUi.is_mobile()
	_persona_reload = PalUi.button("从文件重新载入", persona_actions, _reload_persona_file)
	_persona_reload.tooltip_text = "读取最新的人设文件，替换编辑框中尚未保存的人设。"
	var behavior := _tab("桌面行为", tabs)
	if PalUi.is_mobile():
		tabs.set_tab_hidden(tabs.get_tab_count() - 1, true)
	_look = CheckButton.new()
	_look.text = "看向鼠标"
	behavior.add_child(_look)
	_wander = CheckButton.new()
	_wander.text = "沿桌面底边散步"
	behavior.add_child(_wander)
	_scale_text = PalUi.label("桌面大小 · 100%", behavior, 14)
	_scale = HSlider.new()
	_scale.min_value = 0.65
	_scale.max_value = 1.5
	_scale.step = 0.05
	_scale.custom_minimum_size.y = 32
	behavior.add_child(_scale)
	_scale.value_changed.connect(func(value: float) -> void: _scale_text.text = "桌面大小 · %d%%" % roundi(value * 100))
	PalUi.hint("桌面上也可以用滚轮缩放、拖动角色换位置。", behavior)
	var packages := _tab("导入导出", tabs)
	PalUi.hint("导出当前编辑的名字和人设。世界设定与记忆来自已保存内容。", packages)
	_include_world = CheckBox.new()
	_include_world.text = "包含世界设定"
	_include_world.button_pressed = true
	packages.add_child(_include_world)
	_include_memory = CheckBox.new()
	_include_memory.text = "包含长期与活跃记忆"
	packages.add_child(_include_memory)
	_export = PalUi.button("导出人设包", packages, _export_persona)
	PalUi.button("导入数据包", packages, func() -> void: import_requested.emit(_profile_id))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	add_child(actions)
	_remove = PalUi.button("移除伙伴", actions, func() -> void: remove_requested.emit(_profile_id))
	PalUi.danger(_remove)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	PalUi.button("取消", actions, func() -> void: close_requested.emit())
	_save = PalUi.button("保存伙伴档案", actions, _submit, true)
	_status = PalUi.hint("", self)
	_file = FileDialog.new()
	_file.title = "选择 VRM 角色"
	_file.access = FileDialog.ACCESS_FILESYSTEM
	_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file.filters = PackedStringArray(["*.vrm ; VRM 角色"])
	_file.use_native_dialog = true
	_file.file_selected.connect(func(path: String) -> void:
		if _browse_generation == _generation:
			if PalUi.is_mobile():
				var imported := PalMobileFiles.import_avatar(path)
				if imported.has("error"):
					_status.text = str(imported.error)
					return
				path = str(imported.path)
			_avatar.text = path
			_queue_preview()
	)
	add_child(_file)
	if PalUi.is_mobile():
		_file.filters = PackedStringArray(["*.vrm ; VRM 角色 ; application/octet-stream,model/gltf-binary"])
		resized.connect(_mobile_layout)
		_mobile_layout()


func _mobile_layout() -> void:
	if _body_layout == null:
		return
	var portrait := size.x < 600
	_body_layout.vertical = portrait
	_preview_card.custom_minimum_size.x = 0 if portrait else 200
	_preview_surface.custom_minimum_size = Vector2(160, 130 if portrait else 100)
	_preview_card.visible = PalUi.keyboard_height() == 0
	_form_scroll.custom_minimum_size.y = 100
	_form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_persona.custom_minimum_size.y = 150


func _process(_delta: float) -> void:
	if PalUi.is_mobile() and is_visible_in_tree():
		_mobile_layout()
		if is_instance_valid(_preview):
			_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _preview_card.visible and Engine.max_fps > 5 else SubViewport.UPDATE_DISABLED


func _tab(caption: String, tabs: TabContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = caption
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	tabs.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	return column


func open_profile(profile: PalProfile, author: String = "") -> void:
	_release_preview()
	_opening = true
	_preview_source = profile.duplicate(true) as PalProfile
	_generation += 1
	_profile_id = profile.profile_id
	_name.text = profile.display_name
	_visual.select(1 if profile.visual_id == "vrm3d" and not PalUi.is_mobile() else 0)
	_avatar.text = profile.avatar_path
	_avatar_row.visible = _visual.selected == 1
	_render_controls.set_settings(profile.render_settings)
	_render_controls.set_available(_visual.selected == 1)
	_hidden_persona = ""
	_persona.text = profile.persona
	_adult_mode.set_pressed_no_signal(profile.adult_mode)
	var file_error := ""
	if not _profile_id.is_empty():
		var role: Dictionary = JSON.parse_string(service.call("GetRole", _profile_id))
		_persona.text = str(role.get("profile", {}).get("persona", profile.persona))
		_adult_mode.set_pressed_no_signal(bool(role.get("profile", {}).get("adult_mode", profile.adult_mode)))
		file_error = str(role.get("file_error", ""))
	_persona.editable = file_error.is_empty()
	refresh_persona_presets()
	_look.set_pressed_no_signal(profile.look_at_mouse)
	_wander.set_pressed_no_signal(profile.wander)
	_scale.value = profile.desktop_scale
	_credit.text = "内置 2D 角色包：蓝色肥鱼 · 24 张全身 / 24 张通话近景" if _visual.selected == 0 else ("模型作者：" + author if not author.is_empty() else "内置角色或你选择的 VRM 外观")
	_look.disabled = _visual.selected == 0
	_wander.disabled = _visual.selected == 0
	_look.tooltip_text = "静态立绘保持固定视线" if _visual.selected == 0 else ""
	_wander.tooltip_text = "静态行走姿势可从互动菜单选择，2D 尚未启用自动散步" if _visual.selected == 0 else ""
	_remove.visible = not _profile_id.is_empty()
	_summary.disabled = _profile_id.is_empty()
	_persona_file.disabled = _profile_id.is_empty()
	_persona_reload.disabled = _profile_id.is_empty()
	_sync_persona_restore()
	_export.disabled = _profile_id.is_empty()
	_save.text = "添加伙伴" if _profile_id.is_empty() else "保存伙伴档案"
	_save.disabled = false
	_status.text = "设定文件读取失败：" + file_error if not file_error.is_empty() else ""
	_original_persona = str(_data().persona)
	_baseline = JSON.stringify(_data())
	_submitted_signature = ""
	_opening = false
	_queue_preview()


func _data() -> Dictionary:
	var persona := (_persona.text if _hidden_persona.is_empty() else _hidden_persona).strip_edges()
	return {"name": _name.text.strip_edges(), "visual": "vrm3d" if _visual.selected == 1 else "sprite2d", "avatar": _avatar.text,
		"persona": persona, "adult_mode": _adult_mode.button_pressed,
		"look_at_mouse": _look.button_pressed, "wander": _wander.button_pressed, "scale": _scale.value,
		"render_settings": _render_controls.get_settings()}


func refresh_persona_presets() -> void:
	var text := _persona.text if _hidden_persona.is_empty() else _hidden_persona
	_hidden_persona = ""
	_persona_preset.clear()
	for index: int in PalProfile.PERSONA_PRESETS.size():
		var preset: Dictionary = PalProfile.PERSONA_PRESETS[index]
		if bool(preset.get("adult_only", false)) and not _adult_mode.button_pressed:
			continue
		_persona_preset.add_item(str(preset.name))
		_persona_preset.set_item_metadata(_persona_preset.item_count - 1, index)
	if not _adult_mode.button_pressed and text.strip_edges() == PalProfile.ANDROID_PERSONA:
		# Keep the saved choice while the regular mode uses the first preset.
		_hidden_persona = text
		text = PalProfile.DEFAULT_PERSONA
	_changing_persona = true
	_persona.text = text
	_changing_persona = false
	_sync_persona_preset()


func _sync_persona_preset() -> void:
	_persona_preset.select(-1)
	_persona_description.text = "使用下方编辑的人设。"
	for index: int in _persona_preset.item_count:
		var preset: Dictionary = PalProfile.PERSONA_PRESETS[int(_persona_preset.get_item_metadata(index))]
		if _persona.text.strip_edges() == str(preset.persona):
			_persona_preset.select(index)
			_persona_description.text = str(preset.description)
			return


func _on_persona_selected(index: int) -> void:
	var preset: Dictionary = PalProfile.PERSONA_PRESETS[int(_persona_preset.get_item_metadata(index))]
	_hidden_persona = ""
	_changing_persona = true
	_persona.text = str(preset.persona)
	_changing_persona = false
	_sync_persona_preset()
	_status.text = "已选择「%s」，保存后从下一次回复生效。" % str(preset.name)


func _on_persona_edited() -> void:
	if _opening or _changing_persona:
		return
	_hidden_persona = ""
	_sync_persona_preset()


func _sync_persona_restore() -> void:
	var data: Dictionary = JSON.parse_string(service.call("GetPersonaRestore", _profile_id)) if not _profile_id.is_empty() else {}
	_restore_persona.disabled = not bool(data.get("available", false))


func _open_persona_file() -> void:
	var data: Dictionary = JSON.parse_string(service.call("GetManualContext", _profile_id))
	var path := str(data.get("paths", {}).get("persona", ""))
	if path.is_empty() or OS.shell_open(path) != OK:
		_status.text = "未能打开人设文件：" + path


func _reload_persona_file() -> void:
	var data: Dictionary = JSON.parse_string(service.call("GetRole", _profile_id))
	if not str(data.get("file_error", "")).is_empty():
		_status.text = "人设文件读取失败：" + str(data.file_error)
		return
	_hidden_persona = ""
	_changing_persona = true
	_persona.text = str(data.get("profile", {}).get("persona", ""))
	_persona.editable = true
	_changing_persona = false
	refresh_persona_presets()
	_original_persona = str(_data().persona)
	var baseline: Dictionary = JSON.parse_string(_baseline)
	baseline["persona"] = _original_persona
	_baseline = JSON.stringify(baseline)
	_sync_persona_restore()
	_status.text = "已读取文件中的最新人设。"


func restore_persona() -> void:
	var data: Dictionary = JSON.parse_string(service.call("GetPersonaRestore", _profile_id))
	if not bool(data.get("available", false)):
		_status.text = str(data.get("error", "当前没有需要还原的 AI 人设追加。"))
		return
	_hidden_persona = ""
	_changing_persona = true
	_persona.text = str(data.persona)
	_changing_persona = false
	refresh_persona_presets()
	for index: int in _tabs.get_tab_count():
		if _tabs.get_tab_title(index) == "人设":
			_tabs.current_tab = index
	_status.text = "已放回 AI 追加前的手写人设，保存伙伴档案后生效。"
	_restore_persona.disabled = true


func _on_visual_selected(index: int) -> void:
	_avatar_row.visible = index == 1
	_render_controls.set_available(index == 1)
	_look.disabled = index == 0
	_wander.disabled = index == 0
	_look.tooltip_text = "静态立绘保持固定视线" if index == 0 else ""
	_wander.tooltip_text = "静态行走姿势可从互动菜单选择，2D 尚未启用自动散步" if index == 0 else ""
	_credit.text = "内置 2D 角色包：蓝色肥鱼 · 24 张全身 / 24 张通话近景" if index == 0 else "内置角色或你选择的 VRM 外观"
	_queue_preview()


func _queue_preview() -> void:
	if _opening or _preview_queued or _preview_source == null or not is_visible_in_tree():
		return
	_preview_queued = true
	_sync_preview.call_deferred()


func _sync_preview() -> void:
	_preview_queued = false
	if not is_visible_in_tree() or _preview_source == null:
		return
	if not is_instance_valid(_preview):
		_preview = preload("res://scenes/characters/pet_instance.tscn").instantiate() as PalPetInstance
		_preview.profile = _preview_source.duplicate(true) as PalProfile
		_preview.profile.profile_id = ""
		_preview_surface.add_child(_preview)
		_preview.set_presentation_mode("full_body")
		_attempted_visual = ""
	var data := _data()
	var signature := JSON.stringify([data.visual, data.avatar])
	if _preview.profile.adult_mode != bool(data.adult_mode):
		_preview.set_adult_mode(bool(data.adult_mode))
	if signature != _attempted_visual:
		_attempted_visual = signature
		if _preview.presenter == null or _preview.profile.visual_id != data.visual or _preview.profile.avatar_path != data.avatar:
			var proposed := _preview.profile.duplicate(true) as PalProfile
			proposed.visual_id = str(data.visual)
			proposed.avatar_path = str(data.avatar)
			var candidate := (PalPetInstance.PRESENTERS[str(data.visual)] as PackedScene).instantiate() as PalPresenter
			var error := candidate.prepare(proposed)
			if not error.is_empty():
				candidate.free()
				_preview_caption.text = "新外观预览失败，保留上一份预览。\n" + error
				_preview_caption.add_theme_color_override("font_color", PalUi.ERROR)
			else:
				_preview.profile = proposed
				_preview.install_presenter(candidate, str(data.visual), str(data.avatar))
				_preview_caption.text = "调整只作用于预览，保存后生效。"
				_preview_caption.add_theme_color_override("font_color", PalUi.MUTED)
		else:
			_preview_caption.text = "调整只作用于预览，保存后生效。"
			_preview_caption.add_theme_color_override("font_color", PalUi.MUTED)
	_preview.profile.render_settings = data.render_settings.duplicate(true)
	_preview.apply_render_settings()


func _release_preview() -> void:
	if is_instance_valid(_preview):
		_preview_surface.remove_child(_preview)
		_preview.queue_free()
	_preview = null
	_preview_source = null
	_attempted_visual = ""
	_preview_queued = false


func is_dirty() -> bool:
	return JSON.stringify(_data()) != _baseline


func _submit() -> void:
	var data := _data()
	if str(data.name).is_empty() or str(data.name).length() > 40:
		_status.text = "名字需要 1～40 字。"
		return
	if _persona.text.length() > 4000:
		_status.text = "人设最多 4000 字，请缩短后保存。"
		return
	_save.disabled = true
	_submitted_signature = JSON.stringify(data)
	_submitted_persona = str(data.persona)
	data["update_persona"] = _submitted_persona != _original_persona
	data["persona_baseline"] = _original_persona
	_status.text = "正在保存，准备角色外观…"
	save_requested.emit(_profile_id, data)


func complete(error: String = "") -> void:
	_save.disabled = false
	_status.text = "档案已保存。" if error.is_empty() else error
	_status.add_theme_color_override("font_color", PalUi.ACCENT if error.is_empty() else PalUi.ERROR)
	if error.is_empty():
		_baseline = _submitted_signature if not _submitted_signature.is_empty() else JSON.stringify(_data())
		_original_persona = _submitted_persona
		_sync_persona_restore()
		if is_dirty():
			_status.text = "档案已保存，后续编辑尚未保存。"


func mark_created(profile_id: String) -> void:
	_profile_id = profile_id
	_summary.disabled = false
	_persona_file.disabled = false
	_persona_reload.disabled = false
	_export.disabled = false
	_remove.show()
	_save.text = "保存档案"


func _export_persona() -> void:
	var generation := _generation
	_export.disabled = true
	_status.text = "正在打包…"
	PalPackageFiles.export_package(self, service, _profile_id, "persona", "", _data(), _include_memory.button_pressed, _include_world.button_pressed, func(message: String) -> void:
		if generation == _generation:
			_export.disabled = false
			_status.text = message)


func before_close() -> void:
	_generation += 1
	_file.hide()
	_release_preview()
