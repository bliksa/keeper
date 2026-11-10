class_name Platformer
extends Node2D
## The cave: vertical platformer + boss fight. Port of the web `vv` component.
##
## Physics constants and behaviours are copied 1:1 from the prototype; all
## per-frame values are scaled by dt60 (= delta * 60) like the original.
##
## Level 2 (the meadow, level_id 2) is horizontal (left → right): the river below
## is the old cycle flowing away (wading through it is slow, the current pushes
## back), dew drops on the leaves fill the vessel (estrogen: 25 % longer thread,
## 50 % faster pull, 75 % the dew absorbs one shadow hit), light seeds are caught
## with the focus thread (aim + hold), shadows attack while you focus and push
## the gate further away.
## Level 3 (the summit, level_id 3) is an Icy Tower style climb: faster movement,
## wall jumps off the sides, a combo for landing higher and higher, and adds: climbing up
## instead of down, bubble platforms, updrafts, distractions instead of cramps,
## power-ups from its minigames (jump, dash, double) and the LH wave chase that
## replaces the boss (reach the summit before the wave catches you).
## Level 5 (the jackpot climb, level 3 of the game) is climbed up with the board at the
## bottom edge rising behind her (the ticker): springs, hearts (they fill the heart meter;
## ready hearts buy a heart boost and rocket fuel), bells (+1 heart), jokers (the spinner
## top-left spins and pays a power-up), jackpot rows (checkpoints) and, once in the middle,
## the wheel of the cycle (minigame mg11, FertilityWheel); no score. Caught by the board she
## sits, no death. The board never stops rising (except while the wheel is open); there are
## no dialog boxes: dialogs play on the board itself (board_dialog). The forest run's sun
## shines in its sky, rising as she climbs (_draw_climb_sun).
## Level 6 (the PMS maze, level 4 of the game) is drawn upside down: the physics stay normal,
## the whole view is rotated 180° around the screen centre (view_flip), so on screen she
## walks on the ceiling and the arrows feel reversed. Walls (W) are solid from every side;
## three comfort items open the door (PmsMaze). The climb's end turns into it (start_prerod).

signal trigger(name: String)
signal boss_defeated
signal boss_lost
## The maze: a movement key was pressed while a dialog holds her (Main shakes its button).
signal dialog_nudge
var _stick_held := {}
## The maze's look-down peek, eased (px of camera).
var pms_peek := 0.0
## The climb: a dialog played on the board (board_dialog) has said all its parts.
signal board_dialog_done(id: String)
## The climb's end: the transformation has turned the view upside down (start_prerod).
signal prerod_turned

const W := 1066.0
const H := 600.0
const GRAVITY := 0.4
const JUMP_FORCE := -10.5
const MAX_SPEED := 6.0
const ACCEL := 1.2
const FRICTION := 0.75
const MAX_FALL := 15.0
const HEX_W := 48.0
const HEX_H := 42.0
## Level 2: a popping bubble bursts after standing on it this long, regrows after REGROW.
const POP_AFTER := 0.7
const REGROW := 3.5
const DASH_TIME := 0.22
const DASH_SPEED := 15.0
const DASH_COOLDOWN := 0.9
## LH wave: start speed and max speed (px per frame at 60 fps) and acceleration.
const WAVE_SPEED := 1.3
const WAVE_MAX := 2.0
const WAVE_ACCEL := 0.02
## Game feel in levels 2 and 3 (the cave keeps the web build's values).
const FEEL_ACCEL := 2.0
const FEEL_FRICTION := 0.6
const COYOTE := 0.1
const JUMP_BUFFER := 0.12
## Level 2: the river (swimming against the current), the focus thread and the shadows.
const SWIM_SPEED := 0.5
const SWIM_JUMP := 0.9
const CURRENT := 1.6
const THREAD_RANGE := 220.0
const THREAD_RANGE_LONG := 320.0
const THREAD_CONE := 0.6 # radians
const PULL_SPEED := 110.0
const PULL_SPEED_DODGE := 70.0
const CATCH_DIST := 30.0
const SHADOW_SPEED := 3.2
## Level 3 (Icy Tower): run speed becomes jump height, walls bounce, the wave
## rises from the start, floors count and multi-floor jumps chain into combos.
const SUMMIT_SPEED := 1.4
const SUMMIT_ACCEL := 1.3
const MOMENTUM_JUMP := 0.55
const WALL_KICK := 10.0
const WALL_BOUNCE := 0.85
const WAVE_START_SPEED := 0.55
const WAVE_SPRINT := 1.2
## The jackpot climb (level 5): the board at the bottom edge (same rect as a dialog box)
## rises on its own (px per frame at 60 fps, accelerating per second) and catches her.
const BOARD_H := 150.0
const RISE_START := 0.7
const RISE_ACCEL := 0.04
const RISE_MAX := 2.6
## At the start / a checkpoint the board waits this long (s) before it starts rising;
## after that it never stops (a catch only resets its speed to RISE_START).
const RISE_GRACE := 1.0
## The climb is drawn zoomed out (world, background and player scaled; HUD and board not):
## the screen shows 1 / CLIMB_ZOOM more world, exactly its CLIMB_COLS columns across.
const CLIMB_ZOOM := float(LevelData.COLS) / LevelData.CLIMB_COLS
## Following her up keeps at least this much (px) above her head (boosts, the rocket).
const CLIMB_TOP_MARGIN := 70.0
## Spring launch: v² / (2 · GRAVITY) ≈ 550 px; the rocket ≈ 900 px.
const SPRING_FORCE := 21.0
const ROCKET_FORCE := 26.8
## Timed power-ups (s), the magnet's reach (px), the spinner top-left (a joker: s until
## it pays; a bell: a shorter spin, BELL_STOPS).
const POWER_TIME := 12.0
const ROCKET_TIME := 1.4
const MAGNET_RANGE := 260.0
const SLOT_SPIN := 1.2
const SLOT_STOPS := [0.5, 0.85, 1.2]
const BELL_STOPS := [0.3, 0.45, 0.6]
## The spinner's symbols (its three windows) and what it shows before the first spin.
const SPIN_SYMBOLS := ["heart", "bell", "joker"]
const POWERS := ["super_jump", "triple", "magnet", "rocket"]
## The board's news ticker: speed (px/s), font size, the text area on the board.
const TICKER_SPEED := 90.0
const TICKER_FS := 22
const TICKER_LEFT := 158.0
const TICKER_GAP := 70.0
## The heart meter (MeterModel, like the forest run's water and a gun's magazine):
## HEART_SLOTS hearts in the magazine and a reserve of as many more (the line round the
## pill). Every heart picked up is HEART_FILL (%) of one: it fills the magazine first, a
## full magazine sends it into the reserve, which reloads the magazine (at once when it is
## empty, else after a moment without spending), heart by heart. Ready hearts buy the abilities: rocket fuel (jump held past a jump's top: the thrusters
## burn hearts, FUEL_HEART_TIME s each) and the heart boost (Shift / B: a launch up like a
## spring, HEART_BOOST_COST).
const HEART_SLOTS := 4
const HEART_FILL := 20.0
## Rocket fuel: the thrusters ignite once her rise has run out (vy >= FUEL_IGNITE_VY) with
## jump still held, climb at FUEL_SPEED px/frame (reached at FUEL_ACCEL px/frame²) and burn
## one heart per FUEL_HEART_TIME s; they stop FUEL_CEIL px below the level's top.
const FUEL_IGNITE_VY := -1.0
const FUEL_SPEED := 12.0
const FUEL_ACCEL := 1.5
const FUEL_HEART_TIME := 0.8
const FUEL_CEIL := 60.0
## The least of a heart in the magazine that lights the thrusters.
const FUEL_MIN := 0.2
## While the thrusters burn the camera keeps this share of the view above her.
const FUEL_VIEW_LEAD := 0.38
## … but a short burn keeps the board this far under the platform she jumped from.
const FUEL_GUARD_SLACK := 30.0
const HEART_BOOST_COST := 2
const HEART_BOOST_FORCE := 20.0
## The forest run's sun in the climb's sky (screen px, not zoomed): at the start where the
## run left it (SUN_MELT_POS, ForestRunner.END_SUN_R), rising to SUN_TOP_Y at the top.
const SUN_TOP_Y := 92.0
const SUN_R0 := 96.0
const SUN_R1 := 80.0
## Dialogs on the board (the climb has no dialog box): the text area relative to the
## board's top-left corner, and each part's reading time (s) from its length.
const BOARD_TEXT := Rect2(158, 50, 644, 88)
const BOARD_READ_BASE := 2.5
const BOARD_READ_CHAR := 0.05
const BOARD_READ_MIN := 3.0
const BOARD_READ_MAX := 8.0
## The new phase's announcement on the board when the climb comes in from the forest run
## (announce_phase): its time (s); the bulbs blink in during the first PHASE_BULBS s.
const PHASE_TIME := 3.0
const PHASE_BULBS := 0.8
## The forest run's sun in the middle of the sky melting into the climb's light (s).
const SUN_MELT := 3.0
const SUN_MELT_POS := Vector2(533, 200)
## The dialog that explains a power-up, said on the board the first time it is won.
const POWER_DIALOG := {"super_jump": "3A", "triple": "3B", "magnet": "3C", "rocket": "3D"}
## The board dialog that explains the heart reserve (the first heart into it in a climb).
const RESERVE_DIALOG := "3F"

# --- the transformation (the climb's end) and the PMS maze (level 6) -------------------
## The transformation (start_prerod), one clock prerod_t in phases (s): FOCUS the casino
## winds down (WIND) while the sun (the follicle) comes to the screen's middle and grows;
## EGG it opens along its slices and the egg floats away (ovulation); LUTEUM it closes into
## the yellow body (the corpus luteum: a hollow amber sphere with an opening); PULL Kyra is
## drawn into the opening while the view turns 180° (view_flip) and zooms in; IRIS the
## opening fills the screen (warm amber, never black). Then prerod_turned: Main starts the
## maze inside it (start_warm).
const PREROD_WIND := 1.5
const PREROD_FOCUS := 2.0
const PREROD_EGG := 2.2
const PREROD_LUTEUM := 2.9
const PREROD_PULL := 2.2
const PREROD_IRIS := 0.7
const PREROD_T_EGG := PREROD_FOCUS
const PREROD_T_LUTEUM := PREROD_T_EGG + PREROD_EGG
const PREROD_T_PULL := PREROD_T_LUTEUM + PREROD_LUTEUM
const PREROD_T_IRIS := PREROD_T_PULL + PREROD_PULL
const PREROD_T_END := PREROD_T_IRIS + PREROD_IRIS
## The sky's sun (in _bg, behind the platforms) hands over to the follicle on the veil
## (over the world): the veil's body fades in over this long, the sky sun's glow out.
const PREROD_HAND := 0.5
## When the egg leaves the opened sun (s after the EGG phase starts) and how long it floats.
const EGG_OUT := 0.45
const EGG_FLY := 2.2
## The yellow body in the middle of the screen (screen px; the view turns around it) and
## its radius there; its opening's share of the radius; how far the zoom goes (radius ×).
const LUTEUM_C := Vector2(533, 300)
const LUTEUM_R := 130.0
const LUTEUM_HOLE := 0.38
const LUTEUM_ZOOM := 14.0
## Inside the opening: dark amber in the middle, brighter towards its rim.
const LUTEUM_IN := Color(0.5, 0.25, 0.09)
const LUTEUM_RIM := Color(0.86, 0.52, 0.17)
## The transformation's captions (PREROD_EGG, PREROD_LUTEUM): size, width, baseline.
const CAPTION_FS := 24
const CAPTION_W := 820.0
## The least share of board_read_time each caption stays on (the sequence can't wait).
const CAPTION_READ := 0.6
const CAPTION_Y := 516.0
## The maze's first look from inside the yellow body: the opening clears (s), then the
## warm amber tint fades to the maze's dusk (s) as the hormones drop.
const WARM_IRIS := 1.1
const WARM_FADE := 4.0
const WARM_TINT := Color(1.0, 0.8, 0.5)
## The maze's light is her energy (pms_light 0..1, the PMS tiredness): it drains LIGHT_DRAIN
## per s while she moves or jumps (full → empty in 55 s of play), LIGHT_DRAIN_STILL standing
## still. Rest (the ability held, on the ground: she sits and can't move): after REST_DELAY s
## it comes back REST_FILL per s. The rest hint shows below REST_HINT (the light is visibly
## small by then), on the ground.
const LIGHT_DRAIN := 1.0 / 55.0
const LIGHT_DRAIN_STILL := 1.0 / 240.0
const REST_DELAY := 0.4
const REST_FILL := 0.2
const REST_HINT := 0.5
## Blob wobble (px) and view sway (radians) in the maze; both grow by up to PMS_TIRED as the
## energy drops (tired_k, from `tired`: the spent energy eased at TIRED_EASE per s, so a
## pickup doesn't snap the view) and settle a little while she rests.
const PMS_WOBBLE := 4.0
const PMS_SWAY := 0.022
## The maze's camera keeps Kyra on screen between the HUD (the top: slots, gauge, labels, a
## hint line, with room for the sway) and the dialog box / phase board (the bottom).
## On screen her top is never above PMS_TOP, her feet never below H - PMS_BOTTOM; the camera
## may over-scroll the map's first rows by PMS_OVER for it.
const PMS_TOP := 140.0
const PMS_BOTTOM := 190.0
const PMS_OVER := 200.0
const PMS_VIEW_Y := 0.42
## Holding down (standing still) peeks ahead, as in the other levels: up to PMS_PEEK px, her
## head then at least PMS_PEEK_EDGE from the screen's bottom (no dialog is open meanwhile).
const PMS_PEEK := 300.0
const PMS_PEEK_EDGE := 40.0
## A stick counts as let go (for the next dialog nudge) below this.
const STICK_REST := 0.2
const PMS_TIRED := 0.5
const TIRED_EASE := 3.0
## The dark maze (_dark): the light round Kyra (radius, screen px) = lerp(LIGHT_MIN, LIGHT_R,
## energy), with the lantern lerp(LANTERN_MIN, LANTERN_R, energy): never no light at all. A
## comfort item's warm burst adds LIGHT_BURST for BURST_TIME s. Things still to find
## glimmer in the dark: the lantern lying in the maze (LANTERN_GLIMMER, from anywhere), once
## she has it the nearest comfort items within GLIMMER_RANGE world px of her (ITEM_GLIMMER,
## growing from nothing at the range's edge to full GLIMMER_NEAR px away), the door once open.
const LIGHT_MIN := 85.0
const LIGHT_R := 150.0
const LANTERN_MIN := 125.0
const LANTERN_R := 275.0
const LIGHT_BURST := 110.0
const BURST_TIME := 1.4
const LANTERN_GLIMMER := 62.0
const LANTERN_REACH_ROWS := 3.0
const ITEM_GLIMMER := 50.0
const GLIMMER_RANGE := 500.0
const GLIMMER_NEAR := 340.0
const DOOR_GLIMMER := 130.0
## The shader's holes of light.
const DARK_HOLES := 4
## The energy gauge (top-right) is unreliable: every FOG_GAP s of play a foggy spell of
## FOG_LEN s, in which it shows a wrong value (gauge(); eased in / out over FOG_EDGE s). The
## first one comes after FOG_FIRST s and is explained (trigger pms_fog → PmsMaze.FOG_DIALOG),
## FOG_TELL s into it, standing on the ground. If the explanation wasn't read to its end
## (another dialog took its place), the first spell comes again after FOG_RETELL s.
const FOG_FIRST := 12.0
const FOG_GAP := Vector2(8.0, 15.0)
const FOG_LEN := Vector2(3.0, 5.0)
const FOG_EDGE := 0.4
const FOG_TELL := 0.9
const FOG_RETELL := 2.5
const FOG_MODES: Array[String] = ["drift", "jitter", "freeze"]
## The warm arrival's light (light_radius: light_r + WARM_LIGHT · warm, the screen is lit
## while warm is high, then it closes in on her as the warm fades).
const WARM_LIGHT := 2600.0
## The darkness: a soft-edged hole per light (screen px; xy = centre, z = radius).
const DARK_SHADER := """
shader_type canvas_item;
uniform vec4 dark : source_color = vec4(0.05, 0.02, 0.09, 0.93);
uniform vec2 size = vec2(1066.0, 600.0);
uniform vec3 l0 = vec3(0.0, 0.0, 0.0);
uniform vec3 l1 = vec3(0.0, 0.0, 0.0);
uniform vec3 l2 = vec3(0.0, 0.0, 0.0);
uniform vec3 l3 = vec3(0.0, 0.0, 0.0);
float hole(vec2 q, vec3 l) {
	if (l.z <= 0.5) return 0.0;
	return 1.0 - smoothstep(l.z * 0.35, l.z, distance(q, l.xy));
}
void fragment() {
	vec2 q = UV * size;
	float lit = max(max(hole(q, l0), hole(q, l1)), max(hole(q, l2), hole(q, l3)));
	COLOR = vec4(dark.rgb, dark.a * (1.0 - lit));
}
"""


## Updated by Main.
var active := false
var dialog_open := false
var active_dialog_id := ""
var hide_platforms := false

var level: LevelData
var level_h := 0.0
var level_w := W
var camera_x := 0.0
## Screen px per world px (CLIMB_ZOOM in the climb, 1 elsewhere); see _apply_view().
var view_zoom := 1.0
## Level 2 state.
var last_ground := Vector2.ZERO
## Wading through the river right now.
var in_water := false
var shield_used := false
var focus := false
var aim := Vector2.ZERO
var aim_mode := "keys" # keys | mouse | stick
var _stick := Vector2.ZERO
var thread_target := -1
var shadows: Array[Dictionary] = []
var shadow_timer := 2.0
var gate_locked_timer := 0.0
## Seconds since the gate opened (pouring the water, the golden flower).
var meadow_end := 0.0
var _meadow_done_sent := false
## Scripted walk to the right after the boss (seconds left).
var scripted_walk := 0.0
## After the boss: a corridor into the forest opens in the middle (seconds since)
## and Kyra walks to it.
var corridor_t := 0.0
## The grain is drawn by the forest run's intro instead (the crossfade).
var hide_egg := false
## After the boss: Kyra drops out of the arena, down behind the dialog box.
var exit_fall := false
var _exit_x0 := 0.0
var _exit_t := 0.0
## The hop off the vanished floor (px per frame, up) and how long she takes to the middle (s).
const EXIT_HOP := -10.0
const EXIT_TO_MID := 0.7
## How much bigger Kyra gets as she falls out of the arena (towards us).
const EXIT_GROW := 0.8
var walk_to_x := -1.0
## 1 = the cave (down, cramps, boss), 2 = the garden (up, bubbles, LH wave).
var level_id := 1
## The view's rotation: 0 = upright, 1 = upside down (180° around the screen centre). The
## PMS maze keeps 1; the climb's end turns it 0 → 1 (start_prerod). Physics never turn.
var view_flip := 0.0
## The transformation's clock (-1 = not started) and the casino's wind-down 0..1.
var prerod_t := -1.0
var wind := 0.0
var _prerod_sent := false
## The transformation: the sun on screen when it started [centre, radius], the egg is out,
## where Kyra was when the pull began (INF = not yet).
var _prerod_sun0: Array = [Vector2(533, 120), 90.0]
var egg_released := false
var _pull_from := Vector2.INF
## The maze's warm start (start_warm): seconds since (-1 = none) and the tint left (1 → 0).
var warm_t := -1.0
var warm := 0.0
## The casino lights' own clock (it slows down while the casino winds down).
var _light_t := 0.0
## No control (the transformation, the maze's settling and its end).
var hold_input := false
## The maze: comfort items found (0..3), the door's open time.
var pms_items := 0
## Which comfort items (by tier = PmsMaze.ITEMS index) are found; any order is possible.
var pms_found: Array[bool] = [false, false, false]
var door_open := 0.0
var _pms_done_sent := false
## Her light's energy (0..1), resting now (the ability held on the ground; rest_t = s so far,
## rest_k 0..1 eases in once the energy refills), a comfort item's warm burst (1 → 0).
var pms_light := 1.0
var resting := false
var rest_t := 0.0
var rest_k := 0.0
var light_burst := 0.0
## The spent energy (1 - pms_light), eased: what tired_k() feels.
var tired := 0.0
## The gauge's foggy spells: s of play until the next, s left of this one (0 = none) of
## fog_len, its mode (FOG_MODES), its wrong offset, the value it froze at. Explained once:
## fog_told = the explanation was sent (trigger pms_fog), fog_explained = it was read to its
## end (set by Main when 4H closes); _fog_unread = s of play told but not explained.
var fog_wait := FOG_FIRST
var fog_t := 0.0
var fog_len := 0.0
var fog_mode := ""
var fog_off := 0.0
var fog_from := 0.0
var fog_told := false
var fog_explained := false
var _fog_unread := 0.0
var fog_count := 0
## The dark maze: the lantern found, the light's radius now (follows the energy, smooth), the
## darkness overlay (screen space, under the HUD).
var has_lantern := false
var light_r := LIGHT_R
var _dark: ColorRect
var deco: Array = []
## Tops of the walls, landed on like platforms (built in setup).
var wall_tops: Array[LevelData.Plat] = []
## The walls as drawn: runs of the same width stacked in a column merged into one blob.
var wall_blobs: Array[Rect2] = []
## The LH wave (level 2): rises from below once triggered; reach the summit first.
var wave := {"active": false, "y": 0.0, "speed": 0.0, "lost": false, "won": false}
## Seconds since the summit was reached (egg release animation).
var summit_timer := 0.0
## The jackpot climb (level 5): reached the top (E → "climb_top").
var climb_won := false
## The board: how fast it rises now (px/frame), the wait before it rises again, and
## whether she is standing / sitting on it (caught).
var rise := RISE_START
var rise_wait := RISE_GRACE
var on_board := false
## Feet (world y) on the last platform she stood on: following her up never lifts the
## board past it (only the board's own rise does), so a missed jump or the way down
## from a boost still lands on a platform.
var last_stand_y := 0.0
var jackpots := 0
## The heart meter (`meter`: the magazine and the reserve); `hearts` = whole hearts ready in
## the magazine (setting it, for dev shortcuts and tests, also empties the reserve);
## hearts picked up and bells rung in this climb; heart_short > 0 blinks the missing hearts
## (an ability tried without enough).
var meter := MeterModel.new(HEART_SLOTS, 0.0, 0.0)
var hearts: int:
	get:
		return meter.whole()
	set(v):
		meter.reset(float(v), 0.0)
var hearts_taken := 0
var bells := 0
var heart_short := 0.0
## Rocket fuel: the thrusters burn now (they drain the magazine); the thruster sound's clock.
var thrusting := false
var _thrust_sfx := 0.0
## Only a hold that carries on a launch (a jump, a spring, the heart boost, the rocket)
## ignites the thrusters: a press while falling stays a buffered jump.
var _fuel_armed := false
## After the wheel: jump must be let go once before the thrusters can ignite (the key
## that confirmed the wheel may still be down).
var _fuel_wait_release := false
var _flame_acc := 0.0
## The room kept above her head by the camera (CLIMB_TOP_MARGIN, more while thrusting).
var _top_margin := CLIMB_TOP_MARGIN
## The wheel of the cycle (mg11) has been played in this climb.
var wheel_done := false
## Timed power-ups from the jokers: name → seconds left (not Game.upgrades).
var climb_power := {}
var _power_bag: Array = []
## The spinner top-left (a joker or a bell spins it): {t, kind ("joker" / "bell"), power,
## stops, stop_at (Array of s), result (3 symbols), paid}; empty = idle.
var slot_spin := {}
## What the spinner's three windows show while idle (the last spin's result).
var spin_rest: Array = SPIN_SYMBOLS.duplicate()
## Big centre banner ({text, t}), floating number pops in the world.
var banner := {}
var pops: Array[Dictionary] = []
## A spring / rocket flight: letting go of jump doesn't cut it short.
var boost_t := 0.0
var _heart_note := 0
## The news ticker: segments on the board ({text, x, w, event}) and event lines waiting.
var ticker: Array[Dictionary] = []
var ticker_queue: Array[String] = []
var _tick_next := 0
## The dialog on the board ({id, part, t, dur, speaker, key}; empty = the ticker runs),
## the ones waiting after it, and the power-ups already explained in this climb.
var board_talk := {}
var board_queue: Array[String] = []
var powers_explained := {}
## The new phase's announcement on the board ({key, sub, t}; empty = none). The ticker and
## board dialogs wait for it; play and input don't.
var phase_note := {}
## Whose portrait the phase board shows (the cave / the PMS maze).
var phase_speaker := "Estrogenka"
## The forest run's sun melting into the climb's light (1 → 0 over SUN_MELT s).
var sun_glow := 0.0
var _rest_ms := -1e9
## Level 3: touching a side wall in the air (wall jump), combo of higher landings.
var on_wall := false
var combo := 0
var last_landing_y := 0.0
var combo_flash := 0.0
## Level 3: floor the player stands on (0 = the ground), the highest reached, the
## floor of the last landing (for combos).
var floor_now := 0
var best_floor := 0
var last_floor := 0
var p := PlayerBody.new()
var camera_y := 0.0
var particles: Array[Dictionary] = []
var hexes: Array[Dictionary] = []
var boss := {}
var shake_timer := 0.0
var egg_growth := 0.0
var time_ms := 0.0
var _boss_dialog_sent := false
var _first_enemy_seen := false
var _initial_dialog_sent := false
var _start_checkpoint := 0
## A "try again" restart (Main._start_level with retry): the level's dialog A doesn't replay.
var skip_start_dialog := false
var _prev_breathe := false
## Background (BackgroundData config). Empty = the level's own (bundled or "Use
## in game"); the level editor's test play sets the one being edited.
var background := {}
var _font: Font
var _shake := Vector2.ZERO

