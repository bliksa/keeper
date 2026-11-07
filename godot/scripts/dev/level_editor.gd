class_name LevelEditor
extends Control
## In-game level editor (developer menu). Paints the same text format as
## data/levels/cave.txt, test-plays it with the real cave rules, and
## imports / exports text so a level can be pasted into the repo (or into a prompt).
##
## Mouse: left = paint, right = erase, wheel = scroll. Enter = test / back.
## Tools are grouped icon buttons on the left (a click opens the group's menu);
## level actions sit in the header. The grid fills the rest of the screen.

## Cells are as wide as the screen allows (25 columns next to the toolbar).
const CELL_W := 39.0
const CELL_H := 30.0
## Space below the last row that shows where the level ends.
const END_PAD := 96.0
## Same as the developer menu header height, so all toolbar icons line up.
const SIDEBAR := 48.0
const ICON := 36.0
const AUTOSAVE := "user://custom_level.txt"
## Autosave of the level being edited, per level id (1 cave, 2 garden).
const AUTOSAVE_FMT := "user://custom_level_%d.txt"
## Backgrounds being edited (level id -> BackgroundData config), kept in this browser.
const BG_AUTOSAVE := "user://backgrounds_edit.json"
## Background images bigger than this are scaled down when committed.
const BG_MAX_PX := 4096

var rows: PackedStringArray = []
## Which game level is being edited (Game.LEVELS).
var level_id := 1
var _level_pick: OptionButton
## Space reserved at the top (the developer menu's tab bar).
var top := 0.0
var tool := "="
var _grid: Control
var _scroll: ScrollContainer
var _toast: Label
var _toast_t := 0.0
var _painting := 0 # 0 none, 1 paint, 2 erase
var _test: Platformer
## Test play of the forest run map.
var _test_run: ForestRunner
var _test_info: Label
var _import: Control
var _saved_state := {}
## Edited backgrounds: "level id" -> config (only levels actually changed).
var bg_edit := {}
## Backgrounds committed from this browser: "level id" -> {"local": json of the
## edited config, "committed": json of what was committed (res:// paths)}.
var bg_saved := {}
## Untouched copies being looked at (not persisted until changed).
var _bg_view := {}
var bg_panel: BackgroundPanel


func _ready() -> void:
	size = Vector2(1066, 600)
	var bg := ColorRect.new()
	bg.color = Color("#0f172a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_sidebar()
	_scroll = ScrollContainer.new()
	# The grid fills everything right of the toolbar.
	_scroll.position = Vector2(SIDEBAR + 4, top)
	_scroll.size = Vector2(1066 - SIDEBAR - 4, 600 - top)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_grid_input)
	_scroll.add_child(_grid)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _grid.queue_redraw())
	# One wheel notch scrolls 4 rows (the level is ~300 rows tall).
	_scroll.get_v_scroll_bar().custom_step = CELL_H * 4
	_toast = UiKit.label("", 14, Color.WHITE, true)
	_toast.position = Vector2(SIDEBAR + 24, top + 12)
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
	_load_bg_edits()
	_load_initial()


func _autosave_path() -> String:
	# The cave keeps the old path so earlier autosaves still load.
	return AUTOSAVE if level_id == 1 else AUTOSAVE_FMT % level_id


func horizontal() -> bool:
	return Game.is_horizontal(level_id)


## Columns of the level being edited (horizontal levels are as long as their rows).
func cols() -> int:
	return rows[0].length() if horizontal() and rows.size() > 0 else Game.level_cols(level_id)


## The forest run's top-down map (few, wide cells; the start is at the bottom).
func is_runner() -> bool:
	return level_id == ForestRunner.LEVEL_ID


## Cell width on screen.
func cw() -> float:
	return 96.0 if is_runner() else CELL_W


## The level as text (the forest run keeps its legend as a header).
func _level_text() -> String:
	return (ForestRunner.MAP_HEADER if is_runner() else "") + LevelData.to_text(rows)


func _load_initial() -> void:
	rows = PackedStringArray()
	if FileAccess.file_exists(_autosave_path()):
		var f := FileAccess.open(_autosave_path(), FileAccess.READ)
		rows = LevelData.parse_text(f.get_as_text(), Game.level_cols(level_id))
		# An autosave of the wrong shape (e.g. from before the level changed orientation) is ignored.
		if not is_runner() and horizontal() != (rows.size() <= 16 and rows.size() > 0 and rows[0].length() > LevelData.COLS):
			rows = PackedStringArray()
	if rows.is_empty():
		rows = Game.level_rows(level_id)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal() else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_horizontal = 0
	_resize_grid()
	if is_runner():
		# The run starts at the bottom of the map.
		_scroll_to_start.call_deferred()


func _scroll_to_start() -> void:
	# The scroll range follows the grid's new size a frame later.
	for i in 2:
		await get_tree().process_frame
	if is_runner():
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _level_file() -> String:
	return String(Game.LEVELS[level_id]).get_file()


