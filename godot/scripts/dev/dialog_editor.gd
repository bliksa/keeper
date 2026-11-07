class_name DialogEditor
extends Control
## Developer menu > Dialogs: every dialog of the game, with its lines in all
## three languages, and a way to commit them to the repo.
##
## Names: story dialogs are <level><letter> (0 prologue in the forest, 1 cave,
## 2 forest run, 3 summit, M the old meadow), their lines <level><letter><n>:
## 2C3 = level 2, dialog C, line 3 (also the line's key in data/i18n/*.json).
## A lowercase letter in a level map starts the dialog with that letter in that
## level (c in the forest run = 2C); every level starts with its dialog A.
## Minigame talk (mg*_start / _after …) is not a story dialog: it keeps its own
## names and keys and is listed under "Minigames".
##
## Edits live in this browser (user://dialogs_edit.json) until "Save to repo"
## commits data/dialogs.json + data/i18n/{sk,en,pt}.json (merged with GitHub).
## "Use in game" applies them to the running game until the page is reloaded.

const DIALOGS := "res://data/dialogs.json"
const EDIT_PATH := "user://dialogs_edit.json"
const LANGS := ["sk", "en", "pt"]
const LANG_NAMES := {"sk": "SK", "en": "EN", "pt": "PT"}
const GROUPS := [["0", "0 · Prologue (forest)"], ["1", "1 · Cave"], ["2", "2 · Forest run"],
	["3", "3 · Summit"], ["M", "M · Old meadow"], ["mg", "Minigames"]]
const SPEAKERS := ["Kyra", "Estrogenka", "Iskra"]
const LIST_W := 270.0
const ICONS := "res://assets/ui/icons/%s.svg"

## Space reserved at the top (the developer menu's tab bar).
var top := 0.0
## Optional header (the developer menu's top bar) for the actions.
var header: HBoxContainer

## Working copy: id -> {"lines": [{"key", "speaker", "text": {lang: s}, "voice"}],
## "buttons": [keys], "has_buttons": bool}
var nodes := {}
## Node ids in file order.
var order: Array = []
## Deleted ids (they exist in the bundled files).
var deleted := {}
var group := "1"
var current := ""

var _bundled := {}
var _list: VBoxContainer
var _lines: VBoxContainer
var _title: Label
var _where: Label
var _status: Label
var _group_pick: OptionButton
var _measure: RichTextLabel
var _preview: DialogBox
var _gh: GitHubSave


func _ready() -> void:
	size = Vector2(1066, 600)
	_gh = GitHubSave.new()
	add_child(_gh)
	_gh.progress.connect(_say)
	var bg := ColorRect.new()
	bg.color = Color("#0f172a")
	bg.position = Vector2(0, top)
	bg.size = Vector2(1066, 600 - top)
	add_child(bg)
	# Measures whether a line fits the dialog box (same size and font, off screen).
	_measure = RichTextLabel.new()
	_measure.bbcode_enabled = true
	_measure.scroll_active = false
	_measure.fit_content = true
	_measure.position = Vector2(-3000, 0)
	_measure.custom_minimum_size = Vector2(DialogBox.text_area().x, 0)
	_measure.size = Vector2(DialogBox.text_area().x, 0)
	_measure.add_theme_font_override("normal_font", Text.font_dialog)
	_measure.add_theme_font_size_override("normal_font_size", DialogBox.TEXT_SIZES[DialogBox.TEXT_SIZES.size() - 1])
	_measure.add_theme_constant_override("line_separation", 0)
	add_child(_measure)
	load_data()
	_build_left()
	_build_right()
	_build_header()
	select_group(group)


# --- data ---------------------------------------------------------------------------