## An unrotated backdrop under the background (the corners while the view turns).
var _backdrop: Node2D
var _bg: Node2D
var _world: Node2D
## Screen-space veil over the world (the transformation's vignette, the maze's haze).
var _veil: Node2D
## On the veil: the transformation's follicle / yellow body and its captions (its own
## node, so it fades in over the world at the start: PREROD_HAND).
var _veil_body: Node2D
var _player_layer: Node2D
var _player_canvas: CanvasLayer
var hud: PlatformerHud
## CanvasLayer index of the HUD (the level editor raises it above its own UI).
var hud_layer := 6
## CanvasLayer of the player sprite. Above the dialog panels (layer 8), as in
## the web build, so Kyra sitting on a dialog box keeps her legs in front of it.
var player_layer := 9


## rows: level text rows. checkpoint: 0/1 = start, 2..4 = after minigame N,
## 5 = boss (level 2: the LH wave). lvl: 1 cave, 2 garden.
func setup(rows: PackedStringArray, checkpoint: int, lvl := 1) -> void:
	level = LevelData.build(rows, LevelData.ROW_H, Game.is_horizontal(lvl))
	level_h = level.height()
	level_w = level.width()
	level_id = lvl
	view_zoom = CLIMB_ZOOM if is_climb() else 1.0
	view_flip = 1.0 if is_pms() else 0.0
	wall_tops.clear()
	for r in level.walls:
		var top := LevelData.Plat.new()
		top.x = r.position.x
		top.y = r.position.y
		top.base_y = r.position.y
		top.w = r.size.x
		top.kind = "wall"
		wall_tops.append(top)
	if is_pms():
		deco = PmsMaze.deco_spots(level)
		wall_blobs = PmsMaze.merge_columns(level.walls)
	last_landing_y = level_h
	if is_climb():
		# The jackpot climb's E row is its top, not the old summit.
		for e in level.entities:
			if e.trigger_type == "summit":
				e.trigger_type = "climb_top"
			elif e.trigger_type == "dialog":
				# Dialog letters span their whole row here: she flies past them.
				e.x = 0
				e.w = level_w
	for e in level.entities:
		if e.trigger_type == "gate":
			e.base_x = e.x
			e.has_base = true
	_start_checkpoint = checkpoint
	_reset_boss()
	_place_at_checkpoint(checkpoint)
	if is_summit():
		# Icy Tower: the LH wave rises from the very start (slowly at first).
		start_wave(WAVE_START_SPEED, H)
		last_floor = floor_of(p.y + p.height)
	if is_climb():
		ticker.clear()
		ticker_queue.clear()
		_update_ticker(0.0)
	if is_pms():
		last_ground = Vector2(p.x, p.y)


func is_summit() -> bool:
	return level_id == 3


## The jackpot climb (level 3 of the game, id Game.CLIMB_ID): up with the board.
func is_climb() -> bool:
	return level_id == Game.CLIMB_ID


## Levels climbed upwards (the old summit and the jackpot climb): camera, background
## anchor and checkpoint search look below.
func is_up() -> bool:
	return is_summit() or is_climb()


func is_meadow() -> bool:
	return level_id == 2


## The PMS maze (level 4 of the game, id Game.PMS_ID): drawn upside down.
func is_pms() -> bool:
	return level_id == Game.PMS_ID


## The view's angle: view_flip turned into radians, plus the maze's slow sway and the
## transformation's wobble (the sway grows as her energy drops, see tired_k).
func view_angle() -> float:
	var a := PI * view_flip
	if is_pms():
		a += sin(time_ms / 2300.0) * PMS_SWAY * tired_k()
	a += sin(time_ms / 420.0) * 0.025 * _turning()
	return a


## 0..1..0 while the transformation turns the view (its wobble / melt).
func _turning() -> float:
	if prerod_t < 0:
		return 0.0
	return sin(PI * _pk(PREROD_T_PULL, PREROD_PULL))


## 0..1 through a part of the transformation (from its start, `dur` s long).
func _pk(from: float, dur: float) -> float:
	return clampf((prerod_t - from) / dur, 0, 1)


static func _smooth(k: float) -> float:
	return k * k * (3 - 2 * k)


## The transformation's phase now: "" (none), focus, egg, luteum, pull, iris, done.
func prerod_phase() -> String:
	if prerod_t < 0:
		return ""
	if prerod_t < PREROD_T_EGG:
		return "focus"
	if prerod_t < PREROD_T_LUTEUM:
		return "egg"
	if prerod_t < PREROD_T_PULL:
		return "luteum"
	if prerod_t < PREROD_T_IRIS:
		return "pull"
	if prerod_t < PREROD_T_END:
		return "iris"
	return "done"


func prerod_finished() -> bool:
	return _prerod_sent


## The extra zoom into the yellow body's opening while she is pulled in (the world too).
func _pull_zoom() -> float:
	return 1.0 + 0.5 * _smooth(_pk(PREROD_T_PULL, PREROD_PULL)) if prerod_t >= 0 else 1.0


## Kyra's size while she is pulled in (on screen, the zoom divided out) and her slow spin.
func _pull_scale() -> float:
	if prerod_t < PREROD_T_PULL:
		return 1.0
	return (1.0 - 0.85 * _smooth(clampf(_pk(PREROD_T_PULL, PREROD_PULL) / 0.85, 0, 1))) / _pull_zoom()


func _pull_spin() -> float:
	if prerod_t < PREROD_T_PULL:
		return 0.0
	var k := _pk(PREROD_T_PULL, PREROD_PULL)
	return 2.4 * k * k


## The visible area in world px (the screen / view_zoom).
func view_w() -> float:
	return W / view_zoom


func view_h() -> float:
	return H / view_zoom


## World y of a screen y (the HUD / board are drawn in screen space).
func world_y(screen_y: float) -> float:
	return camera_y + screen_y / view_zoom


## Places the drawn layers (background, world, player) for the camera, the zoom, the
## rotation and the shake: v = (world - camera) · zoom is the upright screen position, then
## screen = C + R(angle) · (melt ⊙ (v - C)) + shake, C = the screen centre (the PMS maze
## and the climb's end turn it; melt is the transformation's soft squash). The one place
## the view is set.
func _apply_view() -> void:
	var cam := Vector2(camera_x, camera_y)
	var a := view_angle()
	var tk := _turning()
	var melt := Vector2(1.0 + 0.035 * tk * sin(time_ms / 330.0), 1.0 - 0.035 * tk * sin(time_ms / 330.0))
	# Zooming into the yellow body's opening while she is pulled in.
	melt *= _pull_zoom()
	var c := Vector2(W, H) / 2
	var sc := melt * view_zoom
	_bg.position = c - (melt * c).rotated(a) + _shake
	_bg.rotation = a
	_bg.scale = melt * view_zoom
	_world.position = c - (melt * (cam * view_zoom + c)).rotated(a) + _shake
	_world.rotation = a
	_world.scale = sc
	_player_layer.position = c - (melt * (cam * view_zoom + c)).rotated(a) + (_shake if shake_timer > 0 else Vector2.ZERO)
	_player_layer.rotation = a
	_player_layer.scale = sc


## The transformation's clock (see PREROD_*): the casino winds down (wind), the sun opens,
## the egg leaves, the yellow body forms, Kyra is pulled into it while the view turns upside
## down (view_flip, ease-in-out) and zooms in; the HUD goes, the colours drain to dusk.
## In the maze: its warm start (warm_t).
func _update_view(dt: float) -> void:
	if warm_t >= 0:
		_update_warm(dt)
	if prerod_t < 0:
		return
	prerod_t += dt
	wind = clampf(prerod_t / PREROD_WIND, 0, 1)
	_light_t += dt * 1000.0 * (1.0 - 0.85 * wind)
	var k := _pk(PREROD_T_PULL, PREROD_PULL)
	view_flip = 0.5 - 0.5 * cos(PI * k)
	hud.modulate.a = 1.0 - _pk(1.0, 0.8)
	var tint := Color.WHITE.lerp(Color(0.8, 0.7, 0.88), wind)
	_bg.modulate = tint
	_world.modulate = tint
	_player_layer.modulate = Color(tint.r, tint.g, tint.b, _player_layer.modulate.a)
	if not egg_released and prerod_t >= PREROD_T_EGG + EGG_OUT:
		# Ovulation: the egg leaves the opened follicle.
		egg_released = true
		Audio.play_sfx("cink-08.wav", 0.55)
	if prerod_t >= PREROD_T_PULL:
		# Drawn into the yellow body: from where she stands to the opening (the screen's
		# middle, where the view turns), in a soft arc; she shrinks, spins and goes in.
		if _pull_from == Vector2.INF:
			_pull_from = p.center()
			Audio.play_sfx("breathok.wav", 0.4)
		var target := Vector2(camera_x, camera_y) + LUTEUM_C / view_zoom
		var kk := _smooth(clampf(k / 0.85, 0, 1))
		var c := _pull_from.lerp(target, kk) + Vector2(0, -70.0 * sin(PI * kk))
		p.x = c.x - p.width / 2
		p.y = c.y - p.height / 2
		p.vx = 0
		p.vy = 0
		_player_layer.modulate.a = 1.0 - _pk(PREROD_T_PULL + PREROD_PULL * 0.7, PREROD_PULL * 0.25)
	if prerod_t >= PREROD_T_END and not _prerod_sent:
		_prerod_sent = true
		prerod_turned.emit()


## The climb's end turns into the PMS maze (see PREROD_*): no control meanwhile; at its end
## prerod_turned is emitted and Main starts the maze from inside the yellow body.
func start_prerod() -> void:
	if prerod_t >= 0:
		return
	prerod_t = 0.0
	_prerod_sun0 = sun_screen()
	_light_t = time_ms
	hold_input = true
	thrusting = false
	board_talk = {}
	board_queue.clear()
	slot_spin = {}
	banner = {}
	climb_power.clear()


## The maze seen first from inside the yellow body: the opening clears (WARM_IRIS), Kyra
## appears with it, and the warm amber fades to the maze's dusk (WARM_FADE).
func start_warm() -> void:
	warm_t = 0.0
	warm = 1.0
	_update_view(0.0)
	_apply_view()


func _update_warm(dt: float) -> void:
	warm_t += dt
	warm = 1.0 - _smooth(clampf((warm_t - WARM_IRIS * 0.6) / WARM_FADE, 0, 1))
	var tint := Color.WHITE.lerp(WARM_TINT, warm)
	_bg.modulate = tint
	_world.modulate = tint
	# Kyra and the maze's HUD come in as the opening clears.
	var ik := _smooth(clampf(warm_t / WARM_IRIS, 0, 1))
	_player_layer.modulate = Color(tint.r, tint.g, tint.b, ik)
	hud.modulate.a = ik
	if warm <= 0.0:
		hud.modulate.a = 1.0
		warm_t = -1.0
		_bg.modulate = Color.WHITE
		_world.modulate = Color.WHITE
		_player_layer.modulate = Color.WHITE


## Fades the whole level (world, Kyra, HUD, veil: the CanvasLayers don't inherit modulate).
## hud_too = false: only the world and Kyra (the board is already there: the forest run's
## end turns the dialog box into it).
func set_fade(a: float, hud_too := true) -> void:
	modulate.a = a
	_player_layer.modulate.a = a
	if not hud_too:
		return
	hud.modulate.a = a if prerod_t < 0 else minf(a, hud.modulate.a)
	_veil.modulate.a = a


## The new phase: a big title (key) and a sub-line with the marquee bulbs blinking in
## (PhaseBoard). In the climb on its board (the ticker starts after it); in the cave and
## the PMS maze a board of its own where the dialog box is (PlatformerHud), and the level's
## first dialog waits for it. delay: seconds before it shows (a fade still running).
func announce_phase(key: String, sub := "", dur := PHASE_TIME, delay := 0.0, speaker := "Estrogenka") -> void:
	phase_note = PhaseBoard.note(key, sub, dur, delay)
	phase_speaker = speaker
	if delay <= 0.0:
		Audio.play_sfx("cink-11.wav", 0.5)


func phase_showing() -> bool:
	return not phase_note.is_empty()


## 0..1: the climb's counters (the spinner, the heart meter) come in after the announcement starts.
func counters_in() -> float:
	if phase_note.is_empty():
		return 1.0
	return clampf((float(phase_note.t) - 0.6) / 0.8, 0, 1)


## Behind the rotating background: dusk filling the screen's corners while it turns.
func _draw_backdrop() -> void:
	if view_flip <= 0.0 and prerod_t < 0 and not is_pms():
		return
	_backdrop.draw_rect(Rect2(-20, -20, W + 40, H + 40), Color("#2a2238"))


## Screen space over the world: the transformation's vignette, the maze's soft haze.
func _draw_veil() -> void:
	var screen := Rect2(0, 0, W, H)
	if prerod_t >= 0:
		# The world steps back, the follicle comes forward (in screen space, over the world;
		# Kyra's layer stays above it).
		var f := _smooth(_pk(0.0, PREROD_FOCUS))
		_veil.draw_rect(screen, Color(0.35, 0.22, 0.42, 0.16 * wind))
		_veil.draw_rect(screen, Color(0.09, 0.05, 0.14, 0.42 * f))
		Draw.vignette(_veil, screen, Color(0.12, 0.06, 0.18, 0.55 * f), 0.35)
	elif is_pms():
		Draw.vignette(_veil, screen, Color(0.14, 0.08, 0.2, 0.5 - 0.15 * rest_k), 0.4)
		if warm > 0:
			# Inside the yellow body: warm amber at first, then the maze's dusk.
			_veil.draw_rect(screen, Color(1, 0.62, 0.2, 0.2 * warm))
			Draw.vignette(_veil, screen, Color(0.8, 0.42, 0.1, 0.55 * warm), 0.35)
		if warm_t >= 0 and warm_t < WARM_IRIS:
			# Through the opening: its amber inside clears from the middle outwards.
			var ik := _smooth(warm_t / WARM_IRIS)
			var r_open := LUTEUM_R * LUTEUM_ZOOM * LUTEUM_HOLE * (1.0 + 1.5 * ik)
			draw_opening(_veil, LUTEUM_C, r_open, 720.0 * ik, 1.0)
	if sun_glow > 0:
		# The forest run's sun melts into the climb's morning light.
		var g := sun_glow * sun_glow * (3 - 2 * sun_glow)
		_veil.draw_rect(screen, Color(1, 0.84, 0.5, 0.22 * g))
		Draw.radial_glow(_veil, SUN_MELT_POS, 170.0 + 320.0 * (1.0 - g), Color(1, 0.82, 0.4, 0.8 * g), Color(1, 0.97, 0.82, 0.95 * g))


## The transformation's follicle / yellow body and captions, over the world: it fades in
## (PREROD_HAND) where the sky's sun is, so the sun comes forward without a cut.
func _draw_veil_body() -> void:
	if prerod_t < 0:
		return
	_veil_body.modulate.a = prerod_hand()
	_draw_prerod_body(_veil_body)
	_draw_prerod_caption(_veil_body)


## 0..1: the follicle on the veil has taken over from the sky's sun (PREROD_HAND).
func prerod_hand() -> float:
	return _smooth(_pk(0.0, PREROD_HAND)) if prerod_t >= 0 else 0.0


## Camera where the level starts (background layers are anchored to it).
func bg_origin() -> Vector2:
	return bg_origin_for(level_id, level_h)


## The visible world size of a level (the screen / its view zoom); the background panel previews with it.
static func view_size_for(id: int) -> Vector2:
	return Vector2(W, H) / (CLIMB_ZOOM if id == Game.CLIMB_ID else 1.0)


static func bg_origin_for(id: int, lh: float) -> Vector2:
	# The summit and the jackpot climb are climbed from the bottom.
	if id == Game.CLIMB_ID:
		return Vector2(0, maxf(0, lh - view_size_for(id).y))
	return Vector2(0, maxf(0, lh - H)) if id == 3 else Vector2.ZERO


## Snappier controls, coyote time, jump buffer and squash (levels 2 and 3).
func feel() -> bool:
	return level_id >= 2


## Level 3: floor index of a y (feet) — 0 at the bottom row.
func floor_of(feet_y: float) -> int:
	return maxi(0, int((level_h - feet_y) / LevelData.ROW_H + 0.5))


## Level 2 unlocks from the dew vessel: "thread" (25 %, longer), "pull" (50 %,
## faster), "shield" (75 %, the first shadow hit while focusing is absorbed).
func water_unlock(name: String) -> bool:
	return Game.water >= {"thread": 25, "pull": 50, "shield": 75}[name]


func _max_jumps() -> int:
	return 3 if is_climb() and climb_power.has("triple") else 2


func thread_range() -> float:
	return THREAD_RANGE_LONG if water_unlock("thread") else THREAD_RANGE


## Trigger kinds that mark progress in this level (checkpoint 2..5).
func progress_kinds() -> Array:
	return LevelData.PROGRESS.get(level_id, LevelData.PROGRESS[1])


## Earned power-ups (level 2).
func has_upgrade(name: String) -> bool:
	return Game.upgrades.has(name)


func _ready() -> void:
	_font = Text.font_bold
	_backdrop = Node2D.new()
	_bg = Node2D.new()
	_world = Node2D.new()
	_player_layer = Node2D.new()
	add_child(_backdrop)
	add_child(_bg)
	add_child(_world)
	var pl := CanvasLayer.new()
	_player_canvas = pl
	pl.layer = player_layer
	add_child(pl)
	pl.add_child(_player_layer)
	_backdrop.draw.connect(_draw_backdrop)
	_bg.draw.connect(_draw_bg)
	_world.draw.connect(_draw_world)
	_player_layer.draw.connect(_draw_player)
	var layer := CanvasLayer.new()
	layer.layer = hud_layer
	add_child(layer)
	_veil = Node2D.new()
	_veil.draw.connect(_draw_veil)
	layer.add_child(_veil)
	# The maze's darkness: over the world and the veil's haze, under the HUD (and Kyra's layer).
	_dark = ColorRect.new()
	_dark.size = Vector2(W, H)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = DARK_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_dark.material = mat
	_dark.visible = false
	_veil.add_child(_dark)
	_veil_body = Node2D.new()
	_veil_body.draw.connect(_draw_veil_body)
	_veil.add_child(_veil_body)
	hud = PlatformerHud.new()
	hud.platformer = self
	layer.add_child(hud)
	if level == null:
		setup(Game.current_level_rows(), 0)


func spawn_point() -> Vector2:
	return level.spawn if level.has_spawn() else Vector2(W / 2 - 15, 100)


func _place_at_checkpoint(cp: int) -> void:
	p.vx = 0
	p.vy = 0
	if cp <= 1:
		var s := spawn_point()
		p.x = s.x
		p.y = s.y
		camera_y = maxf(0, s.y - H / 2)
		if is_climb():
			_settle_on_ground()
			_board_camera()
		if level.horizontal:
			camera_y = 0
			camera_x = clampf(s.x - W * 0.4, 0, maxf(0, level_w - W))
			last_ground = s
		return
	if cp >= 5 and not is_up() and not level.horizontal:
		return
	var kinds := progress_kinds()
	var idx := mini(cp, 5) - 2
	var want: String = kinds[idx]
	# A repeated kind (the climb's jackpot rows): the n-th of them in level order.
	var nth := kinds.slice(0, idx).count(want)
	var found: Array[LevelData.Ent] = []
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == want:
			found.append(e)
	found.sort_custom(func(a: LevelData.Ent, b: LevelData.Ent) -> bool:
		return a.x < b.x if level.horizontal else (a.y > b.y if is_up() else a.y < b.y))
	if found.is_empty():
		return
	var e: LevelData.Ent = found[mini(nth, found.size() - 1)]
	# The wave / gate / top checkpoints re-arm; minigame checkpoints are done.
	e.collected = not want in ["wave", "gate", "climb_top"]
	_stand_at_trigger(e)
	# Earlier triggers are done too (above in the cave, below in upward levels, left in the meadow).
	for e2 in level.entities:
		var earlier: bool = e2.x < e.x if level.horizontal else (e2.y > e.y if is_up() else e2.y < e.y)
		if e2.type == "trigger" and earlier and e2.trigger_type in kinds.slice(0, 3):
			e2.collected = true


func _reset_boss() -> void:
	boss = {
		"active": false, "x": W / 2, "y": 3800.0, "vx": 1.5, "vy": -1.5, "hp": 8, "max_hp": 8,
		"hit_timer": 0.0, "slow_timer": 0.0, "radius": 40.0, "lost": false, "spike_order": [],
		"defeated_timer": 0.0, "wait": 0.0,
	}


## The cave's rest points (map marker R) she has passed: the y of the lowest one, -1 = none.
func last_rest_y() -> float:
	var y := -1.0
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == "rest" and e.collected:
			y = maxf(y, e.y)
	return y


## A "try again" at a rest point (after _place_at_checkpoint): she stands at the rest row
## at `y`, it and the rest rows above it are done. False if the map has none there.
func place_at_rest(y: float) -> bool:
	var at: LevelData.Ent = null
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == "rest" and e.y <= y + 1 and (at == null or e.y > at.y):
			at = e
	if at == null:
		return false
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == "rest" and e.y <= at.y:
			e.collected = true
	p.vx = 0
	p.vy = 0
	_stand_at_trigger(at)
	return true


## Starts the boss arena (from the trigger, or from Main for retry / dev skip).
## The iron is the floor: at least 10 hexes, and she has as much iron as there is floor.
func start_boss(iron: int) -> void:
	p.held_by_cramp = -1
	p.is_recharging = false
	p.is_dead = false
	Audio.stop_loop("krcloop.wav")
	boss.active = true
	boss.hp = 20
	boss.max_hp = 20
	boss.x = W / 2
	boss.y = level_h + 400
	boss.vx = 3.5
	boss.vy = -3.5
	boss.radius = 60.0
	boss.lost = false
	boss.defeated_timer = 0.0
	boss.hit_timer = 0.0
	egg_growth = 0
	_boss_dialog_sent = false
	var order := range(20)
	order.shuffle()
	boss.spike_order = order
	p.breath_charges = 1
	p.x = W / 2
	p.y = level_h + 100
	p.vy = 0
	camera_y = level_h
	hexes.clear()
	var total := maxi(10, iron)
	var left := total
	var row := 0
	while left > 0:
		var n := mini(left, 20)
		var x0 := W / 2 - n * HEX_W / 2 + HEX_W / 2
		for i in n:
			hexes.append({
				"x": x0 + i * HEX_W + (HEX_W / 2 if row % 2 == 1 else 0.0),
				"y": level_h + 200 + row * HEX_H,
				"active": true,
			})
		left -= n
		row += 1
	for e in level.entities:
		if e.type == "iron" or e.trigger_type == "end":
			e.collected = false
	Game.iron = total
	Game.boss_iron = total


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	time_ms += dt * 1000.0
	if exit_fall:
		# Falling out of the arena; the camera goes down with her.
		var f60 := dt * 60.0
		_exit_t += dt
		p.vy = minf(p.vy + 0.55 * f60, 18.0)
		p.y += p.vy * f60
		var mk := clampf(_exit_t / EXIT_TO_MID, 0, 1)
		p.x = lerpf(_exit_x0, W / 2 - p.width / 2, mk * mk * (3 - 2 * mk))
		if p.vy > 0:
			camera_y = lerpf(camera_y, p.y - H * 0.4, 1.0 - pow(0.88, f60))
	if is_climb() or not dialog_open:
		# (Outside the climb the board sits where the dialog box is: it waits for a dialog.)
		phase_note = PhaseBoard.tick(phase_note, dt)
	sun_glow = maxf(0, sun_glow - dt / SUN_MELT)
	if active:
		_update(dt)
		if active and not _initial_dialog_sent and _start_checkpoint <= 1 and not is_climb() and not is_pms() and phase_note.is_empty():
			_initial_dialog_sent = true
			if skip_start_dialog:
				return
			get_tree().create_timer(0.3).timeout.connect(_send_initial_dialog)
	_shake = Vector2.ZERO
	if shake_timer > 0:
		var s := shake_timer * 20
		_shake = Vector2((randf() - 0.5) * s, (randf() - 0.5) * s)
	elif p.held_by_cramp != -1:
		_shake = Vector2((randf() - 0.5) * 4, (randf() - 0.5) * 4)
	_update_view(dt)
	_apply_view()
	_update_dark()
	_backdrop.queue_redraw()
	_bg.queue_redraw()
	_world.queue_redraw()
	_player_layer.queue_redraw()
	_veil.queue_redraw()
	_veil_body.queue_redraw()
	hud.queue_redraw()


func _send_initial_dialog() -> void:
	# Every level starts with its dialog A (1A, 3A, MA).
	trigger.emit("dialog_a")


func _clear_breath_failed() -> void:
	p.breath_failed = false


func _clear_breath_success() -> void:
	p.breath_success = false


# --- input helpers -------------------------------------------------------------

## Debug: put the player just above a trigger ("mg2", "mg3", "mg4", "end").
func teleport_to_trigger(kind: String) -> void:
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == kind:
			e.collected = false
			if is_up() or level.horizontal:
				_stand_at_trigger(e)
			else:
				p.x = W / 2 - 15
				p.y = e.y - 120
				camera_y = maxf(0, p.y - H / 2)
			p.vy = 0
			return


