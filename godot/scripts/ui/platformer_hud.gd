class_name PlatformerHud
extends Control
## Cave HUD: iron counter (top-left) and the breath pill (top-right, or under
## the player while recharging / held by a cramp).

const BG := Color("#f0eee9")
const INK := Color("#064e3b")
const TEAL := Color("#5f9b99")
const RUST := Color("#b15827")
const PILL := Vector2(140, 48)

var platformer: Platformer
var breath_error := false
var _last_iron := -1
var _bounce := 0.0
var _spin := 0.0
## The climb's heart meter: a pop when a ready heart is added; the last count seen.
var _heart_pop := 0.0
var _hearts_seen := 0
## The abilities usable right now, under the top-right indicator (AbilityHints).
var hints := AbilityHints.new()
## The climb's counters fade during the transformation (colours through _a()).
var _alpha := 1.0
## The maze's item slots: a little pop when one fills.
var _slot_pop := [0.0, 0.0, 0.0]
var _items_seen: Array[bool] = [false, false, false]


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_spin += delta * TAU / 4.0
	if Game.iron != _last_iron:
		_last_iron = Game.iron
		_bounce = 0.3
	_bounce = maxf(0, _bounce - delta)
	if platformer and platformer.is_climb():
		if platformer.hearts > _hearts_seen:
			_heart_pop = 0.4
		_hearts_seen = platformer.hearts
	_heart_pop = maxf(0, _heart_pop - delta)
	if platformer and platformer.is_pms():
		for i in 3:
			if platformer.pms_found[i] and not _items_seen[i]:
				_slot_pop[i] = 0.45
				_items_seen[i] = true
		for i in 3:
			_slot_pop[i] = maxf(0.0, _slot_pop[i] - delta)
	hints.update(delta, _wanted_hints() if platformer else [])


## The keys of the ability hints shown right now.
func hint_lines() -> Array:
	return hints.active()


## Cave: what the breath can do now (attack / charge it / the rhythm while charging).
## Climb: what the ready hearts can buy now (heart boost / rocket fuel, only while
## affordable), then the active power-ups with their time. Other levels: none.
func _wanted_hints() -> Array:
	var pf := platformer
	if pf.is_pms():
		# The maze: the calming breath (hold), and how long the calm lasts.
		if pf.dialog_open or pf.hold_input:
			return []
		if pf.calm_t > 0:
			return [{"key": "HINT_PMS_CALM", "k": pf.calm_t / Platformer.CALM_TIME}]
		return ["HINT_PMS_BREATHE"]
	if pf.prerod_t >= 0:
		return []
	if pf.is_climb():
		var out: Array = []
		if pf.climb_won or pf.hold_input or pf.phase_showing():
			return out
		if pf.hearts >= Platformer.HEART_BOOST_COST:
			out.append("HINT_CLIMB_HEART_BOOST")
		if pf.thrusting:
			out.append({"key": "HINT_CLIMB_FUEL_BURN", "k": pf.fuel_left() / Platformer.HEART_SLOTS})
		elif pf.hearts >= 1:
			out.append("HINT_CLIMB_FUEL")
		for k in Platformer.POWERS:
			if pf.climb_power.has(k):
				var full := Platformer.ROCKET_TIME if k == "rocket" else Platformer.POWER_TIME
				out.append({"key": "HINT_CLIMB_" + String(k).to_upper(), "k": float(pf.climb_power[k]) / full})
		return out
	if pf.is_meadow() or pf.is_summit() or not Game.has_breathing:
		return []
	var p := pf.p
	if pf.dialog_open or p.is_dead:
		return []
	if p.is_recharging:
		return ["HINT_BREATH_RHYTHM"]
	if p.breath_charges > 0 and p.held_by_cramp == -1:
		return ["HINT_BREATH_ATTACK"]
	if p.breath_charges == 0:
		return ["HINT_BREATH_CHARGE"]
	return []


