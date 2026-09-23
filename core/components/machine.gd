class_name Machine
extends RefCounted
## Runtime state + behaviour of one placed machine. Pure logic, no nodes.
## Rendering (MachineView) only *reads* this object.

enum State { IDLE, RECEIVING, PROCESSING, OUTPUT_READY, BLOCKED, ERROR, DISABLED }
const STATE_NAMES := ["IDLE", "RECEIVING", "PROCESSING", "OUTPUT READY", "BLOCKED", "ERROR", "DISABLED"]

var id: int
var type: String
var cell: Vector2i
var rot: int = 0
var params: Dictionary = {}
var locked := false  # placed by the mission (IO); cannot be moved or deleted
var label: String = ""  # e.g. "Multiply #2" — used in packet paths
var port_types: Dictionary = {}  # per-instance datatype overrides (mission IO)

# --- runtime (reset() clears) ---
var inq: Dictionary = {}  # in/ctrl port id -> Array[Packet]
var outq: Dictionary = {}  # out port id -> Packet or null
var job: Dictionary = {}  # {ticks_left, total, results: {port: Packet}, input: Packet}
var state: int = State.IDLE
var error_text := ""
var processed := 0
var busy_ticks := 0
var blocked_ticks := 0
var starved_full_ticks := 0  # ticks the inputs were full while busy (bottleneck signal)
var received_ports: PackedStringArray = PackedStringArray()  # this tick (view flashes)
var sent_ports: PackedStringArray = PackedStringArray()
var rr := 0  # round-robin cursor (splitter/merger)
var counter := 0
var delay_line: Array = []  # [[Packet, ready_tick], ...]

# Input/Output machines are configured by the mission.
var stream: Array = []  # input: values to emit
var stream_type: int = DataType.NUMBER
var interval := 1  # input: ticks between packets
var strict := false  # input: drop (and fail) instead of waiting when blocked
var next_emit := 0
var emitted := 0
var channel := 0  # output: which expected stream it validates
var received: Array = []  # output: Packet list


func _init(p_id: int, p_type: String, p_cell: Vector2i, p_rot: int = 0, p_params: Dictionary = {}) -> void:
	id = p_id
	type = p_type
	cell = p_cell
	rot = p_rot
	params = Catalog.default_params(type)
	for k in p_params:
		params[k] = p_params[k]
	label = "%s #%d" % [Catalog.def(type)["name"], id]
	reset()


func def() -> Dictionary:
	return Catalog.def(type)


func ports() -> Array:
	return Catalog.def(type)["ports"]


func processing_ticks() -> int:
	return int(Catalog.def(type)["ticks"])


func power() -> int:
	return int(Catalog.def(type)["power"])


func in_capacity(port_id: String) -> int:
	if type == "buffer" and port_id == "in":
		return int(params.get("capacity", 4))
	return 1


func footprint() -> Array[Vector2i]:
	var s := Catalog.size_of(type, rot)
	var out: Array[Vector2i] = []
	for y in s.y:
		for x in s.x:
			out.append(cell + Vector2i(x, y))
	return out


## World-grid information about a port after rotation: {cell, side, outside}
## `outside` is the neighbouring tile a wire must start/end on.
func port_geom(port_id: String) -> Dictionary:
	var pd := Catalog.port_def(type, port_id)
	var base: Vector2i = Catalog.SIZES[def()["size"]]
	var c := cell + Catalog.rotate_cell(pd["cell"], base, rot)
	var side := Catalog.rotate_side(pd["side"], rot)
	return {"cell": c, "side": side, "outside": c + Catalog.side_vec(side), "type": port_type(port_id), "dir": pd["dir"]}


func port_type(port_id: String) -> int:
	return int(port_types.get(port_id, Catalog.port_def(type, port_id)["type"]))