## Lands the player on the nearest platform below their feet (same column).
func _settle_on_ground() -> void:
	var best: LevelData.Plat = null
	for pl in level.platforms + wall_tops:
		if not pl.solid() or pl.x > p.x + p.width or pl.x + pl.w < p.x:
			continue
		if pl.base_y >= p.y + p.height - 30 and (best == null or pl.base_y < best.base_y):
			best = pl
	if best:
		p.y = best.base_y - p.height
	p.vy = 0
	p.is_grounded = true
	p.was_grounded = true
	p.jumps_left = 2
	p.is_sitting = false


## Puts the player in a trigger's row: in the garden on the nearest platform at
## or below it near the middle (the row's own platform), in the cave just inside it.
func _stand_at_trigger(e: LevelData.Ent) -> void:
	p.x = level_w / 2 - 15
	p.y = e.y + 100 - 30
	if level.horizontal:
		# The trigger column: stand on the highest ground there.
		var cx := e.x + e.w / 2
		p.x = cx - p.width / 2
		var best: LevelData.Plat = null
		for pl in level.platforms:
			if pl.x <= cx + 40 and pl.x + pl.w >= cx - 40 and (level.water_top < 0 or pl.base_y < level.water_top) and (best == null or pl.base_y < best.base_y):
				best = pl
		p.y = (best.base_y - p.height) if best else 200.0
		camera_x = clampf(p.x - W * 0.4, 0, maxf(0, level_w - W))
		camera_y = 0
		last_ground = Vector2(p.x, p.y)
		return
	if is_up():
		# The climb's top: a few rows below it, so she isn't on the goal already.
		var below := 340.0 if e.trigger_type == "climb_top" else 99.0
		var best: LevelData.Plat = null
		for pl in level.platforms:
			# The old summit: the row's own platform near the middle; the climb: the
			# nearest platform below, wherever it is.
			var near_mid := pl.x <= level_w / 2 + 60 and pl.x + pl.w >= level_w / 2 - 60
			if pl.base_y >= e.y + below and (near_mid or is_climb()) and (best == null or pl.base_y < best.base_y):
				best = pl
		if best:
			p.x = clampf(level_w / 2 - 15, best.x + 4, best.x + best.w - p.width - 4)
			p.y = best.base_y - p.height
	camera_y = maxf(0, p.y - H / 2)
	if is_climb():
		_board_camera()


## The maze with a dialog (node or panel) open: Kyra stays where she is until it is closed
## (a press meanwhile nudges the dialog's button: dialog_nudge).
func dialog_frozen() -> bool:
	return is_pms() and dialog_open


const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "breathe"]


## A stick event: true when it newly pushes a movement action (a held stick sends an event
## for every small change, all of them "pressed"; it must come back to the centre first).
func _stick_edge(event: InputEventJoypadMotion) -> bool:
	var edge := false
	for a in MOVE_ACTIONS:
		if not event.is_action(a):
			continue
		if event.is_action_pressed(a):
			if not _stick_held.get(a, false):
				edge = true
			_stick_held[a] = true
		elif absf(event.axis_value) < STICK_REST:
			_stick_held[a] = false
	return edge


## A movement / jump / rest press (not the keys the dialog itself takes: Enter and the
## gamepad's four face buttons, also when the dialog's debounce let one through).
func _is_move_press(event: InputEvent, stick_edge := false) -> bool:
	if event.is_echo():
		return false
	if event is InputEventJoypadMotion:
		return stick_edge
	if event is InputEventJoypadButton and event.button_index <= JOY_BUTTON_Y:
		return false
	for a in MOVE_ACTIONS:
		if event.is_action_pressed(a):
			return true
	return false


func _can_jump_in_dialog() -> bool:
	# The climb's dialogs sit on the board: she keeps jumping while they talk.
	return not dialog_open or active_dialog_id in ["1A", "1B", "3A", "MA", "SA"] or (is_climb() and active_dialog_id.begins_with("3"))


## Jump impulse with the level-2 power-ups (jump: +15 %, double: second jump +20 %).
func _jump_force() -> float:
	var f := JUMP_FORCE
	if has_upgrade("jump"):
		f *= 1.15
	if has_upgrade("double") and p.jumps_left == 1:
		f *= 1.2
	if is_climb() and climb_power.has("super_jump"):
		f *= 1.3
	if is_summit():
		# Icy Tower: a running start turns into height.
		var run := clampf(absf(p.vx) / (MAX_SPEED * SUMMIT_SPEED), 0, 1)
		f *= 1.0 + MOMENTUM_JUMP * run + 0.02 * mini(combo, 5)
	return f


func _do_jump() -> void:
	Audio.jump_sound(p.jumps_left == 1)
	p.vy = _jump_force() * (SWIM_JUMP if in_water else 1.0)
	p.jumps_left -= 1
	p.jumped_from_ground = p.is_grounded or p.coyote > 0
	p.coyote = 0
	p.is_grounded = false
	p.is_sitting = false
	_fuel_armed = true
	if feel():
		p.squash = -0.6
	if focus:
		# Jumping breaks the focus (the seed escapes, the shadows fade).
		end_focus()


func _unhandled_input(event: InputEvent) -> void:
	# (The stick's state is followed all the time, so one held when a dialog opens is no press.)
	var stick_edge := false
	if event is InputEventJoypadMotion:
		stick_edge = _stick_edge(event)
	if not active:
		return
	if dialog_frozen():
		# "Click me first": the dialog's button shakes (also at the door's 4E, under hold_input).
		if _is_move_press(event, stick_edge):
			dialog_nudge.emit()
		return
	if hold_input:
		return
	if is_meadow():
		if event is InputEventMouseMotion:
			aim = event.position + Vector2(camera_x, camera_y)
			aim_mode = "mouse"
		elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
			if event.axis == JOY_AXIS_RIGHT_X: _stick.x = event.axis_value
			else: _stick.y = event.axis_value
			if _stick.length() > 0.3:
				aim_mode = "stick"
		if event.is_action_pressed("focus") and not event.is_echo():
			if event is InputEventKey:
				aim_mode = "keys"
			begin_focus()
		elif event.is_action_released("focus"):
			end_focus()
	if event.is_action_released("jump") and thrusting:
		# Let go of the thrusters: they cut out and she falls (no coasting up).
		thrusting = false
		p.vy = maxf(p.vy, -2.0)
	elif event.is_action_released("jump") and feel() and p.vy < -4 and not in_water and boost_t <= 0:
		# Variable jump height: let go early for a short hop.
		p.vy *= 0.55
	if event.is_action_pressed("jump") and not event.is_echo():
		if p.is_recharging or meadow_end > 0 or resting:
			return
		if in_water and p.y + p.height / 2 > level.water_top + 60:
			# Too deep to jump out: swim up first.
			return
		if p.jumps_left > 0 and not boss.lost and not wave.lost and _can_jump_in_dialog():
			_do_jump()
		elif feel() and not boss.lost and not wave.lost and _can_jump_in_dialog() and not on_wall:
			# Pressed a moment too early: jump as soon as we land.
			p.jump_buffer = JUMP_BUFFER
		elif on_wall and not wave.lost and not dialog_open:
			# Wall jump (level 3): kick off the side wall.
			Audio.jump_sound(true)
			p.vy = _jump_force()
			p.vx = WALL_KICK if p.x <= 0 else -WALL_KICK
			p.facing_right = p.x <= 0
			p.jumps_left = 1
			p.is_grounded = false
	elif event.is_action_pressed("run") and not event.is_echo() and has_upgrade("dash"):
		# Dash (level 2): a short burst in the facing direction.
		if p.dash_cooldown <= 0 and p.dash_timer <= 0 and not dialog_open and not p.is_recharging and not p.is_dead and not wave.lost:
			p.dash_timer = DASH_TIME
			p.dash_cooldown = DASH_COOLDOWN
			p.slow_timer = 0
			Audio.play_sfx("breathoff.wav", 0.4)
	elif event.is_action_pressed("breathe") and not event.is_echo():
		if is_climb():
			# The climb: Shift / B spends hearts on the heart boost.
			heart_boost()
			return
		if dialog_open or is_pms() or (is_summit() and has_upgrade("dash")):
			return
		# Toggle the recharge sequence when out of breath charges.
		if p.breath_charges == 0 and Game.has_breathing and p.breathing_cooldown <= 0:
			if p.held_by_cramp != -1 and p.is_recharging:
				return
			p.is_recharging = not p.is_recharging
			if not p.is_recharging:
				p.breath_index = 0
				p.breath_timer = 0


# --- update -------------------------------------------------------------------

func _die(boss_variant: bool) -> void:
	# (Already down, e.g. fell into the depths: one game over, no second panel.)
	if p.is_dead:
		return
	p.is_recharging = false
	p.breath_charges = 0
	p.breath_timer = 0
	p.breath_index = 0
	p.breath_error_timer = 0
	p.held_by_cramp = -1
	Audio.stop_loop("krcloop.wav")
	Audio.set_bgm_volume(0.5)
	p.is_sitting = true
	p.is_dead = true
	p.vx = 0
	particles.clear()
	shake_timer = 0
	Game.iron = 0
	trigger.emit("game_over_boss" if boss_variant else "game_over")


func _spray_nuts(count: int, spread := 12.0, up := 10.0, base := 5.0) -> void:
	for i in count:
		particles.append({
			"x": p.x + p.width / 2, "y": p.y + p.height / 2,
			"vx": (randf() - 0.5) * spread, "vy": -randf() * up - base,
			"rot": randf() * TAU, "rot_speed": (randf() - 0.5) * 0.5, "type": "nut",
		})


## Knock-back hit used by spikes and (without breathing) enemies.
func _hurt(from_x: float) -> void:
	p.hit_timer = 1
	p.vy = -8
	p.vx = -10.0 if p.x < from_x else 10.0
	p.is_grounded = false
	if is_climb():
		# No losses in the climb: just a knock.
		Audio.play_sfx("au%d.wav" % randi_range(1, 5), 0.5)
		return
	# The iron rule: a hit costs 3–5 iron, down to 0; only a hit with none left is too much
	# (game over → Main restarts at the last checkpoint).
	if Game.iron <= 0:
		_die(boss.active)
		return
	var lost := mini(Game.iron, randi_range(3, 5))
	Game.iron -= lost
	Audio.nut_sound()
	_spray_nuts(lost)


## Developer shortcut: the Big Cramp is beaten at once.
func dev_defeat_boss() -> void:
	if boss.active and boss.defeated_timer == 0:
		boss.hp = 0
		boss.defeated_timer = 0.01


## Kyra drops out of the bottom of the screen (level 1 is over).
func start_exit_fall() -> void:
	if exit_fall:
		return
	exit_fall = true
	_exit_x0 = p.x
	_exit_t = 0.0
	p.held_by_cramp = -1
	p.is_recharging = false
	# The nuts are gone from under her: she hops up and over to the middle of
	# the screen, then drops (towards us, growing), right where the forest run
	# catches her.
	p.vy = EXIT_HOP
	p.vx = 0
	p.is_grounded = false


func _exit_grow() -> float:
	return 1.0 + EXIT_GROW * clampf((_exit_t - 0.3) / 1.0, 0, 1)


## Where Kyra is on screen while she falls out (her feet) and how tall she is
## drawn (px): the forest run goes on from there (ForestRunner.handoff).
func exit_visual() -> Array:
	var k := PlayerArt.scale * _exit_grow()
	var f := Vector2(p.x + p.width / 2, p.y + p.height / 2 + 30.0 * k)
	return [Vector2(f.x - camera_x, f.y - camera_y), PlayerArt.SPRITE_H * k]


## She is out of sight (below the screen).
func exit_fall_done() -> bool:
	return exit_fall and p.y > camera_y + H + 40


func _update(dt: float) -> void:
	if exit_fall:
		# Kyra is gone (no control, the camera stays); the nuts keep forming
		# their ring around the grain.
		var e60 := dt * 60.0
		_update_particles(dt, e60)
		if boss.active:
			_update_boss(dt, e60)
		return
	var d60 := dt * 60.0
	hud.breath_error = false
	if shake_timer > 0:
		shake_timer -= dt

	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	if scripted_walk > 0:
		scripted_walk -= dt
		left = false
		right = true
	if corridor_t > 0:
		corridor_t += dt
	if walk_to_x >= 0:
		var d := walk_to_x - (p.x + p.width / 2)
		left = d < -4
		right = d > 4
		if not (left or right):
			p.facing_right = true
	if meadow_end > 0 or hold_input:
		left = false
		right = false
	# The maze: a dialog freezes her (she falls away from the dialog box there, so she can't
	# sit on it): no walking, no drifting; a fall ends on the next ground.
	var frozen := dialog_frozen()
	if frozen:
		left = false
		right = false
		p.vx = 0
		p.jump_buffer = 0
	var up := Input.is_action_pressed("move_up") and not hold_input
	var down := Input.is_action_pressed("move_down") and not hold_input
	# Shift is the level's one ability: on the summit, once the dash is earned,
	# it dashes instead of breathing.
	var breathe := Input.is_action_pressed("breathe") and not (is_summit() and has_upgrade("dash")) and not is_climb() and not hold_input
	var breathe_pressed := breathe and not _prev_breathe
	_prev_breathe = breathe
	if is_pms():
		# The maze: Shift is rest (she sits and stays put while it is held).
		_update_rest(dt, breathe)
		if resting:
			left = false
			right = false

	# --- horizontal movement
	var max_speed := MAX_SPEED
	if p.slow_timer > 0:
		p.slow_timer -= dt
		max_speed *= 0.45
	if in_water:
		# Swimming: slow, and the current always carries you along.
		max_speed *= SWIM_SPEED
	var accel := ACCEL
	var friction := FRICTION
	if feel():
		accel = FEEL_ACCEL
		friction = FEEL_FRICTION
	if is_summit():
		max_speed *= SUMMIT_SPEED * (1.0 + 0.03 * mini(combo, 6))
		accel *= SUMMIT_ACCEL
	if in_water:
		accel *= 0.6
	if p.coyote > 0:
		p.coyote -= dt
		if p.coyote <= 0 and not p.is_grounded:
			p.jumps_left = mini(p.jumps_left, _max_jumps() - 1)
	if p.jump_buffer > 0:
		p.jump_buffer -= dt
	if p.squash != 0:
		p.squash = move_toward(p.squash, 0, dt * 4)
	if p.dash_cooldown > 0:
		p.dash_cooldown -= dt
	if p.invuln_timer > 0:
		p.invuln_timer -= dt
	if p.dash_timer > 0:
		p.dash_timer -= dt
		p.vx = DASH_SPEED if p.facing_right else -DASH_SPEED
		max_speed = DASH_SPEED
		particles.append({"x": p.x + p.width / 2, "y": p.y + p.height / 2 + (randf() - 0.5) * 30,
			"vx": -p.vx * 0.1, "vy": (randf() - 0.5) * 2, "rot": 0.0, "rot_speed": 0.0, "type": "dash", "life": 0.35, "max_life": 0.35})
	elif p.hit_timer > 0 or boss.lost or wave.lost or p.held_by_cramp != -1 or p.is_dead or p.is_recharging:
		if p.hit_timer > 0:
			p.hit_timer -= dt
		p.vx = 0
	elif right:
		p.vx += accel * d60
		p.facing_right = true
	elif left:
		p.vx -= accel * d60
		p.facing_right = false
	else:
		p.vx *= pow(friction, d60)
	if p.vx > max_speed: p.vx = maxf(max_speed, p.vx - accel * d60)
	if p.vx < -max_speed: p.vx = minf(-max_speed, p.vx + accel * d60)
	if absf(p.vx) < 0.1: p.vx = 0
	var prev_x := p.x
	p.x += p.vx * d60
	if in_water:
		p.x -= CURRENT * d60
	var hit_wall := p.x < 0 or p.x > level_w - p.width
	p.x = clampf(p.x, 0, level_w - p.width)
	if not level.walls.is_empty():
		_walls_x(prev_x)
	# Level 3: the side walls bounce you back (Icy Tower) and let you kick off.
	on_wall = is_summit() and not p.is_grounded and (p.x <= 0 or p.x >= level_w - p.width) and p.held_by_cramp == -1 and not p.is_recharging
	if is_summit() and hit_wall and absf(p.vx) > 2:
		p.vx = -p.vx * WALL_BOUNCE
		p.facing_right = p.vx > 0
		Audio.footstep(0.4)

	for pl in level.platforms:
		# Platforms bob (not in the maze: its blobs only look soft, the rects stay put).
		pl.y = pl.base_y + (0.0 if is_pms() else sin(time_ms / 500.0 + pl.x) * 5)
		if pl.regrow > 0:
			pl.regrow -= dt
			if pl.regrow <= 0:
				pl.pop_timer = 0

	# --- breathing (the maze has its light instead: energy, rest, the unreliable gauge)
	if is_pms():
		var moving := left or right or absf(p.vx) > 0.4 or not p.is_grounded
		_update_light(dt, moving)
		_update_fog(dt)
		if door_open > 0:
			door_open += dt
	elif Game.has_breathing:
		if breathe_pressed and p.breath_charges > 0 and p.breathing_cooldown <= 0 and not dialog_open:
			p.is_breathing = 40
			p.breath_charges -= 1
			p.breathing_cooldown = 0.5
			p.has_used_breath = true
		if p.breathing_cooldown > 0:
			p.breathing_cooldown -= dt
		if not (p.breath_charges > 0 and p.held_by_cramp == -1):
			if p.is_recharging and p.breathing_cooldown <= 0:
				_update_recharge(dt, up, down)
		if p.is_breathing > 0:
			p.is_breathing = maxf(0, p.is_breathing - dt * 80)

	# --- gravity
	if p.held_by_cramp != -1:
		p.vx = 0
		p.vy = minf(p.vy + GRAVITY * d60, MAX_FALL)
		p.cramp_drain_timer += dt
		if p.cramp_drain_timer >= 1.5:
			p.cramp_drain_timer = 0
			# The cramp takes a nut now and then while it holds her, down to 0; it never kills
			# (only being grabbed with no iron at all does: _update_enemy).
			if Game.iron > 0:
				Game.iron -= 1
				Audio.nut_sound()
				_spray_nuts(1)
	elif p.dash_timer > 0:
		p.vy = 0
	elif in_water:
		# Buoyancy: float with the head above the surface; ↑/↓ swim a little.
		var target := level.water_top + 30 - p.height / 2
		p.vy += (target - p.y) * 0.02 * d60
		if up: p.vy -= 0.25 * d60
		if down: p.vy += 0.25 * d60
		p.vy *= pow(0.85, d60)
	else:
		p.vy = minf(p.vy + GRAVITY * d60, MAX_FALL)
		if is_climb():
			_update_fuel(dt, d60)

	var prev_bottom := p.y + p.height - p.vy * d60
	p.y += p.vy * d60
	if is_climb() and p.y < 0:
		# The level's top is a ceiling (a boost / the thrusters never take her off it).
		p.y = 0
		p.vy = maxf(p.vy, 0.0)
	var grounded := false
	var solids: Array = [] if hide_platforms else level.platforms.duplicate()
	if not hide_platforms:
		solids.append_array(wall_tops)
	if boss.active and boss.defeated_timer > 0:
		var rise := maxf(0, 40 - boss.defeated_timer * 40)
		var floor_pl := LevelData.Plat.new()
		floor_pl.x = 0
		floor_pl.y = camera_y + H - 40 + rise
		floor_pl.w = W
		floor_pl.h = 40
		solids.append(floor_pl)
	p.is_hanging = false
	var stood_on: LevelData.Plat = null
	for pl in solids:
		if not pl.solid():
			continue
		if p.vy >= 0 and prev_bottom <= pl.y + 20 and p.y + p.height >= pl.y - 10 and p.x + p.width > pl.x and p.x < pl.x + pl.w:
			p.y = pl.y - p.height
			p.vy = 0
			grounded = true
			p.jumps_left = _max_jumps()
			stood_on = pl
	if not level.walls.is_empty():
		_walls_y()
	if stood_on != null:
		last_stand_y = stood_on.y
		_fuel_armed = false
		if is_pms():
			last_ground = Vector2(p.x, p.y)
	for pl in level.platforms:
		if pl.kind != "pop" or pl.regrow > 0:
			continue
		if pl == stood_on:
			pl.pop_timer += dt
			if pl.pop_timer >= POP_AFTER:
				_pop_bubble(pl)
		else:
			pl.pop_timer = maxf(0, pl.pop_timer - dt * 2)
	if boss.active:
		for hx in hexes:
			if not hx.active:
				continue
			var top: float = hx.y - HEX_H / 2
			if p.vy >= 0 and prev_bottom <= top + 20 and p.y + p.height >= top - 10 and p.x + p.width > hx.x - HEX_W / 2 and p.x < hx.x + HEX_W / 2:
				p.y = top - p.height
				p.vy = 0
				grounded = true
				p.jumps_left = 2
	var on_dialog_floor := false
	# The top of the dialog box (and in the climb the board, always) is a floor.
	if (dialog_open or boss.lost or is_climb()) and not level.horizontal and not is_pms():
		var fy := board_y()
		if p.vy >= 0 and prev_bottom <= fy + 20 and p.y + p.height >= fy - 10:
			p.y = fy - p.height
			p.vy = 0
			grounded = true
			on_dialog_floor = true
			p.jumps_left = _max_jumps()
		elif is_climb() and p.y + p.height > fy:
			# The rising board pushes her up; she never ends up below it.
			p.y = fy - p.height
			if p.vy >= 0:
				p.vy = 0
				grounded = true
				on_dialog_floor = true
				p.jumps_left = _max_jumps()
	if is_climb():
		# Landing on the board (or the board reaching her feet) is a catch.
		if on_dialog_floor and not on_board and not climb_won:
			_caught()
		on_board = on_dialog_floor
	p.is_grounded = grounded
	if feel() and p.was_grounded and not grounded and not p.jumped_from_ground and p.vy >= 0 and not in_water:
		# Walked off an edge: a moment of coyote time keeps the ground jump.
		p.coyote = COYOTE
	if grounded:
		p.jumped_from_ground = false
	if p.is_grounded and not p.was_grounded and p.held_by_cramp == -1 and not p.is_recharging:
		Audio.footstep(0.8)
		if feel():
			p.squash = 0.8
		if is_summit() and stood_on != null:
			# Icy Tower combo: jumps that clear two or more floors chain up.
			var fl := floor_of(stood_on.base_y)
			var gained := fl - last_floor
			if gained >= 2:
				combo += gained
				combo_flash = 0.9
				Audio.play_sfx("cink-%02d.wav" % (1 + mini(combo, 10)), 0.4)
			else:
				combo = 0
			last_floor = fl
		if p.jump_buffer > 0 and feel():
			p.jump_buffer = 0
			_do_jump()
	if is_summit():
		floor_now = floor_of(p.y + p.height)
		best_floor = maxi(best_floor, last_floor)
		if combo > 0 and floor_now < last_floor - 2:
			# Fell back down: the chain is broken.
			combo = 0
	if combo_flash > 0:
		combo_flash -= dt
	p.was_grounded = p.is_grounded
	if p.is_recharging:
		p.anim_progress = 0
	else:
		p.step_animation(d60)
	p.is_sitting = p.is_dead or (p.is_recharging and p.held_by_cramp == -1) or (on_dialog_floor and absf(p.vx) < 0.1 and p.is_grounded) or resting

	if level.horizontal:
		_update_meadow(dt, d60)
	# --- camera (the summit is climbed, so keep more of the screen above the player)
	if is_climb():
		# (Still while she is pulled into the yellow body.)
		if prerod_t < PREROD_T_PULL:
			_climb_camera(dt, d60)
		if on_board and p.vy >= 0 and prerod_t < PREROD_T_PULL:
			# The board rose this frame: she rides on it (no sinking into its edge).
			p.y = board_y() - p.height
	else:
		_camera(dt, d60, down)

	_update_entities(dt, d60)
	_update_particles(dt, d60)
	if is_climb():
		_update_climb(dt, d60)
	if boss.active:
		_update_boss(dt, d60)
	if wave.active:
		_update_wave(dt, d60)
	if summit_timer > 0:
		summit_timer += dt


## The maze's camera: she is kept a little above the middle of the (upright) view, and always between the
## HUD and the dialog box on the rotated screen, at the map's first and last rows too.
func _pms_camera(dt: float, d60: float, down: bool) -> void:
	# Holding down while standing: the look-down pose and a peek ahead (not in a dialog / resting).
	if down and p.is_grounded and not p.is_sitting and absf(p.vx) < 0.5 and not dialog_open and not resting and not hold_input:
		p.look_down_timer += dt
	else:
		p.look_down_timer = 0
	var want := 0.0
	if p.look_down_timer > 0.3:
		want = minf(PMS_PEEK, (p.look_down_timer - 0.3) * 400)
	var k := 0.15 if p.vy > 5 else 0.1
	var e := 1.0 - pow(1.0 - k, d60)
	pms_peek += (want - pms_peek) * e
	if want == 0.0 and pms_peek < 0.5:
		pms_peek = 0.0
	var target := p.y - H * PMS_VIEW_Y + pms_peek
	camera_y += (target - camera_y) * e
	camera_y = pms_camera_clamp(camera_y, pms_peek)
	if p.y > level_h + 200 or p.y < -400:
		# Out of the maze (it is closed, but just in case): back where she last stood.
		p.x = last_ground.x
		p.y = last_ground.y
		p.vx = 0
		p.vy = 0


## A camera y that keeps her between the HUD and the dialog box (upright view: her top at
## least PMS_BOTTOM from its top, her feet at least PMS_TOP from its bottom).
## A peek (pms_peek) lets her nearer the dialog box's place, down to PMS_PEEK_EDGE.
func pms_camera_clamp(cy: float, peek := 0.0) -> float:
	cy = clampf(cy, p.y + p.height - (H - PMS_TOP), p.y - maxf(PMS_PEEK_EDGE, PMS_BOTTOM - peek))
	return clampf(cy, -PMS_OVER, level_h)


