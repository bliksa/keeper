class_name TitleScreen
extends Control
## Main menu: layered forest with mouse parallax, blinking Kyra, logo,
## Start / Credits, mute and keyboard/gamepad toggles.
## Port of the web `A2` component.

signal start_pressed

var _back: Texture2D
var _middle: Texture2D
var _front: Texture2D
var _kira: Array = []
var _kira_frame := 0
var _blink_seq: Array = []
var _blink_timer := 3.0
var _mouse := Vector2.ZERO
var _parallax := Vector2.ZERO
var _t := 0.0
var _credits: Control
var _start_btn: Button
var _credits_btn: Button
var _mute_btn: Button
var _mode_btn: Button


func _ready() -> void:
	size = Vector2(1066, 600)
	_back = load("res://assets/images/back.png")
	_middle = load("res://assets/images/middle3.png")
	_front = load("res://assets/images/front.png")
	for n in ["kira", "kira1", "kira2", "kira3"]:
		_kira.append(load("res://assets/images/%s.png" % n))

	var front_layer := Control.new()
	front_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	front_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front_layer.draw.connect(_draw_front.bind(front_layer))
	add_child(front_layer)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/images/keeper.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.position = Vector2(533 + (533 - 320) / 2.0, 70)
	logo.size = Vector2(320, 320)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	_start_btn = UiKit.button("", Vector2(256, 56), UiKit.MENU_FONT)
	_start_btn.position = Vector2(533 + (533 - 256) / 2.0, 400)
	_start_btn.pressed.connect(func(): start_pressed.emit())
	add_child(_start_btn)
	_credits_btn = UiKit.button("", Vector2(256, 56), UiKit.MENU_FONT)
	_credits_btn.position = Vector2(533 + (533 - 256) / 2.0, 476)
	_credits_btn.pressed.connect(_open_credits)
	add_child(_credits_btn)

	_mute_btn = UiKit.pill_button("")
	_mute_btn.position = Vector2(24, 24)
	_mute_btn.pressed.connect(func():
		Audio.muted = not Audio.muted
		_refresh())
	add_child(_mute_btn)
	_mode_btn = UiKit.pill_button("")
	_mode_btn.position = Vector2(150, 24)
	_mode_btn.pressed.connect(func():
		Game.control_mode = "gamepad" if Game.control_mode == "keyboard" else "keyboard")
	add_child(_mode_btn)

	var ver := Label.new()
	ver.name = "Version"
	ver.position = Vector2(24, 552)
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	add_child(ver)

	Game.control_mode_changed.connect(_refresh)
	Text.language_changed.connect(_refresh)
	_refresh()
	modulate.a = 0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


func _refresh() -> void:
	var pad := Game.control_mode == "gamepad"
	_start_btn.text = Text.t("BTN_START")
	_start_btn.icon = load("res://assets/ui/pad_blue.png") if pad else null
	_credits_btn.text = Text.t("BTN_CREDITS")
	_credits_btn.icon = load("res://assets/ui/pad_red.png") if pad else null
	_mute_btn.text = "SOUND OFF" if Audio.muted else "SOUND ON"
	_mute_btn.tooltip_text = "Unmute" if Audio.muted else "Mute"
	_mode_btn.text = "KEYBOARD" if Game.control_mode == "keyboard" else "GAMEPAD"
	_mode_btn.tooltip_text = "Switch to Gamepad" if Game.control_mode == "keyboard" else "Switch to Keyboard"
	get_node("Version").text = Text.t("UI_WORK_IN_PROGRESS") + " v" + str(ProjectSettings.get_setting("application/config/version"))


func _open_credits() -> void:
	if _credits:
		return
	_credits = CreditsPanel.new()
	_credits.tree_exited.connect(func(): _credits = null)
	add_child(_credits)


func _unhandled_input(event: InputEvent) -> void:
	if _credits:
		if event.is_action_pressed("confirm") or event.is_action_pressed("choice_1") or event.is_action_pressed("choice_2"):
			_credits.queue_free()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("confirm"):
		start_pressed.emit()
	elif event.is_action_pressed("choice_1"):
		_open_credits()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = Vector2(event.position.x / 1066.0 * 2 - 1, event.position.y / 600.0 * 2 - 1)


func _process(delta: float) -> void:
	_t += delta
	_parallax = _parallax.lerp(_mouse, minf(1, delta * 3))
	_blink_timer -= delta
	if _blink_timer <= 0:
		if _blink_seq.is_empty():
			_blink_seq = [1, 2, 3, 2, 1, 0]
		_kira_frame = _blink_seq.pop_front()
		if _blink_seq.is_empty():
			_blink_timer = randf_range(2.0, 7.0)
		else:
			_blink_timer = 0.07
	queue_redraw()
	get_child(0).queue_redraw()


func _cover(tex: Texture2D, rect: Rect2, extra_scale := 1.0) -> Rect2:
	var k := maxf(rect.size.x / tex.get_width(), rect.size.y / tex.get_height()) * extra_scale
	var s := Vector2(tex.get_width(), tex.get_height()) * k
	return Rect2(rect.get_center() - s / 2, s)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color.BLACK)
	var o1 := Vector2(_parallax.x * -5, _parallax.y * -2.5)
	var o2 := Vector2(_parallax.x * -15, _parallax.y * -7.5)
	draw_texture_rect(_back, _cover(_back, Rect2(Vector2(-100, -100) + o1, Vector2(1266, 800))), false)
	draw_texture_rect(_middle, _cover(_middle, Rect2(Vector2(-100, -100) + o2, Vector2(1266, 800))), false)
	# Kyra (object-contain, top aligned, scaled 1.2 from the top) with a slow bob.
	var tex: Texture2D = _kira[_kira_frame]
	var k := minf(500.0 / tex.get_width(), 720.0 / tex.get_height()) * 1.2
	var sz := Vector2(tex.get_width(), tex.get_height()) * k
	var phase := fmod(_t, 12.0) / 12.0
	var bob := 0.0
	if phase < 0.2: bob = -8 * smoothstep(0, 0.2, phase)
	elif phase < 0.4: bob = -8
	elif phase < 0.7: bob = -8 * (1 - smoothstep(0.4, 0.7, phase))
	draw_texture_rect(tex, Rect2(Vector2(300 - sz.x / 2, -120 + bob), sz), false)


func _draw_front(ci: Control) -> void:
	var o3 := Vector2(_parallax.x * -30, _parallax.y * -15)
	ci.draw_texture_rect(_front, _cover(_front, Rect2(Vector2(-200, -200) + o3, Vector2(1466, 1000)), 2.5), false)
