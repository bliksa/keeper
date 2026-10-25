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
	var h := 52.0
	var x := 117.0 if c == 0 else 549.0
	return Rect2(x, 68 + i * (h + 8), w, h)


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
	Draw.text_center(self, fb, Vector2(317, 50), Text.plain(Text.t("MG10_SIGNALS")), 14, Color("#a7f3d0", a))
	Draw.text_center(self, fb, Vector2(749, 50), Text.plain(Text.t("MG10_MEANINGS")), 14, Color("#a7f3d0", a))
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
			draw_multiline_string(fb if c == 0 else Text.font, Vector2(r.position.x + 14, r.position.y + 20), Text.plain(Text.t(key)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 28, 12 if c == 0 else 11, 3, Color("#064e3b", (0.55 if done else 1.0) * a))
			if done:
				Draw.text_center(self, fb, Vector2(r.end.x - 14, r.position.y + 18), "✓", 14, Color("#059669", a))
	var foot := Rect2(117, 432, 832, 30)
	if all_matched():
		Draw.panel(self, foot, Color("#ecfdf5", a), 10, Color("#10b981"), 2)
		Draw.text_center(self, fb, foot.get_center() + Vector2(0, 5), Text.plain(Text.t("MG10_DONE")), 14, Color("#064e3b", a))
	elif hint_text != "":
		Draw.panel(self, foot, Color("#fffbeb", a), 10, Color("#f59e0b"), 2)
		Draw.text_center(self, Text.font, foot.get_center() + Vector2(0, 5), Text.plain(Text.t(hint_text)), 12, Color("#92400e", a))
