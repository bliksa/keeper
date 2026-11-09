class_name SpriteArt
extends RefCounted
## Art for everything that isn't Kyra: collectibles, enemies and NPCs.
##
## Most of them are drawn in code (placeholders). The animation lab can give any
## of them a frame list (variant); the game then draws those frames instead.
## Variants share data/anim_variants.json with the player animations
## ("anims" / "in_game"); per-sprite scale and fps live in "sprites".
##
## Ids must not clash with PlayerArt.ANIMS (the test checks this).

const VARIANTS := "res://data/anim_variants.json"
const IMG := "res://assets/images/"

const CATEGORIES := {
	"collectibles": "Collectibles",
	"enemies": "Enemies",
	"npcs": "NPCs",
}

## id -> {cat, label, size (on-screen height in px at scale 1), fps, frames (original
## files; empty = drawn in code), where (shown in the lab)}
const DEFS := {
	"iron": {"cat": "collectibles", "label": "Iron nut", "size": 28.0, "fps": 8.0, "frames": [],
		"where": "Cave + boss arena (O in the level)"},
	"drop": {"cat": "collectibles", "label": "Water drop", "size": 26.0, "fps": 8.0, "frames": [],
		"where": "Forest run + meadow"},
	"seed": {"cat": "collectibles", "label": "Light seed", "size": 30.0, "fps": 8.0, "frames": [],
		"where": "Meadow (old level 2)"},
	"sun_piece": {"cat": "collectibles", "label": "Sun piece", "size": 40.0, "fps": 8.0, "frames": [],
		"where": "Forest run (12 fill the sun)"},
	"heart": {"cat": "collectibles", "label": "Heart", "size": 28.0, "fps": 8.0, "frames": [],
		"where": "Jackpot climb ($ in the level: fills the heart meter)"},
	"bell": {"cat": "collectibles", "label": "Bell", "size": 34.0, "fps": 8.0, "frames": [],
		"where": "Jackpot climb (: in the level: +1 heart)"},
	"joker": {"cat": "collectibles", "label": "Joker", "size": 46.0, "fps": 8.0, "frames": [],
		"where": "Jackpot climb (? in the level: spins the reels)"},
	"cramp": {"cat": "enemies", "label": "Cramp", "size": 52.0, "fps": 10.0, "frames": [],
		"where": "Cave (S / F / J / C in the level)"},
	"spike": {"cat": "enemies", "label": "Spike cramp", "size": 44.0, "fps": 10.0, "frames": [],
		"where": "Cave (^ in the level)"},
	"boss": {"cat": "enemies", "label": "Big Cramp (boss)", "size": 170.0, "fps": 10.0, "frames": [],
		"where": "Boss arena"},
	"bird": {"cat": "enemies", "label": "Flying notification", "size": 60.0, "fps": 10.0, "frames": [],
		"where": "Forest run (grabs her mid-jump)"},
	"vine": {"cat": "enemies", "label": "Side trap (vine)", "size": 50.0, "fps": 8.0, "frames": [],
		"where": "Forest run (lashes in from the side)"},
	"distraction": {"cat": "enemies", "label": "Notification", "size": 40.0, "fps": 8.0, "frames": [],
		"where": "Summit + meadow (N in the level)"},
	"thorn": {"cat": "enemies", "label": "Thorns", "size": 30.0, "fps": 8.0, "frames": [],
		"where": "Summit (^ in the level)"},
	"shadow": {"cat": "enemies", "label": "Shadow", "size": 46.0, "fps": 10.0, "frames": [],
		"where": "Meadow (old level 2)"},
	"estra": {"cat": "npcs", "label": "Estra (ghost)", "size": 120.0, "fps": 6.67,
		"frames": ["duch1", "duch2", "duch3", "duch4", "duch5", "duch6"], "where": "Forest intro"},
	"portrait_estra": {"cat": "npcs", "label": "Estra – dialog portrait", "size": 118.0, "fps": 6.0,
		"frames": ["dia1"], "where": "Dialog box"},
	"portrait_kyra": {"cat": "npcs", "label": "Kyra – dialog portrait", "size": 118.0, "fps": 6.0,
		"frames": ["dia2"], "where": "Dialog box"},
	"portrait_iskra": {"cat": "npcs", "label": "Iskra – dialog portrait", "size": 118.0, "fps": 6.0,
		"frames": [], "where": "Dialog box (level 2)"},
}

