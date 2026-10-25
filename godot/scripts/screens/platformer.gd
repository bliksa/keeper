class_name Platformer
extends Node2D
## The cave: vertical platformer + boss fight. Port of the web `vv` component.
##
## Physics constants and behaviours are copied 1:1 from the prototype; all
## per-frame values are scaled by dt60 (= delta * 60) like the original.
##
## Level 2 (the garden, level_id 2) reuses everything and adds: climbing up
## instead of down, bubble platforms, updrafts, distractions instead of cramps,
## power-ups from its minigames (jump, dash, double) and the LH wave chase that
## replaces the boss (reach the summit before the wave catches you).

signal trigger(name: String)
signal boss_defeated
signal boss_lost

const W := 1066.0
const H := 600.0
const GRAVITY := 0.4
const JUMP_FORCE := -10.5
const MAX_SPEED := 6.0
const ACCEL := 1.2
const FRICTION := 0.75
const MAX_FALL := 15.0
const HEX_W := 48.0
const HEX_H := 42.0
## Level 2: a popping bubble bursts after standing on it this long, regrows after REGROW.
const POP_AFTER := 0.7
const REGROW := 3.5
const DASH_TIME := 0.22
const DASH_SPEED := 15.0
const DASH_COOLDOWN := 0.9
## LH wave: start speed and max speed (px per frame at 60 fps) and acceleration.
const WAVE_SPEED := 1.3
const WAVE_MAX := 2.0
const WAVE_ACCEL := 0.02

const PARALLAX := [
	["res://assets/images/1.png", 0.1],
	["res://assets/images/2.png", 0.3],
	["res://assets/images/3.png", 0.6],
	["res://assets/images/4.png", 0.8],
	["res://assets/images/5.png", 1.2],
]

## Updated by Main.
var active := false
var dialog_open := false
var active_dialog_id := ""
var hide_platforms := false

var level: LevelData
var level_h := 0.0
## 1 = the cave (down, cramps, boss), 2 = the garden (up, bubbles, LH wave).
var level_id := 1
## The LH wave (level 2): rises from below once triggered; reach the summit first.
var wave := {"active": false, "y": 0.0, "speed": 0.0, "lost": false, "won": false}
## Seconds since the summit was reached (egg release animation).
var summit_timer := 0.0
var p := PlayerBody.new()
var camera_y := 0.0
var particles: Array[Dictionary] = []
var hexes: Array[Dictionary] = []
var boss := {}
var shake_timer := 0.0
var egg_growth := 0.0
var time_ms := 0.0
var _boss_dialog_sent := false
var _first_enemy_seen := false
var _initial_dialog_sent := false
var _start_checkpoint := 0
var _prev_breathe := false
var _layers: Array = []
var _font: Font
var _shake := Vector2.ZERO

var _bg: Node2D
var _world: Node2D
var _player_layer: Node2D
var hud: PlatformerHud
## CanvasLayer index of the HUD (the level editor raises it above its own UI).
var hud_layer := 6
## CanvasLayer of the player sprite. Above the dialog panels (layer 8), as in
## the web build, so Kyra sitting on a dialog box keeps her legs in front of it.
var player_layer := 9


## rows: level text rows. checkpoint: 0/1 = start, 2..4 = after minigame N,
## 5 = boss (level 2: the LH wave). lvl: 1 cave, 2 garden.
func setup(rows: PackedStringArray, checkpoint: int, lvl := 1) -> void:
	level = LevelData.build(rows)
	level_h = level.height()
	level_id = lvl
	_start_checkpoint = checkpoint
	_reset_boss()
	_place_at_checkpoint(checkpoint)


func is_garden() -> bool:
	return level_id == 2


## Trigger kinds that mark progress in this level (checkpoint 2..5).
func progress_kinds() -> Array:
	return LevelData.PROGRESS.get(level_id, LevelData.PROGRESS[1])


## Earned power-ups (level 2).
func has_upgrade(name: String) -> bool:
	return Game.upgrades.has(name)


func _ready() -> void:
	_font = Text.font_bold
	for l in PARALLAX:
		_layers.append([load(l[0]), l[1]])
	_bg = Node2D.new()
	_world = Node2D.new()
	_player_layer = Node2D.new()
	add_child(_bg)
	add_child(_world)
	var pl := CanvasLayer.new()
	pl.layer = player_layer
	add_child(pl)
	pl.add_child(_player_layer)
	_bg.draw.connect(_draw_bg)
	_world.draw.connect(_draw_world)
	_player_layer.draw.connect(_draw_player)
	var layer := CanvasLayer.new()
	layer.layer = hud_layer
	add_child(layer)
	hud = PlatformerHud.new()
	hud.platformer = self
	layer.add_child(hud)
	if level == null:
		setup(Game.current_level_rows(), 0)


func spawn_point() -> Vector2:
	return level.spawn if level.has_spawn() else Vector2(W / 2 - 15, 100)


func _place_at_checkpoint(cp: int) -> void:
	p.vx = 0
	p.vy = 0
	if cp <= 1:
		var s := spawn_point()
		p.x = s.x
		p.y = s.y
		camera_y = maxf(0, s.y - H / 2)
		return
	if cp >= 5 and not is_garden():
		return
	var kinds := progress_kinds()
	var want: String = kinds[mini(cp, 5) - 2]
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == want:
			# The wave checkpoint re-arms the chase; minigame checkpoints are done.
			e.collected = want != "wave"
			_stand_at_trigger(e)
			# Earlier triggers are done too (above in the cave, below in the garden).
			for e2 in level.entities:
				var earlier: bool = e2.y > e.y if is_garden() else e2.y < e.y
				if e2.type == "trigger" and earlier and e2.trigger_type in kinds.slice(0, 3):
					e2.collected = true
			return


func _reset_boss() -> void:
	boss = {
		"active": false, "x": W / 2, "y": 3800.0, "vx": 1.5, "vy": -1.5, "hp": 8, "max_hp": 8,
		"hit_timer": 0.0, "slow_timer": 0.0, "radius": 40.0, "lost": false, "spike_order": [],
		"defeated_timer": 0.0,
	}


## Starts the boss arena (from the trigger, or from Main for retry / dev skip).
func start_boss(iron: int) -> void:
	p.held_by_cramp = -1
	p.is_recharging = false
	p.is_dead = false
	Audio.stop_loop("krcloop.wav")
	boss.active = true
	boss.hp = 20
	boss.max_hp = 20
	boss.x = W / 2
	boss.y = level_h + 400
	boss.vx = 3.5
	boss.vy = -3.5
	boss.radius = 60.0
	boss.lost = false
	boss.defeated_timer = 0.0
	boss.hit_timer = 0.0
	egg_growth = 0
	_boss_dialog_sent = false
	var order := range(20)
	order.shuffle()
	boss.spike_order = order
	p.breath_charges = 1
	p.x = W / 2
	p.y = level_h + 100
	p.vy = 0
	camera_y = level_h
	hexes.clear()
	var total := maxi(10, iron)
	var left := total
	var row := 0
	while left > 0:
		var n := mini(left, 20)
		var x0 := W / 2 - n * HEX_W / 2 + HEX_W / 2
		for i in n:
			hexes.append({
				"x": x0 + i * HEX_W + (HEX_W / 2 if row % 2 == 1 else 0.0),
				"y": level_h + 200 + row * HEX_H,
				"active": true,
			})
		left -= n
		row += 1
	for e in level.entities:
		if e.type == "iron" or e.trigger_type == "end":
			e.collected = false
	Game.boss_iron = iron


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)
	time_ms += dt * 1000.0
	if active:
		_update(dt)
		if active and not _initial_dialog_sent and _start_checkpoint <= 1:
			_initial_dialog_sent = true
			get_tree().create_timer(0.3).timeout.connect(_send_initial_dialog)
	_shake = Vector2.ZERO
	if shake_timer > 0:
		var s := shake_timer * 20
		_shake = Vector2((randf() - 0.5) * s, (randf() - 0.5) * s)
	elif p.held_by_cramp != -1:
		_shake = Vector2((randf() - 0.5) * 4, (randf() - 0.5) * 4)
	_bg.position = _shake
	_world.position = _shake + Vector2(0, -camera_y)
	_player_layer.position = (_shake if shake_timer > 0 else Vector2.ZERO) + Vector2(0, -camera_y)
	_bg.queue_redraw()
	_world.queue_redraw()
	_player_layer.queue_redraw()
	hud.queue_redraw()