func _camera(dt: float, d60: float, down: bool) -> void:
	if is_pms():
		_pms_camera(dt, d60, down)
		return
	var target := p.y - (H / 2 if is_up() else H / 3)
	if down and p.is_grounded and not p.is_sitting and absf(p.vx) < 0.5 and not p.is_recharging:
		p.look_down_timer += dt
	else:
		p.look_down_timer = 0
	if p.look_down_timer > 0.3:
		target += minf(300, (p.look_down_timer - 0.3) * 400)
	if dialog_open and target > camera_y:
		target = camera_y
	if boss.active:
		target = level_h
	var k := 0.15 if p.vy > 5 else 0.1
	camera_y += (target - camera_y) * (1.0 - pow(1.0 - k, d60))
	if not boss.active and camera_y < p.y - H + 100:
		camera_y = p.y - H + 100
	if boss.active:
		camera_y = level_h
	if not boss.active and p.y > level_h + 1000:
		p.held_by_cramp = -1
		p.is_recharging = false
		Audio.stop_loop("krcloop.wav")
		_place_at_checkpoint(Game.checkpoint if Game.checkpoint < 5 else 1)
	camera_y = clampf(camera_y, 0, level_h)
	if level.horizontal:
		camera_y = 0
		var tx := clampf(p.x - W * 0.4, 0, maxf(0, level_w - W))
		camera_x += (tx - camera_x) * (1.0 - pow(0.88, d60))


func _update_recharge(dt: float, up: bool, down: bool) -> void:
	p.vx = 0
	var err := false
	match p.breath_index:
		0:
			if up and not down:
				p.breath_timer += dt
			elif p.breath_timer > 0.2:
				err = true
			if p.breath_timer >= 4:
				p.breath_index = 1
				p.breath_timer = 4
		1:
			if (up or down) and p.breath_timer > 4.2:
				err = true
			else:
				p.breath_timer += dt
			if p.breath_timer >= 6:
				p.breath_index = 2
				p.breath_timer = 6
		2:
			if down and not up:
				p.breath_timer += dt
			elif p.breath_timer > 6.2:
				err = true
			else:
				p.breath_timer += dt
	hud.breath_error = err
	if err:
		p.breath_error_timer += dt
		if p.breath_error_timer > 1:
			p.breath_index = 0
			p.breath_timer = 0
			p.breath_error_timer = 0
			p.breath_failed = true
			if p.held_by_cramp == -1:
				p.is_recharging = false
			get_tree().create_timer(0.5).timeout.connect(_clear_breath_failed)
	if p.breath_index == 2 and p.breath_timer >= 12 and not err:
		if p.held_by_cramp != -1:
			for e in level.entities:
				if e.id == p.held_by_cramp:
					e.defeated = true
					e.knocked_back = true
					e.vx = 10
					e.vy = -10
			p.held_by_cramp = -1
			p.invuln_timer = 2
			p.breath_charges = 3
			Audio.stop_loop("krcloop.wav")
			Audio.set_bgm_volume(0.5)
			Audio.play_sfx("krcoff.wav")
		else:
			# The boss: the finished cycle is a blast at once (below: it shrinks the monster, as
			# 1C says) and one charge to aim later (the hint says "charge breath").
			p.breath_charges = 1 if boss.active else 3
		Audio.play_sfx("breathok.wav")
		p.is_recharging = false
		p.breath_index = 0
		p.breath_timer = 0
		p.breath_error_timer = 0
		p.breathing_cooldown = 0.3
		p.breath_success = true
		if boss.active:
			p.is_breathing = 40
			shake_timer = 0.5
			Audio.play_sfx("krcoff.wav")
		trigger.emit("white_fade")
		get_tree().create_timer(0.5).timeout.connect(_clear_breath_success)


func _update_entities(dt: float, d60: float) -> void:
	var prect := p.rect()
	for e in level.entities:
		if e.collected or (e.defeated and not e.knocked_back):
			continue
		if e.knocked_back:
			e.x += e.vx * d60
			e.y += e.vy * d60
			e.vy += GRAVITY * 4 * d60
			if e.y > camera_y + view_h() + 100:
				e.knocked_back = false
			continue
		var touching := prect.intersects(e.rect())
		match e.type:
			"iron":
				if touching:
					e.collected = true
					if is_meadow():
						# A water drop: fills the vessel (estrogen).
						Audio.play_sfx("cink-%02d.wav" % randi_range(1, 11), 0.5)
						Game.water = mini(100, Game.water + Game.WATER_PER_DROP)
					else:
						Audio.play_sfx("nut0%d.wav" % randi_range(1, 3), 0.6)
						Game.iron += 1
			"seed":
				_update_seed(e, dt, d60)
			"enemy":
				_update_enemy(e, dt, d60, touching)
			"spike":
				if touching and not p.is_dead and p.hit_timer <= 0 and p.invuln_timer <= 0 and not dialog_open:
					_hurt(e.x)
			"trigger":
				if touching and active:
					_hit_trigger(e)
			"spring":
				if e.lunge_timer > 0:
					e.lunge_timer -= dt
				elif touching and p.vy >= 0 and not p.is_dead:
					_spring(e)
			"heart":
				if not touching and climb_power.has("magnet"):
					# The magnet pulls hearts in.
					var to := p.center() - Vector2(e.x + e.w / 2, e.y + e.h / 2)
					var d := to.length()
					if d < MAGNET_RANGE and d > 1:
						var step := minf(d, (5.0 + (MAGNET_RANGE - d) * 0.06) * d60)
						e.x += to.x / d * step
						e.y += to.y / d * step
						touching = prect.intersects(e.rect())
				if touching:
					_take_heart(e)
			"bell":
				if touching and not p.is_dead:
					_ring_bell(e)
			"joker":
				if touching and not p.is_dead:
					_take_joker(e)
			"comfort":
				if touching and not p.is_dead:
					_take_comfort(e)
			"door":
				if touching and door_open > 0.6 and not _pms_done_sent:
					_pms_done()
			"lantern":
				# Its whole column up to the ceiling takes it: a jump can't carry her over it.
				if (touching or prect.intersects(lantern_reach(e))) and not p.is_dead:
					_take_lantern(e)
			"updraft":
				if touching and not p.is_dead and not p.is_recharging and p.held_by_cramp == -1:
					p.vy = maxf(p.vy - 1.1 * d60, -9.0)
					p.jumps_left = _max_jumps()
					p.is_grounded = false


func _update_enemy(e: LevelData.Ent, dt: float, d60: float, touching: bool) -> void:
	if not _first_enemy_seen and Vector2(p.x - e.x, p.y - e.y).length() < 400:
		_first_enemy_seen = true
		trigger.emit("first_enemy")
	if not e.has_base:
		e.base_x = e.x
		e.base_y = e.y
		e.has_base = true
	match e.behavior:
		"float":
			e.x = e.base_x + sin(time_ms / 1000.0 + e.id) * 30
			e.y = e.base_y + cos(time_ms / 800.0 + e.id) * 20
		"distract":
			# Hovers around home and drifts towards a nearby player.
			var hx := e.base_x + sin(time_ms / 900.0 + e.id) * 40
			var hy := e.base_y + cos(time_ms / 700.0 + e.id) * 25
			var to_p := Vector2(p.x - e.x, p.y - e.y)
			if to_p.length() < 320 and not dialog_open:
				e.x += to_p.normalized().x * 0.9 * d60
				e.y += to_p.normalized().y * 0.9 * d60
			else:
				e.x += (hx - e.x) * 0.04 * d60
				e.y += (hy - e.y) * 0.04 * d60
		"chase":
			var home := Vector2(p.x - e.base_x, p.y - e.base_y)
			var dir: Vector2
			var spd := 1.2
			if home.length() < 400:
				dir = Vector2(p.x - e.x, p.y - e.y)
			else:
				dir = Vector2(e.base_x - e.x, e.base_y - e.y)
				spd = 1.0
			if dir.length() > 5:
				dir = dir.normalized() * spd * d60
				e.x += dir.x
				e.y += dir.y
		"lunge":
			e.lunge_timer -= dt
			if e.lunge_timer <= 0:
				var to_p := Vector2(p.x - e.x, p.y - e.y)
				if to_p.length() < 300:
					var v := to_p.normalized() * 5
					e.vx = v.x
					e.vy = v.y
					e.lunge_timer = 2 + randf()
				else:
					e.lunge_timer = 0.5
			if p.held_by_cramp != e.id:
				if e.vx != 0 or e.vy != 0:
					e.x += e.vx * d60
					e.y += e.vy * d60
					e.vx *= pow(0.95, d60)
					e.vy *= pow(0.95, d60)
					if absf(e.vx) < 0.5 and absf(e.vy) < 0.5:
						e.vx = 0
						e.vy = 0
				else:
					e.x += (e.base_x - e.x) * 0.05 * d60
					e.y += (e.base_y - e.y) * 0.05 * d60
	# Breath blast knocks enemies away.
	if p.is_breathing > 0:
		var r := (40.0 - p.is_breathing) / 40.0 * 200.0
		var dv := Vector2(e.x + e.w / 2 - (p.x + p.width / 2), e.y + e.h / 2 - (p.y + p.height / 2))
		if dv.length() < r and not e.knocked_back:
			e.defeated = true
			e.knocked_back = true
			var a := dv.angle()
			e.vx = cos(a) * 8
			e.vy = sin(a) * 8 - 6
			Audio.play_sfx("krcoff.wav")
	if p.held_by_cramp == e.id:
		e.x = p.x + p.width / 2 - e.w / 2
		e.y = p.y + p.height / 2 - e.h / 2
	if e.behavior == "distract":
		# A distraction only slows you down (dashing through it shrugs it off).
		if touching and not e.defeated and not dialog_open and p.is_breathing <= 0 and not p.is_dead:
			e.defeated = true
			e.knocked_back = true
			e.vx = 6.0 if e.x > p.x else -6.0
			e.vy = -8
			if p.dash_timer <= 0:
				p.slow_timer = 2.0
				p.vx *= 0.3
				Audio.play_sfx("au%d.wav" % randi_range(1, 5), 0.6)
			else:
				Audio.play_sfx("krcoff.wav", 0.5)
		return
	if touching and not p.is_dead and p.hit_timer <= 0 and p.invuln_timer <= 0 and not e.defeated and not dialog_open and p.is_breathing <= 0:
		if Game.has_breathing and not is_climb():
			if p.held_by_cramp == -1 and Game.iron <= 0:
				# Grabbed with no iron left: too much (the same rule as a hit, _hurt).
				_die(boss.active)
			elif p.held_by_cramp == -1:
				# A cramp grabs the player: breathe (▲■▼) to get free.
				p.held_by_cramp = e.id
				p.cramp_drain_timer = 0
				p.vx = 0
				p.vy = 0
				p.breath_charges = 0
				p.is_recharging = true
				p.breath_index = 0
				p.breath_timer = 0
				p.breath_error_timer = 0
				Audio.play_sfx("au%d.wav" % randi_range(1, 5))
				Audio.start_loop("krcloop.wav", 0.8)
				Audio.set_bgm_volume(0.15)
		else:
			_hurt(e.x)


func _hit_trigger(e: LevelData.Ent) -> void:
	if e.trigger_type == "teleport":
		p.x = e.target.x
		p.y = e.target.y
		p.vx = 0
		p.vy = 0
		return
	if is_climb() and not e.trigger_type in ["dialog", "jackpot", "climb_top", "mg11"]:
		# Nothing else interrupts the climb: other minigame (and cramp / boss / wave / gate /
		# summit) triggers painted in the editor do nothing here; only the wheel (mg11) opens.
		e.collected = true
		return
	e.collected = true
	if e.trigger_type == "dialog":
		if is_climb():
			# The climb has no dialog box: a painted letter talks on the board.
			var did := Text.dialog_for_letter(e.dialog_id, level_id)
			if did != "":
				board_dialog(did)
			return
		trigger.emit("dialog_" + e.dialog_id)
		return
	if e.trigger_type == "rest":
		# A rest point (the cave): a checkpoint between the minigames; she keeps moving.
		trigger.emit("rest")
		return
	if e.trigger_type == "jackpot":
		# A jackpot row (the climb): the JACKPOT and a checkpoint; she keeps flying.
		_jackpot()
		trigger.emit("jackpot")
		return
	p.vx = 0
	p.vy = 0
	if e.trigger_type == "climb_top":
		# The top: the egg is released — the biggest win of all.
		climb_won = true
		summit_timer = 0.01
		climb_power.clear()
		_jackpot()
		_coin_shower(90)
	if e.trigger_type == "mg11" and is_climb():
		# The wheel of the cycle: the climb waits where she is (Main opens it; after_wheel).
		if wheel_done:
			return
		wheel_done = true
		trigger.emit("mg11")
		return
	if e.trigger_type.begins_with("mg"):
		# A minigame opens: put Kyra on the ground so she isn't frozen mid-jump.
		_settle_on_ground()
		end_focus()
		wave_grace()
	if e.trigger_type == "gate":
		if Game.water >= 100 and Game.seeds >= Game.SEEDS_NEEDED:
			end_focus()
			_settle_on_ground()
			meadow_end = 0.01
			Audio.play_sfx("finished.wav")
		else:
			# Locked: say what is missing, let the player try again in a moment.
			gate_locked_timer = 1.5
			trigger.emit("gate_locked")
			return
	if e.trigger_type == "end":
		start_boss(Game.iron)
	elif e.trigger_type == "wave":
		# The final sprint: the wave speeds up.
		if wave.active:
			wave.speed = maxf(wave.speed, WAVE_SPRINT)
			wave_grace()
		else:
			start_wave()
	elif e.trigger_type == "summit":
		wave.won = true
		wave.active = false
		summit_timer = 0.01
		Audio.play_sfx("finished.wav")
	trigger.emit(e.trigger_type)


func _update_particles(dt: float, d60: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var q: Dictionary = particles[i]
		q.x += q.vx * d60
		q.y += q.vy * d60
		q.rot += q.rot_speed * d60
		if q.type in ["boss_body_part", "dash", "pollen", "splash", "sparkle", "glint", "heart"]:
			q.vx *= pow(0.95, d60)
			q.vy *= pow(0.95, d60)
		elif q.type == "coin":
			# Coins drift down slowly through the whole screen.
			q.vy = minf(q.vy + GRAVITY * 0.2 * d60, 6.0)
		else:
			q.vy += GRAVITY * d60
		if q.has("life"):
			q.life -= dt
			if q.life <= 0:
				particles.remove_at(i)
		elif q.y > camera_y + view_h() + 100:
			particles.remove_at(i)


func _boss_spike_particle() -> void:
	var idx: int = boss.hp - 1
	boss.hp -= 1
	if idx < 0 or idx >= boss.spike_order.size():
		return
	var s: int = boss.spike_order[idx]
	var outer := s >= 10
	var n := s - 10 if outer else s
	var a := n / 10.0 * TAU + time_ms * (0.002 if outer else -0.003)
	particles.append({
		"x": boss.x + cos(a) * boss.radius * 0.5, "y": boss.y + sin(a) * boss.radius * 0.5,
		"vx": cos(a) * 15, "vy": sin(a) * 15, "rot": a, "rot_speed": (randf() - 0.5) * 0.5,
		"type": "boss_spike",
	})


func _update_boss(dt: float, d60: float) -> void:
	var b := boss
	if b.hit_timer > 0:
		b.hit_timer -= dt
	var hit_now := false
	if b.hp > 0:
		# Breath blast (radius 400 in the arena).
		if p.is_breathing > 0 and b.hit_timer <= 0:
			var r := (40.0 - p.is_breathing) / 40.0 * 400.0
			var dv := Vector2(b.x - (p.x + p.width / 2), b.y - (p.y + p.height / 2))
			if dv.length() < r + b.radius:
				b.hit_timer = 0.5
				b.slow_timer = 5.0
				var a := dv.angle()
				b.vx += cos(a) * 2
				b.vy += sin(a) * 2
				for i in mini(b.hp, randi_range(1, 3)):
					_boss_spike_particle()
				Audio.play_sfx("krcoff.wav")
				shake_timer = maxf(shake_timer, 0.5)
				hit_now = true
		if b.defeated_timer == 0:
			if b.lost:
				var tx := p.x + p.width / 2
				var ty := p.y - 120
				b.x += (tx - b.x) * 0.05 * d60
				b.y += (ty - b.y) * 0.05 * d60 + sin(time_ms / 200.0) * 1.5
			elif dialog_open or b.wait > 0:
				# (wait: a retry without a dialog gives her a moment before it comes.)
				if not dialog_open:
					b.wait -= dt
				b.x = W / 2
				b.y = level_h + 400
			else:
				if b.slow_timer > 0:
					b.slow_timer -= dt
				var slow: bool = b.slow_timer > 0
				var spd := 1.5 if slow else 5.0
				var min_v := 0.5 if slow else 1.5
				if absf(b.vx) < min_v: b.vx = -min_v if b.vx < 0 else min_v
				if absf(b.vy) < min_v: b.vy = -min_v if b.vy < 0 else min_v
				var v := Vector2(b.vx, b.vy).normalized() * spd
				b.vx = v.x
				b.vy = v.y
				b.x += b.vx * d60
				b.y += b.vy * d60
				var top := camera_y + 100
				if b.x < b.radius:
					b.x = b.radius
					b.vx *= -1
				if b.x > W - b.radius:
					b.x = W - b.radius
					b.vx *= -1
				if b.y < top + b.radius:
					b.y = top + b.radius
					b.vy *= -1
				if b.y > camera_y + H - b.radius:
					b.y = camera_y + H - b.radius
					b.vy *= -1
			# Touching the boss.
			var to_p := Vector2(p.x + p.width / 2 - b.x, p.y + p.height / 2 - b.y)
			if to_p.length() < b.radius + p.width / 2 and not p.is_dead and p.hit_timer <= 0 and p.invuln_timer <= 0 and not b.lost and Game.iron > 0 and not dialog_open:
				if p.vy > 0 and p.y + p.height < b.y + b.radius * 0.5:
					b.hit_timer = 0.5 # stomp: bounce off
					p.vy = -12
					p.is_grounded = false
				else:
					p.hit_timer = 1
					p.vy = -10
					p.vx = -12.0 if p.x < b.x else 12.0
					p.is_grounded = false
					var lose := randi_range(3, 5)
					var lost := mini(Game.iron, lose)
					var left := maxi(0, Game.iron - lose)
					if left == 0:
						_die(true)
					else:
						Game.iron = left
						Audio.nut_sound()
					var removed := 0
					for i in range(hexes.size() - 1, -1, -1):
						if removed >= lost: break
						if hexes[i].active:
							hexes[i].active = false
							removed += 1
					_spray_nuts(lost, 10, 8, 2)
			# Boss eats the iron floor (not once the fight is lost: nothing more to take).
			if not dialog_open and not b.lost and not p.is_dead:
				for hx in hexes:
					if not hx.active:
						continue
					if Vector2(hx.x - b.x, hx.y - b.y).length() < b.radius + HEX_W / 2:
						hx.active = false
						var n := maxi(0, Game.iron - 1)
						if n == 0:
							_die(true)
						else:
							Game.iron = n
							Audio.nut_sound()
						if b.hit_timer <= 0 and not hit_now:
							_boss_spike_particle()
							Audio.play_sfx("krcoff.wav")
							hit_now = true
						_hex_particle(hx)
						if randf() < 0.5:
							for h2 in hexes:
								if h2.active and absf(h2.x - hx.x) <= HEX_W + 5 and absf(h2.y - hx.y) <= HEX_H + 5:
									h2.active = false
									Game.iron = maxi(0, Game.iron - 1)
									if Game.iron == 0:
										_die(true)
									_hex_particle(h2)
									break
						b.vy = absf(b.vy) if b.y > hx.y else -absf(b.vy)
			if hit_now:
				b.hit_timer = 0.5
				if b.hp <= 0 and b.defeated_timer == 0:
					b.defeated_timer = 0.01
					for i in 300:
						particles.append({
							"x": b.x + (randf() - 0.5) * b.radius * 2, "y": b.y + (randf() - 0.5) * b.radius * 2,
							"vx": (randf() - 0.5) * 15, "vy": (randf() - 0.5) * 15, "rot": randf() * TAU,
							"rot_speed": (randf() - 0.5) * 2, "type": "boss_body_part",
							"life": 2 + randf() * 4, "max_life": 6.0,
						})
	if b.defeated_timer > 0:
		b.defeated_timer += dt
		var c := Vector2(W / 2, camera_y + H / 2 - 50)
		if b.defeated_timer > 1.5:
			var t: float = b.defeated_timer - 1.5
			for i in hexes.size():
				var hx: Dictionary = hexes[i]
				if not hx.active:
					continue
				var rad := maxf(0, 150 - t * 50)
				var ang := i * TAU / maxf(1, hexes.size()) + t * 2
				var goal := c + Vector2(cos(ang), sin(ang)) * rad
				var dv := goal - Vector2(hx.x, hx.y)
				var dist := dv.length()
				var spd := 300 + t * 100
				if rad <= 0 and dist < 10:
					hx.active = false
					egg_growth += 1
				elif dist > 5:
					hx.x += dv.x / dist * spd * dt
					hx.y += dv.y / dist * spd * dt
				else:
					hx.x = goal.x
					hx.y = goal.y
		if b.defeated_timer > 0.1 and not _boss_dialog_sent:
			_boss_dialog_sent = true
			Audio.play_sfx("finished.wav")
			boss_defeated.emit()
	# Falling into the lava.
	if b.active and p.y + p.height > camera_y + H - 40 and not b.lost and b.hp > 0:
		b.lost = true
		p.y = camera_y + H - 150 - p.height
		p.vy = 0
		for e in level.entities:
			if e.type == "iron":
				e.collected = false
		# (Already lost because the iron ran out: that game-over panel is on its way.)
		if not p.is_dead:
			_die_quiet()
			boss_lost.emit()


func _die_quiet() -> void:
	p.is_recharging = false
	p.breath_charges = 0
	p.held_by_cramp = -1
	Audio.stop_loop("krcloop.wav")
	Audio.set_bgm_volume(0.5)
	p.is_sitting = true
	p.is_dead = true
	particles.clear()
	shake_timer = 0
	Game.iron = 0


func _hex_particle(hx: Dictionary) -> void:
	particles.append({
		"x": hx.x, "y": hx.y, "vx": (randf() - 0.5) * 10, "vy": -randf() * 8 - 2,
		"rot": randf() * TAU, "rot_speed": (randf() - 0.5) * 0.5, "type": "hex",
	})


# --- level 2: bubbles, the LH wave --------------------------------------------------

func _pop_bubble(pl: LevelData.Plat) -> void:
	pl.regrow = REGROW
	pl.pop_timer = 0
	Audio.play_sfx("breathoff.wav", 0.5)
	for i in 12:
		particles.append({"x": pl.x + randf() * pl.w, "y": pl.y + randf() * 20,
			"vx": (randf() - 0.5) * 6, "vy": -randf() * 4 - 1, "rot": 0.0, "rot_speed": 0.0,
			"type": "pollen", "life": 0.6, "max_life": 0.6})


## The LH wave starts rising below the player (from the trigger, or a retry).
func start_wave(speed := WAVE_SPEED, below := 260.0) -> void:
	wave.active = true
	wave.lost = false
	wave.won = false
	wave.y = p.y + p.height + below
	wave.speed = speed
	summit_timer = 0
	p.slow_timer = 0


## After a minigame or a dialog the wave gives a head start again.
func wave_grace() -> void:
	if wave.active and not wave.won:
		wave.y = maxf(wave.y, p.y + p.height + H * 0.8)


func _update_wave(dt: float, d60: float) -> void:
	if wave.lost or wave.won or dialog_open:
		return
	wave.speed = minf(WAVE_MAX, wave.speed + WAVE_ACCEL * dt)
	wave.y -= wave.speed * d60
	if is_summit():
		# Never lets the player get more than ~1.5 screens ahead: keeps the pressure on.
		wave.y = minf(wave.y, p.y + p.height + H * 1.5)
	if p.y + p.height > wave.y + 12 and not p.is_dead:
		wave.lost = true
		_die_quiet()
		Game.iron = maxi(Game.iron, 1)
		trigger.emit("wave_lost")


# --- drawing ------------------------------------------------------------------

func _draw_bg() -> void:
	var ci := _bg
	var cfg := background if not background.is_empty() else BackgroundData.for_level(level_id)
	var vs := Vector2(view_w(), view_h())
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color.from_string(cfg.get("base", "#101018"), Color("#101018")))
	if cfg.get("procedural", false):
		if is_pms():
			PmsMaze.draw_bg(ci, vs, time_ms, camera_y, level_h, rest_k * 0.5)
		elif is_up():
			_draw_garden_bg()
			if is_climb():
				_draw_casino_lights()
		elif is_meadow():
			_draw_meadow_bg()
	BackgroundData.draw_layers(ci, cfg, Vector2(camera_x, camera_y), vs, level.horizontal, bg_origin())
	if cfg.get("tint", false) and not boss.active:
		var pulse := sin(time_ms / 4000.0) * 0.5 + 0.5
		Draw.h_gradient(ci, Rect2(0, 0, vs.x * 0.8, vs.y), Color(80 / 255.0, 5 / 255.0, 23 / 255.0, 0.15 + pulse * 0.05), Color(0, 0, 0, 0))
		Draw.vignette(ci, Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.3 + pulse * 0.1), 0.4)


