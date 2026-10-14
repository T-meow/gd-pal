class_name PalMemoryWindow
extends PalManualContextPanel


func _init() -> void:
	caption = "记忆"
	help_text = "长期记忆保存稳定事实，活跃记忆保存当前进展。"
	documents = [
		{"field": "memory", "caption": "长期记忆", "help": "称呼、稳定偏好、重要经历、长期约定和关系事实。"},
		{"field": "active_memory", "caption": "活跃记忆", "help": "当前场景、近期进展、临时状态和未完成事项；过时后可直接编辑移除。"},
	]


func remember_message(profile_id: String, _session_id: String, _message_id: String, text: String) -> void:
	open_profile(profile_id)
	_editor.text += ("\n\n" if not _editor.text.is_empty() else "") + text
	_notice.text = "已加入编辑区，可修改后保存。"
