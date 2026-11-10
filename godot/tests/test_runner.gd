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


## A button's text (+ icon, margins) fits its intended width. Not against b.size: a Control
## grows to its minimum size, so that check could never fail. get_minimum_size() is what the
## content needs (font, icon, stylebox margins), custom_minimum_size the width it was given.
func _button_fits(b: Button) -> bool:
	var w := b.custom_minimum_size.x
	if w <= 0.0:
		return true
	return b.get_minimum_size().x <= w + 0.5 and b.size.x <= w + 0.5


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
	# The test keeps its own save file (never the player's) and starts without one, in English.
	Game.save_path = "user://test_save.json"
	DirAccess.remove_absolute(Game.save_path)
	Game.load_save()
	Text.language = "en"
	step("the save: language, sound, the furthest place")
	check(Game.save.is_empty() and not Game.has_progress() and Game.reached_chapter() == 0 and not Game.is_finished(), "no save: nothing to continue")
	check(Game.pick_language("", "", "sk-SK") == "sk" and Game.pick_language("", "", "pt-BR") == "pt" and Game.pick_language("", "", "de") == "en" and Game.pick_language("", "", "cs") == "sk" and Game.pick_language("", "", "") == "en", "the first run takes the browser's language (sk / pt, else en)")
	check(Game.pick_language("", "pt", "sk") == "pt" and Game.pick_language("SK", "pt", "en") == "sk" and Game.pick_language("xx", "pt", "en") == "pt", "the saved language wins over the browser's, ?lang= over both")
	Text.choose_language("sk")
	check(FileAccess.file_exists(Game.save_path), "choosing a language writes the save")
	# A restart: the autoloads read the file again.
	Game.save = {}
	Text.language = "en"
	Game.load_save()
	Text.language = Game.start_language()
	check(Text.language == "sk" and Game.save.get("language") == "sk", "the language persists across a restart (the save is read back)")
	check(Game.progress(1, 2, 7) and not Game.progress(1, 1, 30) and Game.progress(2, 0) and not Game.progress(1, 4, 9) and Game.saved_chapter() == 2 and Game.saved_checkpoint() == 0, "only a further place replaces the saved one")
	Game.save = {}
	Game.load_save()
	check(Game.has_progress() and Game.saved_chapter() == 2 and Game.reached_chapter() == 2 and Game.save.get("language") == "sk", "the furthest place is read back too")
	Game.mark_finished()
	check(Game.is_finished() and not Game.has_progress() and Game.reached_chapter() == Game.CHAPTERS, "a finished game: nothing to continue, every phase open")
	DirAccess.remove_absolute(Game.save_path)
	Game.load_save()
	Text.language = "en"

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
	# The jackpot climb (level 3 of the game, id 5): up from P at the bottom to E at the top.
	var rows5: PackedStringArray = Game.level_rows(Game.CLIMB_ID)
	var L5 := LevelData.build(rows5)
	check(rows5.size() > 30 and L5.has_spawn() and L5.spawn.y > L5.height() - 400, "the jackpot climb has %d rows and a spawn at the bottom" % rows5.size())
	var c5 := {}
	var top_y := L5.height()
	for e in L5.entities:
		var k5: String = e.trigger_type if e.type == "trigger" else e.type
		c5[k5] = int(c5.get(k5, 0)) + 1
		if e.trigger_type == "summit":
			top_y = minf(top_y, e.y)
	check(top_y < 600, "the climb's top (E) is near the top")
	check(c5.get("spring", 0) > 0 and c5.get("heart", 0) > 100 and c5.get("bell", 0) > 3 and c5.get("joker", 0) > 3 and c5.get("jackpot", 0) == 3, "the climb has springs, plenty of hearts, some bells and jokers and 3 jackpot rows")
	# The wheel of the cycle (mg11): one row, between the 1st and 2nd jackpot rows.
	var jys: Array = L5.entities.filter(func(e): return e.trigger_type == "jackpot").map(func(e): return e.y)
	jys.sort()
	var wheels: Array = L5.entities.filter(func(e): return e.trigger_type == "mg11")
	check(wheels.size() == 1 and wheels[0].y > jys[1] and wheels[0].y < jys[2] and not L5.entities.any(func(e): return e.type == "chip" or e.type == "slot"), "the climb's wheel (Z, mg11) is there once, between the 1st and 2nd jackpot rows")
	check(LevelData.parse_text(LevelData.to_text(rows5), LevelData.CLIMB_COLS) == rows5, "climb text round-trips")
	check(["!", "$", ":", "?", "0", "Z"].all(func(ch): return LevelData.PALETTE.has(ch)), "the climb's legend has labels")
	# The PMS maze (level 4 of the game, id 6): a spawn, three comfort items, one door, walls.
	var rows6: PackedStringArray = Game.level_rows(Game.PMS_ID)
	var L6 := LevelData.build(rows6)
	var c6 := {}
	for e in L6.entities:
		c6[e.type] = int(c6.get(e.type, 0)) + 1
	check(rows6.size() >= 20 and rows6[0].length() == 25 and L6.has_spawn() and L6.spawn.y < 400, "the PMS maze: %d rows of 25, the spawn at the top" % rows6.size())
	check(c6.get("comfort", 0) == 3 and c6.get("door", 0) == 1 and L6.walls.size() > 10, "the maze has 3 comfort items, a door and %d wall blocks" % L6.walls.size())
	var tiers6: Array = L6.entities.filter(func(e): return e.type == "comfort").map(func(e): return e.tier)
	check(tiers6 == [0, 1, 2], "the items are tea, hot-water bottle, blanket by order %s" % str(tiers6))
	var reach6 := PmsMaze.check(rows6)
	check(reach6.ok, "every item and the door can be reached with single / double jumps, no soft lock (unreachable %s, traps %d)" % [str(reach6.unreachable), reach6.traps.size()])
	var blocked := rows6.duplicate()
	blocked[rows6.size() - 2] = "W".repeat(25)
	check(not PmsMaze.check(blocked).ok, "the reachability check notices a walled-in door")
	check(c6.get("lantern", 0) == 1 and reach6.lantern.x >= 0 and not reach6.unreachable.has(reach6.lantern), "the dark maze has one lantern and the check reaches it %s" % str(reach6.lantern))
	var lant_shut := rows6.duplicate()
	var lnr: int = reach6.lantern.x - 1
	var lnc: int = reach6.lantern.y
	lant_shut[lnr] = lant_shut[lnr].substr(0, lnc - 1) + "W+W" + lant_shut[lnr].substr(lnc + 2)
	lant_shut[lnr - 1] = lant_shut[lnr - 1].substr(0, lnc - 1) + "WWW" + lant_shut[lnr - 1].substr(lnc + 2)
	check(not PmsMaze.check(lant_shut).ok, "the check includes the lantern (a walled-in lantern fails)")
	# The lantern lies in the spawn corridor: the same row as P, a walk along the floor (no
	# jump, no gap, no branching on the way), a few cells away, before anything else to find.
	var sp_r := -1
	var sp_c := -1
	for r in rows6.size():
		if rows6[r].find("P") >= 0:
			sp_r = r
			sp_c = rows6[r].find("P")
	var ln_c: int = rows6[sp_r].find("+") if sp_r >= 0 else -1
	var walk_ok := sp_r >= 0 and ln_c >= 0
	if walk_ok:
		for c in range(mini(sp_c, ln_c), maxi(sp_c, ln_c) + 1):
			walk_ok = walk_ok and rows6[sp_r][c] in [".", " ", "P", "+"] and rows6[sp_r + 1][c] == "W"
	check(walk_ok and absi(ln_c - sp_c) >= 6 and absi(ln_c - sp_c) <= 14, "the lantern lies in the spawn corridor, a plain walk from P (%d cells along the floor)" % absi(ln_c - sp_c))
	check(walk_ok and rows6[sp_r][ln_c + signi(ln_c - sp_c) * 2] == "W", "… at the corridor's end (the wall is right behind it)")
	check(LevelData.parse_text(LevelData.to_text(rows6)) == rows6 and Game.LEVELS.keys().find(Game.PMS_ID) == Game.LEVELS.keys().find(Game.CLIMB_ID) + 1, "maze text round-trips; it comes after the climb in the level list")

	step("pipes layouts are solvable")
	_check_pipe_layouts()

	step("boot → title")
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE # as under the real root
	add_child(main)
	await frames(5)
	check(main.state == "boot", "starts on boot screen")
	var boot_long := []
	var lang_b: String = Text.language
	for lang in Text.LANGUAGES:
		Text.language = lang
		await frames(1)
		var bs := main._menu as BootScreen
		for b in [bs._full, bs._start]:
			if not _button_fits(b):
				boot_long.append("%s/%s %s %s %d" % [lang, b.text, b.get_minimum_size(), b.size, b.get_theme_font_size("font_size")])
	Text.language = lang_b
	check(boot_long.is_empty(), "the boot screen's buttons fit their text with KeeperDyslexic in sk / en / pt %s" % str(boot_long))
	var boot0 := main._menu as BootScreen
	var lang_lbl := []
	for lang in Text.LANGUAGES:
		Text.language = lang
		await frames(1)
		lang_lbl.append(boot0._subs.text)
		if boot0._subs.get_minimum_size().x > 148:
			lang_lbl.append("too wide")
	check(lang_lbl == ["JAZYK", "LANGUAGE", "IDIOMA"], "the flags' label says what they do: Language (not Subtitles) %s" % str(lang_lbl))
	(boot0._flags["pt"] as TextureButton).pressed.emit()
	check(Text.language == "pt" and Game.save.get("language") == "pt", "a flag switches the language and saves it")
	(boot0._flags["en"] as TextureButton).pressed.emit()
	Game.save_set("muted", true)
	main._menu.started.emit()
	await frames(5)
	check(main.state == "title", "title screen")
	check(Audio.muted, "the saved sound switch is applied after the boot screen")
	var ts0 := main._menu as TitleScreen
	ts0._mute_btn.pressed.emit()
	check(not Audio.muted and Game.save.get("muted") == false, "the title's sound switch is saved")
	check(not ts0.can_continue() and not ts0._continue_btn.visible and ts0._start_btn.text == Text.t("BTN_START") and not ts0._chapters[0].visible and not ts0._finished.visible, "no save: just Start and Credits (no Continue, no phases)")
	var en_pills := [ts0._mute_btn.text, ts0._mode_btn.text]
	Text.language = "sk"
	await frames(1)
	check(ts0._mute_btn.text == "SO ZVUKOM" and ts0._mode_btn.text == "KLÁVESNICA" and en_pills == ["SOUND ON", "KEYBOARD"] and ts0._mute_btn.tooltip_text == "Vypnúť zvuk", "the title's sound / control pills are translated")
	Text.language = "en"
	await frames(1)

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
	# The jackpot climb's dialogs (3*) talk on the board: they must fit its text area too,
	# in both control modes, and have no buttons (nothing to press on the board).
	var board_long := []
	var board_smallest := 99
	var mode0: String = Game.control_mode
	for lang in ["en", "sk", "pt"]:
		Text.language = lang
		for mode in ["keyboard", "gamepad"]:
			Game.control_mode = mode
			for id in Text.dialogs:
				if not DialogEditor.on_board(id):
					continue
				var parts: Array = Text.dialogs[id].get("parts", [])
				for i in parts.size():
					var sz := Platformer.board_text_size(Platformer.board_line(parts[i].get("text", "")))
					board_smallest = mini(board_smallest, sz if sz > 0 else 99)
					if sz < 0:
						board_long.append("%s/%s:%s#%d" % [lang, mode, id, i])
	Text.language = lang0
	Game.control_mode = mode0
	check(board_long.is_empty(), "every board dialog (3A..3E) fits the board's text area (smallest size %d) %s" % [board_smallest, str(board_long)])
	check(["3A", "3B", "3C", "3D", "3E", "3F"].all(func(id): return Text.dialogs.has(id) and not Text.dialogs[id].has("buttons")), "the climb's dialogs have no buttons")

	step("game font")
	# KeeperDyslexic is the default font of every player-facing text: Text.font(_bold)
	# (HUD, minigames, menus), the board, a plain label (the project theme); the developer
	# mode stays in Comfortaa (its own theme).
	var plain := Label.new()
	main.add_child(plain)
	var plain_font: Font = plain.get_theme_font("font")
	plain.queue_free()
	check(Text.font == Text.font_dialog and Text.font_bold == Text.font_dialog_bold and str(ProjectSettings.get_setting("gui/theme/custom_font")).ends_with("KeeperDyslexic-Regular.otf") and plain_font != null and plain_font.resource_path.ends_with("KeeperDyslexic-Regular.otf"), "KeeperDyslexic is the game's default font (Text.font / font_bold, the theme: a plain label)")
	var dev_b := UiKit.dev_button("x", Vector2(80, 30))
	var game_b := UiKit.button("x", Vector2(80, 30))
	check((Text.font_dev as FontVariation).base_font.resource_path.ends_with("Comfortaa.ttf") and UiKit.dev_theme().default_font == Text.font_dev and dev_b.get_theme_font("font") == Text.font_dev_bold and game_b.get_theme_font("font") == Text.font_bold, "the developer mode keeps Comfortaa (dev_button / dev_label / dev_theme), game buttons use KeeperDyslexic")
	dev_b.free()
	game_b.free()
	var ts := main._menu as TitleScreen
	var menu_long := []
	var lang_t: String = Text.language
	var mode_t: String = Game.control_mode
	for lang in Text.LANGUAGES:
		Text.language = lang
		for mode in ["keyboard", "gamepad"]:
			Game.control_mode = mode
			await frames(1)
			for muted in [false, true]:
				Audio.muted = muted
				ts._refresh()
				for b in [ts._start_btn, ts._credits_btn, ts._mute_btn, ts._mode_btn] + main._pause._buttons:
					if not _button_fits(b):
						menu_long.append("%s/%s" % [lang, b.text])
			Audio.muted = false
			# With a save: Continue / New game and the phases' label.
			Game.save["chapter"] = 1
			ts._refresh()
			for b in [ts._continue_btn, ts._start_btn]:
				if not _button_fits(b):
					menu_long.append("%s/%s" % [lang, b.text])
			if ts._phases_lbl.get_minimum_size().x > 256 or Text.font_bold.get_string_size(Text.t("TITLE_FINISHED"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > 230:
				menu_long.append("%s/phases" % lang)
			Game.save.erase("chapter")
			ts._refresh()
			for pr in EndScreen.fit_problems():
				menu_long.append("%s/end/%s" % [lang, pr])
	Text.language = lang_t
	Game.control_mode = mode_t
	await frames(1)
	check(menu_long.is_empty(), "the title's (with and without a save), the pause menu's and the end screen's texts fit in sk / en / pt %s" % str(menu_long))
	var mg_long := []
	for lang in Text.LANGUAGES:
		Text.language = lang
		for probs in [IronPlateGame.fit_problems(), SignalsGame.fit_problems(), CatchGame.fit_problems(), MemoryGame.fit_problems(),
				PairsGame.fit_problems(), PricesGame.fit_problems(), RhythmGame.fit_problems(), FertilityWheel.fit_problems()]:
			for pr in probs:
				mg_long.append("%s/%s" % [lang, pr])
	Text.language = lang_t
	check(mg_long.is_empty(), "every minigame text fits its card / panel / line with KeeperDyslexic in sk / en / pt %s" % str(mg_long))

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
	check(Game.saved_chapter() == 1 and Game.saved_checkpoint() == 1, "the save: the cave is reached")
	var cave_note := await until(func(): return main.platformer != null and PhaseBoard.showing(main.platformer.phase_note), 4)
	check(cave_note and main.platformer.phase_note.key == "CAVE_PHASE_NEW" and node_box().node_id() == "", "the cave opens with its phase on the board (Phase: menstruation), before 1A")
	var phase_bad: Array = []
	var phase_lang := Text.language
	for lang in ["sk", "en", "pt"]:
		Text.language = lang
		phase_bad.append_array(PhaseBoard.fit_problems())
		for pair in [["0B3", ["menštruáci", "menstruation", "menstruação"]], ["CAVE_PHASE_NEW", ["menštruáci", "menstruation", "menstruação"]], ["1B1", ["maternica", "uterus", "útero"]], ["RUN_PHASE_NEW", ["folikulárna", "follicular", "folicular"]], ["2A2", ["folikul", "follicle", "folículo"]], ["2E1", ["folikul", "follicle", "folículo"]], ["PMS_PHASE_NEW", ["luteálna", "luteal", "lútea"]]]:
			var words: Array = pair[1]
			if not words.any(func(w): return Text.plain(Text.t(str(pair[0]))).to_lower().contains(w)):
				phase_bad.append("%s/%s" % [lang, pair[0]])
	Text.language = phase_lang
	check(phase_bad.is_empty(), "every phase's announcement fits; menstruation, the cramp and the follicle are named in sk / en / pt %s" % str(phase_bad))
	check(Text.voice_file("0B3") == "" and Text.voice_file("1B1") == "" and Text.voice_file("0B4") != "" and Text.voice_file("1C2") == "" and Text.voice_file("1C3") == "DIA_046.wav" and Text.voice_file("DIA_034") == "" and Text.voice_file("DIA_043") == "" and Text.voice_file("DIA_033") == "DIA_033.wav", "rewritten (Slovak) lines don't play their old recording, also the DIA_ ones; the others still do")
	await finish_dialog("1A")
	var pf: Platformer = main.platformer
	check(pf != null and pf.active, "platformer active")

	step("cave physics")
	await seconds(1.0)
	check(pf.p.is_grounded, "player stands on a platform")
	check(pf.view_zoom == 1.0 and pf._world.scale == Vector2.ONE and pf.level.cols == 25 and pf.level_w == Platformer.W, "the cave is not zoomed: 25 columns, one screen wide")
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

	step("the cramp lesson 1B can't be skipped")
	var cave_rows := Game.level_rows(1)
	var b_rows := 0
	var b_open := false
	for row in cave_rows:
		if row.contains("b"):
			b_rows += 1
			for ch in row:
				if ch != "b" and ch != "=":
					b_open = true
	check(b_rows == 1 and not b_open, "the row with the cramp lesson's letter is closed but for the letter itself (no way past it)")
	pf.p.x = Platformer.W / 2 - 15
	for bi in cave_rows.size():
		if cave_rows[bi].contains("b"):
			pf.p.y = bi * LevelData.ROW_H - 100
	pf.p.vy = 0
	pf.camera_y = pf.p.y - 200
	await finish_dialog("1B")
	check(Game.cramp_taught, "falling through the gap plays 1B (the breath-attack lesson)")
	await frames(3)

	step("cramp grabs, breathing frees")
	Game.iron = 10
	var enemy := _teleport_to_entity(pf, "enemy")
	await frames(3)
	check(pf.p.held_by_cramp == enemy.id, "held by a cramp")
	if not pf.dialog_open:
		check(pf.hud.hint_lines() == ["HINT_BREATH_RHYTHM"], "held: the hint under the pill shows the breathing rhythm %s" % str(pf.hud.hint_lines()))
	await _do_recharge()
	check(pf.p.held_by_cramp == -1, "breathing cycle freed the player")
	check(pf.p.breath_charges == 3, "breath charges refilled")
	await frames(2)
	check(pf.hud.hint_lines() == ["HINT_BREATH_ATTACK"], "breath charged: the hint says the breath attacks %s" % str(pf.hud.hint_lines()))
	_check_labels(pf.hud.labels, ["HUD_LBL_IRON", "HUD_LBL_BREATH"], "cave")
	pf.p.breath_charges = 0
	await frames(2)
	check(pf.hud.hint_lines() == ["HINT_BREATH_CHARGE"], "breath used up: the hint says to charge it %s" % str(pf.hud.hint_lines()))
	pf.p.breath_charges = 3
	for hk in ["HINT_BREATH_ATTACK", "HINT_BREATH_CHARGE", "HINT_BREATH_RHYTHM", "HINT_RUN_FOCUS", "HINT_RUN_DOUBLE", "HINT_CLIMB_SUPER_JUMP", "HINT_CLIMB_TRIPLE", "HINT_CLIMB_MAGNET", "HINT_CLIMB_ROCKET", "HINT_CLIMB_HEART_BOOST", "HINT_CLIMB_FUEL", "HINT_CLIMB_FUEL_BURN"]:
		check(Text.LANGUAGES.all(func(lang): return Text._strings.get(lang, {}).has(hk)), "ability hint %s exists in sk / en / pt" % hk)
	# One hint format: [KEY] caps, the *action* in yellow, plain text between.
	var ps := AbilityHints.parse("[SHIFT] + [🔴] to *double jump*")
	check(ps.size() == 5 and ps[0].get("cap", "") == "SHIFT" and ps[1].get("text", "") == " + " and ps[2].has("icon") and ps[3].get("text", "") == " to " and ps[4].get("action", "") == "double jump", "the hint parser: caps / glyph cap / text / yellow action %s" % str(ps))
	check(AbilityHints.parse("a [b c *d") == [{"text": "a [b c *d"}], "the hint parser keeps unclosed mark-up as text")
	var mode_was := Game.control_mode
	var bad_hints: Array = []
	for lang in Text.LANGUAGES:
		for hk in Text._strings.get(lang, {}):
			if not String(hk).begins_with("HINT_") or not (String(hk).begins_with("HINT_BREATH_") or String(hk).begins_with("HINT_RUN_") or String(hk).begins_with("HINT_CLIMB_") or String(hk).begins_with("HINT_PMS_")):
				continue
			for mode in ["keyboard", "gamepad"]:
				Game.control_mode = mode
				var segs := AbilityHints.parse(Text._filter_mode(str(Text._strings[lang][hk])))
				var caps := segs.filter(func(sg): return sg.has("cap")).size()
				var acts := segs.filter(func(sg): return sg.has("action")).size()
				# Passive power-ups / states (no key to press) have no cap.
				var passive: bool = hk in ["HINT_CLIMB_MAGNET", "HINT_CLIMB_ROCKET", "HINT_CLIMB_FUEL_BURN", "HINT_PMS_RESTING"]
				# Leftover mark-up or a pad glyph outside a cap would draw literally / as tofu.
				var stray := segs.any(func(sg):
					if not sg.has("text"):
						return false
					var t: String = sg["text"]
					if t.contains("[") or t.contains("]") or t.contains("*"):
						return true
					for g in Text._ICONS:
						if t.contains(g):
							return true
					return false)
				if stray or acts != 1 or (caps == 0 and not passive) or AbilityHints.line_width(Text._filter_mode(str(Text._strings[lang][hk]))) > 420:
					bad_hints.append("%s/%s/%s (%d px)" % [lang, hk, mode, int(AbilityHints.line_width(Text._filter_mode(str(Text._strings[lang][hk]))))])
	Game.control_mode = mode_was
	check(bad_hints.is_empty(), "every ability hint parses as [key] caps + one *action* in all languages and both control modes %s" % str(bad_hints))
	_hud_layout()

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
	check(Game.saved_chapter() == 1 and Game.saved_checkpoint() == 2 and int(Game.save.get("iron", -1)) == Game.iron, "the save: the cave's checkpoint 2 with her iron")

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
	await frames(2)
	var bt0: float = main.platformer.boss.defeated_timer
	await frames(10)
	check(not main.platformer.exit_fall and main.runner == null and main.platformer.boss.defeated_timer > bt0, "the boss's dialog plays in the arena (Kyra stays, the nuts form their ring)")
	await finish_dialog("1D")
	var falls := await until(func(): return main.platformer != null and main.platformer.exit_fall, 7)
	check(falls, "after the dialog the floor is gone and Kyra falls")
	var hop_y: float = main.platformer.p.y
	var hop_dx: float = absf(main.platformer.p.x + main.platformer.p.width / 2 - 533)
	await frames(6)
	check(main.platformer != null and main.platformer.p.y < hop_y and absf(main.platformer.p.x + main.platformer.p.width / 2 - 533) <= hop_dx, "she hops up and over towards the middle first")
	var under := await until(func(): return main.runner != null, 4)
	check(under and main.runner._over_cave and main.runner.modulate.a < 1.0, "the forest fades in over the arena below her")
	await frames(5)
	var run_ok := await until(func(): return main.state == "runner" and main.runner != null, 8)
	check(run_ok and Game.level == 2, "the forest run (level 2) starts after the boss")
	check(Game.saved_chapter() == 2 and Game.saved_checkpoint() == 0, "the save: the forest run is reached")

	step("level 2 – the forest run")
	var rn0: ForestRunner = main.runner
	check(rn0.intro > 0 and not rn0._landed and node_box().node_id() == "", "level start: she is still falling in, no dialog")
	var rn_landed := await until(func(): return rn0._landed, 6)
	check(rn_landed and rn0.py == 0 and rn0._handoff_at >= ForestRunner.INTRO_FADE - 0.1 and rn0._handoff_h > 0, "Kyra falls on from where she was in the arena and lands (back to us)")
	var played := await until(func(): return rn0.intro <= 0, 4)
	await frames(3)
	check(played and node_box().node_id() == "" and PhaseBoard.showing(rn0.phase_note) and rn0.phase_note.key == "RUN_PHASE_NEW" and rn0.phase_note.sub == "RUN_PHASE_SUB", "then the board announces the phase (New phase: follicular)")
	var hold_d := rn0.dist
	await frames(20)
	check(rn0.dist == hold_d and rn0.loop_note == 0.0 and rn0.hint_lines().is_empty(), "the run waits while the phase is announced")
	var intro_2a := await until(func(): return node_box().node_id() == "2A", PhaseBoard.READ_TIME + 2)
	var a_parts: Array = Text.dialogs["2A"].parts
	check(intro_2a and rn0.phase_note.is_empty() and a_parts.size() <= 3 and a_parts.any(func(pt): return pt.speaker == "Iskra"), "then the short 2A: Iskra introduces herself and the goal (%d parts)" % a_parts.size())
	check(rn0.dist == hold_d, "the run still waits during 2A")
	await finish_dialog("2A")
	await frames(3)
	check(node_box().node_id() == "" and rn0.loop_note > 0, "then the run starts, the controls shown briefly")
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
	check(rn.lane == 0.5 and absf(rn.px - 0.5 * ForestRunner.LANE) < 0.05, "→ moves her one path to the right (four paths)")
	_key(KEY_LEFT, true)
	await frames(2)
	_key(KEY_LEFT, false)
	await seconds(0.3)
	check(rn.lane == -0.5, "← back one path")
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
	check(rn.lane == 0.5, "a stick tilt moves one path, not two")
	check(ForestRunner.PATHS.size() == 4 and Array(rn.rows).any(func(r): return r.length() > 4 and r[4] in ["H", "D", "+", "R"]), "four paths, the outer ones used")
	rn.lane = -0.5
	rn.px = -0.5 * ForestRunner.LANE
	rn.build_course()
	check(rn.stages.size() == 4 and rn.objects.filter(func(o): return o.kind == "sun").size() == ForestRunner.SUN_TOTAL, "the map has 4 stages and 12 sun pieces")
	check(not rn.objects.any(func(o): return o.kind == "bird" and o.stage < 2) and not rn.objects.any(func(o): return o.kind == "seed"), "no flying notifications before stage 3, no seeds")
	check(not rn.objects.any(func(o): return o.kind == "bird" and o.stage == 0), "stage 1 has no crows (only jumping and water)")
	var roots: Array = rn.objects.filter(func(o): return o.kind == "root" and o.lane == -9)
	var root0: Dictionary = roots[0]
	rn.drops = 4
	var w_before := rn.drops
	rn.jump_to(root0.z - 0.4)
	rn.py = 0
	rn.vy = 0
	await frames(3)
	check(rn.bump_t > 0, "running into a root bounces her off")
	check(rn.invuln > 2.9, "after a hit she blinks: nothing can hit her for 3 s")
	check(rn.drops <= w_before - ForestRunner.HIT_DROPS + 0.01, "a hit costs a drop")
	await seconds(0.45)
	check(rn.dist < root0.z - 4 and not root0.hit, "the path rolls back and the root waits for her again")
	await frames(2)
	var d_stand := rn.dist
	await seconds(0.25)
	check(rn.recover_t > 0 and absf(rn.dist - d_stand) < 0.01, "after the roll-back she stands a moment")
	await seconds(1.0)
	check(rn.recover_t <= 0 and rn.dist > d_stand + 2, "then she runs again")
	rn.jump_to(root0.z - 0.4)
	rn.invuln = 1.0
	rn.py = 0
	rn.vy = 0
	await frames(3)
	check(rn.bump_t <= 0 and not root0.hit, "while she blinks she runs through an obstacle")
	rn.jump_to(root0.z - 3.0)
	rn.drops = 4
	rn.jump()
	check(rn.drops == 4 and rn.vy > 0, "a jump is free")
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
	rn.drops = 4
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
	rn.meter.reset(4.0, 0.4)
	rn.py = 0
	rn.jump_to(rdrop.z - 0.3)
	await frames(3)
	check(rdrop.taken and rn.reserve > 0.5 and rn.flyers.any(func(f): return f.kind == "drop" and f.into == "reserve"), "a water drop with a full magazine goes into the reserve (it flies up to the reserve badge)")
	# Slowed time: the world runs slower while the water drains.
	rn.objects.clear()
	rn.meter.reset(4.0, 0.0)
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
	check(rn.slow == false and slowed < normal * 0.6 and rn.drops < 4 and rn.drops > 3.0, "holding focus slows time (%.1f m vs %.1f m) and burns a drop a second" % [slowed, normal])
	rn.meter.reset(0.0, 0.0)
	Input.action_press("slow_time")
	await frames(3)
	check(not rn.slow, "no slow-down without water")
	Input.action_release("slow_time")
	# The ability hints under the water pill: only what the drops allow right now.
	rn.drops = 0
	await frames(2)
	check(rn.hint_lines().is_empty(), "no drops: no ability hints %s" % str(rn.hint_lines()))
	rn.drops = 1
	await frames(2)
	check(rn.hint_lines() == ["HINT_RUN_FOCUS"], "one drop: the focus hint %s" % str(rn.hint_lines()))
	_check_labels(rn.hud_labels, ["HUD_LBL_SUN", "HUD_LBL_WATER"], "forest run")
	rn.drops = 4
	await frames(2)
	check(rn.hint_lines() == ["HINT_RUN_FOCUS", "HINT_RUN_DOUBLE"], "two drops or more: focus and the double jump %s" % str(rn.hint_lines()))
	# The water meter is a magazine and a reserve (MeterModel, as the climb's hearts): a
	# double jump costs two drops from the magazine, pickups fill the magazine first, then
	# the reserve, and the reserve reloads the magazine.
	rn.objects.clear()
	rn.py = 0
	rn.vy = 0
	rn.jumps = 2
	rn.meter.reset(4.0, 0.0)
	rn.jump()
	rn.jump()
	check(rn.jumps == 0 and absf(rn.drops - 2) < 0.01, "a double jump costs two drops")
	check(absf(ForestRunner.DROP_WATER - Platformer.HEART_FILL) < 0.01, "a path drop is the same share of a drop as a heart of a heart")
	rn.meter.reset(2.0, 0.0)
	rn._add_water(ForestRunner.DROP_WATER)
	check(absf(rn.drops - 2.2) < 0.01 and rn.reserve == 0.0, "a drop fills the magazine first (%.2f in it, %.2f in reserve)" % [rn.drops, rn.reserve])
	for k in 10:
		rn._add_water(ForestRunner.DROP_WATER)
	check(absf(rn.drops - 4) < 0.01 and absf(rn.reserve - 0.2) < 0.01, "a full magazine sends the rest into the reserve (%.2f, %.2f)" % [rn.drops, rn.reserve])
	rn.meter.fill(1000.0)
	check(rn.drops == 4 and rn.reserve == rn.meter.reserve_max, "the reserve holds %d more, then the meter is full" % int(rn.meter.reserve_max))
	_meter_model_checks()
	# The run reloads its magazine while it plays (the drops fly into the pill).
	rn.meter.reset(0.0, 2.0)
	await frames(3)
	check(rn.meter.reloading and not rn.meter.flyers.is_empty() and rn.drops == 0.0, "an empty magazine: the run reloads it at once, a drop flies from the reserve")
	await seconds(1.4)
	check(absf(rn.drops - 2) < 0.01 and rn.reserve < 0.01 and not rn.meter.reloading, "… the reserve's two drops are in the magazine (%.2f, %.2f)" % [rn.drops, rn.reserve])
	rn.meter.reset(0.0, 0.0)
	await frames(5)
	check(rn.drops == 0 and rn.reserve == 0 and rn.meter.flyers.is_empty(), "nothing in reserve: no reload, the drops stay empty until water is collected")
	# Focus held with an empty magazine and a full reserve: the reload from empty runs to
	# the end (focus doesn't cancel it), so slowed time comes on once and stays on.
	rn.objects.clear()
	rn.meter.reset(0.0, 4.0)
	Input.action_press("slow_time")
	var toggles := 0
	var was_slow := rn.slow
	for i in 150:
		await frames(1)
		if rn.slow != was_slow:
			toggles += 1
			was_slow = rn.slow
	Input.action_release("slow_time")
	var held_mag := rn.drops
	await seconds(1.5)
	check(toggles <= 1 and was_slow and held_mag > 0.5, "focus held while an empty magazine reloads: slowed time comes on once and stays (%d toggles, %.2f drops)" % [toggles, held_mag])
	check(rn.reserve < 0.01 and rn.meter.flyers.is_empty() and not rn.meter.reloading and absf(rn.drops - held_mag) < 0.01 and held_mag > 1.5, "… the whole reserve went into the magazine, what focus didn't burn stays (%.2f)" % rn.drops)
	# A drop taken while another drop's flash shows doesn't cut that flash short.
	rn.meter.reset(2.0, 0.0)
	rn.meter.slot_flash = MeterModel.FLASH
	rn.meter.slot_flash_i = 1
	var into_w := rn._add_water(ForestRunner.DROP_WATER)
	check(into_w == "mag" and rn.meter.slot_flash == MeterModel.FLASH and rn.meter.slot_flash_i == 1 and rn.meter.last_slot == 2, "a new drop leaves the last one's flash alone (its own comes when it lands, slot %d)" % rn.meter.last_slot)
	rn.meter.reset(0.0, 0.0)
	# Side traps: placed ones, and random ones in the last stage.
	rn.build_course()
	rn.reserve = 0
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
	rn.build_course()
	rn.objects = rn.objects.filter(func(o): return o.kind in ["sun", "dialog"])
	# The sun: a stage repeats while its pieces are missing.
	rn.jump_to(rn.stages[0].start + 1)
	check(rn.sun == 0 and rn.stage == 0, "the sun starts empty")
	rn.jump_to(rn.stages[0].end - 0.2)
	await frames(3)
	var first_piece: Array = rn.objects.filter(func(o): return o.kind == "sun" and o.stage == 0)
	check(rn.loops == 1 and rn.stage == 0 and absf(rn.dist - rn.stages[0].start) < 2 and first_piece[0].z > rn.dist and node_box().node_id() == "", "the stage repeats seamlessly ahead of her while its pieces are missing (no message)")
	check(rn.trees.any(func(t): return t.z > rn.stages[0].end), "the forest grows on with it")
	for n in ForestRunner.SUN_TOTAL:
		var pieces: Array = rn.objects.filter(func(o): return o.kind == "sun" and not o.taken)
		var pc: Dictionary = pieces[0]
		rn.lane = pc.lane
		rn.px = pc.lane * ForestRunner.LANE
		rn.py = 0
		# The last piece is caught mid-jump: she must come down for the end.
		var hold_up := func():
			if not pc.taken:
				rn.py = 1.0
				rn.vy = 0.0
		if n == ForestRunner.SUN_TOTAL - 1:
			get_tree().process_frame.connect(hold_up)
		rn.jump_to(pc.z - 0.3)
		var got := await until(func(): return pc.taken, 3)
		if get_tree().process_frame.is_connected(hold_up):
			get_tree().process_frame.disconnect(hold_up)
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
	var gliding := await until(func(): return rn.end_t > 0.3, 5)
	var mid_sun: Array = rn.sun_screen()
	check(gliding and rn.done and node_box().node_id() == "" and (mid_sun[0] as Vector2).distance_to(ForestRunner.SUN_HUD) > 60, "the 12th piece: the run stops and the whole sun glides from the HUD towards the middle")
	var fin := await until(func(): return node_box().node_id() == "2E", 5)
	var end_sun: Array = rn.sun_screen()
	check(fin and rn.sun == ForestRunner.SUN_TOTAL and (end_sun[0] as Vector2).distance_to(ForestRunner.END_SUN_POS) < 1 and float(end_sun[1]) > 90, "the sun is in the middle, big, when 2E opens")
	check(absf(rn.py) < 0.05 and rn.vy == 0.0, "the last piece was caught mid-jump: she has come down onto the path when 2E opens (py %.2f)" % rn.py)
	var fade_max := [0.0]
	var watch_fade := func():
		fade_max[0] = maxf(fade_max[0], main._fade.modulate.a)
	get_tree().process_frame.connect(watch_fade)
	await finish_dialog("2E")
	var cpf: Platformer = main.platformer
	check(main.state == "platformer" and Game.level == Game.CLIMB_ID and cpf != null and cpf.is_climb() and cpf.phase_showing() and cpf.phase_note.key == "CLIMB_PHASE_NEW", "2E closes into the climb at once: the board announces the new phase")
	var csun: Array = cpf.sun_screen()
	check((csun[0] as Vector2).distance_to(ForestRunner.END_SUN_POS) < 25 and absf(float(csun[1]) - ForestRunner.END_SUN_R) < 4, "the run's sun goes on as the climb's sun, where it was (%s, r %.0f)" % [str(csun[0]), float(csun[1])])
	check(is_instance_valid(rn) and rn.is_inside_tree() and cpf.modulate.a < 0.5 and cpf.hud.modulate.a == 1.0, "the forest stays under the climb crossfading in; the board is there at once")
	await seconds(0.3)
	var y_before := cpf.p.y
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	await frames(10)
	check(cpf.p.y < y_before - 20 and cpf.phase_showing(), "a jump during the announcement moves her up right away")
	await seconds(main.CLIMB_IN)
	check(not is_instance_valid(rn) and cpf.modulate.a == 1.0 and cpf.camera_y > 0, "the forest is gone after the crossfade")
	var ticker_x: float = cpf.ticker[0].x if not cpf.ticker.is_empty() else 0.0
	await frames(5)
	check(cpf.phase_showing() and (cpf.ticker.is_empty() or cpf.ticker[0].x == ticker_x), "the ticker waits for the announcement")
	await until(func(): return not cpf.phase_showing(), 4)
	await seconds(0.3)
	check(not cpf.phase_showing() and not cpf.ticker.is_empty() and cpf.ticker[0].x < ticker_x, "after the announcement the ticker runs")
	get_tree().process_frame.disconnect(watch_fade)
	check(fade_max[0] == 0.0, "no fade to black from the forest run into the climb (max %.2f)" % fade_max[0])
	var climb: bool = main.state == "platformer" and Game.level == Game.CLIMB_ID and main.platformer == cpf
	check(climb, "the jackpot climb (level 3) starts after the forest run")
	check(not node_box().is_open() and not main.platformer.dialog_open and not main.platformer.board_talking(), "the climb starts without a dialog (no 3A at the start, no dialog box)")
	check(Text.t("CLIMB_PHASE_NEW") != "CLIMB_PHASE_NEW" and Platformer.board_text_size(Text.plain(Text.t("CLIMB_PHASE_SUB"))) > 0, "the phase announcement has its texts")

	step("forest run – a repeat is laid out behind what she sees")
	var lmap: Array = []
	for i in 130:
		var row := "......"
		if i == 5 or i == 8 or i == 100:
			row = "..+..."
		elif i in [10, 20, 40, 55, 62, 70, 80, 110]:
			row = ".R...."
		elif i == 60:
			row = "A....."
		lmap.append(row)
	lmap.reverse()
	var lr := ForestRunner.new()
	lr.rows = PackedStringArray(lmap)
	main.add_child(lr)
	await frames(1)
	# She found the first piece and missed the second.
	lr.objects.filter(func(o): return o.kind == "sun")[0].taken = true
	lr.sun = 1
	lr.sun_shown = 1
	lr.jump_to(lr.stages[0].end - ForestRunner.VIEW + 4.0)
	var in_view := func() -> Array:
		var zs: Array = []
		for o in lr.objects:
			if o.kind != "dialog" and o.z > lr.dist and o.z < lr.dist + ForestRunner.VIEW:
				zs.append(o.z)
		zs.sort()
		return zs
	var seen: Array = in_view.call()
	var old_end: float = lr.stages[0].end
	lr._check_loop()
	var after: Array = in_view.call()
	check(lr.loops == 1 and seen.size() >= 2 and seen.all(func(z): return after.has(z)), "a missed piece queues the repeat: nothing she can see moves or vanishes")
	check(lr.objects.any(func(o): return o.kind == "root" and o.stage == 0 and o.z > lr.dist + ForestRunner.VIEW) and lr.stages[1].start > lr.dist + ForestRunner.VIEW, "the repeat (and the next stage after it) lie beyond the view")
	lr.dist = old_end + 0.5
	lr._enter_loop()
	var missed: Array = lr.objects.filter(func(o): return o.kind == "sun" and o.stage == 0 and not o.taken)
	check(lr.stage == 0 and absf(lr.stages[0].start - old_end) < 0.01 and missed.size() == 1 and missed[0].z > lr.dist + 10, "past the old end the stage runs on, the missed piece lies ahead in the repeat")
	check(absf(lr.stage_progress()) < 0.05, "the stage ring starts again only here")
	lr.bump()
	var back: Array = lr.objects.filter(func(o): return o.kind == "sun" and o.stage == 0 and not o.taken)
	check(lr.sun == 0 and back.size() == 2 and back.all(func(o): return o.z >= lr.stages[0].start), "a slice lost in the repeat goes back into the repeat (never behind the stage start)")
	check(lr.lost_flyers.size() == 1 and lr.sun_lost > 1.0, "a lost slice tumbles out of her and blinks in the sun")
	await seconds(ForestRunner.LOST_FLY + 0.1)
	check(lr.lost_flyers.is_empty(), "then it is gone")
	lr.queue_free()

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
	er.bump()
	check(er.sun == 1 and er.objects.filter(func(o): return o.kind == "sun" and not o.taken and o.stage == 0).size() == 1 and er.sun_lost > 0, "a hit costs a slice: the piece goes back onto the track")
	er.bump_t = 0
	er.recover_t = 0
	take_next.call()
	er.meter.reset(1.0, 0.0)
	er.jumps = 1
	er.vy = 0
	er.jump()
	check(er.vy <= 0 and er.jumps == 1 and er.water_short > 0 and er.short_for == "double", "without two drops there's no double jump")
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

	step("level 3 – the jackpot climb")
	# It kept running during the steps above: start it again from the bottom.
	await main._start_climb(1, false)
	await frames(2)
	pf = main.platformer
	check(pf.is_climb() and pf.is_up() and not pf.is_summit() and pf.p.y > pf.level_h - 500, "the jackpot climb starts at the bottom")
	check(Game.saved_chapter() == 3 and Game.saved_checkpoint() >= 1, "the save: the jackpot climb is reached")
	check(not pf.wave.active and pf.camera_y > pf.level_h - 1200, "no LH wave; the camera starts at the bottom")
	await seconds(0.5)
	check(pf.p.is_grounded, "stands on the climb's floor")
	var climb_events: Array = []
	pf.trigger.connect(func(n): climb_events.append(n))
	check(not pf.on_board and pf.meter.mag == 0.0 and pf.meter.reserve == 0.0 and pf.ticker.size() > 0 and pf.hud.visible, "the board's ticker runs, she starts just above the board with an empty heart meter")
	check(not ("climb_win" in pf) and not ("climb_mult" in pf) and not Text._strings.get("en", {}).has("CLIMB_WIN"), "no score in the climb (no win counter, no multiplier)")
	# The sun of the forest run shines in the climb's sky (opaque), rising as she climbs.
	var sun0: Array = pf.sun_screen()
	check(absf((sun0[0] as Vector2).x - Platformer.W / 2) < 1 and (sun0[0] as Vector2).y > 150, "the sun is at the top centre of the sky (%s)" % str(sun0[0]))
	check(pf.board_y() > pf.p.y + pf.p.height and pf.board_y() - (pf.p.y + pf.p.height) < 120, "the board's top edge is right below her feet")
	check(not node_box().is_open() and not pf.board_talking(), "no dialog at the start of the climb")
	# Wider and zoomed out: 36 columns, drawn at CLIMB_ZOOM so the whole width fits the screen.
	check(absf(pf.view_zoom - Platformer.CLIMB_ZOOM) < 0.001 and absf(pf.view_zoom - 0.7) < 0.02 and pf._world.scale.is_equal_approx(Vector2.ONE * pf.view_zoom) and pf._bg.scale.is_equal_approx(pf._world.scale) and pf._player_layer.scale.is_equal_approx(pf._world.scale), "the climb is drawn zoomed out (%.3f): world, background and player layers" % pf.view_zoom)
	check(pf.level.cols == LevelData.CLIMB_COLS and LevelData.CLIMB_COLS == 36 and Game.level_cols(Game.CLIMB_ID) == 36 and absf(pf.level_w - 36 * LevelData.CELL_W) < 0.01, "the climb's map has 36 columns (%.0f px wide)" % pf.level_w)
	check(absf(pf.view_w() - pf.level_w) < 1.0 and absf(pf.level_w * pf.view_zoom - Platformer.W) < 1.0, "the level's side walls are the screen's edges")
	check(absf((pf.board_y() - pf.camera_y) * pf.view_zoom - (Platformer.H - Platformer.BOARD_H)) < 0.5 and pf.hud.scale == Vector2.ONE, "the board stays at the bottom of the screen (screen space, not zoomed)")
	# No dialog letters and no minigames in the climb's map.
	check(not pf.level.entities.any(func(e): return e.type == "trigger" and (e.trigger_type == "dialog" or (e.trigger_type.begins_with("mg") and e.trigger_type != "mg11") or e.trigger_type in ["end", "wave", "gate"])), "the climb's map has no dialog letters and no minigame triggers but the wheel")
	# A letter painted in the editor anyway talks on the board, never in the dialog box;
	# a painted minigame does nothing.
	var painted := LevelData.Ent.new()
	painted.type = "trigger"
	painted.trigger_type = "dialog"
	painted.dialog_id = "c"
	pf._hit_trigger(painted)
	var painted_mg := LevelData.Ent.new()
	painted_mg.type = "trigger"
	painted_mg.trigger_type = "mg5"
	pf._hit_trigger(painted_mg)
	await frames(3)
	check(pf.board_talking("3C") and not node_box().is_open() and not pf.dialog_open and main.state == "platformer" and main.minigame == null, "a painted letter plays its dialog on the board; a painted minigame doesn't open")
	_board_flush(pf)
	var base: LevelData.Plat = _climb_plat(pf, pf.level_h - 300)
	_climb_put(pf, base.x + base.w / 2, base.base_y)
	await frames(2)
	_climb_put(pf, 500, pf.p.y + pf.p.height - 11 * LevelData.ROW_H)
	await frames(2)
	var sun_hi: Array = pf.sun_screen()
	check((sun_hi[0] as Vector2).y < (sun0[0] as Vector2).y - 2, "higher up the sun has risen (screen y %.0f → %.0f)" % [(sun0[0] as Vector2).y, (sun_hi[0] as Vector2).y])
	pf.camera_y = 0
	var sun_top: Array = pf.sun_screen()
	pf.camera_y = pf.p.y + pf.p.height - 300
	check(absf((sun_top[0] as Vector2).y - Platformer.SUN_TOP_Y) < 1 and (sun_top[0] as Vector2).y > 0, "at the top the sun is high in the sky, still on screen")
	# Caught: the board rises past her feet → she stands on it, sits, x1, a calm line.
	pf.rise_wait = 0.0
	pf.rise = 2.0
	pf.camera_y = pf.p.y + pf.p.height - (Platformer.H - Platformer.BOARD_H) / pf.view_zoom - 40
	pf.p.vy = 0
	await frames(3)
	check(pf.on_board and pf.p.is_grounded and absf(pf.p.y + pf.p.height - pf.board_y()) < 2, "the rising board catches her: she stands on its top edge")
	var rest := Text.plain(Text.t("CLIMB_REST"))
	check(pf.ticker_queue.has(rest) or pf.ticker.any(func(sg): return sg.text == rest), "caught: the board says take a breath")
	check(pf.rise <= Platformer.RISE_START + 0.05, "caught: the board slows back to its starting speed")
	await seconds(0.4)
	var cy := pf.camera_y
	check(pf.p.is_sitting and not pf.p.is_dead, "on the board she sits down (no death)")
	await seconds(0.5)
	check(pf.camera_y < cy - 5 and pf.on_board and pf.p.is_sitting and absf(pf.p.y + pf.p.height - pf.board_y()) < 1.5, "the board keeps rising while she sits on it and carries her up (%.0f px)" % (cy - pf.camera_y))
	# Frame spike: even far below the board she ends up on it.
	pf.p.y = pf.board_y() + 200
	pf.p.vy = 14
	await frames(1)
	check(pf.p.y + pf.p.height <= pf.board_y() + 0.5, "she never falls below the board")
	await frames(3)
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	check(pf.p.vy < 0 and not pf.on_board and not pf.p.is_sitting, "a jump takes her off the board any time")
	# Off the board (on a platform above it) the board just goes on rising, no wait.
	var hold: LevelData.Plat = _climb_plat(pf, pf.p.y - 400)
	_climb_put(pf, hold.x + hold.w / 2, hold.base_y)
	pf.camera_y = hold.base_y - 400
	await frames(2)
	cy = pf.camera_y
	await seconds(0.4)
	check(not pf.on_board and pf.rise_wait <= 0 and pf.camera_y < cy - 5 and pf.rise >= Platformer.RISE_START, "on a platform above the board it keeps rising (the camera climbs on its own)")
	# Following her up never lifts the board past the platform she jumped from, so a
	# missed jump (or the way down from a boost) lands on a platform, not the board.
	var from: LevelData.Plat = _climb_plat(pf, pf.p.y - 600)
	_climb_put(pf, from.x + from.w / 2, from.base_y)
	await frames(3)
	pf.rise_wait = 30.0
	var stand_y := pf.p.y + pf.p.height
	pf.p.vy = Platformer.JUMP_FORCE
	pf.p.is_grounded = false
	var peaked := await until(func(): return pf.p.vy > 0, 3)
	check(peaked and pf.board_y() >= stand_y - 8 and not pf.on_board, "a plain jump: the camera follows but the board stays below the platform she jumped from")
	_climb_put(pf, from.x + from.w / 2, from.base_y)
	await frames(3)
	pf.p.vy = -Platformer.SPRING_FORCE
	pf.p.is_grounded = false
	peaked = await until(func(): return pf.p.vy > 0, 4)
	var gap := pf.board_y() - (pf.p.y + pf.p.height)
	check(peaked and gap > 250 and pf.p.y > pf.camera_y + 60, "a boost: at her highest the board is %d px below her (room for the rows under the peak), she stays on screen" % int(gap))
	pf.rise_wait = 0.0
	# A dialog on the board doesn't stop anything: the board keeps rising, landing on it
	# is a catch (x1), there is no dialog box and nothing to press.
	_climb_put(pf, 500, from.base_y - 60)
	pf.camera_y = from.base_y - 60 - (Platformer.H - Platformer.BOARD_H) / pf.view_zoom + 30
	var talked: Array = []
	pf.board_dialog_done.connect(func(id): talked.append(id))
	pf.board_dialog("3C")
	var caught_in_dialog := await until(func(): return pf.on_board, 3)
	check(caught_in_dialog and pf.board_talking("3C") and not node_box().is_open() and not pf.dialog_open, "caught while the board talks: no dialog box")
	cy = pf.camera_y
	await seconds(0.4)
	check(pf.camera_y < cy - 5 and pf.on_board and pf.board_talking("3C"), "the board keeps rising while its dialog talks")
	check(pf.board_talk.speaker == "Estrogenka" and pf.board_talk.dur >= Platformer.BOARD_READ_MIN and pf.board_talk.dur <= Platformer.BOARD_READ_MAX and pf.ticker.size() > 0, "the board shows the line for its reading time (%.1f s)" % pf.board_talk.dur)
	for part in 4:
		if not pf.board_talking("3C"):
			break
		pf.board_talk.t = pf.board_talk.dur - 0.01
		await frames(4)
	check(talked == ["3C"] and not pf.board_talking(), "after its reading time the board dialog ends (board_dialog_done) and the ticker comes back")
	await frames(3)
	# A spring launches her.
	var spring: LevelData.Ent = _climb_ent(pf, "spring")
	_climb_put(pf, spring.x + spring.w / 2, spring.y + spring.h)
	await frames(2)
	check(pf.p.vy < -15 and pf.boost_t > 0, "a spring launches her (vy %.1f)" % pf.p.vy)
	await frames(20)
	check(pf.p.y < spring.y - 250, "the spring sends her several rows up")
	await _climb_hearts(pf)
	# The bag: every power-up comes up.
	pf._power_bag.clear()
	var drawn: Array = []
	for i in 4:
		drawn.append(pf._next_power())
	drawn.sort()
	var all_powers: Array = Platformer.POWERS.duplicate()
	all_powers.sort()
	check(drawn == all_powers, "the slot bag holds every power-up once")
	# A joker spins the reels top-left and always pays a power-up; the first one in a
	# climb pays the super jump (3A also introduces the jokers).
	pf.climb_power.clear()
	pf.powers_explained.clear()
	pf._power_bag.clear()
	pf.hearts = 0
	var slot: LevelData.Ent = _climb_ent(pf, "joker")
	_climb_put(pf, slot.x + slot.w / 2, slot.y + slot.h + 25)
	await frames(2)
	check(slot.collected and not pf.slot_spin.is_empty() and not pf.slot_spin.paid, "a joker spins the reels top-left")
	await seconds(Platformer.SLOT_SPIN + 0.2)
	check(pf.slot_spin.get("paid", false) and pf.climb_power.size() > 0, "the reels stop and pay a power-up (%s)" % pf.slot_spin.get("power", "?"))
	check(pf.board_talking(Platformer.POWER_DIALOG.get(pf.slot_spin.get("power", ""), "?")) and not node_box().is_open(), "the first power-up from a joker is explained on the board")
	check(pf.slot_spin.get("power", "") == "super_jump" and pf.board_talking("3A"), "the first joker of a climb pays the super jump (3A introduces the jokers)")
	check(pf.slot_spin.get("kind", "") == "joker" and pf.spin_rest == ["joker", "joker", "joker"] and pf.ticker_queue.has(Text.plain(Text.t("CLIMB_PU_SUPER_JUMP"))), "the joker's spin settles on three jokers; the power-up's name goes to the ticker")
	check(PlatformerHud.SPINNER.size.y == PlatformerHud.HEART_PILL.y and PlatformerHud.SPINNER.size.y == ForestRunner.WATER_HUD.size.y and PlatformerHud.SPINNER.position.y == 16, "the spinner is a pill as high as the heart meter / the water pill, top-left")
	var floor_txt := false
	for lang in Text.LANGUAGES:
		floor_txt = floor_txt or Text._strings.get(lang, {}).has("CLIMB_FLOOR")
	check(not floor_txt and not FileAccess.get_file_as_string("res://scripts/ui/platformer_hud.gd").contains("CLIMB_FLOOR"), "the climb has no floor counter (no CLIMB_FLOOR text)")
	var en_s: Dictionary = Text._strings.get("en", {})
	check(str(en_s.get("3A1", "")).to_lower().contains("joker") and str(en_s.get("3C1", "")).to_lower().contains("heart") and not str(en_s.get("3C1", "")).to_lower().contains("chip"), "3A introduces the jokers, 3C talks about hearts")
	# Each power-up's first grant in a climb explains it on the board (3A..3D), once.
	_board_flush(pf)
	pf.powers_explained.clear()
	# Each power-up works.
	var stand: LevelData.Plat = _climb_plat(pf, pf.level_h - 1200)
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	pf.climb_power.clear()
	pf.hearts = 0
	await frames(3)
	var jf := pf._jump_force()
	pf.grant_power("super_jump")
	check(pf._jump_force() < jf * 1.25 and pf.banner.get("text", "") == Text.plain(Text.t("CLIMB_PU_SUPER_JUMP")), "super jump: jumps 30 % higher, a banner")
	check(pf.board_talk.get("id", "") == "3A" and not node_box().is_open() and not pf.dialog_open, "the first super jump: 3A talks on the board (no dialog box, no buttons)")
	var sj_left: float = pf.climb_power.get("super_jump", 0.0)
	pf.hearts = 0
	await frames(2)
	check(pf.hud.hint_lines() == ["HINT_CLIMB_SUPER_JUMP"], "the super jump's hint shows top-right while it lasts %s" % str(pf.hud.hint_lines()))
	await frames(30)
	check(pf.board_talking("3A") and absf(float(pf.climb_power.get("super_jump", 0.0)) - sj_left) < 0.001, "the super jump doesn't run out while 3A explains it")
	pf.climb_power.clear()
	pf.hearts = 0
	await frames(2)
	check(pf.hud.hint_lines().is_empty(), "expired: no power-up hint")
	pf.grant_power("triple")
	pf.hearts = 0
	await frames(3)
	check(pf.hud.hint_lines() == ["HINT_CLIMB_TRIPLE"], "the triple jump's hint %s" % str(pf.hud.hint_lines()))
	check(pf._max_jumps() == 3 and pf.p.jumps_left == 3, "triple jump: three jumps")
	check(pf.board_talking("3B") and pf.board_queue.has("3B"), "the first triple jump: 3B waits for 3A on the board")
	for i in 3:
		_key(KEY_SPACE, true)
		await frames(2)
		_key(KEY_SPACE, false)
		await frames(5)
	check(pf.p.jumps_left == 0 and pf.p.vy < 0, "three jumps in a row")
	# A full triple-jump stack (each jump at the top of the last, with the super jump) stays
	# below the top of the visible area: the camera follows.
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	pf.rise_wait = 30.0
	pf.grant_power("super_jump")
	pf.grant_power("triple")
	await frames(3)
	var top_gap := 9999.0
	for i in 3:
		_key(KEY_SPACE, true)
		await frames(1)
		_key(KEY_SPACE, false)
		var guard := 0
		while pf.p.vy < 0 and guard < 200:
			top_gap = minf(top_gap, (pf.p.y - pf.camera_y) * pf.view_zoom)
			await frames(1)
			guard += 1
	check(top_gap > 20 and pf.p.jumps_left == 0, "a triple-jump stack stays below the top of the screen (%.0f px at the closest)" % top_gap)
	# The side walls are the level's edges: she runs into them, at the screen's edge.
	_climb_put(pf, pf.level_w - 60, stand.base_y)
	pf.p.y = stand.base_y - 400
	Input.action_press("move_right")
	await frames(40)
	Input.action_release("move_right")
	check(absf(pf.p.x - (pf.level_w - pf.p.width)) < 0.5 and (pf.p.x + pf.p.width - pf.camera_x) * pf.view_zoom <= Platformer.W + 0.5 and (pf.p.x + pf.p.width - pf.camera_x) * pf.view_zoom > Platformer.W - 2, "the right wall is the level's edge, at the screen's right edge")
	pf.rise_wait = 0.0
	pf.climb_power.clear()
	await frames(60)
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.grant_power("magnet")
	var pull: LevelData.Ent = _climb_ent(pf, "heart")
	pull.x = pf.p.x + 200
	pull.y = pf.p.y
	check(pf.board_talking("3C"), "the first magnet: 3C on the board")
	var magnet_pulled := await until(func(): return pull.collected, 2)
	check(magnet_pulled, "the magnet pulls a heart in")
	pf.climb_power.clear()
	var ry0 := pf.p.y
	pf.grant_power("rocket")
	check(pf.p.vy < -25 and pf.board_talking("3D"), "the rocket fires her up; 3D on the board")
	await frames(40)
	check(ry0 - pf.p.y > 500, "the rocket lifts her %d px" % int(ry0 - pf.p.y))
	var said_powers: Array = []
	pf.board_dialog_done.connect(func(id): said_powers.append(id))
	_board_flush(pf)
	check(said_powers == ["3A", "3B", "3C", "3D"], "the power-ups' dialogs play one after another %s" % str(said_powers))
	pf.grant_power("super_jump")
	pf.grant_power("magnet")
	check(not pf.board_talking() and not node_box().is_open(), "a second super jump / magnet isn't explained again")
	pf.climb_power.clear()
	# Other triggers painted in the editor (a cramp's dialog, a minigame) do nothing here.
	for tt in ["first_cramp", "mg5", "wave"]:
		var stray := LevelData.Ent.new()
		stray.type = "trigger"
		stray.trigger_type = tt
		stray.x = pf.p.x
		stray.y = pf.p.y
		pf._hit_trigger(stray)
	await frames(3)
	check(not climb_events.has("first_cramp") and not climb_events.has("mg5") and not node_box().is_open() and not pf.dialog_open and not pf.wave.active and main.state == "platformer", "a painted cramp / minigame / wave trigger is ignored in the climb")
	# Hazards (if the editor places any) never end the run.
	var iron0 := Game.iron
	pf._hurt(pf.p.x)
	check(Game.iron == iron0 and not pf.p.is_dead, "a hit only knocks her back in the climb")
	await frames(30)
	pf.p.hit_timer = 0
	check(not climb_events.has("game_over") and not climb_events.has("game_over_boss"), "no game over in the climb")
	# A jackpot row: the JACKPOT (banner, coins; no score).
	var jp0 := pf.jackpots
	var jrows: Array = pf.level.entities.filter(func(e): return e.type == "trigger" and e.trigger_type == "jackpot")
	jrows.sort_custom(func(a, b): return a.y > b.y)
	await _go_trigger(pf, "jackpot")
	check(Game.checkpoint >= 2 and Game.level == Game.CLIMB_ID and main.state == "platformer", "a jackpot row is a checkpoint (%d)" % Game.checkpoint)
	check(pf.jackpots > jp0 and pf.banner.get("text", "") == Text.plain(Text.t("CLIMB_JACKPOT")) and pf.particles.any(func(q): return q.type == "coin"), "a jackpot row: the JACKPOT banner with a coin shower")
	pf._place_at_checkpoint(3)
	check(absf(pf.p.y + pf.p.height - jrows[1].y) < 400 and jrows[0].collected and jrows[1].collected, "checkpoint 3 = the 2nd jackpot row from the bottom")
	_board_flush(pf)
	await _climb_wheel(pf)
	await _go_trigger(pf, "climb_top")
	await frames(3)
	check(pf.climb_won and pf.summit_timer > 0, "the top of the climb (E) is reached")
	var end_talk := await until(func(): return pf.board_talking("3E"), 4)
	check(end_talk and not node_box().is_open() and not pf.dialog_open and main.state == "platformer", "at the top 3E talks on the board (no dialog box, no buttons)")
	var end_speakers: Array = []
	var guard5 := 0
	while is_instance_valid(pf) and main.platformer == pf and pf.prerod_t < 0 and guard5 < 20:
		guard5 += 1
		if pf.board_talking():
			if not end_speakers.has(pf.board_talk.speaker):
				end_speakers.append(pf.board_talk.speaker)
			pf.board_talk.t = pf.board_talk.dur
		await frames(3)
	check(end_speakers.has("Kyra") and end_speakers.has("Estrogenka"), "3E's parts show their speakers on the board %s" % str(end_speakers))

	step("the transformation (the climb's end → the PMS maze)")
	check(pf.prerod_t >= 0 and pf.hold_input and main.platformer == pf, "after 3E the transformation starts (no control)")
	check(Platformer.prerod_fit_problems().is_empty(), "the transformation's captions fit (current language)")
	var cap_long: Array = []
	var lang_c: String = Text.language
	for lang in ["en", "sk", "pt"]:
		Text.language = lang
		cap_long.append_array(Platformer.prerod_fit_problems())
	Text.language = lang_c
	check(cap_long.is_empty(), "the transformation's captions fit in sk / en / pt %s" % str(cap_long))
	var tick0: float = pf.ticker[0].x if not pf.ticker.is_empty() else 0.0
	var lut_sun0: Array = pf.prerod_body()
	var phases: Array = []
	var pr_fade_max := 0.0
	var pr_seen := {}
	var kyra0 := pf.p.center()
	var guard_t := 0
	while is_instance_valid(pf) and main.platformer == pf and guard_t < 60 * 14:
		guard_t += 1
		var ph := pf.prerod_phase()
		if phases.is_empty() or phases.back() != ph:
			phases.append(ph)
		pr_fade_max = maxf(pr_fade_max, main._fade.modulate.a)
		if ph == "focus" and pf.prerod_t > 1.0 and not pr_seen.has("ticker"):
			pr_seen["ticker"] = pf.ticker.is_empty() or is_equal_approx(pf.ticker[0].x, tick0)
		if ph == "egg" and pf.prerod_t > Platformer.PREROD_T_EGG + 0.3 and not pr_seen.has("egg_open"):
			var b: Array = pf.prerod_body()
			pr_seen["egg_open"] = pf.prerod_open() > 0.5 and pf.view_flip < 0.01 and (b[0] as Vector2).distance_to(Platformer.LUTEUM_C) < 2.0 and float(b[1]) > float(lut_sun0[1])
			pr_seen["dusk"] = pf._world.modulate.b > pf._world.modulate.g and pf._world.modulate.r < 0.9 and pf.hud.modulate.a < 0.05
		if pf.egg_released and not pr_seen.has("egg_out"):
			pr_seen["egg_out"] = ph == "egg" and float(pf.prerod_egg()[1]) > 0 and pf.prerod_luteum() == 0.0
			pr_seen["egg_cap"] = pf.prerod_caption()[0] == "PREROD_EGG"
		if ph == "luteum" and pf.prerod_t > Platformer.PREROD_T_LUTEUM + 1.3 and not pr_seen.has("luteum"):
			pr_seen["luteum"] = pf.prerod_luteum() > 0.9 and pf.prerod_open() < 0.05 and float(pf.prerod_egg()[1]) == 0.0 and pf.prerod_caption()[0] == "PREROD_LUTEUM" and pf.view_flip < 0.01
		if ph == "pull" and pf.prerod_t > Platformer.PREROD_T_PULL + Platformer.PREROD_PULL * 0.5 and not pr_seen.has("pull"):
			var mid := Vector2(pf.camera_x, pf.camera_y) + Platformer.LUTEUM_C / pf.view_zoom
			pr_seen["pull"] = pf.p.center().distance_to(mid) < kyra0.distance_to(mid) and pf._pull_scale() < 0.8 and pf.view_flip > 0.3 and pf.view_flip < 0.7 and absf(pf._world.rotation - PI / 2) < 0.5
		if ph == "iris" and not pr_seen.has("iris"):
			pr_seen["iris"] = pf.view_flip >= 1.0 and absf(pf._world.rotation - PI) < 0.05 and absf(pf._bg.rotation - PI) < 0.05 and absf(pf._player_layer.rotation - PI) < 0.05 and pf._player_layer.modulate.a < 0.05
		await frames(1)
	check(phases == ["focus", "egg", "luteum", "pull", "iris", "done"] or phases == ["focus", "egg", "luteum", "pull", "iris"], "the transformation's phases in order %s" % str(phases))
	check(pr_seen.get("ticker", false), "the board's ticker stops")
	check(pr_seen.get("egg_open", false), "the sun (the follicle) comes to the middle, grows and opens along its slices")
	check(pr_seen.get("dusk", false), "the casino's gold drains to dusk and the HUD is gone")
	check(pr_seen.get("egg_out", false) and pr_seen.get("egg_cap", false), "ovulation: the egg is released and floats away (caption PREROD_EGG)")
	check(pr_seen.get("luteum", false), "the opened sun closes into the yellow body (caption PREROD_LUTEUM)")
	check(pr_seen.get("pull", false), "Kyra is pulled into the opening (shrinking) while the view turns")
	check(pr_seen.get("iris", false), "the whole view (background, world, Kyra) has turned 180° when the opening fills the screen")
	check(pr_fade_max == 0.0, "no fade to black during the transformation (%.2f)" % pr_fade_max)
	var short_caps: Array = []
	var lang_cap := Text.language
	for lang in ["sk", "en", "pt"]:
		Text.language = lang
		for sp: Array in Platformer.prerod_caption_spans():
			var need := Platformer.CAPTION_READ * Platformer.board_read_time(Text.plain(Text.t(str(sp[0]))))
			if float(sp[2]) - float(sp[1]) < need:
				short_caps.append("%s/%s %.2f < %.2f" % [lang, sp[0], float(sp[2]) - float(sp[1]), need])
	Text.language = lang_cap
	check(short_caps.is_empty(), "the transformation's captions stay on long enough to read %s" % str(short_caps))
	var maze_on: bool = main.platformer != null and main.platformer != pf and main.platformer.is_pms()
	check(maze_on and Game.level == Game.PMS_ID and main.state == "platformer", "the PMS maze (level 6) comes in")
	var pms: Platformer = main.platformer
	check(pms.view_flip == 1.0 and pms.warm > 0.9 and pms.warm_t >= 0 and pms._world.modulate.b < 0.7, "the maze starts upside down inside the yellow body (warm amber)")
	check(pms._dark.visible and pms.light_radius() > 1000, "the arrival: the warm light still fills the screen (%d px)" % pms.light_radius())
	await frames(2)
	check(not is_instance_valid(pf), "the climb is gone")
	var warm_fades := await until(func(): return pms.warm < 0.5, 4)
	check(warm_fades and main._fade.modulate.a == 0.0, "the warm tint fades to the maze's dusk")
	var pms_note := await until(func(): return PhaseBoard.showing(pms.phase_note), 4)
	check(pms_note and pms.phase_note.key == "PMS_PHASE_NEW" and pms.phase_speaker == "Progesteronka" and node_box().node_id() == "" and pms.hold_input, "the maze announces its phase on the board (New phase: luteal), before 4A; she stands still meanwhile")
	await finish_dialog("4A")
	check(Text.dialogs["4A"].parts.any(func(pt): return pt.speaker == "Progesteronka"), "4A: Progesterónka greets her inside the corpus luteum")
	var cooled := await until(func(): return pms.warm == 0.0 and pms.warm_t < 0, 6)
	check(cooled and pms._world.modulate == Color.WHITE, "the maze has its dusky colours after the warm start")
	check(absf(pms.light_radius() - pms.light_r) < 1.0 and pms.light_r < Platformer.LIGHT_R + 1, "the warm light shrank to her light in the dark (%d px)" % pms.light_radius())
	var no_firefly := true
	var lang_ff := Text.language
	for lang in ["sk", "en", "pt"]:
		Text.language = lang
		for key in ["4A1", "4A2", "4A3", "4A4", "4A5", "4A6", "4A7", "4G1", "4H1"]:
			var line := Text.t(key).to_lower()
			for word in ["firefly", "svetlušk", "pirilampo"]:
				no_firefly = no_firefly and line.find(word) < 0
	Text.language = lang_ff
	check(no_firefly and Text.dialogs["4A"].parts.any(func(pt): return pt.text == "4A6"), "4A points her to the lantern at the corridor's end; no firefly in the maze's talk")
	check(pms.modulate.a == 1.0 and not pms.hold_input and pms.p.is_grounded, "Kyra settled onto her platform; control is back after 4A")

	step("level 4 – the PMS maze")
	await _pms_play(pms)
	await _end_and_continue()
	main._dev_action("checkpoint6", 2)
	var door_dev := await until(func(): return main.state == "platformer" and main.platformer != null and main.platformer.is_pms() and main.platformer.pms_items == 3, 8)
	await frames(3)
	check(door_dev and main.platformer.pms_items == 3 and main.platformer.door_open > 0 and not node_box().is_open(), "the developer menu opens the maze with the door open")
	main._quit_to_title()
	await frames(3)
	main._dev_action("pms_transform", 0)
	var dev_top := await until(func(): return main.platformer != null and main.platformer.is_climb() and main.platformer.climb_won, 8)
	check(dev_top, "the developer menu's Transformation starts at the climb's top")
	var tpf: Platformer = main.platformer
	check(not tpf._dark.visible, "the darkness is only in the maze (not in the climb)")
	var g6 := 0
	while is_instance_valid(tpf) and main.platformer == tpf and tpf.prerod_t < Platformer.PREROD_T_LUTEUM and g6 < 400:
		g6 += 1
		if tpf.board_talking():
			tpf.board_talk.t = tpf.board_talk.dur
		await frames(2)
	check(is_instance_valid(tpf) and tpf.prerod_phase() == "luteum", "the developer Transformation plays the sequence (%s)" % (tpf.prerod_phase() if is_instance_valid(tpf) else "-"))
	_key(KEY_ESCAPE, true)
	await frames(2)
	_key(KEY_ESCAPE, false)
	var pt0: float = tpf.prerod_t
	await frames(30)
	check(main._pause.is_open() and get_tree().paused and tpf.prerod_t == pt0, "the pause menu stops the transformation")
	main._pause._buttons[1].pressed.emit()
	await frames(5)
	check(not get_tree().paused and main.state == "intro", "Restart game during the transformation starts a new run")
	await seconds(Platformer.PREROD_T_END - pt0 + 2.0)
	check(main.state == "intro" and Game.level != Game.PMS_ID and not (main.platformer != null and main.platformer.is_pms()) and main._fade.modulate.a == 0.0, "the old transformation doesn't reach into the new run")
	main._quit_to_title()
	await frames(3)

	main._dev_action("checkpoint5", 5)
	var near_top := await until(func(): return main.state == "platformer" and Game.level == Game.CLIMB_ID and main.platformer != null, 8)
	await frames(3)
	check(near_top and main.platformer.p.y < 1200 and not main.platformer.climb_won and not node_box().is_open(), "the developer menu starts the climb near the top")
	main._quit_to_title()
	await frames(3)
	main._dev_action("climb_wheel", 0)
	var dev_wheel := await until(func(): return main.state == "mg11" and main.minigame is FertilityWheel and main.platformer != null and main.platformer.is_climb(), 8)
	check(dev_wheel, "the developer menu's The wheel opens the climb's wheel of the cycle")
	main._quit_to_title()
	await frames(3)
	main.open_minigame_for_dev("mg11")
	await frames(2)
	var mgw: FertilityWheel = main.minigame as FertilityWheel
	check(main.state == "mg11" and mgw != null, "?mg=mg11 opens the wheel on its own")
	if mgw:
		mgw.stop_at(9)
		mgw.continue_game()
	var w_title := await until(func(): return main.state == "title" and main.minigame == null, 3)
	check(w_title, "the wheel on its own: Continue goes back to the title")

	step("old summit (developer menu)")
	main._dev_action("checkpoint3", 1)
	var old_summit := await until(func(): return main.state == "platformer" and Game.level == 3 and main.platformer != null, 8)
	check(old_summit, "the old summit still starts from the developer menu")

	step("old level 3 – the summit")
	await finish_dialog("SA")
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
	await finish_dialog("SF")
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
	await finish_dialog("SG")
	await frames(5)
	check(main.state == "title" and Game.level == 1, "back to the title after the old summit")

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
	var summit := await until(func(): return main.state == "platformer" and Game.level == 3 and main.platformer != null, 6)
	check(summit, "the old summit starts after the old meadow")
	main._quit_to_title()
	await frames(5)

	step("an aborted fade can't cover the next run")
	main._fade_to(1.0, 3.0, Color.WHITE)
	await frames(5)
	main._abort_run()
	await seconds(0.5)
	check(main._fade.modulate.a == 0.0, "aborting a run stops a fade in progress")

	await _cave_fail_soft()

	step("pause menu")
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
	for i in [1, 2, 3, Game.CLIMB_ID]:
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
	check(Game.dev_unlocked, "opening developer mode unlocks the debug keys for this session")
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
	var pms_btns: Array = dev.find_children("*", "Button", true, false).filter(func(b): return b.text in ["Transformation", "Door open"])
	check(pms_btns.size() == 2 and pms_btns.all(func(b): return not b.disabled), "the developer menu's column 4 (PMS maze) is playable")
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
	# The jackpot climb: its tools, it opens at the bottom, new rows go on top.
	ed.select_level(Game.CLIMB_ID)
	await frames(4)
	var vbar := ed._scroll.get_v_scroll_bar()
	check(ed.upward() and not ed.horizontal() and ed.rows == Game.level_rows(Game.CLIMB_ID) and ["!", "$", "?", "0"].all(func(ch): return ed._tool_info.has(ch)), "editor switches to the jackpot climb and has its tools")
	check(ed._scroll.scroll_vertical > 0 and ed._scroll.scroll_vertical >= int(vbar.max_value - vbar.page) - 2, "the climb opens scrolled to its start at the bottom")
	# ~ and E are in both the climb's group and the old summit's: the group it was picked from lights up.
	ed._select_tool("E", "climb")
	check(ed.tool == "E" and _icon_on(ed._groups.climb.button) and not _icon_on(ed._groups.garden.button), "E from the Jackpot climb menu keeps that group active")
	ed._select_tool("~", "garden")
	check(ed.tool == "~" and _icon_on(ed._groups.garden.button) and not _icon_on(ed._groups.climb.button), "~ from the old summit's menu lights the old summit's group")
	ed._select_tool("=")
	var bottom_row := ed.rows[ed.rows.size() - 1]
	var n5 := ed.rows.size()
	ed._add_rows()
	check(ed.rows.size() == n5 + 20 and ed.rows[ed.rows.size() - 1] == bottom_row and ed.rows[0].strip_edges() == "", "Add 20 rows adds them at the top of the climb")
	ed.rows = Game.level_rows(Game.CLIMB_ID)
	ed._autosave()
	DirAccess.remove_absolute(LevelEditor.AUTOSAVE_FMT % Game.CLIMB_ID)
	if FileAccess.file_exists(LevelEditor.AUTOSAVE_FMT % ForestRunner.LEVEL_ID):
		DirAccess.remove_absolute(LevelEditor.AUTOSAVE_FMT % ForestRunner.LEVEL_ID)
	# The PMS maze: its tools; test play is upside down; the door ends a test.
	if FileAccess.file_exists(LevelEditor.AUTOSAVE_FMT % Game.PMS_ID):
		DirAccess.remove_absolute(LevelEditor.AUTOSAVE_FMT % Game.PMS_ID)
	ed.select_level(Game.PMS_ID)
	await frames(3)
	check(not ed.upward() and ed.cols() == 25 and ed.rows == Game.level_rows(Game.PMS_ID) and ["W", "&", "D"].all(func(ch): return ed._tool_info.has(ch)), "editor switches to the PMS maze and has its tools (W, &, D)")
	ed.start_test()
	await frames(5)
	check(ed._test != null and ed._test.is_pms() and ed._test.view_flip == 1.0 and absf(ed._test._world.rotation - PI) < 0.05, "test play of the maze is upside down")
	ed._test.dev_all_comforts()
	ed._test._pms_done()
	await frames(3)
	check(ed._test != null and ed._test.is_pms() and ed._toast.text.contains("door"), "the door in a test restarts it with a toast")
	ed.stop_test()
	await frames(2)
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
	check(BackgroundData.of_bundled(2).procedural and BackgroundData.of_bundled(3).procedural and BackgroundData.of_bundled(Game.CLIMB_ID).procedural, "meadow, old summit and the jackpot climb keep their procedural skies")
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
	check(Platformer.bg_origin_for(3, 28200) == Vector2(0, 27600) and Platformer.bg_origin_for(Game.CLIMB_ID, 20000).is_equal_approx(Vector2(0, 20000 - 600 / Platformer.CLIMB_ZOOM)) and Platformer.bg_origin_for(1, 28200) == Vector2.ZERO, "summit and climb layers are anchored to their start at the bottom")
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
	var old_edits := {"nodes": {"3A": {"lines": [{"key": "3A1", "speaker": "Kyra", "text": {}, "voice": ""}]}, "2C": {"lines": []}}, "saved": {"3F": null}, "deleted": {"3G": true}}
	DialogEditor._migrate_edits(old_edits)
	check(old_edits.nodes.has("SA") and not old_edits.nodes.has("3A") and old_edits.nodes.SA.lines[0].key == "SA1" and old_edits.nodes.has("2C") and old_edits.saved.has("SF") and old_edits.deleted.has("SG") and old_edits.version == DialogEditor.EDIT_VERSION, "older local edits of the old summit's 3A..3G move to SA..SG")
	var new_edits := {"version": DialogEditor.EDIT_VERSION, "nodes": {"3A": {"lines": []}}}
	DialogEditor._migrate_edits(new_edits)
	check(new_edits.nodes.has("3A"), "current edits of the climb's 3A stay")
	if FileAccess.file_exists(DialogEditor.EDIT_PATH):
		DirAccess.remove_absolute(DialogEditor.EDIT_PATH)
	dev._show("dialogs")
	await frames(3)
	var de: DialogEditor = dev._dialogs
	check(dev.actions.get_child_count() == 4 and (dev.actions.get_child(3) as Button).icon.resource_path.ends_with("save.svg"), "test / use in game / save (floppy) on the right of the bar")
	check(de != null and de.ids_in("2") == ["2A", "2B", "2C", "2E"] and de.ids_in("0").size() == 4, "the Dialogs tab lists each level's dialogs (2A–2E, 0A–0D)")
	check(Text.dialog_for_letter("c", ForestRunner.LEVEL_ID) == "2C" and Text.dialog_for_letter("b", Game.CLIMB_ID) == "3B" and Text.dialog_for_letter("b", 3) == "SB" and Text.dialog_for_letter("z", 1) == "", "letter c in level 2 starts dialog 2C")
	check(de.ids_in("mg").has("mg8_start") and not DialogEditor.is_story("mg8_start"), "minigame talk is listed apart, under its own names")
	check(de.ids_in("4") == ["4A", "4B", "4C", "4D", "4E", "4F", "4G", "4H"] and Text.dialog_for_letter("a", Game.PMS_ID) == "4A" and DialogEditor.BY_GAME.has("4A") and DialogEditor.BY_GAME.has("4E") and DialogEditor.BY_GAME.has("4F") and DialogEditor.BY_GAME.has("4G") and DialogEditor.BY_GAME.has("4H"), "the PMS maze's dialogs 4A–4H are listed (started by the game)")
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
	check(de.current == "2D" and de.nodes.has("2D") and de.ids_in("2") == ["2A", "2B", "2C", "2D", "2E"], "a new dialog gets the next free letter (2D)")
	de.set_text(0, "en", "Brand new.")
	var dfiles := de.build_commit(bundled)
	var dj: Dictionary = JSON.parse_string(dfiles["godot/data/dialogs.json"])
	var den: Dictionary = JSON.parse_string(dfiles["godot/data/i18n/en.json"])
	var nk: Array = dj.nodes.keys()
	check(dj.nodes["2C"].parts.size() == 2 and dj.nodes["2C"].parts[1].text == "2C2" and den["2C1"] == "Second line." and den["2C2"] == "Edited line one." and den["2D1"] == "Brand new.", "save writes the dialogs and their lines in every language")
	check(nk.find("2D") == nk.find("2C") + 1 and nk.find("2E") == nk.find("2D") + 1 and nk.find("3A") == nk.find("2E") + 1 and dj.nodes.has("mg8_start"), "saved dialogs stay in level order")
	# Characters: who speaks, with an avatar sprite each.
	de.select("2C")
	await frames(2)
	var sp_pick: OptionButton = de._lines.get_child(0).find_children("*", "OptionButton", true, false)[0]
	check(sp_pick.get_item_text(sp_pick.item_count - 1) == "New character…" and Text.speaker_name("Estrogenka") in ["Estra", "Estrogénka"], "each line has a speaker dropdown with the characters and New character…")
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
	de.select("2D")
	de.delete_dialog()
	check(not de.nodes.has("2D") and not de.deleted.has("2D"), "a new dialog can be deleted again")
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
	check(de.next_id("2") == "2D" and de.next_id("1") == "1F", "new dialogs never take a letter the game uses")
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


func _stick(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


## The next Platformer after the one with instance id `old` (a restart), once its fade is over.
func _next_pf(old: int, what: String) -> Platformer:
	var ok := await until(func(): return main.platformer != null and main.platformer.get_instance_id() != old and main.state == "platformer", 6)
	check(ok, what)
	await seconds(1.2)
	return main.platformer


func _debug_key(code: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = true
	main._unhandled_input(e)


func _collected(pf: Platformer, kind: String) -> bool:
	for e in pf.level.entities:
		if e.type == "trigger" and e.trigger_type == kind:
			return e.collected
	return false


## The cave fails soft (the iron rule, "try again" at the last checkpoint / rest point, the
## boss's "Retry fight" + 1E, the breath in the boss) and the debug keys are developer-only.
func _cave_fail_soft() -> void:
	step("the iron rule: a hit costs iron, only a hit with none left is too much")
	Game.dev_unlocked = false
	var old: int = main.platformer.get_instance_id() if main.platformer else 0
	main._dev_action("checkpoint", 3)
	Game.cramp_taught = true
	var pf := await _next_pf(old, "the cave from checkpoint 3")
	check(Game.cave_checkpoint == 3 and Game.checkpoint == 3 and node_box().node_id() == "", "checkpoint 3: after the pipes, no dialog")
	var spike := LevelData._ent("spike", pf.p.x, pf.p.y, 30, 30)
	spike.id = 99999
	pf.level.entities.append(spike)
	Game.iron = 4
	await frames(3)
	check(Game.iron <= 1 and not pf.p.is_dead and pf.p.hit_timer > 0 and not panel_box().is_open(), "a spike with 4 iron: it costs iron (down to 0), knocks her back, she goes on (%d left)" % Game.iron)
	pf.level.entities.erase(spike)
	Game.iron = 2
	pf.p.hit_timer = 0
	pf.p.invuln_timer = 0
	var en := _teleport_to_entity(pf, "enemy")
	await frames(3)
	check(pf.p.held_by_cramp == en.id, "a cramp grabs her with 2 iron")
	await seconds(5.0)
	check(Game.iron == 0 and not pf.p.is_dead and pf.p.held_by_cramp == en.id and not panel_box().is_open(), "held: the cramp takes her nuts down to 0 but never kills, she can still breathe free")
	pf.p.breath_index = 0
	pf.p.breath_timer = 0
	await _do_recharge()
	check(pf.p.held_by_cramp == -1 and not pf.p.is_dead and Game.iron == 0, "she breathes free with 0 iron")
	pf.p.invuln_timer = 0
	pf.p.hit_timer = 0
	pf.p.is_breathing = 0
	_teleport_to_entity(pf, "enemy")
	var over := await until(func(): return panel_box().is_open(), 5)
	check(over and pf.p.is_dead and panel_box()._panel.get("text", "") == "UI_CRAMPS_OVERWHELMED", "grabbed with no iron at all: too much pain, the game-over panel")
	var lang_was := Text.language
	var long_btns := []
	for lang in Text.LANGUAGES:
		Text.language = lang
		for bk in ["BTN_TRY_AGAIN", "BTN_RETRY_FIGHT", "BTN_MORE_IRON"]:
			check(Text._strings.get(lang, {}).has(bk), "%s exists in %s" % [bk, lang])
			if Text.font_dialog_bold.get_string_size(Text.plain(Text.t(bk)), HORIZONTAL_ALIGNMENT_LEFT, -1, DialogBox.BUTTON_SIZES.back()).x > 220.0 - 24 - 28:
				long_btns.append("%s/%s" % [lang, bk])
		for tk in ["UI_CRAMPS_OVERWHELMED", "UI_PAIN_PULLED_DOWN", "UI_BOSS_NO_IRON"]:
			check(Text._strings.get(lang, {}).has(tk), "%s exists in %s" % [tk, lang])
	Text.language = lang_was
	check(long_btns.is_empty(), "the game-over buttons fit in sk / en / pt %s" % str(long_btns))

	step("try again: the last checkpoint with a little iron, no 1A, no finished minigames")
	old = pf.get_instance_id()
	panel_box()._press(0)
	pf = await _next_pf(old, "try again starts a new cave")
	var mg3y := 0.0
	for e in pf.level.entities:
		if e.type == "trigger" and e.trigger_type == "mg3":
			mg3y = e.y
	check(Game.checkpoint == 3 and absf(pf.p.y - mg3y) < 1000, "she is back at checkpoint 3 (after the pipes), not at the cave's start (y %d, the pipes' row %d)" % [int(pf.p.y), int(mg3y)])
	check(Game.iron == Game.RETRY_IRON, "with a little iron (%d)" % Game.iron)
	check(node_box().node_id() == "" and not panel_box().is_open() and main.state == "platformer" and not pf.p.is_dead, "1A doesn't replay")
	check(_collected(pf, "mg2") and _collected(pf, "mg3") and not _collected(pf, "mg4"), "the chocolate and the pipes are done, the prices still ahead")
	Game.checkpoint_iron = 12
	pf._die(false)
	await until(func(): return panel_box().is_open(), 5)
	old = pf.get_instance_id()
	panel_box()._press(0)
	pf = await _next_pf(old, "try again once more")
	check(Game.iron == 12 and Game.checkpoint == 3, "she had 12 iron at the checkpoint: she gets them back (%d)" % Game.iron)

	step("debug keys are for developers only")
	old = pf.get_instance_id()
	var iron0 := Game.iron
	for kc in [KEY_5, KEY_1, KEY_G, KEY_H, KEY_C]:
		_debug_key(kc)
	await seconds(1.5)
	check(main.platformer != null and main.platformer.get_instance_id() == old and not pf.boss.active and Game.iron == iron0 and Game.level == 1, "1 / 5 / G / H / C do nothing for a normal player")
	await _go_trigger(pf, "mg4")
	await finish_dialog("mg3_start")
	var mgx: Minigame = main.minigame
	_key(KEY_X, true)
	await frames(3)
	_key(KEY_X, false)
	await frames(10)
	check(main.minigame == mgx and mgx != null and main.state == "mg4" and node_box().node_id() == "", "X doesn't skip a minigame for a normal player")
	Game.dev_unlocked = true
	_key(KEY_X, true)
	await frames(3)
	_key(KEY_X, false)
	await finish_dialog("mg3_after")
	await frames(3)
	check(main.state == "platformer" and Game.checkpoint == 4 and Game.cave_checkpoint == 4, "with developer mode unlocked X skips it (checkpoint 4)")
	Game.dev_unlocked = false

	step("a rest point between the prices and the boss")
	Game.iron = 9
	await _go_trigger(pf, "rest")
	var rest_y := Game.rest_y
	check(rest_y > 0 and Game.checkpoint_iron == 9 and main.state == "platformer" and node_box().node_id() == "", "passing the rest point (map marker R) saves it, the game goes on")
	Game.iron = 3
	pf._die(false)
	await until(func(): return panel_box().is_open(), 5)
	old = pf.get_instance_id()
	panel_box()._press(0)
	pf = await _next_pf(old, "try again after the rest point")
	check(Game.checkpoint == 4 and absf(pf.p.y - rest_y) < 400 and Game.iron == 9 and _collected(pf, "mg4") and _collected(pf, "rest"), "she starts at the rest point with the iron she had there (y %d, rest %d, iron %d)" % [int(pf.p.y), int(rest_y), Game.iron])

	step("boss lost: retry the fight")
	Game.iron = 14
	await _go_trigger(pf, "end")
	await finish_dialog("1C")
	check(pf.boss.active and Game.boss_iron == 14 and Game.checkpoint == 5, "in the arena with 14 iron")
	Game.iron = 6
	# A real fall: the floor under her goes, she drops into the depths.
	for hx in pf.hexes:
		if absf(hx.x - (pf.p.x + pf.p.width / 2)) < 140:
			hx.active = false
	pf.p.is_grounded = false
	var lost := await until(func(): return panel_box().is_open(), 8)
	check(pf.boss.lost, "she fell through the gap into the depths")
	# The monster drifts over what is left of the floor while the panel waits.
	for hx in pf.hexes:
		if hx.active:
			pf.boss.x = hx.x
			pf.boss.y = hx.y - 20
			break
	await seconds(1.5)
	check(panel_box()._panel.get("text", "") == "UI_PAIN_PULLED_DOWN" and Game.iron == 0, "the fallen fight is over: the monster takes nothing more, the one panel stays")
	var choices: Array = panel_box()._panel.get("choices", [])
	check(lost and choices.size() == 2 and choices[0].text == "BTN_RETRY_FIGHT" and choices[1].text == "BTN_MORE_IRON", "falling into the depths offers Retry fight and Back for more iron")
	old = pf.get_instance_id()
	panel_box()._press(0)
	pf = await _next_pf(old, "Retry fight starts the arena again")
	check(pf.boss.active and Game.iron == 14 and pf.hexes.size() == 14 and Game.checkpoint == 5, "the fight restarts at the arena with the iron she entered with (%d)" % Game.iron)
	await seconds(1.5)
	check(not panel_box().is_open() and Game.boss_retries == 1, "no stale game-over panel over the rematch (retries %d)" % Game.boss_retries)
	await finish_dialog("1E")
	await frames(3)
	check(node_box().node_id() == "" and main.state == "platformer", "Estrogenka's rematch talk 1E played (not 1C, not the whole cave)")

	step("the breath in the boss fight")
	pf.boss.x = pf.p.x + 110
	pf.boss.y = pf.p.y
	var hp0: int = pf.boss.hp
	pf.p.breath_charges = 0
	pf.p.breathing_cooldown = 0
	pf.p.is_recharging = true
	pf.p.breath_index = 2
	pf.p.breath_timer = 11.9
	Input.action_press("move_down")
	await frames(12)
	Input.action_release("move_down")
	await frames(10)
	check(pf.boss.hp < hp0 and pf.p.breath_charges == 1, "a finished breathing cycle shrinks the monster at once (as 1C says) and leaves one charge (hp %d → %d, charges %d)" % [hp0, pf.boss.hp, pf.p.breath_charges])

	step("boss lost again: no talk; back for more iron")
	pf._die(true)
	await until(func(): return panel_box().is_open(), 5)
	choices = panel_box()._panel.get("choices", [])
	check(panel_box()._panel.get("text", "") == "UI_BOSS_NO_IRON" and choices.size() == 2, "the iron ran out in the fight: the same two choices (%s)" % str(panel_box()._panel.get("text", "")))
	old = pf.get_instance_id()
	panel_box()._press(0)
	pf = await _next_pf(old, "Retry fight again")
	await seconds(0.5)
	check(pf.boss.active and Game.iron == 14 and node_box().node_id() == "" and main.state == "platformer", "the second retry starts the fight at once (1E only the first time) %s" % str([pf.boss.active, Game.iron, node_box().node_id(), main.state]))
	pf.p.y = pf.camera_y + 600
	await until(func(): return panel_box().is_open(), 5)
	for hx in pf.hexes:
		if hx.active:
			pf.boss.x = hx.x
			pf.boss.y = hx.y - 20
			break
	await seconds(1.5)
	old = pf.get_instance_id()
	panel_box()._press(1)
	pf = await _next_pf(old, "Back for more iron")
	check(not pf.boss.active and Game.checkpoint == 4 and absf(pf.p.y - rest_y) < 400 and Game.iron == 14 and Game.checkpoint_iron == 14 and node_box().node_id() == "", "back at the last checkpoint (the rest point) keeping the iron she entered the fight with (%d), so what she gathers is more" % Game.iron)
	await seconds(1.5)
	check(not panel_box().is_open() and main.state == "platformer", "no stale game-over panel in the cave after Back for more iron")
	Game.iron = 3
	await _go_trigger(pf, "end")
	await finish_dialog("1C")
	check(pf.boss.active and pf.hexes.size() == 10 and Game.iron == 10 and Game.boss_iron == 10, "the arena's floor is at least 10 hexes and she has as much iron as there is floor")

	step("debug keys once developer mode is unlocked; 1B when the first cramp comes near")
	Game.dev_unlocked = true
	old = pf.get_instance_id()
	_debug_key(KEY_2)
	pf = await _next_pf(old, "with developer mode unlocked, key 2 restarts at checkpoint 2")
	check(Game.checkpoint == 2 and not pf.boss.active, "checkpoint 2")
	_debug_key(KEY_C)
	check(Game.iron == 20, "C gives 20 iron")
	Game.dev_unlocked = false
	# 1B was never played in this (pretend) run and she is past its letter: the first cramp
	# that comes near plays it.
	Game.cramp_taught = false
	pf._first_enemy_seen = false
	for e in pf.level.entities:
		if e.type == "enemy" and not e.defeated:
			pf.p.x = clampf(e.x + 160, 40, 1000)
			pf.p.y = e.y - 30
			pf.p.vy = 0
			pf.camera_y = pf.p.y - 200
			break
	await finish_dialog("1B")
	check(Game.cramp_taught, "past the letter (an edited map): the first cramp near her still plays 1B")
	pf._first_enemy_seen = false
	await seconds(0.5)
	check(node_box().node_id() == "", "1B plays once per run")
	Game.iron = 20
	pf.p.held_by_cramp = -1
	pf.p.is_recharging = false
	Audio.stop_loop("krcloop.wav")
	pf._place_at_checkpoint(2)
	pf.p.invuln_timer = 5
	await frames(5)


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


## A tool group button lit as active (UiKit.set_icon_active).
func _icon_on(b: Button) -> bool:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.a > 0.5


## The climb: put Kyra with her feet at (cx, feet_y), the board a little below.
func _climb_put(pf: Platformer, cx: float, feet_y: float) -> void:
	pf.p.x = cx - pf.p.width / 2
	pf.p.y = feet_y - pf.p.height
	pf.p.vx = 0
	pf.p.vy = 0
	pf.camera_y = feet_y - 300
	pf.last_stand_y = feet_y
	pf.on_board = false


## The climb's heart meter: hearts fill the magazine (five make a whole heart, up to four),
## then the reserve, which reloads the magazine; a bell adds one; rocket fuel (jump held past a jump's top burns hearts) and the heart
## boost (Shift, 2), their hints only while affordable.
func _climb_hearts(pf: Platformer) -> void:
	var stand: LevelData.Plat = _climb_plat(pf, pf.level_h - 900)
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	pf.hearts = 0
	pf.climb_power.clear()
	pf.rise_wait = 30.0
	await frames(3)
	check(pf.hud.hint_lines().is_empty(), "no hearts ready: no heart abilities in the hints")
	_check_labels(pf.hud.labels, ["HUD_LBL_HEARTS"], "jackpot climb")
	var h: LevelData.Ent = _climb_ent(pf, "heart")
	var taken0 := pf.hearts_taken
	_climb_put(pf, h.x + h.w / 2, h.y + 30)
	await frames(2)
	var got := pf.hearts_taken - taken0
	check(h.collected and got >= 1 and absf(pf.meter.mag - Platformer.HEART_FILL / 100.0 * got) < 0.01 and pf.hearts == 0 and pf.meter.reserve == 0.0, "a heart fills the magazine's first heart part-way (%.2f)" % pf.meter.mag)
	pf.hearts = 0
	for i in 5:
		pf._take_heart(LevelData.Ent.new())
	check(pf.hearts == 1 and absf(pf.meter.mag - 1.0) < 0.001, "five hearts: one whole heart in the magazine")
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	check(pf.hud.hint_lines() == ["HINT_CLIMB_FUEL"], "one heart: rocket fuel is offered, not the boost (2) %s" % str(pf.hud.hint_lines()))
	_key(KEY_SHIFT, true)
	await frames(2)
	_key(KEY_SHIFT, false)
	await frames(2)
	check(pf.hearts == 1 and pf.heart_short > 0 and pf.p.vy >= -1, "the boost with one heart: nothing, the missing hearts blink")
	var bell: LevelData.Ent = _climb_ent(pf, "bell")
	_climb_put(pf, bell.x + bell.w / 2, bell.y + bell.h + 10)
	var bells0 := pf.bells
	await frames(2)
	check(bell.collected and pf.hearts == 2 and pf.bells == bells0 + 1, "a bell rings: one more ready heart (%d)" % pf.hearts)
	check(pf.slot_spin.get("kind", "") == "bell" and int(pf.slot_spin.get("stops", 9)) < 3, "a bell spins the spinner top-left")
	await seconds(Platformer.BELL_STOPS[-1] + 0.1)
	check(pf.spin_rest == ["bell", "bell", "bell"] and pf.hearts == 2, "… a short spin that settles on three bells (the +1 heart stays)")
	await seconds(0.7)
	check(pf.slot_spin.is_empty() and pf.spin_rest == ["bell", "bell", "bell"], "then the spinner rests (still) on them")
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	check(pf.hud.hint_lines() == ["HINT_CLIMB_HEART_BOOST", "HINT_CLIMB_FUEL"], "two hearts: the heart boost and rocket fuel are offered %s" % str(pf.hud.hint_lines()))
	var y0 := pf.p.y
	_key(KEY_SHIFT, true)
	await frames(2)
	_key(KEY_SHIFT, false)
	check(pf.hearts == 0 and pf.p.vy < -12 and pf.boost_t > 0, "Shift: the heart boost launches her for two hearts (vy %.1f)" % pf.p.vy)
	await frames(25)
	check(pf.p.y < y0 - 250, "the heart boost sends her several rows up (%d px)" % int(y0 - pf.p.y))
	await frames(3)
	check(pf.hud.hint_lines().is_empty(), "hearts spent: their hints go %s" % str(pf.hud.hint_lines()))
	# Rocket fuel: jump held once the jump's rise has run out ignites the thrusters.
	var pf_src := FileAccess.get_file_as_string("res://scripts/screens/platformer.gd")
	check(not pf.has_method("_heart_jump") and not pf_src.contains("HEART_JUMP_COST"), "the heart jump is gone (rocket fuel instead)")
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.hearts = 0
	_key(KEY_SPACE, true)
	var past_top := await until(func(): return pf.p.vy > 0.5, 2)
	await frames(4)
	check(past_top and not pf.thrusting and pf.p.vy > 0, "no hearts: jump held past its top, she just falls (vy %.1f)" % pf.p.vy)
	_key(KEY_SPACE, false)
	await until(func(): return pf.p.is_grounded, 3)
	# Let go early: the jump is still cut short, no thrusters, no fuel burnt.
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.hearts = 2
	_key(KEY_SPACE, true)
	await frames(4)
	var vy_rise := pf.p.vy
	_key(KEY_SPACE, false)
	await frames(1)
	check(not pf.thrusting and vy_rise < -6 and pf.p.vy > vy_rise + 2.5, "let go early: the jump is cut (vy %.1f → %.1f), no thrusters" % [vy_rise, pf.p.vy])
	await until(func(): return pf.p.is_grounded, 3)
	check(pf.meter.mag == 2.0, "… and no fuel burnt (%.2f hearts)" % pf.meter.mag)
	# Held past the top: the thrusters climb fast and burn hearts.
	_key(KEY_SPACE, true)
	var lit := await until(func(): return pf.thrusting, 2)
	var vy_lit := pf.p.vy
	var y_lit := pf.p.y
	await frames(18)
	check(lit and vy_lit >= Platformer.FUEL_IGNITE_VY - 2.0 and pf.thrusting and pf.p.vy < -10 and pf.p.y < y_lit - 120, "held past the top: the thrusters fire, she flies up fast (vy %.1f, %d px)" % [pf.p.vy, int(y_lit - pf.p.y)])
	check(pf.fuel_left() < 1.85 and pf.fuel_left() > 1.0, "the thrusters burn the hearts (%.2f left)" % pf.fuel_left())
	check(pf.particles.any(func(q): return q.type == "flame"), "flames under her feet")
	check(pf.hud.hint_lines().has("HINT_CLIMB_FUEL_BURN") and not pf.hud.hint_lines().has("HINT_CLIMB_FUEL"), "while burning, the fuel hint with its time bar %s" % str(pf.hud.hint_lines()))
	var sy := (pf.p.y - pf.camera_y) * pf.view_zoom
	check(sy > 20 and sy < 600 - Platformer.BOARD_H, "the camera follows her up (screen y %d)" % int(sy))
	_key(KEY_SPACE, false)
	await frames(1)
	check(not pf.thrusting and pf.p.vy >= -2.5, "jump let go: the thrusters cut out at once, no coasting up (vy %.1f)" % pf.p.vy)
	await frames(1)
	var fuel_after := pf.fuel_left()
	var fell := await until(func(): return pf.p.vy > 1, 2)
	await frames(10)
	check(fell and absf(pf.fuel_left() - fuel_after) < 0.001, "… she falls normally and no more fuel burns (%.2f)" % pf.fuel_left())
	await until(func(): return pf.p.is_grounded, 4)
	# A fresh press in the air is still the double jump; held after its top: the thrusters.
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.hearts = 1
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	await frames(8)
	_key(KEY_SPACE, true)
	await frames(2)
	check(pf.p.jumps_left == 0 and pf.p.vy < -8 and not pf.thrusting and pf.hearts == 1, "a fresh press in the air is the double jump (vy %.1f), no fuel" % pf.p.vy)
	lit = await until(func(): return pf.thrusting, 2)
	check(lit and pf.p.jumps_left == 0, "held past the double jump's top: the thrusters")
	# Out of fuel: they stop and she falls.
	var out := await until(func(): return not pf.thrusting, 2)
	check(out and pf.meter.mag <= MeterModel.EPS, "the last heart burnt: the thrusters stop (%.2f hearts)" % pf.meter.mag)
	await frames(30)
	check(pf.p.vy > 0 and not pf.thrusting, "… and she falls (vy %.1f)" % pf.p.vy)
	_key(KEY_SPACE, false)
	await until(func(): return pf.p.is_grounded, 4)
	# Near the level's top: she never flies off it (nor off the top of the screen).
	var top_trig: LevelData.Ent = null
	for e in pf.level.entities:
		if e.type == "trigger" and e.trigger_type == "climb_top":
			top_trig = e
	var top_was := top_trig.collected
	top_trig.collected = true
	_climb_put(pf, pf.level_w / 2, 700.0)
	pf.camera_y = 300.0
	pf.hearts = Platformer.HEART_SLOTS
	pf.p.vy = 0.0
	var min_y := pf.p.y
	var min_sy := 9999.0
	_key(KEY_SPACE, true)
	for i in 90:
		await frames(1)
		min_y = minf(min_y, pf.p.y)
		min_sy = minf(min_sy, (pf.p.y - pf.camera_y) * pf.view_zoom)
	_key(KEY_SPACE, false)
	check(min_y >= 0.0 and min_sy >= -1.0, "the thrusters never take her off the level's top (y %d) or the screen (%d)" % [int(min_y), int(min_sy)])
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	top_trig.collected = top_was
	# Pressed just before landing: buffered into the free ground jump, no heart spent.
	pf.hearts = 1
	pf.p.jumps_left = 0
	pf.p.y = stand.y - pf.p.height - 14
	pf.p.vy = 4.0
	pf.p.is_grounded = false
	pf.p.coyote = 0
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	var buffered := await until(func(): return pf.p.vy < -5, 1)
	check(buffered and pf.hearts == 1, "a jump pressed just before landing is buffered (free), not a heart jump (hearts %d)" % pf.hearts)
	await until(func(): return pf.p.is_grounded, 3)
	# … also when the key stays down: a press while falling (no jump left) never lights
	# the thrusters, it stays the buffered ground jump.
	pf.hearts = 2
	pf.p.jumps_left = 0
	pf.p.y = stand.y - pf.p.height - 40
	pf.p.vy = 8.0
	pf.p.is_grounded = false
	pf.p.coyote = 0
	_key(KEY_SPACE, true)
	var lit_falling := false
	var jumped := false
	for i in 40:
		await frames(1)
		if pf.p.vy < -5:
			jumped = true
			break
		lit_falling = lit_falling or pf.thrusting
	check(jumped and not lit_falling and pf.meter.mag == 2.0, "jump held down while falling: buffered into the ground jump, no thrusters (hearts %d)" % pf.hearts)
	_key(KEY_SPACE, false)
	await until(func(): return pf.p.is_grounded, 3)
	# A heart boost during a burn: the thrusters wait (no fuel burnt for nothing).
	pf.hearts = Platformer.HEART_SLOTS
	_key(KEY_SPACE, true)
	await until(func(): return pf.thrusting, 2)
	var h_before := pf.fuel_left()
	_key(KEY_SHIFT, true)
	await frames(1)
	_key(KEY_SHIFT, false)
	var fuel_boost := pf.fuel_left()
	await frames(8)
	check(h_before - fuel_boost > 1.5 and not pf.thrusting and absf(pf.fuel_left() - fuel_boost) < 0.001, "a heart boost mid-burn: the thrusters wait for its top (%.2f → %.2f)" % [fuel_boost, pf.fuel_left()])
	_key(KEY_SPACE, false)
	await until(func(): return pf.p.is_grounded, 4)
	# A short burn doesn't lift the board past the platform she jumped from.
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.rise_wait = 99.0
	pf.hearts = 1
	_key(KEY_SPACE, true)
	await until(func(): return pf.thrusting, 2)
	await frames(10)
	_key(KEY_SPACE, false)
	await frames(2)
	check(pf.board_y() >= stand.y - 1.0, "a short burn keeps the board under her platform (board %d, platform %d)" % [int(pf.board_y()), int(stand.y)])
	var back := await until(func(): return pf.p.is_grounded, 4)
	check(back and absf(pf.p.y + pf.p.height - stand.y) < 8.0, "… she lands back at her platform's height, not on a lifted board (feet %d, platform %d, board %d)" % [int(pf.p.y + pf.p.height), int(stand.y), int(pf.board_y())])
	pf.rise_wait = 0.0
	# After the wheel, the key that confirmed it doesn't light the thrusters.
	pf.hearts = 2
	pf.p.y = stand.y - pf.p.height - 200
	pf.p.vy = -0.5
	pf.p.is_grounded = false
	pf.thrusting = true
	_key(KEY_SPACE, true)
	pf.after_wheel()
	await frames(6)
	check(not pf.thrusting and pf.hearts == 2, "after the wheel: Space still down doesn't light the thrusters")
	_key(KEY_SPACE, false)
	pf.board_talk = {}
	pf.board_queue.clear()
	await until(func(): return pf.p.is_grounded, 4)
	# A bell with a full meter gives nothing, and says so.
	pf.meter.reset(Platformer.HEART_SLOTS, pf.meter.reserve_max)
	pf.ticker_queue.clear()
	var full_bell := LevelData.Ent.new()
	full_bell.x = pf.p.x
	full_bell.y = pf.p.y
	pf._ring_bell(full_bell)
	check(pf.hearts == Platformer.HEART_SLOTS and pf.ticker_queue.has(Text.plain(Text.t("CLIMB_BELL_FULL"))) and not pf.ticker_queue.has(Text.plain(Text.t("CLIMB_BELL"))), "a bell on a full meter doesn't promise +1 heart")
	# The magazine holds four, the rest goes to the reserve, which reloads it.
	pf.hearts = 0
	var bell2 := LevelData.Ent.new()
	bell2.x = pf.p.x
	bell2.y = pf.p.y
	pf._ring_bell(bell2)
	check(pf.hearts == 1 and pf.meter.reserve == 0.0, "a bell: one heart into the magazine first")
	pf.add_heart_fill(500.0)
	check(pf.hearts == Platformer.HEART_SLOTS and absf(pf.meter.reserve - 2.0) < 0.001, "a full magazine (%d) sends the rest into the reserve (%.1f)" % [pf.hearts, pf.meter.reserve])
	check(pf.spend_hearts(3) and pf.hearts == 1 and not pf.meter.reloading, "spending three: one left, the reserve waits a moment")
	await seconds(0.5)
	check(pf.hearts == 1 and pf.meter.flyers.is_empty(), "… no reload right after spending")
	var re := await until(func(): return not pf.meter.flyers.is_empty(), 1.5)
	check(re and pf.meter.reloading, "then the reserve reloads the magazine, a heart flies into the pill")
	await until(func(): return not pf.meter.reloading and pf.meter.flyers.is_empty(), 3)
	check(pf.hearts == 3 and pf.meter.reserve < 0.001, "the reserve's two hearts are in the magazine (%d, reserve %.2f)" % [pf.hearts, pf.meter.reserve])
	check(pf.powers_explained.has(Platformer.RESERVE_DIALOG) and (pf.board_talking(Platformer.RESERVE_DIALOG) or pf.board_queue.has(Platformer.RESERVE_DIALOG) or pf.board_talk.is_empty()), "the first heart into the reserve: the board explains the reserve (3F)")
	pf.board_talk = {}
	pf.board_queue.clear()
	# Rocket fuel burns the magazine itself: half a heart burnt is half a heart missing.
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.hearts = Platformer.HEART_SLOTS
	_key(KEY_SPACE, true)
	await until(func(): return pf.thrusting, 2)
	await until(func(): return pf.meter.mag <= Platformer.HEART_SLOTS - 0.5, 2)
	_key(KEY_SPACE, false)
	await frames(1)
	var burnt := pf.meter.mag
	check(burnt < Platformer.HEART_SLOTS - 0.3 and burnt > Platformer.HEART_SLOTS - 0.8 and not pf.thrusting, "a short burn takes part of the top heart from the magazine (%.2f)" % burnt)
	var hr := pf.add_heart_fill(Platformer.HEART_FILL)
	check(hr.x > 0.19 and hr.y == 0.0 and pf.meter.reserve == 0.0, "… a heart picked up then fills that part-burnt heart, not the reserve (%.2f)" % pf.meter.mag)
	await until(func(): return pf.p.is_grounded, 4)
	pf.meter.reset(2.5, 2.0)
	await until(func(): return not pf.meter.reloading and pf.meter.flyers.is_empty() and pf.meter.mag >= 4.0 - 0.001, 4)
	check(absf(pf.meter.mag - 4.0) < 0.001 and absf(pf.meter.reserve - 0.5) < 0.001, "the reload tops the part-burnt heart up to a full magazine (%.2f, reserve %.2f)" % [pf.meter.mag, pf.meter.reserve])
	# A part of a heart is fuel too; burnt down to empty, the magazine reloads at once.
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	await frames(3)
	pf.rise_wait = 99.0
	pf.meter.reset(0.6, 2.0)
	_key(KEY_SPACE, true)
	var lit_part := await until(func(): return pf.thrusting, 2)
	var out_part := await until(func(): return not pf.thrusting, 2)
	check(lit_part and out_part and pf.meter.mag <= MeterModel.EPS + 0.01, "0.6 of a heart lights the thrusters and burns down to empty (%.2f)" % pf.meter.mag)
	await frames(2)
	check(pf.meter.reloading and pf.meter.reload_from_empty, "… then the empty magazine reloads at once")
	_key(KEY_SPACE, false)
	await until(func(): return pf.p.is_grounded, 4)
	pf.rise_wait = 0.0
	pf.board_talk = {}
	pf.board_queue.clear()
	pf.hearts = 0
	_climb_put(pf, stand.x + stand.w / 2, stand.base_y)
	pf.rise_wait = 0.0
	await frames(3)


## The climb's wheel of the cycle (mg11): its row opens the minigame (the climb waits),
## a spin lands on a day, the card says whether a pregnancy is possible, Continue goes
## back to the climb where she was and the after-talk plays on the board.
func _climb_wheel(pf: Platformer) -> void:
	var events: Array = []
	pf.trigger.connect(func(n): events.append(n))
	pf.wheel_done = false
	pf.teleport_to_trigger("mg11")
	var opened := await until(func(): return main.state == "mg11" and main.minigame is FertilityWheel, 3)
	check(opened and events.has("mg11") and not node_box().is_open() and panel_box().is_open(), "the wheel's row opens the wheel of the cycle (mg11); its intro is the hint panel")
	var fw: FertilityWheel = main.minigame as FertilityWheel
	if fw == null:
		return
	var y0 := pf.p.y
	var cam := pf.camera_y
	await seconds(1.0)
	check(not pf.active and absf(pf.camera_y - cam) < 0.01 and absf(pf.p.y - y0) < 0.01, "while the wheel is open the climb waits (the board doesn't rise)")
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	check(fw.state == "spinning" and fw.spins == 1 and fw.speed > 5, "Space spins the wheel")
	await seconds(0.6)
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	check(fw.braking, "pressing again brakes it")
	var landed := await until(func(): return fw.state == "result", 10)
	check(landed and fw.result_day >= 1 and fw.result_day <= 28 and fw.results.size() == 1, "it lands on a day of the cycle (%d)" % fw.result_day)
	check(FertilityWheel.verdict_key(9) == "MG11_POSSIBLE" and FertilityWheel.verdict_key(12) == "MG11_POSSIBLE" and FertilityWheel.verdict_key(14) == "MG11_POSSIBLE" and FertilityWheel.verdict_key(3) == "MG11_UNLIKELY" and FertilityWheel.verdict_key(8) == "MG11_UNLIKELY" and FertilityWheel.verdict_key(22) == "MG11_UNLIKELY", "the fertile window (days 9–14) says pregnancy is possible, the other days very unlikely")
	check(FertilityWheel.phase_key(2) == "MG11_PERIOD" and FertilityWheel.phase_key(7) == "MG11_AFTER_PERIOD" and FertilityWheel.phase_key(11) == "MG11_FERTILE" and FertilityWheel.phase_key(14) == "MG11_OVULATION" and FertilityWheel.phase_key(20) == "MG11_LUTEAL", "each day has its phase")
	var all_days := true
	for d in range(1, 29):
		all_days = all_days and FertilityWheel.day_at(-((d - 1) + 0.5) * FertilityWheel.seg_angle()) == d
	check(all_days, "the pointer reads the day under it for all 28 slices")
	fw.stop_at(12)
	check(fw.result_day == 12 and fw.spins == 2 and fw.buttons().size() == 2, "a second spin: day 12 (two buttons: spin again, continue)")
	fw.stop_at(22)
	check(fw.result_day == 22 and fw.spins == FertilityWheel.MAX_SPINS and fw.buttons().size() == 1 and fw.sel == 1, "after %d spins only Continue is left" % FertilityWheel.MAX_SPINS)
	var lang0 := Text.language
	var fit := true
	var texts := true
	for lang in Text.LANGUAGES:
		Text.language = lang
		fit = fit and FertilityWheel.texts_fit()
		for k in ["MG11_HINT", "MG11_POSSIBLE", "MG11_POSSIBLE_TEXT", "MG11_UNLIKELY", "MG11_UNLIKELY_TEXT", "MG11_AGAIN", "MG11_DAY", "MG11_SPIN", "MG11_STOP", "MG11_AFTER1", "MG11_AFTER2"]:
			texts = texts and Text._strings.get(lang, {}).has(k)
	Text.language = lang0
	check(fit and texts, "the wheel's texts exist and fit its card in sk / en / pt")
	await seconds(0.5)
	_key(KEY_SPACE, true)
	await frames(2)
	_key(KEY_SPACE, false)
	var back := await until(func(): return main.state == "platformer" and main.minigame == null, 3)
	await frames(2)
	check(back and pf.active and absf(pf.p.y - y0) < 12 and not panel_box().is_open(), "Continue: back in the climb where she was, on her bobbing platform (active %s, dy %.1f, panel %s)" % [pf.active, pf.p.y - y0, panel_box().is_open()])
	check(pf.board_talking("mg11_after") and not node_box().is_open() and pf.rise_wait > 0, "Estrogenka sums it up on the board; the board waits a moment before it rises")
	pf.teleport_to_trigger("mg11")
	await frames(3)
	check(main.state == "platformer", "the wheel opens once per climb")
	_board_flush(pf)


## The climb: ends the board dialogs (the current one and the queue) right away.
func _board_flush(pf: Platformer) -> void:
	var guard := 0
	while pf.board_talking() and guard < 40:
		pf.board_next()
		guard += 1


## The climb: the platform nearest to (above) y.
func _climb_plat(pf: Platformer, y: float) -> LevelData.Plat:
	var best: LevelData.Plat = null
	for pl in pf.level.platforms:
		if pl.base_y <= y and (best == null or pl.base_y > best.base_y):
			best = pl
	return best


## The climb: the lowest entity of a type not taken yet.
func _climb_ent(pf: Platformer, type: String) -> LevelData.Ent:
	var best: LevelData.Ent = null
	for e in pf.level.entities:
		if e.type == type and not e.collected and (best == null or e.y > best.y):
			best = e
	return best


## Kyra's drawn bounds on the rotated screen (her box, with room for the sprite's head and
## sides).
func _pms_screen_rect(pf: Platformer) -> Rect2:
	var world := Rect2(pf.p.x - 12, pf.p.y - 28, pf.p.width + 24, pf.p.height + 28)
	var a := pf.screen_of(world.position)
	var r := Rect2(a, Vector2.ZERO)
	for c in [Vector2(world.end.x, world.position.y), world.end, Vector2(world.position.x, world.end.y)]:
		r = r.expand(pf.screen_of(c))
	return r


## Whether she is clear of the maze's HUD (the top) and the dialog box's place (the bottom).
func _pms_clear(pf: Platformer) -> bool:
	var r := _pms_screen_rect(pf)
	for h in PlatformerHud.pms_hud_rects():
		if r.intersects(h):
			return false
	return r.end.y <= Platformer.H - DialogBox.H + 0.5


## The maze: a dialog holds Kyra in place (a movement press nudges its button), and the
## camera keeps her clear of the HUD and the dialog box at the spawn, in the middle, at the
## door and in a fall.
func _pms_hold_and_hud(pf: Platformer) -> void:
	var start := Vector2(pf.p.x, pf.p.y)
	var energy := pf.pms_light
	await frames(30)
	check(_pms_clear(pf), "at the spawn (the map's first rows) she is clear of the HUD and the dialog box's place %s" % _pms_screen_rect(pf))
	# A jump at the spawn (as high in the world = as low on screen as she gets there).
	var clear := true
	_key(KEY_SPACE, true)
	for i in 50:
		await frames(1)
		clear = clear and _pms_clear(pf)
	_key(KEY_SPACE, false)
	await until(func(): return pf.p.is_grounded, 3)
	check(clear, "… and through a jump there (the camera may over-scroll the first rows: %.0f)" % pf.camera_y)
	# A dialog open: she is held; movement keys only nudge its button.
	main._dialog("4G")
	await frames(3)
	var box := node_box()
	var held := Vector2(pf.p.x, pf.p.y)
	var n0 := box.nudges
	check(pf.dialog_frozen() and box.is_open(), "a dialog in the maze holds Kyra")
	_key(KEY_RIGHT, true)
	await frames(5)
	check(box.nudges == n0 + 1 and box.shaking(), "pressing a movement key nudges the dialog's button (it wiggles)")
	_key(KEY_RIGHT, false)
	await frames(15)
	_key(KEY_LEFT, true)
	await frames(3)
	check(box.nudges == n0 + 1 and not box.shaking(), "the wiggle is short and the nudge rate-limited")
	await frames(40)
	_key(KEY_LEFT, false)
	_key(KEY_SPACE, true)
	await frames(15)
	_key(KEY_SPACE, false)
	Input.action_press("breathe")
	await frames(10)
	Input.action_release("breathe")
	check(box.nudges == n0 + 2 and Vector2(pf.p.x, pf.p.y).distance_to(held) < 0.5 and pf.p.is_grounded and not pf.resting and not pf.p.is_sitting, "she doesn't walk, jump or rest while it is open (%s → %s)" % [held, Vector2(pf.p.x, pf.p.y)])
	check(_pms_clear(pf), "… and stays clear of the HUD and the dialog box")
	# A held stick sends an event for every small change: one nudge per push, not one per event.
	var mode_was: String = Game.control_mode
	await frames(40)
	var n1 := box.nudges
	for i in 60:
		_stick(JOY_AXIS_LEFT_X, 0.6 + 0.3 * sin(i * 0.9))
		await frames(1)
	check(box.nudges == n1 + 1, "a held (jittering) stick nudges once (%d)" % (box.nudges - n1))
	_stick(JOY_AXIS_LEFT_X, 0.0)
	await frames(2)
	_stick(JOY_AXIS_LEFT_X, -0.9)
	await frames(3)
	_stick(JOY_AXIS_LEFT_X, 0.0)
	check(box.nudges == n1 + 2, "… and again after it came back to the centre")
	# The dialog's own face buttons never nudge (a debounced one reaches the maze).
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_X
	jb.pressed = true
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	check(not pf._is_move_press(jb) and pf._is_move_press(rb), "the dialog's face buttons are not a movement press (RB is)")
	Game.control_mode = mode_was
	# At the door (4E) she is under hold_input: the nudge works there too.
	await frames(40)
	n1 = box.nudges
	pf.hold_input = true
	_key(KEY_LEFT, true)
	await frames(3)
	_key(KEY_LEFT, false)
	pf.hold_input = false
	check(box.nudges == n1 + 1, "a dialog under hold_input (4E at the door) nudges too")
	while box.is_open():
		box._press(0)
		await frames(2)
	_key(KEY_RIGHT, true)
	await frames(20)
	_key(KEY_RIGHT, false)
	check(pf.p.x > held.x + 15 and not pf.dialog_frozen(), "after it is closed she moves again")
	await frames(20)
	# Holding down while standing: the look-down pose and a peek ahead (bounded), as elsewhere.
	await until(func(): return pf.p.is_grounded and absf(pf.p.vx) < 0.5, 3)
	var cam0 := pf.camera_y
	Input.action_press("move_down")
	await seconds(1.4)
	var peek_r := _pms_screen_rect(pf)
	check(pf.p.look_down_timer > 0.3 and pf.pms_peek > 100.0 and pf.camera_y > cam0 + 60.0, "holding down in the maze looks down and peeks ahead (peek %.0f, camera %.0f → %.0f)" % [pf.pms_peek, cam0, pf.camera_y])
	check(Rect2(0, 0, Platformer.W, Platformer.H).encloses(peek_r), "… she stays on screen meanwhile %s" % peek_r)
	main._dialog("4G")
	await frames(3)
	check(pf.p.look_down_timer == 0.0, "… a dialog ends the look-down")
	Input.action_release("move_down")
	while box.is_open():
		box._press(0)
		await frames(2)
	await until(func(): return pf.pms_peek == 0.0, 3)
	await frames(30)
	check(pf.pms_peek == 0.0 and _pms_clear(pf), "… and the camera comes back, clear of the HUD and the dialog box's place")
	# A dialog opened in the air: she lands (no drifting sideways) and then stays.
	pf._do_jump()
	pf.p.vx = 5.0
	await frames(4)
	main._dialog("4G")
	await frames(2)
	var air_x := pf.p.x
	check(not pf.p.is_grounded and pf.p.vx == 0.0, "a dialog opened in the air stops her drift")
	Input.action_press("move_right")
	var landed := await until(func(): return pf.p.is_grounded, 3)
	var land := Vector2(pf.p.x, pf.p.y)
	_key(KEY_SPACE, true)
	await frames(20)
	_key(KEY_SPACE, false)
	Input.action_release("move_right")
	check(landed and absf(land.x - air_x) < 0.5 and Vector2(pf.p.x, pf.p.y).distance_to(land) < 0.5 and pf.p.is_grounded, "… she lands straight down and stays there")
	while box.is_open():
		box._press(0)
		await frames(2)
	# The middle of the maze, a fall, the door (the map's last rows).
	var mid: LevelData.Plat = null
	for t in pf.wall_tops:
		if is_equal_approx(t.base_y, 1440.0) and t.x <= 100 and t.x + t.w >= 140:
			mid = t
	check(mid != null, "the maze has the middle floor the test stands on")
	if mid != null:
		pf.p.x = 100
		pf.p.y = mid.base_y - pf.p.height
		pf.p.vx = 0
		pf.p.vy = 0
		await frames(60)
		check(_pms_clear(pf), "in the middle of the maze she is clear of the HUD %s" % _pms_screen_rect(pf))
		# A fall (down in the world = up on screen, towards the HUD).
		pf.p.y = mid.base_y - 2 * LevelData.ROW_H + 4
		pf.p.vy = Platformer.MAX_FALL
		clear = true
		for i in 40:
			await frames(1)
			clear = clear and _pms_clear(pf)
		check(clear and pf.p.is_grounded, "… and while she falls (up on screen)")
	for e in pf.level.entities:
		if e.type == "door":
			pf.p.x = e.x - 70
			pf.p.y = e.y + e.h - pf.p.height - 2
			pf.p.vx = 0
			pf.p.vy = 0
			pf.p.y -= 100
			clear = true
			for i in 70:
				await frames(1)
				clear = clear and (i < 3 or _pms_clear(pf))
			check(clear and pf.p.is_grounded, "at the door (the map's last rows) she is clear of the HUD %s" % _pms_screen_rect(pf))
	# The cave keeps its dialog floor (she can run and sit on the box): only the maze holds her.
	check(not pf.dialog_frozen(), "nothing holds her without a dialog")
	pf.p.x = start.x
	pf.p.y = start.y
	pf.p.vx = 0
	pf.p.vy = 0
	pf.last_ground = start
	pf.pms_light = energy
	pf.camera_y = pf.pms_camera_clamp(start.y - Platformer.H * Platformer.PMS_VIEW_Y)
	await frames(30)


## The PMS maze from its start (4A finished): reversed on screen, walls, the breath, the
## items, the door, the end.
func _pms_play(pf: Platformer) -> void:
	var events: Array = []
	pf.trigger.connect(func(n): events.append(n))
	# (The gauge's foggy spells are played on their own, in _pms_light.)
	pf.fog_wait = 999.0
	await _pms_hold_and_hud(pf)
	await _pms_dark(pf)
	check(absf(pf._world.rotation - PI) < 0.05 and pf.view_flip == 1.0, "the maze's world is drawn rotated 180°")
	# Right moves her right in the world, which is left on screen.
	var xf := pf._player_layer.get_transform()
	var sx0 := (xf * Vector2(pf.p.x, pf.p.y)).x
	var wx0 := pf.p.x
	Input.action_press("move_right")
	await frames(20)
	Input.action_release("move_right")
	xf = pf._player_layer.get_transform()
	var sx1 := (xf * Vector2(pf.p.x, pf.p.y)).x
	check(pf.p.x > wx0 + 20 and sx1 < sx0 - 20, "pressing right: world x up (%d → %d), screen x down (%d → %d)" % [wx0, pf.p.x, sx0, sx1])
	# A wall blocks from the side (the low block in the top corridor).
	var cw := LevelData.CELL_W
	var block := Rect2()
	for r in pf.level.walls:
		if is_equal_approx(r.position.y, 240.0) and r.position.x > 300 and r.end.x < 1000:
			block = r
	check(block.size.x > 0, "the top corridor has a low wall block")
	pf.p.x = block.position.x - pf.p.width - 30
	pf.p.y = block.end.y - pf.p.height
	pf.p.vx = 0
	pf.p.vy = 0
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	check(pf.p.x + pf.p.width <= block.position.x + 0.6, "a wall stops her from the side")
	# … and from below: jumping up into a wall's underside bumps her head.
	var floor3 := Rect2()
	for r in pf.level.walls:
		if is_equal_approx(r.position.y, 360.0) and r.size.x > 300:
			floor3 = r
	pf.p.x = floor3.position.x + 200
	pf.p.y = floor3.end.y + 5
	pf.p.vy = -12
	pf.p.is_grounded = false
	var through := false
	for i in 12:
		await frames(1)
		through = through or pf.p.y < floor3.end.y - 1
	check(not through and pf.p.y >= floor3.end.y - 0.5, "a wall stops her from below")
	await _pms_light(pf, events)
	# The door is closed until all three items are found.
	var door: LevelData.Ent = null
	var items: Array = []
	for e in pf.level.entities:
		if e.type == "door":
			door = e
		elif e.type == "comfort":
			items.append(e)
	pf.p.x = door.x + door.w / 2 - pf.p.width / 2
	pf.p.y = door.y + door.h - pf.p.height - 2
	pf.p.vy = 0
	await frames(20)
	check(pf.door_open == 0.0 and not events.has("pms_done") and not pf._pms_done_sent, "the door stays closed without the items")
	# Out of map order (the tea's pocket is off the obvious route): each item still gets its
	# own tip and its own HUD slot; the last one, whichever it is, opens the door (4F).
	var pick_order := [1, 2, 0]
	for n in pick_order.size():
		var tier: int = pick_order[n]
		var it: LevelData.Ent = null
		for e in items:
			if e.tier == tier:
				it = e
		pf.pms_light = 0.2
		pf.p.x = it.x + it.w / 2 - pf.p.width / 2
		pf.p.y = it.y + it.h - pf.p.height
		pf.p.vy = 0
		var did: String = PmsMaze.ITEM_DIALOGS[tier]
		var got := await until(func(): return node_box().node_id() == did, 3)
		check(pf.pms_light == 1.0 and pf.light_burst > 0.3, "the %s fills her energy, with a warm burst of light (%.2f, burst %.2f)" % [PmsMaze.ITEMS[tier], pf.pms_light, pf.light_burst])
		var slots_ok := true
		for k in 3:
			slots_ok = slots_ok and pf.pms_found[k] == pick_order.slice(0, n + 1).has(k)
		check(got and pf.pms_items == n + 1 and it.collected and slots_ok, "item %d picked (%s): dialog %s, its own slot filled %s" % [n + 1, PmsMaze.ITEMS[tier], did, pf.pms_found])
		if n < 2:
			check(pf.door_open == 0.0, "the door is still closed after %d item(s)" % (n + 1))
		await finish_dialog(did)
	check(pf.door_open > 0, "the third item opens the door")
	var door_line := await until(func(): return node_box().node_id() == PmsMaze.DOOR_DIALOG, 3)
	check(door_line, "after the third item, whichever it is: %s (the door is open)" % PmsMaze.DOOR_DIALOG)
	await finish_dialog(PmsMaze.DOOR_DIALOG)
	await seconds(0.8)
	pf.p.x = door.x + door.w / 2 - pf.p.width / 2
	pf.p.y = door.y + door.h - pf.p.height - 2
	pf.p.vy = 0
	var done := await until(func(): return events.has("pms_done"), 3)
	check(done and pf.hold_input, "the open door ends the level (pms_done)")
	await finish_dialog("4E")
	await frames(5)


## After 4E: the end screen (the ring, four phases, the buttons), the save marks the game as
## finished; then the title's Continue and phase picker with saves of different places.
func _end_and_continue() -> void:
	step("the end screen")
	var es := main._menu as EndScreen
	check(main.state == "end" and es != null and Game.level == 1 and main.platformer == null, "after 4E: the end screen (not the title)")
	if es == null:
		return
	check(Game.is_finished() and not Game.has_progress() and Game.reached_chapter() == 4, "the save marks the game as finished")
	check(EndScreen.PHASES.size() == 4 and es._cards.size() == 4 and EndScreen.PHASES.map(func(ph): return ph.name) == ["PHASE_MENSTRUATION", "PHASE_FOLLICULAR", "PHASE_OVULATION", "PHASE_LUTEAL"], "the four phases in the cycle's order")
	var texts := {}
	for ph: Dictionary in EndScreen.PHASES:
		texts[Text.t(ph.text)] = true
	check(texts.size() == 4 and not texts.has("END_PHASE_1") and Text.t("END_CLOSING") != "END_CLOSING", "one take-away per phase and a closing line")
	# The ring runs clockwise from the top: each phase's connector lies in its card's corner.
	var side_ok := true
	for ph: Dictionary in EndScreen.PHASES:
		var dp := EndScreen.day_point(ph.day, EndScreen.RING_OUT)
		var r: Rect2 = ph.rect
		if absf(dp.x - EndScreen.RING_C.x) > 20 and (dp.x > EndScreen.RING_C.x) != (r.position.x > EndScreen.RING_C.x):
			side_ok = false
	check(side_ok and EndScreen.day_point(1.0, 100).y < EndScreen.RING_C.y and EndScreen.day_point(8.0, 100).x > EndScreen.RING_C.x and EndScreen.day_point(22.0, 100).x < EndScreen.RING_C.x, "the ring runs clockwise from day 1 at the top; every card is on its phase's side (ovulation at the bottom)")
	# The Enter that closed 4E can't skip it: nothing works until everything is shown.
	var again := [0]
	es.again_pressed.connect(func(): again[0] += 1)
	_key(KEY_ENTER, true)
	await frames(2)
	_key(KEY_ENTER, false)
	es._again.pressed.emit()
	await frames(2)
	check(main.state == "end" and again[0] == 0 and es._again.disabled and es._cards[3].modulate.a < 1.0, "the buttons wait until the cards have come in")
	await seconds(EndScreen.READY + 0.2)
	check(es.ready_for_input() and not es._again.disabled and es._cards.all(func(c): return c.modulate.a == 1.0) and es._again.modulate.a == 1.0, "then all four cards and both buttons show")
	check(es.buttons().all(func(b): return _button_fits(b)) and es._again.text == Text.t("BTN_PLAY_AGAIN") and es._menu.text == Text.t("BTN_MAIN_MENU"), "Play again / Main menu fit their buttons")
	es._menu.pressed.emit()
	await frames(5)
	var ts := main._menu as TitleScreen
	check(main.state == "title" and ts != null, "Main menu goes to the title")
	check(not ts._continue_btn.visible and ts._finished.visible and ts._start_btn.text == Text.t("BTN_START") and ts._chapters.all(func(b): return b.visible and not b.disabled), "a finished game: a Finished mark, no Continue, every phase open")
	# Enter on the end screen is the main menu too (not a new game from the start).
	main._go_end()
	await frames(3)
	es = main._menu as EndScreen
	es.skip_intro()
	_key(KEY_ENTER, true)
	await frames(2)
	_key(KEY_ENTER, false)
	await frames(5)
	check(main.state == "title" and main.forest == null, "Enter on the end screen goes to the main menu")
	# Play again is the second button: a new game from the forest.
	main._go_end()
	await frames(3)
	es = main._menu as EndScreen
	es.skip_intro()
	es._again.pressed.emit()
	await frames(5)
	check(main.state == "intro" and main.forest != null, "Play again starts a new game")
	main._quit_to_title()
	await frames(3)

	step("the title: Continue and the phases")
	# A phase from the picker: the PMS maze from its start.
	ts = main._menu as TitleScreen
	ts._chapters[3].pressed.emit()
	var pick_ok := await until(func(): return main.state == "platformer" and main.platformer != null and main.platformer.is_pms(), 6)
	check(pick_ok, "the phase picker starts the PMS maze")
	main._quit_to_title()
	await frames(3)
	# Saves of different places: Continue starts each at its level and checkpoint.
	Game.save = {"language": "en", "chapter": 1, "checkpoint": 3, "iron": 9, "reached": 1}
	Game.write_save()
	Game.save = {}
	Game.load_save()
	main._go_title()
	await frames(3)
	ts = main._menu as TitleScreen
	check(ts.can_continue() and ts._continue_btn.visible and ts._start_btn.text == Text.t("BTN_NEW_GAME") and not ts._finished.visible, "with a save: Continue above New game")
	check(not ts._chapters[0].disabled and ts._chapters[1].disabled and ts._chapters[3].disabled and ts._continue_btn.position.y + ts._continue_btn.size.y <= ts._start_btn.position.y and ts._logo.position.y + ts._logo.size.y <= ts._continue_btn.position.y + 1, "only the phases reached are open; Continue sits between the logo and New game")
	ts._chapters[2].pressed.emit()
	await frames(3)
	check(main.state == "title", "a locked phase does nothing")
	ts._continue_btn.pressed.emit()
	var c1 := await until(func(): return main.state == "platformer" and main.platformer != null and Game.level == 1, 6)
	await frames(3)
	check(c1 and Game.checkpoint == 3 and Game.cave_checkpoint == 3 and Game.iron == 9 and Game.has_breathing and main.platformer._start_checkpoint == 3 and not PhaseBoard.showing(main.platformer.phase_note), "Continue: the cave at checkpoint 3 with the saved iron")
	main._quit_to_title()
	await frames(3)
	Game.save = {"chapter": 1, "checkpoint": 5, "iron": 14, "reached": 1}
	(main._menu as TitleScreen).continue_pressed.emit()
	var c1b := await until(func(): return main.state == "platformer" and main.platformer != null and main.platformer.boss.active, 8)
	check(c1b and Game.checkpoint == 5 and Game.boss_iron == 14, "Continue: the boss fight with the saved iron")
	main._quit_to_title()
	await frames(3)
	Game.save = {"chapter": 2, "checkpoint": 2, "reached": 2}
	_key(KEY_ENTER, true)
	await frames(2)
	_key(KEY_ENTER, false)
	var c2 := await until(func(): return main.state == "runner" and main.runner != null, 6)
	await frames(3)
	check(c2 and main.runner.stage == 2 and main.runner.sun == 2 * ForestRunner.SUN_PER_GAME, "Continue (Enter): the forest run at stage 3 with its sun pieces")
	main._quit_to_title()
	await frames(3)
	Game.save = {"chapter": 3, "checkpoint": 3, "reached": 3}
	(main._menu as TitleScreen).continue_pressed.emit()
	# (The title stays during the fade: a second press, or New game, does nothing more.)
	(main._menu as TitleScreen).continue_pressed.emit()
	(main._menu as TitleScreen).start_pressed.emit()
	await frames(2)
	check(main.state == "title" and main._title_locked and Game.saved_chapter() == 3, "a start from the title locks it: New game during the fade does nothing")
	var c3 := await until(func(): return main.state == "platformer" and main.platformer != null and main.platformer.is_climb(), 6)
	await frames(3)
	check(c3 and Game.checkpoint == 3 and main.platformer._start_checkpoint == 3, "Continue: the jackpot climb at its 2nd jackpot row")
	check(str(main.platformer.phase_note.get("key", "")) == "CLIMB_PHASE_NEW", "a climb started from the title announces its phase on the board")
	check(not main._title_locked, "the title's lock goes with the title")
	main._quit_to_title()
	await frames(3)
	Game.save = {"chapter": 4, "checkpoint": 1, "reached": 4}
	(main._menu as TitleScreen).continue_pressed.emit()
	var c4 := await until(func(): return main.state == "platformer" and main.platformer != null and main.platformer.is_pms(), 6)
	check(c4, "Continue: the PMS maze")
	main._quit_to_title()
	await frames(3)
	# New game is a new playthrough: its place is saved from now on (the old Continue place
	# goes), the language and the phases reached stay.
	Game.save = {"language": "en", "chapter": 3, "checkpoint": 3, "iron": 4, "reached": 3}
	(main._menu as TitleScreen).start_pressed.emit()
	await frames(5)
	check(main.state == "intro" and not Game.has_progress() and Game.reached_chapter() == 3 and Game.save.get("language") == "en", "New game starts from the forest: a new playthrough, the phases reached and the language stay")
	check(Game.progress(1, 2, 5) and Game.saved_chapter() == 1 and Game.saved_checkpoint() == 2 and Game.reached_chapter() == 3, "the new playthrough saves its own place")
	main._quit_to_title()
	await frames(3)
	# A phase from the picker is a new playthrough from that phase.
	Game.save = {"chapter": 3, "checkpoint": 3, "reached": 3}
	(main._menu as TitleScreen)._chapters[0].pressed.emit()
	var p1 := await until(func(): return main.state == "platformer" and main.platformer != null and Game.level == 1, 6)
	check(p1 and Game.saved_chapter() == 1 and Game.saved_checkpoint() == 1 and Game.reached_chapter() == 3, "a phase from the picker starts a new playthrough there")
	main._quit_to_title()
	await frames(3)
	# Developer shortcuts don't touch the save.
	Game.save = {"chapter": 1, "checkpoint": 1, "reached": 1}
	main._dev_action("checkpoint6", 1)
	await until(func(): return main.state == "platformer" and main.platformer != null and main.platformer.is_pms(), 6)
	check(Game.saved_chapter() == 1 and Game.reached_chapter() == 1, "a developer shortcut doesn't move the save")
	main._quit_to_title()
	await frames(3)
	# (Web ?run=hit, a shortcut that doesn't go through _dev_action.)
	Game.save = {"chapter": 1, "checkpoint": 1, "reached": 1}
	main._dev_runner_hits()
	await until(func(): return main.state == "runner" and main.runner != null, 6)
	check(Game.saved_chapter() == 1 and Game.reached_chapter() == 1 and main._no_save, "the web shortcut ?run=hit doesn't move the save")
	main._quit_to_title()
	await frames(3)
	# A preview save (?title=continue / ?title=finished) is never written.
	Game.save = {"chapter": 1, "checkpoint": 1, "reached": 1}
	Game.write_save()
	Game.save_readonly = true
	Game.save.merge({"finished": true, "reached": Game.CHAPTERS}, true)
	Game.save_set("muted", true)
	Game.save_readonly = false
	Game.load_save()
	check(not Game.is_finished() and Game.reached_chapter() == 1 and not Game.save.has("muted"), "a read-only (preview) save is not written")
	Game.save = {}
	DirAccess.remove_absolute(Game.save_path)


## The maze's light is her energy: it drains (slower standing still), the radius follows it,
## rest (hold the ability) refills it and keeps her put; the
## gauge top-right is wrong in its foggy spells (explained once) and right outside them.
func _pms_light(pf: Platformer, events: Array) -> void:
	pf.fog_wait = 999.0
	pf.fog_t = 0.0
	pf.p.vx = 0
	await until(func(): return pf.p.is_grounded, 3)
	pf.pms_light = 1.0
	await frames(30)
	_check_labels(pf.hud.labels, ["HUD_LBL_COMFORT", "HUD_LBL_ENERGY"], "PMS maze")
	check(pf.hud.hint_lines().is_empty(), "full energy: no ability hint %s" % str(pf.hud.hint_lines()))
	check(pf.fog_k() == 0.0 and pf.gauge() == pf.pms_light, "outside a foggy spell the gauge tells the truth")
	# Draining: slowly standing still, faster moving.
	var e0 := pf.pms_light
	await seconds(1.0)
	var still := e0 - pf.pms_light
	e0 = pf.pms_light
	for dir in ["move_right", "move_left"]:
		Input.action_press(dir)
		await seconds(0.5)
		Input.action_release(dir)
	var moved := e0 - pf.pms_light
	check(still > 0.0 and moved > still * 3 and moved > Platformer.LIGHT_DRAIN * 0.8 and moved < Platformer.LIGHT_DRAIN * 1.3, "her energy drains while she moves (%.4f in 1 s), much slower standing still (%.4f)" % [moved, still])
	check(1.0 / Platformer.LIGHT_DRAIN >= 45.0 and 1.0 / Platformer.LIGHT_DRAIN <= 60.0, "full → spent in 45–60 s of play")
	# The radius follows the energy; the lantern raises it; never no light.
	pf.p.vx = 0
	await seconds(1.5)
	var r_full := pf.light_r
	var sway_full := pf.tired_k()
	pf.pms_light = 0.1
	await seconds(2.5)
	var r_low := pf.light_r
	check(pf.has_lantern and absf(r_full - pf.light_for(1.0)) < 12 and absf(r_low - pf.light_for(pf.pms_light)) < 4 and r_low < r_full - 100, "her light's radius follows the energy (%d → %d px)" % [r_full, r_low])
	check(pf.light_for(0.0) == Platformer.LANTERN_MIN and Platformer.LIGHT_MIN == 0.0 and Platformer.LIGHT_R == 0.0, "with the lantern a small glow always stays (%d px); without it she gives no light (%d)" % [Platformer.LANTERN_MIN, Platformer.LIGHT_MIN])
	pf.has_lantern = false
	var plain_full := pf.light_for(1.0)
	var plain_low := pf.light_for(0.1)
	pf.has_lantern = true
	check(plain_full == Platformer.LIGHT_R and pf.light_for(1.0) == Platformer.LANTERN_R and pf.light_for(1.0) > plain_full + 90 and pf.light_for(0.1) > plain_low, "the lantern raises the light at every energy")
	check(pf.tired_k() > sway_full + 0.3, "tired, the world sways a bit more (%.2f → %.2f)" % [sway_full, pf.tired_k()])
	check(pf.hud.hint_lines() == ["HINT_PMS_REST"], "low energy: the hint to rest %s" % str(pf.hud.hint_lines()))
	var x0 := pf.p.x
	var e_low := pf.pms_light
	Input.action_press("breathe")
	await frames(8)
	check(pf.resting and pf.p.is_sitting and not pf.rest_filling() and pf.pms_light <= e_low, "holding the ability she sits down to rest; nothing refills in the first %.1f s" % Platformer.REST_DELAY)
	Input.action_press("move_right")
	var jump := InputEventAction.new()
	jump.action = "jump"
	jump.pressed = true
	pf._unhandled_input(jump)
	await seconds(3.2)
	Input.action_release("move_right")
	check(absf(pf.p.x - x0) < 1.0 and pf.p.is_grounded and pf.p.vy == 0.0, "she can't walk or jump while she rests (%.1f → %.1f)" % [x0, pf.p.x])
	check(pf.pms_light > e_low + Platformer.REST_FILL * 2.0 and pf.light_r > r_low + 25, "rest refills her energy and the light grows (%.2f → %.2f, %d → %d px)" % [e_low, pf.pms_light, r_low, pf.light_r])
	check(pf.rest_k > 0.95, "… and the maze calms while she rests (%.2f)" % pf.rest_k)
	check(pf.hud.hint_lines() == ["HINT_PMS_RESTING"], "while resting: the resting hint with the energy as its bar %s" % str(pf.hud.hint_lines()))
	pf.pms_light = 0.97
	await seconds(0.5)
	check(pf.pms_light == 1.0 and pf.resting, "rest fills the energy to full")
	Input.action_release("breathe")
	await frames(40)
	check(not pf.resting and not pf.p.is_sitting and pf.hud.hint_lines().is_empty(), "letting go ends the rest (no hint at full energy) %s" % str(pf.hud.hint_lines()))
	Input.action_press("move_right")
	await frames(15)
	Input.action_release("move_right")
	check(pf.p.x > x0 + 10, "… and she walks again")
	# The gauge: its first foggy spell is explained (once), the spell goes on after it.
	pf.pms_light = 0.8
	pf.p.vx = 0
	events.clear()
	pf.fog_wait = 0.2
	var fogged := await until(func(): return events.has("pms_fog"), 3)
	check(fogged and pf.fog_t > 0 and pf.fog_told and not pf.fog_explained, "the gauge's first foggy spell starts; it only counts as explained once 4H is read")
	await until(func(): return node_box().node_id() == PmsMaze.FOG_DIALOG, 2)
	await frames(3)
	var fog_at := pf.fog_t
	var e_at := pf.pms_light
	await seconds(0.6)
	check(pf.dialog_open and pf.fog_t == fog_at and pf.pms_light == e_at and not pf.fog_explained, "the spell and the energy wait while 4H is open (%.2f s left, energy %.3f)" % [pf.fog_t, pf.pms_light])
	await finish_dialog(PmsMaze.FOG_DIALOG)
	check(pf.fog_explained, "4H closed: the gauge is explained")
	check(Text.dialogs[PmsMaze.FOG_DIALOG].parts[0].speaker == "Progesteronka", "%s: Progesterónka explains the unreliable gauge" % PmsMaze.FOG_DIALOG)
	await seconds(0.8)
	check(pf.fog_k() == 1.0 and absf(pf.gauge() - pf.pms_light) > 0.15, "in a foggy spell the gauge is wrong (shows %.2f, the energy is %.2f)" % [pf.gauge(), pf.pms_light])
	var cleared := await until(func(): return pf.fog_t == 0.0, Platformer.FOG_LEN.y + 1)
	check(cleared and pf.gauge() == pf.pms_light and pf.fog_wait >= Platformer.FOG_GAP.x and pf.fog_wait <= Platformer.FOG_GAP.y, "after the spell the gauge is right again; the next comes in %.1f s" % pf.fog_wait)
	pf.fog_wait = 0.1
	var again := await until(func(): return pf.fog_t > 0, 2)
	await frames(20)
	check(again and events.count("pms_fog") == 1 and not node_box().is_open(), "later spells are not explained again")
	for mode in Platformer.FOG_MODES:
		pf.start_fog(mode, 3.0)
		var worst := 0.0
		var seen: Array = []
		for i in 60:
			await frames(1)
			if pf.fog_k() == 1.0:
				worst = maxf(worst, absf(pf.gauge() - pf.pms_light))
				if not seen.has(snappedf(pf.gauge(), 0.01)):
					seen.append(snappedf(pf.gauge(), 0.01))
		check(worst > 0.1 and (mode != "freeze" or seen.size() == 1) and (mode != "jitter" or seen.size() > 2), "a '%s' spell: the gauge is off by %.2f (%d values)" % [mode, worst, seen.size()])
	pf.fog_t = 0.0
	pf.fog_wait = 999.0
	check(pf.gauge() == pf.pms_light, "… and right again when it ends")
	check(events.count("pms_fog") == 1, "the gauge was explained once")
	await _pms_light_edges(pf, events)
	pf.pms_light = 1.0
	pf.tired = 0.0


## The maze's light, the edge cases: the rest hint only where resting works, Shift in the air,
## losing the ground, a dialog while resting, the gauge's explanation replaced by another
## dialog or due while she is in the air, the sway not snapping when the energy jumps.
func _pms_light_edges(pf: Platformer, events: Array) -> void:
	var jump := InputEventAction.new()
	jump.action = "jump"
	jump.pressed = true
	pf.fog_t = 0.0
	pf.fog_wait = 999.0
	pf.p.vx = 0
	await until(func(): return pf.p.is_grounded, 3)
	# The rest hint: only once the light is visibly small, and only on the ground.
	pf.pms_light = Platformer.REST_HINT + 0.1
	await frames(40)
	check(pf.hud.hint_lines().is_empty(), "above %.2f energy: no rest hint yet %s" % [Platformer.REST_HINT, str(pf.hud.hint_lines())])
	pf.pms_light = 0.3
	await frames(20)
	check(pf.hud.hint_lines() == ["HINT_PMS_REST"], "a small light, on the ground: the hint to rest %s" % str(pf.hud.hint_lines()))
	# Shift held in the air does nothing (and the hint doesn't promise it) until she lands.
	pf._unhandled_input(jump)
	await frames(3)
	Input.action_press("breathe")
	var air := 0
	var rested_in_air := false
	var hinted_in_air := false
	for i in 240:
		await frames(1)
		if pf.p.is_grounded:
			break
		air += 1
		rested_in_air = rested_in_air or pf.resting or pf.p.is_sitting
		hinted_in_air = hinted_in_air or not pf.hud._wanted_hints().is_empty()
	check(air > 10 and not rested_in_air, "the ability held in the air doesn't rest (%d frames in the air)" % air)
	check(not hinted_in_air, "… and no rest hint in the air, where it can't be used")
	var landed := await until(func(): return pf.resting, 2)
	check(landed and pf.p.is_grounded, "… she sits down to rest when she lands")
	await seconds(Platformer.REST_DELAY + 0.3)
	check(pf.rest_filling() and pf.pms_light > 0.3, "(resting: the energy comes back, %.2f)" % pf.pms_light)
	# Losing the ground ends the rest.
	pf.p.y -= 40
	pf.p.is_grounded = false
	await frames(2)
	check(not pf.p.is_grounded and not pf.resting and not pf.rest_filling(), "losing the ground ends the rest")
	var again := await until(func(): return pf.resting, 2)
	check(again, "(still held: she rests again on landing)")
	await seconds(Platformer.REST_DELAY + 0.2)
	# A dialog ends the rest; neither the energy nor a foggy spell moves while it is open.
	pf.start_fog("drift", 4.0)
	await frames(10)
	main._dialog(PmsMaze.LANTERN_DIALOG)
	await frames(3)
	var e0 := pf.pms_light
	var f0 := pf.fog_t
	await seconds(1.0)
	check(pf.dialog_open and not pf.resting and not pf.rest_filling(), "a dialog ends the rest (the ability still held)")
	check(pf.pms_light == e0 and pf.fog_t == f0 and f0 > 0, "in a dialog the energy neither drains nor refills and the foggy spell waits (%.3f, %.2f s)" % [pf.pms_light, pf.fog_t])
	check(pf.hud.hint_lines().is_empty() or pf.hud._wanted_hints().is_empty(), "no ability hint in a dialog")
	Input.action_release("breathe")
	await finish_dialog(PmsMaze.LANTERN_DIALOG)
	await frames(5)
	check(not pf.resting and events.count("pms_fog") == 1, "after the dialog she is up again (the ability let go)")
	pf.fog_t = 0.0
	# The gauge's explanation replaced by another dialog before it was read: it comes again.
	pf.fog_told = false
	pf.fog_explained = false
	pf.pms_light = 0.8
	events.clear()
	pf.fog_wait = 0.1
	await until(func(): return node_box().node_id() == PmsMaze.FOG_DIALOG, 4)
	check(events.count("pms_fog") == 1 and pf.fog_told and pf.fog_count > 0 and pf.fog_mode == "drift", "(the first spell again: 4H opens)")
	main._dialog(PmsMaze.LANTERN_DIALOG)
	await finish_dialog(PmsMaze.LANTERN_DIALOG)
	check(not pf.fog_explained and not node_box().is_open(), "another dialog took 4H's place: the gauge is not explained yet")
	var retold := await until(func(): return events.count("pms_fog") == 2, Platformer.FOG_RETELL + Platformer.FOG_TELL + 2.0)
	check(retold and not pf.fog_explained, "… so the first spell and its explanation come again")
	await finish_dialog(PmsMaze.FOG_DIALOG)
	check(pf.fog_explained, "… and reading 4H to its end explains it")
	await seconds(0.6)
	check(events.count("pms_fog") == 2 and pf.fog_told, "… once")
	# The explanation waits for her to land (a dialog opening mid-jump is easily lost).
	pf.fog_t = 0.0
	pf.fog_told = false
	pf.fog_explained = false
	events.clear()
	pf.start_fog("", 5.0)
	await seconds(Platformer.FOG_TELL - 0.25)
	pf._unhandled_input(jump)
	var due_in_air := false
	var told_in_air := false
	for i in 300:
		await frames(1)
		var due: bool = pf.fog_len - pf.fog_t >= Platformer.FOG_TELL
		if events.has("pms_fog"):
			told_in_air = not pf.p.is_grounded
			break
		due_in_air = due_in_air or (due and not pf.p.is_grounded)
	check(due_in_air and events.has("pms_fog") and not told_in_air, "the explanation waits until she stands on the ground")
	await finish_dialog(PmsMaze.FOG_DIALOG)
	check(pf.fog_explained and events.count("pms_fog") == 1, "(explained)")
	# … and not right beside something to pick up (its dialog would take 4H's place).
	var spot := Vector2(pf.p.x, pf.p.y)
	var item: LevelData.Ent = null
	for e in pf.level.entities:
		if e.type == "comfort" and not e.collected:
			item = e
			break
	check(not pf._near_pickup(), "(nothing to pick up beside her)")
	if item != null:
		pf.p.x = item.x + item.w + 30
		pf.p.y = item.y + item.h - pf.p.height
		check(pf._near_pickup(), "beside a comfort item the explanation would wait")
		pf.p.x = spot.x
		pf.p.y = spot.y
	pf.fog_t = 0.0
	pf.fog_wait = 999.0
	# The sway follows the energy smoothly: a pickup's refill doesn't snap the view.
	pf.pms_light = 0.02
	await seconds(2.5)
	var k_low := pf.tired_k()
	pf.pms_light = 1.0
	await frames(1)
	var step_k := absf(pf.tired_k() - k_low)
	await seconds(2.5)
	check(k_low > 1.4 and step_k < 0.05 and pf.tired_k() < 1.02, "the sway eases when the energy jumps (%.2f, %.3f in one frame, then %.2f)" % [k_low, step_k, pf.tired_k()])


## The dark maze: the light follows her on screen (the rotated view), no firefly, the lantern
## glimmers at the end of the spawn corridor and is the first thing she walks into, it makes
## her light bigger; comfort items glimmer only when she is near.
func _pms_dark(pf: Platformer) -> void:
	await frames(2)
	var ls := pf.dark_lights()
	var sc := pf.screen_of(pf.p.center())
	var upright := Vector2(Platformer.W, Platformer.H) - (pf.p.center() - Vector2(pf.camera_x, pf.camera_y))
	check(pf._dark.visible and ls.size() >= 2 and Vector2(ls[0].x, ls[0].y).distance_to(sc) < 1.0 and sc.distance_to(upright) < 30, "the maze is dark, lit round Kyra where she is on the rotated screen %s (≈ %s)" % [sc, upright])
	var ff_left := false
	for prop in pf.get_property_list():
		var pn: String = prop.name
		ff_left = ff_left or pn.begins_with("ff_") or pn.find("firefly") >= 0 or pn == "_ff_node"
	check(not ff_left and not pf.has_method("firefly_guide") and not pf.has_method("_update_firefly"), "there is no firefly in the maze any more (no state, no guiding)")
	Input.action_press("move_left")
	await frames(25)
	Input.action_release("move_left")
	await frames(2)
	var sc2 := pf.screen_of(pf.p.center())
	check(Vector2(pf.dark_lights()[0].x, pf.dark_lights()[0].y).distance_to(sc2) < 1.0 and sc2.x > sc.x + 10, "her light follows her on screen (left in the world = right on screen: %d → %d)" % [sc.x, sc2.x])
	# The lantern glimmers down the corridor from the start, on screen, outside her own light.
	var lantern: LevelData.Ent = null
	var items: Array[LevelData.Ent] = []
	for e in pf.level.entities:
		if e.type == "lantern":
			lantern = e
		elif e.type == "comfort":
			items.append(e)
	ls = pf.dark_lights()
	var lsc := pf.screen_of(lantern.rect().get_center())
	var glim := ls.size() == 2 and Vector2(ls[1].x, ls[1].y).distance_to(lsc) < 1.0 and ls[1].z >= 45.0
	var on_screen := Rect2(40, 40, Platformer.W - 80, Platformer.H - 80).has_point(lsc)
	check(glim and on_screen and lsc.distance_to(sc2) > pf.light_radius() + ls[1].z * 0.5, "the lantern glimmers down the spawn corridor, on screen and beyond her own light (%s, %d px away, glimmer %d px)" % [lsc, lsc.distance_to(sc2), ls[1].z if ls.size() > 1 else 0.0])
	check(items.size() == 3 and items.all(func(e): return pf.item_glimmer(e) == 0.0), "only the lantern glimmers until she has it (no comfort item yet)")
	# A running jump towards the wall behind it can't carry her over it: from each of the
	# cells before it (single and double jumps) she still ends up with the lantern.
	var r0 := pf.light_r
	var home := Vector2(pf.p.x, pf.p.y)
	var reach := pf.lantern_reach(lantern)
	check(reach.size.y >= LevelData.ROW_H * 2 - 10 and reach.position.y == LevelData.ROW_H and reach.size.x >= LevelData.CELL_W - 1 and reach.end.y == lantern.y + lantern.h, "the lantern is taken anywhere in its column, floor to ceiling (%s)" % reach)
	var lcol := int(lantern.rect().get_center().x / LevelData.CELL_W)
	var jumped_over := ""
	var highest := 0.0
	for variant in [[4, 0], [3, 0], [2, 0], [1, 0], [4, 14], [3, 16], [2, 12], [5, 22]]:
		lantern.collected = false
		pf.has_lantern = false
		pf.p.x = (lcol - 7) * LevelData.CELL_W
		pf.p.y = home.y
		pf.p.vx = 0
		pf.p.vy = 0
		var jump_x: float = (lcol - int(variant[0])) * LevelData.CELL_W
		Input.action_press("move_right")
		await until(func(): return pf.p.x >= jump_x or pf.has_lantern, 3)
		var jump_ev := InputEventAction.new()
		jump_ev.action = "jump"
		jump_ev.pressed = true
		var y_jump: float = pf.p.y
		pf._unhandled_input(jump_ev)
		if int(variant[1]) > 0:
			await frames(int(variant[1]))
			pf._unhandled_input(jump_ev)
		var top := [pf.p.y]
		await until(func(): top[0] = minf(top[0], pf.p.y); return pf.has_lantern or pf.p.x > lantern.x + LevelData.CELL_W * 4, 3)
		highest = maxf(highest, y_jump - top[0])
		Input.action_release("move_right")
		if not pf.has_lantern:
			jumped_over += " %s" % str(variant)
		if pf.has_lantern:
			await finish_dialog(PmsMaze.LANTERN_DIALOG)
		await frames(2)
	check(jumped_over == "" and highest > 46.0, "a running jump before the lantern never flies over it (taken up to %d px above the floor)%s" % [highest, jumped_over])
	# Past the corridor without it (an edited map), the items glimmer all the same.
	lantern.collected = false
	pf.has_lantern = false
	var gy := pf.p.y
	var gx := pf.p.x
	pf.p.x = items[0].rect().get_center().x + 60
	pf.p.y = items[0].y
	var past: float = pf.item_glimmer(items[0])
	pf.p.x = gx
	pf.p.y = gy
	check(past == 1.0, "below the spawn corridor the items glimmer even without the lantern (%.2f)" % past)
	pf.p.x = home.x
	pf.p.y = home.y
	pf.p.vx = 0
	pf.p.vy = 0
	await frames(3)
	check(items.all(func(e): return pf.item_glimmer(e) == 0.0), "… but not while she is still in the corridor")
	# She just walks along the corridor (no jump) and picks it up first.
	Input.action_press("move_right")
	var lit := await until(func(): return node_box().node_id() == PmsMaze.LANTERN_DIALOG, 6)
	Input.action_release("move_right")
	check(lit and pf.has_lantern and lantern.collected and pf.pms_items == 0, "walking along the corridor she picks the lantern up first (%s)" % PmsMaze.LANTERN_DIALOG)
	await finish_dialog(PmsMaze.LANTERN_DIALOG)
	await seconds(1.5)
	check(pf.light_r > r0 + 90 and pf.light_radius() > Platformer.LIGHT_R + 90, "the lantern makes her light bigger (%d → %d px)" % [r0, pf.light_r])
	check(pf.dark_lights().size() == 1, "no glimmer where the lantern lay")
	# Comfort items still to find glimmer when she is near (nearest first, ≤ 4 holes), not far.
	var it: LevelData.Ent = items[0]
	var ic := it.rect().get_center()
	pf.p.x = ic.x + Platformer.GLIMMER_NEAR * 0.6
	pf.p.y = ic.y - pf.p.height / 2
	ls = pf.dark_lights()
	var isc := pf.screen_of(ic)
	check(pf.item_glimmer(it) == 1.0 and ls.size() >= 2 and Vector2(ls[1].x, ls[1].y).distance_to(isc) < 1.0 and ls[1].z > Platformer.ITEM_GLIMMER * 0.8 and ls[1].z < pf.light_radius() * 0.5, "a comfort item nearby glimmers faintly in the dark (%d px)" % (ls[1].z if ls.size() > 1 else 0.0))
	pf.p.x = ic.x + (Platformer.GLIMMER_RANGE + Platformer.GLIMMER_NEAR) * 0.5
	var half := pf.item_glimmer(it)
	pf.p.x = ic.x + Platformer.GLIMMER_RANGE + 20
	check(half > 0.2 and half < 0.8 and pf.item_glimmer(it) == 0.0, "… fading out with the distance (%.2f half-way, none beyond %d px)" % [half, Platformer.GLIMMER_RANGE])
	pf.p.x = ic.x + 60
	it.collected = true
	check(pf.item_glimmer(it) == 0.0 and not pf.dark_lights().any(func(l: Vector3): return Vector2(l.x, l.y).distance_to(isc) < 1.0), "a found item doesn't glimmer")
	it.collected = false
	pf.door_open = 1.0
	var xs: Array[float] = []
	var ys: Array[float] = []
	for e in items:
		xs.append(e.x)
		ys.append(e.y)
		e.x = it.x + items.find(e) * 30.0
		e.y = it.y
	var crowd := pf.dark_lights()
	for i in items.size():
		items[i].x = xs[i]
		items[i].y = ys[i]
	check(crowd.size() == Platformer.DARK_HOLES and crowd[2].z >= crowd[3].z, "at most %d lights: Kyra, the open door, the nearest items" % Platformer.DARK_HOLES)
	pf.door_open = 0.0
	# On to the corridor below (where the rest of the maze is played from).
	pf.p.x = (19 + 0.5) * LevelData.CELL_W - pf.p.width / 2
	pf.p.y = 6 * pf.level.row_h - 6 - pf.p.height
	pf.p.vx = 0
	pf.p.vy = 0
	pf.camera_y = pf.pms_camera_clamp(pf.p.y - Platformer.H * Platformer.PMS_VIEW_Y)
	await until(func(): return pf.p.is_grounded, 3)


func _go_trigger(pf: Platformer, kind: String) -> void:
	for e in pf.level.entities:
		if e.type == "trigger" and e.trigger_type == kind:
			if pf.level.horizontal:
				# Column triggers: drop into the column from above the ground.
				pf.p.x = e.x + e.w / 2 - pf.p.width / 2
				pf.p.y = 240
				pf.camera_x = clampf(pf.p.x - 400, 0, pf.level_w - 1066)
			else:
				pf.p.x = pf.level_w / 2 - 15
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


## MeterModel (the run's water, the climb's hearts) on its own, at a steady 60 fps:
## pickups into the magazine first, then the reserve; spending; the reload (at once when
## empty, after RELOAD_DELAY when part-empty, unit by unit, postponed by spending).
func _meter_model_checks() -> void:
	var dt := 1.0 / 60.0
	var mm := MeterModel.new(4.0, 2.0, 0.0)
	var r := mm.fill(30.0)
	check(r.x > 0.29 and r.y == 0.0 and absf(mm.mag - 2.3) < 0.001 and mm.slot_flash > 0 and mm.slot_flash_i == 2, "MeterModel: a pickup fills the magazine's part-filled slot (it flashes)")
	r = mm.fill(200.0)
	check(mm.mag == 4.0 and absf(mm.reserve - 0.3) < 0.001 and mm.reserve_flash > 0, "MeterModel: past a full magazine the pickup goes to the reserve (it flashes)")
	check(not mm.spend(4.5) and mm.spend(4.0) and mm.mag == 0.0, "MeterModel: spending empties the magazine, never more than it holds")
	mm.reset(0.0, 4.0)
	mm.update(dt)
	check(mm.reloading and mm.flyers.size() == 1 and absf(mm.reserve - 3.0) < 0.001 and mm.mag == 0.0, "MeterModel: an empty magazine reloads at once, one unit leaves the reserve (still on its way)")
	var t := dt
	var first := -1.0
	var full := -1.0
	while t < 4.0 and full < 0:
		mm.update(dt)
		t += dt
		if first < 0 and mm.mag >= 1.0:
			first = t
		if mm.mag >= 4.0:
			full = t
	check(first > 0.3 and first < 0.5, "MeterModel: the unit lands in the magazine after its flight (%.2f s)" % first)
	check(full > 1.4 and full < 2.0 and mm.reserve < 0.001 and not mm.reloading, "MeterModel: a full reload takes time, unit by unit (%.2f s)" % full)
	mm.reset(4.0, 4.0)
	mm.spend(1.5)
	for i in 60:
		mm.update(dt)
	check(mm.mag == 2.5 and not mm.reloading and mm.flyers.is_empty(), "MeterModel: a part-empty magazine waits before reloading")
	mm.spend(0.5)
	for i in 60:
		mm.update(dt)
	check(mm.mag == 2.0 and mm.flyers.is_empty(), "MeterModel: spending during the wait postpones the reload")
	for i in 20:
		mm.update(dt)
	check(mm.reloading and mm.flyers.size() == 1 and int(mm.flyers[0].slot) == 2, "MeterModel: … then it reloads, into the first empty slot")
	for i in 120:
		mm.update(dt)
	check(mm.mag == 4.0 and absf(mm.reserve - 2.0) < 0.001, "MeterModel: two units moved from the reserve into the magazine")
	mm.reset(1.4, 3.0)
	mm.update(dt)
	check(mm.flyers.size() == 1 and absf(float(mm.flyers[0].amount) - 0.6) < 0.001 and int(mm.flyers[0].slot) == 1, "MeterModel: the part-filled slot is topped up first")
	mm.reset(2.0, 3.0)
	for i in 120:
		mm.update(dt)
		if not mm.flyers.is_empty():
			break
	var in_air := mm.flyers.size()
	mm.spend(1.0)
	for i in 30:
		mm.update(dt)
	check(in_air == 1 and not mm.reloading and mm.flyers.is_empty() and mm.mag == 2.0 and absf(mm.reserve - 2.0) < 0.001, "MeterModel: spending stops a part-empty reload, the unit in the air still lands (%.1f, %.1f)" % [mm.mag, mm.reserve])
	mm.reset(0.0, 4.0)
	for i in 30:
		mm.update(dt)
	mm.spend(1.0)
	mm.drain(0.2)
	check(mm.reloading and mm.reload_from_empty, "MeterModel: a reload from an empty magazine goes on while she spends (as in a shooter)")
	for i in 180:
		mm.update(dt)
	check(absf(mm.mag - 3.0) < 0.001 and mm.reserve < 0.001 and not mm.reloading, "MeterModel: … to the end: the whole reserve is in the magazine (%.2f)" % mm.mag)
	mm.reset(2.0, 0.0)
	mm.slot_flash = 0.0
	r = mm.fill(20.0, false)
	check(r.x > 0.19 and mm.slot_flash == 0.0 and mm.last_slot == 2, "MeterModel: fill(…, false) fills without its own flash (the caller flashes on arrival)")


## The HUD labels a level drew this frame: the expected keys, each under its indicator
## (not inside it), centred on it.
func _check_labels(labels: Array, keys: Array, level: String) -> void:
	var got: Array = labels.map(func(l): return l.key)
	check(got == keys, "%s: the HUD labels under the indicators %s" % [level, str(got)])
	var bad: Array = []
	for l in labels:
		var box: Rect2 = l.box
		var r: Rect2 = l.rect
		if r.position.y < box.end.y or absf(r.get_center().x - box.get_center().x) > 1.0 or r.size.x <= 0:
			bad.append("%s %s under %s" % [l.key, str(r), str(box)])
	check(bad.is_empty(), "%s: each label sits centred under its indicator %s" % [level, str(bad)])


## The HUD in every level (static layout, all languages): the labels fit under their
## indicators without touching the pills or the ability hints; the icons are centred in
## their pills (their drawn bounds against the pill, 1.5 px).
func _hud_layout() -> void:
	step("HUD labels and centred icons")
	var lang_was := Text.language
	var bad: Array = []
	var cave_pill := Rect2(1066 - 16 - PlatformerHud.PILL.x, 16, PlatformerHud.PILL.x, PlatformerHud.PILL.y)
	var heart_pill := Rect2(1066 - 16 - PlatformerHud.HEART_PILL.x, 16, PlatformerHud.HEART_PILL.x, PlatformerHud.HEART_PILL.y)
	# Every indicator: [label key, its box, the hint anchor under it (or none)].
	var sets := [
		["HUD_LBL_IRON", PlatformerHud.iron_box(), Vector2(-1, -1)],
		["HUD_LBL_BREATH", cave_pill, Vector2(cave_pill.end.x, Draw.label_bottom(cave_pill))],
		["HUD_LBL_SUN", ForestRunner.sun_box(), Vector2(-1, -1)],
		["HUD_LBL_WATER", ForestRunner.WATER_HUD, ForestRunner.hint_anchor()],
		["HUD_LBL_HEARTS", heart_pill, Vector2(heart_pill.end.x, Draw.label_bottom(heart_pill))],
		["HUD_LBL_COMFORT", PlatformerHud.PMS_SLOTS, Vector2(-1, -1)],
		["HUD_LBL_ENERGY", cave_pill, Vector2(cave_pill.end.x, Draw.label_bottom(cave_pill))],
	]
	for lang in ["sk", "en", "pt"]:
		Text.language = lang
		for st in sets:
			var key: String = st[0]
			var box: Rect2 = st[1]
			var anchor: Vector2 = st[2]
			var txt := Text.plain(Text.t(key))
			var r := Draw.label_rect(box, txt)
			if txt == "" or txt == key:
				bad.append("%s/%s missing" % [lang, key])
			# Under the box (a gap), centred, on the screen, not wider than the box + 40.
			if r.position.y < box.end.y + 1 or absf(r.get_center().x - box.get_center().x) > 0.5 or r.position.x < 2 or r.end.x > 1064 or r.size.x > box.size.x + 40:
				bad.append("%s/%s %s under %s" % [lang, key, str(r), str(box)])
			# The ability hints start under the label (AbilityHints.draw: anchor.y + 7).
			if anchor.x >= 0 and anchor.y + 7.0 - 6.0 < r.end.y:
				bad.append("%s/%s: hints at %.0f overlap the label (ends %.0f)" % [lang, key, anchor.y + 1.0, r.end.y])
	Text.language = lang_was
	# The forest run's stage ring at the top of the sun pulse stays above the sun's label.
	var ring_bottom := ForestRunner.SUN_HUD.y + ForestRunner.SUN_RING_R * ForestRunner.SUN_RING_PULSE + 1.5
	var sun_lbl := Draw.label_rect(ForestRunner.sun_box(), Text.plain(Text.t("HUD_LBL_SUN")))
	if ring_bottom >= sun_lbl.position.y:
		bad.append("the pulsed sun ring (to %.1f) runs into the label (from %.1f)" % [ring_bottom, sun_lbl.position.y])
	check(bad.is_empty(), "every HUD indicator has its label under it, clear of the pill and the hints, in sk / en / pt %s" % str(bad))
	# Icons centred: the drawn bounds of the slot row (both pills) against the pill.
	var off: Array = []
	var water := ForestRunner.WATER_HUD
	var drops := PackedVector2Array()
	for i in 4:
		var c := MeterHud.slot_center(water, i)
		drops.append_array(ForestRunner._drop_pts(MeterHud.drop_at(c, 1.05), 1.05))
	_centred(off, "water drops", Draw.bounds(drops), water)
	var hearts := PackedVector2Array()
	for i in Platformer.HEART_SLOTS:
		var c := MeterHud.slot_center(heart_pill, i, Platformer.HEART_SLOTS)
		# A full heart's ink: the polygon plus its outline (the point's spike below).
		var hb := Draw.bounds(PlatformerHud._heart_pts(MeterHud.heart_at(c, 12.0), 12.0))
		hearts.append(hb.position - Vector2(0, SpriteArt.HEART_INK_TOP * 12.0))
		hearts.append(hb.end + Vector2(0, SpriteArt.HEART_INK_BOTTOM * 12.0))
		var empty := Draw.bounds(PlatformerHud._heart_pts(MeterHud.heart_at(c, 11.0, false), 11.0))
		if absf(empty.get_center().y - heart_pill.get_center().y) > 1.0:
			off.append("an empty heart %.1f off" % (empty.get_center().y - heart_pill.get_center().y))
	_centred(off, "hearts", Draw.bounds(hearts), heart_pill)
	# The maze's energy gauge: the light + the bar as one row centred in its pill.
	var en := PlatformerHud.energy_layout(cave_pill)
	var en_icon: Vector2 = en.icon
	var en_bar: Rect2 = en.bar
	var en_row := Rect2(en_icon - Vector2.ONE * PlatformerHud.ENERGY_ICON_R, Vector2.ONE * PlatformerHud.ENERGY_ICON_R * 2).merge(en_bar)
	if absf(en_row.get_center().x - cave_pill.get_center().x) > 0.5 or absf(en_bar.get_center().y - cave_pill.get_center().y) > 0.5 or absf(en_icon.y - cave_pill.get_center().y) > 0.5 or en_row.position.x < cave_pill.position.x + 8:
		off.append("the energy gauge's row %s in %s" % [str(en_row), str(cave_pill)])
	# The reserve's badge: its icon + "+N" as one row centred in the badge.
	for n in [0, 3, 12]:
		var lay := MeterHud.badge_layout(water, n)
		var b := MeterHud.badge_rect(water)
		var left: float = lay.icon.x - MeterHud.BADGE_ICON_W / 2 - b.position.x
		var right: float = b.end.x - (float(lay.text_x) + float(lay.text_w))
		if absf(left - right) > 1.0 or absf(lay.icon.y - b.get_center().y) > 0.01:
			off.append("badge +%d: %.1f / %.1f" % [n, left, right])
	# The breath pill's rows (text + icon, the charges) centred.
	for items in [["t:SHIFT", "wind"], ["t:PUSH", "pad"], ["t:RELOAD", "pad"], ["t:SHIFT", "reload"], ["wind", "wind", "wind"]]:
		var row := PlatformerHud.icon_row_items(Text.font_bold, cave_pill.get_center(), items)
		var first: Dictionary = row[0]
		var last: Dictionary = row[row.size() - 1]
		var l: float = first.c.x - first.w / 2.0 - cave_pill.position.x
		var rr: float = cave_pill.end.x - (last.c.x + last.w / 2.0)
		if absf(l - rr) > 1.0:
			off.append("breath row %s: %.1f / %.1f" % [str(items), l, rr])
	# The maze's slots: centred in the panel, each item's drawn bounds centred in its slot.
	var sl := Rect2(PlatformerHud.pms_slot_center(0) - Vector2(21, 21), Vector2(42 * 3 + 20, 42))
	_centred(off, "PMS slots", sl, PlatformerHud.PMS_SLOTS)
	for i in 3:
		var kind: String = PmsMaze.ITEMS[i]
		var k := PlatformerHud.pms_item_scale(kind)
		var c := PlatformerHud.pms_slot_center(i)
		var at := c - PmsMaze.item_bounds(kind).get_center() * k
		var ib := Rect2(at + PmsMaze.item_bounds(kind).position * k, PmsMaze.item_bounds(kind).size * k)
		_centred(off, "PMS item " + kind, ib, Rect2(c - Vector2(21, 21), Vector2(42, 42)))
	# The spinner's symbols: a heart's / a bell's bounds on the card's centre.
	var hb := Draw.bounds(PlatformerHud._heart_pts(MeterHud.heart_at(Vector2(100, 100), 14.0), 14.0))
	var hmid := (hb.position.y - SpriteArt.HEART_INK_TOP * 14.0 + hb.end.y + SpriteArt.HEART_INK_BOTTOM * 14.0) / 2.0
	if absf(hmid - 100.0) > 1.0 or absf(hb.get_center().x - 100.0) > 1.0:
		off.append("spinner heart %.1f" % hmid)
	var bell_c := Vector2(100, 100) - Vector2(0, SpriteArt.bell_mid(13.0))
	var bell_top := bell_c.y - 13.0 * 1.4
	var bell_bottom := bell_c.y + 13.0 * 1.0
	if absf((bell_top + bell_bottom) / 2 - 100.0) > 1.0:
		off.append("spinner bell %.1f" % ((bell_top + bell_bottom) / 2))
	check(off.is_empty(), "the HUD's icons are centred in their pills (drops, hearts, the badge, the breath, the maze's items, the spinner) %s" % str(off))


func _centred(off: Array, what: String, b: Rect2, pill: Rect2) -> void:
	var dl := b.position.x - pill.position.x
	var dr := pill.end.x - b.end.x
	var dt := b.position.y - pill.position.y
	var db := pill.end.y - b.end.y
	if absf(dl - dr) > 1.5 or absf(dt - db) > 1.5 or dl < 0 or dt < 0:
		off.append("%s: left %.1f right %.1f top %.1f bottom %.1f" % [what, dl, dr, dt, db])
