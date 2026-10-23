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

const COLS := 25
const ROW_H := 120.0
const CELL_W := 1066.0 / COLS

const PALETTE := {
	"=": "Platform", "O": "Iron", "^": "Spike", "P": "Spawn",
	"S": "Cramp static", "F": "Cramp floating", "J": "Cramp lunging", "C": "Cramp chasing",
	"2": "Minigame: chocolate", "3": "Minigame: pipes", "4": "Minigame: prices", "5": "Boss",
	"T": "Teleport to top", "I": "Hint text",
}


class Plat:
	var x: float
	var y: float
	var w: float
	var h := 20.0
	var base_y: float


class Ent:
	var id: int
	var type: String # iron | spike | enemy | trigger | text
	var x: float
	var y: float
	var w: float
	var h: float
	var trigger_type := "" # dialog | first_cramp | teleport | mg2 | mg3 | mg4 | end
	var dialog_id := ""
	var target := Vector2.ZERO
	var text := ""
	var behavior := "" # static | float | lunge | chase
	var lunge_timer := 0.0
	var base_x := 0.0
	var base_y := 0.0
	var has_base := false
	var vx := 0.0
	var vy := 0.0
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


func height() -> float:
	return rows.size() * row_h


func has_spawn() -> bool:
	return spawn.x >= 0


static func build(level_rows: PackedStringArray, rh := ROW_H) -> LevelData:
	var L := LevelData.new()
	L.rows = level_rows
	L.row_h = rh
	var next_id := 0
	for r in level_rows.size():
		var row := level_rows[r]
		var y := r * rh
		var start := -1.0
		for c in range(row.length() + 1):
			var ch := row[c] if c < row.length() else " "
			var x := c * CELL_W
			if ch == "=":
				if start < 0: start = x
				continue
			if start >= 0:
				var p := Plat.new()
				p.x = start
				p.y = y
				p.w = x - start
				p.base_y = y
				L.platforms.append(p)
				start = -1
			var e: Ent = null
			match ch:
				"O", "*":
					e = _ent("iron", x + CELL_W / 2 - 12, y + rh - 45, 24, 24)
				"^":
					e = _ent("spike", x + CELL_W / 2 - 15, y + rh - 30, 30, 30)
				"X":
					e = _ent("trigger", x, y, CELL_W, rh)
					e.trigger_type = "first_cramp"
				"S", "F", "L", "J", "C":
					e = _ent("enemy", x + CELL_W / 2 - 20, y + rh - 45, 40, 40)
					e.behavior = {"S": "static", "F": "float", "L": "lunge", "J": "lunge", "C": "chase"}[ch]
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
				"1", "2", "3", "4", "5", "B":
					e = _ent("trigger", 0, y - 100, 1066, 200)
					e.trigger_type = {"1": "mg1", "2": "mg2", "3": "mg3", "4": "mg4", "5": "end", "B": "end"}[ch]
				_:
					if ch >= "a" and ch <= "z":
						e = _ent("trigger", x, y, CELL_W, rh)
						e.trigger_type = "dialog"
						e.dialog_id = ch
			if e:
				e.id = next_id
				next_id += 1
				L.entities.append(e)
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
static func parse_text(txt: String) -> PackedStringArray:
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
			if line.begins_with("#"):
				continue
			out.append(line)
		while out.size() > 0 and out[out.size() - 1].strip_edges() == "":
			out.remove_at(out.size() - 1)
	for i in out.size():
		var row := out[i].replace(".", " ")
		if row.length() < COLS:
			row = row + " ".repeat(COLS - row.length())
		out[i] = row.substr(0, COLS)
	return out


static func to_text(level_rows: PackedStringArray) -> String:
	var lines := PackedStringArray()
	for r in level_rows:
		lines.append(r.replace(" ", "."))
	return "\n".join(lines) + "\n"
