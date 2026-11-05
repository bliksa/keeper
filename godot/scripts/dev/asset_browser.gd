class_name AssetBrowser
extends Control
## Developer tools: a browser of the images in the game (repo) and the ones
## uploaded in this browser. Used by the animation lab (frames, preview
## background) and the level editor (background layers).
##
##  * Folders: character art, backgrounds, saved animation variants, and the
##    uploads that live only in this browser (user://, IndexedDB on the web).
##  * Upload… (or drop PNGs on the window) stores files in user://uploads/.
##  * Every tile can be downloaded (the original file for uploads, a PNG of the
##    imported image for repo art); uploads can also be deleted.
##  * A click on a tile emits `picked(path)`; "" is the optional "none" tile.

signal picked(path: String)
signal closed

const UPLOAD_DIR := "user://uploads/"
const ANIM_UPLOAD_DIR := "user://anim_uploads/"
const ICONS := "res://assets/ui/icons/%s.svg"
const IMAGE_EXT := ["png", "webp", "jpg", "jpeg"]
## Uploads bigger than this are scaled down when loaded (big textures don't load
## in some browsers; the committed copies are scaled the same way).
const MAX_PX := 4096

## Heading of the overlay.
var title := "Assets"
## When set, the first tile is "none" (picks ""), labelled with this.
var none_label := ""
## A path whose folder opens first (e.g. the current frame or layer).
var start_path := ""
## Optional check from the caller: paths still in use can't be deleted.
var in_use: Callable = Callable()
## Space reserved at the top (the developer menu's tab bar).
var top := 0.0

var grid: GridContainer
var folder_pick: OptionButton
var search: LineEdit
var status: Label

var _thumb_queue: Array = []
var _js_cb: JavaScriptObject
var _pending: Array = []
var _dialog: FileDialog
var _save_dialog: FileDialog
var _save_bytes := PackedByteArray()

static var _tex_cache := {}
static var _thumbs := {}


# --- static helpers (shared with the lab, the editor and the game) -----------------

static func is_image(f: String) -> bool:
	return f.get_extension().to_lower() in IMAGE_EXT


static func is_local(path: String) -> bool:
	return path.begins_with("user://")


## Folders that hold images: [[label, dir], …].
static func folders() -> Array:
	var out := [["Character art  ·  assets/images", "res://assets/images/"]]
	if not ResourceLoader.list_directory("res://assets/backgrounds/").is_empty():
		out.append(["Backgrounds  ·  assets/backgrounds", "res://assets/backgrounds/"])
	var stack := ["res://assets/anim_test/"]
	while not stack.is_empty():
		var d: String = stack.pop_front()
		var has_img := false
		for f in ResourceLoader.list_directory(d):
			if f.ends_with("/"):
				stack.append(d + f)
			elif is_image(f):
				has_img = true
		if has_img:
			out.append(["Saved  ·  " + d.trim_prefix("res://assets/anim_test/").trim_suffix("/"), d])
	if DirAccess.dir_exists_absolute(UPLOAD_DIR):
		out.append(["Uploaded in this browser", UPLOAD_DIR])
	if DirAccess.dir_exists_absolute(ANIM_UPLOAD_DIR):
		out.append(["Animation uploads (this browser)", ANIM_UPLOAD_DIR])
	return out


## Images in a folder (uploads are searched one level of sub-folders deep).
static func list(dir: String) -> Array:
	var out := []
	if is_local(dir):
		for f in DirAccess.get_files_at(dir):
			if is_image(f):
				out.append(dir + f)
		for sub in DirAccess.get_directories_at(dir):
			for f in DirAccess.get_files_at(dir + sub):
				if is_image(f):
					out.append(dir + sub + "/" + f)
	else:
		for f in ResourceLoader.list_directory(dir):
			if is_image(f):
				out.append(dir + f)
	return out


## Uploaded files are stored as <ticks>-<original name>; show the original name.
static func label(path: String) -> String:
	var f := path.get_file()
	if is_local(path) and f.find("-") > 0 and f.get_slice("-", 0).is_valid_int():
		f = f.substr(f.find("-") + 1)
	return f


static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if is_local(path):
		if FileAccess.file_exists(path):
			var img := decode(FileAccess.get_file_as_bytes(path))
			if img:
				t = ImageTexture.create_from_image(fit(img))
	elif ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


