class_name RhythmGame
extends Minigame
## Level 2, minigame 6 ("Pohyb podľa fázy"): catch the rhythm. Beats travel
## towards the ring; press jump / confirm / click when a beat is inside it.
## In the follicular phase the body has more energy, so it likes moving.

const PERIOD := 0.65
const SPEED := 420.0
const WINDOW := 0.15
const NEED := 10
const TARGET_X := 300.0
const LINE_Y := 250.0

var hits := 0
var misses := 0
var _time := 0.0
var _next := 0
var _flash := 0.0
var _miss_flash := 0.0
var _done_beats := {}
var _started := false


func _ready() -> void:
	super()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	hint.emit({"title": "NAME_ESTRA", "text": "MG6_HINT", "hide_button": true})


func _beat_time(i: int) -> float:
	return 1.5 + i * PERIOD


## The player pressed: hit if a beat is inside the ring.
func tap() -> void:
	if dialog_active or _done:
		return
	var best := -1
	var best_d := WINDOW
	var near := int(roundf((_time - 1.5) / PERIOD))
	for i in range(maxi(0, near - 1), near + 2):
		if _done_beats.has(i):
			continue
		var d := absf(_beat_time(i) - _time)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_done_beats[best] = true
		hits += 1
		_flash = 0.3
		Audio.play_sfx("cink-%02d.wav" % (1 + hits % 11), 0.5)
		if hits >= NEED:
			Audio.play_sfx("finished.wav")
			finish(1.2)
	else:
		misses += 1
		_miss_flash = 0.3
		Audio.play_sfx("click.wav", 0.2)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap()


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active:
		return
	if (event.is_action_pressed("jump") or event.is_action_pressed("confirm")) and not event.is_echo():
		tap()
	elif event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y:
		tap()


func _process(delta: float) -> void:
	if not dialog_active and not _done:
		_time += delta
		# Beats that passed the ring without a press count as misses (once).
		while _beat_time(_next) < _time - WINDOW:
			if not _done_beats.has(_next):
				_done_beats[_next] = false
				misses += 1
			_next += 1
	_flash = maxf(0, _flash - delta)
	_miss_flash = maxf(0, _miss_flash - delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active else 1.0
	var fb: Font = Text.font_bold
	var board := Rect2(117, 60, 832, 370)
	Draw.panel(self, board, Color("#f0eee9", a), 16, Color("#d1fae5"), 1)
	# Track and the ring.
	draw_line(Vector2(board.position.x + 30, LINE_Y), Vector2(board.end.x - 30, LINE_Y), Color("#a7f3d0", a), 4.0)
	var ring := Color("#059669", a)
	if _flash > 0:
		ring = Color("#34d399")
	elif _miss_flash > 0:
		ring = Color("#f43f5e")
	draw_arc(Vector2(TARGET_X, LINE_Y), 34 + (_flash * 20), 0, TAU, 48, ring, 5.0, true)
	draw_arc(Vector2(TARGET_X, LINE_Y), 44, 0, TAU, 48, Color(ring, 0.25), 2.0, true)
	# Beats travelling in from the right.
	for i in range(maxi(0, _next - 3), _next + 10):
		var x := TARGET_X + (_beat_time(i) - _time) * SPEED
		if x < board.position.x + 20 or x > board.end.x - 20:
			continue
		var col := Color("#f472b6", a)
		if _done_beats.has(i):
			col = Color("#34d399", 0.9) if _done_beats[i] else Color("#94a3b8", 0.5)
		var r := 16.0 + (6.0 if i % 4 == 0 else 0.0)
		draw_circle(Vector2(x, LINE_Y), r, col)
		draw_circle(Vector2(x - r * 0.3, LINE_Y - r * 0.3), r * 0.3, Color(1, 1, 1, 0.5 * a))
	# Energy bar.
	var bar := Rect2(board.position.x + 40, board.end.y - 70, board.size.x - 80, 22)
	Draw.panel(self, bar, Color("#d1fae5", a), 11)
	Draw.panel(self, Rect2(bar.position, Vector2(bar.size.x * minf(1, hits / float(NEED)), bar.size.y)), Color("#10b981", a), 11)
	draw_string(fb, Vector2(bar.position.x, bar.position.y - 12), "%s  %d / %d" % [Text.plain(Text.t("MG6_ENERGY")), hits, NEED], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#064e3b", a))
	var mtxt := "%s %d" % [Text.plain(Text.t("MG6_MISSES")), misses]
	var mw := Text.font.get_string_size(mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(Text.font, Vector2(bar.end.x - mw, bar.position.y - 12), mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#9f1239", a))
	Draw.text_center(self, fb, Vector2(board.get_center().x, board.position.y + 40), Text.plain(Text.t("MG6_TITLE")), 20, Color("#064e3b", a))
	Draw.text_center(self, Text.font, Vector2(board.get_center().x, LINE_Y + 80), Text.plain(Text.t("MG6_KEYS")), 13, Color("#059669", a))
