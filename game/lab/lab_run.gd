class_name LabRun
extends RunBase
## Lab-mode run: ONE persistent factory, never reset. Implements the same interface the
## Simulation calls on MissionRun (allows / on_output / on_overflow / after_tick / reset /
## build_board) plus the fields the HUD reads. Pure data — no Node, no signals.
##
## The USB Output validates each arriving BitVector against the current request (width AND
## bits). A match increments `delivered`; anything else is counted in `rejected` and ignored.
## Meeting the count advances to the next level: the board grows, the new level's USB sources
## are added locked, unlocks accumulate and `level_completed_tick` marks the moment (the view
## polls it; no signal is emitted from the pure run).

var level := 0  # current level index; == LabDef.LEVELS.size() once the lab is complete
var delivered := 0
var rejected := 0
var unlocked := PackedStringArray()
var level_completed_tick := -1


func _init() -> void:
	live_edit = true  # the factory keeps running while the player builds


# ------------------------------------------------------------------ accessors

func title() -> String:
	return str(LabDef.level(level)["title"])


func request_bits() -> BitVector:
	return LabDef.request_bits(level)


func request_count() -> int:
	return LabDef.request_count(level)


func view_mode() -> int:
	return LabDef.view_mode(level)


func allows(type: String) -> bool:
	if type in unlocked:
		return true
	# The lab's IO is added locked by build_board; tools/tests may still query these types.
	return type in ["usb_input", "usb_output"]


func correct_total() -> int:
	return delivered


func rejected_total() -> int:
	return rejected


func accuracy() -> float:
	var seen := delivered + rejected
	return 100.0 * delivered / float(seen) if seen > 0 else 100.0


# ------------------------------------------------------------------ run interface

## Fresh lab board for the CURRENT `level`: initial size, the locked USB Output and every
## source up to this level. Never used to reset a running factory — see reset().
func build_board(sim: Simulation) -> void:
	sim.clear()
	sim.size = LabDef.size_for(level)
	sim.default_width = LabDef.request_bits(level).width
	sim.campaign_timing = true
	sim.mission = self
	var out := Machine.new(0, LabDef.OUTPUT_TYPE, LabDef.OUTPUT_CELL, 1)
	out.locked = true
	sim.add_machine(out)
	out.label = "USB Output"
	unlocked = LabDef.unlocks_upto(level)
	for k in range(0, level + 1):
		_add_sources(sim, k)
	reset(sim)
	sim.changed.emit()


## Reset per-run counters only — the factory (machines, wires, progress) is NEVER cleared.
func reset(_sim: Simulation) -> void:
	status = MissionRun.Status.RUNNING
	warning = ""
	failure = {}
	last_ok = [{}]
	_sync()


func on_output(_sim: Simulation, m: Machine, p: Packet) -> void:
	if m.type != LabDef.OUTPUT_TYPE:
		return
	var ok := p.data.equals(request_bits())
	if ok:
		delivered += 1
	else:
		rejected += 1
	last_ok = [{"packet": p.id, "ok": ok}]
	progress = [delivered]
	if delivered >= request_count():
		_advance(_sim)


## Overflow is not a failure in the lab: the source loops and the player can rewire live.
func on_overflow(_sim: Simulation, _m: Machine, _p: Packet) -> void:
	pass


## A stall is only a warning string; the lab never fails.
func after_tick(sim: Simulation) -> void:
	if sim.tick - sim.last_activity_tick >= Simulation.STALL_TICKS:
		warning = "Nothing has moved for %d ticks — packets are stuck somewhere." % Simulation.STALL_TICKS
	else:
		warning = ""


# ------------------------------------------------------------------ levels

func _advance(sim: Simulation) -> void:
	delivered = 0
	warning = ""
	if level >= LabDef.LEVELS.size():
		_sync()
		return
	level += 1
	unlocked = LabDef.unlocks_upto(level)
	var sz := LabDef.size_for(level)
	sim.size = Vector2i(maxi(sim.size.x, sz.x), maxi(sim.size.y, sz.y))
	sim.default_width = LabDef.request_bits(level).width
	_add_sources(sim, level)
	level_completed_tick = sim.tick
	_sync()
	sim.changed.emit()


func _add_sources(sim: Simulation, lvl: int) -> void:
	if lvl < 0 or lvl >= LabDef.LEVELS.size():
		return
	for src in LabDef.level(lvl).get("sources", []):
		var m := Machine.new(0, "usb_input", src["cell"], int(src["width"]))
		m.locked = true
		sim.add_machine(m)
		m.label = "USB Input"
		m.stream = LabDef.source_bits(src)
		m.interval = int(src.get("interval", 4))
		m.loop = true
		m.strict = false
		m.next_emit = 1


func _sync() -> void:
	expected_bits = [[request_bits()]]
	progress = [delivered]
