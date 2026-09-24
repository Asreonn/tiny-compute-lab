extends ComponentLogic
## IO machines: input, usb_input (sources); output, terminal_output (validating sinks).


func start(m, sim) -> void:
	match m.type:
		"input", "usb_input":
			_start_input(m, sim)
		"output", "terminal_output", "usb_output":
			_start_output(m, sim)


func _start_input(m, sim) -> void:
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
func _make_packet(sim, m, value: Variant) -> Packet:
	var p: Packet
	if value is RawValue:
		p = Packet.make_raw(sim.new_packet_id(), value, sim.tick)
	else:
		p = Packet.new(sim.new_packet_id(), value, sim.tick)
	p.origins[m.id] = {"seq": m.emitted, "value": value}
	return p


func _start_output(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	m.received.append(p)
	m.processed += 1
	sim.note_output(m, p)
