class_name FertilityWheel
extends Minigame
## Level 3 (the jackpot climb), minigame 11 ("the wheel"): a casino wheel with the 28
## days of a cycle, coloured by phase. The player spins it (Space / 🟡 / click) and may
## press again to brake; it lands on a day and a card says the day, its phase and whether
## a pregnancy is possible then (the fertile window: the five days before ovulation and
## ovulation day itself) or very unlikely (but cycles vary, so protection matters every
## day). Up to MAX_SPINS spins, then Continue → completed (Main: back to the climb, the
## after-talk mg11_after on the board).

const DAYS := 28
const MAX_SPINS := 3
## The fertile window (days, inclusive) and ovulation day.
const FERTILE_FROM := 9
const OVULATION := 14
const PERIOD_TO := 5
const CENTER := Vector2(350, 226)
const RADIUS := 184.0
const CARD := Rect2(574, 40, 352, 370)
## Spin: start speed (rad/s) range, the slowing (per s), the brake, the stop speed.
const SPIN_MIN := 9.0
const SPIN_MAX := 13.0
const DRAG := 0.5
const DRAG_LIN := 0.35
const BRAKE := 2.4
const STOP_SPEED := 0.06

## Wheel rotation (rad) and speed (rad/s); state "idle" | "spinning" | "result".
var angle := 0.0
var speed := 0.0
var state := "idle"
var braking := false
var spins := 0
var result_day := 0
## The days it landed on (one per spin).
var results: Array[int] = []
## The result card's focused button: 0 = spin again, 1 = continue.
var sel := 0
var _last_seg := -1
var _tick_cd := 0.0
var _land_t := 0.0
var _t := 0.0


func _ready() -> void:
	super()
	angle = randf() * TAU
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	hint.emit({"title": "NAME_ESTRA", "text": "MG11_HINT", "hide_button": true})


static func seg_angle() -> float:
	return TAU / DAYS


## Is a pregnancy possible on this day (the fertile window)?
static func fertile(day: int) -> bool:
	return day >= FERTILE_FROM and day <= OVULATION


## The part of the cycle a day is in (an i18n key). Days 1..OVULATION are all the
## follicular phase (the legend says so); within it: the period, the days after it, the
## fertile window and ovulation.
static func phase_key(day: int) -> String:
	if day <= PERIOD_TO:
		return "MG11_PERIOD"
	if day == OVULATION:
		return "MG11_OVULATION"
	if day < OVULATION:
		return "MG11_FERTILE" if fertile(day) else "MG11_AFTER_PERIOD"
	return "MG11_LUTEAL"


## The verdict's title and text keys for a day.
static func verdict_key(day: int) -> String:
	return "MG11_POSSIBLE" if fertile(day) else "MG11_UNLIKELY"


static func day_color(day: int) -> Color:
	var c: Color
	if day <= PERIOD_TO:
		c = Color("#ef4444")
	elif day == OVULATION:
		c = Color("#fde047")
	elif fertile(day):
		c = Color("#fbbf24")
	elif day < OVULATION:
		c = Color("#2dd4bf")
	else:
		c = Color("#a78bfa")
	return c.darkened(0.12) if day % 2 == 0 else c


## The day under the pointer (top) at a wheel rotation.
static func day_at(rot: float) -> int:
	return int(fposmod(-rot, TAU) / seg_angle()) % DAYS + 1


## A small wheel (the climb's wheel row, the HUD): the 28 coloured slices and a hub.
static func draw_mini(ci: CanvasItem, c: Vector2, r: float, rot: float) -> void:
	Draw.radial_glow(ci, c, r * 1.5, Color(1, 0.6, 0.75, 0.3))
	ci.draw_circle(c, r + 3, Color("#78350f"))
	for i in DAYS:
		var a0 := -PI / 2 + rot + i * seg_angle()
		var tri := PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a0 + seg_angle()), sin(a0 + seg_angle())) * r])
		Draw.polygon_safe(ci, tri, day_color(i + 1))
	ci.draw_circle(c, r * 0.22, Color("#fbbf24"))
	Draw.polygon_safe(ci, PackedVector2Array([c + Vector2(-r * 0.18, -r - 6), c + Vector2(r * 0.18, -r - 6), c + Vector2(0, -r + r * 0.25)]), Color("#fef3c7"))


## Spins the wheel (speed < 0: a random start speed); also "spin again" from the card.
func spin(start_speed := -1.0) -> void:
	if _done or state == "spinning" or spins >= MAX_SPINS:
		return
	speed = start_speed if start_speed > 0 else randf_range(SPIN_MIN, SPIN_MAX)
	state = "spinning"
	braking = false
	spins += 1
	Audio.play_sfx("click.wav", 0.6)
	Audio.play_sfx("breathoff.wav", 0.3)


