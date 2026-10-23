extends Node
## Headless end-to-end test. Plays through the whole game by driving inputs
## and game state, and fails loudly if a step does not happen.
##
##   godot --headless --fixed-fps 60 --path godot res://tests/test_runner.tscn
##
## Exit code 0 = all passed.

var main: Node
var failures := 0
var _step := ""


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("\n%s (%d failure%s)" % ["PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   ", msg)
	else:
		failures += 1
		printerr("  FAIL ", msg, "  [", _step, "]")


func step(name: String) -> void:
	_step = name
	print("\n== ", name)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func seconds(s: float) -> void:
	await frames(int(s * 60))


## Wait until cond() is true (max `timeout` seconds of game time).
func until(cond: Callable, timeout := 20.0) -> bool:
	for i in int(timeout * 60):
		if cond.call():
			return true
		await get_tree().process_frame
	return false


func node_box() -> DialogBox:
	return main._node_box


func panel_box() -> DialogBox:
	return main._panel_box


## Click through the open story dialog (always the first button).
func finish_dialog(expect: String) -> void:
	var opened := await until(func(): return node_box().node_id() == expect, 10)
	check(opened, "dialog '%s' opened" % expect)
	var guard := 0
	while node_box().node_id() == expect and guard < 20:
		node_box()._press(0)
		await frames(2)
		guard += 1


func _run() -> void:
	step("level data")
	var rows: PackedStringArray = Game.load_level_rows()
	var L := LevelData.build(rows)
	check(rows.size() > 100, "level has %d rows" % rows.size())
	check(L.has_spawn(), "level has a spawn point (P)")
	var types := {}
	for e in L.entities:
		if e.type == "trigger":
			types[e.trigger_type] = true
	for t in ["mg2", "mg3", "mg4", "end"]:
		check(types.has(t), "level has trigger " + t)
	check(L.platforms.size() > 50, "level has %d platforms" % L.platforms.size())
	check(LevelData.parse_text(LevelData.to_text(rows)) == rows, "level text round-trips")

	step("pipes layouts are solvable")
	_check_pipe_layouts()

	step("boot → title")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await frames(5)
	check(main.state == "boot", "starts on boot screen")
	main._menu.started.emit()
	await frames(5)
	check(main.state == "title", "title screen")

	step("forest intro")
	main._menu.start_pressed.emit()
	await frames(5)
	check(main.state == "intro", "intro state")
	await finish_dialog("intro_forest")
	Input.action_press("move_right")
	await finish_dialog("intro_fairy")
	Input.action_release("move_right")
	await finish_dialog("intro_breathing")
	await frames(3)
	check(main.state == "mg1", "breathing minigame started")
	check(main.minigame is BreathingGame, "BreathingGame shown")

	step("breathing minigame (real input)")
	var bg: BreathingGame = main.minigame
	for cycle in 6:
		Input.action_press("move_up")
		await seconds(4.1)
		Input.action_release("move_up")
		await seconds(2.0)
		Input.action_press("move_down")
		await seconds(6.1)
		Input.action_release("move_down")
		await frames(3)
		if not is_instance_valid(bg) or main.minigame != bg:
			break
	await until(func(): return main.minigame == null, 3)
	check(Game.has_breathing, "breathing unlocked after 6 cycles")
	await finish_dialog("intro_breathing_done")

	step("walk into the cave")
	Input.action_press("move_right")
	var in_cave := await until(func(): return main.state == "platformer", 30)
	Input.action_release("move_right")
	check(in_cave, "entered the cave")
	await finish_dialog("cave_start")
	var pf: Platformer = main.platformer
	check(pf != null and pf.active, "platformer active")

	step("cave physics")
	await seconds(1.0)
	check(pf.p.is_grounded, "player stands on a platform")
	var y0 := pf.p.y
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	await frames(10)
	check(pf.p.y < y0 - 20, "player jumped")
	await seconds(1.5)
	var iron_before := Game.iron
	_teleport_to_entity(pf, "iron")
	await frames(3)
	check(Game.iron == iron_before + 1, "collected one iron")

	step("cramp grabs, breathing frees")
	Game.iron = 10
	var enemy := _teleport_to_entity(pf, "enemy")
	await frames(3)
	check(pf.p.held_by_cramp == enemy.id, "held by a cramp")
	await _do_recharge()
	check(pf.p.held_by_cramp == -1, "breathing cycle freed the player")
	check(pf.p.breath_charges == 3, "breath charges refilled")

	step("minigame 2 – chocolate")
	await _go_trigger(pf, "mg2")
	check(main.state == "mg2", "state mg2")
	await finish_dialog("mg1_start")
	await finish_dialog("mg1_intro")
	var choco: ChocoPuzzle = main.minigame
	_solve_choco(choco)
	check(choco.solved, "chocolate puzzle solved")
	await finish_dialog("mg1_after")
	await frames(3)
	check(main.state == "platformer" and Game.checkpoint == 2, "back in the cave, checkpoint 2")

	step("minigame 3 – pipes")
	await _go_trigger(pf, "mg3")
	await finish_dialog("mg2_start")
	await finish_dialog("mg2_intro")
	var pipes: PipesGame = main.minigame
	check(_solve_pipes(pipes), "pipes solved by rotating")
	await finish_dialog("mg2_win")
	await finish_dialog("mg2_after")
	await frames(3)
	check(Game.checkpoint == 3, "checkpoint 3")

	step("minigame 4 – prices")
	await _go_trigger(pf, "mg4")
	await finish_dialog("mg3_start")
	var prices: PricesGame = main.minigame
	prices._set_guess(0, 1200)
	await frames(2)
	check(panel_box().is_open(), "evaluate button offered")
	panel_box()._press(0)
	await frames(2)
	check(prices.evaluated, "prices evaluated")
	await finish_dialog("mg3_after")
	check(Game.checkpoint == 4, "checkpoint 4")

	step("boss")
	Game.iron = 30
	await _go_trigger(pf, "end")
	check(pf.boss.active, "boss arena active")
	check(pf.hexes.size() == 30, "iron floor built from 30 iron")
	await finish_dialog("boss_start")
	pf.boss.hp = 1
	pf.boss.x = pf.p.x + 100
	pf.boss.y = pf.p.y
	pf.p.breath_charges = 1
	pf.p.breathing_cooldown = 0
	Input.action_press("breathe")
	await frames(2)
	Input.action_release("breathe")
	var won := await until(func(): return node_box().node_id() == "boss_win", 5)
	check(won, "boss defeated")
	await finish_dialog("boss_win")
	await frames(5)
	check(main.state == "title", "back to the title after the win")

	step("game over")
	main._dev_action("checkpoint", 1)
	await until(func(): return main.platformer != null and main.state == "platformer", 5)
	pf = main.platformer
	await finish_dialog("cave_start")
	Game.iron = 1
	var en := _teleport_to_entity(pf, "enemy")
	var over := await until(func(): return panel_box().is_open(), 5)
	check(over, "game over panel after losing the last iron")
	panel_box()._press(0)
	var old_id := pf.get_instance_id()
	var restarted := await until(func(): return main.platformer != null and main.platformer.get_instance_id() != old_id, 5)
	check(restarted, "try again restarts the cave")

	step("developer menu + level editor")
	main._go_title()
	await frames(3)
	main._go_dev()
	await frames(3)
	var dev: DevMenu = main._menu
	dev._show("level")
	await frames(3)
	var ed: LevelEditor = dev._editor
	check(ed != null and ed.rows.size() > 100, "editor loaded the level")
	ed._select_tool("^")
	ed._painting = 1
	ed._paint_at(Vector2(15, 15))
	ed._painting = 0
	check(ed.rows[0][0] == "^", "painting a spike works")
	ed.start_test()
	await seconds(1.0)
	check(ed._test != null and ed._test.active, "test play runs")
	ed.stop_test()
	await frames(3)
	check(ed._test == null, "test play stopped")
	if FileAccess.file_exists(LevelEditor.AUTOSAVE):
		DirAccess.remove_absolute(LevelEditor.AUTOSAVE)


# --- helpers ------------------------------------------------------------------

func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _teleport_to_entity(pf: Platformer, type: String) -> LevelData.Ent:
	for e in pf.level.entities:
		if e.type == type and not e.collected and not e.defeated:
			pf.p.x = e.x + e.w / 2 - pf.p.width / 2
			pf.p.y = e.y + e.h / 2 - pf.p.height / 2
			pf.p.vy = 0
			pf.camera_y = pf.p.y - 200
			return e
	check(false, "found a %s entity" % type)
	return null


func _go_trigger(pf: Platformer, kind: String) -> void:
	for e in pf.level.entities:
		if e.type == "trigger" and e.trigger_type == kind:
			pf.p.x = 500
			pf.p.y = e.y + 60
			pf.p.vy = 0
			pf.camera_y = e.y - 200
			break
	await frames(4)


func _do_recharge() -> void:
	Input.action_press("move_up")
	await seconds(4.1)
	Input.action_release("move_up")
	await seconds(2.0)
	Input.action_press("move_down")
	await seconds(6.2)
	Input.action_release("move_down")
	await frames(3)


func _solve_choco(c: ChocoPuzzle) -> void:
	for i in c.tiles.size():
		if c.tiles[i] != i:
			var j := c.tiles.find(i)
			c._pick(i)
			c._pick(j)


func _solve_pipes(g: PipesGame) -> bool:
	# Depth-first search along the water path, then the coffee path, choosing
	# rotations cell by cell; the result is checked with the game's own _check().
	var assign := {}
	if not _dfs(g, assign, 0, 0, 1, 1, 0):
		return false
	for i in assign:
		g.cells[i].rot = assign[i]
	g._check()
	return g.solved


func _dfs(g: PipesGame, assign: Dictionary, path: int, x: int, y: int, dir: int, steps: int) -> bool:
	var goal_y := 1 if path == 0 else 2
	if x == PipesGame.N:
		if y == goal_y and dir == 1:
			return true if path == 1 else _dfs(g, assign, 1, 0, 2, 1, 0)
		return false
	if x < 0 or y < 0 or y >= PipesGame.N or steps > 20:
		return false
	var i := y * PipesGame.N + x
	var cell: Dictionary = g.cells[i]
	if cell.type == "empty":
		return false
	var rots := [assign[i]] if assign.has(i) else [0, 1, 2, 3]
	for r in rots:
		var o := g._openings({"type": cell.type, "rot": r})
		var came := (dir + 2) % 4
		if not o[came]:
			continue
		var out := -1
		if cell.type == "cross":
			out = dir
		else:
			for k in 4:
				if k != came and o[k]:
					out = k
					break
		if out == -1:
			continue
		var fresh := not assign.has(i)
		assign[i] = r
		var nx: int = x + [0, 1, 0, -1][out]
		var ny: int = y + [-1, 0, 1, 0][out]
		if _dfs(g, assign, path, nx, ny, out, steps + 1):
			return true
		if fresh:
			assign.erase(i)
	return false


func _check_pipe_layouts() -> void:
	for li in PipesGame.LAYOUTS.size():
		var g := PipesGame.new()
		g.cells = []
		for c in PipesGame.LAYOUTS[li]:
			g.cells.append({"type": c[0], "rot": c[1], "shown": 0.0})
		g._done = true # don't emit completed
		var ok := _solve_pipes(g)
		check(ok, "layout %d solvable" % li)
		g.free()
