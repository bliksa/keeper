class_name MeterHud
## Draws a MeterModel's reserve and reload on its pill (the forest run's water pill, the
## climb's heart meter; the pills draw the magazine's four slots themselves):
## - the reserve = the line round the pill (`ForestRunner.progress_outline`), with a notch
##   at every whole unit and a badge on the pill's left "+N" (whole units in reserve);
## - a pickup into the reserve: the line and the badge flash;
## - a reload: a soft shimmer sweeps the pill and each unit flies as a small drop / heart
##   from the reserve's badge in a short arc into the slot it fills (which then pops).

const BADGE_W := 46.0


## The pill's outline (a rounded rect, clockwise from the top left), as the reserve
## line follows it.
static func outline_path(rect: Rect2) -> PackedVector2Array:
	var r := rect.grow(-2)
	var rad := 14.0
	var path := PackedVector2Array([Vector2(r.position.x + rad, r.position.y)])
	var corners := [[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2], [Vector2(r.end.x - rad, r.end.y - rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI / 2], [Vector2(r.position.x + rad, r.position.y + rad), PI]]
	for cr in corners:
		var cc: Vector2 = cr[0]
		var a0: float = cr[1]
		for j in 9:
			var a := a0 + j / 8.0 * PI / 2
			path.append(cc + Vector2(cos(a), sin(a)) * rad)
	path.append(Vector2(r.position.x + rad, r.position.y))
	return path


## The outline cut at `k` (0–1 of its length).
static func outline_part(rect: Rect2, k: float) -> PackedVector2Array:
	var path := outline_path(rect)
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
	return out


## The point at `k` along the outline.
static func outline_point(rect: Rect2, k: float) -> Vector2:
	var part := outline_part(rect, k)
	return part[part.size() - 1]


## Where slot `i` of `n` sits in the pill: the row of slots centred both ways (the
## icons are drawn centred on it: `drop_at` / `heart_at` correct their shapes' offsets).
static func slot_center(r: Rect2, i: int, n := 4) -> Vector2:
	var step := (r.size.x - 24) / n
	return Vector2(r.position.x + 12 + step * (i + 0.5), r.get_center().y)


## The point to draw a drop (`SpriteArt.draw_drop`, scale `k`: −13 k … +12 k round it) at
## so that its bounds are centred on `c`.
static func drop_at(c: Vector2, k: float) -> Vector2:
	return c + Vector2(0, 0.5 * k)


## The same for a heart (`SpriteArt.draw_heart`, size `s`; `outlined` = with its dark
## outline, false = the bare shape).
static func heart_at(c: Vector2, s: float, outlined := true) -> Vector2:
	return c - Vector2(0, SpriteArt.heart_mid(s, outlined))


## How much a slot pops (scale) right now: a pickup's flash, a reloaded unit landing.
static func slot_pop(m: MeterModel, i: int) -> float:
	var k := 0.0
	if m.slot_flash > 0 and m.slot_flash_i == i:
		k = maxf(k, sin(clampf(m.slot_flash / MeterModel.FLASH, 0, 1) * PI) * 0.25)
	if m.land_flash > 0 and m.land_i == i:
		k = maxf(k, sin(clampf(m.land_flash / MeterModel.FLASH, 0, 1) * PI) * 0.35)
	return k


## A glow behind a slot that just got something (drawn before the slot's icon).
static func draw_slot_glow(ci: CanvasItem, m: MeterModel, i: int, c: Vector2, col: Color, alpha := 1.0) -> void:
	var k := 0.0
	if m.slot_flash > 0 and m.slot_flash_i == i:
		k = maxf(k, m.slot_flash / MeterModel.FLASH)
	if m.land_flash > 0 and m.land_i == i:
		k = maxf(k, m.land_flash / MeterModel.FLASH)
	if k > 0.01:
		Draw.radial_glow(ci, c, 22.0 + 6.0 * k, Color(col, 0.55 * k * alpha), Color(1, 1, 1, 0.7 * k * alpha))


## The shimmer (under the slots): a soft light band sweeping the pill while it reloads.
static func draw_shimmer(ci: CanvasItem, r: Rect2, m: MeterModel, t: float, alpha := 1.0) -> void:
	if m.reload_glow <= 0.01:
		return
	var inner := r.grow(-4)
	var x := inner.position.x - 30 + fmod(t * 1.6, 1.0) * (inner.size.x + 60)
	var band := PackedVector2Array([Vector2(x - 10, inner.end.y), Vector2(x + 8, inner.position.y), Vector2(x + 30, inner.position.y), Vector2(x + 12, inner.end.y)])
	var box := PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)])
	for part in Geometry2D.intersect_polygons(band, box):
		Draw.polygon_safe(ci, part, Color(1, 1, 1, 0.45 * m.reload_glow * alpha))


