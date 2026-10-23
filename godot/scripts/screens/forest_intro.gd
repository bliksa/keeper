class_name ForestIntro
extends Node2D
## Forest side-scroller before the cave: Kyra wakes up in pain, meets the
## wisp (Estra), does the breathing minigame and walks into the cave.
## Port of the web `g2` component.

signal show_dialog(id: String, on_done: Callable)
signal start_breathing
signal entered_cave

const W := 1066.0
const H := 600.0
const GROUND := 520.0
const GHOST_HOME := 1050.0
const CAVE_X := 1600.0

var active := true
var dialog_open := false
## After the breathing minigame: faster, can jump, wisp fades, cave opens.
var has_breathing := false:
	set(v):
		has_breathing = v
		if v:
			_monologue_done = true

var p := PlayerBody.new()
var camera_x := 0.0
var ghost_x := 1450.0
var ghost_alpha := 1.0
var time_ms := 0.0
var _dialog_triggered := false
var _minigame_triggered := false
var _cave_entered := false
var _monologue_sent := false
var _monologue_done := false

var _back: Texture2D
var _middle: Texture2D
var _front: Texture2D
var _cave: Texture2D
var _ghost: Array = []


func _ready() -> void:
	_back = load("res://assets/images/back.png")
	_middle = load("res://assets/images/middle3.png")
	_front = load("res://assets/images/front.png")
	_cave = load("res://assets/images/cave.png")
	for i in range(1, 7):
		_ghost.append(load("res://assets/images/duch%d.png" % i))
	p.y = 420
	p.is_grounded = true
	p.was_grounded = true
	p.jumps_left = 0
	if has_breathing:
		p.x = 2200
		camera_x = 2200 - W / 3
		ghost_x = 2150
		ghost_alpha = 0
		_dialog_triggered = true
		_minigame_triggered = true
		_monologue_sent = true
		_monologue_done = true
	else:
		p.x = W / 3


func _cave_w() -> float:
	return _cave.get_width() / float(_cave.get_height()) * H


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	time_ms += dt * 1000.0
	if active:
		_update(dt)
	queue_redraw()


func _update(dt: float) -> void:
	var d60 := dt * 60.0
	var left := false
	var right := false
	var jump := false
	var run := false
	if not dialog_open and (_monologue_done or has_breathing):
		left = Input.is_action_pressed("move_left")
		right = Input.is_action_pressed("move_right")
		jump = Input.is_action_pressed("jump")
		# Keyboard always runs; gamepad runs while holding Y (web behaviour).
		run = Game.control_mode == "keyboard" or Input.is_action_pressed("run")
	if not _monologue_sent and not has_breathing:
		_monologue_sent = true
		p.is_crouched = true
		show_dialog.emit("intro_forest", func(_b):
			_monologue_done = true
			p.is_crouched = false)
	if not _monologue_done and not has_breathing:
		p.is_crouched = true

	var max_speed := (6.0 if run else 3.0) if has_breathing else 6.0 * 0.45
	if left:
		p.vx -= 1.2 * d60
		p.facing_right = false
		p.is_sitting = false
	elif right:
		p.vx += 1.2 * d60
		p.facing_right = true
		p.is_sitting = false
	else:
		p.vx *= pow(0.75, d60)
	if p.vx > max_speed: p.vx = maxf(max_speed, p.vx - 1.2 * d60)
	if p.vx < -max_speed: p.vx = minf(-max_speed, p.vx + 1.2 * d60)
	if absf(p.vx) < 0.1: p.vx = 0
	p.vy += 0.4 * d60
	if jump and p.is_grounded and has_breathing:
		p.vy = -10.5
		p.is_grounded = false
		p.is_sitting = false
	p.x += p.vx * d60
	p.y += p.vy * d60
	if p.y + p.height >= GROUND:
		p.y = GROUND - p.height
		p.vy = 0
		p.is_grounded = true
	if p.is_grounded and not p.was_grounded:
		Audio.footstep(0.8)
	p.was_grounded = p.is_grounded
	p.step_animation(d60)
	if p.x < 0:
		p.x = 0
		p.vx = 0
	var cam_max := (CAVE_X + _cave_w() - W) * 2
	var cave_entry := CAVE_X + camera_x * 0.5 + 250
	if p.x > CAVE_X + camera_x * 0.5 + _cave_w() - 20:
		p.x = CAVE_X + camera_x * 0.5 + _cave_w() - 20
	camera_x = clampf(p.x - W / 3, 0, cam_max)

	if has_breathing:
		ghost_alpha = maxf(0, ghost_alpha - 0.02 * d60)
	elif _minigame_triggered:
		var target := p.x - 100 if p.facing_right else p.x + 100
		ghost_x += (target - ghost_x) * (1 - pow(0.8, d60))
	elif _dialog_triggered:
		var target := p.x + 100 if p.facing_right else p.x - 100
		ghost_x += (target - ghost_x) * (1 - pow(0.8, d60))
	else:
		ghost_x = GHOST_HOME + camera_x * 0.5

	if not _dialog_triggered and p.x > ghost_x - 100:
		_dialog_triggered = true
		p.vx = 0
		show_dialog.emit("intro_fairy", func(_b):
			show_dialog.emit("intro_breathing", func(_b2):
				_minigame_triggered = true
				start_breathing.emit()))
	if has_breathing and p.x > cave_entry and not _cave_entered:
		_cave_entered = true
		entered_cave.emit()


func _tile_x(tex: Texture2D, factor: float) -> void:
	var w := tex.get_width() * H / float(tex.get_height())
	var off := fposmod(-(camera_x * factor), w)
	var x := off - w
	while x < W:
		draw_texture_rect(tex, Rect2(x, H - H, w, H), false)
		x += w


func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), Color.BLACK)
	_tile_x(_back, 0.2)
	_tile_x(_middle, 0.5)
	draw_set_transform(Vector2(-camera_x, 0), 0, Vector2.ONE)
	if ghost_alpha > 0:
		var tex: Texture2D = _ghost[int(time_ms / 150.0) % 6]
		var gh := 120.0
		var gw := tex.get_width() / float(tex.get_height()) * gh
		var bob := sin(time_ms / 500.0) * 10
		draw_texture_rect(tex, Rect2(ghost_x, GROUND - 160 + bob, gw, gh), false, Color(1, 1, 1, ghost_alpha))
	draw_texture_rect(_cave, Rect2(CAVE_X + camera_x * 0.5, 0, _cave_w(), H), false)
	draw_set_transform(Vector2(-camera_x, 0), 0, Vector2.ONE)
	_draw_player_world()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_tile_x(_front, 1.2)


func _draw_player_world() -> void:
	# PlayerArt sets its own transforms; shift the body into screen space.
	var shifted := PlayerBody.new()
	for prop in ["y", "vx", "vy", "width", "height", "is_grounded", "facing_right", "jumps_left", "is_sitting", "is_crouched", "anim_progress", "look_down_timer"]:
		shifted.set(prop, p.get(prop))
	shifted.x = p.x - camera_x
	PlayerArt.draw(self, shifted, time_ms, false, {"pain": p.is_crouched})
