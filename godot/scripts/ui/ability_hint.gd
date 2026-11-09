class_name AbilityHints
extends RefCounted
## One way to announce abilities in every level: right-aligned lines directly under the
## top-right indicator (the cave's breath pill, the runner's water pill, the climb's heart
## meter, the maze's breath pill), one per ability that can be used right now.
##
## The caller passes the wanted lines every frame to `update()` (an i18n key, or
## {key, k} with k = 0..1 for a draining time bar) and draws them with `draw()`.
## Lines fade in / out (FADE s). Text: `Text.t(key)` (filtered by the control mode) in
## one format, e.g. `[SHIFT] to *focus*`, `[↑] + [↑] to *double jump*`:
## `[…]` = a key cap (a tinted rounded square, white label; gamepad glyphs 🔴 🟡 ⬆ …
## drawn as their images inside it), `*…*` = the action in yellow, the rest (" to ",
## " + ") plain light text. Everything has a dark outline so it reads on any background.
## `parse()` splits a line into these segments (tests).

const FADE := 0.2
const SIZE := 15
const H := 25.0
const GAP := 6.0
const CAP_H := 22.0
const CAP_SIZE := 13
const CAP := Color("#0f3d3a", 0.82)
const CAP_RIM := Color("#7dd3c0", 0.55)
const CAP_SHADE := Color(0, 0, 0, 0.55)
const CAP_TEXT := Color("#ffffff")
const ACTION := Color("#fbbf24")
const TEXT := Color("#f8f5ee")
const OUTLINE := Color("#1a1022", 0.85)
const OUTLINE_W := 6
const SHADOW := Color("#140a1c", 0.22)
const BAR := Color("#fbbf24")

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
	var y := anchor.y + 7.0
	for key in _order:
		if not _lines.has(key):
			continue
		var l: Dictionary = _lines[key]
		var a: float = l.a
		if a <= 0.0:
			continue
		var e := a * a * (3.0 - 2.0 * a)
		draw_hint(ci, Text.t(key), Vector2(anchor.x, y - (1.0 - e) * 6.0), e, float(l.k), centered)
		y += (H + GAP + (5.0 if float(l.k) >= 0.0 else 0.0)) * e


## A line split into segments: {cap: label} (a key cap; `icon` = a gamepad glyph image),
## {action: text} (yellow), {text: text} (plain). Malformed mark-up stays plain text.
static func parse(s: String) -> Array:
	var out: Array = []
	var cur := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		var close := ""
		if c == "[":
			close = "]"
		elif c == "*":
			close = "*"
		var end := s.find(close, i + 1) if close != "" else -1
		if end > i + 1:
			if cur != "":
				out.append({"text": cur})
				cur = ""
			var inner := s.substr(i + 1, end - i - 1)
			if close == "]":
				var seg := {"cap": inner}
				var g := inner.strip_edges()
				if Text._ICONS.has(g):
					seg["icon"] = Text._ICONS[g]
				out.append(seg)
			else:
				out.append({"action": inner})
			i = end + 1
		else:
			cur += c
			i += 1
	if cur != "":
		out.append({"text": cur})
	return out


static func _seg_width(font: Font, seg: Dictionary) -> float:
	if seg.has("cap"):
		if seg.has("icon"):
			return CAP_H
		var tw := font.get_string_size(str(seg.cap), HORIZONTAL_ALIGNMENT_LEFT, -1, CAP_SIZE).x
		return maxf(CAP_H, tw + 12.0)
	var s: String = str(seg.get("action", seg.get("text", "")))
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x


## The width of a line as drawn.
static func line_width(text: String) -> float:
	var font: Font = Text.font_bold
	var w := 0.0
	for seg in parse(text):
		w += _seg_width(font, seg)
	return w


## One line; returns its width. `pos` = its top-right corner (top-centre if `centered`).
static func draw_hint(ci: CanvasItem, text: String, pos: Vector2, alpha: float, k := -1.0, centered := false) -> float:
	var font: Font = Text.font_bold
	var segs := parse(text)
	var w := 0.0
	for seg in segs:
		w += _seg_width(font, seg)
	var x := pos.x - (w / 2 if centered else w)
	var mid := pos.y + H / 2
	var base := mid + SIZE * 0.36
	var ol := Color(OUTLINE, OUTLINE.a * alpha)
	# A soft dark shadow behind the line (two feathered layers), so it reads over
	# platforms, trees and the casino lights without a pill of its own.
	var back := Rect2(x - 6.0, pos.y + 1.0, w + 12.0, H - 2.0)
	Draw.panel(ci, back.grow(4.0), Color(SHADOW, SHADOW.a * 0.5 * alpha), (H + 6.0) / 2)
	Draw.panel(ci, back, Color(SHADOW, SHADOW.a * alpha), (H - 2.0) / 2)
	for seg in segs:
		var sw := _seg_width(font, seg)
		if seg.has("cap"):
			var r := Rect2(x, mid - CAP_H / 2, sw, CAP_H)
			# A raised key: a dark shade under it, the tinted top with a light rim.
			Draw.panel(ci, Rect2(r.position + Vector2(0, 2), r.size), Color(CAP_SHADE, CAP_SHADE.a * alpha), 5)
			Draw.panel(ci, r, Color(CAP, CAP.a * alpha), 5, Color(CAP_RIM, CAP_RIM.a * alpha), 1)
			if seg.has("icon"):
				var tex: Texture2D = load(str(seg.icon))
				var sz := CAP_H - 5.0
				ci.draw_texture_rect(tex, Rect2(r.get_center() - Vector2(sz, sz) / 2, Vector2(sz, sz)), false, Color(1, 1, 1, alpha))
			else:
				var label: String = str(seg.cap)
				var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, CAP_SIZE).x
				ci.draw_string(font, Vector2(r.get_center().x - tw / 2, mid + CAP_SIZE * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, CAP_SIZE, Color(CAP_TEXT, alpha))
		else:
			var s: String = str(seg.get("action", seg.get("text", "")))
			var col: Color = ACTION if seg.has("action") else TEXT
			ci.draw_string_outline(font, Vector2(x, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, OUTLINE_W, ol)
			ci.draw_string(font, Vector2(x, base), s, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(col, alpha))
		x += sw
	if k >= 0.0:
		# The time left: a thin yellow bar under the line, draining from the left.
		var x0 := pos.x - (w / 2 if centered else w)
		var by := pos.y + H + 2.0
		ci.draw_line(Vector2(x0, by), Vector2(x0 + w, by), Color(OUTLINE, 0.5 * alpha), 4.0, true)
		var bw := w * clampf(k, 0, 1)
		if bw > 0.5:
			ci.draw_line(Vector2(x0 + w - bw, by), Vector2(x0 + w, by), Color(BAR, alpha), 2.0, true)
	return w
