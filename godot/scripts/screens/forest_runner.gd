class_name ForestRunner
extends Node2D
## Level 2 (demo): after the Big Cramp a corridor opens and Kyra, seen from
## behind (a 2D sprite), runs forward through the forest like an endless runner.
##
##  * Three lanes; ← → change lane, jump / double jump over roots (low, all lanes)
##    and branches (higher, one or two lanes). Hitting one bounces her back and
##    the path rolls back a bit.
##  * Birds (placeholders) fly at her at jump height: one that meets her in the
##    air carries her back along the path.
##  * Water drops fill the focus bar; holding Slow (Shift / E / LB) slows time
##    while it drains, so a tight cluster of obstacles can be read and jumped.
##  * Light seeds are counted for the end of the level (to be designed).
## Coordinates: x = sideways (m, lane centres -LANE..LANE), y = up (m),
## z = along the path (m). The camera follows behind and above Kyra.

signal finished
signal show_dialog(id: String)

const W := 1066.0
const H := 600.0
const HORIZON := 240.0
const FOCAL := 430.0
const CAM_H := 2.0
const CAM_BACK := 3.6
const LANE := 1.7
const SPEED := 9.0
const SPEED_MAX := 13.0
const GRAVITY := 20.0
const JUMP_V := 7.0
const DOUBLE_V := 6.2
const LANE_SPEED := 11.0
const SLOW_SCALE := 0.4
const SLOW_DRAIN := 28.0
const SLOW_MIN := 6.0
const DROP_WATER := 8.0
const BUMP_BACK := 6.0
const CARRY_BACK := 14.0
const LENGTH := 640.0
const VIEW := 70.0
const ROOT_H := 0.5
const BRANCH_H := 1.05
## Height above which a bird catches her (in the air, in its lane).
const BIRD_REACH := 0.75
const BIRD_SPEED := 6.0

## Updated by Main.
var active := false
var dialog_open := false

## Progress along the path (m); the speed grows with it.
var dist := 0.0
var speed := SPEED
var lane := 0
var px := 0.0
var py := 0.0
var vy := 0.0
var jumps := 2
var slow := false
var water := 30.0
var seeds := 0
var time := 0.0
## Rolling back after a bump (s left) or being carried by a bird (s left).
var bump_t := 0.0
var carry_t := 0.0
var _roll_to := 0.0
var done := false
var flash := 0.0

## Course: [{kind, z, lane (or -9 = all), y, hit / taken}]
var objects: Array = []
var trees: Array = []
var _font: Font
var _prev_slow := false


func _ready() -> void:
	_font = Text.font_bold
	water = Game.water if Game.water > 0 else 30.0
	seeds = Game.seeds
	build_course()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var z := 0.0
	while z < LENGTH + VIEW:
		for side: float in [-1.0, 1.0]:
			trees.append({"x": side * rng.randf_range(4.2, 9.0), "z": z + rng.randf_range(0, 3), "h": rng.randf_range(4.5, 8.0), "r": rng.randf_range(1.2, 2.2), "tone": rng.randf()})
		z += rng.randf_range(2.5, 4.0)


## The obstacle course: hand-made patterns, harder towards the end. Clusters
## marked "focus" are meant to be read with slowed time.
func build_course() -> void:
	objects.clear()
	var z := 24.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var step := 0
	while z < LENGTH - 30:
		var k := z / LENGTH
		var pat := step % 7
		step += 1
		match pat:
			0:
				_add("root", z, -9)
				_add_drops(z + 4, rng.randi_range(-1, 1), 3)
				z += 16
			1:
				var l := rng.randi_range(-1, 1)
				_add("branch", z, l)
				_add("drop", z, l, BRANCH_H + 0.5)
				_add_drops(z + 5, (l + 2) % 3 - 1, 3)
				z += 14
			2:
				_add("bird", z, rng.randi_range(-1, 1), 1.1)
				_add("root", z + 8, -9)
				z += 18
			3:
				# Two branches leave one free lane.
				var free := rng.randi_range(-1, 1)
				for l in [-1, 0, 1]:
					if l != free:
						_add("branch", z, l)
				_add("seed", z, free, 0.4)
				z += 15
			4:
				_add_drops(z, rng.randi_range(-1, 1), 5)
				_add("seed", z + 6, rng.randi_range(-1, 1), 1.3)
				z += 14
			5:
				# A focus cluster: root, bird above the jump, then a branch.
				_add("root", z, -9)
				_add("bird", z + 4, 0, 1.2)
				_add("branch", z + 7, -1)
				_add("branch", z + 7, 1)
				_add("seed", z + 7, 0, 0.4)
				z += 20 if k < 0.5 else 16
			6:
				_add("root", z, -9)
				_add("root", z + 5.5, -9)
				_add("drop", z + 2.8, 0, 1.2)
				z += 16
		z += maxf(2.0, 8.0 - k * 6.0)


