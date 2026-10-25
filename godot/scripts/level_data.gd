class_name LevelData
extends RefCounted
## Turns the text level (data/levels/*.txt) into platforms and entities.
##
## Each text row is one band of ROW_H pixels; each column is 1066/25 px wide.
## Legend (same as the web prototype):
##   =      platform (consecutive '=' merge into one platform)
##   O *    iron (collectible / health)
##   ^      spike (hurts, costs 3–5 iron)
##   S F J C  cramp enemy: S static, F floating, J (or L) lunging, C chasing
##   P      player spawn
##   2 3 4  minigame trigger (2 chocolate puzzle, 3 pipes, 4 prices) — spans the whole row
##   5 B    boss fight trigger — spans the whole row
##   a…z    dialog trigger (letters mapped in data/dialogs.json → "letter_dialogs")
##   X      "first cramp" dialog trigger (uppercase)
##   T      teleport to the top of the level
##   I      on-screen hint text (double jump)
##   . or space   empty
## Level 2 (the meadow, horizontal: left → right, 10 rows of 60 px) adds:
##   #      river (the rows of water at the bottom; falling in carries you back)
##   Y      light seed (a follicle; caught with the focus thread, not by touch)
##   K M Q  minigame trigger (K memory, M catch, Q pairs) — spans the whole column
##   G      the gate / level end — spans the whole column
##   (O is a water drop here, N a notification, ^ a thorn)
## Level 3 (the summit, climbed upwards) adds:
##   @      bubble platform (a follicle; inflates when the player is near)
##   %      popping bubble (bursts shortly after you stand on it, regrows later)
##   ~      updraft (a column of warm air that lifts the player)
##   N      distraction (floating "notification": slows the player on touch)
##   6 7 8  minigame trigger (6 iron plate, 7 rhythm, 8 body signals) — whole row
##   9      the LH wave starts rising — whole row
##   E      summit / level end — whole row

const COLS := 25
const ROW_H := 120.0
const CELL_W := 1066.0 / COLS
## Horizontal levels: square-ish cells, 10 rows = one screen.
const ROW_H_H := 60.0

const PALETTE := {
	"=": "Platform", "O": "Iron", "^": "Spike", "P": "Spawn",
	"S": "Cramp static", "F": "Cramp floating", "J": "Cramp lunging", "C": "Cramp chasing",
	"2": "Minigame: chocolate", "3": "Minigame: pipes", "4": "Minigame: prices", "5": "Boss",
	"T": "Teleport to top", "I": "Hint text",
	"@": "Bubble platform", "%": "Popping bubble", "~": "Updraft", "N": "Distraction",
	"6": "Minigame: iron plate", "7": "Minigame: rhythm", "8": "Minigame: body signals",
	"9": "LH wave", "E": "Summit",
	"#": "River", "Y": "Light seed", "K": "Minigame: memory", "M": "Minigame: catch", "Q": "Minigame: pairs", "G": "Gate",
}

## Trigger kinds that mark progress, in level order (checkpoints 2..5).
const PROGRESS := {1: ["mg2", "mg3", "mg4", "end"], 2: ["mg8", "mg9", "mg10", "gate"], 3: ["mg5", "mg6", "mg7", "wave"]}


class Plat:
	var x: float
	var y: float
	var w: float
	var h := 20.0
	var base_y: float
	## "rock" (cave), "bubble" (stable follicle) or "pop" (bursts when stood on).
	var kind := "rock"
	## Popping bubbles: time stood on (> POP_AFTER bursts it) and regrow timer.
	var pop_timer := 0.0
	var regrow := 0.0

	func solid() -> bool:
		return regrow <= 0


class Ent:
	var id: int
	var type: String # iron | spike | enemy | trigger | text
	var x: float
	var y: float
	var w: float
	var h: float
	var trigger_type := "" # dialog | first_cramp | teleport | mg2..mg10 | end | wave | summit | gate
	var dialog_id := ""
	var target := Vector2.ZERO
	var text := ""
	var behavior := "" # static | float | lunge | chase | distract
	var lunge_timer := 0.0
	var base_x := 0.0
	var base_y := 0.0
	var has_base := false
	var vx := 0.0
	var vy := 0.0
	## Seeds: 0 still, 1 blinking, 2 drifting, 3 dodging; blink phase; visible flag.
	var tier := 0
	var visible := true
	var collected := false
	var defeated := false
	var knocked_back := false

	func rect() -> Rect2:
		return Rect2(x, y, w, h)


var platforms: Array[Plat] = []
var entities: Array[Ent] = []
var spawn := Vector2(-1, -1)
var rows := PackedStringArray()
var row_h := ROW_H
## Horizontal level (left → right): long rows, fixed height.
var horizontal := false
var cols := COLS
## Top of the river (horizontal levels), -1 = none.
var water_top := -1.0


func height() -> float:
	return rows.size() * row_h


func width() -> float:
	return cols * CELL_W


func has_spawn() -> bool:
	return spawn.x >= 0