## Presses the brake while it spins.
func brake() -> void:
	if state == "spinning" and not braking:
		braking = true
		Audio.play_sfx("click.wav", 0.5)


## Developer / test shortcut: the wheel lands on `day` now.
func stop_at(day: int) -> void:
	if state != "spinning":
		spin(1.0)
	angle = -((day - 1) + 0.5) * seg_angle()
	speed = 0.0
	_land()


func _land() -> void:
	speed = 0.0
	state = "result"
	result_day = day_at(angle)
	results.append(result_day)
	_land_t = 0.0
	sel = 0 if spins < MAX_SPINS else 1
	Audio.play_sfx("finished.wav", 0.5)
	if fertile(result_day):
		Audio.play_sfx("cink-11.wav", 0.5)


## Continue (after at least one spin): back to the climb.
func continue_game() -> void:
	if state != "result" or _done:
		return
	Audio.play_sfx("click.wav", 0.5)
	finish(0.2)


## The card's buttons: [spin again, continue] (spin again only while spins are left).
func buttons() -> Array:
	var out := []
	var y := CARD.end.y - 58
	if spins < MAX_SPINS:
		out.append({"id": 0, "rect": Rect2(CARD.position.x + 18, y, 152, 42), "key": "MG11_AGAIN"})
	out.append({"id": 1, "rect": Rect2(CARD.end.x - 18 - 152, y, 152, 42), "key": "BTN_CONTINUE"})
	return out


func _activate(id: int) -> void:
	if id == 0:
		spin()
	else:
		continue_game()


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or _done:
		return
	var press := event.is_action_pressed("jump") or event.is_action_pressed("ui_accept")
	if press and not event.is_echo():
		get_viewport().set_input_as_handled()
		match state:
			"idle":
				spin()
			"spinning":
				brake()
			"result":
				if _land_t > 0.35:
					_activate(sel)
	elif state == "result" and (event.is_action_pressed("move_left") or event.is_action_pressed("move_right")):
		if spins < MAX_SPINS:
			sel = 1 - sel
			Audio.play_sfx("click.wav", 0.3)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or dialog_active or _done:
		return
	var pos: Vector2 = event.position
	if state == "result":
		for b in buttons():
			if (b.rect as Rect2).has_point(pos):
				_activate(int(b.id))
				return
	elif pos.distance_to(CENTER) < RADIUS + 20:
		if state == "idle":
			spin()
		else:
			brake()


func _process(delta: float) -> void:
	_t += delta
	_tick_cd = maxf(0.0, _tick_cd - delta)
	if state == "result":
		_land_t += delta
	if state == "spinning" and not dialog_active:
		var drag := BRAKE if braking else DRAG
		speed = maxf(0.0, speed * exp(-drag * delta) - DRAG_LIN * delta)
		angle += speed * delta
		var seg := day_at(angle)
		if seg != _last_seg:
			_last_seg = seg
			if _tick_cd <= 0:
				Audio.play_sfx("click.wav", clampf(0.15 + speed * 0.02, 0.15, 0.4))
				_tick_cd = 0.05
		if speed <= STOP_SPEED:
			_land()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var fb: Font = Text.font_bold
	var board := Rect2(117, 16, 832, 418)
	Draw.panel(self, board, Color("#2e1065"), 16, Color("#fbbf24"), 3)
	# Marquee bulbs round the board.
	var n := 40
	for i in n:
		var k := float(i) / n
		var bp := Vector2(board.position.x + 10 + (board.size.x - 20) * k, board.position.y + 8)
		var on := (i + int(_t * 8.0)) % 3 == 0
		draw_circle(bp, 3, Color("#fff7c2") if on else Color("#b45309"))
		draw_circle(Vector2(bp.x, board.end.y - 8), 3, Color("#fff7c2") if not on else Color("#b45309"))
	_draw_wheel()
	if state == "result":
		_draw_card(fb)
	else:
		_draw_legend(fb)


