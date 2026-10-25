class_name PlayerArt
extends RefCounted
## Draws the player character (Kyra) onto any CanvasItem.
## Port of the web `wf()` function: same frames, offsets and timings.
##
## Every animation can be swapped for another frame list (animation lab,
## data/anim_variants.json → "in_game").

const SPRITE_H := 85.0
const DIR := "res://assets/images/"
const VARIANTS := "res://data/anim_variants.json"

## Animation id -> [file prefix, frame count]; count 0 = a single file "<prefix>.png".
const ANIMS := {
	"idle": ["idle", 4], "walk": ["walk", 8], "run": ["run", 8],
	"jump": ["jump", 0], "sidejump": ["sidejump", 0], "doublejump": ["doublejump", 0], "fall": ["fall", 0],
	"lookdown": ["lookdown", 0], "sit": ["sed", 7], "pain": ["pain", 4], "dead": ["smrt", 0], "hang": ["hang", 0],
}

## Sprite scale (1.6 like the web build); the animation lab can change it.
static var scale := 1.6
## Frame overrides: animation id -> Array[Texture2D]. Missing = original art.
static var overrides := {}
## Playback speed of multi-frame poses (jump, fall, lookdown, dead, hang).
static var anim_fps := 12.0

static var _frames := {}


## Original frame paths of an animation.
static func original_paths(anim: String) -> Array:
	var def: Array = ANIMS[anim]
	if def[1] == 0:
		return [DIR + def[0] + ".png"]
	var out := []
	for i in range(1, def[1] + 1):
		out.append(DIR + "%s%d.png" % [def[0], i])
	return out


## Frames used for an animation right now (override or original).
static func frames(anim: String) -> Array:
	if overrides.has(anim) and not overrides[anim].is_empty():
		return overrides[anim]
	if not _frames.has(anim):
		var arr := []
		for path in original_paths(anim):
			arr.append(load(path))
		_frames[anim] = arr
	return _frames[anim]


## Applies the "in_game" variants and settings from data/anim_variants.json
## (saved from the animation lab). Called once at start-up.
static func load_game_defaults() -> void:
	overrides = {}
	if not FileAccess.file_exists(VARIANTS):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(VARIANTS))
	if not d is Dictionary:
		return
	var anims: Dictionary = d.get("anims", {})
	var in_game: Dictionary = d.get("in_game", {})
	for anim in in_game:
		var paths: Array = anims.get(anim, {}).get(in_game[anim], [])
		var tex := []
		for path in paths:
			if ResourceLoader.exists(path):
				tex.append(load(path))
		if not tex.is_empty():
			overrides[anim] = tex
	var s: Dictionary = d.get("settings", {})
	scale = s.get("scale", 1.6)
	anim_fps = s.get("anim_fps", 12.0)
	PlayerBody.run_rate = s.get("run_rate", 0.026)


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
	var k_scale := scale

	var off_y := 0.0
	if sitting: off_y = 22 * k_scale
	if pain: off_y = 0
	if dead: off_y = 22 * k_scale
	if hanging: off_y = 45 * k_scale
	var origin := Vector2(p.x + p.width / 2, p.y + p.height / 2 + off_y)

	# Which animation, and how its frame is chosen: "progress" (walk cycle),
	# a fixed period in ms (idle 360, sit/pain 240) or "fps" (poses).
	var anim := "idle"
	var timing := "360"
	var lift := -1.0
	if dead:
		anim = "dead"
		timing = "fps"
	elif hanging:
		anim = "hang"
		timing = "fps"
	elif pain:
		anim = "pain"
		timing = "240"
	elif airborne:
		timing = "fps"
		if p.vy > 0: anim = "fall"
		elif p.jumps_left == 0: anim = "doublejump"
		elif speed > 1: anim = "sidejump"
		else: anim = "jump"
	elif sitting or crouched:
		anim = "sit"
		timing = "240"
		lift = -8
	elif looking_down:
		anim = "lookdown"
		timing = "fps"
	elif moving:
		anim = "run" if running else "walk"
		timing = "progress"

	var seq := frames(anim)
	var tex: Texture2D = null
	if seq.size() > 0:
		var idx := 0
		match timing:
			"progress":
				idx = int(floorf(p.anim_progress)) % seq.size()
			"fps":
				idx = int(floorf(time_ms / 1000.0 * anim_fps)) % seq.size()
			_:
				idx = int(floorf(time_ms / float(timing))) % seq.size()
		tex = seq[idx]

	# Landing squash / jump stretch (o.squash: +1 squashed, -1 stretched).
	var sq: float = o.get("squash", 0.0)
	var sx := k_scale * (1.0 + 0.25 * sq)
	var sy := k_scale * (1.0 - 0.3 * sq)
	ci.draw_set_transform(origin, 0.0, Vector2(sx if facing else -sx, sy))
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
