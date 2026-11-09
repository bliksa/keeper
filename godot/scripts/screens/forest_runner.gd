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
##  * Four lanes; ← → change lane, jump / double jump over roots (low, all lanes)
##    and branches (higher, one or two lanes). Hitting one bounces her back and
##    the path rolls back a bit.
##  * Flying notifications (envelopes with wings, kind "bird") fly at her at jump
##    height: one that meets her in the air carries her back along the path.
##  * Water drops fill the focus bar; holding Slow (Shift / E / LB) slows time
##    while it drains, so a tight cluster of obstacles can be read and jumped.
## Coordinates: x = sideways (m, lane centres -LANE..LANE), y = up (m),
## z = along the path (m). The camera follows behind and above Kyra.

signal finished
signal show_dialog(id: String)
## n-th group of sun pieces is complete (1, 2): Main runs a minigame, then
## after_minigame() continues with the next stage.
signal sun_game(n: int)
## The level-start sequence is over (Main then shows dialog 2A).
signal intro_done

## Coming from the cave: Kyra fell out of the arena (its floor became the grain);
## the forest fades in over it, she drops in from above onto the path and stands
## with her back to us, the grain flies to the top-left and becomes the sun (the
## progress meter), and the trees appear from the middle around her.
const INTRO_TIME := 3.0
const INTRO_FADE := 1.0
const INTRO_GRAIN := [0.35, 1.55]
const INTRO_TREES := 1.0
## She keeps falling from the cave: in from above, onto the path.
const INTRO_FALL_AT := 0.45
const INTRO_FROM_Y := 10.0
## Her size at the top of that fall (she grows to 1 as she comes down).
const INTRO_FALL_SCALE := 0.5
const INTRO_FALL_V := -4.0
## Over the arena: when the arena goes she is taken over where she was on
## screen (handoff) and goes on falling onto the path in this time (s).
const HANDOFF_FALL := 0.55
## Where the grain is in the arena (Platformer._draw_egg) and its size there.
const GRAIN_FROM := Vector2(533, 250)
const GRAIN_R := 45.0

## The level editor's id of the map (Game.LEVELS).
const LEVEL_ID := 4
## Kept at the top of the map file (the level editor writes it back).
const MAP_HEADER := """# Forest run (level 2), a top-down map: the bottom row is the start, she runs up the file.
# Columns: left side | four paths | right side. One row = 2 m.
# R root (jump; RRRR = across all paths)  H branch (high: change path or double jump)  V flying notification  D water drop  U drop up high
# + sun piece (12 = the sun; every 3 a minigame, the 12th leads to the summit)
# < > side trap from the left / right side   A next stage starts here (faster; stage 4: random side traps)
# a-z dialog of level 2 (c = dialog 2C, Developer mode > Dialogs)
"""
const COLS := 6
## Four paths: their centres are at PATHS[i] * LANE (between the paths the middle).
const PATHS := [-1.5, -0.5, 0.5, 1.5]
## Water a jump costs (a double jump more).
const ROW_M := 2.0
## The first row lies this far ahead of the start.
const START_Z := 8.0
## Base speed per stage (m/s); within a stage it grows by STAGE_RAMP.
const STAGE_SPEED := [9.0, 11.0, 12.5, 14.5]
const STAGE_RAMP := 1.5
const RANDOM_TRAPS_FROM := 3
const SUN_TOTAL := 12
const SUN_PER_GAME := 3
## Side traps (thorny vines): they lash into the outer path when she is this near.
const VINE_REACH := 12.0
const VINE_H := 0.7
## HUD: the sun (top-left) and the water pill (top-right).
const SUN_HUD := Vector2(66, 66)
const WATER_HUD := Rect2(W - 16 - 150, 16, 150, 48)

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
## Water: a magazine of DROPS_MAX drops (the HUD shows them) fed by the bar
## below it (`water`, 0–100, filled by the drops on the path). A double jump
## costs DOUBLE_DROPS, focus burns FOCUS_DRAIN drops a second, a hit HIT_DROPS.
## When the magazine is empty it reloads from the bar (DROP_UNIT of the bar per
## drop), which takes RELOAD_TIME.
const DROPS_MAX := 4.0
const DOUBLE_DROPS := 2.0
const FOCUS_DRAIN := 1.0
const HIT_DROPS := 1.0
const DROP_UNIT := 25.0
const RELOAD_TIME := 2.0
const DROP_WATER := 5.0
## Water (focus) a hit on an obstacle costs.
const BUMP_BACK := 6.0
const CARRY_BACK := 14.0
const VIEW := 70.0
const ROOT_H := 0.5
const BRANCH_H := 1.05
## Height above which a bird catches her (in the air, in its lane).
const BIRD_REACH := 1.0
## How high the flying notifications fly (m): over her head, dodge them sideways.
const BIRD_Y := 1.7
const BIRD_SPEED := 6.0

## Updated by Main.
var active := false
var dialog_open := false

