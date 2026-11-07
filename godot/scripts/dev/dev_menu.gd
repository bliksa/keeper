class_name DevMenu
extends Control
## Developer menu (port of the web "start" screen): shortcuts, the level
## editor, the animation lab and the dialog editor.

signal back
## Main handles these: ("skip_intro"), ("boss", iron), ("checkpoint", n)
signal action(name: String, value: int)

var _tab := "shortcuts"
var _content: Control
var _tabs := {}
var _iron := 20
var _editor: LevelEditor
var _lab: AnimLab
var _dialogs: DialogEditor
var _gh: GitHubSave
var _old_pick: OptionButton
## Header slot the active tab can fill with its own icon buttons.
var header_tools: HBoxContainer
var _help: Label

## Same thickness as the level editor's tool sidebar (LevelEditor.SIDEBAR).
const BAR_H := 48.0
const ICON := 36.0


func _ready() -> void:
	size = Vector2(1066, 600)
	var bg := ColorRect.new()
	bg.color = Color("#0a0f0a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.8)
	bar.size = Vector2(1066, BAR_H)
	add_child(bar)
	var x := 8.0
	for t in [["shortcuts", "Shortcuts"], ["level", "Level editor"], ["anim", "Animations"], ["dialogs", "Dialogs"]]:
		var b := UiKit.button(t[1], Vector2(110, ICON), 12, Color(0, 0, 0, 0), Color("#94a3b8"))
		b.position = Vector2(x, (BAR_H - ICON) / 2)
		b.pressed.connect(_show.bind(t[0]))
		add_child(b)
		_tabs[t[0]] = b
		x += 114
	var ret := UiKit.button("Menu", Vector2(76, ICON), 12, Color("#0f172a"), Color("#cbd5e1"))
	ret.tooltip_text = "Return to the title screen"
	ret.position = Vector2(1066 - 84, (BAR_H - ICON) / 2)
	ret.pressed.connect(func(): back.emit())
	add_child(ret)
	_content = Control.new()
	_content.position = Vector2(0, BAR_H)
	_content.size = Vector2(1066, 600 - BAR_H)
	_content.clip_contents = true
	# Only a holder: it must not swallow clicks meant for the level editor below it.
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	header_tools = HBoxContainer.new()
	header_tools.position = Vector2(x + 16, (BAR_H - ICON) / 2)
	header_tools.add_theme_constant_override("separation", 2)
	add_child(header_tools)
	_help = UiKit.label("", 10, Color("#64748b"))
	_help.position = Vector2(800, 0)
	_help.size = Vector2(172, BAR_H)
	_help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_help)
	_show("shortcuts")


func _show(tab: String) -> void:
	_tab = tab
	for k in _tabs:
		var b: Button = _tabs[k]
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		sb.bg_color = Color("#334155") if k == tab else Color(0, 0, 0, 0)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", Color.WHITE if k == tab else Color("#94a3b8"))
	for c in _content.get_children():
		c.queue_free()
	for c in header_tools.get_children():
		c.queue_free()
	_help.text = ""

	if _editor:
		_editor.stop_test()
		_editor.queue_free()
		_editor = null
	if _lab:
		# Free now (not queued) so it restores the original frames before a new lab starts.
		remove_child(_lab)
		_lab.free()
		_lab = null
	if _dialogs:
		_dialogs.queue_free()
		_dialogs = null
	if tab == "dialogs":
		_dialogs = DialogEditor.new()
		_dialogs.top = BAR_H
		_dialogs.header = header_tools
		add_child(_dialogs)
		move_child(_dialogs, 1)
	elif tab == "anim":
		_lab = AnimLab.new()
		_lab.top = BAR_H
		_help.text = "Space pause / play\n← → step frames"
		add_child(_lab)
		move_child(_lab, 1)
	elif tab == "level":
		# Full-screen editor below the tab bar (added first so the bar stays on top).
		_editor = LevelEditor.new()
		_editor.top = BAR_H
		_editor.header = header_tools
		# The level editor's header is full; its tips are in the tooltips.
		_help.text = ""
		add_child(_editor)
		move_child(_editor, 1)
	else:
		_build_shortcuts()


