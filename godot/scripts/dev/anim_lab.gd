class_name AnimLab
extends Control
## Developer menu > Animations: try out run and jump frame variants
## (data/anim_variants.json) on the real character renderer before they go
## into the game. The character runs and jumps by itself (Auto) or with the
## keys: arrows / A D move, Up / W / Space jump (twice = double jump).

const MANIFEST := "res://data/anim_variants.json"
const PANEL_W := 250.0
const STAGE := Rect2(266, 14, 784, 316)
const FLOOR_Y := 280.0
const GRAVITY := 0.4
const JUMP := -10.5
const ACCEL := 1.2
const FRICTION := 0.75

## Space reserved at the top (the developer menu's tab bar).
var top := 0.0

var variants := {"run": {}, "jump": {}}
var run_variant := "original"
var jump_variant := "original"
var max_speed := 6.0
var auto := true

var p := PlayerBody.new()
var _time := 0.0
var _auto_jump_t := 1.0
var _auto_jumps := 0
var _applied := false
var _saved := {}
var _status: Label
var _run_pick: OptionButton
var _jump_pick: OptionButton
var _auto_box: CheckBox
var _stage: Control
var _strip: Control
var _thumbs := {}


func _ready() -> void:
	size = Vector2(1066, 600)
	_saved = {"overrides": PlayerArt.overrides.duplicate(), "scale": PlayerArt.scale,
		"fps": PlayerArt.jump_fps, "rate": PlayerBody.run_rate}
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			variants.run = d.get("run", {})
			variants.jump = d.get("jump", {})
	var bg := ColorRect.new()
	bg.color = Color("#0f172a")
	bg.position = Vector2(0, top)
	bg.size = Vector2(1066, 600 - top)
	add_child(bg)
	_build_panel()
	_stage = Control.new()
	_stage.position = Vector2(STAGE.position.x, top + STAGE.position.y)
	_stage.size = STAGE.size
	_stage.clip_contents = true
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_strip = Control.new()
	_strip.position = Vector2(STAGE.position.x, top + STAGE.end.y + 12)
	_strip.size = Vector2(STAGE.size.x, 600 - top - STAGE.end.y - 20)
	_strip.draw.connect(_draw_strip)
	add_child(_strip)
	p.x = 120
	p.y = FLOOR_Y - p.height
	p.is_grounded = true
	_apply_preview()


func _exit_tree() -> void:
	if not _applied:
		PlayerArt.overrides = _saved.overrides
		PlayerArt.scale = _saved.scale
		PlayerArt.jump_fps = _saved.fps
		PlayerBody.run_rate = _saved.rate


# --- panel ----------------------------------------------------------------------

