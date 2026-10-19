extends SceneTree
## Validate the monitor-page entry, compact host, interaction and restoration without user storage.
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _expect(value: bool, message: String) -> void:
	if not value:
		_failed = true
		push_error(message)


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _run() -> void:
	OS.set_environment("GD_PAL_TEST", "1")
	var app: PalUiCoordinator = load("res://scenes/app/app.tscn").instantiate()
	app._ui_state_path = "res://output/minimal-monitor-check.cfg"
	root.add_child(app)
	await _settle()
	var pet: PalPetInstance = app._manager.instances.values()[0]
	var profile_id := pet.profile.profile_id
	pet.profile.desktop_scale = 0.8
	app._restore_floating_call(profile_id)
	var chat: PalChatWindow = app._chat_windows[pet.instance_id]
	chat.open_chat(false)
	var service: Node = app._pc_monitor
	service.call("SetDesktopVisibleFor", profile_id, true)
	app._show_main()
	app._hall.show_view("performance")
	await _settle()
	var entry: Button = app._hall._monitor_page.find_child("OpenMinimalMonitor", true, false)
	_expect(entry != null and not entry.disabled, "Performance page is missing the minimal-mode entry")
	if entry == null:
		quit(1)
		return
	entry.pressed.emit()
	await _settle()
	var desktop: PalDesktopWindow = app._desktop_windows[pet.instance_id]
	_expect(is_equal_approx(desktop.display_scale(), 1.0), "First minimal entry inherited the normal desktop scale")
	_expect(desktop.visible and desktop.is_minimal_mode() and pet.presentation_mode == "call" and pet.monitor_only, "Minimal mode did not use a visible close-up host")
	_expect(desktop._minimal_scroll.visible and desktop._minimal_background.visible, "Minimal monitor data/background is hidden")
	_expect(not chat.visible and chat.display_mode == "expanded" and not desktop._monitor_window.visible, "Separate record or performance windows survived minimal mode")
	_expect(service.call("IsDesktopVisibleFor", profile_id), "Minimal mode changed the saved performance-card preference")
	app._set_desktop_dialogue(pet, true)
	var during: Dictionary = JSON.parse_string(app._chat_service.call("GetSnapshot", profile_id))
	_expect(pet.profile.desktop_dialogue_enabled and not during.dialogue_enabled, "Minimal mode failed to block dialogue while preserving the preference")
	for method: String in ["SendMessage", "ContinueMessage", "RetryMessage", "SendImageMessage"]:
		var result: String
		if method == "SendMessage":
			result = app._chat_service.call(method, profile_id, "must stay local")
		elif method == "SendImageMessage":
			result = app._chat_service.call(method, profile_id, "must stay local", "[]")
		else:
			result = app._chat_service.call(method, profile_id)
		_expect(result.contains("已关闭"), "Chat API entry point bypassed minimal mode: " + method)
	if "--capture" in OS.get_cmdline_user_args():
		# Simulate carrying a config from another PC; readouts must resolve current hardware.
		service.call("SelectGpu", "previous-pc-gpu")
		service.call("SelectNetwork", "previous-pc-network")
		service.call("SelectSensor", "gpu_temp", "previous-pc-temperature")
		await create_timer(4.0).timeout
		var gpu_value: Label = desktop._minimal_panel.find_child("gpu", true, false)
		var gpu_temperature: Label = desktop._minimal_panel.find_child("gpu_sub", true, false)
		var network_value: Label = desktop._minimal_panel.find_child("download", true, false)
		_expect(gpu_value.text != "—" and not gpu_temperature.text.contains("—") and not network_value.text.contains("—"), "Unavailable bindings did not fall back to this PC's GPU, network and temperature")
		DirAccess.make_dir_recursive_absolute("res://output/performance-monitor-design")
		desktop.resize_pet(1.0)
		for glass_theme: String in ["light", "dark"]:
			service.call("SetMinimalAppearance", glass_theme, 0.12)
			await _settle()
			await RenderingServer.frame_post_draw
			var image := desktop.get_texture().get_image()
			image.save_png("res://output/performance-monitor-design/minimal-glass-%s.png" % glass_theme)
		app.queue_free()
		await process_frame
		print("Glass capture and hardware-migration fallback completed.")
		quit(1 if _failed else 0)
		return
	desktop.say("This must stay hidden", true)
	desktop.set_unread_count(3)
	await _settle()
	_expect(not desktop._toolbar.visible and not desktop._bubble.visible and not desktop._description_bubble.visible and not desktop._unread_button.visible, "Minimal mode showed extra conversation controls")
	for scale_value: float in [0.65, 1.0, 1.5]:
		desktop.resize_pet(scale_value)
		await _settle()
		var bounds := Rect2(Vector2.ZERO, Vector2(desktop.size))
		_expect(bounds.encloses(desktop.surface.get_rect()) and bounds.encloses(desktop._minimal_scroll.get_rect()), "Minimal content escaped window bounds")
		_expect(not desktop.surface.get_rect().intersects(desktop._minimal_scroll.get_rect()), "Portrait overlaps monitoring data")
		_expect(desktop._minimal_panel.size.x <= desktop._minimal_scroll.size.x, "Minimal data requires horizontal scrolling")
	for outfit: String in ["maid", "nightdress"]:
		pet.set_outfit(outfit)
		await _settle()
		desktop._touch_regions.refresh()
		var point: Vector2 = desktop.surface.position + desktop._touch_regions._regions[0].center
		var before: String = pet.presenter._pose_id
		app._last_touch.erase(profile_id)
		desktop._press_local_position = point
		desktop._finish_press(point)
		await _settle()
		_expect(before != pet.presenter._pose_id and not app._pending_touches.has(profile_id), "Minimal portrait click failed or queued chat")
		var performance: PalPerformanceQueue = app._performances[profile_id]
		performance.present_segment("Should not speak", "")
		performance.speak_manual("Should not speak")
		_expect(not performance.is_playing(), "Minimal mode started a speech performance")
	service.call("SetExpandedFor", profile_id, true)
	await _settle()
	_expect(desktop._minimal_panel.find_child("CloseMonitor", true, false) == null, "Changing the normal monitor mode rebuilt minimal mode as a full panel")
	desktop._minimal_menu.id_pressed.emit(1)
	await _settle()
	_expect(is_equal_approx(pet.profile.desktop_scale, 0.8), "Minimal resizing overwrote the normal desktop scale")
	_expect(not desktop.is_minimal_mode() and not pet.monitor_only and not desktop._minimal_scroll.visible, "Exit did not restore the normal host")
	_expect(chat.visible and pet.profile.desktop_dialogue_enabled, "Exit lost record visibility or dialogue preference")
	var resumed: Dictionary = JSON.parse_string(app._chat_service.call("GetSnapshot", profile_id))
	_expect(resumed.dialogue_enabled, "Leaving minimal mode did not restore the backend dialogue preference")
	app._set_desktop_dialogue(pet, false)
	app._open_minimal_monitor(profile_id)
	await _settle()
	desktop._minimal_menu.id_pressed.emit(2)
	await _settle()
	_expect(not app._desktop_windows.has(pet.instance_id) and pet.get_parent() == app._hall.surface and not pet.monitor_only, "Returning to the hall left a minimal window or disabled presenter")
	_expect(not pet.profile.desktop_dialogue_enabled, "Minimal mode re-enabled disabled dialogue")
	var snapshot: Dictionary = JSON.parse_string(app._chat_service.call("GetSnapshot", profile_id))
	_expect(snapshot.total_messages == 0, "Minimal-mode operations created chat messages")
	app.queue_free()
	await process_frame
	if not _failed:
		print("Minimal monitor passed: page entry, close-up/data layout at three sizes, isolated panel state, hidden chat/controls, touch without chat/voice, two outfits, exit and recall preserve preferences.")
	quit(1 if _failed else 0)
