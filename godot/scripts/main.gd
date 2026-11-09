extends Node
## Game flow (port of the web App `M2`).
##
## boot → title → intro (forest) → mg1 (breathing) → intro → platformer (cave)
##   → mg2 chocolate → platformer → mg3 pipes → platformer → mg4 prices
##   → platformer → boss → level 2 (the forest run, runner): mg8 memory → mg9 catch
##   → mg10 pairs → 2E → level 3 (the jackpot climb, id 5, up with the board)
##   → climb_top → 3E (on the board) → the transformation (the view turns upside down)
##   → level 4 (the PMS maze, id 6): 4A, three comfort items (4B–4D), the door → 4E → title
## Old levels (developer menu only): the meadow (id 2) → the old summit (id 3:
## mg5 iron plate → mg6 rhythm → mg7 body signals → LH wave chase → summit → title).
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
## Level 2 (demo): the forest run after the Big Cramp.
var runner: ForestRunner
var minigame: Minigame
var _menu: Control
var _pause: PauseMenu
## Bumped when a run is aborted (pause menu) so pending fades/timers of the
## old run don't act on the new one.
var _run_id := 0
## Running screen fades (killed when a run is aborted, so a fade frozen by the
## pause menu can't cover the new run).
var _fade_tws: Array = []


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
	# Developer shortcut: ?mg=mg1 … mg11 opens that minigame right away.
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('mg') || ''")
		if q is String and q != "":
			open_minigame_for_dev.call_deferred(q)
		# ?boss=win: the arena with the Big Cramp just beaten (the transition to level 2).
		var bq: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('boss') || ''")
		if bq is String and bq == "win":
			_dev_boss_win.call_deferred()
		# ?run=hit: the forest run, a slice found, then a hit every few seconds.
		var rq: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('run') || ''")
		if rq is String and rq == "hit":
			_dev_runner_hits.call_deferred()
		elif rq is String and rq == "reload":
			# ?run=reload (?climb=reload): an empty magazine and a full reserve every few
			# seconds, so the reload can be watched.
			_dev_meter_reload.call_deferred(true)
		elif rq is String and rq == "end":
			# ?run=end: the last stage, the 12th piece taken: the sun, 2E, the climb.
			_dev_action.call_deferred("runner_end", 0)
		# ?climb=1: the jackpot climb from its start; ?climb=top: just below the top.
		var cq: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('climb') || ''")
		if cq is String and cq == "end":
			# ?climb=end: the climb's top → 3E on the board → the transformation.
			_dev_action.call_deferred("pms_transform", 0)
		elif cq is String and cq != "":
			_dev_action.call_deferred("checkpoint5", 5 if cq == "top" else 1)
			if cq == "power":
				_dev_climb_powers.call_deferred()
			elif cq == "reload":
				_dev_meter_reload.call_deferred(false)
		# ?pms=1: the PMS maze from its start (?pms=door: all three items found).
		var pq: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('pms') || ''")
		if pq is String and pq != "":
			_dev_action.call_deferred("checkpoint6", 2 if pq == "door" else 1)
		# ?cave=N: the cave from checkpoint N (with breathing; its ability hints).
		var vq: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('cave') || ''")
		if vq is String and vq != "":
			_dev_action.call_deferred("checkpoint", clampi(int(vq), 0, 4))


## ?climb=power: the climb with three ready hearts, a super jump and the magnet (their
## hints top-right), then a joker spins the spinner top-left.
func _dev_climb_powers() -> void:
	await get_tree().create_timer(2.0).timeout
	if platformer and platformer.is_climb():
		platformer.powers_explained = {"super_jump": true, "magnet": true, "triple": true, "rocket": true}
		platformer.meter.reset(3.0, 2.2)
		platformer.grant_power("super_jump")
		platformer.grant_power("magnet")
	await get_tree().create_timer(1.5).timeout
	if platformer and platformer.is_climb():
		platformer._take_joker(LevelData.Ent.new())


## ?run=reload / ?climb=reload: the water's / the hearts' magazine emptied with a full
## reserve every few seconds: the reload plays drop by drop / heart by heart.
func _dev_meter_reload(run_level: bool) -> void:
	var run := _run_id
	if run_level:
		await _start_runner(false, 1)
		_node_box.close()
	else:
		await get_tree().create_timer(2.5).timeout
	while run == _run_id:
		var m: MeterModel = null
		if run_level and runner:
			m = runner.meter
		elif not run_level and platformer and platformer.is_climb():
			m = platformer.meter
			platformer.rise_wait = 99.0
		if m == null:
			return
		m.reset(0.0, 4.0)
		await get_tree().create_timer(4.0).timeout