## Switch the editor to another game level (its own autosave).
func select_level(id: int) -> void:
	if id == level_id:
		return
	_autosave()
	level_id = id
	if _level_pick:
		_level_pick.select(Game.LEVELS.keys().find(id))
	_scroll.scroll_vertical = 0
	_load_initial()
	_refresh_dialog_tools()
	if bg_panel:
		# A browser opened for the previous level must not add to this one.
		bg_panel.close_browser()
		bg_panel.refresh()
	_toast_msg("Editing %s (%s)" % [Game.LEVEL_NAMES[id], _level_file()])


func _resize_grid() -> void:
	if horizontal():
		_grid.custom_minimum_size = Vector2(cols() * CELL_W + END_PAD, rows.size() * CELL_H)
	else:
		_grid.custom_minimum_size = Vector2(cols() * cw(), rows.size() * CELL_H + END_PAD)
	_grid.queue_redraw()


func _autosave() -> void:
	var f := FileAccess.open(_autosave_path(), FileAccess.WRITE)
	if f:
		f.store_string(_level_text())


func _toast_msg(s: String) -> void:
	_toast.text = s
	_toast.visible = true
	_toast_t = 3.0


# --- toolbars -----------------------------------------------------------------

## Tool groups (Photoshop-style): each toolbar button holds a group; clicking it
## uses its current tool and opens a menu with the group's other tools.
## Items: [level char, lucide icon, name]. Dialog letters are added to "events".
const GROUPS := [
	{"id": "platforms", "name": "Platforms", "items": [
		["=", "rectangle-horizontal", "Platform (=)"],
		["^", "triangle", "Spike (^)"],
	]},
	{"id": "enemies", "name": "Enemies", "items": [
		["S", "bug", "Cramp – static (S)"],
		["F", "ghost", "Cramp – floating (F)"],
		["J", "zap", "Cramp – lunging (J)"],
		["C", "footprints", "Cramp – chasing (C)"],
	]},
	{"id": "collectibles", "name": "Collectibles", "items": [
		["O", "hexagon", "Iron (O)"],
	]},
	{"id": "events", "name": "Event triggers", "items": [
		["2", "cookie", "Minigame: chocolate (2)"],
		["3", "droplets", "Minigame: pipes (3)"],
		["4", "euro", "Minigame: prices (4)"],
		["5", "skull", "Boss fight (5)"],
		["I", "lightbulb", "Hint text (I)"],
	]},
	{"id": "teleports", "name": "Spawn & teleports", "items": [
		["P", "map-pin", "Spawn point (P)"],
		["T", "arrow-up-to-line", "Teleport to top (T)"],
	]},
	{"id": "forest", "name": "Forest run (level 2)", "items": [
		["+", "sun", "Sun piece (+): 12 = the sun, every 4 a minigame"],
		["R", "sprout", "Root (R): jump over it"],
		["H", "rectangle-horizontal", "Branch (H): high, change path or double jump"],
		["V", "bird", "Flying notification (V): grabs her in the air"],
		["D", "droplets", "Water drop (D)"],
		["U", "arrow-up", "Water drop up high (U)"],
		["Y", "sparkles", "Light seed (Y)"],
		["<", "chevron-right", "Side trap from the left (<)"],
		[">", "chevron-left", "Side trap from the right (>)"],
		["A", "flag-triangle-right", "Next stage starts here (A): faster"],
	]},
	{"id": "meadow", "name": "Meadow (old level 2)", "items": [
		["#", "droplets", "River (#)"],
		["K", "brain", "Minigame: memory (K)"],
		["M", "cloud-lightning", "Minigame: catch (M)"],
		["Q", "link", "Minigame: pairs (Q)"],
		["G", "door-open", "Gate / level end (G)"],
	]},
	{"id": "garden", "name": "Summit (level 3)", "items": [
		["@", "circle", "Bubble platform (@)"],
		["%", "circle-dashed", "Popping bubble (%)"],
		["~", "wind", "Updraft (~)"],
		["N", "bell", "Distraction (N)"],
		["6", "utensils", "Minigame: iron plate (6)"],
		["7", "music", "Minigame: rhythm (7)"],
		["8", "calendar-heart", "Minigame: body signals (8)"],
		["9", "waves", "LH wave starts (9)"],
		["E", "flag", "Summit / level end (E)"],
	]},
	{"id": "eraser", "name": "Eraser", "items": [
		[" ", "eraser", "Eraser (or right click on the grid)"],
	]},
]
const ICONS := "res://assets/ui/icons/%s.svg"

## Optional header (the developer menu's top bar) for the level actions.
var header: HBoxContainer
var _test_button: Button
## The event group's tool list (its dialog letters change with the level).
var _events_items: Array = []
## group id -> {button, menu, current: [char, icon, name]}
var _groups := {}
## level char -> [char, icon, name, group id] for every tool
var _tool_info := {}


