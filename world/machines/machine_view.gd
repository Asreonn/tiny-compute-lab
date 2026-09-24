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
var _led: Sprite2D
var _led_rel := ""
var _overlays := {}  # name -> Sprite2D
var _port_nodes := {}  # port id -> Sprite2D
var _port_bus := {}  # port id -> bool
var _port_dir := {}  # port id -> "in"/"out"/"ctrl"
var _port_w := {}  # port id -> int
var _port_contact := {}  # port id -> PortContact (L1 contact ring node)
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

	# 1 InstallPad · 2 Shell (ghosts skip the pad; the tools draw the placement pad under them)
	if not ghost:
		body.add_child(Art.sprite(Art.pad_file("default", _size_key), Vector2.ZERO))
	body.add_child(Art.sprite(str(fm.get("asset", "machine/shell_%s.svg" % _size_key)), Vector2.ZERO))
	# 3 FamilyTab
	var tab: Variant = ly.get("tab", [0, 0])
	body.add_child(Art.sprite(Art.tab_file(str(m.def()["family"])), _v(tab) if tab is Array and not tab.is_empty() else Vector2.ZERO))
	# 4 ActivityArea (idle state; the roadmap schema stores `areas[]`)
	var area: Dictionary = _entry(ly, "area")
	if area.is_empty() and ly.get("areas", null) is Array and not (ly["areas"] as Array).is_empty():
		var a0: Variant = (ly["areas"] as Array)[0]
		area = a0 if a0 is Dictionary else {}
	if not area.is_empty():
		_area_kind = str(area.get("kind", "Dial"))
		_area_idle = str(area.get("idle", "Idle"))
		_area = Art.sprite(Art.area_file(_area_kind, _area_idle), _v(area.get("pos", [0, 0])))
		_area.name = "ActivityArea"
		body.add_child(_area)
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
	# 12 upright text layer
	# 12a processing progress (ActivityArea progress, docs/MOTION_SYSTEM.md): rotates with the body
	_progress = ProcessProgress.new()
	_progress.name = "ProcessProgress"
	_progress.center = core_local()
	_progress.dial = _area_kind == "Dial"
	var asz := Art.area_size(_area_kind)
	_progress.area_rect = Rect2(_progress.center - asz * 0.5, asz) if asz != Vector2.ZERO else Rect2()
	body.add_child(_progress)
	text_layer = UprightText.new()
	text_layer.name = "UprightText"
	add_child(text_layer)
	_build_texts(ly, area, disp, ro)


func _build_width_tags(ly: Dictionary) -> void:
	_tag_values.clear()
	_tag_ports.clear()
	_tag_fallback.clear()
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
		elif machine.type == "bit_splitter" and i < cports.size():
			# The BusSplitter kit's tags sit at ports in / hi / lo; tag i shows the CURRENT
			# width of port i (machine.port_width), refreshed on param changes — not the
			# layout's placeholder numbers.
			port_id = str(cports[i]["id"])
			w = machine.port_width(port_id)
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
		else:
			var c := Art.sprite(rel, pos)
			c.name = "WidthTag%d" % i
			body.add_child(c)
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
	# Machine stats silk (player request 2026-09-24; STYLE_GUIDE §3 exception): tick cost and
	# power as silkscreen (8 px, 55 % silk) in the bottom-right corner zone, right-aligned at
	# (W − 24, H − 15) — one S-gap clear of the chassis corner screw — on player machines only
	# (mission I/O is fixed and costs nothing).
	if not machine.locked:
		var base := Vector2(Catalog.SIZES[machine.def()["size"]]) * T
		_text_specs.append({
			"key": "stats", "pos": _upright(Vector2(base.x - 24.0, base.y - 15.0), off, rot),
			"width": 0.0, "size": 8.0, "align": HORIZONTAL_ALIGNMENT_RIGHT,
			"color": Color(Palette.MATERIAL_SILK, SILK_ALPHA), "text": "",
			"ticks": machine.processing_ticks(), "power": machine.power(),
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
	# LED from machine state
	var led_name: String = MACHINE_STATE_LED[m.state]
	if _led != null and led_name != _led_rel:
		_led.texture = Art.tex(Art.led_file(led_name))
		_led_rel = led_name
	# Activity area variant
	if _area != null:
		var rel := Art.area_file(_area_kind, _area_state(running))
		var t := Art.tex(rel)
		if _area.texture != t:
			_area.texture = t
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
	# Upright texts
	_update_texts(sim, running)
	text_layer.queue_redraw()


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
		if t["key"] == "dial" or t["key"] == "stats":
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
			if m.type == "demux":
				if m.job.has("b") or (m.outq.has("b") and m.outq["b"] != null):
					return "laneb"
				return "lanea"
			return "dup"
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
	var ring: PortContact = _port_contact.get(pid)
	if ring == null or sim == null:
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
		var cam := get_viewport().get_camera_2d()
		var far := cam != null and cam.zoom.x < Palette.ZOOM_FAR_BELOW
		for t in mv._text_specs:
			if t["key"] == "stats":
				if not far:
					_draw_stats(f, t)
				continue
			var txt: String = t.get("text", "")
			if txt == "":
				continue
			var base := Vector2(t["pos"].x, t["pos"].y + f.get_ascent(t["size"]))
			if t.has("height"):  # vertically centred in a box (e.g. the Output bin)
				var h: float = f.get_ascent(t["size"]) + f.get_descent(t["size"])
				base.y = t["pos"].y + (float(t["height"]) - h) / 2.0 + f.get_ascent(t["size"])
			draw_string(f, base, txt, t["align"], t["width"], t["size"], t["color"])

	## "[clock] 4  [power] 1" right-aligned at pos (top of the text box): the HUD's own
	## latency/power icons at 9 px, tinted like the silk text.
	func _draw_stats(f: Font, t: Dictionary) -> void:
		var size := int(t["size"])
		var col: Color = t["color"]
		var asc := f.get_ascent(size)
		var items := [["icon_latency", str(t["ticks"])], ["icon_power", str(t["power"])]]
		var x: float = t["pos"].x
		var y: float = t["pos"].y
		for k in range(items.size() - 1, -1, -1):
			var txt: String = items[k][1]
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			x -= w
			draw_string(f, Vector2(x, y + asc), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			x -= 10.0
			var tex := Art.icon(items[k][0])
			if tex != null:
				draw_texture_rect(tex, Rect2(Vector2(x, y + 0.5), Vector2(9, 9)), false, col)
			x -= 6.0


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
		var total := maxf(float(m.job.get("total", 1)), 1.0)
		var left := float(m.job.get("ticks_left", total))
		p = clampf((total - left + t) / total, 0.0, 1.0)
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
	var center := Vector2.ZERO
	var dial := false
	var area_rect := Rect2()
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
		elif area_rect.size.x > 0.0:
			var y := area_rect.end.y - 3.0
			var x0 := area_rect.position.x + 4.0
			var w := area_rect.size.x - 8.0
			draw_line(Vector2(x0, y), Vector2(x0 + w, y), Color(Palette.MATERIAL_VENT, 0.9 * _a), 2.0, true)
			draw_line(Vector2(x0, y), Vector2(x0 + w * _p, y), fill, 2.0, true)