func _draw() -> void:
	if platformer == null:
		return
	var font: Font = Text.font_bold
	if platformer.is_meadow():
		_draw_meadow(font)
		if Game.has_breathing:
			_draw_breath(font)
		return
	if platformer.is_pms():
		_draw_pms(font)
		return
	if platformer.is_climb():
		_draw_climb(font)
		return
	# Iron: one big nut with the count in its middle (top-left, like the sun in level 2).
	var r := draw_iron(self, font, Vector2(60, 58), Game.iron, _bounce, _spin)
	if Game.has_breathing:
		var br := _draw_breath(font)
		if not platformer.is_summit():
			# The hints follow the pill (under Kyra while she breathes / is held).
			var follow := _breath_follows()
			hints.draw(self, Vector2(br.get_center().x if follow else br.end.x, br.end.y), follow)
	if platformer.is_summit():
		_draw_upgrades(font, r.end.y + 8)
		# Floor counter (Icy Tower) and the combo.
		var ft := "%s %d" % [Text.plain(Text.t("HUD_FLOOR")), platformer.floor_now]
		var fw := font.get_string_size(ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var fr := Rect2(1066 / 2 - fw / 2 - 14, 16, fw + 28, 34)
		Draw.panel(self, fr, BG, 17, Color(TEAL, 0.2), 2)
		draw_string(font, Vector2(fr.position.x + 14, fr.position.y + 24), ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
		if platformer.combo >= 2:
			var ct := "COMBO x%d" % platformer.combo
			var cw := font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			var cr := Rect2(1066 / 2 - cw / 2 - 14, 56, cw + 28, 34)
			Draw.panel(self, cr, Color("#78350f"), 17, Color("#fbbf24"), 2)
			draw_string(font, Vector2(cr.position.x + 14, cr.position.y + 24), ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#fef3c7"))


## The big nut of the HUD centred on `c`; returns its box (for what goes below).
static func draw_iron(ci: CanvasItem, font: Font, c: Vector2, count: int, bounce := 0.0, spin := 0.0) -> Rect2:
	c.y += -sin(bounce / 0.3 * PI) * 8.0
	var r := 42.0
	var tex := SpriteArt.texture("iron", 0.0)
	if tex:
		# The drawn nut, face on (its first frame), a little larger than the code one.
		var h := r * 2.3
		var w := tex.get_width() * h / tex.get_height()
		ci.draw_texture_rect(tex, Rect2(c.x - w / 2, c.y - h / 2, w, h), false)
	else:
		var hex := PackedVector2Array()
		for i in 6:
			var a := i / 6.0 * TAU - PI / 2
			hex.append(c + Vector2(cos(a), sin(a)) * r)
		ci.draw_colored_polygon(hex, Color("#9ca3af"))
		ci.draw_polyline(hex + PackedVector2Array([hex[0]]), Color("#374151"), 3.0, true)
		ci.draw_circle(c, r * 0.5, Color("#4b5563"))
	# The count in the hole: white with a dark outline, readable on any nut.
	var label := str(count)
	var fs := 28 if label.length() < 3 else 22
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(c.x - tw / 2, c.y + fs * 0.36)
	ci.draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color("#1f2937"))
	ci.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2)


## Level 2 power-ups earned so far (and the dash cooldown).
func _draw_upgrades(font: Font, y: float) -> void:
	var x := 16.0
	for u in [["jump", "UPGRADE_JUMP"], ["dash", "UPGRADE_DASH"], ["double", "UPGRADE_DOUBLE"]]:
		if not Game.upgrades.has(u[0]):
			continue
		var label := Text.plain(Text.t(u[1]))
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var r := Rect2(x, y, tw + 24, 26)
		Draw.panel(self, r, BG, 13, Color(TEAL, 0.2), 2)
		if u[0] == "dash":
			var cd: float = platformer.p.dash_cooldown
			if cd > 0:
				Draw.panel(self, Rect2(r.position, Vector2(r.size.x * (1.0 - clampf(cd / 0.9, 0, 1)), r.size.y)), Color(TEAL, 0.25), 13)
		draw_string(font, Vector2(r.position.x + 12, r.position.y + 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
		x += r.size.x + 6


## The pill sits under Kyra while she is held by a cramp or breathes to recharge.
func _breath_follows() -> bool:
	var p := platformer.p
	return p.held_by_cramp != -1 or (p.is_recharging and p.breath_charges == 0 and p.breathing_cooldown <= 0)


## Draws the breath pill; returns its box.
func _draw_breath(font: Font) -> Rect2:
	var p := platformer.p
	var follow := _breath_follows()
	var pos := Vector2(size.x - 16 - PILL.x, 16)
	if follow:
		pos = Vector2(p.x + p.width / 2 - PILL.x / 2, p.y + p.height - platformer.camera_y + 49)
	var scale_k := 1.1 if p.breath_success else 1.0
	var rect := Rect2(pos - PILL * (scale_k - 1) / 2, PILL * scale_k)
	if p.breath_failed or (p.is_recharging and p.breath_error_timer > 0 and breath_error):
		rect.position.x += sin(Time.get_ticks_msec() / 25.0) * 4
	Draw.panel(self, rect, BG, 16)
	if p.breath_failed:
		Draw.panel(self, rect.grow(2), Color(0, 0, 0, 0), 18, Color("#ef4444"), 4)
	var c := rect.get_center()
	var keyboard := Game.control_mode == "keyboard"
	if p.breath_charges > 0 and p.held_by_cramp == -1:
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0)
		_progress_outline(rect, 1.0, Color(TEAL, pulse))
		if p.has_used_breath:
			var n := p.breath_charges
			for i in n:
				var x := c.x + (i - (n - 1) / 2.0) * 26
				if keyboard:
					_wind_icon(Vector2(x, c.y), INK)
				else:
					draw_texture_rect(load("res://assets/ui/pad_red.png"), Rect2(x - 10, c.y - 10, 20, 20), false)
		else:
			_key_hint(font, c, "SHIFT" if keyboard else "PUSH", keyboard)
	elif p.is_recharging and p.breathing_cooldown <= 0:
		var k := minf(1.0, p.breath_timer / 12.0)
		_progress_outline(rect, k, RUST if breath_error else TEAL)
		var syms := ["up", "hold", "down"]
		for i in 3:
			var col := Color("#d1d5db")
			if p.breath_index == i:
				col = Color("#ef4444") if breath_error else Color("#10b981")
			elif p.breath_index > i:
				col = Color("#10b981", 0.5)
			_shape(syms[i], Vector2(c.x + (i - 1) * 34, c.y), col)
	else:
		if p.breath_charges > 0:
			_key_hint(font, c, "SHIFT" if keyboard else "PUSH", keyboard)
		else:
			var s := "SHIFT" if keyboard else "RELOAD"
			Draw.text_center(self, font, c + Vector2(-12 if keyboard else -14, 0), s, 18, INK)
			if keyboard:
				_reload_icon(c + Vector2(30, 0))
			else:
				draw_texture_rect(load("res://assets/ui/pad_red.png"), Rect2(c.x + 34, c.y - 10, 20, 20), false)
	return rect


func _key_hint(font: Font, c: Vector2, s: String, keyboard: bool) -> void:
	Draw.text_center(self, font, c + Vector2(-14, 0), s, 18, INK)
	if keyboard:
		_wind_icon(c + Vector2(30, 0), INK)
	else:
		draw_texture_rect(load("res://assets/ui/pad_red.png"), Rect2(c.x + 24, c.y - 10, 20, 20), false)


func _wind_icon(c: Vector2, col: Color) -> void:
	# Three gusts with curled ends (the lucide "wind" icon).
	for row in [[-6.0, 14.0], [0.0, 18.0], [6.0, 12.0]]:
		var y: float = c.y + row[0]
		var len: float = row[1]
		draw_line(Vector2(c.x - 10, y), Vector2(c.x - 10 + len - 3, y), col, 2.0, true)
		draw_arc(Vector2(c.x - 10 + len - 3, y - 2.5), 2.5, PI / 2, -PI, 8, col, 2.0, true)


func _reload_icon(c: Vector2) -> void:
	draw_arc(c, 8, -PI * 0.25, PI * 1.4, 16, INK, 2.0, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(6, -9), c + Vector2(10, -2), c + Vector2(3, -3)]), INK)


