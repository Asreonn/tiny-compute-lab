class_name MissionRun
extends RunBase
## Runtime validation of a mission against the simulation.
## Campaign missions are non-fatal (docs/ARCHITECTURE.md §6): sources loop, wrong values are
## rejected and shown, an ordered output needs its expected sequence as an unbroken streak, and
## stalls only raise a warning. Legacy missions (def.strict_validation) keep strict FAIL rules.

enum Status { RUNNING, PASS, FAIL }

const SETTLE_TICKS := 20  # after the last expected output, wait for stray extras

var remaining: Array = []  # per output channel (unordered): BitVectors still expected
var complete_tick := -1
var discarded := 0
var rejected: Array = []  # per output channel: wrong values received (non-strict)


func _init(p_def: MissionDef) -> void:
	def = p_def


func allows(type: String) -> bool:
	return type in def.allowed


## Place the locked Input/Output machines for this mission on a fresh board.
func build_board(sim: Simulation) -> void:
	sim.clear()
	sim.size = def.board_size
	sim.default_width = def.default_width
	sim.campaign_timing = not def.legacy
	sim.mission = self
	for i in def.inputs.size():
		var d: Dictionary = def.inputs[i]
		var source := str(d.get("source", "input"))
		var m := Machine.new(0, source, d["cell"], int(d.get("width", def.default_width)), int(d.get("rot", 0)))
		m.locked = true
		sim.add_machine(m)
		var base := "USB Input" if source == "usb_input" else "Input"
		m.label = base if def.inputs.size() == 1 else "%s %s" % [base, char(65 + i)]
	for i in def.outputs.size():
		var d: Dictionary = def.outputs[i]
		var sink := str(d.get("sink", "output"))
		var m := Machine.new(0, sink, d["cell"], int(d.get("width", def.default_width)), int(d.get("rot", 0)))
		m.locked = true
		m.channel = i
		sim.add_machine(m)
		var base := "Terminal" if sink == "terminal_output" else "Output"
		m.label = base if def.outputs.size() == 1 else "%s %s" % [base, char(65 + i)]
	reset(sim)
	sim.changed.emit()


func reset(sim: Simulation) -> void:
	status = Status.RUNNING
	failure = {}
	complete_tick = -1
	discarded = 0
	rejected = []
	last_ok = []
	warning = ""
	progress = []
	remaining = []
	expected_bits = []
	for o in def.outputs:
		var w := int(o.get("width", def.default_width))
		var arr: Array = []
		for v in o["expected"]:
			arr.append(MissionDef.to_bits(v, w))
		expected_bits.append(arr)
		progress.append(0)
		rejected.append(0)
		last_ok.append({})
		remaining.append(arr.duplicate())
	var ii := 0
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type in ["input", "usb_input"] and m.locked and ii < def.inputs.size():
			var d: Dictionary = def.inputs[ii]
			m.stream = []
			for v in d["values"]:
				m.stream.append(MissionDef.to_bits(v, m.width))
			m.interval = int(d.get("interval", 3))
			m.loop = not def.strict_validation  # campaign sources repeat until the mission passes
			m.strict = bool(d.get("strict", false))
			m.next_emit = int(d.get("start", 1))
			ii += 1


func expected_for(ch: int) -> Array:
	return def.outputs[ch]["expected"]


func correct_total() -> int:
	var n := 0
	for p in progress:
		n += p
	return n


func rejected_total() -> int:
	var n := 0
	for r in rejected:
		n += r
	return n


func accuracy() -> float:
	if not def.strict_validation:
		var seen := correct_total() + rejected_total()
		return 100.0 * correct_total() / float(seen) if seen > 0 else 100.0
	var t: int = def.expected_total()
	return 100.0 * correct_total() / float(t) if t > 0 else 100.0


# ------------------------------------------------------------------ hooks

func on_output(sim: Simulation, m: Machine, p: Packet) -> void:
	if status != Status.RUNNING:
		return
	var ch := m.channel
	var out: Dictionary = def.outputs[ch]
	var want: Array = expected_bits[ch]
	var ordered: bool = out.get("ordered", true)
	var view := int(out.get("view", ViewMode.Mode.BIN))
	var mname := m.label
	if not def.strict_validation:
		_on_output_lenient(sim, ch, p, want, ordered)
		return
	if ordered:
		var i: int = progress[ch]
		if i >= want.size():
			_fail(sim, "Unexpected extra output", "%s already received all %d expected values." % [mname, want.size()], "—", p, view)
			return
		if not want[i].equals(p.data):
			_fail(sim, "Wrong value", "Result #%d at %s is incorrect." % [i + 1, mname], ViewMode.format(want[i], view), p, view, want[i])
			return
		progress[ch] = i + 1
	else:
		var idx := -1
		for k in remaining[ch].size():
			if remaining[ch][k].equals(p.data):
				idx = k
				break
		if idx < 0:
			var want_s := "one of " + ", ".join(remaining[ch].map(func(v): return ViewMode.format(v, view))) if not remaining[ch].is_empty() else "—"
			_fail(sim, "Wrong value" if not remaining[ch].is_empty() else "Unexpected extra output", "%s received a value that is not expected." % mname, want_s, p, view)
			return
		remaining[ch].remove_at(idx)
		progress[ch] += 1
	if _all_complete() and complete_tick < 0:
		complete_tick = sim.tick