func _build_sidebar() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.55)
	panel.position = Vector2(0, top)
	panel.size = Vector2(SIDEBAR, 600 - top)
	add_child(panel)
	var col := VBoxContainer.new()
	col.position = Vector2((SIDEBAR - ICON) / 2, top + (SIDEBAR - ICON) / 2)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	for g in GROUPS:
		var items: Array = g.items.duplicate()
		if g.id == "events":
			items.append_array(_letter_items())
		for it in items:
			_tool_info[it[0]] = [it[0], it[1], it[2], g.id]
		var b := UiKit.icon_button(ICONS % items[0][1], "", ICON)
		b.draw.connect(_draw_group_corner.bind(b, items.size() > 1))
		var menu := PopupMenu.new()
		_fill_menu(menu, items)
		menu.id_pressed.connect(func(id): _select_tool(items[id][0]))
		b.add_child(menu)
		if g.id == "events":
			_events_items = items
		b.gui_input.connect(_group_input.bind(g.id))
		b.pressed.connect(_group_pressed.bind(g.id))
		col.add_child(b)
		if g.id == "garden":
			col.add_child(HSeparator.new())
		_groups[g.id] = {"button": b, "menu": menu, "current": items[0], "name": g.name, "multi": items.size() > 1}
	_build_header()
	_select_tool("=")


## Dialog letters a–x: in this level, letter c starts its dialog "<level>C".
func _letter_items() -> Array:
	var out := []
	var prefix: String = Game.DIALOG_LEVEL.get(level_id, "?")
	for i in 24:
		var ch := char(97 + i)
		var target := Text.dialog_for_letter(ch, level_id)
		var preview := ""
		if target != "":
			var parts: Array = Text.dialogs[target].get("parts", [])
			if not parts.is_empty():
				preview = Text.plain(Text.t(parts[0].get("text", "")))
				if preview.length() > 34:
					preview = preview.substr(0, 32) + "…"
		out.append([ch, "message-square", "Dialog %s%s%s" % [prefix, ch.to_upper(), ("  " + preview) if preview != "" else "  (none yet)"]])
	return out


## Fills a group's menu; dialog letters without a dialog in this level go to a submenu.
func _fill_menu(menu: PopupMenu, items: Array) -> void:
	for c in menu.get_children():
		menu.remove_child(c)
		c.queue_free()
	menu.clear()
	var dialogs: PopupMenu = null
	for i in items.size():
		var it: Array = items[i]
		var is_letter: bool = it[0] >= "a" and it[0] <= "z"
		if is_letter and Text.dialog_for_letter(it[0], level_id) == "":
			if dialogs == null:
				dialogs = PopupMenu.new()
				dialogs.id_pressed.connect(func(id): _select_tool(items[id][0]))
			dialogs.add_icon_item(load(ICONS % it[1]), it[2], i)
			continue
		if is_letter and menu.get_item_count() > 0 and not menu.is_item_separator(menu.get_item_count() - 1) and not (items[i - 1][0] >= "a" and items[i - 1][0] <= "z"):
			menu.add_separator()
		menu.add_icon_item(load(ICONS % it[1]), it[2], i)
	if dialogs:
		menu.add_submenu_node_item("Other dialog letters", dialogs)


## The dialog letters name this level's dialogs (after a level switch).
func _refresh_dialog_tools() -> void:
	if _events_items.is_empty() or not _groups.has("events"):
		return
	var letters := _letter_items()
	var n := _events_items.size() - letters.size()
	for i in letters.size():
		_events_items[n + i] = letters[i]
		_tool_info[letters[i][0]] = [letters[i][0], letters[i][1], letters[i][2], "events"]
	_fill_menu(_groups.events.menu, _events_items)


## Small triangle in the corner of groups that hold more than one tool.
func _draw_group_corner(b: Button, multi: bool) -> void:
	if not multi:
		return
	var s := b.size
	b.draw_colored_polygon(PackedVector2Array([s - Vector2(4, 11), s - Vector2(4, 4), s - Vector2(11, 4)]), Color("#94a3b8"))


func _group_pressed(id: String) -> void:
	# Select the group's current tool and, if it has more, show them right away.
	var g: Dictionary = _groups[id]
	_select_tool(g.current[0])
	if g.multi:
		_open_group_menu(id)


func _group_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _groups[id].multi:
		_open_group_menu(id)


func _open_group_menu(id: String) -> void:
	var g: Dictionary = _groups[id]
	var b: Button = g.button
	var menu: PopupMenu = g.menu
	menu.position = Vector2i(b.get_screen_position() + Vector2(b.size.x + 6, 0))
	menu.popup()


