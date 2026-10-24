class_name AnimLab
extends Control
## Developer menu > Animations: try out run and jump frames on the real
## character renderer before they go into the game.
##
##  * Variants from the repo: data/anim_variants.json (tools/add_anim_variant.py).
##  * Variants uploaded in the browser: "Upload run/jump frames…" or drag PNGs
##    onto the window. They are kept in this browser (user://anim_uploads/).
##  * Single frames: click a frame to pause on it, step with ◀ ▶, replace it,
##    add frames or remove it (the variant becomes a local editable copy).
## Keys: arrows / A D move, Up / W / Space jump (twice = double jump).

const MANIFEST := "res://data/anim_variants.json"
const LOCAL_DIR := "user://anim_uploads/"
const LOCAL_MANIFEST := LOCAL_DIR + "manifest.json"
const LOCAL_TAG := " (local)"
const POSES := ["jump", "sidejump", "doublejump", "fall"]
const PANEL_W := 250.0
const STAGE := Rect2(266, 10, 784, 280)
const FLOOR_Y := 246.0
const SLOT := Vector2(46, 52)
const GRAVITY := 0.4
const JUMP := -10.5
const ACCEL := 1.2
const FRICTION := 0.75
const ICONS := "res://assets/ui/icons/%s.svg"

## Space reserved at the top (the developer menu's tab bar).
var top := 0.0

## run: name -> [paths]; jump: name -> {pose: [paths]}. Local names end with LOCAL_TAG.
var variants := {"run": {}, "jump": {}}
var run_variant := "original"
var jump_variant := "original"
var max_speed := 6.0
var auto := true
var paused := false
## Selected frame: {"kind": "run", "i": n} or {"kind": "pose", "pose": name, "i": n}
var selected := {}

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
var _play_btn: Button
var _stage: Control
var _strip: Control
var _thumbs := {}
var _tex_cache := {}
var _slots: Array = []
var _local := {"run": {}, "jump": {}}
var _js_cb: JavaScriptObject
var _pending: Array = []
var _pick_purpose := ""
var _dialog: FileDialog


func _ready() -> void:
	size = Vector2(1066, 600)
	_saved = {"overrides": PlayerArt.overrides.duplicate(), "scale": PlayerArt.scale,
		"fps": PlayerArt.jump_fps, "rate": PlayerBody.run_rate}
	_load_manifests()
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
	_build_frame_toolbar()
	_strip = Control.new()
	_strip.position = Vector2(STAGE.position.x, top + STAGE.end.y + 52)
	_strip.size = Vector2(STAGE.size.x, 600 - top - STAGE.end.y - 56)
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.draw.connect(_draw_strip)
	_strip.gui_input.connect(_strip_input)
	add_child(_strip)
	p.x = 120
	p.y = FLOOR_Y - p.height
	p.is_grounded = true
	get_window().files_dropped.connect(_on_files_dropped)
	_apply_preview()


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)
	if not _applied:
		PlayerArt.overrides = _saved.overrides
		PlayerArt.scale = _saved.scale
		PlayerArt.jump_fps = _saved.fps
		PlayerBody.run_rate = _saved.rate


# --- manifests ----------------------------------------------------------------------

func _load_manifests() -> void:
	var d: Variant = _read_json(MANIFEST)
	if d is Dictionary:
		variants.run = d.get("run", {}).duplicate(true)
		variants.jump = d.get("jump", {}).duplicate(true)
	var l: Variant = _read_json(LOCAL_MANIFEST)
	if l is Dictionary:
		_local = {"run": l.get("run", {}), "jump": l.get("jump", {})}
	for kind in ["run", "jump"]:
		for name in _local[kind]:
			variants[kind][name + LOCAL_TAG] = _local[kind][name]


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else null


func _save_local() -> void:
	DirAccess.make_dir_recursive_absolute(LOCAL_DIR)
	var f := FileAccess.open(LOCAL_MANIFEST, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_local, " "))


func is_local(kind: String, name: String) -> bool:
	return name.ends_with(LOCAL_TAG) and _local[kind].has(name.trim_suffix(LOCAL_TAG))


# --- panel ----------------------------------------------------------------------