func _dev_boss_win() -> void:
	_clear_menu()
	await _skip_to_boss(20)
	await get_tree().create_timer(1.0).timeout
	if platformer:
		platformer.dev_defeat_boss()


func _dev_runner_hits() -> void:
	await _start_runner(false, 1)
	_node_box.close()
	var run := _run_id
	while runner != null and run == _run_id:
		await get_tree().create_timer(1.5).timeout
		if runner == null or run != _run_id:
			return
		for o in runner.objects:
			if o.kind == "sun" and not o.taken and o.stage == runner.stage:
				o.taken = true
				runner.sun += 1
				runner.sun_shown = runner.sun
				break
		await get_tree().create_timer(1.0).timeout
		if runner == null or run != _run_id:
			return
		runner.bump()
		await get_tree().create_timer(2.0).timeout


## The forest run's end (?run=end, the dev menu): the last stage, every piece but the last
## found, then the last one (the sun goes to the middle, 2E, the climb comes in).
func _dev_runner_end() -> void:
	var run := _run_id
	await _start_runner(true, 3)
	if run != _run_id or runner == null:
		return
	_node_box.close()
	await get_tree().create_timer(1.2).timeout
	if run != _run_id or runner == null:
		return
	runner.dev_last_piece()


## Opens a minigame on its own (developer shortcut ?mg=, tests).
func open_minigame_for_dev(id: String) -> void:
	_clear_menu()
	Game.has_breathing = true
	Game.intro_done = true
	if id == "mg1":
		_start_breathing()
	else:
		_on_trigger(id)


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

## The page's update check (tools/web_update_check.js) reloads by itself only
## on the boot / title screens: it reads the state from window.keeperState.
var _reported_state := "-"


func _report_state() -> void:
	if state == _reported_state or not OS.has_feature("web"):
		return
	_reported_state = state
	JavaScriptBridge.eval("window.keeperState = '%s'" % state.c_escape())


func _set_state(s: String) -> void:
	state = s
	# The forest intro's dialogs sit at the top (Kyra walks below), also in its
	# breathing minigame; the other minigames keep theirs at the bottom.
	_node_box.at_top = s in ["intro", "mg1"]
	_panel_box.at_top = _node_box.at_top
	match s:
		"intro", "mg1": Audio.play_bgm("forest.mp3", 0.4)
		"platformer":
			if Game.level == Game.PMS_ID:
				Audio.play_bgm("menu.mp3", 0.4)
			else:
				Audio.play_bgm("chamber.mp3" if Game.level == 1 else "forest.mp3", 0.5)
		"runner": Audio.play_bgm("forest.mp3", 0.55)
		"mg2", "mg3", "mg4", "mg5", "mg6", "mg7", "mg8", "mg9", "mg10", "mg11": Audio.play_bgm("minihra.mp3", 0.5)
		"title": Audio.play_bgm("menu.mp3", 0.5)


## Fade the screen to `col` (alpha `to`) over `time` seconds.
func _fade_to(to: float, time := 0.5, col := Color.BLACK) -> void:
	_fade.color = col
	var tw := create_tween()
	_fade_tws = _fade_tws.filter(func(t): return t.is_valid())
	_fade_tws.append(tw)
	tw.tween_property(_fade, "modulate:a", to, time)
	await tw.finished


func _set_dim(on: bool) -> void:
	create_tween().tween_property(_dim, "modulate:a", 0.7 if on else 0.0, 0.5)


func _clear_world() -> void:
	for c in _world_layer.get_children():
		c.queue_free()
	forest = null
	platformer = null
	runner = null
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
	_report_state()
	_pause.allowed = state in ["intro", "mg1", "platformer", "runner", "mg2", "mg3", "mg4", "mg5", "mg6", "mg7", "mg8", "mg9", "mg10", "mg11"]
	var any_dialog := _node_box.is_open() or _panel_box.is_open()
	if runner:
		runner.active = state == "runner"
		runner.visible = not state.begins_with("mg")
		runner.dialog_open = any_dialog
	if platformer:
		platformer.active = state == "platformer"
		platformer.dialog_open = any_dialog
		platformer.active_dialog_id = _node_box.node_id()
		platformer.hide_platforms = state in ["mg2", "mg3", "mg4", "mg5", "mg6", "mg7", "mg8", "mg9", "mg10", "mg11"]
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


