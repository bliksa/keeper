class_name PmsMaze
extends RefCounted
## Level 4 of the game, the PMS maze (luteal phase, Platformer level_id 6 = Game.PMS_ID):
## the map check (reachability with the real jump physics) and the code-drawn art: soft
## breathing blobs for walls and platforms, the three comfort items, the door, the
## objects that don't belong (a melting clock, a floating chair, a tilted frame, a sock)
## and the hazy dusk background. Everything is drawn in world coordinates; Platformer
## rotates the whole view 180° (view_flip), so on screen it is all upside down.

## The comfort items by order in the map (LevelData "&", Ent.tier).
const ITEMS := ["tea", "bottle", "blanket"]
const ITEM_DIALOGS := ["4B", "4C", "4D"]
## After the third item, whichever it is: the door is open.
const DOOR_DIALOG := "4F"
const WALL := Color("#45375c")
const WALL_RIM := Color("#2a2040")
const WALL_TOP := Color("#7d6a96")
const PLAT := Color("#c98aa6")
const PLAT_RIM := Color("#85506b")
const DECO := ["clock", "chair", "frame", "sock"]


# --- the map check -------------------------------------------------------------------

## Reachability on the grid with the real jump: a single jump climbs one row (≈ 130 px of
## 120), a double jump two rows, up to 3 cells sideways; walking off an edge falls straight
## down; W blocks from every side, = only from above. Returns {ok, spawn, items, door,
## unreachable: [...], traps: [...]}: ok = from the spawn every item and the door can be
## reached, and from everywhere she can get to, all of them still can (no soft lock).
static func check(rows: PackedStringArray) -> Dictionary:
	var out := {"ok": false, "spawn": Vector2i(-1, -1), "items": [], "door": Vector2i(-1, -1), "unreachable": [], "traps": []}
	if rows.is_empty():
		return out
	var targets: Array = []
	for r in rows.size():
		for c in rows[r].length():
			var ch := rows[r][c]
			if ch == "P":
				out.spawn = _land(rows, r + 1, c)
			elif ch == "&":
				out.items.append(Vector2i(r + 1, c))
			elif ch == "D":
				out.door = Vector2i(r + 1, c)
	targets.append_array(out.items)
	targets.append(out.door)
	if out.spawn.x < 0 or out.door.x < 0:
		return out
	var reach := _bfs(rows, out.spawn)
	for t in targets:
		if not reach.has(t):
			out.unreachable.append(t)
	for n in reach:
		var from := _bfs(rows, n)
		for t in targets:
			if not from.has(t):
				out.traps.append(n)
				break
	out.ok = out.unreachable.is_empty() and out.traps.is_empty() and out.items.size() == 3
	return out


static func _g(rows: PackedStringArray, r: int, c: int) -> String:
	if r < 0 or r >= rows.size() or c < 0 or c >= rows[r].length():
		return "W"
	return rows[r][c]


static func _solid(ch: String) -> bool:
	return ch == "=" or ch == "W"


## A standing place: feet on the top of row r, the body in row r - 1.
static func _surf(rows: PackedStringArray, r: int, c: int) -> bool:
	return c >= 0 and c < rows[0].length() and _solid(_g(rows, r, c)) and _g(rows, r - 1, c) != "W"


## Falling down column c from the top of row r: the first solid row.
static func _land(rows: PackedStringArray, r: int, c: int) -> Vector2i:
	var rr := r
	while rr < rows.size() and not _solid(_g(rows, rr, c)):
		rr += 1
	return Vector2i(rr, c) if rr < rows.size() else Vector2i(-1, -1)


static func _clear(rows: PackedStringArray, r: int, c0: int, c1: int) -> bool:
	for x in range(mini(c0, c1), maxi(c0, c1) + 1):
		if _g(rows, r, x) == "W":
			return false
	return true


