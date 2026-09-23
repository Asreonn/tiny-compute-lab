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

const MACHINE_STATE_LED := ["idle", "receiving", "processing", "outputready", "blocked", "error", "off"]

var machine: Machine
var hovered := false
var selected := false
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
var _tag_values: Array = []  # width shown by each width tag (upright text)
var _text_specs: Array = []  # {key, pos, width, size, align, color, text}
var _bin_color := Palette.DATA_NUMBER


func setup(m: Machine) -> MachineView:
	machine = m
	name = "Machine_%d" % m.id
	_size_key = str(m.def()["size"]).to_lower()
	_build()
	position = Vector2(m.cell) * T
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

	# 1 InstallPad · 2 Shell
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
	for name in ["processing", "outputready", "blocked", "error", "hover", "selected"]:
		var s := Art.sprite(Art.state_file(name, _size_key), Vector2.ZERO)
		s.modulate.a = 0.0
		_overlays[name] = s
		body.add_child(s)
	# 12 upright text layer
	text_layer = UprightText.new()
	text_layer.name = "UprightText"
	add_child(text_layer)
	_build_texts(ly, area, disp, ro)


func _build_width_tags(ly: Dictionary) -> void:
	_tag_values.clear()
	var tags: Array = ly.get("width_tags", [])
	if tags == null:
		tags = []
	if machine.type == "output":
		# The Output wears one tag of its width, one S-gap right of its family tab (16..40).
		tags = [{"width": str(machine.width), "pos": [48.0, 4.0]}]
	var i := 0
	for tag in tags:
		if not (tag is Dictionary):
			continue
		var w: int = int(tag["width"])
		if machine.type == "usb_input":
			w = machine.width  # the roadmap tag is a placeholder for the instance width
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
			c.scale.x = target / base
			c.name = "WidthTag%d" % i
			body.add_child(c)
		else:
			var c := Art.sprite(rel, pos)
			c.name = "WidthTag%d" % i
			body.add_child(c)
		_tag_values.append(w)
		_text_specs.append({
			"key": "tag%d" % i, "pos": Vector2(pos.x + 0.0, pos.y + 1.0),
			"width": chip_w, "size": 7.5, "align": HORIZONTAL_ALIGNMENT_CENTER,
			"color": Palette.DATA_NUMBER, "text": "",
		})
		i += 1


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
	# Silk text
	var sylk: Dictionary = _entry(ly, "silk")
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
	# State overlays (alpha tween 0.12 s); hover/selected driven by the tools
	var want := {
		"processing": 1.0 if m.state == Machine.State.PROCESSING else 0.0,
		"outputready": 1.0 if m.state == Machine.State.OUTPUT_READY else 0.0,
		"blocked": 1.0 if m.state == Machine.State.BLOCKED else 0.0,
		"error": 1.0 if m.state == Machine.State.ERROR else 0.0,
		"hover": 1.0 if hovered and not selected else 0.0,
		"selected": 1.0 if selected else 0.0,
	}
	for k in want:
		var o: Sprite2D = _overlays[k]
		o.modulate.a = move_toward(o.modulate.a, want[k], delta / OVERLAY_TWEEN)
	# Ports: connected / active / idle from SimulationManager.sim
	for pid in _port_nodes:
		var st := _port_state(pid, running)
		var rel2 := Art.port_sprite(_port_dir[pid], _port_bus[pid], _port_w[pid], st)
		var pt := Art.tex(rel2)
		if _port_nodes[pid].texture != pt:
			_port_nodes[pid].texture = pt
	# Upright texts
	_update_texts(sim, running)
	text_layer.queue_redraw()


func _update_texts(sim: Simulation, running: bool) -> void:
	var m := machine
	var vm := resolve_view_mode()
	var vals := {}
	vals["display"] = _display_value(vm)
	var ro: Dictionary = _entry(Art.layout(m.type), "readout")
	if not ro.is_empty():
		vals["ro_mode"] = ViewMode.chip(_mode_from_name(str(ro.get("mode", "DEC"))))
		vals["ro_value"] = _readout_value(vm)
	vals["silk"] = _silk_text(sim)
	vals["bin"] = _bin_value(sim)
	for i in _tag_values.size():
		vals["tag%d" % i] = str(_tag_values[i])
	for t in _text_specs:
		var txt: String = vals.get(t["key"], "")
		t["text"] = txt
		if t["key"] == "bin":
			t["color"] = _bin_color


func resolve_view_mode() -> int:
	if view_mode >= ViewMode.Mode.BIN:
		return view_mode
	var md := SimulationManager.mission
	for o in md.outputs if md != null else []:
		return int(o.get("view", ViewMode.Mode.BIN))
	return ViewMode.Mode.BIN


func _display_value(vm: int) -> String:
	var m := machine
	match m.type:
		"add":
			return "+" + ViewMode.format(BitVector.of(int(m.params.get("k", 0)), m.width), vm)
		"multiply":
			var k := int(m.params.get("k", 0))
			var sign := "−" if k < 0 else ""
			return "×" + sign + ViewMode.format(BitVector.of(abs(k), m.width), vm)
		"delay":
			return "%dt" % int(m.params.get("ticks", 3))
	return ""


func _readout_value(vm: int) -> String:
	# No MVP machine carries a readout yet; reuse the value the machine displays.
	var v := _display_value(vm)
	return v if v != "" else "0"


func _silk_text(sim: Simulation) -> String:
	var m := machine
	match m.type:
		"input", "usb_input":
			var left := m.stream.size() - m.emitted
			var base := "USB" if m.type == "usb_input" else ""
			var cnt := " ×%d" % left if left > 0 else ""
			return base + cnt
		"output":
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


func _bin_value(sim: Simulation) -> String:
	if machine.type != "output" or machine.received.is_empty():
		return ""
	var last: Packet = machine.received[machine.received.size() - 1]
	var wrong := false
	var run := SimulationManager.run
	if run != null and run.status == MissionRun.Status.FAIL:
		wrong = int(run.failure.get("packet", -1)) == last.id
	_bin_color = Palette.STATE_ERROR if wrong else Palette.DATA_NUMBER
	return ViewMode.format(last.data, resolve_view_mode())


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
		_:
			if not busy:
				return _area_idle
			match _area_kind:
				"Die": return "processing"
				"Counter": return "tick"
				"Valve": return "open"
				"Split": return "dup"
				"Merge": return "lanea"
				_:
					return "active"


func _port_state(pid: String, running: bool) -> String:
	var m := machine
	if running and (pid in m.received_ports or pid in m.sent_ports):
		return "active"
	var sim := SimulationManager.sim
	if sim != null and sim.connection_at_port(m.id, pid) != null:
		return "connected"
	return "idle"


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