func reset() -> void:
	inq.clear()
	outq.clear()
	for p in ports():
		if p["dir"] == Catalog.DIR_OUT:
			outq[p["id"]] = null
		else:
			inq[p["id"]] = []
	job = {}
	state = State.IDLE
	error_text = ""
	processed = 0
	busy_ticks = 0
	blocked_ticks = 0
	starved_full_ticks = 0
	received_ports = PackedStringArray()
	sent_ports = PackedStringArray()
	rr = 0
	counter = 0
	delay_line = []
	next_emit = 0
	emitted = 0
	received = []


func can_accept(port_id: String) -> bool:
	if not inq.has(port_id):
		return false
	if type == "delay":
		return delay_line.size() + inq[port_id].size() < int(params.get("ticks", 3))
	return inq[port_id].size() < in_capacity(port_id)


func accept(port_id: String, p: Packet) -> void:
	inq[port_id].append(p)
	received_ports.append(port_id)


func queued_count() -> int:
	var n := 0
	for k in inq:
		n += inq[k].size()
	return n + delay_line.size()


func outputs_empty() -> bool:
	for k in outq:
		if outq[k] != null:
			return false
	return true


func has_pending_output() -> bool:
	return not outputs_empty()


## Packets currently inside this machine, for the view: [{packet, where: "in:<port>"|"core"|"out:<port>", index}]
func packets_inside() -> Array:
	var out := []
	for k in inq:
		var i := 0
		for p in inq[k]:
			out.append({"packet": p, "where": "in:" + k, "index": i})
			i += 1
	for i in delay_line.size():
		out.append({"packet": delay_line[i][0], "where": "core", "index": i})
	if not job.is_empty() and job.has("input") and job["input"] != null:
		out.append({"packet": job["input"], "where": "core", "index": 0})
	for k in outq:
		if outq[k] != null:
			out.append({"packet": outq[k], "where": "out:" + k, "index": 0})
	return out


func job_progress() -> float:
	if job.is_empty():
		return 0.0
	return 1.0 - float(job["ticks_left"]) / float(max(1, job["total"]))


# ---------------------------------------------------------------- tick phases

## Phase: advance processing. Completed jobs move their results to output slots.
func advance(_sim) -> void:
	if job.is_empty():
		return
	busy_ticks += 1
	job["ticks_left"] -= 1
	if job["ticks_left"] <= 0:
		for port in job["results"]:
			outq[port] = job["results"][port]
		job = {}
		processed += 1


## Phase: start a new job if inputs are ready and all output slots are free.
func start(sim) -> void:
	if not job.is_empty():
		return
	match type:
		"input":
			_start_input(sim)
		"output":
			_start_output(sim)
		"delay":
			_start_delay(sim)
		_:
			if not outputs_empty():
				return
			_start_generic(sim)


func _begin(results: Dictionary, input: Packet, ticks: int = -1) -> void:
	job = {"ticks_left": processing_ticks() if ticks < 0 else ticks, "total": processing_ticks() if ticks < 0 else ticks, "results": results, "input": input}


func _pop(port: String) -> Packet:
	var p: Packet = inq[port].pop_front()
	p.path.append(label)
	return p