func load_data() -> void:
	nodes = {}
	order = []
	deleted = {}
	_bundled = {}
	var d: Variant = _read(DIALOGS)
	if not d is Dictionary:
		return
	var strings := {}
	for l in LANGS:
		var s: Variant = _read("res://data/i18n/%s.json" % l)
		strings[l] = s if s is Dictionary else {}
	var vo: Dictionary = d.get("voice_overrides", {})
	for id in d.get("nodes", {}):
		nodes[id] = _model(d.nodes[id], strings, vo)
		order.append(id)
		_bundled[id] = JSON.stringify(nodes[id])
	var e: Variant = _read(EDIT_PATH)
	if e is Dictionary:
		for id in e.get("nodes", {}):
			if e.nodes[id] is Dictionary:
				nodes[id] = e.nodes[id]
				if not order.has(id):
					order.append(id)
		for id in e.get("deleted", {}):
			deleted[id] = true
			nodes.erase(id)
			order.erase(id)


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _model(node: Dictionary, strings: Dictionary, vo: Dictionary) -> Dictionary:
	var lines := []
	for p in node.get("parts", []):
		var key: String = p.get("text", "")
		var text := {}
		for l in LANGS:
			text[l] = str(strings[l].get(key, ""))
		lines.append({"key": key, "speaker": str(p.get("speaker", "Kyra")), "text": text, "voice": str(vo.get(key, ""))})
	return {"lines": lines, "buttons": node.get("buttons", []).duplicate(), "has_buttons": node.has("buttons")}


## Story dialogs are named <level><letter> (1C, MA); the rest is minigame talk.
static func is_story(id: String) -> bool:
	return id.length() == 2 and "0123456789M".contains(id[0]) and id[1] >= "A" and id[1] <= "Z"


static func group_of(id: String) -> String:
	return id[0] if is_story(id) else "mg"


func ids_in(g: String) -> Array:
	var out := order.filter(func(id): return group_of(id) == g)
	if g != "mg":
		out.sort()
	return out


## The key of line i: story lines are numbered (2C3), minigame lines keep theirs.
func key_of(id: String, i: int) -> String:
	if is_story(id):
		return Text.line_id(id, i + 1)
	return nodes[id].lines[i].key


func is_changed(id: String) -> bool:
	if deleted.has(id):
		return true
	return not _bundled.has(id) or JSON.stringify(_normalized(id)) != _bundled[id]


## The model with story keys renumbered (what would be saved).
func _normalized(id: String) -> Dictionary:
	var n: Dictionary = nodes[id].duplicate(true)
	for i in n.lines.size():
		n.lines[i].key = key_of(id, i)
	return n


func changed_ids() -> Array:
	return order.filter(func(id): return is_changed(id))


func has_unsaved() -> bool:
	return not deleted.is_empty() or not changed_ids().is_empty()


func _save_local() -> void:
	var out := {"nodes": {}, "deleted": deleted}
	for id in changed_ids():
		out.nodes[id] = _normalized(id)
	var f := FileAccess.open(EDIT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, " ", false))


## The dialogs.json node of a dialog.
func node_json(id: String) -> Dictionary:
	var n: Dictionary = nodes[id]
	var parts := []
	for i in n.lines.size():
		parts.append({"speaker": n.lines[i].speaker, "text": key_of(id, i)})
	var out := {"parts": parts}
	if n.get("has_buttons", true) or not (n.buttons as Array).is_empty():
		out["buttons"] = n.buttons.duplicate()
	return out


## Next free letter of a level ("" when all 26 are used).
func next_id(g: String) -> String:
	for i in 26:
		var id := g + char(65 + i)
		if not nodes.has(id):
			return id
	return ""


## Does a line fit the dialog box at the smallest text size?
func fits(text: String) -> bool:
	_measure.text = Text.glyphs_to_bb(_filter_both(text))
	return _measure.get_content_height() <= DialogBox.text_area().y


