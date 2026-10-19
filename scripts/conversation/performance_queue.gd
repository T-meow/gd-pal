class_name PalPerformanceQueue
extends Node
## Owns only live performances; event history is never replayed on startup.
signal speech_failed(message: String)

var service: Node
var pet: PalPetInstance
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _audio: AudioStreamPlayer
var _remaining := 0.0
var _waiting_voice := false
var _voice_request := ""
var _generation := 0
var _manual_text := ""
var _manual_waiting_cancel := false


func _ready() -> void:
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	service.connect("PerformanceCancelled", _on_cancel)
	service.connect("SpeechReady", _on_speech)
	pet.behavior.manual_action.connect(func(_action: String) -> void: service.call("CancelPerformance", pet.profile.profile_id); cancel())
	pet.visual_changed.connect(func(_visual: String) -> void: service.call("CancelPerformance", pet.profile.profile_id); cancel())


func present_segment(dialogue: String, description: String) -> void:
	if (not pet.profile.desktop_dialogue_enabled or pet.monitor_only):
		return
	# Bubble navigation owns the sequence, so speech never runs ahead of the text.
	cancel()
	_queue.append({"segment_id": str(_generation), "data": {"say": dialogue, "aside": description}})
	_start_next()


func is_playing() -> bool:
	return not _active.is_empty() or not _queue.is_empty() or _waiting_voice or not _manual_text.is_empty() or (_audio != null and _audio.playing)


func _start_next() -> void:
	if (not pet.profile.desktop_dialogue_enabled or pet.monitor_only) or not _active.is_empty() or _queue.is_empty() or pet.presenter == null:
		return
	_active = _queue.pop_front()
	var segment: Dictionary = _active.data
	var action := str(segment.get("act", "")) if segment.get("act") != null else ""
	var face := str(segment.get("face", "")) if segment.get("face") != null else ""
	var available := pet.presenter.get_capabilities()
	_remaining = 0.8
	if action in available.get("actions", []):
		pet.behavior.request_action(action, "model")
		var clip: Dictionary = available.get("action_details", {}).get(action, PalMotionLibrary.clip(PalMotionLibrary.body_clip(action)))
		_remaining = maxf(0.8, float(clip.get("seconds", 2.0)))
	elif segment.get("say") != null and not str(segment.say).is_empty() and "respond" in available.get("actions", []) and not bool(pet.behavior.action_definitions.get(pet.behavior.current_action, {}).get("preserve_activity", false)):
		pet.behavior.request_action("respond", "model")
		_remaining = 2.5
	pet.presenter.set_expression(face)
	var role_data: Dictionary = JSON.parse_string(service.call("GetRole", pet.profile.profile_id))
	var say := str(segment.get("say", "")) if segment.get("say") != null else ""
	if bool(role_data.get("profile", {}).get("auto_speak", false)) and bool(segment.get("speak", true)) and not say.is_empty():
		_waiting_voice = true
		_voice_request = str(_active.segment_id) + ":" + str(_generation)
		service.call("RequestSpeech", pet.profile.profile_id, _voice_request, say)


func _process(delta: float) -> void:
	if (not pet.profile.desktop_dialogue_enabled or pet.monitor_only):
		if is_playing():
			cancel()
			stop_speech()
		return
	if not _manual_text.is_empty() and not _manual_waiting_cancel:
		_voice_request = "manual:" + str(_generation)
		service.call("RequestSpeech", pet.profile.profile_id, _voice_request, _manual_text)
		_manual_text = ""
	if _active.is_empty():
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining == 0 and not _waiting_voice and not _audio.playing:
		if str(pet.behavior.action_definitions.get(pet.behavior.current_action, {}).get("mode", "")) == "segment":
			pet.behavior.complete_action(pet.behavior.current_action)
		_active.clear()
		pet.presenter.set_expression("")
		_start_next()


func _on_speech(profile_id: String, request_id: String, wav: PackedByteArray, error: String) -> void:
	if (not pet.profile.desktop_dialogue_enabled or pet.monitor_only) or profile_id != pet.profile.profile_id or request_id != _voice_request:
		return
	_waiting_voice = false
	if not error.is_empty():
		speech_failed.emit(error)
		return
	var stream := AudioStreamWAV.load_from_buffer(wav)
	if stream != null:
		_audio.stream = stream
		_audio.play()


func speak_manual(text: String) -> void:
	if (not pet.profile.desktop_dialogue_enabled or pet.monitor_only):
		return
	service.call("CancelPerformance", pet.profile.profile_id)
	cancel()
	_manual_text = text
	_manual_waiting_cancel = true


func stop_speech() -> void:
	_generation += 1
	_voice_request = ""
	_waiting_voice = false
	_manual_text = ""
	_manual_waiting_cancel = false
	if is_instance_valid(_audio):
		_audio.stop()
	service.call("CancelSpeech", pet.profile.profile_id)


func _on_cancel(profile_id: String) -> void:
	if profile_id == pet.profile.profile_id:
		cancel()
		_manual_waiting_cancel = false


func cancel() -> void:
	_generation += 1
	if not _active.is_empty():
		pet.behavior.request_action("idle", "model")
	_queue.clear()
	_active.clear()
	_voice_request = ""
	_waiting_voice = false
	if is_instance_valid(_audio):
		_audio.stop()
	service.call("CancelSpeech", pet.profile.profile_id)
	if pet.presenter != null:
		pet.presenter.set_expression("")


func _exit_tree() -> void:
	if is_instance_valid(service):
		service.call("CancelSpeech", pet.profile.profile_id)
