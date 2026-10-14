class_name PalUiCoordinator
extends Control
## Owns profile selection, physical hosts and all in-window navigation.

const HALL_SCENE := preload("res://scenes/app/companion_hall.tscn")
const UI_STATE_PATH := "user://ui_state.cfg"

@onready var _manager: PalInstanceManager = $PetInstanceManager
@onready var _bridge: Node = $WindowsDesktopBridge
@onready var _chat_service: Node = $ChatService
var _hall: PalCompanionHall
var _tray: PalSystemTray
var _main_hidden := false
var _mobile_paused := false
var _panels: PalPanelHost
var _parking: Control
var _chat_window: PalChatWindow
var _views: Dictionary = {}
var _hosts: Dictionary = {}
var _desktop_windows: Dictionary = {}
var _chat_windows: Dictionary = {}
var _pages: Dictionary = {}
var _unread: Dictionary = {}
var _selected_profile_id := ""
var _storage_notice: Label
var _status: Label
var _save_timer: Timer
var _restoring := true
var _scale_time := 0.0
var _saving_profile := false
var _session_path := PalSessionStore.DEFAULT_PATH
var _persist_session := OS.get_environment("GD_PAL_TEST") != "1"
var _ui_state_path := UI_STATE_PATH
var _persist_ui := OS.get_environment("GD_PAL_TEST") != "1"
var _session_writable := true
var _preferences := PalUiPreferences.new()
var _performances: Dictionary = {}
var _idle_routines: Dictionary = {}
var _idle_actions_enabled := true
var _pending_touches: Dictionary = {}
var _last_touch: Dictionary = {}
var _touch_poll := 0.0
var _history_deletes: Dictionary = {}


func _ready() -> void:
	_preferences.path = _ui_state_path
	_preferences.persistent = _persist_ui
	_preferences.load_preferences()
	PalUi.show_touch_regions = bool(_preferences.get_value("interaction", "show_touch_regions", false))
	_chat_service.call("ConfigurePersonaPresets", PalProfile.DEFAULT_PERSONA, PalProfile.ANDROID_PERSONA)
	PalUi.overlay_opacity = clampf(float(_preferences.get_value("overlay", "opacity", 0.25)), 0.1, 0.5)
	PalUi.dialogue_bubbles = bool(_preferences.get_value("overlay", "dialogue", true))
	PalUi.description_bubbles = bool(_preferences.get_value("overlay", "description", true))
	PalUi.dialogue_autoplay = bool(_preferences.get_value("overlay", "autoplay", false))
	_idle_actions_enabled = bool(_preferences.get_value("companion", "idle_actions", true))
	var theme_mode := str(_preferences.get_value("appearance", "mode", "light" if PalUi.is_mobile() else "dark"))
	var accent := Color.from_string(str(_preferences.get_value("appearance", "accent", "2468b5" if PalUi.is_mobile() else "acc9e7")), Color("6b9fd4"))
	PalUi.configure_appearance(theme_mode, accent)
	Engine.max_fps = 60
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	theme = PalUi.make_theme()
	PalUi.fit_window(get_window(), Vector2i(1440, 900), Vector2i(960, 640))
	get_window().gui_embed_subwindows = true
	if not PalUi.is_mobile() and not PalUi.is_editor_preview(get_window()):
		get_window().borderless = true
	_hall = PalMobileHall.new() if PalUi.is_mobile() else HALL_SCENE.instantiate()
	add_child(_hall)
	_hall.pomodoro.configure({"focus_minutes": _preferences.get_value("pomodoro", "focus_minutes", 25), "rest_minutes": _preferences.get_value("pomodoro", "rest_minutes", 5), "automatic": _preferences.get_value("pomodoro", "automatic", true)}, _idle_actions_enabled)
	_hall.pomodoro.settings_changed.connect(func(settings: Dictionary) -> void: _preferences.put_values("pomodoro", settings))
	_hall.pomodoro.idle_actions_changed.connect(_set_idle_actions_enabled)
	_hall.pomodoro.running_changed.connect(func(running: bool) -> void:
		for routine: PalIdleRoutine in _idle_routines.values():
			routine.hanging = running)
	_hall.visual_requested.connect(_change_visual_from_stage)
	_hall.portrait_framing_requested.connect(func(mode: String) -> void: _set_character_framing(_selected_profile_id, mode))
	_hall.touch_regions_requested.connect(_set_touch_regions_visible)
	if _hall is PalMobileHall:
		_hall.framing_changed.connect(func(mode: String) -> void:
			var pet := _pet_for_profile(_selected_profile_id)
			if pet != null:
				pet.set_presentation_mode(mode)
		)
	_hall.chat_width = float(_preferences.get_value("ui", "chat_width", 360.0))
	_hall.chat_width_changed.connect(func(value: float) -> void: _preferences.put("ui", "chat_width", value))
	if not PalUi.is_mobile():
		_hall.configure_preferences(str(_preferences.get_value("ui", "room_id", "night-study")), bool(_preferences.get_value("ui", "chat_open", true)))
		_hall.room_changed.connect(func(id: String) -> void: _preferences.put("ui", "room_id", id))
		_hall.history_visibility_changed.connect(func(value: bool) -> void: _preferences.put("ui", "chat_open", value))
		_hall.view_changed.connect(_on_hall_view_changed)
		_hall.voice_requested.connect(_toggle_voice)
		_hall.desktop_preference_requested.connect(_set_desktop_preference)
	_hall.character_pressed.connect(func(point: Vector2) -> void:
		if _panels != null and (_panels.is_open() or _panels.is_confirming()):
			return
		var pet := _pet_for_profile(_selected_profile_id)
		if pet != null and pet.presenter != null and _hosts.get(pet.instance_id) == "hall":
			var region := _hall.touch_region_at(point)
			if not region.is_empty():
				_touch_character(pet.instance_id, region)
			else:
				_note_user_activity(pet.profile.profile_id)
				_ensure_chat_window(pet.instance_id).panel.navigate_bubbles(1)
	)
	_parking = Control.new()
	_parking.name = "ParkedCompanions"
	_parking.hide()
	add_child(_parking)
	_panels = PalPanelHost.new()
	add_child(_panels)
	_status = _hall._notice
	_storage_notice = _status
	_panels.close_requested.connect(_close_panel)
	_hall.profile_selected.connect(select_profile)
	_hall.page_requested.connect(func(page: String) -> void: open_panel(page, _selected_profile_id))
	_hall.desktop_requested.connect(func() -> void:
		var pet := _pet_for_profile(_selected_profile_id)
		if pet != null:
			_guard_navigation(func() -> void: _toggle_desktop(pet.instance_id))
	)
	_hall.action_requested.connect(func(action: String) -> void:
		var pet := _pet_for_profile(_selected_profile_id)
		if pet != null and _hosts.get(pet.instance_id) == "hall":
			pet.behavior.request_action(action)
	)
	_hall.close_requested.connect(_close_main)
	_tray = PalSystemTray.new()
	_tray.show_requested.connect(_show_main)
	_tray.hide_requested.connect(_hide_main)
	_tray.quit_requested.connect(_quit_requested)
	add_child(_tray)
	if _tray.is_available():
		_hall._close_button.tooltip_text = "收起到托盘，右键托盘图标可退出"
	_chat_service.connect("ConversationChanged", _on_chat_changed)
	_chat_service.connect("HistoryDeleteFinished", _on_history_deleted)
	_chat_service.connect("ReplyFinished", _on_chat_reply)
	_chat_service.connect("OutfitRequested", func(profile_id: String, outfit: String) -> void:
		var pet := _pet_for_profile(profile_id)
		if pet != null:
			pet.set_outfit(outfit, "model")
	)
	_chat_service.connect("SettingsChanged", _refresh_connection)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(_save_session)
	add_child(_save_timer)
	var session := {"valid": false, "status": "missing", "profiles": []}
	if _persist_session:
		session = PalSessionStore.load_session(_session_path)
	_session_writable = session.status != "invalid"
	if session.status == "missing":
		_add_pet("sprite2d")
	elif session.valid:
		for profile: PalProfile in session.profiles:
			_add_pet(profile.visual_id, profile)
	if not _session_writable:
		_hall.set_notice("角色配置无法读取，已保留原文件并暂停创建和保存。请恢复 pal_session.json 或其 .bak 备份后重启。")
	elif session.status == "recovered":
		_hall.set_notice("已从备份恢复角色配置。再次保存时会另存损坏的原文件，最近一次设置可能需要重新调整。")
	_storage_notice.tooltip_text = ProjectSettings.globalize_path(_session_path)
	_restoring = false
	var selected := _load_ui_selection()
	if _pet_for_profile(selected) == null and not _manager.instances.is_empty():
		selected = (_manager.instances.values()[0] as PalPetInstance).profile.profile_id
	if not selected.is_empty():
		_activate_profile(selected, false)
	else:
		_hall.show_presence("empty")
	_refresh_roster()
	_refresh_connection()
	var core_error: String = _chat_service.call("GetStartupError")
	if not core_error.is_empty():
		_hall.set_notice(core_error)
	if session.status == "recovered":
		_queue_save()
	get_window().files_dropped.connect(_on_files_dropped)
	get_window().close_requested.connect(_close_main)
	get_window().focus_entered.connect(_mark_active_read)
	if "--chat" in OS.get_cmdline_user_args() and not _manager.instances.is_empty():
		_open_chat.call_deferred(str(_manager.instances.keys()[0]))
	print("GD Pal companion hall ready.")