## Progress along the path (m); the speed grows with it.
var dist := 0.0
var speed := SPEED
var lane := -0.5
var px := -0.5 * 1.7
var py := 0.0
var vy := 0.0
var jumps := 2
var slow := false
var water := 30.0
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
## Slices drawn in the sun: a found piece flies up first, then fills its slice.
var sun_shown := 0
var sun_pulse := 0.0
var water_flash := 0.0
## Too little water for a jump: the pill shakes red for a moment.
var water_short := 0.0
## Which mark the missing water was for ("jump", "focus", "double"): it blinks.
var short_for := ""
## The magazine (0–DROPS_MAX) and the reload in progress (s left; the drops
## it is filling to).
var drops := DROPS_MAX
var reload_t := 0.0
var _reload_to := 0.0
## Seconds left of the blinking after a hit (nothing hits her meanwhile).
var invuln := 0.0
## A slice lost in a hit: its place in the sun blinks red (s left).
var sun_lost := 0.0
const LOST_TIME := 1.4
const LOST_FLY := 0.9
## Lost slices tumbling out of her: [{from: Vector2, t}].
var lost_flyers: Array = []
## A repeat of the stage queued behind what she can see: where it begins (the
## old stage end; -1 = none) and how far its copy lies ahead.
var _loop_cross := -1.0
var _loop_shift := 0.0
## Pickups flying to their indicator: [{kind: "sun" / "drop", from: Vector2, t}].
var flyers: Array = []
## Seconds left of the level-start sequence (0 = playing).
var intro := 0.0
## Landing squash after the drop (s left).
var land_t := 0.0
var _landed := false
var _jumped := false
var _told := false
## The last frame of the cave (crossfaded away), or null.
var _from_cave: Texture2D
## Drawn over the arena (Main fades this screen in): the grain starts where it is there.
var _over_cave := false
## The handoff from the arena: when (intro time), her feet on screen, her height (px).
var _handoff_at := -1.0
var _handoff_from := Vector2.ZERO
var _handoff_h := 0.0
## A minigame (n) or the end waiting for the flying piece to land.
var _pending_game := 0
var _pending_end := false
const FLY_TIME := 0.65
## Waiting for a minigame (after every SUN_PER_GAME pieces).
var waiting := false
var loops := 0
## Seconds left of standing / speeding up again after a hit (see RECOVER_*).
var recover_t := 0.0
## Seconds left of the controls line (show_controls).
var loop_note := 0.0
## How long the controls line shows at the start (s); set by show_controls().
const CONTROLS_TIME := 6.0
var trees: Array = []
var _tree_rng := RandomNumberGenerator.new()
var _tree_z := 0.0
var _font: Font
var _prev_slow := false
## The abilities usable right now, under the water pill (AbilityHints).
var hints := AbilityHints.new()
## Lane / jump presses made while she is bumped or carried, applied after.
var _pending_lane := 0
var _pending_jump := false
## Obstacles closer than this to where a roll-back lands stay disarmed.
const GRACE := 5.0
## After a hit she blinks and nothing can hit her for this long (s).
const INVULN_TIME := 3.0
## After a hit or a carry: standing still, then speeding up again (s).
const RECOVER_STAND := 0.5
const RECOVER_RAMP := 0.7


func _ready() -> void:
	_font = Text.font_bold
	water = Game.water if Game.water > 0 else 40.0
	build_course()
	_tree_rng.seed = 7
	_extend_trees()


## Trees along both sides of the path up to the end of the course (grows when a
## stage repeats further on).
func _extend_trees() -> void:
	while _tree_z < length + VIEW:
		for side: float in [-1.0, 1.0]:
			trees.append({"x": side * _tree_rng.randf_range(5.0, 10.0), "z": _tree_z + _tree_rng.randf_range(0, 3), "h": _tree_rng.randf_range(4.5, 8.0), "r": _tree_rng.randf_range(1.2, 2.2), "tone": _tree_rng.randf()})
		_tree_z += _tree_rng.randf_range(2.5, 4.0)


## The course from the top-down map. Per cell:
##   R root (jump; RRR across the paths = one long root)   H branch (high)
##   V flying notification (flies at her)   D water drop   U water drop up high
##   + sun piece   < > side trap from the left / right side (any column)
##   A a new stage starts at this row   a–z dialog (c = 2C)
func build_course() -> void:
	objects.clear()
	loops = 0
	_loop_cross = -1.0
	if rows.is_empty():
		rows = Game.current_level_rows(LEVEL_ID)
	var n := rows.size()
	var starts := [0.0]
	for i in n:
		var row: String = rows[n - 1 - i]
		var z := START_Z + i * ROW_M
		var full_root := row.length() >= 5 and row[1] == "R" and row[2] == "R" and row[3] == "R" and row[4] == "R"
		if full_root:
			_add("root", z, -9)
		for c in mini(row.length(), COLS):
			var ch := row[c]
			# Columns: 0 left side, 1–4 the paths, 5 right side.
			var on_path := c >= 1 and c <= 4
			var l: float = PATHS[clampi(c - 1, 0, 3)]
			var pl := l
			match ch:
				"R":
					if on_path and not full_root:
						_add("root", z, l)
				"H":
					if on_path:
						_add("branch", z, l)
				"V":
					if on_path:
						_add("bird", z, l, BIRD_Y)
				"D":
					_add("drop", z, pl, 0.45)
				"U":
					_add("drop", z, pl, BRANCH_H + 0.5)
				"+":
					_add("sun", z, pl, 0.5)
				"<":
					_add("vine", z, PATHS[0])
				">":
					_add("vine", z, PATHS[3])
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
func _random_traps(k: int, from_z := -INF) -> void:
	objects = objects.filter(func(o): return not (o.get("random", false) and o.stage == k and o.z >= from_z))
	if k < RANDOM_TRAPS_FROM or k >= stages.size():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + k * 7 + loops * 101
	var z: float = maxf(stages[k].start, from_z) + 10.0
	while z < stages[k].end - 6.0:
		var clear := true
		for o in objects:
			if o.kind in ["root", "branch", "bird", "vine", "sun"] and absf(o.z - z) < 2.5:
				clear = false
				break
		if clear:
			_add("vine", z, PATHS[0] if rng.randf() < 0.5 else PATHS[3])
			var v: Dictionary = objects[objects.size() - 1]
			v["random"] = true
			v["stage"] = k
		z += rng.randf_range(9.0, 15.0)


