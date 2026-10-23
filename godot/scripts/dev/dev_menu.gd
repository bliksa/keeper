class_name DevMenu
extends Control
## Developer menu (port of the web "start" screen). Kept: shortcuts and the
## level editor. The character/animation testers were not ported.

signal back
## Main handles these: ("skip_intro"), ("boss", iron), ("checkpoint", n)
signal action(name: String, value: int)

var _tab := "shortcuts"
var _content: Control
var _tabs := {}
var _iron := 20
var _editor: LevelEditor


func _ready() -> void:
	size = Vector2(1066, 600)
	var bg := ColorRect.new()
	bg.color = Color("#0a0f0a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.8)
	bar.size = Vector2(1066, 56)
	add_child(bar)
	var x := 12.0
	for t in [["shortcuts", "Shortcuts"], ["level", "Level Editor"]]:
		var b := UiKit.button(t[1].to_upper(), Vector2(150, 40), 12, Color(0, 0, 0, 0), Color("#94a3b8"))
		b.position = Vector2(x, 8)
		b.pressed.connect(_show.bind(t[0]))
		add_child(b)
		_tabs[t[0]] = b
		x += 158
	var ret := UiKit.button("RETURN TO MENU", Vector2(170, 40), 12, Color("#0f172a"), Color("#cbd5e1"))
	ret.position = Vector2(1066 - 182, 8)
	ret.pressed.connect(func(): back.emit())
	add_child(ret)
	_content = Control.new()
	_content.position = Vector2(0, 56)
	_content.size = Vector2(1066, 544)
	_content.clip_contents = true
	add_child(_content)
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
	if _editor:
		_editor.stop_test()
		_editor.queue_free()
		_editor = null
	if tab == "level":
		# Full-screen editor below the tab bar (added first so the bar stays on top).
		_editor = LevelEditor.new()
		_editor.top = 56
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
