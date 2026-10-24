extends Node
## Game flow (port of the web App `M2`).
##
## boot → title → intro (forest) → mg1 (breathing) → intro → platformer (cave)
##   → mg2 chocolate → platformer → mg3 pipes → platformer → mg4 prices
##   → platformer → boss → title
## plus the developer menu ("dev").

var state := ""

var _world_layer: CanvasLayer
var _overlay_layer: CanvasLayer
var _menu_layer: CanvasLayer
var _dim: ColorRect
var _fade: ColorRect
var _panel_box: DialogBox
var _node_box: DialogBox

var forest: ForestIntro
var platformer: Platformer
var minigame: Minigame
var _menu: Control
var _pause: PauseMenu
## Bumped when a run is aborted (pause menu) so pending fades/timers of the
## old run don't act on the new one.
var _run_id := 0


func _ready() -> void:
	var base := TextureRect.new()
	base.texture = load("res://assets/images/back2.png")
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	base.size = Vector2(1066, 600)
	var base_layer := CanvasLayer.new()
	base_layer.layer = -1
	base_layer.add_child(base)
	add_child(base_layer)
	_world_layer = _layer(0)
	_overlay_layer = _layer(5)
	var dim_layer := _layer(7)
	_dim = _rect(Color.BLACK)
	dim_layer.add_child(_dim)
	var dialog_layer := _layer(8)
	_panel_box = DialogBox.new()
	dialog_layer.add_child(_panel_box)
	_node_box = DialogBox.new()
	dialog_layer.add_child(_node_box)
	_panel_box.blocker = _node_box
	_menu_layer = _layer(10)
	var pause_layer := _layer(15)
	_pause = PauseMenu.new()
	_pause.restart_pressed.connect(_restart_game)
	_pause.title_pressed.connect(_quit_to_title)
	pause_layer.add_child(_pause)
	var fade_layer := _layer(20)
	_fade = _rect(Color.BLACK)
	fade_layer.add_child(_fade)
	_go_boot()


