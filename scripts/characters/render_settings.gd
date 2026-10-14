class_name PalRenderSettings
extends RefCounted
## Serializable per-character lighting and viewport quality, including old-save defaults.

const DEFAULTS := {
	"key_energy": 0.9, "key_color": "#ffffff", "key_yaw": -25.0, "key_pitch": -20.0,
	"fill_energy": 0.35, "fill_color": "#ffffff", "fill_yaw": 140.0, "fill_pitch": -15.0,
	"ambient_energy": 0.75, "ambient_color": "#fff2fa",
	"msaa": Viewport.MSAA_4X, "fxaa": false, "render_scale": 1.0,
	"shadows": false, "debanding": true,
}
const LIMITS := {
	"key_energy": Vector2(0, 3), "fill_energy": Vector2(0, 3), "ambient_energy": Vector2(0, 2),
	"key_yaw": Vector2(-180, 180), "fill_yaw": Vector2(-180, 180),
	"key_pitch": Vector2(-90, 90), "fill_pitch": Vector2(-90, 90),
	"render_scale": Vector2(0.5, 2.0),
}
const QUALITY_KEYS := ["msaa", "fxaa", "render_scale", "shadows", "debanding"]
const PRESET_NAMES := ["省电", "均衡", "高画质", "超高画质"]
const PRESETS := [
	{"msaa": Viewport.MSAA_DISABLED, "fxaa": false, "render_scale": 0.75, "shadows": false, "debanding": false},
	{"msaa": Viewport.MSAA_4X, "fxaa": false, "render_scale": 1.0, "shadows": false, "debanding": true},
	{"msaa": Viewport.MSAA_4X, "fxaa": false, "render_scale": 1.25, "shadows": true, "debanding": true},
	{"msaa": Viewport.MSAA_8X, "fxaa": false, "render_scale": 1.5, "shadows": true, "debanding": true},
]


static func normalize(value: Variant) -> Dictionary:
	var result := DEFAULTS.duplicate()
	if not value is Dictionary:
		return result
	for key: String in LIMITS:
		var number: Variant = value.get(key)
		if (number is float or number is int) and is_finite(float(number)):
			var limits: Vector2 = LIMITS[key]
			result[key] = clampf(float(number), limits.x, limits.y)
	var msaa: Variant = value.get("msaa")
	if (msaa is int or msaa is float) and is_finite(float(msaa)) and float(msaa) == floorf(float(msaa)) and float(msaa) >= Viewport.MSAA_DISABLED and float(msaa) < Viewport.MSAA_MAX:
		result.msaa = int(msaa)
	for key: String in ["fxaa", "shadows", "debanding"]:
		if value.get(key) is bool:
			result[key] = value[key]
	for key: String in ["key_color", "fill_color", "ambient_color"]:
		var color: Variant = value.get(key)
		if color is String and Color.html_is_valid(color):
			result[key] = "#" + Color.html(color).to_html(false)
	return result


static func preset_index(settings: Dictionary) -> int:
	for index: int in PRESETS.size():
		var matches := true
		for key: String in QUALITY_KEYS:
			if settings.get(key) != PRESETS[index][key]:
				matches = false
				break
		if matches:
			return index
	return PRESETS.size()
