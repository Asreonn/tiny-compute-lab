extends Node
## The ONLY node that advances the simulation (docs/ARCHITECTURE.md §2, §5).
## Accumulates real time and calls Simulation.step() at TICK_RATE × speed.
## Views read sim.run / sim.sim and interpolate with `alpha`; they never tick the sim.

signal mission_loaded(def: Variant)
signal layout_changed
signal ticked(tick: int)
signal run_state_changed(running: bool)
signal run_finished(status: int)
signal speed_changed(speed: int)
signal view_mode_changed(mode: int)
signal overlay_changed(kind: String)
signal history_changed

const MAX_STEPS_PER_FRAME := 8
## Real-time playback at 1× (player feedback 2026-09-24: 1× should be calm; the former 1× of
## 10 ticks/s is now 3×). Visual motion is continuous between ticks at every speed.
const TICK_RATE := float(Simulation.TICKS_PER_SEC) / 3.0
const SPEEDS := [1, 2, 5, 10]

var sim: Simulation
## The active run: MissionRun (tutorial) or LabRun (lab), both RunBase. Typed as the shared
## base so views can hold either while the Simulation duck-types sim.mission.
var run: RunBase = null
var mission: MissionDef
## True while the persistent Lab is loaded. `lab_run` is the LabRun driving it.
var in_lab := false
var lab_run: LabRun = null
var _lab_level_shown := -1
var running := false
var speed := 1  # allowed: SPEEDS
var alpha := 0.0  # 0..1 progress towards the next tick, for view interpolation only
## Display state only: the ViewMode.Mode the HUD offers for packet/machine values.
## -1 = mission default (the mission's first view mode); reset on every mission load.
var view_mode := -1
## Board overlay over the machines: "" | "thermal" | "power" (keys T / P; at most one at a time).
var overlay := ""
var _acc := 0.0

# --- undo / redo (SYSTEMS_EXPANSION §9): layout snapshots, one step per frame of edits ---
const HISTORY_MAX := 100
var _undo: Array = []  # older snapshots, newest last
var _redo: Array = []
var _snap := ""  # JSON of the current snapshot
var _hist_pending := false
var _restoring := false


func load_mission(id: String) -> void:
	var def := Missions.by_id(id)
	if def == null:
		push_error("SimulationManager.load_mission: unknown mission '%s'" % id)
		return
	sim = Simulation.new()
	mission = def
	in_lab = false
	lab_run = null
	run = MissionRun.new(def)
	run.build_board(sim)
	sim.changed.connect(_on_sim_changed)
	var saved := SaveStore.load_layout(id)
	if not saved.is_empty():
		sim.load_player_layout(saved)
	sim.reset_run()
	running = false
	_acc = 0.0
	alpha = 0.0
	set_view_mode(def.view_modes[0] if not def.view_modes.is_empty() else -1)
	_reset_history()
	mission_loaded.emit(mission)


## Build or restore the persistent Lab. Restoring rebuilds the board of the saved level
## (size + every source up to it) and then lays the player's layout on top.
func load_lab() -> void:
	sim = Simulation.new()
	in_lab = true
	var saved := SaveStore.load_lab()
	var lvl := clampi(int(saved.get("level", 0)), 0, LabDef.LEVELS.size())
	var lr := LabRun.new()
	lr.level = lvl
	lr.build_board(sim)
	lab_run = lr
	run = lr
	mission = LabDef.mission_def(lvl)
	_lab_level_shown = lvl
	sim.changed.connect(_on_sim_changed)
	var lay = saved.get("layout", {})
	if lay is Dictionary and not (lay as Dictionary).is_empty():
		sim.load_player_layout(lay)
	lr.psu_tier = maxi(lr.psu_tier, int(saved.get("psu_tier", 0)))  # never below what the levels earned
	var desk = saved.get("desk", {})
	lr.desk_from_dict(desk if desk is Dictionary else {}, sim)
	lr.delivered = int(saved.get("delivered", 0))
	lr.rejected = int(saved.get("rejected", 0))
	sim.reset_run()
	running = false
	_acc = 0.0
	alpha = 0.0
	set_view_mode(LabDef.view_mode(lvl))
	_reset_history()
	mission_loaded.emit(run)


## Keep the layout autosaved and forward changes to the views. Connected once per mission
## to a fresh Simulation, so it can never reference a stale board.
func _on_sim_changed() -> void:
	layout_changed.emit()
	if sim == null:
		return
	if not _restoring and not _hist_pending:
		_hist_pending = true
		_commit_history.call_deferred()
	if in_lab and lab_run != null:
		if lab_run.level != _lab_level_shown:
			_lab_level_shown = lab_run.level
			mission = LabDef.mission_def(lab_run.level)
			_reset_history()  # never undo across a level-up (the board itself changed)
			mission_loaded.emit(lab_run)
		_save_lab()
	elif mission != null:
		SaveStore.save_layout(mission.id, sim.layout_to_dict())


