extends ComponentLogic
## Routing machines: splitter (alternate/duplicate) and merger (fair round-robin).


func start(m, sim) -> void:
	if not m.outputs_empty():
		return
	match m.type:
		"splitter":
			_start_splitter(m, sim)
		"merger":
			_start_merger(m, sim)
		"demux":
			_start_demux(m, sim)


func _start_splitter(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	if str(m.params["mode"]) == "Duplicate":
		m.begin_job({"a": p, "b": p.derive(sim.new_packet_id(), p.data)}, p)
		return
	var port := "a" if m.rr % 2 == 0 else "b"
	# prefer a port whose wire can take it; stay deterministic
	if not sim.output_connected(m, port):
		port = "b" if port == "a" else "a"
	m.rr += 1
	m.begin_job({port: p}, p)


func _start_merger(m, sim) -> void:
	var order := ["a", "b"] if m.rr % 2 == 0 else ["b", "a"]
	for port in order:
		if not m.inq[port].is_empty():
			var p: Packet = m.pop(port)
			m.rr = 1 if port == "a" else 0
			m.begin_job({"out": p}, p)
			return


func _start_demux(m, sim) -> void:
	if m.inq["in"].is_empty() or m.inq["sel"].is_empty():
		return
	var d: Packet = m.pop("in")
	var sel: Packet = m.pop("sel")
	d.merge_origins(sel)
	var port := "b" if sel.data.as_bool() else "a"
	var out := {}
	out[port] = d
	m.begin_job(out, d)
