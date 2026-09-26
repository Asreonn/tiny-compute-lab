class_name Machine
extends RefCounted
## Runtime state + behaviour of one placed machine. Pure logic, no nodes.
## Rendering (MachineView) only *reads* this object.
## Behaviour lives in core/components/logic/*; this class keeps instance state.

enum State { IDLE, RECEIVING, PROCESSING, OUTPUT_READY, BLOCKED, ERROR, DISABLED }
const STATE_NAMES := ["IDLE", "RECEIVING", "PROCESSING", "OUTPUT READY", "BLOCKED", "ERROR", "DISABLED"]

var id: int
## The machine's kind: what its behaviour and art are keyed on. A variant ("add_quick") runs as
## its base ("add"); `variant` keeps its own id, so its numbers, name and params apply.
var type: String
var variant := ""
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
var outq: Dictionary = {}  # out port id -> Packet or null (the head of the output line)
var out_backlog: Dictionary = {}  # out port id -> Array[Packet] waiting behind the head
## Running jobs, up to lanes() (FACTORY_SYSTEMS §3.3). Each has today's job shape
## {work_left, work_total, ticks_left, total, results: {port: Packet}, input: Packet}.
var jobs: Array = []
## Read-only view of jobs[0] for readers that predate lanes ({} when nothing runs).
var job: Dictionary:
	get:
		return jobs[0] if not jobs.is_empty() else {}
## Work units per tick at the normal clock (docs/SYSTEMS_EXPANSION.md §6). A job costs
## processing_ticks() * WORK_PER_TICK units; clock modes, brownout and heat scale the rate.
const WORK_PER_TICK := 12
const CLOCK_RATE := {"normal": 12, "fast": 16, "overclocked": 24}
const CLOCK_POWER := {"normal": 1.0, "fast": 1.5, "overclocked": 2.0}
const CLOCK_HEAT := {"normal": 1, "fast": 2, "overclocked": 4}
## Clock power multipliers in quarters: ×4 / 16 = the float multipliers 1.0 / 1.5 / 2.0.
const CLOCK_Q := {"normal": 4, "fast": 6, "overclocked": 8}
## Efficiency power multipliers in quarters: standard 4/4, efficient 3/4.
const STANDARD_Q := 4
const EFFICIENT_Q := 3
## Work units applied on the last advance (the progress ring interpolates with it).
var last_rate := WORK_PER_TICK
## Thermal work factor (E2): numerator / denominator; 0 = paused (CRITICAL).
var thermal_num := 1
var thermal_den := 1
var work_done := 0  # work units applied this tick (the ThermalGrid turns them into heat)
var temp := 0  # hottest footprint tile, tenths of °C above ambient (ThermalGrid)
var heat_stage := 0  # ThermalGrid.Stage, with hysteresis
var state: int = State.IDLE
var error_text := ""
var processed := 0
var busy_ticks := 0
var blocked_ticks := 0
var starved_full_ticks := 0  # ticks the inputs were full while busy (bottleneck signal)
## The last 60 ticks of "all lanes busy and inputs full" as a bit window + popcount (§7.4).
var bound_hist := 0
var bound_cnt := 0
var received_ports: PackedStringArray = PackedStringArray()  # this tick (view flashes)
var sent_ports: PackedStringArray = PackedStringArray()
var rr := 0  # round-robin cursor (splitter/merger)
var counter := 0
var delay_line: Array = []  # [[Packet, ready_tick], ...]
var last_carry := 0  # Add: carry out of the most recent addition
var carries := 0  # Add: total carry-outs this run
var dropped := 0  # codec: values dropped this run (unencodable or of the wrong kind)
var orphans := 0  # waiting values discarded because their record can no longer be completed
var orphan_check_tick := -1000  # last tick the orphan scan ran (throttled, deterministic)
# memory / control machines (Group E–F)
var memory: Array = []  # register (1 cell), register bank (4), RAM (16): BitVector per cell
var held: Packet = null  # register: the packet last written (its lineage is re-emitted on read)
var primed := false  # register: the reset value was emitted; program counter: started
var last_mem_op := ""  # "read" / "write" (the Cells area shows it)

