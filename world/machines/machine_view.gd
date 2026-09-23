class_name MachineView
extends Node2D
## Visual composition of one machine — mirrors Penpot "05 Machines":
##   MachineView
##   ├─ Body        (rotates with the footprint)
##   │  ├─ Shell        machine_shell_{s,m,l}.svg
##   │  ├─ FamilyTab    24×3, family colour
##   │  ├─ Decor        routing/compute motif svg (splitter, merger, processor)
##   │  ├─ StateLayer   state_*_{size}.svg overlays, alpha-tweened
##   │  ├─ ActivityBar  processing sweep (ticks × tick)
##   │  └─ Ports        PortView per port
##   └─ Content     (always upright: icon, title, screen, readout, LED)
## It only READS Machine state; it never changes the simulation.

const T := Palette.TILE
const OVERLAYS := ["hover", "selected", "receiving", "processing", "outputready", "blocked", "error", "disabled"]

var machine: Machine
var ghost := false
var hovered := false
var selected := false
var highlighted := false  # failure path highlight

var body: Node2D
var content: Node2D
var led: Sprite2D
var readout: Label
var title: Label
var icon: Sprite2D
var overlay := {}  # name -> Sprite2D
var ports := {}  # port id -> PortView
var activity: ActivityBar
var slots: Node2D
var _led_state := ""
var _pulse := 0.0
var _size_key := "m"
var _base := Vector2i(2, 1)


func setup(m: Machine, as_ghost := false) -> MachineView:
	machine = m
	ghost = as_ghost
	name = "Machine_%d" % m.id
	_size_key = Art.size_key(m.type)
	_base = Catalog.SIZES[m.def()["size"]]
	_build()
	sync_transform()
	return self


func _build() -> void:
	var d := machine.def()
	var W := _base.x * T
	var H := _base.y * T
	body = Node2D.new()
	body.name = "Body"
	add_child(body)
	body.add_child(Art.sprite("machine/machine_shell_%s.svg" % _size_key))
	var tab := ColorRect.new()
	tab.name = "FamilyTab"
	tab.color = Palette.family(d["family"])
	tab.position = Vector2(16, 4)
	tab.size = Vector2(24, 3)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(tab)
	if machine.type in ["splitter", "merger", "processor"]:
		var dec := Art.sprite("machine/machine_%s_decor.svg" % machine.type)
		dec.name = "Decor"
		body.add_child(dec)
	activity = ActivityBar.new()
	activity.name = "ActivityBar"
	activity.color = Palette.family(d["family"]) if d["family"] != "io" else Palette.DATA_NUMBER
	activity.position = Vector2(12, H - 9)
	activity.width = W - 24 if _size_key != "s" else 40
	body.add_child(activity)
	var sl := Node2D.new()
	sl.name = "StateLayer"
	body.add_child(sl)
	for o in OVERLAYS:
		var s := Art.sprite("machine/state_%s_%s.svg" % [o, _size_key])
		s.name = o
		s.modulate.a = 0.0
		sl.add_child(s)
		overlay[o] = s
	var pn := Node2D.new()
	pn.name = "Ports"
	body.add_child(pn)
	for p in machine.ports():
		var pv := PortView.new().setup(machine, p)
		pn.add_child(pv)
		ports[p["id"]] = pv
	# upright content
	content = Node2D.new()
	content.name = "Content"
	add_child(content)
	_build_content(W, H)
	if ghost:
		modulate = Color(1, 1, 1, 0.5)


func _label(text: String, variation: String, pos: Vector2, width: float, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, size := 0) -> Label:
	var l := Label.new()
	l.theme_type_variation = variation
	l.text = text
	l.position = pos
	l.size = Vector2(width, 18)
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	return l


