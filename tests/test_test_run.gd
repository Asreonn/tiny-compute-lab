class_name TestRunTests
extends RefCounted
## Job C7b acceptance tests: the test-run tracker, exact verdicts and require_test
## (game/lab/test_run.gd + the LabRun integration). Each case calls t.check(cond, msg);
## run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_pass_run(t)
	_live_paused(t)
	_fail_run(t)
	_stall(t)
	_require_test(t)


## A fresh L1 lab board: the "bit" stick in USB In 1, its Job drive in USB Out 1.
static func _board() -> Array:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	var sock: Machine = run._input_at(sim, LabDef.PORT_ROWS[0])
	var drive: Machine = run._output_at(sim, LabDef.PORT_ROWS[0])
	return [sim, run, sock, drive]


## 1. Pass: socket -> drive. RUN TEST SET resolves all 4 vectors PASS; the quest counters
## never move (test packets never count).
static func _pass_run(t) -> void:
	var board := _board()
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var sock: Machine = board[2]
	var drive: Machine = board[3]
	sim.connect_ports(sock.id, "out", drive.id, "in")
	var before := run.delivered + run.rejected
	var tr := run.start_test(sim, sock.id)
	tr.run_all(sim)
	var guard := 0
	while not tr.done() and guard < 400:
		sim.step()
		guard += 1
	t.check(tr.done(), "the run resolves within 400 steps (tick %d)" % sim.tick)
	t.check(tr.summary() == "4 / 4 PASS", "summary is '4 / 4 PASS', got '%s'" % tr.summary())
	t.check(tr.all_pass(), "all_pass() is true for a straight wire")
	t.check(run.delivered + run.rejected == before, "test packets never count (delivered %d + rejected %d)" % [run.delivered, run.rejected])


## 2. While a run exists, the socket is in TEST and sends no live records.
static func _live_paused(t) -> void:
	var board := _board()
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var sock: Machine = board[2]
	var drive: Machine = board[3]
	sim.connect_ports(sock.id, "out", drive.id, "in")
	run.start_test(sim, sock.id)
	t.check(sim.source_mode(sock.id) == "test", "starting a run switches the socket to TEST")
	for i in 40:
		sim.step()
	t.check(run.delivered == 0 and run.rejected == 0, "TEST emits no live records (delivered %d, rejected %d)" % [run.delivered, run.rejected])


## 3. Fail: socket -> Inverter -> drive. 010 becomes 101, the contract expects 010: every
## vector fails with the exact delivery/expectation text.
static func _fail_run(t) -> void:
	var board := _board()
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var sock: Machine = board[2]
	var drive: Machine = board[3]
	run.unlocked.append("not_gate")
	var ng := sim.place("not_gate", Vector2i(12, 7), 0, {}, 3)
	t.check(ng != null, "the Inverter places on a free tile")
	sim.connect_ports(sock.id, "out", ng.id, "in")
	sim.connect_ports(ng.id, "out", drive.id, "in")
	var tr := run.start_test(sim, sock.id)
	tr.run_all(sim)
	var guard := 0
	while not tr.done() and guard < 400:
		sim.step()
		guard += 1
	t.check(tr.done(), "the failing run resolves within 400 steps")
	t.check(tr.passed() == 0, "an inverting circuit passes nothing (passed %d)" % tr.passed())
	for line in tr.lines():
		t.check(str(line).contains("delivered 101, expected 010"), "a failing line names the delivery and the expectation (got '%s')" % line)


## 4. Stall: socket -> Gate (ctrl unwired) -> drive. The vector never reaches the drive and
## shows STALLED at the machine after STALL_TICKS.
static func _stall(t) -> void:
	var board := _board()
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var sock: Machine = board[2]
	var drive: Machine = board[3]
	run.unlocked.append("gate")
	var g := sim.place("gate", Vector2i(12, 7), 0, {}, 3)
	t.check(g != null, "the Gate places on a free tile")
	sim.connect_ports(sock.id, "out", g.id, "in")
	sim.connect_ports(g.id, "out", drive.id, "in")
	var tr := run.start_test(sim, sock.id)
	t.check(tr.send_next(sim, run), "send_next emits the first vector")
	for i in 160:
		sim.step()
	var v: Dictionary = tr.vectors[0]
	t.check(v["status"] == "stalled", "a vector stuck in the Gate stalls (got '%s')" % v["status"])
	t.check(str(tr.lines()[0]).contains("STALLED at"), "the stalled line names where it is stuck (got '%s')" % tr.lines()[0])


## 5. require_test: a duplicated config marks the first level require_test; the quest refuses
## to fill without an all-pass run on the current circuit and fills after one.
static func _require_test(t) -> void:
	var cfg: LabConfig = ResourceLoader.load(ContentDB.LAB_CONFIG, "", ResourceLoader.CACHE_MODE_IGNORE)
	var dup: LevelDef = cfg.levels[0].duplicate()
	dup.require_test = true
	var cfg2: LabConfig = cfg.duplicate()
	cfg2.levels = cfg.levels.duplicate()
	cfg2.levels[0] = dup
	LabDef.use_config(cfg2)
	var board := _board()
	var sim: Simulation = board[0]
	var run: LabRun = board[1]
	var sock: Machine = board[2]
	var drive: Machine = board[3]
	sim.connect_ports(sock.id, "out", drive.id, "in")
	run.auto_file = false
	var qp := run.quest_progress(run.level)
	qp.delivered = run.quest_contract(run.level).count
	run._check_filled(sim, run.level)
	t.check(not qp.filled, "require_test: not filled without a passing run")
	t.check(qp.warning == "Run the test set on this circuit first", "require_test sets the exact warning (got '%s')" % qp.warning)
	var tr := run.start_test(sim, sock.id)
	tr.run_all(sim)
	var guard := 0
	while not tr.done() and guard < 400:
		sim.step()
		guard += 1
	t.check(tr.all_pass(), "the straight wire passes the test set")
	t.check(int(run.test_ok.get(run.level, -1)) == sim.layout_version, "an all-pass run records the circuit version")
	run._check_filled(sim, run.level)
	t.check(qp.filled, "require_test: fills after an all-pass run on the unchanged circuit")
	LabDef.use_config(ResourceLoader.load(ContentDB.LAB_CONFIG, "", ResourceLoader.CACHE_MODE_IGNORE))