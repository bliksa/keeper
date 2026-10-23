class_name CreditsPanel
extends Control
## Credits overlay (port of the web `w2`). Click outside or press a button to close.

const CREDITS := [
	["CREDIT_IDEA", ["Nataša Juračková"]],
	["CREDIT_CODE", ["Michal Kabát & Klaara"]],
	["CREDIT_VISUALS", ["Alexandra Pavelová", "Alexandra Just", "Barbora Grellová", "Hana Filipovičová", "Emma Čičáková"]],
	["CREDIT_SOUND", ["Tomáš Farkaš"]],
	["CREDIT_VOICES", ["Aďa Farkašová", "Alicka Farkašová"]],
]


func _ready() -> void:
	size = Vector2(1066, 600)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f172a")
	sb.border_color = Color("#10b981", 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(24)
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(183, 60)
	card.size = Vector2(700, 480)
	add_child(card)
	var cols := [Vector2(48, 48), Vector2(380, 48)]
	var y := [cols[0].y, cols[1].y]
	var layout := [0, 1, 0, 1, 1]
	for i in CREDITS.size():
		var col: int = layout[i]
		var head := UiKit.label(Text.t(CREDITS[i][0]).to_upper(), 18, Color("#34d399"), true)
		head.position = Vector2(cols[col].x, y[col])
		card.add_child(head)
		y[col] += 32
		for n in CREDITS[i][1]:
			var l := UiKit.label(n, 16)
			l.position = Vector2(cols[col].x, y[col])
			card.add_child(l)
			y[col] += 26
		y[col] += 28
	var close := UiKit.button("X", Vector2(40, 40), 18, Color(0, 0, 0, 0), Color("#94a3b8"))
	close.position = Vector2(700 - 56, 16)
	close.pressed.connect(queue_free)
	card.add_child(close)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		queue_free()
