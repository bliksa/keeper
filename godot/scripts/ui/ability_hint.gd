class_name AbilityHints
extends RefCounted
## One way to announce abilities in every level: small right-aligned pills directly
## under the top-right indicator (the cave's breath pill, the runner's water pill, the
## climb's corner), one per ability that can be used right now, with its key.
##
## The caller passes the wanted lines every frame to `update()` (an i18n key, or
## {key, k} with k = 0..1 for a draining time bar) and draws them with `draw()`.
## Lines fade in / out (FADE s). Text: `Text.t(key)` (filtered by the control mode);
## "<key part>: <description>" draws the key part as a small key cap, gamepad glyphs
## (🔴 🟡 ⬆ …) as their images.

const FADE := 0.2
const SIZE := 13
const H := 26.0
const GAP := 5.0
const BG := Color("#f0eee9", 0.94)
const INK := Color("#064e3b")
const BORDER := Color(0.37, 0.61, 0.6, 0.35)
const CAP := Color("#064e3b")
const CAP_TEXT := Color("#f0eee9")
const BAR := Color("#5f9b99")

## key → {a: alpha 0..1, k: time bar (-1 = none), on: wanted this frame}
var _lines := {}
var _order: Array = []


## The wanted lines this frame: [key] or [{key, k}].
func update(delta: float, wanted: Array) -> void:
	var now := {}
	var keys: Array = []
	for w in wanted:
		var key: String = w if w is String else str(w.key)
		var k: float = -1.0 if w is String else float(w.get("k", -1.0))
		now[key] = k
		keys.append(key)
	for key in keys:
		if not _lines.has(key):
			_lines[key] = {"a": 0.0, "k": now[key], "on": true}
		var l: Dictionary = _lines[key]
		l.on = true
		l.k = now[key]
		l.a = minf(1.0, float(l.a) + delta / FADE)
	for key in _lines.keys():
		if not now.has(key):
			var l: Dictionary = _lines[key]
			l.on = false
			l.a = maxf(0.0, float(l.a) - delta / FADE)
			if l.a <= 0.0:
				_lines.erase(key)
	# Wanted lines in their order; the fading ones stay where they were.
	var order: Array = []
	for key in _order:
		if _lines.has(key) and not now.has(key):
			order.append(key)
	var merged: Array = []
	for key in keys:
		merged.append(key)
	for key in order:
		var at := _order.find(key)
		merged.insert(mini(at, merged.size()), key)
	_order = merged


## The keys of the lines shown right now (wanted this frame).
func active() -> Array:
	return _order.filter(func(k): return _lines.has(k) and _lines[k].on)


func clear() -> void:
	_lines.clear()
	_order.clear()


## Draws the lines under `anchor` (the indicator's bottom-right corner, or its
## bottom-centre with `centered`).
func draw(ci: CanvasItem, anchor: Vector2, centered := false) -> void:
	var y := anchor.y + 6.0
	for key in _order:
		if not _lines.has(key):
			continue
		var l: Dictionary = _lines[key]
		var a: float = l.a
		if a <= 0.0:
			continue
		var e := a * a * (3.0 - 2.0 * a)
		draw_line_pill(ci, Text.t(key), Vector2(anchor.x, y - (1.0 - e) * 6.0), e, float(l.k), centered)
		y += (H + GAP) * e


## One pill; returns its width. `pos` = its top-right corner (top-centre if `centered`).
static func draw_line_pill(ci: CanvasItem, text: String, pos: Vector2, alpha: float, k := -1.0, centered := false) -> float:
	var font: Font = Text.font_bold
	var key_part := ""
	var desc := text
	var colon := text.find(": ")
	if colon > 0:
		key_part = text.substr(0, colon)
		desc = text.substr(colon + 2)
	var key_segs := _segments(key_part)
	var desc_segs := _segments(desc)
	var kw := _segs_width(font, key_segs)
	var dw := _segs_width(font, desc_segs)
	var w := 20.0 + dw + (kw + 12.0 + 7.0 if kw > 0 else 0.0)
	var r := Rect2(pos.x - (w / 2 if centered else w), pos.y, w, H)
	Draw.panel(ci, r, Color(BG, BG.a * alpha), H / 2, Color(BORDER, BORDER.a * alpha), 1.5)
	var x := r.position.x + 10.0
	var base := r.position.y + H / 2 + SIZE * 0.36 - (1.5 if k >= 0.0 else 0.0)
	if kw > 0:
		var cap := Rect2(r.position.x + 4, r.position.y + 4, kw + 12.0, H - 8.0 - (2.0 if k >= 0.0 else 0.0))
		Draw.panel(ci, cap, Color(CAP, alpha), 6)
		_draw_segs(ci, font, key_segs, Vector2(cap.position.x + 6, base), Color(CAP_TEXT, alpha), alpha)
		x = cap.end.x + 7.0
	_draw_segs(ci, font, desc_segs, Vector2(x, base), Color(INK, alpha), alpha)
	if k >= 0.0:
		var bw := (r.size.x - H) * clampf(k, 0, 1)
		if bw > 0.5:
			ci.draw_line(Vector2(r.position.x + H / 2, r.end.y - 3), Vector2(r.position.x + H / 2 + bw, r.end.y - 3), Color(BAR, alpha), 2.0, true)
	return w


## Text split into strings and gamepad glyphs ({icon: path}).
static func _segments(s: String) -> Array:
	var out: Array = []
	var cur := ""
	var glyphs: Array = Text._ICONS.keys()
	glyphs.sort_custom(func(p, q): return String(p).length() > String(q).length())
	var i := 0
	while i < s.length():
		var hit := ""
		for g in glyphs:
			if s.substr(i, String(g).length()) == g:
				hit = g
				break
		if hit != "":
			if cur != "":
				out.append(cur)
				cur = ""
			out.append({"icon": Text._ICONS[hit]})
			i += hit.length()
		else:
			cur += s[i]
			i += 1
	if cur != "":
		out.append(cur)
	return out


static func _segs_width(font: Font, segs: Array) -> float:
	var w := 0.0
	for s in segs:
		if s is String:
			w += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		else:
			w += SIZE + 4.0
	return w


static func _draw_segs(ci: CanvasItem, font: Font, segs: Array, pos: Vector2, col: Color, alpha: float) -> void:
	var x := pos.x
	for s in segs:
		if s is String:
			ci.draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, col)
			x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		else:
			var tex: Texture2D = load(str(s.icon))
			var sz := float(SIZE + 3)
			ci.draw_texture_rect(tex, Rect2(x + 0.5, pos.y - SIZE * 0.36 - sz / 2, sz, sz), false, Color(1, 1, 1, alpha))
			x += SIZE + 4.0