func _send_initial_dialog() -> void:
	trigger.emit("dialog_g" if is_garden() else "dialog_a")


func _clear_breath_failed() -> void:
	p.breath_failed = false


func _clear_breath_success() -> void:
	p.breath_success = false


# --- input helpers -------------------------------------------------------------

## Debug: put the player just above a trigger ("mg2", "mg3", "mg4", "end").
func teleport_to_trigger(kind: String) -> void:
	for e in level.entities:
		if e.type == "trigger" and e.trigger_type == kind:
			e.collected = false
			if is_garden():
				_stand_at_trigger(e)
			else:
				p.x = W / 2 - 15
				p.y = e.y - 120
				camera_y = maxf(0, p.y - H / 2)
			p.vy = 0
			return


## Puts the player in a trigger's row: in the garden on the nearest platform at
## or below it near the middle (the row's own platform), in the cave just inside it.
func _stand_at_trigger(e: LevelData.Ent) -> void:
	p.x = W / 2 - 15
	p.y = e.y + 100 - 30
	if is_garden():
		var best: LevelData.Plat = null
		for pl in level.platforms:
			if pl.base_y >= e.y + 99 and pl.x <= W / 2 + 60 and pl.x + pl.w >= W / 2 - 60 and (best == null or pl.base_y < best.base_y):
				best = pl
		if best:
			p.x = clampf(W / 2 - 15, best.x + 4, best.x + best.w - p.width - 4)
			p.y = best.base_y - p.height
	camera_y = maxf(0, p.y - H / 2)


func _can_jump_in_dialog() -> bool:
	return not dialog_open or active_dialog_id in ["cave_start", "first_cramp", "garden_start"]


## Jump impulse with the level-2 power-ups (jump: +15 %, double: second jump +20 %).
func _jump_force() -> float:
	var f := JUMP_FORCE
	if has_upgrade("jump"):
		f *= 1.15
	if has_upgrade("double") and p.jumps_left == 1:
		f *= 1.2
	return f


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("jump") and not event.is_echo():
		if p.is_recharging:
			return
		if p.jumps_left > 0 and not boss.lost and not wave.lost and _can_jump_in_dialog():
			Audio.jump_sound(p.jumps_left == 1)
			p.vy = _jump_force()
			p.jumps_left -= 1
			p.is_grounded = false
			p.is_sitting = false
	elif event.is_action_pressed("run") and not event.is_echo() and has_upgrade("dash"):
		# Dash (level 2): a short burst in the facing direction.
		if p.dash_cooldown <= 0 and p.dash_timer <= 0 and not dialog_open and not p.is_recharging and not p.is_dead and not wave.lost:
			p.dash_timer = DASH_TIME
			p.dash_cooldown = DASH_COOLDOWN
			p.slow_timer = 0
			Audio.play_sfx("breathoff.wav", 0.4)
	elif event.is_action_pressed("breathe") and not event.is_echo():
		if dialog_open:
			return
		# Toggle the recharge sequence when out of breath charges.
		if p.breath_charges == 0 and Game.has_breathing and p.breathing_cooldown <= 0:
			if p.held_by_cramp != -1 and p.is_recharging:
				return
			p.is_recharging = not p.is_recharging
			if not p.is_recharging:
				p.breath_index = 0
				p.breath_timer = 0


# --- update -------------------------------------------------------------------

func _die(boss_variant: bool) -> void:
	p.is_recharging = false
	p.breath_charges = 0
	p.breath_timer = 0
	p.breath_index = 0
	p.breath_error_timer = 0
	p.held_by_cramp = -1
	Audio.stop_loop("krcloop.wav")
	Audio.set_bgm_volume(0.5)
	p.is_sitting = true
	p.is_dead = true
	p.vx = 0
	particles.clear()
	shake_timer = 0
	Game.iron = 0
	trigger.emit("game_over_boss" if boss_variant else "game_over")


func _spray_nuts(count: int, spread := 12.0, up := 10.0, base := 5.0) -> void:
	for i in count:
		particles.append({
			"x": p.x + p.width / 2, "y": p.y + p.height / 2,
			"vx": (randf() - 0.5) * spread, "vy": -randf() * up - base,
			"rot": randf() * TAU, "rot_speed": (randf() - 0.5) * 0.5, "type": "nut",
		})


## Knock-back hit used by spikes and (without breathing) enemies.
func _hurt(from_x: float) -> void:
	p.hit_timer = 1
	p.vy = -8
	p.vx = -10.0 if p.x < from_x else 10.0
	p.is_grounded = false
	var lose := randi_range(3, 5)
	var lost := mini(Game.iron, lose)
	var left := maxi(0, Game.iron - lose)
	if left == 0:
		_die(boss.active)
	else:
		Game.iron = left
		Audio.nut_sound()
	_spray_nuts(lost)


