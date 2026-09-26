extends Control
## Network Inspector (JOB C8b): the locked NIC's panel. 340 px wide, right edge (16 px margin),
## top 68 — the same placement as the Inspector. Visible while the selected machine is the NIC
## (the Inspector hides then). Rebuilds on selection / layout changes; _process refreshes only
## the live labels/bars whose text or width actually changed (cheap). UI only READS simulation
## state and changes it through Simulation / LabRun methods; colours only from Palette.

const W := 340.0
const ROW := 30.0

var tools: Node
var _mid := -1
var _ch := "a"  # the shown RX channel (always one of the open RX channels)
var _source_open := false  # the SOURCE picker list
var _bg: Panel
var _body: Control
var _acquiring := {}  # source id -> elapsed seconds of the 3 s acquire sequence
var _acquiring_labels := {}  # source id -> the row Label the sequence animates
var _live_labels := {}  # key -> Label refreshed every frame
var _live_bars := {}  # key -> Panel refreshed every frame
var _live_buttons := {}  # key -> Panel restyled every frame


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -W - 16
	offset_right = -16
	offset_top = 68
	visible = false
	_bg = HudKit.box(self, Vector2.ZERO, Vector2(W, 400), Palette.SURFACE_PANEL, Color(0, 0, 0, 0), 0, 10)
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	var sm := _mgr()
	sm.layout_changed.connect(func(): if visible: _rebuild())
	sm.view_mode_changed.connect(func(_m): if visible: _rebuild())


func bind_tools(t: Node) -> void:
	tools = t
	tools.selection_changed.connect(_on_selection)


func _mgr() -> Node:
	return get_node("/root/SimulationManager")


func _on_selection(machine_id: int, _conn_id: int) -> void:
	var nic := false
	if machine_id >= 0:
		var sim: Simulation = _mgr().sim
		var m = sim.machines.get(machine_id) if sim != null else null
		nic = m != null and m.type == "nic"
	if _mid >= 0 and (machine_id < 0 or not nic):
		HudKit.panel_hide(self, Vector2(12, 0), 0.14)
	_mid = machine_id if nic else -1
	if _mid >= 0:
		_rebuild()
		HudKit.panel_show(self, Vector2(12, 0), 0.18)


func _machine() -> Machine:
	var sim: Simulation = _mgr().sim
	return sim.machines.get(_mid) if sim != null else null