func _shape(kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"up":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(10, 8), c + Vector2(-10, 8)]), col)
		"hold":
			draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), col)
		"down":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 10), c + Vector2(10, -8), c + Vector2(-10, -8)]), col)


## Outline that runs clockwise along the pill's rounded edge as the breath
## progresses (like the web build's SVG stroke-dashoffset), corners included.
func _progress_outline(rect: Rect2, k: float, col: Color) -> void:
	var path := _rounded_path(rect.grow(-2), 14.0)
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var left := total * clampf(k, 0, 1)
	var out := PackedVector2Array([path[0]])
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if left >= seg:
			out.append(path[i])
			left -= seg
		else:
			if seg > 0:
				out.append(path[i - 1].lerp(path[i], left / seg))
			break
	if out.size() > 1:
		draw_polyline(out, col, 4.0, true)


## Closed rounded-rectangle path starting at the top edge after the top-left corner.
func _rounded_path(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	pts.append(Vector2(r.position.x + rad, r.position.y))
	for c in corners:
		for i in 9:
			var a: float = c[1] + i / 8.0 * PI / 2
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	pts.append(Vector2(r.position.x + rad, r.position.y))
	return pts


## Level 2: caught seeds (top left) and the water vessel (bottom centre).
func _draw_meadow(font: Font) -> void:
	var label := "%d / %d" % [Game.seeds, Game.SEEDS_NEEDED]
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var r := Rect2(16, 16, tw + 20 + 24 + 30, 48)
	Draw.panel(self, r, BG, 16, Color(TEAL, 0.2), 2)
	draw_string(font, Vector2(r.position.x + 20, r.position.y + 31), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	var ic := Vector2(r.end.x - 26, r.position.y + 24)
	Draw.radial_glow(self, ic, 16 + sin(_spin * 2) * 2, Color(1, 0.85, 0.4, 0.5), Color(1, 0.98, 0.8, 0.95))
	draw_circle(ic, 6, Color("#fff4c2"))
	# The vessel.
	var v := Rect2(1066 / 2 - 170, 600 - 44, 340, 28)
	Draw.panel(self, v, BG, 14, Color(TEAL, 0.2), 2)
	var inner := Rect2(v.position.x + 6, v.position.y + 6, v.size.x - 12, v.size.y - 12)
	Draw.panel(self, inner, Color("#dbeafe"), 8)
	var fill := inner
	fill.size.x = inner.size.x * Game.water / 100.0
	if fill.size.x > 2:
		Draw.panel(self, fill, Color("#5fb3f0"), 8)
	for k: int in [25, 50, 75]:
		var x := inner.position.x + inner.size.x * k / 100.0
		var on := Game.water >= k
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(INK, 0.35), 2.0)
		var tag: String = {25: "UPGRADE_THREAD", 50: "UPGRADE_PULL", 75: "UPGRADE_SHIELD"}[k]
		var txt := Text.plain(Text.t(tag))
		Draw.text_center(self, Text.font, Vector2(x, v.position.y - 8), txt, 10, Color(INK if on else Color(INK, 0.45)))
	draw_string(font, Vector2(v.position.x + 12, v.position.y + 20), "%d %%" % Game.water, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	var wl := Text.plain(Text.t("HUD_WATER"))
	var ww := Text.font.get_string_size(wl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(Text.font, Vector2(v.end.x - ww - 12, v.position.y + 19), wl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, INK)



## The jackpot climb (level 5): the board at the bottom edge (ticker, marquee), the spinner
## top-left (a bell or a joker spins it), the heart meter top-right with the ability hints
## under it, and the banner. No score, no floor counter.
func _draw_climb(font: Font) -> void:
	var pf := platformer
	var t := pf.time_ms
	_draw_board(font, t)
	# The transformation: the counters fade out (the casino winds down).
	_alpha = (1.0 - pf.wind) * pf.counters_in()
	if _alpha <= 0.01:
		return
	# The spinner (top-left): still when idle, a bell or a joker spins it. No floor counter.
	_draw_reels(font, t, SPINNER)
	# The heart meter (top-right) and what the hearts can buy under it.
	var pill := Rect2(1066 - 16 - HEART_PILL.x, 16, HEART_PILL.x, HEART_PILL.y)
	draw_heart_pill(self, pill, pf.hearts, pf.heart_bar / 100.0, t / 1000.0, pf.heart_short > 0, _heart_pop, _alpha, pf.fuel_burn)
	hints.draw(self, Vector2(pill.end.x, pill.end.y))
	# The banner (JACKPOT!, SUPER JUMP! …).
	if not pf.banner.is_empty() and pf.prerod_t < 0:
		var bt: float = pf.banner.t
		var k := clampf(bt / 0.2, 0, 1)
		var fade := clampf((1.8 - bt) / 0.4, 0, 1)
		var txt: String = pf.banner.text
		var sc := (0.4 + 0.75 * k - 0.15 * clampf((bt - 0.2) / 0.2, 0, 1)) * (1.0 + 0.04 * sin(t / 60.0))
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54).x
		draw_set_transform(Vector2(1066 / 2, 160), sin(t / 200.0) * 0.04, Vector2(sc, sc))
		Draw.radial_glow(self, Vector2.ZERO, tw * 0.6, Color(1, 0.8, 0.2, 0.35 * fade))
		draw_string_outline(font, Vector2(-tw / 2, 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, 10, Color(0.47, 0.2, 0.03, fade))
		draw_string(font, Vector2(-tw / 2, 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(1, 0.88, 0.3, fade))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


const HEART_PILL := Vector2(176, 48)
## The climb's spinner top-left: the heart meter's height and panel.
const SPINNER := Rect2(16, 16, 150, 48)


## The heart meter (like the forest run's water pill): HEART_SLOTS hearts, the ready ones
## filled; the bar that fills the next one as a line round the pill. `short`: the missing
## hearts blink red (an ability tried without enough); `pop` > 0: the newest one pops;
## `burn`: how much of the last ready heart rocket fuel has burnt (it shrinks).
static func draw_heart_pill(ci: CanvasItem, r: Rect2, ready: int, bar_k: float, t: float, short := false, pop := 0.0, alpha := 1.0, burn := 0.0) -> void:
	Draw.panel(ci, r, Color(BG, alpha), 16, Color(0.96, 0.25, 0.37, 0.25 * alpha), 2)
	var step := (r.size.x - 24) / Platformer.HEART_SLOTS
	var blink := short and fmod(t, 0.2) < 0.12
	for i in Platformer.HEART_SLOTS:
		var c := Vector2(r.position.x + 12 + step * (i + 0.5), r.get_center().y + 1)
		if i < ready:
			var s := 12.0 * (1.0 + (0.35 * sin(clampf(pop / 0.4, 0, 1) * PI) if i == ready - 1 else 0.0))
			if i == ready - 1 and burn > 0.0:
				# Rocket fuel burning it: the heart shrinks into its empty slot.
				_heart_shape(ci, c, 11.0, Color(0.58, 0.5, 0.6, 0.3 * alpha))
				s *= maxf(0.15, 1.0 - burn)
			SpriteArt.draw_heart(ci, c, s, 1.0, alpha)
		else:
			var empty := Color(0.94, 0.27, 0.27, 0.75 * alpha) if blink else Color(0.58, 0.5, 0.6, 0.3 * alpha)
			_heart_shape(ci, c, 11.0, empty)
	var col := Color("#f43f5e").lerp(Color("#f9a8d4"), 0.3)
	ForestRunner.progress_outline(ci, r, bar_k, Color(col, alpha))


static func _heart_shape(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := i / 24.0 * TAU
		pts.append(c + Vector2(16.0 * pow(sin(a), 3), -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a)) + 2.0) * s / 16.0)
	Draw.polygon_safe(ci, pts, col)


## The board: a dialog-box panel (Estrogenka on the left) with a casino marquee and the
## news ticker running right → left.
## A board dialog (Platformer.board_talk) replaces the ticker: the speaker's portrait
## and name, the line wrapped in BOARD_TEXT and a thin line for its reading time.
func _draw_board(font: Font, t: float) -> void:
	var pf := platformer
	var r := Rect2(0, 600 - Platformer.BOARD_H, 1066, Platformer.BOARD_H)
	draw_rect(Rect2(r.position - Vector2(0, 10), Vector2(r.size.x, 10)), Color(0, 0, 0, 0.12))
	draw_rect(r, DialogBox.PANEL_BG)
	# The ticker (under the avatar / edge covers).
	var ty := r.position.y + 96
	var talk: Dictionary = pf.board_talk
	var note: Dictionary = pf.phase_note
	# A story dialog covers the board (it is translucent): no ticker under it.
	for seg in ([] if pf.dialog_open or not talk.is_empty() or not note.is_empty() else pf.ticker):
		var sx: float = seg.x
		if sx > 1066 or sx + seg.w < 0:
			continue
		var col := Color("#b45309") if seg.event else INK
		if pf.prerod_t >= 0:
			_draw_loose_letters(font, seg, ty, col, pf.prerod_t)
			continue
		draw_string(font, Vector2(sx, ty), seg.text, HORIZONTAL_ALIGNMENT_LEFT, -1, Platformer.TICKER_FS, col)
		var dx: float = sx + seg.w + Platformer.TICKER_GAP / 2
		draw_colored_polygon(PackedVector2Array([Vector2(dx, ty - 15), Vector2(dx + 6, ty - 8), Vector2(dx, ty - 1), Vector2(dx - 6, ty - 8)]), Color("#f59e0b"))
	# Edge covers: the text comes out from behind the avatar's column and the right edge.
	draw_rect(Rect2(0, r.position.y + 14, Platformer.TICKER_LEFT, r.size.y - 14), Color(DialogBox.PANEL_BG, 1))
	draw_rect(Rect2(1066 - 16, r.position.y + 14, 16, r.size.y - 14), Color(DialogBox.PANEL_BG, 1))
	# Estrogenka, like in a dialog.
	var av := Rect2(16, r.position.y + 18, Platformer.BOARD_H - 34, Platformer.BOARD_H - 34)
	Draw.panel(self, av, DialogBox.PANEL_BG.darkened(0.06), 12, Color("#fbbf24"), 3)
	var speaker: String = talk.get("speaker", "Estrogenka") if not talk.is_empty() else "Estrogenka"
	var tex := SpriteArt.portrait(speaker, t)
	if tex:
		var ts := tex.get_size()
		var k := maxf((av.size.x - 8) / ts.x, (av.size.y - 8) / ts.y)
		var src := Rect2((ts - (av.size - Vector2(8, 8)) / k) / 2, (av.size - Vector2(8, 8)) / k)
		draw_texture_rect_region(tex, av.grow(-4), src)
	if not note.is_empty():
		_draw_phase_note(font, note, r, t)
	else:
		draw_string(font, Vector2(Platformer.TICKER_LEFT, r.position.y + 44), Text.speaker_name(speaker).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4a7d7b"))
	if not talk.is_empty() and not pf.dialog_open and note.is_empty():
		_draw_board_talk(talk, r)
	# Gold trim and the marquee: bulbs chasing along the top edge.
	# The new phase: the strip lights up bulb by bulb from the left, then blinks all together.
	var pt: float = note.get("t", -1.0)
	var strip_k := clampf(pt / Platformer.PHASE_BULBS, 0, 1) if pt >= 0 else 1.0
	var gold := Color("#f59e0b")
	if pt >= 0 and pt < Platformer.PHASE_TIME - 0.6 and fmod(pt, 0.3) < 0.15:
		gold = Color("#fde047")
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x * strip_k, 4), gold)
	draw_rect(Rect2(r.position.x, r.position.y + 14, r.size.x * strip_k, 2), Color("#fbbf24", 0.8))
	var step := 26.0
	var n := int(1066 / step)
	var chase := int(t / 110.0)
	for i in n + 1:
		var c := Vector2(8 + i * step, r.position.y + 9)
		var on := (i + chase) % 3 == 0 and pf.wind < 0.5
		if pt >= 0:
			if pt < Platformer.PHASE_BULBS:
				# Lighting up one by one, left to right (the rest still dark).
				if float(i) / n > strip_k:
					draw_circle(c, 3.5, Color("#92400e", 0.6))
					continue
				on = float(i) / n > strip_k - 0.12
			elif pt < Platformer.PHASE_TIME - 0.6:
				on = fmod(pt, 0.3) < 0.15
		if on:
			draw_circle(c, 7, Color(1, 0.85, 0.3, 0.35))
		draw_circle(c, 3.5, Color("#fff7c2") if on else Color("#d97706"))


## The new phase's announcement on the board (Platformer.phase_note): a big title popping
## in and a sub-line under it, both fading out at the end; the speaker's name is not shown.
func _draw_phase_note(font: Font, note: Dictionary, r: Rect2, t: float) -> void:
	var nt: float = note.t
	var a := clampf(nt / 0.25, 0, 1) * clampf((Platformer.PHASE_TIME - nt) / 0.4, 0, 1)
	var title := Text.plain(Text.t(str(note.key)))
	var size := 34
	var right := 1066.0 - 24.0
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	while tw > right - Platformer.TICKER_LEFT and size > 20:
		size -= 2
		tw = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pop := 1.0 + 0.25 * (1.0 - clampf(nt / 0.3, 0, 1)) + 0.02 * sin(t / 90.0)
	var tp := Vector2(Platformer.TICKER_LEFT, r.position.y + 62)
	draw_set_transform(tp, 0, Vector2(pop, pop))
	Draw.radial_glow(self, Vector2(tw / 2, -10), tw * 0.55, Color(1, 0.8, 0.25, 0.25 * a))
	draw_string_outline(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0.47, 0.2, 0.03, a))
	draw_string(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.86, 0.3, a))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var sub: String = str(note.get("sub", ""))
	if sub != "":
		var line := Text.plain(Text.t(sub))
		var f: Font = Text.font_dialog
		var sa := clampf((nt - 0.35) / 0.3, 0, 1) * a
		var w := right - Platformer.TICKER_LEFT
		var fs := 17
		while fs > 12 and f.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, w, fs).y > 52:
			fs -= 1
		draw_multiline_string(f, Vector2(Platformer.TICKER_LEFT, r.position.y + 86 + f.get_ascent(fs)), line, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, Color(INK, sa))


