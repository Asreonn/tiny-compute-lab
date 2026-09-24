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
	return p


## Lab socket (docs/SYSTEMS_EXPANSION.md §2): every `interval` ticks the plugged module pushes
## the next stream value into a 2-slot FIFO; when the wire is full the OLDEST pending value is
## dropped and counted as `lost`. Every tick one pending value moves into the free output slot,
## so a blocked socket never stalls the stream — it overruns. Without a module nothing is
## generated (the wire stays in place and simply sees no data).
func _start_socket(m, sim) -> void:
	if m.device != "" and not m.stream.is_empty() and sim.tick >= m.next_emit:
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
		if m.fifo.size() > 2:
			m.fifo.pop_front()
			m.lost += 1
			sim.events.append({"kind": "lost", "machine": m.id})
	if m.outq["out"] == null and not m.fifo.is_empty():
		var entry: Array = m.fifo.pop_front()
		var p := _make_packet(sim, m, entry[0], int(entry[1]))
		p.path.append(m.label)
		m.outq["out"] = p
		m.processed += 1
		m.emitted += 1


func _start_output(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	m.received.append(p)
	m.processed += 1
	sim.note_output(m, p)