func _build_header() -> void:
	var own := header == null
	if own:
		# Standalone use (no developer menu): make a small bar of our own.
		header = HBoxContainer.new()
		header.position = Vector2(SIDEBAR + 8, (SIDEBAR - ICON) / 2)
		add_child(header)
	header.add_theme_constant_override("separation", 2)
	_level_pick = OptionButton.new()
	_level_pick.focus_mode = Control.FOCUS_NONE
	_level_pick.add_theme_font_size_override("font_size", 12)
	_level_pick.custom_minimum_size = Vector2(96, ICON)
	_level_pick.tooltip_text = "Which game level to edit"
	for id in Game.LEVELS:
		_level_pick.add_item(Game.LEVEL_NAMES[id])
	_level_pick.select(Game.LEVELS.keys().find(level_id))
	_level_pick.item_selected.connect(func(i): select_level(Game.LEVELS.keys()[i]))
	header.add_child(_level_pick)
	var items := [
		["play", "Test level (Enter)", start_test], null,
		["gamepad-2", "Use this level in the game", _use_in_game],
		["undo-2", "Back to the bundled level", _use_bundled], null,
		["folder-open", "Load the game level from the build", _load_game_level],
		["file-plus", "New empty level", _new_level],
		["list-plus", "Add 20 rows (horizontal levels: 20 columns)", _add_rows],
		["layers", "Background: parallax layers", toggle_bg_panel], null,
		["import", "Import level text", _open_import],
		["download", "Export: copy + download the level text", _export], null,
		["git-commit-horizontal", "Save to repo (commits the level to GitHub)", save_to_repo],
	]
	for it in items:
		if it == null:
			var sep := VSeparator.new()
			sep.custom_minimum_size = Vector2(10, ICON)
			header.add_child(sep)
			continue
		var b := UiKit.icon_button(ICONS % it[0], it[1], ICON)
		b.pressed.connect(it[2])
		header.add_child(b)
		if it[0] == "play":
			_test_button = b
			UiKit.set_icon_active(b, true)


func _select_tool(t: String) -> void:
	if not _tool_info.has(t):
		return
	tool = t
	var info: Array = _tool_info[t]
	for id in _groups:
		var g: Dictionary = _groups[id]
		var on: bool = id == info[3]
		if on:
			g.current = info
			g.button.icon = load(ICONS % info[1])
		UiKit.set_icon_active(g.button, on)
		var cur: Array = g.current
		g.button.tooltip_text = "%s: %s%s" % [g.name, cur[2], ""]


# --- painting -----------------------------------------------------------------

