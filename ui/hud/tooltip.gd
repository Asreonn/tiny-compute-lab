extends Control
## Tooltip (Penpot 06): Machine 168×60 · Port 150×32 · Wire 168×60 · Packet 120×72. Raised fill,
## 1 px border, r6; title 11/800 (width-coloured dot for port/wire/packet), sub 9/500 muted.
## Follows ToolController.hover_changed; hidden while dragging. Machines use the hover card.

var tools: Node
var _box: Panel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func bind_tools(t: Node) -> void:
	tools = t
	tools.hover_changed.connect(_on_hover)


func _on_hover(info: Dictionary) -> void:
	if _box:
		_box.queue_free()
		_box = null
	if info.is_empty() or tools._dragging():
		if visible:
			HudKit.panel_hide(self, Vector2(0, 4), 0.14)
		else:
			visible = false
		return
	var sim: Simulation = get_node("/root/SimulationManager").sim
	var kind: String = info.get("kind", "")
	var title := ""
	var sub := ""
	var big := ""
	var dot_col = null
	var sz := Vector2(168, 60)
	match kind:
		"machine":
			# machines get the hover card (ui/hud/hover_card.gd)
			visible = false
			return
		"port":
			var m: Machine = sim.machines.get(info["id"])
			if m == null:
				return
			var w := m.port_width(info["port"])
			var dir: String = Catalog.port_def(m.type, info["port"]).get("dir", "in")
			title = "%d-bit %s" % [w, {"in": "input", "out": "output", "ctrl": "control"}.get(dir, dir)]
			dot_col = Palette.datatype(w)
			sz = Vector2(150, 32)
		"wire":
			var c: Connection = sim.connections.get(info["id"])
			if c == null:
				return
			title = "%d-bit wire" % c.width
			sub = "1 packet / tick · %d tiles" % c.cells.size()
			dot_col = Palette.datatype(c.width)
		"packet":
			var p := _find_packet(sim, int(info["id"]))
			if p == null:
				return
			title = "#%d" % p.id
			if p.is_raw():
				big = p.raw.glyph()
				sub = p.raw.kind_name()
				dot_col = Palette.FAMILY_IO
			else:
				# bits read as bits; the view mode's reading is the second line
				big = ViewMode.format(p.data, ViewMode.Mode.BIN)
				var reading := HudKit.fmt(p.data)
				sub = "%d-bit" % p.data.width + ("" if reading == big else " · %s" % reading)
				dot_col = Palette.datatype(p.data.width)
			sz = Vector2(120, 72)
		_:
			return
	_box = HudKit.box(self, Vector2.ZERO, sz, Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, 1, 6)
	var x := 12.0
	if dot_col != null:
		HudKit.dot(_box, Vector2(15, 16), 6, dot_col)
		x = 24.0
	HudKit.label(_box, title, Vector2(x, 9), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, sz.x - x - 8)
	if big != "":
		HudKit.label(_box, big, Vector2(12, 26), 16 if kind == "packet" else 11, HudKit.W_XBOLD, Palette.DATA_NUMBER, sz.x - 20)
	if sub != "":
		HudKit.label(_box, sub, Vector2(12, sz.y - 18), 9, HudKit.W_MEDIUM, Palette.TEXT_MUTED, sz.x - 20)
	var sp: Vector2 = info.get("screen_pos", Vector2.ZERO)
	var vp := get_viewport_rect().size
	position = Vector2(minf(sp.x + 16, vp.x - sz.x - 8), minf(sp.y + 16, vp.y - sz.y - 8))
	HudKit.panel_show(self, Vector2(0, 4), 0.12)


func _find_packet(sim: Simulation, pid: int) -> Packet:
	for cid in sim.sorted_connection_ids():
		for e in sim.connections[cid].all_packets():
			if e["packet"].id == pid:
				return e["packet"]
	for mid in sim.sorted_machine_ids():
		for e in sim.machines[mid].packets_inside():
			if e["packet"].id == pid:
				return e["packet"]
	return null
