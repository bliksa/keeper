class_name BootScreen
extends Control
## First screen (port of the web loading screen): fullscreen toggle,
## "start game" (unlocks audio in browsers), "dev" (straight to developer mode)
## and subtitle language.

signal started
signal dev_pressed

var _start: Button
var _dev: Button
var _subs: Label
var _full: Button
var _flags := {}


func _ready() -> void:
	size = Vector2(1066, 600)
	var bg := ColorRect.new()
	bg.color = Color("#121212")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_full = UiKit.button("", Vector2(300, 30), 13, Color(0, 0, 0, 0), Color("#9ca3af"))
	_full.position = Vector2(383, 170)
	_full.pressed.connect(_toggle_fullscreen)
	add_child(_full)
	var bar := ColorRect.new()
	bar.color = Color("#10b981")
	bar.position = Vector2(405, 226)
	bar.size = Vector2(256, 8)
	add_child(bar)
	_start = UiKit.button("", Vector2(190, 48), 16)
	_start.position = Vector2(405, 266)
	_start.pressed.connect(_go)
	add_child(_start)
	_dev = UiKit.button("DEV", Vector2(58, 48), 13, Color("#1e293b"), Color("#cbd5e1"))
	_dev.position = Vector2(603, 266)
	_dev.pressed.connect(func(): dev_pressed.emit())
	add_child(_dev)
	_subs = UiKit.label("", 13, Color("#9ca3af"), true)
	_subs.position = Vector2(405, 348)
	add_child(_subs)
	var x := 560.0
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
	Text.language_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_full.text = Text.t("UI_SWITCH_FULLSCREEN").to_upper()
	_start.text = Text.t("UI_CLICK_TO_START").to_upper()
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
