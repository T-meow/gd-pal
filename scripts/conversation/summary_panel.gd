class_name PalSummaryPanel
extends VBoxContainer

signal persona_restore_requested(profile_id: String)

var service: Node
var _profile_id := ""
var _request := ""
var _state: Dictionary = {}
var _selected: Dictionary = {}
var _messages: Array = []
var _sessions: OptionButton
var _requirements: TextEdit
var _original: TextEdit
var _sources: VBoxContainer
var _entries: VBoxContainer
var _entry_views: Dictionary = {}
var _results: ScrollContainer
var _tabs: TabContainer
var _notice: Label
var _generate: Button
var _stop: Button
var _response: Button
var _apply: Button
var _finish: Button
var _restore_persona: Button
var _consolidate: CheckButton
var _apply_merge: Button
var _merge_backup: Button
var _merge_page: ScrollContainer
var _merge_body: VBoxContainer
var _merge_editors: Dictionary = {}
var _source_count: Label
var _save_timer: Timer
var _loading := false
var _baseline := ""
const TARGET_NAMES := {"memory": "长期记忆", "active_memory": "活跃记忆", "persona": "人设", "world": "世界设定"}


func _ready() -> void:
	set_meta("self_scrolling", true)
	set_meta("preferred_width", 1120)
	set_meta("preferred_height", 820)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	PalUi.hint("模型自动分析并归类为候选条目，由你选择是否加入现有设定。", self)
	PalUi.label("整理要求（可选）", self, 15)
	_requirements = _text_box(self, "例如：提炼用户习惯、重要经历和伙伴的自我认知，只整理已确定的信息。", 60)
	_requirements.size_flags_vertical = Control.SIZE_FILL
	_consolidate = CheckButton.new()
	_consolidate.text = "同时整理已有记忆文件（去重与合并）"
	add_child(_consolidate)
	PalUi.hint("开启后，在提取各段对话的新信息后，再统一合并长期记忆、活跃记忆和世界设定。也可不选聊天，只整理已有文件；先审阅合并草稿，再应用。此选项影响下一次生成。", self)
	_consolidate.toggled.connect(func(_enabled: bool) -> void: _queue_save())
	_tabs = TabContainer.new()
	_tabs.use_hidden_tabs_for_min_size = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.y = 220 if PalUi.is_mobile() else 320
	add_child(_tabs)
	var material := VBoxContainer.new()
	material.name = "聊天素材"
	_tabs.add_child(material)
	var filters: BoxContainer = VBoxContainer.new() if PalUi.is_mobile() else HBoxContainer.new()
	material.add_child(filters)
	_sessions = OptionButton.new()
	_sessions.fit_to_longest_item = false
	_sessions.custom_minimum_size.x = 140
	_sessions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(_sessions)
	_sessions.item_selected.connect(func(_index: int) -> void: _load_messages())
	PalUi.button("全选本段", filters, func() -> void: _select_sources(true))
	PalUi.button("清空本段", filters, func() -> void: _select_sources(false))
	_source_count = PalUi.hint("切换会话后保留勾选，可同时选择多段对话。", material)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	material.add_child(scroll)
	_sources = VBoxContainer.new()
	_sources.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_sources)
	var original_page := VBoxContainer.new()
	original_page.name = "原文"
	_tabs.add_child(original_page)
	PalUi.hint("所选聊天原文与当前已有设定，可在加入条目前核对。", original_page)
	_original = _text_box(original_page, "选择聊天素材后在这里阅读原文。", 180)
	_original.editable = false
	var result_page := VBoxContainer.new()
	result_page.name = "整理结果"
	_tabs.add_child(result_page)
	var selection := HFlowContainer.new()
	result_page.add_child(selection)
	PalUi.button("勾选全部待选条目", selection, func() -> void: _select_entries(true))
	PalUi.button("清除勾选", selection, func() -> void: _select_entries(false))
	_results = ScrollContainer.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	result_page.add_child(_results)
	_entries = VBoxContainer.new()
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries.add_theme_constant_override("separation", 12)
	_results.add_child(_entries)
	_merge_page = ScrollContainer.new()
	_merge_page.name = "合并草稿"
	_merge_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_merge_page.follow_focus = true
	_tabs.add_child(_merge_page)
	_merge_body = VBoxContainer.new()
	_merge_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_merge_body.add_theme_constant_override("separation", 12)
	_merge_page.add_child(_merge_body)
	_tabs.set_tab_hidden(3, true)
	var actions := HFlowContainer.new()
	add_child(actions)
	_generate = PalUi.button("生成追加条目", actions, _start, true)
	_stop = PalUi.button("停止生成", actions, func() -> void: service.call("CancelSummary", _profile_id))
	_apply = PalUi.button("加入勾选条目", actions, _accept_selected)
	_apply_merge = PalUi.button("应用合并稿", actions, _accept_merge, true)
	_apply_merge.tooltip_text = "保存当前三份合并稿，应用前自动备份原文件。"
	_merge_backup = PalUi.button("打开合并前备份", actions, _open_merge_backup)
	_finish = PalUi.button("结束并清空", actions, _finish_review)
	_finish.tooltip_text = "保留已加入的内容，清空本次候选和素材勾选，开始下一次整理。"
	_restore_persona = PalUi.button("还原人设", actions, func() -> void:
		if _save_review():
			persona_restore_requested.emit(_profile_id))
	_restore_persona.tooltip_text = "将 AI 追加前的手写人设放回编辑框，保存后生效。"
	_response = PalUi.button("查看返回值", actions, _view_response)
	_response.hide()
	_notice = PalUi.hint("", self)
	_notice.max_lines_visible = 2
	_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(_save_review)
	add_child(_save_timer)
	_requirements.text_changed.connect(_queue_save)
	_tabs.tab_changed.connect(func(index: int) -> void:
		if index == 1 and not _profile_id.is_empty():
			_refresh_original())
	service.connect("SummaryChanged", _on_result)


