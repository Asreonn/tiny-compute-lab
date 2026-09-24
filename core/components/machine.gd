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
## Resolved width of a "*" port (any-width sink, e.g. usb_output): port id -> source width.
## Set by Simulation when a wire is connected; never touched by reset() (it is not runtime state).
var port_width_override: Dictionary = {}
var locked := false  # placed by the mission (IO); cannot be moved or deleted
var label: String = ""  # e.g. "Multiply #2" — used in packet paths

# --- runtime (reset() clears) ---
var inq: Dictionary = {}  # in/ctrl port id -> Array[Packet]
var outq: Dictionary = {}  # out port id -> Packet or null
var job: Dictionary = {}  # {work_left, work_total, ticks_left, total, results: {port: Packet}, input: Packet}
## Work units per tick at the normal clock (docs/SYSTEMS_EXPANSION.md §6). A job costs
## processing_ticks() * WORK_PER_TICK units; clock modes, brownout and heat scale the rate.
const WORK_PER_TICK := 12
const CLOCK_RATE := {"normal": 12, "fast": 16, "overclocked": 24}
const CLOCK_POWER := {"normal": 1.0, "fast": 1.5, "overclocked": 2.0}
const CLOCK_HEAT := {"normal": 1, "fast": 2, "overclocked": 4}
## Work units applied on the last advance (the progress ring interpolates with it).
var last_rate := WORK_PER_TICK
## Thermal work factor (E2): numerator / denominator; 0 = paused (CRITICAL).
var thermal_num := 1
var thermal_den := 1
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
var dropped := 0  # codec: values dropped this run (unencodable or of the wrong kind)

# Input/Output machines are configured by the mission.
var stream: Array = []  # input: Array[BitVector|RawValue] to emit
var interval := 1  # input: ticks between packets
var pattern: Array = []  # socket: optional intervals cycled per emitted value (bursts)
var pattern_idx := 0  # socket: next pattern slot to use
var strict := false  # input: drop (and fail) instead of waiting when blocked
var loop := false  # input: repeat the stream until the mission passes (campaign sources)
var campaign_timing := false  # set by the Simulation: campaign dwell times (Catalog.ticks)
var next_emit := 0
var emitted := 0
var channel := 0  # output: which expected stream it validates
var received: Array = []  # output: Packet list

# --- USB socket (lab): a locked usb_input the player plugs a data module into ---
var device: String = ""  # plugged module kind, "" = none (docs/SYSTEMS_EXPANSION.md §2)
var last_device: String = ""  # kind of the last plugged module; keeps the wire valid after removal
var socket := false  # true = lab socket semantics (module stream + 2-slot FIFO overrun)
var fifo: Array = []  # pending [value, seq] pairs, max 2; the oldest is dropped on overrun
var lost := 0  # overruns this run (values dropped from the FIFO)
var gen_seq := 0  # index of the next stream value to generate


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
	return Catalog.ticks(type, campaign_timing)


func power() -> int:
	return int(Catalog.def(type)["power"])


## "normal" | "fast" | "overclocked" (the clock param; machines without it run normal).
func clock_mode() -> String:
	var c := str(params.get("clock", "normal"))
	return c if CLOCK_RATE.has(c) else "normal"


func clock_rate() -> int:
	return int(CLOCK_RATE[clock_mode()])


## Rated power × the clock multiplier, rounded up (fast Add = 2, overclocked Multiply = 4).
func power_demand() -> int:
	return int(ceil(power() * float(CLOCK_POWER[clock_mode()])))


func heat_mult() -> int:
	return int(CLOCK_HEAT[clock_mode()])


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


## Raw width spec of a port: an int, "W", "P:<param>", "R:<param>" or "*".
## "*" marks an any-width sink (usb_output) — the ONLY exception to the width-match rule.
func port_width_spec(port_id: String) -> Variant:
	var pd := Catalog.port_def(type, port_id)
	if pd.is_empty():
		return "W"
	return pd["width"]


## True when this machine's stream carries RawValues instead of BitVectors: a USB line with
## a data module plugged in. It is what makes a raw source wireable to an Encoder
## (docs/SYSTEMS_EXPANSION.md §1); bit streams keep their normal data port.
func is_raw_source() -> bool:
	return not stream.is_empty() and stream[0] is RawValue


