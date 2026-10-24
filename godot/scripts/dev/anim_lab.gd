class_name AnimLab
extends Control
## Developer menu > Animations: edit and test every character animation on
## the real renderer, then save it to the repo for everyone.
##
##  * Left: animation dropdown, its variants (new / duplicate / rename / delete)
##    and the frame list — each frame can be replaced, moved or removed, and
##    frames can be added. Changes live in this browser (user://anim_uploads/)
##    until "Save to repo" commits them (GitHubSave) and the game rebuilds.
##  * Right: preview of the selected animation (or gameplay: auto run & jump /
##    keys), play / pause / step, settings, "Use in game".
## Variants in the repo: data/anim_variants.json (anims / in_game / settings).

const LOCAL_DIR := "user://anim_uploads/"
const LOCAL_MANIFEST := LOCAL_DIR + "manifest.json"
const LIST_W := 300.0
const STAGE := Rect2(316, 10, 740, 292)
const FLOOR_Y := 256.0
const ROW_H := 58.0
const GRAVITY := 0.4
const JUMP := -10.5
const ACCEL := 1.2
const FRICTION := 0.75
const ICONS := "res://assets/ui/icons/%s.svg"
## How each animation is shown in "this animation" preview.
const POSED := ["jump", "sidejump", "doublejump", "fall", "lookdown", "sit", "pain", "dead", "hang"]

## Space reserved at the top (the developer menu's tab bar).
var top := 0.0

## Variants from data/anim_variants.json: anim -> {name -> [paths]}
var repo := {}
## Browser-side work: {"anims": {anim: {name: [paths]}}, "deleted": {anim: [names]}, "saved": {anim: [names]}}
var local := {"anims": {}, "deleted": {}, "saved": {}}
## Variant chosen per animation (what "Use in game" / "Save to repo" applies).
var chosen := {}
var settings := {"scale": 1.6, "anim_fps": 12.0, "run_rate": 0.026}

var anim := "run"
var preview := "anim" # "anim" = the selected animation, "game" = auto run & jump / keys
var paused := false
var selected := -1
var max_speed := 6.0

var p := PlayerBody.new()
var _time := 0.0
var _auto_jump_t := 1.0
var _auto_jumps := 0
var _applied := false
var _saved_state := {}
var _anim_pick: OptionButton
var _var_pick: OptionButton
var _list: VBoxContainer
var _list_title: Label
var _status: Label
var _play_btn: Button
var _mode_btns := {}
var _stage: Control
var _tex_cache := {}
var _thumbs := {}
var _js_cb: JavaScriptObject
var _pending: Array = []
var _pick_purpose := ""
var _dialog: FileDialog
var _gh: GitHubSave


func _ready() -> void:
	size = Vector2(1066, 600)
	_saved_state = {"overrides": PlayerArt.overrides.duplicate(), "scale": PlayerArt.scale,
		"fps": PlayerArt.anim_fps, "rate": PlayerBody.run_rate}
	_gh = GitHubSave.new()
	add_child(_gh)
	_gh.progress.connect(_say)
	_load_manifests()
	var bg := ColorRect.new()
	bg.color = Color("#0f172a")
	bg.position = Vector2(0, top)
	bg.size = Vector2(1066, 600 - top)
	add_child(bg)
	_build_left()
	_stage = Control.new()
	_stage.position = Vector2(STAGE.position.x, top + STAGE.position.y)
	_stage.size = STAGE.size
	_stage.clip_contents = true
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_build_right()
	p.x = 120
	p.y = FLOOR_Y - p.height
	p.is_grounded = true
	get_window().files_dropped.connect(_on_files_dropped)
	_select_anim(anim)


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)
	if not _applied:
		PlayerArt.overrides = _saved_state.overrides
		PlayerArt.scale = _saved_state.scale
		PlayerArt.anim_fps = _saved_state.fps
		PlayerBody.run_rate = _saved_state.rate


# --- data ---------------------------------------------------------------------------