func _grid_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if horizontal() and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# The wheel scrolls along a horizontal level.
			_scroll.scroll_horizontal += int(CELL_W * 4) * (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
			_grid.queue_redraw()
			get_viewport().set_input_as_handled()
			return
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
	var c := int(pos.x / cw())
	var r := int(pos.y / CELL_H)
	if r < 0 or r >= rows.size() or c < 0 or c >= cols():
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
	var CW := cw()
	var ci := _grid
	var font: Font = Text.font_bold
	var scroll_top := _scroll.scroll_vertical
	var first := maxi(0, int(scroll_top / CELL_H) - 1)
	var last := mini(rows.size(), first + int(600 / CELL_H) + 3)
	var ncols := cols()
	var w := ncols * CW
	var level_h := rows.size() * CELL_H
	var scroll_left := _scroll.scroll_horizontal
	var first_c := maxi(0, int(scroll_left / CW) - 1) if horizontal() else 0
	var last_c := mini(ncols, first_c + int(1066 / CW) + 3) if horizontal() else ncols
	ci.draw_rect(Rect2(first_c * CW, first * CELL_H, (last_c - first_c) * CW, (last - first) * CELL_H), Color("#111827"))
	for r in range(first, last):
		var y := r * CELL_H
		ci.draw_line(Vector2(first_c * CW, y), Vector2(last_c * CW, y), Color(1, 1, 1, 0.12 if r % 4 == 0 else 0.05))
		var row := rows[r]
		if is_runner():
			_draw_runner_row(ci, r, y)
		for c in range(first_c, last_c):
			var ch := row[c]
			var cell := Rect2(c * CW, y, CW, CELL_H)
			var mid := cell.get_center()
			if is_runner() and _draw_runner_cell(ci, ch, cell):
				continue
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
				"#":
					ci.draw_rect(cell, Color("#1d4ed8", 0.7))
					ci.draw_line(Vector2(cell.position.x + 6, mid.y), Vector2(cell.end.x - 6, mid.y), Color("#93c5fd", 0.8), 2.0)
				"Y":
					ci.draw_circle(mid, 11, Color("#fde68a", 0.5))
					ci.draw_circle(mid, 5, Color("#fff4c2"))
				"1", "2", "3", "4", "5", "B", "6", "7", "8", "9", "E", "K", "M", "Q", "G":
					ci.draw_rect(cell.grow(-1), Color("#581c87", 0.8))
					ci.draw_rect(cell.grow(-1), Color("#c084fc"), false, 1.0)
					Draw.text_center(ci, font, mid, ch, 12, Color.WHITE)
				"@":
					ci.draw_circle(mid, 13, Color("#f9a8d4", 0.5))
					ci.draw_arc(mid, 13, 0, TAU, 24, Color("#fbcfe8"), 2.0, true)
				"%":
					ci.draw_circle(mid, 13, Color("#fde68a", 0.4))
					for k in 8:
						ci.draw_arc(mid, 13, k * TAU / 8, k * TAU / 8 + TAU / 16, 4, Color("#fde68a"), 2.0, true)
				"~":
					ci.draw_rect(cell.grow(-2), Color("#fef9c3", 0.12))
					for k in 3:
						var yy := cell.position.y + 6 + k * 8
						ci.draw_line(Vector2(mid.x - 2, yy + 6), Vector2(mid.x - 2, yy), Color("#fef08a", 0.8), 2.0)
						ci.draw_line(Vector2(mid.x + 8, yy + 8), Vector2(mid.x + 8, yy + 2), Color("#fef08a", 0.5), 2.0)
				"N":
					ci.draw_rect(Rect2(mid - Vector2(12, 9), Vector2(24, 18)), Color("#e2e8f0"))
					ci.draw_circle(mid + Vector2(10, -8), 4, Color("#ef4444"))
					Draw.text_center(ci, font, mid, "!", 12, Color("#334155"))
				_:
					ci.draw_rect(cell.grow(-1), Color("#1e3a8a", 0.8))
					ci.draw_rect(cell.grow(-1), Color("#60a5fa"), false, 1.0)
					Draw.text_center(ci, font, mid, (str(Game.DIALOG_LEVEL.get(level_id, "")) + ch.to_upper()) if ch >= "a" and ch <= "z" else ch.to_upper(), 11, Color.WHITE)
	for c in range(first_c, last_c + 1):
		ci.draw_line(Vector2(c * CW, first * CELL_H), Vector2(c * CW, last * CELL_H), Color(1, 1, 1, 0.12 if (horizontal() and c % 10 == 0) else 0.05))
	# Level boundary: a bright frame, and a hatched "end of level" band after the last row / column.
	var frame_col := Color("#10b981")
	ci.draw_line(Vector2(1, 0), Vector2(1, level_h), frame_col, 2.0)
	ci.draw_line(Vector2(w - 1, 0), Vector2(w - 1, level_h), frame_col, 2.0)
	ci.draw_line(Vector2(first_c * CW, 1), Vector2(last_c * CW, 1), frame_col, 2.0)
	if horizontal():
		ci.draw_line(Vector2(first_c * CW, level_h - 1), Vector2(last_c * CW, level_h - 1), frame_col, 2.0)
		if w + END_PAD >= scroll_left and w <= scroll_left + 1066:
			ci.draw_rect(Rect2(w, 0, END_PAD, level_h), Color("#020617"))
			ci.draw_line(Vector2(w, 0), Vector2(w, level_h), frame_col, 3.0)
			ci.draw_set_transform(Vector2(w + END_PAD / 2, level_h / 2), -PI / 2, Vector2.ONE)
			Draw.text_center(ci, font, Vector2(0, -6), "END OF LEVEL  ·  %d columns" % ncols, 13, Color(frame_col, 0.9))
			Draw.text_center(ci, Text.font, Vector2(0, 14), "add more with “Add 20 columns” in the header", 11, Color("#64748b"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	if level_h + END_PAD >= scroll_top and level_h <= scroll_top + 600:
		ci.draw_rect(Rect2(0, level_h, w, END_PAD), Color("#020617"))
		var x := -END_PAD
		while x < w:
			ci.draw_line(Vector2(maxf(x, 0), level_h + (maxf(x, 0) - x)), Vector2(minf(x + END_PAD, w), level_h + END_PAD - (x + END_PAD - minf(x + END_PAD, w))), Color(1, 1, 1, 0.04), 2.0)
			x += 18
		ci.draw_line(Vector2(0, level_h), Vector2(w, level_h), frame_col, 3.0)
		if is_runner():
			Draw.text_center(ci, font, Vector2(w / 2, level_h + END_PAD / 2 - 8), "START  ·  she runs upwards  ·  %d rows" % rows.size(), 13, Color(frame_col, 0.9))
			Draw.text_center(ci, Text.font, Vector2(w / 2, level_h + END_PAD / 2 + 14), "“Add 20 rows” adds them at the top (the end)", 11, Color("#64748b"))
			return
		Draw.text_center(ci, font, Vector2(w / 2, level_h + END_PAD / 2 - 8), "END OF LEVEL  ·  %d rows" % rows.size(), 13, Color(frame_col, 0.9))
		Draw.text_center(ci, Text.font, Vector2(w / 2, level_h + END_PAD / 2 + 14), "add more with “Add 20 rows” in the header", 11, Color("#64748b"))


## The forest run's map: green sides, a brown path of three lanes, stage lines.
func _draw_runner_row(ci: CanvasItem, r: int, y: float) -> void:
	var w := cw()
	ci.draw_rect(Rect2(0, y, w, CELL_H), Color("#14532d", 0.55))
	ci.draw_rect(Rect2(w, y, w * 3, CELL_H), Color("#78350f", 0.35))
	ci.draw_rect(Rect2(w * 4, y, w, CELL_H), Color("#14532d", 0.55))
	if rows[r].contains("A"):
		ci.draw_line(Vector2(0, y + CELL_H - 1), Vector2(w * 5, y + CELL_H - 1), Color("#facc15"), 3.0)
	# Distance from the start every 10 rows (20 m).
	var from_start := rows.size() - 1 - r
	if from_start % 10 == 0:
		ci.draw_string(Text.font, Vector2(w * 5 + 8, y + CELL_H - 8), "%d m" % int(ForestRunner.START_Z + from_start * ForestRunner.ROW_M), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#64748b"))


## Cells of the forest run; false = drawn the usual way (dialog letters).
func _draw_runner_cell(ci: CanvasItem, ch: String, cell: Rect2) -> bool:
	var mid := cell.get_center()
	var font: Font = Text.font_bold
	match ch:
		" ":
			return true
		"R":
			ci.draw_rect(Rect2(cell.position.x + 6, mid.y - 6, cell.size.x - 12, 12), Color("#6b4423"))
			ci.draw_rect(Rect2(cell.position.x + 6, mid.y - 6, cell.size.x - 12, 12), Color("#a16207"), false, 1.0)
		"H":
			ci.draw_line(Vector2(cell.position.x + 8, mid.y - 2), Vector2(cell.end.x - 8, mid.y + 2), Color("#a16207"), 6.0)
			Draw.text_center(ci, font, mid + Vector2(0, -1), "H", 10, Color.WHITE)
		"V":
			SpriteArt.draw_bird(ci, mid, 16, 0.5)
		"D", "U":
			SpriteArt.draw_drop(ci, mid + Vector2(0, 2), 0.7)
			if ch == "U":
				ci.draw_line(mid + Vector2(12, 6), mid + Vector2(12, -8), Color("#93c5fd"), 2.0)
				ci.draw_colored_polygon(PackedVector2Array([mid + Vector2(8, -6), mid + Vector2(16, -6), mid + Vector2(12, -11)]), Color("#93c5fd"))
		"Y":
			ci.draw_circle(mid, 10, Color("#fde68a", 0.5))
			ci.draw_circle(mid, 5, Color("#fff4c2"))
		"+":
			ci.draw_circle(mid, 13, Color("#fbbf24", 0.35))
			SpriteArt.draw_sun_piece(ci, mid, 18)
		"<", ">":
			var d := 1.0 if ch == "<" else -1.0
			var x0: float = cell.position.x + (4.0 if ch == "<" else cell.size.x - 4)
			ci.draw_line(Vector2(x0, mid.y), Vector2(x0 + d * (cell.size.x - 14), mid.y), Color("#2f6b2f"), 5.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x0 + d * (cell.size.x - 8), mid.y), Vector2(x0 + d * (cell.size.x - 18), mid.y - 7), Vector2(x0 + d * (cell.size.x - 18), mid.y + 7)]), Color("#b91c1c"))
		"A":
			ci.draw_rect(cell.grow(-2), Color("#facc15", 0.25))
			Draw.text_center(ci, font, mid, "STAGE", 10, Color("#fef08a"))
		_:
			return false
	return true


# --- level actions -------------------------------------------------------------

func _use_in_game() -> void:
	Game.custom_level_rows = rows.duplicate()
	Game.custom_level_id = level_id
	Game.custom_backgrounds[level_id] = current_bg().duplicate(true)
	_toast_msg("The game now uses this %s level and background (until reload)." % Game.LEVEL_NAMES[level_id].to_lower())


func _use_bundled() -> void:
	Game.custom_level_rows = PackedStringArray()
	Game.custom_backgrounds = {}
	_toast_msg("Game uses the bundled levels and backgrounds again.")


# --- background (parallax layers) -------------------------------------------------------

func _load_bg_edits() -> void:
	bg_edit = {}
	bg_saved = {}
	_bg_view = {}
	if not FileAccess.file_exists(BG_AUTOSAVE):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(BG_AUTOSAVE))
	if not d is Dictionary:
		return
	# Older autosaves held only the edits; newer ones {"edit": …, "saved": …}.
	var edits: Variant = d.get("edit", d) if d.has("edit") else d
	if d.get("saved") is Dictionary:
		bg_saved = d.saved
	if edits is Dictionary:
		for k in edits:
			if edits[k] is Dictionary:
				bg_edit[str(k)] = BackgroundData.normalize(edits[k])
	# Once the build ships what was committed from here, the local edit is done.
	for k in bg_saved.keys():
		if JSON.stringify(BackgroundData.of_bundled(int(k))) == str(bg_saved[k].get("committed", "")):
			bg_edit.erase(k)
			bg_saved.erase(k)


