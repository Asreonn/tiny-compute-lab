class_name LabRun
extends RunBase
## Lab-mode run: ONE persistent factory, never reset. Implements the same interface the
## Simulation calls on MissionRun (allows / on_output / on_overflow / after_tick / reset /
## build_board) plus the fields the HUD reads. Pure data — no Node, no signals.
##
## QUESTS. Up to QUEST_WINDOW quests are active at once. Each comes with its own sticks: input
## sticks ("text@11") and a Job stick ("job@11"). Every value an input stick emits carries its
## quest; a quest's Job stick judges only that quest's results against its contract (lineage-
## driven, never a constant). A match counts as that quest's `delivered`, anything else as
## `rejected`. A quest is FILLED once its count AND its constraints are met; the player then
## unplugs its Job stick (or any of its sticks) and files it in the desk's COMPLETED tray
## (file_quest) — only then does it count as done and the next quest arrives.
## Breaking a constraint is soft: it only restarts that quest's window, never fails the run.
## Plain modules ("text") belong to the current quest (`level`) — tests and old saves.

## How many quests are active at once (LabConfig.quest_window).
static var QUEST_WINDOW: int:
	get: return LabDef.CONFIG.quest_window

## The effective active-quest window of THIS run: 1 before LabConfig.quest_window_level, else
## quest_window (FACTORY_SYSTEMS §4). The static QUEST_WINDOW getter stays for callers that do
## not have a run.
func quest_window() -> int:
	return 1 if level < LabDef.CONFIG.quest_window_level else LabDef.CONFIG.quest_window

## One quest's progress (per quest; `delivered` & co. below read the current quest's).
class QuestProgress:
	extends RefCounted
	var delivered := 0
	var rejected := 0
	var accepted_ticks: Array[int] = []  # ticks of accepted values, the last 60 (min_rate)
	var rate_since := -1  # the tick since which quest_rate has stayed >= min_rate (sustain)
	var window_lost := 0  # overruns since the window started
	var window_rejected := 0  # wrong deliveries in the window (max_rejected)
	var filled := false  # count + constraints met: ready to be filed
	var warning := ""


var level := 0  # the lowest unfinished quest; == LabDef.LEVELS.size() once every quest is done
var completed: Dictionary = {}  # quest index -> true: filed ahead of `level`
## Tests and tools: a filled quest files itself. The game sets false: the player files it.
var auto_file := true
var files := 0  # quests filed so far (the completion banner / sweep / cue watch it)
var last_filed := -1  # the quest filed last
var unlocked := PackedStringArray()
var level_completed_tick := -1
var drive_quest: Dictionary = {}  # output port id -> the quest it judged last (the drive's face)
var _qp: Dictionary = {}  # quest index -> QuestProgress
var _contracts: Dictionary = {}  # quest index -> Contract (pure data, built once)
## Test runs (JOB C7b): run id -> TestRun, and quest -> the layout_version of its last all-pass
## run (require_test compares it to the current circuit).
var test_runs: Dictionary = {}
var _next_test_run := 1
var test_ok: Dictionary = {}

## Source access (JOB C8b): source id -> "accessible" | "compromised" (absent = locked).
## "compromised" sources are bindable in the Network Inspector; "accessible" ones can be
## acquired (a fictional sequence flips them to compromised).
var sources: Dictionary = {}

## The current quest's progress (the HUD and the older single-quest code read these).
var delivered: int:
	get: return _q(level).delivered
	set(v): _q(level).delivered = v
var rejected: int:
	get: return _q(level).rejected
	set(v): _q(level).rejected = v
var accepted_ticks: Array[int]:
	get: return _q(level).accepted_ticks
var window_lost: int:
	get: return _q(level).window_lost
	set(v): _q(level).window_lost = v
var window_rejected: int:
	get: return _q(level).window_rejected
	set(v): _q(level).window_rejected = v
## Desk zones (docs/SYSTEMS_EXPANSION.md §2.2): slot index -> module kind beside the laptop.
## Every owned device is in exactly one place: a desk slot or a port.
var desk_inputs: Dictionary = {}
var desk_outputs: Dictionary = {}
## Where each stick lies on its free desk area (view data, saved with the desk): kind -> [x, y,
## rot], relative to the area. The desk physics lives in the view (world/desk/desk_view.gd).
var desk_pos: Dictionary = {}
## Devices that landed on the desk on the last level-up (the views pulse them as "New").
var new_devices := PackedStringArray()
## PSU tier (SYSTEMS_EXPANSION §4), an index into LabConfig.psu_capacity / psu_names: 0 Starter 8
## · 1 Improved 16 · 2 Desktop 32 · 3 High-Capacity 64 in the default campaign.
var psu_tier := 0
## NIC tier (JOB C6b): 0 = the Network Module has not been earned yet; 1..3 = its tier.
var nic_tier := 0
var _io_warning := ""


