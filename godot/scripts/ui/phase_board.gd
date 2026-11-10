class_name PhaseBoard
## The announcement of a phase of the cycle, the same in all four levels: a board where the
## dialog box sits (the dialog-box panel with a casino marquee along its top), a big title
## popping in ("New phase: follicular") and a line under it. The jackpot climb draws it on its
## own board (PlatformerHud._draw_board uses draw_title / draw_marquee); the cave, the forest
## run and the PMS maze show the whole board for the note's time (draw), then their first dialog.
##
## A note = {key, sub, t, dur}: text keys, seconds shown (t < 0: still waiting to show),
## its duration. Its owner ticks it (tick).

## Seconds of a note that is read standing still (the cave, the run, the maze); the climb's,
## read while playing, is Platformer.PHASE_TIME.
const READ_TIME := 4.5
## The bulbs light up one by one during the first BULBS s.
const BULBS := 0.8
const RECT := Rect2(0, 600 - 150, 1066, 150)
const TEXT_LEFT := 158.0
const INK := Color("#064e3b")


static func note(key: String, sub := "", dur := READ_TIME, delay := 0.0) -> Dictionary:
	return {"key": key, "sub": sub, "t": -delay, "dur": dur}


## Is the note on screen (not empty, its delay over)?
static func showing(n: Dictionary) -> bool:
	return not n.is_empty() and float(n.t) >= 0.0


## Advances a note; returns {} when it is over. Chimes when it appears.
static func tick(n: Dictionary, dt: float) -> Dictionary:
	if n.is_empty():
		return n
	var before: float = n.t
	n.t = before + dt
	if before < 0.0 and float(n.t) >= 0.0:
		Audio.play_sfx("cink-11.wav", 0.5)
	if float(n.t) >= float(n.get("dur", READ_TIME)):
		return {}
	return n


## The whole board with the note (levels that have no board of their own). t: a clock in ms.
static func draw(ci: CanvasItem, n: Dictionary, t: float, speaker := "Estrogenka") -> void:
	if not showing(n):
		return
	var r := RECT
	var nt: float = n.t
	var dur: float = n.get("dur", READ_TIME)
	var a := clampf(nt / 0.25, 0, 1) * clampf((dur - nt) / 0.3, 0, 1)
	ci.draw_rect(Rect2(r.position - Vector2(0, 10), Vector2(r.size.x, 10)), Color(0, 0, 0, 0.12 * a))
	ci.draw_rect(r, Color(DialogBox.PANEL_BG, DialogBox.PANEL_BG.a * a))
	var av := Rect2(16, r.position.y + 18, r.size.y - 34, r.size.y - 34)
	Draw.panel(ci, av, Color(DialogBox.PANEL_BG.darkened(0.06), a), 12, Color("#fbbf24", a), 3)
	var tex := SpriteArt.portrait(speaker, t)
	if tex:
		var ts := tex.get_size()
		var k := maxf((av.size.x - 8) / ts.x, (av.size.y - 8) / ts.y)
		var src := Rect2((ts - (av.size - Vector2(8, 8)) / k) / 2, (av.size - Vector2(8, 8)) / k)
		ci.draw_texture_rect_region(tex, av.grow(-4), src, Color(1, 1, 1, a))
	draw_title(ci, Text.font_bold, n, r, t)
	draw_marquee(ci, r, t, n, true, a)


