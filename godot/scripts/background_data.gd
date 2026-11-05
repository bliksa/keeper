class_name BackgroundData
extends RefCounted
## The background behind each level: a base colour, the level's procedural sky
## (meadow, summit) and any number of parallax image layers, drawn back to front.
## Bundled in data/backgrounds.json; the level editor edits a copy and can use it
## in the game (Game.custom_backgrounds) or commit it to the repo.
##
## Level entry: {"base": "#rrggbb", "procedural": bool, "tint": bool, "layers": [layer…]}
## Layer: {"image": path, "speed": float, "scale": float, "offset": [x, y],
##         "opacity": float, "repeat": bool}
##   speed   how much the layer moves with the camera (0 = fixed, 1 = with the
##           world, > 1 = a foreground layer that moves faster)
##   scale   1 = the image fills the screen's width (vertical levels) or height
##           (horizontal levels)
##   offset  extra shift in pixels
##   repeat  tile the image along the level's direction

const PATH := "res://data/backgrounds.json"

static var _bundled := {}


static func bundled() -> Dictionary:
	if _bundled.is_empty() and FileAccess.file_exists(PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			_bundled = d
	return _bundled


## A layer with every field filled in.
static func layer(image := "", speed := 0.5) -> Dictionary:
	return {"image": image, "speed": speed, "scale": 1.0, "offset": [0.0, 0.0], "opacity": 1.0, "repeat": true}


## Normalised config of a level (missing fields filled with defaults).
static func normalize(cfg: Dictionary) -> Dictionary:
	var out := {"base": str(cfg.get("base", "#101018")), "procedural": bool(cfg.get("procedural", false)),
		"tint": bool(cfg.get("tint", false)), "layers": []}
	for l in cfg.get("layers", []):
		if l is Dictionary:
			var n := layer()
			n.merge(l, true)
			var off: Variant = n.offset
			n.offset = [float(off[0]), float(off[1])] if off is Array and off.size() >= 2 else [0.0, 0.0]
			n.speed = float(n.speed)
			n.scale = maxf(0.05, float(n.scale))
			n.opacity = clampf(float(n.opacity), 0, 1)
			n.repeat = bool(n.repeat)
			n.image = str(n.image)
			out.layers.append(n)
	return out


## The bundled background of a level.
static func of_bundled(id: int) -> Dictionary:
	return normalize(bundled().get(str(id), {}))


## What the game shows for a level (the editor's "Use in game" wins).
static func for_level(id: int) -> Dictionary:
	if Game.custom_backgrounds.has(id):
		return Game.custom_backgrounds[id]
	return of_bundled(id)


## Draws the image layers into a rect of `view` size with the camera at `cam`
## (world pixels). Horizontal levels scroll the layers sideways, vertical ones
## up and down. `origin` is the camera where the level starts (the summit starts
## at the bottom), so a layer with no shift sits on screen at the start.
static func draw_layers(ci: CanvasItem, cfg: Dictionary, cam: Vector2, view: Vector2, horizontal: bool, origin := Vector2.ZERO) -> void:
	cam -= origin
	for l in cfg.get("layers", []):
		var t := AssetBrowser.tex(l.image)
		if t == null or t.get_width() == 0 or t.get_height() == 0:
			continue
		var sc: float = l.scale
		var off: Array = l.offset
		var mod := Color(1, 1, 1, l.opacity)
		if horizontal:
			var th := view.y * sc
			var tw := t.get_width() * th / t.get_height()
			var y: float = view.y - th + off[1]
			var shift: float = cam.x * l.speed - off[0]
			if l.repeat:
				var x := -fposmod(shift, tw)
				while x < view.x:
					ci.draw_texture_rect(t, Rect2(x, y, tw, th), false, mod)
					x += tw
			else:
				ci.draw_texture_rect(t, Rect2(-shift, y, tw, th), false, mod)
		else:
			var tw := view.x * sc
			var th := t.get_height() * tw / t.get_width()
			var x: float = (view.x - tw) / 2 + off[0]
			var shift: float = cam.y * l.speed - off[1]
			if l.repeat:
				var y := -fposmod(shift, th)
				while y < view.y:
					ci.draw_texture_rect(t, Rect2(x, y, tw, th), false, mod)
					y += th
			else:
				ci.draw_texture_rect(t, Rect2(x, -shift, tw, th), false, mod)
