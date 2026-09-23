extends ComponentLogic
## Logic machines: compare (1-bit result) and gate (control-driven pass/discard).


func start(m, sim) -> void:
	if not m.outputs_empty():
		return
	match m.type:
		"compare":
			if m.inq["in"].is_empty():
				return
			var p: Packet = m.pop("in")
			var x: BitVector = p.data
			var c := x.ucmp(BitVector.of(int(m.params["k"]), x.width))
			var r := false
			match str(m.params["op"]):
				">": r = c > 0
				"<": r = c < 0
				"=": r = c == 0
				"≥": r = c >= 0
				"≤": r = c <= 0
				"≠": r = c != 0
			var v := BitVector.of(1 if r else 0, 1)
			m.begin_job({"out": p.derive(sim.new_packet_id(), v)}, p)
		"gate":
			if m.inq["in"].is_empty() or m.inq["ctrl"].is_empty():
				return
			var d: Packet = m.pop("in")
			var ctrl: Packet = m.pop("ctrl")
			if ctrl.data.as_bool():
				m.begin_job({"out": d}, d)
			else:
				m.begin_job({}, d)  # consumed and discarded after processing
				sim.note_discard(m, d)