func _text_box(parent: Node, placeholder: String, height: int) -> TextEdit:
	var editor := TextEdit.new()
	editor.placeholder_text = placeholder
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.custom_minimum_size = Vector2(160, height)
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(editor)
	return editor


func open_profile(profile_id: String) -> void:
	_profile_id = profile_id
	_request = ""
	_merge_page.scroll_vertical = 0
	var draft: Dictionary = JSON.parse_string(service.call("GetSummaryDraft", profile_id))
	var completed: bool = draft.get("status") != "running" and (not draft.get("entries", []).is_empty() or draft.get("merge_status") == "applied")
	for entry: Dictionary in draft.get("entries", []):
		if entry.status == "pending":
			completed = false
	if bool(draft.get("consolidate_existing", false)) and draft.get("merge_status", "none") != "applied":
		completed = false
	if completed:
		var error: String = service.call("FinishSummaryReview", profile_id)
		if error.is_empty():
			draft = JSON.parse_string(service.call("GetSummaryDraft", profile_id))
		else:
			draft["error"] = error
	_show_state(draft)
	_restore_sources()
	_sessions.clear()
	var sessions: Variant = JSON.parse_string(service.call("GetSummarySessions", profile_id))
	if sessions is Array:
		var current := str(service.call("GetActiveSessionId", profile_id))
		for session: Dictionary in sessions:
			_sessions.add_item(str(session.title).replace("\n", " "))
			_sessions.set_item_metadata(_sessions.item_count - 1, str(session.session_id))
			if str(session.session_id) == current:
				_sessions.select(_sessions.item_count - 1)
		_load_messages()
		if _state.get("status", "empty") == "empty":
			_select_sources(true)
	_tabs.current_tab = 3 if bool(_state.get("consolidate_existing", false)) else (0 if _state.get("entries", []).is_empty() else 2)
	_sync_actions()


func _restore_sources() -> void:
	_selected.clear()
	for source: Dictionary in _state.get("sources", []):
		_selected[str(source.session_id) + ":" + str(source.message_id)] = source


