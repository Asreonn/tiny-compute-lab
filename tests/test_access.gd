class_name AccessTests
extends RefCounted
## C8b acceptance tests: LabRun source access (game/lab/lab_run.gd). Logic only, no UI.
## Each case calls t.check(cond, msg); run() is invoked from tests/run_tests.gd. The runner
## restores the shipped campaign before the next suite.

static func run(t) -> void:
	_all_locked(t)
	_start_sources_compromised(t)
	_access_and_acquire(t)
	_save_roundtrip(t)


## A fresh L1 lab board, then the NIC earned at `tier` (0 = no NIC) via the IO refresh.
static func _board(tier: int) -> Array:
	var sim := Simulation.new()
	var run := LabRun.new()
	run.build_board(sim)
	if tier > 0:
		run.nic_tier = tier
		run._ensure_io(sim)
	return [sim, run]


## A duplicated LabConfig (never touches the shipped asset) with the first level replaced by a
## duplicate carrying `access`.
static func _config_with_access(access: PackedStringArray) -> LabConfig:
	var cfg := ResourceLoader.load(ContentDB.LAB_CONFIG, "", ResourceLoader.CACHE_MODE_IGNORE).duplicate(true) as LabConfig
	var lv0 := (cfg.levels[0] as LevelDef).duplicate(true) as LevelDef
	lv0.access = access
	cfg.levels[0] = lv0
	return cfg


## 1. With no start_sources and no access lists every source is "locked".
static func _all_locked(t) -> void:
	var board := _board(1)
	var run: LabRun = board[1]
	t.check(run.sources.is_empty(), "no start_sources and no access lists leave no known source")
	for id in ["forumcache", "shopmirror", "archivenode"]:
		t.check(run.source_state(id) == "locked", "%s is locked (got %s)" % [id, run.source_state(id)])


## 2. A duplicated LabConfig with start_sources = ["forumcache"] makes it compromised.
static func _start_sources_compromised(t) -> void:
	var cfg := ResourceLoader.load(ContentDB.LAB_CONFIG, "", ResourceLoader.CACHE_MODE_IGNORE).duplicate(true) as LabConfig
	cfg.start_sources = PackedStringArray(["forumcache"])
	LabDef.use_config(cfg)
	var board := _board(1)
	var run: LabRun = board[1]
	t.check(run.source_state("forumcache") == "compromised", "a start source is compromised from the start (got %s)" % run.source_state("forumcache"))
	t.check(run.source_state("shopmirror") == "locked", "a non-start source stays locked (got %s)" % run.source_state("shopmirror"))


## 3. A level whose LevelDef has access = ["shopmirror"] makes it accessible; acquire flips it.
static func _access_and_acquire(t) -> void:
	LabDef.use_config(_config_with_access(PackedStringArray(["shopmirror"])))
	var board := _board(1)
	var run: LabRun = board[1]
	t.check(run.source_state("shopmirror") == "accessible", "a level access list makes the source accessible (got %s)" % run.source_state("shopmirror"))
	t.check(run.acquire_access("shopmirror"), "acquire_access on an accessible source returns true")
	t.check(run.source_state("shopmirror") == "compromised", "acquired access flips the source to compromised (got %s)" % run.source_state("shopmirror"))
	t.check(not run.acquire_access("archivenode"), "acquire_access on a locked source returns false")
	t.check(run.source_state("archivenode") == "locked", "a locked source stays locked (got %s)" % run.source_state("archivenode"))
	t.check(not run.acquire_access("shopmirror"), "acquire_access on an already compromised source returns false")


## 4. quests_to_dict -> a fresh LabRun quests_from_dict keeps the source states (bad entries
## are ignored).
static func _save_roundtrip(t) -> void:
	LabDef.use_config(_config_with_access(PackedStringArray(["shopmirror"])))
	var board := _board(1)
	var run: LabRun = board[1]
	run.acquire_access("shopmirror")
	var d := run.quests_to_dict()
	var run2 := LabRun.new()
	run2.quests_from_dict(d)
	t.check(run2.source_state("shopmirror") == "compromised", "saved source states survive quests_from_dict (got %s)" % run2.source_state("shopmirror"))
	var d2 := run.quests_to_dict()
	d2["sources"] = {"shopmirror": "compromised", "bogus": 42, "forumcache": "weird"}
	var run3 := LabRun.new()
	run3.quests_from_dict(d2)
	t.check(run3.source_state("shopmirror") == "compromised", "a valid saved source state is restored")
	t.check(run3.source_state("bogus") == "locked", "a non-string source entry is ignored")
	t.check(run3.source_state("forumcache") == "locked", "an invalid source state value is ignored")