func _load_manifests() -> void:
	var d: Variant = _read_json(PlayerArt.VARIANTS)
	if d is Dictionary:
		repo = d.get("anims", {}).duplicate(true)
		chosen = d.get("in_game", {}).duplicate()
		settings.merge(d.get("settings", {}), true)
	var l: Variant = _read_json(LOCAL_MANIFEST)
	if l is Dictionary:
		for k in ["anims", "deleted", "saved"]:
			local[k] = l.get(k, {})
		# The lab reopens on the variants picked last time.
		chosen.merge(l.get("chosen", {}), true)
	# Drop local copies that were saved and are now part of the repo build.
	for a in local.saved:
		for name in local.saved[a]:
			if repo.get(a, {}).has(name):
				local.anims.get(a, {}).erase(name)
	local.saved = {}
	PlayerArt.scale = settings.scale
	PlayerArt.anim_fps = settings.anim_fps
	PlayerBody.run_rate = settings.run_rate


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _save_local() -> void:
	DirAccess.make_dir_recursive_absolute(LOCAL_DIR)
	var f := FileAccess.open(LOCAL_MANIFEST, FileAccess.WRITE)
	if f:
		var out := local.duplicate()
		out["chosen"] = chosen
		f.store_string(JSON.stringify(out, " "))


## Variant names of an animation: original, repo ones (not deleted), local ones.
func variant_names(a: String) -> Array:
	var names := ["original"]
	for n in repo.get(a, {}):
		if not local.deleted.get(a, []).has(n):
			names.append(n)
	for n in local.anims.get(a, {}):
		if not names.has(n):
			names.append(n)
	return names


func is_local(a: String, name: String) -> bool:
	return local.anims.get(a, {}).has(name)


func paths_of(a: String, name: String) -> Array:
	if is_local(a, name):
		return local.anims[a][name]
	if name == "original" or not repo.get(a, {}).has(name):
		return PlayerArt.original_paths(a)
	return repo[a][name]


func current_variant() -> String:
	var v: String = chosen.get(anim, "original")
	return v if variant_names(anim).has(v) else "original"


func current_paths() -> Array:
	return paths_of(anim, current_variant())


func has_unsaved() -> bool:
	for a in local.anims:
		if not local.anims[a].is_empty():
			return true
	for a in local.deleted:
		if not local.deleted[a].is_empty():
			return true
	return false


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


func _textures(paths: Array) -> Array:
	var out := []
	for path in paths:
		var t := _tex(path)
		if t:
			out.append(t)
	return out


## Push the chosen variants into the renderer (preview = what the game would show).
func _apply_preview() -> void:
	var o := {}
	for a in chosen:
		var v: String = chosen[a]
		if v != "original" and variant_names(a).has(v):
			o[a] = _textures(paths_of(a, v))
	PlayerArt.overrides = o


# --- left: animation, variants, frames ------------------------------------------------

