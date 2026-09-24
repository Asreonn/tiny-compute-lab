class_name LabRun
extends RunBase
## Lab-mode run: ONE persistent factory, never reset. Implements the same interface the
## Simulation calls on MissionRun (allows / on_output / on_overflow / after_tick / reset /
## build_board) plus the fields the HUD reads. Pure data — no Node, no signals.
##
## The Contract Drive judges every arriving packet with Contract.judge() (lineage-driven, not a
## constant): a match counts as `delivered`, anything else as `rejected`. The level completes
## once the count AND the contract's constraints (min_rate, max_lost) are met. Breaking a
## constraint is soft: it only restarts the window, never fails the run.

var level := 0  # current level index; == LabDef.LEVELS.size() once the lab is complete
var delivered := 0
var rejected := 0
var unlocked := PackedStringArray()
var level_completed_tick := -1
## Ticks of accepted values, trimmed to the last 60 (the min_rate window).
var accepted_ticks: Array[int] = []
## Overruns since the window started (docs/SYSTEMS_EXPANSION.md §2, §3).
var window_lost := 0
var window_rejected := 0  # wrong deliveries in the window (max_rejected)
var _window_warning := ""
## Desk zones (docs/SYSTEMS_EXPANSION.md §2.2): slot index -> module kind beside the laptop.
## Every owned device is in exactly one place: a desk slot or a port.
var desk_inputs: Dictionary = {}
var desk_outputs: Dictionary = {}
## Devices that landed on the desk on the last level-up (the views pulse them as "New").
var new_devices := PackedStringArray()
## PSU tier (SYSTEMS_EXPANSION §4): 0 Starter 8 · 1 Improved 16 · 2 Desktop 32 · 3 High-Capacity 64.
var psu_tier := 0
const PSU_CAPACITY := [8, 16, 32, 64]
const PSU_NAMES := ["Starter Adapter", "Improved Adapter", "Desktop PSU", "High-Capacity PSU"]
var _io_warning := ""


func _init() -> void:
	live_edit = true  # the factory keeps running while the player builds


# ------------------------------------------------------------------ accessors

func title() -> String:
	return "Free Build" if all_done() else str(LabDef.level(level)["title"])


## Every contract is complete: the Lab is a sandbox (the last contract keeps judging deliveries).
func all_done() -> bool:
	return level >= LabDef.count()


## The current level's contract (fresh, pure data).
func contract() -> Contract:
	return LabDef.contract_for(level)


## A representative BitVector for the HUD's request box (see LabDef.request_bits).
func request_bits() -> BitVector:
	return LabDef.request_bits(level)


func request_count() -> int:
	return contract().count


## Short HUD text for the contract, e.g. "map x → x + 3 (3-bit)".
func request_label() -> String:
	return contract().describe()


func view_mode() -> int:
	return LabDef.view_mode(level)


## Accepted values per Lab second (= per 10 ticks) over the last 60 ticks.
func rate() -> float:
	return float(accepted_ticks.size()) * Simulation.TICKS_PER_SEC / 60.0


func allows(type: String) -> bool:
	if type in unlocked:
		return true
	# The lab's IO is added locked by build_board; tools/tests may still query these types.
	return type in ["usb_input", "usb_output"]


## The contract's stream for a device kind at the current level (Simulation.insert_device).
func stream_for_device(kind: String) -> Dictionary:
	return LabDef.stream_spec(level, kind)


## The data modules the player owns (union of every level up to the current one).
func devices_owned() -> PackedStringArray:
	return LabDef.devices_upto(level)


## The output devices owned from L9 (idx 8) on: the Job drive, then the Monitor.
func output_devices_owned() -> PackedStringArray:
	var out := PackedStringArray(["job"])
	if level >= 8:
		out.append("monitor")
	return out


func correct_total() -> int:
	return delivered


func rejected_total() -> int:
	return rejected


func accuracy() -> float:
	var seen := delivered + rejected
	return 100.0 * delivered / float(seen) if seen > 0 else 100.0


# ------------------------------------------------------------------ run interface

## Fresh lab board for the CURRENT `level`: initial size, the locked socket + Contract Drive and
## the level's unlocks. At L1 the Bit module is plugged in automatically; later levels leave the
## socket empty so the player chooses the module. Never used to reset a running factory.
func build_board(sim: Simulation) -> void:
	sim.clear()
	sim.size = LabDef.size_for(level)
	sim.default_width = LabDef.request_bits(level).width
	sim.campaign_timing = true
	sim.mission = self
	unlocked = LabDef.unlocks_upto(level)
	psu_tier = maxi(psu_tier, LabDef.psu_tier_upto(level))  # rewards of every finished level
	_ensure_io(sim)
	new_devices = PackedStringArray()  # a fresh board is not a level-up: nothing pulses as "New"
	reset(sim)
	sim.changed.emit()


