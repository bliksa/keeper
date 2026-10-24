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
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	main.process_mode = Node.PROCESS_MODE_PAUSABLE # as under the real root
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

	step("pause menu")
	await finish_dialog("cave_start")
	_key(KEY_ESCAPE, true)
	await frames(2)
	_key(KEY_ESCAPE, false)
	check(main._pause.is_open() and get_tree().paused, "Esc opens the pause menu and pauses")
	var px: float = main.platformer.p.x
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	check(main.platformer.p.x == px, "game is frozen while paused")
	_key(KEY_ESCAPE, true)
	await frames(2)
	_key(KEY_ESCAPE, false)
	check(not main._pause.is_open() and not get_tree().paused, "Esc again resumes")
	_key(KEY_ESCAPE, true)
	await frames(2)
	_key(KEY_ESCAPE, false)
	main._pause._buttons[1].pressed.emit()
	await frames(5)
	check(not get_tree().paused and main.state == "intro" and Game.iron == 0, "Restart game starts a new run")
	await finish_dialog("intro_forest")
	_key(KEY_ESCAPE, true)
	await frames(2)
	_key(KEY_ESCAPE, false)
	check(main._pause._buttons.size() == 4 and main._pause._buttons[2].text != "", "pause menu offers a fullscreen toggle")
	main._pause._buttons[3].pressed.emit()
	await frames(5)
	check(main.state == "title", "Main menu goes to the title screen")
	_key(KEY_ESCAPE, true)
	await frames(2)
	_key(KEY_ESCAPE, false)
	check(not main._pause.is_open(), "no pause menu on the title screen")

	step("developer menu + level editor")
	main._go_boot()
	await frames(3)
	await _click((main._menu as BootScreen)._dev.get_global_rect().get_center())
	await frames(3)
	check(main.state == "dev" and main._menu is DevMenu, "DEV button on the first screen opens developer mode")
	var dev: DevMenu = main._menu
	dev._show("level")
	await frames(3)
	var ed: LevelEditor = dev._editor
	check(ed != null and ed.rows.size() > 100, "editor loaded the level")
	# Real clicks: pick the Spike tool, then paint the top-left cell.
	var enemies: Button = ed._groups["enemies"].button
	await _click(enemies.get_global_rect().get_center())
	check(ed.tool == "S", "clicking a group selects its tool")
	check(ed._groups["enemies"].menu.visible, "clicking a group opens its menu right away")
	ed._groups["enemies"].menu.hide()
	ed._select_tool("^")
	check(ed._groups["platforms"].button.icon.resource_path.ends_with("triangle.svg"), "group button shows the chosen tool")
	await _click(ed._grid.get_global_rect().position + Vector2(LevelEditor.CELL_W / 2, LevelEditor.CELL_H / 2))
	await frames(2)
	check(ed.rows[0][0] == "^", "clicking the grid paints a spike")
	# Real mouse click on the TEST LEVEL button (it used to be swallowed by the dev menu).
	await _click(ed._test_button.get_global_rect().get_center())
	await seconds(1.0)
	check(ed._test != null and ed._test.active, "test play runs")
	await _click(Vector2(97, 584))
	await frames(3)
	check(ed._test == null, "BACK TO EDITOR button stops the test")

	step("animation lab")
	if FileAccess.file_exists(AnimLab.LOCAL_MANIFEST):
		DirAccess.remove_absolute(AnimLab.LOCAL_MANIFEST)
	dev._show("anim")
	await frames(3)
	var lab: AnimLab = dev._lab
	check(lab != null and lab.variant_names("run")[0] == "original" and lab._list.get_child_count() == 8, "lab lists the 8 original run frames")
	lab.set_preview("game")
	await seconds(2.0)
	check(absf(lab.p.vx) > 3.5 and lab.p.anim_progress > 0, "gameplay preview runs the character")
	var jumped := await until(func(): return not lab.p.is_grounded, 3)
	check(jumped, "gameplay preview jumps")
	lab.set_preview("anim")
	lab._select_anim("fall")
	await frames(2)
	check(lab.anim == "fall" and lab.current_paths().size() == 1, "animation dropdown switches to the fall pose")
	# Upload in the browser = receive_files(); use a real PNG's bytes.
	var png := FileAccess.get_file_as_bytes("res://assets/images/run3.png")
	lab._select_anim("run")
	lab.receive_files([["a1.png", png], ["a2.png", png], ["a3.png", png]], "new")
	var v := lab.current_variant()
	check(lab.is_local("run", v) and PlayerArt.overrides.get("run", []).size() == 3, "uploaded PNGs become a new run variant")
	lab.selected = 1
	lab.receive_files([["b.png", png]], "add")
	check(lab.current_paths().size() == 4 and lab.current_paths()[2].ends_with("b.png"), "adding a frame after the selected one")
	lab.selected = 0
	lab.receive_files([["c.png", png]], "replace")
	check(lab.current_paths()[0].ends_with("c.png") and lab.current_paths().size() == 4, "replacing a frame")
	lab.move_frame(0, 1)
	check(lab.current_paths()[1].ends_with("c.png"), "moving a frame down")
	lab.remove_frame(1)
	check(lab.current_paths().size() == 3 and PlayerArt.overrides.get("run", []).size() == 3, "removing a frame")
	lab.duplicate_variant()
	check(lab.current_variant() == v + " copy", "duplicating a variant")
	lab.rename_variant("fast run")
	check(lab.current_variant() == "fast run" and not lab.variant_names("run").has(v + " copy"), "renaming a variant")
	lab._select_anim("jump")
	lab.remove_frame(0)
	check(lab.current_paths().size() == 1, "a single-frame pose keeps its last frame")
	lab.step_frame(1)
	check(lab.paused, "stepping pauses the preview")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await frames(2)
	check(not lab.paused, "Space plays the paused animation")
	await _click(lab._play_btn.get_global_rect().get_center())
	await frames(2)
	check(lab.paused and lab._play_btn.text == "Play", "the Pause button pauses")
	# Asset browser: pick repo art for a frame.
	lab._select_anim("run")
	lab.selected = 0
	lab.open_assets("replace")
	await frames(30)
	check(lab._asset_grid.get_child_count() > 20, "asset browser lists the repo images")
	lab._asset_search.text = "idle"
	lab._fill_assets()
	await frames(2)
	check(lab._asset_grid.get_child_count() == 4, "asset browser filters by name")
	lab.assign_asset("res://assets/images/idle2.png")
	check(lab._assets == null and lab.current_paths()[0] == "res://assets/images/idle2.png", "picking an asset replaces the frame")
	lab.open_assets("add")
	lab.assign_asset("res://assets/images/idle3.png")
	check(lab.current_paths().size() == 4 and lab.current_paths()[1] == "res://assets/images/idle3.png", "picking an asset adds a frame")
	lab.remove_frame(1)
	lab.open_assets("background")
	await frames(2)
	check((lab._asset_grid.get_child(0).get_child(1) as Label).text == "No background", "background picker offers 'No background'")
	lab.assign_asset("res://assets/images/cave.png")
	await frames(2)
	check(lab.stage_bg == "res://assets/images/cave.png" and lab._assets == null, "picking a preview background")
	lab.open_assets("background")
	lab.assign_asset("")
	check(lab.stage_bg == "", "removing the preview background")
	var uploaded := lab.asset_folders().filter(func(f): return f[1] == AnimLab.LOCAL_DIR)
	check(uploaded.size() == 1 and lab.list_assets(AnimLab.LOCAL_DIR).size() >= 3, "uploads show up in the asset browser")
	# What "Save to repo" would commit, merged into the manifest on GitHub.
	lab._select_anim("run")
	var remote := JSON.stringify({"anims": {"run": {"other": ["res://x.png"]}}, "in_game": {}, "settings": {}})
	var files: Dictionary = lab.build_commit(remote)
	var m: Dictionary = JSON.parse_string(files["godot/data/anim_variants.json"].get_string_from_utf8())
	var pngs := files.keys().filter(func(k): return k.begins_with("godot/assets/anim_test/run/fast-run/"))
	check(pngs.size() == 2 and m.anims.run.has("other") and m.anims.run["fast run"].size() == 3 and m.in_game.run == "fast run", "save builds PNGs + merged manifest")
	check(m.anims.run["fast run"][1].begins_with("res://assets/anim_test/run/fast-run/02-") and m.anims.run["fast run"][0] == "res://assets/images/idle2.png", "saved manifest points at committed PNGs and picked repo assets")
	dev._show("anim")
	await frames(3)
	check(dev._lab.variant_names("run").has("fast run"), "local variants survive reopening")
	dev._lab.delete_variant()
	check(not dev._lab.variant_names("run").has("fast run"), "deleting a variant")
	dev._show("shortcuts")
	await frames(3)
	check(PlayerArt.overrides.is_empty(), "leaving without 'Use in game' restores the original frames")
	DirAccess.remove_absolute(AnimLab.LOCAL_MANIFEST)
	if FileAccess.file_exists(LevelEditor.AUTOSAVE):
		DirAccess.remove_absolute(LevelEditor.AUTOSAVE)


# --- helpers ------------------------------------------------------------------

func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		get_viewport().push_input(e, true)
		await get_tree().process_frame


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
