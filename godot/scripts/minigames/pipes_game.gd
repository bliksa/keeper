class_name PipesGame
extends Minigame
## Minigame 3 ("Potrubie"): rotate pipes so water reaches Kyra and coffee
## goes to the trash. Port of the web `h2` component (same 5 layouts).

const N := 4
const BOARD := 320.0
const PAD := 8.0
const GAP := 4.0

## Openings per type in order [top, right, bottom, left] at rotation 0.
const SHAPES := {
	"empty": [false, false, false, false],
	"straight": [true, false, true, false],
	"corner": [true, true, false, false],
	"cross": [true, true, true, true],
}

## Each layout: 16 cells row by row as [type, rotation]. A random layout is
## picked and every non-empty piece gets a random rotation.
const LAYOUTS := [
	[["empty", 0], ["empty", 0], ["empty", 0], ["empty", 0], ["straight", 1], ["corner", 2], ["corner", 1], ["straight", 1],
	 ["corner", 2], ["corner", 0], ["corner", 3], ["corner", 1], ["corner", 0], ["straight", 1], ["straight", 1], ["corner", 3]],
	[["empty", 0], ["empty", 0], ["empty", 0], ["empty", 0], ["straight", 1], ["straight", 1], ["straight", 1], ["straight", 1],
	 ["corner", 2], ["empty", 0], ["empty", 0], ["corner", 1], ["corner", 0], ["straight", 1], ["straight", 1], ["corner", 3]],
	[["corner", 1], ["straight", 1], ["straight", 1], ["corner", 2], ["corner", 3], ["empty", 0], ["empty", 0], ["corner", 0],
	 ["straight", 1], ["straight", 1], ["straight", 1], ["straight", 1], ["empty", 0], ["empty", 0], ["empty", 0], ["empty", 0]],
	[["corner", 1], ["corner", 2], ["empty", 0], ["empty", 0], ["corner", 3], ["corner", 0], ["straight", 1], ["straight", 1],
	 ["straight", 1], ["corner", 2], ["corner", 1], ["straight", 1], ["empty", 0], ["corner", 0], ["corner", 3], ["empty", 0]],
	[["empty", 0], ["corner", 1], ["corner", 2], ["empty", 0], ["straight", 1], ["corner", 3], ["corner", 0], ["straight", 1],
	 ["corner", 2], ["corner", 1], ["straight", 1], ["straight", 1], ["corner", 0], ["corner", 3], ["empty", 0], ["empty", 0]],
]

var cells: Array = [] # [{type, rot, shown_rot}]
var cursor := 0
var solved := false
var _glow := 0.0


func _ready() -> void:
	super()
	var layout: Array = LAYOUTS.pick_random()
	for c in layout:
		var rot: int = c[1] if c[0] == "empty" else randi_range(0, 3)
		cells.append({"type": c[0], "rot": rot, "shown": float(rot)})
	_send_hint()
	_check()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if not dialog_active and not _done:
		hint.emit({"title": "Spring path", "text": "DIA_028", "hide_button": true})


func _openings(c: Dictionary) -> Array:
	var base: Array = SHAPES[c.type]
	var r: int = c.rot % 4
	return [base[(4 - r) % 4], base[(5 - r) % 4], base[(6 - r) % 4], base[(7 - r) % 4]]


## Follow the pipe from cell (x, y) entering with direction dir (0 up, 1 right, 2 down, 3 left).
func _trace(x: int, y: int, dir: int) -> Variant:
	var steps := 0
	while x >= 0 and x < N and y >= 0 and y < N and steps < 20:
		var c: Dictionary = cells[y * N + x]
		var o := _openings(c)
		var came := (dir + 2) % 4
		if not o[came]:
			return null
		var out := -1
		if c.type == "cross":
			out = dir
		else:
			for k in 4:
				if k != came and o[k]:
					out = k
					break
		if out == -1:
			return null
		dir = out
		match dir:
			0: y -= 1
			1: x += 1
			2: y += 1
			3: x -= 1
		steps += 1
	return Vector3i(x, y, dir)


func _check() -> void:
	var water = _trace(0, 1, 1)
	var coffee = _trace(0, 2, 1)
	var ok_w: bool = water != null and water == Vector3i(4, 1, 1)
	var ok_c: bool = coffee != null and coffee == Vector3i(4, 2, 1)
	if ok_w and ok_c and not solved:
		solved = true
		_glow = 1.0
		finish(1.0)


func _rotate(i: int, d: int) -> void:
	cursor = i
	if solved or dialog_active:
		return
	var c: Dictionary = cells[i]
	if c.type == "empty":
		return
	c.rot = (c.rot + d + 4) % 4
	_check()


func _board() -> Rect2:
	return Rect2((1066 - BOARD) / 2, 236 - BOARD / 2, BOARD, BOARD)