func _pet_for_profile(profile_id: String) -> PalPetInstance:
	for pet: PalPetInstance in _manager.instances.values():
		if pet.profile.profile_id == profile_id:
			return pet
	return null


func _add_pet(visual_id: String, saved_profile: PalProfile = null, allow_fallback: bool = true) -> PalPetInstance:
	if not _session_writable or _manager.instances.size() >= PalInstanceManager.MAX_PREVIEW_INSTANCES:
		return null
	var viewport := SubViewportContainer.new()
	viewport.size = Vector2(350, 360)
	viewport.stretch = true
	_parking.add_child(viewport)
	var pet := _manager.create_pet(visual_id, viewport, saved_profile)
	if pet == null:
		viewport.queue_free()
		return null
	if pet.presenter == null:
		var error := pet.last_error
		if not allow_fallback:
			_manager.remove_pet(pet.instance_id)
			viewport.queue_free()
			_hall.set_notice(error)
			return null
		pet.switch_visual("sprite2d")
		_hall.set_notice(error + " 已暂用内置 2D 外观。")
	pet.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_views[pet.instance_id] = {"viewport": viewport}
	_hosts[pet.instance_id] = "parked"
	_chat_service.call("RegisterProfile", pet.profile.profile_id, pet.profile.display_name, pet.profile.persona, pet.profile.adult_mode)
	var role_data: Dictionary = JSON.parse_string(_chat_service.call("GetRole", pet.profile.profile_id))
	pet.profile.persona = str(role_data.get("profile", {}).get("persona", pet.profile.persona))
	pet.profile.display_name = str(role_data.get("profile", {}).get("display_name", pet.profile.display_name))
	pet.set_adult_mode(bool(role_data.get("profile", {}).get("adult_mode", false)))
	var performance := PalPerformanceQueue.new()
	performance.service = _chat_service
	performance.pet = pet
	performance.speech_failed.connect(func(message: String) -> void: _hall.set_notice(message))
	pet.add_child(performance)
	_performances[pet.profile.profile_id] = performance
	var routine := PalIdleRoutine.new()
	routine.name = "IdleRoutine"
	routine.pet = pet
	routine.performance = performance
	routine.enabled = _idle_actions_enabled
	routine.hanging = _hall.pomodoro.running
	pet.add_child(routine)
	_idle_routines[pet.profile.profile_id] = routine
	pet.visual_changed.connect(func(_value: String) -> void: _on_pet_visual_changed(pet))
	pet.capabilities_changed.connect(_refresh_roster)
	pet.wardrobe_changed.connect(func() -> void:
		_sync_model_wardrobe(pet)
		_refresh_roster()
		_queue_save()
	)
	pet.load_failed.connect(func(error: String) -> void: _hall.set_notice(error))
	_ensure_chat_window(pet.instance_id)
	_refresh_chat_profiles()
	_refresh_roster()
	_queue_save()
	if not _restoring and _selected_profile_id.is_empty():
		_activate_profile(pet.profile.profile_id)
	return pet


func select_profile(profile_id: String) -> void:
	_guard_navigation(func() -> void: _activate_profile(profile_id))


func _activate_profile(profile_id: String, focus: bool = true) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null:
		return
	_note_user_activity(profile_id)
	var previous := _pet_for_profile(_selected_profile_id)
	if previous != null and previous != pet and _hosts.get(previous.instance_id) == "hall":
		_park(previous.instance_id)
	if _hosts.get(pet.instance_id) == "desktop":
		_release_desktop(pet.instance_id)
	_selected_profile_id = profile_id
	_chat_window = _ensure_chat_window(pet.instance_id)
	if _hosts.get(pet.instance_id) != "hall":
		_chat_window.panel.save_view_state()
		pet.reparent(_hall.surface, false)
		pet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		pet.set_presentation_mode(pet.profile.portrait_framing if pet.profile.visual_id == "sprite2d" else "call")
		_hosts[pet.instance_id] = "hall"
		_hall.attach_conversation(_chat_window.panel)
		_chat_window.panel.restore_view_state()
	_chat_window.hide()
	if _idle_routines.has(profile_id):
		(_idle_routines[profile_id] as PalIdleRoutine).active_on_host = true
	_hall.show_presence("hall")
	if not PalUi.is_mobile() and focus:
		_hall.show_view("call")
	if PalUi.is_mobile() or _hall.is_reading_conversation():
		_chat_window.unread = 0
		_unread[profile_id] = 0
	_refresh_roster()
	_save_ui_selection()
	if focus:
		_show_main()


func set_host(profile_id: String, host: String) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null or host not in ["hall", "desktop", "parked"]:
		return
	if host == "hall":
		select_profile(profile_id)
	elif host == "desktop":
		_guard_navigation(func() -> void: _put_on_desktop(pet.instance_id))
	else:
		_guard_navigation(func() -> void:
			_park(pet.instance_id)
			if profile_id == _selected_profile_id:
				_selected_profile_id = ""
				_hall.show_presence("empty")
			_refresh_roster()
		)


func _park(instance_id: String) -> void:
	if not _manager.instances.has(instance_id):
		return
	_release_desktop(instance_id)
	var pet: PalPetInstance = _manager.instances[instance_id]
	var chat := _ensure_chat_window(instance_id)
	chat.panel.save_view_state()
	if _hall.panel == chat.panel:
		_hall.detach_conversation()
	chat.attach_panel()
	chat.hide()
	pet.reparent(_views[instance_id].viewport, false)
	pet.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_hosts[instance_id] = "parked"
	if _idle_routines.has(pet.profile.profile_id):
		(_idle_routines[pet.profile.profile_id] as PalIdleRoutine).active_on_host = false


