class_name TitleScreen
extends Control
## Main menu: layered forest with mouse parallax, blinking Kyra, logo,
## Start / Credits, mute and keyboard/gamepad toggles.
## Port of the web `A2` component.
##
## With a save (Game.save): Continue above the start button (then "New game"; the furthest
## place of the playthrough, Main._continue_game) and under Credits the four phases
## (chapter buttons with their level's motif, EndScreen.draw_motif: open up to the furthest
## one reached, all of them once the game was finished; a finished game shows a small
## "Finished" mark). The logo is smaller then (layout()).

signal start_pressed
signal continue_pressed
## A phase picked in the row under Credits (1 cave … 4 PMS maze).
signal chapter_pressed(n: int)

const COL_X := 533 + (533 - 256) / 2.0
const CHAPTER := Vector2(58, 40)

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
var _continue_btn: Button
var _logo: TextureRect
var _chapters: Array[Button] = []
var _phases_lbl: Label
var _finished: Control


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
	_logo = logo
	_continue_btn = UiKit.button("", Vector2(256, 56), UiKit.MENU_FONT, Color("#059669"))
	_continue_btn.pressed.connect(func(): continue_pressed.emit())
	add_child(_continue_btn)
	_start_btn = UiKit.button("", Vector2(256, 56), UiKit.MENU_FONT)
	_start_btn.position = Vector2(533 + (533 - 256) / 2.0, 400)
	_start_btn.pressed.connect(func(): start_pressed.emit())
	add_child(_start_btn)
	_credits_btn = UiKit.button("", Vector2(256, 56), UiKit.MENU_FONT)
	_credits_btn.position = Vector2(533 + (533 - 256) / 2.0, 476)
	_credits_btn.pressed.connect(_open_credits)
	add_child(_credits_btn)

	_phases_lbl = UiKit.label("", 12, Color(1, 1, 1, 0.75), true)
	_phases_lbl.add_theme_color_override("font_outline_color", Color("#1a1022", 0.8))
	_phases_lbl.add_theme_constant_override("outline_size", 4)
	_phases_lbl.size = Vector2(256, 16)
	_phases_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_phases_lbl)
	for i in Game.CHAPTERS:
		var cb := UiKit.button("", CHAPTER, 12)
		cb.pressed.connect(func(): chapter_pressed.emit(i + 1))
		cb.draw.connect(_draw_chapter.bind(cb, i))
		add_child(cb)
		_chapters.append(cb)
	_finished = Control.new()
	_finished.size = Vector2(256, 20)
	_finished.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finished.draw.connect(_draw_finished)
	add_child(_finished)

	_mute_btn = UiKit.pill_button("")
	_mute_btn.position = Vector2(24, 24)
	_mute_btn.pressed.connect(func():
		Audio.muted = not Audio.muted
		Game.save_set("muted", Audio.muted)
		_refresh())
	add_child(_mute_btn)
	_mode_btn = UiKit.pill_button("")
	_mode_btn.position = Vector2(24 + PILL_W + 10, 24)
	_mode_btn.pressed.connect(func():
		Game.control_mode = "gamepad" if Game.control_mode == "keyboard" else "keyboard")
	add_child(_mode_btn)

	var ver := Label.new()
	ver.name = "Version"
	ver.add_theme_font_override("font", Text.font_dev)
	ver.position = Vector2(24, 552)
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
	add_child(ver)

	Game.control_mode_changed.connect(_refresh)
	Text.language_changed.connect(_refresh)
	_refresh()
	modulate.a = 0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


## The pills top-left are a little wider than UiKit's (sk "KLÁVESNICA", pt "SEM SOM").
const PILL_W := 132.0


## Is there a place to continue from (the Continue button shows)?
func can_continue() -> bool:
	return Game.has_progress()