## Developer mode: behind the team password once it is set up (DevAccess).
func _go_dev() -> void:
	if DevAccess.is_set_up() and not GitHubSave.has_token() and _menu:
		# Password only: an unchecked pasted token must not open developer mode.
		DevAccess.password_dialog(_menu, func(ok):
			if ok:
				_open_dev(), false)
		return
	_open_dev()


func _open_dev() -> void:
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
		"new_game":
			_start_new_game()
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
		"runner":
			# Level 2: the forest run (value = the stage to start at, 0–3).
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			Game.iron = 20
			_start_runner(true, value)
		"runner_end":
			# Level 2's end: the last piece, the sun to the middle, 2E, the climb (no fade).
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			Game.iron = 20
			_dev_runner_end()
		"checkpoint2":
			# Old meadow checkpoints: 1 start, 2..4 after its minigames, 5 the gate (ready to open).
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			Game.water = [0, 0, 30, 55, 80, 100][value]
			Game.seeds = [0, 0, 3, 6, 8, Game.SEEDS_NEEDED][value]
			_start_meadow(value, 10)
		"checkpoint5":
			# The jackpot climb: 1 start, 2..4 the 1st..3rd jackpot row, 5 near the top.
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			_start_climb(value)
		"climb_wheel":
			# The jackpot climb at its wheel of the cycle (mg11).
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			_dev_climb_wheel()
		"checkpoint6":
			# The PMS maze: 1 start, 2 the door open (all three items found).
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			_start_pms(value)
		"pms_transform":
			# The climb's top: the jackpot, 3E on the board, then the transformation.
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			_dev_climb_end()
		"checkpoint3":
			# Old summit checkpoints: 1 start, 2..4 after its minigames, 5 the LH wave.
			Game.reset_run()
			Game.has_breathing = true
			Game.intro_done = true
			for i in mini(value, 4) - 1:
				Game.upgrades[["jump", "dash", "double"][i]] = true
			_start_summit(value, 10)


## Stop everything that belongs to a run in progress (sounds, dialogs, overlays).
func _abort_run() -> void:
	_run_id += 1
	Audio.stop_all_loops()
	Audio.stop_voice()
	Audio.set_bgm_volume(0.5)
	_node_box.close()
	_panel_box.close()
	_dim.modulate.a = 0
	for t in _fade_tws:
		if t.is_valid():
			t.kill()
	_fade_tws.clear()
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
		_dialog("0D")
	else:
		_set_state("intro")
		forest.has_breathing = true
		_dialog("0D")


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
	await _start_level(1, checkpoint, iron, fade)


## (Re)start the meadow (level 2): 1 start, 2–4 after its minigames, 5 the gate.
func _start_meadow(checkpoint: int, iron: int, fade := true) -> void:
	await _start_level(2, checkpoint, iron, fade)


## (Re)start the old summit (id 3): 1 start, 2–4 after its minigames, 5 the LH wave.
func _start_summit(checkpoint: int, iron: int, fade := true) -> void:
	await _start_level(3, checkpoint, iron, fade)


## (Re)start the jackpot climb (level 3 of the game, id 5): 1 start, 2–4 the
## 1st–3rd jackpot row, 5 near the top. No iron, no game over.
func _start_climb(checkpoint := 1, fade := true) -> void:
	Game.upgrades = {}
	await _start_level(Game.CLIMB_ID, checkpoint, Game.iron, fade)


## (Re)start the PMS maze (level 4 of the game, id 6): 1 start, 2 the door open (all
## three comfort items found; developer menu). 4A when it shows.
func _start_pms(checkpoint := 1, fade := true) -> void:
	var run := _run_id
	await _start_level(Game.PMS_ID, mini(checkpoint, 1), Game.iron, fade)
	if run != _run_id or platformer == null or not platformer.is_pms():
		return
	if checkpoint >= 2:
		platformer.dev_all_comforts()
		platformer.dev_near_door()
	else:
		await get_tree().create_timer(0.4).timeout
		if run == _run_id and platformer != null and platformer.is_pms():
			_dialog("4A")


