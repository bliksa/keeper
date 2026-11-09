class_name PairsGame
extends Minigame
## Level 2, minigame 10 ("Priraď symptóm"): pair what the body says with what
## it means. A wrong pair turns back with a short hint, not an error.

const PAIRS := [
	{"sig": "SIG_ENERGY", "exp": "EXP_ENERGY", "hint": "HINT_ENERGY"},
	{"sig": "SIG_FOCUS", "exp": "EXP_FOCUS", "hint": "HINT_FOCUS"},
	{"sig": "SIG_LINING", "exp": "EXP_LINING", "hint": "HINT_LINING"},
	{"sig": "SIG_MUCUS", "exp": "EXP_MUCUS", "hint": "HINT_MUCUS"},
	{"sig": "SIG_STRESS", "exp": "EXP_STRESS", "hint": "HINT_STRESS"},
	{"sig": "SIG_IRREGULAR", "exp": "EXP_IRREGULAR", "hint": "HINT_IRREGULAR"},
]

## Top of the card columns; the column labels sit just above, the hint line
## below; everything stays above the hint panel (y 450).
const CARDS_Y := 48.0
## A card's text width (400 px card, clear of the ✓) and how many lines fit its 50 px.
const TEXT_W := 400.0 - 50
const MAX_LINES := 2


## Texts that don't fit their place in the current language ([] = all fit; the tests).
static func fit_problems() -> Array:
	var out: Array = []
	for pr in PAIRS:
		out.append(Draw.fit_problem(pr.sig, Text.font_bold, Text.plain(Text.t(pr.sig)), TEXT_W, 12, MAX_LINES))
		out.append(Draw.fit_problem(pr.exp, Text.font, Text.plain(Text.t(pr.exp)), TEXT_W, 11, MAX_LINES))
		out.append(Draw.fit_problem(pr.hint, Text.font, Text.plain(Text.t(pr.hint)), 832 - 24, 12))
	out.append(Draw.fit_problem("MG10_DONE", Text.font_bold, Text.plain(Text.t("MG10_DONE")), 832 - 24, 14))
	return out.filter(func(x): return x != "")

var right_order: Array = []
var sel_left := -1
var sel_right := -1
var matched := {}
var col := 0
var row := 0
var hint_text := ""
var wrong := 0
var _shake := 0.0
var _ok_flash := 0.0


func _ready() -> void:
	super()
	right_order = range(PAIRS.size())
	right_order.shuffle()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	hint.emit({"title": "NAME_ESTRA", "text": "MG10_HINT", "hide_button": true})


func all_matched() -> bool:
	return matched.size() == PAIRS.size()


## Picks a card: column 0 = signals, 1 = meanings (index in the shuffled column).
func pick(c: int, i: int) -> void:
	if dialog_active or _done or all_matched():
		return
	col = c
	row = i
	if c == 0:
		if matched.has(i):
			return
		sel_left = i
	else:
		if matched.has(right_order[i]):
			return
		sel_right = i
	Audio.play_sfx("click.wav", 0.1)
	if sel_left >= 0 and sel_right >= 0:
		if right_order[sel_right] == sel_left:
			matched[sel_left] = true
			_ok_flash = 0.6
			hint_text = ""
			Audio.play_sfx("cink-%02d.wav" % (1 + matched.size()), 0.5)
			if all_matched():
				Audio.play_sfx("finished.wav")
				finish(1.5)
		else:
			wrong += 1
			_shake = 0.4
			hint_text = PAIRS[sel_left].hint
			Audio.play_sfx("breathoff.wav", 0.3)
		sel_left = -1
		sel_right = -1


func _card_rect(c: int, i: int) -> Rect2:
	var w := 400.0
	var h := 50.0
	var x := 117.0 if c == 0 else 549.0
	return Rect2(x, CARDS_Y + i * (h + 8), w, h)


func _gui_input(event: InputEvent) -> void:
	if dialog_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for c in 2:
			for i in PAIRS.size():
				if _card_rect(c, i).has_point(event.position):
					pick(c, i)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or all_matched():
		return
	if event.is_action_pressed("move_right"): col = 1
	elif event.is_action_pressed("move_left"): col = 0
	elif event.is_action_pressed("move_down"): row = mini(PAIRS.size() - 1, row + 1)
	elif event.is_action_pressed("move_up"): row = maxi(0, row - 1)
	elif event.is_action_pressed("confirm") or (event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y):
		pick(col, row)


func _process(delta: float) -> void:
	_shake = maxf(0, _shake - delta)
	_ok_flash = maxf(0, _ok_flash - delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active else 1.0
	var fb: Font = Text.font_bold
	for c in 2:
		for i in PAIRS.size():
			var r := _card_rect(c, i)
			var pair_i: int = i if c == 0 else right_order[i]
			var done := matched.has(pair_i)
			var sel := (c == 0 and sel_left == i) or (c == 1 and sel_right == i)
			var cur := c == col and i == row and not all_matched()
			if _shake > 0 and not done and ((c == 0 and i == row and col == 0) or (c == 1 and i == row and col == 1)):
				r.position.x += sin(_shake * 60) * 5 * _shake
			var border := Color("#d1fae5")
			var bw := 1.0
			if done:
				border = Color("#10b981")
				bw = 2
			if sel:
				border = Color("#065f46")
				bw = 3
			if cur:
				border = Color("#f59e0b")
				bw = 3
			Draw.panel(self, r, Color("#ecfdf5", a) if done else Color("#f0eee9", a), 10, border, bw)
			var key: String = PAIRS[pair_i].sig if c == 0 else PAIRS[pair_i].exp
			# Text centred vertically in the card, clear of the ✓ on the right.
			var f: Font = fb if c == 0 else Text.font
			var fs := 12 if c == 0 else 11
			var tw := TEXT_W
			var txt := Text.plain(Text.t(key))
			var th := f.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 3).y
			var ty := r.position.y + (r.size.y - th) / 2 + f.get_ascent(fs)
			draw_multiline_string(f, Vector2(r.position.x + 14, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, 3, Color("#064e3b", (0.55 if done else 1.0) * a))
			if done:
				# A drawn tick (the UI fonts have no ✓ glyph).
				var k := Vector2(r.end.x - 24, r.get_center().y)
				draw_polyline(PackedVector2Array([k + Vector2(-6, 0), k + Vector2(-1, 5), k + Vector2(8, -6)]), Color("#059669", a), 3, true)
	var last := _card_rect(0, PAIRS.size() - 1)
	var foot := Rect2(117, last.end.y + 12, 832, 32)
	if all_matched():
		Draw.panel(self, foot, Color("#ecfdf5", a), 10, Color("#10b981"), 2)
		Draw.text_center(self, fb, foot.get_center(), Text.plain(Text.t("MG10_DONE")), 14, Color("#064e3b", a))
	elif hint_text != "":
		Draw.panel(self, foot, Color("#fffbeb", a), 10, Color("#f59e0b"), 2)
		Draw.text_center(self, Text.font, foot.get_center(), Text.plain(Text.t(hint_text)), 12, Color("#92400e", a))
