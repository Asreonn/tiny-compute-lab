extends ComponentLogic
## IO machines: input, usb_input (sources); output, terminal_output (validating sinks).


func start(m, sim) -> void:
	match m.type:
		"input", "usb_input":
			_start_input(m, sim)
		"output", "terminal_output", "usb_output":
			_start_output(m, sim)


func _start_input(m, sim) -> void:
	if m.socket:
		_start_socket(m, sim)
		return
	if m.stream.is_empty() or sim.tick < m.next_emit:
		return
	if m.emitted >= m.stream.size() and not m.loop:
		return
	if m.outq["out"] != null:
		if m.strict:
			var lost := _make_packet(sim, m, m.stream[m.emitted % m.stream.size()])
			lost.path.append(m.label)
			m.emitted += 1
			m.next_emit = sim.tick + m.interval
			sim.note_overflow(m, lost)
		return
	var p := _make_packet(sim, m, m.stream[m.emitted % m.stream.size()])
	p.path.append(m.label)
	m.outq["out"] = p
	m.emitted += 1
	m.next_emit = sim.tick + m.interval
	m.processed += 1


## A source packet carrying the stream element (a BitVector or a RawValue) and stamped with
## this socket's lineage: {machine id: {seq, value}} (docs/SYSTEMS_EXPANSION.md §3).
## `seq` overrides the emitted counter for lab sockets, whose generation index advances even
## when a value is dropped by the overrun FIFO.
func _make_packet(sim, m, value: Variant, seq: int = -1) -> Packet:
	var p: Packet
	if value is RawValue:
		p = Packet.make_raw(sim.new_packet_id(), value, sim.tick)
	else:
		p = Packet.new(sim.new_packet_id(), value, sim.tick)
	p.origins[m.id] = {"seq": m.emitted if seq < 0 else seq, "value": value}
	p.ctx = m.emitted if seq < 0 else seq
	var q := Devices.quest_of(m.device)
	if q >= 0:
		p.origins[m.id]["quest"] = q  # a quest stick: the drive judges this value for that quest
	return p


## Lab socket (docs/SYSTEMS_EXPANSION.md §2): every `interval` ticks the plugged module pushes
## `burst` stream values into a FIFO that holds 2 × burst (FACTORY_SYSTEMS §2.3). When the FIFO
## overflows the OLDEST pending value is dropped and counted as `lost`. As many pending values
## move into the output head + backlog each tick as the wire's lanes accept (1 without a wire),
## so a blocked socket never stalls the stream — it overruns. Without a module nothing is
## generated (the wire stays in place and simply sees no data). Burst 1 on a 1-lane wire is
## exactly the original behaviour.
func _start_socket(m, sim) -> void:
	# Test mode (JOB C7a): the socket generates nothing; test vectors arrive via emit_test.
	if not m.test_mode and m.device != "" and not m.stream.is_empty() and sim.tick >= m.next_emit:
		for g in m.burst:
			var seq: int = m.gen_seq
			m.fifo.append([m.stream[seq % m.stream.size()], seq])
			m.gen_seq += 1
		# An optional pattern cycles the emission intervals (bursty contracts); otherwise the
		# module's plain interval applies.
		var wait: int = m.interval
		if not m.pattern.is_empty():
			wait = int(m.pattern[m.pattern_idx % m.pattern.size()])
			m.pattern_idx += 1
		m.next_emit = sim.tick + maxi(1, wait)
		while m.fifo.size() > 2 * m.burst:
			m.fifo.pop_front()
			m.lost += 1
			sim.events.append({"kind": "lost", "machine": m.id})
	var cap := 1
	var c: Connection = sim.connection_at_port(m.id, "out")
	if c != null:
		cap = c.lanes
	while not m.fifo.is_empty() and m.waiting_results() < cap:
		var entry: Array = m.fifo.pop_front()
		var p := _make_packet(sim, m, entry[0], int(entry[1]))
		p.path.append(m.label)
		if m.outq["out"] == null:
			m.outq["out"] = p
		else:
			m.out_backlog["out"].append(p)
		m.processed += 1
		m.emitted += 1


func _start_output(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	if m.type == "usb_output" and m.socket and m.device == "":
		return  # empty Lab output port: nothing is there (can_accept already refuses)
	# A multi-lane wire may deliver several packets in one tick; every queued packet is judged
	# this same tick (the sink drains, FACTORY_SYSTEMS §2.3).
	while not m.inq["in"].is_empty():
		var p: Packet = m.pop("in")
		m.received.append(p)
		m.processed += 1
		if m.type == "usb_output" and m.socket and m.device == "monitor":
			# The Monitor keeps the last 10 samples and judges nothing (SYSTEMS_EXPANSION §2.1).
			while m.received.size() > 10:
				m.received.pop_front()
			continue
		sim.note_output(m, p)