## Frame overrides: id -> Array[Texture2D] (from "in_game" or the lab).
static var overrides := {}
## Per-sprite settings: id -> {"scale": float, "fps": float}.
static var settings := {}

## Dialog avatars of characters added in the dialog editor (not in DEFS):
## id -> a DEFS-like entry. Rebuilt from Text.characters by sync_characters().
static var extra := {}
static var _orig := {}
static var _iskra: ImageTexture


## The entry of a sprite (DEFS or a character's avatar).
static func def(id: String) -> Dictionary:
	if DEFS.has(id):
		return DEFS[id]
	return extra.get(id, {})


## Every character in Text.characters gets a dialog-avatar sprite.
static func sync_characters() -> void:
	extra = {}
	for cid in Text.characters:
		var pid := Text.portrait_of(cid)
		if not DEFS.has(pid):
			extra[pid] = {"cat": "npcs", "label": "%s – dialog portrait" % Text.speaker_name(cid), "size": 118.0,
				"fps": 6.0, "frames": [], "where": "Dialog box (one frame = a static avatar)"}


static func ids_in(cat: String) -> Array:
	var out := []
	for id in DEFS:
		if DEFS[id].cat == cat:
			out.append(id)
	if cat == "npcs":
		out.append_array(extra.keys())
	return out


static func is_sprite(id: String) -> bool:
	return DEFS.has(id) or extra.has(id)


static func label(id: String) -> String:
	return str(def(id).get("label", id))


## Original frame files (empty = the code-drawn placeholder).
static func original_paths(id: String) -> Array:
	var out := []
	for f in def(id).get("frames", []):
		out.append(IMG + str(f) + ".png")
	return out


static func code_drawn(id: String) -> bool:
	return original_paths(id).is_empty()


static func scale_of(id: String) -> float:
	return float(settings.get(id, {}).get("scale", 1.0))


static func fps_of(id: String) -> float:
	return float(settings.get(id, {}).get("fps", def(id).get("fps", 8.0)))


static func set_setting(id: String, key: String, v: float) -> void:
	settings.get_or_add(id, {})[key] = v


## Frames the game draws right now (override, else the original files; empty =
## code-drawn).
static func frames(id: String) -> Array:
	if overrides.has(id) and not (overrides[id] as Array).is_empty():
		return overrides[id]
	if not _orig.has(id):
		var arr := []
		for path in original_paths(id):
			arr.append(load(path))
		_orig[id] = arr
	return _orig[id]


## True when the lab / manifest replaced the art of `id`.
static func has_art(id: String) -> bool:
	return overrides.has(id) and not (overrides[id] as Array).is_empty()


static func frame_index(id: String, time_ms: float, n: int) -> int:
	return int(floorf(time_ms / 1000.0 * fps_of(id))) % maxi(1, n)


## Current frame of `id` (null = drawn in code).
static func texture(id: String, time_ms: float) -> Texture2D:
	var f := frames(id)
	if f.is_empty():
		return null
	return f[frame_index(id, time_ms, f.size())]


## Draws the frames of `id` centred on `c`, `h` px tall (times the sprite's
## scale). Returns false when there are no frames: the caller draws its
## placeholder. Code-drawn sprites only use frames once the lab gave them some.
static func draw(ci: CanvasItem, id: String, c: Vector2, h: float, time_ms: float, mod := Color.WHITE, flip := false, frame := -1) -> bool:
	var f := frames(id)
	if f.is_empty():
		return false
	var t: Texture2D = f[frame % f.size()] if frame >= 0 else f[frame_index(id, time_ms, f.size())]
	if t == null or t.get_height() == 0:
		return false
	h *= scale_of(id)
	var w := t.get_width() * h / t.get_height()
	# No draw_set_transform: it would replace the caller's (camera) transform.
	var src := Rect2(0, 0, t.get_width(), t.get_height())
	if flip:
		src = Rect2(t.get_width(), 0, -t.get_width(), t.get_height())
	ci.draw_texture_rect_region(t, Rect2(c.x - w / 2, c.y - h / 2, w, h), src, mod)
	return true