func _init() -> void:
	live_edit = true  # the factory keeps running while the player builds


# ------------------------------------------------------------------ quests

func _q(i: int) -> QuestProgress:
	if not _qp.has(i):
		_qp[i] = QuestProgress.new()
	return _qp[i]


## The active quests, lowest first: up to quest_window() unfinished quests from `level` on.
func active_quests() -> Array[int]:
	var out: Array[int] = []
	var i := level
	while i < LabDef.count() and out.size() < quest_window():
		if not completed.has(i):
			out.append(i)
		i += 1
	return out


## The highest active quest: unlocks, the board size and the open ports follow it.
func frontier() -> int:
	var a := active_quests()
	return a[-1] if not a.is_empty() else level


func quest_contract(q: int) -> Contract:
	if not _contracts.has(q):
		_contracts[q] = LabDef.contract_for(q)
	return _contracts[q]


func quest_title(q: int) -> String:
	return str(LabDef.level(q)["title"])


func quest_progress(q: int) -> QuestProgress:
	return _q(q)


## 0..1 toward the quest's count (1 once it is filled).
func quest_fill(q: int) -> float:
	if _q(q).filled:
		return 1.0
	var n := quest_contract(q).count
	return clampf(float(_q(q).delivered) / float(n), 0.0, 1.0) if n > 0 else 0.0


## The quest a drive shows: its Job stick's, else the one it judged last while that is still
## active, else the current.
func quest_for_drive(port_id: int, sim: Simulation = null) -> int:
	if sim != null and sim.machines.has(port_id):
		var dq := Devices.quest_of(sim.machines[port_id].device)
		if dq >= 0:
			return dq
	var q := int(drive_quest.get(port_id, level))
	return q if q in active_quests() else level


## Filled quests that wait for the COMPLETED tray.
func quests_ready() -> Array[int]:
	var out: Array[int] = []
	for q in active_quests():
		if _q(q).filled:
			out.append(q)
	return out


func quest_rate(q: int) -> float:
	return float(_q(q).accepted_ticks.size()) * Simulation.TICKS_PER_SEC / 60.0


## What bounds quest q's line: the first bound upstream of the drive holding its Job stick.
func quest_bound(sim: Simulation, q: int) -> Dictionary:
	var job := quest_job(q)
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.socket and m.device == job:
			return sim.first_bound(id)
	return {}


## The Job stick a quest comes with ("job@11").
func quest_job(q: int) -> String:
	return Devices.stick("job", q)


# ------------------------------------------------------------------ source access (JOB C8b)

## "accessible" | "compromised" | "locked" (absent).
func source_state(id: String) -> String:
	return str(sources.get(id, "locked"))


## Re-apply the campaign's access rules: every LabConfig.start_sources id is compromised from
## the start; every id in an active quest's LevelDef "access" list becomes accessible unless it
## is already compromised. Never removes an entry: acquired access persists across levels.
func refresh_access() -> void:
	for id in LabDef.CONFIG.start_sources:
		sources[str(id)] = "compromised"
	for q in active_quests():
		for id in LabDef.level(q).get("access", []):
			if source_state(str(id)) != "compromised":
				sources[str(id)] = "accessible"


## The UI plays a 3 s fictional sequence first; this flips the sim state when it ends. Only an
## "accessible" source becomes "compromised" (true); anything else returns false.
func acquire_access(id: String) -> bool:
	if source_state(id) != "accessible":
		return false
	sources[id] = "compromised"
	return true


## True when the quest's Job stick sits in an output port.
func quest_job_plugged(sim: Simulation, q: int) -> bool:
	return _plugged(sim, "out").has(quest_job(q))


## The input sticks a quest comes with ("text@11", "key@11").
func quest_sticks(q: int) -> PackedStringArray:
	var out := PackedStringArray()
	for kind in LabDef.quest_kinds(q):
		out.append(Devices.stick(kind, q))
	return out


## Where a quest's sticks are: {kind@q: port id | -1 on the desk}.
func quest_stick_places(sim: Simulation, q: int) -> Dictionary:
	var out := {}
	for st in quest_sticks(q):
		out[st] = -1
		for id in sim.sorted_machine_ids():
			var m: Machine = sim.machines[id]
			if m.type == "usb_input" and m.device == st:
				out[st] = id
	return out


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


## The stream a stick carries: its quest's (a quest stick) or the current quest's (a plain module).
func stream_for_device(kind: String) -> Dictionary:
	var q := Devices.quest_of(kind)
	return LabDef.stream_spec(q if q >= 0 else level, Devices.base(kind))