func _add(kind: String, z: float, l: int, y := 0.0) -> void:
	objects.append({"kind": kind, "z": z, "lane": l, "y": y, "hit": false, "taken": false, "dz": 0.0})


func _add_drops(z: float, l: int, n: int) -> void:
	for i in n:
		_add("drop", z + i * 1.6, l, 0.45)


# --- input & update ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or dialog_open or done or carry_t > 0:
		return
	if event.is_action_pressed("move_left") and not event.is_echo():
		lane = maxi(-1, lane - 1)
	elif event.is_action_pressed("move_right") and not event.is_echo():
		lane = mini(1, lane + 1)
	elif event.is_action_pressed("jump") and not event.is_echo():
		jump()


func jump() -> void:
	if jumps <= 0 or bump_t > 0 or carry_t > 0:
		return
	vy = JUMP_V if jumps == 2 else DOUBLE_V
	jumps -= 1
	Audio.jump_sound(jumps == 0)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	time += dt
	flash = maxf(0, flash - dt)
	if active and not dialog_open and not done:
		_update(dt)
	queue_redraw()


func _update(dt: float) -> void:
	# Slowed time: the world runs slower, Kyra keeps her own pace (focus).
	var want_slow := Input.is_action_pressed("slow_time") and water > (0.0 if _prev_slow else SLOW_MIN)
	slow = want_slow
	_prev_slow = slow
	var wdt := dt * (SLOW_SCALE if slow else 1.0)
	if slow:
		water = maxf(0, water - SLOW_DRAIN * dt)
	# Moving sideways and jumping use real time.
	px = move_toward(px, lane * LANE, LANE_SPEED * dt)
	if carry_t > 0:
		carry_t -= dt
		dist = move_toward(dist, _roll_to, CARRY_BACK / 1.2 * dt)
		py = lerpf(py, 1.8, dt * 3)
		if carry_t <= 0:
			vy = 0
			jumps = 1
		return
	vy -= GRAVITY * dt
	py += vy * dt
	if py <= 0:
		py = 0
		vy = 0
		jumps = 2
	if bump_t > 0:
		bump_t -= dt
		dist = move_toward(dist, _roll_to, BUMP_BACK / 0.45 * dt)
		return
	speed = lerpf(SPEED, SPEED_MAX, clampf(dist / LENGTH, 0, 1))
	dist += speed * wdt
	_hits(wdt)
	if dist >= LENGTH:
		done = true
		finished.emit()


func _hits(wdt: float) -> void:
	for o in objects:
		if o.taken or o.hit:
			continue
		if o.kind == "bird" and o.z + o.dz - dist < 28.0:
			# Birds fly at her once she is near: their speed adds to hers.
			o.dz -= BIRD_SPEED * wdt
		var rz: float = o.z + o.dz - dist
		if rz > 0.6 or rz < -0.6:
			continue
		var in_lane: bool = o.lane == -9 or absf(px - o.lane * LANE) < LANE * 0.6
		if not in_lane:
			continue
		match o.kind:
			"root":
				if py < ROOT_H:
					o.hit = true
					bump()
			"branch":
				if py < BRANCH_H:
					o.hit = true
					bump()
			"bird":
				if py > BIRD_REACH:
					o.hit = true
					carried()
			"drop":
				if absf(py - o.y) < 0.8:
					o.taken = true
					water = minf(100, water + DROP_WATER)
					Audio.play_sfx("cink-%02d.wav" % (1 + int(time * 7) % 11), 0.35)
			"seed":
				if absf(py - o.y) < 0.9:
					o.taken = true
					seeds += 1
					Audio.play_sfx("finished.wav", 0.4)


