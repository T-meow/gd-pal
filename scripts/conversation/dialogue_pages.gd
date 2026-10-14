class_name PalDialoguePages
extends RefCounted
## Build stable pages while a reply streams; an unfinished tail waits for more text.

const MAX_LENGTH := 100
const SENTENCE_ENDS := "。！？!?；;"
const CLOSING_MARKS := "。！？!?；;.……\"'”’」』"


static func parse(text: String, complete: bool = true) -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var buffer := ""
	var depth := 0
	for character: String in text:
		if character in ["（", "("]:
			if depth == 0:
				_append_parts(parts, buffer, false, true)
				buffer = ""
			depth += 1
		buffer += character
		if character in ["）", ")"] and depth > 0:
			depth -= 1
			if depth == 0:
				_append_parts(parts, buffer, true, true)
				buffer = ""
	_append_parts(parts, buffer, depth > 0, complete)
	var pages: Array[Dictionary] = []
	var description := ""
	for part: Dictionary in parts:
		if part.has("aside"):
			if not description.is_empty():
				pages.append({"dialogue": "", "description": description})
			description = str(part.aside)
		else:
			pages.append({"dialogue": str(part.say), "description": description})
			description = ""
	if complete and not description.is_empty():
		pages.append({"dialogue": "", "description": description})
	return pages


static func _append_parts(parts: Array[Dictionary], text: String, aside: bool, complete: bool) -> void:
	if aside:
		if not complete:
			return
		text = text.trim_prefix("（").trim_prefix("(").trim_suffix("）").trim_suffix(")")
	var buffer := ""
	for index: int in text.length():
		var character := text[index]
		var following := text[index + 1] if index + 1 < text.length() else ""
		buffer += character
		var sentence_end := character in SENTENCE_ENDS or (character == "." and (following.is_empty() or following in [" ", "\n", "\r"]))
		var closing_quote := character in "\"'”’」』" and buffer.length() > 1 and buffer[buffer.length() - 2] in SENTENCE_ENDS
		var boundary := (sentence_end or closing_quote) and (complete or not following.is_empty()) and (following.is_empty() or not following in CLOSING_MARKS)
		var long_clause := buffer.length() >= 64 and character in ["，", ",", "：", ":", " "]
		if character == "\n" or boundary or long_clause or buffer.length() >= MAX_LENGTH:
			_add_part(parts, buffer, aside)
			buffer = ""
	if complete:
		_add_part(parts, buffer, aside)


static func _add_part(parts: Array[Dictionary], text: String, aside: bool) -> void:
	text = text.strip_edges()
	if not text.is_empty():
		parts.append({"aside": "（" + text + "）"} if aside else {"say": text})