func _update(dt: float) -> void:
	var d60 := dt * 60.0
	hud.breath_error = false
	if shake_timer > 0:
		shake_timer -= dt

	var left := Input.is_action_pressed("move_left")
	var right := Input.is_action_pressed("move_right")
	var up := Input.is_action_pressed("move_up")
	var down := Input.is_action_pressed("move_down")
	var breathe := Input.is_action_pressed("breathe")
	var breathe_pressed := breathe and not _prev_breathe
	_prev_breathe = breathe

	# --- horizontal movement
	var max_speed := MAX_SPEED
	if Game.control_mode == "gamepad" and not Input.is_action_pressed("run"):
		max_speed = MAX_SPEED * 0.5
	if p.slow_timer > 0:
		p.slow_timer -= dt
		max_speed *= 0.45
	if p.dash_cooldown > 0:
		p.dash_cooldown -= dt
	if p.invuln_timer > 0:
		p.invuln_timer -= dt
	if p.dash_timer > 0:
		p.dash_timer -= dt
		p.vx = DASH_SPEED if p.facing_right else -DASH_SPEED
		max_speed = DASH_SPEED
		particles.append({"x": p.x + p.width / 2, "y": p.y + p.height / 2 + (randf() - 0.5) * 30,
			"vx": -p.vx * 0.1, "vy": (randf() - 0.5) * 2, "rot": 0.0, "rot_speed": 0.0, "type": "dash", "life": 0.35, "max_life": 0.35})
	elif p.hit_timer > 0 or boss.lost or wave.lost or p.held_by_cramp != -1 or p.is_dead or p.is_recharging:
		if p.hit_timer > 0:
			p.hit_timer -= dt
		p.vx = 0
	elif right:
		p.vx += ACCEL * d60
		p.facing_right = true
	elif left:
		p.vx -= ACCEL * d60
		p.facing_right = false
	else:
		p.vx *= pow(FRICTION, d60)
	if p.vx > max_speed: p.vx = maxf(max_speed, p.vx - ACCEL * d60)
	if p.vx < -max_speed: p.vx = minf(-max_speed, p.vx + ACCEL * d60)
	if absf(p.vx) < 0.1: p.vx = 0
	p.x += p.vx * d60
	p.x = clampf(p.x, 0, W - p.width)

	for pl in level.platforms:
		pl.y = pl.base_y + sin(time_ms / 500.0 + pl.x) * 5
		if pl.regrow > 0:
			pl.regrow -= dt
			if pl.regrow <= 0:
				pl.pop_timer = 0

	# --- breathing
	if Game.has_breathing:
		if breathe_pressed and p.breath_charges > 0 and p.breathing_cooldown <= 0 and not dialog_open:
			p.is_breathing = 40
			p.breath_charges -= 1
			p.breathing_cooldown = 0.5
			p.has_used_breath = true
		if p.breathing_cooldown > 0:
			p.breathing_cooldown -= dt
		if not (p.breath_charges > 0 and p.held_by_cramp == -1):
			if p.is_recharging and p.breathing_cooldown <= 0:
				_update_recharge(dt, up, down)
		if p.is_breathing > 0:
			p.is_breathing = maxf(0, p.is_breathing - dt * 80)

	# --- gravity
	if p.held_by_cramp != -1:
		p.vx = 0
		p.vy = minf(p.vy + GRAVITY * d60, MAX_FALL)
		p.cramp_drain_timer += dt
		if p.cramp_drain_timer >= 1.5:
			p.cramp_drain_timer = 0
			var n := maxi(0, Game.iron - 1)
			if n == 0:
				_die(boss.active)
			else:
				Game.iron = n
				Audio.nut_sound()
				_spray_nuts(1)
	elif p.dash_timer > 0:
		p.vy = 0
	else:
		p.vy = minf(p.vy + GRAVITY * d60, MAX_FALL)

	var prev_bottom := p.y + p.height - p.vy * d60
	p.y += p.vy * d60
	var grounded := false
	var solids: Array = [] if hide_platforms else level.platforms.duplicate()
	if boss.active and boss.defeated_timer > 0:
		var rise := maxf(0, 40 - boss.defeated_timer * 40)
		var floor_pl := LevelData.Plat.new()
		floor_pl.x = 0
		floor_pl.y = camera_y + H - 40 + rise
		floor_pl.w = W
		floor_pl.h = 40
		solids.append(floor_pl)
	p.is_hanging = false
	var stood_on: LevelData.Plat = null
	for pl in solids:
		if not pl.solid():
			continue
		if p.vy >= 0 and prev_bottom <= pl.y + 20 and p.y + p.height >= pl.y - 10 and p.x + p.width > pl.x and p.x < pl.x + pl.w:
			p.y = pl.y - p.height
			p.vy = 0
			grounded = true
			p.jumps_left = 2
			stood_on = pl
	for pl in level.platforms:
		if pl.kind != "pop" or pl.regrow > 0:
			continue
		if pl == stood_on:
			pl.pop_timer += dt
			if pl.pop_timer >= POP_AFTER:
				_pop_bubble(pl)
		else:
			pl.pop_timer = maxf(0, pl.pop_timer - dt * 2)
	if boss.active:
		for hx in hexes:
			if not hx.active:
				continue
			var top: float = hx.y - HEX_H / 2
			if p.vy >= 0 and prev_bottom <= top + 20 and p.y + p.height >= top - 10 and p.x + p.width > hx.x - HEX_W / 2 and p.x < hx.x + HEX_W / 2:
				p.y = top - p.height
				p.vy = 0
				grounded = true
				p.jumps_left = 2
	var on_dialog_floor := false
	if dialog_open or boss.lost:
		var fy := camera_y + H - 150
		if p.vy >= 0 and prev_bottom <= fy + 20 and p.y + p.height >= fy - 10:
			p.y = fy - p.height
			p.vy = 0
			grounded = true
			on_dialog_floor = true
			p.jumps_left = 2
	p.is_grounded = grounded
	if p.is_grounded and not p.was_grounded and p.held_by_cramp == -1 and not p.is_recharging:
		Audio.footstep(0.8)
	p.was_grounded = p.is_grounded
	if p.is_recharging:
		p.anim_progress = 0
	else:
		p.step_animation(d60)
	p.is_sitting = p.is_dead or (p.is_recharging and p.held_by_cramp == -1) or (on_dialog_floor and absf(p.vx) < 0.1 and p.is_grounded)

	# --- camera (the garden is climbed, so keep more of the screen above the player)
	var target := p.y - (H / 2 if is_garden() else H / 3)
	if down and p.is_grounded and not p.is_sitting and absf(p.vx) < 0.5 and not p.is_recharging:
		p.look_down_timer += dt
	else:
		p.look_down_timer = 0
	if p.look_down_timer > 0.3:
		target += minf(300, (p.look_down_timer - 0.3) * 400)
	if dialog_open and target > camera_y:
		target = camera_y
	if boss.active:
		target = level_h
	var k := 0.15 if p.vy > 5 else 0.1
	camera_y += (target - camera_y) * (1.0 - pow(1.0 - k, d60))
	if not boss.active and camera_y < p.y - H + 100:
		camera_y = p.y - H + 100
	if boss.active:
		camera_y = level_h
	if not boss.active and p.y > level_h + 1000:
		p.held_by_cramp = -1
		p.is_recharging = false
		Audio.stop_loop("krcloop.wav")
		_place_at_checkpoint(Game.checkpoint if Game.checkpoint < 5 else 1)
	camera_y = clampf(camera_y, 0, level_h)

	_update_entities(dt, d60)
	_update_particles(dt, d60)
	if boss.active:
		_update_boss(dt, d60)
	if wave.active:
		_update_wave(dt, d60)
	if summit_timer > 0:
		summit_timer += dt


func _update_recharge(dt: float, up: bool, down: bool) -> void:
	p.vx = 0
	var err := false
	match p.breath_index:
		0:
			if up and not down:
				p.breath_timer += dt
			elif p.breath_timer > 0.2:
				err = true
			if p.breath_timer >= 4:
				p.breath_index = 1
				p.breath_timer = 4
		1:
			if (up or down) and p.breath_timer > 4.2:
				err = true
			else:
				p.breath_timer += dt
			if p.breath_timer >= 6:
				p.breath_index = 2
				p.breath_timer = 6
		2:
			if down and not up:
				p.breath_timer += dt
			elif p.breath_timer > 6.2:
				err = true
			else:
				p.breath_timer += dt
	hud.breath_error = err
	if err:
		p.breath_error_timer += dt
		if p.breath_error_timer > 1:
			p.breath_index = 0
			p.breath_timer = 0
			p.breath_error_timer = 0
			p.breath_failed = true
			if p.held_by_cramp == -1:
				p.is_recharging = false
			get_tree().create_timer(0.5).timeout.connect(_clear_breath_failed)
	if p.breath_index == 2 and p.breath_timer >= 12 and not err:
		if p.held_by_cramp != -1:
			for e in level.entities:
				if e.id == p.held_by_cramp:
					e.defeated = true
					e.knocked_back = true
					e.vx = 10
					e.vy = -10
			p.held_by_cramp = -1
			p.invuln_timer = 2
			p.breath_charges = 3
			Audio.stop_loop("krcloop.wav")
			Audio.set_bgm_volume(0.5)
			Audio.play_sfx("krcoff.wav")
		else:
			p.breath_charges = 0 if boss.active else 3
		Audio.play_sfx("breathok.wav")
		p.is_recharging = false
		p.breath_index = 0
		p.breath_timer = 0
		p.breath_error_timer = 0
		p.breathing_cooldown = 0.3
		p.breath_success = true
		if boss.active:
			p.is_breathing = 40
			shake_timer = 0.5
			Audio.play_sfx("krcoff.wav")
		trigger.emit("white_fade")
		get_tree().create_timer(0.5).timeout.connect(_clear_breath_success)


