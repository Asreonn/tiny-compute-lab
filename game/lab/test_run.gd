class_name TestRun
extends RefCounted
## One run of a test set on one source for one quest (JOB C7b — TEST before LIVE, Lab side).
## The run emits known vectors into the circuit, tracks where each one is, and resolves it to
## an exact verdict (pass / fail / stalled) against the quest's contract. Pure data — no Node.
##
## status: "idle" (not emitted) | "pending" | "pass" | "fail" | "stalled".

var id := 0
var source := -1            # machine id (USB socket or NIC)
var channel := ""           # "" (USB) or "a" | "b" | "c" (NIC RX)
var quest := -1
var vectors: Array = []     # [{value: BitVector, seq: int, note: String, expected: Variant, emitted: int (tick, -1), deliveries: Array[BitVector], status: String, where: String}]
var queue: Array[int] = []  # indices waiting to be emitted (RUN TEST SET: one per 10 ticks)
var next_tick := 0
var version := -1           # sim.layout_version when the run started (a result is valid for this circuit only)
const STALL_TICKS := 150


## Fill the fields and the vector list. The test set comes from, in order of preference:
##   1. the quest's LevelDef "tests" entries ({value: "BIN string"} or {seq: int}, plus note);
##   2. for a NIC channel, the bound source's default test_vectors;
##   3. otherwise the first 4 values of the source (seq 0..3), notes "value 1" … "value 4".
## Entries that give no BitVector are skipped.
static func build(lab, sim: Simulation, run_id: int, mid: int, channel: String, q: int) -> TestRun:
	var tr := TestRun.new()
	tr.id = run_id
	tr.source = mid
	tr.channel = channel
	tr.quest = q
	tr.version = sim.layout_version
	var m: Machine = sim.machines.get(mid)
	var entries: Array = []
	var lv: Dictionary = LabDef.level(q)
	if lv.has("tests") and lv["tests"] is Array:
		entries = lv["tests"]
	if entries.is_empty() and m != null and m.type == "nic":
		var def: RemoteSourceDef = SourceStream.source(str(m.params.get("rx_" + channel, "")))
		if def != null:
			entries = def.test_vectors
	if entries.is_empty():
		for i in 4:
			entries.append({"seq": i, "note": "value %d" % (i + 1)})
	for e in entries:
		var v := _vector_value(sim, m, channel, e)
		if v == null:
			continue
		tr.vectors.append({
			"value": v,
			"seq": int(e.get("seq", -1)),
			"note": str(e.get("note", "")),
			"expected": null,
			"emitted": -1,
			"deliveries": [],
			"status": "idle",
			"where": "",
		})
	return tr


## The BitVector of one test entry: its "value" (a BIN string), or the source's value at its
## "seq" (USB: the stream, cycling; NIC: the deterministic record generator). null when none.
static func _vector_value(sim: Simulation, m: Machine, channel: String, e: Dictionary) -> BitVector:
	if e.has("value"):
		return BitVector.from_bin(str(e["value"]))
	if not e.has("seq"):
		return null
	var seq := int(e["seq"])
	if m == null:
		return null
	if m.type == "usb_input" and m.socket:
		if m.stream.is_empty():
			return null
		var v: Variant = m.stream[seq % m.stream.size()]
		return v if v is BitVector else null
	if m.type == "nic":
		var def: RemoteSourceDef = SourceStream.source(str(m.params.get("rx_" + channel, "")))
		if def == null:
			return null
		return SourceStream.record(def, SourceStream.population(), seq)
	return null


## Emit the first "idle" vector now (SEND TEST FRAME); false when none is left.
func send_next(sim: Simulation, lab) -> bool:
	for i in vectors.size():
		if vectors[i]["status"] == "idle":
			_emit(sim, lab, i)
			return true
	return false


## Queue every "idle" vector index, in order (RUN TEST SET: one per 10 ticks).
func run_all(sim: Simulation) -> void:
	queue.clear()
	for i in vectors.size():
		if vectors[i]["status"] == "idle":
			queue.append(i)
	next_tick = sim.tick


func _emit(sim, lab, i: int) -> void:
	var v: Dictionary = vectors[i]
	var p: Packet = sim.emit_test(source, channel, v["value"], v["seq"], id, i)
	if p == null:
		return
	v["expected"] = lab.quest_contract(quest).expected_for(p, lab._socket_ids_for(sim, quest))
	v["emitted"] = sim.tick
	v["status"] = "pending"