## Places everything by the save: nothing saved = the plain menu (big logo, Start,
## Credits); with a save the logo shrinks and Continue / the phases row come in.
func layout() -> void:
	var cont := can_continue()
	var reached := Game.reached_chapter()
	var compact := cont or reached > 0
	var logo_s := 250.0 if compact else 320.0
	_logo.size = Vector2(logo_s, logo_s)
	_logo.position = Vector2(533 + (533 - logo_s) / 2.0, 36 if compact else 70)
	_continue_btn.visible = cont
	_continue_btn.position = Vector2(COL_X, 296)
	_start_btn.position = Vector2(COL_X, 362 if compact else 400)
	_credits_btn.position = Vector2(COL_X, 428 if compact else 476)
	_phases_lbl.visible = compact
	_phases_lbl.position = Vector2(COL_X, 492)
	var gap := (256.0 - CHAPTER.x * Game.CHAPTERS) / (Game.CHAPTERS - 1)
	for i in _chapters.size():
		var cb := _chapters[i]
		cb.visible = compact
		cb.position = Vector2(COL_X + i * (CHAPTER.x + gap), 512)
		cb.disabled = i + 1 > reached
		cb.tooltip_text = Text.t(EndScreen.PHASES[i].name) if not cb.disabled else Text.t("TITLE_LOCKED")
		cb.queue_redraw()
	# "Finished" sits where Continue would be (a finished game has nothing to continue).
	_finished.visible = Game.is_finished()
	_finished.position = Vector2(COL_X, 562 if cont else 318)
	_finished.queue_redraw()


func _draw_chapter(cb: Button, i: int) -> void:
	var c := cb.size / 2
	if cb.disabled:
		# A small padlock.
		var col := Color(1, 1, 1, 0.4)
		cb.draw_arc(c + Vector2(0, -3), 5.0, PI, TAU, 12, col, 2.0, true)
		cb.draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 11)), col)
	else:
		EndScreen.draw_motif(cb, i, c, 0.0, 0.85)


## A green tick and "Finished", centred.
func _draw_finished() -> void:
	var fb: Font = Text.font_bold
	var s := Text.t("TITLE_FINISHED")
	var fs := 14
	var w := fb.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := (_finished.size.x - (w + 22)) / 2
	var col := Color("#6ee7b7")
	_finished.draw_polyline(PackedVector2Array([Vector2(x, 10), Vector2(x + 5, 15), Vector2(x + 14, 4)]), Color("#1a1022", 0.8), 6.0, true)
	_finished.draw_polyline(PackedVector2Array([Vector2(x, 10), Vector2(x + 5, 15), Vector2(x + 14, 4)]), col, 3.0, true)
	_finished.draw_string_outline(fb, Vector2(x + 22, 15), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color("#1a1022", 0.8))
	_finished.draw_string(fb, Vector2(x + 22, 15), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _refresh() -> void:
	var pad := Game.control_mode == "gamepad"
	var cont := can_continue()
	_continue_btn.text = Text.t("BTN_CONTINUE_GAME")
	_continue_btn.icon = load("res://assets/ui/pad_blue.png") if pad else null
	# With a save the start button is "New game" (yellow on the gamepad; blue continues).
	_start_btn.text = Text.t("BTN_NEW_GAME" if cont else "BTN_START")
	_start_btn.icon = load("res://assets/ui/pad_yellow.png" if cont else "res://assets/ui/pad_blue.png") if pad else null
	_credits_btn.text = Text.t("BTN_CREDITS")
	_credits_btn.icon = load("res://assets/ui/pad_red.png") if pad else null
	_phases_lbl.text = Text.t("TITLE_PHASES").to_upper()
	_mute_btn.text = Text.t("UI_SOUND_OFF" if Audio.muted else "UI_SOUND_ON")
	_mute_btn.tooltip_text = Text.t("UI_UNMUTE" if Audio.muted else "UI_MUTE")
	_mode_btn.text = Text.t("UI_KEYBOARD" if Game.control_mode == "keyboard" else "UI_GAMEPAD")
	_mode_btn.tooltip_text = Text.t("UI_SWITCH_GAMEPAD" if Game.control_mode == "keyboard" else "UI_SWITCH_KEYBOARD")
	for b: Button in [_mute_btn, _mode_btn]:
		b.custom_minimum_size.x = PILL_W
		b.size.x = PILL_W
	get_node("Version").text = Text.t("UI_WORK_IN_PROGRESS") + " " + Game.build_label()
	layout()


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
		if can_continue():
			continue_pressed.emit()
		else:
			start_pressed.emit()
	elif event.is_action_pressed("choice_1"):
		_open_credits()
	elif event.is_action_pressed("choice_2") and can_continue() and event is InputEventJoypadButton:
		start_pressed.emit()


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
