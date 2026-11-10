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
## The labels under the indicators as last drawn: [{key, box, rect}] (tests).
var labels: Array = []


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
		# The maze: rest (hold) once the light is visibly small, and only where it works (on
		# the ground: in the air Shift does nothing); while resting, the energy
		# coming back as the line's bar (the true energy: the gauge may be foggy).
		if pf.dialog_open or pf.hold_input:
			return []
		if pf.resting:
			return [{"key": "HINT_PMS_RESTING", "k": pf.pms_light}]
		if pf.pms_light < Platformer.REST_HINT and pf.p.is_grounded:
			return ["HINT_PMS_REST"]
		return []
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
		elif pf.meter.mag > Platformer.FUEL_MIN:
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
	labels = []
	if platformer == null:
		return
	var font: Font = Text.font_bold
	if not platformer.is_climb():
		# The phase's announcement where the dialog box is (the climb has its own board).
		PhaseBoard.draw(self, platformer.phase_note, platformer.time_ms, platformer.phase_speaker)
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
	# Iron: one big nut with the count in its middle (top-left, like the sun in level 2),
	# its label under it.
	draw_iron(self, font, IRON_HUD, Game.iron, _bounce, _spin)
	labels = [{"key": "HUD_LBL_IRON", "box": iron_box(), "rect": Draw.hud_label(self, iron_box(), "HUD_LBL_IRON")}]
	if Game.has_breathing:
		var br := _draw_breath(font)
		labels.append({"key": "HUD_LBL_BREATH", "box": br, "rect": Draw.hud_label(self, br, "HUD_LBL_BREATH")})
		if not platformer.is_summit():
			# The hints follow the pill (under Kyra while she breathes / is held), under
			# its label.
			var follow := _breath_follows()
			hints.draw(self, Vector2(br.get_center().x if follow else br.end.x, Draw.label_bottom(br)), follow)
	if platformer.is_summit():
		_draw_upgrades(font, Draw.label_bottom(iron_box()) + 6)
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


## The cave's iron nut (its centre) and its drawn box (the texture is 2.3 × its radius
## of 42 tall): the label goes under it.
const IRON_HUD := Vector2(60, 58)


static func iron_box() -> Rect2:
	return Rect2(IRON_HUD - Vector2(49, 49), Vector2(98, 98))


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
			var row: Array = []
			for i in p.breath_charges:
				row.append("wind" if keyboard else "pad")
			_icon_row(font, c, row)
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
			_icon_row(font, c, ["t:" + ("SHIFT" if keyboard else "RELOAD"), "reload" if keyboard else "pad"])
	return rect


func _key_hint(font: Font, c: Vector2, s: String, keyboard: bool) -> void:
	_icon_row(font, c, ["t:" + s, "wind" if keyboard else "pad"])


## The breath pill's contents as one row centred on `c` (both ways): "t:TEXT" (the HUD
## font at 18 px), "wind", "reload", "pad" (the gamepad's red button).
const ROW_GAP := 8.0
const ROW_FS := 18
const TEXT_BEARING := 0.14


static func icon_row_items(font: Font, c: Vector2, items: Array) -> Array:
	var ws: Array = []
	var total := 0.0
	for it in items:
		var w := _row_item_w(font, str(it))
		ws.append(w)
		total += w
	total += ROW_GAP * maxf(0.0, items.size() - 1)
	var x := c.x - total / 2
	var out: Array = []
	for i in items.size():
		var w: float = ws[i]
		out.append({"item": str(items[i]), "c": Vector2(x + w / 2, c.y), "w": w})
		x += w + ROW_GAP
	return out


