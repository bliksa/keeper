class_name BreathingGame
extends Minigame
## Forest minigame: 6 calm breathing cycles — hold ▲ 4 s (inhale), release
## 2 s (hold), hold ▼ 6 s (exhale). Port of the web `f2` component.

const CYCLES := 6
const CENTER := Vector2(842, 360)
const DOT_R := 140.0
const TEAL := Color("#5f9b99")
const RUST := Color("#b15827")

var phase := "inhale"
var progress := 0.0
var is_error := false
var cycles := 0
var waiting := true
var lost_dot := -1
var hint_key := ""
var fail_count := 0
var _err_ms := 0.0
var _idle_ms := 0.0
var _spin := 0.0
var _pop := {}
var _intro_voice_played := false


func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_send_hint()


func _on_dialog_active_changed() -> void:
	if not dialog_active:
		_send_hint()


func _send_hint() -> void:
	if dialog_active or _done:
		return
	hint.emit({"title": "NAME_ESTRA", "text": hint_key if hint_key != "" else "DIA_B00", "hide_button": true})
	if hint_key == "" and cycles == 0 and waiting and not _intro_voice_played:
		_intro_voice_played = true
		Audio.play_voice("DIA_B00.wav")


func _say(key: String) -> void:
	hint_key = key
	Audio.play_voice(key + ".wav")


func _process(delta: float) -> void:
	_spin += delta * TAU / 20.0
	for k in _pop.keys():
		_pop[k] -= delta
		if _pop[k] <= 0:
			_pop.erase(k)
	queue_redraw()
	if _done or dialog_active or cycles >= CYCLES:
		return
	var ms := minf(delta * 1000.0, 100.0)
	var up := Input.is_action_pressed("move_up") or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	var down := Input.is_action_pressed("move_down") or Input.is_joy_button_pressed(0, JOY_BUTTON_X)
	var old_hint := hint_key

	if waiting:
		if up:
			waiting = false
			_idle_ms = 0
		else:
			_idle_ms += ms
			if _idle_ms > 10000:
				_idle_ms = 0
				if cycles > 0:
					cycles -= 1
					lost_dot = cycles
					_pop[cycles] = 0.3
					var enc: Array = Text.breathing_hints.get("encouragement", ["DIA_B10"])
					_say(enc.pick_random())
				else:
					_say("DIA_B00")
			if hint_key != old_hint:
				_send_hint()
			return
	else:
		_idle_ms = 0

	var bad := false
	match phase:
		"inhale":
			progress += ms / 4000.0
			bad = not (up and not down)
			if progress >= 1:
				phase = "hold"
				progress = 0
		"hold":
			progress += ms / 2000.0
			bad = up or down
			if progress >= 1:
				phase = "exhale"
				progress = 0
		"exhale":
			progress += ms / 6000.0
			bad = not (down and not up)
			if progress >= 1:
				cycles += 1
				_pop[cycles - 1] = 0.6
				if cycles < CYCLES:
					var ok: Array = Text.breathing_hints.get("success", ["DIA_B01"])
					_say(ok[cycles % ok.size()])
				else:
					hint_key = "DIA_009_FINAL"
					finish(0.5)
				Audio.play_sfx("breathok.wav", 0.6)
				phase = "inhale"
				progress = 0
				_err_ms = 0
				waiting = true
				lost_dot = -1
				fail_count = 0
	if bad:
		_err_ms += ms
		if _err_ms > 1500:
			Audio.play_sfx("breathoff.wav", 0.6)
			cycles = maxi(0, cycles - 1)
			lost_dot = cycles
			_pop[cycles] = 0.3
			phase = "inhale"
			progress = 0
			_err_ms = 0
			waiting = true
			fail_count += 1
			if fail_count >= 2:
				_say(Text.breathing_hints.get("errorLong", ["DIA_B09"])[0])
				fail_count = 0
			else:
				var short: Array = Text.breathing_hints.get("errorShort", ["DIA_B06"])
				_say(short.pick_random())
	else:
		_err_ms = 0
		lost_dot = -1
	is_error = bad
	if hint_key != old_hint:
		_send_hint()


func _draw() -> void:
	var a := 0.5 if dialog_active else 1.0
	# Ring of cycle dots.
	for i in CYCLES:
		var ang := i / float(CYCLES) * TAU - PI / 2 + _spin
		var c := CENTER + Vector2(cos(ang), sin(ang)) * DOT_R
		var done := i < cycles
		var lost := i == lost_dot
		var pop: float = _pop.get(i, 0.0)
		var r := 12.0 * (1.0 + pop)
		if done:
			draw_circle(c, r + 6, Color(TEAL, 0.35 * a))
			draw_circle(c, r, Color("#10b981", a))
		elif lost:
			draw_circle(c, r, Color("#ef4444", a))
		else:
			draw_circle(c, r, Color(1, 1, 1, 0.2 * a))
			draw_arc(c, r, 0, TAU, 24, Color(1, 1, 1, 0.4 * a), 1.0, true)
		if pop > 0:
			draw_arc(c, r * (1 + (0.6 - pop) * 3), 0, TAU, 24, Color(1, 1, 1, pop * a), 2.0, true)
	# Breathing ball.
	var s := 1.0
	match phase:
		"inhale": s = 1.0 + progress * 0.5
		"hold": s = 1.5
		"exhale": s = 1.5 - progress * 0.5
	draw_circle(CENTER + Vector2(0, 4), 64 * s + 6, Color(0, 0, 0, 0.15 * a))
	draw_circle(CENTER, 64 * s, Color(RUST if is_error else TEAL, a))
	# Centre label: arrows for the first two cycles, countdown for cycles 3–4.
	if cycles >= 2 and cycles < 4 and not waiting:
		var n := 1
		var total := 1
		match phase:
			"inhale":
				n = ceili(4 - progress * 4)
				total = 4
			"hold":
				n = ceili(2 - progress * 2)
				total = 2
			"exhale":
				n = ceili(6 - progress * 6)
				total = 6
		Draw.text_center(self, Text.font_bold, CENTER, str(n), 72 if n == total else 48, Color(1, 1, 1, a))
	elif cycles < 2:
		var bob := sin(Time.get_ticks_msec() / 160.0) * 8 if waiting else 0.0
		var c := CENTER + Vector2(0, bob)
		var col := Color(1, 1, 1, a)
		match phase:
			"inhale":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -24), c + Vector2(24, 18), c + Vector2(-24, 18)]), col)
			"hold":
				draw_rect(Rect2(c - Vector2(18, 18), Vector2(36, 36)), col)
			"exhale":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, 24), c + Vector2(24, -18), c + Vector2(-24, -18)]), col)