## The longer of the keyboard / gamepad versions of a line.
func _filter_both(s: String) -> String:
	var kb := RegEx.create_from_string("<GP>.*?</GP>").sub(s, "", true)
	kb = RegEx.create_from_string("<KB>(.*?)</KB>").sub(kb, "$1", true)
	var gp := RegEx.create_from_string("<KB>.*?</KB>").sub(s, "", true)
	gp = RegEx.create_from_string("<GP>(.*?)</GP>").sub(gp, "$1", true)
	return kb if kb.length() >= gp.length() else gp


# --- editing ------------------------------------------------------------------------

func new_dialog() -> void:
	if group == "mg":
		_say("Minigame talk is started by its minigame; add story dialogs in a level.")
		return
	var id := next_id(group)
	if id == "":
		_say("All letters A–Z of this level are used.")
		return
	nodes[id] = {"lines": [{"key": Text.line_id(id, 1), "speaker": "Kyra", "text": {"sk": "", "en": "", "pt": ""}, "voice": ""}],
		"buttons": ["BTN_CONTINUE"], "has_buttons": true}
	order.append(id)
	deleted.erase(id)
	_changed("New dialog %s." % id)
	select(id)


func delete_dialog() -> void:
	if current == "" or not nodes.has(current):
		return
	if not is_story(current):
		_say("Minigame talk can't be deleted (its minigame starts it).")
		return
	var id := current
	nodes.erase(id)
	order.erase(id)
	if _bundled.has(id):
		deleted[id] = true
	current = ""
	_changed("Dialog %s deleted." % id)
	select_group(group)


func add_line(after := -1) -> void:
	var lines: Array = nodes[current].lines
	var at := lines.size() if after < 0 else after + 1
	var speaker: String = lines[at - 1].speaker if at > 0 else "Kyra"
	var key := Text.line_id(current, at + 1) if is_story(current) else _free_key(current)
	lines.insert(at, {"key": key, "speaker": speaker, "text": {"sk": "", "en": "", "pt": ""}, "voice": ""})
	_changed("Line %s added." % key_of(current, at))
	_refresh_lines()


func _free_key(id: String) -> String:
	var n := 1
	var used := {}
	for nid in nodes:
		for l in nodes[nid].lines:
			used[l.key] = true
	while used.has("%s_%d" % [id, n]):
		n += 1
	return "%s_%d" % [id, n]


func remove_line(i: int) -> void:
	var lines: Array = nodes[current].lines
	if lines.size() <= 1:
		_say("A dialog needs at least one line (delete the dialog instead).")
		return
	lines.remove_at(i)
	_changed("Line removed; the next ones moved up.")
	_refresh_lines()


func move_line(i: int, d: int) -> void:
	var lines: Array = nodes[current].lines
	var j := i + d
	if j < 0 or j >= lines.size():
		return
	var tmp: Dictionary = lines[i]
	lines[i] = lines[j]
	lines[j] = tmp
	_changed("Line moved.")
	_refresh_lines()


func set_text(i: int, lang: String, s: String) -> void:
	nodes[current].lines[i].text[lang] = s
	_changed("")


func set_speaker(i: int, s: String) -> void:
	nodes[current].lines[i].speaker = s
	_changed("")


func set_button(k: int, key: String) -> void:
	nodes[current].buttons[k] = key
	_changed("")


func _changed(msg: String) -> void:
	_save_local()
	_refresh_list()
	if msg != "":
		_say(msg)


## Undo every local edit (back to the bundled dialogs).
func discard() -> void:
	DirAccess.remove_absolute(EDIT_PATH)
	load_data()
	current = ""
	select_group(group)
	_say("Local edits discarded.")


# --- game & repo --------------------------------------------------------------------

## Puts the edited dialogs into the running game (until the page is reloaded).
func use_in_game() -> void:
	for id in deleted:
		Text.dialogs.erase(id)
	for id in changed_ids():
		var n: Dictionary = nodes[id]
		for i in n.lines.size():
			var key := key_of(id, i)
			for l in LANGS:
				Text._strings.get_or_add(l, {})[key] = n.lines[i].text[l]
			if n.lines[i].voice != "":
				Text.voice_overrides[key] = n.lines[i].voice
			else:
				Text.voice_overrides.erase(key)
		Text.dialogs[id] = node_json(id)
	_say("The game uses these dialogs now (until reload).")


