extends Node
## The ONLY node that advances the simulation (docs/ARCHITECTURE.md §2, §5).
## Accumulates real time and calls Simulation.step() at TICK_RATE × speed.
## Views read sim.run / sim.sim and interpolate with `alpha`; they never tick the sim.

signal mission_loaded(def: MissionDef)
signal layout_changed
signal ticked(tick: int)
signal run_state_changed(running: bool)
signal run_finished(status: int)
signal speed_changed(speed: int)
signal view_mode_changed(mode: int)

const MAX_STEPS_PER_FRAME := 8
## Real-time playback at 1× (player feedback 2026-09-24: 1× should be calm; the former 1× of
## 10 ticks/s is now 3×). Visual motion is continuous between ticks at every speed.
const TICK_RATE := float(Simulation.TICKS_PER_SEC) / 3.0
const SPEEDS := [1, 2, 5, 10]

var sim: Simulation
var run: MissionRun
var mission: MissionDef
var running := false
var speed := 1  # allowed: SPEEDS
var alpha := 0.0  # 0..1 progress towards the next tick, for view interpolation only
## Display state only: the ViewMode.Mode the HUD offers for packet/machine values.
## -1 = mission default (the mission's first view mode); reset on every mission load.
var view_mode := -1
var _acc := 0.0


func load_mission(id: String) -> void:
	var def := Missions.by_id(id)
	if def == null:
		push_error("SimulationManager.load_mission: unknown mission '%s'" % id)
		return
	sim = Simulation.new()
	mission = def
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
	mission_loaded.emit(mission)


## Keeps the layout autosaved and forwards changes to the views. Connected once per mission
## to a fresh Simulation, so it can never reference a stale board.
func _on_sim_changed() -> void:
	layout_changed.emit()
	if sim != null and mission != null:
		SaveStore.save_layout(mission.id, sim.layout_to_dict())


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


## Switch the display view mode (never the data). Emits view_mode_changed when it changes.
func set_view_mode(mode: int) -> void:
	if mode == view_mode:
		return
	view_mode = mode
	view_mode_changed.emit(mode)


## Tools call this before any Simulation mutation: editing while running is allowed, but the
## in-flight run resets first so the layout and the run never diverge.
func request_edit() -> void:
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