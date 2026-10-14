class_name PalSystemTray
extends Node
## Owns the native notification icon and its menu for the application lifetime.

signal show_requested
signal hide_requested
signal quit_requested

var _indicator := -1
var _menu := RID()


func _ready() -> void:
	if not OS.has_feature("windows") or PalUi.is_editor_preview(get_window()):
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR) or not NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU):
		return
	_menu = NativeMenu.create_menu()
	NativeMenu.add_item(_menu, "打开陪伴大厅", _on_menu, Callable(), "show")
	NativeMenu.add_item(_menu, "收起到托盘", _on_menu, Callable(), "hide")
	NativeMenu.add_separator(_menu)
	NativeMenu.add_item(_menu, "退出 GD Pal", _on_menu, Callable(), "quit")
	_indicator = DisplayServer.create_status_indicator(preload("res://icon.svg"), "GD Pal · 点击打开大厅，右键打开菜单", _on_pressed)
	if is_available():
		DisplayServer.status_indicator_set_menu(_indicator, _menu)


func is_available() -> bool:
	return _indicator >= 0


func _on_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_on_menu("show")


func _on_menu(action: Variant) -> void:
	# Leave the native menu callback before changing focus or shutting down.
	match str(action):
		"show": show_requested.emit.call_deferred()
		"hide": hide_requested.emit.call_deferred()
		"quit": quit_requested.emit.call_deferred()


func _exit_tree() -> void:
	if is_available():
		DisplayServer.delete_status_indicator(_indicator)
		_indicator = -1
	if _menu.is_valid():
		NativeMenu.free_menu(_menu)
		_menu = RID()