func _draw_world() -> void:
	var ci := _world
	var t := time_ms
	if not active:
		return
	if p.hit_timer > 0.8:
		ci.draw_rect(Rect2(camera_x, camera_y, view_w(), view_h()), Color(177 / 255.0, 88 / 255.0, 39 / 255.0, (p.hit_timer - 0.8) / 0.2 * 0.5))
	# While the view turns, more of the world shows (its corners): draw a wider area.
	var extra := 0.6 * view_w() if prerod_t >= 0 else 0.0
	var top := camera_y - 100 - extra
	var bottom := camera_y + view_h() + 100 + extra
	var left := camera_x - 120 - extra
	var right := camera_x + view_w() + 120 + extra
	if hide_platforms:
		return
	if is_meadow():
		_draw_meadow_back(ci, t, left, right)
	if is_pms():
		_draw_pms_world(ci, t, Rect2(left, top, right - left, bottom - top))
	for pl in ([] if is_pms() else level.platforms):
		if pl.y < top or pl.y > bottom or pl.x + pl.w < left or pl.x > right:
			continue
		if pl.kind != "rock":
			_draw_bubble(ci, pl, t)
		elif is_summit():
			_draw_garden_platform(ci, pl, t)
		elif is_climb():
			_draw_climb_platform(ci, pl, t)
		elif is_meadow():
			_draw_meadow_platform(ci, pl, t)
		else:
			_draw_platform(ci, pl, t)
	for e in level.entities:
		if e.collected or (e.defeated and not e.knocked_back):
			continue
		if e.y < top or e.y > bottom or e.x + e.w < left or e.x > right:
			continue
		match e.type:
			"iron":
				if is_meadow():
					_draw_drop(ci, e, t)
				else:
					var ic := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 300.0 + e.id) * 3)
					if not SpriteArt.draw(ci, "iron", ic, SpriteArt.DEFS.iron.size, t + e.id * 137.0):
						Draw.iron_nut(ci, ic, e.w / 2, t / 800.0 + e.id)
			"seed":
				_draw_seed(ci, e, t)
			"enemy", "spike":
				if e.behavior == "distract":
					_draw_distraction(ci, e, t)
				elif e.type == "spike" and is_summit():
					_draw_thorn(ci, e, t)
				else:
					_draw_cramp(ci, e, t)
			"updraft":
				_draw_updraft(ci, e, t)
			"spring":
				_draw_spring(ci, e, t)
			"heart":
				_draw_heart(ci, e, t)
			"bell":
				_draw_bell(ci, e, t)
			"joker":
				_draw_joker(ci, e, t)
			"comfort":
				# A little out of place: it drifts a few px around its real spot.
				var cc := e.rect().get_center() + Vector2(sin(t / 1700.0 + e.id) * 5, -4 + sin(t / 650.0 + e.id) * 4)
				Draw.radial_glow(ci, cc, 34, Color(1, 0.9, 0.75, 0.28))
				ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
				PmsMaze.draw_item(ci, PmsMaze.ITEMS[clampi(e.tier, 0, 2)], cc, t, 1.15)
			"door":
				PmsMaze.draw_door(ci, e, t, pms_items, clampf(door_open / 0.6, 0, 1))
			"lantern":
				PmsMaze.draw_lantern(ci, e.rect().get_center() + Vector2(0, 4 + sin(t / 800.0) * 2), t, 1.1, 0.75)
			"trigger":
				if e.trigger_type == "teleport":
					ci.draw_rect(e.rect(), Color(190 / 255.0, 24 / 255.0, 93 / 255.0, 0.1))
				elif e.trigger_type == "gate":
					_draw_gate(ci, e, t)
				elif e.trigger_type == "jackpot":
					_draw_jackpot_row(ci, e, t)
				elif e.trigger_type == "mg11" and is_climb():
					_draw_wheel_row(ci, e, t)
				elif e.trigger_type in ["mg2", "mg3", "mg4", "end", "mg5", "mg6", "mg7", "wave", "summit", "climb_top", "mg8", "mg9", "mg10"]:
					_draw_orb(ci, e, t)
			"text":
				ci.draw_string(_font, Vector2(e.x, e.y + e.h / 2 + 8), Text.plain(Text.t(e.text)), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.8))
	if boss.active:
		_draw_arena(ci, t, top, bottom)
	if summit_timer > 0 and not is_climb():
		# (The climb's egg comes out of its sun in the transformation: _draw_prerod_body.)
		_draw_summit_egg(ci, t)
	if corridor_t > 0:
		_draw_corridor(ci, t)
	if combo_flash > 0 and combo >= 2:
		var ck := combo_flash / 0.8
		Draw.text_center(ci, _font, Vector2(p.x + p.width / 2, p.y - 20 - (1 - ck) * 30), "x%d" % combo, 22, Color(1, 0.9, 0.4, ck))
	if is_meadow():
		_draw_meadow_front(ci, t, left, right)
	for q in particles:
		_draw_particle(ci, q)
	for pp in pops:
		var pk: float = clampf(1.0 - pp.t / pp.life, 0, 1)
		var pos := Vector2(pp.x, pp.y)
		# Number pops keep their size on screen (the climb is drawn zoomed out).
		var fs: int = roundi(float(pp.size) / view_zoom)
		var tw := _font.get_string_size(pp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_string_outline(_font, pos - Vector2(tw / 2, 0), pp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.3, 0.12, 0.02, pk))
		ci.draw_string(_font, pos - Vector2(tw / 2, 0), pp.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(pp.col, pk))
	if boss.defeated_timer > 1.5 and not hide_egg:
		_draw_egg(ci, t)
	if wave.active or wave.lost:
		_draw_wave(ci, t)


func _draw_platform(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var pts := PackedVector2Array()
	var top_line := PackedVector2Array()
	var m := 0.0
	while m <= pl.w:
		var yy := pl.y + sin((pl.x + m) * 0.03 + t * 0.0015) * 3
		pts.append(Vector2(pl.x + m, yy))
		top_line.append(Vector2(pl.x + m, yy))
		m += 10
	m = pl.w
	while m >= 0:
		var f := m / pl.w
		var hh := 10 + sin(f * PI) * (pl.h * 1.5)
		pts.append(Vector2(pl.x + m, pl.y + hh + sin((pl.x + m) * 0.04 + t * 0.002) * 4))
		m -= 10
	Draw.polygon_safe(ci, pts, Color("#881337"))
	if top_line.size() > 1:
		ci.draw_polyline(top_line, Color("#e11d48"), 4.0, true)
	m = 20
	while m < pl.w - 10:
		var f := m / pl.w
		var hh := 10 + sin(f * PI) * (pl.h * 1.5)
		var yy := sin((pl.x + m) * 0.03 + t * 0.0015) * 3
		Draw.quad_curve(ci, Vector2(pl.x + m, pl.y + yy + 2), Vector2(pl.x + m + 15, pl.y + hh * 0.5), Vector2(pl.x + m - 10, pl.y + hh - 5), Color("#4c0519"), 2.0)
		m += 40


func _draw_cramp(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var pulse := sin(t / 150.0) * 6
	var held := p.held_by_cramp == e.id
	var amp := 10.0 if held else 3.0
	var jx := sin(t / 50.0 + e.x) * amp + ((randf() - 0.5) * 10 if held else 0.0)
	var jy := cos(t / 40.0 + e.y) * amp + ((randf() - 0.5) * 10 if held else 0.0)
	var c := Vector2(e.x + e.w / 2 + jx, e.y + e.h / 2 + jy)
	var spike := e.type == "spike"
	var id := "spike" if spike else "cramp"
	if SpriteArt.draw(ci, id, c, SpriteArt.DEFS[id].size * (1 + pulse / 60.0), t + e.id * 137.0, Color.WHITE, c.x > p.x + p.width / 2):
		return
	SpriteArt.draw_cramp(ci, c, e.w / 2 + pulse, t, spike)


func _draw_orb(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 500.0) * 10)
	if level.horizontal:
		# Column triggers: the orb floats above the ground of its column.
		c.y = (level.water_top if level.water_top > 0 else H) - 200 + sin(t / 500.0) * 10
	var r := 30 + sin(t / 300.0) * 5
	var glow := Color(95 / 255.0, 155 / 255.0, 153 / 255.0, 0.6)
	var core := Color("#c7e1e0")
	var dots := Color("#9fcbcb")
	if e.trigger_type in ["wave", "summit", "climb_top"]:
		glow = Color(250 / 255.0, 204 / 255.0, 21 / 255.0, 0.55)
		core = Color("#fef3c7")
		dots = Color("#fde68a")
	elif is_summit():
		glow = Color(134 / 255.0, 239 / 255.0, 172 / 255.0, 0.55)
		core = Color("#ecfdf5")
		dots = Color("#86efac")
	Draw.radial_glow(ci, c, r * 2, glow)
	ci.draw_circle(c, r * 0.5, core)
	for i in 3:
		var a := t / 1000.0 + i * TAU / 3
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 1.2, 4, dots)


func _draw_arena(ci: CanvasItem, t: float, top: float, bottom: float) -> void:
	var lava_y := camera_y + H - 40
	if boss.defeated_timer > 0:
		var yy := lava_y + maxf(0, 40 - boss.defeated_timer * 40)
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= W:
			pts.append(Vector2(x, yy + sin(x * 0.03 + t * 0.0015) * 3))
			x += 20
		pts.append(Vector2(W, camera_y + H))
		pts.append(Vector2(0, camera_y + H))
		Draw.polygon_safe(ci, pts, Color("#b15827"))
	else:
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= W:
			pts.append(Vector2(x, lava_y + sin(t / 200.0 + x / 50.0) * 8 + cos(t / 300.0 + x / 30.0) * 5))
			x += 20
		pts.append(Vector2(W, camera_y + H))
		pts.append(Vector2(0, camera_y + H))
		Draw.polygon_safe(ci, pts, Color("#9a3b1f"))
		for i in 10:
			var bx := fmod(t / 20.0 + i * 100, W)
			var by := lava_y + 20 + sin(t / 150.0 + i) * 10
			ci.draw_circle(Vector2(bx, by), maxf(0.5, 2 + sin(t / 100.0 + i) * 2), Color(252 / 255.0, 165 / 255.0, 165 / 255.0, 0.6))
	for hx in hexes:
		if hx.active and hx.y >= top and hx.y <= bottom:
			Draw.hex_tile(ci, Vector2(hx.x, hx.y), 0.0, HEX_W / 2)
	if boss.hp > 0 and boss.defeated_timer == 0 and boss.y >= top and boss.y <= bottom:
		_draw_boss(ci, t)


func _draw_boss(ci: CanvasItem, t: float) -> void:
	var b := boss
	var col := Color("#fca5a5") if b.hit_timer > 0 else Color("#b15827")
	var c := Vector2(b.x, b.y) + Vector2(sin(t / 50.0 + b.x) * 6, cos(t / 40.0 + b.y) * 6)
	var r: float = b.radius + sin(t / 150.0) * 12
	if SpriteArt.draw(ci, "boss", c, SpriteArt.DEFS.boss.size * r / 60.0, t, Color(1, 0.6, 0.6) if b.hit_timer > 0 else Color.WHITE):
		return
	var alive := {}
	for i in range(0, maxi(0, b.hp)):
		alive[b.spike_order[i]] = true
	SpriteArt.draw_boss(ci, c, r, t, alive, col)


func _draw_particle(ci: CanvasItem, q: Dictionary) -> void:
	var pos := Vector2(q.x, q.y)
	match q.type:
		"hex":
			Draw.hex_tile(ci, pos, q.rot, HEX_W / 2)
		"nut":
			Draw.nut_particle(ci, pos, q.rot)
		"spark":
			ci.draw_set_transform(pos, q.rot, Vector2.ONE)
			ci.draw_rect(Rect2(-4, -4, 8, 8), Color("#b15827"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"boss_body_part":
			var a: float = q.life / q.max_life if q.has("life") else 1.0
			ci.draw_circle(pos, 3 + fmod(absf(q.x), 2.0), Color(177 / 255.0, 88 / 255.0, 39 / 255.0, clampf(a, 0, 1)))
		"boss_spike":
			ci.draw_set_transform(pos, q.rot, Vector2.ONE)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-10, -5), Vector2(15, 0), Vector2(-10, 5)]), Color("#b15827"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"dash":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 3 + 6 * a, Color(1, 1, 1, 0.5 * a))
		"pollen":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 2 + 2 * a, Color(1, 0.95, 0.75, 0.8 * a))
		"splash":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 2 + 3 * a, Color(0.6, 0.85, 1.0, 0.8 * a))
		"sparkle":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 1.5 + 3 * a, Color(1, 0.9, 0.5, 0.9 * a))
		"coin":
			var a: float = clampf(q.life / 0.5, 0, 1)
			ci.draw_set_transform(pos, 0, Vector2(maxf(0.15, absf(cos(q.rot))), 1))
			ci.draw_circle(Vector2.ZERO, 9, Color(0.85, 0.55, 0.05, a))
			ci.draw_circle(Vector2.ZERO, 7, Color(1, 0.82, 0.2, a))
			ci.draw_circle(Vector2(-2, -2), 2.5, Color(1, 1, 0.85, a))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"glint":
			# A four-pointed gold star.
			var a: float = q.life / q.max_life
			var r := 3.0 + 7.0 * a
			var col := Color(1, 0.93, 0.55, a)
			ci.draw_line(pos - Vector2(r, 0), pos + Vector2(r, 0), col, 2.0)
			ci.draw_line(pos - Vector2(0, r), pos + Vector2(0, r), col, 2.0)
			ci.draw_circle(pos, 2.0, Color(1, 1, 0.9, a))
		"flame":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 3 + 7 * a, Color(1, 0.45 + 0.4 * a, 0.1, 0.8 * a))
		"heart":
			var a: float = q.life / q.max_life
			SpriteArt.draw_heart(ci, pos, 3.0 + 5.0 * a, 1.0, a)


func _draw_egg(ci: CanvasItem, t: float) -> void:
	var c := Vector2(W / 2, camera_y + H / 2 - 50)
	var g := egg_growth / maxf(1, hexes.size())
	var r := maxf(0.1, g * 45)
	var pulse := sin(t / 200.0) * 3 * g
	Draw.radial_glow(ci, c, r + 20 * g + pulse, Color(224 / 255.0, 89 / 255.0, 122 / 255.0, 0.6), Color(1, 1, 1, 0.9))
	ci.draw_circle(c, r * 0.8, Color("#efdacd"))
	ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.2), maxf(0.1, r * 0.3), Color("#d69c70"))


func _draw_player() -> void:
	var ci := _player_layer
	if hide_platforms:
		# A minigame covers the screen; Kyra waits out of sight.
		return
	PlayerArt.draw(ci, p, time_ms, boss.active, {
		"crouched": p.held_by_cramp != -1,
		"pain": p.hit_timer > 0 or p.held_by_cramp != -1,
		"sitting": p.is_sitting or meadow_end > 0,
		"airborne": false if (p.is_recharging or in_water) else not p.is_grounded,
		"squash": p.squash,
		# Falling out of the arena she comes towards us: she grows.
		"grow": _exit_grow() if exit_fall else _pull_scale(),
		# Pulled into the yellow body (the transformation) she spins slowly.
		"spin": _pull_spin(),
	})
	if is_pms():
		if has_lantern:
			# Her lantern floats at her side, swinging a little.
			var lp := p.center() + Vector2(24 if p.facing_right else -24, 4 + sin(time_ms / 320.0) * 2.5)
			PmsMaze.draw_lantern(ci, lp, time_ms, 0.8, 1.0, sin(time_ms / 540.0) * 0.14)
	if in_water:
		# Swimming: the river covers everything below the surface.
		ci.draw_rect(Rect2(p.x - 40, level.water_top + 14, p.width + 80, 120), Color(0.35, 0.65, 0.9, 0.75))
	if focus and thread_target != -1:
		_draw_thread(ci, time_ms)
	if is_meadow() and not dialog_open and meadow_end == 0:
		# The aim: a small ring where the thread would go (brighter while focusing).
		var ap := _aim_point()
		var hand := _hand()
		var dir := ap - hand
		if dir.length() > 1:
			ap = hand + dir.normalized() * minf(dir.length(), thread_range())
		ci.draw_arc(ap, 9, 0, TAU, 24, Color(1, 0.95, 0.6, 0.9 if focus else 0.45), 2.0, true)
		ci.draw_circle(ap, 2, Color(1, 1, 0.8, 0.9 if focus else 0.5))
	if not active:
		return
	var screen := Rect2(camera_x, camera_y, view_w(), view_h())
	if p.held_by_cramp != -1:
		var k := p.breath_timer / 12.0
		var a := maxf(0, 0.6 * (1 - k)) + sin(time_ms / 200.0) * 0.1
		Draw.vignette(ci, screen, Color(80 / 255.0, 5 / 255.0, 23 / 255.0, clampf(a, 0, 1)), 0.0)
	elif p.breath_success:
		Draw.vignette(ci, screen, Color(95 / 255.0, 155 / 255.0, 153 / 255.0, 0.4), 0.0)


# --- level 2 drawing -----------------------------------------------------------------

## Progress up the garden: 0 at the bottom (dusk), 1 at the top (morning).
func _climb() -> float:
	return clampf(1.0 - (camera_y + view_h() / 2) / maxf(1, level_h), 0, 1)


func _draw_garden_bg() -> void:
	var ci := _bg
	# Fills the visible area (larger than the screen in the zoomed-out climb).
	var vw := view_w()
	var vh := view_h()
	var k := _climb()
	# Dusk (dark indigo & pink) → dawn → spring morning.
	var stops_top := [Color("#1c1533"), Color("#4a2a5e"), Color("#c76a8a"), Color("#8fd0c4")]
	var stops_bot := [Color("#0e0c18"), Color("#2a1e3a"), Color("#5a3a6a"), Color("#f2d9a0")]
	var f := k * 3.0
	var i := int(floorf(f))
	var u := f - i
	var top_c: Color = stops_top[mini(i, 3)].lerp(stops_top[mini(i + 1, 3)], u)
	var bot_c: Color = stops_bot[mini(i, 3)].lerp(stops_bot[mini(i + 1, 3)], u)
	# While the view turns (the climb's end) the sky reaches past the screen's corners.
	var m := 0.6 * vw if prerod_t >= 0 else 0.0
	var bands := 16 if m == 0.0 else 40
	for b in bands:
		var y0 := -m + (vh + 2 * m) * b / bands
		var u2 := clampf((y0 + (vh + 2 * m) / bands / 2) / vh, 0, 1)
		ci.draw_rect(Rect2(-m, y0, vw + 2 * m, (vh + 2 * m) / bands + 1), top_c.lerp(bot_c, u2))
	if is_climb() and prerod_hand() < 1.0:
		# The forest run's sun, whole, shining over the casino and rising as she climbs.
		# (The transformation draws it in screen space, _draw_prerod_body, fading in over
		# it: its glow and rays fade out meanwhile.)
		_draw_climb_sun(ci, 1.0 - prerod_hand())
	elif k > 0.45:
		# Sun rising behind the summit.
		var sk := (k - 0.45) / 0.55
		var sc := Vector2(vw * 0.72, vh * (1.1 - sk * 0.9))
		Draw.radial_glow(ci, sc, 220 + sk * 120, Color(1, 0.92, 0.6, 0.35 * sk), Color(1, 0.98, 0.85, 0.9 * sk))
	# Vines along the edges (parallax) and drifting pollen.
	var t := time_ms
	for v in 6:
		var side := -1.0 if v % 2 == 0 else 1.0
		var depth := 0.3 + 0.12 * v
		var off := camera_y * depth
		var x0 := (vw / 2) + side * (vw / 2 - 40 - v * 35)
		var pts := PackedVector2Array()
		var yy := -40.0
		while yy < vh + 40:
			pts.append(Vector2(x0 + sin((yy + off) * 0.012 + v) * 18, yy))
			yy += 24
		var vc := Color(0.1, 0.35, 0.2, 0.25 + 0.06 * v).lerp(Color(0.2, 0.55, 0.3, 0.35), k)
		vc.a *= 1.0 - 0.7 * wind
		ci.draw_polyline(pts, vc, 3 + v, true)
		var ly := fmod(-off * 0.5, 160.0)
		while ly < vh:
			var lp := Vector2(x0 + sin((ly + off) * 0.012 + v) * 18, ly)
			ci.draw_set_transform(lp, side * 0.6 + sin(t / 900.0 + ly) * 0.1, Vector2(1, 0.45))
			ci.draw_circle(Vector2.ZERO, 12 + v, vc)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			ly += 160
	for i2 in 36:
		var px := fmod(i2 * 173.0 + sin(t / 1500.0 + i2) * 30 + vw, vw)
		var py := fmod(vh - fmod(t * (0.02 + 0.01 * (i2 % 3)) + i2 * 97.0, vh), vh)
		ci.draw_circle(Vector2(px, py), 1.5 + (i2 % 3) * 0.7, Color(1, 0.95, 0.7, 0.25 + 0.3 * k))
	Draw.vignette(ci, Rect2(0, 0, vw, vh), Color(0, 0, 0, (0.35 - 0.2 * k) * (1.0 - wind)), 0.45)


## 0 at the climb's start (the camera at the bottom) .. 1 at its top.
func sun_progress() -> float:
	var k0 := view_h() / 2 / maxf(1, level_h)
	return clampf((_climb() - k0) / maxf(0.01, 1.0 - 2 * k0), 0, 1)


## The climb's sun on the screen (not zoomed): [centre, radius]. It starts where the forest
## run left it (SUN_MELT_POS) and rises to SUN_TOP_Y as she climbs.
func sun_screen() -> Array:
	var k := sun_progress()
	var e := 1.0 - (1.0 - k) * (1.0 - k)
	return [Vector2(W / 2, lerpf(SUN_MELT_POS.y, SUN_TOP_Y, e)), lerpf(SUN_R0, SUN_R1, k)]


## The climb's sun in the background (behind the platforms, not transparent): a warm
## glow, turning rays, a solid disc and the 12 golden slices (SpriteArt.draw_sun). It turns
## with the view and dims when the casino winds down (the transformation).
func _draw_climb_sun(ci: CanvasItem, glow := 1.0) -> void:
	var at: Array = sun_screen()
	var c: Vector2 = at[0] / view_zoom
	var r: float = at[1] / view_zoom
	var tt := (_light_t if prerod_t >= 0 else time_ms) / 1000.0
	var dim := (1.0 - 0.55 * wind) * glow
	Draw.radial_glow(ci, c, r * (2.6 + 0.12 * sin(tt * 1.7)), Color(1, 0.8, 0.35, 0.45 * dim), Color(1, 0.93, 0.7, 0.85 * dim))
	for i in 18:
		var a := tt * 0.25 + i * TAU / 18
		var l := r * (1.32 + 0.16 * sin(tt * 2.0 + i * 1.3))
		var d := Vector2(cos(a), sin(a))
		ci.draw_line(c + d * r * 1.05, c + d * l, Color(1, 0.86, 0.42, 0.85 * dim), maxf(2.0, r * 0.07), true)
	ci.draw_circle(c, r * 1.04, Color(0.96, 0.62, 0.12).lerp(Color(0.55, 0.42, 0.6), wind))
	SpriteArt.draw_sun(ci, c, r, 12, 0.0, tt)
	if wind > 0:
		ci.draw_circle(c, r * 1.06, Color(0.24, 0.16, 0.32, 0.45 * wind))


## The transformation's follicle / yellow body on screen: [centre, radius]. It starts as
## the sky's sun (where it was), comes to LUTEUM_C and grows (FOCUS), then the zoom into
## its opening (PULL + IRIS: up to LUTEUM_ZOOM ×, the opening then fills the screen).
func prerod_body() -> Array:
	var s0c: Vector2 = _prerod_sun0[0]
	var s0r: float = _prerod_sun0[1]
	var f := _smooth(_pk(0.25, PREROD_FOCUS - 0.25))
	var r := lerpf(s0r, LUTEUM_R, f) * (1.0 + 0.025 * sin(_light_t / 380.0) * _pk(PREROD_T_LUTEUM, 0.6))
	var z := _pk(PREROD_T_PULL, PREROD_PULL + PREROD_IRIS)
	return [s0c.lerp(LUTEUM_C, f), r * pow(LUTEUM_ZOOM, z * z)]


## 0..1: the follicle open (its slices apart like petals) — up in EGG, closed again in LUTEUM.
func prerod_open() -> float:
	return _smooth(_pk(PREROD_T_EGG, 0.5)) * (1.0 - _smooth(_pk(PREROD_T_LUTEUM, 0.8)))


## 0..1: how much of the yellow body (the corpus luteum) has formed.
func prerod_luteum() -> float:
	return _smooth(_pk(PREROD_T_LUTEUM + 0.2, 1.0))


## Where the released egg is on screen (and its size; 0 = not out yet / gone).
func prerod_egg() -> Array:
	var at: Array = prerod_body()
	var c: Vector2 = at[0]
	var r: float = at[1]
	var grow := _smooth(_pk(PREROD_T_EGG + 0.1, 0.45))
	var k := _pk(PREROD_T_EGG + EGG_OUT, EGG_FLY)
	if grow <= 0.0 or k >= 1.0:
		return [c, 0.0]
	# A gentle arc up and out of the frame (top right).
	var e := k * k * (3 - 2 * k) * 0.5 + k * 0.5
	var ctrl := c + Vector2(r * 1.6, -r * 2.2)
	var end := Vector2(W + 90, -90)
	var pos := c.lerp(ctrl, e).lerp(ctrl.lerp(end, e), e)
	return [pos, (0.13 * r + 6.0) * grow * (1.0 + 0.35 * k)]


