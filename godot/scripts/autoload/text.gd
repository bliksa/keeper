extends Node
## Localized strings (data/i18n/<lang>.json) and dialog data (data/dialogs.json).
##
## Strings may contain <KB>…</KB> (shown only in keyboard mode) and <GP>…</GP>
## (shown only in gamepad mode). Gamepad glyphs (🔵 🔴 🟡 🟢 ⬆️ ⬇️) are turned
## into inline images when rendered with bb().

signal language_changed

const LANGUAGES := ["sk", "en", "pt"]

var language := "en":
	set(v):
		language = v
		language_changed.emit()

var _strings := {}
var dialogs := {}
var voice_overrides := {}
var breathing_hints := {}
## Who speaks in dialogs (data/characters.json): id -> {name: {lang: s}, portrait: sprite id}.
var characters := {}

## The game's default font for every player-facing text (HUD, minigames, menus,
## the climb's board): KeeperDyslexic, the same faces as font_dialog / _bold.
var font: Font
var font_bold: Font
## Comfortaa (the web build's font): only the developer mode UI and the build label.
var font_dev: Font
var font_dev_bold: Font
## OpenDyslexic for the dialog boxes (easier to read with dyslexia), as
## KeeperDyslexic: the same font with . , ! ? : ; … closer to the letter before
## them (tools/tighten_punctuation.py; OFL, renamed as the licence asks). It covers
## every character in the SK / EN / PT texts (the pad / arrow glyphs are images).
var font_dialog: Font
var font_dialog_bold: Font

const _ICONS := {
	"🔵": "res://assets/ui/pad_blue.png",
	"🔴": "res://assets/ui/pad_red.png",
	"🟡": "res://assets/ui/pad_yellow.png",
	"🟢": "res://assets/ui/pad_green.png",
	"⬆️": "res://assets/ui/arrow_up.png",
	"⬇️": "res://assets/ui/arrow_down.png",
	"⬆": "res://assets/ui/arrow_up.png",
	"⬇": "res://assets/ui/arrow_down.png",
}
## Face-button glyphs in choice order (choice_0 … choice_3).
const PAD_GLYPHS := ["🔵", "🔴", "🟡", "🟢"]


func _ready() -> void:
	for lang in LANGUAGES:
		_strings[lang] = _load_json("res://data/i18n/%s.json" % lang)
	var d: Dictionary = _load_json("res://data/dialogs.json")
	dialogs = d.get("nodes", {})
	voice_overrides = d.get("voice_overrides", {})
	breathing_hints = d.get("breathing_hints", {})
	var ch: Variant = _load_json("res://data/characters.json")
	characters = ch.get("characters", {}) if ch is Dictionary else {}
	# Characters made in this browser's dialog editor (not in the build yet).
	if FileAccess.file_exists(DialogEditor.EDIT_PATH):
		var e: Variant = JSON.parse_string(FileAccess.get_file_as_string(DialogEditor.EDIT_PATH))
		if e is Dictionary:
			for part in ["saved_characters", "characters"]:
				var c: Variant = e.get(part, {})
				if c is Dictionary:
					for cid in c:
						if not characters.has(cid) or part == "characters":
							characters[cid] = c[cid]
	# Sprites (with an avatar for every character) once the characters are known.
	SpriteArt.load_game_defaults()
	var base: Font = load("res://assets/fonts/Comfortaa.ttf")
	var reg := FontVariation.new()
	reg.base_font = base
	reg.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	font_dev = reg
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	font_dev_bold = bold
	font_dialog = _dialog_font("res://assets/fonts/KeeperDyslexic-Regular.otf")
	font_dialog_bold = _dialog_font("res://assets/fonts/KeeperDyslexic-Bold.otf")
	font = font_dialog
	font_bold = font_dialog_bold


## OpenDyslexic has very tall built-in line spacing (≈ 1.9 × size); trimmed to
## ≈ 1.5 × so three lines fit in the dialog box.
func _dialog_font(path: String) -> Font:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.spacing_top = -3
	f.spacing_bottom = -3
	# The letters are tightened in the font itself (KeeperDyslexic); a pixel
	# spacing would squeeze narrow glyphs like dots into each other.
	f.spacing_glyph = 0
	return f


## Dialog of a level letter: `c` in level 2 (the forest run) = node "2C".
## level_id is a Game.LEVELS id (Game.DIALOG_LEVEL gives its dialog prefix).
func dialog_for_letter(letter: String, level_id: int) -> String:
	var id: String = Game.DIALOG_LEVEL.get(level_id, "") + letter.to_upper()
	return id if dialogs.has(id) else ""


## Name of a dialog's line n (1-based): "2C" + 3 = "2C3".
static func line_id(dialog_id: String, n: int) -> String:
	return "%s%d" % [dialog_id, n]


func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data if data != null else {}


## Raw translated string for the current control mode (no BBCode).
func t(key: String) -> String:
	var s: String = _strings.get(language, {}).get(key, _strings.get("en", {}).get(key, key))
	return _filter_mode(s)


## Translated string as BBCode with gamepad glyphs as images.
func bb(key: String, icon_size := 22) -> String:
	return glyphs_to_bb(t(key), icon_size)


func glyphs_to_bb(s: String, icon_size := 22) -> String:
	s = s.replace("[", "[lb]")
	for g in _ICONS:
		s = s.replace(g, "[img=%d]%s[/img]" % [icon_size, _ICONS[g]])
	return s


func plain(s: String) -> String:
	for g in _ICONS:
		s = s.replace(g, "")
	return s.strip_edges()


func _filter_mode(s: String) -> String:
	var re := RegEx.new()
	if Game.control_mode == "keyboard":
		re.compile("<GP>.*?</GP>")
		s = re.sub(s, "", true)
		re.compile("<KB>(.*?)</KB>")
		return re.sub(s, "$1", true)
	re.compile("<KB>.*?</KB>")
	s = re.sub(s, "", true)
	re.compile("<GP>(.*?)</GP>")
	return re.sub(s, "$1", true)


func speaker_name(speaker: String) -> String:
	if speaker == "Estra":
		speaker = "Estrogenka"
	var c: Dictionary = characters.get(speaker, {})
	var names: Dictionary = c.get("name", {})
	return str(names.get(language, names.get("en", speaker)))


## Sprite id of a speaker's dialog avatar (SpriteArt).
func portrait_of(speaker: String) -> String:
	if speaker == "Estra":
		speaker = "Estrogenka"
	var c: Dictionary = characters.get(speaker, {})
	return str(c.get("portrait", "portrait_" + speaker.to_lower().validate_filename().replace(" ", "_")))


func voice_file(key: String) -> String:
	if voice_overrides.has(key):
		return voice_overrides[key]
	if key.begins_with("DIA_"):
		return key + ".wav"
	return ""
