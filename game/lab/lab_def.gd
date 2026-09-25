class_name LabDef
extends RefCounted
## Lab mode data (docs/IMPLEMENTATION.md "Lab mode", docs/SYSTEMS_EXPANSION.md §10): one
## persistent factory that grows as each quest is met. The campaign is an asset —
## content/lab/lab.tres, a LabConfig listing the quests (LevelDef assets) and the progression
## rules (docs/CONTENT.md) — read here as plain data. LabRun does the ticking.
##
## A level is {id, title, brief, contract, streams, devices, unlocks, grow, view, reward}:
##   contract  the Contract dictionary (kind, ops, count, constraints) — see game/lab/contract.gd
##   streams   {kind: {values, width?, interval?, pattern?}} — the contract's stream per device kind
##   devices   data modules owned from this level on
##   unlocks   machine types unlocked when this level starts
##   grow      board size once this level starts (never smaller than the previous)
##   view      ViewMode.Mode used to display the contract
## The laptop port racks (docs/SYSTEMS_EXPANSION.md §2.1): input ports on the west edge (column
## 0) and output ports on the east edge (last two columns), at the config's port rows. Each row
## opens at the level the config names; the sealed ones are reserved bays until then.

const SOCKET_CELL := Vector2i(0, 1)
const OUTPUT_TYPE := "usb_output"

## The 8 three-bit words several quests stream (kept for tests that check a stream).
const WORDS_3 := ["010", "101", "111", "000", "011", "110", "001", "100"]

## The active campaign and its quests (dictionary form, LevelDef.to_dict).
static var CONFIG: LabConfig
static var LEVELS: Array = []
## From the config: the board before any quest grows it, and every port row top to bottom.
static var INITIAL_SIZE := Vector2i(28, 16)
static var PORT_ROWS: Array = []


static func _static_init() -> void:
	use_config(load(ContentDB.LAB_CONFIG))


## Switch the campaign (a LabConfig asset; tests and campaign variants).
static func use_config(cfg: LabConfig) -> void:
	CONFIG = cfg
	LEVELS = cfg.level_dicts()
	INITIAL_SIZE = cfg.initial_size
	PORT_ROWS = Array(cfg.port_rows)


## The level index a port row of `side` opens at: 0 from the start, -1 never.
static func port_open_level(side: String, row: int) -> int:
	var i := PORT_ROWS.find(row)
	var opens: PackedInt32Array = CONFIG.input_port_open if side == "in" else CONFIG.output_port_open
	return int(opens[i]) if i >= 0 and i < opens.size() else -1


## The best PSU tier earned by the levels finished before level `i` (their "reward" entries).
static func psu_tier_upto(i: int) -> int:
	var t := 0
	for k in range(0, clampi(i, 0, LEVELS.size())):
		t = maxi(t, int(LEVELS[k].get("reward", {}).get("psu_tier", 0)))
	return t


## Index of the first level that unlocks machine `type`, or -1 when no level does (yet).
static func unlock_level(type: String) -> int:
	for i in LEVELS.size():
		if type in (LEVELS[i].get("unlocks", []) as Array):
			return i
	return -1


static func count() -> int:
	return LEVELS.size()


static func level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


## The Contract of level `i` (fresh each call; cheap and pure).
static func contract_for(i: int) -> Contract:
	return Contract.from_level(level(i))


## The cell of the port at `row` on `side` ("in" = west column 0, "out" = east edge).
static func port_cell(size: Vector2i, side: String, row: int) -> Vector2i:
	return Vector2i(0 if side == "in" else size.x - 2, row)


## The default drive cell once the board is `size`: the east edge, row 1.
static func drive_cell(size: Vector2i) -> Vector2i:
	return port_cell(size, "out", PORT_ROWS[0])


## The input rows open at level index `level_idx` (LabConfig.input_port_open).
static func open_input_rows(level_idx: int) -> Array[int]:
	return _open_rows("in", level_idx)


## The output rows open at level index `level_idx` (LabConfig.output_port_open).
static func open_output_rows(level_idx: int) -> Array[int]:
	return _open_rows("out", level_idx)


static func _open_rows(side: String, level_idx: int) -> Array[int]:
	var out: Array[int] = []
	for r in PORT_ROWS:
		var at := port_open_level(side, r)
		if at >= 0 and at <= level_idx:
			out.append(r)
	return out


## The rows of `side` still sealed at level index `idx`.
static func sealed_rows(level_idx: int, input_side: bool) -> Array[int]:
	var open := open_input_rows(level_idx) if input_side else open_output_rows(level_idx)
	var out: Array[int] = []
	for r in PORT_ROWS:
		if not open.has(r):
			out.append(r)
	return out


## Every port open at level index `idx`, as [{side, row}] in board creation order: by the level
## it opens at, then top to bottom, input before output — so the ports open from the start come
## first as [input row 1, output row 1, …] (save migration depends on it).
static func ports_upto(level_idx: int) -> Array:
	var keyed: Array = []
	for i in PORT_ROWS.size():
		for side in ["in", "out"]:
			var at := port_open_level(side, PORT_ROWS[i])
			if at >= 0 and at <= level_idx:
				keyed.append([at, i, 0 if side == "in" else 1, {"side": side, "row": PORT_ROWS[i]}])
	keyed.sort()
	var out: Array = []
	for k in keyed:
		out.append(k[3])
	return out


