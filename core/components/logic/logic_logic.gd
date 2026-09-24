extends ComponentLogic
## Logic machines: compare (1-bit result), gate (control-driven pass/discard) and the bitwise
## gates AND / OR / XOR (a pair at a time, lineages merged) and NOT.


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
		"and_gate", "or_gate", "xor_gate":
			if m.inq["a"].is_empty() or m.inq["b"].is_empty():
				return
			var pa: Packet = m.pop("a")
			var pb: Packet = m.pop("b")
			var v: BitVector
			match m.type:
				"and_gate": v = pa.data.band(pb.data)
				"or_gate": v = pa.data.bor(pb.data)
				_: v = pa.data.bxor(pb.data)
			var out := pa.derive(sim.new_packet_id(), v)
			out.merge_origins(pb)
			m.begin_job({"out": out}, pa)
		"not_gate":
			if m.inq["in"].is_empty():
				return
			var pn: Packet = m.pop("in")
			m.begin_job({"out": pn.derive(sim.new_packet_id(), pn.data.bnot())}, pn)
		"gate":
			if m.inq["in"].is_empty() or m.inq["ctrl"].is_empty():
				return
			var d: Packet = m.pop("in")
			var ctrl: Packet = m.pop("ctrl")
			if ctrl.data.as_bool():
				d.merge_origins(ctrl)
				m.begin_job({"out": d}, d)
			else:
				m.begin_job({}, d)  # consumed and discarded after processing
				sim.note_discard(m, d)