## The developer shortcut to the climb's wheel: from the 1st jackpot row onto the wheel's row.
func _dev_climb_wheel() -> void:
	var run := _run_id
	await _start_climb(2)
	if run != _run_id or platformer == null or not platformer.is_climb():
		return
	await get_tree().create_timer(0.5).timeout
	if run == _run_id and platformer != null and platformer.is_climb() and state == "platformer":
		platformer.teleport_to_trigger("mg11")


## The developer shortcut to the transformation: the climb near its top, then onto the top.
func _dev_climb_end() -> void:
	var run := _run_id
	await _start_climb(5)
	if run != _run_id or platformer == null:
		return
	await get_tree().create_timer(0.8).timeout
	if run != _run_id or platformer == null or not platformer.is_climb():
		return
	platformer.dev_to_top()


## A new Platformer for a level (not added to the tree yet), its signals connected.
func _make_platformer(lvl: int, checkpoint: int) -> Platformer:
	var pf := Platformer.new()
	pf.setup(Game.current_level_rows(lvl), checkpoint, lvl)
	pf.trigger.connect(_on_trigger)
	pf.boss_defeated.connect(_on_boss_defeated)
	pf.boss_lost.connect(_on_boss_lost)
	return pf


## The climb's end turns into the PMS maze (Platformer.start_prerod): the casino winds down,
## the sun (the follicle) comes close, opens and lets the egg go (ovulation), closes into the
## yellow body (the corpus luteum) and Kyra is pulled into its opening while the view turns
## upside down; when the opening fills the screen the maze (already upside down) starts
## inside it (Platformer.start_warm: warm amber, then its dusk), the climb goes and 4A opens.
## No fade to black.
func _into_pms(old: Platformer) -> void:
	var run := _run_id
	old.start_prerod()
	# (Polled, not a timer: the pause menu can stop the transformation half way.)
	while not old.prerod_finished():
		await get_tree().process_frame
		if run != _run_id or not is_instance_valid(old):
			return
	Game.level = Game.PMS_ID
	Game.checkpoint = 1
	Game.upgrades = {}
	var pf := _make_platformer(Game.PMS_ID, 1)
	pf.hold_input = true
	_world_layer.add_child(pf)
	platformer = pf
	# She comes in a little above (in the world) her platform and settles onto it.
	pf.p.y -= 70
	pf.start_warm()
	_set_state("platformer")
	old.queue_free()
	await get_tree().create_timer(Platformer.WARM_IRIS + 0.5, false).timeout
	if run != _run_id or platformer != pf:
		return
	pf.hold_input = false
	_dialog("4A")