func _show_state(state: Dictionary) -> void:
	_state = state
	_loading = true
	_requirements.text = str(state.get("instructions", ""))
	_consolidate.set_pressed_no_signal(bool(state.get("consolidate_preference", false)))
	_tabs.set_tab_hidden(3, not bool(state.get("consolidate_existing", false)))
	_tabs.set_tab_title(2, "人设建议" if bool(state.get("consolidate_existing", false)) else "整理结果")
	_baseline = _signature()
	_render_entries()
	_render_merge()
	_loading = false
	var status := str(state.get("status", "empty"))
	if status == "finished":
		_selected.clear()
		_request = ""
		_original.clear()
		_render_sources()
	_notice.text = str(state.get("error", ""))
	if _notice.text.is_empty():
		_notice.text = str(state.get("response_notice", ""))
	if _notice.text.is_empty():
		if status == "running":
			_notice.text = "正在统一合并已有记忆，核对重复与冲突…" if state.get("phase") == "merge" else "正在提取第 %d / %d 步，已生成 %d 条…" % [int(state.get("completed_batches", 0)) + 1, int(state.get("total_batches", 0)), state.get("entries", []).size()]
		elif status == "finished":
			_notice.text = "本次整理已结束，列表与素材勾选已清空。选择新素材后生成新的列表。"
			if not str(state.get("memory_backup_path", "")).is_empty():
				_notice.text += " 合并前文件已备份。"
		elif state.get("merge_status") == "ready":
			_notice.text = "合并草稿已生成，%d 项冲突待核对。请对照原文，编辑后应用；人设建议仍可单独审核。" % state.get("merge_conflicts", []).size()
		elif state.get("merge_status") == "applied":
			_notice.text = "记忆合并稿已应用，可继续处理剩余人设建议。"
		elif state.get("entries", []).is_empty():
			_notice.text = "没有需要追加的新条目。可调整要求后重新生成。" if status == "ready" else "生成后逐条查看、编辑并选择加入。要求与审核结果会自动保存。"
		else:
			var pending := 0
			var accepted := 0
			for entry: Dictionary in state.entries:
				pending += int(entry.status == "pending")
				accepted += int(entry.status == "accepted")
			_notice.text = "%d 条待选 · %d 条已加入 · %d 条已忽略" % [pending, accepted, state.entries.size() - pending - accepted]
	_notice.tooltip_text = _notice.text
	_sync_actions()


func _refresh_original() -> void:
	var data: Dictionary = JSON.parse_string(service.call("GetSummaryOriginal", _profile_id, JSON.stringify(_selected.values())))
	if data.has("error"):
		_notice.text = str(data.error)
		data = _state
	var existing: Dictionary = data.get("originals", {})
	_original.text = "【所选聊天原文】\n" + str(data.get("source_text", ""))
	for target: String in ["persona", "memory", "active_memory", "world"]:
		_original.text += "\n\n【现有%s】\n%s" % [TARGET_NAMES[target], str(existing.get(target, ""))]


func _load_messages() -> void:
	if _sessions.item_count == 0:
		_messages.clear()
		_render_sources()
		_sync_actions()
		return
	var value: Variant = JSON.parse_string(service.call("GetSummaryMessages", _profile_id, str(_sessions.get_selected_metadata())))
	_messages = value if value is Array else []
	_render_sources()


func _render_sources() -> void:
	PalUi.clear_children(_sources)
	for message: Dictionary in _messages:
		var key := str(message.session_id) + ":" + str(message.message_id)
		var check := CheckBox.new()
		check.text = ("你：" if message.role == "user" else "伙伴：") + str(message.text).replace("\n", " ").left(110)
		check.tooltip_text = str(message.text)
		check.clip_text = true
		check.button_pressed = _selected.has(key)
		check.disabled = _busy()
		_sources.add_child(check)
		check.toggled.connect(func(value: bool) -> void:
			if value:
				_selected[key] = {"session_id": message.session_id, "message_id": message.message_id}
			else:
				_selected.erase(key)
			_sync_actions())


func _select_sources(value: bool) -> void:
	if _busy():
		return
	for message: Dictionary in _messages:
		var key := str(message.session_id) + ":" + str(message.message_id)
		if value:
			_selected[key] = {"session_id": message.session_id, "message_id": message.message_id}
		else:
			_selected.erase(key)
	_render_sources()
	_sync_actions()


