extends ComponentLogic
## Routing machines: splitter (alternate/duplicate), merger (fair round-robin), demux / mux
## (a select bit picks the lane) and the conditional router (a value test picks the lane).


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
		"mux":
			_start_mux(m, sim)
		"cond_router":
			_start_cond_router(m, sim)


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


## Mux: the select bit says which input to take next; only that input is consumed.
func _start_mux(m, sim) -> void:
	if m.inq["sel"].is_empty():
		return
	var port := "b" if (m.inq["sel"][0] as Packet).data.as_bool() else "a"
	if m.inq[port].is_empty():
		return
	var sel: Packet = m.pop("sel")
	var d: Packet = m.pop(port)
	d.merge_origins(sel)
	m.begin_job({"out": d}, d)


## Conditional Router: A when the test holds on the value (unsigned), else B.
func _start_cond_router(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var d: Packet = m.pop("in")
	var port := "a" if test(str(m.params.get("op", ">")), int(m.params.get("k", 0)), d.data) else "b"
	var out := {}
	out[port] = d
	m.begin_job(out, d)


static func test(op: String, k: int, v: BitVector) -> bool:
	var u := v.unsigned()
	match op:
		">": return u > k
		"<": return u < k
		"=": return u == k
		"bit": return k >= 0 and k < v.width and (u >> k) & 1 == 1
	return false

