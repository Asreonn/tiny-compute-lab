extends ComponentLogic
## Memory and control machines (SYSTEMS_EXPANSION §11 Groups E–F): register, register bank,
## RAM, ROM, ALU, program counter and instruction decoder. State lives on the Machine
## (memory / held / primed / counter) and is cleared by Machine.reset().


func start(m, sim) -> void:
	if not m.has_free_lane():
		return
	match m.type:
		"register":
			_register(m, sim)
		"register_bank":
			_memory(m, sim, 4)
		"ram":
			_memory(m, sim, 16)
		"rom":
			_rom(m, sim)
		"alu":
			_alu(m, sim)
		"program_counter":
			_pc(m, sim)
		"instruction_decoder":
			_decoder(m, sim)


## Register. Echo mode: seeds a feedback loop with its initial value at reset, then passes every
## write on. On-read mode: writes are silent; each READ pulse sends the stored value.
func _register(m, sim) -> void:
	var echo: bool = str(m.params.get("mode", "echo")) == "echo"
	var init := BitVector.of(int(m.params.get("init", 0)), m.width)
	if m.memory.is_empty():
		m.memory = [init]
	if not m.primed:
		m.primed = true
		if echo:
			var seed := Packet.new(sim.new_packet_id(), init, sim.tick)
			m.begin_job({"out": seed}, seed)
			return
	if not m.inq["in"].is_empty():
		var p: Packet = m.pop("in")
		m.memory[0] = p.data
		m.held = p
		m.last_mem_op = "write"
		m.begin_job({"out": p.derive(sim.new_packet_id(), p.data)} if echo else {}, p)
		return
	if not m.inq["read"].is_empty():
		var r: Packet = m.pop("read")
		var out: Packet = m.held.derive(sim.new_packet_id(), m.memory[0]) if m.held != null else Packet.new(sim.new_packet_id(), m.memory[0], sim.tick)
		out.merge_origins(r)
		m.last_mem_op = "read"
		m.begin_job({"out": out}, r)


## Register bank / RAM: one operation = one address + one value + one WE bit (all consumed).
func _memory(m, sim, cells: int) -> void:
	if m.inq["a"].is_empty() or m.inq["d"].is_empty() or m.inq["we"].is_empty():
		return
	if m.memory.size() != cells:
		m.memory = []
		for i in cells:
			m.memory.append(BitVector.of(0, m.width))
	var pa: Packet = m.pop("a")
	var pd: Packet = m.pop("d")
	var pw: Packet = m.pop("we")
	var idx: int = pa.data.unsigned() % cells
	if pw.data.as_bool():
		m.memory[idx] = BitVector.of(pd.data.unsigned(), m.width)
		m.last_mem_op = "write"
		m.begin_job({}, pa)
		return
	var out: Packet = pa.derive(sim.new_packet_id(), m.memory[idx])
	out.merge_origins(pd)
	out.merge_origins(pw)
	m.last_mem_op = "read"
	m.begin_job({"out": out}, pa)


## "6 4 7 1" / "6,4,7,1" → [6, 4, 7, 1] (at most 16 entries; junk entries read as 0).
static func parse_table(text: String) -> Array:
	var out := []
	for part in text.replace(",", " ").split(" ", false):
		if out.size() >= 16:
			break
		out.append(int(part) if part.is_valid_int() else 0)
	return out


func _rom(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	var table := parse_table(str(m.params.get("table", "")))
	var idx: int = p.data.unsigned()
	var v: int = int(table[idx]) if idx < table.size() else 0
	m.last_mem_op = "read"
	m.begin_job({"out": p.derive(sim.new_packet_id(), BitVector.of(v, m.port_width("out")))}, p)


func _alu(m, sim) -> void:
	if m.inq["a"].is_empty() or m.inq["b"].is_empty() or m.inq["op"].is_empty():
		return
	var pa: Packet = m.pop("a")
	var pb: Packet = m.pop("b")
	var po: Packet = m.pop("op")
	var op := str(m.params.get("op1" if po.data.as_bool() else "op0", "ADD"))
	var out: Packet = pa.derive(sim.new_packet_id(), MemoryOps.alu(op, pa.data, pb.data))
	out.merge_origins(pb)
	out.merge_origins(po)
	m.begin_job({"out": out}, pa)


## Program counter: each pulse sends the current address, then counts on (wraps at the width).
func _pc(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	if not m.primed:
		m.primed = true
		m.counter = int(m.params.get("start", 0))
	var p: Packet = m.pop("in")
	var v := BitVector.of(m.counter, m.width)
	m.counter = (m.counter + 1) % (1 << mini(m.width, 62))
	m.begin_job({"out": p.derive(sim.new_packet_id(), v)}, p)


## Instruction decoder: the top bit → A, the next bit → B; only wired outputs are sent.
func _decoder(m, sim) -> void:
	if m.inq["in"].is_empty():
		return
	var p: Packet = m.pop("in")
	var x: BitVector = p.data
	var w: int = x.width
	var results := {}
	if sim.output_connected(m, "a"):
		results["a"] = p.derive(sim.new_packet_id(), BitVector.of(x.bit(w - 1), 1))
	if sim.output_connected(m, "b") and w >= 2:
		results["b"] = p.derive(sim.new_packet_id(), BitVector.of(x.bit(w - 2), 1))
	m.begin_job(results, p)