func _render_entries() -> void:
	var previous_scroll := 0 if _state.get("entries", []).is_empty() else _results.scroll_vertical
	PalUi.clear_children(_entries)
	_entry_views.clear()
	var visible_count := 0
	for entry: Dictionary in _state.get("entries", []):
		if entry.status != "pending" or not _is_append_entry(entry):
			continue
		visible_count += 1
		var id := str(entry.id)
		var pending: bool = entry.status == "pending"
		var editable := pending and not _busy()
		var column := PalUi.card(_entries, PalUi.SURFACE, 12)
		var heading := HBoxContainer.new()
		column.add_child(heading)
		var check := CheckBox.new()
		check.button_pressed = bool(entry.get("selected", false)) and pending
		check.disabled = not editable
		heading.add_child(check)
		var target_name := str(TARGET_NAMES.get(str(entry.target), "设定"))
		PalUi.label("建议加入" + target_name, heading, 14).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		PalUi.label(str({"pending": "待选择", "accepted": "已加入", "dismissed": "已忽略"}.get(entry.status, "")), heading, 13, true)
		var title := LineEdit.new()
		title.text = str(entry.title)
		title.editable = editable
		title.placeholder_text = "条目标题"
		column.add_child(title)
		var body := _text_box(column, "可编辑需要追加的内容", 110)
		body.text = str(entry.text)
		body.editable = editable
		body.size_flags_vertical = Control.SIZE_FILL
		_entry_views[id] = {"title": title, "body": body, "check": check}
		if not str(entry.get("reason", "")).is_empty():
			PalUi.hint("依据：" + str(entry.reason), column)
		var actions := HFlowContainer.new()
		column.add_child(actions)
		var accept := PalUi.button("加入现有" + target_name, actions, func() -> void: _accept_entries.call_deferred([id]), true)
		accept.disabled = not editable
		if entry.status != "accepted":
			var dismiss := PalUi.button("忽略" if pending else "恢复待选", actions, func() -> void: _dismiss_entry.call_deferred(id, pending))
			dismiss.disabled = _busy()
		check.toggled.connect(func(value: bool) -> void: entry.selected = value; _queue_save())
		title.text_changed.connect(func(value: String) -> void: entry.title = value; _queue_save())
		body.text_changed.connect(func() -> void: entry.text = body.text; _queue_save())
	if visible_count == 0:
		PalUi.hint("记忆内容统一放在「合并草稿」中，这里只显示需要逐条确认的人设建议。" if bool(_state.get("consolidate_existing", false)) else ("正在分析聊天素材…" if _busy() else "候选条目会显示在这里。可逐条加入或忽略，也可以勾选后一起加入。"), _entries)
	_results.set_deferred("scroll_vertical", previous_scroll)


func _is_append_entry(entry: Dictionary) -> bool:
	return not bool(_state.get("consolidate_existing", false)) or str(entry.target) == "persona"


func _render_merge() -> void:
	var previous_scroll := _merge_page.scroll_vertical
	PalUi.clear_children(_merge_body)
	_merge_editors.clear()
	var documents: Dictionary = _state.get("merged_documents", {})
	if documents.is_empty():
		PalUi.hint("会先从所选对话提取新信息，最后与已有文件统一合并。生成过程中不会修改记忆文件。" if _busy() else "开启整理已有记忆后，完整合并稿会显示在这里。", _merge_body)
		_merge_page.set_deferred("scroll_vertical", 0)
		return
	var notes := str(_state.get("merge_notes", ""))
	if not notes.is_empty():
		PalUi.hint("合并说明：" + notes, _merge_body)
	var conflicts: Array = _state.get("merge_conflicts", [])
	if not conflicts.is_empty():
		var lines := PackedStringArray()
		for conflict: Variant in conflicts:
			lines.append("• " + str(conflict))
		PalUi.hint("待核对的冲突：\n" + "\n".join(lines), _merge_body)
	var editable: bool = not _busy() and _state.get("merge_status") == "ready"
	for target: String in ["memory", "active_memory", "world"]:
		var card := PalUi.card(_merge_body, PalUi.SURFACE, 12)
		var count := PalUi.label("%s · %d / 16000 字" % [TARGET_NAMES[target], str(documents.get(target, "")).length()], card, 16)
		var row: BoxContainer = VBoxContainer.new() if PalUi.is_mobile() else HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var before := VBoxContainer.new()
		before.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(before)
		PalUi.label("生成时原文", before, 13, true)
		var original := _text_box(before, "原文件为空", 180)
		original.text = str(_state.get("originals", {}).get(target, ""))
		original.editable = false
		var after := VBoxContainer.new()
		after.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(after)
		PalUi.label("合并后 · 可编辑" if editable else "合并后", after, 13)
		var editor := _text_box(after, "文件为空；也可在这里编辑补充", 180)
		editor.text = str(documents.get(target, ""))
		editor.editable = editable
		_merge_editors[target] = editor
		count.add_theme_color_override("font_color", PalUi.ERROR if editor.text.length() > 16000 else PalUi.TEXT)
		editor.text_changed.connect(func() -> void:
			_state.merged_documents[target] = editor.text
			count.text = "%s · %d / 16000 字" % [TARGET_NAMES[target], editor.text.length()]
			count.add_theme_color_override("font_color", PalUi.ERROR if editor.text.length() > 16000 else PalUi.TEXT)
			_queue_save())
	_merge_page.set_deferred("scroll_vertical", previous_scroll)