## The transformation: the stopped ticker's letters come loose one by one and drift up
## and away (each its own delay, sway and spin), fading.
func _draw_loose_letters(font: Font, seg: Dictionary, ty: float, col: Color, pt: float) -> void:
	var x: float = seg.x
	var text: String = seg.text
	for i in text.length():
		var ch := text[i]
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, Platformer.TICKER_FS).x
		var h := fposmod(sin((x + i * 7.3) * 12.9898) * 43758.5453, 1.0)
		var k := clampf((pt - 0.15 - h * 0.7) / 1.4, 0, 1)
		var e := k * k
		if x > Platformer.TICKER_LEFT - 20 and x < 1066:
			var pos := Vector2(x + sin(pt * 2.0 + h * 9.0) * 14.0 * e, ty - e * (90.0 + 160.0 * h))
			draw_set_transform(pos, (h - 0.5) * 1.6 * e, Vector2.ONE)
			draw_string(font, Vector2.ZERO, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, Platformer.TICKER_FS, Color(col, col.a * (1.0 - k)))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		x += w


## The board dialog's line (wrapped, the largest size that fits) and its reading-time line.
func _draw_board_talk(talk: Dictionary, r: Rect2) -> void:
	var text := Platformer.board_line(talk.get("key", ""))
	var size := Platformer.board_text_size(text)
	if size < 0:
		size = DialogBox.TEXT_SIZES[-1]
	var area := Rect2(r.position + Platformer.BOARD_TEXT.position, Platformer.BOARD_TEXT.size)
	var f: Font = Text.font_dialog
	var a := clampf(float(talk.t) / 0.2, 0, 1)
	draw_multiline_string(f, Vector2(area.position.x, area.position.y + f.get_ascent(size)), text, HORIZONTAL_ALIGNMENT_LEFT, area.size.x, size, -1, Color(INK, a))
	var k := clampf(float(talk.t) / maxf(0.1, float(talk.dur)), 0, 1)
	var ly := r.end.y - 8
	draw_line(Vector2(area.position.x, ly), Vector2(area.end.x, ly), Color("#fbbf24", 0.25), 2)
	draw_line(Vector2(area.position.x, ly), Vector2(area.position.x + area.size.x * k, ly), Color("#f59e0b"), 2)


