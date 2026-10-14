class_name PalConnectionPanel
extends VBoxContainer

signal chat_requested
signal close_requested
var service: Node
var _provider: OptionButton
var _base_url: LineEdit
var _model: LineEdit
var _key: LineEdit
var _remember: CheckButton
var _reveal: CheckButton
var _reasoning: OptionButton
var _api_status: Label
var _test_button: Button
var _forget: Button
var _baseline := ""
var _generation := 0
var _pending_test: Dictionary = {}
var _endpoints: VBoxContainer
var _advanced: VBoxContainer
var _advanced_toggle: CheckButton
var _start: Button
var _tabs: TabContainer
var _speech: PalSpeechControls
var _opening := false
var _provider_presets: Array = []
var _provider_hint: Label
var _reasoning_hint: Label
var _format: OptionButton
var _message_limit: HBoxContainer
var _message_tokens: SpinBox
const EFFORT_NAMES := {"auto": "服务默认", "none": "关闭思考 · none", "minimal": "极低 · minimal", "low": "低 · low", "medium": "中 · medium", "high": "高 · high", "xhigh": "很高 · xhigh", "max": "最高 · max"}


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 1184)
	set_meta("preferred_height", 790)
	PalUi.hint("配置聊天模型与语音服务。", self)
	_tabs = TabContainer.new()
	_tabs.use_hidden_tabs_for_min_size = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	var chat := _tab("聊天模型")
	_build_chat(chat)
	var speech := _tab("语音服务")
	_speech = PalSpeechControls.new()
	_speech.service = service
	speech.add_child(_speech)
	_speech.changed.connect(_form_changed)
	add_child(HSeparator.new())
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	add_child(actions)
	_forget = PalUi.button("清除 Key", actions, _forget_key)
	PalUi.danger(_forget)
	_test_button = PalUi.button("保存并测试聊天连接", actions, _test_connection)
	_start = PalUi.button("开始聊天", actions, func() -> void: chat_requested.emit())
	PalUi.button("取消", actions, func() -> void: close_requested.emit())
	PalUi.button("保存设置", actions, _save_settings, true)
	_api_status = PalUi.hint("", self)
	_tabs.tab_changed.connect(func(_index: int) -> void: _sync_actions())
	service.connect("ConnectionTestFinished", _on_test_finished)
	service.connect("SettingsChanged", _refresh_connection_status)
	_sync_fields()
	_sync_actions()