## Files to commit, merged into the repo's current files (path -> text).
func build_commit(remote: Dictionary) -> Dictionary:
	var d: Variant = JSON.parse_string(remote.get("godot/data/dialogs.json", ""))
	if not d is Dictionary:
		return {}
	var rnodes: Dictionary = d.get("nodes", {})
	var vo: Dictionary = d.get("voice_overrides", {})
	var strings := {}
	for l in LANGS:
		var s: Variant = JSON.parse_string(remote.get("godot/data/i18n/%s.json" % l, ""))
		if not s is Dictionary:
			return {}
		strings[l] = s
	var touched := deleted.keys() + changed_ids()
	for id in touched:
		# Story lines are named by their dialog: the old ones go (renumbered or deleted).
		if is_story(id) and rnodes.has(id):
			for p in rnodes[id].get("parts", []):
				for l in LANGS:
					strings[l].erase(p.get("text", ""))
				vo.erase(p.get("text", ""))
		rnodes.erase(id)
	for id in changed_ids():
		var n: Dictionary = nodes[id]
		rnodes[id] = node_json(id)
		for i in n.lines.size():
			var key := key_of(id, i)
			for l in LANGS:
				strings[l][key] = n.lines[i].text[l]
			if n.lines[i].voice != "":
				vo[key] = n.lines[i].voice
			else:
				vo.erase(key)
	# Story dialogs in level order (0, 1, 2, 3, M; A–Z), then the minigame talk.
	var sorted := {}
	for g in GROUPS:
		var ids: Array = rnodes.keys().filter(func(id): return group_of(id) == g[0])
		if g[0] != "mg":
			ids.sort()
		for id in ids:
			sorted[id] = rnodes[id]
	for id in rnodes:
		if not sorted.has(id):
			sorted[id] = rnodes[id]
	d["nodes"] = sorted
	d["voice_overrides"] = vo
	var files := {"godot/data/dialogs.json": JSON.stringify(d, " ", false) + "\n"}
	for l in LANGS:
		files["godot/data/i18n/%s.json" % l] = JSON.stringify(strings[l], " ", false) + "\n"
	return files


func save_to_repo() -> void:
	if not has_unsaved():
		_say("Nothing to save: no dialog was changed.")
		return
	if not GitHubSave.has_token():
		GitHubSave.token_dialog(self, _on_token)
		return
	_say("Reading the repo…")
	var remote := {}
	for path in ["godot/data/dialogs.json"] + LANGS.map(func(l): return "godot/data/i18n/%s.json" % l):
		var r := await _gh.read_text(path)
		if not r.ok:
			_say("Save failed: " + r.error)
			if "token" in r.error:
				GitHubSave.forget_token()
			return
		remote[path] = r.text
	var texts := build_commit(remote)
	if texts.is_empty():
		_say("Save failed: the repo's dialog files can't be read.")
		return
	var files := {}
	for k in texts:
		files[k] = (texts[k] as String).to_utf8_buffer()
	var names: Array = changed_ids() + deleted.keys()
	var res := await _gh.commit(files, "Dialog editor: update %s\n\nSaved from Developer mode > Dialogs in the browser." % ", ".join(names))
	if not res.ok:
		_say("Save failed: " + res.error)
		if "token" in res.error:
			GitHubSave.forget_token()
		return
	DirAccess.remove_absolute(EDIT_PATH)
	use_in_game()
	_say("Saved to the repo. Everyone gets it after the next build (~2 min).")


func _on_token(ok: bool) -> void:
	if ok:
		save_to_repo()


# --- preview ------------------------------------------------------------------------

