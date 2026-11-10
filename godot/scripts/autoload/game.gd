extends Node
## Global game state + input setup.
## Everything the web prototype kept in React state at the App level lives here.

signal control_mode_changed

const VIEW_W := 1066.0
const VIEW_H := 600.0

const LEVEL_PATH := "res://data/levels/cave.txt"
const CUSTOM_LEVEL_PATH := "user://custom_level.txt"
## Levels: 1 the cave (menstruation, down), 2 the meadow (follicular phase, left → right,
## horizontal), 3 the summit (ovulation, up). dir: "down" | "right" | "up" | "left".
## 4 = the forest run (level 2 of the game, a top-down map for ForestRunner);
## 5 = the jackpot climb (level 3 of the game, ovulation, up with the board);
## 6 = the PMS maze (level 4 of the game, luteal phase; drawn upside down, see Platformer.view_flip);
## 2 = the old meadow and 3 = the old summit (developer menu only).
## The dict order is the level editor's picker order.
const CLIMB_ID := 5
const PMS_ID := 6
const LEVELS := {1: "res://data/levels/cave.txt", 4: "res://data/levels/forest_run.txt", 5: "res://data/levels/climb.txt", 6: "res://data/levels/pms.txt", 2: "res://data/levels/meadow.txt", 3: "res://data/levels/garden.txt"}
const LEVEL_NAMES := {1: "Cave", 4: "Forest run", 5: "Jackpot climb", 6: "PMS maze", 2: "Meadow (old)", 3: "Summit (old)"}
const LEVEL_DIRS := {1: "down", 4: "forward", 5: "up", 6: "down", 2: "right", 3: "up"}
## Prefix of the dialogs of each level (data/dialogs.json): 2C = level 2, dialog C.
## "0" is the prologue in the forest (no level map). The old summit (id 3) uses "S".
const DIALOG_LEVEL := {1: "1", 4: "2", 5: "3", 6: "4", 2: "M", 3: "S"}

## "keyboard" or "gamepad" — decides which <KB>/<GP> hint text is shown.
var control_mode := "keyboard":
	set(v):
		control_mode = v
		control_mode_changed.emit()

## Iron (the collectible): her protection in the cave and the floor / fuel of the boss fight.
## A hit costs iron, down to 0; only a hit with none left sends her back to the last
## checkpoint (Platformer._hurt / the cramp's grab).
var iron := 0
## Iron the player had when reaching the boss (used for boss retry).
var boss_iron := 20
## The cave's fail-soft state (Main._retry_cave / _retry_boss): the last cave checkpoint
## reached (1 start, 2..4 after its minigames; stays when `checkpoint` becomes 5 at the boss),
## the iron she had there, the rest point (map marker R) reached after it (its y, -1 = none),
## whether 1B (the cramp lesson) has played, and the boss retries so far (1E plays on the first).
var cave_checkpoint := 1
var checkpoint_iron := 0
var rest_y := -1.0
var cramp_taught := false
var boss_retries := 0
## The iron a restart at a checkpoint gives at least.
const RETRY_IRON := 5
## Developer mode was opened in this session (Main._open_dev) or the page has ?dev=1: only
## then the debug keys work (Main._unhandled_input: 1–5, Shift+2–5, G, H, C; X in a minigame).
var dev_unlocked := false
## Breathing ability unlocked (after the forest breathing minigame).
var has_breathing := false
## Skip the forest intro on restart (set after it was finished once).
var intro_done := false
## Checkpoint index: 0 = level start (first run), 1 = cave start,
## 2..4 = after minigame N, 5 = boss (level 2: the LH wave).
var checkpoint := 0
## Current level: 1 cave, 4 forest run, 5 jackpot climb, 6 PMS maze (2 old meadow, 3 old summit).
var level := 1
## Level 3 power-ups earned in the minigames: "jump", "dash", "double".
var upgrades := {}
## Level 2: the water vessel (0..100, estrogen), caught light seeds, and how far
## stress has pushed the gate (cells).
var water := 0
var seeds := 0
var gate_shift := 0
const SEEDS_NEEDED := 10
const WATER_PER_DROP := 4


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_save()
	_setup_input()
	PlayerArt.load_game_defaults()
	# SpriteArt.load_game_defaults() runs in Text._ready (it needs the characters).


