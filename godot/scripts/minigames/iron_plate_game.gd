class_name IronPlateGame
extends Minigame
## Level 2, minigame 5 ("Tanier so železom"): put together a plate that lets
## the body absorb the iron collected in the cave. Pick 4 of 8 foods; vitamin C
## helps, tea / coffee / cola block the absorption, sweets add nothing.

const PICK := 4
const ITEMS := [
	{"id": "lentils", "name": "FOOD_LENTILS", "good": true, "fact": "FOOD_LENTILS_FACT", "col": "#b45309"},
	{"id": "seeds", "name": "FOOD_SEEDS", "good": true, "fact": "FOOD_SEEDS_FACT", "col": "#4d7c0f"},
	{"id": "orange", "name": "FOOD_ORANGE", "good": true, "fact": "FOOD_ORANGE_FACT", "col": "#ea580c"},
	{"id": "pepper", "name": "FOOD_PEPPER", "good": true, "fact": "FOOD_PEPPER_FACT", "col": "#dc2626"},
	{"id": "tea", "name": "FOOD_TEA", "good": false, "fact": "FOOD_TEA_FACT", "col": "#78350f"},
	{"id": "coffee", "name": "FOOD_COFFEE", "good": false, "fact": "FOOD_COFFEE_FACT", "col": "#44403c"},
	{"id": "cola", "name": "FOOD_COLA", "good": false, "fact": "FOOD_COLA_FACT", "col": "#7f1d1d"},
	{"id": "candy", "name": "FOOD_CANDY", "good": false, "fact": "FOOD_CANDY_FACT", "col": "#db2777"},
]

var chosen: Array[String] = []
var cursor := 0
var evaluated := false
var perfect := false
var _reveal := 0.0
var _order: Array = []


func _ready() -> void:
	super()
	_order = range(ITEMS.size())
	_order.shuffle()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	if evaluated:
		if perfect:
			hint.emit({})
		else:
			hint.emit({"title": "NAME_ESTRA", "text": "MG5_WRONG", "hide_button": true,
				"choices": [{"text": "BTN_TRY_AGAIN", "action": _retry}]})
		return
	var choices := []
	if chosen.size() == PICK:
		choices.append({"text": "BTN_SERVE", "action": _evaluate})
	hint.emit({"title": "NAME_ESTRA", "text": "MG5_HINT", "hide_button": true, "choices": choices})


func _item(i: int) -> Dictionary:
	return ITEMS[_order[i]]


func toggle(i: int) -> void:
	if dialog_active or evaluated:
		return
	cursor = i
	var id: String = _item(i).id
	if chosen.has(id):
		chosen.erase(id)
	elif chosen.size() < PICK:
		chosen.append(id)
	else:
		return
	Audio.play_sfx("click.wav", 0.1)
	_send_hint()


func _evaluate() -> void:
	if evaluated or chosen.size() != PICK:
		return
	evaluated = true
	perfect = true
	for it in ITEMS:
		if it.good != chosen.has(it.id):
			perfect = false
	_reveal = 0
	Audio.play_sfx("finished.wav" if perfect else "breathoff.wav", 0.5)
	_send_hint()
	if perfect:
		finish(2.5)


func _retry() -> void:
	evaluated = false
	chosen.clear()
	_send_hint()


func _card_rect(i: int) -> Rect2:
	var w := 196.0
	var h := 150.0
	var gap := 12.0
	var x0 := (1066 - (4 * w + 3 * gap)) / 2
	return Rect2(x0 + (i % 4) * (w + gap), 70 + (i / 4) * (h + gap), w, h)


func _gui_input(event: InputEvent) -> void:
	if dialog_active or evaluated:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in ITEMS.size():
			if _card_rect(i).has_point(event.position):
				toggle(i)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or evaluated:
		return
	if event.is_action_pressed("move_right"): cursor = (cursor + 1) % ITEMS.size()
	elif event.is_action_pressed("move_left"): cursor = posmod(cursor - 1, ITEMS.size())
	elif event.is_action_pressed("move_down"): cursor = (cursor + 4) % ITEMS.size()
	elif event.is_action_pressed("move_up"): cursor = posmod(cursor - 4, ITEMS.size())
	elif event.is_action_pressed("confirm") or (event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y):
		toggle(cursor)


func _process(delta: float) -> void:
	if evaluated:
		_reveal = minf(1, _reveal + delta * 2)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active and not evaluated else 1.0
	var fb: Font = Text.font_bold
	# The plate: how many foods are on it.
	var pr := Rect2(1066 / 2 - 110, 20, 220, 36)
	Draw.panel(self, pr, Color("#f0eee9", a), 18, Color("#d1fae5"), 1)
	Draw.text_center(self, fb, pr.get_center() + Vector2(0, 6), "%s  %d / %d" % [Text.plain(Text.t("MG5_PLATE")), chosen.size(), PICK], 15, Color("#064e3b", a))
	for i in ITEMS.size():
		var it := _item(i)
		var r := _card_rect(i)
		var on := chosen.has(it.id)
		var sel := i == cursor and not evaluated
		var border := Color("#d1fae5")
		var bw := 1.0
		if evaluated:
			var right: bool = it.good == on
			border = Color("#10b981") if right else Color("#f43f5e")
			bw = 3
		elif on:
			border = Color("#10b981")
			bw = 3
		if sel:
			border = Color("#065f46")
			bw = 3
		Draw.panel(self, r, Color("#f0eee9", a) if not on else Color("#ecfdf5", a), 12, border, bw)
		# A simple food blob in its colour.
		var c := Vector2(r.position.x + 36, r.position.y + 40)
		draw_circle(c, 22, Color(it.col, a))
		draw_circle(c + Vector2(-7, -7), 7, Color(1, 1, 1, 0.35 * a))
		draw_string(fb, Vector2(r.position.x + 68, r.position.y + 46), Text.plain(Text.t(it.name)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 76, 14, Color("#064e3b", a))
		if on and not evaluated:
			Draw.text_center(self, fb, Vector2(r.end.x - 18, r.position.y + 22), "✓", 16, Color("#059669", a))
		if evaluated and _reveal > 0.3:
			var mark := "✓" if it.good else "✗"
			Draw.text_center(self, fb, Vector2(r.end.x - 18, r.position.y + 22), mark, 18, Color("#059669") if it.good else Color("#e11d48"))
			draw_multiline_string(Text.font, Vector2(r.position.x + 12, r.position.y + 84), Text.plain(Text.t(it.fact)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 11, 4, Color("#065f46", _reveal))
		elif not evaluated:
			draw_multiline_string(Text.font, Vector2(r.position.x + 12, r.position.y + 84), Text.plain(Text.t("MG5_PICK_HINT")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24, 11, 3, Color("#059669", 0.7 * a))