## Applies "in_game" variants and "sprites" settings from the manifest.
static func load_game_defaults() -> void:
	overrides = {}
	settings = {}
	if not FileAccess.file_exists(VARIANTS):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(VARIANTS))
	if not d is Dictionary:
		return
	var anims: Dictionary = d.get("anims", {})
	var in_game: Dictionary = d.get("in_game", {})
	sync_characters()
	for id in in_game:
		if not is_sprite(id):
			continue
		var tex := []
		for path in anims.get(id, {}).get(in_game[id], []):
			if ResourceLoader.exists(path):
				tex.append(load(path))
		if not tex.is_empty():
			overrides[id] = tex
	var s: Variant = d.get("sprites", {})
	if s is Dictionary:
		for id in s:
			if is_sprite(id) and s[id] is Dictionary:
				settings[id] = {"scale": float(s[id].get("scale", 1.0)), "fps": float(s[id].get("fps", def(id).get("fps", 8.0)))}


# --- portraits ------------------------------------------------------------------------

## Dialog portrait of a speaker (frame at `time_ms`): the lab's frames, the
## original art, Iskra's code-drawn sparkle, or a plain avatar for a new character.
static func portrait(speaker: String, time_ms := 0.0) -> Texture2D:
	var id := Text.portrait_of(speaker)
	var t := texture(id, time_ms)
	if t:
		return t
	if id == "portrait_iskra":
		return iskra_texture()
	return blank_portrait(id)


## True when a speaker's portrait has more than one frame (the dialog animates it).
static func portrait_animated(speaker: String) -> bool:
	return frames(Text.portrait_of(speaker)).size() > 1


static var _blank := {}

## A soft disc in a colour of its own: the avatar of a character without art yet.
static func blank_portrait(id: String) -> Texture2D:
	if not _blank.has(id):
		var col := Color.from_hsv(float(hash(id) % 360) / 360.0, 0.35, 0.85)
		var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		img.fill(Color("#2b4150"))
		for y in 96:
			for x in 96:
				var d := Vector2(x, y).distance_to(Vector2(48, 44))
				if d < 26:
					img.set_pixel(x, y, col)
				elif Vector2(x, y).distance_to(Vector2(48, 112)) < 46:
					img.set_pixel(x, y, col.darkened(0.15))
		_blank[id] = ImageTexture.create_from_image(img)
	return _blank[id]


## Iskra (FSH) is a sparkle drawn in code.
static func iskra_texture() -> Texture2D:
	if _iskra == null:
		var img := Image.create(160, 160, false, Image.FORMAT_RGBA8)
		img.fill(Color("#1a2a3a"))
		var c := Vector2(80, 86)
		for y in 160:
			for x in 160:
				var d := Vector2(x, y).distance_to(c)
				var ray := absf(sin(atan2(y - c.y, x - c.x) * 4.0))
				var glow := clampf(1.0 - d / 70.0, 0, 1)
				var a := clampf(glow * glow * (0.35 + 0.65 * ray) + clampf(1.0 - d / 22.0, 0, 1), 0, 1)
				if a > 0.02:
					var col := Color("#ffd166").lerp(Color("#fff7d6"), clampf(1.0 - d / 24.0, 0, 1))
					img.set_pixel(x, y, Color("#1a2a3a").lerp(col, a))
		for i in 26:
			var px := int(20 + fmod(i * 61.0, 120.0))
			var py := int(16 + fmod(i * 37.0, 130.0))
			if Vector2(px, py).distance_to(c) > 36:
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if absi(dx) + absi(dy) <= 1:
							img.set_pixel(px + dx, py + dy, Color("#fff1a8"))
		_iskra = ImageTexture.create_from_image(img)
	return _iskra