func reset_run() -> void:
	iron = 0
	boss_iron = 20
	cave_checkpoint = 1
	checkpoint_iron = 0
	rest_y = -1.0
	cramp_taught = false
	boss_retries = 0
	has_breathing = false
	intro_done = false
	checkpoint = 0
	level = 1
	upgrades = {}
	water = 0
	seeds = 0
	gate_shift = 0


# --- the save (user://save.json; on the web Godot keeps user:// in IndexedDB) ----------
## {language, muted, chapter, checkpoint, iron, reached, finished}: the language and the
## sound switch; the furthest place of the current playthrough (chapter 1 cave / 2 forest
## run / 3 jackpot climb / 4 PMS maze, and its checkpoint: the cave's 1–4 and 5 = the boss,
## the run's stage 0–3, the climb's 1–4, the maze's 1; `iron` = the cave's iron there);
## `reached` = the furthest chapter ever (the title's phase picker) and `finished` (the end
## screen was reached). Written by save_set / progress / mark_finished, read at boot.
## Main decides what counts (developer shortcuts don't: Main._no_save).
const SAVE_PATH := "user://save.json"
const CHAPTERS := 4
var save_path := SAVE_PATH
var save := {}
## Nothing is written (web previews ?title=continue / ?title=finished put a made-up save
## into memory: it must not reach the real one).
var save_readonly := false


func load_save() -> void:
	save = {}
	if not FileAccess.file_exists(save_path):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if d is Dictionary:
		save = d


func write_save() -> void:
	if save_readonly:
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(save, " "))
	f.close()


func save_set(key: String, value: Variant) -> void:
	if save.get(key) == value:
		return
	save[key] = value
	write_save()


func saved_chapter() -> int:
	return clampi(int(save.get("chapter", 0)), 0, CHAPTERS)


func saved_checkpoint() -> int:
	return int(save.get("checkpoint", 0))


## Is there a place to continue from (the title's Continue)?
func has_progress() -> bool:
	return saved_chapter() >= 1


## The furthest chapter ever reached (0 = none; all of them once the game was finished).
func reached_chapter() -> int:
	if bool(save.get("finished", false)):
		return CHAPTERS
	return clampi(maxi(int(save.get("reached", 0)), saved_chapter()), 0, CHAPTERS)


func is_finished() -> bool:
	return bool(save.get("finished", false))


## A place was reached: saved when it is further than the saved one (a later chapter, or
## a later checkpoint of the same one; the same place keeps the larger iron).
func progress(chapter: int, checkpoint: int, iron_now := 0) -> bool:
	var ch := saved_chapter()
	var cp := saved_checkpoint()
	if chapter < ch or (chapter == ch and checkpoint < cp):
		return false
	if chapter == ch and checkpoint == cp and iron_now <= int(save.get("iron", 0)):
		return false
	save["chapter"] = chapter
	save["checkpoint"] = checkpoint
	save["iron"] = iron_now
	save["reached"] = maxi(int(save.get("reached", 0)), chapter)
	write_save()
	return true


## A new playthrough starts (New game, Restart game, a phase from the picker): its place
## is saved from here on, so the old one (Continue) goes; the phases reached, `finished`,
## the language and the sound stay.
func new_playthrough() -> void:
	if not (save.has("chapter") or save.has("checkpoint") or save.has("iron")):
		return
	save.erase("chapter")
	save.erase("checkpoint")
	save.erase("iron")
	write_save()


## The end screen was reached: every phase stays open in the title's picker, and there is
## nothing left to continue (the next playthrough saves its own place again).
func mark_finished() -> void:
	save["finished"] = true
	save["reached"] = CHAPTERS
	save.erase("chapter")
	save.erase("checkpoint")
	save.erase("iron")
	write_save()


## The language the game starts in: ?lang= on the web (and it is kept), else the saved
## one, else the browser's (sk / pt; Czech readers get Slovak), else English.
static func pick_language(query: String, saved: String, browser: String) -> String:
	for c in [query.to_lower(), saved]:
		if c in ["sk", "en", "pt"]:
			return c
	var b := browser.to_lower().substr(0, 2)
	if b == "cs":
		return "sk"
	return b if b in ["sk", "pt"] else "en"