func _update_entities(dt: float, d60: float) -> void:
	var prect := p.rect()
	for e in level.entities:
		if e.collected or (e.defeated and not e.knocked_back):
			continue
		if e.knocked_back:
			e.x += e.vx * d60
			e.y += e.vy * d60
			e.vy += GRAVITY * 4 * d60
			if e.y > camera_y + H + 100:
				e.knocked_back = false
			continue
		var touching := prect.intersects(e.rect())
		match e.type:
			"iron":
				if touching:
					e.collected = true
					Audio.play_sfx("nut0%d.wav" % randi_range(1, 3), 0.6)
					Game.iron += 1
			"enemy":
				_update_enemy(e, dt, d60, touching)
			"spike":
				if touching and not p.is_dead and p.hit_timer <= 0 and p.invuln_timer <= 0 and Game.iron > 0 and not dialog_open:
					_hurt(e.x)
			"trigger":
				if touching and active:
					_hit_trigger(e)
			"updraft":
				if touching and not p.is_dead and not p.is_recharging and p.held_by_cramp == -1:
					p.vy = maxf(p.vy - 1.1 * d60, -9.0)
					p.jumps_left = 2
					p.is_grounded = false


func _update_enemy(e: LevelData.Ent, dt: float, d60: float, touching: bool) -> void:
	if not _first_enemy_seen and Vector2(p.x - e.x, p.y - e.y).length() < 400:
		_first_enemy_seen = true
		trigger.emit("first_enemy")
	if not e.has_base:
		e.base_x = e.x
		e.base_y = e.y
		e.has_base = true
	match e.behavior:
		"float":
			e.x = e.base_x + sin(time_ms / 1000.0 + e.id) * 30
			e.y = e.base_y + cos(time_ms / 800.0 + e.id) * 20
		"distract":
			# Hovers around home and drifts towards a nearby player.
			var hx := e.base_x + sin(time_ms / 900.0 + e.id) * 40
			var hy := e.base_y + cos(time_ms / 700.0 + e.id) * 25
			var to_p := Vector2(p.x - e.x, p.y - e.y)
			if to_p.length() < 320 and not dialog_open:
				e.x += to_p.normalized().x * 0.9 * d60
				e.y += to_p.normalized().y * 0.9 * d60
			else:
				e.x += (hx - e.x) * 0.04 * d60
				e.y += (hy - e.y) * 0.04 * d60
		"chase":
			var home := Vector2(p.x - e.base_x, p.y - e.base_y)
			var dir: Vector2
			var spd := 1.2
			if home.length() < 400:
				dir = Vector2(p.x - e.x, p.y - e.y)
			else:
				dir = Vector2(e.base_x - e.x, e.base_y - e.y)
				spd = 1.0
			if dir.length() > 5:
				dir = dir.normalized() * spd * d60
				e.x += dir.x
				e.y += dir.y
		"lunge":
			e.lunge_timer -= dt
			if e.lunge_timer <= 0:
				var to_p := Vector2(p.x - e.x, p.y - e.y)
				if to_p.length() < 300:
					var v := to_p.normalized() * 5
					e.vx = v.x
					e.vy = v.y
					e.lunge_timer = 2 + randf()
				else:
					e.lunge_timer = 0.5
			if p.held_by_cramp != e.id:
				if e.vx != 0 or e.vy != 0:
					e.x += e.vx * d60
					e.y += e.vy * d60
					e.vx *= pow(0.95, d60)
					e.vy *= pow(0.95, d60)
					if absf(e.vx) < 0.5 and absf(e.vy) < 0.5:
						e.vx = 0
						e.vy = 0
				else:
					e.x += (e.base_x - e.x) * 0.05 * d60
					e.y += (e.base_y - e.y) * 0.05 * d60
	# Breath blast knocks enemies away.
	if p.is_breathing > 0:
		var r := (40.0 - p.is_breathing) / 40.0 * 200.0
		var dv := Vector2(e.x + e.w / 2 - (p.x + p.width / 2), e.y + e.h / 2 - (p.y + p.height / 2))
		if dv.length() < r and not e.knocked_back:
			e.defeated = true
			e.knocked_back = true
			var a := dv.angle()
			e.vx = cos(a) * 8
			e.vy = sin(a) * 8 - 6
			Audio.play_sfx("krcoff.wav")
	if p.held_by_cramp == e.id:
		e.x = p.x + p.width / 2 - e.w / 2
		e.y = p.y + p.height / 2 - e.h / 2
	if e.behavior == "distract":
		# A distraction only slows you down (dashing through it shrugs it off).
		if touching and not e.defeated and not dialog_open and p.is_breathing <= 0 and not p.is_dead:
			e.defeated = true
			e.knocked_back = true
			e.vx = 6.0 if e.x > p.x else -6.0
			e.vy = -8
			if p.dash_timer <= 0:
				p.slow_timer = 2.0
				p.vx *= 0.3
				Audio.play_sfx("au%d.wav" % randi_range(1, 5), 0.6)
			else:
				Audio.play_sfx("krcoff.wav", 0.5)
		return
	if touching and not p.is_dead and p.hit_timer <= 0 and p.invuln_timer <= 0 and not e.defeated and Game.iron > 0 and not dialog_open and p.is_breathing <= 0:
		if Game.has_breathing:
			if p.held_by_cramp == -1:
				# A cramp grabs the player: breathe (▲■▼) to get free.
				p.held_by_cramp = e.id
				p.cramp_drain_timer = 0
				p.vx = 0
				p.vy = 0
				p.breath_charges = 0
				p.is_recharging = true
				p.breath_index = 0
				p.breath_timer = 0
				p.breath_error_timer = 0
				Audio.play_sfx("au%d.wav" % randi_range(1, 5))
				Audio.start_loop("krcloop.wav", 0.8)
				Audio.set_bgm_volume(0.15)
		else:
			_hurt(e.x)


func _hit_trigger(e: LevelData.Ent) -> void:
	if e.trigger_type == "teleport":
		p.x = e.target.x
		p.y = e.target.y
		p.vx = 0
		p.vy = 0
		return
	e.collected = true
	if e.trigger_type == "dialog":
		trigger.emit("dialog_" + e.dialog_id)
		return
	p.vx = 0
	p.vy = 0
	if e.trigger_type == "end":
		start_boss(Game.iron)
	elif e.trigger_type == "wave":
		start_wave()
	elif e.trigger_type == "summit":
		wave.won = true
		wave.active = false
		summit_timer = 0.01
		Audio.play_sfx("finished.wav")
	trigger.emit(e.trigger_type)


