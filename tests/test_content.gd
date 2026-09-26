class_name ContentTests
extends RefCounted
## Content assets (docs/CONTENT.md): every machine, stick and quest loads from content/, the
## registries are complete and consistent, and variants resolve and behave like their base with
## their own numbers.


static func run(t) -> void:
	_components(t)
	_devices(t)
	_levels(t)
	_component_variant(t)
	_bad_variant(t)
	_device_variant(t)
	_level_variant(t)
	_campaign_variant(t)


static func _components(t) -> void:
	var defs := ContentDB.load_dir(ContentDB.COMPONENTS_DIR)
	t.check(defs.size() == Catalog.DEFS.size() and defs.size() >= 46, "every machine asset is in the Catalog (%d)" % defs.size())
	t.check(Catalog.ORDER.size() == Catalog.DEFS.size(), "the build order lists every machine once")
	var bad := PackedStringArray()
	for type in Catalog.DEFS:
		var d: Dictionary = Catalog.def(type)
		if not d["family"] in ComponentDef.FAMILIES or not Catalog.SIZES.has(d["size"]):
			bad.append("%s family/size" % type)
		if d["family"] != "thermal" and d["family"] != "power" and Catalog.logic_script(type) == null:
			bad.append("%s has no logic" % type)
		if Art.layout(type).is_empty() and d["family"] != "thermal":
			bad.append("%s has no art layout" % type)
		for p in d["ports"]:
			if not p["dir"] in ["in", "out", "ctrl"] or not p["role"] in ["data", "control", "flag", "raw"]:
				bad.append("%s port %s" % [type, p["id"]])
		for k in d["params"]:
			var pm: Dictionary = d["params"][k]
			if pm["kind"] == "int" and (int(pm["default"]) < int(pm["min"]) or int(pm["default"]) > int(pm["max"])):
				bad.append("%s param %s default out of range" % [type, k])
			if pm["kind"] == "enum" and not pm["default"] in pm["options"]:
				bad.append("%s param %s default not an option" % [type, k])
	t.check(bad.is_empty(), "every machine asset is complete: %s" % ", ".join(bad))
	t.check(Catalog.heat("add") == Catalog.HEAT_PER_POWER and Catalog.heat("processor") == 440, "heat is derived from the power unless the asset sets it")
	t.check(Catalog.def("add")["params"].has("clock") and not Catalog.def("heatsink")["params"].has("clock"), "powered machines get the Clock param")


static func _devices(t) -> void:
	t.check(Devices.KINDS.size() == 6 and Devices.OUTPUT_KINDS.size() == 3, "6 input sticks and 3 output devices load from content/devices")
	t.check(Devices.glyph("text@4") == "Aa" and Devices.accent("bit") == "data" and Devices.accent("key") == "io", "a stick's glyph and accent come from its asset")
	var s := Devices.make_stream("key", {"values": [5, 7]})
	t.check(s.size() == 2 and s[0] is RawValue and s[0].kind == RawValue.Kind.KEY and s[1].value == 7, "a raw stick's stream follows its raw kind")


static func _levels(t) -> void:
	t.check(LabDef.count() == LabDef.CONFIG.levels.size() and LabDef.count() >= 28, "every quest of lab.tres is loaded (%d)" % LabDef.count())
	var bad := PackedStringArray()
	for i in LabDef.count():
		var lv := LabDef.level(i)
		for u in lv.get("unlocks", []):
			if not Catalog.has(u):
				bad.append("%s unlocks unknown %s" % [lv["id"], u])
		for k in lv.get("streams", {}):
			if not Devices.has(k):
				bad.append("%s streams unknown stick %s" % [lv["id"], k])
		for dv in lv.get("devices", []):
			if not Devices.has(dv):
				bad.append("%s owns unknown stick %s" % [lv["id"], dv])
	t.check(bad.is_empty(), "every quest names known machines and sticks: %s" % ", ".join(bad))
	var cfg := LabDef.CONFIG
	t.check(cfg.input_port_open.size() == cfg.port_rows.size() and cfg.output_port_open.size() == cfg.port_rows.size(), "the port schedule covers every port row")
	t.check(LabDef.slot_label("in", 7) == "USB 3 · opens at L18" and LabDef.slot_label("out", 10) == "USB 4 · sealed", "port labels follow the schedule")