## The input sticks the player holds: every active quest's own sticks.
func devices_owned() -> PackedStringArray:
	var out := PackedStringArray()
	for q in active_quests():
		out.append_array(quest_sticks(q))
	return out


## The output devices: every active quest's Job stick, the Monitor from LabConfig.monitor_level
## (L9) on.
func output_devices_owned() -> PackedStringArray:
	var out := PackedStringArray()
	for q in active_quests():
		out.append(quest_job(q))
	if frontier() >= LabDef.CONFIG.monitor_level:
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
	sim.size = LabDef.size_for(frontier())
	sim.default_width = LabDef.request_bits(level).width
	sim.campaign_timing = true
	sim.mission = self
	unlocked = LabDef.unlocks_upto(frontier())
	psu_tier = maxi(psu_tier, LabDef.psu_tier_upto(level))  # rewards of every finished level
	nic_tier = maxi(nic_tier, LabDef.nic_tier_upto(level))
	_ensure_io(sim)
	# a fresh board has the current quest's Job stick in output port 1 (a save re-applies its own)
	var first_out := _output_at(sim, LabDef.PORT_ROWS[0])
	if not all_done() and first_out != null and first_out.device == "":
		sim.insert_device(first_out.id, quest_job(level))
		sync_desk(sim)
	new_devices = PackedStringArray()  # a fresh board is not a level-up: nothing pulses as "New"
	reset(sim)
	refresh_access()
	sim.changed.emit()


## Reset per-run counters only — the factory (machines, wires, progress) is NEVER cleared.
func reset(_sim: Simulation) -> void:
	status = MissionRun.Status.RUNNING
	warning = ""
	failure = {}
	last_ok = [{}]
	for q in _qp:
		var qp: QuestProgress = _qp[q]
		qp.accepted_ticks.clear()
		qp.window_lost = 0
		qp.window_rejected = 0
		qp.warning = ""
	_io_warning = ""
	_sync()


func on_output(sim: Simulation, m: Machine, p: Packet) -> void:
	# A test packet never counts for quests or sales: hand its delivery to its run and stop.
	for k in p.origins:
		var e: Dictionary = p.origins[k]
		if e.has("test"):
			var tr: TestRun = test_runs.get(int(e["run"]))
			if tr != null:
				tr.on_delivery(p)
			return
	var dev := m.device
	if m.type == "nic":
		dev = str(m.params.get("tx_" + str(p.meta.get("tx", "a")), ""))
	if not (m.type == LabDef.OUTPUT_TYPE or m.type == "nic") or not Devices.is_job(dev):
		return
	var q := _quest_of_packet(p)
	# a quest's Job stick takes that quest's results only; a plain Job drive judges any quest
	var dq := Devices.quest_of(dev)
	var target := dq if dq >= 0 else q
	var ok := false
	if target >= 0:
		drive_quest[m.id] = target
	if target >= 0 and target in active_quests() and not _q(target).filled:
		ok = q == target and quest_contract(target).judge(p, _socket_ids_for(sim, target))
		q = target
		var qp := _q(q)
		if ok:
			qp.delivered += 1
			qp.accepted_ticks.append(sim.tick)
			qp.warning = ""
		else:
			qp.rejected += 1
			var c := quest_contract(q)
			if c.max_rejected >= 0:
				qp.window_rejected += 1
				if qp.window_rejected > c.max_rejected:
					_restart_window(q, "A value that should not arrive reached the drive — the window restarted.")
		_trim(q, sim.tick)
		_check_filled(sim, q)
	last_ok = [{"packet": p.id, "ok": ok, "quest": q}]
	progress = [delivered]


## The quest a delivered value belongs to: the quest its sticks stamped (one), the current quest
## for plain modules, -1 when it mixes two quests' data.
func _quest_of_packet(p: Packet) -> int:
	var qs := {}
	for sid in p.origins:
		var e: Dictionary = p.origins[sid]
		if e.has("quest"):
			qs[int(e["quest"])] = true
	if qs.is_empty():
		return level
	return int(qs.keys()[0]) if qs.size() == 1 else -1


## Overflow is not a failure in the lab: the source loops and the player can rewire live.
func on_overflow(_sim: Simulation, _m: Machine, _p: Packet) -> void:
	pass


## Start a test run on source `mid` (a USB socket or a NIC RX channel) for quest `q` (default:
## the current level) and switch the source to TEST. The vectors come from the quest's test set,
## the source's default test vectors, or the first 4 stream values.
func start_test(sim: Simulation, mid: int, channel: String = "", q: int = -1) -> TestRun:
	q = level if q < 0 else q
	sim.set_source_mode(mid, channel, "test")
	var tr := TestRun.build(self, sim, _next_test_run, mid, channel, q)
	_next_test_run += 1
	test_runs[tr.id] = tr
	return tr


