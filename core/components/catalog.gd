class_name Catalog
extends RefCounted
## The machine registry. Every machine is an asset — content/components/<family>/<id>.tres, a
## ComponentDef — and every variant a ContentVariant of one (docs/CONTENT.md); this class loads
## them once and serves the definition dictionaries the simulation reads. Visually a machine is
## MachineShell(size) + family accent + operation icon + ports (Penpot "05 Machines"); its
## behaviour is the ComponentLogic script its asset names.
##
## Ports are PortDefinitions: {id, dir, role, width, bus, cell, side, label}.
## width is an explicit int (1 for control/flag) or "W" = the instance width.
## There is NO global default width — see docs/ARCHITECTURE.md §4.1.

enum Side { E, S, W, N }  # clockwise order; rotation k adds k (mod 4)

const DIR_IN := "in"
const DIR_OUT := "out"
const DIR_CTRL := "ctrl"

const ROLE_DATA := "data"
const ROLE_CONTROL := "control"
const ROLE_FLAG := "flag"
## Raw ports carry a RawValue, not a BitVector: they only connect to other raw ports
## (docs/ARCHITECTURE.md §0 rule 7) and always have width 0.
const ROLE_RAW := "raw"

## Timing profiles (docs/ARCHITECTURE.md §5): campaign boards give every machine a readable
## dwell ("campaign_ticks") and wires 2 slots per tile, so a value can be followed by eye at
## 1× (10 ticks/s). Legacy regression missions keep the original timings ("ticks", 1 slot/tile).
const CAMPAIGN_SLOTS_PER_TILE := 2

const MIN_WIDTH := 1
const MAX_WIDTH := 64

const SIZES := {"S": Vector2i(1, 1), "M": Vector2i(2, 1), "L": Vector2i(2, 2)}

const FAMILIES := ComponentDef.FAMILIES
const CATEGORIES := [
	{"id": "io", "label": "IO"},
	{"id": "math", "label": "Math"},
	{"id": "logic", "label": "Logic"},
	{"id": "routing", "label": "Routing"},
	{"id": "storage", "label": "Storage"},
]


## Heat per full-rate tick per rated power unit (tenths of °C, SYSTEMS_EXPANSION §5) for a
## machine whose asset leaves `heat` derived; routing makes half. Calibrated in
## tests/test_thermal.gd.
const HEAT_PER_POWER := 84
const HEAT_PER_POWER_ROUTING := 42
## Every powered machine gets this param (SYSTEMS_EXPANSION §6); the Inspector only shows it once
## the run unlocks clock modes (run.clock_unlocked()).
const CLOCK_PARAM := {"label": "Clock", "kind": "enum", "default": "normal", "options": ["normal", "fast", "overclocked"]}
## Every machine with max_lanes > 1 gets this param (its options are the subset ≤ the max);
## the Inspector only shows it once the run unlocks lane upgrades (run.max_lanes() > 1).
const LANES_PARAM := {"label": "Lanes", "kind": "enum", "default": "1", "options": ["1", "2", "4", "8"]}
const LANES_VALUES := [1, 2, 4, 8]
## Every powered machine gets this param (FACTORY_SYSTEMS §3.1); the Inspector only shows it once
## the run unlocks efficiency (run.efficiency_unlocked()).
const EFFICIENCY_PARAM := {"label": "Efficiency", "kind": "enum", "default": "standard", "options": ["standard", "efficient"]}

## type -> ComponentDefinition dictionary, built from the content assets (docs/CONTENT.md):
## {name, family, size, ticks, campaign_ticks, power, heat, icon, glyph_text?, desc, ports,
##  params, logic, order, base?}. params: key -> {label, kind ("int"|"enum"|"text"), default,
## min, max, options}. A variant carries "base": the machine it derives from.
static var DEFS := {}
## Build-menu order: every type by its asset's menu_order (a variant right after its base).
static var ORDER: Array = []


static func _static_init() -> void:
	reload()


## (Re)build DEFS / ORDER from content/components (tests call it after registering fixtures).
static func reload() -> void:
	DEFS = {}
	var table := ContentDB.table(ContentDB.COMPONENTS_DIR, ComponentDef)
	var ids := table.keys()
	ids.sort()
	for t in ids:
		var d: Dictionary = table[t]
		if d.has("base") and not _valid_variant(t, d, table):
			continue
		DEFS[t] = _finish(d)
	for t in DEFS:
		var d: Dictionary = DEFS[t]
		if d.has("base") and DEFS.has(d["base"]) and int(d["order"]) == int(DEFS[d["base"]]["order"]):
			d["order"] = int(d["order"]) + 1  # a variant lists right after its base
	_sort_order()


## Register one more definition at run time (a ComponentDef or a machine ContentVariant).
static func register(r: Resource) -> bool:
	var id := ""
	var d := {}
	if r is ContentVariant:
		id = (r as ContentVariant).id
		d = (r as ContentVariant).resolve()
		if int(d.get("order", 0)) == int(DEFS.get(d.get("base", ""), {}).get("order", -1)):
			d["order"] = int(d["order"]) + 1
		if not _valid_variant(id, d, DEFS):
			return false
	elif r is ComponentDef:
		id = (r as ComponentDef).id
		d = (r as ComponentDef).to_dict()
	if id == "":
		return false
	DEFS[id] = _finish(d)
	_sort_order()
	return true


