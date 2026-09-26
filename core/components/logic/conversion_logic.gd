extends ComponentLogic
## Conversion machines: bit_splitter (splits a word into high and low bits) and the width
## converters zero_extend / sign_extend / truncate (the only machines that change a width).


func start(m, sim) -> void:
	if m.type in ["zero_extend", "sign_extend", "truncate"]:
		_start_width(m, sim)
		return
	if m.type == "bus_combiner":
		_start_combiner(m, sim)
		return
	if m.type != "bit_splitter":
		return
	if not m.has_free_lane():
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


## Zero / sign extend to the wider `to` width, or truncate to the narrower one. A `to` on the
## wrong side of the input width is a configuration error (the machine says so and stops).
func _start_width(m, sim) -> void:
	if not m.has_free_lane() or m.inq["in"].is_empty():
		return
	var to := int(m.params.get("to", m.width))
	var w: int = m.width
	if (m.type == "truncate" and to > w) or (m.type != "truncate" and to < w):
		m.set_error("%s needs %s %d bits" % [m.def()["name"], "at most" if m.type == "truncate" else "at least", w])
		return
	var p: Packet = m.pop("in")
	var x: BitVector = p.data
	var v: BitVector
	match m.type:
		"zero_extend": v = x.zero_extend(to)
		"sign_extend": v = x.sign_extend(to)
		_: v = x.truncate(to)
	m.begin_job({"out": p.derive(sim.new_packet_id(), v)}, p)


## Bus Combiner: hi:lo, one pair at a time (the inverse of the Bit Splitter).
func _start_combiner(m, sim) -> void:
	if not m.has_free_lane():
		return
	var got: Dictionary = m.take_record(["hi", "lo"], sim)
	if got.is_empty():
		return
	var ph: Packet = got["hi"]
	var pl: Packet = got["lo"]
	var out := pl.derive(sim.new_packet_id(), pl.data.concat(ph.data))
	out.merge_origins(ph)
	m.begin_job({"out": out}, pl)