## Ran into a root or a branch: bounce back, the path rolls back a bit.
func bump() -> void:
	bump_t = 0.45
	_roll_to = maxf(0, dist - BUMP_BACK)
	vy = 3.0
	flash = 0.4
	Audio.play_sfx("au%d.wav" % (1 + int(time * 13) % 5), 0.6)
	_reset_behind()


## Caught by a bird in the air: carried back along the path.
func carried() -> void:
	carry_t = 1.2
	_roll_to = maxf(0, dist - CARRY_BACK)
	flash = 0.3
	Audio.play_sfx("au%d.wav" % (1 + int(time * 7) % 5), 0.7)
	_reset_behind()


## Obstacles she now has to pass again are armed again.
func _reset_behind() -> void:
	for o in objects:
		if o.kind in ["root", "branch", "bird"] and o.z + o.dz > _roll_to - 1 and o.z <= dist + 1:
			o.hit = false
			o.dz = 0.0


func progress() -> float:
	return clampf(dist / LENGTH, 0, 1)


# --- drawing --------------------------------------------------------------------------------

## Screen position of a world point (x, y, z relative to the path start).
func project(x: float, y: float, z: float) -> Vector3:
	var rz := z - dist + CAM_BACK
	if rz < 0.3:
		return Vector3(0, 0, -1)
	var k := FOCAL / rz
	return Vector3(W / 2 + (x - px * 0.35) * k, HORIZON + (CAM_H - y) * k, k)


func _fog(c: Color, z: float) -> Color:
	var k := clampf((z - dist) / VIEW, 0, 1)
	return c.lerp(Color("#cfe7df"), k * 0.85)


func _draw() -> void:
	# Sky and ground.
	for b in 8:
		draw_rect(Rect2(0, HORIZON * b / 8.0, W, HORIZON / 8.0 + 1), Color("#a8d8cf").lerp(Color("#e8efd0"), b / 8.0))
	Draw.radial_glow(self, Vector2(W * 0.5, HORIZON - 30), 160, Color(1, 0.96, 0.75, 0.5), Color(1, 1, 0.9, 0.9))
	draw_rect(Rect2(0, HORIZON, W, H - HORIZON), Color("#4f8a4f"))
	# The path: a trapezoid to the horizon with moving stripes.
	var near_l := project(-LANE * 1.9, 0, dist + 0.4 - CAM_BACK + 0.31)
	var near_r := project(LANE * 1.9, 0, dist + 0.4 - CAM_BACK + 0.31)
	var far_l := project(-LANE * 1.9, 0, dist + VIEW)
	var far_r := project(LANE * 1.9, 0, dist + VIEW)
	draw_colored_polygon(PackedVector2Array([Vector2(near_l.x - 200, H), Vector2(far_l.x, far_l.y), Vector2(far_r.x, far_r.y), Vector2(near_r.x + 200, H)]), Color("#b48a5a"))
	var sz := floorf(dist / 3.0) * 3.0
	while sz < dist + VIEW:
		var a := project(-LANE * 1.9, 0, sz)
		var b := project(LANE * 1.9, 0, sz)
		if a.z > 0:
			draw_line(Vector2(a.x, a.y), Vector2(b.x, b.y), _fog(Color("#9c7448"), sz), maxf(1, a.z * 0.05))
		sz += 3.0
	# Far to near: trees and course objects.
	var items := []
	for t in trees:
		if t.z > dist - CAM_BACK + 0.5 and t.z < dist + VIEW:
			items.append([t.z, "tree", t])
	for o in objects:
		var oz: float = o.z + o.dz
		if oz > dist - CAM_BACK + 0.5 and oz < dist + VIEW and not o.taken:
			items.append([oz, o.kind, o])
	items.sort_custom(func(a, b): return a[0] > b[0])
	var player_drawn := false
	for it in items:
		if not player_drawn and it[0] < dist:
			_draw_player()
			player_drawn = true
		match it[1]:
			"tree": _draw_tree(it[2])
			"root": _draw_root(it[2])
			"branch": _draw_branch(it[2])
			"bird": _draw_bird(it[2])
			"drop": _draw_drop(it[2])
			"seed": _draw_seed(it[2])
	if not player_drawn:
		_draw_player()
	# Slowed time: a cool tint and a focus ring.
	if slow:
		draw_rect(Rect2(0, 0, W, H), Color(0.35, 0.55, 0.9, 0.18))
		Draw.vignette(self, Rect2(0, 0, W, H), Color(0.1, 0.15, 0.35, 0.45), 0.35)
	if flash > 0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 0.4, 0.3, flash * 0.6))
	_draw_hud()


