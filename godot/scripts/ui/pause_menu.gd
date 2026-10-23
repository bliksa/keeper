class_name PauseMenu
extends Control
## Esc / gamepad Start during play: pauses the game and offers
## Continue, Restart game and Main menu.

signal restart_pressed
signal title_pressed

## Main sets this: the menu only opens while actually playing.
var allowed := false

var _buttons: Array[Button] = []
var _cursor := 0
var _title: Label


func _ready() -> void:
	size = Vector2(1066, 600)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_title = UiKit.label("", 32, Color.WHITE, true)
	_title.position = Vector2(0, 150)
	_title.size = Vector2(1066, 40)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	var actions := [close, func(): _pick(restart_pressed), func(): _pick(title_pressed)]
	for i in 3:
		var b := UiKit.button("", Vector2(300, 52), 18)
		b.position = Vector2((1066 - 300) / 2.0, 230 + i * 66)
		b.pressed.connect(actions[i])
		b.mouse_entered.connect(func(): _select(i))
		add_child(b)
		_buttons.append(b)
	Text.language_changed.connect(_refresh)
	_refresh()
	visible = false


func _refresh() -> void:
	_title.text = Text.t("UI_PAUSED")
	var keys := ["BTN_RESUME", "BTN_RESTART_GAME", "BTN_MAIN_MENU"]
	for i in _buttons.size():
		_buttons[i].text = Text.t(keys[i])


func is_open() -> bool:
	return visible


func open() -> void:
	_select(0)
	visible = true
	get_tree().paused = true
	Audio.set_bgm_volume(0.15)


func close() -> void:
	visible = false
	get_tree().paused = false
	Audio.set_bgm_volume(0.5)


func _pick(sig: Signal) -> void:
	close()
	sig.emit()


func _select(i: int) -> void:
	_cursor = i
	for k in _buttons.size():
		var sb: StyleBoxFlat = _buttons[k].get_theme_stylebox("normal").duplicate()
		sb.border_color = Color.WHITE if k == i else Color("#475569")
		sb.set_border_width_all(3 if k == i else 1)
		_buttons[k].add_theme_stylebox_override("normal", sb)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		if visible:
			close()
			get_viewport().set_input_as_handled()
		elif allowed:
			open()
			get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	# While open, the menu takes all keyboard / gamepad input.
	if event.is_action_pressed("move_down", true):
		_select((_cursor + 1) % _buttons.size())
	elif event.is_action_pressed("move_up", true):
		_select((_cursor + _buttons.size() - 1) % _buttons.size())
	elif event.is_action_pressed("confirm"):
		_buttons[_cursor].pressed.emit()
	elif event.is_action_pressed("choice_1"):
		close()
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