## From LabConfig.test_level on, a newly plugged USB stick starts in TEST (JOB C7b).
func test_before_live() -> bool:
	return LabDef.CONFIG.test_level >= 0 and level >= LabDef.CONFIG.test_level


## Lost values feed the max_lost constraint; a broken constraint only restarts the window.
## A stall is only a warning string; the lab never fails.
func after_tick(sim: Simulation) -> void:
	for e in sim.events:
		if str(e.get("kind", "")) == "lost":
			var src: Machine = sim.machines.get(int(e.get("machine", -1)))
			var lq := Devices.quest_of(src.device) if src != null else -1
			_q(lq if lq >= 0 else level).window_lost += 1
	for q in active_quests():
		var c := quest_contract(q)
		var qp := _q(q)
		if c.max_lost >= 0 and qp.window_lost > c.max_lost:
			_restart_window(q, "Values were lost at a USB port — the window restarted.")
		# power / heat caps (soft: breaking one only restarts the window)
		if c.max_power > 0 and sim.power_demand() > c.max_power:
			_restart_window(q, "Power demand %d is over the %d cap — the window restarted." % [sim.power_demand(), c.max_power])
		if c.max_heat >= 0:
			for id in sim.sorted_machine_ids():
				var m: Machine = sim.machines[id]
				if m.heat_stage >= c.max_heat:
					_restart_window(q, "%s reached %s — the window restarted." % [m.label, ThermalGrid.STAGE_NAMES[m.heat_stage]])
					break
		_trim(q, sim.tick)
		# sustain (FACTORY_SYSTEMS §4): track how long min_rate has held, then re-check the
		# fill gate every tick so filling needs the rate to hold for the full N seconds.
		if c.min_rate > 0.0:
			if quest_rate(q) >= c.min_rate:
				if qp.rate_since < 0:
					qp.rate_since = sim.tick
			else:
				qp.rate_since = -1
			if c.sustain > 0.0:
				_check_filled(sim, q)
	# Test runs (JOB C7b): advance every run in id order; an all-pass run on the unchanged
	# circuit records its layout_version for require_test.
	var run_ids := test_runs.keys()
	run_ids.sort()
	for rid in run_ids:
		var tr: TestRun = test_runs[rid]
		if tr.done() and tr.total() > 0:
			continue  # a finished run no longer scans the board
		tr.update(sim, self)
		if tr.done() and tr.all_pass() and tr.version == sim.layout_version:
			test_ok[tr.quest] = tr.version
	var ww := _q(level).warning
	if ww != "":
		warning = ww
	elif _io_warning != "":
		warning = _io_warning
	elif sim.tick - sim.last_activity_tick >= Simulation.STALL_TICKS:
		warning = "Nothing has moved for %d ticks — packets are stuck somewhere." % Simulation.STALL_TICKS
	else:
		warning = ""


func _restart_window(q: int, why: String) -> void:
	var qp := _q(q)
	if qp.filled:
		return  # a filled quest is done; it only waits to be filed
	qp.delivered = 0
	qp.window_lost = 0
	qp.window_rejected = 0
	qp.accepted_ticks.clear()
	qp.rate_since = -1
	qp.warning = why


# ------------------------------------------------------------------ levels

## Count + constraints met: the quest is filled (tests file it right away).
func _check_filled(sim: Simulation, q: int) -> void:
	var c := quest_contract(q)
	var qp := _q(q)
	if qp.filled or qp.delivered < c.count:
		return
	if c.min_rate > 0.0 and quest_rate(q) < c.min_rate:
		return
	if c.sustain > 0.0:
		# min_rate must have held continuously for N Lab seconds (N × 10 ticks).
		if qp.rate_since < 0 or sim.tick - qp.rate_since < int(c.sustain * Simulation.TICKS_PER_SEC):
			return
	if c.max_lost >= 0 and qp.window_lost > c.max_lost:
		return
	# require_test (JOB C7b): the quest files only after one all-pass run on this circuit.
	if bool(LabDef.level(q).get("require_test", false)) and int(test_ok.get(q, -1)) != sim.layout_version:
		qp.warning = "Run the test set on this circuit first"
		return
	qp.filled = true
	qp.warning = ""
	if auto_file:
		file_quest(sim, q)


