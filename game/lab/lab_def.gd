class_name LabDef
extends RefCounted
## Static data for Lab mode (docs/IMPLEMENTATION.md "Lab mode", docs/SYSTEMS_EXPANSION.md §10):
## one persistent factory that grows as each contract is met. Pure data — LabRun does the ticking.
##
## A level is {id, title, brief, contract, streams, devices, unlocks, grow, view}:
##   contract  the Contract dictionary (kind, ops, count, constraints) — see game/lab/contract.gd
##   streams   {kind: {values, width?, interval?, pattern?}} — the contract's stream per device kind
##   devices   data modules owned from this level on
##   unlocks   machine types unlocked when this level starts
##   grow      board size once this level starts (never smaller than the previous)
##   view      ViewMode.Mode used to display the contract
## The laptop port racks (docs/SYSTEMS_EXPANSION.md §2.1): 4 input ports on the west edge
## (column 0) and 4 output ports on the east edge (last two columns). Ports sit at rows 1, 4,
## 7 and 10; they open top-first and the sealed ones are reserved bays until their level.

const SOCKET_CELL := Vector2i(0, 1)
const INITIAL_SIZE := Vector2i(28, 16)
const OUTPUT_TYPE := "usb_output"
## Every port row, top to bottom. All are sealed except the open ones for the level.
const PORT_ROWS := [1, 4, 7, 10]

## The 8 three-bit words the contract streams cycle through.
const WORDS_3 := ["010", "101", "111", "000", "011", "110", "001", "100"]

static var LEVELS: Array = [
	{
		"id": "lab_l1", "title": "First Contact",
		"brief": "A stick of raw data was plugged in. Hand the words back unchanged.",
		"contract": {"kind": "deliver", "value": "010", "count": 10},
		"streams": {"bit": {"values": ["010"], "width": 3, "interval": 4}},
		"devices": ["bit"], "unlocks": [], "grow": Vector2i(28, 16),
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l2", "title": "Plus Two",
		"brief": "Someone needs 100s. Your source only gives 010.",
		"contract": {"kind": "deliver", "value": "100", "count": 20},
		"unlocks": ["add"], "view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l3", "title": "Over the Top",
		"brief": "Three bits wrap around. Make 001 from 010.",
		"contract": {"kind": "deliver", "value": "001", "count": 20},
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l4", "title": "Moving Target",
		"brief": "The stick changes its word every time. Transform whatever arrives.",
		"contract": {"kind": "map", "ops": [{"op": "add", "k": 3}], "count": 20, "accept_format": "bits", "accept_width": 3},
		"streams": {"bit": {"values": WORDS_3, "width": 3}},
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l5", "title": "Numbers",
		"brief": "The stick now speaks numbers. Encode one, add one, hand the bits back.",
		"contract": {"kind": "map", "ops": [{"op": "encode_num", "width": 3}, {"op": "add", "k": 1}], "count": 20, "accept_format": "bits", "accept_width": 3},
		"streams": {"number": {"values": [3, 6, 1, 4, 7, 2, 5, 0]}},
		"devices": ["number"], "unlocks": ["number_encoder", "number_decoder"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l6", "title": "Letters", "grow": Vector2i(32, 18),
		"brief": "A text stick carries letters. Shift each one by three.",
		"contract": {"kind": "map", "ops": [{"op": "encode_char", "width": 5}, {"op": "add", "k": 3}, {"op": "decode_char"}], "count": 24, "accept_format": "text"},
		"streams": {"text": {"values": ["HELLOCOMPUTE"]}},
		"devices": ["text"], "unlocks": ["char_encoder", "char_decoder"],
		"view": ViewMode.Mode.CHAR,
	},
	{
		"id": "lab_l7", "title": "Past Z",
		"brief": "X + 3 falls off the alphabet. Wrap it back to A.",
		"contract": {"kind": "map", "ops": [{"op": "encode_char", "width": 5}, {"op": "add", "k": 3}, {"op": "mod", "k": 26}, {"op": "decode_char"}], "count": 24, "accept_format": "text"},
		"streams": {"text": {"values": ["XYZZYBITWAVE"]}},
		"unlocks": ["modulo"],
		"view": ViewMode.Mode.CHAR,
	},
	{
		"id": "lab_l8", "title": "Payload",
		"brief": "Tagged words: keep only the 3-bit payload.",
		"contract": {"kind": "map", "ops": [{"op": "slice", "lo": 0, "len": 3}], "count": 24, "accept_format": "bits", "accept_width": 3},
		"streams": {"bit": {"values": ["10101", "01110", "11011", "00100"], "width": 5}},
		"unlocks": ["bit_splitter"],
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l9", "title": "Sorting",
		"brief": "A noisy sensor. Keep only the readings above four.",
		"contract": {"kind": "filter", "ops": [{"op": "encode_num", "width": 3}, {"op": "keep_if", "cmp": ">", "k": 4}], "count": 16, "accept_format": "bits", "accept_width": 3},
		"streams": {"sensor": {"values": [2, 6, 5, 1, 7, 3, 4, 0, 6, 2]}},
		"devices": ["sensor"], "unlocks": ["compare", "gate", "splitter"], "grow": Vector2i(36, 20),
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l10", "title": "Burst",
		"brief": "The stick fires bursts. Nothing may be dropped — buffer it.",
		"contract": {"kind": "map", "ops": [{"op": "add", "k": 1}], "count": 24, "accept_format": "bits", "accept_width": 3, "max_lost": 0},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "pattern": [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 60]}},  # bursts of 12, then a 60-tick gap: the average fits one Add, the burst does not
		"unlocks": ["buffer", "delay"],
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l11", "title": "Rush Hour",
		"brief": "Values arrive fast. Multiply in parallel to keep up.",
		"contract": {"kind": "map", "ops": [{"op": "mul", "k": 3}], "count": 30, "accept_format": "bits", "accept_width": 3, "min_rate": 4.0},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "interval": 2}},
		"unlocks": ["multiply", "merger"], "grow": Vector2i(40, 22),
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l12", "title": "Two Sticks",
		"brief": "A second stick holds the key. Shift every letter by it — in step.",
		"contract": {"kind": "paired", "pair": ["text", "key"], "ops": [{"op": "encode_char", "width": 5}, {"op": "add_src", "src": "key"}, {"op": "mod", "k": 26}, {"op": "decode_char"}], "count": 24, "accept_format": "text"},
		"streams": {"text": {"values": ["TWOSTICKSMEET"]}, "key": {"values": [5]}},
		"devices": ["key"], "unlocks": ["adder"],
		"view": ViewMode.Mode.CHAR,
	},
]


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


