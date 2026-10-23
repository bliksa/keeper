class_name Draw
extends RefCounted
## Small procedural drawing helpers (gradients, iron nut, hex tiles…)
## replacing the HTML canvas calls used by the web prototype.

static var _vignette_tex: GradientTexture2D
static var _glow_tex: GradientTexture2D
static var _hgrad_tex: GradientTexture2D


static func polygon_safe(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return
	ci.draw_colored_polygon(pts, col)


static func quad_curve(ci: CanvasItem, a: Vector2, ctrl: Vector2, b: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	ci.draw_polyline(pts, col, width, true)


## Horizontal linear gradient from `from` (left) to `to` (right).
static func h_gradient(ci: CanvasItem, rect: Rect2, from: Color, to: Color) -> void:
	if _hgrad_tex == null:
		_hgrad_tex = GradientTexture2D.new()
		_hgrad_tex.width = 64
		_hgrad_tex.height = 4
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		_hgrad_tex.gradient = g
	ci.draw_texture_rect(_hgrad_tex, rect, false, from)


## Dark edges: transparent centre → `col` at the border. `inner` = clear radius (0..1).
static func vignette(ci: CanvasItem, rect: Rect2, col: Color, inner := 0.4) -> void:
	if _vignette_tex == null:
		_vignette_tex = GradientTexture2D.new()
		_vignette_tex.width = 128
		_vignette_tex.height = 128
		_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		_vignette_tex.fill_from = Vector2(0.5, 0.5)
		_vignette_tex.fill_to = Vector2(1.0, 0.5)
		_vignette_tex.gradient = Gradient.new()
	var g := _vignette_tex.gradient
	g.offsets = PackedFloat32Array([inner * 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE])
	# Stretch the circle a bit beyond the screen so the corners stay soft.
	var grow := rect.size * 0.25
	ci.draw_texture_rect(_vignette_tex, Rect2(rect.position - grow, rect.size + grow * 2), false, col)


## Soft round glow, `col` in the middle fading out at `radius`. Optional bright core.
static func radial_glow(ci: CanvasItem, c: Vector2, radius: float, col: Color, core := Color(0, 0, 0, 0)) -> void:
	if radius <= 0.5:
		return
	if _glow_tex == null:
		_glow_tex = GradientTexture2D.new()
		_glow_tex.width = 64
		_glow_tex.height = 64
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.33), Color(1, 1, 1, 0)])
		_glow_tex.gradient = g
	ci.draw_texture_rect(_glow_tex, Rect2(c - Vector2(radius, radius), Vector2(radius, radius) * 2), false, col)
	if core.a > 0:
		ci.draw_texture_rect(_glow_tex, Rect2(c - Vector2(radius, radius) * 0.5, Vector2(radius, radius)), false, core)


static func _hex(r: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := i / 6.0 * TAU + rot
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


## Collectible iron: a hex nut spinning in 3D (stack of offset hexes).
static func iron_nut(ci: CanvasItem, c: Vector2, r: float, spin: float, roll: float) -> void:
	var cs := cos(spin)
	var front_first := cs > 0
	var depth := 6
	var shift := sin(spin) * 6
	var order := range(depth, -1, -1) if front_first else range(0, depth + 1)
	for i in order:
		var xf := Transform2D(roll, Vector2(absf(cs) + 0.001, 1.0), 0.0, c + Vector2(shift * (i / float(depth)), 0))
		ci.draw_set_transform_matrix(xf)
		var hex := _hex(r)
		if i == 0:
			ci.draw_colored_polygon(hex, Color("#9ca3af"))
			ci.draw_polyline(hex + PackedVector2Array([hex[0]]), Color("#374151"), 1.5, true)
			ci.draw_circle(Vector2.ZERO, r * 0.45, Color("#2b0b0b"))
		else:
			ci.draw_colored_polygon(hex, Color("#4b5563"))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Iron floor tile of the boss arena (also used as flying debris).
static func hex_tile(ci: CanvasItem, c: Vector2, rot: float, r: float) -> void:
	ci.draw_set_transform(c, rot, Vector2.ONE)
	var hex := _hex(r)
	ci.draw_colored_polygon(hex, Color("#9ca3af"))
	ci.draw_polyline(hex + PackedVector2Array([hex[0]]), Color("#4b5563"), 2.0, true)
	ci.draw_circle(Vector2.ZERO, r / 2, Color("#1e293b"))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Lost-iron particle.
static func nut_particle(ci: CanvasItem, c: Vector2, rot: float) -> void:
	ci.draw_set_transform(c, rot, Vector2.ONE)
	var hex := _hex(12)
	ci.draw_colored_polygon(hex, Color("#9ca3af"))
	ci.draw_polyline(hex + PackedVector2Array([hex[0]]), Color("#4b5563"), 2.0, true)
	ci.draw_circle(Vector2.ZERO, 5, Color.WHITE)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Rounded panel with optional border.
static func panel(ci: CanvasItem, rect: Rect2, bg: Color, radius := 12.0, border := Color(0, 0, 0, 0), border_w := 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(int(border_w))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, rect)


static func text_center(ci: CanvasItem, font: Font, c: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, Vector2(c.x - w / 2, c.y + size * 0.35), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