func _build_panel() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(0, top)
	panel.size = Vector2(PANEL_W, 600 - top)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(16, top + 14)
	box.custom_minimum_size = Vector2(PANEL_W - 32, 0)
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	box.add_child(UiKit.label("RUN VARIANT", 11, Color("#94a3b8"), true))
	_run_pick = _picker(variants.run.keys(), _pick_run)
	box.add_child(_run_pick)
	box.add_child(UiKit.label("JUMP VARIANT", 11, Color("#94a3b8"), true))
	_jump_pick = _picker(variants.jump.keys(), _pick_jump)
	box.add_child(_jump_pick)

	box.add_child(_gap(6))
	_slider(box, "Run speed", 2.0, 12.0, 0.1, max_speed, "%.1f", func(v): max_speed = v)
	_slider(box, "Run frame rate", 0.008, 0.08, 0.001, PlayerBody.run_rate, "%.3f", func(v): PlayerBody.run_rate = v)
	_slider(box, "Jump frames / s", 2.0, 30.0, 1.0, PlayerArt.jump_fps, "%d", func(v): PlayerArt.jump_fps = v)
	_slider(box, "Sprite scale", 0.8, 2.6, 0.05, PlayerArt.scale, "%.2f", func(v): PlayerArt.scale = v)

	_auto_box = CheckBox.new()
	_auto_box.text = "Auto run & jump"
	_auto_box.button_pressed = auto
	_auto_box.add_theme_font_size_override("font_size", 12)
	_auto_box.toggled.connect(func(on): auto = on)
	box.add_child(_auto_box)
	box.add_child(_gap(6))
	var use := UiKit.button("Use in game", Vector2(PANEL_W - 32, 34), 12, Color("#059669"))
	use.tooltip_text = "Keep these frames and settings in the game until the page is reloaded"
	use.pressed.connect(func():
		_applied = true
		_status.text = "Used in game (until reload).")
	box.add_child(use)
	var reset := UiKit.button("Back to original", Vector2(PANEL_W - 32, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
	reset.pressed.connect(_reset)
	box.add_child(reset)
	_status = UiKit.label("Keys: ← → move · ↑ / Space jump", 10, Color("#64748b"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(PANEL_W - 32, 0)
	box.add_child(_status)


func _pick_run(name: String) -> void:
	run_variant = name
	_apply_preview()


func _pick_jump(name: String) -> void:
	jump_variant = name
	_apply_preview()


func _picker(names: Array, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 12)
	o.focus_mode = Control.FOCUS_NONE
	for n in names:
		o.add_item(n)
	o.item_selected.connect(func(i): on_pick.call(o.get_item_text(i)))
	return o


func _slider(box: VBoxContainer, label: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var l := UiKit.label(label, 11, Color("#cbd5e1"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := UiKit.label(fmt % value, 11, Color("#34d399"), true)
	row.add_child(v)
	box.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x):
		v.text = fmt % x
		on_change.call(x))
	box.add_child(s)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _reset() -> void:
	run_variant = "original"
	jump_variant = "original"
	_run_pick.select(maxi(0, variants.run.keys().find("original")))
	_jump_pick.select(maxi(0, variants.jump.keys().find("original")))
	PlayerArt.scale = 1.6
	PlayerArt.jump_fps = 12.0
	PlayerBody.run_rate = 0.026
	PlayerArt.overrides = {}
	_applied = false
	_status.text = "Original frames."
	_apply_preview()


# --- frames -------------------------------------------------------------------------

func _load_list(paths: Array) -> Array:
	var out := []
	for path in paths:
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if t:
			out.append(t)
	return out


## Put the selected variants into PlayerArt so the preview uses the real renderer.
func _apply_preview() -> void:
	var o := {}
	if run_variant != "original" and variants.run.has(run_variant):
		o.run = _load_list(variants.run[run_variant])
	if jump_variant != "original" and variants.jump.has(jump_variant):
		var poses: Dictionary = variants.jump[jump_variant]
		for pose in poses:
			o[pose] = _load_list(poses[pose])
	PlayerArt.overrides = o
	if _strip:
		_strip.queue_redraw()


# --- character ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not event.is_echo():
		_set_auto(false)
		_jump()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_set_auto(false)


func _set_auto(on: bool) -> void:
	auto = on
	_auto_box.set_pressed_no_signal(on)


func _jump() -> void:
	if p.jumps_left > 0:
		Audio.jump_sound(p.jumps_left == 1)
		p.vy = JUMP
		p.jumps_left -= 1
		p.is_grounded = false


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	var d60 := dt * 60.0
	_time += dt * 1000.0
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	if auto:
		# Run to the edge, turn around; hop now and then, sometimes a double jump.
		right = p.facing_right
		left = not right
		if p.x > STAGE.size.x - 140:
			p.facing_right = false
		elif p.x < 110:
			p.facing_right = true
		right = p.facing_right
		left = not right
		_auto_jump_t -= dt
		if _auto_jump_t <= 0 and p.is_grounded:
			_jump()
			_auto_jumps += 1
			_auto_jump_t = 1.6
		if not p.is_grounded and p.jumps_left == 1 and p.vy > -2 and _auto_jumps % 3 == 0:
			_jump()
	if right:
		p.vx += ACCEL * d60
		p.facing_right = true
	elif left:
		p.vx -= ACCEL * d60
		p.facing_right = false
	else:
		p.vx *= pow(FRICTION, d60)
	p.vx = clampf(p.vx, -max_speed, max_speed)
	if absf(p.vx) < 0.1:
		p.vx = 0
	p.x = clampf(p.x + p.vx * d60, 20, STAGE.size.x - 60)
	p.vy = minf(p.vy + GRAVITY * d60, 15)
	p.y += p.vy * d60
	if p.y + p.height >= FLOOR_Y:
		if not p.is_grounded:
			Audio.footstep(0.6)
		p.y = FLOOR_Y - p.height
		p.vy = 0
		p.is_grounded = true
		p.jumps_left = 2
	else:
		p.is_grounded = false
	p.step_animation(d60)
	_stage.queue_redraw()
	_strip.queue_redraw()


func current_run_frames() -> Array:
	return PlayerArt.overrides.get("run", _load_list(variants.run.get("original", [])))


func _draw_stage() -> void:
	var s := _stage
	Draw.panel(s, Rect2(Vector2.ZERO, STAGE.size), Color("#111827"), 10, Color("#334155"), 1)
	for i in range(0, int(STAGE.size.x), 40):
		s.draw_line(Vector2(i, 0), Vector2(i, FLOOR_Y), Color(1, 1, 1, 0.03))
	s.draw_line(Vector2(0, FLOOR_Y), Vector2(STAGE.size.x, FLOOR_Y), Color("#475569"), 2.0)
	PlayerArt.draw(s, p, _time)
	var info := "run: %s   jump: %s   speed %.1f" % [run_variant, jump_variant, absf(p.vx)]
	s.draw_string(Text.font, Vector2(14, STAGE.size.y - 14), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#64748b"))


## Small pre-scaled copy of a frame for the strip (drawing 1190 px sprites at
## 60 px directly can show up blank in some browsers, and looks aliased).
func _thumb(t: Texture2D) -> Texture2D:
	if _thumbs.has(t):
		return _thumbs[t]
	var img := t.get_image()
	var out: Texture2D = t
	if img:
		if img.is_compressed():
			img.decompress()
		var k := minf(104.0 / img.get_width(), 120.0 / img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(img)
	_thumbs[t] = out
	return out


func _draw_strip() -> void:
	var s := _strip
	var font: Font = Text.font_bold
	s.draw_string(font, Vector2(0, 12), "RUN FRAMES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#94a3b8"))
	var frames := current_run_frames()
	var running := p.is_grounded and absf(p.vx) > 3.5
	var cur := int(floorf(p.anim_progress)) % maxi(1, frames.size()) if running else -1
	var x := 0.0
	for i in frames.size():
		var t: Texture2D = _thumb(frames[i])
		var r := Rect2(x, 20, 56, 64)
		Draw.panel(s, r, Color("#1e293b"), 6, Color("#10b981") if i == cur else Color(0, 0, 0, 0), 2)
		var k := minf(52.0 / t.get_width(), 60.0 / t.get_height())
		var sz := Vector2(t.get_width(), t.get_height()) * k
		s.draw_texture_rect(t, Rect2(r.get_center() - sz / 2, sz), false)
		x += 60
	s.draw_string(font, Vector2(0, 108), "JUMP POSES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#94a3b8"))
	var pose := ""
	if not p.is_grounded:
		pose = "fall" if p.vy > 0 else ("doublejump" if p.jumps_left == 0 else ("sidejump" if absf(p.vx) > 1 else "jump"))
	x = 0.0
	for name in ["jump", "sidejump", "doublejump", "fall"]:
		var list: Array = PlayerArt.overrides.get(name, [])
		if list.is_empty():
			list = [load("res://assets/images/%s.png" % name)]
		for frame in list:
			var t: Texture2D = _thumb(frame)
			var r := Rect2(x, 116, 56, 64)
			Draw.panel(s, r, Color("#1e293b"), 6, Color("#10b981") if name == pose else Color(0, 0, 0, 0), 2)
			var k := minf(52.0 / t.get_width(), 60.0 / t.get_height())
			var sz := Vector2(t.get_width(), t.get_height()) * k
			s.draw_texture_rect(t, Rect2(r.get_center() - sz / 2, sz), false)
			x += 60
		s.draw_string(Text.font, Vector2(x - 60 * list.size(), 194), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#64748b"))
		x += 12