# Input/Output machines are configured by the mission.
var stream: Array = []  # input: Array[BitVector|RawValue] to emit
var interval := 1  # input: ticks between packets
var pattern: Array = []  # socket: optional intervals cycled per emitted value (bursts)
var burst := 1  # socket: values generated per emission (FACTORY_SYSTEMS §2.3)
var pattern_idx := 0  # socket: next pattern slot to use
var strict := false  # input: drop (and fail) instead of waiting when blocked
var loop := false  # input: repeat the stream until the mission passes (campaign sources)
var campaign_timing := false  # set by the Simulation: campaign dwell times (Catalog.ticks)
var next_emit := 0
var emitted := 0
var channel := 0  # output: which expected stream it validates
var received: Array = []  # output: Packet list

## Network fixture state (NicLogic): credit, per-channel remote buffers and counters.
var net: Dictionary = {}

# --- USB socket (lab): a locked usb_input the player plugs a data module into ---
var device: String = ""  # plugged module kind, "" = none (docs/SYSTEMS_EXPANSION.md §2)
var last_device: String = ""  # kind of the last plugged module; keeps the wire valid after removal
var socket := false  # true = lab socket semantics (module stream + 2-slot FIFO overrun)
## The remote source a Database Dump stick streams ("" = none): its values are that source's
## records, stamped with origins "source" so contracts can judge them (DATA_FACTORY §9.1).
var stream_source := ""
## Test mode (JOB C7a): the socket generates nothing; test vectors arrive via emit_test.
## A setting, like `device` — reset() must not clear it.
var test_mode := false
## Lab USB port: the rack row it opened at (its identity for saves), -1 otherwise.
var port_row := -1
var fifo: Array = []  # pending [value, seq] pairs, max 2; the oldest is dropped on overrun
var lost := 0  # overruns this run (values dropped from the FIFO)
var gen_seq := 0  # index of the next stream value to generate


## `p_type` is a machine type or a variant id (Catalog.is_variant).
func _init(p_id: int, p_type: String, p_cell: Vector2i, p_width: int, p_rot: int = 0, p_params: Dictionary = {}) -> void:
	id = p_id
	type = Catalog.base_type(p_type)
	variant = p_type if p_type != type else ""
	cell = p_cell
	width = p_width
	rot = p_rot
	params = Catalog.default_params(def_id())
	for k in p_params:
		params[k] = p_params[k]
	label = "%s #%d" % [def()["name"], id]
	reset()


## The id of the definition this machine was placed from: the variant, else its type. Saves,
## copies and the palette use it; behaviour checks use `type`.
func def_id() -> String:
	return variant if variant != "" else type


func def() -> Dictionary:
	return Catalog.def(def_id())


func ports() -> Array:
	return Catalog.def(type)["ports"]


func processing_ticks() -> int:
	return Catalog.ticks(def_id(), campaign_timing) + (1 if efficient() else 0)


func power() -> int:
	return int(def()["power"])


## The number of parallel jobs this machine may run: params "lanes" snapped to the allowed set
## {1, 2, 4, 8} and capped by the def's max_lanes (FACTORY_SYSTEMS §3).
func lanes() -> int:
	var l := int(params.get("lanes", "1"))
	var cap := maxi(1, int(def().get("max_lanes", 1)))
	for k in [8, 4, 2, 1]:
		if l >= k and cap >= k:
			return k
	return 1


## "efficient" trades one extra processing tick for ¾ power and ½ heat (FACTORY_SYSTEMS §3.1).
func efficient() -> bool:
	return str(params.get("efficiency", "standard")) == "efficient"


## Display-only generation label from lanes: 1/2/4/8 -> Mk1..Mk4.
func mk() -> int:
	match lanes():
		2: return 2
		4: return 3
		8: return 4
		_: return 1


## Heat per tick at the full normal-clock rate (tenths of °C): the rated heat scaled by the
## value width; efficient runs at half. Lanes scale heat through work_done, not here.
func heat() -> int:
	var h := Catalog.heat(def_id()) * Catalog.width_factor(width)
	if efficient():
		h /= 2
	return h


## "normal" | "fast" | "overclocked" (the clock param; machines without it run normal).
func clock_mode() -> String:
	var c := str(params.get("clock", "normal"))
	return c if CLOCK_RATE.has(c) else "normal"