func _release_desktop(instance_id: String) -> void:
	if not _desktop_windows.has(instance_id):
		return
	var desktop: PalDesktopWindow = _desktop_windows[instance_id]
	desktop.detach_pet(_views[instance_id].viewport)
	_desktop_windows.erase(instance_id)
	desktop.queue_free()
	var chat: PalChatWindow = _chat_windows[instance_id]
	chat.panel.save_view_state()
	chat.bind_desktop(null)
	chat.hide()
	_hosts[instance_id] = "parked"


func _toggle_desktop(instance_id: String) -> void:
	if not _manager.instances.has(instance_id):
		return
	var pet: PalPetInstance = _manager.instances[instance_id]
	if _desktop_windows.has(instance_id):
		_activate_profile(pet.profile.profile_id)
	else:
		_put_on_desktop(instance_id)


func _put_on_desktop(instance_id: String) -> void:
	if PalUi.is_mobile():
		return
	if not _manager.instances.has(instance_id) or _desktop_windows.has(instance_id):
		return
	_park(instance_id)
	var pet: PalPetInstance = _manager.instances[instance_id]
	pet.set_presentation_mode(pet.profile.desktop_mode if pet.profile.visual_id == "sprite2d" else "full_body")
	pet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var window := PalDesktopWindow.new()
	window.pet = pet
	window.bridge = _bridge
	window.theme = theme
	window.visible = false
	window.force_native = true
	window.return_requested.connect(_return_pet)
	window.chat_requested.connect(_open_chat)
	window.scene_requested.connect(_open_scene)
	window.navigation_requested.connect(func(page: String, id: String) -> void:
		if _manager.instances.has(id):
			open_panel(page, _manager.instances[id].profile.profile_id)
	)
	window.settings_changed.connect(func() -> void: _refresh_roster(); _queue_save())
	window.framing_requested.connect(func(mode: String) -> void: _set_desktop_mode(pet.profile.profile_id, mode))
	window.touch_requested.connect(_touch_character)
	window.touch_regions_requested.connect(_set_touch_regions_visible)
	_desktop_windows[instance_id] = window
	_hosts[instance_id] = "desktop"
	(_idle_routines[pet.profile.profile_id] as PalIdleRoutine).active_on_host = true
	add_child(window)
	var chat := _ensure_chat_window(instance_id)
	chat.attach_panel()
	chat.bind_desktop(window)
	chat.apply_saved_mode()
	if pet.profile.profile_id == _selected_profile_id:
		_hall.show_presence("desktop", pet.profile.display_name)
	_refresh_roster()
	_queue_save()


func _return_pet(instance_id: String) -> void:
	if _manager.instances.has(instance_id):
		select_profile(_manager.instances[instance_id].profile.profile_id)


func _open_scene(instance_id: String) -> void:
	_return_pet(instance_id)


func _recall_all() -> void:
	for instance_id: String in _desktop_windows.keys():
		_park(instance_id)
	if _pet_for_profile(_selected_profile_id) != null:
		_activate_profile(_selected_profile_id)
	_refresh_roster()


func _ensure_chat_window(instance_id: String) -> PalChatWindow:
	if _chat_windows.has(instance_id):
		return _chat_windows[instance_id]
	var pet: PalPetInstance = _manager.instances[instance_id]
	var panel := PalConversationPanel.new()
	panel.service = _chat_service
	panel.performance = _performances.get(pet.profile.profile_id)
	panel.user_activity.connect(_note_user_activity)
	panel.theme = theme
	panel.navigation_requested.connect(open_panel)
	panel.reveal_requested.connect(func() -> void: _open_chat(instance_id))
	panel.speech_requested.connect(func(text: String) -> void:
		if is_instance_valid(_performances.get(pet.profile.profile_id)):
			(_performances[pet.profile.profile_id] as PalPerformanceQueue).speak_manual(text)
	)
	var window := PalChatWindow.new()
	window.panel = panel
	window.preferences = _preferences
	window.profile_id = pet.profile.profile_id
	window.bridge = _bridge
	window.theme = theme
	window.visible = false
	window.scene_requested.connect(_return_pet.bind(instance_id))
	window.read_requested.connect(func() -> void:
		_unread[pet.profile.profile_id] = 0
		_refresh_roster()
	)
	_chat_windows[instance_id] = window
	add_child(window)
	panel.open_profile(pet.profile.profile_id)
	return window


func _refresh_chat_profiles() -> void:
	var profiles: Dictionary = {}
	for pet: PalPetInstance in _manager.instances.values():
		profiles[pet.profile.profile_id] = pet.profile.display_name
	for window: PalChatWindow in _chat_windows.values():
		window.panel.set_profiles(profiles)


func _open_chat(instance_id: String) -> void:
	if not _manager.instances.has(instance_id):
		return
	var pet: PalPetInstance = _manager.instances[instance_id]
	_chat_window = _ensure_chat_window(instance_id)
	if _hosts.get(instance_id) == "desktop":
		_chat_window.open_chat(true)
	else:
		_guard_navigation(func() -> void:
			_activate_profile(pet.profile.profile_id)
			_hall.set_history_visible(true)
			_chat_window.panel.focus_input()
		)
	_unread[pet.profile.profile_id] = 0
	_refresh_roster()


func open_panel(page_id: String, profile_id: String = "", context: Dictionary = {}) -> void:
	_guard_navigation(func() -> void:
		_open_panel_now(page_id, profile_id, context)
		if _panels.is_open() and is_instance_valid(context.get("return_focus")):
			_panels.set_return_focus(context.return_focus)
	)