func _save_lab() -> void:
	if lab_run == null or sim == null:
		return
	SaveStore.save_lab({
		"level": lab_run.level,
		"delivered": lab_run.delivered,
		"rejected": lab_run.rejected,
		"size": [sim.size.x, sim.size.y],
		"layout": sim.layout_to_dict(),
		"devices_owned": Array(lab_run.devices_owned()),
		"desk": lab_run.desk_to_dict(),
		"psu_tier": lab_run.psu_tier,
	})


# ------------------------------------------------------------------ undo / redo

func _snapshot() -> String:
	var d := {"layout": sim.layout_to_dict()}
	if in_lab and lab_run != null:
		d["desk"] = lab_run.desk_to_dict()
	return JSON.stringify(d)


func _reset_history() -> void:
	_undo.clear()
	_redo.clear()
	_hist_pending = false
	_snap = _snapshot() if sim != null else ""
	history_changed.emit()


## Called once per frame after edits: an actual change becomes one undo step.
func _commit_history() -> void:
	_hist_pending = false
	if sim == null:
		return
	var s := _snapshot()
	if s == _snap:
		return
	_undo.append(_snap)
	if _undo.size() > HISTORY_MAX:
		_undo.pop_front()
	_redo.clear()
	_snap = s
	history_changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Ctrl+Z: back to the previous layout (packets of the machines and wires that change are
## dropped, everything else keeps running — Simulation.apply_layout).
func undo() -> bool:
	if sim == null or _undo.is_empty():
		return false
	_redo.append(_snap)
	_restore(_undo.pop_back())
	return true


## Ctrl+Y / Ctrl+Shift+Z.
func redo() -> bool:
	if sim == null or _redo.is_empty():
		return false
	_undo.append(_snap)
	_restore(_redo.pop_back())
	return true


func _restore(snap: String) -> void:
	request_edit()
	var d = JSON.parse_string(snap)
	if typeof(d) != TYPE_DICTIONARY:
		return
	_restoring = true
	sim.apply_layout(d.get("layout", {}))
	if in_lab and lab_run != null and d.has("desk"):
		lab_run.desk_from_dict(d["desk"], sim)
		sim.changed.emit()  # desk-only differences still refresh the views + autosave
	_restoring = false
	_snap = _snapshot()
	history_changed.emit()


func play() -> void:
	if sim == null or running:
		return
	running = true
	run_state_changed.emit(true)


func pause() -> void:
	if not running:
		return
	running = false
	run_state_changed.emit(false)


func toggle() -> void:
	if running:
		pause()
	else:
		play()


## Pause, then advance exactly one tick.
func step_once() -> void:
	if sim == null:
		return
	pause()
	_do_step()


func reset_run() -> void:
	if sim == null:
		return
	pause()
	sim.reset_run()
	_acc = 0.0
	alpha = 0.0
	ticked.emit(0)


## Sim-metric rate (per Simulation.TICKS_PER_SEC ticks) converted to real seconds at 1×.
static func real_rate(sim_rate: float) -> float:
	return sim_rate * TICK_RATE / float(Simulation.TICKS_PER_SEC)


func set_speed(s: int) -> void:
	if s in SPEEDS and s != speed:
		speed = s
		speed_changed.emit(s)


## Toggle the thermal / power overlay (pressing the shown one again hides it).
func toggle_overlay(kind: String) -> void:
	overlay = "" if overlay == kind else kind
	overlay_changed.emit(overlay)


## Switch the display view mode (never the data). Emits view_mode_changed when it changes.
func set_view_mode(mode: int) -> void:
	if mode == view_mode:
		return
	view_mode = mode
	view_mode_changed.emit(mode)


## Tools call this before any Simulation mutation. The lab keeps running while the player
## builds (live editing); the tutorial pauses and resets so layout and run never diverge.
func request_edit() -> void:
	if run != null and run.live_edit:
		return
	pause()
	if sim != null and sim.tick > 0:
		reset_run()


func _process(delta: float) -> void:
	if not running or sim == null:
		return
	_acc += delta * TICK_RATE * speed
	var stepped := 0
	while _acc >= 1.0 and stepped < MAX_STEPS_PER_FRAME:
		_do_step()
		_acc -= 1.0
		stepped += 1
		if not running:  # the run finished inside this frame
			break
	if stepped >= MAX_STEPS_PER_FRAME:
		_acc = minf(_acc, 1.0)  # drop the backlog after a hitch instead of fast-forwarding
	alpha = clampf(_acc, 0.0, 1.0)


## One simulation tick: emit + finish/autosave handling. The only place sim.step() is called.
func _do_step() -> void:
	sim.step()
	ticked.emit(sim.tick)
	if run.status != MissionRun.Status.RUNNING:
		pause()
		run_finished.emit(run.status)
		SaveStore.record_result(mission.id, run.stars(sim), sim.throughput())