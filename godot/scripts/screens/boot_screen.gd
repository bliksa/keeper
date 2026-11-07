class_name BootScreen
extends Control
## First screen (port of the web loading screen): fullscreen toggle,
## "start game" (unlocks audio in browsers), "dev" (straight to developer mode)
## and subtitle language.

signal started
signal dev_pressed

## One text size for everything on this screen (same as the other menus).
const FONT := UiKit.MENU_FONT

var _start: Button
var _dev: Button
var _version: Label
var _subs: Label
var _full: Button
var _flags := {}


func _ready() -> void:
	size = Vector2(1066, 600)
	var bg := ColorRect.new()
	bg.color = Color("#121212")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# As wide as the green bar and START + DEV below it.
	_full = UiKit.button("", Vector2(256, 40), FONT, Color(0, 0, 0, 0), Color("#9ca3af"))
	_full.position = Vector2(405, 166)
	_icon_left(_full, "maximize")
	_full.pressed.connect(_toggle_fullscreen)
	add_child(_full)
	# The green bar (where the browser's loading bar was), rounded like it.
	var bar := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color("#10b981")
	bsb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("panel", bsb)
	bar.position = Vector2(405, 226)
	bar.size = Vector2(256, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	# START (green) and DEV, side by side, the same width; together as wide as the bar.
	_start = UiKit.button("", Vector2(124, 50), FONT, Color("#059669"))
	_start.position = Vector2(405, 266)
	_icon_left(_start, "play")
	_start.pressed.connect(_go)
	add_child(_start)
	_dev = UiKit.button("DEV", Vector2(124, 50), FONT)
	_dev.position = Vector2(405 + 256 - 124, 266)
	_icon_left(_dev, "lock")
	_dev.pressed.connect(func(): dev_pressed.emit())
	add_child(_dev)
	_subs = UiKit.label("", FONT, Color("#9ca3af"), true)
	_subs.position = Vector2(405, 342)
	add_child(_subs)
	var x := 557.0
	for lang in ["sk", "en", "pt"]:
		var tb := TextureButton.new()
		tb.texture_normal = load("res://assets/images/%s.png" % ("gb" if lang == "en" else lang))
		tb.ignore_texture_size = true
		tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		tb.position = Vector2(x, 340)
		tb.size = Vector2(32, 24)
		tb.pressed.connect(func(): Text.language = lang)
		add_child(tb)
		_flags[lang] = tb
		x += 36
	# Under the green bar, exactly where the browser's loading screen shows it.
	var ver := Label.new()
	ver.text = Game.build_label()
	ver.add_theme_font_override("font", Text.font)
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color("#6b7280"))
	ver.position = Vector2(533 - 200, 240)
	ver.size = Vector2(400, 16)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(ver)
	_version = ver
	Text.language_changed.connect(_refresh)
	_refresh()


## A lucide icon before the button's text (like the developer menu's icons),
## in the text's colour; icon and text are centred together (_center_icon).
func _icon_left(b: Button, icon: String) -> void:
	b.icon = load("res://assets/ui/icons/%s.svg" % icon)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("icon_max_width", ICON_W)
	b.add_theme_constant_override("h_separation", 10)
	var fg := b.get_theme_color("font_color")
	for k in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(k, fg)


const ICON_W := 22


## Left padding so the icon and the text sit in the middle of the button.
func _center_icon(b: Button) -> void:
	var tw := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
	var pad := maxf(6, (b.size.x - (ICON_W + 10 + tw)) / 2)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
		sb.content_margin_left = pad
		sb.content_margin_right = 4
		b.add_theme_stylebox_override(st, sb)


func _refresh() -> void:
	_full.text = Text.t("UI_SWITCH_FULLSCREEN").to_upper()
	_start.text = Text.t("UI_CLICK_TO_START").to_upper()
	for b in [_full, _start, _dev]:
		_center_icon(b)
	_subs.text = Text.t("UI_SUBTITLES").to_upper()
	_dev.tooltip_text = Text.t("UI_DEVELOPER_MODE")
	for lang in _flags:
		var tb: TextureButton = _flags[lang]
		tb.modulate = Color.WHITE if lang == Text.language else Color(1, 1, 1, 0.55)
		tb.scale = Vector2(1.1, 1.1) if lang == Text.language else Vector2.ONE
	queue_redraw()


func _draw() -> void:
	var tb: TextureButton = _flags.get(Text.language)
	if tb:
		draw_rect(Rect2(tb.position - Vector2(2, 2), tb.size * tb.scale + Vector2(4, 4)), Color("#10b981"), false, 2.0)


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _go() -> void:
	started.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("confirm"):
		_go()