func _store_bg_edits() -> void:
	var f := FileAccess.open(BG_AUTOSAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"edit": bg_edit, "saved": bg_saved}, " "))


## The background of the level being edited: the edit if there is one, else a
## copy of the game's (kept only in memory until something changes).
func current_bg() -> Dictionary:
	var k := str(level_id)
	if bg_edit.has(k):
		return bg_edit[k]
	if not _bg_view.has(k):
		_bg_view[k] = BackgroundData.normalize(BackgroundData.for_level(level_id).duplicate(true))
	return _bg_view[k]


## True when the edited background differs from the bundled one and hasn't been
## committed from here already.
func bg_dirty() -> bool:
	var k := str(level_id)
	if not bg_edit.has(k):
		return false
	var cur := JSON.stringify(bg_edit[k])
	if bg_saved.has(k) and str(bg_saved[k].get("local", "")) == cur:
		return false
	return cur != JSON.stringify(BackgroundData.of_bundled(level_id))


## Called by the panel after any change to current_bg().
func bg_changed() -> void:
	var k := str(level_id)
	if _bg_view.has(k):
		bg_edit[k] = _bg_view[k]
		_bg_view.erase(k)
	_store_bg_edits()
	if _test:
		_test.background = current_bg()


func reset_bg() -> void:
	var k := str(level_id)
	bg_edit.erase(k)
	bg_saved.erase(k)
	_bg_view.erase(k)
	_store_bg_edits()
	if _test:
		_test.background = current_bg()
	_toast_msg("Background reset to the game's.")