func _open_panel_now(page_id: String, profile_id: String, context: Dictionary) -> void:
	var pet := _pet_for_profile(profile_id)
	if page_id == "end" and _hall is PalMobileHall:
		if pet != null:
			_park(pet.instance_id)
		_hall.show_presence("empty")
		_hall.show_partners(true)
		_refresh_roster()
		return
	if page_id in ["history", "desktop_chat"]:
		if pet != null:
			_open_chat(pet.instance_id)
		return
	if page_id == "recall_all":
		_recall_all()
		return
	_show_main()
	if page_id == "appearance":
		var appearance: PalAppearancePanel = _get_page("appearance")
		_panels.open_view("appearance", "主题与外观", appearance)
		appearance.open_current()
		return
	if page_id == "settings":
		var settings: PalConnectionPanel = _get_page("settings")
		_panels.open_view("settings", "设置", settings)
		settings.open_settings(profile_id)
		return
	if page_id == "add" or (page_id == "profile" and pet == null):
		# Imports can also create a companion when the roster is empty.
		if not _session_writable or _manager.instances.size() >= PalInstanceManager.MAX_PREVIEW_INSTANCES:
			_hall.set_notice("最多同时陪伴四位伙伴。" if _session_writable else "请先恢复角色配置文件。")
			return
		var profile := PalProfile.new()
		profile.display_name = PalProfile.DEFAULT_NAME if _manager.instances.is_empty() else PalProfile.DEFAULT_NAME + " %d" % (_manager.instances.size() + 1)
		profile.visual_id = "sprite2d" if PalUi.is_mobile() else str(context.get("visual", "sprite2d"))
		profile.avatar_path = str(context.get("avatar", PalVrmLoader.DEFAULT_AVATAR))
		var editor: PalProfilePanel = _get_page("profile")
		_panels.open_view("add", "认识新伙伴", editor)
		editor.open_profile(profile)
		return
	if page_id == "packages":
		var packages: PalPackagePanel = _get_page("packages")
		_panels.open_view(page_id, "导入数据包", packages)
		packages.open_profile(profile_id)
		return
	if pet == null:
		return
	match page_id:
		"summary":
			var summary: PalSummaryPanel = _get_page("summary")
			_panels.open_view(page_id, "AI 整理 · " + pet.profile.display_name, summary)
			summary.open_profile(profile_id)
		"agent":
			if OS.get_name() == "Windows":
				var agent: PalAgentPanel = _get_page("agent")
				_panels.open_view(page_id, "Agent 任务 · " + pet.profile.display_name, agent)
				agent.open_profile(profile_id)
		"profile":
			var editor: PalProfilePanel = _get_page("profile")
			_panels.open_view(page_id, "伙伴档案 · " + pet.profile.display_name, editor)
			var capabilities: Dictionary = pet.presenter.get_capabilities() if pet.presenter != null else {}
			editor.open_profile(pet.profile, str(capabilities.get("author", "")))
			if bool(context.get("restore_persona", false)):
				editor.restore_persona()
			if context.has("avatar") and not PalUi.is_mobile():
				editor._avatar.text = str(context.avatar)
				editor._visual.select(1)
				editor._on_visual_selected(1)
				editor._avatar_row.show()
				editor._status.text = "已选择新外观，保存后应用。"
		"memory":
			var memory: PalMemoryWindow = _get_page("memory")
			_panels.open_view(page_id, "记忆 · " + pet.profile.display_name, memory)
			if context.has("message_id"):
				memory.remember_message(profile_id, str(context.session_id), str(context.message_id), str(context.text))
			else:
				memory.open_profile(profile_id)
		"world":
			var world: PalWorldWindow = _get_page("world")
			_panels.open_view(page_id, "世界设定 · " + pet.profile.display_name, world)
			world.open_profile(profile_id)
		"sessions", "new":
			var history: PalHistoryPanel = _get_page("sessions")
			_panels.open_view(page_id, ("新对话" if page_id == "new" else "历史会话") + " · " + pet.profile.display_name, history)
			history.open_profile(profile_id, page_id == "new")


func _get_page(id: String) -> Control:
	if _pages.has(id):
		return _pages[id]
	var page: Control
	match id:
		"summary":
			page = PalSummaryPanel.new()
			page.service = _chat_service
			page.persona_restore_requested.connect(func(profile_id: String) -> void: open_panel("profile", profile_id, {"restore_persona": true}))
		"packages":
			page = PalPackagePanel.new()
			page.service = _chat_service
			page.new_persona_requested.connect(_import_new_persona)
		"agent":
			page = PalAgentPanel.new()
			page.service = _chat_service
		"appearance":
			page = PalAppearancePanel.new()
			page.appearance_requested.connect(_apply_appearance)
			page.overlay_requested.connect(_apply_overlay)
			page.touch_regions_requested.connect(_set_touch_regions_visible)
		"settings":
			page = PalConnectionPanel.new()
			page.service = _chat_service
			page.close_requested.connect(func() -> void: _panels.close_requested.emit())
			page.chat_requested.connect(func() -> void:
				if _pet_for_profile(_selected_profile_id) == null:
					open_panel("add")
				else:
					open_panel("history", _selected_profile_id)
			)
		"profile":
			page = PalProfilePanel.new()
			page.service = _chat_service
			page.save_requested.connect(_save_profile)
			page.close_requested.connect(func() -> void: _panels.close_requested.emit())
			page.remove_requested.connect(_confirm_remove)
			page.summary_requested.connect(func(profile_id: String) -> void: open_panel("summary", profile_id))
			page.import_requested.connect(func(profile_id: String) -> void: open_panel("packages", profile_id))
		"memory":
			page = PalMemoryWindow.new()
			page.service = _chat_service
			page.summary_requested.connect(func(profile_id: String) -> void: open_panel("summary", profile_id))
		"world":
			page = PalWorldWindow.new()
			page.service = _chat_service
			page.summary_requested.connect(func(profile_id: String) -> void: open_panel("summary", profile_id))
		"sessions":
			page = PalHistoryPanel.new()
			page.service = _chat_service
			page.preferences = _preferences
			page.session_requested.connect(_select_session)
			page.new_requested.connect(_new_session)
			page.record_requested.connect(_open_history_record)
			page.delete_requested.connect(_delete_history)
			page.import_requested.connect(func(profile_id: String) -> void: open_panel("packages", profile_id))
	page.theme = theme
	page.hide()
	_panels.content.add_child(page)
	_pages[id] = page
	return page


func _import_new_persona(token: String, fields: Array, data: Dictionary) -> void:
	var page: PalPackagePanel = _get_page("packages")
	if not _session_writable or _manager.instances.size() >= PalInstanceManager.MAX_PREVIEW_INSTANCES:
		page.complete("最多四位伙伴，请先移除一位，或选择覆盖当前伙伴。" if _session_writable else "请先恢复角色配置文件。")
		return
	var profile := PalProfile.new()
	if "name" in fields:
		profile.display_name = str(data.display_name)
	if "persona" in fields:
		profile.persona = str(data.persona)
	var pet := _add_pet("sprite2d", profile, false)
	if pet == null:
		page.complete("未能创建伙伴。")
		return
	var error: String = _chat_service.call("ApplyPersonaPackage", pet.profile.profile_id, token, JSON.stringify(fields))
	if not error.is_empty():
		_remove_pet(pet.instance_id)
		page.complete(error)
		return
	_on_chat_changed(pet.profile.profile_id)
	var saved := _save_session()
	page.complete("")
	if saved != OK:
		page._notice.text = "伙伴已导入，外观列表保存失败，请检查存储空间和目录权限。"
	_refresh_roster()


func _set_touch_regions_visible(value: bool) -> void:
	PalUi.show_touch_regions = value
	get_tree().call_group("pal_touch_hosts", "refresh_touch_regions")
	get_tree().call_group("pal_touch_regions", "refresh")
	if _pages.has("appearance"):
		_pages.appearance.sync_touch_regions()
	if _preferences.put("interaction", "show_touch_regions", value) != OK:
		_hall.set_notice("触控范围显示已更新，设置暂未保存。")


func _apply_appearance(mode: String, color: Color) -> void:
	PalUi.apply_appearance(self, mode, color)
	get_tree().call_group("pal_bubbles", "refresh_overlay")
	get_tree().call_group("pal_overlay_hosts", "refresh_overlay")
	for chat: PalChatWindow in _chat_windows.values():
		chat.panel.refresh_theme()
		if is_instance_valid(chat._tail):
			chat._tail.queue_redraw()
	_refresh_roster()
	var error := _preferences.put_values("appearance", {"mode": PalUi.appearance_mode, "accent": PalUi.theme_color.to_html(false)})
	if _pages.has("appearance"):
		(_pages.appearance as PalAppearancePanel)._status.text = "已应用并保存。" if error == OK else "已应用，但保存失败，请检查目录权限。"


func _apply_overlay(opacity: float, dialogue: bool, description: bool, autoplay: bool) -> void:
	PalUi.overlay_opacity = clampf(opacity, 0.1, 0.5)
	PalUi.dialogue_bubbles = dialogue
	PalUi.description_bubbles = description
	PalUi.dialogue_autoplay = autoplay
	for chat: PalChatWindow in _chat_windows.values():
		chat.panel.refresh_bubble_preferences()
	get_tree().call_group("pal_bubbles", "refresh_overlay")
	get_tree().call_group("pal_overlay_hosts", "refresh_overlay")
	var error := _preferences.put_values("overlay", {"opacity": PalUi.overlay_opacity, "dialogue": dialogue, "description": description, "autoplay": autoplay})
	if _pages.has("appearance"):
		_pages.appearance._status.text = "浮层设置已保存。" if error == OK else "设置已应用，保存失败。"


