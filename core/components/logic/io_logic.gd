extends ComponentLogic
## IO machines: input, usb_input (sources) and output (sink).


func start(m, sim) -> void:
	match m.type:
		"input", "usb_input":
			_start_input(m, sim)
		"output":
			_start_output(m, sim)


func _start_input(m, sim) -> void:
	if m.emitted >= m.stream.size() or sim.tick < m.next_emit:
		return
	if m.outq["out"] != null:
		if m.strict:
			var lost := Packet.new(sim.new_packet_id(), m.stream[m.emitted], sim.tick)
			lost.path.append(m.label)
			m.emitted += 1
			m.next_emit = sim.tick + m.interval
			sim.note_overflow(m, lost)
		return
	var p := Packet.new(sim.new_packet_id(), m.stream[m.emitted], sim.tick)
	p.path.append(m.label)
	m.outq["out"] = p
	m.emitted += 1
	m.next_emit = sim.tick + m.interval
	m.processed += 1


func _start_output(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	m.received.append(p)
	m.processed += 1
	sim.note_output(m, p)