static func _next(rows: PackedStringArray, n: Vector2i) -> Array:
	var r := n.x
	var c := n.y
	var out: Array = []
	for dc in [-1, 1]:
		var cc: int = c + dc
		if cc < 0 or cc >= rows[0].length() or _g(rows, r - 1, cc) == "W":
			continue
		out.append(Vector2i(r, cc) if _surf(rows, r, cc) else _land(rows, r, cc))
	for d in range(-3, 4):
		var cc := c + d
		if _surf(rows, r - 1, cc) and _clear(rows, r - 2, c, cc):
			out.append(Vector2i(r - 1, cc))
		if _surf(rows, r - 2, cc) and _g(rows, r - 2, c) != "W" and _clear(rows, r - 3, c, cc):
			out.append(Vector2i(r - 2, cc))
		# A hop over a gap or a low block, landing on the same level or lower.
		if cc >= 0 and cc < rows[0].length() and _clear(rows, r - 2, c, cc) and _clear(rows, r - 1, c, cc):
			out.append(Vector2i(r, cc) if _surf(rows, r, cc) else _land(rows, r, cc))
	return out.filter(func(v): return v.x >= 0)


static func _bfs(rows: PackedStringArray, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var n: Vector2i = q.pop_front()
		for m in _next(rows, n):
			if not seen.has(m):
				seen[m] = true
				q.append(m)
	return seen


## Places for the objects that don't belong: empty cells with an empty cell above,
## spread out (deterministic). [{kind, pos, rot, phase}]
static func deco_spots(level: LevelData) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4061
	var cand: Array = []
	var rows := level.rows
	for r in range(1, rows.size() - 1):
		for c in range(1, rows[r].length() - 1):
			if rows[r][c] == " " and rows[r - 1][c] == " " and rows[r][c - 1] == " " and rows[r][c + 1] == " ":
				cand.append(Vector2(c * LevelData.CELL_W + LevelData.CELL_W / 2, r * level.row_h - 10))
	for i in range(cand.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Vector2 = cand[i]
		cand[i] = cand[j]
		cand[j] = tmp
	var out: Array = []
	for pos in cand:
		var far := true
		for d in out:
			if (d.pos as Vector2).distance_to(pos) < 330:
				far = false
				break
		if far:
			out.append({"kind": DECO[out.size() % DECO.size()], "pos": pos, "rot": rng.randf_range(-0.7, 0.7), "phase": rng.randf() * TAU})
		if out.size() >= 12:
			break
	return out


# --- drawing ---------------------------------------------------------------------------

## Wall rects stacked exactly on each other (same x and width, touching) as one rect, so a
## column of W cells is drawn as one soft blob.
static func merge_columns(walls: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in walls:
		var merged := false
		for i in out.size():
			var o := out[i]
			if is_equal_approx(o.position.x, r.position.x) and is_equal_approx(o.size.x, r.size.x) and is_equal_approx(o.end.y, r.position.y):
				out[i] = Rect2(o.position, Vector2(o.size.x, o.size.y + r.size.y))
				merged = true
				break
		if not merged:
			out.append(r)
	return out


## A soft, slowly breathing blob over a rect (sin-perturbed rounded outline). amp = px.
static func blob_points(r: Rect2, t: float, amp: float, seed_v: float) -> PackedVector2Array:
	var rad := minf(13.0, minf(r.size.x, r.size.y) / 2)
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2],
		[Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
		[Vector2(r.position.x + rad, r.position.y + rad), PI],
	]
	var edges := [
		[Vector2(r.position.x + rad, r.position.y), Vector2(r.end.x - rad, r.position.y), Vector2.UP],
		[Vector2(r.end.x, r.position.y + rad), Vector2(r.end.x, r.end.y - rad), Vector2.RIGHT],
		[Vector2(r.end.x - rad, r.end.y), Vector2(r.position.x + rad, r.end.y), Vector2.DOWN],
		[Vector2(r.position.x, r.end.y - rad), Vector2(r.position.x, r.position.y + rad), Vector2.LEFT],
	]
	for i in 4:
		var a: Vector2 = edges[i][0]
		var b: Vector2 = edges[i][1]
		var n := int(a.distance_to(b) / 18.0)
		for k in n:
			pts.append(a.lerp(b, float(k) / maxf(1, n)))
			nrm.append(edges[i][2])
		var cc: Vector2 = corners[i][0]
		for k in 5:
			var ang: float = corners[i][1] + k / 4.0 * PI / 2
			var d := Vector2(cos(ang), sin(ang))
			pts.append(cc + d * rad)
			nrm.append(d)
	var breath := sin(t / 1500.0 + seed_v) * amp * 0.5
	for i in pts.size():
		var q := pts[i]
		var w := sin(t / 900.0 + q.x * 0.045 + q.y * 0.031 + seed_v) * 0.6 + sin(t / 1300.0 - q.x * 0.021 + q.y * 0.052) * 0.4
		pts[i] = q + nrm[i] * (amp * w + breath)
	return pts


## A wall block or a platform as a blob (pass 0 = the rim, 1 = the body).
static func draw_blob(ci: CanvasItem, r: Rect2, t: float, amp: float, wall: bool, pass_i: int, a := 1.0) -> void:
	var sv := r.position.x * 0.013 + r.position.y * 0.007
	if pass_i == 0:
		Draw.polygon_safe(ci, blob_points(r.grow(4), t, amp, sv), Color(WALL_RIM if wall else PLAT_RIM, a))
		return
	var body := blob_points(r, t, amp, sv)
	Draw.polygon_safe(ci, body, Color(WALL if wall else PLAT, a))
	# A soft lighter top on wide blobs (the walkable side, in world coordinates).
	var top := Rect2(r.position + Vector2(10, 4), Vector2(maxf(0, r.size.x - 20), minf(10.0, r.size.y * 0.25)))
	if top.size.x > 60 or not wall:
		Draw.panel(ci, Rect2(top.position + Vector2(0, sin(t / 1100.0 + sv) * amp * 0.5), top.size), Color(WALL_TOP if wall else Color("#e0b3c4"), 0.45 * a), 5)


## The hazy dusk behind the maze (drawn in view space, a margin around it for the sway).
static func draw_bg(ci: CanvasItem, vs: Vector2, t: float, cam_y: float, level_h: float, steady: float) -> void:
	var m := 260.0
	var full := Rect2(-m, -m, vs.x + 2 * m, vs.y + 2 * m)
	var k := clampf(cam_y / maxf(1, level_h), 0, 1)
	# Local top = the screen's bottom (the view is upside down): rose haze → deep violet.
	var top := Color("#d9b3c5").lerp(Color("#c7a9cf"), k)
	var bot := Color("#9a7fb0").lerp(Color("#8d77ab"), k)
	var bands := 18
	for b in bands:
		var y0 := full.position.y + full.size.y * b / bands
		ci.draw_rect(Rect2(full.position.x, y0, full.size.x, full.size.y / bands + 1), top.lerp(bot, (b + 0.5) / bands))
	# Slow fog: wide soft ellipses drifting sideways (calmer while she breathes).
	var drift := 1.0 - 0.6 * steady
	for i in 9:
		var depth := 0.15 + 0.07 * (i % 4)
		var x := fposmod(i * 311.0 + t * 0.012 * drift * (1 + i % 3), vs.x + 2 * m) - m
		var y := fposmod(i * 197.0 - cam_y * depth, vs.y + 2 * m) - m
		ci.draw_set_transform(Vector2(x, y), 0.0, Vector2(3.2, 0.9))
		Draw.radial_glow(ci, Vector2.ZERO, 90 + 20 * (i % 3), Color(0.93, 0.85, 0.95, 0.10 * (1.0 - 0.4 * steady)))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# Dust motes.
	for i in 30:
		var px := fposmod(i * 173.0 + sin(t / 2100.0 + i) * 30, vs.x + 2 * m) - m
		var py := fposmod(i * 89.0 + t * 0.008 * (1 + i % 3) - cam_y * 0.2, vs.y + 2 * m) - m
		ci.draw_circle(Vector2(px, py), 1.4 + (i % 3) * 0.6, Color(1, 0.92, 0.96, 0.18 + 0.1 * sin(t / 700.0 + i)))


## A comfort item centred on c (s = scale).
## The drawn bounds of an item at scale 1 round its `c` (`draw_item`; the tea's faint
## steam left out): the HUD centres them in its slots.
static func item_bounds(kind: String) -> Rect2:
	match kind:
		"tea":
			return Rect2(-22.4, -11, 44.8, 23.3)
		"bottle":
			return Rect2(-14, -22, 28, 39)
		"blanket":
			return Rect2(-17, -12, 42, 24)
	return Rect2(-16, -16, 32, 32)


static func draw_item(ci: CanvasItem, kind: String, c: Vector2, t: float, s := 1.0, a := 1.0) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(s, s))
	match kind:
		"tea":
			ci.draw_set_transform(c + Vector2(0, 6) * s, 0.0, Vector2(s * 1.6, s * 0.45))
			ci.draw_circle(Vector2.ZERO, 14, Color("#f3e6ee", a))
			ci.draw_set_transform(c, 0.0, Vector2(s, s))
			var cup := PackedVector2Array([Vector2(-12, -10), Vector2(12, -10), Vector2(9, 6), Vector2(-9, 6)])
			ci.draw_colored_polygon(cup, Color("#f7d9e3", a))
			ci.draw_polyline(cup + PackedVector2Array([cup[0]]), Color("#9d6b80", a), 2.0, true)
			ci.draw_rect(Rect2(-11, -9, 22, 4), Color("#c98a5a", a))
			ci.draw_arc(Vector2(13, -3), 5, -PI / 2, PI / 2, 10, Color("#9d6b80", a), 2.5, true)
			for i in 2:
				var x0 := -4.0 + i * 8
				var pts := PackedVector2Array()
				for k in 7:
					var yy := -14.0 - k * 3.0
					pts.append(Vector2(x0 + sin(t / 260.0 + k * 0.9 + i) * 2.5, yy))
				ci.draw_polyline(pts, Color(1, 1, 1, 0.55 * a), 1.5, true)
		"bottle":
			ci.draw_rect(Rect2(-5, -19, 10, 7), Color("#7c3a55", a))
			Draw.panel(ci, Rect2(-14, -13, 28, 30), Color("#e0708f", a), 9)
			for i in 3:
				var yy := -6.0 + i * 7
				ci.draw_line(Vector2(-9, yy), Vector2(9, yy), Color("#f6b3c4", 0.8 * a), 2.0)
			ci.draw_rect(Rect2(-6, -22, 12, 4), Color("#4a2236", a))
		"blanket":
			Draw.panel(ci, Rect2(-17, -12, 34, 24), Color("#9fb7d9", a), 7)
			for i in 3:
				ci.draw_line(Vector2(-17 + 9 + i * 8, -12), Vector2(-17 + 9 + i * 8, 12), Color("#eef3fb", 0.6 * a), 2.0)
			ci.draw_line(Vector2(-17, -2), Vector2(17, -2), Color("#eef3fb", 0.6 * a), 2.0)
			ci.draw_arc(Vector2(15, 0), 8, -PI / 2, PI / 2, 10, Color("#7d96bd", a), 4.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## The door: closed = dim and wobbly, a small lamp per item found; open = warm light.
static func draw_door(ci: CanvasItem, e: LevelData.Ent, t: float, found: int, open_k: float) -> void:
	var base := Vector2(e.x + e.w / 2, e.y + e.h)
	var sway := sin(t / 700.0) * 0.05 * (1.0 - open_k)
	if open_k > 0:
		Draw.radial_glow(ci, base + Vector2(0, -e.h * 0.5), 90 + 20 * open_k + sin(t / 400.0) * 6, Color(1, 0.85, 0.6, 0.45 * open_k), Color(1, 0.97, 0.88, 0.8 * open_k))
	ci.draw_set_transform(base, sway, Vector2(1.0 + sin(t / 900.0) * 0.03 * (1.0 - open_k), 1.0))
	var w := e.w
	var h := e.h
	var arch := PackedVector2Array([Vector2(-w / 2, 0), Vector2(-w / 2, -h + w / 2)])
	for k in 9:
		var ang := PI + k / 8.0 * PI
		arch.append(Vector2(0, -h + w / 2) + Vector2(cos(ang), sin(ang)) * w / 2)
	arch.append(Vector2(w / 2, 0))
	ci.draw_colored_polygon(arch, Color("#3b2f4b"))
	if open_k > 0:
		# The opening: warm light inside, the door leaf swung aside.
		var inner := PackedVector2Array()
		for q in arch:
			inner.append(q * 0.84 + Vector2(0, -3))
		ci.draw_colored_polygon(inner, Color(1, 0.93, 0.78).lerp(Color("#3b2f4b"), 1.0 - open_k))
		var leaf := w * 0.8 * (1.0 - 0.75 * open_k)
		ci.draw_rect(Rect2(-w / 2 - 2, -h + 6, leaf, h - 6), Color("#7a5f8a"))
	else:
		var inner := PackedVector2Array()
		for q in arch:
			inner.append(q * 0.84 + Vector2(0, -3))
		ci.draw_colored_polygon(inner, Color("#6d5680"))
		ci.draw_circle(Vector2(w * 0.25, -h * 0.45), 3, Color("#cdb6d8"))
	for i in 3:
		var lp := Vector2((i - 1) * 12, -h + w / 2 - 4)
		var on := i < found
		if on:
			ci.draw_circle(lp, 7, Color(1, 0.86, 0.6, 0.35))
		ci.draw_circle(lp, 3.5, Color("#ffe7b0") if on else Color("#4b3c5c"))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## An object that doesn't belong, drifting slightly at an odd angle.
static func draw_deco(ci: CanvasItem, d: Dictionary, t: float, steady: float) -> void:
	var ph: float = d.phase
	var calm := 1.0 - 0.7 * steady
	var pos: Vector2 = d.pos + Vector2(sin(t / 2300.0 + ph) * 12, cos(t / 1900.0 + ph) * 9) * calm
	var rot: float = d.rot + sin(t / 3100.0 + ph) * 0.18 * calm
	ci.draw_set_transform(pos, rot, Vector2.ONE)
	var a := 0.8
	match String(d.kind):
		"clock":
			# A melting clock: a face that drips down.
			var face := PackedVector2Array()
			for k in 24:
				var ang := k / 24.0 * TAU
				var rr := 20.0
				var drip := maxf(0, sin(ang)) * (8 + 6 * sin(t / 1200.0 + ph + k))
				face.append(Vector2(cos(ang) * rr, sin(ang) * rr + drip))
			ci.draw_colored_polygon(face, Color("#f1e3c6", a))
			ci.draw_polyline(face + PackedVector2Array([face[0]]), Color("#9c7b54", a), 2.0, true)
			ci.draw_line(Vector2.ZERO, Vector2(0, -12), Color("#4b3c5c", a), 2.0)
			ci.draw_line(Vector2.ZERO, Vector2(9, 4), Color("#4b3c5c", a), 2.0)
		"chair":
			var wood := Color("#8a6a58", a)
			ci.draw_rect(Rect2(-14, -2, 28, 5), wood)
			ci.draw_rect(Rect2(-14, -26, 4, 24), wood)
			ci.draw_rect(Rect2(-14, -26, 20, 4), wood)
			ci.draw_rect(Rect2(-13, 3, 3, 18), wood)
			ci.draw_rect(Rect2(10, 3, 3, 18), wood)
		"frame":
			ci.draw_rect(Rect2(-20, -16, 40, 32), Color("#b39058", a))
			ci.draw_rect(Rect2(-15, -11, 30, 22), Color("#cfe0e6", a))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-15, 11), Vector2(-4, -2), Vector2(4, 5), Vector2(9, 0), Vector2(15, 11)]), Color("#7f9a7d", a))
			ci.draw_circle(Vector2(8, -5), 3, Color("#f2c46d", a))
		"sock":
			var sock := PackedVector2Array([Vector2(-6, -22), Vector2(6, -22), Vector2(6, 4), Vector2(16, 8), Vector2(16, 16), Vector2(-4, 16), Vector2(-6, 10)])
			ci.draw_colored_polygon(sock, Color("#d98fb0", a))
			for k in 3:
				ci.draw_rect(Rect2(-6, -18 + k * 7, 12, 3), Color("#f6d2e2", a))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
