class_name EndScreen
extends Control
## The end of the game (after 4E): the cycle as a ring of its 28 days (the wheel of the
## cycle's colours, FertilityWheel.day_color; day 1 at the top, clockwise) with the four
## phases round it in the order she played them: menstruation (the cave, the iron nut),
## follicular (the forest run, the sun), ovulation (the jackpot climb, a heart), luteal (the
## PMS maze, the lantern). Each has ONE take-away sentence; then a closing line and
## Play again / Main menu. The cards come in one after another; the buttons (and the keys)
## only work once everything is shown (READY), so the Enter that closed 4E can't skip it.

signal again_pressed
signal menu_pressed

## Per phase: its name, its take-away, its colour, the day its connector points at, and
## the card's place (clockwise from the top right, like the ring).
const PHASES := [
	{"name": "PHASE_MENSTRUATION", "text": "END_PHASE_1", "col": "#ef4444", "day": 3.0, "rect": Rect2(708, 74, 334, 142)},
	{"name": "PHASE_FOLLICULAR", "text": "END_PHASE_2", "col": "#2dd4bf", "day": 7.0, "rect": Rect2(708, 258, 334, 142)},
	{"name": "PHASE_OVULATION", "text": "END_PHASE_3", "col": "#fbbf24", "day": 14.0, "rect": Rect2(24, 258, 334, 142)},
	{"name": "PHASE_LUTEAL", "text": "END_PHASE_4", "col": "#a78bfa", "day": 21.5, "rect": Rect2(24, 74, 334, 142)},
]
const RING_C := Vector2(533, 238)
const RING_OUT := 112.0
const RING_IN := 66.0
const TITLE_Y := 36.0
const CLOSING_Y := 436.0
const NOTE_Y := 468.0
const TEXT_W := 1000.0
const BUTTON := Vector2(240, 52)
const BUTTON_Y := 506.0
## Card text: the phase's name beside its icon, the sentence under it (at most BODY_LINES).
const NAME_FS := 18
const NAME_MIN := 15
const BODY_SIZES := [15, 14, 13]
const BODY_LINES := 3
const CARD_PAD := 16.0
const ICON_BOX := 40.0
## Seconds: the first card, the gap between cards, the closing line, everything usable.
const FIRST := 0.5
const STEP := 0.55
const CLOSING_AT := 2.9
const READY := 3.5

var _t := 0.0
var _cards: Array[Control] = []
var _again: Button
var _menu: Button


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for i in PHASES.size():
		var c := Control.new()
		var r: Rect2 = PHASES[i].rect
		c.position = r.position
		c.size = r.size
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.modulate.a = 0.0
		c.draw.connect(_draw_card.bind(c, i))
		add_child(c)
		_cards.append(c)
	# The main menu is the main way out (green, on the left, Enter); playing again is
	# the second choice.
	_again = UiKit.button("", BUTTON, UiKit.MENU_FONT)
	_again.position = Vector2(533 + 10, BUTTON_Y)
	_again.pressed.connect(func(): _pick(again_pressed))
	add_child(_again)
	_menu = UiKit.button("", BUTTON, UiKit.MENU_FONT, Color("#059669"))
	_menu.position = Vector2(533 - BUTTON.x - 10, BUTTON_Y)
	_menu.pressed.connect(func(): _pick(menu_pressed))
	add_child(_menu)
	Game.control_mode_changed.connect(_refresh)
	Text.language_changed.connect(_refresh)
	_refresh()
	_apply()


func _refresh() -> void:
	var pad := Game.control_mode == "gamepad"
	_again.text = Text.t("BTN_PLAY_AGAIN")
	_again.icon = load("res://assets/ui/pad_red.png") if pad else null
	_menu.text = Text.t("BTN_MAIN_MENU")
	_menu.icon = load("res://assets/ui/pad_blue.png") if pad else null
	queue_redraw()
	for c in _cards:
		c.queue_redraw()


## Everything is shown and the buttons work.
func ready_for_input() -> bool:
	return _t >= READY


## Shows everything at once (tests, an impatient click).
func skip_intro() -> void:
	_t = maxf(_t, READY)
	_apply()


func buttons() -> Array:
	return [_menu, _again]


func _pick(sig: Signal) -> void:
	if ready_for_input():
		Audio.play_sfx("click.wav", 0.6)
		sig.emit()


func _process(delta: float) -> void:
	_t += delta
	_apply()
	queue_redraw()
	for c in _cards:
		c.queue_redraw()


func _apply() -> void:
	for i in _cards.size():
		_cards[i].modulate.a = clampf((_t - FIRST - i * STEP) / 0.5, 0.0, 1.0)
	var k := clampf((_t - READY + 0.4) / 0.4, 0.0, 1.0)
	for b: Button in [_again, _menu]:
		b.modulate.a = k
		b.disabled = not ready_for_input()


