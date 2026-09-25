class_name MachineView
extends Node2D
## Penpot "05 Machines / V2.1" composition built from assets/art/machine_layouts.json +
## manifest pads. Read-only over the Machine: refresh() reads Machine / SimulationManager
## state every frame and never writes the simulation.
##
## Node tree (z-order in the rotating Body): InstallPad · Shell · FamilyTab · ActivityArea ·
## glyph · MiniDisplay · Readout chip · WidthTag chips · LED · ports · state overlays.
## All text is drawn upright by the UprightText layer under the same local positions,
## rotated back so it never tilts with the body.

const T := Palette.TILE
const OVERLAY_TWEEN := 0.12  # s, state overlay fade in/out
const SILK_ALPHA := 0.55  # material silk text opacity

const TAG_ASSETS := ["1", "2", "3", "4", "8", "16"]  # widthtag assets that exist
const TAG_FALLBACK := "16"  # chip used for widths without an asset (single-digit widths use 14 px, others 18 px)
const GHOST_ALPHA := 0.6  # opacity of drag/build ghost views
## Codec machines (D4): the raw <-> bits boundary, drawn with a procedural raw port and a
## token-slot pill + silk chevron (design/reference/systems_v1.js codec()).
const CODEC_TYPES := ["number_encoder", "char_encoder", "number_decoder", "char_decoder"]

const MACHINE_STATE_LED := ["idle", "receiving", "processing", "outputready", "blocked", "error", "off"]

var machine: Machine
var hovered := false
var selected := false
## Failure-path highlight: set by the tools when the run FAILs; forces the error state
## overlay so the player sees exactly which machines are implicated.
var highlighted := false
## Ghost (move/build preview): the InstallPad is suppressed (the tools draw the
## placevalid/placeinvalid pad under it) and the view renders at ghost_alpha.
var ghost := false
var ghost_alpha := 1.0
## HUD-set view mode; -1 means "mission default" (output channel view / BIN).
var view_mode: int = -1

var body: Node2D
var text_layer: UprightText
var _size_key := "m"
var _area: Sprite2D
var _area_kind := ""
var _area_idle := "Idle"
var _opwin: Sprite2D = null  # roadmap OpWindow area (idle / active)
var _led: Sprite2D
var _led_rel := ""
var _overlays := {}  # name -> Sprite2D
var _port_nodes := {}  # port id -> Sprite2D
var _port_bus := {}  # port id -> bool
var _port_dir := {}  # port id -> "in"/"out"/"ctrl"
var _port_w := {}  # port id -> int
var _port_contact := {}  # port id -> PortContact (L1 contact ring node)
var _raw_ports := {}  # port id -> RawPortView (procedural raw receptacle)
var _codec_slot: CodecSlot = null  # codec token slot (D4)
var _usb_socket: UsbSocketView = null  # USB socket face + module (D4)
var _contract: ContractDriveView = null  # locked USB Output contract drive (D4)
var _thermal: ThermalPartView = null  # thermal family hardware (E3)
var _strip: ThermalStrip = null  # heat stage strip / critical frame (E3)
var _tag_nodes: Array = []  # width tag sprites (hidden when the mapped port is raw)
var _tag_values: Array = []  # width shown by each width tag (upright text)
var _tag_ports: Array = []  # tag i -> port id whose CURRENT width it shows ("" = layout/instance width)
var _tag_fallback: Array = []  # tag i -> layout width used when there is no port mapping
## Expansion reveal: newly added locked USB Input machines pulse their hover overlay for
## REVEAL_DURATION after a lab level-up (2 fade-in/out pulses). Set by World, read only.
var reveal_active := false
var reveal_start := -1.0
const REVEAL_DURATION := 2.5
const REVEAL_PULSES := 2.0
var _text_specs: Array = []  # {key, pos, width, size, align, color, text}
var _bin_color := Palette.DATA_NUMBER
var _progress: ProcessProgress
var _ri: ResourceIndicators
const DONE_HOLD := 0.25  # fraction of a tick a finished job shows 100 % before the next fills


func setup(m: Machine, as_ghost := false) -> MachineView:
	machine = m
	name = "Machine_%d" % m.id
	_size_key = str(m.def()["size"]).to_lower()
	ghost = as_ghost
	ghost_alpha = GHOST_ALPHA if as_ghost else 1.0
	_build()
	position = Vector2(m.cell) * T
	modulate.a = ghost_alpha
	return self


func _build() -> void:
	var m := machine
	var ly := Art.layout(m.type)
	var fm := Art.form(ly.get("form", ""))
	var rot := m.rot % 4

	body = Node2D.new()
	body.name = "Body"
	body.position = _rotated_body_offset()
	body.rotation = rot * PI / 2.0
	add_child(body)

	# Thermal family (STYLE_GUIDE §14.7): board-level copper, no chassis / ports / LED / silk.
	if str(m.def()["family"]) == "thermal":
		_build_thermal()
		return

	# 1 InstallPad · 2 Shell (ghosts skip the pad; the tools draw the placement pad under them)
	if not ghost:
		body.add_child(Art.sprite(Art.pad_file("default", _size_key), Vector2.ZERO))
	body.add_child(Art.sprite(str(fm.get("asset", "machine/shell_%s.svg" % _size_key)), Vector2.ZERO))
	# 3 FamilyTab
	var tab: Variant = ly.get("tab", [0, 0])
	body.add_child(Art.sprite(Art.tab_file(str(m.def()["family"])), _v(tab) if tab is Array and not tab.is_empty() else Vector2.ZERO))
	# 4 ActivityArea (idle state; the roadmap schema stores `areas[]`)
	var area: Dictionary = _entry(ly, "area")
	if area.is_empty() and ly.get("areas", null) is Array:
		# the first area that is not the OpWindow (drawn separately below) is the ActivityArea
		for a0 in ly["areas"]:
			if a0 is Dictionary and str(a0.get("kind", "")) != "OpWindow":
				area = a0
				break
	if not area.is_empty():
		_area_kind = str(area.get("kind", "Dial"))
		_area_idle = str(area.get("idle", "Idle"))
		_area = Art.sprite(Art.area_file(_area_kind, _area_idle), _v(area.get("pos", [0, 0])))
		_area.name = "ActivityArea"
		body.add_child(_area)
	# 4b OpWindow (roadmap kits): the exported operator window, lit while processing; its
	# glyph is upright text
	if ly.get("areas", null) is Array:
		for a in ly["areas"]:
			if a is Dictionary and str(a.get("kind", "")) == "OpWindow":
				_opwin = Art.sprite(Art.area_file("OpWindow", "Idle"), _v(a.get("pos", [0, 0])))
				_opwin.name = "OpWindow"
				body.add_child(_opwin)
	# 5 glyph icon, scaled to glyph.size
	var glyph: Dictionary = _entry(ly, "glyph")
	if not glyph.is_empty() and str(glyph.get("icon", "")) != "":
		var g := Art.sprite("icon/%s.svg" % glyph["icon"], _v(glyph.get("pos", [0, 0])))
		var gs := float(glyph.get("size", 24))
		if g.texture != null:
			var n := Vector2(g.texture.get_width() / Art.SCALE, g.texture.get_height() / Art.SCALE)
			g.scale *= Vector2(gs / n.x if n.x > 0 else 1.0, gs / n.y if n.y > 0 else 1.0)
		g.name = "Glyph"
		body.add_child(g)
	# 6 MiniDisplay chip
	var disp: Dictionary = _entry(ly, "display")
	if not disp.is_empty():
		body.add_child(Art.sprite(Art.display_file(str(disp.get("width", "W36"))), _v(disp.get("pos", [0, 0]))))
	# 7 Readout chip — only for layouts that carry a readout entry
	var ro: Dictionary = _entry(ly, "readout")
	if not ro.is_empty():
		body.add_child(Art.sprite(Art.readout_file(str(ro.get("mode", "DEC"))), _v(ro.get("pos", [0, 0]))))
	# 8 WidthTag chips
	_build_width_tags(ly)
	# 9 StatusLED (layout.led; falls back to the form position when the layout omits it; null = none)
	var led_p: Variant = ly.get("led", fm.get("led", []))
	if led_p is Array and not (led_p as Array).is_empty():
		_led = Art.sprite(Art.led_file("idle"), _v(led_p as Array))
		_led.name = "StatusLED"
		body.add_child(_led)
	# 10 Ports centred on their anchors
	_build_ports(ly)
	# 11 state overlays (over the shell)
	for overlay in ["processing", "outputready", "blocked", "error", "hover", "selected"]:
		var s := Art.sprite(Art.state_file(overlay, _size_key), Vector2.ZERO)
		s.modulate.a = 0.0
		_overlays[overlay] = s
		body.add_child(s)
	# 11b D4 procedural systems layered over the chassis: codec token slot, USB socket
	# face + data module, and the locked USB Output contract drive.
	if machine.type in CODEC_TYPES:
		_codec_slot = CodecSlot.new()
		_codec_slot.name = "CodecSlot"
		body.add_child(_codec_slot)
	if machine.type == "usb_input":
		_usb_socket = UsbSocketView.new()
		_usb_socket.machine = machine
		_usb_socket.name = "UsbSocket"
		body.add_child(_usb_socket)
	if machine.type == "usb_output" and machine.locked and SimulationManager.run != null and SimulationManager.run.has_method("request_bits"):
		_contract = ContractDriveView.new()
		_contract.machine = machine
		_contract.name = "ContractDrive"
		body.add_child(_contract)
	# 12 upright text layer
	# 12a processing progress (ActivityArea progress, docs/MOTION_SYSTEM.md): rotates with the body
	_progress = ProcessProgress.new()
	_progress.name = "ProcessProgress"
	_progress.center = core_local()
	_progress.dial = _area_kind == "Dial"
	var asz := Art.area_size(_area_kind)
	_progress.area_rect = Rect2(_progress.center - asz * 0.5, asz) if asz != Vector2.ZERO else Rect2()
	_progress.chassis = Rect2(Vector2.ZERO, Vector2(Catalog.SIZES[machine.def()["size"]]) * T)
	if machine.type in ["usb_input", "usb_output"] or machine.type in CODEC_TYPES:
		_progress.chassis = Rect2(0, 0, 2 * T, T)  # the chassis is the top row (bay / screen below)
	body.add_child(_progress)
	# 12b resource indicators (STYLE_GUIDE §3): a child of the rotating Body so it rotates
	# with the chassis like other silk (tiny geometry, no text -> no upright problem).
	# Player machines only: mission IO / lab infrastructure (locked) and ghosts show none.
	if not machine.locked and not ghost:
		var base := Vector2(Catalog.SIZES[machine.def()["size"]]) * T
		if machine.type in CODEC_TYPES:
			base = Vector2(2 * T, T)  # on the chassis row, above the conversion screen
		_ri = ResourceIndicators.new()
		_ri.name = "ResourceIndicators"
		if _size_key == "s":
			_ri.compact = true
			_ri.xr = 58.0
			_ri.y = 4.0
		else:
			_ri.compact = false
			_ri.xr = base.x - 20.0
			_ri.y = base.y - 15.0
		body.add_child(_ri)
	# 12c heat stage strip + CRITICAL frame/badge (player machines; the body is never tinted)
	if not machine.locked and not ghost:
		_strip = ThermalStrip.new()
		_strip.name = "ThermalStrip"
		_strip.size = Vector2(Catalog.SIZES[machine.def()["size"]]) * T
		body.add_child(_strip)
	text_layer = UprightText.new()
	text_layer.name = "UprightText"
	add_child(text_layer)
	_build_texts(ly, area, disp, ro)