## A delivery of this run's packet: append its payload to the vector's deliveries. Raw packets
## and unknown indices are ignored.
func on_delivery(p: Packet) -> void:
	if p.is_raw():
		return
	for k in p.origins:
		var e: Dictionary = p.origins[k]
		if int(e.get("run", -1)) != id or not e.has("test"):
			continue
		var i := int(e["test"])
		if i < 0 or i >= vectors.size():
			return
		(vectors[i]["deliveries"] as Array).append(p.data)
		return


## Tick the run: emit one queued vector per Lab second, then check every pending/stalled vector
## against where its packets are. A vector still anywhere after STALL_TICKS shows STALLED at the
## first holder; once nothing of it is left it resolves to pass/fail (a stalled vector keeps
## being checked the same way, so it can still resolve later).
func update(sim: Simulation, lab) -> void:
	if not queue.is_empty() and sim.tick >= next_tick:
		var i: int = queue.pop_front()
		_emit(sim, lab, i)
		next_tick = sim.tick + Simulation.TICKS_PER_SEC
	var where: Dictionary = sim.test_packets(id)
	for i in vectors.size():
		var v: Dictionary = vectors[i]
		var st: String = v["status"]
		if st != "pending" and st != "stalled":
			continue
		if where.has(i):
			if st == "pending" and sim.tick - int(v["emitted"]) > STALL_TICKS:
				v["status"] = "stalled"
				var holders: Array = where[i]
				v["where"] = str(holders[0]["label"]) if not holders.is_empty() else "a wire"
			continue
		_resolve(v)


## Exact verdict: DROP expected passes with no deliveries; a BitVector expected passes with
## exactly one equal delivery; anything else fails.
func _resolve(v: Dictionary) -> void:
	var exp: Variant = v["expected"]
	var ok := false
	if exp is String:
		ok = (v["deliveries"] as Array).is_empty()
	elif exp is BitVector:
		var ds: Array = v["deliveries"]
		ok = ds.size() == 1 and (ds[0] as BitVector).equals(exp)
	v["status"] = "pass" if ok else "fail"


## True when nothing waits in the queue and every emitted vector is resolved.
func done() -> bool:
	if not queue.is_empty():
		return false
	for v in vectors:
		var st: String = v["status"]
		if st == "pending" or st == "stalled":
			return false
	return true


## Vectors resolved as PASS so far.
func passed() -> int:
	var n := 0
	for v in vectors:
		if v["status"] == "pass":
			n += 1
	return n


## Vectors emitted so far.
func total() -> int:
	var n := 0
	for v in vectors:
		if v["status"] != "idle":
			n += 1
	return n


## True when the run is done, every vector was emitted and all of them passed.
func all_pass() -> bool:
	if not done() or total() != vectors.size():
		return false
	for v in vectors:
		if v["status"] != "pass":
			return false
	return true


## One line per vector: circled number + note + outcome, e.g. "① valid record — PASS",
## "③ invalid flag — delivered 101, expected: not delivered".
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for i in vectors.size():
		var v: Dictionary = vectors[i]
		var line := "%s %s — " % [_circle(i + 1), str(v["note"])]
		match str(v["status"]):
			"pass":
				line += "PASS"
			"stalled":
				line += "STALLED at %s" % str(v["where"])
			"fail":
				line += _failure_text(v)
			_:
				line += "pending"
		out.append(line)
	return out


func _failure_text(v: Dictionary) -> String:
	var ds: Array = v["deliveries"]
	var exp: Variant = v["expected"]
	if exp is String:
		return "delivered %s, expected: not delivered" % _fmt_deliveries(ds)
	if exp is BitVector:
		var want := _bin(exp as BitVector)
		if ds.is_empty():
			return "not delivered, expected %s" % want
		return "delivered %s, expected %s" % [_fmt_deliveries(ds), want]
	return "no expectation"


func summary() -> String:
	return "%d / %d PASS" % [passed(), vectors.size()]


static func _fmt_deliveries(ds: Array) -> String:
	var parts := PackedStringArray()
	for d in ds:
		if d is BitVector:
			parts.append(_bin(d as BitVector))
	return ", ".join(parts)


static func _bin(bv: BitVector) -> String:
	var s := ""
	for k in range(bv.width - 1, -1, -1):
		s += "1" if bv.bit(k) != 0 else "0"
	return s


## ① ② … ⑩ for 1..10, then "(11)".
static func _circle(n: int) -> String:
	if n >= 1 and n <= 10:
		return ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"][n - 1]
	return "(%d)" % n