func _start_generic(sim) -> void:
	match type:
		"add", "multiply", "processor", "compare", "counter":
			if inq["in"].is_empty():
				return
			var p := _pop("in")
			var out_type := DataType.NUMBER
			var v: Variant = null
			var x = p.value
			match type:
				"add":
					v = x + int(params["k"])
				"multiply":
					v = x * int(params["k"])
				"processor":
					match str(params["op"]):
						"x³": v = x * x * x
						"|x|": v = abs(x)
						"−x": v = -x
						_: v = x * x
				"compare":
					out_type = DataType.BOOLEAN
					v = _compare(x, str(params["op"]), int(params["k"]))
				"counter":
					counter += 1
					v = counter
			_begin({"out": p.derive(sim.new_packet_id(), out_type, v)}, p)
		"gate":
			if inq["in"].is_empty() or inq["ctrl"].is_empty():
				return
			var d := _pop("in")
			var c := _pop("ctrl")
			if c.value:
				_begin({"out": d}, d)
			else:
				_begin({}, d)  # consumed and discarded after processing
				sim.note_discard(self, d)
		"splitter":
			if inq["in"].is_empty():
				return
			var p := _pop("in")
			if str(params["mode"]) == "Duplicate":
				_begin({"a": p, "b": p.derive(sim.new_packet_id(), p.type, p.value)}, p)
			else:
				var port := "a" if rr % 2 == 0 else "b"
				# prefer a port whose wire can take it; stay deterministic
				if not sim.output_connected(self, port):
					port = "b" if port == "a" else "a"
				rr += 1
				_begin({port: p}, p)
		"merger":
			var order := ["a", "b"] if rr % 2 == 0 else ["b", "a"]
			for port in order:
				if not inq[port].is_empty():
					var p := _pop(port)
					rr = 1 if port == "a" else 0
					_begin({"out": p}, p)
					return
		"buffer":
			if inq["in"].is_empty():
				return
			var p := _pop("in")
			_begin({"out": p}, p)


static func _compare(x, op: String, k: int) -> bool:
	match op:
		">": return x > k
		"<": return x < k
		"=": return x == k
		"≥": return x >= k
		"≤": return x <= k
		"≠": return x != k
	return false


func _start_delay(sim) -> void:
	# accept arrivals into the delay line, stamped with their release tick
	while not inq["in"].is_empty():
		var p := _pop("in")
		delay_line.append([p, sim.tick + int(params.get("ticks", 3))])
	if outq["out"] == null and not delay_line.is_empty() and sim.tick >= delay_line[0][1]:
		outq["out"] = delay_line.pop_front()[0]
		processed += 1


func _start_input(sim) -> void:
	if emitted >= stream.size() or sim.tick < next_emit:
		return
	if outq["out"] != null:
		if strict:
			var lost := Packet.new(sim.new_packet_id(), stream_type, stream[emitted], sim.tick)
			lost.path.append(label)
			emitted += 1
			next_emit = sim.tick + interval
			sim.note_overflow(self, lost)
		return
	var p := Packet.new(sim.new_packet_id(), stream_type, stream[emitted], sim.tick)
	p.path.append(label)
	outq["out"] = p
	emitted += 1
	next_emit = sim.tick + interval
	processed += 1


func _start_output(sim) -> void:
	if inq["in"].is_empty():
		return
	var p := _pop("in")
	received.append(p)
	processed += 1
	sim.note_output(self, p)


## Refresh the visible state after all phases ran this tick.
func update_state(blocked_now: bool) -> void:
	if state == State.ERROR:
		return
	if blocked_now:
		blocked_ticks += 1
		state = State.BLOCKED
	elif not job.is_empty():
		state = State.PROCESSING
		if queued_count() >= _total_in_capacity():
			starved_full_ticks += 1
	elif has_pending_output():
		state = State.OUTPUT_READY
	elif received_ports.size() > 0:
		state = State.RECEIVING
	else:
		state = State.IDLE


func _total_in_capacity() -> int:
	var n := 0
	for k in inq:
		n += in_capacity(k)
	return n


func set_error(msg: String) -> void:
	state = State.ERROR
	error_text = msg


# ---------------------------------------------------------------- persistence

func to_dict() -> Dictionary:
	return {"type": type, "cell": [cell.x, cell.y], "rot": rot, "params": params.duplicate(), "locked": locked, "channel": channel}


static func from_dict(p_id: int, d: Dictionary) -> Machine:
	var m := Machine.new(p_id, d["type"], Vector2i(d["cell"][0], d["cell"][1]), int(d.get("rot", 0)), d.get("params", {}))
	m.locked = d.get("locked", false)
	m.channel = int(d.get("channel", 0))
	return m