func _build_thermal() -> void:
	_thermal = ThermalPartView.new()
	_thermal.name = "ThermalPart"
	_thermal.setup(machine)
	# a heat pipe draws its conduit in board directions, so it must not rotate with the body
	if machine.type == "heat_pipe":
		add_child(_thermal)
	else:
		body.add_child(_thermal)
	for overlay in ["processing", "outputready", "blocked", "error", "hover", "selected"]:
		var s := Art.sprite(Art.state_file(overlay, _size_key), Vector2.ZERO)
		s.modulate.a = 0.0
		_overlays[overlay] = s
		body.add_child(s)
	text_layer = UprightText.new()
	text_layer.name = "UprightText"
	add_child(text_layer)


func _build_width_tags(ly: Dictionary) -> void:
	_tag_values.clear()
	_tag_ports.clear()
	_tag_fallback.clear()
	_tag_nodes.clear()
	var tags: Array = ly.get("width_tags", [])
	if tags == null:
		tags = []
	if machine.type == "output":
		# The Output wears one tag of its width, one S-gap right of its family tab (16..40).
		tags = [{"width": str(machine.width), "pos": [48.0, 4.0]}]
	var cports: Array = machine.ports()
	var i := 0
	for tag in tags:
		if not (tag is Dictionary):
			continue
		var w: int = int(tag["width"])
		var port_id := ""
		if machine.type == "usb_input":
			w = machine.width  # the roadmap tag is a placeholder for the instance width
		elif machine.type in ["bit_splitter", "bus_combiner", "zero_extend", "sign_extend", "truncate"] and i < cports.size():
			# The BusSplitter kit's tags sit at ports in / hi / lo; tag i shows the CURRENT
			# width of port i (machine.port_width), refreshed on param changes — not the
			# layout's placeholder numbers.
			port_id = str(cports[i]["id"])
			w = machine.port_width(port_id)
		elif machine.type in CODEC_TYPES:
			# One tag on the bus side; it shows the live `width` param (D4).
			for p in cports:
				if bool(p.get("bus", false)):
					port_id = str(p["id"])
					w = machine.port_width(port_id)
					break
		var pos := _v(tag.get("pos", [0, 0]))
		var chip_w := 14.0
		var rel := Art.widthtag_file(w)
		if not (str(w) in TAG_ASSETS):
			# No asset for this width: draw the 16 chip and scale it horizontally to fit
			# (14 px for single digits, keep the two-digit 18 px for wider widths).
			rel = Art.widthtag_file(TAG_FALLBACK)
			var target := 14.0 if str(w).length() <= 1 else 18.0
			var base := 18.0
			chip_w = target
			var c := Art.sprite(rel, pos)
			c.scale.x *= target / base  # keep Art.SCALE rasterisation; only narrow the chip
			c.name = "WidthTag%d" % i
			body.add_child(c)
			_tag_nodes.append(c)
		else:
			var c := Art.sprite(rel, pos)
			c.name = "WidthTag%d" % i
			body.add_child(c)
			_tag_nodes.append(c)
		_tag_values.append(w)
		_tag_ports.append(port_id)
		_tag_fallback.append(int(tag["width"]))
		_text_specs.append({
			"key": "tag%d" % i, "pos": Vector2(pos.x + 0.0, pos.y + 1.0),
			"width": chip_w, "size": 7.5, "align": HORIZONTAL_ALIGNMENT_CENTER,
			"color": Palette.DATA_NUMBER, "text": "",
		})
		i += 1


## Current value of width tag i: the live port width when mapped, the instance width for
## USB I/O, otherwise the layout's placeholder.
func _tag_width(i: int) -> int:
	var pid: String = _tag_ports[i]
	if pid != "":
		return machine.port_width(pid)
	if machine.type in ["usb_input", "output"]:
		return machine.width
	return _tag_fallback[i]


func _build_ports(ly: Dictionary) -> void:
	var lports: Array = ly.get("ports", [])
	if lports == null:
		lports = []
	var cports: Array = machine.ports()
	for i in lports.size():
		var lp: Variant = lports[i]
		if not (lp is Dictionary):
			continue
		var pid := str(cports[i]["id"]) if i < cports.size() else "p%d" % i
		var pd := Catalog.port_def(machine.type, pid)
		var dir: String = str(pd.get("dir", "out"))
		var bus: bool = bool(pd.get("bus", false))
		var w: int = machine.port_width(pid)
		var s := Art.sprite_centered(Art.port_sprite(dir, bus, w, "idle"), _v(lp.get("anchor", [0, 0])))
		s.name = "Port%s" % pid.capitalize()
		body.add_child(s)
		_port_nodes[pid] = s
		_port_bus[pid] = bus
		_port_dir[pid] = dir
		_port_w[pid] = w
		# L1 port contact ring: follows the sprite (child of the rotating Body, inherits ghost alpha).
		var ring := PortContact.new()
		ring.bus = bus
		ring.width = w
		ring.position = _v(lp.get("anchor", [0, 0]))
		ring.name = "PortContact%s" % pid.capitalize()
		body.add_child(ring)
		_port_contact[pid] = ring
		# D4: a procedural raw receptacle. Visibility follows machine.port_role() every
		# frame, so a USB socket swaps its BusPort sprite for the raw port when a raw
		# module is plugged (and back when it is unplugged).
		var rp := RawPortView.new()
		rp.dir = dir
		rp.position = _v(lp.get("anchor", [0, 0]))
		rp.name = "RawPort%s" % pid.capitalize()
		body.add_child(rp)
		_raw_ports[pid] = rp