func _guard_navigation(action: Callable) -> void:
	if _saving_profile or _panels.is_confirming():
		return
	if _panels.is_dirty():
		_panels.confirm("放弃未保存的编辑", "当前面板的修改尚未保存。", "放弃并继续", func() -> void:
			_panels.hide_panel()
			action.call()
		)
	else:
		_panels.hide_panel()
		action.call()


func _close_panel() -> void:
	_guard_navigation(_mark_active_read)


func _run_session_action(profile_id: String, description: String, action: Callable) -> void:
	var data: Dictionary = JSON.parse_string(_chat_service.call("GetSnapshot", profile_id))
	if data.is_empty():
		return
	if bool(data.busy):
		var session_id: String = data.session_id
		_panels.confirm("停止回复并继续", "伙伴正在回复。继续将停止这次回复，然后" + description + "。", "停止并继续", func() -> void:
			if _chat_service.call("GetActiveSessionId", profile_id) != session_id:
				_hall.set_notice("对话已变化，请重新操作。")
				return
			_chat_service.call("StopReply", profile_id)
			action.call()
		)
	else:
		action.call()


func _select_session(profile_id: String, session_id: String) -> void:
	_run_session_action(profile_id, "切换历史对话", func() -> void:
		var error: String = _chat_service.call("SelectConversation", profile_id, session_id)
		_finish_session_action(profile_id, error)
	)


func _open_history_record(profile_id: String, session_id: String) -> String:
	var history: PalHistoryPanel = _get_page("sessions")
	if _chat_service.call("GetActiveSessionId", profile_id) == session_id:
		var error: String = _chat_service.call("SaveConversation", profile_id)
		if not error.is_empty():
			history._notice.text = error
			return ""
	var entry: Dictionary = JSON.parse_string(_chat_service.call("GetHistoryRecord", profile_id, session_id))
	var path := str(entry.get("path", ""))
	if not path.is_empty() and FileAccess.file_exists(path):
		if PalUi.is_mobile():
			if bool(entry.get("has_images", false)):
				PalPackageFiles.export_package(self, _chat_service, profile_id, "conversations", session_id, {}, false, false, func(message: String) -> void: history._notice.text = message)
			else:
				PalMobileFiles.export_record(self, path, func(message: String) -> void: history._notice.text = message)
		elif DisplayServer.get_name() != "headless" and OS.shell_open(path) != OK:
			history._notice.text = "未能打开记录文件，请检查默认打开方式。"
			return ""
		return path
	history._notice.text = str(entry.get("error", "未找到这段记录，原会话保持不变。"))
	return ""


func _delete_history(profile_id: String, session_id: String, title: String) -> void:
	var message := "删除「%s」？\n\n这会删除该会话的聊天记录，无法撤销。手动编辑的记忆和世界设定会保留。" % title
	if _chat_service.call("GetActiveSessionId", profile_id) == session_id:
		message += "\n\n这是当前会话，删除后将开始空白对话，未发送草稿也会清除。"
	_panels.confirm("删除会话", message, "删除会话", func() -> void:
		var request_id := Crypto.new().generate_random_bytes(16).hex_encode()
		_history_deletes[request_id] = {"profile_id": profile_id, "session_id": session_id}
		(_get_page("sessions") as PalHistoryPanel).begin_delete(profile_id)
		_chat_service.call("DeleteHistory", profile_id, request_id, session_id)
	)


func _on_history_deleted(profile_id: String, request_id: String, result: String) -> void:
	if not _history_deletes.has(request_id):
		return
	var request: Dictionary = _history_deletes[request_id]
	_history_deletes.erase(request_id)
	var parsed: Variant = JSON.parse_string(result)
	var data: Dictionary = parsed if parsed is Dictionary else {"error": "无法读取删除结果，请刷新历史记录。"}
	if bool(data.get("deleted", false)):
		for window: PalChatWindow in _chat_windows.values():
			window.panel.forget_session_view(profile_id, str(request.session_id))
		_on_chat_changed(profile_id)
		_save_session()
	(_get_page("sessions") as PalHistoryPanel).complete_delete(profile_id, data)


func _new_session(profile_id: String) -> void:
	_run_session_action(profile_id, "开始新对话", func() -> void:
		var error: String = _chat_service.call("NewConversation", profile_id)
		_finish_session_action(profile_id, error)
	)


func _finish_session_action(profile_id: String, error: String) -> void:
	if not error.is_empty():
		(_get_page("sessions") as PalHistoryPanel)._notice.text = error
		return
	_panels.hide_panel()
	var pet := _pet_for_profile(profile_id)
	if pet != null:
		var conversation := _ensure_chat_window(pet.instance_id).panel
		conversation._refresh()
		_open_chat(pet.instance_id)


func _locate_source(profile_id: String, session_id: String, message_id: String) -> void:
	_guard_navigation(func() -> void:
		_run_session_action(profile_id, "定位记忆来源", func() -> void:
			var pet := _pet_for_profile(profile_id)
			if pet != null:
				_ensure_chat_window(pet.instance_id).panel._show_memory_source(profile_id, session_id, message_id)
		)
	)


func _save_profile(profile_id: String, data: Dictionary) -> void:
	if _saving_profile:
		return
	var editor: PalProfilePanel = _get_page("profile")
	if PalUi.is_mobile() and str(data.visual) != "sprite2d":
		editor.complete("安卓版仅支持 2D 立绘。")
		return
	if not _session_writable:
		editor.complete("请先恢复角色配置文件。")
		return
	_saving_profile = true
	await get_tree().process_frame
	await get_tree().process_frame
	var profile: PalProfile
	var pet := _pet_for_profile(profile_id)
	if profile_id.is_empty():
		profile = PalProfile.new()
		profile.display_name = str(data.name)
		profile.visual_id = str(data.visual)
		profile.avatar_path = str(data.avatar)
		profile.persona = str(data.persona).strip_edges()
		profile.adult_mode = bool(data.adult_mode)
		profile.look_at_mouse = bool(data.look_at_mouse)
		profile.wander = bool(data.wander)
		profile.desktop_scale = float(data.scale)
		profile.render_settings = PalRenderSettings.normalize(data.get("render_settings"))
		pet = _add_pet(profile.visual_id, profile, false)
		if pet == null:
			_saving_profile = false
			editor.complete("未能添加伙伴。请检查模型文件和伙伴数量，现有伙伴保持原样。")
			return
	else:
		if pet == null:
			_saving_profile = false
			editor.complete("伙伴已不存在。")
			return
		profile = pet.profile
		var candidate: PalPresenter
		if str(data.visual) != profile.visual_id or (str(data.visual) == "vrm3d" and str(data.avatar) != profile.avatar_path):
			var proposed := profile.duplicate() as PalProfile
			proposed.avatar_path = str(data.avatar)
			proposed.visual_id = str(data.visual)
			candidate = (PalPetInstance.PRESENTERS[str(data.visual)] as PackedScene).instantiate() as PalPresenter
			var load_error := candidate.prepare(proposed)
			if not load_error.is_empty():
				candidate.free()
				_saving_profile = false
				editor.complete(load_error + " 原外观已保留。")
				return
		var profile_error: String = _chat_service.call("SaveProfileSettings", profile_id, str(data.name), bool(data.adult_mode),
			str(data.persona), bool(data.get("update_persona", true)), str(data.get("persona_baseline", profile.persona)))
		if not profile_error.is_empty():
			if candidate != null:
				candidate.free()
			_saving_profile = false
			editor.complete(profile_error)
			return
		profile.display_name = str(data.name)
		var role: Dictionary = JSON.parse_string(_chat_service.call("GetRole", profile_id))
		profile.persona = str(role.get("profile", {}).get("persona", profile.persona))
		if profile.adult_mode != bool(data.adult_mode):
			_pending_touches.erase(profile_id)
		pet.set_adult_mode(bool(data.adult_mode))
		profile.look_at_mouse = bool(data.look_at_mouse)
		profile.wander = bool(data.wander)
		profile.render_settings = PalRenderSettings.normalize(data.get("render_settings", profile.render_settings))
		if candidate != null:
			pet.install_presenter(candidate, str(data.visual), str(data.avatar))
		else:
			pet.apply_render_settings()
		profile.desktop_scale = float(data.scale)
		if _desktop_windows.has(pet.instance_id):
			_desktop_windows[pet.instance_id].resize_pet(profile.desktop_scale)
			_desktop_windows[pet.instance_id].title = profile.display_name + " · GD Pal"
	_saving_profile = false
	_refresh_chat_profiles()
	_ensure_chat_window(pet.instance_id).panel._refresh()
	var save_error := _save_session()
	if profile_id.is_empty():
		editor.mark_created(pet.profile.profile_id)
	editor.complete("" if save_error == OK else "档案已应用，但本地保存失败，请重试。")
	_refresh_roster()
	if profile_id.is_empty():
		if save_error == OK and not editor.is_dirty():
			_panels.hide_panel()
		_activate_profile(pet.profile.profile_id, not _panels.is_open())


