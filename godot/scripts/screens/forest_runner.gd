class_name ForestRunner
extends Node2D
## Level 2: after the Big Cramp a corridor opens and Kyra, seen from behind
## (a 2D sprite), runs forward through the forest like an endless runner.
##
##  * The course is a top-down map (data/levels/forest_run.txt, level editor id
##    4, LEVEL_ID): 5 columns (left side, three paths, right side), one row =
##    ROW_M metres, the bottom row is the start. Legend in build_course().
##  * The sun at the top is 12 triangular slices: each sun piece fills one. Every
##    SUN_PER_GAME pieces a minigame starts (signal sun_game); the 12th leads
##    straight to level 3 (finished).
##  * The map is cut into stages by "A" rows. Each is faster than the one before
##    (STAGE_SPEED); from RANDOM_TRAPS_FROM on, side traps also appear at random.
##    A stage repeats from its start until its pieces are found (endless forest).
##
##  * Three lanes; ← → change lane, jump / double jump over roots (low, all lanes)
##    and branches (higher, one or two lanes). Hitting one bounces her back and
##    the path rolls back a bit.
##  * Flying notifications (envelopes with wings, kind "bird") fly at her at jump
##    height: one that meets her in the air carries her back along the path.
##  * Water drops fill the focus bar; holding Slow (Shift / E / LB) slows time
##    while it drains, so a tight cluster of obstacles can be read and jumped.
##  * Light seeds are counted for the end of the level (to be designed).
## Coordinates: x = sideways (m, lane centres -LANE..LANE), y = up (m),
## z = along the path (m). The camera follows behind and above Kyra.

signal finished
signal show_dialog(id: String)
## n-th group of sun pieces is complete (1, 2): Main runs a minigame, then
## after_minigame() continues with the next stage.
signal sun_game(n: int)

## The level editor's id of the map (Game.LEVELS).
const LEVEL_ID := 4
## Kept at the top of the map file (the level editor writes it back).
const MAP_HEADER := """# Forest run (level 2), a top-down map: the bottom row is the start, she runs up the file.
# Columns: left side | left path | middle path | right path | right side. One row = 2 m.
# R root (jump)  H branch (high: change path or double jump)  V flying notification  D water drop  U drop up high
# Y light seed  + sun piece (12 = the sun; every 4 a minigame, the 12th leads to the summit)
# < > side trap from the left / right side   A next stage starts here (faster; stage 3: random side traps)
# a-z dialog of level 2 (c = dialog 2C, Developer mode > Dialogs)
"""
const COLS := 5
const ROW_M := 2.0
## The first row lies this far ahead of the start.
const START_Z := 8.0
## Base speed per stage (m/s); within a stage it grows by STAGE_RAMP.
const STAGE_SPEED := [9.0, 11.5, 14.0]
const STAGE_RAMP := 1.5
const RANDOM_TRAPS_FROM := 2
const SUN_TOTAL := 12
const SUN_PER_GAME := 4
## Side traps (thorny vines): they lash into the outer path when she is this near.
const VINE_REACH := 12.0
const VINE_H := 0.7

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

## Course: [{kind, z, lane (or -9 = all), y, hit / taken, stage}]
var objects: Array = []
## The map (rows of COLS chars, the last row = the start); empty = the game's.
var rows := PackedStringArray()
## Length of the course (m), from the map.
var length := 0.0
## [{start, end}] in metres, in order.
var stages: Array = []
var stage := 0
## Sun pieces found (0–12).
var sun := 0
var sun_flash := 0.0
## Waiting for a minigame (after every SUN_PER_GAME pieces).
var waiting := false
var loops := 0
var _loop_told := false
var trees: Array = []
var _font: Font
var _prev_slow := false
## Lane / jump presses made while she is bumped or carried, applied after.
var _pending_lane := 0
var _pending_jump := false
## Obstacles closer than this to where a roll-back lands stay disarmed.
const GRACE := 5.0