func _build_texts(ly: Dictionary, area: Dictionary, disp: Dictionary, ro: Dictionary) -> void:
	var rot := machine.rot % 4
	# Local -> upright (root-space) position for a body-local point.
	var off := _rotated_body_offset()
	# MiniDisplay value (centred across the display width, top of the text box at +2)
	if not disp.is_empty():
		var dw := int(str(disp.get("width", "W36")).trim_prefix("W"))
		var dp: Array = disp.get("pos", [0, 0])
		_text_specs.append({
			"key": "display", "pos": _upright(Vector2(dp[0], dp[1] + 2), off, rot),
			"width": float(dw), "size": 11.0, "align": HORIZONTAL_ALIGNMENT_CENTER,
			"color": Palette.DATA_NUMBER, "text": "",
		})
	# Readout: mode chip (3,4,26,14) + value (30,4,54,14), relative to readout.pos
	if not ro.is_empty():
		var rp: Array = ro.get("pos", [0, 0])
		_text_specs.append({
			"key": "ro_mode", "pos": _upright(Vector2(rp[0] + 3, rp[1] + 4), off, rot),
			"width": 26.0, "size": 7.0, "align": HORIZONTAL_ALIGNMENT_CENTER,
			"color": Palette.TEXT_SECONDARY, "text": "",
		})
		var col := Palette.DATA_NUMBER
		if str(ro.get("mode", "DEC")).to_upper() == "CHR":
			col = Palette.FAMILY_IO
		_text_specs.append({
			"key": "ro_value", "pos": _upright(Vector2(rp[0] + 30, rp[1] + 4), off, rot),
			"width": 54.0, "size": 10.0, "align": HORIZONTAL_ALIGNMENT_RIGHT,
			"color": col, "text": "",
		})
	# Dial operator text (roadmap kit, e.g. Modulo "%"): Penpot draws it 18/800 centred in the
	# 40 px dial at (area.x, area.y + 9).
	if ly.get("dial_text", null) is String and not area.is_empty():
		var dp2: Array = area.get("pos", [0, 0])
		_text_specs.append({
			"key": "dial", "pos": _upright(Vector2(dp2[0], dp2[1] + 9), off, rot),
			"width": 40.0, "size": 18.0, "align": HORIZONTAL_ALIGNMENT_CENTER,
			"color": Palette.TEXT_PRIMARY, "text": str(ly["dial_text"]),
		})
	# Operator glyph in the OpWindow (roadmap kits: "&", "^", "+"): 16/800 text.primary, centred
	# in the 30x24 window, top of the text box at +2
	if ly.get("operator", null) is String and ly.get("areas", null) is Array:
		for a in ly["areas"]:
			if a is Dictionary and str(a.get("kind", "")) == "OpWindow":
				var op: Array = a.get("pos", [0, 0])
				_text_specs.append({
					"key": "operator", "pos": _upright(Vector2(op[0], op[1] + 2), off, rot),
					"width": 30.0, "size": 16.0, "align": HORIZONTAL_ALIGNMENT_CENTER,
					"color": Palette.TEXT_PRIMARY, "text": str(ly["operator"]),
				})
	# Silk text (the Terminal has no silk entry in its kit layout: it shares the Output's slot)
	var sylk: Dictionary = _entry(ly, "silk")
	if sylk.is_empty() and machine.type == "terminal_output":
		sylk = {"pos": [18, 47]}
	if not sylk.is_empty():
		var sp: Array = sylk.get("pos", [0, 0])
		_text_specs.append({
			"key": "silk", "pos": _upright(Vector2(sp[0] - 2, sp[1]), off, rot),
			"width": 120.0, "size": 8.0, "align": HORIZONTAL_ALIGNMENT_LEFT,
			"color": Color(Palette.MATERIAL_SILK, SILK_ALPHA), "text": "",
		})
	# Output Bin read-back (drawn inside the Bin area, which fills the chassis)
	if machine.type == "output" and not area.is_empty():
		var ap: Array = area.get("pos", [16, 18])
		_text_specs.append({
			"key": "bin", "pos": _upright(Vector2(ap[0], ap[1]), off, rot),
			"width": 84.0, "height": 28.0, "size": 11.0, "align": HORIZONTAL_ALIGNMENT_CENTER,
			"color": Palette.DATA_NUMBER, "text": "",
		})


## Rotate a body-local point to the upright (root-space) layer under body offset `off`.
static func _upright(p: Vector2, off: Vector2, rot: int) -> Vector2:
	return off + _rot_point(p, rot)


# ------------------------------------------------------------------ transform

## Body offset so a 90°·rot rotation lands the footprint on the cell (Catalog rules).
func _rotated_body_offset() -> Vector2:
	var b := Vector2(Catalog.SIZES[machine.def()["size"]]) * T
	match machine.rot % 4:
		1: return Vector2(b.y, 0)
		2: return b
		3: return Vector2(0, b.x)
	return Vector2.ZERO


static func _rot_point(p: Vector2, rot: int) -> Vector2:
	match rot % 4:
		1: return Vector2(-p.y, p.x)
		2: return Vector2(-p.x, -p.y)
		3: return Vector2(p.y, -p.x)
	return p


## Layout entries may be explicit nulls ("display": null in the JSON); treat them as absent.
static func _entry(ly: Dictionary, key: String) -> Dictionary:
	var v: Variant = ly.get(key, {})
	return v if v is Dictionary else {}


## Map a layout readout mode label ("DEC", "CHR", …) to a ViewMode int.
static func _mode_from_name(s: String) -> int:
	match s.to_upper():
		"BIN": return ViewMode.Mode.BIN
		"DEC": return ViewMode.Mode.UDEC
		"HEX": return ViewMode.Mode.HEX
		"CHR", "CHAR": return ViewMode.Mode.CHAR
		"SDEC": return ViewMode.Mode.SDEC
		"TYPE": return ViewMode.Mode.TYPE
	return ViewMode.Mode.BIN


## World centre of the machine's function region (ActivityArea): where a job's packet sits
## while it is processed (PacketLayer) and where the progress indicator draws.
func core_world() -> Vector2:
	return body.to_global(core_local())


## Body-local centre of the ActivityArea (layout pos + area size / 2), or the chassis centre.
func core_local() -> Vector2:
	var ly := Art.layout(machine.type)
	var area: Dictionary = _entry(ly, "area")
	if area.is_empty() and ly.get("areas", null) is Array and not (ly["areas"] as Array).is_empty():
		area = (ly["areas"] as Array)[0]
	var base := Vector2(Catalog.SIZES[machine.def()["size"]]) * T
	if area.is_empty():
		return base * 0.5
	var sz := Art.area_size(str(area.get("kind", "")))
	return _v(area.get("pos", [0, 0])) + sz * 0.5


static func _v(a: Array) -> Vector2:
	return Vector2(a[0], a[1])


## World position of a port anchor, consistent with Machine.port_geom and the layout anchors.
static func port_world(m: Machine, port_id: String) -> Vector2:
	var g := m.port_geom(port_id)
	var c: Vector2 = Vector2(g["cell"]) * T + Vector2(T, T) / 2.0
	return c + Vector2(Catalog.side_vec(g["side"])) * (T / 2.0)


func world_rect() -> Rect2:
	return Rect2(position, Vector2(Catalog.size_of(machine.type, machine.rot)) * T)


func port_anchor(port_id: String) -> Vector2:
	return port_world(machine, port_id)


# ------------------------------------------------------------------ per-frame

