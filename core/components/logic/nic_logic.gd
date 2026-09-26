extends ComponentLogic
## Network Interface Card (JOB C6a): a locked 5×1 fixture that moves records between remote
## sources and the factory under ONE frame budget per Lab second. It never understands the
## data it carries. Pure and deterministic: fixed iteration order (a, b, c / a, b), no RNG,
## no Node.

class_name NicLogic

## Frames per second per tier (a frame is 16 bits).
const CAP := {1: 12, 2: 24, 3: 48}
const RX := ["a", "b", "c"]
const TX := ["a", "b"]


## The machine's tier, clamped to 1..3 (param "tier").
static func tier(m) -> int:
	return clampi(int(str(m.params.get("tier", "1"))), 1, 3)


## Ports open at the machine's tier (the rest are sealed with caps).
static func open_ports(t: int) -> PackedStringArray:
	match t:
		1: return PackedStringArray(["rx_a", "tx_a"])
		2: return PackedStringArray(["rx_a", "rx_b", "tx_a", "tx_b"])
	return PackedStringArray(["rx_a", "rx_b", "rx_c", "tx_a", "tx_b"])


## Frames a record of `width` bits costs (16 bits = 1 frame).
static func frames(width: int) -> int:
	return maxi(1, ceili(width / 16.0))


## Frames used in the last Lab second (the sum of the frames window).
static func load_per_sec(m) -> int:
	var sum := 0
	for f in m.net.get("frames", []):
		sum += int(f)
	return sum


## The tier's frame budget per second.
static func capacity(m) -> int:
	return CAP[tier(m)]


## A fresh per-channel remote buffer: the next remote seq, the records waiting remotely,
## the accumulator for the source's rate, and the counters.
static func _ch() -> Dictionary:
	return {"seq": 0, "buf": 0, "acc": 0.0, "sent": 0, "lost": 0, "waited": false}


## Runs once per tick (Machine.start calls it directly — the NIC spends its own frame
## budget and has no lane gate).
func start(m, sim) -> void:
	if m.net.is_empty():
		m.net = {
			"credit": 0.0,
			"rx": {"a": _ch(), "b": _ch(), "c": _ch()},
			"tx": {"a": {"sent": 0}, "b": {"sent": 0}},
			"frames": [],
			"waited": false,
		}
	var net: Dictionary = m.net
	var t := tier(m)
	var cap: int = CAP[t]
	# 1. credit: the frame budget accrues 1 second's worth per second, capped at half a
	# second (at least 4 frames so a 32-bit record can always start).
	net["credit"] = minf(float(net["credit"]) + cap / float(Simulation.TICKS_PER_SEC), maxf(4.0, cap / 2.0))
	# 2. remote generation: every open RX channel whose source id resolves. A normal source
	# pauses when its remote buffer is full; a realtime source drops the oldest record.
	var open := open_ports(t)
	for ch in RX:
		if not "rx_" + ch in open:
			continue
		if str(m.params.get("mode_" + ch, "live")) == "test":
			continue  # test mode: the channel pauses remotely (JOB C7a)
		var src_id := str(m.params.get("rx_" + ch, ""))
		if src_id == "":
			continue
		var def := SourceStream.source(src_id)
		if def == null:
			continue
		var ch_state: Dictionary = net["rx"][ch]
		ch_state["acc"] = float(ch_state["acc"]) + def.rate / float(Simulation.TICKS_PER_SEC)
		while float(ch_state["acc"]) >= 1.0:
			ch_state["acc"] = float(ch_state["acc"]) - 1.0
			if int(ch_state["buf"]) < def.remote_buffer:
				ch_state["buf"] = int(ch_state["buf"]) + 1
			elif def.realtime:
				ch_state["seq"] = int(ch_state["seq"]) + 1
				ch_state["lost"] = int(ch_state["lost"]) + 1
				sim.events.append({"kind": "lost", "machine": m.id})
			else:
				ch_state["acc"] = 0.0
				break
	# 3. TX first, so the factory always drains: empty every open TX queue the credit allows.
	var frames_this_tick := 0
	for ch in TX:
		if not "tx_" + ch in open:
			continue
		var port: String = "tx_" + ch
		var tx_state: Dictionary = net["tx"][ch]
		while not (m.inq[port] as Array).is_empty():
			var p: Packet = m.inq[port][0]
			var f := frames(p.data.width if p.data != null else 16)
			if float(net["credit"]) < f:
				net["waited"] = true
				break
			m.pop(port)
			p.meta["tx"] = ch
			sim.note_output(m, p)
			net["credit"] = float(net["credit"]) - f
			frames_this_tick += f
			tx_state["sent"] = int(tx_state["sent"]) + 1
			m.processed += 1
			m.received.append(p)
			while m.received.size() > 16:
				m.received.pop_front()
			sim.events.append({"kind": "tx", "machine": m.id, "channel": ch, "packet": p.id})
	# 4. RX, round-robin starting at sim.tick % open_rx_count over the open, bound channels
	# with records waiting; repeat passes while at least one record moved. One record waits on
	# its port (outq) until the wire takes it.
	var rx_open: Array = []
	for ch in RX:
		if "rx_" + ch in open and str(m.params.get("rx_" + ch, "")) != "" and SourceStream.source(str(m.params.get("rx_" + ch, ""))) != null and str(m.params.get("mode_" + ch, "live")) != "test":
			rx_open.append(ch)
	if not rx_open.is_empty():
		var moved := true
		while moved:
			moved = false
			for k in rx_open.size():
				var ch: String = rx_open[(sim.tick + k) % rx_open.size()]
				var ch_state: Dictionary = net["rx"][ch]
				if int(ch_state["buf"]) <= 0:
					continue
				if m.outq["rx_" + ch] != null:
					continue
				var def: RemoteSourceDef = SourceStream.source(str(m.params.get("rx_" + ch, "")))
				var f := frames(def.width)
				if float(net["credit"]) < f:
					ch_state["waited"] = true
					continue
				var seq := int(ch_state["seq"])
				var v := SourceStream.record(def, SourceStream.population(), seq)
				var p := Packet.new(sim.new_packet_id(), v, sim.tick)
				p.origins[m.id] = {"seq": seq, "value": v, "source": def.id, "channel": ch}
				p.ctx = seq  # records of the same seq from different sources pair up
				p.path.append(m.label)
				m.outq["rx_" + ch] = p
				ch_state["seq"] = seq + 1
				ch_state["buf"] = int(ch_state["buf"]) - 1
				ch_state["sent"] = int(ch_state["sent"]) + 1
				net["credit"] = float(net["credit"]) - f
				frames_this_tick += f
				m.processed += 1
				moved = true
	# 5. frames window: the last second's frame counts; every second boundary clears the
	# "waited during this second" flags first.
	var frames_arr: Array = net["frames"]
	if sim.tick % Simulation.TICKS_PER_SEC == 0:
		net["waited"] = false
		for ch in RX:
			(net["rx"][ch] as Dictionary)["waited"] = false
	frames_arr.append(frames_this_tick)
	while frames_arr.size() > Simulation.TICKS_PER_SEC:
		frames_arr.pop_front()