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
	var lo := clampi(int(m.params.get("lo", 3)), 1, maxi(w - 1, 1))
	# Only wired outputs produce a part: unused bits are dropped instead of jamming the
	# splitter (keeping just the payload must not need a dummy wire for the tag).
	var results := {}
	if sim.output_connected(m, "hi"):
		results["hi"] = p.derive(sim.new_packet_id(), x.slice(lo, w - lo))
	if sim.output_connected(m, "lo"):
		results["lo"] = p.derive(sim.new_packet_id(), x.slice(0, lo))
	m.begin_job(results, p)