func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_live_labels.clear()
	_live_bars.clear()
	_live_buttons.clear()
	_acquiring_labels.clear()
	var m := _machine()
	if m == null or m.type != "nic":
		visible = false
		return
	var sm := _mgr()
	var sim: Simulation = sm.sim
	var lab: LabRun = sm.lab_run
	var tier := NicLogic.tier(m)
	var open_rx := _open_rx(tier)
	if not _ch in open_rx:
		_ch = str(open_rx[0] if not open_rx.is_empty() else "a")
	var ch := _ch
	var src_id := str(m.params.get("rx_" + ch, ""))
	var src_def: RemoteSourceDef = SourceStream.source(src_id) if src_id != "" else null
	# 1. header: family tab, title, subtitle, RX channel arrows
	HudKit.box(_body, Vector2(16, 18), Vector2(24, 3), Palette.FAMILY_IO)
	HudKit.label(_body, "NETWORK MODULE · MK%d" % tier, Vector2(46, 12), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
	HudKit.label(_body, "RX %s · channel %d of %d" % [ch.to_upper(), open_rx.find(ch) + 1, open_rx.size()], Vector2(46, 30), 10, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	HudKit.icon(_body, "icon_chevron_left", Vector2(W - 16 - 46, 13), 16, Palette.TEXT_SECONDARY)
	HudKit.hit(_body, Vector2(W - 16 - 48, 10), Vector2(22, 22), func(): _cycle_ch(-1), "Previous RX channel")
	HudKit.icon(_body, "icon_chevron_right", Vector2(W - 16 - 24, 13), 16, Palette.TEXT_SECONDARY)
	HudKit.hit(_body, Vector2(W - 16 - 26, 10), Vector2(22, 22), func(): _cycle_ch(1), "Next RX channel")
	var y := 56.0
	# 2. SOURCE: bound source + picker of "" and every compromised source
	_key("SOURCE", y)
	HudKit.label(_body, _source_name(src_id) if src_id != "" else "— none —", Vector2(90, y + 4), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 180)
	HudKit.icon(_body, "icon_chevron_down", Vector2(282, y + 5), 16, Palette.TEXT_SECONDARY)
	HudKit.hit(_body, Vector2(90, y), Vector2(220, 26), func(): _toggle_source(), "Bind a compromised source")
	y += ROW
	if _source_open:
		var items: Array = [""]
		items.append_array(_compromised_sources(lab))
		for item in items:
			var pick: String = item
			HudKit.label(_body, "— none —" if pick == "" else _source_name(pick), Vector2(100, y + 4), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 170)
			if pick == src_id:
				HudKit.icon(_body, "icon_check", Vector2(286, y + 5), 16, Palette.DATA_NUMBER)
			HudKit.hit(_body, Vector2(90, y), Vector2(220, 26), func(): _pick_source(pick))
			y += 26
	# 3. ACCESS: one row per accessible source (only when at least one exists)
	var accessible := _accessible_sources(lab)
	if not accessible.is_empty():
		_key("ACCESS", y)
		y += ROW
		for id in accessible:
			var acc_id: String = id
			var name := _source_name(acc_id)
			var row_label := HudKit.label(_body, "%s  [ACQUIRE ACCESS]" % name, Vector2(90, y + 4), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 220)
			_acquiring_labels[acc_id] = row_label
			if _acquiring.has(acc_id):
				HudKit.set_text(row_label, _acquire_text(float(_acquiring[acc_id])))
			HudKit.hit(_body, Vector2(90, y), Vector2(220, 26), func(): _start_acquire(acc_id), "Acquire access to %s" % name)
			y += ROW
	# 4. STATUS
	_key("STATUS", y)
	var state_text := "NOT BOUND"
	var state_col := Palette.TEXT_MUTED
	if src_id != "":
		var st := lab.source_state(src_id) if lab != null else "locked"
		if st == "compromised":
			state_text = "COMPROMISED · CONNECTED"
			state_col = Palette.STATE_VALID
		elif st == "accessible":
			state_text = "ACCESSIBLE · TEST ONLY"
			state_col = Palette.TEXT_SECONDARY
		else:
			state_text = "LOCKED · NO ACCESS"
			state_col = Palette.TEXT_MUTED
	HudKit.label(_body, state_text, Vector2(90, y + 4), 12, HudKit.W_XBOLD, state_col)
	y += ROW
	# 5. SCHEMA: one segment per field of the bound source
	if src_def != null:
		_key("SCHEMA", y)
		y += ROW
		var ranges: Array = SourceStream.field_ranges(src_def)
		var x := 90.0
		for i in ranges.size():
			var r: Dictionary = ranges[i]
			var w := 200.0 * int(r["width"]) / float(src_def.width)
			var col := Palette.DATA_NUMBER
			col.a = 0.8 if i % 2 == 0 else 0.45
			HudKit.box(_body, Vector2(x, y), Vector2(maxf(w - 2.0, 1.0), 10), col, Color(0, 0, 0, 0), 0, 1)
			x += w
		y += 14
		var x2 := 90.0
		for i in ranges.size():
			var r: Dictionary = ranges[i]
			var w := 200.0 * int(r["width"]) / float(src_def.width)
			HudKit.label(_body, str(r["name"]), Vector2(x2, y), 7, HudKit.W_XBOLD, Palette.TEXT_SECONDARY, w)
			HudKit.label(_body, "%d–%d" % [int(r["hi"]), int(r["lo"])], Vector2(x2, y + 10), 7, HudKit.W_MEDIUM, Palette.TEXT_MUTED, w)
			x2 += w
		y += 24
	# 6. MODE: TEST | LIVE segmented control
	_key("MODE", y)
	var mode := sim.source_mode(m.id, ch) if sim != null else "live"
	HudKit.box(_body, Vector2(90, y), Vector2(192, 24), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 12)
	for mi in [["TEST", "test", Palette.STATE_BLOCKED], ["LIVE", "live", Palette.STATE_VALID]]:
		var label_text: String = mi[0]
		var mode_key: String = mi[1]
		var col: Color = mi[2]
		var on := mode == mode_key
		var px := 90.0 + (96.0 if mode_key == "live" else 0.0)
		var fill := col
		fill.a = 0.18
		HudKit.box(_body, Vector2(px, y), Vector2(96, 24), fill if on else Color(0, 0, 0, 0), col if on else Color(0, 0, 0, 0), 1 if on else 0, 12)
		HudKit.label(_body, label_text, Vector2(px, y + 6), 10, HudKit.W_XBOLD, col if on else Palette.TEXT_MUTED, 96, HORIZONTAL_ALIGNMENT_CENTER)
		HudKit.hit(_body, Vector2(px, y), Vector2(96, 24), func(): _set_mode(mode_key))
	y += ROW
	# 7. RATE
	_key("RATE", y)
	HudKit.label(_body, "— records/s when live" if src_def == null else ("%s records/s when live" % String.num(src_def.rate, 1).trim_suffix(".0")), Vector2(90, y + 4), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY)
	y += ROW
	# 8. NETWORK: frame-budget well + load text
	_key("NETWORK", y)
	y += ROW
	HudKit.box(_body, Vector2(90, y), Vector2(200, 8), Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 4)
	var fill_col := Palette.DATA_NUMBER
	fill_col.a = 0.8
	_live_bars["net"] = HudKit.box(_body, Vector2(90, y), Vector2(0, 8), fill_col, Color(0, 0, 0, 0), 0, 4)
	y += 12
	_live_labels["net"] = HudKit.label(_body, "", Vector2(90, y), 10, HudKit.W_MEDIUM, Palette.TEXT_SECONDARY)
	y += 20
	# 9. divider + the three buttons
	y += 2
	HudKit.box(_body, Vector2(16, y), Vector2(W - 32, 1), Palette.SURFACE_BORDER)
	y += 10
	var tr := _current_run(lab, m, ch)
	var last := _last_run(lab, m, ch)
	var unbound := src_id == ""
	y = _send_button(y, tr, unbound)
	y = _run_button(y, tr, last, unbound)
	y = _live_button(y, last)
	# 10. LAST TEST SET: summary + one row per line
	if last != null:
		y += 4
		_key("LAST TEST SET", y)
		_live_labels["last_summary"] = HudKit.label(_body, "", Vector2(90, y + 6), 11, HudKit.W_XBOLD, Palette.STATE_VALID, 220, HORIZONTAL_ALIGNMENT_RIGHT)
		y += ROW
		var lines := last.lines()
		for i in lines.size():
			var line: String = lines[i]
			var sep := line.rfind(" — ")
			var note := line.substr(0, sep) if sep >= 0 else line
			var outcome := line.substr(sep + 3) if sep >= 0 else ""
			_live_labels["line_%d_note" % i] = HudKit.label(_body, note, Vector2(90, y), 11, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, 148)
			_live_labels["line_%d_out" % i] = HudKit.label(_body, outcome, Vector2(242, y), 10, HudKit.W_MEDIUM, Palette.STATE_ERROR, 56, HORIZONTAL_ALIGNMENT_RIGHT)
			_live_labels["line_%d_glyph" % i] = HudKit.label(_body, "", Vector2(302, y), 10, HudKit.W_XBOLD, Palette.STATE_ERROR, 16, HORIZONTAL_ALIGNMENT_RIGHT)
			y += 22
	# 11. TX bindings: each open TX port cycles "" and the active quests' Job sticks
	y += 4
	var open_tx := NicLogic.open_ports(tier)
	for tx in NicLogic.TX:
		var port: String = "tx_" + str(tx)
		if not port in open_tx:
			continue
		var cur := str(m.params.get(port, ""))
		var title := "— nobody —"
		if cur != "" and lab != null:
			for q in lab.active_quests():
				if lab.quest_job(q) == cur:
					title = lab.quest_title(q)
					break
		HudKit.label(_body, "TX %s → %s" % [tx.to_upper(), title], Vector2(16, y + 4), 12, HudKit.W_XBOLD, Palette.TEXT_PRIMARY, W - 32)
		var tx_ch: String = tx
		HudKit.hit(_body, Vector2(16, y), Vector2(W - 32, 26), func(): _cycle_tx(tx_ch), "Bind a quest to TX %s" % tx.to_upper())
		y += ROW
	_bg.size = Vector2(W, y + 10)
	size = _bg.size


func _key(text: String, y: float) -> void:
	HudKit.label(_body, text, Vector2(16, y + 6), 9, HudKit.W_XBOLD, Palette.TEXT_MUTED)


func _send_button(y: float, tr: TestRun, unbound: bool) -> float:
	var enabled := tr != null and not unbound
	var b := HudKit.box(_body, Vector2(16, y), Vector2(W - 32, 30), Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, 1, 6)
	_live_buttons["send"] = b
	_live_labels["send"] = HudKit.label(_body, _send_text(tr, unbound), Vector2(16, y + 8), 11, HudKit.W_XBOLD, Palette.TEXT_SECONDARY if enabled else Palette.TEXT_MUTED, W - 32, HORIZONTAL_ALIGNMENT_CENTER)
	if enabled:
		HudKit.hit(_body, Vector2(16, y), Vector2(W - 32, 30), _send)
	return y + 36


func _run_button(y: float, tr: TestRun, last: TestRun, unbound: bool) -> float:
	var enabled := tr != null and not unbound
	var fill := Palette.DATA_NUMBER
	fill.a = 0.14
	var b := HudKit.box(_body, Vector2(16, y), Vector2(W - 32, 30), fill, Palette.DATA_NUMBER, 1, 6)
	_live_buttons["run"] = b
	_live_labels["run"] = HudKit.label(_body, _run_text(tr, last, unbound), Vector2(16, y + 8), 11, HudKit.W_XBOLD, Palette.DATA_NUMBER if enabled else Palette.TEXT_MUTED, W - 32, HORIZONTAL_ALIGNMENT_CENTER)
	if enabled:
		HudKit.hit(_body, Vector2(16, y), Vector2(W - 32, 30), _run)
	return y + 36


func _live_button(y: float, last: TestRun) -> float:
	var ok := last == null or last.all_pass()
	var col := Palette.STATE_VALID if ok else Palette.STATE_BLOCKED
	var fill := col
	fill.a = 0.14
	var b := HudKit.box(_body, Vector2(16, y), Vector2(W - 32, 30), fill, col, 1, 6)
	_live_buttons["live"] = b
	_live_labels["live"] = HudKit.label(_body, _live_text(last), Vector2(16, y + 8), 11, HudKit.W_XBOLD, col, W - 32, HORIZONTAL_ALIGNMENT_CENTER)
	HudKit.hit(_body, Vector2(16, y), Vector2(W - 32, 30), _go_live)
	return y + 36


func _process(delta: float) -> void:
	if not visible:
		return
	var m := _machine()
	if m == null or m.type != "nic":
		visible = false
		return
	var sm := _mgr()
	var sim: Simulation = sm.sim
	var lab: LabRun = sm.lab_run
	var ch := _ch
	var src_id := str(m.params.get("rx_" + ch, ""))
	var unbound := src_id == ""
	var tr := _current_run(lab, m, ch)
	var last := _last_run(lab, m, ch)
	# NETWORK bar + text
	var load := NicLogic.load_per_sec(m)
	var cap := NicLogic.capacity(m)
	var frac := float(load) / float(cap)
	if _live_bars.has("net"):
		var fill: Panel = _live_bars["net"]
		var w := frac * 200.0
		if fill.size.x != w:
			fill.size.x = w
		var col := Palette.DATA_NUMBER
		col.a = 0.8
		if frac >= 0.75:
			col = Palette.STATE_BLOCKED
		HudKit.restyle(fill, col, Color(0, 0, 0, 0), 0, 4)
	if _live_labels.has("net"):
		HudKit.set_text(_live_labels["net"], "%d / %d frames/s" % [load, cap])
	# SEND / RUN / LIVE buttons
	if _live_labels.has("send"):
		HudKit.set_text(_live_labels["send"], _send_text(tr, unbound))
	if _live_labels.has("run"):
		HudKit.set_text(_live_labels["run"], _run_text(tr, last, unbound))
	if _live_labels.has("live"):
		HudKit.set_text(_live_labels["live"], _live_text(last))
		if _live_buttons.has("live"):
			var ok := last == null or last.all_pass()
			var col2 := Palette.STATE_VALID if ok else Palette.STATE_BLOCKED
			var fill2 := col2
			fill2.a = 0.14
			HudKit.restyle(_live_buttons["live"], fill2, col2, 1, 6)
	# LAST TEST SET lines
	if last != null:
		if _live_labels.has("last_summary"):
			HudKit.set_text(_live_labels["last_summary"], last.summary(), Palette.STATE_VALID if last.all_pass() else Palette.STATE_BLOCKED)
		var lines := last.lines()
		for i in lines.size():
			var line: String = lines[i]
			var sep := line.rfind(" — ")
			var note := line.substr(0, sep) if sep >= 0 else line
			var outcome := line.substr(sep + 3) if sep >= 0 else ""
			var ok := outcome == "PASS"
			if _live_labels.has("line_%d_note" % i):
				HudKit.set_text(_live_labels["line_%d_note" % i], note)
			if _live_labels.has("line_%d_out" % i):
				HudKit.set_text(_live_labels["line_%d_out" % i], outcome, Palette.STATE_VALID if ok else Palette.STATE_ERROR)
			if _live_labels.has("line_%d_glyph" % i):
				HudKit.set_text(_live_labels["line_%d_glyph" % i], "✓" if ok else "✗", Palette.STATE_VALID if ok else Palette.STATE_ERROR)
	# the 3 s acquire sequences (handshake… → mapping schema… → access granted)
	var finished: Array = []
	for id in _acquiring.keys():
		var acc_id: String = id
		_acquiring[acc_id] = float(_acquiring[acc_id]) + delta
		var el := float(_acquiring[acc_id])
		if _acquiring_labels.has(acc_id):
			HudKit.set_text(_acquiring_labels[acc_id], _acquire_text(el))
		if el >= 3.0:
			finished.append(acc_id)
	if not finished.is_empty():
		for id in finished:
			_acquiring.erase(id)
			if lab != null:
				lab.acquire_access(id)
		_rebuild()


# ------------------------------------------------------------------ interactions

func _toggle_source() -> void:
	_source_open = not _source_open
	_rebuild()


func _pick_source(id: String) -> void:
	_source_open = false
	_set_param("rx_" + _ch, id)


func _cycle_ch(dir: int) -> void:
	var m := _machine()
	if m == null:
		return
	var open := _open_rx(NicLogic.tier(m))
	if open.size() < 2:
		return
	var i := open.find(_ch)
	_ch = str(open[(i + dir + open.size()) % open.size()])
	_rebuild()


func _set_mode(mode: String) -> void:
	var sm := _mgr()
	sm.request_edit()
	sm.sim.set_source_mode(_mid, _ch, mode)
	_rebuild()


func _set_param(key: String, value: Variant) -> void:
	var sm := _mgr()
	sm.request_edit()
	sm.sim.set_param(_mid, key, value)


func _send() -> void:
	var sm := _mgr()
	var lab: LabRun = sm.lab_run
	var m := _machine()
	if lab == null or m == null:
		return
	var tr := _current_run(lab, m, _ch)
	if tr == null:
		tr = lab.start_test(sm.sim, m.id, _ch)
	tr.send_next(sm.sim, lab)
	_rebuild()


func _run() -> void:
	var sm := _mgr()
	var lab: LabRun = sm.lab_run
	var m := _machine()
	if lab == null or m == null:
		return
	var tr := _current_run(lab, m, _ch)
	if tr == null:
		tr = lab.start_test(sm.sim, m.id, _ch)
	tr.run_all(sm.sim)
	_rebuild()


func _go_live() -> void:
	var sm := _mgr()
	sm.request_edit()
	sm.sim.set_source_mode(_mid, _ch, "live")
	_rebuild()


func _cycle_tx(tx: String) -> void:
	var m := _machine()
	if m == null:
		return
	var lab: LabRun = _mgr().lab_run
	var opts: Array = [""]
	if lab != null:
		for q in lab.active_quests():
			opts.append(lab.quest_job(q))
	var cur := str(m.params.get("tx_" + tx, ""))
	var i := opts.find(cur)
	var next: String = str(opts[(i + 1) % opts.size()] if i >= 0 else opts[0])
	_set_param("tx_" + tx, next)


func _start_acquire(id: String) -> void:
	_acquiring[id] = 0.0
	if _acquiring_labels.has(id):
		HudKit.set_text(_acquiring_labels[id], _acquire_text(0.0))


# ------------------------------------------------------------------ data helpers

static func _open_rx(tier: int) -> Array:
	var out: Array = []
	for ch in NicLogic.RX:
		if "rx_" + ch in NicLogic.open_ports(tier):
			out.append(ch)
	return out


func _compromised_sources(lab: LabRun) -> Array:
	var out: Array = []
	if lab == null:
		return out
	for id in lab.sources:
		var sid := str(id)
		if lab.source_state(sid) == "compromised":
			out.append(sid)
	out.sort()
	return out


func _accessible_sources(lab: LabRun) -> Array:
	var out: Array = []
	if lab == null:
		return out
	for id in lab.sources:
		var sid := str(id)
		if lab.source_state(sid) == "accessible":
			out.append(sid)
	out.sort()
	return out


func _source_name(id: String) -> String:
	var def := SourceStream.source(id)
	return def.display_name if def != null else id


## The channel's current TestRun: the highest id with source == nic.id and channel == ch that is
## not all-emitted-and-done (a fresh run starts on the next press once it is).
func _current_run(lab: LabRun, nic: Machine, ch: String) -> TestRun:
	if lab == null:
		return null
	var best: TestRun = null
	var ids := lab.test_runs.keys()
	ids.sort()
	for rid in ids:
		var tr: TestRun = lab.test_runs[rid]
		if tr.source == nic.id and tr.channel == ch:
			if tr.done() and tr.total() == tr.vectors.size():
				continue
			best = tr
	return best


## The highest-id run on this channel, done or not (what LAST TEST SET and the LIVE button read).
func _last_run(lab: LabRun, nic: Machine, ch: String) -> TestRun:
	if lab == null:
		return null
	var best: TestRun = null
	for rid in lab.test_runs:
		var tr: TestRun = lab.test_runs[rid]
		if tr.source == nic.id and tr.channel == ch:
			best = tr
	return best


func _send_text(tr: TestRun, unbound: bool) -> String:
	if unbound:
		return "SEND TEST FRAME · next: —"
	if tr == null:
		return "SEND TEST FRAME · next: ①"
	for i in tr.vectors.size():
		if tr.vectors[i]["status"] == "idle":
			return "SEND TEST FRAME · next: %s" % _circle(i + 1)
	return "SEND TEST FRAME · next: —"


func _run_text(tr: TestRun, last: TestRun, unbound: bool) -> String:
	var n := tr.vectors.size() if tr != null else (last.vectors.size() if last != null else _fresh_vector_count())
	return "RUN TEST SET · %d vectors" % n


func _live_text(last: TestRun) -> String:
	if last == null or last.all_pass():
		return "OPEN LIVE FEED"
	return "⚠ %s · OPEN LIVE FEED ANYWAY" % last.summary()


## How many vectors a fresh run would queue (TestRun.build's preference order).
func _fresh_vector_count() -> int:
	var lab: LabRun = _mgr().lab_run
	var m := _machine()
	var entries: Array = []
	var lv: Dictionary = LabDef.level(lab.level if lab != null else 0)
	if lv.has("tests") and lv["tests"] is Array:
		entries = lv["tests"]
	if entries.is_empty() and m != null:
		var def := SourceStream.source(str(m.params.get("rx_" + _ch, "")))
		if def != null:
			entries = def.test_vectors
	if entries.is_empty():
		return 4
	var n := 0
	for e in entries:
		if e.has("value") or e.has("seq"):
			n += 1
	return n


static func _acquire_text(el: float) -> String:
	if el < 1.0:
		return "handshake…"
	if el < 2.0:
		return "mapping schema…"
	return "access granted"


static func _circle(n: int) -> String:
	if n >= 1 and n <= 10:
		return ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"][n - 1]
	return "(%d)" % n