class_name PalBehavior
extends Node

signal action_requested(action: String)
signal manual_action(action: String)

const ACTIONS: PackedStringArray = ["idle", "greet", "head_pat", "happy", "surprised", "drag", "walk"]
var current_action: String = "idle"
var current_origin: String = "system"
var motion_actions := PackedStringArray()
var action_definitions: Dictionary = {}
var _resume_action := "idle"
var _return_timer: Timer


func _ready() -> void:
	_return_timer = Timer.new()
	_return_timer.one_shot = true
	_return_timer.timeout.connect(_return_to_idle)
	add_child(_return_timer)


func request_action(action: String, origin: String = "user") -> bool:
	if not action_definitions.is_empty() and not action_definitions.has(action):
		return false
	if not ACTIONS.has(action) and not motion_actions.has(action):
		return false
	var previous := current_action
	var previous_origin := current_origin
	if origin in ["user", "touch"]:
		manual_action.emit(action)
	current_action = action
	current_origin = origin
	_return_timer.stop()
	action_requested.emit(action)
	if not action_definitions.is_empty():
		var definition: Dictionary = action_definitions[action]
		var mode := str(definition.get("mode", "once"))
		if mode in ["once", "segment"]:
			if previous_origin == "ambient":
				_resume_action = "idle"
			elif str(action_definitions.get(previous, {}).get("mode", "")) == "hold" and previous not in ["drag", "walk"]:
				_resume_action = previous
			if mode == "once" or origin != "model":
				_return_timer.start(maxf(0.1, float(definition.get("seconds", 3.0))))
		elif action == "idle":
			_resume_action = "idle"
		return true
	if action not in ["idle", "drag", "walk"] and not motion_actions.has(action):
		var body_id := PalMotionLibrary.body_clip(action)
		if motion_actions.has(body_id) or (not motion_actions.is_empty() and PalMotionLibrary.DESKTOP_CLIPS.has(body_id)):
			var body := PalMotionLibrary.clip(body_id)
			# A one-shot reports its real completion through the presenter. A
			# looped reaction plays one cycle; a static reaction holds for 2 seconds.
			if body.mode != "once":
				_return_timer.start(float(body.seconds) if body.mode == "loop" else 2.0)
		else:
			_return_timer.start(2.6 if action == "greet" else 2.0)
	return true


func complete_action(action: String) -> void:
	if action == current_action:
		_return_to_idle()


func _return_to_idle() -> void:
	var resume := _resume_action if action_definitions.has(_resume_action) else "idle"
	_resume_action = "idle"
	request_action(resume, "system")