func _build_content(W: float, H: float) -> void:
	var d := machine.def()
	var c := content
	var iconrel := "icon/%s.svg" % d["icon"]
	var mirror := machine.type == "output"
	match _size_key:
		"s":
			icon = Art.sprite(iconrel, Vector2(20, 11))
			c.add_child(icon)
			c.add_child(Art.sprite("machine/screen_s.svg", Vector2(8, 38)))
			readout = _label("", "LabelValue", Vector2(8, 38), 48, Palette.DATA_NUMBER, HORIZONTAL_ALIGNMENT_CENTER, 10)
			c.add_child(readout)
			led = Art.sprite_centered("machine/led_idle.svg", Vector2(51, 13))
		"m":
			var ix := 88.0 if mirror else 16.0
			var sx := 14.0 if mirror else 48.0
			icon = Art.sprite(iconrel, Vector2(ix, 22))
			c.add_child(icon)
			title = _label(str(d["name"]).to_upper(), "LabelMicro", Vector2(sx, 7), 60, Palette.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT, 9)
			c.add_child(title)
			c.add_child(Art.sprite("machine/screen_m.svg", Vector2(sx, 24)))
			readout = _label("", "LabelValue", Vector2(sx, 27), 66, Palette.DATA_NUMBER, HORIZONTAL_ALIGNMENT_CENTER, 11)
			c.add_child(readout)
			if machine.type == "buffer":
				slots = BufferSlots.new()
				slots.position = Vector2(sx + 6, 31)
				c.add_child(slots)
				readout.position.x = sx + 30
				readout.size.x = 36
			led = Art.sprite_centered("machine/led_idle.svg", Vector2(W - 14, 11))
		"l":
			title = _label(str(d["name"]).to_upper(), "LabelMicro", Vector2(16, 10), 90, Palette.TEXT_SECONDARY, HORIZONTAL_ALIGNMENT_LEFT, 9)
			c.add_child(title)
			match machine.type:
				"splitter":
					icon = Art.sprite(iconrel, Vector2(10, 52))
					c.add_child(icon)
					c.add_child(Art.sprite("machine/screen_m.svg", Vector2(52, 52)))
					readout = _label("", "LabelValue", Vector2(52, 55), 66, Palette.DATA_NUMBER, HORIZONTAL_ALIGNMENT_CENTER, 11)
				"merger":
					icon = Art.sprite(iconrel, Vector2(94, 52))
					c.add_child(icon)
					c.add_child(Art.sprite("machine/screen_m.svg", Vector2(12, 52)))
					readout = _label("", "LabelValue", Vector2(12, 55), 66, Palette.DATA_NUMBER, HORIZONTAL_ALIGNMENT_CENTER, 11)
				_:
					c.add_child(Art.sprite("machine/screen_l.svg", Vector2(16, 84)))
					readout = _label("", "LabelValue", Vector2(16, 87), 96, Palette.DATA_NUMBER, HORIZONTAL_ALIGNMENT_CENTER, 11)
			c.add_child(readout)
			led = Art.sprite_centered("machine/led_idle.svg", Vector2(W - 14, 11))
	led.name = "StatusLED"
	c.add_child(led)
	_led_state = "idle"


## Position/rotation from the machine's cell + rot. Body rotates, content stays upright.
func sync_transform() -> void:
	var s := Catalog.size_of(machine.type, machine.rot)
	position = Vector2(machine.cell * T)
	var b := Vector2(_base * T)
	match machine.rot % 4:
		0: body.position = Vector2.ZERO
		1: body.position = Vector2(b.y, 0)
		2: body.position = b
		3: body.position = Vector2(0, b.x)
	body.rotation = machine.rot * PI / 2.0
	# upright content, centred in the rotated footprint
	var fp := Vector2(s * T)
	content.position = (fp - b) / 2.0 if machine.rot % 2 == 0 else (fp - b) / 2.0
	if machine.rot % 2 == 1:
		# portrait footprint: keep landscape content centred (it overhangs slightly — PCB silkscreen style)
		content.position = (fp - b) / 2.0
	for p in ports.values():
		p.sync_rotation(machine.rot)


func world_rect() -> Rect2:
	return Rect2(position, Vector2(Catalog.size_of(machine.type, machine.rot) * T))


## Port anchor in world space (tile-edge midpoint).
func port_anchor(port_id: String) -> Vector2:
	return port_world(machine, port_id)


static func port_world(m: Machine, port_id: String) -> Vector2:
	var g := m.port_geom(port_id)
	var c: Vector2 = Vector2(g["cell"]) * T + Vector2(T, T) / 2.0
	return c + Vector2(Catalog.side_vec(g["side"])) * (T / 2.0)


# ------------------------------------------------------------------ per-frame state

