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


## Below the board: the status line (+26) and the timer bar (+40, 8 px high);
## the whole block is centred in the free area y 16–434 (the hint panel covers
## y 450–600).
const BELOW_GRID := 48.0


func _grid_layout(n: int) -> Dictionary:
	var cols := 4 if n <= 12 else 5
	var rows := int(ceil(n / float(cols)))
	var h := minf(76.0, (340.0 - (rows - 1) * 10) / rows)
	var gh := rows * h + (rows - 1) * 10
	return {"cols": cols, "h": h, "top": 16.0 + (418.0 - gh - BELOW_GRID) / 2, "bottom": 16.0 + (418.0 - gh - BELOW_GRID) / 2 + gh}


## The board: x 60–1006.
func _grid_rect(i: int, n: int) -> Rect2:
	var g := _grid_layout(n)
	var cols: int = g.cols
	var h: float = g.h
	var w := (946.0 - (cols - 1) * 10) / cols
	var y0: float = g.top
	return Rect2(60.0 + (i % cols) * (w + 10), y0 + (i / cols) * (h + 10), w, h)


## The smallest label size; the narrowest tile text (5 columns, a shown tile: the dot
## takes 52 px of it).
const LABEL_MIN := 9
const NARROW_W := (946.0 - 4 * 10) / 5 - 52


## Texts that don't fit their place in the current language ([] = all fit; the tests).
static func fit_problems() -> Array:
	var out: Array = []
	for sc in SCENES:
		out.append(Draw.fit_problem(sc.name, Text.font, Text.plain(Text.t(sc.name)) + "  ·  " + Text.plain(Text.t("MG8_ROUND")) + " 3 / 3", 900, 12))
		for i in PER_SCENE:
			var k := "%s_%02d" % [sc.prefix, i + 1]
			out.append(Draw.fit_problem(k, Text.font_bold, Text.plain(Text.t(k)), NARROW_W, LABEL_MIN))
	out.append(Draw.fit_problem("MG8_RESULT", Text.font_bold, Text.plain(Text.t("MG8_RESULT")), 400 - 32, 16))
	return out.filter(func(x): return x != "")


## A label left-aligned in a tile: steps the size down until it fits the width.
func _label(font: Font, x: float, cy: float, width: float, s: String, col: Color) -> void:
	var size := Draw.fit_size(font, s, width, 13, LABEL_MIN)
	draw_string(font, Vector2(x, cy + size * 0.38), s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)


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
	# Compact status right under the board (no heading at the top).
	var status := "%s  ·  %s %d / %d" % [Text.plain(Text.t(sc.name)), Text.plain(Text.t("MG8_ROUND")), round_i + 1, ROUNDS.size()]
	var gb: float = _grid_layout(shown.size() if phase == "show" else options.size()).bottom
	var status_y := 290.0 if phase == "result" else gb + 26
	Draw.text_center(self, Text.font, Vector2(533, status_y), status, 12, Color("#a7f3d0", a))
	match phase:
		"show":
			for i in shown.size():
				var r := _grid_rect(i, shown.size())
				Draw.panel(self, r, Color("#f0eee9", a), 10, Color(sc.col), 2)
				draw_circle(Vector2(r.position.x + 22, r.get_center().y), 12, Color(sc.col, a))
				_label(fb, r.position.x + 42, r.get_center().y, r.size.x - 52, Text.plain(Text.t(shown[i])), Color("#064e3b", a))
			var bar := Rect2(60, gb + 40, 946, 8)
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
				_label(fb, r.position.x + 36, r.get_center().y, r.size.x - 46, Text.plain(Text.t(options[i])), Color("#064e3b", a))
		"result":
			var r := Rect2(1066 / 2 - 200, 144, 400, 120)
			Draw.panel(self, r, Color("#f0eee9", a), 16, Color("#10b981"), 3)
			Draw.text_center(self, fb, r.get_center() + Vector2(0, -12), Text.plain(Text.t("MG8_RESULT")), 16, Color("#065f46", a))
			Draw.text_center(self, fb, r.get_center() + Vector2(0, 26), "%d / %d" % [found, shown.size()], 30, Color("#064e3b", a))