func clock_rate() -> int:
	return int(CLOCK_RATE[clock_mode()])


## Rated power × lanes × width factor × clock multiplier × efficiency multiplier, computed in
## integer quarters (FACTORY_SYSTEMS §3.1). Normal / 1 lane / ≤5-bit keeps today's numbers:
## Add 1, fast Add 2, overclocked Multiply 4.
func power_demand() -> int:
	var q: int = power() * lanes() * Catalog.width_factor(width) * CLOCK_Q[clock_mode()] * (EFFICIENT_Q if efficient() else STANDARD_Q)
	return (q + 15) / 16


func heat_mult() -> int:
	return int(CLOCK_HEAT[clock_mode()])


## Idle baseline (DATA_FACTORY §2.0b): percent of the full-rate heat / power a powered part
## still costs while idle (the def's idle_pct, data-driven); 0 for unpowered or locked parts.
func idle_pct() -> int:
	if locked or power() <= 0:
		return 0
	return clampi(int(def().get("idle_pct", 12)), 0, 100)


## Heat generated this tick (tenths of °C): heat × clock heat × (idle share × lanes + active share
## × work done / clock rate). Full load is exactly the rated heat × lanes; an idle powered part
## still warms by idle_pct.
func heat_this_tick() -> int:
	var base := heat() * heat_mult()
	if base <= 0:
		return 0
	var cr := maxi(1, clock_rate())
	var idle := idle_pct()
	return base * (idle * lanes() * cr + (100 - idle) * work_done) / (100 * cr)


## Power drawn this tick: the idle share of power_demand() plus the active share scaled by the
## work done. A readout only — the power network sizes the rails for the peak power_demand().
func power_draw() -> int:
	var d := power_demand()
	if d <= 0:
		return 0
	var full := maxi(1, lanes() * clock_rate())
	var idle := idle_pct()
	var num := d * (idle * full + (100 - idle) * mini(work_done, full))
	return (num + 50 * full) / (100 * full)  # rounded to the nearest unit


## Values per Lab second at the current lanes / clock / processing ticks (FACTORY_SYSTEMS §3.3):
## lanes × clock work rate / (processing ticks × WORK_PER_TICK) × TICKS_PER_SEC. Used by the
## upgrade preview and the hover card.
func rate_per_sec() -> float:
	return float(lanes() * clock_rate()) / float(processing_ticks() * WORK_PER_TICK) * 10.0


func in_capacity(port_id: String) -> int:
	if type == "buffer" and port_id == "in":
		return int(params.get("capacity", 4))
	# Sinks drain a whole 8-lane bus in one tick (FACTORY_SYSTEMS §2.3): a multi-lane wire
	# may hand them several packets per tick and every one is validated that same tick.
	if type in ["output", "terminal_output", "usb_output"]:
		return 8
	# A part that combines several inputs holds one more value per input than it has lanes, so
	# an early value can wait for its record's partner (DATA_FACTORY §3.1). Waiting still fills
	# the queue and backs up the branch.
	if inq.size() >= 2:
		return lanes() + 1
	return maxi(1, lanes())


func footprint() -> Array[Vector2i]:
	var s := Catalog.size_of(type, rot)
	var out: Array[Vector2i] = []
	for y in s.y:
		for x in s.x:
			out.append(cell + Vector2i(x, y))
	return out


## Raw width spec of a port: an int, "W", "P:<param>", "R:<param>", "F:<i>", "F:+",
## "N:<param>" (the record width of the remote source bound to that param) or "*".
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


## Field widths of a field part (param "fields", MSB first): "6 3 4 3" / "6,3,4,3" -> [6, 3, 4, 3].
## At most 4 entries; entries that are not positive integers are skipped; each is clamped to 1..64.
func field_widths() -> Array:
	var out: Array = []
	for part in str(params.get("fields", "")).replace(",", " ").split(" ", false):
		if out.size() >= 4:
			break
		if part.is_valid_int() and int(part) > 0:
			out.append(clampi(int(part), 1, 64))
	return out


