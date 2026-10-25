class_name SignalsGame
extends Minigame
## Level 2, minigame 7 ("Signály tela"): sort what the body says into the four
## phases of the cycle, like a cycle-tracking app would.

const PHASES := [
	{"id": "m", "name": "PHASE_MENSTRUATION", "days": "PHASE_MENSTRUATION_DAYS", "col": "#be123c"},
	{"id": "f", "name": "PHASE_FOLLICULAR", "days": "PHASE_FOLLICULAR_DAYS", "col": "#15803d"},
	{"id": "o", "name": "PHASE_OVULATION", "days": "PHASE_OVULATION_DAYS", "col": "#ca8a04"},
	{"id": "l", "name": "PHASE_LUTEAL", "days": "PHASE_LUTEAL_DAYS", "col": "#6d28d9"},
]
const CARDS := [
	{"text": "SIGNAL_BLEEDING", "phase": "m"},
	{"text": "SIGNAL_TIRED", "phase": "m"},
	{"text": "SIGNAL_ENERGY", "phase": "f"},
	{"text": "SIGNAL_MOOD", "phase": "f"},
	{"text": "SIGNAL_TWINGE", "phase": "o"},
	{"text": "SIGNAL_MUCUS", "phase": "o"},
	{"text": "SIGNAL_CRAVINGS", "phase": "l"},
	{"text": "SIGNAL_PMS", "phase": "l"},
]

var order: Array = []
var current := 0
var cursor := 1
var placed := {"m": [], "f": [], "o": [], "l": []}
var wrong := 0
var _shake := 0.0
var _ok_flash := 0.0
var _last_wrong := -1


func _ready() -> void:
	super()
	order = range(CARDS.size())
	order.shuffle()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	hint.emit({"title": "NAME_ESTRA", "text": "MG7_HINT", "hide_button": true})


func all_placed() -> bool:
	return current >= order.size()


func card() -> Dictionary:
	return CARDS[order[current]]


## Put the current card into a phase column.
func place(phase_index: int) -> void:
	if dialog_active or all_placed() or _done:
		return
	cursor = phase_index
	var ph: Dictionary = PHASES[phase_index]
	if card().phase == ph.id:
		placed[ph.id].append(order[current])
		current += 1
		_ok_flash = 0.6
		_last_wrong = -1
		Audio.play_sfx("cink-%02d.wav" % (1 + current % 11), 0.5)
		if all_placed():
			Audio.play_sfx("finished.wav")
			finish(1.5)
	else:
		wrong += 1
		_shake = 0.4
		_last_wrong = phase_index
		Audio.play_sfx("breathoff.wav", 0.4)


func _phase_rect(i: int) -> Rect2:
	var w := 196.0
	var gap := 12.0
	var x0 := (1066 - (4 * w + 3 * gap)) / 2
	return Rect2(x0 + i * (w + gap), 250, w, 190)


func _card_rect() -> Rect2:
	return Rect2(1066 / 2 - 230, 60, 460, 150)


func _gui_input(event: InputEvent) -> void:
	if dialog_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in 4:
			if _phase_rect(i).has_point(event.position):
				place(i)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or all_placed():
		return
	if event.is_action_pressed("move_right"): cursor = mini(3, cursor + 1)
	elif event.is_action_pressed("move_left"): cursor = maxi(0, cursor - 1)
	elif event.is_action_pressed("confirm") or event.is_action_pressed("move_down") or (event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y):
		place(cursor)


func _process(delta: float) -> void:
	_shake = maxf(0, _shake - delta)
	_ok_flash = maxf(0, _ok_flash - delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active else 1.0
	var fb: Font = Text.font_bold
	# The card to sort.
	var cr := _card_rect()
	if _shake > 0:
		cr.position.x += sin(_shake * 60) * 6 * _shake
	if not all_placed():
		Draw.panel(self, cr, Color("#f0eee9", a), 14, Color("#f43f5e") if _shake > 0 else Color("#d1fae5"), 3 if _shake > 0 else 1)
		draw_string(fb, Vector2(cr.position.x + 20, cr.position.y + 30), "%s %d / %d" % [Text.plain(Text.t("MG7_SIGNAL")), current + 1, order.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#059669", a))
		draw_multiline_string(fb, Vector2(cr.position.x + 20, cr.position.y + 70), Text.plain(Text.t(card().text)), HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 40, 20, 3, Color("#064e3b", a))
		if _last_wrong >= 0:
			draw_string(Text.font, Vector2(cr.position.x + 20, cr.end.y - 16), Text.plain(Text.t("MG7_NOT_THAT")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#be123c", a))
	else:
		Draw.panel(self, cr, Color("#ecfdf5", a), 14, Color("#10b981"), 3)
		Draw.text_center(self, fb, cr.get_center(), Text.plain(Text.t("MG7_DONE")), 20, Color("#064e3b", a))
	# Phase columns.
	for i in 4:
		var ph: Dictionary = PHASES[i]
		var r := _phase_rect(i)
		var sel := i == cursor and not all_placed()
		var border := Color(ph.col)
		var bw := 3.0 if sel else 1.0
		if _ok_flash > 0 and i == cursor and _last_wrong < 0:
			border = Color("#34d399")
			bw = 4
		elif _shake > 0 and i == _last_wrong:
			border = Color("#f43f5e")
			bw = 4
		Draw.panel(self, r, Color("#f0eee9", a), 12, border, bw)
		Draw.panel(self, Rect2(r.position, Vector2(r.size.x, 46)), Color(ph.col, a), 12)
		Draw.text_center(self, fb, Vector2(r.get_center().x, r.position.y + 22), Text.plain(Text.t(ph.name)), 14, Color.WHITE)
		Draw.text_center(self, Text.font, Vector2(r.get_center().x, r.position.y + 38), Text.plain(Text.t(ph.days)), 10, Color(1, 1, 1, 0.85))
		var list: Array = placed[ph.id]
		for j in list.size():
			var cd: Dictionary = CARDS[list[j]]
			var y := r.position.y + 62 + j * 58
			Draw.panel(self, Rect2(r.position.x + 8, y, r.size.x - 16, 50), Color("#ecfdf5", a), 8, Color("#a7f3d0"), 1)
			draw_multiline_string(Text.font, Vector2(r.position.x + 16, y + 18), Text.plain(Text.t(cd.text)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32, 10, 3, Color("#065f46", a))
	Draw.text_center(self, Text.font, Vector2(533, 228), Text.plain(Text.t("MG7_KEYS")), 12, Color("#a7f3d0", a))