func _build_panel() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(0, top)
	panel.size = Vector2(PANEL_W, 600 - top)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(16, top + 10)
	box.custom_minimum_size = Vector2(PANEL_W - 32, 0)
	box.add_theme_constant_override("separation", 5)
	add_child(box)

	box.add_child(UiKit.label("RUN VARIANT", 11, Color("#94a3b8"), true))
	_run_pick = _picker()
	_run_pick.item_selected.connect(func(i): _pick_run(_run_pick.get_item_text(i)))
	box.add_child(_run_pick)
	box.add_child(UiKit.label("JUMP VARIANT", 11, Color("#94a3b8"), true))
	_jump_pick = _picker()
	_jump_pick.item_selected.connect(func(i): _pick_jump(_jump_pick.get_item_text(i)))
	box.add_child(_jump_pick)
	_refresh_pickers()

	var up := HBoxContainer.new()
	up.add_theme_constant_override("separation", 6)
	var up_run := UiKit.button("Upload run…", Vector2((PANEL_W - 38) / 2, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
	up_run.tooltip_text = "New run variant from PNG files (natural name order: run1, run2 …).\nYou can also drag PNGs onto the window."
	up_run.pressed.connect(open_picker.bind("run"))
	up.add_child(up_run)
	var up_jump := UiKit.button("Upload jump…", Vector2((PANEL_W - 38) / 2, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
	up_jump.tooltip_text = "New jump variant. File names starting with jump / sidejump /\ndoublejump / fall choose the pose (others become 'jump')."
	up_jump.pressed.connect(open_picker.bind("jump"))
	up.add_child(up_jump)
	box.add_child(up)

	_slider(box, "Run speed", 2.0, 12.0, 0.1, max_speed, "%.1f", func(v): max_speed = v)
	_slider(box, "Run frame rate", 0.008, 0.08, 0.001, PlayerBody.run_rate, "%.3f", func(v): PlayerBody.run_rate = v)
	_slider(box, "Jump frames / s", 2.0, 30.0, 1.0, PlayerArt.jump_fps, "%d", func(v): PlayerArt.jump_fps = v)
	_slider(box, "Sprite scale", 0.8, 2.6, 0.05, PlayerArt.scale, "%.2f", func(v): PlayerArt.scale = v)

	_auto_box = CheckBox.new()
	_auto_box.text = "Auto run & jump"
	_auto_box.button_pressed = auto
	_auto_box.focus_mode = Control.FOCUS_NONE
	_auto_box.add_theme_font_size_override("font_size", 12)
	_auto_box.toggled.connect(func(on): auto = on)
	box.add_child(_auto_box)
	var use := UiKit.button("Use in game", Vector2(PANEL_W - 32, 32), 12, Color("#059669"))
	use.tooltip_text = "Keep these frames and settings in the game until the page is reloaded"
	use.pressed.connect(func():
		_applied = true
		_say("Used in game (until reload)."))
	box.add_child(use)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var reset := UiKit.button("Original", Vector2((PANEL_W - 38) / 2, 28), 11, Color("#1e293b"), Color("#cbd5e1"))
	reset.tooltip_text = "Back to the original frames and settings"
	reset.pressed.connect(_reset)
	row.add_child(reset)
	var del := UiKit.button("Delete local", Vector2((PANEL_W - 38) / 2, 28), 11, Color("#1e293b"), Color("#fca5a5"))
	del.tooltip_text = "Delete the selected uploaded/edited variant(s) from this browser"
	del.pressed.connect(_delete_local)
	row.add_child(del)
	box.add_child(row)
	_status = UiKit.label("Drag PNGs here or use Upload.", 10, Color("#64748b"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size = Vector2(PANEL_W - 32, 0)
	box.add_child(_status)


func _picker() -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 12)
	o.focus_mode = Control.FOCUS_NONE
	o.clip_text = true
	o.custom_minimum_size = Vector2(PANEL_W - 32, 0)
	return o


func _refresh_pickers() -> void:
	for pair in [[_run_pick, "run", run_variant], [_jump_pick, "jump", jump_variant]]:
		var o: OptionButton = pair[0]
		o.clear()
		var names: Array = variants[pair[1]].keys()
		for n in names:
			o.add_item(n)
		o.select(maxi(0, names.find(pair[2])))


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


func _build_frame_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(STAGE.position.x, top + STAGE.end.y + 8)
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	_play_btn = UiKit.icon_button(ICONS % "pause", "Pause / play (click a frame to inspect it)", 36)
	_play_btn.pressed.connect(func(): set_paused(not paused))
	bar.add_child(_play_btn)
	var prev := UiKit.icon_button(ICONS % "chevron-left", "Previous frame", 36)
	prev.pressed.connect(step_frame.bind(-1))
	bar.add_child(prev)
	var next := UiKit.icon_button(ICONS % "chevron-right", "Next frame", 36)
	next.pressed.connect(step_frame.bind(1))
	bar.add_child(next)
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(10, 36)
	bar.add_child(sep)
	var rep := UiKit.icon_button(ICONS % "replace", "Replace the selected frame with a PNG", 36)
	rep.pressed.connect(open_picker.bind("replace"))
	bar.add_child(rep)
	var add := UiKit.icon_button(ICONS % "image-plus", "Add frames after the selected one\n(or to the selected jump pose)", 36)
	add.pressed.connect(open_picker.bind("add"))
	bar.add_child(add)
	var rem := UiKit.icon_button(ICONS % "trash-2", "Remove the selected frame", 36)
	rem.pressed.connect(remove_selected)
	bar.add_child(rem)


func _say(s: String) -> void:
	_status.text = s


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


# --- variants ----------------------------------------------------------------------

func _pick_run(name: String) -> void:
	run_variant = name
	selected = {}
	_apply_preview()


func _pick_jump(name: String) -> void:
	jump_variant = name
	selected = {}
	_apply_preview()


func _reset() -> void:
	run_variant = "original"
	jump_variant = "original"
	_refresh_pickers()
	PlayerArt.scale = 1.6
	PlayerArt.jump_fps = 12.0
	PlayerBody.run_rate = 0.026
	_applied = false
	selected = {}
	set_paused(false)
	_say("Original frames.")
	_apply_preview()


func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if path.begins_with("user://"):
		var img := Image.load_from_file(path)
		if img:
			t = ImageTexture.create_from_image(img)
	elif ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


func _load_list(paths: Array) -> Array:
	var out := []
	for path in paths:
		var t := _tex(path)
		if t:
			out.append(t)
	return out


func run_paths() -> Array:
	return variants.run.get(run_variant, variants.run.get("original", []))


func pose_paths(pose: String) -> Array:
	var v: Dictionary = variants.jump.get(jump_variant, {})
	if v.has(pose):
		return v[pose]
	return variants.jump.get("original", {}).get(pose, ["res://assets/images/%s.png" % pose])


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


# --- uploads ------------------------------------------------------------------------

## purpose: "run" / "jump" (new variant), "replace", "add", "auto" (dropped files).
func open_picker(purpose: String) -> void:
	_pick_purpose = purpose
	_pending.clear()
	var multiple := purpose != "replace"
	if OS.has_feature("web"):
		if _js_cb == null:
			_js_cb = JavaScriptBridge.create_callback(_on_js_file)
			var win := JavaScriptBridge.get_interface("window")
			win.godotAnimFile = _js_cb
		JavaScriptBridge.eval("""(function(){
			const i = document.createElement('input');
			i.type = 'file'; i.multiple = %s; i.accept = 'image/png,image/webp,image/jpeg';
			i.onchange = async () => {
				const fs = [...i.files].sort((a, b) => a.name.localeCompare(b.name, undefined, {numeric: true}));
				for (const f of fs) {
					const d = await new Promise(r => { const rd = new FileReader(); rd.onload = () => r(rd.result.split(',')[1]); rd.readAsDataURL(f); });
					window.godotAnimFile(f.name, d);
				}
				window.godotAnimFile('', '');
			};
			i.click();
		})();""" % ("true" if multiple else "false"))
	else:
		if _dialog == null:
			_dialog = FileDialog.new()
			_dialog.access = FileDialog.ACCESS_FILESYSTEM
			_dialog.filters = PackedStringArray(["*.png, *.webp, *.jpg ; Images"])
			_dialog.files_selected.connect(_on_paths)
			_dialog.file_selected.connect(func(path): _on_paths(PackedStringArray([path])))
			add_child(_dialog)
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES if multiple else FileDialog.FILE_MODE_OPEN_FILE
		_dialog.popup_centered(Vector2i(800, 500))


func _on_js_file(args: Array) -> void:
	var name := str(args[0])
	if name == "":
		var files := _pending.duplicate()
		_pending.clear()
		receive_files(files, _pick_purpose)
		return
	_pending.append([name, Marshalls.base64_to_raw(str(args[1]))])


func _on_paths(paths: PackedStringArray) -> void:
	var files := []
	var sorted := Array(paths)
	sorted.sort_custom(func(a, b): return a.get_file().naturalnocasecmp_to(b.get_file()) < 0)
	for path in sorted:
		files.append([path.get_file(), FileAccess.get_file_as_bytes(path)])
	receive_files(files, _pick_purpose)


func _on_files_dropped(paths: PackedStringArray) -> void:
	if not is_visible_in_tree():
		return
	_pick_purpose = "auto"
	_on_paths(paths)


static func _pose_of(file_name: String) -> String:
	var n := file_name.to_lower()
	for pose in ["doublejump", "sidejump", "jump", "fall"]:
		if n.begins_with(pose):
			return pose
	return ""


## files: [[file_name, PackedByteArray], …]
func receive_files(files: Array, purpose: String) -> void:
	files = files.filter(func(f): return _image_from(f[1]) != null)
	if files.is_empty():
		_say("No readable PNG/WebP/JPG files.")
		return
	if purpose == "auto":
		purpose = "jump" if files.any(func(f): return _pose_of(f[0]) != "") else "run"
	match purpose:
		"run", "jump":
			var name := "upload %s" % Time.get_time_string_from_system()
			var paths := _store(purpose, name, files)
			if purpose == "run":
				_local.run[name] = paths
			else:
				var poses := {}
				for i in files.size():
					var pose := _pose_of(files[i][0])
					poses.get_or_add(pose if pose != "" else "jump", []).append(paths[i])
				_local.jump[name] = poses
			_save_local()
			variants[purpose][name + LOCAL_TAG] = _local[purpose][name]
			if purpose == "run":
				run_variant = name + LOCAL_TAG
			else:
				jump_variant = name + LOCAL_TAG
			_refresh_pickers()
			_apply_preview()
			_say("New %s variant '%s' with %d frame(s). Saved in this browser." % [purpose, name, files.size()])
		"replace", "add":
			_edit_frames(purpose, files)


func _image_from(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	for loader in [img.load_png_from_buffer, img.load_webp_from_buffer, img.load_jpg_from_buffer]:
		if loader.call(bytes) == OK:
			return img
	return null


## Writes uploaded files to user://anim_uploads/<kind>/<slug>/ and returns their paths.
func _store(kind: String, variant: String, files: Array) -> Array:
	var slug := variant.to_lower().replace(" ", "-").replace(":", "")
	var dir := LOCAL_DIR + kind + "/" + slug + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	var out := []
	for f in files:
		var path: String = dir + "%d-%s" % [Time.get_ticks_usec(), String(f[0]).get_file()]
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa:
			fa.store_buffer(f[1])
			fa.close()
		out.append(path)
	return out


## Make the current variant of `kind` a local copy we may change; returns its local name.
func _editable(kind: String) -> String:
	var current := run_variant if kind == "run" else jump_variant
	if is_local(kind, current):
		return current.trim_suffix(LOCAL_TAG)
	var base := current.trim_suffix(LOCAL_TAG)
	var name := base + " edit"
	var n := 2
	while _local[kind].has(name):
		name = "%s edit %d" % [base, n]
		n += 1
	if kind == "run":
		_local.run[name] = run_paths().duplicate()
	else:
		var poses := {}
		for pose in POSES:
			poses[pose] = pose_paths(pose).duplicate()
		_local.jump[name] = poses
	variants[kind][name + LOCAL_TAG] = _local[kind][name]
	if kind == "run":
		run_variant = name + LOCAL_TAG
	else:
		jump_variant = name + LOCAL_TAG
	return name


func _edit_frames(purpose: String, files: Array) -> void:
	if selected.is_empty():
		selected = {"kind": "run", "i": run_paths().size() - 1}
	var kind := "run" if selected.kind == "run" else "jump"
	var name := _editable(kind)
	var paths := _store(kind, name, files)
	var list: Array = _local.run[name] if kind == "run" else _local.jump[name][selected.pose]
	var i: int = clampi(selected.i, 0, maxi(0, list.size() - 1))
	if purpose == "replace":
		list[i] = paths[0]
		_say("Frame %d replaced." % (i + 1))
	else:
		for k in paths.size():
			list.insert(i + 1 + k, paths[k])
		selected.i = i + paths.size()
		_say("%d frame(s) added." % paths.size())
	_save_local()
	_refresh_pickers()
	_apply_preview()


func remove_selected() -> void:
	if selected.is_empty():
		_say("Click a frame first.")
		return
	var kind := "run" if selected.kind == "run" else "jump"
	var current: Array = run_paths() if kind == "run" else pose_paths(selected.pose)
	if current.size() <= 1:
		_say("A run cycle / pose needs at least one frame.")
		return
	var name := _editable(kind)
	var list: Array = _local.run[name] if kind == "run" else _local.jump[name][selected.pose]
	list.remove_at(clampi(selected.i, 0, list.size() - 1))
	selected.i = clampi(selected.i, 0, list.size() - 1)
	_save_local()
	_refresh_pickers()
	_apply_preview()
	_say("Frame removed.")


func _delete_local() -> void:
	var gone := []
	for pair in [["run", run_variant], ["jump", jump_variant]]:
		if is_local(pair[0], pair[1]):
			_local[pair[0]].erase(pair[1].trim_suffix(LOCAL_TAG))
			variants[pair[0]].erase(pair[1])
			gone.append(pair[1])
	if gone.is_empty():
		_say("The selected variants come from the repo; nothing to delete.")
		return
	_save_local()
	if not variants.run.has(run_variant):
		run_variant = "original"
	if not variants.jump.has(jump_variant):
		jump_variant = "original"
	selected = {}
	_refresh_pickers()
	_apply_preview()
	_say("Deleted: " + ", ".join(gone))


# --- frame inspection -------------------------------------------------------------

func set_paused(on: bool) -> void:
	paused = on
	_play_btn.icon = load(ICONS % ("play" if paused else "pause"))
	if paused and selected.is_empty():
		selected = {"kind": "run", "i": 0}


## Flat list of all frames shown in the strip, for stepping across rows.
func _all_frames() -> Array:
	var out := []
	for i in run_paths().size():
		out.append({"kind": "run", "i": i})
	for pose in POSES:
		for i in pose_paths(pose).size():
			out.append({"kind": "pose", "pose": pose, "i": i})
	return out


func step_frame(d: int) -> void:
	set_paused(true)
	var all := _all_frames()
	var at := 0
	for k in all.size():
		if all[k].kind == selected.get("kind") and all[k].i == selected.get("i") and all[k].get("pose", "") == selected.get("pose", ""):
			at = k
	selected = all[posmod(at + d, all.size())]


func _strip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for s in _slots:
			if s.rect.has_point(event.position):
				selected = s.sel
				set_paused(true)


# --- character ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not event.is_echo():
		_set_auto(false)
		set_paused(false)
		_jump()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_set_auto(false)
		set_paused(false)


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
	_stage.queue_redraw()
	_strip.queue_redraw()
	if paused:
		return
	var dt := minf(delta, 0.1)
	var d60 := dt * 60.0
	_time += dt * 1000.0
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	if auto:
		# Run to the edge, turn around; hop now and then, sometimes a double jump.
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


## A posed copy of the body that makes PlayerArt draw exactly the selected frame.
func _posed_body() -> Array:
	var b := PlayerBody.new()
	b.x = STAGE.size.x / 2 - b.width / 2
	b.y = FLOOR_Y - b.height
	b.facing_right = true
	var t := 0.0
	if selected.get("kind") == "run":
		b.is_grounded = true
		b.vx = 6.0
		b.anim_progress = selected.i + 0.5
	else:
		var pose: String = selected.get("pose", "jump")
		b.is_grounded = false
		b.y -= 60
		b.vy = 5.0 if pose == "fall" else -5.0
		b.jumps_left = 0 if pose == "doublejump" else 1
		b.vx = 4.0 if pose == "sidejump" else 0.0
		t = (selected.i + 0.5) * 1000.0 / PlayerArt.jump_fps
	return [b, t]


func _draw_stage() -> void:
	var s := _stage
	Draw.panel(s, Rect2(Vector2.ZERO, STAGE.size), Color("#111827"), 10, Color("#334155"), 1)
	for i in range(0, int(STAGE.size.x), 40):
		s.draw_line(Vector2(i, 0), Vector2(i, FLOOR_Y), Color(1, 1, 1, 0.03))
	s.draw_line(Vector2(0, FLOOR_Y), Vector2(STAGE.size.x, FLOOR_Y), Color("#475569"), 2.0)
	var info := "run: %s   jump: %s" % [run_variant, jump_variant]
	if paused:
		var posed := _posed_body()
		PlayerArt.draw(s, posed[0], posed[1])
		var what := "run frame %d" % (selected.i + 1) if selected.get("kind") == "run" else "%s frame %d" % [selected.get("pose"), selected.i + 1]
		info += "   ·   PAUSED on " + what
	else:
		PlayerArt.draw(s, p, _time)
		info += "   speed %.1f" % absf(p.vx)
	s.draw_string(Text.font, Vector2(14, STAGE.size.y - 12), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#64748b"))


## Small pre-scaled copy of a frame for the strip (drawing 1190 px sprites at
## 50 px directly can show up blank in some browsers, and looks aliased).
func _thumb(t: Texture2D) -> Texture2D:
	if _thumbs.has(t):
		return _thumbs[t]
	var img := t.get_image()
	var out: Texture2D = t
	if img:
		if img.is_compressed():
			img.decompress()
		var k := minf(84.0 / img.get_width(), 96.0 / img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(img)
	_thumbs[t] = out
	return out


func _slot(s: Control, r: Rect2, t: Texture2D, sel: Dictionary, live: bool) -> void:
	var is_sel: bool = paused and sel.kind == selected.get("kind") and sel.i == selected.get("i") and sel.get("pose", "") == selected.get("pose", "")
	var border := Color("#f59e0b") if is_sel else (Color("#10b981") if live else Color(0, 0, 0, 0))
	Draw.panel(s, r, Color("#1e293b"), 6, border, 2)
	if t:
		var th := _thumb(t)
		var k := minf((r.size.x - 4) / th.get_width(), (r.size.y - 4) / th.get_height())
		var sz := Vector2(th.get_width(), th.get_height()) * k
		s.draw_texture_rect(th, Rect2(r.get_center() - sz / 2, sz), false)
	_slots.append({"rect": r, "sel": sel})


func _draw_strip() -> void:
	var s := _strip
	var font: Font = Text.font_bold
	_slots.clear()
	s.draw_string(font, Vector2(0, 10), "RUN FRAMES  (click to inspect)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#94a3b8"))
	var frames := _load_list(run_paths())
	var running := not paused and p.is_grounded and absf(p.vx) > 3.5
	var cur := int(floorf(p.anim_progress)) % maxi(1, frames.size()) if running else -1
	for i in frames.size():
		_slot(s, Rect2(i * (SLOT.x + 4), 16, SLOT.x, SLOT.y), frames[i], {"kind": "run", "i": i}, i == cur)
	s.draw_string(font, Vector2(0, 92), "JUMP POSES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#94a3b8"))
	var live_pose := ""
	if not paused and not p.is_grounded:
		live_pose = "fall" if p.vy > 0 else ("doublejump" if p.jumps_left == 0 else ("sidejump" if absf(p.vx) > 1 else "jump"))
	var x := 0.0
	for pose in POSES:
		var list := _load_list(pose_paths(pose))
		var start := x
		for i in list.size():
			_slot(s, Rect2(x, 98, SLOT.x, SLOT.y), list[i], {"kind": "pose", "pose": pose, "i": i}, pose == live_pose)
			x += SLOT.x + 4
		s.draw_string(Text.font, Vector2(start, 98 + SLOT.y + 12), pose, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#64748b"))
		x += 14