## Effective width of a port: an explicit int, the instance width for "W",
## "P:<param>" (= the instance param value), "R:<param>" (= instance width minus that param),
## "F:<i>" (= field i's width, 0 when unconfigured), "F:+" (= the sum of the field widths),
## "N:<param>" (= the bound remote source's record width, 0 while unbound/unknown)
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
	# string form: "W", "P:<param>", "R:<param>", "F:<i>", "F:+", "*"
	var s: String = str(w)
	if s == "*":
		return int(port_width_override.get(port_id, 0))
	if s == "W":
		return width
	if s.begins_with("P:"):
		return int(params.get(s.substr(2), 0))
	if s.begins_with("R:"):
		return maxi(1, width - int(params.get(s.substr(2), 0)))
	if s == "F:+":
		var fw := field_widths()
		var t := 0
		for f in fw:
			t += int(f)
		return t
	if s.begins_with("F:"):
		var fw2 := field_widths()
		var i := int(s.substr(2))
		return int(fw2[i]) if i < fw2.size() else 0
	if s.begins_with("N:"):
		var def: RemoteSourceDef = SourceStream.source(str(params.get(s.substr(2), "")))
		return def.width if def != null else 0
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
	bound_hist = 0
	bound_cnt = 0
	inq.clear()
	outq.clear()
	out_backlog = {}
	for p in ports():
		if p["dir"] == Catalog.DIR_OUT:
			outq[p["id"]] = null
			out_backlog[p["id"]] = []
		else:
			inq[p["id"]] = []
	jobs = []
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
	orphans = 0
	orphan_check_tick = -1000
	next_emit = 0
	emitted = 0
	received = []
	fifo = []
	lost = 0
	gen_seq = 0
	pattern_idx = 0
	memory = []
	held = null
	primed = false
	last_mem_op = ""
	net = {}
	work_done = 0
	temp = 0
	heat_stage = 0
	thermal_num = 1
	thermal_den = 1


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
	for k in out_backlog:
		if not out_backlog[k].is_empty():
			return false
	return true


func has_pending_output() -> bool:
	return not outputs_empty()


## Finished results waiting to leave: the outq heads plus every backlog packet.
func waiting_results() -> int:
	var n := 0
	for k in outq:
		if outq[k] != null:
			n += 1
	for k in out_backlog:
		n += out_backlog[k].size()
	return n


## A lane is free to start a job when running jobs + waiting results are below the lane count
## (FACTORY_SYSTEMS §3.3: a blocked output stalls every lane — back-pressure stays physical).
func has_free_lane() -> bool:
	return jobs.size() + waiting_results() < lanes()


## Packets currently inside this machine, for the view: [{packet, where: "in:<port>"|"core"|"out:<port>", index}]
## Running jobs are indexed by their lane; backlog packets sit behind the outq head (index 1..n).
func packets_inside() -> Array:
	var out := []
	for k in inq:
		var i := 0
		for p in inq[k]:
			out.append({"packet": p, "where": "in:" + k, "index": i})
			i += 1
	for i in delay_line.size():
		out.append({"packet": delay_line[i][0], "where": "core", "index": i})
	var lane := 0
	for j in jobs:
		if j.has("input") and j["input"] != null:
			out.append({"packet": j["input"], "where": "core", "index": lane})
		lane += 1
	for k in outq:
		if outq[k] != null:
			out.append({"packet": outq[k], "where": "out:" + k, "index": 0})
		var b := 1
		for p in out_backlog.get(k, []):
			out.append({"packet": p, "where": "out:" + k, "index": b})
			b += 1
	return out


func job_progress() -> float:
	if jobs.is_empty():
		return 0.0
	return 1.0 - float(jobs[0]["work_left"]) / float(max(1, jobs[0]["work_total"]))


## Progress (0..1) of every running job, in start order (lane 0 first).
func lane_progress() -> Array:
	var out := []
	for j in jobs:
		out.append(1.0 - float(j["work_left"]) / float(max(1, j["work_total"])))
	return out


# ---------------------------------------------------------------- tick phases