## The spinner top-left: a light pill like the heart meter (SPINNER: same height), three
## white windows. Idle it rests (still) on the last spin's symbols; a bell or a joker spins
## it (Platformer.slot_spin): symbols slide down each window until it stops one after
## another (a click each) on three bells / three jokers. The power-up's name goes to the
## board's ticker, not here.
func _draw_reels(font: Font, t: float, box: Rect2) -> void:
	# Three separate white cards with a soft shadow, no frame and no borders (like a
	# phone slot machine); big symbols; a spin scrolls them down at a steady speed and
	# the cards stop one after another.
	var spin: Dictionary = platformer.slot_spin
	var active := not spin.is_empty()
	var gap := 7.0
	var rw := (box.size.x - gap * 2) / 3.0
	var rh := box.size.y
	var syms := ["heart", "joker", "bell", "heart", "bell", "joker"]
	for i in 3:
		var rr := Rect2(box.position.x + i * (rw + gap), box.position.y, rw, rh)
		# Soft shadow: a few widening, fading rounded rects under the card.
		for k in 4:
			var g := 2.0 + k * 2.0
			Draw.panel(self, Rect2(rr.position + Vector2(-g / 2, 3 + k), rr.size + Vector2(g, g / 2)), _a(Color(0, 0, 0, 0.05)), 12 + g / 2)
		Draw.panel(self, rr, _a(Color.WHITE), 11)
		var c := rr.get_center()
		var stopped: bool = active and int(spin.stops) > i
		if active and not stopped:
			# Spinning: a strip of symbols sliding down; near the card's edges they
			# shrink (a drum), so nothing leaves the card.
			var step := rh * 0.8
			var pos := t / 1000.0 * 900.0 + i * 37.0
			var off := fmod(pos, step)
			var base := int(pos / step)
			for j in range(-1, 2):
				var dy := off - j * step
				var k2 := clampf(1.0 - absf(dy) / (rh * 0.55), 0, 1)
				if k2 <= 0.05:
					continue
				var sym: String = syms[(base + j + i * 2 + 60) % syms.size()]
				_reel_symbol(font, sym, Vector2(c.x, c.y + dy * 0.85), k2)
		else:
			var rest: Array = spin.result if active else platformer.spin_rest
			# A little settle bounce right after a card stops.
			var bounce := 0.0
			if active:
				var since: float = float(spin.t) - float(spin.get("stop_at", [0, 0, 0])[i]) if spin.has("stop_at") else 1.0
				if since >= 0 and since < 0.25:
					bounce = sin(since / 0.25 * PI) * 4.0
			_reel_symbol(font, rest[i], c + Vector2(0, bounce), 1.0)