func _add(kind: String, z: float, l: float, y := 0.0) -> void:
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
		lane = clampf(lane + d, PATHS[0], PATHS[PATHS.size() - 1])
	if j:
		jump()


func jump() -> void:
	if jumps <= 0 or bump_t > 0 or carry_t > 0:
		return
	# A jump is free; a double jump costs two drops from the magazine.
	# (some places can't be passed dry).
	if jumps == 1:
		if drops < DOUBLE_DROPS - 0.001:
			water_short = 0.5
			short_for = "double"
			return
		drops -= DOUBLE_DROPS
	vy = JUMP_V if jumps == 2 else DOUBLE_V
	jumps -= 1
	Audio.jump_sound(jumps == 0)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	time += dt
	flash = maxf(0, flash - dt)
	sun_flash = maxf(0, sun_flash - dt)
	sun_pulse = maxf(0, sun_pulse - dt)
	water_flash = maxf(0, water_flash - dt)
	water_short = maxf(0, water_short - dt)
	sun_lost = maxf(0, sun_lost - dt)
	invuln = maxf(0, invuln - dt)
	for f in lost_flyers.duplicate():
		f.t += dt / LOST_FLY
		if f.t >= 1.0:
			lost_flyers.erase(f)
	if not dialog_open and intro <= 0:
		loop_note = maxf(0, loop_note - dt)
	_update_flyers(dt)
	land_t = maxf(0, land_t - dt)
	hints.update(dt, _wanted_hints())
	if intro > 0:
		_update_intro(dt)
		queue_redraw()
		return
	if active and not dialog_open and not done and not waiting:
		_update(dt)
	queue_redraw()


## Focus while a drop is in the magazine (and it isn't reloading), the double jump
## while two are.
func _wanted_hints() -> Array:
	if intro > 0 or not active or dialog_open or done or waiting:
		return []
	var out: Array = []
	if (drops >= 1.0 or slow) and reload_t <= 0:
		out.append("HINT_RUN_FOCUS")
	if drops >= DOUBLE_DROPS - 0.001:
		out.append("HINT_RUN_DOUBLE")
	return out


## The keys of the ability hints shown right now.
func hint_lines() -> Array:
	return hints.active()


func _update(dt: float) -> void:
	_read_input()
	# Slowed time: the world (and her fall) runs slower while her steering stays
	# quick, so a tight spot can be read and taken. Not while bumped / carried.
	var rolling := carry_t > 0 or bump_t > 0
	var pressing := Input.is_action_pressed("slow_time")
	var want_slow := not rolling and pressing and drops > 0.001 and reload_t <= 0
	if pressing and not want_slow and not _prev_slow and not rolling and Input.is_action_just_pressed("slow_time"):
		water_short = 0.5
		short_for = "focus"
	_update_magazine(dt)
	slow = want_slow
	_prev_slow = slow
	var wdt := dt * (SLOW_SCALE if slow else 1.0)
	if slow:
		drops = maxf(0, drops - FOCUS_DRAIN * dt)
	# Moving sideways uses real time (the focus advantage).
	px = move_toward(px, lane * LANE, LANE_SPEED * dt)
	if carry_t > 0:
		carry_t -= dt
		dist = move_toward(dist, _roll_to, CARRY_BACK / 1.2 * dt)
		py = lerpf(py, 2.2, dt * 3)
		if carry_t <= 0:
			vy = 0
			jumps = 1
			recover_t = RECOVER_STAND + RECOVER_RAMP
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
		if bump_t <= 0:
			recover_t = RECOVER_STAND + RECOVER_RAMP
		return
	var base: float = STAGE_SPEED[mini(stage, STAGE_SPEED.size() - 1)]
	speed = base + STAGE_RAMP * stage_progress()
	if recover_t > 0:
		# After a hit: she stands a moment, then picks up speed again.
		recover_t = maxf(0, recover_t - dt)
		speed *= recover_k()
	dist += speed * wdt
	_hits(wdt)
	if done or waiting or stages.is_empty():
		return
	_check_loop()
	if _loop_cross >= 0 and dist >= _loop_cross:
		_enter_loop()
	if dist >= stages[stage].end:
		_stage_end()


## The end of a stage: repeat it while its sun pieces are missing, else go on.
func _stage_end() -> void:
	var need := mini(SUN_TOTAL, (stage + 1) * SUN_PER_GAME)
	var left := objects.any(func(o): return o.kind == "sun" and not o.taken and o.stage == stage)
	if sun < need and left:
		if _loop_cross < 0:
			_loop_stage()
	elif stage >= stages.size() - 1:
		_finish()
	else:
		stage += 1
		_random_traps(stage)


## Whether this stage must come round again: even with every piece still
## ahead of her taken, its quota would not be met.
func _loop_needed() -> bool:
	var need := mini(SUN_TOTAL, (stage + 1) * SUN_PER_GAME)
	var ahead := 0
	var missing := false
	for o in objects:
		if o.kind == "sun" and o.stage == stage and not o.taken:
			missing = true
			if o.z > dist:
				ahead += 1
	return missing and sun + ahead < need


## As the stage's end comes into view, a repeat it will need is queued at once,
## so it lies behind what she can see (see _loop_stage).
func _check_loop() -> void:
	if _loop_cross >= 0 or dist < stages[stage].end - VIEW - 1.0:
		return
	if _loop_needed():
		_loop_stage()