## The reserve line round the pill with its notches, the badge, the reload's flyers.
## `kind` = "drop" / "heart" (the flyers' and the badge's icon).
static func draw_reserve(ci: CanvasItem, r: Rect2, m: MeterModel, col: Color, kind: String, t: float, alpha := 1.0) -> void:
	var k := m.shown_reserve / maxf(0.001, m.reserve_max)
	var fl := m.reserve_flash / MeterModel.FLASH
	# The empty track, faint, so the line reads as a store that can fill.
	var track := outline_part(r, 1.0)
	ci.draw_polyline(track, Color(col, 0.13 * alpha), 4.0, true)
	if fl > 0.01:
		Draw.radial_glow(ci, outline_point(r, k), 18.0 * fl + 6.0, Color(col, 0.5 * fl * alpha), Color(1, 1, 1, 0.8 * fl * alpha))
	var part := outline_part(r, k)
	if part.size() > 1:
		var lc := col.lerp(Color.WHITE, 0.45 * fl)
		if m.reload_glow > 0.01:
			lc = lc.lerp(Color.WHITE, 0.2 * m.reload_glow * (0.5 + 0.5 * sin(t * 12.0)))
		ci.draw_polyline(part, Color(lc, alpha), 4.0 + 2.0 * fl, true)
	# A notch at every whole unit of the reserve.
	var n := int(m.reserve_max)
	for i in range(1, n):
		var p := outline_point(r, float(i) / n)
		var q := outline_point(r, float(i) / n + 0.004)
		var d := (q - p).normalized().orthogonal() * 4.0
		ci.draw_line(p - d, p + d, Color(1, 1, 1, 0.9 * alpha), 2.0, true)
	_draw_badge(ci, r, m, col, kind, fl, alpha)
	for f in m.flyers:
		_draw_flyer(ci, r, m, f, col, kind, alpha)


static func badge_rect(r: Rect2) -> Rect2:
	return Rect2(r.position.x - BADGE_W - 2, r.get_center().y - 13, BADGE_W, 26)


## The badge's icon and "+N" as one row centred in the badge: the icon's centre (its
## bounds' centre) and the text's left x.
const BADGE_ICON_W := 11.0
const BADGE_ICON_GAP := 3.0
const BADGE_FS := 15


static func badge_text(n: int) -> String:
	return "+%d" % n


static func badge_layout(r: Rect2, n := 1) -> Dictionary:
	var b := badge_rect(r)
	var tw := Text.font_bold.get_string_size(badge_text(n), HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FS).x
	var x0 := b.get_center().x - (BADGE_ICON_W + BADGE_ICON_GAP + tw) / 2
	return {"icon": Vector2(x0 + BADGE_ICON_W / 2, b.get_center().y), "text_x": x0 + BADGE_ICON_W + BADGE_ICON_GAP, "text_w": tw}


## The badge's icon: where a reloaded unit sets off from.
static func badge_icon(r: Rect2, n := 1) -> Vector2:
	return badge_layout(r, n).icon


## "+N": the whole units in reserve, on a little tab left of the pill (dim while it holds
## less than a whole one); its icon fills from the bottom with the part of the next unit.
static func _draw_badge(ci: CanvasItem, r: Rect2, m: MeterModel, col: Color, kind: String, fl: float, alpha: float) -> void:
	var n := int(floorf(m.reserve + MeterModel.EPS))
	var part := clampf(m.reserve - n, 0.0, 1.0) if m.reserve - n > 0.01 else 0.0
	var a := alpha * (1.0 if n >= 1 else 0.45)
	var g := 3.0 * sin(clampf(fl, 0, 1) * PI)
	var b := badge_rect(r).grow(g)
	Draw.panel(ci, b, Color(Color("#f0eee9"), 0.94 * a), 13, Color(col, (0.35 + 0.5 * fl) * a), 2)
	var lay := badge_layout(r, n)
	var ic: Vector2 = lay.icon
	if n >= 1 or part <= 0.0:
		_icon(ci, kind, ic, 0.55, a)
	else:
		# Only a part of a unit: a faint icon, coloured up to that part.
		_icon(ci, kind, ic, 0.55, 0.35 * alpha)
		_icon_part(ci, kind, ic, 0.55, part, alpha)
	var font: Font = Text.font_bold
	ci.draw_string(font, Vector2(float(lay.text_x), text_baseline(font, b.get_center().y, BADGE_FS)), badge_text(n), HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_FS, Color(Color("#064e3b"), a))