func _update_particles(dt: float, d60: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var q: Dictionary = particles[i]
		q.x += q.vx * d60
		q.y += q.vy * d60
		q.rot += q.rot_speed * d60
		if q.type == "boss_body_part" or q.type == "dash" or q.type == "pollen":
			q.vx *= pow(0.95, d60)
			q.vy *= pow(0.95, d60)
		else:
			q.vy += GRAVITY * d60
		if q.has("life"):
			q.life -= dt
			if q.life <= 0:
				particles.remove_at(i)
		elif q.y > camera_y + H + 100:
			particles.remove_at(i)


func _boss_spike_particle() -> void:
	var idx: int = boss.hp - 1
	boss.hp -= 1
	if idx < 0 or idx >= boss.spike_order.size():
		return
	var s: int = boss.spike_order[idx]
	var outer := s >= 10
	var n := s - 10 if outer else s
	var a := n / 10.0 * TAU + time_ms * (0.002 if outer else -0.003)
	particles.append({
		"x": boss.x + cos(a) * boss.radius * 0.5, "y": boss.y + sin(a) * boss.radius * 0.5,
		"vx": cos(a) * 15, "vy": sin(a) * 15, "rot": a, "rot_speed": (randf() - 0.5) * 0.5,
		"type": "boss_spike",
	})


func _update_boss(dt: float, d60: float) -> void:
	var b := boss
	if b.hit_timer > 0:
		b.hit_timer -= dt
	var hit_now := false
	if b.hp > 0:
		# Breath blast (radius 400 in the arena).
		if p.is_breathing > 0 and b.hit_timer <= 0:
			var r := (40.0 - p.is_breathing) / 40.0 * 400.0
			var dv := Vector2(b.x - (p.x + p.width / 2), b.y - (p.y + p.height / 2))
			if dv.length() < r + b.radius:
				b.hit_timer = 0.5
				b.slow_timer = 5.0
				var a := dv.angle()
				b.vx += cos(a) * 2
				b.vy += sin(a) * 2
				for i in mini(b.hp, randi_range(1, 3)):
					_boss_spike_particle()
				Audio.play_sfx("krcoff.wav")
				shake_timer = maxf(shake_timer, 0.5)
				hit_now = true
		if b.defeated_timer == 0:
			if b.lost:
				var tx := p.x + p.width / 2
				var ty := p.y - 120
				b.x += (tx - b.x) * 0.05 * d60
				b.y += (ty - b.y) * 0.05 * d60 + sin(time_ms / 200.0) * 1.5
			elif dialog_open:
				b.x = W / 2
				b.y = level_h + 400
			else:
				if b.slow_timer > 0:
					b.slow_timer -= dt
				var slow: bool = b.slow_timer > 0
				var spd := 1.5 if slow else 5.0
				var min_v := 0.5 if slow else 1.5
				if absf(b.vx) < min_v: b.vx = -min_v if b.vx < 0 else min_v
				if absf(b.vy) < min_v: b.vy = -min_v if b.vy < 0 else min_v
				var v := Vector2(b.vx, b.vy).normalized() * spd
				b.vx = v.x
				b.vy = v.y
				b.x += b.vx * d60
				b.y += b.vy * d60
				var top := camera_y + 100
				if b.x < b.radius:
					b.x = b.radius
					b.vx *= -1
				if b.x > W - b.radius:
					b.x = W - b.radius
					b.vx *= -1
				if b.y < top + b.radius:
					b.y = top + b.radius
					b.vy *= -1
				if b.y > camera_y + H - b.radius:
					b.y = camera_y + H - b.radius
					b.vy *= -1
			# Touching the boss.
			var to_p := Vector2(p.x + p.width / 2 - b.x, p.y + p.height / 2 - b.y)
			if to_p.length() < b.radius + p.width / 2 and not p.is_dead and p.hit_timer <= 0 and p.invuln_timer <= 0 and not b.lost and Game.iron > 0 and not dialog_open:
				if p.vy > 0 and p.y + p.height < b.y + b.radius * 0.5:
					b.hit_timer = 0.5 # stomp: bounce off
					p.vy = -12
					p.is_grounded = false
				else:
					p.hit_timer = 1
					p.vy = -10
					p.vx = -12.0 if p.x < b.x else 12.0
					p.is_grounded = false
					var lose := randi_range(3, 5)
					var lost := mini(Game.iron, lose)
					var left := maxi(0, Game.iron - lose)
					if left == 0:
						_die(true)
					else:
						Game.iron = left
						Audio.nut_sound()
					var removed := 0
					for i in range(hexes.size() - 1, -1, -1):
						if removed >= lost: break
						if hexes[i].active:
							hexes[i].active = false
							removed += 1
					_spray_nuts(lost, 10, 8, 2)
			# Boss eats the iron floor.
			if not dialog_open:
				for hx in hexes:
					if not hx.active:
						continue
					if Vector2(hx.x - b.x, hx.y - b.y).length() < b.radius + HEX_W / 2:
						hx.active = false
						var n := maxi(0, Game.iron - 1)
						if n == 0:
							_die(true)
						else:
							Game.iron = n
							Audio.nut_sound()
						if b.hit_timer <= 0 and not hit_now:
							_boss_spike_particle()
							Audio.play_sfx("krcoff.wav")
							hit_now = true
						_hex_particle(hx)
						if randf() < 0.5:
							for h2 in hexes:
								if h2.active and absf(h2.x - hx.x) <= HEX_W + 5 and absf(h2.y - hx.y) <= HEX_H + 5:
									h2.active = false
									Game.iron = maxi(0, Game.iron - 1)
									if Game.iron == 0:
										_die(true)
									_hex_particle(h2)
									break
						b.vy = absf(b.vy) if b.y > hx.y else -absf(b.vy)
			if hit_now:
				b.hit_timer = 0.5
				if b.hp <= 0 and b.defeated_timer == 0:
					b.defeated_timer = 0.01
					for i in 300:
						particles.append({
							"x": b.x + (randf() - 0.5) * b.radius * 2, "y": b.y + (randf() - 0.5) * b.radius * 2,
							"vx": (randf() - 0.5) * 15, "vy": (randf() - 0.5) * 15, "rot": randf() * TAU,
							"rot_speed": (randf() - 0.5) * 2, "type": "boss_body_part",
							"life": 2 + randf() * 4, "max_life": 6.0,
						})
	if b.defeated_timer > 0:
		b.defeated_timer += dt
		var c := Vector2(W / 2, camera_y + H / 2 - 50)
		if b.defeated_timer > 1.5:
			var t: float = b.defeated_timer - 1.5
			for i in hexes.size():
				var hx: Dictionary = hexes[i]
				if not hx.active:
					continue
				var rad := maxf(0, 150 - t * 50)
				var ang := i * TAU / maxf(1, hexes.size()) + t * 2
				var goal := c + Vector2(cos(ang), sin(ang)) * rad
				var dv := goal - Vector2(hx.x, hx.y)
				var dist := dv.length()
				var spd := 300 + t * 100
				if rad <= 0 and dist < 10:
					hx.active = false
					egg_growth += 1
				elif dist > 5:
					hx.x += dv.x / dist * spd * dt
					hx.y += dv.y / dist * spd * dt
				else:
					hx.x = goal.x
					hx.y = goal.y
		if b.defeated_timer > 0.1 and not _boss_dialog_sent:
			_boss_dialog_sent = true
			Audio.play_sfx("finished.wav")
			boss_defeated.emit()
	# Falling into the lava.
	if b.active and p.y + p.height > camera_y + H - 40 and not b.lost and b.hp > 0:
		b.lost = true
		p.y = camera_y + H - 150 - p.height
		p.vy = 0
		for e in level.entities:
			if e.type == "iron":
				e.collected = false
		_die_quiet()
		boss_lost.emit()


func _die_quiet() -> void:
	p.is_recharging = false
	p.breath_charges = 0
	p.held_by_cramp = -1
	Audio.stop_loop("krcloop.wav")
	Audio.set_bgm_volume(0.5)
	p.is_sitting = true
	p.is_dead = true
	particles.clear()
	shake_timer = 0
	Game.iron = 0


func _hex_particle(hx: Dictionary) -> void:
	particles.append({
		"x": hx.x, "y": hx.y, "vx": (randf() - 0.5) * 10, "vy": -randf() * 8 - 2,
		"rot": randf() * TAU, "rot_speed": (randf() - 0.5) * 0.5, "type": "hex",
	})


# --- level 2: bubbles, the LH wave --------------------------------------------------

func _pop_bubble(pl: LevelData.Plat) -> void:
	pl.regrow = REGROW
	pl.pop_timer = 0
	Audio.play_sfx("breathoff.wav", 0.5)
	for i in 12:
		particles.append({"x": pl.x + randf() * pl.w, "y": pl.y + randf() * 20,
			"vx": (randf() - 0.5) * 6, "vy": -randf() * 4 - 1, "rot": 0.0, "rot_speed": 0.0,
			"type": "pollen", "life": 0.6, "max_life": 0.6})


## The LH wave starts rising below the player (from the trigger, or a retry).
func start_wave() -> void:
	wave.active = true
	wave.lost = false
	wave.won = false
	wave.y = p.y + p.height + 260
	wave.speed = WAVE_SPEED
	summit_timer = 0
	p.slow_timer = 0


func _update_wave(dt: float, d60: float) -> void:
	if wave.lost or wave.won or dialog_open:
		return
	wave.speed = minf(WAVE_MAX, wave.speed + WAVE_ACCEL * dt)
	wave.y -= wave.speed * d60
	if p.y + p.height > wave.y + 12 and not p.is_dead:
		wave.lost = true
		_die_quiet()
		Game.iron = maxi(Game.iron, 1)
		trigger.emit("wave_lost")


# --- drawing ------------------------------------------------------------------

func _draw_bg() -> void:
	if is_garden():
		_draw_garden_bg()
		return
	var ci := _bg
	ci.draw_rect(Rect2(0, 0, W, H), Color("#1a0505"))
	for l in _layers:
		var tex: Texture2D = l[0]
		var speed: float = l[1]
		var off := camera_y * speed
		var th := tex.get_height() / float(tex.get_width()) * W
		var start := floorf(off / th) * th
		var yy := start
		while yy < off + H:
			ci.draw_texture_rect(tex, Rect2(0, yy - off, W, th), false)
			yy += th
	if not boss.active:
		var pulse := sin(time_ms / 4000.0) * 0.5 + 0.5
		Draw.h_gradient(ci, Rect2(0, 0, W * 0.8, H), Color(80 / 255.0, 5 / 255.0, 23 / 255.0, 0.15 + pulse * 0.05), Color(0, 0, 0, 0))
		Draw.vignette(ci, Rect2(0, 0, W, H), Color(0, 0, 0, 0.3 + pulse * 0.1), 0.4)


func _draw_world() -> void:
	var ci := _world
	var t := time_ms
	if not active:
		return
	if p.hit_timer > 0.8:
		ci.draw_rect(Rect2(0, camera_y, W, H), Color(177 / 255.0, 88 / 255.0, 39 / 255.0, (p.hit_timer - 0.8) / 0.2 * 0.5))
	var top := camera_y - 100
	var bottom := camera_y + H + 100
	if hide_platforms:
		return
	for pl in level.platforms:
		if pl.y < top or pl.y > bottom:
			continue
		if pl.kind != "rock":
			_draw_bubble(ci, pl, t)
		elif is_garden():
			_draw_garden_platform(ci, pl, t)
		else:
			_draw_platform(ci, pl, t)
	for e in level.entities:
		if e.collected or (e.defeated and not e.knocked_back):
			continue
		if e.y < top or e.y > bottom:
			continue
		match e.type:
			"iron":
				Draw.iron_nut(ci, Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 300.0 + e.id) * 3), e.w / 2, t / 800.0 + e.id)
			"enemy", "spike":
				if e.behavior == "distract":
					_draw_distraction(ci, e, t)
				elif e.type == "spike" and is_garden():
					_draw_thorn(ci, e, t)
				else:
					_draw_cramp(ci, e, t)
			"updraft":
				_draw_updraft(ci, e, t)
			"trigger":
				if e.trigger_type == "teleport":
					ci.draw_rect(e.rect(), Color(190 / 255.0, 24 / 255.0, 93 / 255.0, 0.1))
				elif e.trigger_type in ["mg2", "mg3", "mg4", "end", "mg5", "mg6", "mg7", "wave", "summit"]:
					_draw_orb(ci, e, t)
			"text":
				ci.draw_string(_font, Vector2(e.x, e.y + e.h / 2 + 8), Text.plain(Text.t(e.text)), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.8))
	if boss.active:
		_draw_arena(ci, t, top, bottom)
	if summit_timer > 0:
		_draw_summit_egg(ci, t)
	for q in particles:
		_draw_particle(ci, q)
	if boss.defeated_timer > 1.5:
		_draw_egg(ci, t)
	if wave.active or wave.lost:
		_draw_wave(ci, t)