func _tab(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_theme_stylebox_override("panel", PalUi.panel(PalUi.PAPER, 8, 18))
	_tabs.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	return column


func _build_chat(parent: VBoxContainer) -> void:
	PalUi.label("让伙伴听见你", parent, 22)
	PalUi.hint("使用自己的模型服务开始聊天。勾选记住 Key 后，会保存在本机，重启后无需重新输入。", parent)
	PalUi.label("模型服务", parent, 14)
	_provider = OptionButton.new()
	_provider_presets = JSON.parse_string(service.call("GetChatProviders"))
	for preset: Dictionary in _provider_presets:
		_provider.add_item(str(preset.name))
		_provider.set_item_metadata(_provider.item_count - 1, str(preset.id))
	parent.add_child(_provider)
	_provider.item_selected.connect(_on_provider_selected)
	_provider_hint = PalUi.hint("", parent)
	_endpoints = VBoxContainer.new()
	_endpoints.add_theme_constant_override("separation", 10)
	parent.add_child(_endpoints)
	_base_url = PalUi.field("API 地址", _endpoints, "服务地址或兼容服务的 /v1 地址")
	_model = PalUi.field("模型名称", _endpoints, "服务提供的模型 ID")
	var reasoning_row := HBoxContainer.new()
	parent.add_child(reasoning_row)
	PalUi.label("思考强度", reasoning_row, 16).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reasoning = OptionButton.new()
	_reasoning.custom_minimum_size.x = 170
	reasoning_row.add_child(_reasoning)
	_reasoning_hint = PalUi.hint("", parent)
	_key = PalUi.field("API Key", parent)
	_key.secret = true
	_key.max_length = 1280
	var preferences := HFlowContainer.new()
	parent.add_child(preferences)
	_remember = CheckButton.new()
	_remember.text = "在此设备记住 Key"
	_remember.tooltip_text = "保存在本机；未勾选时只在本次运行中使用。对话包不会携带 Key。"
	preferences.add_child(_remember)
	_reveal = CheckButton.new()
	_reveal.text = "显示 Key"
	preferences.add_child(_reveal)
	_reveal.toggled.connect(func(value: bool) -> void: _key.secret = not value)
	_advanced_toggle = CheckButton.new()
	_advanced_toggle.text = "高级连接设置"
	parent.add_child(_advanced_toggle)
	_advanced = VBoxContainer.new()
	parent.add_child(_advanced)
	_advanced_toggle.toggled.connect(func(_value: bool) -> void: _sync_fields())
	PalUi.label("API 格式", _advanced, 14)
	_format = OptionButton.new()
	for item: Array in [["自动选择", "auto"], ["OpenAI Chat Completions", "chat_completions"], ["OpenAI Responses", "responses"], ["Anthropic Messages", "anthropic"], ["Google Gemini", "gemini"]]:
		_format.add_item(str(item[0]))
		_format.set_item_metadata(_format.item_count - 1, str(item[1]))
	_advanced.add_child(_format)
	_format.item_selected.connect(func(_index: int) -> void: _refresh_model_options(); _form_changed())
	_message_limit = HBoxContainer.new()
	_advanced.add_child(_message_limit)
	PalUi.label("Messages 输出额度（tokens）", _message_limit, 14).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_tokens = SpinBox.new()
	_message_tokens.min_value = 2048
	_message_tokens.max_value = 262144
	_message_tokens.step = 1024
	_message_tokens.value = 32768
	_message_tokens.tooltip_text = "Messages 接口必填，额度包含思考与正文；其他格式使用服务默认额度。"
	_message_limit.add_child(_message_tokens)
	_message_tokens.value_changed.connect(func(_value: float) -> void: _form_changed())
	PalUi.hint("自动选择会根据提供商、模型和地址匹配接口；第三方网关也可手动指定。", _advanced)
	PalUi.hint("连接测试会发送一条简短请求，使用少量账户额度。对话会先保存到本地，再发送到所选服务。", parent)
	for field: LineEdit in [_base_url, _model]:
		field.text_changed.connect(_on_connection_field_changed)
	_key.text_changed.connect(func(_text: String) -> void: _form_changed())
	_reasoning.item_selected.connect(func(_index: int) -> void: _form_changed())
	_remember.toggled.connect(func(_value: bool) -> void: _form_changed())
	_refresh_model_options("high")


func _option_value(option: OptionButton, fallback: String) -> String:
	return str(option.get_selected_metadata()) if option != null and option.selected >= 0 else fallback


func _select_value(option: OptionButton, value: String) -> void:
	for index: int in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
	option.select(0)


func _on_provider_selected(index: int) -> void:
	var preset: Dictionary = _provider_presets[index]
	_opening = true
	_base_url.text = str(preset.base_url)
	_model.text = str(preset.model)
	_select_value(_format, "auto")
	_key.clear()
	_key.placeholder_text = "输入此服务对应的 API Key"
	_opening = false
	_refresh_model_options("high" if preset.id == "deepseek" else "auto")
	_sync_fields()
	_form_changed()


func _on_connection_field_changed(_text: String) -> void:
	if not _opening:
		_refresh_model_options()
		_form_changed()


func _refresh_model_options(preferred: String = "") -> void:
	var previous := preferred if not preferred.is_empty() else _option_value(_reasoning, "auto")
	var options: Dictionary = JSON.parse_string(service.call("GetChatOptions", JSON.stringify(_settings())))
	_reasoning.clear()
	for effort: String in options.get("efforts", ["auto"]):
		_reasoning.add_item(str(EFFORT_NAMES.get(effort, effort)))
		_reasoning.set_item_metadata(_reasoning.item_count - 1, effort)
	if not preferred.is_empty() and previous not in options.get("efforts", []):
		_reasoning.add_item("当前设置 · " + previous)
		_reasoning.set_item_metadata(_reasoning.item_count - 1, previous)
	_select_value(_reasoning, previous)
	_reasoning_hint.text = str(options.get("note", ""))
	_message_limit.visible = bool(options.get("needs_output_limit", false))
	_provider_hint.text = str(_provider_presets[_provider.selected].hint) if _provider.selected >= 0 else ""


func open_settings(_profile_id: String = "") -> void:
	_opening = true
	_generation += 1
	_pending_test.clear()
	var data: Dictionary = JSON.parse_string(service.call("GetSettings"))
	var settings: Dictionary = data.settings
	_speech.open_settings()
	_select_value(_provider, str(settings.provider))
	_base_url.text = str(settings.base_url)
	_model.text = str(settings.model)
	_select_value(_format, str(settings.get("api_format", "auto")))
	_message_tokens.value = int(settings.get("message_max_tokens", 32768))
	_refresh_model_options(str(settings.get("reasoning_effort", "high")))
	_remember.set_pressed_no_signal(bool(settings.remember_key))
	_key.clear()
	_key.secret = true
	_reveal.set_pressed_no_signal(false)
	_key.placeholder_text = "已有 Key，留空保持不变" if data.has_key else "输入你的 API Key"
	_baseline = _signature()
	_advanced_toggle.set_pressed_no_signal(_option_value(_format, "auto") != "auto")
	_opening = false
	_sync_fields()
	_refresh_connection_status()


func _settings() -> Dictionary:
	return {"provider": _option_value(_provider, "openai"), "base_url": _base_url.text, "model": _model.text,
		"reasoning_effort": _option_value(_reasoning, "auto"), "api_format": _option_value(_format, "auto"),
		"message_max_tokens": int(_message_tokens.value), "remember_key": _remember.button_pressed}


func _signature() -> String:
	return JSON.stringify(_settings())


func is_dirty() -> bool:
	return not _key.text.is_empty() or _signature() != _baseline or (_speech != null and _speech.is_dirty())


func before_close() -> void:
	_opening = true
	_generation += 1
	_pending_test.clear()
	service.call("CancelConnectionTest")
	_key.clear()
	_key.secret = true
	_reveal.set_pressed_no_signal(false)
	_speech.clear_keys()
	_opening = false


func _save_settings() -> bool:
	_pending_test.clear()
	service.call("CancelConnectionTest")
	var error := ""
	if not _key.text.is_empty() or _signature() != _baseline:
		error = str(service.call("SaveSettings", JSON.stringify(_settings()), _key.text))
		if error.is_empty():
			_key.clear()
			_key.placeholder_text = "已有 Key，留空保持不变"
			_baseline = _signature()
	if error.is_empty() and _speech.is_dirty():
		error = _speech.save_settings()
	_api_status.text = "设置已保存。" if error.is_empty() else error
	_api_status.add_theme_color_override("font_color", PalUi.ACCENT if error.is_empty() else PalUi.ERROR)
	_sync_actions()
	return error.is_empty()


func _test_connection() -> void:
	if not _save_settings():
		return
	var error: String = service.call("TestConnection")
	_api_status.text = "正在测试聊天连接…" if error.is_empty() else error
	_test_button.disabled = error.is_empty()
	if error.is_empty():
		_pending_test = {"generation": _generation, "signature": _signature()}


func _on_test_finished(result: String) -> void:
	var pending := _pending_test
	_pending_test = {}
	if pending.is_empty() or not is_visible_in_tree() or pending.generation != _generation:
		return
	if pending.signature != _signature() or not _key.text.is_empty():
		_api_status.text = "聊天设置已变化，请保存后重新测试。"
	else:
		_api_status.text = result
	_sync_actions()


func _forget_key() -> void:
	_pending_test.clear()
	service.call("CancelConnectionTest")
	var error: String = service.call("ForgetKey")
	if error.is_empty():
		_key.clear()
		_key.placeholder_text = "输入你的 API Key"
		_remember.set_pressed_no_signal(false)
		var baseline: Dictionary = JSON.parse_string(_baseline)
		baseline["remember_key"] = false
		_baseline = JSON.stringify(baseline)
	_api_status.text = "已清除聊天服务 Key。" if error.is_empty() else error
	_sync_actions()


func _sync_fields() -> void:
	_endpoints.show()
	_advanced.visible = _advanced_toggle.button_pressed


func _sync_actions() -> void:
	if _start == null:
		return
	var data: Dictionary = JSON.parse_string(service.call("GetSettings"))
	_test_button.visible = _tabs.current_tab == 0
	_test_button.disabled = bool(data.get("testing", false))
	_start.visible = _tabs.current_tab == 0 and bool(data.get("has_key", false))
	_start.disabled = is_dirty() or bool(data.get("testing", false))
	_forget.visible = _tabs.current_tab == 0
	_forget.text = "清除聊天 Key"


func _form_changed() -> void:
	if _opening or _start == null:
		return
	_sync_actions()
	if is_dirty():
		_api_status.text = "有未保存的更改，保存后生效。"
		_api_status.add_theme_color_override("font_color", PalUi.MUTED)


func _refresh_connection_status() -> void:
	if _start == null or _opening or not is_visible_in_tree():
		return
	_sync_actions()
	if is_dirty():
		_form_changed()
		return
	var data: Dictionary = JSON.parse_string(service.call("GetSettings"))
	var state := str(data.get("connection_state", "unconfigured"))
	var captions := {"unconfigured": "请填写聊天模型和 API Key。", "configured": "聊天连接已配置。", "testing": "正在测试聊天连接…", "verified": "聊天连接测试成功。", "failed": "聊天连接测试失败 · " + str(data.get("last_test_message", "请检查设置。"))}
	_api_status.text = str(data.get("notice", "")) if not str(data.get("notice", "")).is_empty() else str(captions.get(state, "设置已保存。"))
	_api_status.add_theme_color_override("font_color", PalUi.ERROR if state == "failed" else PalUi.MUTED)
