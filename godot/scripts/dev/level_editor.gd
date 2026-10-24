class_name LevelEditor
extends Control
## In-game level editor (developer menu). Paints the same text format as
## data/levels/cave.txt, test-plays it with the real cave rules, and
## imports / exports text so a level can be pasted into the repo (or into a prompt).
##
## Mouse: left = paint, right = erase, wheel = scroll. Enter = test / back.

const CELL := 30.0
const SIDEBAR := 236.0
const AUTOSAVE := "user://custom_level.txt"

var rows: PackedStringArray = []
## Space reserved at the top (the developer menu's tab bar).
var top := 0.0
var tool := "="
var _grid: Control
var _scroll: ScrollContainer
var _toast: Label
var _toast_t := 0.0
var _painting := 0 # 0 none, 1 paint, 2 erase
var _test: Platformer
var _test_info: Label
var _import: Control
var _tool_buttons := {}
var _saved_state := {}


func _ready() -> void:
	size = Vector2(1066, 600)
	var bg := ColorRect.new()
	bg.color = Color("#0f172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_sidebar()
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(SIDEBAR + 20, top + 8)
	_scroll.size = Vector2(LevelData.COLS * CELL + 14, 600 - top - 16)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_grid_input)
	_scroll.add_child(_grid)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _grid.queue_redraw())
	_toast = UiKit.label("", 14, Color.WHITE, true)
	_toast.position = Vector2(SIDEBAR + 40, top + 14)
	_toast.visible = false
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color("#16a34a")
	tsb.set_corner_radius_all(6)
	tsb.content_margin_left = 14
	tsb.content_margin_right = 14
	tsb.content_margin_top = 8
	tsb.content_margin_bottom = 8
	_toast.add_theme_stylebox_override("normal", tsb)
	# Own layer so messages stay visible above the test play too.
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 34
	add_child(toast_layer)
	toast_layer.add_child(_toast)
	_load_initial()


func _load_initial() -> void:
	if FileAccess.file_exists(AUTOSAVE):
		var f := FileAccess.open(AUTOSAVE, FileAccess.READ)
		rows = LevelData.parse_text(f.get_as_text())
	if rows.is_empty():
		rows = Game.load_level_rows()
	_resize_grid()


func _resize_grid() -> void:
	_grid.custom_minimum_size = Vector2(LevelData.COLS * CELL, rows.size() * CELL)
	_grid.queue_redraw()


func _autosave() -> void:
	var f := FileAccess.open(AUTOSAVE, FileAccess.WRITE)
	if f:
		f.store_string(LevelData.to_text(rows))


func _toast_msg(s: String) -> void:
	_toast.text = s
	_toast.visible = true
	_toast_t = 3.0


# --- sidebar ------------------------------------------------------------------