## The inside of the yellow body's opening around `c`: dark amber in the middle, brighter
## to its rim at `r_open` (`hole` > 0: a clear hole in the middle, the way in).
static func draw_opening(ci: CanvasItem, c: Vector2, r_open: float, hole: float, alpha: float) -> void:
	var n := 24
	if hole <= 0.0:
		ci.draw_circle(c, r_open / n + 1.0, Color(LUTEUM_IN, alpha))
	for i in n:
		var a := lerpf(hole, r_open, float(i) / n)
		var b := lerpf(hole, r_open, float(i + 1) / n)
		var col := LUTEUM_IN.lerp(LUTEUM_RIM, clampf((a + b) / 2 / r_open, 0, 1))
		ci.draw_arc(c, (a + b) / 2, 0, TAU, 96, Color(col, alpha), b - a + 1.5, true)
	if hole > 0.0:
		ci.draw_arc(c, hole + 6, 0, TAU, 96, Color(1, 0.86, 0.55, 0.55 * alpha), 14.0, true)
	ci.draw_arc(c, r_open, 0, TAU, 96, Color(1, 0.84, 0.48, 0.8 * alpha), maxf(2.0, r_open * 0.035), true)


## The follicle → the egg → the yellow body (screen space, on the veil; it turns with the view).
func _draw_prerod_body(ci: CanvasItem) -> void:
	var at: Array = prerod_body()
	var c: Vector2 = at[0]
	var r: float = at[1]
	var tt := _light_t / 1000.0
	var turn := view_angle()
	var open := prerod_open()
	var lut := prerod_luteum()
	var gold := Color(1, 0.8, 0.35)
	var amber := Color(1, 0.6, 0.18)
	Draw.radial_glow(ci, c, r * (2.4 + 0.12 * sin(tt * 1.7)), Color(gold.lerp(amber, lut), 0.5), Color(1, 0.93, 0.7, 0.7 * (1.0 - 0.5 * lut)))
	# The sun's rays fade as it becomes the yellow body.
	if lut < 1.0:
		for i in 18:
			var a := turn + tt * 0.25 + i * TAU / 18
			var l := r * (1.32 + 0.16 * sin(tt * 2.0 + i * 1.3) + 0.25 * open)
			var d := Vector2(cos(a), sin(a))
			ci.draw_line(c + d * r * (1.05 + 0.25 * open), c + d * l, Color(1, 0.86, 0.42, 0.85 * (1.0 - lut)), maxf(2.0, r * 0.07), true)
	# The follicle: its disc (gone while it is open) and the 12 slices, apart like petals.
	if lut < 1.0:
		var sun_a := 1.0 - lut
		ci.draw_circle(c, r * 1.04, Color(Color(0.96, 0.62, 0.12), sun_a * (1.0 - open)))
		for i in 12:
			var a0 := turn - PI / 2 + i * TAU / 12 + 0.035
			var a1 := turn - PI / 2 + (i + 1) * TAU / 12 - 0.035
			var am := (a0 + a1) / 2
			var off := Vector2(cos(am), sin(am)) * r * 0.3 * open
			var tip := c + off * 1.2
			var tri := PackedVector2Array([tip, c + off + Vector2(cos(a0), sin(a0)) * r, c + off + Vector2(cos(a1), sin(a1)) * r])
			Draw.polygon_safe(ci, tri, Color(Color("#fbbf24").lerp(amber, lut), sun_a))
			ci.draw_polyline(tri + PackedVector2Array([tri[0]]), Color(1, 0.97, 0.84, 0.8 * sun_a), maxf(1.5, r * 0.02), true)
		if open > 0.0:
			# The opened middle glows where the egg comes out.
			Draw.radial_glow(ci, c, r * 0.7 * open, Color(1, 0.95, 0.8, 0.9 * open * sun_a))
	# The yellow body: a soft hollow amber sphere with an opening (the way in).
	if lut > 0.0:
		var rr := r * (0.85 + 0.15 * lut)
		ci.draw_circle(c, rr, Color(Color("#e9a23b"), lut))
		ci.draw_arc(c, rr * 0.93, 0, TAU, 96, Color(0.72, 0.4, 0.1, 0.55 * lut), rr * 0.14, true)
		Draw.radial_glow(ci, c + Vector2(-0.28, -0.3).rotated(turn) * rr, rr * 0.75, Color(1, 0.9, 0.62, 0.55 * lut))
		var hole := rr * LUTEUM_HOLE * lut
		if hole > 1.0:
			draw_opening(ci, c, hole, 0.0, lut)
	# The egg (as the cave's grain / the summit's egg): out of the middle, away out of the frame.
	var eg: Array = prerod_egg()
	var er: float = eg[1]
	if er > 0.5:
		var ec: Vector2 = eg[0]
		var tm := _light_t
		Draw.radial_glow(ci, ec, er * 2.6 + sin(tm / 200.0) * 3, Color(1, 0.9, 0.55, 0.7), Color(1, 1, 0.9, 0.95))
		ci.draw_circle(ec, er * 0.8, Color("#fff7df"))
		ci.draw_circle(ec + Vector2(-er * 0.2, -er * 0.2), maxf(0.1, er * 0.3), Color("#f9a8d4"))
		for i in 8:
			var a := tm / 600.0 + i * TAU / 8
			ci.draw_circle(ec + Vector2(cos(a), sin(a)) * (er + 14 + sin(tm / 300.0 + i) * 4), 2.5, Color(1, 0.95, 0.7, 0.8))


## The transformation's captions [key, from, to] (s of prerod_t): the egg (from when the
## follicle opens, into the closing), then the yellow body (through the pull, until the
## opening fills the screen; the caption is in screen space, it doesn't turn). Long enough
## to read: the test holds each to CAPTION_READ × board_read_time in every language.
static func prerod_caption_spans() -> Array:
	return [
		["PREROD_EGG", PREROD_T_EGG + 0.25, PREROD_T_LUTEUM + 0.8],
		["PREROD_LUTEUM", PREROD_T_LUTEUM + 0.9, PREROD_T_IRIS],
	]


## The transformation's captions [key, alpha] now: the egg, then the yellow body.
func prerod_caption() -> Array:
	for sp: Array in prerod_caption_spans():
		var t0: float = sp[1]
		var t1: float = sp[2]
		if prerod_t >= t0 and prerod_t < t1:
			return [sp[0], minf(clampf((prerod_t - t0) / 0.35, 0, 1), clampf((t1 - prerod_t) / 0.35, 0, 1))]
	return ["", 0.0]


func _draw_prerod_caption(ci: CanvasItem) -> void:
	var cap: Array = prerod_caption()
	var a: float = cap[1]
	if a <= 0.0:
		return
	var s := Text.plain(Text.t(str(cap[0])))
	var f: Font = Text.font_bold
	var pos := Vector2(W / 2 - CAPTION_W / 2, CAPTION_Y)
	ci.draw_multiline_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, CAPTION_W, CAPTION_FS, 2, 8, Color(0.16, 0.07, 0.2, 0.85 * a))
	ci.draw_multiline_string(f, pos, s, HORIZONTAL_ALIGNMENT_CENTER, CAPTION_W, CAPTION_FS, 2, Color(1, 0.96, 0.86, a))


## The captions must fit (two lines at CAPTION_W) in every language (the test).
static func prerod_fit_problems() -> Array:
	var out: Array = []
	for key: String in ["PREROD_EGG", "PREROD_LUTEUM"]:
		var pr := Draw.fit_problem(key, Text.font_bold, Text.plain(Text.t(key)), CAPTION_W, CAPTION_FS, 2)
		if pr != "":
			out.append(pr)
	return out


func _draw_garden_platform(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var pts := PackedVector2Array()
	var top_line := PackedVector2Array()
	var m := 0.0
	while m <= pl.w:
		var yy := pl.y + sin((pl.x + m) * 0.03 + t * 0.0015) * 2
		pts.append(Vector2(pl.x + m, yy))
		top_line.append(Vector2(pl.x + m, yy))
		m += 10
	m = pl.w
	while m >= 0:
		var f := m / pl.w
		var hh := 8 + sin(f * PI) * (pl.h * 1.2)
		pts.append(Vector2(pl.x + m, pl.y + hh + sin((pl.x + m) * 0.05 + t * 0.002) * 3))
		m -= 10
	Draw.polygon_safe(ci, pts, Color("#2f5d3f"))
	if top_line.size() > 1:
		ci.draw_polyline(top_line, Color("#86efac"), 4.0, true)
	# Small leaves along the top, roots underneath.
	m = 14
	while m < pl.w - 8:
		var lp := Vector2(pl.x + m, pl.y - 2)
		ci.draw_set_transform(lp, -0.5 + sin(t / 700.0 + m) * 0.15, Vector2(1, 0.5))
		ci.draw_circle(Vector2.ZERO, 6, Color("#4ade80"))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		Draw.quad_curve(ci, Vector2(pl.x + m + 6, pl.y + 10), Vector2(pl.x + m + 14, pl.y + 24), Vector2(pl.x + m + 2, pl.y + 30), Color("#1e3d2a"), 2.0)
		m += 36


func _draw_bubble(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var c := Vector2(pl.x + pl.w / 2, pl.y + 14)
	var near := clampf(1.0 - Vector2(p.x + p.width / 2 - c.x, p.y + p.height - c.y).length() / 220.0, 0, 1)
	var grow := 1.0 + 0.22 * near
	var base := Color("#f9a8d4") if pl.kind == "bubble" else Color("#fde68a")
	if pl.regrow > 0:
		# Regrowing: a small faint bubble swelling back.
		var g := 1.0 - pl.regrow / REGROW
		ci.draw_set_transform(c, 0, Vector2(1, 0.7))
		ci.draw_circle(Vector2.ZERO, maxf(1, (pl.w / 2 + 6) * g * 0.6), Color(base, 0.15 * g))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	var jitter := Vector2.ZERO
	if pl.kind == "pop" and pl.pop_timer > 0:
		var k := pl.pop_timer / POP_AFTER
		jitter = Vector2((randf() - 0.5) * 6 * k, (randf() - 0.5) * 4 * k)
	# A cluster: one follicle per cell of the platform.
	var n := maxi(1, int(roundf(pl.w / LevelData.CELL_W)))
	var cw := pl.w / n
	for i in n:
		var cc := Vector2(pl.x + cw * (i + 0.5), pl.y + 12) + jitter
		var r := cw / 2 + 5 + sin(t / 400.0 + pl.x + i) * 2
		ci.draw_set_transform(cc, 0, Vector2(grow, 0.8 * grow))
		ci.draw_circle(Vector2.ZERO, r, Color(base, 0.35))
		ci.draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)
		ci.draw_circle(Vector2(-r * 0.4, -r * 0.35), r * 0.18, Color(1, 1, 1, 0.75))
		if pl.kind == "pop":
			# A tiny follicle inside: these are about to burst.
			ci.draw_circle(Vector2(r * 0.2, r * 0.15), r * 0.25, Color("#f472b6", 0.5))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_updraft(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var r := e.rect()
	ci.draw_rect(r, Color(1, 1, 0.8, 0.05))
	for i in 7:
		var yy := r.end.y - fmod(t * 0.12 + i * 37.0, r.size.y)
		var xx := r.position.x + 6 + fmod(i * 13.0, r.size.x - 12)
		var a := clampf((yy - r.position.y) / r.size.y, 0, 1)
		ci.draw_line(Vector2(xx, yy), Vector2(xx, yy - 14), Color(1, 1, 0.85, 0.5 * a), 2.0)


func _draw_thorn(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var base := Vector2(e.x + e.w / 2, e.y + e.h)
	var h: float = SpriteArt.DEFS.thorn.size
	if not SpriteArt.draw(ci, "thorn", base - Vector2(0, h * SpriteArt.scale_of("thorn") / 2), h, t + e.id * 137.0):
		SpriteArt.draw_thorn(ci, base)


func _draw_distraction(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 180.0 + e.id) * 3)
	if not SpriteArt.draw(ci, "distraction", c, SpriteArt.DEFS.distraction.size, t + e.id * 137.0):
		SpriteArt.draw_distraction(ci, c, t)


func _draw_wave(ci: CanvasItem, t: float) -> void:
	var yy: float = wave.y
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= W:
		pts.append(Vector2(x, yy + sin(t / 180.0 + x / 60.0) * 8 + cos(t / 260.0 + x / 35.0) * 4))
		x += 20
	pts.append(Vector2(W, camera_y + H + 50))
	pts.append(Vector2(0, camera_y + H + 50))
	Draw.polygon_safe(ci, pts, Color(0.98, 0.75, 0.3, 0.85))
	var glow := PackedVector2Array()
	for i in range(0, pts.size() - 2):
		glow.append(pts[i])
	ci.draw_polyline(glow, Color(1, 0.97, 0.8, 0.95), 5.0, true)
	for i in 14:
		var bx := fmod(t / 15.0 + i * 83.0, W)
		var by := yy + 16 + sin(t / 140.0 + i) * 9
		ci.draw_circle(Vector2(bx, by), maxf(0.5, 2.5 + sin(t / 90.0 + i) * 1.5), Color(1, 1, 0.85, 0.7))
	ci.draw_string(_font, Vector2(W / 2 - 40, yy + 46), "LH ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.25, 0.05, 0.8))


func _draw_summit_egg(ci: CanvasItem, t: float) -> void:
	# After ovulation the egg dims softly (the transformation's wind-down).
	var g := clampf(summit_timer / 2.0, 0, 1)
	var k := g * (1.0 - 0.6 * wind)
	var c := Vector2(level_w / 2, p.y - 60 - g * 120)
	var r := 10 + 30 * g
	Draw.radial_glow(ci, c, r * 2.5 + sin(t / 200.0) * 4, Color(1, 0.9, 0.55, 0.6 * k), Color(1, 1, 0.9, 0.95 * k))
	ci.draw_circle(c, r * 0.8, Color("#fff7df", k))
	ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.2), maxf(0.1, r * 0.3), Color("#f9a8d4", k))
	for i in 8:
		var a := t / 600.0 + i * TAU / 8
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * (r + 24 + sin(t / 300.0 + i) * 6), 3, Color(1, 0.95, 0.7, 0.8 * k))


# --- level 2: the meadow (river, vessel, seeds, shadows, gate) --------------------------

func begin_focus() -> void:
	if not is_meadow() or dialog_open or meadow_end > 0 or p.is_dead:
		return
	focus = true
	thread_target = -1
	shield_used = false


func end_focus() -> void:
	if thread_target != -1:
		thread_target = -1
	focus = false
	for sh in shadows:
		sh.fading = true


func _seed_by_id(id: int) -> LevelData.Ent:
	for e in level.entities:
		if e.id == id:
			return e
	return null


## The hand the thread comes from.
func _hand() -> Vector2:
	return Vector2(p.x + p.width / 2 + (10 if p.facing_right else -10), p.y + 26)


func _aim_point() -> Vector2:
	match aim_mode:
		"mouse":
			return aim
		"stick":
			return p.center() + _stick.normalized() * 220 if _stick.length() > 0.3 else p.center() + Vector2(220 if p.facing_right else -220, -60)
		_:
			return p.center() + Vector2(220 if p.facing_right else -220, -60)


## Nearest visible seed inside the thread's range and aiming cone.
func _acquire_seed() -> int:
	var hand := _hand()
	var dir := (_aim_point() - hand)
	if dir.length() < 1:
		return -1
	dir = dir.normalized()
	var best := -1
	var best_d := thread_range()
	for e in level.entities:
		if e.type != "seed" or e.collected or not e.visible:
			continue
		var to := Vector2(e.x + e.w / 2, e.y + e.h / 2) - hand
		var d := to.length()
		if d < best_d and absf(dir.angle_to(to)) < THREAD_CONE:
			best_d = d
			best = e.id
	return best


func _update_meadow(dt: float, d60: float) -> void:
	# The river: swimming. You float, the current carries you back; jump out near the surface.
	if level.water_top >= 0:
		var was := in_water
		in_water = p.y + p.height > level.water_top + 18 and meadow_end == 0
		if in_water:
			p.jumps_left = _max_jumps() - 1 if _max_jumps() > 1 else 1
			if p.jumps_left < 1:
				p.jumps_left = 1
			p.y = minf(p.y, level_h - p.height)
		if in_water and not was:
			end_focus()
			Audio.play_sfx("breathoff.wav", 0.5)
			for i in 12:
				particles.append({"x": p.x + randf() * p.width, "y": level.water_top + 10, "vx": (randf() - 0.5) * 8, "vy": -randf() * 6 - 2,
					"rot": 0.0, "rot_speed": 0.0, "type": "splash", "life": 0.7, "max_life": 0.7})
		if in_water and absf(p.vx) > 0.3 and randf() < 0.25:
			particles.append({"x": p.x + randf() * p.width, "y": level.water_top + 16, "vx": (randf() - 0.5) * 3, "vy": -randf() * 3,
				"rot": 0.0, "rot_speed": 0.0, "type": "splash", "life": 0.5, "max_life": 0.5})
		if p.is_grounded and not in_water:
			last_ground = Vector2(p.x, p.y)
	# The focus thread.
	if focus:
		if dialog_open or p.is_dead:
			end_focus()
		elif thread_target == -1:
			thread_target = _acquire_seed()
		else:
			var e := _seed_by_id(thread_target)
			var hand := _hand()
			if e == null or e.collected or not e.visible:
				thread_target = -1
			else:
				var c := Vector2(e.x + e.w / 2, e.y + e.h / 2)
				var to := hand - c
				if to.length() > thread_range() * 1.4:
					thread_target = -1
				elif to.length() < CATCH_DIST:
					e.collected = true
					thread_target = -1
					Game.seeds += 1
					Audio.play_sfx("finished.wav", 0.6)
					for i in 14:
						particles.append({"x": c.x, "y": c.y, "vx": (randf() - 0.5) * 6, "vy": (randf() - 0.5) * 6 - 2,
							"rot": 0.0, "rot_speed": 0.0, "type": "sparkle", "life": 0.8, "max_life": 0.8})
				else:
					var spd := (PULL_SPEED_DODGE if e.tier == 3 else PULL_SPEED) * dt * (1.5 if water_unlock("pull") else 1.0)
					var step := to.normalized() * spd
					e.x += step.x
					e.y += step.y
					if e.tier == 3:
						e.x += sin(time_ms / 90.0) * 1.2 * d60
	# The shadows: only while a seed is on the thread; more often further in the level.
	if focus and thread_target != -1 and not dialog_open:
		shadow_timer -= dt
		if shadow_timer <= 0:
			var from_left := randf() < 0.5
			var px := p.center().x
			shadows.append({"x": px - W * 0.55 if from_left else px + W * 0.55, "y": p.y + p.height / 2 - 8,
				"vx": SHADOW_SPEED if from_left else -SHADOW_SPEED, "alpha": 0.0, "fading": false})
			shadow_timer = lerpf(4.0, 1.6, clampf(p.x / maxf(1, level_w), 0, 1))
	else:
		shadow_timer = maxf(shadow_timer, 1.0)
	for i in range(shadows.size() - 1, -1, -1):
		var sh: Dictionary = shadows[i]
		sh.x += sh.vx * d60
		if sh.fading:
			sh.alpha -= dt * 3
		else:
			sh.alpha = minf(1, sh.alpha + dt * 3)
			if not focus or thread_target == -1:
				sh.fading = true
			elif absf(sh.x - p.center().x) < 26 and absf(sh.y - p.center().y) < 44:
				if water_unlock("shield") and not shield_used:
					# The dew absorbs the first hit of this focus.
					shield_used = true
					sh.fading = true
					Audio.play_sfx("krcoff.wav", 0.4)
					for k in 10:
						particles.append({"x": p.center().x, "y": p.center().y, "vx": (randf() - 0.5) * 8, "vy": (randf() - 0.5) * 8,
							"rot": 0.0, "rot_speed": 0.0, "type": "splash", "life": 0.6, "max_life": 0.6})
					continue
				# Stress hits: the focus breaks, water spills, the gate moves away.
				end_focus()
				Game.water = maxi(0, Game.water - 15)
				Game.gate_shift = mini(9, Game.gate_shift + 3)
				shake_timer = 0.4
				p.slow_timer = 1.0
				Audio.play_sfx("au%d.wav" % randi_range(1, 5), 0.7)
				sh.fading = true
				trigger.emit("stress_hit")
		if (sh.alpha <= 0 and sh.fading) or absf(sh.x - p.center().x) > W:
			shadows.remove_at(i)
	# The gate: pushed back by stress; locked gates re-arm after a moment.
	for e in level.entities:
		if e.trigger_type == "gate":
			e.x = e.base_x + Game.gate_shift * LevelData.CELL_W
			if e.collected and meadow_end == 0:
				# A locked gate re-arms once the player has stepped away for a moment.
				if gate_locked_timer > 0:
					gate_locked_timer -= dt
				elif not p.rect().intersects(e.rect()):
					e.collected = false
	if meadow_end > 0:
		meadow_end += dt
		p.vx = 0
		if meadow_end > 0.3 and meadow_end < 2.0 and randf() < 0.5:
			particles.append({"x": p.x + p.width / 2 + (randf() - 0.5) * 20, "y": p.y + 40, "vx": (randf() - 0.5) * 2, "vy": 2 + randf() * 2,
				"rot": 0.0, "rot_speed": 0.0, "type": "splash", "life": 0.6, "max_life": 0.6})
		if meadow_end > 4.0 and not _meadow_done_sent:
			_meadow_done_sent = true
			trigger.emit("meadow_done")


func _update_seed(e: LevelData.Ent, dt: float, d60: float) -> void:
	var attached := thread_target == e.id and focus
	match e.tier:
		1:
			e.visible = fmod(time_ms / 1000.0 + e.id * 0.7, 4.0) < 2.5
		2:
			if not attached:
				e.x = e.base_x + sin(time_ms / 1300.0 + e.id) * 70
				e.y = e.base_y + cos(time_ms / 900.0 + e.id) * 30
		3:
			if not attached:
				var dx := e.x - p.center().x
				if absf(dx) < 170 and not dialog_open:
					e.x = clampf(e.x + signf(dx) * 2.2 * d60, e.base_x - 140, e.base_x + 140)
				else:
					e.x += (e.base_x - e.x) * 0.03 * d60
				e.y = e.base_y + sin(time_ms / 500.0 + e.id) * 8
	if not attached and e.tier <= 1:
		# Drifts back home after the thread let go.
		e.x += (e.base_x - e.x) * 0.06 * d60
		e.y += (e.base_y - e.y) * 0.06 * d60 + sin(time_ms / 400.0 + e.id) * 0.3


# --- level 2 drawing -------------------------------------------------------------------

func _draw_meadow_bg() -> void:
	var ci := _bg
	var t := time_ms
	# Sky after rain: pale green-blue to warm gold, soft sun.
	var bands := 12
	for b in bands:
		ci.draw_rect(Rect2(0, H * b / bands, W, H / bands + 1), Color("#bfe3df").lerp(Color("#f1e6b8"), (b + 0.5) / bands))
	Draw.radial_glow(ci, Vector2(W * 0.78, 90), 170, Color(1, 0.95, 0.7, 0.45), Color(1, 1, 0.92, 0.9))
	# Distant hills and trees (parallax).
	for layer in 3:
		var depth := 0.15 + layer * 0.2
		var off := camera_x * depth
		var base_y := 250.0 + layer * 70
		var col := Color("#8fcfae").lerp(Color("#3f8f5f"), layer / 2.0)
		var pts := PackedVector2Array()
		var x := -20.0
		while x <= W + 20:
			var wx := x + off
			pts.append(Vector2(x, base_y + sin(wx * 0.006 + layer) * 40 + sin(wx * 0.017 + layer * 2) * 15))
			x += 20
		pts.append(Vector2(W + 20, H))
		pts.append(Vector2(-20, H))
		Draw.polygon_safe(ci, pts, col)
		# Trees along the hill.
		var tx := -fmod(off, 160.0)
		while tx < W + 80:
			var hy := base_y + sin((tx + off) * 0.006 + layer) * 40 + sin((tx + off) * 0.017 + layer * 2) * 15
			var th := 60 + layer * 20 + fmod(absf(tx + off) * 0.37, 30.0)
			ci.draw_line(Vector2(tx, hy + 8), Vector2(tx, hy - th * 0.4), col.darkened(0.3), 3 + layer)
			ci.draw_circle(Vector2(tx, hy - th * 0.55), th * 0.35, col.darkened(0.15))
			ci.draw_circle(Vector2(tx - th * 0.2, hy - th * 0.35), th * 0.28, col.darkened(0.1))
			ci.draw_circle(Vector2(tx + th * 0.2, hy - th * 0.38), th * 0.26, col.darkened(0.2))
			tx += 160
	# Drizzle sparkle / pollen in the air.
	for i in 24:
		var px := fmod(i * 211.0 - camera_x * 0.5 + sin(t / 1200.0 + i) * 20 + 4000 * W, W)
		var py := fmod(i * 131.0 + t * 0.02 * (1 + i % 3), H)
		ci.draw_circle(Vector2(px, py), 1.5 + (i % 3) * 0.5, Color(1, 1, 0.85, 0.5))