func _layer(n: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.layer = n
	add_child(l)
	return l


func _rect(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.size = Vector2(1066, 600)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0
	return r


# --- helpers -------------------------------------------------------------------

func _set_state(s: String) -> void:
	state = s
	_node_box.at_top = s in ["intro", "mg1"]
	_panel_box.at_top = _node_box.at_top
	match s:
		"intro", "mg1": Audio.play_bgm("forest.mp3", 0.4)
		"platformer": Audio.play_bgm("chamber.mp3", 0.5)
		"mg2", "mg3", "mg4": Audio.play_bgm("minihra.mp3", 0.5)
		"title": Audio.play_bgm("menu.mp3", 0.5)


## Fade the screen to `col` (alpha `to`) over `time` seconds.
func _fade_to(to: float, time := 0.5, col := Color.BLACK) -> void:
	_fade.color = col
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", to, time)
	await tw.finished


func _set_dim(on: bool) -> void:
	create_tween().tween_property(_dim, "modulate:a", 0.7 if on else 0.0, 0.5)


func _clear_world() -> void:
	for c in _world_layer.get_children():
		c.queue_free()
	forest = null
	platformer = null
	_clear_minigame()


func _clear_minigame() -> void:
	if minigame:
		minigame.queue_free()
		minigame = null
	_panel_box.close()


func _clear_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _dialog(id: String, then: Callable = Callable()) -> void:
	_node_box.show_node(id, func(_btn):
		if then.is_valid():
			then.call())


func _process(_delta: float) -> void:
	_pause.allowed = state in ["intro", "mg1", "platformer", "mg2", "mg3", "mg4"]
	var any_dialog := _node_box.is_open() or _panel_box.is_open()
	if platformer:
		platformer.active = state == "platformer"
		platformer.dialog_open = any_dialog
		platformer.active_dialog_id = _node_box.node_id()
		platformer.hide_platforms = state in ["mg2", "mg3", "mg4"]
		platformer.hud.visible = state == "platformer"
	if forest:
		forest.active = state in ["intro", "mg1"]
		forest.dialog_open = any_dialog
	if minigame:
		minigame.dialog_active = _node_box.is_open()


# --- screens ------------------------------------------------------------------

func _go_boot() -> void:
	_clear_menu()
	state = "boot"
	var b := BootScreen.new()
	b.started.connect(func():
		Audio.muted = false
		_go_title())
	b.dev_pressed.connect(func():
		Audio.muted = false
		_go_dev())
	_menu_layer.add_child(b)
	_menu = b


func _go_title() -> void:
	_clear_menu()
	_clear_world()
	_node_box.close()
	_set_dim(false)
	_set_state("title")
	var t := TitleScreen.new()
	t.start_pressed.connect(_start_new_game)
	_menu_layer.add_child(t)
	_menu = t


func _go_dev() -> void:
	_clear_menu()
	state = "dev"
	Audio.stop_bgm()
	var d := DevMenu.new()
	d.back.connect(_go_title)
	d.action.connect(_dev_action)
	_menu_layer.add_child(d)
	_menu = d


func _dev_action(name: String, value: int) -> void:
	match name:
		"skip_intro":
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			_start_cave(0, 0)
		"checkpoint":
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			_start_cave(value, 0)
		"boss":
			_skip_to_boss(value)


## Stop everything that belongs to a run in progress (sounds, dialogs, overlays).
func _abort_run() -> void:
	_run_id += 1
	Audio.stop_all_loops()
	Audio.stop_voice()
	Audio.set_bgm_volume(0.5)
	_node_box.close()
	_panel_box.close()
	_dim.modulate.a = 0
	_fade.modulate.a = 0


## Pause menu → Restart game: a fresh run from the very beginning.
func _restart_game() -> void:
	_abort_run()
	_start_new_game()


## Pause menu → Main menu.
func _quit_to_title() -> void:
	_abort_run()
	Game.reset_run()
	_go_title()


func _start_new_game() -> void:
	Game.reset_run()
	_clear_menu()
	_start_intro()


func _start_intro() -> void:
	_clear_world()
	forest = ForestIntro.new()
	forest.has_breathing = Game.has_breathing
	forest.show_dialog.connect(func(id, cb): _node_box.show_node(id, cb))
	forest.start_breathing.connect(_start_breathing)
	forest.entered_cave.connect(_enter_cave)
	_world_layer.add_child(forest)
	_set_state("intro")


func _start_breathing() -> void:
	_set_state("mg1")
	_open_minigame(BreathingGame.new(), _breathing_done)


func _breathing_done() -> void:
	Game.has_breathing = true
	Game.checkpoint = 1
	_clear_minigame()
	if Game.intro_done:
		_start_cave(1, Game.iron)
		_dialog("intro_breathing_done")
	else:
		_set_state("intro")
		forest.has_breathing = true
		_dialog("intro_breathing_done")


func _enter_cave() -> void:
	var run := _run_id
	await _fade_to(1.0, 1.0)
	if run != _run_id:
		return
	Game.intro_done = true
	_start_cave(1, Game.iron, false)
	await get_tree().create_timer(0.5).timeout
	_fade_to(0.0, 1.0)


## (Re)start the cave at a checkpoint (0/1 start, 2–4 after minigame N).
func _start_cave(checkpoint: int, iron: int, fade := true) -> void:
	var run := _run_id
	if fade:
		await _fade_to(1.0)
		if run != _run_id:
			return
	_clear_menu()
	_clear_world()
	_node_box.close()
	_set_dim(false)
	Game.checkpoint = checkpoint
	Game.iron = iron
	Game.has_breathing = Game.has_breathing or checkpoint >= 1 or Game.intro_done
	platformer = Platformer.new()
	platformer.setup(Game.current_level_rows(), checkpoint)
	platformer.trigger.connect(_on_trigger)
	platformer.boss_defeated.connect(_on_boss_defeated)
	platformer.boss_lost.connect(_on_boss_lost)
	_world_layer.add_child(platformer)
	_set_state("platformer")
	if fade:
		await get_tree().create_timer(0.5).timeout
		_fade_to(0.0)


func _skip_to_boss(iron: int) -> void:
	Game.has_breathing = true
	Game.intro_done = true
	var run := _run_id
	await _start_cave(5, iron)
	if run != _run_id or platformer == null:
		return
	platformer.start_boss(iron)
	_on_trigger("end")


func _open_minigame(m: Minigame, on_done: Callable) -> void:
	_clear_minigame()
	minigame = m
	m.hint.connect(func(panel: Dictionary):
		if panel.is_empty():
			_panel_box.close()
		else:
			_panel_box.show_panel(panel))
	m.completed.connect(on_done)
	_overlay_layer.add_child(m)


# --- platformer events ---------------------------------------------------------

func _on_trigger(name: String) -> void:
	if name.begins_with("dialog_"):
		var id := Text.dialog_for_letter(name.substr(7))
		if id != "" and _node_box.node_id() != id:
			_dialog(id)
		return
	match name:
		"first_cramp":
			_dialog("first_cramp")
		"mg2":
			_set_state("mg2")
			_open_minigame(ChocoPuzzle.new(), _mg2_done)
			_dialog("mg1_start", func(): _dialog("mg1_intro"))
		"mg3":
			_set_state("mg3")
			_open_minigame(PipesGame.new(), _mg3_done)
			_dialog("mg2_start", func(): _dialog("mg2_intro"))
		"mg4":
			_set_state("mg4")
			_open_minigame(PricesGame.new(), _mg4_done)
			_dialog("mg3_start")
		"end":
			Game.checkpoint = 5
			Game.boss_iron = Game.iron
			_dialog("boss_start")
		"game_over", "game_over_boss":
			_set_dim(true)
			var run := _run_id
			await get_tree().create_timer(0.5).timeout
			if run != _run_id:
				return
			_panel_box.show_panel({
				"title": "UI_TOO_MUCH_PAIN", "text": "UI_CRAMPS_OVERWHELMED", "hide_button": true,
				"choices": [{"text": "BTN_TRY_AGAIN" if name == "game_over" else "BTN_RESTART_CAVE", "action": _restart_cave}],
			})
		"white_fade":
			await _fade_to(1.0, 0.1, Color.WHITE)
			_fade_to(0.0, 0.2, Color.WHITE)


func _restart_cave() -> void:
	_panel_box.close()
	_set_dim(false)
	Game.boss_iron = 0
	_start_cave(1, 0)


func _mg2_done() -> void:
	Game.checkpoint = 2
	_panel_box.close()
	_dialog("mg1_after", _back_to_cave)


func _mg3_done() -> void:
	Game.checkpoint = 3
	_panel_box.close()
	_dialog("mg2_win", func(): _dialog("mg2_after", _back_to_cave))


func _mg4_done() -> void:
	Game.checkpoint = 4
	_panel_box.close()
	_dialog("mg3_after", _back_to_cave)


func _back_to_cave() -> void:
	_clear_minigame()
	_set_state("platformer")


func _on_boss_defeated() -> void:
	_dialog("boss_win", func():
		Game.reset_run()
		_go_title())


func _on_boss_lost() -> void:
	_set_dim(true)
	_panel_box.show_panel({
		"title": "UI_FALLING_DEPTHS", "text": "UI_PAIN_PULLED_DOWN", "hide_button": true,
		"choices": [{"text": "BTN_RESTART_CAVE", "action": _restart_cave}],
	})


func _unhandled_input(event: InputEvent) -> void:
	# Debug keys in the cave (same as the web build).
	if state != "platformer" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.shift_pressed and event.physical_keycode in [KEY_2, KEY_3, KEY_4, KEY_5]:
		# Shift+2…5: jump to the minigame / boss trigger.
		platformer.teleport_to_trigger(["mg2", "mg3", "mg4", "end"][event.physical_keycode - KEY_2])
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			_start_cave(event.physical_keycode - KEY_0, Game.iron)
		KEY_5:
			_skip_to_boss(maxi(Game.iron, 20))
		KEY_C:
			Game.has_breathing = true
			Game.iron = 20
