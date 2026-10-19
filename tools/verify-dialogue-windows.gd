extends SceneTree
## Reproduce disabling dialogue, closing the floating view, recalling and restoring it.
## Fixtures use the project's isolated test storage and never configure a model service.

func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


func _run() -> void:
	OS.set_environment("GD_PAL_TEST", "1")
	var app: PalUiCoordinator = load("res://scenes/app/app.tscn").instantiate()
	app._ui_state_path = "res://output/dialogue-window-check.cfg"
	root.add_child(app)
	await process_frame
	await process_frame
	if not _expect(app._manager.instances.size() == 1, "Expected one isolated companion fixture"):
		return
	var pet: PalPetInstance = app._manager.instances.values()[0]
	var chat: PalChatWindow = app._chat_windows[pet.instance_id]
	var service: Node = app._chat_service
	app._pending_touches[pet.profile.profile_id] = {"text": "queued touch"}
	app._hall._desktop_page._dialogue.button_pressed = false
	await process_frame
	var snapshot: Dictionary = JSON.parse_string(service.call("GetSnapshot", pet.profile.profile_id))
	if not _expect(not snapshot.dialogue_enabled and not pet.profile.desktop_dialogue_enabled, "Hall checkbox failed to disable backend dialogue"):
		return
	if not _expect(chat.panel._send_button.disabled and not chat.panel._input.editable and chat.panel._dialogue_notice.visible, "Disabled dialogue must be visibly read-only"):
		return
	app._touch_character(pet.instance_id, "upper")
	app._hall.character_pressed.emit(Vector2(100, 100))
	if not _expect(not app._pending_touches.has(pet.profile.profile_id), "Touch requests survived disabled dialogue"):
		return
	for method: String in ["SendMessage", "ContinueMessage", "RetryMessage"]:
		var result: String = service.call(method, pet.profile.profile_id, "test") if method == "SendMessage" else service.call(method, pet.profile.profile_id)
		if not _expect(result.contains("已关闭"), "Backend entry point bypassed dialogue switch: " + method):
			return
	chat.set_display_mode("hidden")
	app._hall._desktop_page._restore_call.pressed.emit()
	await process_frame
	await process_frame
	if not _expect(app._desktop_windows.has(pet.instance_id) and chat.visible and chat.display_mode == "expanded", "Restore button did not recover the hidden floating window"):
		return
	if not _expect(not pet.profile.desktop_dialogue_enabled and not chat.panel._input.editable, "Restoring the window silently enabled dialogue"):
		return
	chat.set_display_mode("hidden")
	app._return_pet(pet.instance_id)
	await process_frame
	await process_frame
	snapshot = JSON.parse_string(service.call("GetSnapshot", pet.profile.profile_id))
	if not _expect(not snapshot.dialogue_enabled and not chat.panel._input.editable, "Recalling the companion silently enabled dialogue"):
		return
	if not _expect(pet.get_parent() == app._hall.surface and app._hall.surface.visible, "Recall did not restore the character to the hall"):
		return
	app._hall._desktop_page._restore_call.pressed.emit()
	await process_frame
	await process_frame
	if not _expect(chat.visible and chat.display_mode == "expanded" and app._desktop_windows.size() == 1, "Second restore failed or duplicated the floating window"):
		return
	chat.panel.dialogue_enable_requested.emit()
	await process_frame
	snapshot = JSON.parse_string(service.call("GetSnapshot", pet.profile.profile_id))
	if not _expect(snapshot.dialogue_enabled and chat.panel._input.editable and not chat.panel._dialogue_notice.visible, "Explicit enable action did not restore dialogue"):
		return
	if not _expect(snapshot.total_messages == 0, "Window operations unexpectedly created a conversation turn"):
		return
	app.queue_free()
	await process_frame
	print("Dialogue/window flow passed: disabled in hall and desktop, no touch/send bypass, hidden window restored twice without enabling dialogue, explicit enable works.")
	quit(0)
