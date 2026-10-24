class_name PlayerArt
extends RefCounted
## Draws the player character (Kyra) onto any CanvasItem.
## Port of the web `wf()` function: same frames, offsets and timings.

const SPRITE_H := 85.0
const DIR := "res://assets/images/"

## Sprite scale (1.6 like the web build); the animation lab can change it.
static var scale := 1.6
## Frame overrides from the animation lab: "run" | "jump" | "sidejump" |
## "doublejump" | "fall" -> Array[Texture2D]. Empty = original art.
static var overrides := {}
## Playback speed of multi-frame jump/fall overrides.
static var jump_fps := 12.0

static var _frames := {}


static func _seq(name: String, count: int) -> Array:
	var key := "%s%d" % [name, count]
	if not _frames.has(key):
		var arr := []
		for i in range(1, count + 1):
			arr.append(load(DIR + "%s%d.png" % [name, i]))
		_frames[key] = arr
	return _frames[key]


static func _one(name: String) -> Texture2D:
	if not _frames.has(name):
		_frames[name] = load(DIR + name + ".png")
	return _frames[name]


## p: PlayerBody. time_ms: elapsed ms. big_ring: boss breath ring (400 px instead of 200).
## o: optional overrides { facing_right, sitting, crouched, hanging, airborne, looking_down, pain, dead }
static func draw(ci: CanvasItem, p: PlayerBody, time_ms: float, big_ring := false, o := {}) -> void:
	var facing: bool = o.get("facing_right", p.facing_right)
	var sitting: bool = o.get("sitting", p.is_sitting)
	var crouched: bool = o.get("crouched", p.is_crouched)
	var hanging: bool = o.get("hanging", false)
	var airborne: bool = o.get("airborne", not p.is_grounded)
	var looking_down: bool = o.get("looking_down", p.look_down_timer > 0)
	var pain: bool = o.get("pain", p.hit_timer > 0 or p.held_by_cramp != -1)
	var dead: bool = o.get("dead", p.is_dead)
	var speed: float = absf(p.vx)
	var moving := speed > 0.5
	var running := moving and speed > 3.5

	var off_y := 0.0
	var SCALE := scale
	if sitting: off_y = 22 * SCALE
	if pain: off_y = 0
	if dead: off_y = 22 * SCALE
	if hanging: off_y = 45 * SCALE
	var origin := Vector2(p.x + p.width / 2, p.y + p.height / 2 + off_y)

	var single: Texture2D = null
	var seq: Array = []
	var lift := -1.0
	if dead:
		single = _one("smrt")
	elif hanging:
		single = _one("hang")
	elif pain:
		seq = _seq("pain", 4)
	elif airborne:
		var pose := "jump"
		if p.vy > 0: pose = "fall"
		elif p.jumps_left == 0: pose = "doublejump"
		elif speed > 1: pose = "sidejump"
		var alt: Array = overrides.get(pose, [])
		if alt.is_empty():
			single = _one(pose)
		else:
			single = alt[int(floorf(time_ms / 1000.0 * jump_fps)) % alt.size()]
	elif sitting or crouched:
		seq = _seq("sed", 7)
		lift = -8
	elif looking_down:
		single = _one("lookdown")
	elif moving:
		seq = overrides.get("run", _seq("run", 8)) if running else _seq("walk", 8)
	else:
		seq = _seq("idle", 4)

	var tex := single
	if tex == null and seq.size() > 0:
		var idx := 0
		if moving and not airborne and not sitting and not crouched and not looking_down and not pain:
			idx = int(floorf(p.anim_progress)) % seq.size()
		else:
			var period := 240.0 if (sitting or crouched or pain) else 360.0
			idx = int(floorf(time_ms / period)) % seq.size()
		tex = seq[idx]

	ci.draw_set_transform(origin, 0.0, Vector2(SCALE if facing else -SCALE, SCALE))
	if tex:
		var k := SPRITE_H / tex.get_height()
		var w := tex.get_width() * k
		ci.draw_texture_rect(tex, Rect2(-w / 2, 30 - SPRITE_H + lift, w, SPRITE_H), false)
	ci.draw_set_transform(origin, 0.0, Vector2.ONE)
	if p.is_breathing > 0:
		var max_r := 400.0 if big_ring else 200.0
		var r := (40.0 - p.is_breathing) / 40.0 * max_r
		ci.draw_arc(Vector2.ZERO, maxf(r, 0.5), 0, TAU, 72, Color(1, 1, 1, p.is_breathing / 40.0), 4.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
