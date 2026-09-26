extends ComponentLogic
## Conversion machines: bit_splitter (splits a word into high and low bits), the width
## converters zero_extend / sign_extend / truncate (the only machines that change a width),
## and the field parts field_splitter / field_joiner (pure bit slicing into named fields).


func start(m, sim) -> void:
	if m.type == "field_splitter":
		_start_field_splitter(m, sim)
		return
	if m.type == "field_joiner":
		_start_field_joiner(m, sim)
		return
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


## Field Splitter: pure bit slicing, MSB first. Only connected fields are sent; the rest (and
## any low leftover bits) are dropped, so an unused field never blocks the record.
func _start_field_splitter(m, sim) -> void:
	if not m.has_free_lane() or m.inq["in"].is_empty():
		return
	var fw: Array = m.field_widths()
	var total := 0
	for f in fw:
		total += int(f)
	var w: int = m.port_width("in")
	if fw.is_empty() or total > w:
		m.set_error("Fields need %d bits; the input has %d" % [total, w])
		return
	var p: Packet = m.pop("in")
	var x: BitVector = p.data
	var results := {}
	var hi := x.width
	for i in fw.size():
		var fwi: int = fw[i]
		hi -= fwi
		var port := "f%d" % i
		if sim.output_connected(m, port):
			results[port] = p.derive(sim.new_packet_id(), x.slice(hi, fwi))
	m.begin_job(results, p)


## Field Joiner: f0 · f1 · f2 · f3, f0 in the high bits. Waits for every connected field of one
## record; an unconnected field is 0 of its width.
func _start_field_joiner(m, sim) -> void:
	if not m.has_free_lane():
		return
	var fw: Array = m.field_widths()
	var need: Array = []
	for i in fw.size():
		if sim.input_connected(m, "f%d" % i):
			need.append("f%d" % i)
	if need.is_empty():
		return
	var got: Dictionary = m.take_record(need, sim)
	if got.is_empty():
		return
	var base: Packet = got[need[0]]
	var acc: BitVector = null
	for i in range(fw.size() - 1, -1, -1):  # from the lowest field up
		var port := "f%d" % i
		var fwi: int = fw[i]
		var v: BitVector = (got[port] as Packet).data if got.has(port) else BitVector.zero(fwi)
		acc = v if acc == null else acc.concat(v)
	var out := base.derive(sim.new_packet_id(), acc)
	for port in need:
		if port != need[0]:
			out.merge_origins(got[port])
	m.begin_job({"out": out}, base)


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