func _build_left() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(0, top)
	panel.size = Vector2(LIST_W, 600 - top)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(14, top + 10)
	box.custom_minimum_size = Vector2(LIST_W - 28, 0)
	box.add_theme_constant_override("separation", 5)
	add_child(box)
	box.add_child(UiKit.label("ANIMATION", 11, Color("#94a3b8"), true))
	_anim_pick = _picker()
	for a in PlayerArt.ANIMS:
		_anim_pick.add_item(a)
	_anim_pick.item_selected.connect(func(i): _select_anim(_anim_pick.get_item_text(i)))
	box.add_child(_anim_pick)
	box.add_child(UiKit.label("VARIANT", 11, Color("#94a3b8"), true))
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 2)
	_var_pick = _picker()
	_var_pick.custom_minimum_size = Vector2(LIST_W - 28 - 4 * 30, 0)
	_var_pick.item_selected.connect(func(i): _select_variant(_var_pick.get_item_metadata(i)))
	vrow.add_child(_var_pick)
	for it in [["plus", "New variant from PNG files…", open_picker.bind("new")],
			["copy", "Duplicate this variant", duplicate_variant],
			["pencil", "Rename this variant", _rename_dialog],
			["trash-2", "Delete this variant", delete_variant]]:
		var b := UiKit.icon_button(ICONS % it[0], it[1], 28)
		b.pressed.connect(it[2])
		vrow.add_child(b)
	box.add_child(vrow)
	_list_title = UiKit.label("", 11, Color("#94a3b8"), true)
	box.add_child(_list_title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(LIST_W - 28, 600 - top - 10 - 196)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(LIST_W - 40, 0)
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)
	var add := UiKit.button("Add frames…", Vector2(LIST_W - 28, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
	add.icon = load(ICONS % "image-plus")
	add.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.add_theme_constant_override("icon_max_width", 18)
	add.tooltip_text = "Add PNGs after the selected frame (or at the end).\nYou can also drag PNGs onto the window."
	add.pressed.connect(open_picker.bind("add"))
	box.add_child(add)


func _picker() -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", 12)
	o.focus_mode = Control.FOCUS_NONE
	o.clip_text = true
	o.custom_minimum_size = Vector2(LIST_W - 28, 0)
	return o


func _select_anim(a: String) -> void:
	anim = a
	_anim_pick.select(PlayerArt.ANIMS.keys().find(a))
	selected = -1
	set_paused(false)
	_refresh_variants()
	_refresh_frames()
	_apply_preview()


func _select_variant(name: String) -> void:
	if name == "original":
		chosen.erase(anim)
	else:
		chosen[anim] = name
	selected = -1
	_save_local()
	_refresh_frames()
	_apply_preview()


func _refresh_variants() -> void:
	_var_pick.clear()
	var names := variant_names(anim)
	var cur := current_variant()
	for i in names.size():
		var n: String = names[i]
		var label := n
		if is_local(anim, n):
			label += "  • unsaved"
		_var_pick.add_item(label)
		_var_pick.set_item_metadata(i, n)
		if n == cur:
			_var_pick.select(i)


func _refresh_frames() -> void:
	for c in _list.get_children():
		c.queue_free()
	var paths := current_paths()
	_list_title.text = "FRAMES (%d)%s" % [paths.size(), "" if is_local(anim, current_variant()) or current_variant() != "original" else "  · original art"]
	for i in paths.size():
		_list.add_child(_frame_row(i, paths[i]))


func _frame_row(i: int, path: String) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1e293b") if i != selected else Color("#78350f")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(3)
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			select_frame(i))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	row.add_child(h)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(42, ROW_H - 8)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _tex(path)
	if t:
		thumb.texture = _thumb(t)
	h.add_child(thumb)
	var name := UiKit.label("#%d  %s" % [i + 1, path.get_file()], 10, Color("#cbd5e1"))
	name.custom_minimum_size = Vector2(96, 0)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(name)
	for it in [["upload", "Replace this frame with a PNG", func(): _replace_at(i)],
			["arrow-up", "Move up", func(): move_frame(i, -1)],
			["arrow-down", "Move down", func(): move_frame(i, 1)],
			["x", "Remove this frame", func(): remove_frame(i)]]:
		var b := UiKit.icon_button(ICONS % it[0], it[1], 26)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(it[2])
		h.add_child(b)
	return row


func select_frame(i: int) -> void:
	selected = i
	set_paused(true)
	_refresh_frames()


## Small pre-scaled copy for the list (1190 px sprites drawn at 50 px can show
## up blank in some browsers, and look aliased).
func _thumb(t: Texture2D) -> Texture2D:
	if _thumbs.has(t):
		return _thumbs[t]
	var img := t.get_image()
	var out: Texture2D = t
	if img:
		if img.is_compressed():
			img.decompress()
		var k := minf(84.0 / img.get_width(), 100.0 / img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(img)
	_thumbs[t] = out
	return out


# --- editing -------------------------------------------------------------------------

## Make the current variant editable in this browser; returns its (local) name.
func _editable() -> String:
	var cur := current_variant()
	if is_local(anim, cur):
		return cur
	var name := cur
	if cur == "original":
		name = _unique("original edit")
	local.anims.get_or_add(anim, {})[name] = current_paths().duplicate()
	chosen[anim] = name
	return name


func _unique(base: String) -> String:
	var names := variant_names(anim)
	var name := base
	var n := 2
	while names.has(name):
		name = "%s %d" % [base, n]
		n += 1
	return name


func _after_edit(msg: String) -> void:
	_save_local()
	_refresh_variants()
	_refresh_frames()
	_apply_preview()
	_say(msg)


func move_frame(i: int, d: int) -> void:
	var list: Array = local.anims[anim][_editable()]
	var j := i + d
	if j < 0 or j >= list.size():
		return
	var tmp: String = list[i]
	list[i] = list[j]
	list[j] = tmp
	selected = j
	_after_edit("Frame moved.")


func remove_frame(i: int) -> void:
	if current_paths().size() <= 1:
		_say("An animation needs at least one frame.")
		return
	var list: Array = local.anims[anim][_editable()]
	list.remove_at(i)
	selected = mini(i, list.size() - 1)
	_after_edit("Frame %d removed." % (i + 1))


func _replace_at(i: int) -> void:
	selected = i
	open_picker("replace")


func duplicate_variant() -> void:
	var name := _unique(current_variant() + " copy")
	local.anims.get_or_add(anim, {})[name] = current_paths().duplicate()
	chosen[anim] = name
	_after_edit("Duplicated as '%s'." % name)


func delete_variant() -> void:
	var cur := current_variant()
	if cur == "original":
		_say("The original art can't be deleted.")
		return
	if is_local(anim, cur):
		local.anims[anim].erase(cur)
	if repo.get(anim, {}).has(cur):
		local.deleted.get_or_add(anim, []).append(cur)
	chosen.erase(anim)
	selected = -1
	_after_edit("Deleted '%s'%s." % [cur, " (removed from the repo on Save)" if repo.get(anim, {}).has(cur) else ""])


func rename_variant(new_name: String) -> void:
	new_name = new_name.strip_edges()
	var cur := current_variant()
	if new_name == "" or new_name == cur or cur == "original" or variant_names(anim).has(new_name):
		_say("Pick a new, unused name.")
		return
	var paths := current_paths().duplicate()
	if is_local(anim, cur):
		local.anims[anim].erase(cur)
	if repo.get(anim, {}).has(cur):
		local.deleted.get_or_add(anim, []).append(cur)
	local.anims.get_or_add(anim, {})[new_name] = paths
	chosen[anim] = new_name
	_after_edit("Renamed to '%s'." % new_name)


func _rename_dialog() -> void:
	if current_variant() == "original":
		_say("Duplicate the original first, then rename the copy.")
		return
	var root := Control.new()
	root.size = Vector2(1066, 600)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = root.size
	root.add_child(dim)
	var card := Panel.new()
	card.position = Vector2(333, 220)
	card.size = Vector2(400, 140)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", sb)
	root.add_child(card)
	var edit := LineEdit.new()
	edit.text = current_variant()
	edit.position = Vector2(20, 24)
	edit.size = Vector2(360, 36)
	card.add_child(edit)
	var ok := UiKit.button("Rename", Vector2(110, 34), 12, Color("#059669"))
	ok.position = Vector2(270, 84)
	ok.pressed.connect(func():
		rename_variant(edit.text)
		root.queue_free())
	card.add_child(ok)
	var cancel := UiKit.button("Cancel", Vector2(110, 34), 12)
	cancel.position = Vector2(150, 84)
	cancel.pressed.connect(root.queue_free)
	card.add_child(cancel)
	edit.text_submitted.connect(func(t):
		rename_variant(t)
		root.queue_free())
	add_child(root)
	edit.grab_focus()
	edit.select_all()


# --- uploads ------------------------------------------------------------------------

## purpose: "new" (new variant), "add" (after selected), "replace" (selected frame).
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
	if is_visible_in_tree():
		_pick_purpose = "add"
		_on_paths(paths)


## files: [[file_name, PackedByteArray], …]
func receive_files(files: Array, purpose: String) -> void:
	files = files.filter(func(f): return _image_ok(f[1]))
	if files.is_empty():
		_say("No readable PNG/WebP/JPG files.")
		return
	match purpose:
		"new":
			var name := _unique("v%d" % (variant_names(anim).size()))
			local.anims.get_or_add(anim, {})[name] = _store(files)
			chosen[anim] = name
			selected = -1
			_after_edit("New variant '%s' with %d frame(s)." % [name, files.size()])
		"replace":
			var list: Array = local.anims[anim][_editable()]
			var i := clampi(selected, 0, list.size() - 1)
			list[i] = _store(files.slice(0, 1))[0]
			selected = i
			_after_edit("Frame %d replaced." % (i + 1))
		"add":
			var list: Array = local.anims[anim][_editable()]
			var at := list.size() if selected < 0 else selected + 1
			var paths := _store(files)
			for k in paths.size():
				list.insert(at + k, paths[k])
			_after_edit("%d frame(s) added." % paths.size())


func _image_ok(bytes: PackedByteArray) -> bool:
	var img := Image.new()
	return img.load_png_from_buffer(bytes) == OK or img.load_webp_from_buffer(bytes) == OK or img.load_jpg_from_buffer(bytes) == OK


## Writes uploaded files to user://anim_uploads/<anim>/ and returns their paths.
func _store(files: Array) -> Array:
	var dir := LOCAL_DIR + anim + "/"
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


# --- save to repo -------------------------------------------------------------------

## Files to commit: new PNGs + the merged manifest. remote = manifest text from GitHub.
func build_commit(remote: String) -> Dictionary:
	var d: Variant = JSON.parse_string(remote) if remote != "" else null
	var manifest: Dictionary = d if d is Dictionary else {"anims": {}, "in_game": {}, "settings": {}}
	var anims: Dictionary = manifest.get_or_add("anims", {})
	var files := {}
	for a in local.deleted:
		for name in local.deleted[a]:
			anims.get(a, {}).erase(name)
	for a in local.anims:
		for name in local.anims[a]:
			var slug: String = str(name).to_lower().validate_filename().replace(" ", "-")
			var out := []
			var list: Array = local.anims[a][name]
			for i in list.size():
				var path: String = list[i]
				if path.begins_with("user://"):
					# user://…/<ticks>-run1.png -> 01-run1.png (frame order, no clashes)
					var file := path.get_file()
					file = "%02d-%s" % [i + 1, file.substr(file.find("-") + 1)]
					var repo_path := "godot/assets/anim_test/%s/%s/%s" % [a, slug, file]
					files[repo_path] = FileAccess.get_file_as_bytes(path)
					out.append("res://" + repo_path.trim_prefix("godot/"))
				else:
					out.append(path)
			anims.get_or_add(a, {})[name] = out
	var in_game := {}
	for a in chosen:
		if chosen[a] != "original" and anims.get(a, {}).has(chosen[a]):
			in_game[a] = chosen[a]
	manifest["in_game"] = in_game
	manifest["settings"] = {"scale": PlayerArt.scale, "anim_fps": PlayerArt.anim_fps, "run_rate": PlayerBody.run_rate}
	files["godot/data/anim_variants.json"] = (JSON.stringify(manifest, " ") + "\n").to_utf8_buffer()
	return files


func save_to_repo() -> void:
	if not GitHubSave.has_token():
		GitHubSave.token_dialog(self, _on_token)
		return
	_say("Reading the repo…")
	var remote := await _gh.read_text("godot/data/anim_variants.json")
	if not remote.ok:
		_say("Save failed: " + remote.error)
		return
	var files := build_commit(remote.text)
	var res := await _gh.commit(files, "Animation lab: update character animations\n\nSaved from Developer mode > Animations in the browser.")
	if not res.ok:
		_say("Save failed: " + res.error)
		if "token" in res.error:
			GitHubSave.forget_token()
		return
	for a in local.anims:
		local.saved[a] = local.anims[a].keys()
	local.deleted = {}
	_save_local()
	_applied = true
	_say("Saved to the repo. Everyone gets it after the next build (~2 min).")


# --- right: preview & settings -----------------------------------------------------

func _build_right() -> void:
	var x0 := STAGE.position.x
	var y0 := top + STAGE.end.y + 8
	var bar := HBoxContainer.new()
	bar.position = Vector2(x0, y0)
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	_play_btn = UiKit.icon_button(ICONS % "pause", "Pause / play", 36)
	_play_btn.pressed.connect(func(): set_paused(not paused))
	bar.add_child(_play_btn)
	var prev := UiKit.icon_button(ICONS % "chevron-left", "Previous frame", 36)
	prev.pressed.connect(step_frame.bind(-1))
	bar.add_child(prev)
	var next := UiKit.icon_button(ICONS % "chevron-right", "Next frame", 36)
	next.pressed.connect(step_frame.bind(1))
	bar.add_child(next)
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(12, 36)
	bar.add_child(sep)
	for m in [["anim", "This animation"], ["game", "Gameplay (auto / keys)"]]:
		var b := UiKit.button(m[1], Vector2(0, 32), 11, Color("#1e293b"), Color("#cbd5e1"))
		b.custom_minimum_size = Vector2(150 if m[0] == "anim" else 170, 32)
		b.pressed.connect(set_preview.bind(m[0]))
		bar.add_child(b)
		_mode_btns[m[0]] = b
	set_preview(preview)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(x0, y0 + 48)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	_slider(grid, "Run speed (gameplay)", 2.0, 12.0, 0.1, max_speed, "%.1f", func(v): max_speed = v)
	_slider(grid, "Walk/run frame rate", 0.008, 0.08, 0.001, PlayerBody.run_rate, "%.3f", func(v): PlayerBody.run_rate = v)
	_slider(grid, "Pose frames / s", 2.0, 30.0, 1.0, PlayerArt.anim_fps, "%d", func(v): PlayerArt.anim_fps = v)
	_slider(grid, "Sprite scale", 0.8, 2.6, 0.05, PlayerArt.scale, "%.2f", func(v): PlayerArt.scale = v)

	var actions := HBoxContainer.new()
	actions.position = Vector2(x0, 600 - 48)
	actions.add_theme_constant_override("separation", 8)
	add_child(actions)
	var use := UiKit.button("Use in game", Vector2(130, 36), 12, Color("#1e293b"))
	use.tooltip_text = "Play the game with these frames until the page is reloaded"
	use.pressed.connect(func():
		_applied = true
		_say("Used in game (until reload)."))
	actions.add_child(use)
	var save := UiKit.button("Save to repo", Vector2(150, 36), 12, Color("#059669"))
	save.icon = load(ICONS % "git-commit-horizontal")
	save.add_theme_constant_override("icon_max_width", 18)
	save.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	save.tooltip_text = "Commit the variants, the chosen ones and the settings to GitHub;\nthe game for everyone updates after the automatic build."
	save.pressed.connect(save_to_repo)
	actions.add_child(save)
	_status = UiKit.label("Drag PNGs onto the window to add frames.", 11, Color("#94a3b8"))
	_status.custom_minimum_size = Vector2(440, 36)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	actions.add_child(_status)


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(340, 0)
	col.add_theme_constant_override("separation", 0)
	var row := HBoxContainer.new()
	var l := UiKit.label(label, 11, Color("#cbd5e1"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := UiKit.label(fmt % value, 11, Color("#34d399"), true)
	row.add_child(v)
	col.add_child(row)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(x):
		v.text = fmt % x
		on_change.call(x))
	col.add_child(s)
	parent.add_child(col)


func _say(s: String) -> void:
	if _status:
		_status.text = s


func set_preview(m: String) -> void:
	preview = m
	for k in _mode_btns:
		var b: Button = _mode_btns[k]
		var sb: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		sb.bg_color = Color("#059669") if k == m else Color("#1e293b")
		b.add_theme_stylebox_override("normal", sb)
	if m == "game":
		set_paused(false)


func set_paused(on: bool) -> void:
	paused = on
	if _play_btn:
		_play_btn.icon = load(ICONS % ("play" if paused else "pause"))
	if paused and selected < 0:
		selected = 0
		_refresh_frames()
	if paused:
		preview = "anim"
		set_preview.call_deferred("anim")


func step_frame(d: int) -> void:
	var n := current_paths().size()
	selected = posmod(maxi(selected, 0) + d if paused else 0, n)
	set_paused(true)
	_refresh_frames()


# --- character ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not event.is_echo():
		set_preview("game")
		_jump()
	elif event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		set_preview("game")


func _jump() -> void:
	if p.jumps_left > 0:
		Audio.jump_sound(p.jumps_left == 1)
		p.vy = JUMP
		p.jumps_left -= 1
		p.is_grounded = false


func _process(delta: float) -> void:
	_stage.queue_redraw()
	if paused:
		return
	var dt := minf(delta, 0.1)
	var d60 := dt * 60.0
	_time += dt * 1000.0
	if preview == "anim" and anim in POSED:
		return
	var speed := max_speed
	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var auto := preview == "anim" or not (left or right)
	if preview == "anim":
		speed = {"idle": 0.0, "walk": 2.5}.get(anim, max_speed)
	if auto:
		if p.x > STAGE.size.x - 140:
			p.facing_right = false
		elif p.x < 110:
			p.facing_right = true
		right = p.facing_right and speed > 0
		left = not p.facing_right and speed > 0
		if preview == "game":
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
	p.vx = clampf(p.vx, -speed, speed)
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


## A body (and time) that makes PlayerArt draw `anim` — on frame `frame` if >= 0.
func _posed(frame: int) -> Array:
	var b := PlayerBody.new()
	b.x = STAGE.size.x / 2 - b.width / 2
	b.y = FLOOR_Y - b.height
	b.facing_right = true
	b.is_grounded = true
	var o := {}
	var t := _time
	var n := maxi(1, current_paths().size())
	match anim:
		"idle":
			if frame >= 0: t = (frame + 0.5) * 360.0
		"walk", "run":
			b.vx = 2.5 if anim == "walk" else 6.0
			b.anim_progress = frame + 0.5 if frame >= 0 else _time / 1000.0 * 10.0
		"sit", "pain":
			o = {"sitting": true} if anim == "sit" else {"pain": true}
			if frame >= 0: t = (frame + 0.5) * 240.0
		_:
			if frame >= 0: t = (frame + 0.5) * 1000.0 / PlayerArt.anim_fps
			match anim:
				"lookdown": o = {"looking_down": true}
				"dead": o = {"dead": true}
				"hang": o = {"hanging": true}
				_:
					b.is_grounded = false
					b.y -= 70
					b.vy = 5.0 if anim == "fall" else -5.0
					b.jumps_left = 0 if anim == "doublejump" else 1
					b.vx = 4.0 if anim == "sidejump" else 0.0
	return [b, t, o, n]


func _draw_stage() -> void:
	var s := _stage
	Draw.panel(s, Rect2(Vector2.ZERO, STAGE.size), Color("#111827"), 10, Color("#334155"), 1)
	for i in range(0, int(STAGE.size.x), 40):
		s.draw_line(Vector2(i, 0), Vector2(i, FLOOR_Y), Color(1, 1, 1, 0.03))
	s.draw_line(Vector2(0, FLOOR_Y), Vector2(STAGE.size.x, FLOOR_Y), Color("#475569"), 2.0)
	var info := "%s · %s" % [anim, current_variant()]
	if paused or (preview == "anim" and anim in POSED):
		var posed := _posed(selected if paused else -1)
		PlayerArt.draw(s, posed[0], posed[1], false, posed[2])
		info += ("   ·   PAUSED on frame %d / %d" % [selected + 1, posed[3]]) if paused else "   ·   looping"
	else:
		PlayerArt.draw(s, p, _time)
		info += "   ·   " + ("gameplay" if preview == "game" else "looping")
	s.draw_string(Text.font, Vector2(14, STAGE.size.y - 12), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#64748b"))


func _on_token(ok: bool) -> void:
	if ok:
		save_to_repo()
