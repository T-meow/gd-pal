extends SceneTree
## Exercise real close-button and native-close signal handlers, including two companions.
var _app: PalUiCoordinator
var _failed := false

func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error(message)
		quit(1)
	return condition


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _click(owner: Node, button_name: String) -> void:
	var button: Button = owner.find_child(button_name, true, false)
	if not _expect(button != null, "Missing close control: " + button_name):
		return
	button.pressed.emit()


func _run() -> void:
	OS.set_environment("GD_PAL_TEST", "1")
	_app = load("res://scenes/app/app.tscn").instantiate()
	_app._ui_state_path = "res://output/window-close-check.cfg"
	root.add_child(_app)
	await _settle()
	var first: PalPetInstance = _app._manager.instances.values()[0]
	var second: PalPetInstance = _app._add_pet("sprite2d")
	var first_id := first.profile.profile_id
	var second_id := second.profile.profile_id
	_app._set_desktop_dialogue(first, false)
	_app._restore_floating_call(first_id)
	_app._restore_floating_call(second_id)
	await _settle()
	var chat: PalChatWindow = _app._chat_windows[first.instance_id]
	var other_chat: PalChatWindow = _app._chat_windows[second.instance_id]
	var monitor: Window = _app._desktop_windows[first.instance_id]._monitor_window
	var other_monitor: Window = _app._desktop_windows[second.instance_id]._monitor_window
	var service: Node = _app._pc_monitor
	service.call("SetDesktopVisibleFor", first_id, true)
	service.call("SetDesktopVisibleFor", second_id, true)
	service.call("SetExpandedFor", first_id, false)
	service.call("SetExpandedFor", second_id, false)
	await _settle()
	if not _expect(not monitor.unfocusable, "Performance window cannot receive its own native close command"):
		return
	_click(monitor, "CloseMonitor")
	await _settle()
	monitor.call("UpdatePlacement")
	if not _expect(not service.call("IsDesktopVisibleFor", first_id) and service.call("IsDesktopVisibleFor", second_id) and chat.visible and other_chat.visible, "Closing one performance card affected records or another companion"):
		return
	service.call("SetDesktopVisibleFor", first_id, true)
	await _settle()
	var size_before_close := chat.size
	_click(chat, "CloseRecords")
	if not _expect(chat.size == size_before_close, "Closing records first resized the window under the pointer"):
		return
	await _settle()
	chat.follow_pet()
	if not _expect(not chat.visible and chat.display_mode == "hidden" and service.call("IsDesktopVisibleFor", first_id) and other_chat.visible, "Record close reopened itself or closed another window"):
		return
	chat.open_chat(false)
	await _settle()
	_click(chat, "CollapseRecords")
	await _settle()
	if not _expect(chat.visible and chat.display_mode == "compact" and service.call("IsDesktopVisibleFor", first_id), "Record collapse changed performance visibility"):
		return
	_click(chat, "CloseRecordsCompact")
	await _settle()
	if not _expect(not chat.visible and service.call("IsDesktopVisibleFor", first_id), "Compact record close affected the performance card"):
		return
	chat.open_chat(false)
	chat.close_requested.emit()
	await _settle()
	if not _expect(not chat.visible and service.call("IsDesktopVisibleFor", first_id), "Native record close targeted another window"):
		return
	chat.open_chat(false)
	monitor.close_requested.emit()
	await _settle()
	if not _expect(chat.visible and not service.call("IsDesktopVisibleFor", first_id) and service.call("IsDesktopVisibleFor", second_id), "Native monitor close affected records or another monitor"):
		return
	service.call("SetDesktopVisibleFor", first_id, true)
	_click(monitor, "ToggleMonitorDetails")
	await _settle()
	if not _expect(service.call("IsExpandedFor", first_id) and not service.call("IsExpandedFor", second_id), "Monitor detail mode leaked between companions"):
		return
	_click(monitor, "CloseMonitor")
	service.call("SetDesktopVisibleFor", first_id, true)
	chat.close_records()
	chat.open_chat(false)
	await _settle()
	if not _expect(chat.visible and service.call("IsDesktopVisibleFor", first_id), "A stale close callback defeated a newer open request"):
		return
	for records_first: bool in [true, false]:
		chat.open_chat(false)
		service.call("SetDesktopVisibleFor", first_id, true)
		await _settle()
		if records_first:
			_click(chat, "CloseRecords")
			_click(monitor, "CloseMonitor")
		else:
			_click(monitor, "CloseMonitor")
			_click(chat, "CloseRecords")
		await _settle()
		chat.follow_pet()
		monitor.call("UpdatePlacement")
		if not _expect(not chat.visible and not service.call("IsDesktopVisibleFor", first_id) and other_chat.visible and service.call("IsDesktopVisibleFor", second_id), "Consecutive close actions interfered with another window"):
			return
	_app._restore_floating_call(first_id)
	await _settle()
	if not _expect(chat.visible and not service.call("IsDesktopVisibleFor", first_id) and not first.profile.desktop_dialogue_enabled, "Restoring records silently reopened monitoring or enabled dialogue"):
		return
	_app._desktop_windows[first.instance_id].close_requested.emit()
	await _settle()
	if not _expect(not chat.visible and not _app._desktop_windows.has(first.instance_id) and other_chat.visible and service.call("IsDesktopVisibleFor", second_id), "Closing the companion affected another companion's windows"):
		return
	if not _expect(not service.call("IsDesktopVisibleFor", first_id), "Recalling a companion reset its closed performance card"):
		return
	_app.queue_free()
	await _settle()
	if _failed:
		return
	print("Window close flow passed: expanded/compact/native closes, consecutive closes, late-open precedence, per-companion visibility/detail state, host recall and restore.")
	quit(0)