func refresh(delta: float) -> void:
	var m := machine
	var sim := SimulationManager.sim
	var running := SimulationManager.running
	_update_progress()
	# LED from machine state (lab sockets: Receiving on a packet leaving this tick, Idle when
	# plugged, Off when empty — design/reference/systems_v1.js socket states)
	var led_name: String = MACHINE_STATE_LED[m.state]
	if machine.socket:
		if "out" in machine.sent_ports:
			led_name = "receiving"
		elif machine.device != "":
			led_name = "idle"
		else:
			led_name = "off"
	if m.state != Machine.State.ERROR:
		if m.heat_stage == ThermalGrid.Stage.CRITICAL:
			led_name = "overheated"
		elif m.heat_stage == ThermalGrid.Stage.THROTTLING:
			led_name = "throttling"
	if _led != null and led_name != _led_rel:
		_led.texture = Art.tex(Art.led_file(led_name))
		_led_rel = led_name
	# Activity area variant
	if _area != null:
		var rel := Art.area_file(_area_kind, _area_state(running))
		var t := Art.tex(rel)
		if _area.texture != t:
			_area.texture = t
	if _opwin != null:
		var busy := running and m.state in [Machine.State.PROCESSING, Machine.State.RECEIVING]
		var ot := Art.tex(Art.area_file("OpWindow", "Active" if busy else "Idle"))
		if _opwin.texture != ot:
			_opwin.texture = ot
	# State overlays (alpha tween 0.12 s); hover/selected driven by the tools. The
	# processing/outputready body overlays stay at alpha 0 always (VFX ladder L2 is the
	# ActivityArea / LED only, never a body glow).
	var want := {
		"processing": 0.0,  # listed so an already-visible sprite still fades out
		"outputready": 0.0,
		"blocked": 1.0 if m.state == Machine.State.BLOCKED else 0.0,
		"error": 1.0 if (m.state == Machine.State.ERROR or highlighted) else 0.0,
		"hover": 1.0 if hovered and not selected else 0.0,
		"selected": 1.0 if selected else 0.0,
	}
	for k in want:
		var o: Sprite2D = _overlays[k]
		o.modulate.a = move_toward(o.modulate.a, want[k], delta / OVERLAY_TWEEN)
	# Expansion reveal: newly added locked USB Inputs pulse their hover overlay for 2.5 s
	# (2 fade-in/out pulses). Overrides the tween while active.
	if reveal_active:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - reveal_start
		if elapsed < REVEAL_DURATION:
			var ph := elapsed / REVEAL_DURATION * REVEAL_PULSES
			_overlays["hover"].modulate.a = absf(sin(PI * ph))
		else:
			reveal_active = false
			_overlays["hover"].modulate.a = 0.0
	# Ports: connected / idle from SimulationManager.sim (never "active" — the baked halo
	# texture is retired; L1 transfer is the procedural contact ring instead).
	for pid in _port_nodes:
		var st := _port_state(pid, running)
		var rel2 := Art.port_sprite(_port_dir[pid], _port_bus[pid], _port_w[pid], st)
		var pt := Art.tex(rel2)
		if _port_nodes[pid].texture != pt:
			_port_nodes[pid].texture = pt
		_update_contact(pid, sim)
	# D4: raw receptacles follow the port role; codec slot / socket / contract overlays.
	for pid in _raw_ports:
		var raw_role: bool = machine.port_role(pid) == Catalog.ROLE_RAW
		_raw_ports[pid].visible = raw_role
		if _port_nodes.has(pid):
			_port_nodes[pid].visible = not raw_role
		if _port_contact.has(pid):
			_port_contact[pid].visible = not raw_role
	if _codec_slot != null:
		_update_codec_slot()
	if _usb_socket != null:
		_usb_socket.hovered = hovered and not selected
		_usb_socket.refresh()
	if _contract != null:
		_contract.refresh()
	if _thermal != null:
		_thermal.refresh(delta)
	if _strip != null:
		_strip.refresh(machine.heat_stage, delta)
	# Upright texts
	_update_texts(sim, running)
	# Width tags hide (sprite and silk digits) when their port is a raw receptacle.
	for i in _tag_nodes.size():
		var tpid: String = str(_tag_ports[i]) if i < _tag_ports.size() else ""
		var raw_tag: bool = tpid != "" and machine.port_role(tpid) == Catalog.ROLE_RAW
		_tag_nodes[i].visible = not raw_tag
		if raw_tag:
			for t in _text_specs:
				if t["key"] == "tag%d" % i:
					t["text"] = ""
	text_layer.queue_redraw()
	# Resource indicators: same visibility rule as the old stats silk (normal + close zoom,
	# never at far zoom). Ghosts/locked machines have no _ri (they are not built).
	if _ri != null:
		var cam := get_viewport().get_camera_2d()
		var far := cam != null and cam.zoom.x < Palette.ZOOM_FAR_BELOW
		_ri.visible = not far
		if not far:
			_ri.set_data(machine.processing_ticks(), machine.power(), str(machine.params.get("clock", "normal")))


func _update_texts(sim: Simulation, _running: bool) -> void:
	var m := machine
	var vm := resolve_view_mode()
	var vals := {}
	vals["display"] = _display_value(vm)
	var ro: Dictionary = _entry(Art.layout(m.type), "readout")
	if not ro.is_empty():
		vals["ro_mode"] = ViewMode.chip(vm if m.type == "terminal_output" else _mode_from_name(str(ro.get("mode", "DEC"))))
		vals["ro_value"] = _readout_value(vm)
	vals["silk"] = _silk_text(sim)
	vals["bin"] = _bin_value(sim)
	for i in _tag_values.size():
		_tag_values[i] = _tag_width(i)  # refresh live widths (e.g. bit_splitter lo param)
		vals["tag%d" % i] = str(_tag_values[i])
	for t in _text_specs:
		if t["key"] == "operator" and m.type in ["shift_left", "shift_right"]:
			t["text"] = ("«%d" if m.type == "shift_left" else "»%d") % int(m.params.get("n", 1))  # the live amount
			continue
		if t["key"] == "operator" and m.type == "cond_router":
			var op := str(m.params.get("op", ">"))
			t["text"] = "b%d" % int(m.params.get("k", 0)) if op == "bit" else op  # the live test
			continue
		if t["key"] == "dial" or t["key"] == "operator":
			continue  # static text
		var txt: String = vals.get(t["key"], "")
		t["text"] = txt
		if t["key"] == "bin":
			t["color"] = _bin_color
		elif t["key"] == "ro_value" and m.type == "terminal_output":
			t["color"] = _bin_color if _bin_color == Palette.STATE_ERROR else (Palette.FAMILY_IO if vm == ViewMode.Mode.CHAR else Palette.DATA_NUMBER)


func resolve_view_mode() -> int:
	if view_mode >= ViewMode.Mode.BIN:
		return view_mode
	if SimulationManager.view_mode >= ViewMode.Mode.BIN:
		return SimulationManager.view_mode
	var md := SimulationManager.mission
	for o in md.outputs if md != null else []:
		return int(o.get("view", ViewMode.Mode.BIN))
	return ViewMode.Mode.BIN


## Constants are amounts, not characters: under CHR they are shown as DEC.
static func const_mode(vm: int) -> int:
	return ViewMode.Mode.UDEC if vm == ViewMode.Mode.CHAR else vm


func _display_value(vm: int) -> String:
	var m := machine
	match m.type:
		"add":
			return "+" + ViewMode.format(BitVector.of(int(m.params.get("k", 0)), m.width), const_mode(vm))
		"modulo":
			return "%" + ViewMode.format(BitVector.of(int(m.params.get("k", 0)), m.width), const_mode(vm))
		"multiply":
			var k := int(m.params.get("k", 0))
			var sgn := "−" if k < 0 else ""
			return "×" + sgn + ViewMode.format(BitVector.of(abs(k), m.width), vm)
		"delay":
			return "%dt" % int(m.params.get("ticks", 3))
		"register":
			# the stored value (the initial value until the first write)
			var v: BitVector = m.memory[0] if not m.memory.is_empty() else BitVector.of(int(m.params.get("init", 0)), m.width)
			return ViewMode.format(v, vm)
		"program_counter":
			return str(m.counter if m.primed else int(m.params.get("start", 0)))
	return ""


func _readout_value(vm: int) -> String:
	if machine.type == "terminal_output":
		return _bin_value(null) if not machine.received.is_empty() else "—"
	var v := _display_value(vm)
	return v if v != "" else "0"


func _silk_text(_sim: Simulation) -> String:
	var m := machine
	match m.type:
		"input", "usb_input":
			var left := m.stream.size() - m.emitted
			var base := "USB" if m.type == "usb_input" else ""
			var cnt := " ×%d" % left if left > 0 else ""
			return base + cnt
		"output", "terminal_output":
			var total := 0
			var got := 0
			var run := SimulationManager.run
			if run != null and m.channel < run.def.outputs.size():
				total = run.def.outputs[m.channel]["expected"].size()
				if m.channel < run.progress.size():
					got = run.progress[m.channel]
			return "%d/%d" % [got, total]
		"splitter":
			return "DUP" if str(m.params.get("mode", "")) == "Duplicate" else "ALT"  # the live mode
		_:
			var ly := Art.layout(m.type)
			var sylk: Dictionary = _entry(ly, "silk")
			if not sylk.is_empty():
				return str(sylk.get("text", ""))
			return ""


func _bin_value(_sim: Simulation) -> String:
	if not machine.type in ["output", "terminal_output"] or machine.received.is_empty():
		return ""
	var last: Packet = machine.received[machine.received.size() - 1]
	var wrong := false
	var run := SimulationManager.run
	if run != null and run.status == MissionRun.Status.FAIL:
		wrong = int(run.failure.get("packet", -1)) == last.id
	elif run != null and machine.channel < run.last_ok.size():
		var lo: Dictionary = run.last_ok[machine.channel]
		wrong = int(lo.get("packet", -1)) == last.id and not bool(lo.get("ok", true))
	_bin_color = Palette.STATE_ERROR if wrong else (Palette.FAMILY_IO if last.is_raw() else Palette.DATA_NUMBER)
	return last.label(resolve_view_mode())