func _confirm_remove(profile_id: String) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null:
		return
	_panels.confirm("移除伙伴", "将「" + pet.profile.display_name + "」从伙伴列表移除，并停止它的回复。本地聊天文件会保留。", "确认移除", func() -> void:
		_panels.hide_panel()
		_remove_pet(pet.instance_id)
	)


func _remove_pet(instance_id: String) -> void:
	if not _manager.instances.has(instance_id):
		return
	var pet: PalPetInstance = _manager.instances[instance_id]
	var was_selected := pet.profile.profile_id == _selected_profile_id
	_park(instance_id)
	var window: PalChatWindow = _chat_windows[instance_id]
	if window == _chat_window:
		_chat_window = null
	_chat_windows.erase(instance_id)
	window.queue_free()
	_chat_service.call("RemoveProfile", pet.profile.profile_id)
	_idle_routines.erase(pet.profile.profile_id)
	_performances.erase(pet.profile.profile_id)
	_pending_touches.erase(pet.profile.profile_id)
	_last_touch.erase(pet.profile.profile_id)
	_unread.erase(pet.profile.profile_id)
	_views[instance_id].viewport.queue_free()
	_views.erase(instance_id)
	_hosts.erase(instance_id)
	_manager.remove_pet(instance_id)
	if was_selected:
		_selected_profile_id = ""
		if not _manager.instances.is_empty():
			_activate_profile(_manager.instances.values()[0].profile.profile_id)
		else:
			_hall.show_presence("empty")
	_refresh_chat_profiles()
	_refresh_roster()
	_save_ui_selection()
	_queue_save()


func _on_files_dropped(paths: PackedStringArray) -> void:
	if PalUi.is_mobile():
		return
	for path: String in paths:
		if path.get_extension().to_lower() != "vrm":
			continue
		var selected := _selected_profile_id
		_guard_navigation(func() -> void:
			if _pet_for_profile(selected) == null:
				_open_panel_now("add", "", {"avatar": path})
				return
			var add_new := func() -> void: _open_panel_now("add", "", {"avatar": path})
			var can_add := _manager.instances.size() < PalInstanceManager.MAX_PREVIEW_INSTANCES
			_panels.confirm("导入 VRM 外观", "已选择 " + path.get_file() + "。请选择把它用于哪位伙伴，随后在档案中保存。", "替换当前伙伴",
				func() -> void: _open_panel_now("profile", selected, {"avatar": path}),
				"添加新伙伴" if can_add else "", add_new)
		)
		return
	_hall.set_notice("请拖入 .vrm 角色文件。")


func _open_api_settings() -> void:
	open_panel("settings")


func _refresh_roster() -> void:
	if _hall == null:
		return
	var entries: Array = []
	for pet: PalPetInstance in _manager.instances.values():
		var status: String = {"hall": "通话陪伴中", "desktop": "在桌面", "parked": "等待相见"}.get(_hosts.get(pet.instance_id, "parked"))
		_sync_model_wardrobe(pet)
		var unread := int(_unread.get(pet.profile.profile_id, 0))
		entries.append({"id": pet.profile.profile_id, "name": pet.profile.display_name, "status": status, "unread": unread,
			"portrait": pet.presenter.get_portrait_texture() if pet.presenter != null else null})
		if _desktop_windows.has(pet.instance_id):
			_desktop_windows[pet.instance_id].set_unread_count(unread)
	_hall.update_roster(entries, _selected_profile_id, _session_writable and entries.size() < PalInstanceManager.MAX_PREVIEW_INSTANCES)
	var selected_pet := _pet_for_profile(_selected_profile_id)
	_hall.set_character_pet(selected_pet)
	_hall.motion_actions = selected_pet.behavior.motion_actions if selected_pet != null else PackedStringArray()
	_hall.motion_definitions = selected_pet.behavior.action_definitions if selected_pet != null else {}
	_hall.set_character_display(selected_pet.profile.visual_id if selected_pet != null else "sprite2d", selected_pet.profile.portrait_framing if selected_pet != null else "call", selected_pet != null)
	if not PalUi.is_mobile():
		_hall.set_desktop_preferences(selected_pet.profile if selected_pet != null else null)
		var role: Dictionary = JSON.parse_string(_chat_service.call("GetRole", _selected_profile_id)) if selected_pet != null else {}
		_hall.set_voice_enabled(bool(role.get("profile", {}).get("auto_speak", false)))


func _change_visual_from_stage(visual: String) -> void:
	var profile_id := _selected_profile_id
	_guard_navigation(func() -> void:
		var pet := _pet_for_profile(profile_id)
		if pet == null or visual not in ["sprite2d", "vrm3d"]:
			return
		if PalUi.is_mobile() and visual != "sprite2d":
			return
		if pet.profile.visual_id == visual:
			return
		if not pet.switch_visual(visual):
			_hall.set_notice(pet.last_error + " 当前外观已保留。")
			_refresh_roster()
	)


func _on_pet_visual_changed(pet: PalPetInstance) -> void:
	if _hosts.get(pet.instance_id) == "hall":
		pet.set_presentation_mode(pet.profile.portrait_framing if pet.profile.visual_id == "sprite2d" else "call")
	_refresh_roster()
	_queue_save()


func _set_character_framing(profile_id: String, mode: String) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null or pet.profile.visual_id != "sprite2d" or mode not in ["full_body", "call"]:
		return
	pet.profile.portrait_framing = mode
	if _hosts.get(pet.instance_id) == "hall":
		pet.set_presentation_mode(mode)
	_refresh_roster()
	_queue_save()


func _set_desktop_mode(profile_id: String, mode: String) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null or mode not in ["full_body", "call"]:
		return
	pet.profile.desktop_mode = mode
	if _desktop_windows.has(pet.instance_id):
		(_desktop_windows[pet.instance_id] as PalDesktopWindow).refresh_presentation()
	_refresh_roster()
	_queue_save()


