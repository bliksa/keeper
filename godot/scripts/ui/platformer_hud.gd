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


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_spin += delta * TAU / 4.0
	if Game.iron != _last_iron:
		_last_iron = Game.iron
		_bounce = 0.3
	_bounce = maxf(0, _bounce - delta)


func _draw() -> void:
	if platformer == null:
		return
	var font: Font = Text.font_bold
	if platformer.is_meadow():
		_draw_meadow(font)
		if Game.has_breathing:
			_draw_breath(font)
		return
	# Iron counter.
	var label := str(Game.iron)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var bounce := -sin(_bounce / 0.3 * PI) * 10.0
	var r := Rect2(16, 16 + bounce, tw + 20 + 24 + 30, 48)
	Draw.panel(self, r, BG, 16, Color(TEAL, 0.2), 2)
	draw_string(font, Vector2(r.position.x + 20, r.position.y + 31), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
	var ic := Vector2(r.end.x - 26, r.position.y + 24)
	var hex := PackedVector2Array()
	for i in 6:
		# Coin-like spin: only the width changes.
		var a := i / 6.0 * TAU - PI / 2
		hex.append(ic + Vector2(cos(a) * absf(cos(_spin)), sin(a)) * 11)
	draw_colored_polygon(hex, Color("#9ca3af"))
	draw_polyline(hex + PackedVector2Array([hex[0]]), Color("#4b5563"), 1.5, true)
	draw_set_transform(ic, 0, Vector2(maxf(absf(cos(_spin)), 0.01), 1))
	draw_circle(Vector2.ZERO, 4.5, BG)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

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
			_key_hint(font, c, "CTRL" if keyboard else "PUSH", keyboard)
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
			_key_hint(font, c, "CTRL" if keyboard else "PUSH", keyboard)
		else:
			var s := "CTRL" if keyboard else "RELOAD"
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
