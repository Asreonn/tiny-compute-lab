class_name NetworkLabTests
extends RefCounted
## C6b acceptance tests: the Network Module in the Lab (game/lab/lab_run.gd). Each case calls
## t.check(cond, msg); run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_tier_fixture(t)
	_bindings_survive_save(t)
	_tx_judged(t)
	_tx_unbound(t)
	_socket_ids(t)


## A fresh L1 lab board, then the NIC earned at `tier` (0 = no NIC) via the IO refresh.
static func _board(tier: int) -> Array:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	if tier > 0:
		run.nic_tier = tier
		run._ensure_io(sim)
	return [sim, run]


## The locked NIC machine, or null before it exists.
static func _nic(sim: Simulation) -> Machine:
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "nic":
			return sim.machines[id]
	return null


## 1. The fixture: nic_tier 0 has no NIC; 1 creates exactly one locked NIC at the config cell
## with tier "1"; raising to 2 re-tiers it without adding a second NIC.
static func _tier_fixture(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	t.check(_nic(sim) == null, "with nic_tier 0 no NIC machine exists")
	run.nic_tier = 1
	run._ensure_io(sim)
	var nic := _nic(sim)
	t.check(nic != null and nic.locked and nic.cell == LabDef.CONFIG.nic_cell, "nic_tier 1 creates one locked NIC at the config cell (got %s)" % (nic.cell if nic != null else "none"))
	t.check(nic != null and str(nic.params.get("tier", "")) == "1", "the NIC's tier param is 1 (got '%s')" % (str(nic.params.get("tier", "")) if nic != null else "none"))
	t.check(nic != null and nic.label == "Network Module", "the NIC is labelled Network Module")
	run.nic_tier = 2
	run._ensure_io(sim)
	t.check(nic != null and str(nic.params.get("tier", "")) == "2", "raising the tier sets tier 2 (got '%s')" % (str(nic.params.get("tier", "")) if nic != null else "none"))
	var count := 0
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == "nic":
			count += 1
	t.check(count == 1, "re-ensuring does not add a second NIC (got %d)" % count)


## 2. Save/load: the RX/TX bindings survive layout_to_dict -> load_player_layout; the tier
## stays the Lab's.
static func _bindings_survive_save(t) -> void:
	var board := _board(1)
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var nic := _nic(sim)
	nic.params["rx_a"] = "forumcache"
	nic.params["tx_a"] = run.quest_job(run.level)
	var d := sim.layout_to_dict()
	var board2 := _board(1)
	var sim2: Simulation = board2[0]
	var run2: LabRun = board2[1]
	sim2.load_player_layout(d)
	var nic2 := _nic(sim2)
	t.check(nic2 != null and str(nic2.params.get("rx_a", "")) == "forumcache", "rx_a survives save/load (got '%s')" % (str(nic2.params.get("rx_a", "")) if nic2 != null else "none"))
	t.check(nic2 != null and str(nic2.params.get("tx_a", "")) == run.quest_job(run.level), "tx_a survives save/load (got '%s')" % (str(nic2.params.get("tx_a", "")) if nic2 != null else "none"))
	t.check(nic2 != null and str(nic2.params.get("tier", "")) == "1", "the tier stays 1 after load (got '%s')" % (str(nic2.params.get("tier", "")) if nic2 != null else "none"))
	t.check(run2.level == run.level, "the reloaded run keeps the level")


## 3. TX judged: a TX packet bound to the current quest's Job stick is judged like a drive
## delivery (delivered + rejected grows by 1 once it leaves).
static func _tx_judged(t) -> void:
	var board := _board(1)
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var nic := _nic(sim)
	nic.params["tx_a"] = run.quest_job(run.level)
	var before := run.delivered + run.rejected
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin("010"), sim.tick)
	(nic.inq["tx_a"] as Array).append(p)
	var guard := 0
	while run.delivered + run.rejected == before and guard < 200:
		sim.step()
		guard += 1
	t.check(run.delivered + run.rejected == before + 1, "a bound TX packet is judged (delivered %d + rejected %d, before %d)" % [run.delivered, run.rejected, before])
	t.check((nic.inq["tx_a"] as Array).is_empty(), "the TX packet left the NIC")


## 4. Unbound TX: with tx_a = "" the packet is consumed but never judged.
static func _tx_unbound(t) -> void:
	var board := _board(1)
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var nic := _nic(sim)
	nic.params["tx_a"] = ""
	var before := run.delivered + run.rejected
	var p := Packet.new(sim.new_packet_id(), BitVector.from_bin("010"), sim.tick)
	(nic.inq["tx_a"] as Array).append(p)
	var guard := 0
	while not (nic.inq["tx_a"] as Array).is_empty() and guard < 200:
		sim.step()
		guard += 1
	t.check((nic.inq["tx_a"] as Array).is_empty(), "an unbound TX packet is consumed")
	t.check(run.delivered + run.rejected == before, "an unbound TX is not judged (delivered %d + rejected %d)" % [run.delivered, run.rejected])


## 5. The NIC's id counts as a socket for contracts.
static func _socket_ids(t) -> void:
	var board := _board(1)
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var nic := _nic(sim)
	var ids := run._socket_ids(sim)
	t.check(ids.has(nic.id), "the NIC's id is a socket for contracts")
	t.check(ids[0] != nic.id, "the NIC comes after the USB sockets")