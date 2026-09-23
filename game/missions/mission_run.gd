class_name MissionRun
extends RefCounted
## Runtime validation of a mission against the simulation. Explains *why* a run fails.

enum Status { RUNNING, PASS, FAIL }

const SETTLE_TICKS := 20  # after the last expected output, wait for stray extras

var def: MissionDef
var status: int = Status.RUNNING
var progress: Array = []  # per output channel: correct count
var remaining: Array = []  # per output channel (unordered): values still expected
var failure: Dictionary = {}  # {title, reason, expected, received, packet, path: PackedStringArray, machines: Array[int]}
var complete_tick := -1
var discarded := 0


func _init(p_def: MissionDef) -> void:
	def = p_def


func allows(type: String) -> bool:
	return type in def.allowed


## Place the locked Input/Output machines for this mission on a fresh board.
func build_board(sim: Simulation) -> void:
	sim.clear()
	sim.size = def.board_size
	sim.mission = self
	for i in def.inputs.size():
		var d: Dictionary = def.inputs[i]
		var m := Machine.new(0, "input", d["cell"], int(d.get("rot", 0)))
		m.locked = true
		m.port_types = {"out": int(d.get("type", DataType.NUMBER))}
		sim.add_machine(m)
		m.label = "Input" if def.inputs.size() == 1 else "Input %s" % char(65 + i)
	for i in def.outputs.size():
		var d: Dictionary = def.outputs[i]
		var m := Machine.new(0, "output", d["cell"], int(d.get("rot", 0)))
		m.locked = true
		m.channel = i
		m.port_types = {"in": int(d.get("type", DataType.NUMBER))}
		sim.add_machine(m)
		m.label = "Output" if def.outputs.size() == 1 else "Output %s" % char(65 + i)
	reset(sim)
	sim.changed.emit()


func reset(sim: Simulation) -> void:
	status = Status.RUNNING
	failure = {}
	complete_tick = -1
	discarded = 0
	progress = []
	remaining = []
	for o in def.outputs:
		progress.append(0)
		remaining.append(o["expected"].duplicate())
	var ii := 0
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "input" and m.locked and ii < def.inputs.size():
			var d: Dictionary = def.inputs[ii]
			m.stream = d["values"]
			m.stream_type = int(d.get("type", DataType.NUMBER))
			m.interval = int(d.get("interval", 3))
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


func accuracy() -> float:
	var t := def.expected_total()
	return 100.0 * correct_total() / float(t) if t > 0 else 100.0


# ------------------------------------------------------------------ hooks

func on_output(sim: Simulation, m: Machine, p: Packet) -> void:
	if status != Status.RUNNING:
		return
	var ch := m.channel
	var out: Dictionary = def.outputs[ch]
	var want: Array = out["expected"]
	var ordered: bool = out.get("ordered", true)
	var mname := m.label
	if ordered:
		var i: int = progress[ch]
		if i >= want.size():
			_fail(sim, "Unexpected extra output", "%s already received all %d expected values." % [mname, want.size()], "—", p)
			return
		if not _same(want[i], p.value):
			_fail(sim, "Wrong value", "Result #%d at %s is incorrect." % [i + 1, mname], DataType.format_value(p.type, want[i]), p)
			return
		progress[ch] = i + 1
	else:
		var idx := -1
		for k in remaining[ch].size():
			if _same(remaining[ch][k], p.value):
				idx = k
				break
		if idx < 0:
			var want_s := "one of " + ", ".join(remaining[ch].map(func(v): return DataType.format_value(p.type, v))) if not remaining[ch].is_empty() else "—"
			_fail(sim, "Wrong value" if not remaining[ch].is_empty() else "Unexpected extra output", "%s received a value that is not expected." % mname, want_s, p)
			return
		remaining[ch].remove_at(idx)
		progress[ch] += 1
	if _all_complete() and complete_tick < 0:
		complete_tick = sim.tick


func on_overflow(sim: Simulation, m: Machine, p: Packet) -> void:
	if status != Status.RUNNING:
		return
	_fail(sim, "Input overflow", "%s could not send packet #%d — the line downstream is full. Data arrives faster than your machine processes it." % [m.label, p.id], DataType.format_value(p.type, p.value), p, [m.id])


func after_tick(sim: Simulation) -> void:
	if status != Status.RUNNING:
		return
	if complete_tick >= 0:
		if sim.packets_in_flight() == 0 or sim.tick - complete_tick >= SETTLE_TICKS:
			status = Status.PASS
		return
	var inputs_done := true
	for id in sim.machines:
		var m: Machine = sim.machines[id]
		if m.type == "input" and m.emitted < m.stream.size():
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


static func _same(a, b) -> bool:
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return bool(a) == bool(b)
	return is_equal_approx(float(a), float(b))


func _fail(sim: Simulation, title: String, reason: String, expected: String, p: Packet, machines: Array = []) -> void:
	status = Status.FAIL
	var ids := machines.duplicate()
	if ids.is_empty():
		ids = _ids_on_path(sim, p.path)
	failure = {
		"title": title, "reason": reason, "expected": expected,
		"received": p.label(), "packet": p.id, "path": p.path, "machines": ids, "tick": sim.tick,
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