func _build_sidebar() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.8)
	panel.position = Vector2(0, top)
	panel.size = Vector2(SIDEBAR, 600 - top)
	add_child(panel)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, top + 10)
	sc.size = Vector2(SIDEBAR - 14, 580 - top)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(SIDEBAR - 28, 0)
	box.add_theme_constant_override("separation", 6)
	sc.add_child(box)

	var test := UiKit.button("TEST LEVEL (ENTER)", Vector2(SIDEBAR - 28, 38), 12, Color("#059669"))
	test.pressed.connect(start_test)
	box.add_child(test)

	box.add_child(UiKit.label("TOOLS", 11, Color("#94a3b8"), true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var tools := [["=", "Platform"], ["O", "Iron"], ["^", "Spike"], ["P", "Spawn"],
		["S", "Cramp static"], ["F", "Cramp float"], ["J", "Cramp lunge"], ["C", "Cramp chase"],
		["2", "Choco puzzle"], ["3", "Pipes"], ["4", "Prices"], ["5", "Boss"],
		["T", "Teleport"], ["I", "Hint text"], [" ", "Eraser"]]
	for t in tools:
		var label: String = ("%s  %s" % [t[0], t[1]]) if t[0] != " " else t[1]
		var b := UiKit.button(label, Vector2((SIDEBAR - 34) / 2, 30), 10, Color("#1e293b"), Color("#cbd5e1"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_select_tool.bind(t[0]))
		grid.add_child(b)
		_tool_buttons[t[0]] = b

	box.add_child(UiKit.label("DIALOG TRIGGERS", 11, Color("#94a3b8"), true))
	var dlg := OptionButton.new()
	dlg.add_theme_font_size_override("font_size", 12)
	dlg.get_popup().add_theme_font_size_override("font_size", 12)
	for i in 24:
		var ch := char(97 + i)
		var target := Text.dialog_for_letter(ch)
		dlg.add_item("Dialog %s%s" % [ch.to_upper(), (" → " + target) if target != "" else ""])
	dlg.item_selected.connect(func(i): _select_tool(char(97 + i)))
	box.add_child(dlg)

	box.add_child(UiKit.label("LEVEL", 11, Color("#94a3b8"), true))
	for item in [
		["Use in game", _use_in_game], ["Back to bundled level", _use_bundled],
		["Load game level", _load_game_level], ["New empty level", _new_level],
		["Add 20 rows", _add_rows], ["Import…", _open_import], ["Export (copy + download)", _export],
	]:
		var b := UiKit.button(item[0], Vector2(SIDEBAR - 28, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
		b.pressed.connect(item[1])
		box.add_child(b)
	var help := UiKit.label("Left click paint · right click erase\nWheel scroll · Enter test/back\nAutosaved in this browser.", 10, Color("#64748b"))
	box.add_child(help)
	_select_tool("=")


func _select_tool(t: String) -> void:
	tool = t
	for k in _tool_buttons:
		var b: Button = _tool_buttons[k]
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		sb.bg_color = Color("#059669") if k == t else Color("#1e293b")
		b.add_theme_stylebox_override("normal", sb)


# --- painting -----------------------------------------------------------------

func _grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_painting = 2 if event.button_index == MOUSE_BUTTON_RIGHT else 1
				_paint_at(event.position)
			else:
				_painting = 0
				_autosave()
	elif event is InputEventMouseMotion and _painting > 0:
		_paint_at(event.position)


func _paint_at(pos: Vector2) -> void:
	var c := int(pos.x / CELL)
	var r := int(pos.y / CELL)
	if r < 0 or r >= rows.size() or c < 0 or c >= LevelData.COLS:
		return
	var ch := " " if _painting == 2 else tool
	if ch == "P":
		for i in rows.size():
			rows[i] = rows[i].replace("P", " ")
	var row := rows[r]
	if row[c] == ch:
		return
	rows[r] = row.substr(0, c) + ch + row.substr(c + 1)
	_grid.queue_redraw()


func _draw_grid() -> void:
	var ci := _grid
	var font: Font = Text.font_bold
	var top := _scroll.scroll_vertical
	var first := maxi(0, int(top / CELL) - 1)
	var last := mini(rows.size(), first + int(600 / CELL) + 3)
	var w := LevelData.COLS * CELL
	ci.draw_rect(Rect2(0, first * CELL, w, (last - first) * CELL), Color("#111827"))
	for r in range(first, last):
		var y := r * CELL
		ci.draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.12 if r % 4 == 0 else 0.05))
		var row := rows[r]
		for c in LevelData.COLS:
			var ch := row[c]
			var cell := Rect2(c * CELL, y, CELL, CELL)
			var mid := cell.get_center()
			match ch:
				" ":
					pass
				"=":
					ci.draw_rect(cell, Color("#94a3b8"))
				"O", "*":
					ci.draw_circle(mid, 8, Color("#facc15"))
				"^":
					ci.draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -10), mid + Vector2(10, 10), mid + Vector2(-10, 10)]), Color("#ef4444"))
				"S", "F", "J", "L", "C":
					ci.draw_rect(Rect2(mid - Vector2(12, 12), Vector2(24, 24)), Color("#ef4444"))
					Draw.text_center(ci, font, mid, ch, 12, Color.WHITE)
				"P":
					ci.draw_circle(mid, 12, Color("#22c55e"))
					Draw.text_center(ci, font, mid, "P", 12, Color.WHITE)
				"1", "2", "3", "4", "5", "B":
					ci.draw_rect(cell.grow(-1), Color("#581c87", 0.8))
					ci.draw_rect(cell.grow(-1), Color("#c084fc"), false, 1.0)
					Draw.text_center(ci, font, mid, ch, 12, Color.WHITE)
				_:
					ci.draw_rect(cell.grow(-1), Color("#1e3a8a", 0.8))
					ci.draw_rect(cell.grow(-1), Color("#60a5fa"), false, 1.0)
					Draw.text_center(ci, font, mid, ch.to_upper(), 12, Color.WHITE)
	for c in LevelData.COLS + 1:
		ci.draw_line(Vector2(c * CELL, first * CELL), Vector2(c * CELL, last * CELL), Color(1, 1, 1, 0.05))


# --- level actions -------------------------------------------------------------

func _use_in_game() -> void:
	Game.custom_level_rows = rows.duplicate()
	_toast_msg("This level is now used by the game (until reload).")


func _use_bundled() -> void:
	Game.custom_level_rows = PackedStringArray()
	_toast_msg("Game uses the bundled level again.")


func _load_game_level() -> void:
	rows = Game.load_level_rows()
	_resize_grid()
	_autosave()
	_toast_msg("Loaded data/levels/cave.txt")