## File a filled quest (the desk's COMPLETED tray): it counts as done, its sticks are taken, the
## next quest arrives with its sticks, and the board / unlocks / PSU follow. False when the quest
## is not active or not filled yet.
func file_quest(sim: Simulation, q: int) -> bool:
	if q < 0 or q >= LabDef.count() or not q in active_quests() or not _q(q).filled:
		return false
	completed[q] = true
	files += 1
	last_filed = q
	level_completed_tick = sim.tick
	# the quest's sticks (inputs and its Job stick) leave the ports and the desks
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.socket and Devices.quest_of(m.device) == q:
			sim.remove_device(id)
	for d in [desk_inputs, desk_outputs]:
		for slot in d.keys():
			if Devices.quest_of(str(d[slot])) == q:
				d.erase(slot)
	while completed.has(level):
		completed.erase(level)
		_qp.erase(level)
		level += 1
	_qp.erase(q)
	_progress_changed(sim)
	if auto_file:
		_restock_ports(sim)
	return true


## Tests / tools (auto_file): an empty socket takes the next active quest's stick of the kind it
## last held — what a player does right after filing.
func _restock_ports(sim: Simulation) -> void:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		var side := _port_side(m)
		if side == "" or m.device != "" or m.last_device == "" or Devices.quest_of(m.last_device) < 0:
			continue
		var d := _desk(side)
		for q in active_quests():
			var st := Devices.stick(m.last_device, q)
			var owned := quest_sticks(q) if side == "in" else PackedStringArray([quest_job(q)])
			if st in owned and not _plugged(sim, side).has(st):
				var slot := -1
				for k in d:
					if d[k] == st:
						slot = k
				if slot >= 0 and plug_from_desk(sim, side, slot, id):
					break


## File the current quest now (the old single-quest level-up; tests and tools).
func _advance(sim: Simulation) -> void:
	if level >= LabDef.LEVELS.size():
		_sync()
		return
	_q(level).filled = true
	file_quest(sim, level)


## Rebuild what follows the quests: PSU tier, unlocks, board size, ports, desk.
func _progress_changed(sim: Simulation) -> void:
	_io_warning = ""
	psu_tier = maxi(psu_tier, LabDef.psu_tier_upto(level))
	nic_tier = maxi(nic_tier, LabDef.nic_tier_upto(level))
	unlocked = LabDef.unlocks_upto(frontier())
	var sz := LabDef.size_for(frontier())
	var old_size := sim.size
	var grew := sz.x > sim.size.x or sz.y > sim.size.y
	sim.size = Vector2i(maxi(sim.size.x, sz.x), maxi(sim.size.y, sz.y))
	sim.default_width = LabDef.request_bits(mini(level, LabDef.count() - 1)).width
	_ensure_io(sim)
	if grew:
		_move_output_ports(sim, old_size)
	refresh_access()
	_sync()
	sim.changed.emit()


## Ensure the locked port machines and sealed bays match the current level and board size.
func _ensure_io(sim: Simulation) -> void:
	_sync_reservations(sim)
	_ensure_ports(sim)
	_ensure_power_fixtures(sim)
	_ensure_nic(sim)
	if level == 0 and files == 0:
		var first_in := _input_at(sim, LabDef.PORT_ROWS[0])
		if first_in != null and first_in.device == "":
			sim.insert_device(first_in.id, Devices.stick("bit", 0))
	sync_desk(sim)


## Rebuild the sealed bay reservations: every not-yet-open port row reserves its 2x1 footprint
## at the board edge (SYSTEMS_EXPANSION §2.1). Recomputed on every level/size change.
func _sync_reservations(sim: Simulation) -> void:
	sim.reserved.clear()
	for row in LabDef.sealed_rows(frontier(), true):
		for c in _bay_cells(sim, "in", row):
			sim.reserved[c] = LabDef.slot_label("in", row)
	for row in LabDef.sealed_rows(frontier(), false):
		for c in _bay_cells(sim, "out", row):
			sim.reserved[c] = LabDef.slot_label("out", row)
	# the power fixtures' tiles (2x1 input at columns 0-1, 2x2 controller at columns 2-3,
	# rows power_input_row..power_input_row+1) stay sealed until the PSU appears
	if not has_psu():
		var row := LabDef.CONFIG.power_input_row
		var label := "Power · opens at L%d" % (LabDef.CONFIG.power_level + 1)
		for c in [Vector2i(0, row), Vector2i(1, row), Vector2i(2, row), Vector2i(3, row), Vector2i(2, row + 1), Vector2i(3, row + 1)]:
			sim.reserved[c] = label
	# the closed Network Module bay on the top edge (JOB C6b): reserved until a reward earns it
	if nic_tier == 0 and LabDef.CONFIG.nic_bay_level >= 0 and frontier() >= LabDef.CONFIG.nic_bay_level:
		for i in 5:
			sim.reserved[LabDef.CONFIG.nic_cell + Vector2i(i, 0)] = "Network · opens later"


func _bay_cells(sim: Simulation, side: String, row: int) -> Array[Vector2i]:
	if side == "in":
		return [Vector2i(0, row), Vector2i(1, row)]
	return [Vector2i(sim.size.x - 2, row), Vector2i(sim.size.x - 1, row)]


