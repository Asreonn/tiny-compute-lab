extends ComponentLogic
## Conversion machines: bit_splitter (splits a word into high and low bits).


func start(m, sim) -> void:
	if m.type != "bit_splitter":
		return
	if not m.outputs_empty():
		return
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	var x: BitVector = p.data
	var w := x.width
	var lo := clampi(int(m.params.get("lo", 3)), 1, w - 1)
	m.begin_job({"hi": p.derive(sim.new_packet_id(), x.slice(lo, w - lo)), "lo": p.derive(sim.new_packet_id(), x.slice(0, lo))}, p)