## Reset per-run counters only — the factory (machines, wires, progress) is NEVER cleared.
func reset(_sim: Simulation) -> void:
	status = MissionRun.Status.RUNNING
	warning = ""
	failure = {}
	last_ok = [{}]
	accepted_ticks.clear()
	window_lost = 0
	window_rejected = 0
	_window_warning = ""
	_io_warning = ""
	_sync()


func on_output(sim: Simulation, m: Machine, p: Packet) -> void:
	if m.type != LabDef.OUTPUT_TYPE or m.device != "job":
		return
	var ok := contract().judge(p, _socket_ids(sim))
	if ok:
		delivered += 1
		accepted_ticks.append(sim.tick)
		_window_warning = ""
	else:
		rejected += 1
		var c := contract()
		if c.max_rejected >= 0:
			window_rejected += 1
			if window_rejected > c.max_rejected:
				_restart_window("A value that should not arrive reached the drive — the window restarted.")
	_trim(sim.tick)
	last_ok = [{"packet": p.id, "ok": ok}]
	progress = [delivered]
	_check_complete(sim)


## Overflow is not a failure in the lab: the source loops and the player can rewire live.
func on_overflow(_sim: Simulation, _m: Machine, _p: Packet) -> void:
	pass


## Lost values feed the max_lost constraint; a broken constraint only restarts the window.
## A stall is only a warning string; the lab never fails.
func after_tick(sim: Simulation) -> void:
	var c := contract()
	for e in sim.events:
		if str(e.get("kind", "")) == "lost":
			window_lost += 1
	if c.max_lost >= 0 and window_lost > c.max_lost:
		delivered = 0
		window_lost = 0
		accepted_ticks.clear()
		_window_warning = "Values were lost at USB 1 — the window restarted."
	# power / heat caps (soft: breaking one only restarts the window)
	if c.max_power > 0 and sim.power_demand() > c.max_power:
		_restart_window("Power demand %d is over the %d cap — the window restarted." % [sim.power_demand(), c.max_power])
	if c.max_heat >= 0:
		for id in sim.sorted_machine_ids():
			var m: Machine = sim.machines[id]
			if m.heat_stage >= c.max_heat:
				_restart_window("%s reached %s — the window restarted." % [m.label, ThermalGrid.STAGE_NAMES[m.heat_stage]])
				break
	_trim(sim.tick)
	if _window_warning != "":
		warning = _window_warning
	elif _io_warning != "":
		warning = _io_warning
	elif sim.tick - sim.last_activity_tick >= Simulation.STALL_TICKS:
		warning = "Nothing has moved for %d ticks — packets are stuck somewhere." % Simulation.STALL_TICKS
	else:
		warning = ""


func _restart_window(why: String) -> void:
	delivered = 0
	window_lost = 0
	window_rejected = 0
	accepted_ticks.clear()
	_window_warning = why


# ------------------------------------------------------------------ levels

func _check_complete(sim: Simulation) -> void:
	var c := contract()
	if delivered < c.count:
		return
	if c.min_rate > 0.0 and rate() < c.min_rate:
		return
	if c.max_lost >= 0 and window_lost > c.max_lost:
		return
	_advance(sim)


func _advance(sim: Simulation) -> void:
	delivered = 0
	accepted_ticks.clear()
	window_lost = 0
	_window_warning = ""
	_io_warning = ""
	if level >= LabDef.LEVELS.size():
		_sync()
		return
	# the rewards of the level just finished (SYSTEMS_EXPANSION §10), e.g. a better PSU
	level += 1
	psu_tier = maxi(psu_tier, LabDef.psu_tier_upto(level))
	unlocked = LabDef.unlocks_upto(level)
	var sz := LabDef.size_for(level)
	var grew := sz.x > sim.size.x or sz.y > sim.size.y
	sim.size = Vector2i(maxi(sim.size.x, sz.x), maxi(sim.size.y, sz.y))
	sim.default_width = LabDef.request_bits(level).width
	_ensure_io(sim)
	if grew:
		_move_output_ports(sim)
	level_completed_tick = sim.tick
	_sync()
	sim.changed.emit()


## Ensure the locked port machines and sealed bays match the current level and board size.
func _ensure_io(sim: Simulation) -> void:
	_sync_reservations(sim)
	_ensure_ports(sim)
	if level == 0:
		var first_in := _input_at(sim, LabDef.PORT_ROWS[0])
		if first_in != null and first_in.device == "":
			sim.insert_device(first_in.id, "bit")
	if _job_drive(sim) == null and not desk_outputs.values().has("job"):
		var first_out := _output_at(sim, LabDef.PORT_ROWS[0])
		if first_out != null:
			sim.insert_device(first_out.id, "job")
	sync_desk(sim)