## Add every port open at the current level, in creation order: [input row 1, output row 1]
## first, then the rest as they open (save migration depends on it).
func _ensure_ports(sim: Simulation) -> void:
	for p in LabDef.ports_upto(frontier()):
		var side := str(p["side"])
		var row := int(p["row"])
		if _port_at(sim, side, row) != null:
			continue
		var m := Machine.new(0, "usb_input" if side == "in" else LabDef.OUTPUT_TYPE, LabDef.port_cell(sim.size, side, row), 1)
		m.locked = true
		m.port_row = row  # its identity in saves
		m.socket = true  # Lab port semantics on both sides (module/device slot)
		if side == "in":
			m.loop = true
		sim.add_machine(m)
		var n := LabDef.PORT_ROWS.find(row) + 1
		m.label = "USB In %d" % n if side == "in" else "USB Out %d" % n


## The locked power input + controller at the lower left edge (P5b): the input is the network's
## supply, the controller sets its tier. Created AFTER the ports (the ports' creation order
## must not change; saves match locked machines by creation order). When a player machine
## already holds a tile, the fixtures wait and the player is told to clear the edge (the tiles
## are reserved before the PSU exists, so this only happens on old saves).
func _ensure_power_fixtures(sim: Simulation) -> void:
	if not has_psu():
		return
	var row := LabDef.CONFIG.power_input_row
	for c in [Vector2i(0, row), Vector2i(1, row), Vector2i(2, row), Vector2i(3, row), Vector2i(2, row + 1), Vector2i(3, row + 1)]:
		var m := sim.machine_at(c)
		if m != null and not m.locked:
			_io_warning = "Clear the tiles at the lower left edge for the power input"
			return
	if _power_fixture_at(sim, "power_input", Vector2i(0, row)) == null:
		var mi := Machine.new(0, "power_input", Vector2i(0, row), 1)
		mi.locked = true
		mi.label = "Power Input"
		sim.add_machine(mi)
	var ctrl := _power_fixture_at(sim, "power_controller", Vector2i(2, row))
	if ctrl == null:
		var mc := Machine.new(0, "power_controller", Vector2i(2, row), 1, 0, {"tier": controller_tier()})
		mc.locked = true
		mc.label = "Power Controller"
		sim.add_machine(mc)
	elif str(ctrl.params.get("tier", "")) != controller_tier():
		ctrl.params["tier"] = controller_tier()


func _power_fixture_at(sim: Simulation, type: String, cell: Vector2i) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == type and m.cell == cell:
			return m
	return null


## The locked Network Module, or null before it exists.
func _nic_fixture(sim: Simulation) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "nic":
			return m
	return null


## The locked 5×1 Network Module on the top edge (JOB C6b). Created AFTER the power fixtures
## (locked machines are matched by creation order in saves, so it must come last). Its tier
## follows the rewards; its RX/TX bindings are the player's and survive save/load.
func _ensure_nic(sim: Simulation) -> void:
	if nic_tier <= 0:
		return
	var base := LabDef.CONFIG.nic_cell
	for i in 5:
		var m := sim.machine_at(base + Vector2i(i, 0))
		if m != null and not m.locked:
			_io_warning = "Clear the top edge tiles for the Network Module"
			return
	var nic := _nic_fixture(sim)
	if nic == null:
		var m := Machine.new(0, "nic", base, 16, 0, {"tier": str(nic_tier)})
		m.locked = true
		sim.add_machine(m)
		m.label = "Network Module"
	elif str(nic.params.get("tier", "")) != str(nic_tier):
		nic.params["tier"] = str(nic_tier)


## The port that opened at rack `row`.
func _port_at(sim: Simulation, side: String, row: int) -> Machine:
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.port_row != row and not (m.port_row < 0 and m.cell.y == row):
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
		if m.type == LabDef.OUTPUT_TYPE and Devices.is_job(m.device):
			return m
	return null


## Move every output port to the new east edge, keeping its incoming wire (re-routed through
## the new, empty tiles). If a wire cannot be re-routed, drop that one and warn — never crash.
## Input ports never move.
func _move_output_ports(sim: Simulation, _old_size: Vector2i) -> void:
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


func _trim(q: int, tick: int) -> void:
	var at := _q(q).accepted_ticks
	while not at.is_empty() and at[0] <= tick - 60:
		at.pop_front()


func _socket_ids(sim: Simulation) -> Array[int]:
	var out: Array[int] = []
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "usb_input" and m.socket:
			out.append(id)
	# NIC RX records count as source values for contracts (JOB C6b): after the USB sockets.
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type == "nic":
			out.append(id)
	return out


