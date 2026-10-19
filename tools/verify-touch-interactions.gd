extends SceneTree
## Exercise offline touches through each host, including clothing and edge attachment.
var _app: PalUiCoordinator
var _pet: PalPetInstance
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error(message)
	return condition


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _dispatch(point: Vector2, desktop: PalDesktopWindow = null) -> void:
	_app._last_touch.erase(_pet.profile.profile_id)
	if desktop == null:
		_app._hall.character_pressed.emit(point)
	else:
		desktop._pressing = true
		desktop._dragging = false
		desktop._press_local_position = point
		desktop._finish_press(point)


func _check_touch(index: int, desktop: PalDesktopWindow = null) -> void:
	var regions: Control = _app._hall._touch_regions if desktop == null else desktop._touch_regions
	regions.refresh()
	if not _expect(regions._regions.size() == 3, "Character touch regions missing"):
		return
	var region: Dictionary = regions._regions[index]
	var point: Vector2 = region.center
	if desktop != null:
		point += desktop.surface.position
	var previous: String = _pet.presenter._pose_id
	_dispatch(point, desktop)
	await _settle()
	var action := _pet.behavior.current_action
	_expect(_pet.behavior.current_origin == "touch", "Click failed to start a local touch reaction")
	_expect(action in PalUiCoordinator.TOUCH_REACTIONS[region.region], "Reaction does not match touched region")
	_expect(action in _pet.presenter.get_capabilities().actions, "Reaction unavailable in the current outfit/view")
	_expect(_pet.presenter._pose_id != previous, "Consecutive touch repeated the visible portrait")
	_expect(not _app._pending_touches.has(_pet.profile.profile_id), "Offline touch queued a model request")
	_expect(not _app._performances[_pet.profile.profile_id].is_playing(), "Offline touch started a speech performance")


func _run() -> void:
	OS.set_environment("GD_PAL_TEST", "1")
	_app = load("res://scenes/app/app.tscn").instantiate()
	_app._ui_state_path = "res://output/touch-interaction-check.cfg"
	root.add_child(_app)
	await _settle()
	_pet = _app._manager.instances.values()[0]
	_app._set_desktop_dialogue(_pet, false)
	await _settle()
	for view: String in ["call", "full_body"]:
		_app._set_character_framing(_pet.profile.profile_id, view)
		for outfit: String in ["maid", "nightdress"]:
			_pet.set_outfit(outfit)
			await _settle()
			for index: int in [0, 0, 1, 2]:
				await _check_touch(index)
	_app._hall.show_view("performance")
	await _settle()
	await _check_touch(0)
	var regions: Control = _app._hall._touch_regions
	regions.refresh()
	var outside_hotspots: Vector2 = regions._bounds.position + regions._bounds.size * Vector2(0.95, 0.9)
	_expect(regions.region_at(outside_hotspots).is_empty(), "Offline coverage fixture is still inside a hotspot")
	_expect(not regions.region_at(outside_hotspots, true).is_empty(), "Clicks on the character outside hotspots have no offline feedback")
	var previous: String = _pet.presenter._pose_id
	_dispatch(outside_hotspots)
	await _settle()
	_expect(previous != _pet.presenter._pose_id, "Offline character click outside hotspots did not change the portrait")
	previous = _pet.presenter._pose_id
	_dispatch(Vector2(-20, -20))
	await _settle()
	_expect(previous == _pet.presenter._pose_id, "Blank background triggered a touch")
	_app._restore_floating_call(_pet.profile.profile_id)
	await _settle()
	var desktop: PalDesktopWindow = _app._desktop_windows[_pet.instance_id]
	for view: String in ["call", "full_body"]:
		_app._set_desktop_mode(_pet.profile.profile_id, view)
		for outfit: String in ["maid", "nightdress"]:
			_pet.set_outfit(outfit)
			await _settle()
			for index: int in [0, 0, 1, 2]:
				await _check_touch(index, desktop)
		for scale_value: float in [0.65, 1.0, 1.5]:
			desktop.resize_pet(scale_value)
			desktop._toolbar_timeout = 60.0
			desktop._toolbar.show()
			await _settle()
			_expect(Rect2(Vector2.ZERO, Vector2(desktop.size)).encloses(desktop._toolbar.get_rect()), "Wrapped toolbar escaped the character window")
	previous = _pet.presenter._pose_id
	_dispatch(desktop._chat_button.global_position + desktop._chat_button.size * 0.5, desktop)
	await _settle()
	_expect(previous == _pet.presenter._pose_id, "Toolbar click leaked into character touch")
	desktop._press_local_position = Vector2(10, 10)
	desktop._finish_press(Vector2(30, 30))
	_expect(previous == _pet.presenter._pose_id, "Moved pointer was mistaken for a click")
	_app._last_touch.erase(_pet.profile.profile_id)
	_app._touch_character(_pet.instance_id, "upper")
	var first_action := _pet.behavior.current_action
	_app._touch_character(_pet.instance_id, "upper")
	_expect(first_action == _pet.behavior.current_action, "Duplicate click was not debounced")
	await _settle()
	for posture: String in ["sit", "prone"]:
		_pet.profile.edge_posture = posture
		_pet.behavior.request_action(posture)
		_pet.presenter.set_surface_attachment(true)
		desktop._attachment = {"id": "fixture", "kind": "taskbar", "left": 0, "right": 1920, "y": 1000, "source_left": 0, "source_width": 1920}
		desktop._attachment_time = 60.0
		desktop.resize_pet(0.65)
		await _settle()
		var resting_pose: String = _pet.presenter._pose_id
		await _check_touch(0, desktop)
		_expect(not desktop._attachment.is_empty(), "Local touch detached the character from its edge")
		_pet.behavior.complete_action(_pet.behavior.current_action)
		await _settle()
		_expect(not desktop._attachment.is_empty() and _pet.presenter._pose_id == resting_pose, "Touch did not restore the attached posture")
		_expect(desktop._toolbar.get_rect().end.y <= _pet.presenter.get_support_anchor().y, "Wrapped edge toolbar extended below the support")
	desktop._release_attachment(true)
	var snapshot: Dictionary = JSON.parse_string(_app._chat_service.call("GetSnapshot", _pet.profile.profile_id))
	_expect(not snapshot.dialogue_enabled and snapshot.total_messages == 0, "Offline interactions created conversation history")
	_app.queue_free()
	await process_frame
	if not _failed:
		print("Touch interactions passed: hall/performance/desktop, both views/outfits, per-region random portraits, no repeated pose, no chat/voice, empty-space/toolbar/drag/debounce guards, attachment restoration and wrapped toolbar bounds.")
	quit(1 if _failed else 0)
