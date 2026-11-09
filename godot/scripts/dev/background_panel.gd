class_name BackgroundPanel
extends Control
## Level editor > Background: edits the parallax layers behind the level being
## edited (BackgroundData config held by the editor). Live preview with the
## camera gliding through the level, a list of layers (image, speed, opacity,
## scale, shift, repeat; replace / move / remove), "Add layer…" from the asset
## browser, and the level's base colour / procedural sky / cave tint.

const W := 440.0
const PREVIEW := Vector2(408, 230)
const ICONS := "res://assets/ui/icons/%s.svg"

var editor: LevelEditor
var top := 0.0
var browser: AssetBrowser
## Preview camera: 0..1 through the level; auto-glides unless scrubbed.
var cam_k := 0.0
var auto := true

var _preview: Control
var _list: VBoxContainer
var _scrub: HSlider
var _play: Button
var _opts: HBoxContainer
var _title: Label
var _browser_target := -1


func _ready() -> void:
	position = Vector2(1066 - W, top)
	size = Vector2(W, 600 - top)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0b1220")
	sb.border_color = Color("#334155")
	sb.border_width_left = 1
	bg.add_theme_stylebox_override("panel", sb)
	add_child(bg)
	var head := HBoxContainer.new()
	head.position = Vector2(14, 8)
	head.size = Vector2(W - 28, 30)
	add_child(head)
	_title = UiKit.label("", 14, Color.WHITE, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	var close := UiKit.icon_button(ICONS % "x", "Close", 28)
	close.pressed.connect(func(): editor.toggle_bg_panel())
	head.add_child(close)
	_preview = Control.new()
	_preview.position = Vector2(16, 44)
	_preview.size = PREVIEW
	_preview.clip_contents = true
	_preview.draw.connect(_draw_preview)
	add_child(_preview)
	var scrub_row := HBoxContainer.new()
	scrub_row.position = Vector2(16, 44 + PREVIEW.y + 4)
	scrub_row.size = Vector2(PREVIEW.x, 26)
	scrub_row.add_theme_constant_override("separation", 6)
	add_child(scrub_row)
	_play = UiKit.icon_button(ICONS % "pause", "Glide through the level / stop", 26)
	_play.pressed.connect(func():
		auto = not auto
		_play.icon = load(ICONS % ("pause" if auto else "play")))
	scrub_row.add_child(_play)
	_scrub = HSlider.new()
	_scrub.min_value = 0
	_scrub.max_value = 1
	_scrub.step = 0.001
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.tooltip_text = "Where the camera is in the level"
	_scrub.value_changed.connect(func(v):
		if absf(v - cam_k) > 0.0005:
			cam_k = v
			auto = false
			_play.icon = load(ICONS % "play"))
	scrub_row.add_child(_scrub)
	_opts = HBoxContainer.new()
	_opts.position = Vector2(16, 44 + PREVIEW.y + 34)
	_opts.size = Vector2(PREVIEW.x, 28)
	_opts.add_theme_constant_override("separation", 10)
	add_child(_opts)
	var sc := ScrollContainer.new()
	sc.position = Vector2(12, 44 + PREVIEW.y + 68)
	sc.size = Vector2(W - 20, size.y - (44 + PREVIEW.y + 68) - 50)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(W - 36, 0)
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	var foot := HBoxContainer.new()
	foot.position = Vector2(14, size.y - 42)
	foot.size = Vector2(W - 28, 32)
	foot.add_theme_constant_override("separation", 6)
	add_child(foot)
	var add := UiKit.button("Add layer…", Vector2(130, 32), 12, Color("#059669"))
	add.icon = load(ICONS % "image-plus")
	add.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.add_theme_constant_override("icon_max_width", 16)
	add.tooltip_text = "Pick an image (or upload one) for a new layer in front"
	add.pressed.connect(open_browser.bind(-1))
	foot.add_child(add)
	var reset := UiKit.button("Reset", Vector2(80, 32), 12, Color("#1e293b"), Color("#cbd5e1"))
	reset.tooltip_text = "Back to the game's background for this level"
	reset.pressed.connect(func():
		editor.reset_bg()
		refresh())
	foot.add_child(reset)
	var dl := UiKit.icon_button(ICONS % "download", "Download this background as JSON", 32)
	dl.pressed.connect(editor.export_bg)
	foot.add_child(dl)
	var hint := UiKit.label("Use in game / Save to repo\nin the header apply it", 10, Color("#64748b"))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(hint)
	refresh()


func cfg() -> Dictionary:
	return editor.current_bg()


func layers() -> Array:
	return cfg().layers


## Rebuilds the options and the layer list (after a structural change).
func refresh() -> void:
	_title.text = "Background  ·  %s" % Game.LEVEL_NAMES[editor.level_id]
	for c in _opts.get_children():
		c.queue_free()
	var col := ColorPickerButton.new()
	col.color = Color.from_string(cfg().base, Color.BLACK)
	col.custom_minimum_size = Vector2(32, 24)
	col.edit_alpha = false
	col.tooltip_text = "Base colour (behind everything)"
	col.color_changed.connect(func(c):
		cfg().base = "#" + c.to_html(false)
		editor.bg_changed())
	_opts.add_child(col)
	_opts.add_child(UiKit.label("Base colour", 11, Color("#cbd5e1")))
	if editor.level_id in [2, 3, Game.CLIMB_ID]:
		_opts.add_child(_check("Procedural sky", "procedural", "The level's code-drawn sky (behind the layers)"))
	if editor.level_id == 1:
		_opts.add_child(_check("Red tint", "tint", "The cave's pulsing red tint and vignette (in front of the layers)"))
	for c in _list.get_children():
		c.queue_free()
	var ls := layers()
	if ls.is_empty():
		_list.add_child(UiKit.label("No image layers yet. Add one below.", 11, Color("#64748b")))
	for i in range(ls.size() - 1, -1, -1):
		_list.add_child(_layer_row(i, ls[i]))


func _check(text: String, key: String, tip: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.focus_mode = Control.FOCUS_NONE
	cb.add_theme_font_size_override("font_size", 11)
	cb.button_pressed = cfg().get(key, false)
	cb.tooltip_text = tip
	cb.toggled.connect(func(on):
		cfg()[key] = on
		editor.bg_changed())
	return cb


## One layer: header (thumb, name, actions) and its sliders. The list shows the
## front layer on top.
func _layer_row(i: int, l: Dictionary) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b")
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	v.add_child(h)
	var th := TextureRect.new()
	th.custom_minimum_size = Vector2(54, 34)
	th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t := AssetBrowser.tex(l.image)
	if t:
		th.texture = AssetBrowser.thumb(t, 54, 34)
	h.add_child(th)
	var name := UiKit.label("%d · %s%s" % [i + 1, AssetBrowser.label(l.image), "  (this browser)" if AssetBrowser.is_local(l.image) else ""], 11, Color.WHITE if t else Color("#f87171"))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.custom_minimum_size = Vector2(60, 0)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(name)
	for it in [["images", "Replace the image", open_browser.bind(i)],
			["arrow-up", "Move to the front", move_layer.bind(i, 1)],
			["arrow-down", "Move to the back", move_layer.bind(i, -1)],
			["x", "Remove this layer", remove_layer.bind(i)]]:
		var b := UiKit.icon_button(ICONS % it[0], it[1], 24)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(it[2])
		h.add_child(b)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 0)
	v.add_child(g)
	var horiz := Game.is_horizontal(editor.level_id)
	g.add_child(_slider(i, "speed", "Parallax", 0.0, 2.0, 0.05, "%.2f"))
	g.add_child(_slider(i, "opacity", "Opacity", 0.0, 1.0, 0.05, "%.2f"))
	g.add_child(_slider(i, "scale", "Size", 0.2, 3.0, 0.05, "%.2f"))
	g.add_child(_slider(i, "offset_x", "Shift ↔", -1200.0 if horiz else -600.0, 1200.0 if horiz else 600.0, 5.0, "%d"))
	g.add_child(_slider(i, "offset_y", "Shift ↕", -600.0 if horiz else -1200.0, 600.0 if horiz else 1200.0, 5.0, "%d"))
	var rep := CheckBox.new()
	rep.text = "Repeat"
	rep.focus_mode = Control.FOCUS_NONE
	rep.add_theme_font_size_override("font_size", 10)
	rep.button_pressed = l.repeat
	rep.tooltip_text = "Tile the image along the level"
	rep.toggled.connect(func(on): set_value(i, "repeat", on))
	g.add_child(rep)
	return row


func _slider(i: int, key: String, text: String, lo: float, hi: float, step: float, fmt: String) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(186, 0)
	col.add_theme_constant_override("separation", -2)
	var top_row := HBoxContainer.new()
	var l := UiKit.label(text, 10, Color("#94a3b8"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(l)
	var val := get_value(i, key)
	var vl := UiKit.label(fmt % val, 10, Color("#34d399"), true)
	top_row.add_child(vl)
	col.add_child(top_row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x):
		vl.text = fmt % x
		set_value(i, key, x))
	col.add_child(s)
	return col


# --- editing API (also used by the tests) -------------------------------------------------

func get_value(i: int, key: String) -> float:
	var l: Dictionary = layers()[i]
	match key:
		"offset_x": return l.offset[0]
		"offset_y": return l.offset[1]
		_: return float(l[key])


func set_value(i: int, key: String, v: Variant) -> void:
	if i < 0 or i >= layers().size():
		return
	var l: Dictionary = layers()[i]
	match key:
		"offset_x": l.offset[0] = float(v)
		"offset_y": l.offset[1] = float(v)
		"repeat": l.repeat = bool(v)
		_: l[key] = float(v)
	editor.bg_changed()


## Adds a layer in front of the others.
func add_layer(path: String) -> void:
	var speed := 0.5
	var ls := layers()
	if not ls.is_empty():
		speed = minf(2.0, float(ls.back().speed) + 0.2)
	ls.append(BackgroundData.layer(path, speed))
	editor.bg_changed()
	refresh()


func replace_layer(i: int, path: String) -> void:
	if i >= 0 and i < layers().size():
		layers()[i].image = path
		editor.bg_changed()
		refresh()


func remove_layer(i: int) -> void:
	if i >= 0 and i < layers().size():
		layers().remove_at(i)
		editor.bg_changed()
		refresh()


## d = +1 one step to the front, -1 to the back.
func move_layer(i: int, d: int) -> void:
	var ls := layers()
	var j := i + d
	if i < 0 or j < 0 or i >= ls.size() or j >= ls.size():
		return
	var tmp: Dictionary = ls[i]
	ls[i] = ls[j]
	ls[j] = tmp
	editor.bg_changed()
	refresh()


## target = -1 adds a new layer, otherwise replaces that layer's image.
func open_browser(target: int) -> void:
	if browser and is_instance_valid(browser):
		browser.queue_free()
	_browser_target = target
	browser = AssetBrowser.new()
	browser.top = top
	browser.title = "New background layer" if target < 0 else "Layer %d image" % (target + 1)
	browser.start_path = "res://assets/backgrounds/" if target < 0 else layers()[target].image
	if target < 0 and ResourceLoader.list_directory("res://assets/backgrounds/").is_empty():
		browser.start_path = "res://assets/images/back.png"
	browser.in_use = editor.bg_in_use
	browser.picked.connect(_on_picked)
	# Over the whole editor, not just the panel.
	editor.add_child(browser)


func close_browser() -> void:
	if browser and is_instance_valid(browser):
		browser.close_browser()
	browser = null


func _exit_tree() -> void:
	close_browser()


func _on_picked(path: String) -> void:
	if path == "":
		return
	if _browser_target < 0:
		add_layer(path)
	else:
		replace_layer(_browser_target, path)


# --- preview -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if auto:
		cam_k = fmod(cam_k + delta * 0.04, 1.0)
		_scrub.set_value_no_signal(cam_k)
	_preview.queue_redraw()


## Camera in world pixels for the preview position.
func preview_cam() -> Vector2:
	var rows := editor.rows.size()
	if Game.is_horizontal(editor.level_id):
		var lw := editor.cols() * LevelData.CELL_W
		return Vector2(maxf(0, lw - 1066) * cam_k, 0)
	var lh := rows * LevelData.ROW_H
	# Vertical levels: the cave is played downwards, the climbs (old summit, jackpot climb) upwards.
	var k := cam_k if editor.level_id == 1 else 1.0 - cam_k
	return Vector2(0, maxf(0, lh - 600) * k)


func _draw_preview() -> void:
	var ci := _preview
	var c := cfg()
	ci.draw_rect(Rect2(Vector2.ZERO, PREVIEW), Color.from_string(c.base, Color.BLACK))
	if c.procedural:
		# The code-drawn sky isn't rendered here; hint at it with a soft gradient.
		var top_c := Color("#8fd0c4") if editor.level_id == 2 else Color("#4a2a5e")
		var bot_c := Color("#f1e6b8") if editor.level_id == 2 else Color("#1c1533")
		for b in 10:
			ci.draw_rect(Rect2(0, PREVIEW.y * b / 10.0, PREVIEW.x, PREVIEW.y / 10.0 + 1), top_c.lerp(bot_c, (b + 0.5) / 10.0))
	ci.draw_set_transform(Vector2.ZERO, 0, PREVIEW / Vector2(1066, 600))
	var origin := Platformer.bg_origin_for(editor.level_id, editor.rows.size() * LevelData.ROW_H)
	BackgroundData.draw_layers(ci, c, preview_cam(), Vector2(1066, 600), Game.is_horizontal(editor.level_id), origin)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if c.tint:
		Draw.vignette(ci, Rect2(Vector2.ZERO, PREVIEW), Color(0, 0, 0, 0.35), 0.4)
	if c.procedural:
		Draw.panel(ci, Rect2(6, 6, 150, 18), Color(0, 0, 0, 0.45), 9)
		ci.draw_string(Text.font, Vector2(14, 19), "+ procedural sky in game", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.85))
	ci.draw_rect(Rect2(Vector2.ZERO, PREVIEW), Color("#334155"), false, 1.0)