## The stage comes round again, seamless and with no message: a copy of it is
## laid out right behind what she can see in the distance, nothing in view moves
## or vanishes. What already shows of the next stage (`bridge`) she runs through
## first; it goes on again (copied) after the repeat, with everything later.
## Obstacles and water come back; found sun pieces stay found, missing ones move
## into the copy once she is past them (_enter_loop).
func _loop_stage() -> void:
	loops += 1
	var s: Dictionary = stages[stage]
	var old_end: float = s.end
	var span: float = s.end - s.start
	var at := maxf(old_end, dist + VIEW)
	var shift := span + (at - old_end)
	var copies: Array = []
	for o in objects:
		var z: float = o.z
		if z < old_end:
			if o.stage == stage and z >= s.start and o.kind in ["root", "branch", "bird", "vine", "drop"] and not o.get("random", false) and not o.get("bridge", false):
				var c: Dictionary = o.duplicate()
				c.z = z + shift
				c.hit = false
				c.dz = 0.0
				c.taken = false
				copies.append(c)
		elif z < at and o.kind in ["root", "branch", "bird", "vine", "drop"]:
			# In view already: it stays where it is (part of the run-up to the
			# repeat, never copied into a later repeat); the next stage gets its
			# own copy further on. (Sun pieces and dialogs go on with their stage.)
			var c2: Dictionary = o.duplicate()
			c2.z = z + shift
			c2.hit = false
			c2.dz = 0.0
			c2.taken = false
			copies.append(c2)
			o.stage = stage
			o["bridge"] = true
		else:
			o.z = z + shift
	objects.append_array(copies)
	for k in range(stage + 1, stages.size()):
		stages[k].start += shift
		stages[k].end += shift
	s.end = old_end + shift
	length += shift
	_loop_cross = old_end
	_loop_shift = shift
	_extend_trees()
	_random_traps(stage, at)


## She has passed the old end: the stage now runs from here (the run-up, then
## the repeat). The pieces she missed move into the repeat; what lies behind is
## dropped (a roll-back never goes before the stage start).
func _enter_loop() -> void:
	var s: Dictionary = stages[stage]
	# Found ones too: a slice lost later puts its piece back into the repeat.
	for o in objects:
		if o.kind == "sun" and o.stage == stage and o.z < _loop_cross:
			o.z += _loop_shift
	s.start = _loop_cross
	_loop_cross = -1.0
	var keep_from: float = s.start - CAM_BACK - 2.0
	objects = objects.filter(func(o): return o.kind in ["sun", "dialog"] or o.z >= keep_from)


## After the minigame: on with the next stage (from its start).
func after_minigame() -> void:
	waiting = false
	# The stage whose quota is next (an edited map may hold more or fewer than
	# 3 pieces per stage): never back, never past the last one.
	var target := mini(sun / SUN_PER_GAME, stages.size() - 1)
	if target > stage:
		jump_to(stages[target].start)
	py = 0
	vy = 0
	jumps = 2
	bump_t = 0
	carry_t = 0
	recover_t = 0


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
		if invuln > 0 and o.kind in ["root", "branch", "bird", "vine"]:
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
					_add_water(DROP_WATER)
					_fly("drop", o)
					Audio.play_sfx("cink-%02d.wav" % (1 + int(time * 7) % 11), 0.35)
			"vine":
				if py < VINE_H:
					o.hit = true
					bump()
			"sun":
				if absf(py - o.y) < 0.9:
					o.taken = true
					_fly("sun", o)
					_sun_piece()


## Water from a drop on the path: into the bar under the magazine.
func _add_water(n: float) -> void:
	water = minf(100, water + n)


## The magazine reloads from the bar once it is empty (drop by drop, RELOAD_TIME).
func _update_magazine(dt: float) -> void:
	if reload_t <= 0 and drops <= 0.001 and water >= 1.0:
		reload_t = RELOAD_TIME
		_reload_to = minf(DROPS_MAX, water / DROP_UNIT)
	if reload_t > 0:
		var add := minf(_reload_to / RELOAD_TIME * dt, maxf(0, _reload_to - drops))
		add = minf(add, water / DROP_UNIT)
		drops += add
		water = maxf(0, water - add * DROP_UNIT)
		reload_t = maxf(0, reload_t - dt)
		if reload_t <= 0:
			drops = minf(DROPS_MAX, drops)


## A sun piece: one more slice of the sun. Every SUN_PER_GAME a minigame, the
## last one ends the level.
func _sun_piece() -> void:
	sun += 1
	sun_flash = 1.0
	Audio.play_sfx("finished.wav", 0.6)
	# The world waits while the piece flies up; the minigame / the end follows
	# once it has filled its slice.
	if sun >= SUN_TOTAL:
		waiting = true
		_pending_end = true
	elif sun % SUN_PER_GAME == 0:
		waiting = true
		_pending_game = sun / SUN_PER_GAME
	if flyers.is_empty():
		_land_pending()


func show_controls() -> void:
	loop_note = CONTROLS_TIME


## Starts the level-start sequence (see INTRO_TIME).
func start_intro(from_cave: Texture2D = null, over_cave := false) -> void:
	_from_cave = from_cave
	_over_cave = over_cave
	_handoff_at = -1.0
	intro = INTRO_TIME
	py = INTRO_FROM_Y
	vy = 0.0
	_landed = false
	_jumped = false
	_told = false


func intro_elapsed() -> float:
	return INTRO_TIME - intro if intro > 0 else INTRO_TIME