func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_input():
		return
	if event.is_action_pressed("confirm"):
		get_viewport().set_input_as_handled()
		_pick(menu_pressed)
	elif event.is_action_pressed("choice_1"):
		get_viewport().set_input_as_handled()
		_pick(again_pressed)


## Where day `day` (1..28, fractions allowed: 3.0 = the middle of day 3) sits on a circle
## of radius r round the ring's centre: day 1 starts at the top, clockwise.
static func day_point(day: float, r: float) -> Vector2:
	var a := -PI / 2 + (day - 0.5) / FertilityWheel.DAYS * TAU
	return RING_C + Vector2(cos(a), sin(a)) * r


## The level's motif of phase i (0..3) around c: the cave's iron nut, the run's sun, the
## climb's heart, the maze's lantern. t in seconds.
static func draw_motif(ci: CanvasItem, i: int, c: Vector2, t: float, k := 1.0) -> void:
	match i:
		0:
			Draw.iron_nut(ci, c, 13.0 * k, sin(t * 0.8) * 0.5)
		1:
			SpriteArt.draw_sun(ci, c, 14.0 * k, 12, 0.0, t)
		2:
			var s := 13.0 * k * (1.0 + 0.05 * sin(t * 3.0))
			SpriteArt.draw_heart(ci, c - Vector2(0, SpriteArt.heart_mid(s)), s)
		_:
			PmsMaze.draw_lantern(ci, c + Vector2(0, 1), t * 1000.0, 1.05 * k)


## The largest body size at which a phase's sentence takes at most BODY_LINES lines
## (-1 = it doesn't fit even at the smallest).
static func body_size(text: String, width: float) -> int:
	for fs: int in BODY_SIZES:
		if Draw.line_count(Text.font, text, width, fs) <= BODY_LINES:
			return fs
	return -1


func _draw() -> void:
	# Dusk: the maze's night clearing towards a new morning.
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1a1230"))
	Draw.radial_glow(self, RING_C, 520, Color("#7c3aed", 0.3))
	Draw.radial_glow(self, Vector2(533, 660), 420, Color("#fb923c", 0.28))
	for i in 40:
		var p := Vector2(fposmod(i * 197.3, 1066.0), fposmod(i * 113.7, 430.0))
		draw_circle(p, 1.0 + (i % 3) * 0.4, Color(1, 1, 1, 0.12 + 0.1 * sin(_t * 1.3 + i)))
	var a := clampf(_t / 0.5, 0.0, 1.0)
	var fb: Font = Text.font_bold
	var title := Text.plain(Text.t("END_TITLE"))
	Draw.text_center(self, fb, Vector2(533, TITLE_Y), title, Draw.fit_size(fb, title, TEXT_W, 28, 20), Color("#fef3c7", a))
	_draw_ring(a)
	# The connectors: each card to its part of the ring.
	for i in PHASES.size():
		var ph: Dictionary = PHASES[i]
		var r: Rect2 = ph.rect
		var ca := _cards[i].modulate.a
		var from := day_point(ph.day, RING_OUT + 6)
		var to := Vector2(r.position.x if r.position.x > 533 else r.end.x, clampf(from.y, r.position.y + 24, r.end.y - 24))
		draw_line(from, to, Color(Color(ph.col), 0.7 * ca), 2.0, true)
		draw_circle(from, 4.0, Color(Color(ph.col), ca))
	var ck := clampf((_t - CLOSING_AT) / 0.5, 0.0, 1.0)
	var closing := Text.plain(Text.t("END_CLOSING"))
	Draw.text_center(self, fb, Vector2(533, CLOSING_Y), closing, Draw.fit_size(fb, closing, TEXT_W, 22, 16), Color("#fef3c7", ck))
	var note := Text.plain(Text.t("END_NOTE"))
	Draw.text_center(self, Text.font, Vector2(533, NOTE_Y), note, Draw.fit_size(Text.font, note, TEXT_W, 15, 13), Color("#e9d5ff", 0.9 * ck))