func _reel_symbol(font: Font, sym: String, c: Vector2, k := 1.0) -> void:
	match sym:
		"heart":
			SpriteArt.draw_heart(self, c, 14.0 * k, 1.0, _alpha)
		"bell":
			SpriteArt.draw_bell(self, c, 13.0 * k, 0.0, _alpha)
		"joker":
			SpriteArt.draw_joker(self, c, 38.0 * k, 0.0, _alpha)
		_:
			Draw.text_center(self, font, c + Vector2(0, 12), sym, 34, _a(Color("#dc2626")))


func _a(c: Color) -> Color:
	return Color(c, c.a * _alpha)


## The PMS maze (level 6): the three comfort items as slots (top-left, upright, filled when
## found), the breath pill (top-right: fills while held, then the calm drains) and the hints.
func _draw_pms(font: Font) -> void:
	var pf := platformer
	var t := pf.time_ms
	var label := Text.plain(Text.t("PMS_ITEMS"))
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var box := Rect2(16, 16, 24 + lw + 3 * 52, 56)
	Draw.panel(self, box, BG, 18, Color("#b27c94", 0.5), 2)
	draw_string(font, Vector2(box.position.x + 14, box.position.y + 33), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK)
	for i in 3:
		var c := Vector2(box.position.x + 24 + lw + 22 + i * 52, box.get_center().y)
		var got: bool = pf.pms_found[i]
		var pop: float = _slot_pop[i]
		var sc := 1.0 + 0.35 * sin(clampf(pop / 0.45, 0, 1) * PI)
		Draw.panel(self, Rect2(c - Vector2(21, 21), Vector2(42, 42)), Color("#f6e9ef") if got else Color("#e9e4ea"), 12, Color("#b27c94") if got else Color("#c9bccd"), 2)
		if got:
			Draw.radial_glow(self, c, 22, Color(1, 0.86, 0.7, 0.35))
		PmsMaze.draw_item(self, PmsMaze.ITEMS[i], c + Vector2(0, 2), t, 0.95 * sc, 1.0 if got else 0.22)
	# The breath pill (top-right), the ability hints under it.
	var pill := Rect2(1066 - 16 - PILL.x, 16, PILL.x, PILL.y)
	Draw.panel(self, pill, BG, 16)
	var k := pf.calm_t / Platformer.CALM_TIME if pf.calm_t > 0 else pf.calm_charge
	if k > 0:
		_progress_outline(pill, k, Color("#8b6fa8") if pf.calm_t > 0 else TEAL)
	var bc := pill.get_center()
	var rr := 9.0 + 7.0 * (pf.steady if pf.calm_t > 0 else pf.calm_charge)
	draw_circle(bc, rr + 4, Color("#b9a3cc", 0.35))
	draw_circle(bc, rr, Color("#8b6fa8") if pf.calm_t > 0 else Color(TEAL, 0.8))
	_wind_icon(bc + Vector2(-44, 0), INK)
	draw_arc(bc + Vector2(44, 0), 9, 0, TAU, 24, Color(INK, 0.6), 2.0, true)
	draw_arc(bc + Vector2(44, 0), 4 + 4 * sin(t / 600.0) * (1.0 - pf.steady), 0, TAU, 16, Color(INK, 0.6), 2.0, true)
	hints.draw(self, Vector2(pill.end.x, pill.end.y))