## The arena is gone: she goes on from where she was on its screen.
func handoff(feet: Vector2, height: float) -> void:
	if _handoff_at >= 0:
		return
	_handoff_at = intro_elapsed()
	_handoff_from = feet
	_handoff_h = height


func _land() -> void:
	py = 0
	vy = 0
	_landed = true
	land_t = 0.35
	flash = 0.0
	Audio.footstep(0.9)


func _update_intro(dt: float) -> void:
	intro = maxf(0, intro - dt)
	if _over_cave and not _landed:
		# Falling on from the arena (see handoff): onto the path, growing.
		py = 0
		vy = 0
		if _handoff_at < 0 and intro_elapsed() >= INTRO_FADE + 0.1:
			handoff(Vector2(W / 2, H * 0.5), 90.0)
		if _handoff_at >= 0 and intro_elapsed() - _handoff_at >= HANDOFF_FALL:
			_land()
	elif intro_elapsed() >= INTRO_FALL_AT and not _landed:
		if not _jumped:
			_jumped = true
			vy = INTRO_FALL_V
		vy -= GRAVITY * dt
		py += vy * dt
		if py <= 0 and vy < 0:
			py = 0
			vy = 0
			_landed = true
			land_t = 0.35
			flash = 0.0
			Audio.footstep(0.9)
	if intro <= 0:
		py = 0
		vy = 0
		_landed = true
		if not _told:
			_told = true
			intro_done.emit()


## Growth of a tree during the intro (0 in the middle of the screen, 1 in place):
## the far ones arrive first.
func _intro_k(z: float) -> float:
	if intro <= 0:
		return 1.0
	var far := clampf((z - dist) / VIEW, 0, 1)
	var t := clampf((intro_elapsed() - INTRO_TREES - 0.55 * (1.0 - far)) / 0.85, 0, 1)
	return 1.0 - pow(1.0 - t, 3)


## A pickup flies from where it was to its indicator (sun top-left, water top-right).
func _fly(kind: String, o: Dictionary) -> void:
	var c := project(_lane_x(o), o.y, o.z)
	var from := Vector2(c.x, c.y) if c.z > 0 else Vector2(W / 2, H / 2)
	flyers.append({"kind": kind, "from": from, "t": 0.0})


## Where a flyer lands.
func fly_target(kind: String) -> Vector2:
	return SUN_HUD if kind == "sun" else Vector2(WATER_HUD.position.x + 26, WATER_HUD.get_center().y)


func _update_flyers(dt: float) -> void:
	for f in flyers.duplicate():
		f.t += dt / FLY_TIME
		if f.t >= 1.0:
			flyers.erase(f)
			if f.kind == "sun":
				sun_shown = mini(sun_shown + 1, sun)
				sun_flash = 1.0
				sun_pulse = 0.45
				Audio.play_sfx("finished.wav", 0.35)
			else:
				water_flash = 0.45
	if not flyers.any(func(f): return f.kind == "sun"):
		sun_shown = sun
		_land_pending()


func _land_pending() -> void:
	if _pending_end:
		_pending_end = false
		if waiting:
			waiting = false
			_finish()
	elif _pending_game > 0:
		var n := _pending_game
		_pending_game = 0
		# after_minigame() may already have run (tests): then nothing waits for it.
		if waiting:
			sun_game.emit(n)


## A hit costs a slice of the sun: the last piece found in this stage goes back
## onto the track (the stage comes round again until it is found). Never below
## the minigames already played (every SUN_PER_GAME).
func _lose_slice() -> void:
	var floor_n := (sun - 1) / SUN_PER_GAME * SUN_PER_GAME if sun % SUN_PER_GAME != 0 else sun
	if sun <= floor_n or sun <= 0:
		return
	var last: Dictionary = {}
	for o in objects:
		if o.kind == "sun" and o.taken and o.stage == stage and (last.is_empty() or o.z > last.z):
			last = o
	if last.is_empty():
		return
	last.taken = false
	# A piece still flying up never lands: it is the one that falls out.
	for i in range(flyers.size() - 1, -1, -1):
		if flyers[i].kind == "sun":
			flyers.remove_at(i)
			break
	sun -= 1
	sun_shown = mini(sun_shown, sun)
	sun_lost = LOST_TIME
	var c := project(px, py + 0.9, dist)
	var from := Vector2(c.x, c.y) if c.z > 0 else Vector2(W / 2, H * 0.7)
	lost_flyers.append({"from": from, "t": 0.0})


## Ran into a root or a branch: bounce back, the path rolls back a bit.
func bump() -> void:
	invuln = INVULN_TIME
	drops = maxf(0, drops - HIT_DROPS)
	_lose_slice()
	bump_t = 0.45
	_roll_to = maxf(_stage_start(), dist - BUMP_BACK)
	vy = 3.0
	flash = 0.4
	Audio.play_sfx("au%d.wav" % (1 + int(time * 13) % 5), 0.6)
	_reset_behind()


## Caught by a bird in the air: carried back along the path.
func carried() -> void:
	invuln = INVULN_TIME + 1.2
	drops = maxf(0, drops - HIT_DROPS)
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
	# A queued repeat doesn't count until she reaches it (no jump in the ring
	# or the speed).
	var end: float = s.end - (_loop_shift if _loop_cross >= 0 else 0.0)
	return clampf((dist - s.start) / maxf(1.0, end - s.start), 0, 1)


## Speed factor while recovering: 0 while she stands, then up to 1.
func recover_k() -> float:
	if recover_t <= 0:
		return 1.0
	if recover_t > RECOVER_RAMP:
		return 0.0
	var k := 1.0 - recover_t / RECOVER_RAMP
	return k * k