## Forgets this browser's unlock: DEV asks for the team password next time.
func lock() -> void:
	GitHubSave.forget_token()
	back.emit()


## Sets up / changes the team password (DevAccess).
func open_team_password() -> void:
	if _gh == null:
		_gh = GitHubSave.new()
		add_child(_gh)
	DevAccess.setup_dialog(self, _gh, func(ok):
		if ok:
			_help.text = "Team password saved.\nLive after the build (~2 min).")


func _build_shortcuts() -> void:
	if DevAccess.is_set_up():
		var lk := UiKit.button("Lock", Vector2(80, ICON), 12, Color("#1e293b"), Color("#cbd5e1"))
		lk.icon = load("res://assets/ui/icons/lock.svg")
		lk.add_theme_constant_override("icon_max_width", 16)
		lk.tooltip_text = "Lock developer mode in this browser: DEV asks for the team password again"
		lk.pressed.connect(lock)
		header_tools.add_child(lk)
	var tp := UiKit.button("Change password" if DevAccess.is_set_up() else "Team password", Vector2(150, ICON), 12, Color("#1e293b"), Color("#cbd5e1"))
	tp.icon = load("res://assets/ui/icons/key-round.svg")
	tp.add_theme_constant_override("icon_max_width", 16)
	tp.tooltip_text = "One password for developer mode and every “Save to repo” (no token for the team)"
	tp.pressed.connect(open_team_password)
	header_tools.add_child(tp)
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b")
	sb.set_corner_radius_all(12)
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(33, 20)
	card.size = Vector2(1000, 508)
	_content.add_child(card)
	var title := UiKit.label("PLAY FROM  ·  the cycle", 13, Color("#94a3b8"), true)
	title.position = Vector2(24, 18)
	card.add_child(title)
	# A rainbow across the levels that comes back to its start: the cycle goes round.
	var strip := Control.new()
	strip.position = Vector2(24, 40)
	strip.size = Vector2(952, 4)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(func():
		for i in 120:
			var hue := fposmod(275.0 + i / 120.0 * 300.0, 360.0) / 360.0
			strip.draw_rect(Rect2(i * strip.size.x / 120.0, 0, strip.size.x / 120.0 + 1, 4), Color.from_hsv(hue, 0.7, 0.8)))
	card.add_child(strip)
	# The game in its order: one column per level, each from its start onwards.
	const COL_W := 177.0
	var cols := [
		["0 · Prologue", "the forest + breathing", Color.from_hsv(275.0 / 360, 0.7, 0.75), [
			["New game", "From the very start (the forest intro)", "new_game", 0],
			[Text.t("BTN_SKIP_INTRO"), "Straight into the cave (breathing learnt)", "skip_intro", 0]]],
		["1 · Cave", "menstruation · iron, cramps", Color.from_hsv(0.0, 0.75, 0.75), [
			["Start", "", "checkpoint", 1], ["After chocolate", "After the chocolate puzzle", "checkpoint", 2],
			["After pipes", "", "checkpoint", 3], ["After prices", "", "checkpoint", 4],
			["Boss fight", "The Big Cramp, with the iron below", "boss", -1]]],
		["2 · Forest run", "follicular · the sun", Color.from_hsv(38.0 / 360, 0.8, 0.75), [
			["Start", "", "runner", 0], ["Stage 2", "3 sun pieces found, after the memory game", "runner", 1],
			["Stage 3", "6 pieces, after catch: flying notifications", "runner", 2],
			["Stage 4", "9 pieces, after pairs: fastest + side traps", "runner", 3]]],
		["3 · Summit", "ovulation · LH wave", Color.from_hsv(130.0 / 360, 0.65, 0.6), [
			["Start", "", "checkpoint3", 1], ["After iron plate", "", "checkpoint3", 2],
			["After rhythm", "", "checkpoint3", 3], ["After body signals", "", "checkpoint3", 4],
			["LH wave", "The climb with the wave", "checkpoint3", 5]]],
		["4 · PMS", "luteal phase · right to left", Color.from_hsv(215.0 / 360, 0.7, 0.75), [
			["Start", "Level 4 is not built yet (right to left, PMS; the sex-ed branch)", "", 0]]],
	]
	for c in cols.size():
		var x := 24 + c * (COL_W + 16)
		var head := ColorRect.new()
		head.color = cols[c][2]
		head.position = Vector2(x, 48)
		head.size = Vector2(COL_W, 4)
		card.add_child(head)
		var name := UiKit.label(cols[c][0], 15, Color.WHITE, true)
		name.position = Vector2(x, 58)
		card.add_child(name)
		var sub := UiKit.label(cols[c][1], 11, Color("#94a3b8"))
		sub.position = Vector2(x, 80)
		card.add_child(sub)
		var items: Array = cols[c][3]
		for k in items.size():
			var it: Array = items[k]
			var first := k == 0
			var b := UiKit.button(it[0], Vector2(COL_W, 36), 12, cols[c][2].darkened(0.35) if first else Color("#0f172a"), Color.WHITE if first else Color("#cbd5e1"))
			b.position = Vector2(x, 106 + k * 42)
			b.tooltip_text = it[1]
			var act: String = it[2]
			var val: int = it[3]
			if act == "":
				b.disabled = true
				b.text = it[0] + " (soon)"
			b.pressed.connect(func(): action.emit(act, _iron if val < 0 else val))
			card.add_child(b)
		if c == 1:
			# Iron for the cave checkpoints' boss shortcut.
			var iron_lbl := UiKit.label("Iron for the boss: %d" % _iron, 11, Color("#cbd5e1"))
			iron_lbl.position = Vector2(x, 106 + items.size() * 42 + 4)
			card.add_child(iron_lbl)
			var slider := HSlider.new()
			slider.min_value = 0
			slider.max_value = 100
			slider.value = _iron
			slider.position = Vector2(x, 106 + items.size() * 42 + 24)
			slider.size = Vector2(COL_W, 20)
			slider.focus_mode = Control.FOCUS_NONE
			slider.value_changed.connect(func(v):
				_iron = int(v)
				iron_lbl.text = "Iron for the boss: %d" % _iron)
			card.add_child(slider)

	# Old and deprecated: the first level-2 draft (the meadow).
	var sep := ColorRect.new()
	sep.color = Color("#334155")
	sep.position = Vector2(24, 404)
	sep.size = Vector2(952, 1)
	card.add_child(sep)
	var old_lbl := UiKit.label("OLD / DEPRECATED", 11, Color("#64748b"), true)
	old_lbl.position = Vector2(24, 418)
	card.add_child(old_lbl)
	var old := OptionButton.new()
	old.add_theme_font_size_override("font_size", 12)
	old.focus_mode = Control.FOCUS_NONE
	old.position = Vector2(170, 412)
	old.size = Vector2(300, 30)
	var olds := [["Old meadow (level 2 draft): start", "checkpoint2", 1],
		["Old meadow: after its minigames", "checkpoint2", 4], ["Old meadow: the gate", "checkpoint2", 5]]
	for o in olds:
		old.add_item(o[0])
	card.add_child(old)
	var go := UiKit.button("Play", Vector2(80, 30), 12, Color("#334155"))
	go.position = Vector2(478, 412)
	go.pressed.connect(func():
		var o: Array = olds[old.selected]
		action.emit(o[1], o[2]))
	card.add_child(go)
	_old_pick = old

	var keys := UiKit.label("Keys while playing: 1–4 restart at a checkpoint · Shift+2–5 jump to the next minigame / boss / wave · 5 boss (summit: wave) · G summit with power-ups · C breathing + 20 iron · X skip a minigame · Esc pause", 11, Color("#64748b"))
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD
	keys.custom_minimum_size = Vector2(952, 0)
	keys.position = Vector2(24, 458)
	keys.size = Vector2(952, 36)
	card.add_child(keys)