## The example machine variant: a quicker, hungrier Add with its own default.
static func _component_variant(t) -> void:
	t.check(Catalog.register(load("res://content/examples/add_quick.tres")), "a machine variant registers")
	t.check(Catalog.is_variant("add_quick") and Catalog.base_type("add_quick") == "add", "the variant knows its base")
	t.check(Catalog.ORDER.find("add_quick") == Catalog.ORDER.find("add") + 1, "the variant lists right after its base")
	var sim := Simulation.new()
	sim.size = Vector2i(12, 6)
	sim.campaign_timing = true
	var m := sim.place("add_quick", Vector2i(2, 2), 0, {}, 3)
	t.check(m != null and m.type == "add" and m.def_id() == "add_quick", "a placed variant runs as its base")
	t.check(m.processing_ticks() == 2 and m.power() == 2 and int(m.params["k"]) == 3, "…with its own numbers and defaults")
	t.check(m.label.begins_with("Quick Add") and m.heat() == Catalog.HEAT_PER_POWER * 2, "…its own name, and heat from its own power")
	m.inq["in"].append(Packet.new(sim.new_packet_id(), BitVector.of(2, 3), 0))
	ComponentLogic.for_type(m.type).start(m, sim)
	var r: Packet = (m.job.get("results", {}) as Dictionary).get("out")
	t.check(r != null and r.data.equals(BitVector.of(5, 3)), "…and behaves like an Add (010 + 011 = 101)")
	var d := sim.layout_to_dict()
	var sim2 := Simulation.new()
	sim2.size = sim.size
	sim2.load_player_layout(d)
	var m2: Machine = sim2.machines.values()[0] if not sim2.machines.is_empty() else null
	t.check(m2 != null and m2.def_id() == "add_quick", "a save keeps the variant")
	var clip := sim.copy_group([m.id])
	var pasted := sim.paste_group(clip, Vector2i(6, 2))
	t.check(pasted.size() == 1 and sim.machines[pasted[0]].def_id() == "add_quick", "a copy keeps the variant")
	Catalog.reload()
	t.check(not Catalog.has("add_quick"), "reload() drops run-time registrations")


## A variant may not change its base's shape: its ports, size and art are the base's.
static func _bad_variant(t) -> void:
	var v := ContentVariant.new()
	v.id = "add_wide"
	v.base = load("res://content/components/math/add.tres")
	v.overrides = {"size": "L"}
	t.check(not Catalog.register(v) and not Catalog.has("add_wide"), "a variant that changes the size is refused")


static func _device_variant(t) -> void:
	t.check(Devices.register(load("res://content/examples/sensor_hot.tres")), "a stick variant registers")
	t.check(Devices.display_name("sensor_hot@3") == "Thermo module" and Devices.glyph("sensor_hot") == "°C", "…with its own name and glyph")
	var s := Devices.make_stream("sensor_hot", {"values": [3]})
	t.check(s.size() == 1 and s[0].kind == RawValue.Kind.SENSOR, "…and its base's stream kind")
	Devices.reload()
	t.check(not Devices.has("sensor_hot"), "Devices.reload() drops it again")


static func _level_variant(t) -> void:
	var q: ContentVariant = load("res://content/examples/02b_plus_three.tres")
	var d := q.resolve()
	t.check(d["title"] == "Plus Three" and d["base"] == "lab_l2", "a quest variant renames its base")
	var c := Contract.from_level(d)
	t.check(c.count == 30 and c.value.equals(BitVector.from_bin("101")), "…and merges its contract changes (count 30, value 101)")
	t.check(Array(d["unlocks"]) == ["add"], "…keeping what it does not override")


## A campaign variant: another LabConfig swaps the quest list and the rules at once.
static func _campaign_variant(t) -> void:
	var main := LabDef.CONFIG
	var cfg := LabConfig.new()
	cfg.levels = [main.levels[0], load("res://content/examples/02b_plus_three.tres")]
	cfg.quest_window = 1
	LabDef.use_config(cfg)
	t.check(LabDef.count() == 2 and LabDef.level(1)["title"] == "Plus Three" and LabRun.QUEST_WINDOW == 1, "LabDef.use_config switches the campaign")
	var run := LabRun.new()
	run.level = 1
	t.check(run.active_quests() == [1], "the quest window follows the config")
	LabDef.use_config(main)
	t.check(LabDef.count() >= 28 and LabRun.QUEST_WINDOW == 2, "…and back")
