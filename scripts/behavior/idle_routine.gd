class_name PalIdleRoutine
extends Node
## Local-only daily actions. This node has no model or chat service dependency.

const COOLDOWNS := {"drink_water": 300.0, "eat_snack": 420.0, "read": 120.0, "work": 120.0, "yawn": 180.0, "sleepy": 180.0, "stretch": 240.0}
var pet: PalPetInstance
var performance: PalPerformanceQueue
var enabled := true
var active_on_host := false
var hanging := false
var chat_busy := false
var idle_seconds := 0.0
var _clock := 0.0
var _tick := 0.0
var _next_action := 0.0
var _active_action := ""
var _remaining := 0.0
var _last_action := ""
var _cooldowns: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	pet.behavior.manual_action.connect(func(_action: String) -> void: note_activity(false))
	pet.capabilities_changed.connect(note_activity)


func note_activity(stop_action := true) -> void:
	idle_seconds = 0.0
	if stop_action:
		_stop_action()
	else:
		_active_action = ""
		_remaining = 0.0


func set_chat_busy(value: bool) -> void:
	chat_busy = value
	if value:
		note_activity()


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	var step := _tick
	_tick = 0.0
	advance(step)


func advance(seconds: float) -> void:
	_clock += seconds
	if not enabled or not active_on_host or chat_busy or (performance != null and performance.is_playing()):
		_stop_action()
		return
	idle_seconds += seconds
	if not _active_action.is_empty():
		_remaining -= seconds
		if _remaining <= 0 or pet.behavior.current_action != _active_action:
			_stop_action()
		return
	if idle_seconds < (90.0 if hanging else 180.0) or _clock < _next_action or pet.behavior.current_action != "idle":
		return
	var available: PackedStringArray = pet.presenter.get_capabilities().get("actions", PackedStringArray())
	var choices: Array[String] = []
	for action: String in COOLDOWNS:
		if available.has(action) and _clock >= float(_cooldowns.get(action, 0.0)) and action != _last_action:
			choices.append(action)
	_next_action = _clock + _rng.randf_range(90.0, 180.0)
	if choices.is_empty():
		return
	var action := choices[_rng.randi_range(0, choices.size() - 1)]
	if pet.behavior.request_action(action, "ambient"):
		_active_action = action
		_last_action = action
		_remaining = _rng.randf_range(20.0, 40.0) if action in ["read", "work"] else 8.0
		_cooldowns[action] = _clock + float(COOLDOWNS[action])


func _stop_action() -> void:
	var action := _active_action
	_active_action = ""
	_remaining = 0.0
	if not action.is_empty() and pet.behavior.current_action == action and pet.behavior.current_origin == "ambient":
		pet.behavior.request_action("idle", "ambient")
