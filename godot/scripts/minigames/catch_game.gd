class_name CatchGame
extends Minigame
## Level 2, minigame 9 ("Chyť, čo potrebuješ, vyhni sa stresu"): catch the
## nutrients on the cushion (the growing lining), dodge the lightning (stress).
## 20 nutrients win; 3 lightning strikes restart the round; it speeds up.

const GOAL := 20
const FOODS := [
	{"name": "FOOD_BEANS", "col": "#b45309"}, {"name": "FOOD_NUTS", "col": "#92400e"},
	{"name": "FOOD_VEG", "col": "#15803d"}, {"name": "FOOD_FISH", "col": "#0369a1"},
	{"name": "FOOD_FRUIT", "col": "#dc2626"},
]
const CUSHION_Y := 372.0
## The board; the reset note (14 px, 2 lines) is RESET_W wide.
const BOARD := Rect2(117, 16, 832, 418)
const RESET_W := 460.0 - 36


## Texts that don't fit their place in the current language ([] = all fit; the tests).
static func fit_problems() -> Array:
	var out: Array = []
	var fb: Font = Text.font_bold
	out.append(Draw.fit_problem("MG9_RESET", fb, Text.plain(Text.t("MG9_RESET")), RESET_W, 14, 2))
	# The counters share the top line: nutrients left, stress (+ its bolts) right.
	var top := fb.get_string_size("%s  %d / %d" % [Text.plain(Text.t("MG9_NUTRIENTS")), GOAL, GOAL], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x \
		+ fb.get_string_size(Text.plain(Text.t("MG9_STRESS")), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 3 * 16 + 10 + 48
	if top > BOARD.size.x - 48:
		out.append("MG9 counters (%d px)" % int(top))
	var legend := 0.0
	for f in FOODS:
		legend += 36 + Text.font.get_string_size(Text.plain(Text.t(f.name)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	if legend > BOARD.size.x - 48:
		out.append("MG9 legend (%d px)" % int(legend))
	return out.filter(func(x): return x != "")
const CUSHION_W := 130.0

var cushion_x := 533.0
var items: Array[Dictionary] = []
var caught := 0
var strikes := 0
var resets := 0
var speed := 3.0
var _spawn_t := 1.0
var _flash := 0.0
var _reset_flash := 0.0
var _mouse_x := -1.0


func _ready() -> void:
	super()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	hint.emit({"title": "NAME_ESTRA", "text": "MG9_HINT", "hide_button": true})


## Spawns a falling thing: kind "food" or "bolt".
func drop(kind: String, x: float) -> void:
	items.append({"x": x, "y": -20.0, "kind": kind, "type": randi_range(0, FOODS.size() - 1), "rot": randf() * TAU})


func _catch(it: Dictionary) -> void:
	if it.kind == "bolt":
		strikes += 1
		_flash = 0.4
		Audio.play_sfx("au%d.wav" % randi_range(1, 5), 0.6)
		if strikes >= 3:
			# Too much stress: the cushion thinned, start the round over.
			strikes = 0
			caught = 0
			resets += 1
			speed = 3.0
			_reset_flash = 2.5
			items.clear()
	else:
		caught += 1
		Audio.play_sfx("cink-%02d.wav" % (1 + caught % 11), 0.4)
		if caught % 5 == 0:
			speed += 0.5
		if caught >= GOAL:
			Audio.play_sfx("finished.wav")
			finish(1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_x = event.position.x


func _process(delta: float) -> void:
	_flash = maxf(0, _flash - delta)
	_reset_flash = maxf(0, _reset_flash - delta)
	if not dialog_active and not _done:
		var d60 := minf(delta, 0.1) * 60.0
		if _mouse_x >= 0:
			cushion_x += (_mouse_x - cushion_x) * minf(1, 0.3 * d60)
			if absf(_mouse_x - cushion_x) < 2:
				_mouse_x = -1
		if Input.is_action_pressed("move_left"):
			cushion_x -= 7 * d60
			_mouse_x = -1
		if Input.is_action_pressed("move_right"):
			cushion_x += 7 * d60
			_mouse_x = -1
		cushion_x = clampf(cushion_x, 117 + CUSHION_W / 2, 949 - CUSHION_W / 2)
		_spawn_t -= delta
		if _spawn_t <= 0:
			drop("bolt" if randf() < 0.25 else "food", randf_range(150, 916))
			_spawn_t = maxf(0.45, 0.9 - caught * 0.02)
		for i in range(items.size() - 1, -1, -1):
			var it: Dictionary = items[i]
			it.y += speed * d60
			it.rot += 0.03 * d60
			if it.y > CUSHION_Y - 16 and it.y < CUSHION_Y + 14 and absf(it.x - cushion_x) < CUSHION_W / 2 + 8:
				items.remove_at(i)
				_catch(it)
			elif it.y > 420:
				items.remove_at(i)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active else 1.0
	var fb: Font = Text.font_bold
	var board := BOARD
	Draw.panel(self, board, Color("#f0eee9", a), 16, Color("#f43f5e") if _flash > 0 else Color("#d1fae5"), 4 if _flash > 0 else 1)
	# Counters.
	draw_string(fb, Vector2(board.position.x + 24, board.position.y + 34), "%s  %d / %d" % [Text.plain(Text.t("MG9_NUTRIENTS")), caught, GOAL], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#064e3b", a))
	# Stress: three small bolts, filled per strike (the fonts have no ⚡ glyph).
	var st := Text.plain(Text.t("MG9_STRESS"))
	var sw := fb.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var bx := board.end.x - 24 - 3 * 16
	draw_string(fb, Vector2(bx - 10 - sw, board.position.y + 34), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#9f1239", a))
	for k in 3:
		var bc := Vector2(bx + 8 + k * 16, board.position.y + 28)
		var bp := PackedVector2Array([bc + Vector2(2, -9), bc + Vector2(-3, 1), bc + Vector2(0.5, 1), bc + Vector2(-2, 9), bc + Vector2(3.5, -1.5), bc + Vector2(0, -1.5)])
		if k < strikes:
			draw_colored_polygon(bp, Color("#facc15", a))
		draw_polyline(bp + PackedVector2Array([bp[0]]), Color("#9f1239", a * (1.0 if k < strikes else 0.35)), 1.5, true)
	# Falling things.
	for it in items:
		var c := Vector2(it.x, it.y)
		# Fade in at the board's top edge instead of showing outside the board.
		var ia: float = clampf((it.y - board.position.y - 18) / 24.0, 0, 1) * a
		if ia <= 0:
			continue
		if it.kind == "bolt":
			var pts := PackedVector2Array([c + Vector2(4, -18), c + Vector2(-6, 2), c + Vector2(1, 2), c + Vector2(-4, 18), c + Vector2(7, -3), c + Vector2(0, -3)])
			draw_colored_polygon(pts, Color("#facc15", ia))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#a16207", ia), 1.5, true)
		else:
			var f: Dictionary = FOODS[it.type]
			draw_set_transform(c, it.rot, Vector2.ONE)
			draw_circle(Vector2.ZERO, 13, Color(f.col, ia))
			draw_circle(Vector2(-4, -4), 4, Color(1, 1, 1, 0.4 * ia))
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# The cushion (thinner with each strike).
	var thick := 26.0 - strikes * 6
	var cr := Rect2(cushion_x - CUSHION_W / 2, CUSHION_Y - thick / 2, CUSHION_W, thick)
	Draw.panel(self, cr, Color("#f9a8d4", a), 13, Color("#be185d"), 2)
	draw_line(Vector2(cushion_x - 10, CUSHION_Y + thick / 2), Vector2(cushion_x - 10, CUSHION_Y + thick / 2 + 20), Color("#be185d", a), 3)
	draw_line(Vector2(cushion_x + 10, CUSHION_Y + thick / 2), Vector2(cushion_x + 10, CUSHION_Y + thick / 2 + 20), Color("#be185d", a), 3)
	# Legend (under the counters).
	var lx := board.position.x + 24
	for f in FOODS:
		draw_circle(Vector2(lx + 8, board.position.y + 56), 7, Color(f.col, a))
		var nm := Text.plain(Text.t(f.name))
		draw_string(Text.font, Vector2(lx + 20, board.position.y + 61), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#065f46", a))
		lx += 36 + Text.font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	if _reset_flash > 0:
		var r := Rect2(1066 / 2 - 230, 200, 460, 70)
		Draw.panel(self, r, Color("#fff1f2", a), 12, Color("#f43f5e"), 3)
		draw_multiline_string(fb, Vector2(r.position.x + 18, r.position.y + 28), Text.plain(Text.t("MG9_RESET")), HORIZONTAL_ALIGNMENT_LEFT, RESET_W, 14, 2, Color("#9f1239", a))