func _draw_wheel() -> void:
	var c := CENTER
	var r := RADIUS
	Draw.radial_glow(self, c, r * 1.25, Color(1, 0.75, 0.3, 0.25))
	draw_circle(c, r + 12, Color("#78350f"))
	draw_circle(c, r + 8, Color("#fbbf24"))
	var land := state == "result"
	for i in DAYS:
		var day := i + 1
		var a0 := -PI / 2 + angle + i * seg_angle()
		var a1 := a0 + seg_angle()
		var pts := PackedVector2Array([c])
		for j in 5:
			var a := lerpf(a0, a1, j / 4.0)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var col := day_color(day)
		if land and day == result_day:
			col = col.lerp(Color.WHITE, 0.25 + 0.2 * sin(_t * 8.0))
		Draw.polygon_safe(self, pts, col)
		draw_line(c, c + Vector2(cos(a0), sin(a0)) * r, Color("#78350f", 0.6), 1.5)
		var mid := (a0 + a1) / 2
		# The day's number near the rim, upright along the radius.
		var np := c + Vector2(cos(mid), sin(mid)) * (r - 22)
		draw_set_transform(np, mid + PI / 2, Vector2.ONE)
		Draw.text_center(self, Text.font_bold, Vector2(0, 6), str(day), 15, Color("#1e1b4b"))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		if fertile(day):
			SpriteArt.draw_heart(self, c + Vector2(cos(mid), sin(mid)) * (r - 52), 7.5, 1.0)
		if day == OVULATION:
			var ep := c + Vector2(cos(mid), sin(mid)) * (r - 78)
			draw_circle(ep, 8, Color("#fff7ed"))
			draw_circle(ep + Vector2(-2, -2), 3, Color("#fdba74"))
	# Studs on the rim (they tick past the pointer).
	for i in DAYS:
		var a := -PI / 2 + angle + i * seg_angle()
		draw_circle(c + Vector2(cos(a), sin(a)) * (r + 4), 2.5, Color("#fef3c7"))
	# The hub: SPIN / STOP.
	draw_circle(c, 46, Color("#78350f"))
	draw_circle(c, 42, Color("#fbbf24"))
	var hub := "MG11_STOP" if state == "spinning" else "MG11_SPIN"
	var hub_txt := Text.plain(Text.t(hub))
	var fs := 18
	while fs > 11 and Text.font_bold.get_string_size(hub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 74:
		fs -= 1
	if state != "result" or spins < MAX_SPINS:
		Draw.text_center(self, Text.font_bold, c + Vector2(0, 6), hub_txt, fs, Color("#78350f"))
	# The pointer at the top.
	var tip := c + Vector2(0, -r + 18)
	var pp := PackedVector2Array([c + Vector2(-17, -r - 22), c + Vector2(17, -r - 22), tip])
	Draw.polygon_safe(self, pp, Color("#fef3c7"))
	draw_polyline(pp + PackedVector2Array([pp[0]]), Color("#78350f"), 3, true)


func _draw_legend(fb: Font) -> void:
	var r := CARD
	Draw.panel(self, r, Color("#f0eee9"), 14, Color("#fbbf24"), 2)
	var rows := [[1, "MG11_PERIOD", "1–5"], [7, "MG11_AFTER_PERIOD", "6–8"], [10, "MG11_FERTILE", "9–14"],
		[OVULATION, "MG11_OVULATION", "14"], [20, "MG11_LUTEAL", "15–28"]]
	var y := r.position.y + 34
	for row in rows:
		var day: int = row[0]
		draw_circle(Vector2(r.position.x + 30, y), 11, day_color(day))
		if fertile(day):
			SpriteArt.draw_heart(self, Vector2(r.position.x + 30, y), 6.0, 1.0)
		var nm := Text.plain(Text.t(row[1]))
		draw_string(fb, Vector2(r.position.x + 52, y + 6), nm, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 130, Draw.fit_size(fb, nm, r.size.x - 130, 16, LEGEND_MIN), Color("#064e3b"))
		var dd: String = row[2]
		var dw := Text.font.get_string_size(dd, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(Text.font, Vector2(r.end.x - 20 - dw, y + 5), dd, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4a7d7b"))
		y += 44
	# The follicular phase spans the period, the days after it and the fertile window.
	draw_string(Text.font, Vector2(r.position.x + 20, y + 4), Text.plain(Text.t("MG11_FOLLICULAR_NOTE")), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40, 14, Color("#4a7d7b"))
	# How many spins are left (dots).
	for i in MAX_SPINS:
		var dc := Vector2(r.get_center().x - (MAX_SPINS - 1) * 14 + i * 28, r.end.y - 34)
		draw_circle(dc, 9, Color("#fbbf24") if i >= spins else Color("#d6d3d1"))
		draw_arc(dc, 9, 0, TAU, 16, Color("#b45309"), 1.5, true)


func _draw_card(fb: Font) -> void:
	var r := CARD
	var k := clampf(_land_t / 0.25, 0, 1)
	var possible := fertile(result_day)
	var edge := Color("#f43f5e") if possible else Color("#5f9b99")
	Draw.panel(self, r, Color("#f0eee9", k), 14, Color(edge, k), 3)
	var ink := Color("#064e3b", k)
	var x := r.position.x + 22
	var w := r.size.x - 44
	var day_fmt := Text.plain(Text.t("MG11_DAY"))
	var day_txt := day_fmt % result_day if day_fmt.contains("%d") else "%s %d" % [day_fmt, result_day]
	draw_circle(Vector2(x + 16, r.position.y + 36), 15, Color(day_color(result_day), k))
	draw_string(fb, Vector2(x + 42, r.position.y + 46), day_txt, HORIZONTAL_ALIGNMENT_LEFT, w - 42, 28, ink)
	draw_string(fb, Vector2(x, r.position.y + 82), Text.plain(Text.t(phase_key(result_day))), HORIZONTAL_ALIGNMENT_LEFT, w, 16, Color("#4a7d7b", k))
	var vk := verdict_key(result_day)
	var title := Text.plain(Text.t(vk))
	var ts := 22
	while ts > TITLE_MIN and fb.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x > w - (28 if possible else 0):
		ts -= 1
	var ty := r.position.y + 122
	if possible:
		SpriteArt.draw_heart(self, Vector2(x + 10, ty - 8), 10.0, 1.0, k)
		draw_string(fb, Vector2(x + 28, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color("#be123c", k))
	else:
		draw_string(fb, Vector2(x, ty), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color("#0f766e", k))
	var body := Text.plain(Text.t(vk + "_TEXT"))
	var f: Font = Text.font_dialog
	var bs := 16
	while bs > 12 and f.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, w, bs).y > 150:
		bs -= 1
	draw_multiline_string(f, Vector2(x, ty + 18 + f.get_ascent(bs)), body, HORIZONTAL_ALIGNMENT_LEFT, w, bs, -1, ink)
	for b in buttons():
		var br: Rect2 = b.rect
		var focused: bool = int(b.id) == sel
		Draw.panel(self, br, Color("#fbbf24", k) if focused else Color("#fef3c7", k), 21, Color("#b45309", k), 3 if focused else 1)
		var bt := Text.plain(Text.t(b.key))
		var bfs := 16
		while bfs > 11 and fb.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x > br.size.x - 16:
			bfs -= 1
		Draw.text_center(self, fb, br.get_center() + Vector2(0, bfs * 0.35), bt, bfs, Color("#78350f", k))


## The smallest sizes of the verdict's title and the legend's names (long in sk / pt).
const TITLE_MIN := 12
const LEGEND_MIN := 13


## Does every text of the card fit (tests)? See fit_problems.
static func texts_fit() -> bool:
	return fit_problems().is_empty()


## Texts that don't fit their place in the current language ([] = all fit; the tests):
## the verdict body within its area at size ≥ 12, the title (≥ 14), the legend rows, the
## note, the hub and the buttons at their smallest sizes.
static func fit_problems() -> Array:
	var out: Array = []
	var fb: Font = Text.font_bold
	var w := CARD.size.x - 44
	for vk in ["MG11_POSSIBLE", "MG11_UNLIKELY"]:
		var body := Text.plain(Text.t(vk + "_TEXT"))
		if Text.font_dialog.get_multiline_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, w, 12).y > 150:
			out.append(vk + "_TEXT")
		out.append(Draw.fit_problem(vk, fb, Text.plain(Text.t(vk)), w - (28 if vk == "MG11_POSSIBLE" else 0), TITLE_MIN))
	for k in ["MG11_PERIOD", "MG11_AFTER_PERIOD", "MG11_FERTILE", "MG11_OVULATION", "MG11_LUTEAL"]:
		out.append(Draw.fit_problem(k, fb, Text.plain(Text.t(k)), CARD.size.x - 130, LEGEND_MIN))
	out.append(Draw.fit_problem("MG11_FOLLICULAR_NOTE", Text.font, Text.plain(Text.t("MG11_FOLLICULAR_NOTE")), CARD.size.x - 40, 14))
	for k in ["MG11_SPIN", "MG11_STOP"]:
		out.append(Draw.fit_problem(k, fb, Text.plain(Text.t(k)), 74, 11))
	for k in ["MG11_AGAIN", "BTN_CONTINUE"]:
		out.append(Draw.fit_problem(k, fb, Text.plain(Text.t(k)), 152 - 16, 11))
	return out.filter(func(x): return x != "")