## Plays the dialog in the real dialog box (unsaved edits too), in `lang`.
func play(lang: String) -> void:
	if current == "":
		return
	close_preview()
	var pid := "__preview"
	var n: Dictionary = nodes[current]
	var parts := []
	for i in n.lines.size():
		var key := "__preview_%d" % i
		for l in LANGS:
			Text._strings.get_or_add(l, {})[key] = n.lines[i].text[l]
		parts.append({"speaker": n.lines[i].speaker, "text": key})
	Text.dialogs[pid] = {"parts": parts, "buttons": n.buttons.duplicate() if not (n.buttons as Array).is_empty() else ["BTN_CONTINUE"]}
	var lang0 := Text.language
	Text.language = lang
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.name = "Preview"
	add_child(layer)
	_preview = DialogBox.new()
	layer.add_child(_preview)
	_preview.show_node(pid, func(_b):
		Text.language = lang0
		close_preview.call_deferred())


func close_preview() -> void:
	if has_node("Preview"):
		get_node("Preview").queue_free()
	_preview = null
	Text.dialogs.erase("__preview")


# --- UI -----------------------------------------------------------------------------

func _build_header() -> void:
	var own := header == null
	if own:
		header = HBoxContainer.new()
		header.position = Vector2(LIST_W + 16, top + 6)
		add_child(header)
	header.add_theme_constant_override("separation", 2)
	for it in [["gamepad-2", "Use these dialogs in the game (until reload)", use_in_game],
			["undo-2", "Discard local edits (back to the dialogs in the build)", discard], null,
			["git-commit-horizontal", "Save to repo (commits the dialogs and the texts to GitHub)", save_to_repo]]:
		if it == null:
			var sep := VSeparator.new()
			sep.custom_minimum_size = Vector2(10, 36)
			header.add_child(sep)
			continue
		var b := UiKit.icon_button(ICONS % it[0], it[1], 36)
		b.pressed.connect(it[2])
		header.add_child(b)