func _ready() -> void:
	_font = Text.font_bold
	water = Game.water if Game.water > 0 else 30.0
	seeds = Game.seeds
	build_course()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var z := 0.0
	while z < length + VIEW:
		for side: float in [-1.0, 1.0]:
			trees.append({"x": side * rng.randf_range(4.2, 9.0), "z": z + rng.randf_range(0, 3), "h": rng.randf_range(4.5, 8.0), "r": rng.randf_range(1.2, 2.2), "tone": rng.randf()})
		z += rng.randf_range(2.5, 4.0)


## The course from the top-down map. Per cell:
##   R root (jump; RRR across the paths = one long root)   H branch (high)
##   V flying notification (flies at her)   D water drop   U water drop up high   Y light seed
##   + sun piece   < > side trap from the left / right side (any column)
##   A a new stage starts at this row   a–z dialog (c = 2C)
func build_course() -> void:
	objects.clear()
	if rows.is_empty():
		rows = Game.current_level_rows(LEVEL_ID)
	var n := rows.size()
	var starts := [0.0]
	for i in n:
		var row: String = rows[n - 1 - i]
		var z := START_Z + i * ROW_M
		var full_root := row.length() >= 4 and row[1] == "R" and row[2] == "R" and row[3] == "R"
		if full_root:
			_add("root", z, -9)
		for c in mini(row.length(), COLS):
			var ch := row[c]
			var l := c - 2
			var on_path := absi(l) <= 1
			var pl := clampi(l, -1, 1)
			match ch:
				"R":
					if on_path and not full_root:
						_add("root", z, l)
				"H":
					if on_path:
						_add("branch", z, l)
				"V":
					if on_path:
						_add("bird", z, l, 1.1)
				"D":
					_add("drop", z, pl, 0.45)
				"U":
					_add("drop", z, pl, BRANCH_H + 0.5)
				"Y":
					_add("seed", z, pl, 0.4)
				"+":
					_add("sun", z, pl, 0.5)
				"<":
					_add("vine", z, -1)
				">":
					_add("vine", z, 1)
				"A":
					if z > START_Z and not starts.has(z):
						starts.append(z)
				_:
					if ch >= "a" and ch <= "z":
						var id := Text.dialog_for_letter(ch, LEVEL_ID)
						if id != "":
							_add("dialog", z, 0)
							objects[objects.size() - 1]["id"] = id
	length = START_Z + n * ROW_M + 6.0
	starts.sort()
	stages = []
	for k in starts.size():
		stages.append({"start": starts[k], "end": starts[k + 1] if k + 1 < starts.size() else length})
	for o in objects:
		o["stage"] = stage_of(o.z)
	stage = clampi(stage, 0, stages.size() - 1)
	_random_traps(stage)


## Stage index of a point on the path.
func stage_of(z: float) -> int:
	var k := 0
	for i in stages.size():
		if z >= stages[i].start:
			k = i
	return k


## Late stages get side traps at random places (new ones on every repeat).
func _random_traps(k: int) -> void:
	objects = objects.filter(func(o): return not (o.get("random", false) and o.stage == k))
	if k < RANDOM_TRAPS_FROM or k >= stages.size():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + k * 7 + loops * 101
	var z: float = stages[k].start + 10.0
	while z < stages[k].end - 6.0:
		var clear := true
		for o in objects:
			if o.kind in ["root", "branch", "bird", "vine", "sun"] and absf(o.z - z) < 2.5:
				clear = false
				break
		if clear:
			_add("vine", z, -1 if rng.randf() < 0.5 else 1)
			var v: Dictionary = objects[objects.size() - 1]
			v["random"] = true
			v["stage"] = k
		z += rng.randf_range(9.0, 15.0)


func _add(kind: String, z: float, l: int, y := 0.0) -> void:
	objects.append({"kind": kind, "z": z, "lane": l, "y": y, "hit": false, "taken": false, "dz": 0.0, "stage": 0})


func _add_drops(z: float, l: int, n: int) -> void:
	for i in n:
		_add("drop", z + i * 1.6, l, 0.45)


# --- input & update ---------------------------------------------------------------------