func _start_level(lvl: int, checkpoint: int, iron: int, fade := true) -> void:
	var run := _run_id
	if fade:
		await _fade_to(1.0)
		if run != _run_id:
			return
	_clear_menu()
	_clear_world()
	_node_box.close()
	_set_dim(false)
	Game.level = lvl
	Game.checkpoint = checkpoint
	Game.iron = iron
	Game.has_breathing = Game.has_breathing or checkpoint >= 1 or Game.intro_done
	platformer = _make_platformer(lvl, checkpoint)
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
		var id := Text.dialog_for_letter(name.substr(7), Game.level)
		if id != "" and _node_box.node_id() != id:
			_dialog(id)
		return
	match name:
		"first_cramp":
			_dialog("1B")
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
		"mg5":
			_set_state("mg5")
			_open_minigame(IronPlateGame.new(), _mg5_done)
			_dialog("mg5_start")
		"mg6":
			_set_state("mg6")
			_open_minigame(RhythmGame.new(), _mg6_done)
			_dialog("mg6_start")
		"mg7":
			_set_state("mg7")
			_open_minigame(SignalsGame.new(), _mg7_done)
			_dialog("mg7_start")
		"mg8":
			_set_state("mg8")
			_open_minigame(MemoryGame.new(), _mg8_done)
			_dialog("mg8_start")
		"mg9":
			_set_state("mg9")
			_open_minigame(CatchGame.new(), _mg9_done)
			_dialog("mg9_start")
		"mg10":
			_set_state("mg10")
			_open_minigame(PairsGame.new(), _mg10_done)
			_dialog("mg10_start")
		"mg11":
			# The jackpot climb's wheel of the cycle: the climb waits (inactive, the board
			# doesn't rise); its intro is the minigame's hint panel (no dialog box).
			_set_state("mg11")
			_open_minigame(FertilityWheel.new(), _mg11_done)
		"gate_locked":
			if _node_box.node_id() != "MF":
				_dialog("MF")
		"gate":
			Game.checkpoint = 5
		"meadow_done":
			var run4 := _run_id
			await _fade_to(1.0, 1.5, Color.WHITE)
			if run4 != _run_id:
				return
			_dialog("MG", func():
				_start_summit(1, maxi(Game.iron, 8), false)
				_fade_to(0.0, 1.0, Color.WHITE))
		"wave":
			# The chase starts when the dialog closes (a retry skips the dialog).
			if Game.checkpoint < 5:
				Game.checkpoint = 5
				_dialog("SF")
		"wave_lost":
			_set_dim(true)
			var run2 := _run_id
			await get_tree().create_timer(0.6).timeout
			if run2 != _run_id:
				return
			_panel_box.show_panel({
				"title": "UI_WAVE_CAUGHT", "text": "UI_WAVE_CAUGHT_TEXT", "hide_button": true,
				"choices": [{"text": "BTN_TRY_AGAIN", "action": _retry_wave}],
			})
		"summit":
			var run3 := _run_id
			await get_tree().create_timer(2.5).timeout
			if run3 != _run_id:
				return
			_dialog("SG", func():
				Game.reset_run()
				_go_title())
		"climb_top":
			# The jackpot climb's top: the jackpot shows (platformer), then 3E talks on the
			# board (no dialog box, no buttons), then the title.
			Game.checkpoint = 5
			var run5 := _run_id
			await get_tree().create_timer(2.0).timeout
			if run5 != _run_id or platformer == null or not platformer.is_climb():
				return
			var pf := platformer
			pf.board_dialog_done.connect(func(id: String):
				if id == "3E" and run5 == _run_id and platformer == pf:
					# The transformation into the last level (the PMS maze).
					_into_pms(pf))
			pf.board_dialog("3E")
		"pms_item_1", "pms_item_2", "pms_item_3":
			# The PMS maze: each comfort item has its self-care tip (4B, 4C, 4D; by which
			# item, in any order); after the third one, whichever it is, 4F: the door is open.
			var pf6 := platformer
			_dialog(PmsMaze.ITEM_DIALOGS[int(name.right(1)) - 1], func():
				if platformer == pf6 and pf6 != null and pf6.pms_items >= PmsMaze.ITEMS.size():
					_dialog(PmsMaze.DOOR_DIALOG))
		"pms_done":
			# The open door: the cycle comes round (4E), then the title.
			Game.checkpoint = 5
			var run6 := _run_id
			await get_tree().create_timer(0.8).timeout
			if run6 != _run_id:
				return
			_dialog("4E", func():
				Game.reset_run()
				_go_title())
		"jackpot":
			# A jackpot row in the climb is a checkpoint (2..4 = the 1st..3rd row).
			var reached := 0
			if platformer:
				for e in platformer.level.entities:
					if e.trigger_type == "jackpot" and e.collected:
						reached += 1
			Game.checkpoint = clampi(reached + 1, 2, 4)
		"end":
			Game.checkpoint = 5
			Game.boss_iron = Game.iron
			_dialog("1C")
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
	if Game.level == Game.CLIMB_ID:
		_start_climb(maxi(1, mini(Game.checkpoint, 4)))
		return
	if Game.level == Game.PMS_ID:
		_start_pms(1)
		return
	if Game.level == 3:
		_start_summit(maxi(1, mini(Game.checkpoint, 4)), 5)
		return
	if Game.level == 2:
		_start_meadow(maxi(1, mini(Game.checkpoint, 4)), 5)
		return
	Game.boss_iron = 0
	_start_cave(1, 0)


func _retry_wave() -> void:
	_panel_box.close()
	_set_dim(false)
	# Back to the last stage floor (the wave starts again below it).
	_start_summit(maxi(1, mini(Game.checkpoint, 4)), maxi(Game.iron, 5))


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
	if runner:
		# The forest run goes on with its next stage.
		_set_state("runner")
		runner.after_minigame()
		return
	_set_state("platformer")


## Back from the wheel of the cycle: the climb goes on where she was, Estrogenka sums it
## up on the board (mg11_after). Opened on its own (?mg=mg11): the title.
func _mg11_done() -> void:
	_panel_box.close()
	_clear_minigame()
	if platformer == null or not platformer.is_climb():
		_go_title()
		return
	_set_state("platformer")
	platformer.after_wheel()


