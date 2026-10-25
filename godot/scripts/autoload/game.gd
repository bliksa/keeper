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
const LEVELS := {1: "res://data/levels/cave.txt", 2: "res://data/levels/meadow.txt", 3: "res://data/levels/garden.txt"}
const LEVEL_NAMES := {1: "Cave", 2: "Meadow", 3: "Summit"}
const LEVEL_DIRS := {1: "down", 2: "right", 3: "up"}

## "keyboard" or "gamepad" — decides which <KB>/<GP> hint text is shown.
var control_mode := "keyboard":
	set(v):
		control_mode = v
		control_mode_changed.emit()

## Iron (the collectible) — also the player's "health" in the cave.
var iron := 0
## Iron the player had when reaching the boss (used for boss retry).
var boss_iron := 20
## Breathing ability unlocked (after the forest breathing minigame).
var has_breathing := false
## Skip the forest intro on restart (set after it was finished once).
var intro_done := false
## Checkpoint index: 0 = level start (first run), 1 = cave start,
## 2..4 = after minigame N, 5 = boss (level 2: the LH wave).
var checkpoint := 0
## Current level: 1 cave, 2 meadow, 3 summit.
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
	_setup_input()
	PlayerArt.load_game_defaults()


func reset_run() -> void:
	iron = 0
	boss_iron = 20
	has_breathing = false
	intro_done = false
	checkpoint = 0
	level = 1
	upgrades = {}
	water = 0
	seeds = 0
	gate_shift = 0


## Level rows used by the game. A level edited in the dev menu can replace the
## bundled one of `custom_level_id` for this session ("Use in game" in the editor).
var custom_level_rows := PackedStringArray()
var custom_level_id := 0


## Level rows. Empty cells may be written as ' ' or '.' in the file.
func load_level_rows(path: String = LEVEL_PATH, cols := LevelData.COLS) -> PackedStringArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open level " + path)
		return PackedStringArray()
	return LevelData.parse_text(f.get_as_text(), cols)


func level_rows(id: int) -> PackedStringArray:
	return load_level_rows(LEVELS.get(id, LEVEL_PATH), -1 if is_horizontal(id) else LevelData.COLS)


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
	_action("run", [KEY_SHIFT], [JOY_BUTTON_Y], [])
	_action("breathe", [KEY_CTRL], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
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
	# Level 2: hold to focus the light thread on a seed (also the left mouse button).
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
