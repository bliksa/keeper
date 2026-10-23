class_name PricesGame
extends Minigame
## Minigame 4 ("Ceny"): guess what a lifetime of period products costs.
## Port of the web `m2` component.

const MAX := 2000
const PRODUCTS := [
	{"id": "p1", "name": "PRODUCT_PADS", "price": 1500, "impact": "IMPACT_HIGH"},
	{"id": "p2", "name": "PRODUCT_PANTIES", "price": 150, "impact": "IMPACT_MEDIUM"},
	{"id": "p3", "name": "PRODUCT_CUP", "price": 30, "impact": "IMPACT_LOW"},
]

var guesses := {"p1": 0, "p2": 0, "p3": 0}
var cursor := 0
var evaluated := false
var _dragging := -1
var _reveal := 0.0


func _ready() -> void:
	super()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _any_guess() -> bool:
	for v in guesses.values():
		if v > 0:
			return true
	return false


func _send_hint() -> void:
	if dialog_active or _done:
		return
	if evaluated:
		hint.emit({})
		return
	var choices := []
	if _any_guess():
		choices.append({"text": "BTN_EVALUATE", "action": _evaluate})
	hint.emit({"title": "NAME_ESTRA", "text": "DIA_038", "hide_button": true, "choices": choices})


func _evaluate() -> void:
	if evaluated or not _any_guess():
		return
	evaluated = true
	hint.emit({})
	finish()


func _set_guess(i: int, v: int) -> void:
	if dialog_active or evaluated:
		return
	var id: String = PRODUCTS[i].id
	var had := _any_guess()
	v = clampi(v, 0, MAX)
	if absi(guesses[id] - v) >= 50:
		Audio.play_sfx("click.wav", 0.1)
	guesses[id] = v
	if had != _any_guess():
		_send_hint()


func _row_rect(i: int) -> Rect2:
	# Rows sit above the dialog panel (bottom 150 px).
	var h := 128.0 if evaluated else 92.0
	var gap := 12.0
	var total := h * 3 + gap * 2
	var top := (450 - total) / 2
	return Rect2(117, top + i * (h + gap), 832, h)


func _slider_rect(i: int) -> Rect2:
	var r := _row_rect(i)
	var w := r.size.x - 40 - (190 if evaluated else 48)
	return Rect2(r.position.x + 20, r.position.y + r.size.y / 2 + 6, w, 8)


func _gui_input(event: InputEvent) -> void:
	if dialog_active or evaluated:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for i in 3:
				if _row_rect(i).has_point(event.position):
					cursor = i
					if _slider_rect(i).grow(14).has_point(event.position):
						_dragging = i
						_drag_to(event.position)
		else:
			_dragging = -1
	elif event is InputEventMouseMotion and _dragging >= 0:
		_drag_to(event.position)


func _drag_to(pos: Vector2) -> void:
	var s := _slider_rect(_dragging)
	var k := clampf((pos.x - s.position.x) / s.size.x, 0, 1)
	_set_guess(_dragging, int(round(k * MAX / 10.0)) * 10)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or evaluated:
		return
	if event.is_action_pressed("move_down", true): cursor = mini(2, cursor + 1)
	elif event.is_action_pressed("move_up", true): cursor = maxi(0, cursor - 1)
	elif event.is_action_pressed("move_right", true): _set_guess(cursor, guesses[PRODUCTS[cursor].id] + 50)
	elif event.is_action_pressed("move_left", true): _set_guess(cursor, guesses[PRODUCTS[cursor].id] - 50)
	elif event is InputEventJoypadButton and event.pressed and (event.button_index <= JOY_BUTTON_Y or event.button_index == JOY_BUTTON_START):
		_evaluate()


func _process(delta: float) -> void:
	if evaluated:
		_reveal = minf(1, _reveal + delta * 2)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	var a := 0.5 if dialog_active and not evaluated else 1.0
	var fb: Font = Text.font_bold
	for i in 3:
		var pr: Dictionary = PRODUCTS[i]
		var r := _row_rect(i)
		var sel := i == cursor and not evaluated
		Draw.panel(self, r, Color("#f0eee9", a), 12, Color("#10b981") if sel else Color("#d1fae5"), 3 if sel else 1)
		draw_string(fb, r.position + Vector2(20, 32), Text.plain(Text.t(pr.name)), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#064e3b", a))
		var g: int = guesses[pr.id]
		var right := r.position.x + 20 + _slider_rect(i).size.x
		var txt := "%d €" % g
		if evaluated:
			txt += "  /  %d €" % pr.price
		var tw := fb.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(fb, Vector2(right - tw, r.position.y + 32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#065f46", a))
		var lbl := "Your guess: "
		var lw := Text.font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(Text.font, Vector2(right - tw - lw - 4, r.position.y + 31), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#059669", a))
		var s := _slider_rect(i)
		Draw.panel(self, s, Color("#a7f3d0", a), 4)
		var kx := s.position.x + s.size.x * g / float(MAX)
		if evaluated:
			var px: float = s.position.x + s.size.x * pr.price / float(MAX)
			var lo := minf(kx, px)
			Draw.panel(self, Rect2(lo, s.position.y, absf(px - kx) * _reveal, s.size.y), Color("#f43f5e"), 4)
			draw_circle(Vector2(px, s.get_center().y), 9, Color.WHITE)
			draw_circle(Vector2(px, s.get_center().y), 7, Color("#e11d48"))
		draw_circle(Vector2(kx, s.get_center().y), 9, Color("#059669", a))
		draw_string(Text.font, Vector2(s.position.x, s.end.y + 18), "0 €", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#10b981", a))
		var mw := Text.font.get_string_size("2000 €", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(Text.font, Vector2(s.end.x - mw, s.end.y + 18), "2000 €", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#10b981", a))
		if evaluated:
			var box := Rect2(r.end.x - 20 - 160 * _reveal, r.position.y + 12, 160 * _reveal, r.size.y - 24)
			Draw.panel(self, box, Color("#ecfdf5"), 8, Color("#d1fae5"), 1)
			if _reveal > 0.8:
				var lines := Text.plain(Text.t(pr.impact)).split("\n")
				for li in lines.size():
					Draw.text_center(self, fb, Vector2(box.get_center().x, box.get_center().y + (li - (lines.size() - 1) / 2.0) * 18), lines[li], 14, Color("#065f46"))
