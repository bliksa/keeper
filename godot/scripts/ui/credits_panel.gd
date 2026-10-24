class_name CreditsPanel
extends Control
## Credits overlay (port of the web `w2`). Click outside or press a button to close.
##
## Both columns sit on one line grid (every heading, name and gap is LINE
## pixels tall), so their rows line up, and the card is sized to the text.

## Sections per column; each column must add up to the same number of lines.
const LEFT := [
	["CREDIT_IDEA", ["Nataša Juračková"]],
	["CREDIT_VISUALS", ["Alexandra Pavelová", "Alexandra Just", "Barbora Grellová", "Hana Filipovičová", "Emma Čičáková"]],
]
const RIGHT := [
	["CREDIT_CODE", ["Michal Kabát & Klaara"]],
	["CREDIT_SOUND", ["Tomáš Farkaš"]],
	["CREDIT_VOICES", ["Aďa Farkašová", "Alicka Farkašová"]],
]

const LINE := 30.0
const PAD := Vector2(64, 52)
const COL_GAP := 80.0
const HEAD_SIZE := 15
const NAME_SIZE := 17
const CLOSE_SIZE := 32.0
const CLOSE_INSET := 18.0


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var cols := [_lines(LEFT), _lines(RIGHT)]
	var widths := [_width(cols[0]), _width(cols[1])]
	var rows := maxi(cols[0].size(), cols[1].size())
	var card_size := Vector2(widths[0] + COL_GAP + widths[1], rows * LINE) + PAD * 2
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#10b981", 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(24)
	card.add_theme_stylebox_override("panel", sb)
	card.size = card_size
	card.position = ((size - card_size) / 2).round()
	add_child(card)

	var x := PAD.x
	for c in 2:
		for i in cols[c].size():
			var line: Array = cols[c][i]
			if line[0] == "":
				continue
			var l := UiKit.label(line[0], HEAD_SIZE if line[1] else NAME_SIZE, Color("#34d399") if line[1] else Color.WHITE, line[1])
			l.position = Vector2(x, PAD.y + i * LINE)
			l.size = Vector2(widths[c], LINE)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			card.add_child(l)
		x += widths[c] + COL_GAP

	var close := Button.new()
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	close.position = Vector2(card_size.x - CLOSE_INSET - CLOSE_SIZE, CLOSE_INSET)
	close.draw.connect(_draw_close.bind(close))
	close.mouse_entered.connect(close.queue_redraw)
	close.mouse_exited.connect(close.queue_redraw)
	close.pressed.connect(queue_free)
	card.add_child(close)


## Flatten sections into grid lines: [text, is_heading]; one empty line between sections.
func _lines(sections: Array) -> Array:
	var out := []
	for i in sections.size():
		if i > 0:
			out.append(["", false])
		out.append([Text.t(sections[i][0]).to_upper(), true])
		for n in sections[i][1]:
			out.append([n, false])
	return out


func _width(lines: Array) -> float:
	var w := 0.0
	for line in lines:
		var f: Font = Text.font_bold if line[1] else Text.font
		w = maxf(w, f.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, HEAD_SIZE if line[1] else NAME_SIZE).x)
	return ceilf(w)


## A thin X: two strokes inside the button, brighter on hover.
func _draw_close(b: Button) -> void:
	var col := Color("#e2e8f0") if b.is_hovered() else Color("#64748b")
	var m := 10.0
	var s := b.size
	b.draw_line(Vector2(m, m), s - Vector2(m, m), col, 2.0, true)
	b.draw_line(Vector2(s.x - m, m), Vector2(m, s.y - m), col, 2.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		queue_free()