## The sockets in the order quest `q`'s contract expects: the socket holding its primary stick
## first (map / filter read that origin), then the rest.
func _socket_ids_for(sim: Simulation, q: int) -> Array[int]:
	var all := _socket_ids(sim)
	var want := Devices.stick(quest_contract(q).source_kind, q)
	for id in all:
		if sim.machines[id].device == want:
			var out: Array[int] = [id]
			for other in all:
				if other != id:
					out.append(other)
			return out
	return all


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
	var out := {"in": {}, "out": {}, "pos": desk_pos.duplicate(true)}
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
	var pos = d.get("pos", {})
	desk_pos = (pos as Dictionary).duplicate(true) if pos is Dictionary else {}
	sync_desk(sim)
	new_devices = PackedStringArray()  # restoring a save is not a level-up


# ------------------------------------------------------------------ save

## Save form of the quests: {"completed": [q], "progress": {"q": {delivered, rejected, filled}},
## "files": n}. `level` and the desk are saved beside it.
func quests_to_dict() -> Dictionary:
	var prog := {}
	for q in _qp:
		var qp: QuestProgress = _qp[q]
		if qp.delivered > 0 or qp.rejected > 0 or qp.filled:
			prog[str(q)] = {"delivered": qp.delivered, "rejected": qp.rejected, "filled": qp.filled}
	var done := []
	for q in completed:
		done.append(q)
	done.sort()
	return {"completed": done, "progress": prog, "files": files, "sources": sources.duplicate()}


## Restore the quests BEFORE build_board (the active window decides the board). Old saves without
## quests keep the defaults: only the current quest, counted from `delivered` / `rejected`.
func quests_from_dict(d: Dictionary) -> void:
	completed = {}
	_qp = {}
	for q in d.get("completed", []):
		if int(q) > level and int(q) < LabDef.count():
			completed[int(q)] = true
	var prog = d.get("progress", {})
	if prog is Dictionary:
		for k in prog:
			var e = prog[k]
			if not e is Dictionary or int(k) < level:
				continue
			var qp := _q(int(k))
			qp.delivered = int(e.get("delivered", 0))
			qp.rejected = int(e.get("rejected", 0))
			qp.filled = bool(e.get("filled", false))
	files = int(d.get("files", level + completed.size()))
	# source access (JOB C8b): a Dictionary of String -> "accessible" | "compromised"; bad entries
	# are ignored. Restored BEFORE build_board, whose refresh_access() then re-applies the rules.
	sources = {}
	var src = d.get("sources", {})
	if src is Dictionary:
		for k in src:
			if typeof(k) != TYPE_STRING:
				continue
			var v = src[k]
			if typeof(v) == TYPE_STRING and (v == "accessible" or v == "compromised"):
				sources[k] = v


## Old saves plugged plain modules ("text"): each becomes the matching stick of an active quest
## (the current one first); a plain module no quest needs any more is taken back.
func migrate_plain(sim: Simulation) -> void:
	var plugged := _plugged(sim, "in")
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type != "usb_input" or m.device == "" or Devices.quest_of(m.device) >= 0:
			continue
		var target := ""
		for q in active_quests():
			var st := Devices.stick(m.device, q)
			if st in quest_sticks(q) and not plugged.has(st):
				target = st
				break
		if target == "" or not sim.insert_device(id, target):
			sim.remove_device(id)
		else:
			plugged.append(target)
	# plain Job drives ("job", "job2") become an active quest's Job stick (the current one first)
	var outs := _plugged(sim, "out")
	for id in sim.sorted_machine_ids():
		var m: Machine = sim.machines[id]
		if m.type != LabDef.OUTPUT_TYPE or not Devices.is_job(m.device) or Devices.quest_of(m.device) >= 0:
			continue
		var job := ""
		for q in active_quests():
			if not outs.has(quest_job(q)):
				job = quest_job(q)
				break
		if job == "":
			sim.remove_device(id)
		else:
			sim.insert_device(id, job)
			outs.append(job)
	var owned := devices_owned()
	for slot in desk_inputs.keys():
		if not owned.has(str(desk_inputs[slot])):
			desk_inputs.erase(slot)
	var owned_out := output_devices_owned()
	for slot in desk_outputs.keys():
		if not owned_out.has(str(desk_outputs[slot])):
			desk_outputs.erase(slot)
	sync_desk(sim)
	new_devices = PackedStringArray()


# ------------------------------------------------------------------ HUD helpers

## The module kind the current contract reads from (its primary stream), "" if none.
func needed_module() -> String:
	return contract().source_kind


## True when some open input port holds a module of `kind` (the current quest's stick, or a plain
## module of that kind).
func module_plugged(sim: Simulation, kind: String) -> bool:
	for dev in _plugged(sim, "in"):
		if Devices.base(dev) == kind and Devices.quest_of(dev) in [-1, level]:
			return true
	return false