func _area_state(running: bool) -> String:
	var m := machine
	var st: int = m.state
	var busy := running and st in [Machine.State.PROCESSING, Machine.State.RECEIVING]
	match _area_kind:
		"Feed":
			var left := m.stream.size() - m.emitted
			if left <= 0:
				return "empty"
			return "feeding" if busy else "Idle"
		"Bin":
			var run := SimulationManager.run
			if run != null:
				if run.status == MissionRun.Status.FAIL and m.id in (run.failure.get("machines", []) as Array):
					return "error"
				if run.status == MissionRun.Status.PASS:
					return "ok"
				if m.channel < run.progress.size() and m.channel < run.def.outputs.size():
					if run.progress[m.channel] >= run.def.outputs[m.channel]["expected"].size():
						return "ok"
			return "Idle"
		"Split":
			# SplitWedge (bit_splitter / demux): Idle; LaneA while a job routed to the first
			# output (hi / a) is running or just emitted; LaneB for the second (lo / b);
			# bit_splitter sends to BOTH outputs, so it uses Dup. The classic splitter stays Dup.
			var split_on := running and st in [Machine.State.PROCESSING, Machine.State.RECEIVING, Machine.State.OUTPUT_READY]
			if not split_on:
				return _area_idle
			if m.type in ["demux", "cond_router"]:
				if (m.job.get("results", {}) as Dictionary).has("b") or (m.outq.has("b") and m.outq["b"] != null):
					return "laneb"
				return "lanea"
			return "dup"
		"Cells":
			# memory: the cells light for a write or a read while the operation runs
			if not busy:
				return _area_idle
			return "write" if m.last_mem_op == "write" else "read"
		_:
			if not busy:
				return _area_idle
			match _area_kind:
				"Die": return "processing"
				"Counter": return "tick"
				"Valve": return "open"
				"Merge": return "lanea"
				_:
					return "active"


func _port_state(pid: String, _running: bool) -> String:
	var sim := SimulationManager.sim
	if sim != null and sim.connection_at_port(machine.id, pid) != null:
		return "connected"
	return "idle"


## Edge-detect a port contact on a NEW simulation tick: when the port first becomes part of
## received_ports/sent_ports for sim.tick, stamp _contact_start so the L1 ring plays once.
func _update_contact(pid: String, sim: Simulation) -> void:
	if sim == null:
		return
	# D4 raw receptacle: Idle / Connected when wired / Active during the 120 ms contact
	# window (the rawPort Active ring itself is the L1 contact mark).
	var rp: RawPortView = _raw_ports.get(pid)
	if rp != null and machine.port_role(pid) == Catalog.ROLE_RAW:
		var rnow := Time.get_ticks_msec()
		if pid in machine.received_ports or pid in machine.sent_ports:
			if rp._seen_tick != sim.tick and (rp._start < 0 or rnow - rp._start >= PortContact.DURATION):
				rp._seen_tick = sim.tick
				rp._start = rnow
		else:
			rp._seen_tick = -1
		var ractive := rp._start >= 0 and rnow - rp._start <= PortContact.DURATION
		var rwired := sim.connection_at_port(machine.id, pid) != null
		rp.set_state("Active" if ractive else ("Connected" if rwired else "Idle"))
		return
	var ring: PortContact = _port_contact.get(pid)
	if ring == null:
		return
	var m := machine
	var now := Time.get_ticks_msec()
	if pid in m.received_ports or pid in m.sent_ports:
		# Retrigger at most once per ring duration: at 10× a busy port would otherwise flash
		# every 30 ms and read as a permanent glow (VFX ladder L1).
		if ring._seen_tick != sim.tick and (ring._start < 0 or now - ring._start >= PortContact.DURATION):
			ring._seen_tick = sim.tick
			ring._start = now
	else:
		ring._seen_tick = -1  # idle: next active tick retriggers
	# Redraw only while the 120 ms window is open (plus one frame to clear it).
	if ring._start >= 0 and now - ring._start <= PortContact.DURATION + 34:
		ring.queue_redraw()


## Glyph shown in a codec's token slot: the job's raw input while an encoder absorbs, or the
## produced raw value while a decoder emits (design/reference/systems_v1.js codec()).
func _update_codec_slot() -> void:
	var enc := machine.type in ["number_encoder", "char_encoder"]
	var glyph := ""
	var st := "Idle"
	if not machine.job.is_empty():
		var inp: Packet = machine.job.get("input")
		var res: Packet = machine.job.get("results", {}).get("out")
		if enc and inp != null and inp.is_raw():
			glyph = inp.raw.glyph()
			st = "Absorbing"
		elif not enc and res != null and res.is_raw():
			glyph = res.raw.glyph()
			st = "Emitting"
		# the job holds its input and its result from the start: the screen shows the pair
		if inp != null and res != null:
			_codec_slot.set_conversion(_codec_text(inp if enc else res), _codec_text(res if enc else inp))
	_codec_slot.set_data(enc, glyph, st)


## A codec value as the screen shows it: a raw glyph, or the bits as 0/1.
static func _codec_text(p: Packet) -> String:
	if p.is_raw():
		return p.raw.glyph()
	return ViewMode.format(p.data, ViewMode.Mode.BIN).replace(" ", "")


# ------------------------------------------------------------------ L1 port contact ring

## Procedural 1 px contact ring shown for ≤ 120 ms when a packet enters/exits a port (VFX
## ladder L1, STYLE_GUIDE §8). A child of the rotating Body so it follows the port sprite
## through rotation, and inherits the ghost alpha via the MachineView modulate cascade.
## Drawn only while the window is open; nothing after 120 ms.
class PortContact extends Node2D:
	const DURATION := 120.0
	const RADIUS := 10.0
	var bus := false
	var width := 0
	var _seen_tick := -1
	var _start := -1
	var _style: StyleBoxFlat

	func _draw() -> void:
		if _start < 0:
			return
		var el := float(Time.get_ticks_msec() - _start)
		if el >= DURATION:
			return
		var col: Color
		if el < 40.0:
			col = Color(Palette.TEXT_PRIMARY, 0.8)
		else:
			var base := Palette.datatype(width)
			var a := 0.55
			if el >= 80.0:
				a = 0.55 * (1.0 - (el - 80.0) / 40.0)
			col = Color(base, a)
		if bus:
			# BusPort slot: 1 px rounded-rect ring 21×21, corner 5.
			if _style == null:
				_style = StyleBoxFlat.new()
				_style.bg_color = Color(0, 0, 0, 0)
				_style.set_border_width_all(1)
				_style.set_corner_radius_all(5)
			_style.content_margin_left = 0.0
			_style.content_margin_top = 0.0
			_style.content_margin_right = 0.0
			_style.content_margin_bottom = 0.0
			_style.border_color = col
			draw_style_box(_style, Rect2(Vector2(-10.5, -10.5), Vector2(21, 21)))
		else:
			draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, col, 1.0, true)


# ------------------------------------------------------------------ D4 procedural systems

## A raw receptacle (24x24) drawn procedurally with SystemsDraw.raw_port at the port anchor.
## `dir` is the catalog direction ("in"/"out"), `state` Idle | Connected | Active.
class RawPortView extends Node2D:
	var dir := "out"
	var state := "Idle"
	var _seen_tick := -1
	var _start := -1
	var _drawn := ""

	func set_state(s: String) -> void:
		if s != _drawn:
			_drawn = s
			state = s
			queue_redraw()

	func _draw() -> void:
		SystemsDraw.raw_port(self, Vector2(-12, -12), dir, state)