## The ring of the 28 days in the wheel's colours, a marker going round it (the cycle
## comes round again) and "~28 days" in the middle.
func _draw_ring(a: float) -> void:
	Draw.radial_glow(self, RING_C, RING_OUT * 1.6, Color(1, 0.7, 0.8, 0.3 * a))
	var seg := TAU / FertilityWheel.DAYS
	for d in FertilityWheel.DAYS:
		var a0 := -PI / 2 + d * seg
		var pts := PackedVector2Array()
		for j in 5:
			var an := a0 + seg * j / 4.0
			pts.append(RING_C + Vector2(cos(an), sin(an)) * RING_OUT)
		for j in 5:
			var an := a0 + seg * (4 - j) / 4.0
			pts.append(RING_C + Vector2(cos(an), sin(an)) * RING_IN)
		Draw.polygon_safe(self, pts, Color(FertilityWheel.day_color(d + 1), a))
		draw_line(RING_C + Vector2(cos(a0), sin(a0)) * RING_IN, RING_C + Vector2(cos(a0), sin(a0)) * RING_OUT, Color("#1a1230", 0.55 * a), 1.5, true)
	draw_arc(RING_C, RING_OUT, 0, TAU, 96, Color("#fef3c7", 0.8 * a), 2.0, true)
	draw_arc(RING_C, RING_IN, 0, TAU, 64, Color("#fef3c7", 0.5 * a), 1.5, true)
	# Day 1: a small notch at the top where the cycle starts (and starts again).
	draw_line(RING_C + Vector2(0, -RING_OUT - 9), RING_C + Vector2(0, -RING_OUT + 2), Color("#fef3c7", a), 3.0, true)
	# The marker: once round in 14 s, clockwise.
	var day := fposmod(_t / 14.0, 1.0) * FertilityWheel.DAYS + 0.5
	var m := day_point(day, (RING_OUT + RING_IN) / 2)
	draw_circle(m, 9.0, Color(1, 1, 1, 0.35 * a))
	draw_circle(m, 5.5, Color(1, 1, 1, a))
	var fb: Font = Text.font_bold
	Draw.text_center(self, fb, RING_C + Vector2(0, -8), "~28", 28, Color("#fef3c7", a))
	var days := Text.plain(Text.t("END_DAYS"))
	Draw.text_center(self, Text.font, RING_C + Vector2(0, 22), days, Draw.fit_size(Text.font, days, RING_IN * 2 - 30, 15, 11), Color("#e9d5ff", a))


func _draw_card(c: Control, i: int) -> void:
	var ph: Dictionary = PHASES[i]
	var col := Color(str(ph.col))
	var r := Rect2(Vector2.ZERO, c.size)
	Draw.panel(c, r, Color("#120c22", 0.82), 14, Color(col, 0.9), 2)
	var ic := Vector2(CARD_PAD + ICON_BOX / 2, CARD_PAD + ICON_BOX / 2 - 2)
	c.draw_circle(ic, ICON_BOX / 2 + 2, Color(col, 0.18))
	draw_motif(c, i, ic, _t)
	var fb: Font = Text.font_bold
	var name := Text.plain(Text.t(ph.name))
	var nx := CARD_PAD + ICON_BOX + 12
	var nfs := Draw.fit_size(fb, name, r.size.x - nx - CARD_PAD, NAME_FS, NAME_MIN)
	c.draw_string(fb, Vector2(nx, ic.y + nfs * 0.35), name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, col.lightened(0.25))
	var body := Text.plain(Text.t(ph.text))
	var w := r.size.x - CARD_PAD * 2
	var fs := body_size(body, w)
	if fs < 0:
		fs = BODY_SIZES[-1]
	var f: Font = Text.font
	c.draw_multiline_string(f, Vector2(CARD_PAD, CARD_PAD + ICON_BOX + 8 + f.get_ascent(fs)), body, HORIZONTAL_ALIGNMENT_LEFT, w, fs, BODY_LINES, Color("#f8f5ee"))


## Texts that don't fit (tests; current language).
static func fit_problems() -> Array:
	var out: Array = []
	var fb: Font = Text.font_bold
	out.append(Draw.fit_problem("END_TITLE", fb, Text.plain(Text.t("END_TITLE")), TEXT_W, 20))
	out.append(Draw.fit_problem("END_CLOSING", fb, Text.plain(Text.t("END_CLOSING")), TEXT_W, 16))
	out.append(Draw.fit_problem("END_NOTE", Text.font, Text.plain(Text.t("END_NOTE")), TEXT_W, 13))
	out.append(Draw.fit_problem("END_DAYS", Text.font, Text.plain(Text.t("END_DAYS")), RING_IN * 2 - 30, 11))
	for ph: Dictionary in PHASES:
		var r: Rect2 = ph.rect
		out.append(Draw.fit_problem(ph.name, fb, Text.plain(Text.t(ph.name)), r.size.x - CARD_PAD * 2 - ICON_BOX - 12, NAME_MIN))
		var body := Text.plain(Text.t(ph.text))
		var fs := body_size(body, r.size.x - CARD_PAD * 2)
		if fs < 0:
			out.append("%s (more than %d lines)" % [ph.text, BODY_LINES])
		elif CARD_PAD + ICON_BOX + 8 + Text.font.get_height(fs) * BODY_LINES > r.size.y - 8:
			out.append("%s (too tall for its card)" % ph.text)
	for k in ["BTN_PLAY_AGAIN", "BTN_MAIN_MENU"]:
		out.append(Draw.fit_problem(k, fb, Text.plain(Text.t(k)), BUTTON.x - 24 - 30, UiKit.MENU_FONT))
	return out.filter(func(x): return x != "")