func _sync_model_wardrobe(pet: PalPetInstance) -> void:
	var outfits: Dictionary = pet.presenter.get_capabilities().get("outfits", {}) if pet.presenter != null else {}
	_chat_service.call("SetOutfitState", pet.profile.profile_id, pet.profile.outfit, PackedStringArray(outfits.keys()), pet.profile.allow_model_outfit, pet.profile.outfit_override)


func _toggle_voice() -> void:
	var pet := _pet_for_profile(_selected_profile_id)
	if pet == null:
		return
	var role: Dictionary = JSON.parse_string(_chat_service.call("GetRole", _selected_profile_id))
	var settings: Dictionary = role.get("profile", {})
	if settings.is_empty():
		_hall.set_notice("请先完成伙伴档案设置。")
		return
	settings.auto_speak = not bool(settings.get("auto_speak", false))
	var error: String = _chat_service.call("SetAutoSpeak", _selected_profile_id, bool(settings.auto_speak))
	if not error.is_empty():
		_hall.set_notice(error)
		return
	if not bool(settings.auto_speak) and is_instance_valid(_performances.get(_selected_profile_id)):
		(_performances[_selected_profile_id] as PalPerformanceQueue).stop_speech()
	_hall.set_voice_enabled(bool(settings.auto_speak))


func _set_desktop_preference(key: String, value: Variant) -> void:
	var pet := _pet_for_profile(_selected_profile_id)
	if pet == null:
		return
	match key:
		"desktop_mode":
			_set_desktop_mode(pet.profile.profile_id, str(value))
			return
		"edge_posture":
			pet.profile.edge_posture = "prone" if str(value) == "prone" else "sit"
			if _desktop_windows.has(pet.instance_id) and pet.profile.desktop_mode == "full_body":
				(_desktop_windows[pet.instance_id] as PalDesktopWindow)._play_portrait_or_motion(pet.profile.edge_posture)
		"allow_model_outfit", "outfit_override":
			pet.set_outfit_control(key, bool(value))
		"look_at_mouse":
			pet.profile.look_at_mouse = bool(value)
		"wander":
			pet.profile.wander = bool(value)
		"desktop_scale":
			pet.profile.desktop_scale = clampf(float(value), 0.5, 2.0)
			if _desktop_windows.has(pet.instance_id):
				(_desktop_windows[pet.instance_id] as PalDesktopWindow).resize_pet(pet.profile.desktop_scale)
		_:
			return
	_queue_save()


func _set_idle_actions_enabled(value: bool) -> void:
	_idle_actions_enabled = value
	for routine: PalIdleRoutine in _idle_routines.values():
		routine.enabled = value
		if not value:
			routine.note_activity()
	_preferences.put("companion", "idle_actions", value)


func _note_user_activity(profile_id: String) -> void:
	if _idle_routines.has(profile_id):
		(_idle_routines[profile_id] as PalIdleRoutine).note_activity()


func _touch_character(instance_id: String, region: String) -> void:
	if not _manager.instances.has(instance_id) or region not in ["upper", "middle", "lower"]:
		return
	var pet: PalPetInstance = _manager.instances[instance_id]
	var profile_id := pet.profile.profile_id
	var now := Time.get_ticks_msec()
	if now - int(_last_touch.get(profile_id, -2000)) < 1500:
		return
	_last_touch[profile_id] = now
	_note_user_activity(profile_id)
	var contact := "轻轻摸了摸你的头" if region == "upper" else ("轻轻拍了拍你的肩膀" if region == "middle" else ("轻轻碰了碰你的手" if pet.presentation_mode == "call" else "轻轻碰了碰你的裙摆"))
	var feedback := "head_pat" if region == "upper" else ("happy" if region == "middle" else "shy")
	if pet.profile.adult_mode:
		contact = "触碰了你的" + str({"upper": "嘴唇", "middle": "胸部", "lower": "下体私密处"}[region])
		feedback = "shy"
	var attached := _desktop_windows.has(instance_id) and not (_desktop_windows[instance_id] as PalDesktopWindow)._attachment.is_empty()
	if attached:
		pet.presenter.set_expression("happy")
	else:
		var available: PackedStringArray = pet.presenter.get_capabilities().get("actions", PackedStringArray())
		pet.behavior.request_action(feedback if feedback in available else "head_pat", "touch")
	var snapshot: Dictionary = JSON.parse_string(_chat_service.call("GetSnapshot", profile_id))
	if not bool(snapshot.get("has_key", false)):
		_touch_notice(pet, "请先在连接设置中接入模型，角色才能回应触摸。")
		return
	var messages: Array = snapshot.get("messages", [])
	var turn_id := str(messages[-1].get("turn_id", "")) if not messages.is_empty() else ""
	_pending_touches[profile_id] = {"text": "（" + contact + "。）", "session": str(snapshot.get("session_id", "")), "turn": turn_id}
	_flush_touches.call_deferred()


func _flush_touches() -> void:
	for profile_id: String in _pending_touches.keys():
		var pending: Dictionary = _pending_touches[profile_id]
		var pet := _pet_for_profile(profile_id)
		if pet == null:
			_pending_touches.erase(profile_id)
			continue
		var snapshot: Dictionary = JSON.parse_string(_chat_service.call("GetSnapshot", profile_id))
		var messages: Array = snapshot.get("messages", [])
		var turn_id := str(messages[-1].get("turn_id", "")) if not messages.is_empty() else ""
		if str(snapshot.get("session_id", "")) != str(pending.session) or turn_id != str(pending.turn):
			_pending_touches.erase(profile_id)
			continue
		if bool(snapshot.get("busy", false)):
			continue
		_pending_touches.erase(profile_id)
		var result: Variant = _chat_service.call("SendMessage", profile_id, str(pending.text))
		var error := str(result) if result is String else "这次触摸暂未得到回应，请稍后再试。"
		if not error.is_empty():
			_touch_notice(pet, error)
		_ensure_chat_window(pet.instance_id).panel._refresh()


func _touch_notice(pet: PalPetInstance, message: String) -> void:
	if _desktop_windows.has(pet.instance_id):
		(_desktop_windows[pet.instance_id] as PalDesktopWindow).say(message)
	else:
		_hall.set_notice(message)


func _on_hall_view_changed(_view: String) -> void:
	_sync_hall_rendering()
	_mark_active_read()


func _sync_hall_rendering() -> void:
	var pet := _pet_for_profile(_selected_profile_id)
	if pet == null or _hosts.get(pet.instance_id) != "hall":
		return
	var showing := not _main_hidden and get_window().mode != Window.MODE_MINIMIZED and _hall.current_view == "call"
	pet.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED


func _refresh_connection() -> void:
	var settings: Dictionary = JSON.parse_string(_chat_service.call("GetSettings"))
	_hall.set_connection(bool(settings.get("has_key", false)), str(settings.get("connection_state", "configured")))


func _mark_active_read() -> void:
	if _panels.is_open() or _panels.is_confirming() or get_window().mode == Window.MODE_MINIMIZED:
		return
	if _main_hidden or (not PalUi.is_mobile() and not _hall.is_reading_conversation()):
		return
	var pet := _pet_for_profile(_selected_profile_id)
	if pet != null and _hosts.get(pet.instance_id) == "hall":
		_unread[pet.profile.profile_id] = 0
		var chat: PalChatWindow = _chat_windows[pet.instance_id]
		chat.unread = 0
		chat._refresh_compact()
		_refresh_roster()