func _cell_rect(i: int) -> Rect2:
	var b := _board()
	var s := (BOARD - PAD * 2 - GAP * (N - 1)) / N
	return Rect2(b.position.x + PAD + (i % N) * (s + GAP), b.position.y + PAD + (i / N) * (s + GAP), s, s)


func _gui_input(event: InputEvent) -> void:
	if dialog_active:
		return
	if event is InputEventMouseButton and event.pressed:
		for i in cells.size():
			if _cell_rect(i).has_point(event.position):
				_rotate(i, -1 if event.button_index == MOUSE_BUTTON_RIGHT else 1)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or solved:
		return
	if event.is_action_pressed("move_right") and cursor % N < N - 1: cursor += 1
	elif event.is_action_pressed("move_left") and cursor % N > 0: cursor -= 1
	elif event.is_action_pressed("move_down") and cursor / N < N - 1: cursor += N
	elif event.is_action_pressed("move_up") and cursor / N > 0: cursor -= N
	elif event.is_action_pressed("rotate_left"): _rotate(cursor, -1)
	elif event.is_action_pressed("rotate_right") or event.is_action_pressed("confirm"): _rotate(cursor, 1)


func _process(delta: float) -> void:
	for c in cells:
		var target := float(c.rot)
		# Spin the short way round (3 → 0 turns forward).
		while target - c.shown > 2: target -= 4
		while target - c.shown < -2: target += 4
		c.shown = lerpf(c.shown, target, minf(1.0, delta * 14))
		if absf(c.shown - target) < 0.01:
			c.shown = float(c.rot)
	_glow = maxf(0, _glow - delta * 0.5)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.4))
	var b := _board()
	var fade := 0.5 if dialog_active else 1.0
	Draw.panel(self, b, Color("#1e293b", fade), 10, Color("#334155", fade), 4)
	for i in cells.size():
		var r := _cell_rect(i)
		Draw.panel(self, r, Color("#0f172a", fade), 5)
		if i == cursor and not dialog_active:
			Draw.panel(self, r.grow(2), Color(0, 0, 0, 0), 6, Color.WHITE, 3)
		_draw_pipe(cells[i], r, fade)
	var s := (BOARD - PAD * 2 - GAP * (N - 1)) / N
	var row_y := func(row: int) -> float: return b.position.y + PAD + row * (s + GAP) + s / 2
	_badge(Vector2(b.position.x - 48, row_y.call(1)), Color("#60a5fa"), "drop")
	_badge(Vector2(b.position.x - 48, row_y.call(2)), Color("#92400e"), "cup")
	_badge(Vector2(b.end.x + 48, row_y.call(1)), Color("#fb7185"), "girl")
	_badge(Vector2(b.end.x + 48, row_y.call(2)), Color("#4b5563"), "trash")
	if solved:
		Draw.panel(self, b, Color(0, 0, 0, 0), 10, Color("#34d399", 0.6 + _glow * 0.4), 4)


func _draw_pipe(c: Dictionary, r: Rect2, fade: float) -> void:
	if c.type == "empty":
		return
	var col := Color("#5f9b99", fade)
	var w := 16.0
	var ctr := r.get_center()
	var half := r.size.x / 2
	draw_set_transform(ctr, c.shown * PI / 2, Vector2.ONE)
	match c.type:
		"straight":
			draw_rect(Rect2(-w / 2, -half, w, half * 2), col)
		"corner":
			draw_rect(Rect2(-w / 2, -half, w, half), col)
			draw_rect(Rect2(0, -w / 2, half, w), col)
			draw_circle(Vector2.ZERO, w / 2, col)
		"cross":
			draw_rect(Rect2(-w / 2, -half, w, half * 2), col)
			draw_rect(Rect2(-half, -w / 2, half * 2, w), col)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _badge(c: Vector2, col: Color, kind: String) -> void:
	draw_circle(c, 20, col)
	draw_arc(c, 20, 0, TAU, 32, Color.WHITE, 2.0, true)
	var w := Color.WHITE
	match kind:
		"drop":
			draw_circle(c + Vector2(0, 3), 7, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(6, 0), c + Vector2(-6, 0)]), w)
		"cup":
			draw_rect(Rect2(c.x - 8, c.y - 6, 13, 13), w)
			draw_arc(c + Vector2(6, 0), 4, -PI / 2, PI / 2, 8, w, 2.0)
		"girl":
			draw_circle(c + Vector2(0, -6), 5, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1), c + Vector2(8, 11), c + Vector2(-8, 11)]), w)
		"trash":
			draw_rect(Rect2(c.x - 7, c.y - 5, 14, 15), w)
			draw_rect(Rect2(c.x - 9, c.y - 9, 18, 3), w)