## Rebuild the sealed bay reservations: every not-yet-open port row reserves its 2x1 footprint
## at the board edge (SYSTEMS_EXPANSION §2.1). Recomputed on every level/size change.
func _sync_reservations(sim: Simulation) -> void:
	sim.reserved.clear()
	for row in LabDef.sealed_rows(level, true):
		for c in _bay_cells(sim, "in", row):
			sim.reserved[c] = LabDef.slot_label("in", row)
	for row in LabDef.sealed_rows(level, false):
		for c in _bay_cells(sim, "out", row):
			sim.reserved[c] = LabDef.slot_label("out", row)


func _bay_cells(sim: Simulation, side: String, row: int) -> Array[Vector2i]:
	if side == "in":
		return [Vector2i(0, row), Vector2i(1, row)]
	return [Vector2i(sim.size.x - 2, row), Vector2i(sim.size.x - 1, row)]


## Add every port open at the current level, in creation order: [input row 1, output row 1]
## first, then the rest as they open (save migration depends on it).
func _ensure_ports(sim: Simulation) -> void:
	for p in LabDef.ports_upto(level):
		var side := str(p["side"])
		var row := int(p["row"])
		if _port_at(sim, side, row) != null:
			continue
		var m := Machine.new(0, "usb_input" if side == "in" else LabDef.OUTPUT_TYPE, LabDef.port_cell(sim.size, side, row), 1)
		m.locked = true
		m.socket = true  # Lab port semantics on both sides (module/device slot)
		if side == "in":
			m.loop = true
		sim.add_machine(m)
		var n := LabDef.PORT_ROWS.find(row) + 1
		m.label = "USB In %d" % n if side == "in" else "USB Out %d" % n


func _port_at(sim: Simulation, side: String, row: int) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.cell.y != row:
			continue
		if side == "in":
			if m.type == "usb_input":
				return m
		elif m.type == LabDef.OUTPUT_TYPE:
			return m
	return null


func _input_at(sim: Simulation, row: int) -> Machine:
	return _port_at(sim, "in", row)


func _output_at(sim: Simulation, row: int) -> Machine:
	return _port_at(sim, "out", row)


func _job_drive(sim: Simulation) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == LabDef.OUTPUT_TYPE and m.device == "job":
			return m
	return null


## Move every output port to the new east edge, keeping its incoming wire (re-routed through
## the new, empty tiles). If a wire cannot be re-routed, drop that one and warn — never crash.
## Input ports never move.
func _move_output_ports(sim: Simulation) -> void:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type != LabDef.OUTPUT_TYPE:
			continue
		var target := LabDef.port_cell(sim.size, "out", m.cell.y)
		if m.cell == target:
			continue
		var was_locked := m.locked
		m.locked = false
		if not sim.move(m.id, target):
			var c := sim.connection_at_port(m.id, "in")
			if c != null:
				sim.disconnect_wire(c.id)
			_io_warning = "A wire to an output port could not be re-routed."
			sim.move(m.id, target)
		m.locked = was_locked


func _trim(tick: int) -> void:
	while not accepted_ticks.is_empty() and accepted_ticks[0] <= tick - 60:
		accepted_ticks.pop_front()


func _socket_ids(sim: Simulation) -> Array[int]:
	var out: Array[int] = []
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.socket:
			out.append(id)
	return out


func _sync() -> void:
	expected_bits = [[request_bits()]]
	progress = [delivered]


# ------------------------------------------------------------------ desk zones

## Slots on a desk side: its owned devices + 2 spare (SYSTEMS_EXPANSION §2.2).
func desk_slot_count(side: String) -> int:
	var owned := devices_owned() if side == "in" else output_devices_owned()
	return owned.size() + 2


func _desk(side: String) -> Dictionary:
	return desk_inputs if side == "in" else desk_outputs


func _first_free_slot(side: String) -> int:
	var d := _desk(side)
	for i in desk_slot_count(side):
		if not d.has(i):
			return i
	return -1


## Kinds currently plugged into the ports of one side.
func _plugged(sim: Simulation, side: String) -> PackedStringArray:
	var out := PackedStringArray()
	var ty := "usb_input" if side == "in" else LabDef.OUTPUT_TYPE
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == ty and m.socket and m.device != "":
			out.append(m.device)
	return out


## Make the desks consistent: plugged devices leave the desk, owned devices that are nowhere land
## in the first free slot (and are reported in `new_devices`). Deterministic (owned order).
func sync_desk(sim: Simulation) -> void:
	new_devices = PackedStringArray()
	for side in ["in", "out"]:
		var d := _desk(side)
		var plugged := _plugged(sim, side)
		for slot in d.keys():
			if plugged.has(d[slot]):
				d.erase(slot)
		var owned := devices_owned() if side == "in" else output_devices_owned()
		for kind in owned:
			if plugged.has(kind) or d.values().has(kind):
				continue
			var slot := _first_free_slot(side)
			if slot < 0:
				continue
			d[slot] = kind
			new_devices.append(kind)


