class_name SourceSinkTests
extends RefCounted
## P1c acceptance tests: burst socket streams (FACTORY_SYSTEMS §2.3), draining sinks and the
## `sustain` contract rule (§4). Each case calls t.check(cond, what); run() is invoked from
## tests/run_tests.gd.

static func run(t) -> void:
	_burst_loses_on_a_one_lane_wire(t)
	_burst_flows_on_a_two_lane_wire(t)
	_sink_drains_two_packets_in_one_tick(t)
	_contract_parses_sustain(t)
	_lab_sustain_gate(t)


# --- helpers --------------------------------------------------------------------

## A plain socket + USB Output on an empty board (no mission). The sink is not a Lab port
## (`socket == false`), so it accepts and records anything wired into it.
static func _socket_out() -> Dictionary:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	var out := sim.place("usb_output", Vector2i(9, 5), 0, {}, 3)
	return {"sim": sim, "src": src, "out": out}


# --- burst sources (FACTORY_SYSTEMS §2.3) ---------------------------------------

## burst 2 @ interval 1 on a 1-lane wire: the FIFO (2 × burst = 4) cannot keep up, the oldest
## pending value is dropped and counted as `lost`; the sink only ever sees ~1 value/tick.
static func _burst_loses_on_a_one_lane_wire(t) -> void:
	var d := _socket_out()
	var sim: Simulation = d["sim"]
	var src: Machine = d["src"]
	var out: Machine = d["out"]
	sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 1, "burst": 2})
	var c := sim.connect_ports(src.id, "out", out.id, "in")
	t.check(c != null and c.lanes == 1, "the socket wires to the sink on a 1-lane wire")
	sim.reset_run()
	for i in 50:
		sim.step()
	t.check(src.lost > 0, "a burst-2 stream over a 1-lane wire loses values (lost %d)" % src.lost)
	var warm := 50 - c.length()
	t.check(float(out.received.size()) / float(maxi(1, warm)) < 1.8, "…but the sink sees under 1.8 values/tick after warm-up (%.2f)" % (float(out.received.size()) / float(maxi(1, warm))))


## The same stream over a 2-lane wire: both values enter the wire every tick, nothing is lost
## and the sink receives ~2 values/tick after warm-up.
static func _burst_flows_on_a_two_lane_wire(t) -> void:
	var d := _socket_out()
	var sim: Simulation = d["sim"]
	var src: Machine = d["src"]
	var out: Machine = d["out"]
	sim.insert_device(src.id, "bit", {"values": ["010"], "width": 3, "interval": 1, "burst": 2})
	var c := sim.connect_ports(src.id, "out", out.id, "in")
	t.check(sim.set_wire_lanes(c.id, 2), "the wire is upgraded to 2 lanes")
	sim.reset_run()
	for i in 50:
		sim.step()
	t.check(src.lost == 0, "a burst-2 stream over a 2-lane wire loses nothing (lost %d)" % src.lost)
	var warm := 50 - c.length()
	t.check(float(out.received.size()) / float(maxi(1, warm)) >= 1.8, "…and the sink sees >= 1.8 values/tick after warm-up (%.2f)" % (float(out.received.size()) / float(maxi(1, warm))))


# --- draining sinks -------------------------------------------------------------

## A 2-lane wire offers both head packets to the sink in one tick; the sink accepts both
## (capacity 8) and validates both that same tick.
static func _sink_drains_two_packets_in_one_tick(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(16, 10)
	var out := sim.place("usb_output", Vector2i(7, 4), 0, {}, 3)
	var src := sim.place("usb_input", Vector2i(1, 4), 0, {}, 3)
	var c := sim.connect_ports(src.id, "out", out.id, "in")
	t.check(c != null, "source wires to the sink")
	t.check(out.in_capacity("in") >= 2, "a sink accepts several packets in one tick (capacity %d)" % out.in_capacity("in"))
	c.set_lanes(2)
	# one packet on each head slot: both are delivered to the sink this tick
	var n: int = c.length()
	for k in 2:
		c.lane_slots[k][n - 1] = Packet.new(sim.new_packet_id(), BitVector.of(k + 1, 3), 0)
	sim.step()
	t.check(out.received.size() == 2, "the sink drains both packets in one tick (got %d)" % out.received.size())
	var judged := 0
	for e in sim.events:
		if str(e.get("kind", "")) == "output":
			judged += 1
	t.check(judged == 2, "both drained packets are judged the very same tick (outputs %d)" % judged)


# --- the sustain contract rule (FACTORY_SYSTEMS §4) -------------------------------

static func _contract_parses_sustain(t) -> void:
	var c := Contract.from_level({"contract": {"kind": "deliver", "value": "010", "count": 10, "min_rate": 4.0, "sustain": 3.0}})
	t.check(c.sustain == 3.0, "from_level parses sustain (got %f)" % c.sustain)
	t.check(c.min_rate == 4.0, "min_rate is parsed alongside sustain (got %f)" % c.min_rate)
	t.check(c.describe() == "deliver 010 × 10 @ 4/s for 3s", "describe appends ' for Ns' for a sustained rate (got '%s')" % c.describe())
	var plain := Contract.from_level({"contract": {"kind": "deliver", "value": "010", "count": 10}})
	t.check(plain.sustain == 0.0 and plain.describe() == "deliver 010 × 10", "without sustain describe is unchanged")
	t.check(Contract.from_level({"contract": {"kind": "map", "ops": [{"op": "add", "k": 3}], "accept_format": "bits", "accept_width": 3, "min_rate": 4.0, "sustain": 2.0}}).describe() == "map x → x + 3 (3-bit) @ 4/s for 2s", "a map contract shows its sustained rate")


## The fill gate (FACTORY_SYSTEMS §4): min_rate must hold continuously for N Lab seconds.
## No content level sets sustain yet, so a QuestProgress is driven directly on a real LabRun
## board — the `after_tick` / `_check_filled` path is exactly the production code.
static func _lab_sustain_gate(t) -> void:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	run.auto_file = false  # inspect the gate instead of filing the quest
	var q := 0
	run._contracts[q] = Contract.from_level({"contract": {"kind": "deliver", "value": "010", "count": 1, "min_rate": 4.0, "sustain": 2.0}})
	var qp := run.quest_progress(q)
	qp.delivered = 1  # the count is already met
	for i in 30:
		qp.accepted_ticks.append(1 + i)  # a steady 5/s over the last 60 ticks
	for i in 19:
		sim.tick = 1 + i
		run.after_tick(sim)
	t.check(qp.rate_since == 1, "rate_since starts at the first tick the rate held (got %d)" % qp.rate_since)
	t.check(not qp.filled, "before 2 Lab seconds the quest does not fill (tick %d, since %d)" % [sim.tick, qp.rate_since])
	for i in 25:
		sim.tick = 20 + i
		run.after_tick(sim)
	t.check(qp.filled, "the quest fills once the rate held for the full 2 seconds (tick %d, since %d)" % [sim.tick, qp.rate_since])