# --- code-drawn placeholders (used by the game and the lab) ---------------------------

static func draw_cramp(ci: CanvasItem, c: Vector2, r: float, t: float, spike: bool) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := i / 10.0 * TAU + t * 0.002
		var wob := sin(t / 30.0 + i) * 4
		pts.append(c + Vector2(cos(a), sin(a)) * (r + wob))
		var a2 := a + TAU / 20
		pts.append(c + Vector2(cos(a2), sin(a2)) * (r * 0.4))
	Draw.polygon_safe(ci, pts, Color("#b91c1c") if spike else Color("#ea580c"))
	ci.draw_circle(c, maxf(1, r * 0.4 + sin(t / 80.0) * 2), Color("#b15827") if spike else Color("#facc15"))


## alive: spike index -> true (the boss loses spikes as it is hit).
static func draw_boss(ci: CanvasItem, c: Vector2, r: float, t: float, alive: Dictionary, col: Color) -> void:
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


## k = size factor (1 = the meadow's drop).
static func draw_drop(ci: CanvasItem, c: Vector2, k := 1.0, col := Color("#5fb3f0")) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -13) * k])
	for i in range(1, 12):
		var ang := -PI / 2 + i / 12.0 * TAU
		pts.append(c + Vector2(cos(ang) * 9, sin(ang) * 9 + 3) * k)
	Draw.polygon_safe(ci, pts, col)
	ci.draw_circle(c + Vector2(-3, 1) * k, 2.5 * k, Color(1, 1, 1, 0.8))


## pulse 0–1, a = alpha.
static func draw_seed(ci: CanvasItem, c: Vector2, pulse: float, a := 1.0, k := 1.0) -> void:
	Draw.radial_glow(ci, c, (30 + pulse * 10) * k, Color(1, 0.85, 0.4, 0.45 * a), Color(1, 0.98, 0.8, 0.9 * a))
	ci.draw_circle(c, 7 * k, Color("#fff4c2", a))
	ci.draw_circle(c + Vector2(-2, -2) * k, 2.5 * k, Color(1, 1, 1, a))


