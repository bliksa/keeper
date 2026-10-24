class_name DevMenu
extends Control
## Developer menu (port of the web "start" screen): shortcuts, the level
## editor and the animation lab (run / jump frame variants).

signal back
## Main handles these: ("skip_intro"), ("boss", iron), ("checkpoint", n)
signal action(name: String, value: int)

var _tab := "shortcuts"
var _content: Control
var _tabs := {}
var _iron := 20
var _editor: LevelEditor
var _lab: AnimLab
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
	for t in [["shortcuts", "Shortcuts"], ["level", "Level editor"], ["anim", "Animations"]]:
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
	_help.position = Vector2(700, 0)
	_help.size = Vector2(270, BAR_H)
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
		_lab.queue_free()
		_lab = null
	if tab == "anim":
		_lab = AnimLab.new()
		_lab.top = BAR_H
		_help.text = "Variants: data/anim_variants.json\nKeys: ← → move · ↑ / Space jump"
		add_child(_lab)
		move_child(_lab, 1)
	elif tab == "level":
		# Full-screen editor below the tab bar (added first so the bar stays on top).
		_editor = LevelEditor.new()
		_editor.top = BAR_H
		_editor.header = header_tools
		_help.text = "Left click paint · right click erase\nWheel scroll · Enter test · autosaved"
		add_child(_editor)
		move_child(_editor, 1)
	else:
		_build_shortcuts()


func _build_shortcuts() -> void:
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b")
	sb.set_corner_radius_all(12)
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(83, 32)
	card.size = Vector2(900, 440)
	_content.add_child(card)

	var h1 := UiKit.label("CORE ACTIONS", 13, Color("#94a3b8"), true)
	h1.position = Vector2(32, 28)
	card.add_child(h1)
	var skip := UiKit.button(Text.t("BTN_SKIP_INTRO").to_upper(), Vector2(400, 64), 20, Color("#059669"), Color.BLACK)
	skip.position = Vector2(32, 60)
	skip.pressed.connect(func(): action.emit("skip_intro", 0))
	card.add_child(skip)
	var iron_lbl := UiKit.label("IRON: %d" % _iron, 12, Color.WHITE, true)
	iron_lbl.position = Vector2(32, 152)
	card.add_child(iron_lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = _iron
	slider.position = Vector2(32, 180)
	slider.size = Vector2(400, 20)
	slider.value_changed.connect(func(v):
		_iron = int(v)
		iron_lbl.text = "IRON: %d" % _iron)
	card.add_child(slider)
	var boss := UiKit.button("SKIP TO BOSS", Vector2(160, 34), 12, Color("#022c22"), Color("#34d399"))
	boss.position = Vector2(272, 140)
	boss.pressed.connect(func(): action.emit("boss", _iron))
	card.add_child(boss)

	var h2 := UiKit.label("CHECKPOINTS (cave)", 13, Color("#94a3b8"), true)
	h2.position = Vector2(480, 28)
	card.add_child(h2)
	var cps := [[1, "Cave start"], [2, "After chocolate puzzle"], [3, "After pipes"], [4, "After prices"]]
	for i in cps.size():
		var b := UiKit.button(cps[i][1], Vector2(380, 44), 14)
		b.position = Vector2(480, 60 + i * 54)
		b.pressed.connect(func(): action.emit("checkpoint", cps[i][0]))
		card.add_child(b)

	var h3 := UiKit.label("CAVE DEBUG KEYS: 1–4 restart at checkpoint · Shift+2–5 jump to minigame/boss · 5 boss · C breath + 20 iron · X skip minigame", 11, Color("#64748b"))
	h3.position = Vector2(32, 400)
	card.add_child(h3)
