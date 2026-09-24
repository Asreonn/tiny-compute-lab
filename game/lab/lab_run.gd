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
var _window_warning := ""
var _io_warning := ""


func _init() -> void:
	live_edit = true  # the factory keeps running while the player builds


# ------------------------------------------------------------------ accessors

func title() -> String:
	return str(LabDef.level(level)["title"])


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
	_ensure_io(sim)
	if level == 0:
		var s := _socket(sim)
		if s != null:
			sim.insert_device(s.id, "bit")
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
	_window_warning = ""
	_io_warning = ""
	_sync()


func on_output(sim: Simulation, m: Machine, p: Packet) -> void:
	if m.type != LabDef.OUTPUT_TYPE:
		return
	var ok := contract().judge(p, _socket_ids(sim))
	if ok:
		delivered += 1
		accepted_ticks.append(sim.tick)
		_window_warning = ""
	else:
		rejected += 1
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
	_trim(sim.tick)
	if _window_warning != "":
		warning = _window_warning
	elif _io_warning != "":
		warning = _io_warning
	elif sim.tick - sim.last_activity_tick >= Simulation.STALL_TICKS:
		warning = "Nothing has moved for %d ticks — packets are stuck somewhere." % Simulation.STALL_TICKS
	else:
		warning = ""


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
	level += 1
	unlocked = LabDef.unlocks_upto(level)
	var sz := LabDef.size_for(level)
	var grew := sz.x > sim.size.x or sz.y > sim.size.y
	sim.size = Vector2i(maxi(sim.size.x, sz.x), maxi(sim.size.y, sz.y))
	sim.default_width = LabDef.request_bits(level).width
	_ensure_io(sim)
	if grew:
		_move_drive(sim)
	level_completed_tick = sim.tick
	_sync()
	sim.changed.emit()


## Ensure the locked socket and Contract Drive exist at the grid edges. Sockets never move;
## the drive follows the east edge (see _move_drive).
func _ensure_io(sim: Simulation) -> void:
	if _socket(sim) == null:
		var s := Machine.new(0, "usb_input", LabDef.SOCKET_CELL, 1)
		s.locked = true
		s.socket = true
		s.loop = true
		sim.add_machine(s)
		s.label = "USB Input"
	if _drive(sim) == null:
		var d := Machine.new(0, LabDef.OUTPUT_TYPE, LabDef.drive_cell(sim.size), 1)
		d.locked = true
		sim.add_machine(d)
		d.label = "Contract Drive"


## Move the locked drive to the new east edge, keeping its incoming wire (re-routed through the
## new, empty tiles). If routing fails, drop that one wire and warn — never crash.
func _move_drive(sim: Simulation) -> void:
	var d := _drive(sim)
	if d == null:
		return
	var target := LabDef.drive_cell(sim.size)
	if d.cell == target:
		return
	var was_locked := d.locked
	d.locked = false
	if not sim.move(d.id, target):
		var c := sim.connection_at_port(d.id, "in")
		if c != null:
			sim.disconnect_wire(c.id)
		_io_warning = "The wire to the Contract Drive could not be re-routed."
		sim.move(d.id, target)
	d.locked = was_locked


func _trim(tick: int) -> void:
	while not accepted_ticks.is_empty() and accepted_ticks[0] <= tick - 60:
		accepted_ticks.pop_front()


func _socket(sim: Simulation) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.socket:
			return m
	return null


func _drive(sim: Simulation) -> Machine:
	for id in sim.sorted_machine_ids():
		if sim.machines[id].type == LabDef.OUTPUT_TYPE:
			return sim.machines[id]
	return null


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