## True when a Job drive sits in an output port.
func job_plugged(sim: Simulation) -> bool:
	return _job_drive(sim) != null


# ------------------------------------------------------------------ the COMPLETED tray

## Drop a quest stick lying on a desk into the tray: files its quest when it is filled. False
## (and last_error on `sim` says why) when it is not a quest stick or not finished yet.
func file_from_desk(sim: Simulation, slot: int, side := "in") -> bool:
	var d := _desk(side)
	if not d.has(slot):
		return false
	return _file_stick(sim, str(d[slot]))


## Drop a plugged quest stick straight from its port into the tray.
func file_from_port(sim: Simulation, port_id: int) -> bool:
	if not sim.machines.has(port_id):
		return false
	return _file_stick(sim, sim.machines[port_id].device)


func _file_stick(sim: Simulation, kind: String) -> bool:
	var q := Devices.quest_of(kind)
	if q < 0:
		sim.last_error = "Only a quest's stick goes in the tray"
		return false
	if not _q(q).filled:
		sim.last_error = "Not finished yet — %d / %d" % [_q(q).delivered, quest_contract(q).count]
		return false
	return file_quest(sim, q)


# ------------------------------------------------------------------ power

## First level (index) with a PSU: L16 "Power Cap" (SYSTEMS_EXPANSION §10; LabConfig.power_level).
## Earlier levels have unlimited power, so the L1–L15 factories are never browned out.
static var POWER_LEVEL: int:
	get: return LabDef.CONFIG.power_level


func has_psu() -> bool:
	return level >= POWER_LEVEL


## The power network is on once the PSU exists (P5b): the lab then browning out is per-path.
func uses_power_network() -> bool:
	return has_psu()


## The network's onboard budget: what the controller feeds without any copper (0 = unlimited).
func onboard_capacity() -> int:
	return LabDef.CONFIG.onboard_capacity


## The controller tier at the current level: the highest controller_tier_levels entry <= level
## ("ctrl" before the first entry; power_level picks the fixtures, these only pick the tier).
func controller_tier() -> String:
	var tiers := ["ctrl", "basic", "eff", "hc"]
	var gates := LabDef.CONFIG.controller_tier_levels
	var out := "ctrl"
	for i in gates.size():
		if level >= int(gates[i]):
			out = tiers[i]
	return out


## The PSU's capacity in power units, 0 = unlimited (Simulation.work_rate brownout uses it).
func power_capacity() -> int:
	if not has_psu():
		return 0
	return psu_rating()


func psu_rating() -> int:
	var caps := LabDef.CONFIG.psu_capacity
	return int(caps[clampi(psu_tier, 0, caps.size() - 1)])


func psu_name() -> String:
	var names := LabDef.CONFIG.psu_names
	return str(names[clampi(psu_tier, 0, names.size() - 1)])


## First level (index) with heat: L17 "Heat" (SYSTEMS_EXPANSION §10; LabConfig.heat_level).
static var HEAT_LEVEL: int:
	get: return LabDef.CONFIG.heat_level


## Heat is on once the Heat quest is active (even as the second quest: its max_heat must be real).
func thermal_enabled() -> bool:
	return frontier() >= HEAT_LEVEL


## Clock modes are the reward of L16 Power Cap; the Inspector hides the param until then.
func clock_unlocked() -> bool:
	return level > POWER_LEVEL  # the reward of L16 Power Cap


## The highest lane count (1/2/4/8) this run allows (FACTORY_SYSTEMS §3.1): 1, then 2 / 4 / 8
## once `level` reaches LabConfig.lane_levels[0/1/2]. The Inspector hides the Lanes param while
## it returns 1.
func max_lanes() -> int:
	return _unlock_gate(LabDef.CONFIG.lane_levels)


## The highest wire lane count (1/2/4/8) this run allows (FACTORY_SYSTEMS §2.1): 1, then
## 2 / 4 / 8 once `level` reaches LabConfig.bus_lane_levels[0/1/2].
func max_bus_lanes() -> int:
	return _unlock_gate(LabDef.CONFIG.bus_lane_levels)


## The lane count unlocked at `level` for a gate array: 1 until the first entry, then 2 / 4 / 8.
func _unlock_gate(gates: PackedInt32Array) -> int:
	if level >= int(gates[2]):
		return 8
	if level >= int(gates[1]):
		return 4
	if level >= int(gates[0]):
		return 2
	return 1


## Whether the Efficiency upgrade is unlocked (FACTORY_SYSTEMS §3.1): level >= efficiency_level.
## The Inspector hides the Efficiency param while it is false.
func efficiency_unlocked() -> bool:
	return level >= LabDef.CONFIG.efficiency_level