## Lanes and jumps are read as "just pressed" each frame: a stick tilt (many
## motion events) then changes lane once, like a key press.
func _read_input() -> void:
	var d := 0
	if Input.is_action_just_pressed("move_left"):
		d = -1
	elif Input.is_action_just_pressed("move_right"):
		d = 1
	var j := Input.is_action_just_pressed("jump")
	if carry_t > 0 or bump_t > 0:
		# Remember what was pressed while she couldn't act.
		if d != 0:
			_pending_lane = d
		if j:
			_pending_jump = true
		return
	if _pending_lane != 0 and d == 0:
		d = _pending_lane
	if _pending_jump:
		j = true
	_pending_lane = 0
	_pending_jump = false
	if d != 0:
		lane = clampi(lane + d, -1, 1)
	if j:
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
	sun_flash = maxf(0, sun_flash - dt)
	if active and not dialog_open and not done and not waiting:
		_update(dt)
	queue_redraw()


func _update(dt: float) -> void:
	_read_input()
	# Slowed time: the world (and her fall) runs slower while her steering stays
	# quick, so a tight spot can be read and taken. Not while bumped / carried.
	var rolling := carry_t > 0 or bump_t > 0
	var want_slow := not rolling and Input.is_action_pressed("slow_time") and water > (0.0 if _prev_slow else SLOW_MIN)
	slow = want_slow
	_prev_slow = slow
	var wdt := dt * (SLOW_SCALE if slow else 1.0)
	if slow:
		water = maxf(0, water - SLOW_DRAIN * dt)
	# Moving sideways uses real time (the focus advantage).
	px = move_toward(px, lane * LANE, LANE_SPEED * dt)
	if carry_t > 0:
		carry_t -= dt
		dist = move_toward(dist, _roll_to, CARRY_BACK / 1.2 * dt)
		py = lerpf(py, 1.8, dt * 3)
		if carry_t <= 0:
			vy = 0
			jumps = 1
		return
	# Jumps follow the world's clock, so a jump clears the same obstacles with or
	# without slowed time.
	vy -= GRAVITY * wdt
	py += vy * wdt
	if py <= 0:
		py = 0
		vy = 0
		jumps = 2
	if bump_t > 0:
		bump_t -= dt
		dist = move_toward(dist, _roll_to, BUMP_BACK / 0.45 * dt)
		return
	var base: float = STAGE_SPEED[mini(stage, STAGE_SPEED.size() - 1)]
	speed = base + STAGE_RAMP * stage_progress()
	dist += speed * wdt
	_hits(wdt)
	if done or waiting or stages.is_empty():
		return
	if dist >= stages[stage].end:
		_stage_end()


## The end of a stage: repeat it while its sun pieces are missing, else go on.
func _stage_end() -> void:
	var need := mini(SUN_TOTAL, (stage + 1) * SUN_PER_GAME)
	var left := objects.any(func(o): return o.kind == "sun" and not o.taken and o.stage == stage)
	if sun < need and left:
		_loop_stage()
	elif stage >= stages.size() - 1:
		_finish()
	else:
		stage += 1
		_random_traps(stage)


## Back to the start of the stage: the forest goes round again. Obstacles and
## water come back; found seeds and sun pieces stay found.
func _loop_stage() -> void:
	loops += 1
	dist = stages[stage].start
	for o in objects:
		if o.stage != stage:
			continue
		if o.kind in ["root", "branch", "bird", "vine"]:
			o.hit = false
			o.dz = 0.0
		elif o.kind == "drop":
			o.taken = false
	_random_traps(stage)
	flash = 0.0
	sun_flash = 0.0
	if not _loop_told:
		_loop_told = true
		show_dialog.emit("2D")


## After the minigame: on with the next stage (from its start).
func after_minigame() -> void:
	waiting = false
	# The stage whose quota is next (an edited map may hold more or fewer than
	# 4 pieces per stage): never back, never past the last one.
	var target := mini(sun / SUN_PER_GAME, stages.size() - 1)
	if target > stage:
		jump_to(stages[target].start)
	py = 0
	vy = 0
	jumps = 2
	bump_t = 0
	carry_t = 0


func _finish() -> void:
	if done:
		return
	done = true
	finished.emit()