static func draw_distraction(ci: CanvasItem, c: Vector2, t: float) -> void:
	var r := Rect2(c.x - 22, c.y - 15, 44, 30)
	Draw.panel(ci, r, Color("#e2e8f0"), 8, Color("#94a3b8"), 1)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(c.x - 6, r.end.y), Vector2(c.x + 6, r.end.y), Vector2(c.x, r.end.y + 7)]), Color("#e2e8f0"))
	ci.draw_line(Vector2(r.position.x + 9, c.y - 4), Vector2(r.end.x - 9, c.y - 4), Color("#94a3b8"), 2.0)
	ci.draw_line(Vector2(r.position.x + 9, c.y + 3), Vector2(r.end.x - 15, c.y + 3), Color("#cbd5e1"), 2.0)
	ci.draw_circle(Vector2(r.end.x - 4, r.position.y + 4), 6 + sin(t / 120.0) * 1.0, Color("#ef4444"))
	ci.draw_string(Text.font_bold, Vector2(r.end.x - 7, r.position.y + 8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)


## base = bottom centre.
static func draw_thorn(ci: CanvasItem, base: Vector2) -> void:
	for i in 3:
		var bx := base.x + (i - 1) * 10
		var pts := PackedVector2Array([Vector2(bx - 6, base.y), Vector2(bx + (i - 1) * 3, base.y - 26 - (3 if i == 1 else 0)), Vector2(bx + 6, base.y)])
		ci.draw_colored_polygon(pts, Color("#166534"))
		ci.draw_line(pts[0], pts[1], Color("#4ade80"), 1.5, true)


static func draw_shadow(ci: CanvasItem, c: Vector2, t: float, a: float, seed_x: float) -> void:
	Draw.radial_glow(ci, c, 34, Color(0.1, 0.05, 0.2, 0.5 * a))
	var pts := PackedVector2Array()
	for i in 12:
		var ang := i / 12.0 * TAU
		var rr := 18 + sin(t / 60.0 + i * 2 + seed_x) * 5
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	Draw.polygon_safe(ci, pts, Color(0.12, 0.06, 0.22, 0.85 * a))
	ci.draw_circle(c + Vector2(-5, -3), 2.5, Color(1, 0.3, 0.3, a))
	ci.draw_circle(c + Vector2(5, -3), 2.5, Color(1, 0.3, 0.3, a))


## A flying notification: an envelope with flapping wings and a red "!".
## s = size (the wings span ≈ 2.4 s), flap −1…1, col = the envelope (fog tint).
static func draw_bird(ci: CanvasItem, c: Vector2, s: float, flap: float, col := Color("#f1f5f9")) -> void:
	var wing := col.darkened(0.08)
	for side: float in [-1.0, 1.0]:
		# Feathered wing: three fingers fanning out from the envelope's side.
		var root := c + Vector2(side * s * 0.5, -s * 0.05)
		for f in 3:
			var tip := root + Vector2(side * s * (0.75 - f * 0.12), -s * flap * (1.0 - f * 0.18) - s * (0.12 - f * 0.12))
			Draw.polygon_safe(ci, PackedVector2Array([root + Vector2(0, -s * 0.12), tip, root + Vector2(0, s * 0.14)]), wing.darkened(f * 0.05))
	var r := Rect2(c.x - s * 0.55, c.y - s * 0.36, s * 1.1, s * 0.72)
	ci.draw_rect(r, col)
	ci.draw_rect(r, col.darkened(0.35), false, maxf(1, s * 0.05))
	# The flap of the envelope.
	ci.draw_polyline(PackedVector2Array([r.position, Vector2(c.x, c.y + s * 0.05), Vector2(r.end.x, r.position.y)]), col.darkened(0.35), maxf(1, s * 0.05), true)
	# Red badge with "!".
	var bc := Vector2(r.end.x - s * 0.04, r.position.y + s * 0.02)
	ci.draw_circle(bc, s * 0.24, Color("#ef4444"))
	ci.draw_line(bc + Vector2(0, -s * 0.13), bc + Vector2(0, s * 0.04), Color.WHITE, maxf(1, s * 0.07))
	ci.draw_circle(bc + Vector2(0, s * 0.12), maxf(0.5, s * 0.04), Color.WHITE)


## A sun slice: a triangle pointing down (its tip is the sun's centre).
## turn = cos of the spin (−1…1) for a slow turn.
static func draw_sun_piece(ci: CanvasItem, c: Vector2, s: float, turn := 1.0) -> void:
	var w := s * 0.55 * maxf(0.15, absf(turn))
	var pts := PackedVector2Array([c + Vector2(-w, -s * 0.6), c + Vector2(w, -s * 0.6), c + Vector2(0, s * 0.7)])
	Draw.polygon_safe(ci, pts, Color("#fbbf24") if turn > 0 else Color("#f59e0b"))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#fff7d6"), maxf(1, s * 0.06), true)


## A thorny vine along `pts` (screen points, from the side to its tip).
static func draw_vine(ci: CanvasItem, pts: PackedVector2Array, w: float, col := Color("#2f6b2f")) -> void:
	ci.draw_polyline(pts, col, w, true)
	ci.draw_polyline(pts, col.lightened(0.25), maxf(1, w * 0.3), true)
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var n := (b - a).orthogonal().normalized() * w * 0.9 * (1 if i % 2 == 0 else -1)
		var m := a.lerp(b, 0.5)
		Draw.polygon_safe(ci, PackedVector2Array([m - (b - a) * 0.15, m + (b - a) * 0.15, m + n]), Color("#b91c1c"))


## The sun of the forest run: 12 triangular slices around `c`, the first `found`
## of them golden (flash 1 → 0 lights up the newest), a dot in the middle and a
## dot on each quarter (a minigame every 3 slices; the 12th ends the level).
static func draw_sun(ci: CanvasItem, c: Vector2, r: float, found: int, flash := 0.0, time := 0.0) -> void:
	for i in 12:
		var a0 := -PI / 2 + i * TAU / 12 + 0.035
		var a1 := -PI / 2 + (i + 1) * TAU / 12 - 0.035
		var tri := PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r])
		if i < found:
			var col := Color("#fbbf24")
			if i == found - 1 and flash > 0:
				col = col.lerp(Color("#fffbeb"), flash)
			Draw.polygon_safe(ci, tri, col)
		else:
			Draw.polygon_safe(ci, tri, Color(1, 1, 1, 0.16))
			ci.draw_polyline(tri + PackedVector2Array([tri[0]]), Color(1, 1, 1, 0.45), 1.5, true)
	for k: int in [0, 3, 6, 9]:
		var a := -PI / 2 + k * TAU / 12
		var done := found >= (12 if k == 0 else k)
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * (r + 4), 4.0, Color("#fef3c7") if done else Color(1, 1, 1, 0.75))
	ci.draw_circle(c, maxf(2.0, r * 0.12), Color("#fff7d6"))


