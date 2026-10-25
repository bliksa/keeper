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
	var meadow := await until(func(): return main.state == "platformer" and Game.level == 2 and main.platformer != null, 8)
	check(meadow, "the meadow (level 2) starts after the boss")

	step("level 2 – the meadow")
	await finish_dialog("meadow_start")
	pf = main.platformer
	check(pf.is_meadow() and pf.level.horizontal and pf.level_w > 5000, "a horizontal level with the camera following")
	await seconds(0.5)
	check(pf.p.is_grounded, "stands on the meadow ground")
	_teleport_to_entity(pf, "iron")
	await frames(3)
	check(Game.water == Game.WATER_PER_DROP, "a water drop fills the vessel")
	Game.water = 20
	# The river carries her back to the last ground she stood on.
	# The river: wading is slow and pushes back, no harm done.
	var bank := Vector2(pf.p.x, pf.p.y)
	pf.p.x = bank.x + 1200
	pf.p.y = pf.level.water_top + 10
	pf.p.vy = 0
	await seconds(0.3)
	check(pf.in_water and pf.p.is_grounded and Game.water == 20, "she wades in the river, no water is lost")
	var wx := pf.p.x
	Input.action_press("move_right")
	await seconds(1.0)
	Input.action_release("move_right")
	var waded := pf.p.x - wx
	check(waded > 20 and waded < 160, "wading is slow (%.0f px/s)" % waded)
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
	await finish_dialog("gate_locked")
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
	await finish_dialog("meadow_end")
	var summit := await until(func(): return main.state == "platformer" and Game.level == 3 and main.platformer != null, 6)
	check(summit, "the summit (level 3) starts after the meadow")

	step("level 3 – the summit")
	await finish_dialog("garden_start")
	pf = main.platformer
	check(pf.is_summit() and pf.p.y > pf.level_h - 500, "starts at the bottom of the summit")
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
	# Combo: landing higher and higher.
	var ups: Array = pf.level.platforms.filter(func(pl): return pl.kind == "rock")
	ups.sort_custom(func(a, b): return a.base_y > b.base_y)
	pf.combo = 0
	pf.last_landing_y = pf.level_h
	var landed := 0
	var prev_y: float = pf.level_h
	for pl in ups:
		if landed >= 3:
			break
		if pl.base_y > prev_y - 100:
			continue
		prev_y = pl.base_y
		landed += 1
		pf.p.x = pl.x + 4
		pf.p.y = pl.base_y - pf.p.height - 6
		pf.p.vy = 2
		pf.p.is_grounded = false
		pf.p.was_grounded = false
		await frames(4)
	check(pf.combo == 3, "three landings higher up build a combo of 3")
	pf.p.y = pf.p.y + 400
	await frames(3)
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
	await finish_dialog("wave_start")
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
	check(retried, "try again restarts the climb with the wave")
	pf = main.platformer
	await _go_trigger(pf, "summit")
	await frames(3)
	check(pf.wave.won and pf.summit_timer > 0, "reaching the summit stops the wave")
	await finish_dialog("garden_end")
	await frames(5)
	check(main.state == "title" and Game.level == 1, "back to the title after the summit")

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
	for i in [1, 2, 3]:
		var path := LevelEditor.AUTOSAVE if i == 1 else LevelEditor.AUTOSAVE_FMT % i
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
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
	ed.select_level(2)
	await frames(2)
	check(ed.horizontal() and ed.cols() > 100 and ed.rows.size() == 10 and ed._tool_info.has("Y") and ed._tool_info.has("G"), "editor switches to the horizontal meadow and has its tools")
	ed.select_level(3)
	await frames(2)
	check(not ed.horizontal() and ed.rows.size() == Game.level_rows(3).size() and ed._tool_info.has("@") and ed._tool_info.has("E"), "editor switches to the summit and has its tools")
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
