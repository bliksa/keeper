class_name ChocoPuzzle
extends Minigame
## Minigame 2 ("Matica"): put the 15 chocolate pieces back in order by
## swapping two at a time. Port of the web `d2` component.

const COLS := 5
const ROWS := 3
const TILE := 80.0
const GAP := 4.0
const PAD := 12.0

var tiles: Array[int] = []
var cursor := 0
var selected := -1
var solved := false
var _solve_flash := 0.0
var _choco: Texture2D


func _ready() -> void:
	super()
	_choco = load("res://assets/images/choco.png")
	for i in COLS * ROWS:
		tiles.append(i)
	while _is_solved():
		tiles.shuffle()
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if not dialog_active and not _done:
		hint.emit({"title": "NAME_ESTRA", "text": "DIA_018", "hide_button": true})


func _is_solved() -> bool:
	for i in tiles.size():
		if tiles[i] != i:
			return false
	return true


func _board_rect() -> Rect2:
	var w := COLS * TILE + (COLS - 1) * GAP + PAD * 2
	var h := ROWS * TILE + (ROWS - 1) * GAP + PAD * 2
	return Rect2((1066 - w) / 2, 72, w, h)


func _tile_rect(i: int) -> Rect2:
	var b := _board_rect()
	var cx := i % COLS
	var cy := i / COLS
	return Rect2(b.position.x + PAD + cx * (TILE + GAP), b.position.y + PAD + cy * (TILE + GAP), TILE, TILE)


func _move(dx: int, dy: int) -> void:
	var cx := cursor % COLS + dx
	var cy := cursor / COLS + dy
	if cx >= 0 and cx < COLS and cy >= 0 and cy < ROWS:
		cursor = cy * COLS + cx


func _pick(i: int) -> void:
	cursor = i
	if solved or dialog_active:
		return
	if selected == -1:
		selected = i
	else:
		var t := tiles[selected]
		tiles[selected] = tiles[i]
		tiles[i] = t
		selected = -1
		if _is_solved():
			solved = true
			_solve_flash = 1.5
			finish(1.0)


func _gui_input(event: InputEvent) -> void:
	if dialog_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in tiles.size():
			if _tile_rect(i).has_point(event.position):
				_pick(i)


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if dialog_active or solved:
		return
	if event.is_action_pressed("move_right"): _move(1, 0)
	elif event.is_action_pressed("move_left"): _move(-1, 0)
	elif event.is_action_pressed("move_down"): _move(0, 1)
	elif event.is_action_pressed("move_up"): _move(0, -1)
	elif event.is_action_pressed("confirm") or (event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y):
		_pick(cursor)


func _process(delta: float) -> void:
	_solve_flash = maxf(0, _solve_flash - delta)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1066, 600), Color(0, 0, 0, 0.6))
	if dialog_active:
		var w := 448.0
		var h := w * _choco.get_height() / _choco.get_width()
		draw_texture_rect(_choco, Rect2((1066 - w) / 2, 64, w, h), false, Color(1, 1, 1, 0.9))
		return
	var b := _board_rect()
	var border := Color("#1a0a04")
	if _solve_flash > 0:
		border = Color("#1a0a04").lerp(Color("#5f9b99"), sin(_solve_flash / 1.5 * PI))
	Draw.panel(self, b, Color("#2a1307"), 10, border, 4)
	for i in tiles.size():
		var r := _tile_rect(i)
		var sel := i == selected
		if sel:
			r = r.grow(-2)
		Draw.panel(self, r, Color.WHITE if sel else Color("#3e1f0e"), 3)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y / 2)), Color(1, 1, 1, 0.06))
		if i == cursor and not sel:
			Draw.panel(self, r.grow(2), Color(0, 0, 0, 0), 4, Color.WHITE, 3)
		Draw.text_center(self, Text.font_bold, r.get_center() + Vector2(1, 1), str(tiles[i] + 1), 30, Color(0, 0, 0, 0.6))
		Draw.text_center(self, Text.font_bold, r.get_center(), str(tiles[i] + 1), 30, Color("#3e1f0e") if sel else Color("#ddb892"))
