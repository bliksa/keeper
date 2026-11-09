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
## The climb's WIN counter rolls up towards the real value; a bump when it grows.
var _win_shown := 0.0
var _win_bump := 0.0


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
		var target := float(platformer.climb_win)
		if target < _win_shown:
			_win_shown = target
		elif target > _win_shown:
			_win_shown = minf(target, _win_shown + maxf(1.0, (target - _win_shown) * minf(1.0, delta * 5.0)) + 60.0 * delta)
			_win_bump = 0.25
	_win_bump = maxf(0, _win_bump - delta)


func _draw() -> void:
	if platformer == null:
		return
	var font: Font = Text.font_bold
	if platformer.is_meadow():
		_draw_meadow(font)
		if Game.has_breathing:
			_draw_breath(font)
		return
	if platformer.is_climb():
		_draw_climb(font)
		return
	# Iron: one big nut with the count in its middle (top-left, like the sun in level 2).
	var r := draw_iron(self, font, Vector2(60, 58), Game.iron, _bounce, _spin)
	if Game.has_breathing:
		_draw_breath(font)
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


func _draw_breath(font: Font) -> void:
	var p := platformer.p
	var follow := p.held_by_cramp != -1 or (p.is_recharging and p.breath_charges == 0 and p.breathing_cooldown <= 0)
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