## Role of a port: the catalog's, except that a raw source exposes a raw output.
func port_role(port_id: String) -> String:
	var pd := Catalog.port_def(type, port_id)
	if pd.is_empty():
		return Catalog.ROLE_DATA
	if pd.get("dir", "") == Catalog.DIR_OUT:
		# A lab socket's role follows the plugged module (or the last one, so removing a
		# device never invalidates the wire); every other source follows its stream.
		if socket:
			var kind := device if device != "" else last_device
			return Catalog.ROLE_RAW if Devices.out_kind(kind) == "raw" else Catalog.ROLE_DATA
		if is_raw_source():
			return Catalog.ROLE_RAW
	return pd.get("role", Catalog.ROLE_DATA)


## Effective width of a port: an explicit int, the instance width for "W",
## "P:<param>" (= the instance param value), "R:<param>" (= instance width minus that param)
## or "*" (= the connected source width, 0 while unconnected).
## A raw port has width 0: raw links carry a semantic value, not a word.
func port_width(port_id: String) -> int:
	if port_role(port_id) == Catalog.ROLE_RAW:
		return 0
	var pd := Catalog.port_def(type, port_id)
	if pd.is_empty():
		return width
	var w: Variant = pd["width"]
	if typeof(w) == TYPE_INT:
		return int(w)
	# string form: "W", "P:<param>", "R:<param>", "*"
	var s: String = str(w)
	if s == "*":
		return int(port_width_override.get(port_id, 0))
	if s == "W":
		return width
	if s.begins_with("P:"):
		return int(params.get(s.substr(2), 0))
	if s.begins_with("R:"):
		return maxi(1, width - int(params.get(s.substr(2), 0)))
	return width


## World-grid information about a port after rotation: {cell, side, outside, width, role, bus, dir}
## `outside` is the neighbouring tile a wire must start/end on.
func port_geom(port_id: String) -> Dictionary:
	var pd := Catalog.port_def(type, port_id)
	var base: Vector2i = Catalog.SIZES[def()["size"]]
	var c := cell + Catalog.rotate_cell(pd["cell"], base, rot)
	var side := Catalog.rotate_side(pd["side"], rot)
	return {
		"cell": c, "side": side, "outside": c + Catalog.side_vec(side),
		"width": port_width(port_id), "role": port_role(port_id),
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
	dropped = 0
	next_emit = 0
	emitted = 0
	received = []
	fifo = []
	lost = 0
	gen_seq = 0
	pattern_idx = 0


func can_accept(port_id: String) -> bool:
	if not inq.has(port_id):
		return false
	# An output port with no device is not there: a wire into it must stall (SYSTEMS_EXPANSION §2.1).
	if type == "usb_output" and socket and device == "":
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
	return 1.0 - float(job["work_left"]) / float(max(1, job["work_total"]))


# ---------------------------------------------------------------- tick phases

## Phase: advance processing. Completed jobs move their results to output slots.
func advance(sim) -> void:
	if job.is_empty():
		return
	var rate: int = sim.work_rate(self) if sim != null and sim.has_method("work_rate") else WORK_PER_TICK
	last_rate = rate
	if rate <= 0:
		return  # paused (thermal CRITICAL): the job keeps its progress
	busy_ticks += 1
	job["work_left"] = int(job["work_left"]) - rate
	job["ticks_left"] = int(ceil(maxf(float(job["work_left"]), 0.0) / float(WORK_PER_TICK)))
	if int(job["work_left"]) <= 0:
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
	var w := t * WORK_PER_TICK
	job = {"work_left": w, "work_total": w, "ticks_left": t, "total": t, "results": results, "input": input}


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
	return {
		"type": type, "cell": [cell.x, cell.y], "rot": rot, "width": width,
		"params": params.duplicate(), "locked": locked, "channel": channel,
		"device": device, "last_device": last_device, "socket": socket,
	}


static func from_dict(p_id: int, d: Dictionary, fallback_width: int) -> Machine:
	var w := int(d["width"]) if d.has("width") else fallback_width
	var m := Machine.new(p_id, d["type"], Vector2i(d["cell"][0], d["cell"][1]), w, int(d.get("rot", 0)), d.get("params", {}))
	m.locked = d.get("locked", false)
	m.channel = int(d.get("channel", 0))
	m.device = str(d.get("device", ""))
	m.last_device = str(d.get("last_device", ""))
	m.socket = bool(d.get("socket", false))
	return m
