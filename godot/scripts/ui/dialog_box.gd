class_name DialogBox
extends Control
## Dialog panel along the top or bottom edge (25 % of the screen).
##
## Two modes, like the web build:
##  * node dialog  – show_node("cave_start", cb): multi-part conversation from
##    data/dialogs.json with voice-over; cb(button_text) when finished.
##  * simple panel – show_panel({title, text, choices:[{text, action}], hide_button}):
##    hints from minigames / game-over choices.

signal closed

const H := 150.0
## One warm white for every dialog panel (story dialogs, hints, game-over choices).
const PANEL_BG := Color("#f0eee9")

var at_top := false:
	set(v):
		at_top = v
		_layout()

var _node_id := ""
var _node: Dictionary = {}
var _part := 0
var _on_done: Callable
var _panel: Dictionary = {}
var _last_pad := 0
var _shake := 0.0

var _bg: Panel
var _avatar: TextureRect
var _speaker: Label
var _text: RichTextLabel
var _buttons: VBoxContainer
var _node_style := true
## Another dialog drawn above this one; while it is open this one ignores input.
var blocker: DialogBox


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg = Panel.new()
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	var avatar_frame := Panel.new()
	avatar_frame.position = Vector2(16, 16)
	avatar_frame.size = Vector2(H - 32, H - 32)
	avatar_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG.darkened(0.06)
	sb.set_corner_radius_all(12)
	sb.border_color = PANEL_BG
	sb.set_border_width_all(4)
	avatar_frame.add_theme_stylebox_override("panel", sb)
	_bg.add_child(avatar_frame)
	_avatar = TextureRect.new()
	_avatar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar_frame.add_child(_avatar)
	_speaker = Label.new()
	_speaker.position = Vector2(H + 8, 18)
	_speaker.add_theme_font_override("font", Text.font_bold)
	_speaker.add_theme_font_size_override("font_size", 14)
	_speaker.add_theme_color_override("font_color", Color("#4a7d7b"))
	_bg.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = false
	_text.position = Vector2(H + 8, 40)
	_text.size = Vector2(1066 - H - 8 - 240 - 16, H - 52)
	_text.add_theme_font_override("normal_font", Text.font_bold)
	_text.add_theme_font_size_override("normal_font_size", 18)
	_text.add_theme_color_override("default_color", Color("#064e3b"))
	_text.add_theme_constant_override("line_separation", 4)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.add_child(_text)
	_buttons = VBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 12)
	_buttons.position = Vector2(1066 - 16 - 220, 16)
	_buttons.size = Vector2(220, H - 32)
	_bg.add_child(_buttons)
	_layout()
	visible = false
	Game.control_mode_changed.connect(_refresh)
	Text.language_changed.connect(_refresh)


func _layout() -> void:
	if _bg == null:
		return
	_bg.position = Vector2(0, 0 if at_top else 600 - H)
	_bg.size = Vector2(1066, H)


func is_open() -> bool:
	return visible


func node_id() -> String:
	return _node_id


func show_node(id: String, on_done: Callable = Callable()) -> void:
	if not Text.dialogs.has(id):
		push_warning("Unknown dialog " + id)
		if on_done.is_valid():
			on_done.call("")
		return
	_node_id = id
	_node = Text.dialogs[id]
	_part = 0
	_on_done = on_done
	_panel = {}
	_node_style = true
	_last_pad = Time.get_ticks_msec()
	visible = true
	_refresh()
	_play_voice()


func show_panel(d: Dictionary) -> void:
	_node_id = ""
	_node = {}
	_panel = d
	_node_style = false
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_node_id = ""
	_node = {}
	_panel = {}
	closed.emit()


func _part_data() -> Dictionary:
	var parts: Array = _node.get("parts", [])
	return parts[clampi(_part, 0, parts.size() - 1)] if parts.size() > 0 else {}


func _is_last() -> bool:
	return _part >= _node.get("parts", []).size() - 1


func _play_voice() -> void:
	Audio.play_voice(Text.voice_file(_part_data().get("text", "")))


