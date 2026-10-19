extends SceneTree
## Focused regression for the reported popup/character overlap, including mixed-DPI screen coordinates.

func _initialize() -> void:
	var layout: RefCounted = load("res://scripts/desktop/DesktopPopupLayout.cs").new()
	var cases: Array = [
		[Rect2i(0, 0, 1920, 1040), Rect2i(1520, 380, 360, 610)],
		[Rect2i(0, 0, 960, 640), Rect2i(300, 20, 360, 610)],
		[Rect2i(0, 0, 1280, 720), Rect2i(8, 100, 360, 610)],
		[Rect2i(-1920, 0, 1920, 1040), Rect2i(-1000, 260, 360, 610)],
		[Rect2i(1920, -240, 2560, 1400), Rect2i(3000, 120, 540, 915)],
	]
	for item: Array in cases:
		var area: Rect2i = item[0]
		var character: Rect2i = item[1]
		var chat: Rect2i = layout.call("Arrange", area, character, Vector2i(440, 500), Rect2i(), Vector2i(320, 330))
		var monitor: Rect2i = layout.call("Arrange", area, character, Vector2i(380, 720), chat, Vector2i(280, 128))
		if not chat.has_area() or not monitor.has_area() or not area.encloses(chat) or not area.encloses(monitor) or chat.intersects(character) or monitor.intersects(character) or monitor.intersects(chat):
			push_error("Popup overlap regression: %s / %s / %s" % [character, chat, monitor])
			quit(1)
			return
		var after_close: Rect2i = layout.call("ArrangeWithPreference", area, character, Vector2i(380, 720), Rect2i(), Vector2i(280, 128), monitor)
		if after_close != monitor:
			push_error("Closing records moved the monitor into the vacated close-button position")
			quit(1)
			return
	print("Popup layout: 5 screen/edge cases passed; windows do not overlap and closing records preserves monitor placement.")
	quit(0)