static func _row_item_w(font: Font, it: String) -> float:
	if it.begins_with("t:"):
		# The ink, not the advance: KeeperDyslexic's capitals keep ≈ 0.14 em of side
		# bearing on each side (measured: 2.75 / 2.25 px at 18 px), so the row's ink is
		# what gets centred.
		return font.get_string_size(it.substr(2), HORIZONTAL_ALIGNMENT_LEFT, -1, ROW_FS).x - 2.0 * TEXT_BEARING * ROW_FS
	match it:
		"wind":
			return WIND_BOUNDS.size.x
		"reload":
			return RELOAD_BOUNDS.size.x
	return 20.0


func _icon_row(font: Font, c: Vector2, items: Array) -> void:
	for e in icon_row_items(font, c, items):
		var it: String = e.item
		var ic: Vector2 = e.c
		if it.begins_with("t:"):
			Draw.text_center(self, font, ic, it.substr(2), ROW_FS, INK)
		elif it == "wind":
			_wind_icon(ic, INK)
		elif it == "reload":
			_reload_icon(ic)
		else:
			draw_texture_rect(load("res://assets/ui/pad_red.png"), Rect2(ic.x - 10, ic.y - 10, 20, 20), false)


## The wind icon's drawn bounds round its drawing origin (the lines' ends, the curls).
const WIND_BOUNDS := Rect2(-10, -11, 17.5, 17)
const RELOAD_BOUNDS := Rect2(-8, -9, 18, 17)


## The lucide "wind" icon with its bounds centred on `c`.
func _wind_icon(c: Vector2, col: Color) -> void:
	var o := c - WIND_BOUNDS.get_center()
	# Three gusts with curled ends (the lucide "wind" icon).
	for row in [[-6.0, 14.0], [0.0, 18.0], [6.0, 12.0]]:
		var y: float = o.y + row[0]
		var len: float = row[1]
		draw_line(Vector2(o.x - 10, y), Vector2(o.x - 10 + len - 3, y), col, 2.0, true)
		draw_arc(Vector2(o.x - 10 + len - 3, y - 2.5), 2.5, PI / 2, -PI, 8, col, 2.0, true)


## A circular arrow with its bounds centred on `c`.
func _reload_icon(c: Vector2) -> void:
	var o := c - RELOAD_BOUNDS.get_center()
	draw_arc(o, 8, -PI * 0.25, PI * 1.4, 16, INK, 2.0, true)
	draw_colored_polygon(PackedVector2Array([o + Vector2(6, -9), o + Vector2(10, -2), o + Vector2(3, -3)]), INK)


## The breathing rhythm's symbols, each centred on `c` (18 px tall).
func _shape(kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"up":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(10, 9), c + Vector2(-10, 9)]), col)
		"hold":
			draw_rect(Rect2(c - Vector2(8, 8), Vector2(16, 16)), col)
		"down":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 9), c + Vector2(10, -9), c + Vector2(-10, -9)]), col)


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
	draw_heart_pill(self, pill, pf.meter, t / 1000.0, pf.heart_short > 0, _heart_pop, _alpha)
	labels = [{"key": "HUD_LBL_HEARTS", "box": pill, "rect": Draw.hud_label(self, pill, "HUD_LBL_HEARTS", _alpha)}]
	hints.draw(self, Vector2(pill.end.x, Draw.label_bottom(pill)))
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