func _new_level() -> void:
	rows = PackedStringArray()
	for i in 100:
		rows.append(" ".repeat(LevelData.COLS))
	rows[99] = "=".repeat(LevelData.COLS)
	_resize_grid()
	_autosave()


func _add_rows() -> void:
	for i in 20:
		rows.append(" ".repeat(LevelData.COLS))
	_resize_grid()
	_autosave()


func _export() -> void:
	var txt := LevelData.to_text(rows)
	DisplayServer.clipboard_set(txt)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(txt.to_utf8_buffer(), "cave.txt", "text/plain")
	_toast_msg("Level copied to clipboard%s!" % (" and downloaded" if OS.has_feature("web") else ""))


func _open_import() -> void:
	_import = Control.new()
	_import.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_import)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_import.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(233, 90)
	card.size = Vector2(600, 400)
	_import.add_child(card)
	var title := UiKit.label("Import level", 20, Color.WHITE, true)
	title.position = Vector2(20, 16)
	card.add_child(title)
	var hint := UiKit.label("Paste level text (rows, '.' = empty) or the web editor's JSON:", 12, Color("#94a3b8"))
	hint.position = Vector2(20, 52)
	card.add_child(hint)
	var te := TextEdit.new()
	te.position = Vector2(20, 76)
	te.size = Vector2(560, 250)
	te.add_theme_font_size_override("font_size", 12)
	card.add_child(te)
	var cancel := UiKit.button("Cancel", Vector2(120, 36), 12)
	cancel.position = Vector2(330, 344)
	cancel.pressed.connect(func(): _import.queue_free())
	card.add_child(cancel)
	var load_btn := UiKit.button("Load", Vector2(120, 36), 12, Color("#059669"))
	load_btn.position = Vector2(460, 344)
	load_btn.pressed.connect(func():
		var parsed := LevelData.parse_text(te.text)
		if parsed.is_empty():
			_toast_msg("Nothing to import.")
			return
		rows = parsed
		_resize_grid()
		_autosave()
		_import.queue_free()
		_toast_msg("Level successfully loaded!"))
	card.add_child(load_btn)
	te.grab_focus()


# --- test play ----------------------------------------------------------------

func start_test() -> void:
	if _test:
		return
	_saved_state = {"iron": Game.iron, "breath": Game.has_breathing, "cp": Game.checkpoint}
	Game.iron = 0
	Game.has_breathing = true
	Game.checkpoint = 0
	_test = Platformer.new()
	_test.hud_layer = 32
	_test.player_layer = 31
	_test.setup(rows, 0)
	_test.active = true
	_test.trigger.connect(_on_test_trigger)
	_test.boss_defeated.connect(func(): _toast_msg("Boss defeated!"))
	_test.boss_lost.connect(func(): _toast_msg("Boss lost — Enter to return"))
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.name = "TestLayer"
	add_child(layer)
	layer.add_child(_test)
	# Test-mode bar: clear feedback plus a way back for mouse users.
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 33
	layer.add_child(hud_layer)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.position = Vector2(0, 600 - 44)
	bar.size = Vector2(1066, 44)
	hud_layer.add_child(bar)
	_test_info = UiKit.label("TEST MODE  ·  arrows move, Up/Space jump, Ctrl breathe  ·  Enter or Esc = back", 13, Color.WHITE, true)
	_test_info.position = Vector2(200, 600 - 44)
	_test_info.size = Vector2(700, 44)
	_test_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_layer.add_child(_test_info)
	var back := UiKit.button("BACK TO EDITOR", Vector2(170, 32), 12, Color("#059669"))
	back.position = Vector2(12, 600 - 38)
	back.pressed.connect(stop_test)
	hud_layer.add_child(back)


func stop_test() -> void:
	if not _test:
		return
	Audio.stop_all_loops()
	Audio.set_bgm_volume(0.5)
	get_node("TestLayer").queue_free()
	_test = null
	Game.iron = _saved_state.iron
	Game.has_breathing = _saved_state.breath
	Game.checkpoint = _saved_state.cp


func _on_test_trigger(name: String) -> void:
	if name in ["white_fade", "first_enemy", "dialog_a"]:
		return
	if name.begins_with("game_over"):
		_toast_msg("Out of iron — restarting test")
		stop_test()
		start_test.call_deferred()
		return
	_toast_msg("Trigger: " + name)


func _unhandled_input(event: InputEvent) -> void:
	if _import:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if _test:
			stop_test()
		else:
			start_test()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and _test:
		stop_test()


func _process(delta: float) -> void:
	if _toast_t > 0:
		_toast_t -= delta
		if _toast_t <= 0:
			_toast.visible = false
	if _import and not is_instance_valid(_import):
		_import = null