## Behind the platforms: the river.
func _draw_meadow_back(ci: CanvasItem, t: float, left: float, right: float) -> void:
	if level.water_top < 0:
		return
	var wy := level.water_top + 14
	var pts := PackedVector2Array()
	var x := left
	while x <= right:
		pts.append(Vector2(x, wy + sin(t / 400.0 - x / 70.0) * 4 + cos(t / 650.0 - x / 40.0) * 2))
		x += 20
	pts.append(Vector2(right, level_h + 50))
	pts.append(Vector2(left, level_h + 50))
	Draw.polygon_safe(ci, pts, Color("#3f8fd6", 0.85))
	# The current flows left (against the player): streaks drifting left.
	for i in 30:
		var sx := right - fmod(t * 0.09 + i * 173.0, right - left)
		var sy := wy + 18 + fmod(i * 47.0, level_h - wy - 30)
		ci.draw_line(Vector2(sx, sy), Vector2(sx + 26, sy), Color(1, 1, 1, 0.22), 2.0)
	var glow := PackedVector2Array()
	for i in range(0, pts.size() - 2):
		glow.append(pts[i])
	ci.draw_polyline(glow, Color(0.85, 0.95, 1.0, 0.9), 3.0, true)


## In front of the platforms: the shadows and the end flower.
func _draw_meadow_front(ci: CanvasItem, t: float, left: float, right: float) -> void:
	for sh in shadows:
		var a: float = clampf(sh.alpha, 0, 1)
		var c := Vector2(sh.x, sh.y + sin(t / 120.0 + sh.x) * 4)
		if not SpriteArt.draw(ci, "shadow", c, SpriteArt.DEFS.shadow.size, t + sh.x, Color(1, 1, 1, a)):
			SpriteArt.draw_shadow(ci, c, t, a, sh.x)
	if meadow_end > 0:
		# The poured water sinks in and a golden flower grows.
		var k := clampf((meadow_end - 1.2) / 2.0, 0, 1)
		var base := Vector2(p.x + p.width / 2 + 40, p.y + p.height)
		if k > 0:
			ci.draw_line(base, base + Vector2(0, -120 * k), Color("#3f8f3f"), 5.0)
			for i in 8:
				var ang := -PI / 2 + (i - 3.5) * 0.45
				var tip := base + Vector2(0, -120 * k) + Vector2(cos(ang), sin(ang)) * 34 * k
				ci.draw_line(base + Vector2(0, -120 * k), tip, Color("#f5c842"), 10.0 * k)
			ci.draw_circle(base + Vector2(0, -120 * k), 12 * k, Color("#fff1a8"))
			Draw.radial_glow(ci, base + Vector2(0, -120 * k), 140 * k, Color(1, 0.9, 0.5, 0.5 * k), Color(1, 1, 0.9, 0.9 * k))


func _draw_meadow_platform(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	# Earth with a grassy top; stones peeking out.
	var body := Rect2(pl.x, pl.y + 4, pl.w, pl.h + 36)
	Draw.panel(ci, body, Color("#6b4a2b"), 8)
	Draw.panel(ci, Rect2(pl.x - 2, pl.y - 2, pl.w + 4, 14), Color("#4fae5a"), 6)
	var m := 6.0
	while m < pl.w - 6:
		var gx := pl.x + m
		var sway := sin(t / 600.0 + gx * 0.05) * 3
		ci.draw_line(Vector2(gx, pl.y), Vector2(gx + sway, pl.y - 10 - fmod(gx * 0.7, 6.0)), Color("#7fd68a"), 2.0)
		m += 11
	m = 18
	while m < pl.w - 18:
		ci.draw_circle(Vector2(pl.x + m, pl.y + 30), 6, Color("#8c7a66"))
		m += 57


func _draw_drop(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 300.0 + e.id) * 3)
	if not SpriteArt.draw(ci, "drop", c, SpriteArt.DEFS.drop.size, t + e.id * 137.0):
		SpriteArt.draw_drop(ci, c)


func _draw_seed(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	if not e.visible:
		return
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 350.0 + e.id) * 4)
	var pulse := 0.5 + 0.5 * sin(t / 220.0 + e.id)
	var a := 1.0
	if e.tier == 1:
		var ph := fmod(t / 1000.0 + e.id * 0.7, 4.0)
		a = clampf(minf(ph / 0.3, (2.5 - ph) / 0.3), 0, 1)
	if not SpriteArt.draw(ci, "seed", c, SpriteArt.DEFS.seed.size, t + e.id * 137.0, Color(1, 1, 1, a)):
		SpriteArt.draw_seed(ci, c, pulse, a)
	if thread_target == e.id and focus:
		ci.draw_arc(c, 16 + pulse * 3, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)


func _draw_thread(ci: CanvasItem, t: float) -> void:
	var e := _seed_by_id(thread_target)
	if e == null:
		return
	var a := _hand()
	var b := Vector2(e.x + e.w / 2, e.y + e.h / 2)
	var pts := PackedVector2Array()
	for i in 17:
		var k := i / 16.0
		var pt := a.lerp(b, k)
		pt.y += sin(k * PI) * 10 * sin(t / 120.0)
		pts.append(pt)
	ci.draw_polyline(pts, Color(1, 0.95, 0.6, 0.9), 2.5, true)
	for i in 5:
		var k := fmod(t / 600.0 + i / 5.0, 1.0)
		ci.draw_circle(a.lerp(b, k), 3, Color(1, 1, 0.8, 0.9))


func _draw_gate(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var gx := e.x + e.w / 2
	var gy := (level.water_top if level.water_top > 0 else H) - 60
	var open := Game.water >= 100 and Game.seeds >= Game.SEEDS_NEEDED
	var col := Color("#f5c842") if open else Color("#9fb89f")
	# Two vines arching into a gate.
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 13:
			var k := i / 12.0
			pts.append(Vector2(gx + side * (58 - 50 * k * k), gy - 190 * k))
		ci.draw_polyline(pts, Color("#3f8f3f"), 7.0, true)
		for i in range(2, 12, 3):
			var k := i / 12.0
			var lp := Vector2(gx + side * (58 - 50 * k * k), gy - 190 * k)
			ci.draw_set_transform(lp, side * 0.8 + sin(t / 700.0 + i) * 0.1, Vector2(1, 0.5))
			ci.draw_circle(Vector2.ZERO, 9, Color("#4fae5a"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for i in 5:
		var ang := PI + i / 4.0 * PI
		var fp := Vector2(gx, gy - 190) + Vector2(cos(ang), sin(ang)) * 30
		ci.draw_circle(fp, 8 + (sin(t / 300.0 + i) * 2 if open else 0.0), col)
	Draw.radial_glow(ci, Vector2(gx, gy - 100), 90 if open else 50, Color(col, 0.35 if open else 0.15))
	if not open:
		var txt := "%d/100  ·  %d/%d" % [Game.water, Game.seeds, Game.SEEDS_NEEDED]
		Draw.text_center(ci, _font, Vector2(gx, gy - 215), txt, 14, Color("#2f5d3f", 0.9))


# --- after the boss: the corridor into the forest -------------------------------------

## Opens the corridor in the middle of the arena; Kyra walks to it.
func open_corridor() -> void:
	corridor_t = 0.01
	walk_to_x = W / 2


func _draw_corridor(ci: CanvasItem, t: float) -> void:
	var k := clampf(corridor_t / 1.4, 0, 1)
	var floor_y := camera_y + H - 40
	var w := 280.0 * k
	var h := 340.0
	var r := Rect2(W / 2 - w / 2, floor_y - h, w, h)
	if w < 2:
		return
	Draw.radial_glow(ci, Vector2(W / 2, floor_y - h * 0.45), 260 * k, Color(1, 0.95, 0.75, 0.35 * k))
	# Inside: a forest path running away to a bright horizon.
	var hz := r.position.y + h * 0.45
	for b in 6:
		ci.draw_rect(Rect2(r.position.x, r.position.y + (hz - r.position.y) * b / 6.0, w, (hz - r.position.y) / 6.0 + 1), Color("#a8d8cf").lerp(Color("#f3f0c8"), b / 6.0))
	ci.draw_rect(Rect2(r.position.x, hz, w, r.end.y - hz), Color("#4f8a4f"))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(W / 2 - 6, hz), Vector2(W / 2 + 6, hz), Vector2(W / 2 + w * 0.42, r.end.y), Vector2(W / 2 - w * 0.42, r.end.y)]), Color("#b48a5a"))
	for i in 5:
		var d := 1.0 - i / 5.0
		var tx := w * (0.18 + 0.32 * d)
		var th := h * (0.15 + 0.5 * d)
		for side: float in [-1.0, 1.0]:
			var bx: float = W / 2 + side * tx
			ci.draw_line(Vector2(bx, hz + 4 + 60 * d), Vector2(bx, hz - th * 0.4), Color("#3d2a1a"), 2 + 5 * d)
			ci.draw_circle(Vector2(bx, hz - th * 0.45), 8 + 22 * d, Color("#2f6b3a").lerp(Color("#9fc9a8"), 1.0 - d))
	# The rough edge of the opening.
	ci.draw_rect(r, Color("#3b0a0a"), false, 6.0)
	Draw.radial_glow(ci, Vector2(W / 2, hz), 60 * k, Color(1, 1, 0.9, 0.7 * k))


# --- the jackpot climb (level 5): placeholder art (the gameplay pass replaces it) ---

## Spring / boost pad: a gold coil on the platform below it.
func _draw_spring(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var gold := Color("#fbbf24")
	var base := Rect2(e.x, e.y + e.h - 6, e.w, 6)
	ci.draw_rect(base, Color("#92400e"))
	var squeeze := 1.0 + sin(t / 180.0 + e.id) * 0.08
	var top_y := e.y + e.h - 6 - (e.h - 10) * squeeze
	for i in 3:
		var yy := lerpf(e.y + e.h - 8, top_y + 4, (i + 0.5) / 3.0)
		ci.draw_line(Vector2(e.x + 6, yy + 3), Vector2(e.x + e.w - 6, yy - 3), gold, 3)
	ci.draw_rect(Rect2(e.x - 2, top_y, e.w + 4, 6), gold)


## A heart (pink, glossy, turning and bobbing); a SpriteArt "heart" variant replaces it.
func _draw_heart(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 400.0 + e.id) * 3)
	if SpriteArt.draw(ci, "heart", c, SpriteArt.DEFS.heart.size, t + e.id * 137.0):
		return
	SpriteArt.draw_heart(ci, c, e.w * 0.55, cos(t / 420.0 + e.id * 0.7))


## A bell (gold, swinging): +1 ready heart.
func _draw_bell(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 350.0 + e.id) * 3)
	Draw.radial_glow(ci, c, e.w * 1.1, Color(1, 0.85, 0.3, 0.3))
	if SpriteArt.draw(ci, "bell", c, SpriteArt.DEFS.bell.size, t + e.id * 137.0):
		return
	SpriteArt.draw_bell(ci, c, e.w * 0.5, sin(t / 260.0 + e.id) * 0.3)


## A joker (a card with a jester's hat), bobbing: the spinner top-left spins.
func _draw_joker(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 300.0 + e.id) * 4)
	Draw.radial_glow(ci, c, e.w, Color(250 / 255.0, 204 / 255.0, 21 / 255.0, 0.35))
	if SpriteArt.draw(ci, "joker", c, SpriteArt.DEFS.joker.size, t + e.id * 137.0):
		return
	SpriteArt.draw_joker(ci, c, e.h, sin(t / 500.0 + e.id) * 0.12)


## The wheel row (mg11): a pink dashed line across the level, little wheels turning on it.
func _draw_wheel_row(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var y := e.y + e.h / 2
	var a := 0.55 + sin(t / 260.0) * 0.2
	var x := fposmod(t * 0.04, 40.0) - 40.0
	while x < level_w:
		ci.draw_line(Vector2(x, y), Vector2(x + 22, y), Color(0.98, 0.45, 0.65, a), 4)
		x += 40.0
	for k in 3:
		var cx := level_w * (0.2 + 0.3 * k)
		FertilityWheel.draw_mini(ci, Vector2(cx, y - 34), 26, t / 600.0 + k)


## Jackpot row: a gold line across the level.
func _draw_jackpot_row(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var y := e.y + e.h / 2
	var a := 0.35 if e.collected else 0.6 + sin(t / 200.0) * 0.25
	ci.draw_line(Vector2(0, y), Vector2(level_w, y), Color(250 / 255.0, 204 / 255.0, 21 / 255.0, a), 4)
	for i in 13:
		var x := fposmod(i * level_w / 12.0 + t * 0.05, level_w)
		ci.draw_circle(Vector2(x, y), 4, Color(1, 0.95, 0.6, a))


# --- the jackpot climb (level 5): the board, springs, hearts, bells, jokers -------------

## Camera with the board's top edge a little below her feet (start / checkpoints); the
## board waits RISE_GRACE before it starts rising.
func _board_camera() -> void:
	camera_y = maxf(0, p.y + p.height + 60 - (H - BOARD_H) / view_zoom)
	last_stand_y = p.y + p.height
	_reset_rise()
	rise_wait = RISE_GRACE


## The board's top edge in world coordinates (she stands / sits on it).
func board_y() -> float:
	return world_y(H - BOARD_H)


## The board's rise back to its starting speed (start, checkpoint, caught; it doesn't stop).
func _reset_rise() -> void:
	rise = RISE_START
	on_board = false


## The board caught her: she sits down and rides it up; the board slows down to
## RISE_START but keeps rising.
func _caught() -> void:
	_reset_rise()
	on_board = true
	# Hopping on the board doesn't repeat the calm line (or the sound) every time.
	if time_ms - _rest_ms > 8000.0:
		_rest_ms = time_ms
		Audio.play_sfx("breathok.wav", 0.25)
		ticker_say(Text.plain(Text.t("CLIMB_REST")))


## The camera rises on its own (the board chases her) and follows her up; never down.
## The rise never pauses (she sits on the board, a board dialog talks …), except for
## the short wait at the start / a checkpoint (rise_wait) and after the top.
func _climb_camera(dt: float, d60: float) -> void:
	# Follow her up to the middle, but don't lift the board past the platform she last
	# stood on (it would catch every fall back from a boost or a missed jump) unless
	# she would leave the top of the screen.
	var follow := maxf(p.y - view_h() / 2, last_stand_y - (H - BOARD_H) / view_zoom)
	if follow < camera_y:
		camera_y += (follow - camera_y) * (1.0 - pow(0.85, d60))
	# The thrusters climb fast: keep more room above her while they burn (eased), but
	# only as much as the guard above allows (the board stays under her last platform)
	# unless the board has already passed it.
	# (FUEL_GUARD_SLACK below it: the platforms bob).
	var guard := last_stand_y + FUEL_GUARD_SLACK - (H - BOARD_H) / view_zoom
	var lead := CLIMB_TOP_MARGIN
	if thrusting:
		lead = view_h() * FUEL_VIEW_LEAD
		if camera_y >= guard:
			lead = clampf(p.y - guard, CLIMB_TOP_MARGIN, lead)
	_top_margin = move_toward(_top_margin, lead, 6.0 * d60)
	camera_y = minf(camera_y, p.y - _top_margin)
	if not climb_won and camera_y > 0:
		if rise_wait > 0:
			rise_wait -= dt
		else:
			rise = minf(RISE_MAX, rise + RISE_ACCEL * dt)
			camera_y -= rise * d60
	camera_y = clampf(camera_y, 0, level_h)


func _update_climb(dt: float, d60: float) -> void:
	if boost_t > 0:
		boost_t -= dt
	# Timed power-ups (paused while a dialog talks, and while the board explains the
	# power-up or it waits to, so it never runs out before its explanation is over).
	if not dialog_open:
		for k in climb_power.keys():
			if k != "rocket" and board_talking(str(POWER_DIALOG.get(k, "-"))):
				continue
			climb_power[k] -= dt
			if climb_power[k] <= 0:
				climb_power.erase(k)
	if climb_power.has("rocket") or (boost_t > 0 and p.vy < -6):
		var flame := climb_power.has("rocket")
		for i in 2:
			particles.append({"x": p.x + p.width / 2 + (randf() - 0.5) * 14, "y": p.y + p.height + 4,
				"vx": (randf() - 0.5) * 2, "vy": 2 + randf() * 3, "rot": 0.0, "rot_speed": 0.0,
				"type": "flame" if flame else "glint", "life": 0.4, "max_life": 0.4})
	floor_now = floor_of(p.y + p.height)
	best_floor = maxi(best_floor, floor_now)
	heart_short = maxf(0.0, heart_short - dt)
	# The reserve reloads the magazine (a click per heart that lands).
	if meter.update(dt) > 0:
		Audio.play_sfx("cink-%02d.wav" % (4 + 2 * mini(meter.land_i, 3)), 0.32)
	# Pink sparks around her while she has hearts ready to spend.
	if hearts > 0 and randf() < 0.025 * hearts * d60:
		particles.append({"x": p.x + p.width / 2 + (randf() - 0.5) * 60, "y": p.y + randf() * p.height,
			"vx": (randf() - 0.5) * 1.2, "vy": -0.6 - randf(), "rot": 0.0, "rot_speed": 0.0,
			"type": "heart", "life": 0.7, "max_life": 0.7})
	_update_slot(dt)
	if not banner.is_empty():
		banner.t += dt
		if banner.t > 1.8:
			banner = {}
	for i in range(pops.size() - 1, -1, -1):
		var pp: Dictionary = pops[i]
		pp.t += dt
		pp.y -= 45.0 * dt
		if pp.t >= pp.life:
			pops.remove_at(i)
	if phase_note.is_empty():
		_update_board_talk(dt)
	if board_talk.is_empty() and prerod_t < 0 and phase_note.is_empty():
		# (The transformation stops the ticker: its letters drift away, PlatformerHud.)
		_update_ticker(dt)


func _pop(at: Vector2, text: String, col: Color, size := 22) -> void:
	pops.append({"x": at.x, "y": at.y, "text": text, "col": col, "size": size, "t": 0.0, "life": 1.0})
	if pops.size() > 24:
		pops.pop_front()


func _say_banner(text: String) -> void:
	banner = {"text": text, "t": 0.0}


func _sparkles(at: Vector2, n: int, kind := "glint") -> void:
	for i in n:
		var a := randf() * TAU
		var v := 2.0 + randf() * 4.0
		particles.append({"x": at.x, "y": at.y, "vx": cos(a) * v, "vy": sin(a) * v, "rot": 0.0, "rot_speed": 0.0,
			"type": kind, "life": 0.7, "max_life": 0.7})


## Gold coins rain from the top of the screen.
func _coin_shower(n: int) -> void:
	for i in n:
		particles.append({"x": camera_x + randf() * view_w(), "y": camera_y - 20 - randf() * 200, "vx": (randf() - 0.5) * 3,
			"vy": randf() * 3, "rot": randf() * TAU, "rot_speed": 0.15 + randf() * 0.2, "type": "coin",
			"life": 2.6 + randf() * 0.8, "max_life": 3.4})


## JACKPOT: a jackpot row (a checkpoint), the top. No score: the banner, coins, a fanfare.
func _jackpot() -> void:
	jackpots += 1
	_say_banner(Text.plain(Text.t("CLIMB_JACKPOT")))
	_coin_shower(60)
	_sparkles(p.center(), 24)
	shake_timer = maxf(shake_timer, 0.2)
	Audio.play_sfx("finished.wav", 0.6)
	Audio.play_sfx("cink-11.wav", 0.5)
	ticker_say(Text.plain(Text.t("CLIMB_JACKPOT")))


## A launch (spring, heart boost, rocket): the thrusters wait for its top; a held jump
## then ignites them.
func _launched() -> void:
	thrusting = false
	_fuel_armed = true


## A spring pad: a big launch up, jumps refilled, BOOST!
func _spring(e: LevelData.Ent) -> void:
	e.lunge_timer = 0.5
	p.vy = -SPRING_FORCE
	p.is_grounded = false
	p.was_grounded = false
	p.jumped_from_ground = true
	p.coyote = 0
	p.jump_buffer = 0
	p.jumps_left = _max_jumps()
	p.is_sitting = false
	p.squash = -0.8
	boost_t = 1.0
	_launched()
	var at := Vector2(e.x + e.w / 2, e.y)
	_sparkles(at, 16)
	_pop(at + Vector2(0, -40), Text.plain(Text.t("CLIMB_BOOST")), Color("#fbbf24"), 26)
	Audio.jump_sound(true)
	Audio.play_sfx("cink-10.wav", 0.4)
	ticker_say(Text.plain(Text.t("CLIMB_BOOST")))


## A heart: HEART_FILL of one, into the magazine (or the reserve when it is full).
func _take_heart(e: LevelData.Ent) -> void:
	e.collected = true
	hearts_taken += 1
	_heart_note = _heart_note % 11 + 1
	Audio.play_sfx("cink-%02d.wav" % _heart_note, 0.35)
	add_heart_fill(HEART_FILL)
	_sparkles(Vector2(e.x + e.w / 2, e.y + e.h / 2), 5, "heart")


## Fills the heart meter by `amount` % of a heart: the magazine first, then the reserve
## (the same meter as the forest run's water, MeterModel). A chime when a heart in the
## magazine becomes whole.
func add_heart_fill(amount: float) -> Vector2:
	var before := hearts
	var r := meter.fill(amount)
	if hearts > before:
		Audio.play_sfx("cink-11.wav", 0.3)
	# The first heart of a climb that goes into the reserve: the board explains the rule.
	if r.y > MeterModel.EPS and not powers_explained.has(RESERVE_DIALOG) and is_climb():
		powers_explained[RESERVE_DIALOG] = true
		board_dialog(RESERVE_DIALOG)
	return r


## Spends hearts from the magazine (the reserve reloads it later); false (and the missing
## ones blink) if there aren't enough.
func spend_hearts(n: int) -> bool:
	if not meter.spend(float(n)):
		heart_short = 0.6
		return false
	return true


## Hearts left as rocket fuel: the magazine (the top one may be part-burnt; the burn
## drains the magazine itself, MeterModel.drain).
func fuel_left() -> float:
	return meter.mag


## Rocket fuel (after gravity, every frame in the climb): jump held once her rise has run
## out ignites the thrusters; they climb fast and burn hearts until jump is let go, the
## hearts run out, she lands or nears the level's top.
func _update_fuel(dt: float, d60: float) -> void:
	var held := active and not hold_input and not dialog_open and Input.is_action_pressed("jump")
	if not held:
		# Let go: a later press in the air (with no jump left) is only a buffered jump.
		_fuel_wait_release = false
		_fuel_armed = false
	# Ignite with at least FUEL_MIN of a heart in the magazine; burn it down to empty.
	var fuel_ok := meter.mag > (MeterModel.EPS if thrusting else FUEL_MIN)
	var can := held and fuel_ok and not climb_won and not p.is_grounded and p.hit_timer <= 0 and p.y > FUEL_CEIL and prerod_t < 0
	if thrusting and not can:
		thrusting = false
	elif not thrusting and can and _fuel_armed and not _fuel_wait_release and p.vy >= FUEL_IGNITE_VY:
		thrusting = true
		_thrust_sfx = 0.0
		p.is_sitting = false
		on_board = false
		Audio.play_sfx("breathoff.wav", 0.5)
		_sparkles(Vector2(p.x + p.width / 2, p.y + p.height), 8)
	if not thrusting:
		return
	if boost_t > 0 and p.vy < -FUEL_SPEED:
		# A launch (spring, heart boost, rocket) outruns the thrusters: they wait.
		return
	if p.vy > -FUEL_SPEED:
		p.vy = maxf(p.vy - FUEL_ACCEL * d60, -FUEL_SPEED)
	# The burn drains the magazine itself (a part-burnt heart is part of the meter: the next
	# pickup fills it, the reload tops it up); spending holds a part-empty reload.
	meter.drain(dt / FUEL_HEART_TIME)
	if meter.mag <= MeterModel.EPS:
		# Out of fuel: she falls (the empty magazine reloads at once); a new press lights
		# the thrusters again.
		thrusting = false
		_fuel_wait_release = true
		heart_short = 0.4
		Audio.play_sfx("breath_after.wav", 0.35)
	# The flame under her feet (flickering), the thruster's hum.
	var feet := Vector2(p.x + p.width / 2, p.y + p.height)
	_flame_acc += dt * 180.0
	while _flame_acc >= 1.0:
		_flame_acc -= 1.0
		particles.append({"x": feet.x + (randf() - 0.5) * 16 + sin(time_ms / 30.0) * 3, "y": feet.y + randf() * 6,
			"vx": (randf() - 0.5) * 1.6, "vy": p.vy * 0.7 + 2 + randf() * 3, "rot": 0.0, "rot_speed": 0.0,
			"type": "flame", "life": 0.35, "max_life": 0.35})
	_thrust_sfx -= dt
	if _thrust_sfx <= 0:
		_thrust_sfx = 0.28
		Audio.play_sfx("breathoff.wav", 0.18)


## A bell: one more heart at once (into the magazine, or the reserve when it is full), a chime.
func _ring_bell(e: LevelData.Ent) -> void:
	e.collected = true
	bells += 1
	var got := add_heart_fill(100.0)
	# A full meter takes nothing: then no "+1 heart", just the chime.
	var key := "CLIMB_BELL" if got.x + got.y > 0.001 else "CLIMB_BELL_FULL"
	var at := Vector2(e.x + e.w / 2, e.y)
	_sparkles(at + Vector2(0, e.h / 2), 14)
	_sparkles(at + Vector2(0, e.h / 2), 6, "heart")
	_pop(at + Vector2(0, -20), Text.plain(Text.t(key)), Color("#fde68a"), 24)
	Audio.play_sfx("cink-09.wav", 0.5)
	Audio.play_sfx("cink-11.wav", 0.45)
	ticker_say(Text.plain(Text.t(key)))
	# The spinner top-left spins a short while and settles on three bells (no pay-out:
	# the bell's +1 heart is given above). A joker's spin still running is paid first.
	if not slot_spin.is_empty() and not slot_spin.paid:
		_pay_slot()
	slot_spin = {"t": 0.0, "kind": "bell", "power": "", "stops": 0, "stop_at": BELL_STOPS, "result": ["bell", "bell", "bell"], "paid": true}


## The heart boost (Shift / B): a launch up like a spring for HEART_BOOST_COST hearts.
func heart_boost() -> bool:
	if climb_won or hold_input or not spend_hearts(HEART_BOOST_COST):
		return false
	p.vy = -HEART_BOOST_FORCE
	p.is_grounded = false
	p.was_grounded = false
	p.jumped_from_ground = true
	p.coyote = 0
	p.jump_buffer = 0
	p.jumps_left = _max_jumps()
	p.is_sitting = false
	p.squash = -0.8
	on_board = false
	boost_t = 1.0
	_launched()
	_sparkles(p.center(), 10)
	_sparkles(Vector2(p.x + p.width / 2, p.y + p.height), 12, "heart")
	_pop(p.center() + Vector2(0, -60), Text.plain(Text.t("CLIMB_HEART_BOOST")), Color("#f9a8d4"), 24)
	Audio.jump_sound(true)
	Audio.play_sfx("cink-10.wav", 0.4)
	return true


## A joker: the spinner top-left spins and always pay out a power-up.
func _take_joker(e: LevelData.Ent) -> void:
	e.collected = true
	if not slot_spin.is_empty() and not slot_spin.paid:
		_pay_slot()
	slot_spin = {"t": 0.0, "kind": "joker", "power": _next_power(), "stops": 0, "stop_at": SLOT_STOPS, "result": ["joker", "joker", "joker"], "paid": false}
	_sparkles(Vector2(e.x + e.w / 2, e.y + e.h / 2), 14)
	Audio.play_sfx("click.wav", 0.5)
	ticker_say("? ? ?")


## Back from the wheel of the cycle (mg11): the climb goes on where she was, the board
## waits RISE_GRACE, and Estrogenka sums it up on the board.
func after_wheel() -> void:
	rise_wait = RISE_GRACE
	thrusting = false
	_fuel_armed = false
	_fuel_wait_release = true
	p.vy = minf(p.vy, 0.0)
	board_dialog("mg11_after")


## The next power-up from a shuffled bag (every one comes up).
func _next_power() -> String:
	if _power_bag.is_empty():
		_power_bag = POWERS.duplicate()
		_power_bag.shuffle()
		if not powers_explained.has("super_jump"):
			# The first joker of a climb pays the super jump: its explanation (3A) also
			# introduces the jokers.
			_power_bag.erase("super_jump")
			_power_bag.append("super_jump")
	return _power_bag.pop_back()


func _update_slot(dt: float) -> void:
	if slot_spin.is_empty():
		return
	slot_spin.t += dt
	var stop_at: Array = slot_spin.stop_at
	while slot_spin.stops < stop_at.size() and slot_spin.t >= stop_at[slot_spin.stops]:
		slot_spin.stops += 1
		Audio.play_sfx("click.wav", 0.6)
	if slot_spin.stops >= stop_at.size():
		spin_rest = slot_spin.result.duplicate()
	if not slot_spin.paid and slot_spin.t >= SLOT_SPIN:
		_pay_slot()
	if slot_spin.t > float(stop_at[stop_at.size() - 1]) + 0.6:
		slot_spin = {}


func _pay_slot() -> void:
	slot_spin.paid = true
	slot_spin.stops = SLOT_STOPS.size()
	spin_rest = slot_spin.result.duplicate()
	grant_power(slot_spin.power)
	_coin_shower(30)
	Audio.play_sfx("finished.wav", 0.45)


## Gives a power-up: super_jump / triple / magnet last POWER_TIME s, the rocket fires now.
func grant_power(name: String) -> void:
	if name == "rocket":
		p.vy = -ROCKET_FORCE
		p.is_grounded = false
		p.was_grounded = false
		p.jumped_from_ground = true
		p.coyote = 0
		p.is_sitting = false
		p.jumps_left = _max_jumps()
		boost_t = ROCKET_TIME
		climb_power["rocket"] = ROCKET_TIME
		_launched()
		Audio.play_sfx("breathoff.wav", 0.5)
	else:
		climb_power[name] = POWER_TIME
	var label := Text.plain(Text.t("CLIMB_PU_" + name.to_upper()))
	_say_banner(label)
	_sparkles(p.center(), 20)
	ticker_say(label)
	if POWER_DIALOG.has(name) and not powers_explained.has(name):
		# The first time in this climb: the board explains it.
		powers_explained[name] = true
		board_dialog(POWER_DIALOG[name])


## Plays a dialogs.json node on the board (the climb has no dialog box): each part with
## its speaker's portrait for a reading time, then the next, then the ticker again. Not
## modal, no buttons; play and the rise go on. A newer one waits for the current one.
## board_dialog_done(id) when its last part is over.
func board_dialog(id: String) -> void:
	if not Text.dialogs.has(id):
		push_warning("Unknown dialog " + id)
		return
	if board_talk.get("id", "") == id or board_queue.has(id):
		return
	if board_talk.is_empty():
		_board_part(id, 0)
	else:
		board_queue.append(id)


## Is a dialog (this one, or any with "") talking on the board or waiting for it?
func board_talking(id := "") -> bool:
	if id == "":
		return not board_talk.is_empty()
	return board_talk.get("id", "") == id or board_queue.has(id)


## The board dialog's next part now (tests; the reading time does it in play).
func board_next() -> void:
	if not board_talk.is_empty():
		_board_part(board_talk.id, int(board_talk.part) + 1)


## Reading time (s) of a board dialog line.
static func board_read_time(text: String) -> float:
	return clampf(BOARD_READ_BASE + text.length() * BOARD_READ_CHAR, BOARD_READ_MIN, BOARD_READ_MAX)


## The text of a dialog line as the board shows it (plain, this language and control mode).
static func board_line(key: String) -> String:
	return Text.plain(Text.t(key))


## The largest DialogBox.TEXT_SIZES size at which a line fits the board's text area
## (-1 = it doesn't fit even at the smallest).
static func board_text_size(text: String) -> int:
	for size in DialogBox.TEXT_SIZES:
		var h := Text.font_dialog.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, BOARD_TEXT.size.x, size).y
		if h <= BOARD_TEXT.size.y:
			return size
	return -1


func _board_part(id: String, part: int) -> void:
	var node: Dictionary = Text.dialogs.get(id, {})
	var parts: Array = node.get("parts", [])
	if part >= parts.size():
		board_talk = {}
		board_dialog_done.emit(id)
		if board_talk.is_empty() and not board_queue.is_empty():
			_board_part(board_queue.pop_front(), 0)
		return
	var pd: Dictionary = parts[part]
	var key: String = pd.get("text", "")
	board_talk = {"id": id, "part": part, "t": 0.0, "dur": board_read_time(board_line(key)),
		"speaker": str(pd.get("speaker", "")), "key": key}
	Audio.play_voice(Text.voice_file(key))


func _update_board_talk(dt: float) -> void:
	if board_talk.is_empty():
		return
	board_talk.t += dt
	if board_talk.t >= board_talk.dur:
		board_next()


## Puts an event line on the board's ticker (it comes next, the ticker hurries to it).
func ticker_say(s: String) -> void:
	ticker_queue.append(s)
	while ticker_queue.size() > 4:
		ticker_queue.pop_front()


## Scrolls the ticker right → left and feeds it: event lines first, then the facts.
func _update_ticker(dt: float) -> void:
	var speed := TICKER_SPEED * (2.5 if not ticker_queue.is_empty() else 1.0)
	for seg in ticker:
		seg.x -= speed * dt
	while not ticker.is_empty() and ticker[0].x + ticker[0].w < TICKER_LEFT:
		ticker.pop_front()
	var guard := 0
	while guard < 8:
		guard += 1
		var x := TICKER_LEFT + 12.0
		if not ticker.is_empty():
			x = ticker[-1].x + ticker[-1].w + TICKER_GAP
		if x > W:
			break
		var event := not ticker_queue.is_empty()
		var text := ""
		if event:
			text = ticker_queue.pop_front()
		else:
			text = Text.plain(Text.t("CLIMB_TICK_%d" % (_tick_next % 8 + 1)))
			_tick_next += 1
		var w := Text.font_bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TICKER_FS).x
		ticker.append({"text": text, "x": x, "w": w, "event": event})