func _hits(wdt: float) -> void:
	for o in objects:
		if o.taken or o.hit:
			continue
		if o.kind == "dialog":
			if dist >= o.z:
				o.taken = true
				show_dialog.emit(o.id)
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
			"vine":
				if py < VINE_H:
					o.hit = true
					bump()
			"sun":
				if absf(py - o.y) < 0.9:
					o.taken = true
					_sun_piece()


## A sun piece: one more slice of the sun. Every SUN_PER_GAME a minigame, the
## last one ends the level.
func _sun_piece() -> void:
	sun += 1
	sun_flash = 1.0
	Audio.play_sfx("finished.wav", 0.6)
	if sun >= SUN_TOTAL:
		_finish()
	elif sun % SUN_PER_GAME == 0:
		waiting = true
		sun_game.emit(sun / SUN_PER_GAME)


## Ran into a root or a branch: bounce back, the path rolls back a bit.
func bump() -> void:
	bump_t = 0.45
	_roll_to = maxf(_stage_start(), dist - BUMP_BACK)
	vy = 3.0
	flash = 0.4
	Audio.play_sfx("au%d.wav" % (1 + int(time * 13) % 5), 0.6)
	_reset_behind()


## Caught by a bird in the air: carried back along the path.
func carried() -> void:
	carry_t = 1.2
	_roll_to = maxf(_stage_start(), dist - CARRY_BACK)
	flash = 0.3
	Audio.play_sfx("au%d.wav" % (1 + int(time * 7) % 5), 0.7)
	_reset_behind()


## Obstacles she now has to pass again are armed again — except the ones right
## where she lands (no hit straight after a roll-back). Birds go back to where
## they started and fly at her again.
func _reset_behind() -> void:
	for o in objects:
		if not o.kind in ["root", "branch", "bird", "vine"]:
			continue
		var here: float = o.z + o.dz
		var passed: bool = here <= dist + 1 or o.hit
		if not passed or o.z < _roll_to - 1:
			continue
		if o.z < _roll_to + GRACE:
			o.hit = true
		else:
			o.hit = false
			o.dz = 0.0


func progress() -> float:
	return clampf(dist / maxf(1.0, length), 0, 1)


## How far through the current stage (0–1).
func stage_progress() -> float:
	if stages.is_empty():
		return 0.0
	var s: Dictionary = stages[stage]
	return clampf((dist - s.start) / maxf(1.0, s.end - s.start), 0, 1)


## Puts her at `z` (developer shortcuts, tests): the stage follows.
func jump_to(z: float) -> void:
	var was := stage
	stage = stage_of(z)
	dist = z
	if stage != was:
		_random_traps(stage)
	# Dialogs she skipped over stay unsaid.
	for o in objects:
		if o.kind == "dialog" and o.z <= z:
			o.taken = true
	bump_t = 0
	carry_t = 0


func _stage_start() -> float:
	return stages[stage].start if not stages.is_empty() else 0.0


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
		if oz > dist - CAM_BACK + 0.5 and oz < dist + VIEW and not o.taken and o.kind != "dialog":
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
			"sun": _draw_sun_piece(it[2])
			"vine": _draw_vine(it[2])
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
	# Across all paths (lane -9) or one path.
	var x0: float = -LANE * 1.8 if o.lane == -9 else (o.lane - 0.55) * LANE
	var x1: float = LANE * 1.8 if o.lane == -9 else (o.lane + 0.55) * LANE
	var a := project(x0, 0, z)
	var b := project(x1, 0, z)
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
	for i in (3 if o.lane == -9 else 1):
		var k := 0.25 + i * 0.25 if o.lane == -9 else 0.5
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
	var col := _fog(Color("#f1f5f9"), z)
	# The lab's frames, or the placeholder: an envelope with wings and a red "!".
	if not SpriteArt.draw(self, "bird", Vector2(c.x, c.y), s * 1.5, time * 1000.0 + o.z * 37.0, _fog(Color.WHITE, z)):
		SpriteArt.draw_bird(self, Vector2(c.x, c.y), s, flap, col)
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
	if SpriteArt.draw(self, "drop", Vector2(c.x, c.y), s * 2.9, time * 1000.0 + o.z * 37.0, _fog(Color.WHITE, o.z)):
		return
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
	if SpriteArt.draw(self, "seed", Vector2(c.x, c.y), s * 3.3, time * 1000.0 + o.z * 37.0):
		return
	Draw.radial_glow(self, Vector2(c.x, c.y), s * 3, Color(1, 0.85, 0.4, 0.5), Color(1, 0.98, 0.8, 0.95))
	draw_circle(Vector2(c.x, c.y), s * 0.6, Color("#fff4c2"))