func refresh(sim: Simulation, alpha: float, running: bool, delta: float) -> void:
	var m := machine
	_update_readout(sim)
	var st := m.state
	if not running:
		st = Machine.State.IDLE if st != Machine.State.ERROR else st
	var led_name := ["idle", "receiving", "processing", "outputready", "blocked", "error", "off"][st]
	if led_name != _led_state:
		led.texture = Art.tex("machine/led_%s.svg" % led_name)
		_led_state = led_name
	# overlays (motion tokens: hover 140 ms, select 150 ms)
	var want := {
		"hover": 1.0 if hovered and not selected else 0.0,
		"selected": 1.0 if selected else 0.0,
		"receiving": 1.0 if running and m.received_ports.size() > 0 else 0.0,
		"processing": 1.0 if running and st == Machine.State.PROCESSING else 0.0,
		"outputready": 1.0 if running and st == Machine.State.OUTPUT_READY else 0.0,
		"blocked": 1.0 if running and st == Machine.State.BLOCKED else 0.0,
		"error": 1.0 if st == Machine.State.ERROR or highlighted else 0.0,
		"disabled": 0.0,
	}
	for k in want:
		var rate := delta / (Palette.MOTION_HOVER if k == "hover" else Palette.MOTION_SELECT)
		var s: Sprite2D = overlay[k]
		s.modulate.a = move_toward(s.modulate.a, want[k], rate)
	# processing sweep: the trace sweep inside the processing overlay slides with job progress
	var prog := 0.0
	if running and not m.job.is_empty():
		prog = clamp((float(m.job["total"] - m.job["ticks_left"]) + alpha) / float(max(1, m.job["total"])), 0.0, 1.0)
	activity.progress = prog
	activity.active = running and not m.job.is_empty()
	# icon pulse on job start (port-pulse 160 ms)
	if running and m.received_ports.size() > 0 and alpha < 0.05:
		_pulse = 1.0
	_pulse = max(0.0, _pulse - delta / Palette.MOTION_PORT_PULSE)
	if icon:
		icon.modulate = Palette.TEXT_PRIMARY.lerp(Palette.family(m.def()["family"]), 0.6 * (_pulse if running else 0.0) + (0.35 if activity.active else 0.0))
	if slots:
		slots.fill = m.queued_count()
		slots.capacity = m.in_capacity("in")
		slots.blocked = running and st == Machine.State.BLOCKED
		slots.queue_redraw()
	for pid in ports:
		ports[pid].refresh(sim, running, delta)


func _update_readout(sim: Simulation) -> void:
	var m := machine
	var p := m.params
	var t := ""
	var col := Palette.DATA_NUMBER
	match m.type:
		"input", "usb_input":
			var left := m.stream.size() - m.emitted
			t = ("NEXT %s" % ViewMode.format(m.stream[m.emitted], ViewMode.Mode.BIN)) if left > 0 else "DONE"
			col = Palette.datatype(m.width) if left > 0 else Palette.TEXT_MUTED
		"output":
			var n := m.received.size()
			var total := 0
			if sim.mission != null and m.channel < sim.mission.def.outputs.size():
				total = sim.mission.def.outputs[m.channel]["expected"].size()
			if n == 0:
				t = "0/%d" % total
				col = Palette.TEXT_MUTED
			else:
				var ok := sim.mission == null or sim.mission.status != MissionRun.Status.FAIL or sim.mission.failure.get("packet", -1) != m.received[n - 1].id
				var view := ViewMode.Mode.BIN
				if sim.mission != null and m.channel < sim.mission.def.outputs.size():
					view = int(sim.mission.def.outputs[m.channel].get("view", ViewMode.Mode.BIN))
				t = "%s %s %d/%d" % ["✓" if ok else "✗", m.received[n - 1].label(view), n, total]
				col = Palette.STATE_VALID if ok else Palette.STATE_ERROR
		"add":
			t = ("+%d" if int(p["k"]) >= 0 else "%d") % int(p["k"])
		"multiply":
			t = "×%d" % int(p["k"])
		"compare":
			t = "%s %d" % [p["op"], int(p["k"])]
			col = Palette.DATA_BOOLEAN
		"gate":
			t = "EN"
			col = Palette.DATA_BOOLEAN
		"splitter":
			t = "ALT" if str(p["mode"]) == "Alternate" else "DUP"
		"merger":
			t = "RR"
		"buffer":
			t = "%d/%d" % [m.queued_count(), m.in_capacity("in")]
			col = Palette.TEXT_PRIMARY
		"delay":
			t = "%dt" % int(p["ticks"])
		"counter":
			t = "#%d" % m.counter
		"processor":
			t = str(p["op"])
	if readout.text != t:
		readout.text = t
	readout.add_theme_color_override("font_color", col)


# ------------------------------------------------------------------ helpers

class ActivityBar extends Node2D:
	var width := 104.0
	var progress := 0.0
	var active := false
	var color := Palette.FAMILY_MATH

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0, 0, width, 2), Palette.MACHINE_RAIL)
		if active:
			draw_rect(Rect2(0, 0, width * progress, 2), color)
			# leading spark
			draw_rect(Rect2(width * progress - 2, -1, 3, 4), color.lightened(0.4))


class BufferSlots extends Node2D:
	var fill := 0
	var capacity := 4
	var blocked := false

	func _draw() -> void:
		var n: int = clamp(capacity, 1, 8)
		var w := 22.0 / n * 1.6 if n > 4 else 7.0
		var gap := 3.0 if n <= 4 else 1.5
		var pressure := float(fill) / float(n)
		var col := Palette.FAMILY_STORAGE
		if pressure >= 1.0:
			col = Palette.STATE_BLOCKED if not blocked else Palette.STATE_ERROR
		for i in n:
			var r := Rect2(i * (w + gap), 0, w, 10)
			draw_rect(r, col if i < fill else Palette.MACHINE_RAIL)