func start_language() -> String:
	var query := ""
	var browser := ""
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('lang') || ''")
		var b: Variant = JavaScriptBridge.eval("navigator.language || ''")
		query = q if q is String else ""
		browser = b if b is String else ""
	var lang := pick_language(query, str(save.get("language", "")), browser)
	if query.to_lower() == lang:
		save_set("language", lang)
	return lang


## Level rows used by the game. A level edited in the dev menu can replace the
## bundled one of `custom_level_id` for this session ("Use in game" in the editor).
var custom_level_rows := PackedStringArray()
var custom_level_id := 0
## Backgrounds set with "Use in game" in the level editor: level id -> config
## (see BackgroundData). Empty = the bundled data/backgrounds.json.
var custom_backgrounds := {}


## Level rows. Empty cells may be written as ' ' or '.' in the file.
func load_level_rows(path: String = LEVEL_PATH, cols := LevelData.COLS) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open level " + path)
		return PackedStringArray()
	return LevelData.parse_text(f.get_as_text(), cols)


func level_rows(id: int) -> PackedStringArray:
	return load_level_rows(LEVELS.get(id, LEVEL_PATH), level_cols(id))


## Columns of a level's text (-1 = as long as its rows, for horizontal levels).
static func level_cols(id: int) -> int:
	if is_horizontal(id):
		return -1
	if id == CLIMB_ID:
		return LevelData.CLIMB_COLS
	return ForestRunner.COLS if id == ForestRunner.LEVEL_ID else LevelData.COLS


## "v2.0.0 · build 069a5d1 · 2026-11-07 19:20" (data/build.json, written by
## tools/export_web.sh; just the version when running from the editor / tests).
static func build_label() -> String:
	var v := "v" + str(ProjectSettings.get_setting("application/config/version"))
	if FileAccess.file_exists("res://data/build.json"):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
		if d is Dictionary:
			return "%s · build %s · %s" % [v, d.get("sha", "?"), d.get("date", "")]
	return v


static func is_horizontal(id: int) -> bool:
	return LEVEL_DIRS.get(id, "down") in ["right", "left"]


func current_level_rows(id: int = level) -> PackedStringArray:
	if custom_level_rows.size() > 0 and custom_level_id == id:
		return custom_level_rows
	return level_rows(id)


# --- input -------------------------------------------------------------------

func _setup_input() -> void:
	# Gamepad layout follows the web build (standard mapping):
	# X/left face = jump, Y/top = run, B/right + shoulders/triggers = breathe.
	_action("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("move_up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_down", [KEY_DOWN, KEY_S], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("jump", [KEY_UP, KEY_W, KEY_SPACE], [JOY_BUTTON_X], [])
	# Shift on the keyboard: run (level 1) / dash (level 2, after the rhythm minigame).
	# One key for the level's ability (Shift / B): breathe in the cave, focus in
	# the forest run, breathe and later dash on the summit.
	_action("run", [KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("breathe", [KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
		[[JOY_AXIS_TRIGGER_LEFT, 1.0], [JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("confirm", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A], [])
	# Dialog choice buttons map to the four face buttons (blue, red, yellow, green).
	_action("choice_0", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A], [])
	_action("choice_1", [], [JOY_BUTTON_B], [])
	_action("choice_2", [], [JOY_BUTTON_X], [])
	_action("choice_3", [], [JOY_BUTTON_Y], [])
	_action("rotate_left", [KEY_Q], [JOY_BUTTON_B], [])
	_action("rotate_right", [KEY_E], [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y], [])
	_action("skip_minigame", [KEY_X], [], [])
	_action("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	# Level 2 (forest run): hold to slow time while the water lasts.
	_action("slow_time", [KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER], [])
	# Level 2 (old meadow): hold to focus the light thread on a seed (also the left mouse button).
	_action("focus", [KEY_E], [JOY_BUTTON_LEFT_SHOULDER], [])
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("focus", mb)


func _action(action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.35)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)


func _input(event: InputEvent) -> void:
	# Auto-switch hint texts to whatever device the player touches.
	if event is InputEventJoypadButton and event.pressed and control_mode != "gamepad":
		control_mode = "gamepad"
	elif event is InputEventKey and event.pressed and not event.echo and control_mode != "keyboard":
		control_mode = "keyboard"