## Phase: advance processing. Completed jobs move their results to the output head, or onto
## the output backlog when the head is taken; finished jobs leave in start order.
func advance(sim) -> void:
	work_done = 0
	if jobs.is_empty():
		return
	var rate: int = sim.work_rate(self) if sim != null and sim.has_method("work_rate") else WORK_PER_TICK
	last_rate = rate
	if rate <= 0:
		return  # paused (thermal CRITICAL): the jobs keep their progress
	busy_ticks += 1
	var finished: Array = []
	for j in jobs:
		work_done += mini(rate, int(j["work_left"]))
		j["work_left"] = int(j["work_left"]) - rate
		j["ticks_left"] = int(ceil(maxf(float(j["work_left"]), 0.0) / float(WORK_PER_TICK)))
		if int(j["work_left"]) <= 0:
			finished.append(j)
	for j in finished:
		for port in j["results"]:
			if outq[port] == null:
				outq[port] = j["results"][port]
			else:
				out_backlog[port].append(j["results"][port])
		processed += 1
	if not finished.is_empty():
		var keep: Array = []
		for j in jobs:
			if j not in finished:
				keep.append(j)
		jobs = keep


## Take the head result of an output line and refill the head from the backlog.
func pop_output(port: String) -> Packet:
	var p: Packet = outq[port]
	outq[port] = out_backlog[port].pop_front() if not out_backlog[port].is_empty() else null
	return p


## Phase: start new jobs while inputs are ready and a lane is free. Several lanes can start in
## one tick when inputs are queued (a lane is only taken when the logic actually begins a job).
## Machines that push results straight out (IO sources/sinks, the delay line) bypass the lane
## gate so their own rules — socket overrun, strict overflow, the delay's fixed hold — hold.
func start(sim) -> void:
	if type in ["input", "usb_input", "output", "terminal_output", "usb_output", "delay", "constant", "clock", "nic"]:
		ComponentLogic.for_type(type).start(self, sim)
		return
	while true:
		if not has_free_lane():
			break
		var n := jobs.size()
		ComponentLogic.for_type(type).start(self, sim)
		if jobs.size() == n:
			break


## Called by ComponentLogic to occupy a lane for `ticks` (default: processing time).
func begin_job(results: Dictionary, input: Packet, ticks: int = -1) -> void:
	var t := processing_ticks() if ticks < 0 else ticks
	var w := t * WORK_PER_TICK
	jobs.append({"work_left": w, "work_total": w, "ticks_left": t, "total": t, "results": results, "input": input})


func pop(port: String) -> Packet:
	var p: Packet = inq[port].pop_front()
	p.path.append(label)
	return p


## Index of the first queued value on `port` that fits record `c` (ctx == c, or context-free);
## -1 when none. With c < 0 the first queued value fits.
func find_ctx(port: String, c: int) -> int:
	var q: Array = inq[port]
	for i in q.size():
		var k: int = (q[i] as Packet).ctx
		if c < 0 or k == c or k < 0:
			return i
	return -1


## The param key a tied input reads when unconnected ("" = the port is not tie-able).
func tie_param(port: String) -> String:
	return str(Catalog.port_def(type, port).get("tie", ""))


## True when `port` is tie-able and nothing is wired to it: it reads its tie param, never waits.
func is_tied(port: String, sim) -> bool:
	return tie_param(port) != "" and sim != null and not sim.input_connected(self, port)


## A fresh context-free value of the tie param at the port's width.
func tie_packet(port: String, sim) -> Packet:
	return Packet.new(sim.new_packet_id(), BitVector.of(int(params.get(tie_param(port), 0)), port_width(port)), sim.tick)


## Take one value from each of `ports` that all belong to the same record (DATA_FACTORY §3.1):
## the oldest record present on every port, context-free values fitting any. Returns
## {port: Packet} (removed from the queues, path stamped) or {} when no record is complete.
## Waiting values whose record can no longer be completed are discarded as ORPHANS (checked at
## most every 8 ticks). Tied unconnected inputs never wait: they get a fresh tie value.
## With one waiting port the queue is taken in arrival order.
func take_record(ports: Array, sim) -> Dictionary:
	var wait: Array = []
	var tied: Array = []
	for port in ports:
		if is_tied(port, sim):
			tied.append(port)
		else:
			wait.append(port)
	if wait.is_empty():
		return {}
	if wait.size() == 1:
		var port: String = wait[0]
		if (inq[port] as Array).is_empty():
			return {}
		var p: Packet = inq[port][0]
		inq[port].remove_at(0)
		p.path.append(label)
		var out := {port: p}
		for tp in tied:
			out[tp] = tie_packet(tp, sim)
		return out
	for port in wait:
		if (inq[port] as Array).is_empty():
			_check_orphans(wait, sim)
			return {}
	var cands: Array = []
	for port in wait:
		for p in inq[port]:
			var k: int = (p as Packet).ctx
			if k >= 0 and not cands.has(k):
				cands.append(k)
	cands.sort()
	cands.append(-1)  # finally: a record made only of context-free values
	for c in cands:
		var picks := {}
		for port in wait:
			var i := _find_exact(port, c)
			if i < 0:
				picks = {}
				break
			picks[port] = i
		if picks.is_empty():
			continue
		var out := {}
		for port in wait:
			var p: Packet = inq[port][picks[port]]
			inq[port].remove_at(picks[port])
			p.path.append(label)
			out[port] = p
		for tp in tied:
			out[tp] = tie_packet(tp, sim)
		return out
	_check_orphans(wait, sim)
	return {}