static func build(level_rows: PackedStringArray, rh := ROW_H, horizontal := false) -> LevelData:
	var L := LevelData.new()
	L.rows = level_rows
	L.horizontal = horizontal
	if horizontal:
		rh = ROW_H_H
		L.cols = 0
		for row in level_rows:
			L.cols = maxi(L.cols, row.length())
	L.row_h = rh
	var next_id := 0
	var seeds: Array[Ent] = []
	for r in level_rows.size():
		var row := level_rows[r]
		var y := r * rh
		var start := -1.0
		var kind := ""
		for c in range(row.length() + 1):
			var ch := row[c] if c < row.length() else " "
			var x := c * CELL_W
			var k: String = {"=": "rock", "@": "bubble", "%": "pop"}.get(ch, "")
			if k != "" and (start < 0 or k == kind):
				if start < 0:
					start = x
					kind = k
				continue
			if start >= 0:
				var p := Plat.new()
				p.x = start
				p.y = y
				p.w = x - start
				p.base_y = y
				p.kind = kind
				L.platforms.append(p)
				start = -1
				if k != "":
					start = x
					kind = k
					continue
			var e: Ent = null
			match ch:
				"O", "*":
					e = _ent("iron", x + CELL_W / 2 - 12, y + rh - 45, 24, 24)
				"^":
					e = _ent("spike", x + CELL_W / 2 - 15, y + rh - 30, 30, 30)
				"X":
					e = _ent("trigger", x, y, CELL_W, rh)
					e.trigger_type = "first_cramp"
				"S", "F", "L", "J", "C", "N":
					e = _ent("enemy", x + CELL_W / 2 - 20, y + rh - 45, 40, 40)
					e.behavior = {"S": "static", "F": "float", "L": "lunge", "J": "lunge", "C": "chase", "N": "distract"}[ch]
					if e.behavior == "lunge":
						e.lunge_timer = randf() * 2
				"T":
					e = _ent("trigger", x, y, CELL_W, rh)
					e.trigger_type = "teleport"
					e.target = Vector2(50, 100)
				"I":
					e = _ent("text", x, y, CELL_W, rh)
					e.text = "HINT_DOUBLE_JUMP"
				"P":
					L.spawn = Vector2(x + 5, y - 60)
				"~":
					e = _ent("updraft", x, y, CELL_W, rh)
				"#":
					if L.water_top < 0 or y < L.water_top:
						L.water_top = y
				"Y":
					e = _ent("seed", x + CELL_W / 2 - 14, y + rh / 2 - 14, 28, 28)
					seeds.append(e)
				"1", "2", "3", "4", "5", "B", "6", "7", "8", "9", "E", "K", "M", "Q", "G":
					var tkind: String = {"1": "mg1", "2": "mg2", "3": "mg3", "4": "mg4", "5": "end", "B": "end",
						"6": "mg5", "7": "mg6", "8": "mg7", "9": "wave", "E": "summit",
						"K": "mg8", "M": "mg9", "Q": "mg10", "G": "gate"}[ch]
					if horizontal:
						# Spans the whole column.
						e = _ent("trigger", x - 40, 0, CELL_W + 80, level_rows.size() * rh)
					else:
						e = _ent("trigger", 0, y - 100, 1066, 200)
					e.trigger_type = tkind
				_:
					if ch >= "a" and ch <= "z":
						e = _ent("trigger", x, y, CELL_W, rh)
						e.trigger_type = "dialog"
						e.dialog_id = ch
			if e:
				e.id = next_id
				next_id += 1
				L.entities.append(e)
	# Seeds get harder from left to right: still → blinking → drifting → dodging.
	seeds.sort_custom(func(a, b): return a.x < b.x)
	for i in seeds.size():
		seeds[i].tier = mini(3, i * 4 / maxi(1, seeds.size()))
		seeds[i].base_x = seeds[i].x
		seeds[i].base_y = seeds[i].y
		seeds[i].has_base = true
	return L


static func _ent(type: String, x: float, y: float, w: float, h: float) -> Ent:
	var e := Ent.new()
	e.type = type
	e.x = x
	e.y = y
	e.w = w
	e.h = h
	return e


## Parse level text: one row per line, or a JSON array of strings (web editor export).
## cols: pad / cut every row to this width; -1 = the longest row (horizontal levels).
static func parse_text(txt: String, cols := COLS) -> PackedStringArray:
	var out := PackedStringArray()
	var s := txt.strip_edges()
	if s.begins_with("[") or s.contains("export const"):
		var re := RegEx.new()
		re.compile("\"([^\"]*)\"")
		for m in re.search_all(s):
			out.append(m.get_string(1))
	else:
		for line in txt.split("\n"):
			line = line.replace("\r", "")
			# Comments: "# …" or "//"; a row of river water ("###…") is level data.
			if line.begins_with("# ") or line.begins_with("//"):
				continue
			out.append(line)
		while out.size() > 0 and out[out.size() - 1].strip_edges() == "":
			out.remove_at(out.size() - 1)
	if cols < 0:
		cols = 0
		for row in out:
			cols = maxi(cols, row.length())
	for i in out.size():
		var row := out[i].replace(".", " ")
		if row.length() < cols:
			row = row + " ".repeat(cols - row.length())
		out[i] = row.substr(0, cols)
	return out


static func to_text(level_rows: PackedStringArray) -> String:
	var lines := PackedStringArray()
	for r in level_rows:
		lines.append(r.replace(" ", "."))
	return "\n".join(lines) + "\n"
