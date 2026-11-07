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
	# Headless starts with a 64×64 window; at that scale text metrics are rounded
	# far off. Use the game's real size so text layout matches the browser.
	get_tree().root.size = Vector2i(1066, 600)
	await get_tree().process_frame
	await _run()
	# A script error stops _run() early: that is a failure too.
	if not _finished:
		failures += 1
		print("  FAIL the test run stopped early (script error above)")
	print("\n%s (%d failure%s)" % ["PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
	get_tree().quit(1 if failures > 0 else 0)


## Set by the last line of _run().
var _finished := false


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
	var rowsm: PackedStringArray = Game.level_rows(2)
	var LM := LevelData.build(rowsm, LevelData.ROW_H, true)
	check(LM.horizontal and rowsm.size() == 10 and LM.width() > 5000 and LM.has_spawn(), "meadow is horizontal: %d columns, a spawn" % LM.cols)
	check(LM.water_top > 0, "meadow has a river")
	var tiers := {}
	var nseeds := 0
	var mtypes := {}
	for e in LM.entities:
		if e.type == "seed":
			nseeds += 1
			tiers[e.tier] = true
		if e.type == "trigger":
			mtypes[e.trigger_type] = true
	check(nseeds >= Game.SEEDS_NEEDED + 2 and tiers.size() == 4, "meadow has %d seeds in 4 tiers" % nseeds)
	for t in ["mg8", "mg9", "mg10", "gate"]:
		check(mtypes.has(t), "meadow has " + t)
	check(LevelData.parse_text(LevelData.to_text(rowsm), -1) == rowsm, "meadow text round-trips")
	var rows2: PackedStringArray = Game.level_rows(3)
	var L2 := LevelData.build(rows2)
	check(rows2.size() > 80 and L2.has_spawn(), "summit level has %d rows and a spawn" % rows2.size())
	var types2 := {}
	var kinds := {}
	for e in L2.entities:
		types2[e.trigger_type if e.type == "trigger" else e.type] = true
	for pl in L2.platforms:
		kinds[pl.kind] = true
	for t in ["mg5", "mg6", "mg7", "wave", "summit", "updraft", "dialog"]:
		check(types2.has(t), "garden has " + t)
	check(kinds.has("bubble") and kinds.has("pop") and kinds.has("rock"), "garden has rock, bubble and popping platforms")
	check(LevelData.parse_text(LevelData.to_text(rows2)) == rows2, "garden text round-trips")

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

	step("dialog font")
	var nb := node_box()
	check(nb._text.get_theme_font("normal_font") == Text.font_dialog and (Text.font_dialog as FontVariation).base_font.resource_path.ends_with("KeeperDyslexic-Regular.otf"), "dialog text uses OpenDyslexic (KeeperDyslexic: punctuation closer)")
	var too_long := []
	var smallest := 99
	var lang0: String = Text.language
	for lang in ["en", "sk", "pt"]:
		Text.language = lang
		for id in Text.dialogs:
			var parts: Array = Text.dialogs[id].get("parts", [])
			nb.show_node(id)
			for i in parts.size():
				nb._part = i
				nb._refresh()
				smallest = mini(smallest, nb.text_size())
				if nb._text.get_content_height() > nb._text.size.y:
					too_long.append("%s:%s#%d" % [lang, id, i])
			nb.close()
	Text.language = lang0
	Audio.stop_voice()
	check(too_long.is_empty(), "every dialog fits its box with OpenDyslexic (smallest size %d) %s" % [smallest, str(too_long)])

	step("forest intro")
	main._menu.start_pressed.emit()
	await frames(5)
	check(main.state == "intro", "intro state")
	await finish_dialog("0A")
	Input.action_press("move_right")
	await finish_dialog("0B")
	Input.action_release("move_right")
	await finish_dialog("0C")
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
	await finish_dialog("0D")

	step("walk into the cave")
	Input.action_press("move_right")
	var in_cave := await until(func(): return main.state == "platformer", 30)
	Input.action_release("move_right")
	check(in_cave, "entered the cave")
	await finish_dialog("1A")
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
	await finish_dialog("1C")
	pf.boss.hp = 1
	pf.boss.x = pf.p.x + 100
	pf.boss.y = pf.p.y
	pf.p.breath_charges = 1
	pf.p.breathing_cooldown = 0
	Input.action_press("breathe")
	await frames(2)
	Input.action_release("breathe")
	var won := await until(func(): return node_box().node_id() == "1D", 5)
	check(won, "boss defeated")
	# Click through 1D; on its last line Kyra drops away behind the box.
	var nb1 := node_box()
	var guard1 := 0
	while nb1.node_id() == "1D" and not nb1._is_last() and guard1 < 20:
		nb1._press(0)
		await frames(2)
		guard1 += 1
	await frames(2)
	check(main.platformer.exit_fall and main.platformer.p.vy != 0, "on the last line of 1D Kyra drops away behind the dialog box")
	await finish_dialog("1D")
	await frames(5)
	var run_ok := await until(func(): return main.state == "runner" and main.runner != null, 8)
	check(run_ok and Game.level == 2, "the forest run (level 2) starts after the boss")

	step("level 2 – the forest run")
	var rn0: ForestRunner = main.runner
	check(rn0.intro > 0 and rn0.py < -3 and node_box().node_id() != "2A" and rn0._intro_k(rn0.dist + 20) < 1.0, "level start: the trees appear from the middle, Kyra not there yet, no dialog")
	check(rn0.intro_elapsed() < ForestRunner.INTRO_FADE + 0.5, "the arena crossfades straight into the forest (no corridor, no dark)")
	var rn_landed := await until(func(): return rn0._landed, 6)
	check(rn_landed and rn0.py == 0 and rn0.land_t > 0, "Kyra jumps up from below and lands (back to us)")
	await finish_dialog("2A")
	var rn: ForestRunner = main.runner
	await frames(3)
	check(rn.active and not rn.dialog_open, "the run is active")
	var d0 := rn.dist
	await seconds(0.5)
	check(rn.dist > d0 + 3, "she runs forward on her own")
	rn.objects.clear()
	_key(KEY_RIGHT, true)
	await frames(2)
	_key(KEY_RIGHT, false)
	await seconds(0.3)
	check(rn.lane == 1 and absf(rn.px - ForestRunner.LANE) < 0.05, "→ moves her to the right path")
	_key(KEY_LEFT, true)
	await frames(2)
	_key(KEY_LEFT, false)
	await seconds(0.3)
	check(rn.lane == 0, "← back to the middle")
	# A stick tilt sends many motion events but changes lane once.
	for v in [0.3, 0.5, 0.7, 0.9, 1.0, 1.0]:
		var jm := InputEventJoypadMotion.new()
		jm.axis = JOY_AXIS_LEFT_X
		jm.axis_value = v
		Input.parse_input_event(jm)
		await frames(1)
	var jm0 := InputEventJoypadMotion.new()
	jm0.axis = JOY_AXIS_LEFT_X
	jm0.axis_value = 0.0
	Input.parse_input_event(jm0)
	await frames(2)
	check(rn.lane == 1, "a stick tilt moves one path, not two")
	rn.lane = 0
	rn.px = 0
	rn.build_course()
	check(rn.stages.size() == 4 and rn.objects.filter(func(o): return o.kind == "sun").size() == ForestRunner.SUN_TOTAL, "the map has 4 stages and 12 sun pieces")
	check(not rn.objects.any(func(o): return o.kind == "bird" and o.stage < 2) and not rn.objects.any(func(o): return o.kind == "seed"), "no flying notifications before stage 3, no seeds")
	check(not rn.objects.any(func(o): return o.kind == "bird" and o.stage == 0), "stage 1 has no crows (only jumping and water)")
	var roots: Array = rn.objects.filter(func(o): return o.kind == "root" and o.lane == -9)
	var root0: Dictionary = roots[0]
	rn.jump_to(root0.z - 0.4)
	rn.py = 0
	rn.vy = 0
	await frames(3)
	check(rn.bump_t > 0, "running into a root bounces her off")
	await seconds(0.45)
	check(rn.dist < root0.z - 4 and not root0.hit, "the path rolls back and the root waits for her again")
	rn.jump_to(root0.z - 3.0)
	rn.jump()
	var cleared := await until(func(): return rn.dist > root0.z + 1.5, 3)
	check(cleared and rn.bump_t <= 0 and not root0.hit, "a jump clears the root")
	var birds: Array = rn.objects.filter(func(o): return o.kind == "bird" and o.z - rn.stages[o.stage].start > ForestRunner.CARRY_BACK + 6)
	var bird: Dictionary = birds[0]
	rn.lane = bird.lane
	rn.px = bird.lane * ForestRunner.LANE
	rn.jump_to(bird.z + bird.dz - 0.2)
	rn.py = 1.3
	rn.vy = 0
	var before := rn.dist
	await frames(2)
	check(rn.carry_t > 0, "a bird catches her in the air")
	await seconds(1.4)
	check(rn.dist < before - 10 and rn.carry_t <= 0, "and carries her back along the path")
	check(not bird.hit and bird.z + bird.dz > rn.dist + 3, "the bird is ahead of her again and comes again")
	# With slowed time a single jump still clears a branch.
	var brs: Array = rn.objects.filter(func(o): return o.kind == "branch")
	var rbr: Dictionary = brs[0]
	rn.objects = rn.objects.filter(func(o): return o == rbr)
	rn.lane = rbr.lane
	rn.px = rbr.lane * ForestRunner.LANE
	rn.py = 0
	rn.vy = 0
	rn.bump_t = 0
	rn.water = 100
	rn.jump_to(rbr.z - 3.1)
	Input.action_press("slow_time")
	await frames(2)
	rn.jump_to(rbr.z - 3.1)
	rn.jump()
	var passed_br := await until(func(): return rn.dist > rbr.z + 1.0, 4)
	Input.action_release("slow_time")
	check(passed_br and rn.bump_t <= 0 and not rbr.hit, "a single jump clears a branch with slowed time too")
	rn.build_course()
	var drops: Array = rn.objects.filter(func(o): return o.kind == "drop" and o.y < 1.0 and not o.taken)
	var rdrop: Dictionary = drops[0]
	rn.lane = 0 if rdrop.lane == -9 else rdrop.lane
	rn.px = rn.lane * ForestRunner.LANE
	rn.water = 10
	rn.py = 0
	rn.jump_to(rdrop.z - 0.3)
	await frames(3)
	check(rdrop.taken and rn.water > 10 and rn.flyers.any(func(f): return f.kind == "drop"), "a water drop fills the focus bar (it flies up to it)")
	# Slowed time: the world runs slower while the water drains.
	rn.objects.clear()
	rn.water = 80
	var t0 := rn.dist
	await seconds(0.5)
	var normal := rn.dist - t0
	Input.action_press("slow_time")
	await frames(2)
	t0 = rn.dist
	await seconds(0.5)
	var slowed := rn.dist - t0
	Input.action_release("slow_time")
	await frames(3)
	check(rn.slow == false and slowed < normal * 0.6 and rn.water < 80, "holding Slow slows time (%.1f m vs %.1f m) and uses water" % [slowed, normal])
	rn.water = 2
	Input.action_press("slow_time")
	await frames(3)
	check(not rn.slow, "no slow-down without water")
	Input.action_release("slow_time")
	# Side traps: placed ones, and random ones in the last stage.
	rn.build_course()
	rn.water = 0
	var vines: Array = rn.objects.filter(func(o): return o.kind == "vine" and not o.get("random", false))
	check(vines.size() > 0 and rn.objects.filter(func(o): return o.kind == "vine" and o.get("random", false)).is_empty(), "side traps from the map; no random ones before the last stage")
	var vine: Dictionary = vines[0]
	rn.objects = rn.objects.filter(func(o): return o.kind != "root" and o.kind != "branch" and o.kind != "bird")
	rn.lane = vine.lane
	rn.px = vine.lane * ForestRunner.LANE
	rn.py = 0
	rn.vy = 0
	rn.jump_to(vine.z - 0.4)
	await frames(3)
	check(rn.bump_t > 0 and rn._roll_to < vine.z - 5, "a side trap knocks her back in the outer path")
	await seconds(0.5)
	rn.objects = rn.objects.filter(func(o): return o.kind in ["sun", "dialog"])
	# The sun: a stage repeats while its pieces are missing.
	rn.jump_to(rn.stages[0].start + 1)
	check(rn.sun == 0 and rn.stage == 0, "the sun starts empty")
	rn.jump_to(rn.stages[0].end - 0.2)
	await frames(3)
	check(rn.loops == 1 and rn.stage == 0 and rn.dist < rn.stages[0].start + 2, "the stage repeats from its start while its sun pieces are missing")
	var looped := await until(func(): return node_box().node_id() == "2D", 3)
	check(looped, "Iskra says the path goes round again")
	check(Text.dialogs["2D"].parts.size() == 2 and Text.t("2D2").length() > 20, "… and Estra says stress and strain can lengthen this phase")
	await finish_dialog("2D")
	rn.jump_to(rn.stages[0].end - 0.2)
	await frames(3)
	check(rn.loops == 2 and rn.loop_note > 0 and node_box().node_id() != "2D", "a later repeat shows a short note instead of the dialog")
	rn.loop_note = 0
	for n in ForestRunner.SUN_TOTAL:
		var pieces: Array = rn.objects.filter(func(o): return o.kind == "sun" and not o.taken)
		var pc: Dictionary = pieces[0]
		rn.lane = pc.lane
		rn.px = pc.lane * ForestRunner.LANE
		rn.py = 0
		rn.jump_to(pc.z - 0.3)
		var got := await until(func(): return pc.taken, 3)
		if not got or n == ForestRunner.SUN_TOTAL - 1:
			check(got, "sun piece %d is found" % (n + 1))
			break
		if (n + 1) % ForestRunner.SUN_PER_GAME == 0:
			var game_id: String = ["mg8", "mg9", "mg10"][(n + 1) / ForestRunner.SUN_PER_GAME - 1]
			var opened := await until(func(): return main.state == game_id and main.minigame != null, 3)
			await frames(2)
			check(opened and rn.waiting and not rn.visible and rn.sun == n + 1, "%d sun pieces open minigame %s" % [n + 1, game_id])
			await finish_dialog(game_id + "_start")
			main.minigame.completed.emit()
			await finish_dialog(game_id + "_after")
			await frames(3)
			check(main.state == "runner" and not rn.waiting and rn.stage == (n + 1) / ForestRunner.SUN_PER_GAME and rn.visible, "after the minigame the run goes on with stage %d" % ((n + 1) / ForestRunner.SUN_PER_GAME + 1))
	check(rn.objects.any(func(o): return o.get("random", false) and o.stage == 3), "the last stage has random side traps")
	var fin := await until(func(): return node_box().node_id() == "2E", 5)
	check(fin and rn.sun == ForestRunner.SUN_TOTAL, "the 12th piece completes the sun and ends the level")
	await finish_dialog("2E")
	var summit := await until(func(): return main.state == "platformer" and Game.level == 3 and main.platformer != null, 6)
	check(summit, "the summit (level 3) starts after the forest run")

	step("forest run – an edited map")
	# Stage 1 has 2 pieces, stage 2 has 4 and a dialog after them, stage 3 has 3.
	var map_up := ["..+..", "..+..", "A....", "..+..", "..+..", "..+..", "..+..", "..b..", "A....", "..+..", "..+..", "..+.."]
	map_up.reverse()
	var er := ForestRunner.new()
	er.rows = PackedStringArray(map_up)
	main.add_child(er)
	await frames(1)
	var take_next := func():
		var left: Array = er.objects.filter(func(o): return o.kind == "sun" and not o.taken)
		var pc: Dictionary = left[0]
		er.jump_to(pc.z)
		er.lane = 0
		er.px = 0
		er.py = 0
		er._hits(0.0)
	take_next.call()
	check(er.sun == 1 and er.sun_shown == 0 and er.flyers.size() == 1 and er.flyers[0].kind == "sun", "a found piece flies up to the sun first")
	await seconds(ForestRunner.FLY_TIME + 0.1)
	check(er.sun_shown == 1 and er.flyers.is_empty() and er.sun_pulse > 0, "then its slice fills and the sun lights up")
	take_next.call()
	er.dist = er.stages[0].end
	er._stage_end()
	check(er.sun == 2 and er.stage == 1 and er.loops == 0, "a stage without pieces left goes on (no endless loop)")
	take_next.call()
	check(er.waiting and er.sun == 3, "the 3rd piece (in stage 2) starts a minigame")
	er.after_minigame()
	check(er.stage == 1 and not er.waiting, "after it the run stays in stage 2: its other pieces can still be found")
	for i in 3:
		take_next.call()
	check(er.waiting and er.sun == 6, "6 pieces: the second minigame")
	var said := []
	er.show_dialog.connect(func(id): said.append(id))
	er.after_minigame()
	er._hits(0.0)
	check(er.stage == 2 and said.is_empty(), "then stage 3; the dialog it skipped stays unsaid")
	er.queue_free()

	step("level 3 – the summit")
	await finish_dialog("3A")
	pf = main.platformer
	check(pf.is_summit() and pf.p.y > pf.level_h - 500, "starts at the bottom of the summit")
	check(pf.wave.active and pf.wave.y > pf.p.y + 300, "the LH wave rises from the start, well below the player")
	# The tests teleport around; keep the wave out of the way until its own step.
	pf.wave.active = false
	# Wall jump: out of jumps, touching the left wall.
	pf.p.x = 0
	pf.p.y = pf.level_h - 400
	pf.p.vy = 2
	pf.p.jumps_left = 0
	pf.p.is_grounded = false
	await frames(2)
	check(pf.on_wall, "touching the wall in the air")
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	check(pf.p.vy < -5 and pf.p.vx > 5, "a wall jump kicks off the wall")
	# Momentum: a running jump is higher than a standing one.
	pf.p.vx = 0
	var standing := pf._jump_force()
	pf.p.vx = Platformer.MAX_SPEED * Platformer.SUMMIT_SPEED
	check(pf._jump_force() < standing * 1.3, "a running start jumps much higher")
	pf.p.vx = 0
	# Combo: jumps that clear two or more floors chain up.
	var ups: Array = pf.level.platforms.filter(func(pl): return pl.kind == "rock")
	ups.sort_custom(func(a, b): return a.base_y > b.base_y)
	pf.combo = 0
	pf.last_floor = 0
	var landed := 0
	var prev_floor := 0
	for pl in ups:
		if landed >= 3:
			break
		var fl: int = pf.floor_of(pl.base_y)
		if fl < prev_floor + 2:
			continue
		prev_floor = fl
		landed += 1
		pf.p.x = pl.x + 4
		pf.p.y = pl.base_y - pf.p.height - 6
		pf.p.vy = 2
		pf.p.is_grounded = false
		pf.p.was_grounded = false
		await frames(4)
	check(pf.combo >= 6 and pf.floor_now == prev_floor, "three multi-floor jumps chain into a combo (x%d) on floor %d" % [pf.combo, pf.floor_now])
	pf.p.y = pf.p.y + 400
	await seconds(0.5)
	check(pf.combo == 0, "falling back down resets the combo")
	await seconds(1.0)
	check(pf.p.is_grounded, "stands on the garden floor")
	# A popping bubble bursts after standing on it and regrows later.
	var pop: LevelData.Plat = null
	for pl in pf.level.platforms:
		if pl.kind == "pop":
			pop = pl
			break
	pf.p.x = pop.x + 6
	pf.p.y = pop.base_y - pf.p.height - 2
	pf.p.vy = 0
	pf.camera_y = pf.p.y - 300
	await seconds(1.3)
	check(pop.regrow > 0 and pf.p.y > pop.base_y, "a yellow bubble bursts after standing on it")
	await seconds(4.0)
	check(pop.regrow <= 0, "the bubble regrows")
	# An updraft lifts the player.
	var draft: LevelData.Ent = null
	for e in pf.level.entities:
		if e.type == "updraft":
			draft = e
	pf.p.x = draft.x + 6
	pf.p.y = draft.y + draft.h - pf.p.height
	pf.p.vy = 0
	var y_in := pf.p.y
	await seconds(0.5)
	check(pf.p.vy < 0 and pf.p.y < y_in - 40, "the updraft lifts the player")
	# Distractions only slow the player down.
	var iron_now := Game.iron
	_teleport_to_entity(pf, "enemy")
	await frames(4)
	check(pf.p.slow_timer > 0 and Game.iron == iron_now and pf.p.held_by_cramp == -1, "a distraction slows the player, costs no iron")

	step("minigame 5 – iron plate")
	await _go_trigger(pf, "mg5")
	check(main.state == "mg5", "state mg5")
	check(pf.p.is_grounded and pf.p.vy == 0, "Kyra lands on the ground when a minigame opens")
	await finish_dialog("mg5_start")
	var ip: IronPlateGame = main.minigame
	var bad_i := -1
	var good_i := []
	for i in 8:
		if ip._item(i).good: good_i.append(i)
		elif bad_i < 0: bad_i = i
	for i in [good_i[0], good_i[1], good_i[2], bad_i]:
		ip.toggle(i)
	await frames(2)
	check(ip.chosen.size() == 4 and panel_box().is_open(), "4 foods on the plate, serve button offered")
	panel_box()._press(0)
	await frames(2)
	check(ip.evaluated and not ip.perfect, "a plate with tea is not accepted")
	panel_box()._press(0)
	await frames(2)
	check(not ip.evaluated and ip.chosen.is_empty(), "try again clears the plate")
	for i in good_i:
		ip.toggle(i)
	await frames(2)
	panel_box()._press(0)
	await frames(2)
	check(ip.perfect, "the iron-friendly plate is accepted")
	await finish_dialog("mg5_after")
	await frames(3)
	check(main.state == "platformer" and Game.checkpoint == 2 and Game.upgrades.has("jump"), "back in the garden, checkpoint 2, higher jump")
	check(pf._jump_force() < Platformer.JUMP_FORCE, "jump power-up applies")

	step("minigame 6 – rhythm")
	await _go_trigger(pf, "mg6")
	await finish_dialog("mg6_start")
	var rg: RhythmGame = main.minigame
	rg._time = rg._beat_time(0) + 0.4
	rg.tap()
	check(rg.misses == 1 and rg.hits == 0, "a tap off the beat is a miss")
	for i in range(1, 11):
		rg._time = rg._beat_time(i)
		rg.tap()
	check(rg.hits == 10, "ten taps on the beat")
	await finish_dialog("mg6_after")
	await frames(3)
	check(Game.checkpoint == 3 and Game.upgrades.has("dash"), "checkpoint 3, dash unlocked")
	_key(KEY_SHIFT, true)
	await frames(2)
	_key(KEY_SHIFT, false)
	check(pf.p.dash_timer > 0 and absf(pf.p.vx) >= Platformer.DASH_SPEED - 0.1, "Shift dashes")

	step("minigame 7 – body signals")
	await _go_trigger(pf, "mg7")
	await finish_dialog("mg7_start")
	var sg: SignalsGame = main.minigame
	var phase_ids := ["m", "f", "o", "l"]
	sg.place((phase_ids.find(sg.card().phase) + 1) % 4)
	check(sg.wrong == 1 and sg.current == 0, "a wrong phase shakes the card")
	while not sg.all_placed():
		sg.place(phase_ids.find(sg.card().phase))
	check(sg.all_placed(), "all signals sorted")
	await finish_dialog("mg7_after")
	await frames(3)
	check(Game.checkpoint == 4 and Game.upgrades.has("double"), "checkpoint 4, super double jump")

	step("LH wave and the summit")
	await _go_trigger(pf, "wave")
	await finish_dialog("3F")
	await frames(2)
	check(pf.wave.active and Game.checkpoint == 5, "the LH wave rises")
	var wy: float = pf.wave.y
	await seconds(0.5)
	check(pf.wave.y < wy, "the wave moves up")
	var caught := await until(func(): return panel_box().is_open(), 15)
	check(caught and pf.wave.lost, "standing still, the wave catches the player")
	panel_box()._press(0)
	var old_pf := pf.get_instance_id()
	var retried := await until(func(): return main.platformer != null and main.platformer.get_instance_id() != old_pf and main.platformer.wave.active, 5)
	check(retried and Game.checkpoint == 4, "try again restarts from the last stage floor with the wave")
	pf = main.platformer
	await _go_trigger(pf, "summit")
	await frames(3)
	check(pf.wave.won and pf.summit_timer > 0, "reaching the summit stops the wave")
	await finish_dialog("3G")
	await frames(5)
	check(main.state == "title" and Game.level == 1, "back to the title after the summit")

	step("old meadow (developer menu)")
	main._dev_action("checkpoint2", 1)
	var meadow := await until(func(): return main.state == "platformer" and Game.level == 2 and main.platformer != null, 8)
	check(meadow, "the old meadow still starts from the developer menu")

	step("level 2 – the meadow")
	await finish_dialog("MA")
	pf = main.platformer
	check(pf.is_meadow() and pf.level.horizontal and pf.level_w > 5000, "a horizontal level with the camera following")
	await seconds(0.5)
	check(pf.p.is_grounded, "stands on the meadow ground")
	_teleport_to_entity(pf, "iron")
	await frames(3)
	check(Game.water == Game.WATER_PER_DROP, "a water drop fills the vessel")
	Game.water = 20
	# The river carries her back to the last ground she stood on.
	# The river: she floats, the current carries her, she can jump out near the surface.
	var bank := Vector2(pf.p.x, pf.p.y)
	pf.p.x = bank.x + 1200
	pf.p.y = pf.level.water_top + 10
	pf.p.vy = 0
	await seconds(0.6)
	check(pf.in_water and not pf.p.is_grounded and Game.water == 20 and absf(pf.p.y + pf.p.height / 2 - (pf.level.water_top + 30)) < 25, "she floats in the river, no water is lost")
	var wx := pf.p.x
	await seconds(0.5)
	check(pf.p.x < wx - 20, "the current carries her back")
	wx = pf.p.x
	Input.action_press("move_right")
	await seconds(1.0)
	Input.action_release("move_right")
	var swum := pf.p.x - wx
	check(swum > 10 and swum < 160, "swimming against the current is slow (%.0f px/s)" % swum)
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	check(pf.p.vy < -5, "a jump near the surface gets her out of the water")
	Game.water = 10
	check(pf._max_jumps() == 2 and not pf.water_unlock("thread"), "double jump stays; the thread is short with an empty vessel")
	Game.water = 50
	check(pf.water_unlock("thread") and pf.water_unlock("pull") and not pf.water_unlock("shield"), "50 % dew: longer thread and faster pull")
	pf.p.x = bank.x
	pf.p.y = bank.y
	pf.p.vy = 0
	await frames(3)
	# The focus thread pulls a seed in.
	var seeds: Array = pf.level.entities.filter(func(e): return e.type == "seed")
	seeds.sort_custom(func(a, b): return a.base_x < b.base_x)
	var seed0: LevelData.Ent = seeds[0]
	var seed1: LevelData.Ent = seeds.filter(func(e): return e.tier == 1)[0]
	check(seed0.tier == 0 and seeds[1].tier == 0 and seeds.back().tier == 3, "seeds get harder from left to right")
	_stand_under(pf, seed0)
	pf.aim_mode = "mouse"
	pf.aim = Vector2(seed0.x + 14, seed0.y + 14)
	pf.begin_focus()
	await frames(3)
	check(pf.focus and pf.thread_target == seed0.id, "the thread attaches to the aimed seed")
	var seed_caught := await until(func(): return Game.seeds == 1, 5)
	check(seed_caught and seed0.collected, "holding the focus pulls the seed in")
	pf.end_focus()
	# Letting go early: the seed drifts back.
	var seed2: LevelData.Ent = seeds[1]
	_stand_under(pf, seed2, 140)
	pf.aim = Vector2(seed2.x + 14, seed2.y + 14)
	pf.begin_focus()
	await seconds(0.4)
	var pulled: float = seed2.x
	pf.end_focus()
	await seconds(1.0)
	check(not seed2.collected and absf(seed2.x - seed2.base_x) < absf(pulled - seed2.base_x), "letting go early loses the seed, it drifts home")
	# A blinking seed can't be caught while dark.
	_stand_under(pf, seed1)
	pf.time_ms = (3.0 - seed1.id * 0.7) * 1000.0
	await frames(2)
	check(not seed1.visible, "a blinking seed goes dark")
	pf.aim = Vector2(seed1.x + 14, seed1.y + 14)
	pf.begin_focus()
	await frames(3)
	check(pf.thread_target == -1, "the thread finds nothing while the seed is dark")
	pf.end_focus()
	# A shadow hits while focusing: water spills, the gate moves.
	_stand_under(pf, seed2, 140)
	pf.aim = Vector2(seed2.x + 14, seed2.y + 14)
	pf.begin_focus()
	pf.shadow_timer = 0
	await frames(3)
	check(pf.thread_target == seed2.id and pf.shadows.size() == 1, "a shadow appears while the thread is held")
	Game.water = 80
	pf.shadows[0].x = pf.p.center().x
	pf.shadows[0].y = pf.p.center().y
	await frames(3)
	check(pf.focus and pf.shield_used and Game.water == 80 and (pf.shadows.is_empty() or pf.shadows[0].fading), "at 75 % the dew absorbs the first shadow hit")
	pf.shadow_timer = 0
	await frames(3)
	pf.shadows[0].x = pf.p.center().x
	pf.shadows[0].y = pf.p.center().y
	await frames(3)
	check(not pf.focus and Game.water == 65 and Game.gate_shift == 3, "the second shadow breaks the focus, spills water and pushes the gate")
	var gate: LevelData.Ent = null
	for e in pf.level.entities:
		if e.trigger_type == "gate":
			gate = e
	await frames(2)
	check(absf(gate.x - (gate.base_x + 3 * LevelData.CELL_W)) < 1, "the gate stands 3 cells further")
	await _go_trigger(pf, "gate")
	await finish_dialog("MF")
	check(Game.checkpoint < 5 and pf.meadow_end == 0, "the gate stays shut without a full vessel and ten seeds")

	step("minigame 8 – memory")
	await _go_trigger(pf, "mg8")
	check(main.state == "mg8", "state mg8")
	await finish_dialog("mg8_start")
	var mg: MemoryGame = main.minigame
	for rnd in 3:
		check(mg.phase == "show" and mg.round_i == rnd and mg.shown.size() == MemoryGame.ROUNDS[rnd], "round %d shows %d things" % [rnd + 1, MemoryGame.ROUNDS[rnd]])
		mg.skip_show()
		await frames(2)
		for k in mg.shown:
			mg.mark(k)
		mg.done_round()
		check(mg.found == mg.shown.size(), "all remembered things count")
		if rnd < 2:
			var nxt := await until(func(): return mg.round_i == rnd + 1, 5)
			check(nxt, "next round starts")
	await finish_dialog("mg8_after")
	await frames(3)
	check(main.state == "platformer" and Game.checkpoint == 2, "back in the meadow, checkpoint 2")

	step("minigame 9 – catch")
	await _go_trigger(pf, "mg9")
	await finish_dialog("mg9_start")
	var cg: CatchGame = main.minigame
	cg.items.clear()
	cg.drop("food", cg.cushion_x)
	cg.items[0].y = CatchGame.CUSHION_Y - 10
	await frames(2)
	check(cg.caught == 1, "food on the cushion counts")
	for i in 3:
		cg.drop("bolt", cg.cushion_x)
		cg.items[cg.items.size() - 1].y = CatchGame.CUSHION_Y - 10
		await frames(2)
	check(cg.caught == 0 and cg.resets == 1, "three lightning strikes restart the round")
	for i in CatchGame.GOAL:
		cg.items.clear()
		cg.drop("food", cg.cushion_x)
		cg.items[0].y = CatchGame.CUSHION_Y - 10
		await frames(2)
	check(cg.caught >= CatchGame.GOAL, "twenty nutrients caught")
	await finish_dialog("mg9_after")
	await frames(3)
	check(Game.checkpoint == 3, "checkpoint 3")

	step("minigame 10 – pairs")
	await _go_trigger(pf, "mg10")
	await finish_dialog("mg10_start")
	var pg: PairsGame = main.minigame
	pg.pick(0, 0)
	pg.pick(1, (pg.right_order.find(0) + 1) % PairsGame.PAIRS.size())
	check(pg.wrong == 1 and pg.hint_text != "" and pg.matched.is_empty(), "a wrong pair turns back with a hint")
	for i in PairsGame.PAIRS.size():
		pg.pick(0, i)
		pg.pick(1, pg.right_order.find(i))
	check(pg.all_matched(), "all signals paired with their meaning")
	await finish_dialog("mg10_after")
	await frames(3)
	check(Game.checkpoint == 4, "checkpoint 4")

	step("the gate")
	Game.water = 100
	Game.seeds = Game.SEEDS_NEEDED
	pf.gate_locked_timer = 0
	await frames(3)
	check(not gate.collected, "a locked gate re-arms once she steps away")
	await _go_trigger(pf, "gate")
	await frames(3)
	check(pf.meadow_end > 0 and Game.checkpoint == 5, "the gate opens with a full vessel and ten seeds")
	await finish_dialog("MG")
	summit = await until(func(): return main.state == "platformer" and Game.level == 3 and main.platformer != null, 6)
	check(summit, "the summit (level 3) starts after the meadow")
	main._quit_to_title()
	await frames(5)

	step("an aborted fade can't cover the next run")
	main._fade_to(1.0, 3.0, Color.WHITE)
	await frames(5)
	main._abort_run()
	await seconds(0.5)
	check(main._fade.modulate.a == 0.0, "aborting a run stops a fade in progress")

	step("game over")
	main._dev_action("checkpoint", 1)
	await until(func(): return main.platformer != null and main.state == "platformer", 5)
	pf = main.platformer
	await finish_dialog("1A")
	Game.iron = 1
	var en := _teleport_to_entity(pf, "enemy")
	var over := await until(func(): return panel_box().is_open(), 5)
	check(over, "game over panel after losing the last iron")
	panel_box()._press(0)
	var old_id := pf.get_instance_id()
	var restarted := await until(func(): return main.platformer != null and main.platformer.get_instance_id() != old_id, 5)
	check(restarted, "try again restarts the cave")

	step("pause menu")
	await finish_dialog("1A")
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
	await finish_dialog("0A")
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
	for i in [1, 2, 3]:
		var path := LevelEditor.AUTOSAVE if i == 1 else LevelEditor.AUTOSAVE_FMT % i
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# The team password: the repo token encrypted with it (no server).
	var enc := DevAccess.encrypt("github_pat_TEST123", "four random words here")
	check(DevAccess.decrypt(enc, "four random words here") == "github_pat_TEST123" and DevAccess.decrypt(enc, "wrong password!") == "" and not JSON.stringify(enc).contains("TEST123"), "the team password decrypts the token; a wrong one doesn't")
	var token0 := GitHubSave.get_token()
	GitHubSave.forget_token()
	DevAccess.data_override = enc
	main._go_boot()
	await frames(3)
	await _click((main._menu as BootScreen)._dev.get_global_rect().get_center())
	await frames(3)
	var pwd: Control = main._menu.get_child(main._menu.get_child_count() - 1)
	var pw_edit: LineEdit = pwd.find_children("*", "LineEdit", true, false)[0]
	check(main.state == "boot" and pw_edit != null, "with a team password, DEV asks for it first")
	check(not pwd.find_children("*", "Button", true, false).any(func(b): return b.text == "Use a GitHub token"), "… and only the password (an unchecked token can't open it)")
	pw_edit.text = "nope nope nope"
	pw_edit.text_submitted.emit(pw_edit.text)
	await frames(4)
	check(main.state == "boot" and not GitHubSave.has_token(), "a wrong password keeps developer mode closed")
	pw_edit.text = "four random words here"
	pw_edit.text_submitted.emit(pw_edit.text)
	await frames(4)
	check(main.state == "dev" and main._menu is DevMenu and GitHubSave.get_token() == "github_pat_TEST123", "DEV button on the first screen opens developer mode (password unlocks saving too)")
	var lock_btn: Array = (main._menu as DevMenu).header_tools.get_children().filter(func(b): return b is Button and b.text == "Lock")
	check(lock_btn.size() == 1, "developer mode has a Lock button once the team password exists")
	var gs_box := GitHubSave.token_dialog(main._menu, func(_ok): pass)
	check(gs_box.find_children("*", "LineEdit", true, false)[0].placeholder_text == "Team password", "Save to repo asks for the team password, not a token")
	gs_box.queue_free()
	(main._menu as DevMenu).lock()
	await frames(3)
	check(not GitHubSave.has_token() and main.state == "title", "Lock forgets the unlock (DEV asks again)")
	main._go_boot()
	await frames(3)
	await _click((main._menu as BootScreen)._dev.get_global_rect().get_center())
	await frames(3)
	var pwd2: Control = main._menu.get_child(main._menu.get_child_count() - 1)
	var pw2: LineEdit = pwd2.find_children("*", "LineEdit", true, false)[0]
	pw2.text = "four random words here"
	pw2.text_submitted.emit(pw2.text)
	await frames(4)
	check(main.state == "dev", "… and the password opens it again")
	# Setting up the password commits with the pasted token before any is saved.
	GitHubSave.forget_token()
	var api0 := GitHubSave.api_base
	GitHubSave.api_base = "http://127.0.0.1:9"
	GitHubSave.token_override = "github_pat_NEW"
	var ghs := GitHubSave.new()
	main.add_child(ghs)
	var cres: Dictionary = await ghs.commit({"x.txt": "x".to_utf8_buffer()}, "test")
	GitHubSave.token_override = ""
	GitHubSave.api_base = api0
	ghs.queue_free()
	check(not cres.ok and cres.error != "no token" and not GitHubSave.has_token(), "the team password setup commits with the pasted token (not 'no token')")
	DevAccess.data_override = null
	GitHubSave.forget_token()
	if token0 != "":
		GitHubSave.set_token(token0)
	var dev: DevMenu = main._menu
	dev._show("level")
	await frames(3)
	var ed: LevelEditor = dev._editor
	check(ed != null and ed.rows.size() > 100, "editor loaded the level")
	ed.select_level(2)
	await frames(2)
	check(ed.horizontal() and ed.cols() > 100 and ed.rows.size() == 10 and ed._tool_info.has("Y") and ed._tool_info.has("G"), "editor switches to the horizontal meadow and has its tools")
	# An autosave from before the dialog renaming gets today's letters.
	var old_txt := LevelData.to_text(Game.level_rows(3)).replace("b", "h")
	var af := FileAccess.open(LevelEditor.AUTOSAVE_FMT % 3, FileAccess.WRITE)
	af.store_string(old_txt)
	af.close()
	ed.select_level(3)
	await frames(2)
	check(not ed.horizontal() and ed.rows.size() == Game.level_rows(3).size() and ed._tool_info.has("@") and ed._tool_info.has("E"), "editor switches to the summit and has its tools")
	check(ed.rows == Game.level_rows(3), "an old autosave's dialog letters are moved to the new names (h → b)")
	DirAccess.remove_absolute(LevelEditor.AUTOSAVE_FMT % 3)
	if FileAccess.file_exists(LevelEditor.AUTOSAVE_FMT % ForestRunner.LEVEL_ID):
		DirAccess.remove_absolute(LevelEditor.AUTOSAVE_FMT % ForestRunner.LEVEL_ID)
	ed.select_level(ForestRunner.LEVEL_ID)
	await frames(3)
	check(ed.is_runner() and ed.cols() == ForestRunner.COLS and ed.rows.size() == Game.level_rows(ForestRunner.LEVEL_ID).size() and ed._tool_info.has("+") and ed._tool_info.has("<"), "editor shows the forest run as a top-down map with its tools")
	check(ed._scroll.scroll_vertical > 0, "the map opens at its start (the bottom)")
	check(ed._level_text().begins_with(ForestRunner.MAP_HEADER) and LevelData.parse_text(ed._level_text(), ForestRunner.COLS) == ed.rows, "the map keeps its legend when saved")
	var old_row := ed.rows[ed.rows.size() - 2]
	ed.tool = "+"
	ed._painting = 1
	ed._paint_at(Vector2(ed.cw() * 2.5, (ed.rows.size() - 2) * LevelEditor.CELL_H + 5))
	ed._painting = 0
	check(ed.rows[ed.rows.size() - 2][2] == "+", "painting a sun piece on the left path")
	ed.start_test()
	await frames(3)
	check(ed._test_run != null and ed._test_run.objects.filter(func(o): return o.kind == "sun").size() == ForestRunner.SUN_TOTAL + 1, "test play runs the edited map")
	ed.stop_test()
	await frames(2)
	check(ed._test_run == null, "back from the forest run test")
	ed.rows[ed.rows.size() - 2] = old_row
	ed._autosave()
	ed.select_level(1)
	await frames(2)
	check(ed.rows.size() == Game.level_rows(1).size(), "editor switches back to the cave")
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

	step("backgrounds and the asset browser")
	_clean_bg_state()
	var cave_bg := BackgroundData.of_bundled(1)
	check(cave_bg.layers.size() == 5 and cave_bg.tint and not cave_bg.procedural, "the cave's bundled background has 5 parallax layers")
	check(BackgroundData.of_bundled(2).procedural and BackgroundData.of_bundled(3).procedural, "meadow and summit keep their procedural skies")
	# Uploads: stored in this browser, listed, downloadable, deletable.
	var run_png := FileAccess.get_file_as_bytes("res://assets/images/run3.png")
	var big := Image.create(5000, 40, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.2, 0.6, 0.3))
	var up: Array = AssetBrowser.store([["hills.png", big.save_png_to_buffer()], ["junk.txt", "nope".to_utf8_buffer()]])
	check(up.size() == 1 and AssetBrowser.label(up[0]) == "hills.png", "uploads keep their name; non-images are refused")
	var jfif: Array = AssetBrowser.store([["photo.jfif", big.save_jpg_to_buffer()]])
	check(jfif.size() == 1 and jfif[0].ends_with("-photo.jpg") and AssetBrowser.list(AssetBrowser.UPLOAD_DIR).has(jfif[0]), "a .jfif upload is stored as .jpg and listed")
	var tx := AssetBrowser.tex(up[0])
	check(tx != null and tx.get_width() == AssetBrowser.MAX_PX, "wide uploads are scaled to %d px when loaded" % AssetBrowser.MAX_PX)
	check(AssetBrowser.folders().any(func(f): return f[1] == AssetBrowser.UPLOAD_DIR) and AssetBrowser.list(AssetBrowser.UPLOAD_DIR).has(up[0]), "uploads show up as a folder")
	check(AssetBrowser.bytes_of(up[0]).size() > 0 and AssetBrowser.file_name(up[0]) == "hills.png", "an upload downloads as its original file")
	var repo_png := AssetBrowser.bytes_of("res://assets/images/back2.png")
	var ri := Image.new()
	check(ri.load_png_from_buffer(repo_png) == OK and ri.get_width() == 595 and AssetBrowser.file_name("res://assets/images/back2.png") == "back2.png", "repo art downloads as a PNG")
	# The background panel.
	ed.select_level(1)
	ed.toggle_bg_panel()
	await frames(3)
	var bp: BackgroundPanel = ed.bg_panel
	check(bp != null and bp.layers().size() == 5 and not ed.bg_dirty(), "the background panel shows the cave's 5 layers")
	check(ed.bg_edit.is_empty() and not FileAccess.file_exists(LevelEditor.BG_AUTOSAVE), "just looking at a background stores nothing")
	check(Platformer.bg_origin_for(3, 28200) == Vector2(0, 27600) and Platformer.bg_origin_for(1, 28200) == Vector2.ZERO, "summit layers are anchored to its start at the bottom")
	bp.open_browser(-1)
	await frames(30)
	var br: AssetBrowser = bp.browser
	check(br != null and br.grid.get_child_count() > 5, "Add layer opens the asset browser")
	var drop: Array = br.receive_files([["mist.png", run_png]])
	await frames(2)
	check(drop.size() == 1 and br.current_dir() == AssetBrowser.UPLOAD_DIR and br.grid.get_child_count() >= 2, "uploading in the browser switches to the uploads")
	br.pick(up[0])
	await frames(2)
	check(not is_instance_valid(br) or br.is_queued_for_deletion(), "picking closes the browser")
	check(bp.layers().size() == 6 and bp.layers()[5].image == up[0] and ed.bg_dirty(), "the picked image becomes a new front layer")
	bp.set_value(5, "speed", 1.5)
	bp.set_value(5, "opacity", 0.5)
	bp.set_value(5, "offset_x", 40)
	bp.set_value(5, "repeat", false)
	var l5: Dictionary = bp.layers()[5]
	check(l5.speed == 1.5 and l5.opacity == 0.5 and l5.offset[0] == 40.0 and not l5.repeat, "layer settings change")
	bp.move_layer(5, -1)
	check(bp.layers()[4].image == up[0], "moving a layer to the back")
	bp.replace_layer(4, drop[0])
	check(bp.layers()[4].image == drop[0], "replacing a layer's image")
	bp.remove_layer(0)
	check(bp.layers().size() == 5, "removing a layer")
	bp.replace_layer(3, up[0])
	# Persisted in this browser and reloaded.
	ed._load_bg_edits()
	check(ed.current_bg().layers.size() == 5 and ed.current_bg().layers[3].image == up[0], "background edits survive a reload")
	bp = ed.bg_panel
	# Test play draws the edited background; the panel steps aside meanwhile.
	ed.start_test()
	await frames(5)
	check(ed._test != null and ed._test.background.layers.size() == 5 and ed._test.background.layers[3].image == up[0], "test play uses the edited background")
	check(not bp.visible, "the background panel is hidden during test play")
	ed.stop_test()
	await frames(2)
	check(bp.visible, "and comes back after it")
	# Uploads in use can't be deleted; the lab's frame files never can.
	var br3 := AssetBrowser.new()
	br3.in_use = ed.bg_in_use
	ed.add_child(br3)
	await frames(2)
	check(not br3.delete_asset(up[0]) and FileAccess.file_exists(up[0]), "an upload used by a layer can't be deleted")
	check(not br3.can_delete(AssetBrowser.ANIM_UPLOAD_DIR + "run/1-a.png") and not br3.can_delete("res://assets/images/1.png"), "frame files and repo art have no delete")
	br3.close_browser()
	# Save to repo: uploaded images are committed (scaled down) and the manifest points at them.
	var bfiles: Dictionary = ed.build_bg_commit("")
	var mf: Dictionary = JSON.parse_string(bfiles["godot/data/backgrounds.json"].get_string_from_utf8())
	var bkeys: Array = bfiles.keys().filter(func(k): return k.begins_with("godot/assets/backgrounds/cave-hills-"))
	var bimg := Image.new()
	if bkeys.size() == 1:
		bimg.load_png_from_buffer(bfiles[bkeys[0]])
	check(bkeys.size() == 1 and bimg.get_width() == LevelEditor.BG_MAX_PX, "uploads are committed (name + content hash), wide ones scaled to %d px" % LevelEditor.BG_MAX_PX)
	check(bkeys.size() == 1 and mf["1"].layers[3].image == "res://" + bkeys[0].trim_prefix("godot/") and mf["2"].procedural, "the committed manifest points at the new images and keeps the other levels")
	# After a save it isn't committed again, and a missing image stops the save.
	ed.bg_saved["1"] = {"local": JSON.stringify(ed.current_bg()), "committed": JSON.stringify(BackgroundData.normalize(mf["1"]))}
	check(not ed.bg_dirty(), "a background committed from here isn't committed again")
	ed.bg_saved.erase("1")
	bp.add_layer(AssetBrowser.UPLOAD_DIR + "123-gone.png")
	check(ed.build_bg_commit("").has("_error"), "a layer whose upload is gone stops the save")
	bp.remove_layer(bp.layers().size() - 1)
	# Use in game, then back to the bundled one.
	ed._use_in_game()
	check(BackgroundData.for_level(1).layers[3].image == up[0], "Use in game applies the background")
	ed._use_bundled()
	check(BackgroundData.for_level(1).layers.size() == 5 and BackgroundData.for_level(1).layers[3].image == "res://assets/images/4.png", "back to the bundled background")
	ed.reset_bg()
	check(not ed.bg_dirty() and bp.layers().size() == 5, "Reset restores the game's background")
	# Deleting an upload.
	var br2 := AssetBrowser.new()
	ed.add_child(br2)
	await frames(2)
	br2.delete_asset(up[0])
	check(not FileAccess.file_exists(up[0]), "an unused upload can be deleted")
	br2.close_browser()
	ed.toggle_bg_panel()
	await frames(2)
	check(ed.bg_panel == null, "the background panel closes")
	_clean_bg_state()

	step("animation lab")
	var player_before: Array = PlayerArt.overrides.keys()
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
	await frames(3)
	check(lab._assets.current_dir() == AssetBrowser.ANIM_UPLOAD_DIR, "the browser opens on the current frame's folder")
	var drop_path := "user://drop_test.png"
	var dfa := FileAccess.open(drop_path, FileAccess.WRITE)
	dfa.store_buffer(png)
	dfa.close()
	var nframes := lab.current_paths().size()
	lab._on_files_dropped(PackedStringArray([ProjectSettings.globalize_path(drop_path)]))
	check(lab.current_paths().size() == nframes, "a drop on the open browser doesn't add frames")
	DirAccess.remove_absolute(drop_path)
	lab._assets.refresh_folders("res://assets/images/")
	await frames(30)
	check(lab._assets.grid.get_child_count() > 20, "asset browser lists the repo images")
	lab._assets.search.text = "idle"
	lab._assets.fill()
	await frames(2)
	check(lab._assets.grid.get_child_count() == 4, "asset browser filters by name")
	lab.assign_asset("res://assets/images/idle2.png")
	check(lab._assets == null and lab.current_paths()[0] == "res://assets/images/idle2.png", "picking an asset replaces the frame")
	lab.open_assets("add")
	lab.assign_asset("res://assets/images/idle3.png")
	check(lab.current_paths().size() == 4 and lab.current_paths()[1] == "res://assets/images/idle3.png", "picking an asset adds a frame")
	lab.remove_frame(1)
	lab.open_assets("background")
	await frames(2)
	check((lab._assets.grid.get_child(0).get_child(1) as Label).text == "No background", "background picker offers 'No background'")
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
	# Collectibles, enemies and NPCs.
	var sprites_before: Dictionary = lab._saved_state.sprites
	check(SpriteArt.DEFS.keys().all(func(id): return not PlayerArt.ANIMS.has(id)), "sprite ids don't clash with Kyra's animations")
	lab.select_category("enemies")
	await frames(2)
	check(lab.anim == "cramp" and lab._anim_pick.item_count == SpriteArt.ids_in("enemies").size() and lab.current_paths().is_empty(), "the Enemies tab lists the enemies; the cramp is drawn in code")
	lab.open_assets("add")
	lab.assign_asset("res://assets/images/krc1.png")
	lab.open_assets("add")
	lab.assign_asset("res://assets/images/krc2.png")
	await frames(2)
	check(SpriteArt.has_art("cramp") and SpriteArt.frames("cramp").size() == 2 and lab.current_paths()[1] == "res://assets/images/krc2.png", "frames from the assets replace the code-drawn cramp")
	lab.set_sprite_setting("cramp", "fps", 5.0)
	check(SpriteArt.texture("cramp", 250.0) == SpriteArt.frames("cramp")[1], "a sprite plays at its own frame rate")
	lab.remove_frame(0)
	lab.remove_frame(0)
	check(lab.current_paths().is_empty() and not SpriteArt.has_art("cramp"), "removing every frame goes back to the code-drawn art")
	lab.receive_files([["k.png", png]], "replace")
	check(lab.current_paths().size() == 1 and SpriteArt.has_art("cramp"), "replacing a frame of an empty sprite adds it")
	lab.set_preview("game")
	await frames(3)
	lab.set_preview("anim")
	lab._select_anim("estra")
	check(lab.category == "npcs" and lab.current_paths().size() == 6 and SpriteArt.texture("estra", 0) != null, "Estra (NPC) lists her 6 ghost frames")
	lab._select_anim("portrait_kyra")
	lab.open_assets("replace")
	lab.assign_asset("res://assets/images/kira1.png")
	lab.open_assets("add")
	lab.assign_asset("res://assets/images/kira2.png")
	check(SpriteArt.portrait("Kyra", 0) == SpriteArt.frames("portrait_kyra")[0] and SpriteArt.portrait_animated("Kyra"), "a dialog portrait can be replaced and animated")
	check(SpriteArt.portrait("Iskra") != null and SpriteArt.frames("portrait_iskra").is_empty(), "Iskra's portrait stays code-drawn")
	lab.select_category("collectibles")
	await frames(2)
	check(lab.anim == "iron" and lab._settings_grid.get_child_count() == 2, "the Items tab shows a sprite's fps and size")
	check(lab.current_variant() == "drawn nut" and lab.current_paths().size() == 8 and SpriteArt.has_art("iron"), "the drawn nut (8 frames) is the iron in game")
	var sremote := JSON.stringify({"anims": {}, "in_game": {}, "settings": {}, "sprites": {"bird": {"scale": 2.0, "fps": 4.0}}})
	var sm: Dictionary = JSON.parse_string(lab.build_commit(sremote)["godot/data/anim_variants.json"].get_string_from_utf8())
	check(sm.in_game.cramp == lab.chosen.cramp and sm.sprites.cramp.fps == 5.0 and sm.sprites.bird.scale == 2.0 and sm.anims.portrait_kyra[lab.chosen.portrait_kyra].size() == 2, "save commits sprite variants and settings")
	lab.select_category("kyra")
	check(lab.anim == "run" and lab._settings_grid.get_child_count() == 4, "back to Kyra's animations")
	lab._select_anim("boss")
	lab.select_category("enemies")
	check(lab._anim_pick.get_item_metadata(lab._anim_pick.selected) == "boss", "re-clicking the tab keeps the selected sprite")
	check(not sm.sprites.has("iron") and sm.sprites.bird.fps == 4.0, "only changed sprite settings are committed")
	dev._show("anim")
	await frames(3)
	check(dev._lab.variant_names("run").has("fast run"), "local variants survive reopening")
	dev._lab.delete_variant()
	check(not dev._lab.variant_names("run").has("fast run"), "deleting a variant")
	dev._show("shortcuts")
	await frames(3)
	check(PlayerArt.overrides.keys() == player_before, "leaving without 'Use in game' restores the frames the game had")
	check(SpriteArt.overrides.keys() == SpriteArt.DEFS.keys().filter(func(id): return sprites_before.has(id)) and not SpriteArt.overrides.has("cramp") and not SpriteArt.settings.has("cramp"), "… and the sprites the game had before")
	DirAccess.remove_absolute(AnimLab.LOCAL_MANIFEST)
	if FileAccess.file_exists(LevelEditor.AUTOSAVE):
		DirAccess.remove_absolute(LevelEditor.AUTOSAVE)

	step("dialog editor")
	if FileAccess.file_exists(DialogEditor.EDIT_PATH):
		DirAccess.remove_absolute(DialogEditor.EDIT_PATH)
	dev._show("dialogs")
	await frames(3)
	var de: DialogEditor = dev._dialogs
	check(dev.actions.get_child_count() == 4 and (dev.actions.get_child(3) as Button).icon.resource_path.ends_with("save.svg"), "test / use in game / save (floppy) on the right of the bar")
	check(de != null and de.ids_in("2") == ["2A", "2B", "2C", "2D", "2E"] and de.ids_in("0").size() == 4, "the Dialogs tab lists each level's dialogs (2A–2E, 0A–0D)")
	check(Text.dialog_for_letter("c", ForestRunner.LEVEL_ID) == "2C" and Text.dialog_for_letter("b", 3) == "3B" and Text.dialog_for_letter("z", 1) == "", "letter c in level 2 starts dialog 2C")
	check(de.ids_in("mg").has("mg8_start") and not DialogEditor.is_story("mg8_start"), "minigame talk is listed apart, under its own names")
	# Saving the files as they are changes nothing (same format as in the repo).
	var bundled := {"godot/data/dialogs.json": FileAccess.get_file_as_string("res://data/dialogs.json"),
		"godot/data/characters.json": FileAccess.get_file_as_string("res://data/characters.json")}
	for l in DialogEditor.LANGS:
		bundled["godot/data/i18n/%s.json" % l] = FileAccess.get_file_as_string("res://data/i18n/%s.json" % l)
	var same := de.build_commit(bundled)
	var diff := same.keys().filter(func(k): return same[k] != bundled.get(k))
	check(not same.is_empty() and diff.is_empty(), "the dialog files round-trip unchanged %s" % str(diff))
	de.select_group("2")
	de.select("2C")
	await frames(2)
	check(de._title.text == "Dialog 2C" and de._lines.get_child_count() == 1 + 1, "dialog 2C shows its line and Add line")
	check(de._buttons_box.get_child_count() == 2 and de._buttons_box.get_global_rect().position.x < DialogEditor.LIST_W, "its button is edited on the left (button + Add button)")
	var bkey := de.new_button("Let's run!")
	check(bkey == "BTN_LETS_RUN" and de.button_texts[bkey].en == "Let's run!", "a new button gets a key from its text")
	de.set_button(0, bkey)
	de.set_button_text(bkey, "sk", "Bežíme!")
	de.add_button("BTN_CONTINUE")
	check(de.nodes["2C"].buttons == [bkey, "BTN_CONTINUE"] and de._buttons_box.get_child_count() == 3, "a second button (a choice)")
	de.remove_button(1)
	var bf := de.build_commit(bundled)
	var bsk: Dictionary = JSON.parse_string(bf["godot/data/i18n/sk.json"])
	var bdj: Dictionary = JSON.parse_string(bf["godot/data/dialogs.json"])
	check(bsk.get(bkey, "") == "Bežíme!" and bdj.nodes["2C"].buttons == [bkey], "save writes the button and its texts")
	check(de.fits("Short line.") and not de.fits("Very long line. ".repeat(80)), "a line that doesn't fit the box is marked")
	de.set_text(0, "en", "Edited line one.")
	de.add_line()
	de.set_text(1, "en", "Second line.")
	de.set_text(1, "sk", "Druhý riadok.")
	de.move_line(1, -1)
	check(de.key_of("2C", 0) == "2C1" and de.nodes["2C"].lines[0].text.en == "Second line." and de.is_changed("2C") and FileAccess.file_exists(DialogEditor.EDIT_PATH), "lines are named 2C1, 2C2 in their order; edits are kept locally")
	de.new_dialog()
	check(de.current == "2F" and de.nodes.has("2F") and de.ids_in("2").back() == "2F", "a new dialog gets the next free letter (2F)")
	de.set_text(0, "en", "Brand new.")
	var dfiles := de.build_commit(bundled)
	var dj: Dictionary = JSON.parse_string(dfiles["godot/data/dialogs.json"])
	var den: Dictionary = JSON.parse_string(dfiles["godot/data/i18n/en.json"])
	var nk: Array = dj.nodes.keys()
	check(dj.nodes["2C"].parts.size() == 2 and dj.nodes["2C"].parts[1].text == "2C2" and den["2C1"] == "Second line." and den["2C2"] == "Edited line one." and den["2F1"] == "Brand new.", "save writes the dialogs and their lines in every language")
	check(nk.find("2F") == nk.find("2E") + 1 and nk.find("3A") == nk.find("2F") + 1 and dj.nodes.has("mg8_start"), "saved dialogs stay in level order")
	# Characters: who speaks, with an avatar sprite each.
	de.select("2C")
	await frames(2)
	var sp_pick: OptionButton = de._lines.get_child(0).find_children("*", "OptionButton", true, false)[0]
	check(sp_pick.get_item_text(sp_pick.item_count - 1) == "New character…" and Text.speaker_name("Estrogenka") in ["Estra", "Estrogenka"], "each line has a speaker dropdown with the characters and New character…")
	var dlg := de.character_dialog(0)
	check(dlg != null, "New character asks for the name")
	dlg.queue_free()
	check(de.add_character("Luna", {"en": "Moon"}) == "Luna" and de.add_character("Luna", {}) == "", "a new character (a name can't be taken twice)")
	check(Text.speaker_name("Luna") in ["Luna", "Moon"] and SpriteArt.is_sprite("portrait_luna") and SpriteArt.ids_in("npcs").has("portrait_luna") and SpriteArt.portrait("Luna") != null, "it gets a dialog-avatar slot in Animations > NPCs")
	de.set_speaker(0, "Luna")
	var cfiles := de.build_commit(bundled)
	var cj: Dictionary = JSON.parse_string(cfiles.get("godot/data/characters.json", "{}"))
	var cd: Dictionary = JSON.parse_string(cfiles["godot/data/dialogs.json"])
	check(cj.get("characters", {}).has("Luna") and cj.characters.has("Kyra") and cd.nodes["2C"].parts[0].speaker == "Luna", "save commits the new character and who speaks")
	de.select("2F")
	de.delete_dialog()
	check(not de.nodes.has("2F") and not de.deleted.has("2F"), "a new dialog can be deleted again")
	de.select("2C")
	de.use_in_game()
	check(Text.t("2C2") == "Edited line one." and Text.dialogs["2C"].parts.size() == 2, "Use in game: the game says the edited dialog")
	de.play("en")
	await frames(3)
	check(de._preview != null and de._preview.is_open() and de._preview._node_id == "__preview", "Play shows the dialog in the real dialog box")
	de.close_preview()
	await frames(2)
	de.discard()
	check(not de.is_changed("2C") and not de.has_unsaved(), "discarding the local edits")
	check(not Text.characters.has("Luna") and not SpriteArt.is_sprite("portrait_luna"), "… new characters too")
	Text.language = "sk"
	de.play("en")
	await frames(2)
	de.play("pt")
	await frames(2)
	check(Text.language == "pt", "Play shows the dialog in the chosen language")
	de.close_preview()
	check(Text.language == "sk" and not Text.dialogs.has("__preview") and not Text._strings.en.has("__preview_0"), "closing the preview restores the game's language")
	de.select_group("1")
	de.select("1C")
	de.delete_dialog()
	check(de.nodes.has("1C") and de.where_of("1C").begins_with("Started by the game"), "a dialog the game starts (1C, the boss) can't be deleted")
	check(de.next_id("2") == "2F" and de.next_id("1") == "1F", "new dialogs never take a letter the game uses")
	var cf := FileAccess.open(DialogEditor.EDIT_PATH, FileAccess.WRITE)
	cf.store_string(JSON.stringify({"saved_characters": {"Luna": {"name": {"sk": "Luna", "en": "Luna", "pt": "Luna"}, "portrait": "portrait_luna"}}}))
	cf.close()
	Text._ready()
	check(Text.characters.has("Luna") and SpriteArt.is_sprite("portrait_luna"), "characters made in this browser are known at start-up (avatar slot in the lab)")
	DirAccess.remove_absolute(DialogEditor.EDIT_PATH)
	Text._ready()
	check(Text.dialogs["2C"].parts.size() == 1 and not Text.characters.has("Luna"), "the game's dialogs back as built")
	dev._show("shortcuts")
	await frames(2)
	_finished = true


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


## Stands the player on the highest platform under a seed, a little to its left.
func _stand_under(pf: Platformer, e: LevelData.Ent, dx := 50.0) -> void:
	var best: LevelData.Plat = null
	for pl in pf.level.platforms:
		if pl.base_y > e.base_y and pl.x <= e.base_x + 20 and pl.x + pl.w >= e.base_x - 20 and (best == null or pl.base_y < best.base_y):
			best = pl
	pf.p.x = e.base_x - dx
	pf.p.y = (best.base_y if best else 7 * LevelData.ROW_H_H) - pf.p.height
	pf.p.vy = 0
	pf.camera_x = clampf(pf.p.x - 400, 0, pf.level_w - 1066)


## Removes uploads and background edits made by the tests.
func _clean_bg_state() -> void:
	if FileAccess.file_exists(LevelEditor.BG_AUTOSAVE):
		DirAccess.remove_absolute(LevelEditor.BG_AUTOSAVE)
	if DirAccess.dir_exists_absolute(AssetBrowser.UPLOAD_DIR):
		for f in DirAccess.get_files_at(AssetBrowser.UPLOAD_DIR):
			DirAccess.remove_absolute(AssetBrowser.UPLOAD_DIR + f)
		DirAccess.remove_absolute(AssetBrowser.UPLOAD_DIR)
	Game.custom_backgrounds = {}


func _go_trigger(pf: Platformer, kind: String) -> void:
	for e in pf.level.entities:
		if e.type == "trigger" and e.trigger_type == kind:
			if pf.level.horizontal:
				# Column triggers: drop into the column from above the ground.
				pf.p.x = e.x + e.w / 2 - pf.p.width / 2
				pf.p.y = 240
				pf.camera_x = clampf(pf.p.x - 400, 0, pf.level_w - 1066)
			else:
				pf.p.x = 500
				pf.p.y = e.y + 60
				pf.camera_y = e.y - 200
			pf.p.vy = 0
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
