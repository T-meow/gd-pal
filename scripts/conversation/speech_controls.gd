class_name PalSpeechControls
extends VBoxContainer

signal changed
var service: Node
var _enabled: CheckButton
var _url: LineEdit
var _model: LineEdit
var _voice: LineEdit
var _key: LineEdit
var _remember: CheckButton
var _baseline := ""


func _ready() -> void:
	PalUi.hint("可选的 HTTP 语音服务；在通话页开启自动朗读，也可手动朗读回复。", self)
	_enabled = CheckButton.new()
	_enabled.text = "启用语音"
	add_child(_enabled)
	var fields := PalUi.card(self)
	_url = PalUi.field("语音 API 地址", fields, "例如 http://127.0.0.1:8000/v1")
	_model = PalUi.field("语音模型", fields)
	_voice = PalUi.field("音色", fields)
	_key = PalUi.field("API Key", fields, "留空保持已有 Key，本地服务可不填")
	_key.secret = true
	_remember = CheckButton.new()
	_remember.text = "在此设备记住 Key"
	fields.add_child(_remember)
	_enabled.toggled.connect(func(value: bool) -> void: fields.get_parent().visible = value; changed.emit())
	_remember.toggled.connect(func(_value: bool) -> void: changed.emit())
	for input: LineEdit in [_url, _model, _voice, _key]:
		input.text_changed.connect(func(_value: String) -> void: changed.emit())


func open_settings() -> void:
	var data: Dictionary = JSON.parse_string(service.call("GetSpeechSettings"))
	_enabled.button_pressed = bool(data.get("enabled", false))
	_url.text = str(data.get("base_url", "http://127.0.0.1:8000/v1"))
	_model.text = str(data.get("model", "tts-1"))
	_voice.text = str(data.get("voice", "alloy"))
	_remember.button_pressed = bool(data.get("remember_key", false))
	_key.clear()
	_url.get_parent().get_parent().visible = _enabled.button_pressed
	_baseline = JSON.stringify(_settings())


func _settings() -> Dictionary:
	return {"enabled": _enabled.button_pressed, "base_url": _url.text, "model": _model.text, "voice": _voice.text, "remember_key": _remember.button_pressed}


func is_dirty() -> bool:
	return JSON.stringify(_settings()) != _baseline or not _key.text.is_empty()


func save_settings() -> String:
	var error: String = service.call("SaveSpeechSettings", JSON.stringify(_settings()), _key.text)
	if error.is_empty():
		_key.clear()
		_baseline = JSON.stringify(_settings())
	return error


func clear_keys() -> void:
	_key.clear()
