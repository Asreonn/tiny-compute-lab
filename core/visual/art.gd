class_name Art
extends RefCounted
## Loads Penpot-exported SVGs (assets/art, see docs/VISUAL_SYSTEM.md) and rasterises them
## at SCALE× so they stay crisp when the camera zooms in. Every sprite that uses one must
## be drawn at 1/SCALE (use Art.sprite()).

const ROOT := "res://assets/art/"
const SCALE := 3.0

static var _cache := {}
static var _manifest := {}


static func tex(rel: String) -> Texture2D:
	if _cache.has(rel):
		return _cache[rel]
	var f := FileAccess.open(ROOT + rel, FileAccess.READ)
	if f == null:
		push_error("Art: missing " + rel)
		_cache[rel] = null
		return null
	var img := Image.new()
	var err := img.load_svg_from_string(f.get_as_text(), SCALE)
	if err != OK:
		push_error("Art: bad svg " + rel)
		return null
	var t := ImageTexture.create_from_image(img)
	_cache[rel] = t
	return t


static func pad(rel: String) -> float:
	if _manifest.is_empty():
		var f := FileAccess.open(ROOT + "manifest.json", FileAccess.READ)
		if f:
			_manifest = JSON.parse_string(f.get_as_text())
	return float(_manifest.get(rel, {}).get("pad", 0))


## A Sprite2D positioned so the asset's un-padded origin sits at `pos`.
static func sprite(rel: String, pos := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(rel)
	s.centered = false
	s.scale = Vector2.ONE / SCALE
	var p := pad(rel)
	s.position = pos - Vector2(p, p)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


## Same but centred on `pos` (ports, packets, LEDs).
static func sprite_centered(rel: String, pos := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(rel)
	s.centered = true
	s.scale = Vector2.ONE / SCALE
	s.position = pos
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return s


static func icon(name: String) -> Texture2D:
	return tex("icon/%s.svg" % name)


static func size_key(type: String) -> String:
	return str(Catalog.def(type)["size"]).to_lower()


static func port_file(dir: String, datatype: int, state: String) -> String:
	var d := {"in": "input", "out": "output", "ctrl": "control"}[dir]
	var t := "boolean" if datatype == DataType.BOOLEAN else "number"
	if d == "control":
		t = "boolean"
	return "port/port_%s_%s_%s.svg" % [d, t, state]


static func packet_file(datatype: int, near: bool, state: String) -> String:
	return "packet/packet_%s_%s_%s.svg" % ["boolean" if datatype == DataType.BOOLEAN else "number", "near" if near else "far", state]