## The heart meter (like the forest run's water pill): the magazine's HEART_SLOTS hearts
## (a part-filled one only up to its level) and the reserve as a line round the pill with
## its badge and the reload's flying hearts (MeterHud). `short`: the missing hearts blink
## red (an ability tried without enough); `pop` > 0: the newest one pops. Rocket fuel burns
## the magazine itself, so the top heart drains like water.
static func draw_heart_pill(ci: CanvasItem, r: Rect2, m: MeterModel, t: float, short := false, pop := 0.0, alpha := 1.0) -> void:
	Draw.panel(ci, r, Color(BG, alpha), 16, Color(0.96, 0.25, 0.37, 0.25 * alpha), 2)
	var col := Color("#f43f5e").lerp(Color("#f9a8d4"), 0.3)
	MeterHud.draw_shimmer(ci, r, m, t, alpha)
	var blink := short and fmod(t, 0.2) < 0.12
	var level := m.mag
	var top := m.whole() - 1
	for i in Platformer.HEART_SLOTS:
		var c := MeterHud.slot_center(r, i, Platformer.HEART_SLOTS)
		MeterHud.draw_slot_glow(ci, m, i, c, col, alpha)
		var fill := clampf(level - i, 0, 1)
		var s := 12.0 * (1.0 + MeterHud.slot_pop(m, i) + (0.35 * sin(clampf(pop / 0.4, 0, 1) * PI) if i == top else 0.0))
		var empty := Color(0.94, 0.27, 0.27, 0.75 * alpha) if blink and fill < 0.99 else Color(0.58, 0.5, 0.6, 0.3 * alpha)
		# The heart's bounds centred on the slot (its point hangs lower than its lobes).
		var hc := MeterHud.heart_at(c, s)
		if fill >= 0.99:
			SpriteArt.draw_heart(ci, hc, s, 1.0, alpha)
			continue
		_heart_shape(ci, MeterHud.heart_at(c, 11.0, false), 11.0, empty)
		if fill > 0.01:
			# Only the part below its level (no outline: centred as a bare shape).
			hc = MeterHud.heart_at(c, s, false)
			var pts := _heart_pts(hc, s)
			var y := hc.y + s * (1.19 - 1.81 * fill)
			var below := PackedVector2Array([Vector2(c.x - 30, y), Vector2(c.x + 30, y), Vector2(c.x + 30, hc.y + 30), Vector2(c.x - 30, hc.y + 30)])
			for part in Geometry2D.intersect_polygons(pts, below):
				Draw.polygon_safe(ci, part, Color(Color("#f43f5e"), alpha))
	MeterHud.draw_reserve(ci, r, m, Color(col, 1.0), "heart", t, alpha)