# Level 2 (meadow) minigames.
func _mg8_done() -> void:
	Game.checkpoint = 2
	_panel_box.close()
	_dialog("mg8_after", _back_to_cave)


func _mg9_done() -> void:
	Game.checkpoint = 3
	_panel_box.close()
	_dialog("mg9_after", _back_to_cave)


func _mg10_done() -> void:
	Game.checkpoint = 4
	_panel_box.close()
	_dialog("mg10_after", _back_to_cave)


# Level 3 minigames each unlock a power-up (estrogen rising: more energy).
func _mg5_done() -> void:
	Game.checkpoint = 2
	Game.upgrades["jump"] = true
	_panel_box.close()
	_dialog("mg5_after", _back_to_cave)


func _mg6_done() -> void:
	Game.checkpoint = 3
	Game.upgrades["dash"] = true
	_panel_box.close()
	_dialog("mg6_after", _back_to_cave)


func _mg7_done() -> void:
	Game.checkpoint = 4
	Game.upgrades["double"] = true
	_panel_box.close()
	_dialog("mg7_after", _back_to_cave)


func _on_boss_defeated() -> void:
	# The boss's dialogs play out in the arena (the nuts form their ring into
	# the grain meanwhile); then the floor is gone, Kyra falls, and she lands in
	# the forest run (see _into_forest).
	_dialog("1D", _into_forest)


func _into_forest() -> void:
	var run := _run_id
	if platformer == null:
		return
	# The nuts' ring closed into the grain (max ~6 s): the arena has no floor.
	for i in 360:
		if run != _run_id or platformer == null:
			return
		if platformer.boss.defeated_timer > 4.6:
			break
		await get_tree().process_frame
	# Kyra falls; the camera goes down with her a moment, then the forest fades
	# in below and she drops into it from above.
	platformer.start_exit_fall()
	# She hops up and over to the middle, then drops; the forest comes as she falls.
	for i in 55:
		await get_tree().process_frame
		if run != _run_id or platformer == null:
			return
	platformer.hide_egg = true
	platformer.hud.visible = false
	_start_runner(false, 0, null, true)


## Level 2 (demo): the forest run, seen from behind.
## Level 2: the forest run. stage > 0 (developer menu): from that stage, with
## the sun pieces of the stages before it found.
## over_cave: from the boss arena, which stays underneath while the forest
## fades in over it (and the 1D dialog stays open).
func _start_runner(fade := true, stage := 0, from_cave: Texture2D = null, over_cave := false) -> void:
	var run := _run_id
	if fade:
		await _fade_to(1.0)
		if run != _run_id:
			return
	_clear_menu()
	var old_world: Node = null
	if over_cave:
		old_world = platformer
		platformer = null
	else:
		_clear_world()
		_node_box.close()
	_set_dim(false)
	Game.level = 2
	Game.water = 0
	Game.seeds = 0
	runner = ForestRunner.new()
	runner.finished.connect(_runner_done)
	runner.sun_game.connect(_runner_minigame)
	runner.show_dialog.connect(_runner_dialog)
	_world_layer.add_child(runner)
	if stage > 0 and stage < runner.stages.size():
		runner.sun = stage * ForestRunner.SUN_PER_GAME
		var n := 0
		for o in runner.objects:
			if o.kind == "sun" and n < runner.sun:
				o.taken = true
				n += 1
		runner.jump_to(runner.stages[stage].start)
	_set_state("runner")
	if fade:
		_fade_to(0.0)
	if over_cave:
		# The forest fades in over the arena, which then goes.
		runner.start_intro(null, true)
		runner.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(runner, "modulate:a", 1.0, ForestRunner.INTRO_FADE)
		tw.finished.connect(func():
			if is_instance_valid(old_world):
				# She goes on falling in the forest from where she was.
				if is_instance_valid(runner) and old_world is Platformer:
					var v: Array = (old_world as Platformer).exit_visual()
					runner.handoff(v[0], v[1])
				old_world.queue_free())
		runner.intro_done.connect(runner.show_controls)
	elif stage == 0:
		# The level start: the forest appears, Kyra jumps in, then Iskra talks.
		runner.start_intro(from_cave)
		runner.intro_done.connect(func(): _dialog("2A"))
	else:
		_dialog("2A")


func _runner_dialog(id: String) -> void:
	if _node_box.node_id() != id:
		_dialog(id)