## The input rows open at level index `idx`: row 1 from L1, row 4 from L12, row 7 from L18.
static func open_input_rows(level_idx: int) -> Array[int]:
	var out: Array[int] = [PORT_ROWS[0]]
	if level_idx >= 11:
		out.append(PORT_ROWS[1])
	if level_idx >= 17:
		out.append(PORT_ROWS[2])
	return out


## The output rows open at level index `idx`: row 1 from L1, row 4 from L9, row 7 from L12.
static func open_output_rows(level_idx: int) -> Array[int]:
	var out: Array[int] = [PORT_ROWS[0]]
	if level_idx >= 8:
		out.append(PORT_ROWS[1])
	if level_idx >= 11:
		out.append(PORT_ROWS[2])
	return out


## The rows of `side` still sealed at level index `idx` (row 10 is always sealed).
static func sealed_rows(level_idx: int, input_side: bool) -> Array[int]:
	var open := open_input_rows(level_idx) if input_side else open_output_rows(level_idx)
	var out: Array[int] = []
	for r in PORT_ROWS:
		if not open.has(r):
			out.append(r)
	return out


## Every port of `side` open at level index `idx`, as [{side, row}] in board creation order:
## [input row 1, output row 1] first (save migration depends on it), then as they open.
static func ports_upto(level_idx: int) -> Array:
	var out: Array = [
		{"side": "in", "row": PORT_ROWS[0]},
		{"side": "out", "row": PORT_ROWS[0]},
	]
	if level_idx >= 8:
		out.append({"side": "out", "row": PORT_ROWS[1]})
	if level_idx >= 11:
		out.append({"side": "out", "row": PORT_ROWS[2]})
		out.append({"side": "in", "row": PORT_ROWS[1]})
	if level_idx >= 17:
		out.append({"side": "in", "row": PORT_ROWS[2]})
	return out


## The view label of a port slot: "USB 2 · opens at L12" or "USB 4 · sealed".
static func slot_label(side: String, row: int) -> String:
	var n := PORT_ROWS.find(row) + 1
	var open_at := -1
	if side == "in":
		if row == PORT_ROWS[1]:
			open_at = 11
		elif row == PORT_ROWS[2]:
			open_at = 17
	else:
		if row == PORT_ROWS[1]:
			open_at = 8
		elif row == PORT_ROWS[2]:
			open_at = 11
	if open_at >= 0:
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