func _on_chat_reply(profile_id: String, _text: String) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null:
		return
	var focused := DisplayServer.get_name() == "headless" or get_window().has_focus()
	var reading: bool = _hosts.get(pet.instance_id) == "hall" and not _panels.is_open() and not _panels.is_confirming() and get_window().mode != Window.MODE_MINIMIZED and focused
	if not PalUi.is_mobile():
		reading = reading and not _main_hidden and _hall.is_reading_conversation()
	if _hosts.get(pet.instance_id) == "desktop":
		var chat: PalChatWindow = _chat_windows[pet.instance_id]
		reading = chat.visible and not chat.collapsed and (DisplayServer.get_name() == "headless" or chat.has_focus())
	if not reading:
		_unread[profile_id] = int(_unread.get(profile_id, 0)) + 1
	_refresh_roster()


func _on_chat_changed(profile_id: String) -> void:
	var pet := _pet_for_profile(profile_id)
	if pet == null:
		return
	var snapshot: Dictionary = JSON.parse_string(_chat_service.call("GetSnapshot", profile_id))
	if snapshot.is_empty():
		return
	if _idle_routines.has(profile_id):
		var messages: Array = snapshot.get("messages", [])
		var awaiting_display := not messages.is_empty() and bool(messages[-1].get("display_waiting", false))
		(_idle_routines[profile_id] as PalIdleRoutine).set_chat_busy(bool(snapshot.get("busy", false)) or awaiting_display)
	var changed := false
	for field: Array in [["persona", "persona"], ["display_name", "display_name"]]:
		var value: Variant = snapshot.get(field[1], pet.profile.get(field[0]))
		if pet.profile.get(field[0]) != value:
			pet.profile.set(field[0], value)
			changed = true
	if changed:
		_queue_save()
		_refresh_chat_profiles()
		_refresh_roster()


func _queue_save() -> void:
	if not _restoring and _save_timer != null and _persist_session and _session_writable:
		_save_timer.start()


func _save_session() -> Error:
	if not _persist_session or not _session_writable:
		return OK
	var profiles: Array[PalProfile] = []
	for pet: PalPetInstance in _manager.instances.values():
		profiles.append(pet.profile)
	var error := PalSessionStore.save_profiles(profiles, _session_path)
	if error != OK:
		_hall.set_notice("本次设置未能保存（%d），请检查磁盘空间和目录权限。" % error)
	return error


func _load_ui_selection() -> String:
	if not _persist_ui:
		return ""
	return str(_preferences.get_value("ui", "active_profile_id", ""))


func _save_ui_selection() -> void:
	if _restoring or not _persist_ui:
		return
	if _preferences.put("ui", "active_profile_id", _selected_profile_id) != OK:
		_hall.set_notice("伙伴选择暂未保存，下次启动将打开第一位伙伴。")


func _show_main() -> void:
	if get_window().mode == Window.MODE_MINIMIZED:
		get_window().mode = Window.MODE_WINDOWED
	if DisplayServer.get_name() != "headless":
		if _main_hidden and not _bridge.call("SetMainWindowVisible", true):
			return
		get_window().grab_focus()
	_main_hidden = false
	var pet := _pet_for_profile(_selected_profile_id)
	if pet != null and _hosts.get(pet.instance_id) == "hall":
		if PalUi.is_mobile():
			pet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		else:
			_sync_hall_rendering()


func _hide_main() -> void:
	if _main_hidden or not is_instance_valid(_tray) or not _tray.is_available():
		return
	if not _bridge.call("SetMainWindowVisible", false):
		_hall.set_notice("暂时无法收起大厅，请使用最小化或托盘菜单退出。")
		return
	_main_hidden = true
	var pet := _pet_for_profile(_selected_profile_id)
	if pet != null and _hosts.get(pet.instance_id) == "hall":
		pet.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _close_main() -> void:
	if is_instance_valid(_tray) and _tray.is_available():
		_hide_main()
	else:
		_quit_requested()


func _process(delta: float) -> void:
	_touch_poll -= delta
	if _touch_poll <= 0:
		_touch_poll = 0.25
		if not _pending_touches.is_empty():
			_flush_touches()
	_scale_time -= delta
	if _scale_time <= 0:
		_scale_time = 0.5
		PalUi.sync_window_scale(get_window())
		if not PalUi.is_mobile():
			_sync_hall_rendering()
	var pet := _pet_for_profile(_selected_profile_id)
	if PalUi.is_mobile() and pet != null and _hosts.get(pet.instance_id) == "hall":
		pet.render_target_update_mode = SubViewport.UPDATE_DISABLED if _mobile_paused or _panels.is_open() else SubViewport.UPDATE_ALWAYS
	if not PalUi.is_mobile() and _hall.current_view == "call" and not _main_hidden and pet != null and _hosts.get(pet.instance_id) == "hall" and not _panels.is_open() and not _panels.is_confirming():
		pet.set_look_target((_hall.surface.get_local_mouse_position() - _hall.surface.size * 0.5) / (_hall.surface.size * 0.5).max(Vector2.ONE))


func _notification(what: int) -> void:
	if not PalUi.is_mobile() or not is_node_ready():
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_mobile_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		_mobile_paused = true
		for window: PalChatWindow in _chat_windows.values():
			window.panel.save_view_state()
		for pet: PalPetInstance in _manager.instances.values():
			_chat_service.call("SaveConversation", pet.profile.profile_id)
			pet.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_save_session()
		Engine.max_fps = 5
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_mobile_paused = false
		Engine.max_fps = 60
		var pet := _pet_for_profile(_selected_profile_id)
		if pet != null and _hosts.get(pet.instance_id) == "hall":
			pet.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _unhandled_key_input(event: InputEvent) -> void:
	if PalUi.is_mobile() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_mobile_back()
		get_viewport().set_input_as_handled()


func _mobile_back() -> void:
	for child: PopupMenu in find_children("*", "PopupMenu", true, false):
		if child.visible:
			child.hide()
			return
	var focus := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focus) and focus.has_method("has_ime_text") and focus.call("has_ime_text"):
		DisplayServer.virtual_keyboard_hide()
		return
	if PalUi.keyboard_height() > 0:
		DisplayServer.virtual_keyboard_hide()
		if is_instance_valid(focus):
			focus.release_focus()
		return
	if _panels.is_confirming():
		_panels.cancel_confirmation()
	elif _panels.is_open():
		if _panels.active_view.has_method("mobile_back") and _panels.active_view.call("mobile_back"):
			return
		_close_panel()
	elif not (_hall as PalMobileHall).back():
		_hall.show_partners(true)


func _quit_requested() -> void:
	_show_main()
	if _saving_profile or _panels.is_confirming():
		return
	var needs_confirmation := _panels.is_dirty() or bool(_chat_service.call("HasBackgroundWork"))
	for window: PalChatWindow in _chat_windows.values():
		var snapshot := window.panel._snapshot()
		needs_confirmation = needs_confirmation or bool(snapshot.get("busy", false)) or not window.panel._input.text.is_empty()
		for draft: String in window.panel._drafts.values():
			needs_confirmation = needs_confirmation or not draft.is_empty()
	if needs_confirmation:
		_panels.confirm("退出 GD Pal", "仍有未完成的回复、AI 整理、数据包操作、Agent 任务或未保存编辑。退出会停止处理；已保存草稿和任务记录保留，未发送内容和未保存编辑会放弃。", "退出应用", _finish_quit)
	else:
		_finish_quit()


func _finish_quit() -> void:
	for pet: PalPetInstance in _manager.instances.values():
		_on_chat_changed(pet.profile.profile_id)
	_chat_service.call("Shutdown")
	_save_session()
	get_tree().quit()