## Puts her at `z` (developer shortcuts, tests): the stage follows.
func jump_to(z: float) -> void:
	# A repeat already queued stays (the stage runs on into it) unless she
	# leaves the stage.
	if _loop_cross >= 0 and stage_of(z) != stage:
		_enter_loop()
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
	recover_t = 0
	invuln = 0


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
	var near_l := project(-LANE * 2.4, 0, dist + 0.4 - CAM_BACK + 0.31)
	var near_r := project(LANE * 2.4, 0, dist + 0.4 - CAM_BACK + 0.31)
	# The path runs to the horizon (its vanishing point, far away).
	var far_l := project(-LANE * 2.4, 0, dist + 100000.0)
	var far_r := project(LANE * 2.4, 0, dist + 100000.0)
	draw_colored_polygon(PackedVector2Array([Vector2(near_l.x - 200, H), Vector2(far_l.x, far_l.y), Vector2(far_r.x, far_r.y), Vector2(near_r.x + 200, H)]), Color("#b48a5a"))
	var sz := floorf(dist / 3.0) * 3.0
	while sz < dist + VIEW:
		var a := project(-LANE * 2.4, 0, sz)
		var b := project(LANE * 2.4, 0, sz)
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
		if intro > 0 and intro_elapsed() < INTRO_TREES + 0.8:
			break
		if oz > dist - CAM_BACK + 0.5 and oz < dist + VIEW and not o.taken and o.kind != "dialog":
			items.append([oz, o.kind, o])
	items.sort_custom(func(a, b): return a[0] > b[0])
	var player_drawn := false
	for it in items:
		if not player_drawn and it[0] < dist:
			_draw_player()
			player_drawn = true
		match it[1]:
			"tree":
				var tk := _intro_k(it[0])
				if tk <= 0.001:
					continue
				if tk < 1.0:
					# From the middle of the screen to its place.
					var mid := Vector2(W / 2, H / 2)
					draw_set_transform(mid * (1.0 - tk), 0, Vector2(tk, tk))
					_draw_tree(it[2])
					draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				else:
					_draw_tree(it[2])
			"root": _draw_root(it[2])
			"branch": _draw_branch(it[2])
			"bird": _draw_bird(it[2])
			"drop": _draw_drop(it[2])
			"sun": _draw_sun_piece(it[2])
			"vine": _draw_vine(it[2])
	if not player_drawn:
		_draw_player()
	# Slowed time: a cool tint and a focus ring.
	if slow:
		# Focus: the edges darken, the middle stays clear.
		Draw.vignette(self, Rect2(0, 0, W, H), Color(0.02, 0.04, 0.1, 0.75), 0.3)
		Draw.vignette(self, Rect2(0, 0, W, H), Color(0.1, 0.15, 0.35, 0.45), 0.35)
	if flash > 0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 0.4, 0.3, flash * 0.6))
	if intro <= 0:
		_draw_hud()
		_draw_loop_note()
	else:
		_draw_intro_hud()
	_draw_flyers()
	# The arena crossfading away (over everything, the grain flies above it).
	if intro > 0 and _from_cave and intro_elapsed() < INTRO_FADE:
		var a := 1.0 - intro_elapsed() / INTRO_FADE
		draw_texture_rect(_from_cave, Rect2(0, 0, W, H), false, Color(1, 1, 1, a * a * (3 - 2 * a)))
	if intro > 0:
		_draw_grain()


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
	return PATHS if o.lane == -9 else [o.lane]


func _draw_root(o: Dictionary) -> void:
	var z: float = o.z
	# Across all paths (lane -9) or one path.
	var x0: float = -LANE * 2.3 if o.lane == -9 else (o.lane - 0.55) * LANE
	var x1: float = LANE * 2.3 if o.lane == -9 else (o.lane + 0.55) * LANE
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
	for i in (4 if o.lane == -9 else 1):
		var k := 0.2 + i * 0.2 if o.lane == -9 else 0.5
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
	# From beside the path into the outer path (to its inner edge).
	var sgn := signf(o.lane)
	var side: float = sgn * LANE * 3.6
	var tip: float = lerpf(side, sgn * (absf(o.lane) - 0.5) * LANE, e)
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
	# After a hit she blinks (nothing hits her meanwhile).
	if invuln > 0 and carry_t <= 0 and fmod(invuln, 0.24) < 0.1:
		return
	var handing := _over_cave and intro > 0 and not _landed
	if handing and _handoff_at < 0:
		return
	# Shadow on the path, smaller the higher she is.
	if py > -0.05 and not handing:
		draw_set_transform(Vector2(g.x, g.y), 0, Vector2(1, 0.3))
		draw_circle(Vector2.ZERO, 34 * k * (1.0 - clampf(py / 3.0, 0, 0.6)), Color(0, 0, 0, 0.25))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var run := sin(time * (16.0 if not slow else 9.0))
	var air := absf(py) > 0.05 or carry_t > 0 or handing
	if (intro > 0 and _landed) or (recover_t > RECOVER_RAMP and not air):
		# She stands still (back to us): before the run, or after a hit.
		run = 0.0
	elif recover_t > 0:
		run = sin(time * 16.0 * maxf(0.3, recover_k()))
	var bob := 0.0 if air else absf(run) * 4 * k
	var feet := Vector2(c.x, c.y - bob)
	var hand_k := 1.0
	if handing:
		# The arena's Kyra (drawn by the arena) until the handoff, then from
		# there onto the path, growing to her size here.
		var ht := clampf((intro_elapsed() - _handoff_at) / HANDOFF_FALL, 0, 1)
		feet = _handoff_from.lerp(feet, ht * ht)
		hand_k = lerpf(_handoff_h / maxf(1.0, 145.0 * k), 1.0, ht * ht)
	var lean := -0.25 if bump_t > 0 else 0.0
	# Landing after the drop: squashed, then back up.
	var sq := sin(clampf(land_t / 0.35, 0, 1) * PI) * 0.22
	# Falling in at the start she comes closer: she grows as she drops.
	var grow := 1.0
	if intro > 0 and not _landed:
		grow = lerpf(INTRO_FALL_SCALE, 1.0, 1.0 - clampf(py / INTRO_FROM_Y, 0, 1))
	draw_set_transform(feet, lean, Vector2(1.0 + sq, 1.0 - sq) * grow * hand_k)
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


