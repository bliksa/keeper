class_name PlayerBody
extends RefCounted
## Plain player state (position, velocity, breathing, animation flags).
## Shared by the forest intro and the cave platformer.

var x := 0.0
var y := 0.0
var vx := 0.0
var vy := 0.0
var width := 30.0
var height := 60.0
var is_grounded := false
var was_grounded := false
var facing_right := true
var jumps_left := 2
var is_sitting := false
var is_crouched := false
var is_dead := false
var is_hanging := false
var look_down_timer := 0.0
var anim_progress := 0.0

## Walk/run cycle speed (frames per pixel); the animation lab can change run_rate.
static var run_rate := 0.026
static var walk_rate := 0.038

# --- cave-only state ---
## Breath blast ring (40 → 0).
var is_breathing := 0.0
var breathing_cooldown := 0.0
var breath_charges := 3
var invuln_timer := 0.0
var hit_timer := 0.0
## Recharge sequence (▲ inhale 4 s, ■ hold 2 s, ▼ exhale 6 s).
var is_recharging := false
var breath_timer := 0.0
var breath_index := 0
var breath_error_timer := 0.0
var has_used_breath := false
var breath_failed := false
var breath_success := false
## Id of the cramp enemy holding the player, -1 = free.
var held_by_cramp := -1
var cramp_drain_timer := 0.0

# --- level 2 (garden) state ---
## Dash (after the rhythm minigame): time left in the dash and its cooldown.
var dash_timer := 0.0
var dash_cooldown := 0.0
## A distraction touched the player: slowed down while > 0.
var slow_timer := 0.0
## Game feel (levels 2 and 3): coyote time, jump buffer, landing squash.
var coyote := 0.0
var jump_buffer := 0.0
var squash := 0.0
var jumped_from_ground := false


func rect() -> Rect2:
	return Rect2(x, y, width, height)


func center() -> Vector2:
	return Vector2(x + width / 2, y + height / 2)


## Advance the walk/run cycle and play footsteps on frames 2 and 6 (web behaviour).
func step_animation(dt60: float) -> void:
	if is_grounded and absf(vx) > 0.1:
		var before := anim_progress
		var rate := run_rate if absf(vx) > 3.5 else walk_rate
		anim_progress += absf(vx) * dt60 * rate
		var now_f := int(floorf(fmod(anim_progress, 8)))
		var was_f := int(floorf(fmod(before, 8)))
		if (was_f < 2 and now_f >= 2) or (was_f < 6 and now_f >= 6):
			Audio.footstep(0.5)
	else:
		anim_progress = 0
