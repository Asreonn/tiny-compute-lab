class_name NetworkTests
extends RefCounted
## C6a acceptance tests: the NIC fixture (core/components/logic/nic_logic.gd). Each case
## calls t.check(cond, what); run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_rate_mk1(t)
	_widths(t)
	_sealed(t)
	_budget_tx_first(t)
	_realtime_drops(t)
	_pairing(t)


## A fresh 24×12 board.
static func _sim() -> Simulation:
	var sim := Simulation.new()
	sim.size = Vector2i(24, 12)
	return sim


## A probe sink facing a NIC south RX port (zero-tile wire, ~1-tick latency). The probe
## counts in `.counter` and keeps the last value in `.memory[0]`.
static func _probe_below(sim, nic, port: String, width: int, col: int) -> Machine:
	var p: Machine = sim.place("probe", Vector2i(col, 1), 1, {}, width)
	sim.connect_ports(nic.id, port, p.id, "in")
	return p


## 1. Rate: Mk1, RX A = forumcache (3/s) → ~30 records in 100 steps, and the first record
## the probe saw is record(forumcache, pop, 0).
static func _rate_mk1(t) -> void:
	var sim := _sim()
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "1", "rx_a": "forumcache"}, 16)
	var probe := _probe_below(sim, nic, "rx_a", 16, 2)
	var first: BitVector = null
	for i in 100:
		sim.step()
		if first == null and probe.counter >= 1:
			first = probe.memory[0]
	var def := SourceStream.source("forumcache")
	t.check(first != null and first.equals(SourceStream.record(def, SourceStream.population(), 0)), "the first record the probe saw is record(forumcache, pop, 0)")
	t.check(probe.counter >= 27 and probe.counter <= 33, "forumcache at 3/s delivers ~30 records in 100 steps (got %d)" % probe.counter)


## 2. Widths: rx_a = forumcache → 16; a Mk3 nic's rx_c = archivenode → 32; an unbound rx_b → 0.
static func _widths(t) -> void:
	var sim := _sim()
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "1", "rx_a": "forumcache"}, 16)
	t.check(nic.port_width("rx_a") == 16, "rx_a resolves to forumcache's 16-bit record (got %d)" % nic.port_width("rx_a"))
	t.check(nic.port_width("rx_b") == 0, "an unbound RX port has width 0 (got %d)" % nic.port_width("rx_b"))
	var nic3: Machine = sim.place("nic", Vector2i(10, 0), 0, {"tier": "3", "rx_c": "archivenode"}, 16)
	t.check(nic3.port_width("rx_c") == 32, "rx_c resolves to archivenode's 32-bit record (got %d)" % nic3.port_width("rx_c"))


## 3. Sealed: Mk1 refuses rx_b with "Sealed"; opening the tier unseals it.
static func _sealed(t) -> void:
	var sim := _sim()
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "1", "rx_a": "forumcache", "rx_b": "shopmirror"}, 16)
	var probe: Machine = sim.place("probe", Vector2i(10, 2), 0, {}, 16)
	var err: String = sim.connect_error(nic.id, "rx_b", probe.id, "in")
	t.check(err.contains("Sealed"), "Mk1 seals rx_b (got '%s')" % err)
	nic.params["tier"] = "2"
	var err2: String = sim.connect_error(nic.id, "rx_b", probe.id, "in")
	t.check(err2 == "", "Mk2 opens rx_b (got '%s')" % err2)


## 4. Budget + TX first: Mk1 (12 frames/s) with 60 TX packets fed at once — TX drains first,
## RX stays quiet while tx_a still has packets, and a normal source never loses.
static func _budget_tx_first(t) -> void:
	var sim := _sim()
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "1", "rx_a": "forumcache"}, 16)
	for i in 60:
		(nic.inq["tx_a"] as Array).append(Packet.new(sim.new_packet_id(), BitVector.of(1, 16), sim.tick))
	for i in 20:
		sim.step()
	var tx_sent: int = nic.net["tx"]["a"]["sent"]
	var rx_sent: int = nic.net["rx"]["a"]["sent"]
	t.check(tx_sent <= 29, "Mk1 TX sends at most 29 records in 20 steps (got %d)" % tx_sent)
	t.check(rx_sent == 0, "RX sends nothing while tx_a still has packets (rx sent %d)" % rx_sent)
	t.check((nic.inq["tx_a"] as Array).size() > 0, "tx_a still holds packets after 20 steps (left %d)" % (nic.inq["tx_a"] as Array).size())
	t.check(int(nic.net["rx"]["a"]["lost"]) == 0, "a normal source pauses, never loses (lost %d)" % nic.net["rx"]["a"]["lost"])


## 5. Realtime drops: a realtime source with no wire on rx_a fills its remote buffer and
## drops the oldest records.
static func _realtime_drops(t) -> void:
	var def := (SourceStream.source("forumcache").duplicate() as RemoteSourceDef)
	def.id = "rt_test"
	def.realtime = true
	def.rate = 20.0
	def.remote_buffer = 4
	SourceStream.register(def)
	var sim := _sim()
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "1", "rx_a": "rt_test"}, 16)
	for i in 50:
		sim.step()
	t.check(int(nic.net["rx"]["a"]["lost"]) > 0, "a realtime source drops records when its buffer is full (lost %d)" % nic.net["rx"]["a"]["lost"])


## 6. Pairing: Mk2 with rx_a = forumcache and rx_b = shopmirror — both deliver, and the last
## shop record has ctx = its seq.
static func _pairing(t) -> void:
	var sim := _sim()
	var nic: Machine = sim.place("nic", Vector2i(2, 0), 0, {"tier": "2", "rx_a": "forumcache", "rx_b": "shopmirror"}, 16)
	var pa := _probe_below(sim, nic, "rx_a", 16, 2)
	var pb := _probe_below(sim, nic, "rx_b", 16, 3)
	for i in 60:
		sim.step()
	t.check(pa.counter > 5 and pb.counter > 5, "both RX channels deliver after 60 steps (a=%d b=%d)" % [pa.counter, pb.counter])
	var shop := SourceStream.source("shopmirror")
	t.check(pb.counter > 0 and (pb.memory[0] as BitVector).equals(SourceStream.record(shop, SourceStream.population(), pb.counter - 1)), "the last shop record has ctx = its seq (count %d)" % pb.counter)