## Uploads used by any edited background or by "Use in game" can't be deleted.
func bg_in_use(path: String) -> bool:
	for cfgs in [bg_edit.values(), _bg_view.values(), Game.custom_backgrounds.values()]:
		for c in cfgs:
			for l in c.get("layers", []):
				if l.image == path:
					return true
	return false


func toggle_bg_panel() -> void:
	if is_runner() and not bg_panel:
		_toast_msg("The forest run draws its own sky (no parallax layers).")
		return
	if bg_panel:
		bg_panel.queue_free()
		bg_panel = null
		return
	bg_panel = BackgroundPanel.new()
	bg_panel.editor = self
	bg_panel.top = top
	add_child(bg_panel)


## Downloads the edited background as JSON (to paste into data/backgrounds.json).
func export_bg() -> void:
	var txt := JSON.stringify({str(level_id): current_bg()}, " ")
	DisplayServer.clipboard_set(txt)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(txt.to_utf8_buffer(), "background-%s.json" % Game.LEVEL_NAMES[level_id].to_lower(), "application/json")
	_toast_msg("Background JSON copied%s." % (" and downloaded" if OS.has_feature("web") else ""))


## Files to commit for the edited background: images uploaded in this browser
## (scaled to ≤ BG_MAX_PX) and data/backgrounds.json with this level replaced.
## remote = the current backgrounds.json text on GitHub ("" = use the bundled one).
func build_bg_commit(remote: String) -> Dictionary:
	var d: Variant = JSON.parse_string(remote) if remote != "" else null
	var manifest: Dictionary = d if d is Dictionary else BackgroundData.bundled().duplicate(true)
	var cfg := current_bg().duplicate(true)
	var files := {}
	var named := {}
	for l in cfg.layers:
		if not AssetBrowser.is_local(l.image):
			continue
		if named.has(l.image):
			l.image = named[l.image]
			continue
		var bytes := AssetBrowser.bytes_of(l.image)
		var img := AssetBrowser.decode(bytes)
		if img == null:
			# Never commit a path that only exists in this browser.
			return {"_error": "%s can't be read in this browser any more" % AssetBrowser.label(l.image)}
		AssetBrowser.fit(img, BG_MAX_PX)
		var png := img.save_png_to_buffer()
		# A short hash of the content keeps different images with the same name apart.
		var stem := AssetBrowser.label(l.image).get_basename().to_lower().validate_filename().replace(" ", "-")
		var name := "%s-%s-%s.png" % [Game.LEVEL_NAMES[level_id].to_lower(), stem, png.hex_encode().md5_text().substr(0, 8)]
		files["godot/assets/backgrounds/" + name] = png
		named[l.image] = "res://assets/backgrounds/" + name
		l.image = named[l.image]
	manifest[str(level_id)] = cfg
	files["godot/data/backgrounds.json"] = (JSON.stringify(manifest, " ") + "\n").to_utf8_buffer()
	return files


func _load_game_level() -> void:
	rows = Game.level_rows(level_id)
	_resize_grid()
	_autosave()
	_toast_msg("Loaded data/levels/" + _level_file())


func _new_level() -> void:
	rows = PackedStringArray()
	if horizontal():
		for i in 10:
			rows.append(" ".repeat(120))
		rows[7] = "=".repeat(24) + " ".repeat(96)
		rows[8] = "#".repeat(120)
		rows[9] = "#".repeat(120)
	elif is_runner():
		for i in 120:
			rows.append(" ".repeat(cols()))
	else:
		for i in 100:
			rows.append(" ".repeat(LevelData.COLS))
		rows[99] = "=".repeat(LevelData.COLS)
	_resize_grid()
	_autosave()


## Vertical levels grow by rows, horizontal ones by columns.
func _add_rows() -> void:
	if horizontal():
		for i in rows.size():
			var tail := "#" if rows[i].ends_with("#") else " "
			rows[i] = rows[i] + tail.repeat(20)
	elif is_runner():
		# The end of the run is at the top.
		for i in 20:
			rows.insert(0, " ".repeat(cols()))
	else:
		for i in 20:
			rows.append(" ".repeat(LevelData.COLS))
	_resize_grid()
	_autosave()


func _export() -> void:
	var txt := _level_text()
	DisplayServer.clipboard_set(txt)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(txt.to_utf8_buffer(), _level_file(), "text/plain")
	_toast_msg("Level copied to clipboard%s!" % (" and downloaded" if OS.has_feature("web") else ""))