func _draw_flyers() -> void:
	# A lost slice: it pops out of her, spins up and falls away behind, fading.
	for f in lost_flyers:
		var t: float = f.t
		var p: Vector2 = f.from + Vector2(-90 * t, -230 * t + 420 * t * t)
		var a := 1.0 - clampf((t - 0.6) / 0.4, 0, 1)
		var s := lerpf(30.0, 18.0, t) * a
		if s < 0.5:
			continue
		Draw.radial_glow(self, p, s * 2.4, Color(0.94, 0.27, 0.27, 0.55 * a), Color(1, 0.9, 0.7, 0.8 * a))
		draw_set_transform(p, t * 9.0, Vector2.ONE)
		SpriteArt.draw_sun_piece(self, Vector2.ZERO, s, cos(time * 12))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for f in flyers:
		var k: float = f.t * f.t * (3 - 2 * f.t)
		var to := fly_target(f.kind)
		# An arc: up and over towards the indicator.
		var mid: Vector2 = (f.from + to) / 2 + Vector2(0, -120)
		var p: Vector2 = f.from.lerp(mid, k).lerp(mid.lerp(to, k), k)
		if f.kind == "sun":
			var s := lerpf(30.0, 16.0, k)
			Draw.radial_glow(self, p, s * 2.2, Color(1, 0.8, 0.3, 0.6), Color(1, 0.95, 0.7, 0.9))
			SpriteArt.draw_sun_piece(self, p, s, cos(time * 9))
		else:
			Draw.radial_glow(self, p, 22, Color(0.37, 0.7, 0.94, 0.35))
			SpriteArt.draw_drop(self, p, lerpf(1.2, 0.8, k))


## The grain the nuts formed: from the arena's middle to the sun's place, where
## it opens into the sun.
func _draw_grain() -> void:
	var e := intro_elapsed()
	var t0: float = INTRO_GRAIN[0]
	var t1: float = INTRO_GRAIN[1]
	if e > t1 + 0.45:
		return
	var k := clampf((e - t0) / (t1 - t0), 0, 1)
	k = k * k * (3 - 2 * k)
	var from := GRAIN_FROM if (_from_cave or _over_cave) else Vector2(W / 2, H / 2)
	var mid := (from + SUN_HUD) / 2 + Vector2(40, -60)
	var p := from.lerp(mid, k).lerp(mid.lerp(SUN_HUD, k), k)
	var r := lerpf(GRAIN_R, 14.0, k)
	var fade := 1.0 - clampf((e - t1) / 0.45, 0, 1)
	Draw.radial_glow(self, p, r + 20, Color(224 / 255.0, 89 / 255.0, 122 / 255.0, 0.6 * fade), Color(1, 1, 1, 0.9 * fade))
	draw_circle(p, r * 0.8, Color("#efdacd", fade))
	draw_circle(p + Vector2(-r * 0.2, -r * 0.2), maxf(0.1, r * 0.3), Color("#d69c70", fade))


## During the intro: the sun opens out of the grain, the water pill comes last.
func _draw_intro_hud() -> void:
	var e := intro_elapsed()
	var t1: float = INTRO_GRAIN[1]
	if e >= t1:
		var a := clampf((e - t1) / 0.5, 0, 1)
		var grow := 1.0 - pow(1.0 - a, 3)
		if a < 1.0:
			Draw.radial_glow(self, SUN_HUD, 90 * grow, Color(1, 0.9, 0.5, 0.5 * (1.0 - a)))
		SpriteArt.draw_sun(self, SUN_HUD, 46 * maxf(0.05, grow), 0, 0.0, time)
	if e > INTRO_FALL_AT:
		draw_water_pill(self, WATER_HUD, drops, water / 100.0, false, time)


## The controls, for a few seconds at the start (when Iskra's dialog is skipped).
func _draw_loop_note() -> void:
	if loop_note <= 0:
		return
	var a := clampf(minf(loop_note, CONTROLS_TIME - loop_note) / 0.4, 0, 1)
	var txt := Text.plain(Text.t("RUNNER_CONTROLS"))
	var tw := Text.font_bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var r := Rect2(W / 2 - tw / 2 - 18, 24, tw + 36, 36)
	Draw.panel(self, r, Color(0.94, 0.93, 0.91, 0.92 * a), 18, Color(0.37, 0.61, 0.6, 0.3 * a), 2)
	draw_string(Text.font_bold, Vector2(r.position.x + 18, r.position.y + 24), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.02, 0.3, 0.23, a))