## Codec token slot (D4): 26x18 r9 pill at x 14 (encoder) / 88 (decoder) y 23 with the glyph
## of the value being processed, plus the silk chevron at x 45 / 75.
class CodecSlot extends Node2D:
	var enc := true
	var glyph := ""
	var state := "Idle"
	var raw := ""   # the last conversion, kept on the screen: raw glyph ↔ bits
	var bits := ""

	func set_conversion(r: String, b: String) -> void:
		if r == raw and b == bits:
			return
		raw = r
		bits = b
		queue_redraw()

	func set_data(e: bool, g: String, s: String) -> void:
		if e == enc and g == glyph and s == state:
			return
		enc = e
		glyph = g
		state = s
		queue_redraw()

	func _draw() -> void:
		var slot_x := 14.0 if enc else 88.0
		var chev_x := 45.0 if enc else 75.0
		var pill := Rect2(slot_x, 23, 26, 18)
		SystemsDraw.rrect(self, pill, 9.0, Palette.MACHINE_SCREEN)
		SystemsDraw.rrect_outline(self, pill, 9.0, Color(Palette.FAMILY_IO, 0.55), 1.0)
		if state != "Idle" and glyph != "":
			var col := Color(Palette.FAMILY_IO, 0.5 if state == "Absorbing" else 1.0)
			SystemsDraw.text_center(self, Rect2(slot_x, 24, 26, 16), glyph, 10.0 if glyph.length() > 1 else 12.0, col)
		var chev := PackedVector2Array([Vector2(chev_x + 1, 28), Vector2(chev_x + 5, 32), Vector2(chev_x + 1, 36)])
		draw_polyline(chev, Color(Palette.MATERIAL_SILK, 0.5), 1.5, true)
		_draw_screen()

	## The bottom row: a conversion screen, RAW → BITS (encoder) or BITS → RAW (decoder), showing
	## the last value the codec turned so the player can read what it does.
	func _draw_screen() -> void:
		var plate := Rect2(2, 66, 124, 60)
		SystemsDraw.rrect(self, plate, 6.0, Palette.MATERIAL_PLATE_LO)
		SystemsDraw.rrect_outline(self, plate, 6.0, Palette.MACHINE_FRAME, 1.5)
		var scr := Rect2(8, 72, 112, 48)
		SystemsDraw.rrect(self, scr, 4.0, Palette.MACHINE_SCREEN)
		SystemsDraw.rrect_outline(self, scr, 4.0, Palette.MATERIAL_FRAME, 1.0)
		var on := state != "Idle"
		var a := 1.0 if on else 0.6
		var raw_box := Rect2(12, 82, 34, 34) if enc else Rect2(82, 82, 34, 34)
		var bit_box := Rect2(46, 82, 70, 34) if enc else Rect2(12, 82, 70, 34)
		SystemsDraw.text_center(self, Rect2(raw_box.position.x, 73, raw_box.size.x, 10), "RAW", 7.0, Color(Palette.MATERIAL_SILK, 0.55))
		SystemsDraw.text_center(self, Rect2(bit_box.position.x, 73, bit_box.size.x, 10), "BITS", 7.0, Color(Palette.MATERIAL_SILK, 0.55))
		if raw == "":
			SystemsDraw.text_center(self, Rect2(12, 82, 104, 34), "—", 12.0, Color(Palette.MATERIAL_SILK, 0.4))
			return
		SystemsDraw.text_center(self, raw_box, raw, 20.0 if raw.length() <= 2 else 12.0, Color(Palette.FAMILY_IO, a))
		var fs := 13.0 if bits.length() <= 5 else (11.0 if bits.length() <= 8 else 7.0)
		SystemsDraw.text_center(self, bit_box, bits, fs, Color(Palette.DATA_NUMBER, a))
		# the direction of the conversion
		var cx := 46.0 if enc else 82.0
		var arrow := PackedVector2Array([Vector2(cx - 3, 94), Vector2(cx + 1, 99), Vector2(cx - 3, 104)])
		draw_polyline(arrow, Color(Palette.MATERIAL_SILK, 0.6 * a), 1.5, true)


## USB socket overlay (D4): the female port face + the plugged data module, with the MOTION §8
## plug/unplug motion. Reads only machine.device / gen_seq / sent_ports.
class UsbSocketView extends Node2D:
	const PLUG_S := 0.18
	const UNPLUG_S := 0.16
	var machine: Machine
	var hovered := false
	var _prev := ""
	var _started := false
	var _anim_start := -1.0
	var _anim_plug := true
	var _anim_device := ""
	var _offset := 0.0
	var _alpha := 1.0
	var _cursor := -1
	var _lit := false

	func refresh() -> void:
		var dev: String = machine.device
		if not _started:
			_started = true
			_prev = dev
			if dev != "":
				_anim_device = dev
		if dev != _prev:
			_anim_device = dev if dev != "" else _prev
			_anim_plug = dev != ""
			_anim_start = Time.get_ticks_msec() / 1000.0
			_prev = dev
		var now := Time.get_ticks_msec() / 1000.0
		if _anim_start >= 0.0:
			var dur := PLUG_S if _anim_plug else UNPLUG_S
			var el := now - _anim_start
			if el >= dur:
				_offset = 0.0
				_alpha = 1.0
				_anim_start = -1.0
				if not _anim_plug:
					_anim_device = ""
			else:
				var t := _ease_out(el / dur)
				if _anim_plug:
					_offset = -44.0 * (1.0 - t)
					_alpha = 1.0
				else:
					_offset = -48.0 * t
					_alpha = 1.0 - 0.5 * t
		_lit = "out" in machine.sent_ports
		_cursor = (machine.gen_seq - 1) % 30 if _lit else -1
		queue_redraw()

	func _ease_out(t: float) -> float:
		var c := clampf(t, 0.0, 1.0)
		return 1.0 - pow(1.0 - c, 3.0)

	func _draw() -> void:
		SystemsDraw.hub_bay(self, false)
		var face := SystemsDraw.HUB_FACE_IN
		var at := SystemsDraw.HUB_STICK_IN
		if not machine.socket:
			# a mission's USB input: its stick is fixed (it carries the mission's stream)
			SystemsDraw.data_module(self, at, "bit", {"inserted": true, "cursor": _cursor, "glyph": _mission_glyph(), "acc": Palette.DATA_NUMBER})
			SystemsDraw.port_face(self, face, true, _lit, false)
			return
		var plugged := machine.device != "" or (_anim_start >= 0.0 and not _anim_plug)
		if _anim_device != "":
			var lr = SimulationManager.run
			SystemsDraw.data_module(self, at + Vector2(_offset, 0), _anim_device, DeskView.stick_opts(
				lr as LabRun if lr is LabRun else null, _anim_device, {"inserted": true, "cursor": _cursor, "alpha": _alpha}))
		elif hovered and machine.device == "":
			SystemsDraw.data_module(self, at, "bit", {"ghost": true})
			SystemsDraw.rrect_outline(self, Rect2(face - Vector2(2, 2), Vector2(20, 40)), 3.0, Color(Palette.STATE_HOVER, 0.8), 1.0)
		SystemsDraw.port_face(self, face, plugged, _lit, false)

	func _mission_glyph() -> String:
		if machine.stream.is_empty():
			return ""
		var v = machine.stream[0]
		var g := str(v) if v is BitVector else (str(v.glyph()) if v is Object and v.has_method("glyph") else "")
		return g.substr(0, 5)