## The baseline that centres digits / capitals of size `fs` on `cy` (their ink, not the
## font's line box).
static func text_baseline(font: Font, cy: float, fs: int) -> float:
	return cy + fs * 0.36


## The icon's lower `part` (0–1) only.
static func _icon_part(ci: CanvasItem, kind: String, c: Vector2, k: float, part: float, alpha: float) -> void:
	var shape := PackedVector2Array()
	c = heart_at(c, 12.0 * k) if kind == "heart" else drop_at(c, k)
	if kind == "heart":
		var s := 12.0 * k
		for i in 24:
			var ang := i / 24.0 * TAU
			shape.append(c + Vector2(16.0 * pow(sin(ang), 3), -(13.0 * cos(ang) - 5.0 * cos(2 * ang) - 2.0 * cos(3 * ang) - cos(4 * ang)) + 2.0) * s / 16.0)
	else:
		# As SpriteArt.draw_drop.
		shape.append(c + Vector2(0, -13) * k)
		for i in range(1, 12):
			var ang := -PI / 2 + i / 12.0 * TAU
			shape.append(c + Vector2(cos(ang) * 9, sin(ang) * 9 + 3) * k)
	var top := INF
	var bottom := -INF
	for q in shape:
		top = minf(top, q.y)
		bottom = maxf(bottom, q.y)
	var y := lerpf(bottom, top, part)
	var mask := PackedVector2Array([Vector2(c.x - 30, y), Vector2(c.x + 30, y), Vector2(c.x + 30, bottom + 2), Vector2(c.x - 30, bottom + 2)])
	var colr := Color("#f43f5e") if kind == "heart" else Color("#5fb3f0")
	for poly in Geometry2D.intersect_polygons(shape, mask):
		Draw.polygon_safe(ci, poly, Color(colr, alpha))


## A drop / heart whose bounds are centred on `c`.
static func _icon(ci: CanvasItem, kind: String, c: Vector2, k: float, alpha: float) -> void:
	if kind == "heart":
		SpriteArt.draw_heart(ci, heart_at(c, 12.0 * k), 12.0 * k, 1.0, alpha)
	else:
		SpriteArt.draw_drop(ci, drop_at(c, k), k, Color(Color("#5fb3f0"), alpha))


## One reloaded unit on its way: from the reserve's badge into its slot, a short arc
## over the pill, growing as it comes, a faint trail behind it.
static func _draw_flyer(ci: CanvasItem, r: Rect2, m: MeterModel, f: Dictionary, col: Color, kind: String, alpha: float) -> void:
	var from := badge_icon(r, int(floorf(m.reserve + MeterModel.EPS)))
	var to := slot_center(r, int(f.slot), int(m.slots))
	var mid := (from + to) / 2 + Vector2(0, -26)
	# A part of a unit (a top-up) flies smaller than a whole one.
	var size_k := lerpf(0.55, 1.0, clampf(float(f.amount), 0.0, 1.0))
	for j in 3:
		var tt: float = clampf(float(f.t) - j * 0.09, 0, 1)
		var e := tt * tt * (3 - 2 * tt)
		var p := from.lerp(mid, e).lerp(mid.lerp(to, e), e)
		var a := alpha * (1.0 if j == 0 else 0.3 / j)
		if j == 0:
			Draw.radial_glow(ci, p, 14, Color(col, 0.45 * alpha), Color(1, 1, 1, 0.6 * alpha))
		_icon(ci, kind, p, lerpf(0.7, 1.0, e) * size_k * (1.0 if j == 0 else 0.8), a)