## Non-fatal validation: a correct value extends the streak, a wrong one is rejected and resets
## it (ordered) — so PASS needs the whole expected sequence in a row and a wrong machine can never
## pass by collecting matches across loops.
func _on_output_lenient(sim: Simulation, ch: int, p: Packet, want: Array, ordered: bool) -> void:
	var ok := false
	if ordered:
		var i: int = progress[ch]
		if i < want.size() and want[i].equals(p.data):
			progress[ch] = i + 1
			ok = true
		else:
			# restart the streak; this value may itself be the first expected one
			progress[ch] = 1 if want[0].equals(p.data) else 0
			ok = progress[ch] == 1
			rejected[ch] += 0 if ok else 1
	else:
		var idx := -1
		for k in remaining[ch].size():
			if remaining[ch][k].equals(p.data):
				idx = k
				break
		if idx >= 0:
			remaining[ch].remove_at(idx)
			progress[ch] += 1
			ok = true
		else:
			rejected[ch] += 1
			remaining[ch] = expected_bits[ch].duplicate()
			progress[ch] = 0
	last_ok[ch] = {"packet": p.id, "ok": ok}
	if _all_complete():
		complete_tick = sim.tick
		status = Status.PASS


func on_overflow(sim: Simulation, m: Machine, p: Packet) -> void:
	if status != Status.RUNNING:
		return
	_fail(sim, "Input overflow", "%s could not send packet #%d — the line downstream is full. Data arrives faster than your machine processes it." % [m.label, p.id], ViewMode.format(p.data, ViewMode.Mode.BIN), p, ViewMode.Mode.BIN, null, [m.id])


func after_tick(sim: Simulation) -> void:
	if status != Status.RUNNING:
		return
	if complete_tick >= 0:
		if sim.packets_in_flight() == 0 or sim.tick - complete_tick >= SETTLE_TICKS:
			status = Status.PASS
		return
	if not def.strict_validation:
		# Non-fatal: explain a stall instead of failing; clear it once data moves again.
		warning = _stall_reason(sim) if sim.tick - sim.last_activity_tick >= Simulation.STALL_TICKS else ""
		return
	var inputs_done := true
	for id in sim.machines:
		var m: Machine = sim.machines[id]
		if m.type in ["input", "usb_input"] and m.emitted < m.stream.size():
			inputs_done = false
	if inputs_done and sim.packets_in_flight() == 0 and sim.tick > 1:
		_fail_missing(sim, "All input was consumed, but some results never arrived.")
		return
	if sim.tick - sim.last_activity_tick >= Simulation.STALL_TICKS:
		_fail_missing(sim, _stall_reason(sim))


func _all_complete() -> bool:
	for ch in def.outputs.size():
		if progress[ch] < def.outputs[ch]["expected"].size():
			return false
	return true


func _fail(sim: Simulation, title: String, reason: String, expected: String, p: Packet, view := ViewMode.Mode.BIN, expected_bv: BitVector = null, machines: Array = []) -> void:
	status = Status.FAIL
	var ids := machines.duplicate()
	if ids.is_empty():
		ids = _ids_on_path(sim, p.path)
	var exp_bits := "" if expected_bv == null else ViewMode.format(expected_bv, ViewMode.Mode.BIN)
	failure = {
		"title": title, "reason": reason, "expected": expected,
		"received": p.label(view), "expected_bits": exp_bits,
		"received_bits": ViewMode.format(p.data, ViewMode.Mode.BIN),
		"packet": p.id, "path": p.path, "machines": ids, "tick": sim.tick,
	}


func _fail_missing(sim: Simulation, reason: String) -> void:
	status = Status.FAIL
	var got := correct_total()
	var ids := []
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.state == Machine.State.BLOCKED:
			ids.append(id)
			continue
		for port in m.outq:
			if m.outq[port] != null and sim.connection_at_port(id, port) == null:
				ids.append(id)
				break
	failure = {
		"title": "Missing results", "reason": reason,
		"expected": "%d values" % def.expected_total(), "received": "%d values" % got,
		"expected_bits": "", "received_bits": "",
		"packet": -1, "path": PackedStringArray(), "machines": ids, "tick": sim.tick,
	}


func _stall_reason(sim: Simulation) -> String:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		for port in m.outq:
			if m.outq[port] != null and sim.connection_at_port(id, port) == null:
				return "%s holds a result but its %s port is not wired." % [m.label, port.to_upper()]
		if m.type == "gate" and not m.inq["in"].is_empty() and m.inq["ctrl"].is_empty() and sim.connection_at_port(id, "ctrl") == null:
			return "%s is waiting for a control signal — wire a BOOLEAN into its EN port." % m.label
	return "Nothing has moved for %d ticks — packets are stuck somewhere." % Simulation.STALL_TICKS


func _ids_on_path(sim: Simulation, path: PackedStringArray) -> Array:
	var ids := []
	for id in sim.sorted_machine_ids():
		if sim.machines[id].label in path:
			ids.append(id)
	return ids


## Optional goals, evaluated on a finished run: [{label, met, value}]
func goal_results(sim: Simulation) -> Array:
	var out := []
	for g in def.goals:
		var v: float
		match g["kind"]:
			"power": v = sim.total_power()
			"components": v = sim.component_count()
			"latency": v = sim.avg_latency()
			"throughput": v = sim.throughput()
			_: v = 0
		var met := v <= float(g["max"]) if g.has("max") else v >= float(g.get("min", 0))
		out.append({"label": g["label"], "met": met and status == Status.PASS, "value": v, "kind": g["kind"]})
	return out


func stars(sim: Simulation) -> int:
	if status != Status.PASS:
		return 0
	var s := 1
	for r in goal_results(sim):
		if r["met"]:
			s += 1
	return min(s, 3)