## The title popping in and the sub-line under it, both fading out at the end.
static func draw_title(ci: CanvasItem, font: Font, n: Dictionary, r: Rect2, t: float) -> void:
	var nt: float = n.t
	if nt < 0:
		return
	var dur: float = n.get("dur", READ_TIME)
	var a := clampf(nt / 0.25, 0, 1) * clampf((dur - nt) / 0.4, 0, 1)
	var title := Text.plain(Text.t(str(n.key)))
	var size := title_size(font, title)
	var right := 1066.0 - 24.0
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pop := 1.0 + 0.25 * (1.0 - clampf(nt / 0.3, 0, 1)) + 0.02 * sin(t / 90.0)
	var tp := Vector2(TEXT_LEFT, r.position.y + 62)
	ci.draw_set_transform(tp, 0, Vector2(pop, pop))
	Draw.radial_glow(ci, Vector2(tw / 2, -10), tw * 0.55, Color(1, 0.8, 0.25, 0.25 * a))
	ci.draw_string_outline(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0.47, 0.2, 0.03, a))
	ci.draw_string(font, Vector2.ZERO, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.86, 0.3, a))
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var sub: String = str(n.get("sub", ""))
	if sub != "":
		var line := Text.plain(Text.t(sub))
		var f: Font = Text.font_dialog
		var sa := clampf((nt - 0.35) / 0.3, 0, 1) * a
		var w := right - TEXT_LEFT
		var fs := sub_size(f, line)
		ci.draw_multiline_string(f, Vector2(TEXT_LEFT, r.position.y + 86 + f.get_ascent(fs)), line, HORIZONTAL_ALIGNMENT_LEFT, w, fs, -1, Color(INK, sa))


static func title_size(font: Font, title: String) -> int:
	var size := 34
	while font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > 1066.0 - 24.0 - TEXT_LEFT and size > 20:
		size -= 2
	return size


static func sub_size(f: Font, line: String) -> int:
	var fs := 17
	while fs > 12 and f.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, 1066.0 - 24.0 - TEXT_LEFT, fs).y > SUB_H:
		fs -= 1
	return fs


## Height the sub-line has (two lines of its largest size).
const SUB_H := 52.0


## The gold trim and the marquee along the board's top: bulbs chasing; with a note the strip
## lights up bulb by bulb from the left, then blinks all together. lit: the bulbs chase.
static func draw_marquee(ci: CanvasItem, r: Rect2, t: float, n: Dictionary, lit := true, a := 1.0) -> void:
	var pt: float = n.get("t", -1.0)
	var dur: float = n.get("dur", READ_TIME)
	var strip_k := clampf(pt / BULBS, 0, 1) if pt >= 0 else 1.0
	var gold := Color("#f59e0b", a)
	if pt >= 0 and pt < dur - 0.6 and fmod(pt, 0.3) < 0.15:
		gold = Color("#fde047", a)
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x * strip_k, 4), gold)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 14, r.size.x * strip_k, 2), Color("#fbbf24", 0.8 * a))
	var step := 26.0
	var cnt := int(1066 / step)
	var chase := int(t / 110.0)
	for i in cnt + 1:
		var c := Vector2(8 + i * step, r.position.y + 9)
		var on := (i + chase) % 3 == 0 and lit
		if pt >= 0:
			if pt < BULBS:
				# Lighting up one by one, left to right (the rest still dark).
				if float(i) / cnt > strip_k:
					ci.draw_circle(c, 3.5, Color("#92400e", 0.6 * a))
					continue
				on = float(i) / cnt > strip_k - 0.12
			elif pt < dur - 0.6:
				on = fmod(pt, 0.3) < 0.15
		if on:
			ci.draw_circle(c, 7, Color(1, 0.85, 0.3, 0.35 * a))
		ci.draw_circle(c, 3.5, Color("#fff7c2", a) if on else Color("#d97706", a))


## Texts that don't fit the board at a readable size (tests; current language).
static func fit_problems() -> Array:
	var out: Array = []
	for pair in [["CAVE_PHASE_NEW", "CAVE_PHASE_SUB"], ["RUN_PHASE_NEW", "RUN_PHASE_SUB"], ["CLIMB_PHASE_NEW", "CLIMB_PHASE_SUB"], ["PMS_PHASE_NEW", "PMS_PHASE_SUB"]]:
		var title := Text.plain(Text.t(pair[0]))
		if title_size(Text.font_bold, title) < 26:
			out.append("%s: title at %d px" % [pair[0], title_size(Text.font_bold, title)])
		var line := Text.plain(Text.t(pair[1]))
		var fs := sub_size(Text.font_dialog, line)
		if fs < 14 or Text.font_dialog.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, 1066.0 - 24.0 - TEXT_LEFT, fs).y > SUB_H:
			out.append("%s: sub-line at %d px" % [pair[1], fs])
	return out