## Locked USB Output contract drive (D4, lab only): flipped port face + job module showing the
## requested value / fill progress, the accept/reject seam flash and the complete frame.
class ContractDriveView extends Node2D:
	const SEAM_S := 0.15
	const PULSE_S := 0.2
	var machine: Machine
	var _flash_start := -1.0
	var _flash_ok := true
	var _underline := false
	var _last_tick := -1
	var _last_lct := -100000
	var _lct_start := -1.0

	func refresh() -> void:
		var run = SimulationManager.run
		if run == null or not run.has_method("request_bits"):
			return
		var sim := SimulationManager.sim
		if sim != null and sim.tick != _last_tick:
			_last_tick = sim.tick
			for e in sim.events:
				if str(e.get("kind", "")) == "output" and int(e.get("machine", -1)) == machine.id and (not machine.socket or Devices.is_job(machine.device)):
					_flash_start = Time.get_ticks_msec() / 1000.0
					_flash_ok = bool((run.last_ok[0] as Dictionary).get("ok", true)) if run.last_ok.size() > 0 else true
					_underline = not _flash_ok
		var lct := int(run.level_completed_tick)
		if lct != _last_lct:
			_last_lct = lct
			if lct >= 0:
				_lct_start = Time.get_ticks_msec() / 1000.0
		queue_redraw()

	## The Monitor shows the last value it received (in the HUD view mode) + a 10-sample history.
	func _draw_monitor() -> void:
		var vals: Array = machine.received
		var value := ""
		var hist := []
		var raw := false
		for p in vals:
			var pk: Packet = p
			if pk.is_raw():
				raw = true
				hist.append(0.5)
			else:
				var w := maxi(pk.data.width, 1)
				hist.append(float(pk.data.unsigned()) / float((1 << mini(w, 16)) - 1) if w > 0 else 0.0)
		if not vals.is_empty():
			var last: Packet = vals[vals.size() - 1]
			var vm: int = SimulationManager.view_mode if SimulationManager.view_mode >= 0 else ViewMode.Mode.BIN
			value = last.label(vm) if last.is_raw() else ViewMode.format(last.data, vm).replace(" ", "")
			if value.length() > 8:
				value = value.substr(0, 8)
		SystemsDraw.monitor(self, SystemsDraw.HUB_STICK_OUT, value, hist, Palette.FAMILY_IO if raw else Palette.DATA_NUMBER, {"inserted": true})

	var _glyph_q := -1
	var _glyph_cache := ""

	func _glyph(run) -> String:
		if run.has_method("request_label"):
			var lbl = run.request_label()
			if lbl is String and lbl != "" and lbl.length() <= 5:
				return lbl
		var g: String = ViewMode.format(run.request_bits(), run.view_mode()).replace(" ", "")
		return g.substr(0, 5) if g.length() > 5 else g

	func _draw() -> void:
		var run = SimulationManager.run
		if run == null or not run.has_method("request_bits"):
			return
		var now := Time.get_ticks_msec() / 1000.0
		var accent: Color = Palette.FAMILY_IO if run.view_mode() == ViewMode.Mode.CHAR else Palette.DATA_NUMBER
		var fill := 0.0
		if run.has_method("request_count") and run.request_count() > 0:
			fill = clampf(float(run.delivered) / float(run.request_count()), 0.0, 1.0)
		var glyph := _glyph(run)
		var tag := ""
		var done := false
		if run is LabRun and not run.all_done():
			# a drive shows the quest it served last: its request, its progress, "Q6"
			var q: int = run.quest_for_drive(machine.id)
			fill = run.quest_fill(q)
			done = run.quest_progress(q).filled
			tag = "Q%d" % (q + 1)
			if q != _glyph_q:
				_glyph_q = q
				var g := ViewMode.format(LabDef.request_bits(q), LabDef.view_mode(q)).replace(" ", "")
				_glyph_cache = g.substr(0, 5) if g.length() > 5 else g
			glyph = _glyph_cache
			accent = Palette.FAMILY_IO if LabDef.view_mode(q) == ViewMode.Mode.CHAR else Palette.DATA_NUMBER
		var dev: String = machine.device if machine.socket else "job"
		SystemsDraw.hub_bay(self, true)
		SystemsDraw.port_face(self, SystemsDraw.HUB_FACE_OUT, dev != "", false, true)
		if dev == "monitor":
			_draw_monitor()
			return
		if not Devices.is_job(dev):
			return  # an empty output port: nothing is there (wires into it stall)
		var at := SystemsDraw.HUB_STICK_OUT
		SystemsDraw.data_module(self, at, "job", {
			"flip": true, "inserted": true, "glyph": glyph, "fill": fill, "acc": accent, "tag": tag, "done": done,
		})
		if _flash_start >= 0.0:
			if now - _flash_start < SEAM_S:
				draw_line(at + Vector2(0, 10), at + Vector2(0, 42), Color(Palette.STATE_VALID if _flash_ok else Palette.STATE_BLOCKED, 0.9), 1.5, true)
				if _underline:
					draw_rect(Rect2(18, 44, 80, 1.5), Color(Palette.STATE_BLOCKED, 0.9))
			else:
				_flash_start = -1.0
		if _lct_start >= 0.0:
			var el := now - _lct_start
			if el < PULSE_S * 2.0:
				var a := absf(sin(PI * el / PULSE_S))
				SystemsDraw.rrect_outline(self, Rect2(at - Vector2(2, 2), Vector2(100, 60)), 6.0, Color(Palette.STATE_SUCCESS, a), 1.5)
			else:
				SystemsDraw.rrect_outline(self, Rect2(at - Vector2(2, 2), Vector2(100, 60)), 6.0, Palette.STATE_SUCCESS, 1.5)
				_lct_start = -1.0


# ------------------------------------------------------------------ upright text

class UprightText extends Node2D:
	## Draws the parent MachineView's upright text records (root-space positions) so text
	## never rotates with the body and stays on top of it. Reads the parent's _text_specs
	## directly (it is populated by MachineView.refresh() every frame).

	func _draw() -> void:
		var mv := get_parent() as MachineView
		if mv == null:
			return
		var f := TclTheme.font("ExtraBold")
		for t in mv._text_specs:
			var txt: String = t.get("text", "")
			if txt == "":
				continue
			var base := Vector2(t["pos"].x, t["pos"].y + f.get_ascent(t["size"]))
			if t.has("height"):  # vertically centred in a box (e.g. the Output bin)
				var h: float = f.get_ascent(t["size"]) + f.get_descent(t["size"])
				base.y = t["pos"].y + (float(t["height"]) - h) / 2.0 + f.get_ascent(t["size"])
			draw_string(f, base, txt, t["align"], t["width"], t["size"], t["color"])


# ------------------------------------------------------------------ resource indicators

## Tiny geometry on the chassis (STYLE_GUIDE §3 / design/reference/systems_v1.js `RI`, `RIs`
## — ported 1:1): clock dots (one per tick of job cost, up to 6, then a '+'), gold power pips
## (up to 4), a divider, and clock-mode chevrons. A child of the rotating Body so it rotates
## with the chassis; it is all vector geometry so it needs no upright layer. Hidden at far zoom
## by the parent (same visibility rule the old stats silk had).
class ResourceIndicators extends Node2D:
	var ticks := 0
	var power := 0
	var mode := "normal"  # "normal" / "fast" / "overclocked"
	var compact := false  # S-size machines use the compact form
	var xr := 0.0  # right anchor x in body-local px
	var y := 0.0  # top y in body-local px

	func set_data(t: int, p: int, m: String) -> void:
		if t == ticks and p == power and m == mode:
			return
		ticks = t
		power = p
		mode = m
		queue_redraw()

	func _draw() -> void:
		var silk := Color(Palette.MATERIAL_SILK, 0.7)
		var divider := Color(Palette.MATERIAL_SILK, 0.25)
		var gold := Color(Palette.MATERIAL_GOLD, 0.9)
		var dots := mini(ticks, 6)
		var plus := ticks > 6
		var pips := mini(power, 4)
		if compact:
			_draw_compact(silk, divider, gold, dots, plus, pips)
		else:
			_draw_full(silk, divider, gold, dots, plus, pips)

	func _draw_full(silk: Color, divider: Color, gold: Color, dots: int, plus: bool, pips: int) -> void:
		var chev := 1 if mode == "fast" else (2 if mode == "overclocked" else 0)
		var w := chev * 6 + (2 if chev > 0 else 0) + dots * 6 + (4 if plus else 0) + 6 + (pips * 5 if power > 0 else 5)
		var x := xr - w
		for i in chev:
			draw_polyline(PackedVector2Array([Vector2(x + 1, y + 1), Vector2(x + 4, y + 4), Vector2(x + 1, y + 7)]), Color(Palette.STATE_BLOCKED, 1.0), 1.5, true)
			x += 6
		if chev > 0:
			x += 2
		for i in dots:
			draw_circle(Vector2(x + 2.5, y + 4.0), 2.5, silk)
			x += 6
		if plus:
			draw_rect(Rect2(x, y + 3.5, 3, 1), silk)
			draw_rect(Rect2(x + 1, y + 2.5, 1, 3), silk)
			x += 4
		x += 3
		draw_rect(Rect2(x, y + 1, 1, 6), divider)
		x += 3
		if power == 0:
			draw_rect(Rect2(x, y + 1, 3, 6), Color(Palette.MATERIAL_SILK, 0.35), false, 0.75)
		for i in pips:
			draw_rect(Rect2(x, y, 3, 8), gold)
			x += 5

	func _draw_compact(silk: Color, divider: Color, gold: Color, dots: int, plus: bool, pips: int) -> void:
		var x := xr - (dots * 4 + 5 + pips * 3.5)
		for i in dots:
			draw_circle(Vector2(x + 1.5, y + 3.0), 1.5, silk)
			x += 4
		x += 2
		draw_rect(Rect2(x, y + 1, 1, 4), divider)
		x += 3
		for i in pips:
			draw_rect(Rect2(x, y, 2, 6), gold)
			x += 3.5


## Processing progress, continuous between ticks: (total − ticks_left + tick fraction) / total
## while a job runs; 100% held through the completing tick, then faded out.
func _update_progress() -> void:
	if _progress == null or ghost:
		return
	var m := machine
	var sim := SimulationManager.sim
	var t: float = clampf(SimulationManager.alpha, 0.0, 1.0) if SimulationManager.running else 1.0
	var p := -1.0
	var alpha := 1.0
	var completed_now := false
	if sim != null:
		for e in sim.events:
			if str(e.get("kind", "")) == "complete" and int(e.get("machine", -1)) == m.id:
				completed_now = true
	if completed_now and t < DONE_HOLD:
		p = 1.0  # a job finished this tick: show it complete before the next one fills
	elif not m.job.is_empty():
		# work units (clock / brownout / heat change the rate); at the normal clock this equals
		# the old (total − ticks_left + t) / total
		var total := maxf(float(m.job.get("work_total", 1)), 1.0)
		var left := float(m.job.get("work_left", total))
		p = clampf((total - left + float(m.last_rate) * t) / total, 0.0, 1.0)
	elif completed_now:
		p = 1.0
		alpha = 1.0 - t  # nothing queued: full, fading out towards the next tick
	_progress.set_progress(p, alpha)