func _build_left() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(0, top)
	panel.size = Vector2(LIST_W, 600 - top)
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(12, top + 10)
	box.custom_minimum_size = Vector2(LIST_W - 24, 0)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	box.add_child(UiKit.label("LEVEL", 11, Color("#94a3b8"), true))
	_group_pick = OptionButton.new()
	_group_pick.add_theme_font_size_override("font_size", 12)
	_group_pick.focus_mode = Control.FOCUS_NONE
	for g in GROUPS:
		_group_pick.add_item(g[1])
	_group_pick.item_selected.connect(func(i): select_group(GROUPS[i][0]))
	box.add_child(_group_pick)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var nb := UiKit.button("New dialog", Vector2((LIST_W - 30) / 2, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
	nb.icon = load(ICONS % "plus")
	nb.add_theme_constant_override("icon_max_width", 16)
	nb.tooltip_text = "A new dialog with the next free letter of this level"
	nb.pressed.connect(new_dialog)
	row.add_child(nb)
	var db := UiKit.button("Delete", Vector2((LIST_W - 30) / 2, 30), 11, Color("#1e293b"), Color("#cbd5e1"))
	db.icon = load(ICONS % "trash-2")
	db.add_theme_constant_override("icon_max_width", 16)
	db.tooltip_text = "Delete the selected dialog"
	db.pressed.connect(delete_dialog)
	row.add_child(db)
	box.add_child(row)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(LIST_W - 24, 600 - top - 20 - 100)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(LIST_W - 36, 0)
	_list.add_theme_constant_override("separation", 4)
	sc.add_child(_list)


func _build_right() -> void:
	var x0 := LIST_W + 16
	_title = UiKit.label("", 18, Color.WHITE, true)
	_title.position = Vector2(x0, top + 52)
	add_child(_title)
	_where = UiKit.label("", 11, Color("#94a3b8"))
	_where.position = Vector2(x0, top + 78)
	_where.size = Vector2(1066 - x0 - 300, 18)
	add_child(_where)
	var plays := HBoxContainer.new()
	plays.position = Vector2(1066 - 16 - 3 * 92, top + 54)
	plays.add_theme_constant_override("separation", 4)
	add_child(plays)
	for l in LANGS:
		var b := UiKit.button("Play " + LANG_NAMES[l], Vector2(88, 30), 12, Color("#059669"))
		b.icon = load(ICONS % "play")
		b.add_theme_constant_override("icon_max_width", 14)
		b.tooltip_text = "Play this dialog in the dialog box (%s)" % LANG_NAMES[l]
		b.pressed.connect(play.bind(l))
		plays.add_child(b)
	var sc := ScrollContainer.new()
	sc.position = Vector2(x0, top + 100)
	sc.size = Vector2(1066 - x0 - 12, 600 - top - 100 - 40)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_lines = VBoxContainer.new()
	_lines.custom_minimum_size = Vector2(1066 - x0 - 30, 0)
	_lines.add_theme_constant_override("separation", 8)
	sc.add_child(_lines)
	_status = UiKit.label("Edits are kept in this browser until “Save to repo”.", 11, Color("#94a3b8"))
	_status.position = Vector2(x0, 600 - 34)
	_status.size = Vector2(1066 - x0 - 16, 28)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_status)


func select_group(g: String) -> void:
	group = g
	for i in GROUPS.size():
		if GROUPS[i][0] == g:
			_group_pick.select(i)
	_refresh_list()
	var ids := ids_in(g)
	if current == "" or not ids.has(current):
		current = ids[0] if not ids.is_empty() else ""
	select(current)


func select(id: String) -> void:
	current = id
	_refresh_list()
	_refresh_lines()


func _refresh_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for id in ids_in(group):
		var n: Dictionary = nodes[id]
		var first := ""
		if not (n.lines as Array).is_empty():
			first = Text.plain(_filter_both(str(n.lines[0].text.get(Text.language, n.lines[0].text.get("en", "")))))
		var b := Button.new()
		b.text = "%s%s   %s" % [id, " •" if is_changed(id) else "", first]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(LIST_W - 36, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Text.font)
		b.add_theme_font_size_override("font_size", 12)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#78350f") if id == current else Color("#1e293b")
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 8
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.tooltip_text = "%s · %d line(s)%s" % [id, n.lines.size(), "  · unsaved" if is_changed(id) else ""]
		b.pressed.connect(select.bind(id))
		_list.add_child(b)


## Where a dialog comes from (shown under its name).
func where_of(id: String) -> String:
	if not is_story(id):
		return "Minigame talk: started by its minigame."
	var level := ""
	for lid in Game.DIALOG_LEVEL:
		if Game.DIALOG_LEVEL[lid] == id[0]:
			level = Game.LEVEL_NAMES[lid]
	if id[0] == "0":
		return "Prologue in the forest: started by the game."
	if id[1] == "A":
		return "Said when %s starts (or letter a in its map)." % level
	return "Letter %s in the %s map starts it (level editor)." % [id[1].to_lower(), level]


func _refresh_lines() -> void:
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	if current == "" or not nodes.has(current):
		_title.text = "No dialog"
		_where.text = ""
		return
	var n: Dictionary = nodes[current]
	_title.text = ("Dialog " if is_story(current) else "") + current
	_where.text = where_of(current)
	for i in n.lines.size():
		_lines.add_child(_line_card(i))
	var add := UiKit.button("Add line", Vector2(160, 32), 12, Color("#1e293b"), Color("#cbd5e1"))
	add.icon = load(ICONS % "plus")
	add.add_theme_constant_override("icon_max_width", 16)
	add.pressed.connect(add_line.bind(-1))
	_lines.add_child(add)
	# The buttons that close the dialog.
	if not (n.buttons as Array).is_empty():
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 8)
		brow.add_child(UiKit.label("BUTTONS", 11, Color("#94a3b8"), true))
		var keys: Array = Text._strings.get("en", {}).keys().filter(func(k): return str(k).begins_with("BTN_"))
		for k in n.buttons.size():
			var o := OptionButton.new()
			o.add_theme_font_size_override("font_size", 12)
			o.focus_mode = Control.FOCUS_NONE
			for j in keys.size():
				o.add_item("%s  (%s)" % [Text.plain(Text._strings.get(Text.language, {}).get(keys[j], keys[j])), keys[j]])
				o.set_item_metadata(j, keys[j])
				if keys[j] == n.buttons[k]:
					o.select(j)
			o.item_selected.connect(func(j): set_button(k, o.get_item_metadata(j)))
			brow.add_child(o)
		_lines.add_child(brow)


