extends ComponentLogic
## Codec machines: the raw <-> BitVector boundary (docs/SYSTEMS_EXPANSION.md §7).
## Encoders turn a RawValue into bits; Decoders turn bits into a RawValue. These are the only
## machines allowed to see raw values (docs/ARCHITECTURE.md §0 rule 7).


func start(m, sim) -> void:
	if not m.has_free_lane():
		return
	match m.type:
		"number_encoder":
			_start_number_encoder(m, sim)
		"char_encoder":
			_start_char_encoder(m, sim)
		"number_decoder":
			_start_number_decoder(m, sim)
		"char_decoder":
			_start_char_decoder(m, sim)


## Consume the input without producing anything and count it (wrong kind / unencodable char).
func _drop(m, p: Packet) -> void:
	m.dropped += 1
	m.begin_job({}, p)


func _start_number_encoder(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	if not p.is_raw() or p.raw.kind == RawValue.Kind.TEXT:
		_drop(m, p)
		return
	var v: int = int(p.raw.value)
	var w: int = maxi(1, m.port_width("out"))
	# Masking is the real overflow: the low bits pass, the LED warns (SYSTEMS_EXPANSION §7).
	m.last_carry = 1 if (v < 0 or v >= (1 << w)) else 0
	m.begin_job({"out": p.derive(sim.new_packet_id(), BitVector.of(v, w))}, p)


func _start_char_encoder(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	if not p.is_raw() or p.raw.kind != RawValue.Kind.TEXT:
		_drop(m, p)
		return
	var bv := Charset.encode(str(p.raw.value), maxi(1, m.port_width("out")))
	if bv == null:
		_drop(m, p)
		return
	m.begin_job({"out": p.derive(sim.new_packet_id(), bv)}, p)


func _start_number_decoder(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	if p.is_raw():
		_drop(m, p)
		return
	var n: int = p.data.signed() if str(m.params.get("signed", "Unsigned")) == "Signed" else p.data.unsigned()
	m.begin_job({"out": p.derive_raw(sim.new_packet_id(), RawValue.number(n))}, p)


func _start_char_decoder(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	if p.is_raw():
		_drop(m, p)
		return
	m.begin_job({"out": p.derive_raw(sim.new_packet_id(), RawValue.text(Charset.decode(p.data)))}, p)