func _draw_tree(t: Dictionary) -> void:
	var base := project(t.x, 0, t.z)
	var top := project(t.x, t.h, t.z)
	if base.z <= 0:
		return
	var trunk := _fog(Color("#5b3b24"), t.z)
	draw_line(Vector2(base.x, base.y), Vector2(top.x, top.y), trunk, maxf(1, 0.35 * base.z))
	var leaf := _fog(Color("#2f6b3a").lerp(Color("#4d8f45"), t.tone), t.z)
	var r: float = t.r * base.z
	draw_circle(Vector2(top.x, top.y), r, leaf)
	draw_circle(Vector2(top.x - r * 0.6, top.y + r * 0.35), r * 0.75, leaf.darkened(0.08))
	draw_circle(Vector2(top.x + r * 0.6, top.y + r * 0.3), r * 0.7, leaf.lightened(0.05))


func _lanes_of(o: Dictionary) -> Array:
	return [-1, 0, 1] if o.lane == -9 else [o.lane]


func _draw_root(o: Dictionary) -> void:
	var z: float = o.z
	var a := project(-LANE * 1.8, 0, z)
	var b := project(LANE * 1.8, 0, z)
	if a.z <= 0:
		return
	var col := _fog(Color("#6b4423"), z)
	# A gnarled root humping out of the path across all three lanes.
	var top := PackedVector2Array()
	var poly := PackedVector2Array()
	for i in 17:
		var k := i / 16.0
		var hump := (0.55 + 0.45 * sin(k * PI * 3.0 + z)) * sin(k * PI) ** 0.4
		top.append(Vector2(lerpf(a.x, b.x, k), a.y - ROOT_H * 0.9 * a.z * hump))
	poly.append_array(top)
	poly.append(Vector2(b.x, b.y + 0.04 * a.z))
	poly.append(Vector2(a.x, a.y + 0.04 * a.z))
	Draw.polygon_safe(self, poly, col)
	draw_polyline(top, col.lightened(0.25), maxf(1, 0.06 * a.z), true)
	for i in 3:
		var k := 0.25 + i * 0.25
		var kx := lerpf(a.x, b.x, k)
		draw_circle(Vector2(kx, a.y - ROOT_H * 0.35 * a.z), 0.05 * a.z, col.darkened(0.25))


func _draw_branch(o: Dictionary) -> void:
	var z: float = o.z
	var c := project(o.lane * LANE, 0, z)
	if c.z <= 0:
		return
	var w := LANE * 0.55 * c.z
	var top := c.y - BRANCH_H * 0.85 * c.z
	var col := _fog(Color("#7a5230"), z)
	# A fallen branch lying across the lane on two stubs.
	draw_line(Vector2(c.x - w, c.y), Vector2(c.x - w * 0.8, top), col.darkened(0.2), maxf(1, 0.12 * c.z))
	draw_line(Vector2(c.x + w, c.y), Vector2(c.x + w * 0.8, top), col.darkened(0.2), maxf(1, 0.12 * c.z))
	draw_line(Vector2(c.x - w * 1.15, top + 0.05 * c.z), Vector2(c.x + w * 1.15, top - 0.05 * c.z), col, maxf(2, 0.22 * c.z))
	draw_circle(Vector2(c.x + w * 0.4, top - 0.12 * c.z), 0.12 * c.z, _fog(Color("#4d8f45"), z))


