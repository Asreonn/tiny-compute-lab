extends ComponentLogic
## Storage machines: buffer (queue) and delay (fixed-hold line).


func start(m, sim) -> void:
	if m.type == "delay":
		_start_delay(m, sim)
		return
	# buffer
	if not m.has_free_lane():
		return
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	m.begin_job({"out": p}, p)


func _start_delay(m, sim) -> void:
	# accept arrivals into the delay line, stamped with their release tick
	while not m.inq["in"].is_empty():
		var p: Packet = m.pop("in")
		m.delay_line.append([p, sim.tick + int(m.params.get("ticks", 3))])
	if m.outq["out"] == null and not m.delay_line.is_empty() and sim.tick >= m.delay_line[0][1]:
		m.outq["out"] = m.delay_line.pop_front()[0]
		m.processed += 1