## First index on `port` fitting record c: ctx == c or context-free; for c = -1 only a
## context-free value (so a pure context-free record never swallows a record value).
func _find_exact(port: String, c: int) -> int:
	var q: Array = inq[port]
	for i in q.size():
		var k: int = (q[i] as Packet).ctx
		if k == c or k < 0:
			return i
	return -1


## Discard waiting values whose record can never be completed: a partner port has no value of
## that record and none can still arrive (Simulation.can_still_arrive). Throttled to one scan per
## 8 ticks, deterministic by tick.
func _check_orphans(ports: Array, sim) -> void:
	if sim == null or not sim.has_method("can_still_arrive") or sim.tick - orphan_check_tick < 8:
		return
	orphan_check_tick = sim.tick
	for port in ports:
		var q: Array = inq[port]
		var i := 0
		while i < q.size():
			var p: Packet = q[i]
			var gone := false
			if p.ctx >= 0:
				for other in ports:
					if other == port or _find_exact(other, p.ctx) >= 0:
						continue
					if not sim.can_still_arrive(id, other, p.ctx):
						gone = true
						break
			if gone:
				q.remove_at(i)
				orphans += 1
				sim.note_orphan(self, p)
			else:
				i += 1


## Refresh the visible state after all phases ran this tick.
func update_state(blocked_now: bool) -> void:
	if state == State.ERROR:
		return
	if blocked_now:
		blocked_ticks += 1
		state = State.BLOCKED
	elif not jobs.is_empty():
		state = State.PROCESSING
		if queued_count() >= _total_in_capacity():
			starved_full_ticks += 1
	elif has_pending_output():
		state = State.OUTPUT_READY
	elif received_ports.size() > 0:
		state = State.RECEIVING
	else:
		state = State.IDLE


## Record this tick's compute-bound flag into the 60-tick window.
func note_compute_bound(flag: bool) -> void:
	var leaving := (bound_hist >> 59) & 1
	bound_hist = ((bound_hist << 1) | int(flag)) & ((1 << 60) - 1)
	bound_cnt += int(flag) - leaving


## Share of the last 60 ticks every lane was busy with the inputs full (0..1).
func compute_bound_ratio() -> float:
	return float(bound_cnt) / 60.0


func total_in_capacity() -> int:
	return _total_in_capacity()


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
		"type": def_id(), "cell": [cell.x, cell.y], "rot": rot, "width": width,
		"params": params.duplicate(), "locked": locked, "channel": channel,
		"device": device, "last_device": last_device, "socket": socket, "port_row": port_row,
	}


static func from_dict(p_id: int, d: Dictionary, fallback_width: int) -> Machine:
	var w := int(d["width"]) if d.has("width") else fallback_width
	var m := Machine.new(p_id, d["type"], Vector2i(d["cell"][0], d["cell"][1]), w, int(d.get("rot", 0)), d.get("params", {}))
	m.locked = d.get("locked", false)
	m.channel = int(d.get("channel", 0))
	m.device = str(d.get("device", ""))
	m.last_device = str(d.get("last_device", ""))
	m.socket = bool(d.get("socket", false))
	m.port_row = int(d.get("port_row", -1))
	return m


## Player machines move; locked IO (mission IO, the Lab's USB ports) does not.
func movable() -> bool:
	return not locked
