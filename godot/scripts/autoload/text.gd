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
var letter_dialogs := {}

## Comfortaa (the web build's font) — regular and bold weights.
var font: Font
var font_bold: Font

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
	letter_dialogs = d.get("letter_dialogs", {})
	var base: Font = load("res://assets/fonts/Comfortaa.ttf")
	var reg := FontVariation.new()
	reg.base_font = base
	reg.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	font = reg
	var bold := FontVariation.new()
	bold.base_font = base
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	font_bold = bold


## Dialog node id for a lowercase level letter (a–z), or "" if none.
func dialog_for_letter(letter: String) -> String:
	if letter_dialogs.has(letter):
		return letter_dialogs[letter]
	var id := "DIA_" + letter.to_upper()
	return id if dialogs.has(id) else ""


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
	if speaker == "Estrogenka" or speaker == "Estra":
		return "Estra" if language in ["en", "pt"] else "Estrogenka"
	return speaker


func voice_file(key: String) -> String:
	if voice_overrides.has(key):
		return voice_overrides[key]
	if key.begins_with("DIA_"):
		return key + ".wav"
	return ""
