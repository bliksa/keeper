class_name MemoryGame
extends Minigame
## Level 2, minigame 8 ("Pamätaj si čo najviac"): a scene full of things is
## shown for a moment, then a list of words; pick the ones that were there.
## Three rounds (8, 12, 16 things), recognition not recall, no losing.

const ROUNDS := [8, 12, 16]
const DISTRACTORS := 4
const SCENES := [
	{"name": "SCENE_ROOM", "prefix": "ROOM", "col": "#c084fc"},
	{"name": "SCENE_BAG", "prefix": "BAG", "col": "#60a5fa"},
	{"name": "SCENE_MARKET", "prefix": "MARKET", "col": "#fb923c"},
]
const PER_SCENE := 20

var round_i := 0
var phase := "show" # show | pick | result
var shown: Array = []
var options: Array = []
var marked := {}
var cursor := 0
var show_left := 0.0
var result_left := 0.0
var found := 0
var found_total := 0
var shown_total := 0


func _ready() -> void:
	super()
	_start_round()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _scene() -> Dictionary:
	return SCENES[mini(round_i, SCENES.size() - 1)]


func _key(i: int) -> String:
	return "%s_%02d" % [_scene().prefix, i + 1]


func _start_round() -> void:
	phase = "show"
	marked = {}
	cursor = 0
	var all := range(PER_SCENE)
	all.shuffle()
	shown = []
	options = []
	for i in ROUNDS[round_i]:
		shown.append(_key(all[i]))
	for i in range(ROUNDS[round_i], ROUNDS[round_i] + DISTRACTORS):
		options.append(_key(all[i]))
	options.append_array(shown)
	options.shuffle()
	show_left = 5.0 + ROUNDS[round_i] * 0.5
	_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	match phase:
		"show":
			hint.emit({"title": "NAME_ESTRA", "text": "MG8_LOOK", "hide_button": true,
				"choices": [{"text": "BTN_I_REMEMBER", "action": skip_show}]})
		"pick":
			hint.emit({"title": "NAME_ESTRA", "text": "MG8_PICK", "hide_button": true,
				"choices": [{"text": "BTN_DONE", "action": done_round}]})
		_:
			hint.emit({})


## The scene is hidden; the word list appears.
func skip_show() -> void:
	if phase != "show" or dialog_active:
		return
	phase = "pick"
	cursor = 0
	_send_hint()


func mark(key: String) -> void:
	if phase != "pick" or dialog_active:
		return
	marked[key] = not marked.get(key, false)
	Audio.play_sfx("click.wav", 0.1)


func done_round() -> void:
	if phase != "pick" or dialog_active:
		return
	found = 0
	for k in shown:
		if marked.get(k, false):
			found += 1
	found_total += found
	shown_total += shown.size()
	phase = "result"
	result_left = 2.5
	Audio.play_sfx("cink-%02d.wav" % (1 + found % 11), 0.5)
	_send_hint()


func _next() -> void:
	round_i += 1
	if round_i >= ROUNDS.size():
		Audio.play_sfx("finished.wav")
		finish(0.5)
		return
	_start_round()


func _grid_rect(i: int, n: int) -> Rect2:
	var cols := 4 if n <= 12 else 5
	var w := (832.0 - (cols - 1) * 10) / cols
	var rows := int(ceil(n / float(cols)))
	var h := minf(76.0, (360.0 - (rows - 1) * 10) / rows)
	var x0 := 117.0
	var y0 := 60.0 + (360.0 - rows * h - (rows - 1) * 10) / 2
	return Rect2(x0 + (i % cols) * (w + 10), y0 + (i / cols) * (h + 10), w, h)


func _gui_input(event: InputEvent) -> void:
	if dialog_active or phase != "pick":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in options.size():
			if _grid_rect(i, options.size()).has_point(event.position):
				cursor = i
				mark(options[i])


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active:
		return
	if phase == "show" and (event.is_action_pressed("confirm") or (event is InputEventJoypadButton and event.pressed)):
		skip_show()
		return
	if phase != "pick":
		return
	var cols := 4 if options.size() <= 12 else 5
	if event.is_action_pressed("move_right"): cursor = mini(options.size() - 1, cursor + 1)
	elif event.is_action_pressed("move_left"): cursor = maxi(0, cursor - 1)
	elif event.is_action_pressed("move_down"): cursor = mini(options.size() - 1, cursor + cols)
	elif event.is_action_pressed("move_up"): cursor = maxi(0, cursor - cols)
	elif event.is_action_pressed("confirm") or (event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y):
		mark(options[cursor])


func _process(delta: float) -> void:
	if not dialog_active and not _done:
		if phase == "show":
			show_left -= delta
			if show_left <= 0:
				skip_show()
		elif phase == "result":
			result_left -= delta
			if result_left <= 0:
				_next()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active else 1.0
	var fb: Font = Text.font_bold
	var sc := _scene()
	var head := "%s  ·  %s %d / 3" % [Text.plain(Text.t(sc.name)), Text.plain(Text.t("MG8_ROUND")), round_i + 1]
	var hr := Rect2(1066 / 2 - 220, 14, 440, 34)
	Draw.panel(self, hr, Color("#f0eee9", a), 17, Color("#d1fae5"), 1)
	Draw.text_center(self, fb, hr.get_center() + Vector2(0, 6), head, 14, Color("#064e3b", a))
	match phase:
		"show":
			for i in shown.size():
				var r := _grid_rect(i, shown.size())
				Draw.panel(self, r, Color("#f0eee9", a), 10, Color(sc.col), 2)
				draw_circle(Vector2(r.position.x + 22, r.get_center().y), 12, Color(sc.col, a))
				draw_string(fb, Vector2(r.position.x + 42, r.get_center().y + 5), Text.plain(Text.t(shown[i])), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 50, 13, Color("#064e3b", a))
			var bar := Rect2(117, 436, 832, 8)
			Draw.panel(self, bar, Color("#d1fae5", a), 4)
			Draw.panel(self, Rect2(bar.position, Vector2(bar.size.x * clampf(show_left / (5.0 + shown.size() * 0.5), 0, 1), 8)), Color("#10b981", a), 4)
		"pick":
			for i in options.size():
				var r := _grid_rect(i, options.size())
				var on: bool = marked.get(options[i], false)
				var sel := i == cursor
				Draw.panel(self, r, Color("#ecfdf5", a) if on else Color("#f0eee9", a), 10, Color("#065f46") if sel else (Color("#10b981") if on else Color("#d1fae5")), 3 if (sel or on) else 1)
				if on:
					Draw.text_center(self, fb, Vector2(r.position.x + 20, r.get_center().y + 6), "✓", 16, Color("#059669", a))
				draw_string(fb, Vector2(r.position.x + 36, r.get_center().y + 5), Text.plain(Text.t(options[i])), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 44, 13, Color("#064e3b", a))
		"result":
			var r := Rect2(1066 / 2 - 200, 170, 400, 120)
			Draw.panel(self, r, Color("#f0eee9", a), 16, Color("#10b981"), 3)
			Draw.text_center(self, fb, r.get_center() + Vector2(0, -12), Text.plain(Text.t("MG8_RESULT")), 16, Color("#065f46", a))
			Draw.text_center(self, fb, r.get_center() + Vector2(0, 26), "%d / %d" % [found, shown.size()], 30, Color("#064e3b", a))