## Derived fields every definition gets: heat from the power, the Clock param when powered, the
## Lanes param when the def allows parallel jobs, and the Efficiency param when powered.
static func _finish(d: Dictionary) -> Dictionary:
	if not d.has("heat"):
		var per := HEAT_PER_POWER_ROUTING if d["family"] == "routing" else HEAT_PER_POWER
		d["heat"] = per * int(d.get("power", 0))
	var pow := int(d.get("power", 0))
	var max_l := int(d.get("max_lanes", 1))
	if max_l > 1 and not d["params"].has("lanes"):
		var lp := LANES_PARAM.duplicate(true)
		lp["options"] = []
		for k in LANES_VALUES:
			if k <= max_l:
				lp["options"].append(str(k))
		d["params"]["lanes"] = lp
	if pow > 0 and not d["params"].has("efficiency"):
		d["params"]["efficiency"] = EFFICIENCY_PARAM.duplicate(true)
	if pow > 0 and not d["params"].has("clock"):
		d["params"]["clock"] = CLOCK_PARAM.duplicate(true)
	return d


## Power/heat multiplier for a value width (FACTORY_SYSTEMS §3.1):
## 1–5 → 1, 6–8 → 2, 9–16 → 3, 17–32 → 4, 33–64 → 6.
static func width_factor(w: int) -> int:
	if w <= 5:
		return 1
	if w <= 8:
		return 2
	if w <= 16:
		return 3
	if w <= 32:
		return 4
	return 6


## A machine variant keeps its base's shape: size, ports and behaviour (and so its art).
static func _valid_variant(id: String, d: Dictionary, table: Dictionary) -> bool:
	var b: Dictionary = table.get(d["base"], {})
	if b.is_empty():
		push_error("Catalog: variant '%s' has an unknown base '%s'" % [id, d["base"]])
		return false
	if d["size"] != b["size"] or var_to_str(d["ports"]) != var_to_str(b["ports"]) or d.get("logic") != b.get("logic"):
		push_error("Catalog: variant '%s' changes the shape of '%s' (size / ports / logic)" % [id, d["base"]])
		return false
	return true


static func _sort_order() -> void:
	ORDER = DEFS.keys()
	ORDER.sort_custom(func(a, b):
		var oa := int(DEFS[a]["order"])
		var ob := int(DEFS[b]["order"])
		return oa < ob if oa != ob else str(a) < str(b))


## The machine a type derives from: a variant's base, else the type itself.
static func base_type(type: String) -> String:
	return str(DEFS[type].get("base", type)) if DEFS.has(type) else type


static func is_variant(type: String) -> bool:
	return DEFS.has(type) and DEFS[type].has("base")


## The type's ComponentLogic script (null: no behaviour).
static func logic_script(type: String) -> Script:
	return DEFS[type].get("logic") if DEFS.has(type) else null


## Heat a machine makes per tick at its full normal-clock rate (tenths of °C above ambient).
static func heat(type: String) -> int:
	return int(DEFS[type].get("heat", 0))


static func ticks(type: String, campaign: bool) -> int:
	var d: Dictionary = DEFS[type]
	return int(d.get("campaign_ticks", d["ticks"])) if campaign else int(d["ticks"])


static func has(type: String) -> bool:
	return DEFS.has(type)


static func def(type: String) -> Dictionary:
	return DEFS[type]


static func size_of(type: String, rot: int = 0) -> Vector2i:
	var s: Vector2i = SIZES[DEFS[type]["size"]]
	return Vector2i(s.y, s.x) if rot % 2 == 1 else s


static func category_of(type: String) -> String:
	var f: String = DEFS[type]["family"]
	if f == "conversion":
		return "routing"
	return "storage" if f in ["compute", "memory", "control"] else f


static func default_params(type: String) -> Dictionary:
	var out := {}
	for k in DEFS[type]["params"]:
		out[k] = DEFS[type]["params"][k]["default"]
	return out


static func port_def(type: String, port_id: String) -> Dictionary:
	for p in DEFS[type]["ports"]:
		if p["id"] == port_id:
			return p
	return {}


## Rotate a local footprint cell clockwise k times inside a footprint of base size s.
static func rotate_cell(c: Vector2i, s: Vector2i, rot: int) -> Vector2i:
	var cell := c
	var size := s
	for i in rot % 4:
		cell = Vector2i(size.y - 1 - cell.y, cell.x)
		size = Vector2i(size.y, size.x)
	return cell


static func rotate_side(side: int, rot: int) -> int:
	return (side + rot) % 4


static func side_vec(side: int) -> Vector2i:
	match side:
		Side.E: return Vector2i(1, 0)
		Side.S: return Vector2i(0, 1)
		Side.W: return Vector2i(-1, 0)
		_: return Vector2i(0, -1)
