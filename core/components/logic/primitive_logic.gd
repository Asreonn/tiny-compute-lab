extends ComponentLogic
## Primitive machines: bit_switch (gated pass), fork / distributor / join (fan-out, deal, merge),
## latch (stored state), constant / clock (sources that bypass the lane gate) and probe (a tap).


func start(m, sim) -> void:
	match m.type:
		"constant":
			_start_constant(m, sim)  # source: Machine.start calls it directly, no lane gate
			return
		"clock":
			_start_clock(m, sim)  # source: a blocked pulse is skipped, never queued
			return
	if not m.has_free_lane():
		return
	match m.type:
		"bit_switch":
			_start_bit_switch(m, sim)
		"fork":
			_start_fork(m, sim)
		"distributor":
			_start_distributor(m, sim)
		"join":
			_start_join(m, sim)
		"latch":
			_start_latch(m, sim)
		"probe":
			_start_probe(m, sim)


## Bit Switch: pass D while EN is 1, else output 0 of the same width; it always answers.
func _start_bit_switch(m, sim) -> void:
	var got: Dictionary = m.take_record(["in", "ctrl"], sim)
	if got.is_empty():
		return
	var d: Packet = got["in"]
	var en: Packet = got["ctrl"]
	var value: BitVector = d.data if en.data.as_bool() else BitVector.of(0, d.data.width)
	var out: Packet = d.derive(sim.new_packet_id(), value)
	out.merge_origins(en)
	m.last_mem_op = "pass" if en.data.as_bool() else "zero"  # the view's blade state
	m.begin_job({"out": out}, d)


## Fork: copy the value to every connected output; a full branch holds the next copy back.
func _start_fork(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var ports: Array = []
	for port in ["a", "b", "c"]:
		if sim.output_connected(m, port):
			ports.append(port)
	if ports.is_empty():
		return
	var p: Packet = m.pop("in")
	var results := {}
	results[ports[0]] = p
	for i in range(1, ports.size()):
		results[ports[i]] = p.derive(sim.new_packet_id(), p.data)
	m.begin_job(results, p)


## Distributor: deal each value to the next connected output that can take it (A, B, C in turn).
func _start_distributor(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var order := ["a", "b", "c"]
	var idx := -1
	for k in 3:
		var port: String = order[(m.rr + k) % 3]
		if sim.output_connected(m, port) and m.outq[port] == null and m.out_backlog[port].is_empty():
			idx = (m.rr + k) % 3
			break
	if idx < 0:
		return
	var p: Packet = m.pop("in")
	m.rr = idx + 1
	m.begin_job({order[idx]: p}, p)


## Join: take the next value from the connected inputs in turn and send it on as one stream.
func _start_join(m, sim) -> void:
	var order := ["a", "b", "c"]
	for k in 3:
		var port: String = order[(m.rr + k) % 3]
		if sim.input_connected(m, port) and not m.inq[port].is_empty():
			var p: Packet = m.pop(port)
			m.rr = ((m.rr + k) % 3) + 1
			m.begin_job({"out": p}, p)
			return


## Latch: store D while EN is 1 (an unwired D stores the tie value), else re-emit the state.
func _start_latch(m, sim) -> void:
	if m.memory.is_empty():
		m.memory = [BitVector.of(int(m.params.get("init", 0)), m.width)]
	var required: Array = ["ctrl"]
	if sim.input_connected(m, "in"):
		required.append("in")
	var got: Dictionary = m.take_record(required, sim)
	if got.is_empty():
		return
	var en: Packet = got["ctrl"]
	if en.data.as_bool():
		m.memory[0] = got["in"].data if got.has("in") else BitVector.of(int(m.params.get("d", 1)), m.width)
		m.last_mem_op = "write"
	else:
		m.last_mem_op = "read"
	var out: Packet = en.derive(sim.new_packet_id(), m.memory[0])
	if got.has("in"):
		out.merge_origins(got["in"])
	m.begin_job({"out": out}, en)


## Constant: emit the fixed value whenever the output has room; it fits any record (ctx -1).
func _start_constant(m, sim) -> void:
	if m.outq["out"] == null:
		var pkt: Packet = Packet.new(sim.new_packet_id(), BitVector.of(int(m.params.get("value", 1)), m.width), sim.tick)
		m.outq["out"] = pkt
		m.processed += 1


## Clock: emit a 1-bit pulse every Period ticks; a blocked pulse is skipped, not queued.
func _start_clock(m, sim) -> void:
	if sim.tick >= m.next_emit:
		m.next_emit = sim.tick + maxi(1, int(m.params.get("period", 10)))
		if m.outq["out"] == null:
			m.outq["out"] = Packet.new(sim.new_packet_id(), BitVector.of(1, 1), sim.tick)
			m.processed += 1


## Probe: count and remember the last value; pass it on, or keep it when the output is unwired.
func _start_probe(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	m.memory = [p.data]
	m.counter += 1
	if p.meta.has("test"):
		m.last_mem_op = "T%d" % int(p.meta["test"])  # the vector the probe saw last
	else:
		m.last_mem_op = ""
	m.begin_job({"out": p} if sim.output_connected(m, "out") else {}, p)