func _draw_hud() -> void:
	# The sun at the top-left (where the iron nut is in the cave): 12 slices, one
	# per piece found; the ring shows the way through the stage.
	var sc := SUN_HUD
	var grow := 1.0 + 0.18 * sin(clampf(sun_pulse / 0.45, 0, 1) * PI)
	if sun_pulse > 0:
		Draw.radial_glow(self, sc, 90 * grow, Color(1, 0.9, 0.5, 0.5 * sun_pulse / 0.45))
	draw_arc(sc, 56 * grow, -PI / 2, -PI / 2 + TAU * stage_progress(), 48, Color(1, 1, 1, 0.75), 3.0, true)
	if sun_lost > 0:
		# The lost slice blinks red in its place a few times, the sun shakes.
		var k := sun_lost / LOST_TIME
		sc += Vector2(sin(time * 70.0), cos(time * 55.0)) * 4.0 * k * k
		Draw.radial_glow(self, sc, 80, Color(0.94, 0.27, 0.27, 0.45 * k))
	SpriteArt.draw_sun(self, sc, 46 * grow, sun_shown, sun_flash, time)
	if sun_lost > 0 and fmod(LOST_TIME - sun_lost, 0.24) < 0.14:
		var i := sun_shown
		var r := 46 * grow
		var a0 := -PI / 2 + i * TAU / 12 + 0.035
		var a1 := -PI / 2 + (i + 1) * TAU / 12 - 0.035
		var tri := PackedVector2Array([sc, sc + Vector2(cos(a0), sin(a0)) * r, sc + Vector2(cos(a1), sin(a1)) * r])
		Draw.polygon_safe(self, tri, Color(0.94, 0.27, 0.27, 0.95))
		draw_polyline(tri + PackedVector2Array([tri[0]]), Color(1, 1, 1, 0.9), 2.0, true)
	# Hydration at the top-right (where the breath is in the cave): the water
	# that feeds slowed time.
	var wr := WATER_HUD
	if water_flash > 0:
		var g := 6.0 * sin(water_flash / 0.45 * PI)
		wr = wr.grow(g)
		Draw.radial_glow(self, Vector2(wr.position.x + 26, wr.get_center().y), 50, Color(0.37, 0.7, 0.94, 0.6 * water_flash / 0.45))
	if water_short > 0:
		wr.position.x += sin(water_short * 60.0) * 5.0
	draw_water_pill(self, wr, drops, water / 100.0, slow, time, short_for if water_short > 0 else "", reload_t)
	if water_short > 0:
		Draw.panel(self, wr.grow(2), Color(0, 0, 0, 0), 18, Color(0.94, 0.27, 0.27, water_short / 0.5), 3)
	hints.draw(self, Vector2(WATER_HUD.end.x, WATER_HUD.end.y))


## The hydration pill: a drop and how full the water is (slowed time pulses it).
## The water: the magazine of four drops (a part-used one keeps only its lower
## part) and, as a line round the pill that fills up like the cave's breath
## ring, the bar ("mana") the magazine reloads from. `blink` = "double" /
## "focus": the missing drops blink red; `reload` > 0: the line shimmers while
## the drops fill one by one.
static func draw_water_pill(ci: CanvasItem, r: Rect2, n: float, bar_k: float, slowing: bool, t: float, blink := "", reload := 0.0) -> void:
	Draw.panel(ci, r, Color("#f0eee9"), 16, Color(0.37, 0.61, 0.6, 0.2), 2)
	var red := Color(0.94, 0.27, 0.27)
	var on := fmod(t, 0.2) < 0.12
	var step := (r.size.x - 24) / 4.0
	for i in 4:
		var c := Vector2(r.position.x + 12 + step * (i + 0.5), r.get_center().y + 1)
		var fill := clampf(n - i, 0, 1)
		var empty := Color(0.58, 0.64, 0.72, 0.35)
		if blink != "" and on and fill < 1.0 and (blink == "focus" or i < 2):
			empty = Color(red, 0.75)
		var pts := _drop_pts(c, 1.05)
		Draw.polygon_safe(ci, pts, empty)
		if fill > 0.01:
			var col := Color("#5fb3f0")
			if slowing:
				col = Color("#93c5fd").lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 10))
			if fill >= 0.99:
				Draw.polygon_safe(ci, pts, col)
			else:
				# Only the part below the water line.
				var top := c.y + 13.0 - 27.0 * fill
				var below := PackedVector2Array([Vector2(c.x - 20, top), Vector2(c.x + 20, top), Vector2(c.x + 20, c.y + 20), Vector2(c.x - 20, c.y + 20)])
				for part in Geometry2D.intersect_polygons(pts, below):
					Draw.polygon_safe(ci, part, col)
			ci.draw_circle(c + Vector2(-3, 1) * 1.05, 2.5 * 1.05, Color(1, 1, 1, 0.8))
	# The bar as a line round the pill (like the breath ring in the cave).
	var col_line := Color("#2563eb").lerp(Color("#5fb3f0"), 0.35)
	if reload > 0:
		col_line = col_line.lerp(Color.WHITE, 0.3 + 0.3 * sin(t * 14))
	progress_outline(ci, r, bar_k, col_line)


## A drop's outline (as SpriteArt.draw_drop draws it).
static func _drop_pts(c: Vector2, k: float) -> PackedVector2Array:
	var pts := PackedVector2Array([c + Vector2(0, -13) * k])
	for i in range(1, 12):
		var ang := -PI / 2 + i / 12.0 * TAU
		pts.append(c + Vector2(cos(ang) * 9, sin(ang) * 9 + 3) * k)
	return pts


## A line round a rounded rect, filled to `k` (0–1) clockwise from the top left.
static func progress_outline(ci: CanvasItem, rect: Rect2, k: float, col: Color) -> void:
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
		ci.draw_polyline(out, col, 4.0, true)
