class_name UiKit
extends RefCounted
## Button / label factories in the web build's style (slate buttons, Comfortaa).


static func _box(col: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


## Text size of every menu button (boot, title, pause).
const MENU_FONT := 18


static func button(text: String, size: Vector2, font_size := 16, bg := Color("#1e293b"), fg := Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Text.font_bold)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", _box(bg, 12, Color("#475569"), 1))
	b.add_theme_stylebox_override("hover", _box(bg.lightened(0.12), 12, Color("#475569"), 1))
	b.add_theme_stylebox_override("pressed", _box(bg.darkened(0.2), 12, Color("#475569"), 1))
	b.add_theme_stylebox_override("disabled", _box(Color("#0f172a"), 12, Color("#1e293b"), 1))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", Color("#475569"))
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.add_theme_constant_override("icon_max_width", 22)
	return b


static func pill_button(text: String) -> Button:
	var b := button(text, Vector2(116, 36), 11, Color(0, 0, 0, 0.5))
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st)
		sb.set_corner_radius_all(18)
		sb.border_color = Color(1, 1, 1, 0.2)
	return b


static func label(text: String, size := 14, col := Color.WHITE, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Text.font_bold if bold else Text.font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


## Square toolbar button with an icon and a hover tooltip (Photoshop-style).
static func icon_button(icon_path: String, tooltip: String, side := 34.0) -> Button:
	var b := Button.new()
	b.icon = load(icon_path)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(side, side)
	b.size = Vector2(side, side)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pad := int(side * 0.18)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#334155") if st == "hover" else Color(0, 0, 0, 0)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(pad)
		b.add_theme_stylebox_override(st, sb)
	return b


## Highlight (or un-highlight) an icon button as the active tool.
static func set_icon_active(b: Button, on: bool) -> void:
	var sb: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	sb.bg_color = Color("#059669", 0.85) if on else Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", sb)
	var hv: StyleBoxFlat = b.get_theme_stylebox("hover").duplicate()
	hv.bg_color = Color("#10b981") if on else Color("#334155")
	b.add_theme_stylebox_override("hover", hv)
