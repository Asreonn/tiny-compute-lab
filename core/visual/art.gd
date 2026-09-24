class_name Art
extends RefCounted
## Loads Penpot-exported SVGs (assets/art, see docs/VISUAL_SYSTEM.md) and rasterises them
## at SCALE× so they stay crisp when the camera zooms in. Every sprite that uses one must
## be drawn at 1/SCALE (use Art.sprite()).

const ROOT := "res://assets/art/"
const SCALE := 3.0

static var _cache := {}
static var _manifest := {}
static var _layouts := {}


static func _layout_data() -> Dictionary:
	if _layouts.is_empty():
		var f := FileAccess.open(ROOT + "machine_layouts.json", FileAccess.READ)
		if f:
			_layouts = JSON.parse_string(f.get_as_text())
	return _layouts


## Machine layout entry from assets/art/machine_layouts.json: machines[type] for the MVP
## types; "usb_input" resolves to the roadmap USBInput kit (whose width tag width is
## replaced by the instance width at runtime).
static func layout(type: String) -> Dictionary:
	var l := _layout_data()
	var m: Dictionary = l.get("machines", {})
	if m.has(type):
		return m[type]
	if type == "usb_input":
		return l.get("roadmap", {}).get("USBInput", {})
	if type == "bit_splitter":
		# The Bit Splitter wears the roadmap BusSplitter kit (its width tags show the
		# current per-port widths at runtime, see MachineView._build_width_tags).
		return l.get("roadmap", {}).get("BusSplitter", {})
	if type == "usb_output":
		# Reuses the Output composition (EdgeOut-M) with USB silk and no Bin area yet
		# (docs/IMPLEMENTATION.md "Lab mode"); LabRun validates the width + bits itself.
		var out: Dictionary = m.get("output", {})
		var usb := out.duplicate(true) if not out.is_empty() else {"form": "EdgeOut-M", "family": "io"}
		usb.erase("area")
		usb["silk"] = {"text": "USB", "pos": [18, 47]}
		return usb
	if type in ["rom", "ram", "alu"]:
		return l.get("roadmap", {}).get(type.to_upper(), {})
	if type == "shift_left":
		return l.get("roadmap", {}).get("ShiftLeft", {})
	if type == "shift_right":
		return l.get("roadmap", {}).get("ShiftRight", {})
	if type in ["and_gate", "or_gate", "xor_gate", "not_gate"]:
		return l.get("roadmap", {}).get(type.trim_suffix("_gate").to_upper(), {})
	if type == "cond_router":
		return l.get("roadmap", {}).get("ConditionalRouter", {})
	if type == "adder":
		# The two-input Adder wears the roadmap two-input logic kit (Module-L, Merge lanes into an
		# OpWindow) with the math family and a "+" operator.
		var k: Dictionary = l.get("roadmap", {}).get("AND", {}).duplicate(true)
		k["family"] = "math"
		k["operator"] = "+"
		return k
	# Roadmap kit machines: snake_case type -> PascalCase kit key (modulo -> Modulo,
	# terminal_output -> TerminalOutput).
	var key := "".join(Array(type.split("_")).map(func(w): return w.capitalize()))
	return l.get("roadmap", {}).get(key, {})


## ActivityArea kind size in px from layouts.areas (Dial 40×40, Feed 84×28, …).
## Roadmap-kit areas the MVP layout table does not list (sizes from the Penpot 14 exports).
const KIT_AREA_SIZES := {"Taper": Vector2(56, 28), "OpWindow": Vector2(30, 24)}


static func area_size(kind: String) -> Vector2:
	var a: Dictionary = _layout_data().get("areas", {}).get(kind, {})
	if a.is_empty() and KIT_AREA_SIZES.has(kind):
		return KIT_AREA_SIZES[kind]
	return Vector2(float(a.get("w", 0)), float(a.get("h", 0)))


## Chassis form entry (shell asset + footprint) from layouts.forms.
static func form(name: String) -> Dictionary:
	return _layout_data().get("forms", {}).get(name, {})


# ------------------------------------------------------------------- asset paths

static func tab_file(family: String) -> String:
	return "machine/tab_%s.svg" % family.to_lower()


static func area_file(kind: String, state: String) -> String:
	return "machine/area_%s_%s.svg" % [kind.to_lower(), state.to_lower()]


static func led_file(state: String) -> String:
	return "machine/led_%s.svg" % state.to_lower()


static func pad_file(state: String, size: String) -> String:
	return "machine/pad_%s_%s.svg" % [state.to_lower(), size.to_lower()]


static func state_file(name: String, size: String) -> String:
	return "machine/state_%s_%s.svg" % [name.to_lower(), size.to_lower()]


static func display_file(width: String) -> String:
	return "machine/display_%s.svg" % width.to_lower()


static func readout_file(mode: String) -> String:
	return "signal/readout_%s.svg" % mode.to_lower()


static func widthtag_file(w: Variant) -> String:
	return "signal/widthtag_%s.svg" % str(w)


static func busport_file(dir: String, state: String) -> String:
	var d := "in" if dir == "in" else "out"
	var st := state if state in ["idle", "connected", "active"] else "connected"
	return "port/busport_%s_%s.svg" % [d, st]


## Port sprite file: bus ports use busport_* (bus states idle/connected/active, the
## remaining states map to connected); width-1 ports use boolean; everything else number.
static func port_sprite(dir: String, bus: bool, width: int, state: String) -> String:
	if bus:
		return busport_file(dir, state)
	return port_file(dir, width, state)


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


static func port_file(dir: String, width: int, state: String) -> String:
	var d: String = {"in": "input", "out": "output", "ctrl": "control"}[dir]
	var t := "boolean" if width == 1 else "number"
	if d == "control":
		t = "boolean"
	return "port/port_%s_%s_%s.svg" % [d, t, state]


## Packet sprite file: tier is the camera zoom tier ("far" | "normal" | "close"),
## state is the runtime packet state ("normal", "leaving", "entering", "queued", "processing", "error").
static func packet_file(width: int, tier: String, state: String) -> String:
	var t := tier if tier in ["far", "normal", "close"] else ("close" if tier == "near" else "normal")
	return "packet/packet_%s_%s_%s.svg" % ["boolean" if width == 1 else "number", t, state]