## Forget a cached texture (after the file was replaced or deleted).
static func forget(path: String) -> void:
	_tex_cache.erase(path)


## Small pre-scaled copy for lists (big sprites drawn tiny can show up blank in
## some browsers, and look aliased).
static func thumb(t: Texture2D, w := 84.0, h := 100.0) -> Texture2D:
	if t == null:
		return null
	var key := [t, w, h]
	if _thumbs.has(key):
		return _thumbs[key]
	var img := t.get_image()
	var out: Texture2D = t
	if img:
		if img.is_compressed():
			img.decompress()
		var k := minf(w / img.get_width(), h / img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		out = ImageTexture.create_from_image(img)
	_thumbs[key] = out
	return out


## "png", "jpg" or "webp" from the file's signature, "" for anything else.
static func format_of(bytes: PackedByteArray) -> String:
	if bytes.size() < 12:
		return ""
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		return "png"
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return "jpg"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## Decodes PNG / WebP / JPEG bytes (chosen by their signature, so other files
## don't spam decoder errors); null when it isn't one of those.
static func decode(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match format_of(bytes):
		"png": err = img.load_png_from_buffer(bytes)
		"jpg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
	return img if err == OK else null


## Scales an image down so neither side exceeds max_px (in place; returns it).
static func fit(img: Image, max_px := MAX_PX) -> Image:
	if img.get_width() > max_px or img.get_height() > max_px:
		var k := float(max_px) / maxi(img.get_width(), img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return img


static func image_ok(bytes: PackedByteArray) -> bool:
	return decode(bytes) != null


## The bytes to download / commit for an asset: the original file for uploads,
## a PNG of the imported image for repo art (its source file is not in the build).
static func bytes_of(path: String) -> PackedByteArray:
	if is_local(path):
		return FileAccess.get_file_as_bytes(path)
	var t := tex(path)
	if t == null:
		return PackedByteArray()
	var img := t.get_image()
	if img == null:
		return PackedByteArray()
	if img.is_compressed():
		img.decompress()
	return img.save_png_to_buffer()


## File name to download / commit an asset as.
static func file_name(path: String) -> String:
	var n := label(path)
	return n if is_local(path) else n.get_basename() + ".png"


## Stores uploaded files ([[name, bytes], …]) in dir; returns the new paths.
## The extension follows the file's real format (".jfif" → ".jpg", none → ".png").
static func store(files: Array, dir := UPLOAD_DIR) -> Array:
	DirAccess.make_dir_recursive_absolute(dir)
	var out := []
	for f in files:
		var fmt := format_of(f[1])
		if fmt == "" or decode(f[1]) == null:
			continue
		var base := String(f[0]).get_file().get_basename()
		if base == "":
			base = "image"
		var path: String = dir + "%d-%s.%s" % [Time.get_ticks_usec(), base, fmt]
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa:
			fa.store_buffer(f[1])
			fa.close()
			out.append(path)
	return out


# --- the overlay -----------------------------------------------------------------------

func _ready() -> void:
	position = Vector2(0, top)
	size = Vector2(1066, 600 - top)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = size
	add_child(dim)
	var card := Panel.new()
	card.position = Vector2(40, 14)
	card.size = Vector2(986, size.y - 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)
	var head := HBoxContainer.new()
	head.position = Vector2(16, 12)
	head.size = Vector2(954, 34)
	head.add_theme_constant_override("separation", 8)
	card.add_child(head)
	var t := UiKit.label(title, 16, Color.WHITE, true)
	t.custom_minimum_size = Vector2(0, 34)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	folder_pick = OptionButton.new()
	folder_pick.focus_mode = Control.FOCUS_NONE
	folder_pick.add_theme_font_size_override("font_size", 12)
	folder_pick.custom_minimum_size = Vector2(270, 34)
	folder_pick.item_selected.connect(func(_i): fill())
	head.add_child(folder_pick)
	search = LineEdit.new()
	search.placeholder_text = "Filter by name"
	search.custom_minimum_size = Vector2(170, 34)
	search.add_theme_font_size_override("font_size", 12)
	search.text_changed.connect(func(_t): fill())
	head.add_child(search)
	var up := UiKit.button("Upload…", Vector2(104, 34), 12, Color("#1e293b"), Color("#cbd5e1"))
	up.icon = load(ICONS % "upload")
	up.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	up.add_theme_constant_override("icon_max_width", 16)
	up.tooltip_text = "Upload PNG / WebP / JPG files into this browser\n(you can also drop them onto the window)"
	up.pressed.connect(open_upload)
	head.add_child(up)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := UiKit.icon_button(ICONS % "x", "Close (Esc)", 34)
	close.pressed.connect(close_browser)
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.position = Vector2(16, 56)
	sc.size = Vector2(954, card.size.y - 88)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(sc)
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	status = UiKit.label("Click an image to use it  ·  corner icons: download, delete (uploads only)  ·  drop files here to upload", 11, Color("#94a3b8"))
	status.position = Vector2(16, card.size.y - 26)
	status.size = Vector2(954, 18)
	card.add_child(status)
	refresh_folders()
	get_window().files_dropped.connect(_on_files_dropped)


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)
	if _js_cb != null and OS.has_feature("web"):
		# An upload still being read must not call into this freed browser.
		JavaScriptBridge.eval("window.godotAssetFile = null;")
		_js_cb = null


## Rebuilds the folder list; selects `select_dir`, or the folder of start_path.
func refresh_folders(select_dir := "") -> void:
	folder_pick.clear()
	var best := 0
	var best_len := -1
	var fs := folders()
	for i in fs.size():
		folder_pick.add_item(fs[i][0])
		folder_pick.set_item_metadata(i, fs[i][1])
		var d: String = fs[i][1]
		if select_dir != "":
			if d == select_dir:
				best = i
				best_len = 9999
		elif start_path != "" and start_path.begins_with(d) and d.length() > best_len:
			best = i
			best_len = d.length()
	folder_pick.select(best)
	fill()


func current_dir() -> String:
	return folder_pick.get_item_metadata(folder_pick.selected) if folder_pick.item_count > 0 else ""


func fill() -> void:
	for c in grid.get_children():
		c.queue_free()
	_thumb_queue.clear()
	var q := search.text.strip_edges().to_lower()
	var paths := list(current_dir())
	if none_label != "":
		paths.push_front("")
	for path in paths:
		var name := label(path) if path != "" else none_label
		if q != "" and path != "" and not name.to_lower().contains(q):
			continue
		grid.add_child(_tile(path, name))


func _tile(path: String, name: String) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(112, 132)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = path if path != "" else name
	var st := StyleBoxFlat.new()
	st.bg_color = Color("#1e293b")
	st.set_corner_radius_all(8)
	if path == start_path and path != "":
		st.border_color = Color("#f59e0b")
		st.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = Color("#334155")
	hv.border_color = Color("#34d399")
	hv.set_border_width_all(2)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	var img := TextureRect.new()
	img.position = Vector2(6, 6)
	img.size = Vector2(100, 100)
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(img)
	var l := UiKit.label(name, 10, Color("#cbd5e1"))
	l.position = Vector2(4, 108)
	l.size = Vector2(104, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.pressed.connect(pick.bind(path))
	if path != "":
		_thumb_queue.append([img, path])
		# Small corner actions: download, and delete for uploads.
		var dl := UiKit.icon_button(ICONS % "download", "Download " + file_name(path), 22)
		dl.position = Vector2(86, 4)
		dl.pressed.connect(download.bind(path))
		b.add_child(dl)
		if can_delete(path):
			var del := UiKit.icon_button(ICONS % "trash-2", "Delete this upload", 22)
			del.position = Vector2(86, 30)
			del.pressed.connect(delete_asset.bind(path))
			b.add_child(del)
	return b


func pick(path: String) -> void:
	picked.emit(path)
	close_browser()


func close_browser() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()


func _say(s: String) -> void:
	if status:
		status.text = s


## Downloads an asset (web: a browser download; desktop: a save dialog).
func download(path: String) -> void:
	var bytes := bytes_of(path)
	if bytes.is_empty():
		_say("Can't read %s." % label(path))
		return
	var name := file_name(path)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, name, "image/" + ("jpeg" if name.get_extension().to_lower() in ["jpg", "jpeg"] else name.get_extension().to_lower()))
		_say("Downloaded %s." % name)
	elif DisplayServer.get_name() == "headless":
		_say("Download ready: %s (%d bytes)." % [name, bytes.size()])
	else:
		if _save_dialog == null:
			_save_dialog = FileDialog.new()
			_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
			_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			_save_dialog.file_selected.connect(_save_to)
			add_child(_save_dialog)
		_save_bytes = bytes
		_save_dialog.current_file = name
		_save_dialog.popup_centered(Vector2i(800, 500))


func _save_to(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(_save_bytes)
		_say("Saved %s." % path.get_file())


## Only plain uploads can be deleted (not repo art, not the lab's frame files),
## and not while something still uses them.
func can_delete(path: String) -> bool:
	return path.begins_with(UPLOAD_DIR)


## Deletes an uploaded file. Returns false when it isn't allowed.
func delete_asset(path: String) -> bool:
	if not can_delete(path) or not FileAccess.file_exists(path):
		return false
	if in_use.is_valid() and in_use.call(path):
		_say("%s is still used (a layer or a frame); remove it there first." % label(path))
		return false
	DirAccess.remove_absolute(path)
	forget(path)
	_say("Deleted %s." % label(path))
	var keep := current_dir()
	refresh_folders(keep if DirAccess.dir_exists_absolute(keep) or not is_local(keep) else "")
	return true


# --- uploads ------------------------------------------------------------------------------

func open_upload() -> void:
	_pending.clear()
	if OS.has_feature("web"):
		if _js_cb == null:
			_js_cb = JavaScriptBridge.create_callback(_on_js_file)
			var win := JavaScriptBridge.get_interface("window")
			win.godotAssetFile = _js_cb
		JavaScriptBridge.eval("""(function(){
			const i = document.createElement('input');
			i.type = 'file'; i.multiple = true; i.accept = 'image/png,image/webp,image/jpeg';
			i.onchange = async () => {
				const fs = [...i.files].sort((a, b) => a.name.localeCompare(b.name, undefined, {numeric: true}));
				for (const f of fs) {
					const d = await new Promise(r => { const rd = new FileReader(); rd.onload = () => r(rd.result.split(',')[1]); rd.readAsDataURL(f); });
					if (typeof window.godotAssetFile !== 'function') return;
					window.godotAssetFile(f.name, d);
				}
				if (typeof window.godotAssetFile === 'function') window.godotAssetFile('', '');
			};
			i.click();
		})();""")
	else:
		if _dialog == null:
			_dialog = FileDialog.new()
			_dialog.access = FileDialog.ACCESS_FILESYSTEM
			_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
			_dialog.filters = PackedStringArray(["*.png, *.webp, *.jpg, *.jpeg ; Images"])
			_dialog.files_selected.connect(_on_paths)
			add_child(_dialog)
		_dialog.popup_centered(Vector2i(800, 500))


func _on_js_file(args: Array) -> void:
	var name := str(args[0])
	if name == "":
		var files := _pending.duplicate()
		_pending.clear()
		receive_files(files)
		return
	_pending.append([name, Marshalls.base64_to_raw(str(args[1]))])


func _on_paths(paths: PackedStringArray) -> void:
	var files := []
	for path in paths:
		files.append([path.get_file(), FileAccess.get_file_as_bytes(path)])
	receive_files(files)


func _on_files_dropped(paths: PackedStringArray) -> void:
	if is_visible_in_tree():
		_on_paths(paths)


## files: [[file_name, PackedByteArray], …] — stored in user://uploads/ and shown.
func receive_files(files: Array) -> Array:
	var paths := store(files)
	if paths.is_empty():
		_say("No readable PNG / WebP / JPG files.")
		return paths
	refresh_folders(UPLOAD_DIR)
	_say("Uploaded %d file(s) into this browser." % paths.size())
	return paths


# --- input & thumbnails -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_browser()


## A few thumbnails per frame so the browser opens instantly.
func _process(_delta: float) -> void:
	var n := 3
	while n > 0 and not _thumb_queue.is_empty():
		var it: Array = _thumb_queue.pop_front()
		var img: TextureRect = it[0]
		if not is_instance_valid(img):
			continue
		var t := tex(it[1])
		if t:
			img.texture = thumb(t)
		n -= 1