## Every 3 sun pieces: a minigame (memory, catch, pairs), then the next stage.
func _runner_minigame(n: int) -> void:
	_on_trigger(["mg8", "mg9", "mg10"][clampi(n - 1, 0, 2)])


## The 12th piece: the sun has glided to the middle (ForestRunner._finish); 2E, then the
## dialog box turns into the climb's board and the climb comes in (_into_climb).
func _runner_done() -> void:
	if runner:
		Game.water = int(runner.meter.reserve / runner.meter.reserve_max * 100.0)
	_dialog("2E", _into_climb)


## The forest run → the jackpot climb without a fade to black: the dialog box (2E just
## closed) is the climb's board at once, announcing the new phase (Platformer.announce_phase),
## while the climb (world and Kyra) crossfades in over the forest (CLIMB_IN s) and the sun
## in the middle of the sky melts into its light (Platformer.sun_glow). Kyra has control at
## once; the board waits for the crossfade plus its usual RISE_GRACE.
const CLIMB_IN := 1.2


func _into_climb() -> void:
	var run := _run_id
	var old := runner
	if old == null:
		_start_climb(1)
		return
	_clear_menu()
	Game.level = Game.CLIMB_ID
	Game.checkpoint = 1
	Game.upgrades = {}
	Game.has_breathing = true
	var pf := _make_platformer(Game.CLIMB_ID, 1)
	pf.rise_wait = CLIMB_IN + Platformer.RISE_GRACE
	pf.sun_glow = 1.0
	pf.announce_phase("CLIMB_PHASE_NEW", "CLIMB_PHASE_SUB")
	_world_layer.add_child(pf)
	platformer = pf
	runner = null
	pf.set_fade(0.0, false)
	_set_state("platformer")
	var tw := create_tween()
	tw.tween_method(func(a: float):
		if is_instance_valid(pf):
			pf.set_fade(a, false), 0.0, 1.0, CLIMB_IN)
	_fade_tws.append(tw)
	await tw.finished
	if is_instance_valid(old):
		old.queue_free()
	if run != _run_id:
		return


func _walk_to_meadow() -> void:
	var run := _run_id
	if platformer:
		platformer.scripted_walk = 2.2
	await get_tree().create_timer(1.6).timeout
	if run != _run_id:
		return
	await _fade_to(1.0, 1.0, Color.WHITE)
	if run != _run_id:
		return
	Game.upgrades = {}
	Game.water = 0
	Game.seeds = 0
	Game.gate_shift = 0
	await _start_level(2, 1, Game.iron, false)
	if run != _run_id:
		return
	await get_tree().create_timer(0.4).timeout
	_fade_to(0.0, 1.0, Color.WHITE)


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
	if platformer and platformer.corridor_t > 0:
		# Walking into the corridor: the run is about to start.
		return
	if event.shift_pressed and event.physical_keycode in [KEY_2, KEY_3, KEY_4, KEY_5]:
		# Shift+2…5: jump to the minigame / boss (level 2: LH wave) trigger.
		if platformer.is_climb():
			# The climb: its checkpoints (jackpot rows, near the top).
			platformer._place_at_checkpoint(event.physical_keycode - KEY_0)
			return
		platformer.teleport_to_trigger(platformer.progress_kinds()[event.physical_keycode - KEY_2])
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			if Game.level == Game.PMS_ID:
				_start_pms(1)
				return
			_start_level(Game.level, event.physical_keycode - KEY_0, Game.iron)
		KEY_5:
			if Game.level == Game.PMS_ID:
				# The maze: all three items found, the door opens.
				platformer.dev_all_comforts()
			elif Game.level == Game.CLIMB_ID:
				_start_climb(5)
			elif Game.level == 3:
				_start_summit(5, maxi(Game.iron, 5))
			elif Game.level == 2:
				Game.water = 100
				Game.seeds = Game.SEEDS_NEEDED
				_start_meadow(5, Game.iron)
			else:
				_skip_to_boss(maxi(Game.iron, 20))
		KEY_G:
			# G: jump to the old summit (id 3) with the power-ups.
			Game.upgrades = {"jump": true, "dash": true, "double": true}
			_start_summit(1, maxi(Game.iron, 10))
		KEY_H:
			# H: the meadow (level 2) with a full vessel.
			Game.water = 100
			Game.seeds = Game.SEEDS_NEEDED
			_start_meadow(1, maxi(Game.iron, 10))
		KEY_C:
			Game.has_breathing = true
			Game.iron = 20