func _draw_platform(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var pts := PackedVector2Array()
	var top_line := PackedVector2Array()
	var m := 0.0
	while m <= pl.w:
		var yy := pl.y + sin((pl.x + m) * 0.03 + t * 0.0015) * 3
		pts.append(Vector2(pl.x + m, yy))
		top_line.append(Vector2(pl.x + m, yy))
		m += 10
	m = pl.w
	while m >= 0:
		var f := m / pl.w
		var hh := 10 + sin(f * PI) * (pl.h * 1.5)
		pts.append(Vector2(pl.x + m, pl.y + hh + sin((pl.x + m) * 0.04 + t * 0.002) * 4))
		m -= 10
	Draw.polygon_safe(ci, pts, Color("#881337"))
	if top_line.size() > 1:
		ci.draw_polyline(top_line, Color("#e11d48"), 4.0, true)
	m = 20
	while m < pl.w - 10:
		var f := m / pl.w
		var hh := 10 + sin(f * PI) * (pl.h * 1.5)
		var yy := sin((pl.x + m) * 0.03 + t * 0.0015) * 3
		Draw.quad_curve(ci, Vector2(pl.x + m, pl.y + yy + 2), Vector2(pl.x + m + 15, pl.y + hh * 0.5), Vector2(pl.x + m - 10, pl.y + hh - 5), Color("#4c0519"), 2.0)
		m += 40


func _draw_cramp(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var pulse := sin(t / 150.0) * 6
	var held := p.held_by_cramp == e.id
	var amp := 10.0 if held else 3.0
	var jx := sin(t / 50.0 + e.x) * amp + ((randf() - 0.5) * 10 if held else 0.0)
	var jy := cos(t / 40.0 + e.y) * amp + ((randf() - 0.5) * 10 if held else 0.0)
	var c := Vector2(e.x + e.w / 2 + jx, e.y + e.h / 2 + jy)
	var r := e.w / 2 + pulse
	var pts := PackedVector2Array()
	for i in 10:
		var a := i / 10.0 * TAU + t * 0.002
		var wob := sin(t / 30.0 + i) * 4
		pts.append(c + Vector2(cos(a), sin(a)) * (r + wob))
		var a2 := a + TAU / 20
		pts.append(c + Vector2(cos(a2), sin(a2)) * (r * 0.4))
	var spike := e.type == "spike"
	Draw.polygon_safe(ci, pts, Color("#b91c1c") if spike else Color("#ea580c"))
	ci.draw_circle(c, maxf(1, r * 0.4 + sin(t / 80.0) * 2), Color("#b15827") if spike else Color("#facc15"))


func _draw_orb(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 500.0) * 10)
	var r := 30 + sin(t / 300.0) * 5
	var glow := Color(95 / 255.0, 155 / 255.0, 153 / 255.0, 0.6)
	var core := Color("#c7e1e0")
	var dots := Color("#9fcbcb")
	if e.trigger_type in ["wave", "summit"]:
		glow = Color(250 / 255.0, 204 / 255.0, 21 / 255.0, 0.55)
		core = Color("#fef3c7")
		dots = Color("#fde68a")
	elif is_garden():
		glow = Color(134 / 255.0, 239 / 255.0, 172 / 255.0, 0.55)
		core = Color("#ecfdf5")
		dots = Color("#86efac")
	Draw.radial_glow(ci, c, r * 2, glow)
	ci.draw_circle(c, r * 0.5, core)
	for i in 3:
		var a := t / 1000.0 + i * TAU / 3
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 1.2, 4, dots)


func _draw_arena(ci: CanvasItem, t: float, top: float, bottom: float) -> void:
	var lava_y := camera_y + H - 40
	if boss.defeated_timer > 0:
		var yy := lava_y + maxf(0, 40 - boss.defeated_timer * 40)
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= W:
			pts.append(Vector2(x, yy + sin(x * 0.03 + t * 0.0015) * 3))
			x += 20
		pts.append(Vector2(W, camera_y + H))
		pts.append(Vector2(0, camera_y + H))
		Draw.polygon_safe(ci, pts, Color("#b15827"))
	else:
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= W:
			pts.append(Vector2(x, lava_y + sin(t / 200.0 + x / 50.0) * 8 + cos(t / 300.0 + x / 30.0) * 5))
			x += 20
		pts.append(Vector2(W, camera_y + H))
		pts.append(Vector2(0, camera_y + H))
		Draw.polygon_safe(ci, pts, Color("#9a3b1f"))
		for i in 10:
			var bx := fmod(t / 20.0 + i * 100, W)
			var by := lava_y + 20 + sin(t / 150.0 + i) * 10
			ci.draw_circle(Vector2(bx, by), maxf(0.5, 2 + sin(t / 100.0 + i) * 2), Color(252 / 255.0, 165 / 255.0, 165 / 255.0, 0.6))
	for hx in hexes:
		if hx.active and hx.y >= top and hx.y <= bottom:
			Draw.hex_tile(ci, Vector2(hx.x, hx.y), 0.0, HEX_W / 2)
	if boss.hp > 0 and boss.defeated_timer == 0 and boss.y >= top and boss.y <= bottom:
		_draw_boss(ci, t)