func _style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.shadow_color = Color(0, 0, 0, 0.2)
	sb.shadow_size = 24
	return sb


func _refresh() -> void:
	if not visible:
		return
	for c in _buttons.get_children():
		c.queue_free()
	if _node_style:
		_bg.add_theme_stylebox_override("panel", _style(Color(PANEL_BG, 0.95)))
		var part := _part_data()
		var speaker: String = part.get("speaker", "")
		_avatar.texture = load("res://assets/images/dia2.png" if speaker == "Kyra" else "res://assets/images/dia1.png")
		_speaker.text = Text.speaker_name(speaker).to_upper()
		_text.text = Text.bb(part.get("text", ""))
		if _is_last():
			var btns: Array = _node.get("buttons", ["BTN_NEXT"])
			for i in btns.size():
				_add_button(Text.plain(Text.t(btns[i])), i, _choose.bind(i))
		else:
			_add_button(Text.plain(Text.t("BTN_NEXT")), 0, _next, true)
	else:
		_bg.add_theme_stylebox_override("panel", _style(Color(PANEL_BG, 0.95)))
		_avatar.texture = load(_panel.get("avatar", "res://assets/images/dia1.png"))
		_speaker.text = Text.plain(Text.t(_panel.get("title", ""))).to_upper()
		_text.text = Text.bb(_panel.get("text", ""))
		var choices: Array = _panel.get("choices", [])
		if choices.size() > 0:
			for i in choices.size():
				_add_button(Text.plain(Text.t(choices[i].text)), i, choices[i].action)
		elif not _panel.get("hide_button", false):
			_add_button(Text.plain(Text.t("BTN_UNDERSTOOD")), 0, close, true)


func _add_button(label: String, index: int, cb: Callable, enter_icon := false) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(220, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Text.font_bold)
	b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#334155") if state == "hover" else Color("#1e293b")
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	if Game.control_mode == "gamepad":
		b.icon = load(Text._ICONS[Text.PAD_GLYPHS[index]])
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 20)
	b.pressed.connect(cb)
	_buttons.add_child(b)


func _next() -> void:
	if not _is_last():
		_part += 1
		_refresh()
		_play_voice()


func _choose(i: int) -> void:
	var btns: Array = _node.get("buttons", ["BTN_NEXT"])
	var cb := _on_done
	var id := _node_id
	close()
	if cb.is_valid():
		cb.call(btns[i] if i < btns.size() else "")
	elif id != "":
		pass


func _press(index: int) -> void:
	if _node_style:
		if not _is_last():
			_next()
		else:
			var btns: Array = _node.get("buttons", ["BTN_NEXT"])
			if index < maxi(1, btns.size()):
				_choose(index)
	else:
		var choices: Array = _panel.get("choices", [])
		if choices.size() > 0:
			if index < choices.size():
				choices[index].action.call()
		elif not _panel.get("hide_button", false) and index == 0:
			close()


func _accepts_input() -> bool:
	if not visible:
		return false
	if _node_style:
		return true
	return _panel.get("choices", []).size() > 0 or not _panel.get("hide_button", false)


func _input(event: InputEvent) -> void:
	if not _accepts_input():
		return
	# Only the top-most open dialog handles input (node dialogs sit above panels).
	if blocker != null and blocker.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_press(0)
	elif event is InputEventJoypadButton and event.pressed and event.button_index <= JOY_BUTTON_Y:
		if Time.get_ticks_msec() - _last_pad < 300:
			return
		_last_pad = Time.get_ticks_msec()
		get_viewport().set_input_as_handled()
		_press(event.button_index)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var over_button := false
		for b in _buttons.get_children():
			if b.get_global_rect().has_point(event.position):
				over_button = true
		if not over_button:
			_shake = 0.4


func _process(delta: float) -> void:
	if _shake > 0:
		_shake = maxf(0, _shake - delta)
		_buttons.position.x = 1066 - 16 - 220 + sin(_shake * 60) * 5 * (_shake / 0.4)
