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
		var a := i / 6.0 * TAU - PI / 2 + _spin
		hex.append(ic + Vector2(cos(a), sin(a)) * 11)
	draw_colored_polygon(hex, Color("#9ca3af"))
	draw_polyline(hex + PackedVector2Array([hex[0]]), Color("#4b5563"), 1.5, true)
	draw_circle(ic, 4.5, BG)

	if Game.has_breathing:
		_draw_breath(font)


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
		Draw.panel(self, rect, Color(0, 0, 0, 0), 16, Color(TEAL, pulse), 4)
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
		var fill := Rect2(rect.position, Vector2(rect.size.x * k, rect.size.y))
		Draw.panel(self, fill, Color(RUST, 0.3) if breath_error else Color(TEAL, 0.2), 16)
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


func _progress_outline(rect: Rect2, k: float, col: Color) -> void:
	# Outline that fills clockwise from the top-left as the breath progresses.
	var r := rect.grow(-2)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	var total := (r.size.x + r.size.y) * 2
	var left := total * k
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var seg := pts[i - 1].distance_to(pts[i])
		if left >= seg:
			out.append(pts[i])
			left -= seg
		else:
			out.append(pts[i - 1].lerp(pts[i], left / seg))
			break
	if out.size() > 1:
		draw_polyline(out, col, 5.0, true)