func _draw_bird(o: Dictionary) -> void:
	var z: float = o.z + o.dz
	var c := project(o.lane * LANE, o.y, z)
	if c.z <= 0:
		return
	var s := 0.45 * c.z
	var flap := sin(time * 14 + o.z) * 0.6
	var col := _fog(Color("#3b3b4f"), z)
	# Placeholder bird: body and two flapping wings.
	draw_circle(Vector2(c.x, c.y), s * 0.35, col)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.2, c.y), Vector2(c.x - s * 1.2, c.y - s * flap), Vector2(c.x - s * 0.5, c.y + s * 0.15)]), col)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x + s * 0.2, c.y), Vector2(c.x + s * 1.2, c.y - s * flap), Vector2(c.x + s * 0.5, c.y + s * 0.15)]), col)
	draw_circle(Vector2(c.x, c.y + s * 0.1), s * 0.07, Color("#fbbf24"))
	# Its shadow on the path.
	var g := project(o.lane * LANE, 0, z)
	draw_set_transform(Vector2(g.x, g.y), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, s * 0.6, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_drop(o: Dictionary) -> void:
	var c := project(_lane_x(o), o.y + sin(time * 4 + o.z) * 0.05, o.z)
	if c.z <= 0:
		return
	var s := 0.16 * c.z
	var pts := PackedVector2Array([Vector2(c.x, c.y - s * 1.6)])
	for i in range(1, 12):
		var ang := -PI / 2 + i / 12.0 * TAU
		pts.append(Vector2(c.x + cos(ang) * s, c.y + sin(ang) * s + s * 0.3))
	draw_colored_polygon(pts, _fog(Color("#5fb3f0"), o.z))
	draw_circle(Vector2(c.x - s * 0.3, c.y), s * 0.25, Color(1, 1, 1, 0.8))


func _draw_seed(o: Dictionary) -> void:
	var c := project(_lane_x(o), o.y + sin(time * 3 + o.z) * 0.08, o.z)
	if c.z <= 0:
		return
	var s := 0.18 * c.z
	Draw.radial_glow(self, Vector2(c.x, c.y), s * 3, Color(1, 0.85, 0.4, 0.5), Color(1, 0.98, 0.8, 0.95))
	draw_circle(Vector2(c.x, c.y), s * 0.6, Color("#fff4c2"))


func _lane_x(o: Dictionary) -> float:
	return 0.0 if o.lane == -9 else o.lane * LANE


## Kyra from behind (placeholder art until the back-view frames exist).
func _draw_player() -> void:
	var g := project(px, 0, dist)
	var c := project(px, py, dist)
	if c.z <= 0:
		return
	var k := c.z / 100.0
	# Shadow on the path, smaller the higher she is.
	draw_set_transform(Vector2(g.x, g.y), 0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 34 * k * (1.0 - clampf(py / 3.0, 0, 0.6)), Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var run := sin(time * (16.0 if not slow else 9.0))
	var air := py > 0.05 or carry_t > 0
	var bob := 0.0 if air else absf(run) * 4 * k
	var feet := Vector2(c.x, c.y - bob)
	var lean := -0.25 if bump_t > 0 else 0.0
	draw_set_transform(feet, lean, Vector2.ONE)
	var boot := Color("#8a4b1f")
	var leg := Color("#9aa3ad")
	# Legs (alternating while running, tucked in the air).
	for side: float in [-1.0, 1.0]:
		var lift := (8 * k if air else maxf(0, run * side) * 14 * k)
		var lx := side * 9 * k
		draw_line(Vector2(lx, -52 * k), Vector2(lx, -12 * k - lift), leg, 9 * k)
		draw_rect(Rect2(lx - 6 * k, -14 * k - lift, 12 * k, 14 * k), boot)
	# Tunic, sash, arms.
	var tunic := Color("#5f9b99")
	draw_colored_polygon(PackedVector2Array([Vector2(-22 * k, -52 * k), Vector2(22 * k, -52 * k), Vector2(17 * k, -112 * k), Vector2(-17 * k, -112 * k)]), tunic)
	draw_rect(Rect2(-19 * k, -72 * k, 38 * k, 8 * k), Color("#d97706"))
	var arm_up := carry_t > 0
	for side: float in [-1.0, 1.0]:
		var swing := run * side * 10 * k
		var hand := Vector2(side * 30 * k, (-150 * k) if arm_up else (-62 * k + swing))
		draw_line(Vector2(side * 18 * k, -106 * k), hand, tunic.darkened(0.15), 8 * k)
	# Head from behind: white hair and a swinging ponytail.
	draw_circle(Vector2(0, -126 * k), 17 * k, Color("#f1f5f9"))
	var tail := sin(time * 8) * 6 * k
	draw_line(Vector2(0, -122 * k), Vector2(tail, -96 * k), Color("#e2e8f0"), 9 * k)
	draw_circle(Vector2(0, -118 * k), 5 * k, Color("#d97706"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if carry_t > 0:
		# The bird holding her.
		var bp := Vector2(c.x, c.y - 165 * k)
		var flap := sin(time * 16) * 0.8
		var s := 40 * k
		var col := Color("#3b3b4f")
		draw_circle(bp, s * 0.35, col)
		draw_colored_polygon(PackedVector2Array([bp + Vector2(-s * 0.2, 0), bp + Vector2(-s * 1.4, -s * flap), bp + Vector2(-s * 0.5, s * 0.15)]), col)
		draw_colored_polygon(PackedVector2Array([bp + Vector2(s * 0.2, 0), bp + Vector2(s * 1.4, -s * flap), bp + Vector2(s * 0.5, s * 0.15)]), col)


func _draw_hud() -> void:
	var bg := Color("#f0eee9")
	var ink := Color("#064e3b")
	# Seeds.
	var label := str(seeds)
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var r := Rect2(16, 16, tw + 70, 48)
	Draw.panel(self, r, bg, 16, Color(0.37, 0.61, 0.6, 0.2), 2)
	draw_string(_font, Vector2(r.position.x + 20, r.position.y + 31), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	var ic := Vector2(r.end.x - 26, r.position.y + 24)
	Draw.radial_glow(self, ic, 16, Color(1, 0.85, 0.4, 0.5), Color(1, 0.98, 0.8, 0.95))
	draw_circle(ic, 6, Color("#fff4c2"))
	# Progress along the path.
	var pr := Rect2(W / 2 - 200, 26, 400, 10)
	Draw.panel(self, pr, Color(1, 1, 1, 0.5), 5)
	Draw.panel(self, Rect2(pr.position, Vector2(pr.size.x * progress(), pr.size.y)), Color("#16a34a"), 5)
	draw_circle(Vector2(pr.position.x + pr.size.x * progress(), pr.get_center().y), 8, Color.WHITE)
	# Water = focus bar.
	var v := Rect2(W / 2 - 170, H - 44, 340, 28)
	Draw.panel(self, v, bg, 14, Color(0.37, 0.61, 0.6, 0.2), 2)
	var inner := Rect2(v.position.x + 6, v.position.y + 6, v.size.x - 12, v.size.y - 12)
	Draw.panel(self, inner, Color("#dbeafe"), 8)
	if water > 0.5:
		Draw.panel(self, Rect2(inner.position, Vector2(inner.size.x * water / 100.0, inner.size.y)), Color("#5fb3f0") if not slow else Color("#93c5fd"), 8)
	var hint := Text.plain(Text.t("RUNNER_SLOW_HINT"))
	Draw.text_center(self, Text.font, Vector2(v.get_center().x, v.position.y - 10), hint, 12, Color(1, 1, 1, 0.95))