static func _heart_shape(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	Draw.polygon_safe(ci, _heart_pts(c, s), col)


static func _heart_pts(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var a := i / 24.0 * TAU
		pts.append(c + Vector2(16.0 * pow(sin(a), 3), -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a)) + 2.0) * s / 16.0)
	return pts


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
		PhaseBoard.draw_title(self, font, note, r, t)
	else:
		draw_string(font, Vector2(Platformer.TICKER_LEFT, r.position.y + 44), Text.speaker_name(speaker).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4a7d7b"))
	if not talk.is_empty() and not pf.dialog_open and note.is_empty():
		_draw_board_talk(talk, r)
	# Gold trim and the marquee: bulbs chasing along the top edge (PhaseBoard: the same
	# board announces every phase).
	PhaseBoard.draw_marquee(self, r, t, note, pf.wind < 0.5)


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
			SpriteArt.draw_heart(self, MeterHud.heart_at(c, 14.0 * k), 14.0 * k, 1.0, _alpha)
		"bell":
			SpriteArt.draw_bell(self, c - Vector2(0, SpriteArt.bell_mid(13.0 * k)), 13.0 * k, 0.0, _alpha)
		"joker":
			SpriteArt.draw_joker(self, c, 38.0 * k, 0.0, _alpha)
		_:
			Draw.text_center(self, font, c + Vector2(0, 12), sym, 34, _a(Color("#dc2626")))


func _a(c: Color) -> Color:
	return Color(c, c.a * _alpha)


## The PMS maze (level 6): the three comfort items as slots (top-left, upright, filled when
## found), the energy gauge (top-right: draw_energy_pill, not always right) and the hints.
func _draw_pms(font: Font) -> void:
	var pf := platformer
	var t := pf.time_ms
	var box := PMS_SLOTS
	Draw.panel(self, box, BG, 18, Color("#b27c94", 0.5), 2)
	for i in 3:
		var c := pms_slot_center(i)
		var got: bool = pf.pms_found[i]
		var pop: float = _slot_pop[i]
		var sc := 1.0 + 0.35 * sin(clampf(pop / 0.45, 0, 1) * PI)
		Draw.panel(self, Rect2(c - Vector2(21, 21), Vector2(42, 42)), Color("#f6e9ef") if got else Color("#e9e4ea"), 12, Color("#b27c94") if got else Color("#c9bccd"), 2)
		if got:
			Draw.radial_glow(self, c, 22, Color(1, 0.86, 0.7, 0.35))
		var kind: String = PmsMaze.ITEMS[i]
		var k := pms_item_scale(kind) * sc
		PmsMaze.draw_item(self, kind, c - PmsMaze.item_bounds(kind).get_center() * k, t, k, 1.0 if got else 0.22)
	labels = [{"key": "HUD_LBL_COMFORT", "box": box, "rect": Draw.hud_label(self, box, "HUD_LBL_COMFORT")}]
	# The energy gauge (top-right), the ability hints under it.
	var pill := Rect2(1066 - 16 - PILL.x, 16, PILL.x, PILL.y)
	draw_energy_pill(self, pill, pf.gauge(), pf.fog_k(), t / 1000.0, pf.rest_k)
	labels.append({"key": "HUD_LBL_ENERGY", "box": pill, "rect": Draw.hud_label(self, pill, "HUD_LBL_ENERGY")})
	hints.draw(self, Vector2(pill.end.x, Draw.label_bottom(pill)))


## Where the maze's HUD is on screen (the comfort slots and the energy gauge, each with its
## label; the gauge with room for a hint line under it): the maze's camera keeps Kyra out of
## these (Platformer.PMS_TOP).
static func pms_hud_rects() -> Array[Rect2]:
	var slots := PMS_SLOTS.grow(4)
	slots.end.y = Draw.label_bottom(PMS_SLOTS) + 2
	var pill := Rect2(1066 - 16 - PILL.x, 16, PILL.x, PILL.y)
	var gauge := Rect2(1066 - 16 - 380, 12, 384, Draw.label_bottom(pill) + 7 + AbilityHints.H + 5 + AbilityHints.GAP - 12)
	return [slots, gauge]


## The energy pill's row: a little light (icon centre, ENERGY_ICON_R with its rays) and the
## bar's track, centred in the pill as one row.
const ENERGY_ICON_R := 10.0
const ENERGY_BAR := Vector2(84, 12)
const ENERGY_GAP := 8.0
const ENERGY_WARM := Color("#f4b740")
const ENERGY_LOW := Color("#e2703a")
const ENERGY_FOG := Color("#b06fd8")

static func energy_layout(pill: Rect2) -> Dictionary:
	var w := ENERGY_ICON_R * 2 + ENERGY_GAP + ENERGY_BAR.x
	var x0 := pill.get_center().x - w / 2
	var cy := pill.get_center().y
	return {"icon": Vector2(x0 + ENERGY_ICON_R, cy), "bar": Rect2(x0 + ENERGY_ICON_R * 2 + ENERGY_GAP, cy - ENERGY_BAR.y / 2, ENERGY_BAR.x, ENERGY_BAR.y)}


## The maze's energy gauge: shown = what it says (0..1; Platformer.gauge(), wrong in a foggy
## spell), fog 0..1 = how foggy it is now: the bar shivers and flickers, its colour shifts to
## violet, wavy static runs over the pill and a "?" blinks on the light, so one can tell it
## can't be trusted right now. rest 0..1: a soft pulse while the energy comes back.
static func draw_energy_pill(ci: CanvasItem, pill: Rect2, shown: float, fog: float, ts: float, rest := 0.0) -> void:
	Draw.panel(ci, pill, BG.lerp(Color("#e6daf0"), 0.8 * fog), 16, Color(ENERGY_FOG, 0.75 * fog), 2.0 * fog)
	var lay := energy_layout(pill)
	var shake := Vector2(sin(ts * 47.0) * 1.6, sin(ts * 31.0) * 0.8) * fog
	var flick := 1.0 - 0.45 * fog * (0.5 + 0.5 * sin(ts * 23.0)) * (1.0 if sin(ts * 7.3) > -0.3 else 0.3)
	var k := clampf(shown, 0, 1)
	var col := ENERGY_LOW.lerp(ENERGY_WARM, clampf(k / 0.35, 0, 1)).lerp(ENERGY_FOG, 0.75 * fog)
	# The light: a glowing dot with short rays, as big as it says.
	var ic: Vector2 = lay.icon
	var r := 3.0 + 3.5 * k + 0.8 * rest * sin(ts * 5.0)
	Draw.radial_glow(ci, ic, ENERGY_ICON_R + 2, Color(col, 0.35 * flick))
	for i in 8:
		var d := Vector2.from_angle(TAU * i / 8.0 + ts * 0.4)
		ci.draw_line(ic + d * (r + 1.5), ic + d * (r + 1.5 + 1.0 + 2.0 * k), Color(col, 0.9 * flick), 1.6, true)
	ci.draw_circle(ic, r, Color(col, flick))
	if fog > 0.5 and sin(ts * 9.0) > 0:
		Draw.text_center(ci, Text.font_bold, ic + Vector2(0, 4.5), "?", 13, Color(1, 1, 1, 0.95))
	# The bar.
	var bar: Rect2 = lay.bar
	bar.position += shake
	Draw.panel(ci, bar, Color("#d8d2cf").lerp(Color("#cfc0dd"), fog), bar.size.y / 2)
	if k > 0.01:
		var fill := Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * k), bar.size.y))
		Draw.panel(ci, fill, Color(col, flick), bar.size.y / 2)
		ci.draw_circle(Vector2(fill.end.x - bar.size.y / 2, bar.get_center().y), 2.2 + 0.8 * rest, Color(1, 1, 1, 0.75 * flick))
	if fog > 0:
		# Wavy static across the pill, and a few stray dashes.
		for row in 3:
			var pts := PackedVector2Array()
			var y0 := pill.position.y + pill.size.y * (0.28 + 0.22 * row)
			for i in 15:
				var x := pill.position.x + 12 + (pill.size.x - 24) * i / 14.0
				pts.append(Vector2(x, y0 + sin(x * 0.19 + ts * (9.0 + 3.0 * row) + row * 2.1) * 3.2 * fog))
			ci.draw_polyline(pts, Color(ENERGY_FOG.lerp(Color.WHITE, 0.35 * row), 0.5 * fog), 1.4, true)
		for i in 5:
			var h := sin((floorf(ts * 14.0) + i * 7.0) * 12.9898) * 43758.5453
			h -= floorf(h)
			var h2 := sin((floorf(ts * 14.0) + i * 3.0) * 78.233) * 43758.5453
			h2 -= floorf(h2)
			var q := Vector2(pill.position.x + 14 + (pill.size.x - 40) * h, pill.position.y + 9 + (pill.size.y - 18) * h2)
			ci.draw_line(q, q + Vector2(6 + 8 * h2, 0), Color(1, 1, 1, 0.6 * fog), 1.5)


## The maze's three item slots (42 px each, 10 apart) in their panel (7 px round them).
const PMS_SLOTS := Rect2(16, 16, 7 * 2 + 42 * 3 + 10 * 2, 56)


static func pms_slot_center(i: int) -> Vector2:
	return Vector2(PMS_SLOTS.position.x + 7 + 21 + i * 52, PMS_SLOTS.get_center().y)


## An item's scale in its slot: its drawn bounds fit 34 px (at most 0.95).
static func pms_item_scale(kind: String) -> float:
	var b := PmsMaze.item_bounds(kind)
	return minf(0.95, 34.0 / maxf(b.size.x, b.size.y))