func _line_card(i: int) -> Control:
	var n: Dictionary = nodes[current]
	var line: Dictionary = n.lines[i]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#111827")
	sb.border_color = Color("#334155")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var name := UiKit.label(key_of(current, i), 14, Color("#fbbf24"), true)
	name.custom_minimum_size = Vector2(70, 0)
	name.tooltip_text = "Line %d of %s: its text key in data/i18n/*.json" % [i + 1, current]
	head.add_child(name)
	var sp := OptionButton.new()
	sp.add_theme_font_size_override("font_size", 12)
	sp.focus_mode = Control.FOCUS_NONE
	var speakers: Array = SPEAKERS.duplicate()
	if not speakers.has(line.speaker):
		speakers.append(line.speaker)
	for j in speakers.size():
		sp.add_item(Text.speaker_name(speakers[j]))
		sp.set_item_metadata(j, speakers[j])
		if speakers[j] == line.speaker:
			sp.select(j)
	sp.item_selected.connect(func(j): set_speaker(i, sp.get_item_metadata(j)))
	head.add_child(sp)
	if line.voice != "":
		var vl := UiKit.label("voice: " + str(line.voice), 10, Color("#64748b"))
		vl.tooltip_text = "Recorded voice (assets/audio). It stays with this line when lines move."
		head.add_child(vl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	for it in [["plus", "Insert a line after this one", func(): add_line(i)],
			["arrow-up", "Move up", func(): move_line(i, -1)],
			["arrow-down", "Move down", func(): move_line(i, 1)],
			["x", "Remove this line", func(): remove_line(i)]]:
		var b := UiKit.icon_button(ICONS % it[0], it[1], 26)
		b.pressed.connect(it[2])
		head.add_child(b)
	v.add_child(head)
	for l in LANGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var tag := UiKit.label(LANG_NAMES[l], 11, Color("#94a3b8"), true)
		tag.custom_minimum_size = Vector2(26, 0)
		row.add_child(tag)
		var te := TextEdit.new()
		te.text = line.text.get(l, "")
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.custom_minimum_size = Vector2(0, 46)
		te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		te.add_theme_font_size_override("font_size", 12)
		var mark := UiKit.label("", 10, Color.WHITE, true)
		mark.custom_minimum_size = Vector2(54, 0)
		_mark_fit(mark, te.text)
		te.text_changed.connect(func():
			set_text(i, l, te.text)
			_mark_fit(mark, te.text))
		row.add_child(te)
		row.add_child(mark)
		v.add_child(row)
	return card


func _mark_fit(mark: Label, text: String) -> void:
	if text.strip_edges() == "":
		mark.text = "empty"
		mark.add_theme_color_override("font_color", Color("#f59e0b"))
		mark.tooltip_text = "Empty: the dialog would show nothing in this language."
	elif fits(text):
		mark.text = "fits"
		mark.add_theme_color_override("font_color", Color("#34d399"))
		mark.tooltip_text = "Fits the dialog box."
	else:
		mark.text = "too long"
		mark.add_theme_color_override("font_color", Color("#f87171"))
		mark.tooltip_text = "Too long: it doesn't fit the dialog box even at the smallest size. Split it into two lines."


func _say(s: String) -> void:
	if _status:
		_status.text = s


func _exit_tree() -> void:
	close_preview()