## The jackpot climb (level 5): the board at the bottom edge (ticker, marquee, reels),
## the WIN counter with the multiplier, the floor, active power-ups and the banner.
func _draw_climb(font: Font) -> void:
	var pf := platformer
	var t := pf.time_ms
	_draw_board(font, t)
	# Floor (top-left).
	var fl := pf.floor_of(pf.p.y + pf.p.height)
	var fmt := Text.plain(Text.t("CLIMB_FLOOR"))
	var ft := fmt % fl if fmt.contains("%d") else "%s %d" % [fmt, fl]
	var fw := font.get_string_size(ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var fr := Rect2(16, 16, fw + 28, 34)
	Draw.panel(self, fr, BG, 17, Color("#fbbf24"), 2)
	draw_string(font, Vector2(fr.position.x + 14, fr.position.y + 24), ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	_draw_powers(font, fr.end.y + 8)
	# WIN counter (top centre): rolls up towards the real value, the multiplier beside it.
	var label := Text.plain(Text.t("CLIMB_WIN"))
	var num := "%d" % int(_win_shown)
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var wr := Rect2(1066 / 2 - (nw + lw + 52) / 2, 10, nw + lw + 52, 50)
	var hot := _win_bump > 0
	Draw.panel(self, wr, Color("#2e1065", 0.92), 25, Color("#fde047") if hot else Color("#fbbf24"), 3)
	for i in 14:
		# Little bulbs around the counter.
		var a := i * TAU / 14
		var bp := wr.get_center() + Vector2(cos(a) * (wr.size.x / 2 + 2), sin(a) * (wr.size.y / 2 + 2))
		var on := (i + int(t / 120.0)) % 2 == 0
		draw_circle(bp, 3, Color("#fef08a") if on else Color("#b45309"))
	draw_string(font, Vector2(wr.position.x + 18, wr.position.y + 31), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#fde68a"))
	var s := 1.0 + 0.15 * _win_bump / 0.25
	var np := Vector2(wr.position.x + 30 + lw, wr.position.y + 36)
	draw_set_transform(np, 0, Vector2(s, s))
	draw_string_outline(font, Vector2.ZERO, num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 5, Color("#78350f"))
	draw_string(font, Vector2.ZERO, num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#fef3c7"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var mt := "x%d" % pf.climb_mult
	var mw := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	var mr := Rect2(wr.end.x + 10, 16, mw + 24, 38)
	var mcol := Color("#e11d48") if pf.climb_mult >= 5 else (Color("#ea580c") if pf.climb_mult >= 2 else Color("#64748b"))
	Draw.panel(self, mr, mcol, 19, Color("#fde047"), 2)
	draw_string(font, Vector2(mr.position.x + 12, mr.position.y + 28), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	# The banner (JACKPOT!, SUPER JUMP! …).
	if not pf.banner.is_empty():
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


## Active power-ups as pills with a draining bar.
func _draw_powers(font: Font, y: float) -> void:
	var x := 16.0
	for k in platformer.climb_power.keys():
		var left: float = platformer.climb_power[k]
		var full := Platformer.ROCKET_TIME if k == "rocket" else Platformer.POWER_TIME
		var label := Text.plain(Text.t("CLIMB_PU_" + String(k).to_upper())).trim_suffix("!")
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var r := Rect2(x, y, tw + 24, 26)
		Draw.panel(self, r, Color("#2e1065", 0.9), 13, Color("#fbbf24"), 2)
		var fill := Rect2(r.position + Vector2(3, r.size.y - 7), Vector2((r.size.x - 6) * clampf(left / full, 0, 1), 4))
		draw_rect(fill, Color("#fde047"))
		draw_string(font, Vector2(r.position.x + 12, r.position.y + 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#fef3c7"))
		x += r.size.x + 6


## The board: a dialog-box panel (Estrogenka on the left) with a casino marquee, the
## news ticker running right → left and the slot reels on the right while they spin.
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
	# A story dialog covers the board (it is translucent): no ticker under it.
	for seg in ([] if pf.dialog_open or not talk.is_empty() else pf.ticker):
		var sx: float = seg.x
		if sx > 1066 or sx + seg.w < 0:
			continue
		var col := Color("#b45309") if seg.event else INK
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
	draw_string(font, Vector2(Platformer.TICKER_LEFT, r.position.y + 44), Text.speaker_name(speaker).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#4a7d7b"))
	if not talk.is_empty() and not pf.dialog_open:
		_draw_board_talk(talk, r)
	# Gold trim and the marquee: bulbs chasing along the top edge.
	draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 4), Color("#f59e0b"))
	draw_rect(Rect2(r.position.x, r.position.y + 14, r.size.x, 2), Color("#fbbf24", 0.8))
	var step := 26.0
	var n := int(1066 / step)
	var chase := int(t / 110.0)
	for i in n + 1:
		var c := Vector2(8 + i * step, r.position.y + 9)
		var on := (i + chase) % 3 == 0
		if on:
			draw_circle(c, 7, Color(1, 0.85, 0.3, 0.35))
		draw_circle(c, 3.5, Color("#fff7c2") if on else Color("#d97706"))
	if not pf.slot_spin.is_empty() and not pf.dialog_open:
		_draw_reels(font, t, Rect2(1066 - 16 - 236, r.position.y + 24, 236, r.size.y - 36))


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


## Three reels; they stop one after another on 7-7-7 and show the power-up won.
func _draw_reels(font: Font, t: float, box: Rect2) -> void:
	var spin: Dictionary = platformer.slot_spin
	Draw.panel(self, box, Color("#2e1065"), 14, Color("#fbbf24"), 3)
	var syms := ["7", "$", "?", "*", "7", "+"]
	var cols := [Color("#ef4444"), Color("#22c55e"), Color("#fbbf24"), Color("#60a5fa"), Color("#ef4444"), Color("#f472b6")]
	var rw := 52.0
	var rh := 62.0
	var x0 := box.position.x + 18
	var y0 := box.position.y + 10
	for i in 3:
		var rr := Rect2(x0 + i * (rw + 10), y0, rw, rh)
		Draw.panel(self, rr, Color("#fefce8"), 8, Color("#b45309"), 2)
		var stopped: bool = spin.stops > i
		if stopped:
			Draw.text_center(self, font, rr.get_center() + Vector2(0, 2), "7", 40, Color("#dc2626"))
		else:
			# Spinning: symbols sliding down through the window.
			var off := fmod(t / 30.0 + i * 17.0, rh)
			for j in 2:
				var k := (int(t / 30.0 / rh) + j + i * 2) % syms.size()
				var cy := rr.position.y + off - j * rh + rh / 2
				if cy > rr.position.y + 8 and cy < rr.end.y - 4:
					Draw.text_center(self, font, Vector2(rr.get_center().x, cy), syms[k], 34, cols[k])
	var lbl := ""
	if spin.paid:
		lbl = Text.plain(Text.t("CLIMB_PU_" + String(spin.power).to_upper()))
	var blink: bool = spin.paid and int(t / 150.0) % 2 == 0
	if lbl != "":
		Draw.text_center(self, font, Vector2(box.get_center().x, box.end.y - 14), lbl, 16, Color("#fde047") if blink else Color("#fef3c7"))
