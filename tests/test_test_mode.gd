class_name TestModeTests
extends RefCounted
## Job C7a acceptance tests: source test mode, emit_test, test_packets and layout_version.
## In test mode a source sends no live records; the player sends known test vectors instead.
## Each case calls t.check(cond, what); run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_live_by_default(t)
	_test_mode(t)
	_emit_test(t)
	_test_packets(t)
	_nic(t)
	_layout_version(t)


## A fresh 24×12 board with a USB-socket-like source wired to a probe sink.
static func _socket_board() -> Array:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	src.device = "bit"
	src.stream = [BitVector.of(1, 3), BitVector.of(2, 3)]
	src.interval = 2
	src.loop = true
	var probe := sim.place("probe", Vector2i(9, 5), 0, {}, 3)
	sim.connect_ports(src.id, "out", probe.id, "in")
	return [sim, src, probe]


## 1. Every source starts live: after 20 steps the socket's probe counted > 3.
static func _live_by_default(t) -> void:
	var board := _socket_board()
	var sim: Simulation = board[0]
	var src: Machine = board[1]
	var probe: Machine = board[2]
	t.check(sim.source_mode(src.id, "") == "live", "a socket starts live by default")
	sim.reset_run()
	for i in 20:
		sim.step()
	t.check(probe.counter > 3, "a live socket emits (probe counted %d)" % probe.counter)


## 2. Test mode: the socket generates nothing; source_mode reports "test".
static func _test_mode(t) -> void:
	var board := _socket_board()
	var sim: Simulation = board[0]
	var src: Machine = board[1]
	var probe: Machine = board[2]
	t.check(sim.set_source_mode(src.id, "", "test"), "set_source_mode(test) applies to a socket")
	t.check(sim.source_mode(src.id, "") == "test", "source_mode reads test")
	sim.reset_run()
	for i in 20:
		sim.step()
	t.check(probe.counter == 0, "a test-mode socket emits nothing (probe counted %d)" % probe.counter)
	t.check(sim.set_source_mode(src.id, "", "bogus") == false, "an unknown mode is refused")
	t.check(sim.set_source_mode(999, "", "test") == false, "an unknown machine id is refused")


## 3. emit_test: one tagged packet reaches the probe with its own record ctx.
static func _emit_test(t) -> void:
	var board := _socket_board()
	var sim: Simulation = board[0]
	var src: Machine = board[1]
	var probe: Machine = board[2]
	sim.set_source_mode(src.id, "", "test")
	sim.reset_run()
	var p := sim.emit_test(src.id, "", BitVector.of(5, 3), 7, 1, 0)
	t.check(p != null, "emit_test returns a packet")
	if p == null:
		return
	t.check(p.ctx == Simulation.TEST_CTX_BASE + 1000, "the test packet has its own ctx (got %d)" % p.ctx)
	t.check(p.origins.has(src.id) and int(p.origins[src.id]["test"]) == 0 and int(p.origins[src.id]["run"]) == 1 and int(p.origins[src.id]["seq"]) == 7, "origins carry test idx, run and seq")
	t.check(p.meta.has("test") and int(p.meta["test"]) == 0, "meta carries the test idx")
	var guard := 0
	while guard < 10 and probe.counter < 1:
		sim.step()
		guard += 1
	t.check(probe.counter == 1, "the test packet reaches the probe within 10 steps (counted %d)" % probe.counter)
	t.check(probe.memory.size() == 1 and (probe.memory[0] as BitVector).equals(BitVector.of(5, 3)), "the probe saw 101 (got %s)" % (probe.memory[0] if probe.memory.size() == 1 else "none"))
	t.check(probe.last_mem_op == "T0", "the probe records the test vector in last_mem_op (got '%s')" % probe.last_mem_op)


## 4. test_packets: right after emit_test the packet sits on the source; mid-wire the holder
## is the wire; once the probe consumed it, nothing of the run is left.
static func _test_packets(t) -> void:
	var board := _socket_board()
	var sim: Simulation = board[0]
	var src: Machine = board[1]
	var probe: Machine = board[2]
	sim.set_source_mode(src.id, "", "test")
	sim.reset_run()
	sim.emit_test(src.id, "", BitVector.of(5, 3), 7, 1, 0)
	var where := sim.test_packets(1)
	t.check(where.has(0) and (where[0] as Array).size() == 1 and (where[0] as Array)[0]["machine"] == src.id, "right after emit_test the packet is on the source")
	t.check(sim.test_packets(99).is_empty(), "an unknown run has no packets")
	sim.step()
	var mid := sim.test_packets(1)
	t.check(mid.has(0) and (mid[0] as Array).size() == 1 and (mid[0] as Array)[0]["machine"] == -1 and (mid[0] as Array)[0]["label"] == "wire", "a packet mid-wire is held by the wire")
	var guard := 0
	while guard < 30 and probe.counter < 1:
		sim.step()
		guard += 1
	t.check(probe.counter == 1, "the probe consumed the test packet (counted %d)" % probe.counter)
	sim.step()  # the probe's 1-tick job completes and drops the packet
	t.check(sim.test_packets(1).is_empty(), "a consumed test packet is nowhere")


## 5. NIC: a new rx_a binding starts in TEST (no remote records), and switching it live resumes.
static func _nic(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "1"}, 16)
	t.check(sim.set_param(nic.id, "rx_a", "forumcache"), "rx_a binds to forumcache")
	t.check(str(nic.params.get("mode_a", "")) == "test", "a new binding starts in TEST mode")
	var probe := sim.place("probe", Vector2i(2, 1), 1, {}, 16)
	sim.connect_ports(nic.id, "rx_a", probe.id, "in")
	sim.reset_run()
	for i in 40:
		sim.step()
	t.check(probe.counter == 0, "a test-mode RX channel sends nothing (probe counted %d)" % probe.counter)
	t.check(sim.set_source_mode(nic.id, "a", "live"), "set_source_mode(live) applies to a NIC channel")
	t.check(sim.source_mode(nic.id, "a") == "live", "source_mode reads live for the NIC")
	for i in 40:
		sim.step()
	t.check(probe.counter > 0, "a live RX channel delivers (probe counted %d)" % probe.counter)


## 6. layout_version grows on every layout edit (a place bumps it).
static func _layout_version(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	var v0 := sim.layout_version
	var m := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	t.check(m != null and sim.layout_version > v0, "placing a machine bumps layout_version (%d -> %d)" % [v0, sim.layout_version])