func _draw_boss(ci: CanvasItem, t: float) -> void:
	var b := boss
	var col := Color("#fca5a5") if b.hit_timer > 0 else Color("#b15827")
	var c := Vector2(b.x, b.y) + Vector2(sin(t / 50.0 + b.x) * 6, cos(t / 40.0 + b.y) * 6)
	var r: float = b.radius + sin(t / 150.0) * 12
	var alive := {}
	for i in range(0, maxi(0, b.hp)):
		alive[b.spike_order[i]] = true
	var rot1 := t * 0.002 + sin(t / 1500.0) * 0.8 + cos(t / 800.0) * 0.3
	var rot2 := t * -0.0025 + sin(t / 1100.0 + 1) * 1.0
	for ring in [[10, rot1], [0, rot2]]:
		var pts := PackedVector2Array()
		for i in 10:
			var a: float = i / 10.0 * TAU + ring[1]
			var wob := sin(t / 30.0 + i) * 8
			var a0 := a - TAU / 20
			var a1 := a + TAU / 20
			pts.append(c + Vector2(cos(a0), sin(a0)) * r * 0.5)
			if alive.has(ring[0] + i):
				pts.append(c + Vector2(cos(a), sin(a)) * (r + 15 + wob))
			pts.append(c + Vector2(cos(a1), sin(a1)) * r * 0.5)
		Draw.polygon_safe(ci, pts, col)
	ci.draw_circle(c, r * 0.4, Color("#fef08a"))


func _draw_particle(ci: CanvasItem, q: Dictionary) -> void:
	var pos := Vector2(q.x, q.y)
	match q.type:
		"hex":
			Draw.hex_tile(ci, pos, q.rot, HEX_W / 2)
		"nut":
			Draw.nut_particle(ci, pos, q.rot)
		"spark":
			ci.draw_set_transform(pos, q.rot, Vector2.ONE)
			ci.draw_rect(Rect2(-4, -4, 8, 8), Color("#b15827"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"boss_body_part":
			var a: float = q.life / q.max_life if q.has("life") else 1.0
			ci.draw_circle(pos, 3 + fmod(absf(q.x), 2.0), Color(177 / 255.0, 88 / 255.0, 39 / 255.0, clampf(a, 0, 1)))
		"boss_spike":
			ci.draw_set_transform(pos, q.rot, Vector2.ONE)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-10, -5), Vector2(15, 0), Vector2(-10, 5)]), Color("#b15827"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		"dash":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 3 + 6 * a, Color(1, 1, 1, 0.5 * a))
		"pollen":
			var a: float = q.life / q.max_life
			ci.draw_circle(pos, 2 + 2 * a, Color(1, 0.95, 0.75, 0.8 * a))


func _draw_egg(ci: CanvasItem, t: float) -> void:
	var c := Vector2(W / 2, camera_y + H / 2 - 50)
	var g := egg_growth / maxf(1, hexes.size())
	var r := maxf(0.1, g * 45)
	var pulse := sin(t / 200.0) * 3 * g
	Draw.radial_glow(ci, c, r + 20 * g + pulse, Color(224 / 255.0, 89 / 255.0, 122 / 255.0, 0.6), Color(1, 1, 1, 0.9))
	ci.draw_circle(c, r * 0.8, Color("#efdacd"))
	ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.2), maxf(0.1, r * 0.3), Color("#d69c70"))


func _draw_player() -> void:
	var ci := _player_layer
	PlayerArt.draw(ci, p, time_ms, boss.active, {
		"crouched": p.held_by_cramp != -1,
		"pain": p.hit_timer > 0 or p.held_by_cramp != -1,
		"sitting": p.is_sitting,
		"airborne": false if p.is_recharging else not p.is_grounded,
	})
	if not active:
		return
	var screen := Rect2(0, camera_y, W, H)
	if p.held_by_cramp != -1:
		var k := p.breath_timer / 12.0
		var a := maxf(0, 0.6 * (1 - k)) + sin(time_ms / 200.0) * 0.1
		Draw.vignette(ci, screen, Color(80 / 255.0, 5 / 255.0, 23 / 255.0, clampf(a, 0, 1)), 0.0)
	elif p.breath_success:
		Draw.vignette(ci, screen, Color(95 / 255.0, 155 / 255.0, 153 / 255.0, 0.4), 0.0)


# --- level 2 drawing -----------------------------------------------------------------

## Progress up the garden: 0 at the bottom (dusk), 1 at the top (morning).
func _climb() -> float:
	return clampf(1.0 - (camera_y + H / 2) / maxf(1, level_h), 0, 1)


func _draw_garden_bg() -> void:
	var ci := _bg
	var k := _climb()
	# Dusk (dark indigo & pink) → dawn → spring morning.
	var stops_top := [Color("#1c1533"), Color("#4a2a5e"), Color("#c76a8a"), Color("#8fd0c4")]
	var stops_bot := [Color("#0e0c18"), Color("#2a1e3a"), Color("#5a3a6a"), Color("#f2d9a0")]
	var f := k * 3.0
	var i := int(floorf(f))
	var u := f - i
	var top_c: Color = stops_top[mini(i, 3)].lerp(stops_top[mini(i + 1, 3)], u)
	var bot_c: Color = stops_bot[mini(i, 3)].lerp(stops_bot[mini(i + 1, 3)], u)
	var bands := 16
	for b in bands:
		var y0 := H * b / bands
		ci.draw_rect(Rect2(0, y0, W, H / bands + 1), top_c.lerp(bot_c, (b + 0.5) / bands))
	# Sun rising behind the summit.
	if k > 0.45:
		var sk := (k - 0.45) / 0.55
		var sc := Vector2(W * 0.72, H * (1.1 - sk * 0.9))
		Draw.radial_glow(ci, sc, 220 + sk * 120, Color(1, 0.92, 0.6, 0.35 * sk), Color(1, 0.98, 0.85, 0.9 * sk))
	# Vines along the edges (parallax) and drifting pollen.
	var t := time_ms
	for v in 6:
		var side := -1.0 if v % 2 == 0 else 1.0
		var depth := 0.3 + 0.12 * v
		var off := camera_y * depth
		var x0 := (W / 2) + side * (W / 2 - 40 - v * 35)
		var pts := PackedVector2Array()
		var yy := -40.0
		while yy < H + 40:
			pts.append(Vector2(x0 + sin((yy + off) * 0.012 + v) * 18, yy))
			yy += 24
		var vc := Color(0.1, 0.35, 0.2, 0.25 + 0.06 * v).lerp(Color(0.2, 0.55, 0.3, 0.35), k)
		ci.draw_polyline(pts, vc, 3 + v, true)
		var ly := fmod(-off * 0.5, 160.0)
		while ly < H:
			var lp := Vector2(x0 + sin((ly + off) * 0.012 + v) * 18, ly)
			ci.draw_set_transform(lp, side * 0.6 + sin(t / 900.0 + ly) * 0.1, Vector2(1, 0.45))
			ci.draw_circle(Vector2.ZERO, 12 + v, vc)
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			ly += 160
	for i2 in 36:
		var px := fmod(i2 * 173.0 + sin(t / 1500.0 + i2) * 30 + W, W)
		var py := fmod(H - fmod(t * (0.02 + 0.01 * (i2 % 3)) + i2 * 97.0, H), H)
		ci.draw_circle(Vector2(px, py), 1.5 + (i2 % 3) * 0.7, Color(1, 0.95, 0.7, 0.25 + 0.3 * k))
	Draw.vignette(ci, Rect2(0, 0, W, H), Color(0, 0, 0, 0.35 - 0.2 * k), 0.45)