func _select_entries(value: bool) -> void:
	if _busy():
		return
	_collect_entries()
	for entry: Dictionary in _state.get("entries", []):
		if entry.status == "pending" and _is_append_entry(entry):
			entry.selected = value
	_render_entries()
	_queue_save()


func _busy() -> bool:
	return _state.get("status") == "running"


func _selected_entries() -> Array:
	var result: Array = []
	for entry: Dictionary in _state.get("entries", []):
		if entry.status == "pending" and _is_append_entry(entry) and bool(entry.get("selected", false)):
			result.append(str(entry.id))
	return result


func _sync_actions() -> void:
	if _apply == null:
		return
	_generate.disabled = _busy() or (_selected.is_empty() and not _consolidate.button_pressed)
	_generate.text = "生成并合并记忆" if _consolidate.button_pressed else "生成追加条目"
	_stop.disabled = not _busy()
	_sessions.disabled = _busy()
	_consolidate.disabled = _busy()
	_requirements.editable = not _busy()
	var count := _selected_entries().size()
	_apply.disabled = _busy() or count == 0
	_apply.text = "加入勾选条目（%d）" % count if count > 0 else "加入勾选条目"
	var consolidate := bool(_state.get("consolidate_existing", false))
	_apply_merge.visible = consolidate
	_apply_merge.disabled = _busy() or _state.get("merge_status") != "ready" or _state.get("merged_documents", {}).size() != 3
	_finish.disabled = _busy() or (not consolidate and _state.get("entries", []).is_empty() and _state.get("sources", []).is_empty())
	_merge_backup.visible = not PalUi.is_mobile() and not str(_state.get("memory_backup_path", "")).is_empty()
	_merge_backup.tooltip_text = str(_state.get("memory_backup_path", ""))
	var restore: Dictionary = JSON.parse_string(service.call("GetPersonaRestore", _profile_id)) if not _profile_id.is_empty() else {}
	_restore_persona.disabled = _busy() or not bool(restore.get("available", false))
	_response.visible = not str(_state.get("response_path", "")).is_empty()
	_response.disabled = _busy()
	var sessions: Dictionary = {}
	for source: Dictionary in _selected.values():
		sessions[str(source.session_id)] = true
	_source_count.text = "已选 %d 段对话 · %d 条消息；切换会话后保留勾选。" % [sessions.size(), _selected.size()]
	_generate.tooltip_text = "已选择 %d 条消息。%s" % [_selected.size(), "最后会与已有记忆文件统一合并。" if _consolidate.button_pressed else "模型将生成逐条追加的候选。"]


func _view_response() -> void:
	var path := str(_state.get("response_path", ""))
	if not FileAccess.file_exists(path):
		_notice.text = "返回值文件不存在，请重新整理后查看。"
		return
	if PalUi.is_mobile():
		PalMobileFiles.export_file(self, path, "summary-response.json", "保存模型返回值", "*.json ; 模型返回值 ; application/json", func(message: String) -> void: _notice.text = message)
	elif DisplayServer.get_name() != "headless" and OS.shell_open(path) != OK:
		_notice.text = "无法打开返回值文件：" + path


