extends ComponentLogic
## Math machines: add, multiply, modulo, processor, counter. All arithmetic is BitVector ops
## at the instance width, so masking and overflow are width-driven.


func start(m, sim) -> void:
	if not m.outputs_empty():
		return
	match m.type:
		"adder":
			# a pair at a time: both inputs must be waiting; the result carries both lineages
			if m.inq["a"].is_empty() or m.inq["b"].is_empty():
				return
			var pa: Packet = m.pop("a")
			var pb: Packet = m.pop("b")
			var r := pa.data.add_carry(pb.data.unsigned())
			m.last_carry = int(r["carry"])
			m.carries += m.last_carry
			var out := pa.derive(sim.new_packet_id(), r["value"])
			out.merge_origins(pb)
			m.begin_job({"out": out}, pa)
		"add", "multiply", "processor", "counter", "modulo":
			if m.inq["in"].is_empty():
				return
			var p: Packet = m.pop("in")
			var x: BitVector = p.data
			var v: BitVector = null
			match m.type:
				"add":
					var r := x.add_carry(int(m.params["k"]))
					m.last_carry = int(r["carry"])
					m.carries += m.last_carry
					v = r["value"]
				"multiply":
					v = x.mul(int(m.params["k"]))
				"modulo":
					v = x.umod(maxi(1, int(m.params["k"])))
				"processor":
					match str(m.params["op"]):
						"x³":
							v = x.mul(x).mul(x)
						"|x|":
							v = BitVector.of(absi(x.signed()), m.width)
						"−x":
							v = x.neg()
						_:
							v = x.mul(x)
				"counter":
					m.counter += 1
					v = BitVector.of(m.counter, m.width)
			m.begin_job({"out": p.derive(sim.new_packet_id(), v)}, p)