func _draw_casino_lights() -> void:
	var ci := _bg
	var t := time_ms
	# Twinkling lights drifting down slowly (parallax), gold and pink. When the casino
	# winds down (the transformation) they slow, fade and drip downwards.
	var vw := view_w()
	var vh := view_h()
	if prerod_t >= 0:
		t = _light_t
	var drip_t := maxf(0.0, prerod_t) * wind
	for i in int(40 * vw * vh / (W * H)):
		var px := fmod(i * 263.0 + 17.0 * i * i, vw)
		var py := fposmod(i * 151.0 - camera_y * (0.08 + 0.02 * (i % 4)), vh)
		py += drip_t * drip_t * (14.0 + 9.0 * (i % 5))
		var tw := 0.5 + 0.5 * sin(t / (220.0 + 13.0 * (i % 7)) + i)
		var col := Color(1, 0.85, 0.35) if i % 3 else Color(1, 0.55, 0.8)
		col = col.lerp(Color(0.85, 0.7, 0.95), wind)
		var fade := 1.0 - 0.55 * wind
		ci.draw_circle(Vector2(px, py), 1.5 + 2.0 * tw, Color(col, (0.25 + 0.5 * tw) * fade))
		if wind > 0:
			ci.draw_line(Vector2(px, py), Vector2(px, py - 4 - 10 * wind), Color(col, 0.25 * wind * fade), 2.0)
		if tw > 0.92 and wind < 0.5:
			ci.draw_line(Vector2(px - 6, py), Vector2(px + 6, py), Color(col, 0.6), 1.0)
			ci.draw_line(Vector2(px, py - 6), Vector2(px, py + 6), Color(col, 0.6), 1.0)


## A platform in the climb: a purple casino step with a gold edge and running lights.
func _draw_climb_platform(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var r := Rect2(pl.x + 2, pl.y, pl.w - 4, 18)
	Draw.panel(ci, Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.25), 9)
	Draw.panel(ci, r, Color("#4c1d95"), 9, Color("#fbbf24"), 2)
	var n := int(r.size.x / 18)
	for i in n:
		var on := (i + int(t / 160.0)) % 3 == 0
		ci.draw_circle(Vector2(r.position.x + 9 + i * 18, r.position.y + 9), 3, Color("#fef08a") if on else Color("#a78bfa", 0.7))


# --- the PMS maze (level 6): walls, comfort items, the door, her light (energy, rest) ----

func _overlaps(r: Rect2) -> bool:
	return p.x + p.width > r.position.x + 0.5 and p.x < r.end.x - 0.5 and p.y + p.height > r.position.y + 0.5 and p.y < r.end.y - 0.5


## Walls stop her sideways (resolved before the vertical move).
func _walls_x(prev_x: float) -> void:
	for r in level.walls:
		if not _overlaps(r):
			continue
		if prev_x + p.width <= r.position.x + 1.0:
			p.x = r.position.x - p.width
		elif prev_x >= r.end.x - 1.0:
			p.x = r.end.x
		else:
			continue
		p.vx = 0


## Walls from below (a bump on the head) and anything still inside one (resolved after
## the vertical move; landing on their tops is the platform code, wall_tops).
func _walls_y() -> void:
	for r in level.walls:
		if not _overlaps(r):
			continue
		if p.vy < 0 or p.y + p.height / 2 > r.end.y:
			p.y = r.end.y
			p.vy = maxf(0.0, p.vy)
		elif p.y + p.height - r.position.y < 24:
			p.y = r.position.y - p.height


## How much worse the world feels now (the sway, the blobs' wobble): 1 at full energy, up to
## 1 + PMS_TIRED when the light is spent; resting settles it a little.
func tired_k() -> float:
	return (1.0 + PMS_TIRED * tired) * (1.0 - 0.4 * rest_k)


## Rest: the ability held on the ground. She sits and can't move (_update drops left / right,
## _unhandled_input the jump); after REST_DELAY s the energy comes back (_update_light).
## Letting go, a dialog or losing the ground ends it.
func _update_rest(dt: float, hold: bool) -> void:
	var can := hold and p.is_grounded and active and not dialog_open and not hold_input
	if can and not resting:
		resting = true
		rest_t = 0.0
		Audio.play_sfx("breathok.wav", 0.25)
	elif not can:
		resting = false
	if resting:
		rest_t += dt
	rest_k = move_toward(rest_k, 1.0 if rest_filling() else 0.0, dt / 0.6)


## Resting long enough that the energy refills.
func rest_filling() -> bool:
	return resting and rest_t >= REST_DELAY


func _take_comfort(e: LevelData.Ent) -> void:
	e.collected = true
	pms_items += 1
	var tier := clampi(e.tier, 0, PmsMaze.ITEMS.size() - 1)
	pms_found[tier] = true
	var at := e.rect().get_center()
	_sparkles(at, 12)
	Audio.play_sfx("cink-%02d.wav" % (3 + pms_items * 2), 0.45)
	# Keyed by which item it is (its tip, its HUD slot), not by how many were found.
	trigger.emit("pms_item_%d" % (tier + 1))
	# Comfort: her energy is full again, with a warm burst of light.
	pms_light = 1.0
	light_burst = 1.0
	for i in 16:
		var ang := TAU * i / 16.0
		particles.append({"x": at.x, "y": at.y, "vx": cos(ang) * 3.2, "vy": sin(ang) * 3.2, "rot": 0.0, "rot_speed": 0.0, "type": "glint", "life": 0.7, "max_life": 0.7})
	if pms_items >= PmsMaze.ITEMS.size() and door_open <= 0:
		door_open = 0.01
		Audio.play_sfx("finished.wav", 0.5)


## The lantern: her light grows (its radius at full energy LIGHT_R → LANTERN_R); Main plays 4G.
func _take_lantern(e: LevelData.Ent) -> void:
	e.collected = true
	has_lantern = true
	_sparkles(e.rect().get_center(), 14)
	Audio.play_sfx("cink-09.wav", 0.5)
	trigger.emit("pms_lantern")


## Where the lantern is picked up: its map cell's column from the floor it stands on up to
## the wall above it (at most LANTERN_REACH_ROWS rows), so she can't jump over it on the way
## out of the spawn corridor.
func lantern_reach(e: LevelData.Ent) -> Rect2:
	var cx := e.x + e.w / 2
	var bottom := e.y + e.h
	var top := bottom - LANTERN_REACH_ROWS * LevelData.ROW_H
	for w in level.walls:
		if w.position.x < cx and w.end.x > cx and w.end.y <= e.y + 1.0:
			top = maxf(top, w.end.y)
	return Rect2(cx - LevelData.CELL_W / 2, top, LevelData.CELL_W, bottom - top)


## Her light's radius at an energy (0..1): bigger with the lantern, never nothing.
func light_for(energy: float) -> float:
	var k := clampf(energy, 0, 1)
	return lerpf(LANTERN_MIN, LANTERN_R, k) if has_lantern else lerpf(LIGHT_MIN, LIGHT_R, k)


## The light round Kyra is her energy: it drains while she plays (slowly standing still),
## comes back while she rests; the radius follows it smoothly (light_for), plus a comfort
## item's warm burst.
func _update_light(dt: float, moving: bool) -> void:
	if active and not dialog_open and not hold_input:
		if rest_filling():
			pms_light = minf(1.0, pms_light + REST_FILL * dt)
		elif not resting:
			pms_light = maxf(0.0, pms_light - (LIGHT_DRAIN if moving else LIGHT_DRAIN_STILL) * dt)
	light_burst = maxf(0.0, light_burst - dt / BURST_TIME)
	tired += (1.0 - pms_light - tired) * (1.0 - exp(-TIRED_EASE * dt))
	var want := light_for(pms_light) + LIGHT_BURST * light_burst
	light_r += (want - light_r) * (1.0 - exp(-3.0 * dt))
	if absf(want - light_r) < 0.5:
		light_r = want


## The gauge's foggy spells (only while she plays, after the warm arrival): the first waits
## for her to stand on the ground, is the longest and is explained once, FOG_TELL s into it
## (trigger pms_fog: she has seen it flicker; the spell goes on after the dialog), when she
## stands on the ground and isn't about to pick something up (its dialog would take 4H's
## place). Main marks it explained when 4H is closed; if it never was (another dialog
## replaced it), the first spell and its explanation come again.
func _update_fog(dt: float) -> void:
	if not active or dialog_open or hold_input or warm > 0:
		return
	if fog_told and not fog_explained:
		# Told, no dialog open, not marked as read: 4H was replaced before its end.
		_fog_unread += dt
		if _fog_unread > 0.3:
			fog_told = false
			fog_t = 0.0
			fog_wait = FOG_RETELL
			return
	if fog_t > 0:
		fog_t = maxf(0.0, fog_t - dt)
		if not fog_told and not fog_explained and fog_len - fog_t >= FOG_TELL and p.is_grounded and not _pms_done_sent and not _near_pickup():
			# She has seen it flicker for a moment: now it is explained.
			fog_told = true
			_fog_unread = 0.0
			trigger.emit("pms_fog")
		if fog_t == 0.0:
			# A first spell that passed untold (she was in the air all along) comes again soon.
			fog_wait = randf_range(FOG_GAP.x, FOG_GAP.y) if fog_told or fog_explained else FOG_RETELL
	else:
		fog_wait -= dt
		if fog_wait <= 0 and (fog_explained or p.is_grounded):
			start_fog()


## Main: the gauge's explanation (4H) was read to its end.
func fog_was_explained() -> void:
	fog_explained = true
	fog_told = true


## About to touch something whose dialog would replace the gauge's explanation.
func _near_pickup() -> bool:
	var near := Rect2(p.x, p.y, p.width, p.height).grow(60)
	for e in level.entities:
		if e.collected:
			continue
		if e.type in ["comfort", "lantern"] or (e.type == "door" and door_open > 0):
			if near.intersects(e.rect()):
				return true
	return false


## A foggy spell now (mode: one of FOG_MODES, "" = the first drifts, later ones at random).
func start_fog(mode := "", length := 0.0) -> void:
	fog_len = length if length > 0 else (FOG_LEN.y if not fog_explained else randf_range(FOG_LEN.x, FOG_LEN.y))
	fog_t = fog_len
	fog_mode = mode if mode != "" else ("drift" if not fog_explained else FOG_MODES[randi() % FOG_MODES.size()])
	fog_count += 1
	fog_from = pms_light
	# Wrong towards where the bar has room, so the lie is always visible.
	fog_off = randf_range(0.3, 0.45) * (-1.0 if pms_light > 0.5 else 1.0)


## 0 outside a foggy spell, 1 in it (eased in and out over FOG_EDGE s).
func fog_k() -> float:
	if fog_t <= 0:
		return 0.0
	return clampf(minf(fog_len - fog_t, fog_t) / FOG_EDGE, 0, 1)


## What the gauge shows (0..1): the energy, except in a foggy spell, where it drifts off to a
## wrong value, jitters between wrong values or sticks at one. The truth is her light.
func gauge() -> float:
	var k := fog_k()
	if k <= 0:
		return pms_light
	var el := fog_len - fog_t
	var fake := pms_light
	match fog_mode:
		"freeze":
			fake = fog_from + fog_off * 0.7
		"jitter":
			var h := sin(floorf(el / 0.12) * 12.9898) * 43758.5453
			fake = pms_light + fog_off * (0.35 + 0.9 * (h - floorf(h)))
		_:
			fake = pms_light + fog_off * (0.8 + 0.2 * sin(el * 2.3))
	return clampf(lerpf(pms_light, clampf(fake, 0.04, 1.0), k), 0, 1)


## Her light on screen now (px): the warm arrival (warm 1 → 0) shrinks from the whole
## screen down to light_r as the hormones drop.
func light_radius() -> float:
	var w := clampf(warm, 0, 1)
	return light_r + WARM_LIGHT * w


## A world point on screen (the rotated, swaying view: the player layer's transform).
func screen_of(world: Vector2) -> Vector2:
	return _player_layer.get_transform() * world


## The lights in the dark (screen px): [centre.x, centre.y, radius], at most DARK_HOLES: Kyra,
## the lantern still lying in the maze (a warm glimmer, seen from the start), the open door,
## then the nearest comfort items still to find within GLIMMER_RANGE of her (a faint glow).
func dark_lights() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var kc := screen_of(p.center())
	out.append(Vector3(kc.x, kc.y, light_radius()))
	var items: Array[Vector3] = []
	for e in level.entities:
		if e.collected:
			continue
		var c := screen_of(e.rect().get_center())
		if e.type == "lantern":
			out.append(Vector3(c.x, c.y, LANTERN_GLIMMER + 8.0 * sin(time_ms / 400.0)))
		elif e.type == "door" and door_open > 0:
			out.append(Vector3(c.x, c.y, DOOR_GLIMMER * clampf(door_open / 0.6, 0, 1)))
		elif e.type == "comfort":
			var k := item_glimmer(e)
			if k > 0:
				items.append(Vector3(c.x, c.y, ITEM_GLIMMER * k * (0.92 + 0.08 * sin(time_ms / 520.0 + e.tier * 2.1))))
	# The nearest (= the brightest) first.
	items.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	for it in items:
		if out.size() < DARK_HOLES:
			out.append(it)
	return out


## How much a comfort item still to find glimmers in the dark (0..1): nothing beyond
## GLIMMER_RANGE world px from her, full from GLIMMER_NEAR. Not while she is still in the
## lantern's corridor without it (above its floor): at the start only the lantern glimmers,
## so she walks to it first. Once she is past that floor the items glimmer either way.
func item_glimmer(e: LevelData.Ent) -> float:
	if e.collected or e.type != "comfort":
		return 0.0
	for o in level.entities:
		if o.type == "lantern" and not o.collected and p.center().y < o.y + o.h:
			return 0.0
	var d := p.center().distance_to(e.rect().get_center())
	return smoothstep(GLIMMER_RANGE, GLIMMER_NEAR, d)


## The maze's darkness (level 6 only): its colour (warm amber while the yellow body's warmth
## lingers) and the holes of light.
func _update_dark() -> void:
	_dark.visible = is_pms()
	if not is_pms():
		return
	var mat := _dark.material as ShaderMaterial
	mat.set_shader_parameter("dark", PmsMaze.DARK.lerp(PmsMaze.DARK_WARM, clampf(warm, 0, 1)))
	var ls := dark_lights()
	for i in DARK_HOLES:
		mat.set_shader_parameter("l%d" % i, ls[i] if i < ls.size() else Vector3.ZERO)


## The open door: the level is over (Main plays 4E, then the title).
func _pms_done() -> void:
	_pms_done_sent = true
	hold_input = true
	p.vx = 0
	trigger.emit("pms_done")


## The maze's world: the out-of-place objects, then walls and platforms as soft blobs
## (rims first, so neighbouring blobs melt into one shape).
func _draw_pms_world(ci: CanvasItem, t: float, view: Rect2) -> void:
	for d in deco:
		if view.has_point(d.pos):
			PmsMaze.draw_deco(ci, d, t, rest_k * 0.5)
	var amp := PMS_WOBBLE * tired_k()
	var shown: Array = []
	for r in wall_blobs:
		if r.intersects(view):
			shown.append([r.grow(3), true])
	for pl in level.platforms:
		var pr := Rect2(pl.x, pl.y, pl.w, pl.h)
		if pr.intersects(view):
			shown.append([pr, false])
	for pass_i in 2:
		for b in shown:
			PmsMaze.draw_blob(ci, b[0], t, amp, b[1], pass_i)


## Developer shortcut (the maze): all three comfort items found, the door open.
func dev_all_comforts() -> void:
	for e in level.entities:
		if e.type == "comfort":
			e.collected = true
	pms_items = PmsMaze.ITEMS.size()
	pms_found = [true, true, true]
	door_open = maxf(door_open, 0.6)


## Developer shortcut (the maze): the lantern found (the bigger light at once).
func dev_lantern() -> void:
	for e in level.entities:
		if e.type == "lantern":
			e.collected = true
	has_lantern = true
	light_r = light_for(pms_light)


## Developer shortcuts (the maze): a low energy (a small light, the rest hint); a foggy
## spell of the gauge in a moment.
func dev_low_light(energy := 0.12) -> void:
	pms_light = energy
	fog_wait = maxf(fog_wait, 30.0)


func dev_fog() -> void:
	fog_wait = 0.6


## Developer shortcut (the maze): stand a few cells beside the door.
func dev_near_door() -> void:
	for e in level.entities:
		if e.type == "door":
			p.x = maxf(e.x - 5 * LevelData.CELL_W, 0)
			p.y = e.y + e.h - p.height - 2
			p.vx = 0
			p.vy = 0
			camera_y = pms_camera_clamp(p.y - H * PMS_VIEW_Y)
			last_ground = Vector2(p.x, p.y)


## Developer shortcut (the climb): onto the platform under the top (E), which ends it.
func dev_to_top() -> void:
	for e in level.entities:
		if e.trigger_type != "climb_top":
			continue
		var best: LevelData.Plat = null
		for pl in level.platforms:
			if pl.base_y > e.y + e.h / 2 and (best == null or pl.base_y < best.base_y or (is_equal_approx(pl.base_y, best.base_y) and absf(pl.x + pl.w / 2 - level_w / 2) < absf(best.x + best.w / 2 - level_w / 2))):
				best = pl
		if best:
			p.x = clampf(level_w / 2 - p.width / 2, best.x + 4, best.x + best.w - p.width - 4)
			p.y = best.base_y - p.height - 2
			p.vx = 0
			p.vy = 0
			_board_camera()
		return