## A glossy heart around `c`, `s` = its half width; `turn` (-1..1) squeezes it as it spins.
static func draw_heart(ci: CanvasItem, c: Vector2, s: float, turn := 1.0, alpha := 1.0) -> void:
	var sx := maxf(0.2, absf(turn))
	var pts := PackedVector2Array()
	for i in 24:
		var a := i / 24.0 * TAU
		# The classic heart curve, scaled to a half width of 1.
		var x := 16.0 * pow(sin(a), 3)
		var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
		pts.append(c + Vector2(x * sx, y + 2.0) * s / 16.0)
	var col := Color("#f43f5e") if turn >= 0 else Color("#e11d48")
	Draw.polygon_safe(ci, pts, Color(col, alpha))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.53, 0.07, 0.2, 0.8 * alpha), maxf(1.0, s * 0.1), true)
	ci.draw_circle(c + Vector2(-s * 0.38 * sx, -s * 0.32), s * 0.2, Color(1, 1, 1, 0.75 * alpha))


## A gold bell around `c` (`s` = its half width), swinging by `swing` radians.
static func draw_bell(ci: CanvasItem, c: Vector2, s: float, swing := 0.0) -> void:
	var top := c + Vector2(0, -s * 1.05)
	var pts := PackedVector2Array()
	var outline := [Vector2(-0.25, -0.8), Vector2(-0.5, -0.55), Vector2(-0.62, 0.0), Vector2(-0.75, 0.45), Vector2(-1.0, 0.7),
		Vector2(1.0, 0.7), Vector2(0.75, 0.45), Vector2(0.62, 0.0), Vector2(0.5, -0.55), Vector2(0.25, -0.8)]
	for q: Vector2 in outline:
		pts.append(top + ((q * s) + Vector2(0, s * 1.05)).rotated(swing))
	ci.draw_circle(top + Vector2(0, s * 1.85).rotated(swing * 1.6), s * 0.2, Color("#b45309"))
	Draw.polygon_safe(ci, pts, Color("#fbbf24"))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#92400e"), maxf(1.0, s * 0.1), true)
	ci.draw_line(top + Vector2(-s * 0.35, s * 0.55).rotated(swing), top + Vector2(-s * 0.45, s * 1.35).rotated(swing), Color(1, 1, 0.85, 0.8), maxf(1.0, s * 0.12), true)
	ci.draw_arc(top + Vector2(0, -s * 0.12), s * 0.18, 0, TAU, 12, Color("#92400e"), maxf(1.0, s * 0.09), true)