func _start() -> void:
	_save_timer.stop()
	if not _save_review():
		return
	_request = Crypto.new().generate_random_bytes(16).hex_encode()
	var error: String = service.call("GenerateSummary", _profile_id, _request, JSON.stringify({"instructions": _requirements.text, "sources": _selected.values(), "consolidate_existing": _consolidate.button_pressed}))
	if not error.is_empty():
		_notice.text = error
		return
	_show_state(JSON.parse_string(service.call("GetSummaryDraft", _profile_id)))
	_render_sources()
	_tabs.current_tab = 3 if bool(_state.get("consolidate_existing", false)) else 2


func _on_result(profile_id: String, request_id: String, json: String) -> void:
	if profile_id == _profile_id and (request_id.is_empty() or _request.is_empty() or request_id == _request):
		_show_state(JSON.parse_string(json))
		_restore_sources()
		_render_sources()


func _signature() -> String:
	return JSON.stringify([_requirements.text, _consolidate.button_pressed, _state.get("entries", []), _state.get("merged_documents", {})])


func _collect_entries() -> void:
	for entry: Dictionary in _state.get("entries", []):
		if entry.status != "pending" or not _entry_views.has(str(entry.id)):
			continue
		var view: Dictionary = _entry_views[str(entry.id)]
		if is_instance_valid(view.body):
			entry.title = view.title.text
			entry.text = view.body.text
			entry.selected = view.check.button_pressed
	if _state.get("merge_status") == "ready":
		for target: String in _merge_editors:
			var editor: TextEdit = _merge_editors[target]
			if is_instance_valid(editor):
				_state.merged_documents[target] = editor.text


func _queue_save() -> void:
	if not _loading:
		_save_timer.start()
		_sync_actions()


func _save_review() -> bool:
	if _profile_id.is_empty() or _busy():
		return true
	_collect_entries()
	if _signature() == _baseline:
		return true
	var error: String = service.call("SaveSummaryReview", _profile_id, _requirements.text, JSON.stringify(_state.get("entries", [])), _consolidate.button_pressed, JSON.stringify(_state.get("merged_documents", {})))
	if error.is_empty():
		_baseline = _signature()
	else:
		_notice.text = error
	return error.is_empty()


func _accept_selected() -> void:
	_collect_entries()
	_accept_entries(_selected_entries())


func _accept_entries(ids: Array) -> void:
	_save_timer.stop()
	if not _save_review():
		return
	var error: String = service.call("AcceptSummaryEntries", _profile_id, JSON.stringify(ids))
	_show_state(JSON.parse_string(service.call("GetSummaryDraft", _profile_id)))
	if not error.is_empty():
		_notice.text = error
	elif _state.get("status") != "finished":
		_notice.text = "已加入现有设定，下次回复生效。"


func _dismiss_entry(id: String, dismiss: bool) -> void:
	_save_timer.stop()
	if not _save_review():
		return
	var error: String = service.call("DismissSummaryEntry", _profile_id, id, dismiss)
	_show_state(JSON.parse_string(service.call("GetSummaryDraft", _profile_id)))
	if not error.is_empty():
		_notice.text = error


func _finish_review() -> void:
	_save_timer.stop()
	if not _save_review():
		return
	var error: String = service.call("FinishSummaryReview", _profile_id)
	_show_state(JSON.parse_string(service.call("GetSummaryDraft", _profile_id)))
	if not error.is_empty():
		_notice.text = error


func _accept_merge() -> void:
	_save_timer.stop()
	if not _save_review():
		return
	var error: String = service.call("ApplyConsolidatedMemory", _profile_id)
	_show_state(JSON.parse_string(service.call("GetSummaryDraft", _profile_id)))
	if not error.is_empty():
		_notice.text = error
	elif _state.get("status") != "finished":
		_notice.text = "合并稿已应用，合并前文件已备份。" if not str(_state.get("memory_backup_path", "")).is_empty() else "合并稿与现有文件一致，无需改动。"


func _open_merge_backup() -> void:
	var path := str(_state.get("memory_backup_path", ""))
	if path.is_empty() or OS.shell_open(path) != OK:
		_notice.text = "未能打开备份目录：" + path


func is_dirty() -> bool:
	return not _save_review()


func before_close() -> void:
	_save_timer.stop()
	_save_review()