func _draw_garden_platform(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var pts := PackedVector2Array()
	var top_line := PackedVector2Array()
	var m := 0.0
	while m <= pl.w:
		var yy := pl.y + sin((pl.x + m) * 0.03 + t * 0.0015) * 2
		pts.append(Vector2(pl.x + m, yy))
		top_line.append(Vector2(pl.x + m, yy))
		m += 10
	m = pl.w
	while m >= 0:
		var f := m / pl.w
		var hh := 8 + sin(f * PI) * (pl.h * 1.2)
		pts.append(Vector2(pl.x + m, pl.y + hh + sin((pl.x + m) * 0.05 + t * 0.002) * 3))
		m -= 10
	Draw.polygon_safe(ci, pts, Color("#2f5d3f"))
	if top_line.size() > 1:
		ci.draw_polyline(top_line, Color("#86efac"), 4.0, true)
	# Small leaves along the top, roots underneath.
	m = 14
	while m < pl.w - 8:
		var lp := Vector2(pl.x + m, pl.y - 2)
		ci.draw_set_transform(lp, -0.5 + sin(t / 700.0 + m) * 0.15, Vector2(1, 0.5))
		ci.draw_circle(Vector2.ZERO, 6, Color("#4ade80"))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		Draw.quad_curve(ci, Vector2(pl.x + m + 6, pl.y + 10), Vector2(pl.x + m + 14, pl.y + 24), Vector2(pl.x + m + 2, pl.y + 30), Color("#1e3d2a"), 2.0)
		m += 36


func _draw_bubble(ci: CanvasItem, pl: LevelData.Plat, t: float) -> void:
	var c := Vector2(pl.x + pl.w / 2, pl.y + 14)
	var near := clampf(1.0 - Vector2(p.x + p.width / 2 - c.x, p.y + p.height - c.y).length() / 220.0, 0, 1)
	var grow := 1.0 + 0.22 * near
	var base := Color("#f9a8d4") if pl.kind == "bubble" else Color("#fde68a")
	if pl.regrow > 0:
		# Regrowing: a small faint bubble swelling back.
		var g := 1.0 - pl.regrow / REGROW
		ci.draw_set_transform(c, 0, Vector2(1, 0.7))
		ci.draw_circle(Vector2.ZERO, maxf(1, (pl.w / 2 + 6) * g * 0.6), Color(base, 0.15 * g))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	var jitter := Vector2.ZERO
	if pl.kind == "pop" and pl.pop_timer > 0:
		var k := pl.pop_timer / POP_AFTER
		jitter = Vector2((randf() - 0.5) * 6 * k, (randf() - 0.5) * 4 * k)
	# A cluster: one follicle per cell of the platform.
	var n := maxi(1, int(roundf(pl.w / LevelData.CELL_W)))
	var cw := pl.w / n
	for i in n:
		var cc := Vector2(pl.x + cw * (i + 0.5), pl.y + 12) + jitter
		var r := cw / 2 + 5 + sin(t / 400.0 + pl.x + i) * 2
		ci.draw_set_transform(cc, 0, Vector2(grow, 0.8 * grow))
		ci.draw_circle(Vector2.ZERO, r, Color(base, 0.35))
		ci.draw_arc(Vector2.ZERO, r, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)
		ci.draw_circle(Vector2(-r * 0.4, -r * 0.35), r * 0.18, Color(1, 1, 1, 0.75))
		if pl.kind == "pop":
			# A tiny follicle inside: these are about to burst.
			ci.draw_circle(Vector2(r * 0.2, r * 0.15), r * 0.25, Color("#f472b6", 0.5))
		ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _draw_updraft(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var r := e.rect()
	ci.draw_rect(r, Color(1, 1, 0.8, 0.05))
	for i in 7:
		var yy := r.end.y - fmod(t * 0.12 + i * 37.0, r.size.y)
		var xx := r.position.x + 6 + fmod(i * 13.0, r.size.x - 12)
		var a := clampf((yy - r.position.y) / r.size.y, 0, 1)
		ci.draw_line(Vector2(xx, yy), Vector2(xx, yy - 14), Color(1, 1, 0.85, 0.5 * a), 2.0)


func _draw_thorn(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h)
	for i in 3:
		var bx := c.x + (i - 1) * 10
		var pts := PackedVector2Array([Vector2(bx - 6, c.y), Vector2(bx + (i - 1) * 3, c.y - 26 - (3 if i == 1 else 0)), Vector2(bx + 6, c.y)])
		ci.draw_colored_polygon(pts, Color("#166534"))
		ci.draw_line(pts[0], pts[1], Color("#4ade80"), 1.5, true)


func _draw_distraction(ci: CanvasItem, e: LevelData.Ent, t: float) -> void:
	var c := Vector2(e.x + e.w / 2, e.y + e.h / 2 + sin(t / 180.0 + e.id) * 3)
	var r := Rect2(c.x - 22, c.y - 15, 44, 30)
	Draw.panel(ci, r, Color("#e2e8f0"), 8, Color("#94a3b8"), 1)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, r.end.y), Vector2(c.x + 6, r.end.y), Vector2(c.x, r.end.y + 7)]), Color("#e2e8f0"))
	ci.draw_line(Vector2(r.position.x + 9, c.y - 4), Vector2(r.end.x - 9, c.y - 4), Color("#94a3b8"), 2.0)
	ci.draw_line(Vector2(r.position.x + 9, c.y + 3), Vector2(r.end.x - 15, c.y + 3), Color("#cbd5e1"), 2.0)
	ci.draw_circle(Vector2(r.end.x - 4, r.position.y + 4), 6 + sin(t / 120.0) * 1.0, Color("#ef4444"))
	ci.draw_string(_font, Vector2(r.end.x - 7, r.position.y + 8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)


func _draw_wave(ci: CanvasItem, t: float) -> void:
	var yy: float = wave.y
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= W:
		pts.append(Vector2(x, yy + sin(t / 180.0 + x / 60.0) * 8 + cos(t / 260.0 + x / 35.0) * 4))
		x += 20
	pts.append(Vector2(W, camera_y + H + 50))
	pts.append(Vector2(0, camera_y + H + 50))
	Draw.polygon_safe(ci, pts, Color(0.98, 0.75, 0.3, 0.85))
	var glow := PackedVector2Array()
	for i in range(0, pts.size() - 2):
		glow.append(pts[i])
	ci.draw_polyline(glow, Color(1, 0.97, 0.8, 0.95), 5.0, true)
	for i in 14:
		var bx := fmod(t / 15.0 + i * 83.0, W)
		var by := yy + 16 + sin(t / 140.0 + i) * 9
		ci.draw_circle(Vector2(bx, by), maxf(0.5, 2.5 + sin(t / 90.0 + i) * 1.5), Color(1, 1, 0.85, 0.7))
	ci.draw_string(_font, Vector2(W / 2 - 40, yy + 46), "LH ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.5, 0.25, 0.05, 0.8))


func _draw_summit_egg(ci: CanvasItem, t: float) -> void:
	var k := clampf(summit_timer / 2.0, 0, 1)
	var c := Vector2(W / 2, p.y - 60 - k * 120)
	var r := 10 + 30 * k
	Draw.radial_glow(ci, c, r * 2.5 + sin(t / 200.0) * 4, Color(1, 0.9, 0.55, 0.6 * k), Color(1, 1, 0.9, 0.95 * k))
	ci.draw_circle(c, r * 0.8, Color("#fff7df", k))
	ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.2), maxf(0.1, r * 0.3), Color("#f9a8d4", k))
	for i in 8:
		var a := t / 600.0 + i * TAU / 8
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * (r + 24 + sin(t / 300.0 + i) * 6), 3, Color(1, 0.95, 0.7, 0.8 * k))