## A joker card (`h` tall) with a three-pointed jester's hat, tilted by `tilt` radians.
static func draw_joker(ci: CanvasItem, c: Vector2, h: float, tilt := 0.0) -> void:
	var w := h * 0.72
	ci.draw_set_transform(c, tilt, Vector2.ONE)
	Draw.panel(ci, Rect2(-w / 2, -h / 2, w, h), Color("#fefce8"), h * 0.12, Color("#b45309"), maxf(1.0, h * 0.05))
	var cols := [Color("#7c3aed"), Color("#e11d48"), Color("#16a34a")]
	var base := h * 0.12
	for i in 3:
		var x0 := -w * 0.36 + i * w * 0.24
		var tip := Vector2(-w * 0.32 + i * w * 0.32, -h * 0.32 + (0.0 if i == 1 else h * 0.06))
		Draw.polygon_safe(ci, PackedVector2Array([Vector2(x0, base), Vector2(x0 + w * 0.24, base), tip]), cols[i])
		ci.draw_circle(tip, h * 0.055, Color("#fbbf24"))
	ci.draw_rect(Rect2(-w * 0.38, base - h * 0.01, w * 0.76, h * 0.09), Color("#fbbf24"))
	ci.draw_circle(Vector2(0, base + h * 0.2), h * 0.11, Color("#fde68a"))
	ci.draw_arc(Vector2(0, base + h * 0.2), h * 0.06, 0.3, PI - 0.3, 8, Color("#9a3412"), maxf(1.0, h * 0.03), true)
	ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## The placeholder of `id` at its game size (the lab's preview of "original").
static func draw_placeholder(ci: CanvasItem, id: String, c: Vector2, t: float) -> void:
	match id:
		"heart":
			draw_heart(ci, c + Vector2(0, sin(t / 400.0) * 3), 15, cos(t / 420.0))
		"bell":
			draw_bell(ci, c, 17, sin(t / 260.0) * 0.3)
		"joker":
			draw_joker(ci, c + Vector2(0, sin(t / 300.0) * 4), 46, sin(t / 500.0) * 0.12)
		"sun_piece":
			Draw.radial_glow(ci, c, 34, Color(1, 0.8, 0.3, 0.55), Color(1, 0.95, 0.7, 0.9))
			draw_sun_piece(ci, c, 26, cos(t / 1000.0 * 2.2))
		"vine":
			var pts := PackedVector2Array()
			for i in 9:
				var k := i / 8.0
				pts.append(c + Vector2(-60 + 120 * k, sin(k * PI) * -14 + sin(t / 1000.0 * 6 + k * 5) * 3))
			draw_vine(ci, pts, 8)
		"iron":
			Draw.iron_nut(ci, c + Vector2(0, sin(t / 300.0) * 3), 12, t / 800.0)
		"drop":
			draw_drop(ci, c + Vector2(0, sin(t / 300.0) * 3))
		"seed":
			draw_seed(ci, c + Vector2(0, sin(t / 350.0) * 4), 0.5 + 0.5 * sin(t / 220.0))
		"cramp", "spike":
			var jit := Vector2(sin(t / 50.0) * 3, cos(t / 40.0) * 3)
			draw_cramp(ci, c + jit, (20.0 if id == "cramp" else 15.0) + sin(t / 150.0) * 6, t, id == "spike")
		"boss":
			var alive := {}
			for i in 20:
				alive[i] = true
			draw_boss(ci, c, 60 + sin(t / 150.0) * 12, t, alive, Color("#b15827"))
		"bird":
			draw_bird(ci, c, 40, sin(t / 1000.0 * 14) * 0.6)
		"distraction":
			draw_distraction(ci, c + Vector2(0, sin(t / 180.0) * 3), t)
		"thorn":
			draw_thorn(ci, c + Vector2(0, 15))
		"shadow":
			draw_shadow(ci, c + Vector2(0, sin(t / 120.0) * 4), t, 1.0, 0.0)
		"portrait_iskra":
			var tex := iskra_texture()
			ci.draw_texture_rect(tex, Rect2(c - Vector2(59, 59), Vector2(118, 118)), false)
		_:
			if id.begins_with("portrait_"):
				ci.draw_texture_rect(blank_portrait(id), Rect2(c - Vector2(59, 59), Vector2(118, 118)), false)