## A sun piece: a golden triangular slice, turning slowly, with a glow.
func _draw_sun_piece(o: Dictionary) -> void:
	var c := project(_lane_x(o), o.y + sin(time * 3 + o.z) * 0.08, o.z)
	if c.z <= 0:
		return
	var s := 0.3 * c.z
	var p := Vector2(c.x, c.y)
	if SpriteArt.draw(self, "sun_piece", p, s * 2.6, time * 1000.0 + o.z * 37.0):
		return
	Draw.radial_glow(self, p, s * 2.6, Color(1, 0.8, 0.3, 0.55), Color(1, 0.95, 0.7, 0.9))
	SpriteArt.draw_sun_piece(self, p, s, cos(time * 2.2 + o.z))


## A side trap: a thorny vine that lashes in from the side into the outer path.
func _draw_vine(o: Dictionary) -> void:
	var z: float = o.z
	var rz := z - dist
	var e := clampf((VINE_REACH - rz) / (VINE_REACH - 4.0), 0, 1)
	var side: float = o.lane * LANE * 2.7
	var tip: float = lerpf(side, o.lane * LANE * 0.45, e)
	var col := _fog(Color("#2f6b2f"), z)
	var pts := PackedVector2Array()
	var width := 1.0
	for i in 9:
		var k := i / 8.0
		var x := lerpf(side, tip, k)
		var y := 0.35 + sin(k * PI) * 0.25 * e + sin(time * 6 + k * 5) * 0.04
		var q := project(x, y, z)
		if q.z <= 0:
			return
		pts.append(Vector2(q.x, q.y))
		width = q.z
	if not SpriteArt.draw(self, "vine", pts[pts.size() / 2], 0.6 * width, time * 1000.0, _fog(Color.WHITE, z), o.lane < 0):
		SpriteArt.draw_vine(self, pts, maxf(2, 0.12 * width), col)
	# Its shadow on the path.
	if e > 0.6:
		var g := project(o.lane * LANE, 0, z)
		draw_set_transform(Vector2(g.x, g.y), 0, Vector2(1, 0.25))
		draw_circle(Vector2.ZERO, 0.5 * g.z, Color(0, 0, 0, 0.15 * e))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


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
		# The flying notification holding her.
		var bp := Vector2(c.x, c.y - 165 * k)
		var flap := sin(time * 16) * 0.8
		var s := 40 * k
		if not SpriteArt.draw(self, "bird", bp, s * 1.5, time * 1000.0):
			SpriteArt.draw_bird(self, bp, s, flap)


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
	# The sun: 12 slices, one per piece found; a ring shows the way through the stage.
	var sc := Vector2(W / 2, 62)
	draw_arc(sc, 56, -PI / 2, -PI / 2 + TAU * stage_progress(), 48, Color(1, 1, 1, 0.75), 3.0, true)
	SpriteArt.draw_sun(self, sc, 46, sun, sun_flash, time)
	# Water = focus bar.
	var v := Rect2(W / 2 - 170, H - 44, 340, 28)
	Draw.panel(self, v, bg, 14, Color(0.37, 0.61, 0.6, 0.2), 2)
	var inner := Rect2(v.position.x + 6, v.position.y + 6, v.size.x - 12, v.size.y - 12)
	Draw.panel(self, inner, Color("#dbeafe"), 8)
	if water > 0.5:
		Draw.panel(self, Rect2(inner.position, Vector2(inner.size.x * water / 100.0, inner.size.y)), Color("#5fb3f0") if not slow else Color("#93c5fd"), 8)
	var hint := Text.plain(Text.t("RUNNER_SLOW_HINT"))
	Draw.text_center(self, Text.font, Vector2(v.get_center().x, v.position.y - 10), hint, 12, Color(1, 1, 1, 0.95))
