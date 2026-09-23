class_name Machine
extends RefCounted
## Runtime state + behaviour of one placed machine. Pure logic, no nodes.
## Rendering (MachineView) only *reads* this object.
## Behaviour lives in core/components/logic/*; this class keeps instance state.

enum State { IDLE, RECEIVING, PROCESSING, OUTPUT_READY, BLOCKED, ERROR, DISABLED }
const STATE_NAMES := ["IDLE", "RECEIVING", "PROCESSING", "OUTPUT READY", "BLOCKED", "ERROR", "DISABLED"]

var id: int
var type: String
var cell: Vector2i
var rot: int = 0
var width: int = 1  # instance width; port widths of "W" resolve to this
var params: Dictionary = {}
var locked := false  # placed by the mission (IO); cannot be moved or deleted
var label: String = ""  # e.g. "Multiply #2" — used in packet paths

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
var last_carry := 0  # Add: carry out of the most recent addition
var carries := 0  # Add: total carry-outs this run

# Input/Output machines are configured by the mission.
var stream: Array = []  # input: Array[BitVector] to emit
var interval := 1  # input: ticks between packets
var strict := false  # input: drop (and fail) instead of waiting when blocked
var next_emit := 0
var emitted := 0
var channel := 0  # output: which expected stream it validates
var received: Array = []  # output: Packet list


func _init(p_id: int, p_type: String, p_cell: Vector2i, p_width: int, p_rot: int = 0, p_params: Dictionary = {}) -> void:
	id = p_id
	type = p_type
	cell = p_cell
	width = p_width
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


## Effective width of a port: an explicit int, or the instance width for "W".
func port_width(port_id: String) -> int:
	var pd := Catalog.port_def(type, port_id)
	if pd.is_empty():
		return width
	var w: Variant = pd["width"]
	if typeof(w) == TYPE_STRING:
		return width
	return int(w)


## World-grid information about a port after rotation: {cell, side, outside, width, role, bus, dir}
## `outside` is the neighbouring tile a wire must start/end on.
func port_geom(port_id: String) -> Dictionary:
	var pd := Catalog.port_def(type, port_id)
	var base: Vector2i = Catalog.SIZES[def()["size"]]
	var c := cell + Catalog.rotate_cell(pd["cell"], base, rot)
	var side := Catalog.rotate_side(pd["side"], rot)
	return {
		"cell": c, "side": side, "outside": c + Catalog.side_vec(side),
		"width": port_width(port_id), "role": pd.get("role", Catalog.ROLE_DATA),
		"bus": bool(pd.get("bus", false)), "dir": pd["dir"],
	}


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
	last_carry = 0
	carries = 0
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
## Delegates the per-type behaviour to ComponentLogic.
func start(sim) -> void:
	if not job.is_empty():
		return
	ComponentLogic.for_type(type).start(self, sim)


## Called by ComponentLogic to occupy the machine for `ticks` (default: processing time).
func begin_job(results: Dictionary, input: Packet, ticks: int = -1) -> void:
	var t := processing_ticks() if ticks < 0 else ticks
	job = {"ticks_left": t, "total": t, "results": results, "input": input}


func pop(port: String) -> Packet:
	var p: Packet = inq[port].pop_front()
	p.path.append(label)
	return p


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
	return {"type": type, "cell": [cell.x, cell.y], "rot": rot, "width": width, "params": params.duplicate(), "locked": locked, "channel": channel}


static func from_dict(p_id: int, d: Dictionary, fallback_width: int) -> Machine:
	var w := int(d["width"]) if d.has("width") else fallback_width
	var m := Machine.new(p_id, d["type"], Vector2i(d["cell"][0], d["cell"][1]), w, int(d.get("rot", 0)), d.get("params", {}))
	m.locked = d.get("locked", false)
	m.channel = int(d.get("channel", 0))
	return m