func _port_side(m: Machine) -> String:
	if m == null or not m.socket:
		return ""
	return "in" if m.type == "usb_input" else ("out" if m.type == LabDef.OUTPUT_TYPE else "")


## Plug the module lying in `slot` into the port machine. A module already in that port swaps back
## into `slot`. Refusals (wrong side, sealed/unknown port, the wire rule) change nothing.
func plug_from_desk(sim: Simulation, side: String, slot: int, port_id: int) -> bool:
	var d := _desk(side)
	if not d.has(slot) or not sim.machines.has(port_id):
		return false
	var m: Machine = sim.machines[port_id]
	if _port_side(m) != side:
		sim.last_error = "That module belongs in an %s port" % ("input" if side == "in" else "output")
		return false
	var kind: String = d[slot]
	var old := m.device
	if side == "in":
		if not sim.insert_device(port_id, kind):
			return false
	else:
		sim.insert_device(port_id, kind)
	d.erase(slot)
	if old != "":
		d[slot] = old
	return true


## Unplug a port's module onto the desk (slot -1 = first free). Refused when the slot is taken.
func unplug_to_desk(sim: Simulation, port_id: int, slot: int = -1) -> bool:
	if not sim.machines.has(port_id):
		return false
	var m: Machine = sim.machines[port_id]
	var side := _port_side(m)
	if side == "" or m.device == "":
		return false
	var d := _desk(side)
	var target := _first_free_slot(side) if slot < 0 else slot
	if target < 0 or target >= desk_slot_count(side) or d.has(target):
		return false
	var kind := m.device
	sim.remove_device(port_id)
	d[target] = kind
	return true


## Move a module between desk slots (swap when the target is taken).
func move_on_desk(side: String, from_slot: int, to_slot: int) -> bool:
	var d := _desk(side)
	if not d.has(from_slot) or to_slot < 0 or to_slot >= desk_slot_count(side) or from_slot == to_slot:
		return false
	var kind: String = d[from_slot]
	if d.has(to_slot):
		d[from_slot] = d[to_slot]
	else:
		d.erase(from_slot)
	d[to_slot] = kind
	return true


## Save form: {"in": {slot: kind}, "out": {...}} with string keys (JSON).
func desk_to_dict() -> Dictionary:
	var out := {"in": {}, "out": {}}
	for k in desk_inputs:
		out["in"][str(k)] = desk_inputs[k]
	for k in desk_outputs:
		out["out"][str(k)] = desk_outputs[k]
	return out


func desk_from_dict(d: Dictionary, sim: Simulation) -> void:
	desk_inputs = {}
	desk_outputs = {}
	for k in d.get("in", {}):
		desk_inputs[int(k)] = str(d["in"][k])
	for k in d.get("out", {}):
		desk_outputs[int(k)] = str(d["out"][k])
	sync_desk(sim)
	new_devices = PackedStringArray()  # restoring a save is not a level-up


# ------------------------------------------------------------------ HUD helpers

## The module kind the current contract reads from (its primary stream), "" if none.
func needed_module() -> String:
	return contract().source_kind


## True when some open input port has `kind` plugged in.
func module_plugged(sim: Simulation, kind: String) -> bool:
	return _plugged(sim, "in").has(kind)


## True when the Job drive sits in an output port.
func job_plugged(sim: Simulation) -> bool:
	return _job_drive(sim) != null


# ------------------------------------------------------------------ power

## First level (index) with a PSU: L16 "Power Cap" (SYSTEMS_EXPANSION §10). Earlier levels have
## unlimited power, so the L1–L15 factories are never browned out.
const POWER_LEVEL := 15


func has_psu() -> bool:
	return level >= POWER_LEVEL


## The PSU's capacity in power units, 0 = unlimited (Simulation.work_rate brownout uses it).
func power_capacity() -> int:
	if not has_psu():
		return 0
	return psu_rating()


func psu_rating() -> int:
	return int(PSU_CAPACITY[clampi(psu_tier, 0, PSU_CAPACITY.size() - 1)])


func psu_name() -> String:
	return str(PSU_NAMES[clampi(psu_tier, 0, PSU_NAMES.size() - 1)])


## First level (index) with heat: L17 "Heat" (SYSTEMS_EXPANSION §10).
const HEAT_LEVEL := 16


func thermal_enabled() -> bool:
	return level >= HEAT_LEVEL


## Clock modes are the reward of L16 Power Cap; the Inspector hides the param until then.
func clock_unlocked() -> bool:
	return level > POWER_LEVEL  # the reward of L16 Power Cap