## Commits the level as godot/data/levels/<level>.txt (the game rebuilds with it).
func save_to_repo() -> void:
	if not GitHubSave.has_token():
		GitHubSave.token_dialog(self, _on_token)
		return
	var gh := GitHubSave.new()
	add_child(gh)
	gh.progress.connect(_toast_msg)
	var files := {"godot/data/levels/" + _level_file(): _level_text().to_utf8_buffer()}
	var what := "level"
	var bg_files := {}
	if bg_dirty():
		var remote := await gh.read_text("godot/data/backgrounds.json")
		if not remote.ok:
			gh.queue_free()
			_toast_msg("Save failed: " + remote.error)
			if "token" in remote.error:
				GitHubSave.forget_token()
			return
		bg_files = build_bg_commit(remote.text)
		if bg_files.has("_error"):
			gh.queue_free()
			_toast_msg("Save failed: " + str(bg_files["_error"]))
			return
		files.merge(bg_files)
		what = "level and background"
	var res := await gh.commit(files,
		"Level editor: update the %s %s\n\nSaved from Developer mode > Level editor in the browser." % [Game.LEVEL_NAMES[level_id].to_lower(), what])
	gh.queue_free()
	if not res.ok:
		_toast_msg("Save failed: " + res.error)
		if "token" in res.error:
			GitHubSave.forget_token()
		return
	if not bg_files.is_empty():
		# Remember what was committed, so it isn't committed again (and the edit
		# is dropped once the new build ships it).
		var m: Variant = JSON.parse_string(bg_files["godot/data/backgrounds.json"].get_string_from_utf8())
		if m is Dictionary:
			bg_saved[str(level_id)] = {"local": JSON.stringify(current_bg()),
				"committed": JSON.stringify(BackgroundData.normalize(m[str(level_id)]))}
			_store_bg_edits()
	_toast_msg("Saved to the repo — the game updates after the next build (~2 min).")


func _on_token(ok: bool) -> void:
	if ok:
		save_to_repo()


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
	if _test or _test_run:
		return
	if is_runner():
		_start_runner_test()
		return
	_saved_state = {"iron": Game.iron, "breath": Game.has_breathing, "cp": Game.checkpoint}
	Game.iron = 0
	Game.has_breathing = true
	Game.checkpoint = 0
	_test = Platformer.new()
	_test.hud_layer = 32
	_test.player_layer = 31
	Game.level = level_id
	if level_id == 3:
		Game.upgrades = {"jump": true, "dash": true, "double": true}
	_test.setup(rows, 0, level_id)
	_test.background = current_bg()
	_test.active = true
	if bg_panel:
		# Hidden under the test, it would still take the mouse (and its buttons).
		bg_panel.close_browser()
		bg_panel.visible = false
	# The editor must not swallow the mouse while testing (aiming the thread).
	for c in [self, _scroll, _grid]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## Plays the forest run map; minigames are skipped (a message instead).
func _start_runner_test() -> void:
	_saved_state = {"iron": Game.iron, "breath": Game.has_breathing, "cp": Game.checkpoint}
	_test_run = ForestRunner.new()
	_test_run.rows = rows.duplicate()
	_test_run.active = true
	_test_run.sun_game.connect(func(n):
		_toast_msg("%d sun pieces: minigame %d (skipped in the test)" % [n * ForestRunner.SUN_PER_GAME, n])
		_test_run.after_minigame.call_deferred())
	_test_run.show_dialog.connect(func(id): _toast_msg("Dialog: " + id))
	_test_run.finished.connect(func():
		_toast_msg("The sun is whole: on to the summit!")
		stop_test.call_deferred())
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.name = "TestLayer"
	add_child(layer)
	layer.add_child(_test_run)
	for c in [self, _scroll, _grid]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 33
	layer.add_child(hud_layer)
	var back := UiKit.button("BACK TO EDITOR", Vector2(170, 32), 12, Color("#059669"))
	back.position = Vector2(12, 600 - 100)
	back.pressed.connect(stop_test)
	hud_layer.add_child(back)


func stop_test() -> void:
	if _test_run:
		get_node("TestLayer").queue_free()
		_test_run = null
		for c in [self, _scroll, _grid]:
			c.mouse_filter = Control.MOUSE_FILTER_STOP
		return
	if not _test:
		return
	Audio.stop_all_loops()
	Audio.set_bgm_volume(0.5)
	get_node("TestLayer").queue_free()
	_test = null
	for c in [self, _scroll, _grid]:
		c.mouse_filter = Control.MOUSE_FILTER_STOP
	if bg_panel:
		bg_panel.visible = true
	Game.iron = _saved_state.iron
	Game.has_breathing = _saved_state.breath
	Game.checkpoint = _saved_state.cp


func _on_test_trigger(name: String) -> void:
	if name in ["white_fade", "first_enemy", "dialog_a", "dialog_g"]:
		return
	if name == "wave_lost":
		_toast_msg("The LH wave caught you — restarting test")
		stop_test()
		start_test.call_deferred()
		return
	if name.begins_with("game_over"):
		_toast_msg("Out of iron — restarting test")
		stop_test()
		start_test.call_deferred()
		return
	_toast_msg("Trigger: " + name)


func _unhandled_input(event: InputEvent) -> void:
	if _import or (bg_panel and is_instance_valid(bg_panel.browser)):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		if _test or _test_run:
			stop_test()
		else:
			start_test()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and (_test or _test_run):
		stop_test()


func _process(delta: float) -> void:
	if _toast_t > 0:
		_toast_t -= delta
		if _toast_t <= 0:
			_toast.visible = false
	if _import and not is_instance_valid(_import):
		_import = null