## The view label of a port slot: "USB 2 · opens at L12" or "USB 4 · sealed".
static func slot_label(side: String, row: int) -> String:
	var n := PORT_ROWS.find(row) + 1
	var open_at := port_open_level(side, row)
	if open_at > 0:
		return "USB %d · opens at L%d" % [n, open_at + 1]
	return "USB %d · sealed" % n


## A representative BitVector for the HUD (LabRun.request_bits). deliver: the value. Others:
## the mapped first stream element when it is bits (the last bits value before a trailing
## decode), else BitVector.zero(1).
static func request_bits(i: int) -> BitVector:
	var c := contract_for(i)
	if c.kind == "deliver":
		return c.value if c.value is BitVector else BitVector.zero(1)
	var kind := primary_stream_kind(i)
	var stream := Devices.make_stream(kind, stream_spec(i, kind))
	if not stream.is_empty():
		var rep = c.representative_bits(stream[0])
		if rep is BitVector:
			return rep
	return BitVector.zero(1)


static func request_count(i: int) -> int:
	return contract_for(i).count


static func view_mode(i: int) -> int:
	return int(level(i).get("view", ViewMode.Mode.BIN))


## Cumulative unlocks once level `i` starts (levels 0..i).
static func unlocks_upto(i: int) -> PackedStringArray:
	var out := PackedStringArray()
	for k in range(0, clampi(i, 0, LEVELS.size() - 1) + 1):
		for u in LEVELS[k].get("unlocks", []):
			if not out.has(u):
				out.append(u)
	return out


## The data modules owned once level `i` starts (union of levels 0..i).
## The stick kinds quest `i` comes with: its own streams' kinds, or — for a level that reuses the
## earlier stream (L2, L3) — the kinds of the last level that defined one.
static func quest_kinds(i: int) -> PackedStringArray:
	for k in range(clampi(i, 0, LEVELS.size() - 1), -1, -1):
		var streams: Dictionary = LEVELS[k].get("streams", {})
		if not streams.is_empty():
			return PackedStringArray(streams.keys())
	return PackedStringArray(["bit"])


static func devices_upto(i: int) -> PackedStringArray:
	var out := PackedStringArray()
	for k in range(0, clampi(i, 0, LEVELS.size() - 1) + 1):
		for d in LEVELS[k].get("devices", []):
			if not out.has(d):
				out.append(d)
	return out


## Board size once level `i` starts: the largest grow of levels 0..i.
static func size_for(i: int) -> Vector2i:
	var s := INITIAL_SIZE
	for k in range(0, clampi(i, 0, LEVELS.size() - 1) + 1):
		var g: Variant = LEVELS[k].get("grow", null)
		if g is Vector2i:
			s = Vector2i(maxi(s.x, g.x), maxi(s.y, g.y))
	return s


## The stream kind of the primary socket at level `i`: the level's own first stream, else the
## latest level <= i that defines one (streams are inherited).
static func primary_stream_kind(i: int) -> String:
	var idx := clampi(i, 0, LEVELS.size() - 1)
	for k in range(idx, -1, -1):
		var streams: Dictionary = LEVELS[k].get("streams", {})
		if not streams.is_empty():
			return str(streams.keys()[0])
	return ""


## The contract's stream spec for a device kind at level `i`: the spec of the LATEST level <= i
## that defines that kind ({} when none does). The stream belongs to the contract, so a socket
## always carries the newest applicable stream.
static func stream_spec(level_idx: int, kind: String) -> Dictionary:
	var idx := clampi(level_idx, 0, LEVELS.size() - 1)
	for k in range(idx, -1, -1):
		var streams: Dictionary = LEVELS[k].get("streams", {})
		if streams.has(kind):
			return streams[kind]
	return {}


## A MissionDef-shaped view of a level so the existing HUD/views can read it unchanged.
## The lab's real run is a LabRun; this is presentation data only.
static func mission_def(i: int) -> MissionDef:
	var idx := clampi(i, 0, LEVELS.size() - 1)
	var lv := level(idx)
	var c := contract_for(idx)
	var want := request_bits(idx)
	var d := MissionDef.new()
	d.id = "lab"
	d.index = idx
	d.title = str(lv["title"])
	d.brief = str(lv["brief"])
	d.formula = c.describe()
	d.board_size = size_for(idx)
	d.default_width = want.width
	d.view_modes = [view_mode(idx)]
	d.allowed = unlocks_upto(idx)
	d.unlocks = PackedStringArray(lv.get("unlocks", []))
	var kind := primary_stream_kind(idx)
	var spec := stream_spec(idx, kind)
	var vals := []
	for bv in Devices.make_stream(kind, spec):
		if bv is BitVector:
			vals.append(raw_bin(bv))
	d.inputs = [{"cell": SOCKET_CELL, "rot": 0, "width": want.width, "values": vals, "interval": int(spec.get("interval", 4)), "strict": false, "start": 1, "source": "usb_input"}]
	var out_w: int = c.accept_width if c.accept_format == "bits" else want.width
	d.outputs = [{"cell": drive_cell(d.board_size), "rot": 0, "width": out_w, "expected": [raw_bin(want)], "ordered": true, "view": view_mode(idx)}]
	return d


static func raw_bin(bv: BitVector) -> String:
	var s := ""
	for k in range(bv.width - 1, -1, -1):
		s += "1" if bv.bit(k) != 0 else "0"
	return s