## ActivityArea progress indicator (canonical: "Die/Dial progress tweened"). Dial areas get an
## arc filling clockwise from 12 o'clock around the dial ring; other areas a 2 px fill line
## along the inside bottom edge of the area. DATA_NUMBER on a MATERIAL_VENT track.
class ProcessProgress extends Node2D:
	const RING_R := 17.0
	const RING_W := 2.5
	const BAR_W := 3.0
	var center := Vector2.ZERO
	var dial := false
	var area_rect := Rect2()
	var chassis := Rect2()  # machines without an activity area get their bar along its bottom
	var _p := -1.0
	var _a := 1.0

	func set_progress(p: float, a: float) -> void:
		if absf(p - _p) > 0.001 or absf(a - _a) > 0.01:
			_p = p
			_a = a
			queue_redraw()

	func _draw() -> void:
		if _p < 0.0:
			return
		var fill := Color(Palette.DATA_NUMBER, _a)
		if dial:
			draw_arc(center, RING_R, 0.0, TAU, 48, Color(Palette.MATERIAL_VENT, 0.9 * _a), RING_W, true)
			if _p > 0.0:
				draw_arc(center, RING_R, -PI / 2.0, -PI / 2.0 + TAU * _p, maxi(4, int(48 * _p)), fill, RING_W, true)
		else:
			# every other machine: a 3 px bar — inside its activity area's bottom edge, or along
			# the inside bottom of the chassis when it has no area (register, ALU, gates …)
			var y: float
			var x0: float
			var w: float
			if area_rect.size.x > 0.0:
				y = area_rect.end.y - 3.0
				x0 = area_rect.position.x + 4.0
				w = area_rect.size.x - 8.0
			elif chassis.size.x > 0.0:
				y = chassis.end.y - 6.0
				x0 = chassis.position.x + 12.0
				w = chassis.size.x - 24.0
			else:
				return
			draw_line(Vector2(x0, y), Vector2(x0 + w, y), Color(Palette.MATERIAL_VENT, 0.9 * _a), BAR_W, true)
			if _p > 0.0:
				draw_line(Vector2(x0, y), Vector2(x0 + w * _p, y), fill, BAR_W, true)


## Heat stage strip (STYLE_GUIDE §14.8, systems_v1.js): a 2 px bar at (8, 3, w-16) inside the
## chassis top edge. WARM amber α .3 · HOT amber · THROTTLING amber pulsing α .35↔1 over 1.2 s ·
## CRITICAL red + 1.5 px red frame + the pause badge (pulses twice on entry). Stage changes
## cross-fade over 200 ms. The body is never tinted.
class ThermalStrip extends Node2D:
	const FADE := 0.2
	const PULSE := 1.2
	var size := Vector2(128, 64)
	var _stage := 0
	var _alpha := 0.0  # cross-fade of the current look (0 → 1)
	var _prev := 0
	var _t := 0.0  # seconds in the current stage

	func refresh(stage: int, delta: float) -> void:
		if stage != _stage:
			_prev = _stage
			_stage = stage
			_alpha = 0.0
			_t = 0.0
		_t += delta
		_alpha = minf(1.0, _alpha + delta / FADE)
		if _stage == ThermalGrid.Stage.NORMAL and _alpha >= 1.0 and _prev == _stage:
			if visible:
				visible = false
			return
		visible = true
		if _alpha >= 1.0:
			_prev = _stage
		queue_redraw()

	func _look(stage: int) -> Color:
		match stage:
			ThermalGrid.Stage.WARM: return Color(Palette.STATE_BLOCKED, 0.3)
			ThermalGrid.Stage.HOT: return Palette.STATE_BLOCKED
			ThermalGrid.Stage.THROTTLING:
				var ph := 0.5 - 0.5 * cos(_t / PULSE * TAU)
				return Color(Palette.STATE_BLOCKED, lerpf(1.0, 0.35, ph))
			ThermalGrid.Stage.CRITICAL: return Palette.STATE_ERROR
		return Color(Palette.STATE_BLOCKED, 0.0)

	func _draw() -> void:
		var bar := Rect2(8, 3, size.x - 16, 2)
		var a := _look(_prev)
		var b := _look(_stage)
		var c := b if _alpha >= 1.0 else Color(a.lerp(b, _alpha), lerpf(a.a, b.a, _alpha))
		if c.a > 0.0:
			SystemsDraw.rrect(self, bar, 1.0, c)
		if _stage == ThermalGrid.Stage.CRITICAL:
			# frame + badge pulse twice (2 × 400 ms) on entry, then hold
			var k := 1.0
			if _t < 0.8:
				k = lerpf(0.45, 1.0, 0.5 + 0.5 * cos(_t / 0.4 * TAU))
			var red := Color(Palette.STATE_ERROR, k * minf(1.0, _alpha * 2.0))
			SystemsDraw.rrect_outline(self, Rect2(Vector2(0.75, 0.75), size - Vector2(1.5, 1.5)), 7.0, red, 1.5)
			var badge := Rect2(size.x - 12, -10, 16, 16)
			SystemsDraw.rrect(self, badge, 3.0, red)
			var inv := Color(Palette.TEXT_INVERSE, red.a)
			draw_rect(Rect2(badge.position + Vector2(4, 4), Vector2(2, 8)), inv)
			draw_rect(Rect2(badge.position + Vector2(10, 4), Vector2(2, 8)), inv)


## Thermal family hardware (STYLE_GUIDE §14.7, MOTION_SYSTEM §8): heatsink / radiator fin warmth
## from their tiles' stage; the blower impeller turns at 1 turn/s while the run plays (2 when a
## tile it cools is HOT or worse) and eases out over 400 ms; a heat pipe draws its conduit
## towards linked pipes with pads on its open axis ends, warmth smoothed over 500 ms.
class ThermalPartView extends Node2D:
	var machine: Machine
	var _spin := 0.0
	var _speed := 0.0  # turns per second
	var _level := 0  # blower: 0 idle · 1 running · 2 high load; heatsink/radiator: warmth 0..2
	var _warmth := 0.0  # heat pipe, smoothed 0..1
	var _links: Array = []
	var _pads: Array = []

	func setup(m: Machine) -> void:
		machine = m
		if m.type != "heat_pipe":
			return
		var sim := SimulationManager.sim
		var horiz := m.rot % 2 == 0
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var along: bool = (d.x != 0) == horiz
			var n: Machine = sim.machine_at(m.cell + d) if sim != null else null
			var linked: bool = n != null and n.type == "heat_pipe" and (along or ((d.x != 0) == (n.rot % 2 == 0)))
			if linked:
				_links.append(d)
			elif along:
				_pads.append(d)

	func refresh(delta: float) -> void:
		var sim := SimulationManager.sim
		var th: ThermalGrid = sim.thermal if sim != null else null
		match machine.type:
			"blower":
				var lvl := 0
				if SimulationManager.running and sim != null and sim.work_rate(machine) > 0:
					lvl = 1
					if th != null and _covered_max(th, 2) >= int(ThermalGrid.ENTER[ThermalGrid.Stage.HOT]):
						lvl = 2
				var target := float(lvl)
				_speed = target if target > _speed else move_toward(_speed, target, delta / 0.4)
				if _speed > 0.0 or lvl != _level:
					_level = lvl
					_spin = fmod(_spin + _speed * TAU * delta, TAU)
					queue_redraw()
			"heat_pipe":
				var goal := 0.0
				if th != null:
					goal = clampf(float(th.at(machine.cell) - 250) / 500.0, 0.0, 1.0)
				var w := move_toward(_warmth, goal, delta / 0.5)
				if absf(w - _warmth) > 0.001:
					_warmth = w
					queue_redraw()
			_:
				var lvl2 := 0
				if th != null:
					var st := ThermalGrid.stage_for(th.machine_temp(machine), 0)
					lvl2 = 0 if st == ThermalGrid.Stage.NORMAL else (1 if st == ThermalGrid.Stage.WARM else 2)
				if lvl2 != _level:
					_level = lvl2
					queue_redraw()

	func _covered_max(th: ThermalGrid, r: int) -> int:
		var hi := 0
		var s := Catalog.size_of(machine.type, machine.rot)
		for y in range(machine.cell.y - r, machine.cell.y + s.y + r):
			for x in range(machine.cell.x - r, machine.cell.x + s.x + r):
				hi = maxi(hi, th.at(Vector2i(x, y)))
		return hi

	func _draw() -> void:
		match machine.type:
			"heatsink": SystemsDraw.heatsink(self, Vector2.ZERO, _level)
			"blower": SystemsDraw.blower(self, Vector2.ZERO, _spin, _level)
			"radiator": SystemsDraw.radiator(self, Vector2.ZERO, _level)
			"heat_pipe": SystemsDraw.heat_pipe(self, Vector2.ZERO, _links, _pads, _warmth)

