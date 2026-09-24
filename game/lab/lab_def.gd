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
## ONE socket (column 0, row 5) + ONE Contract Drive (the last two columns, row 5) for all levels.

const SOCKET_CELL := Vector2i(0, 5)
const INITIAL_SIZE := Vector2i(20, 12)
const OUTPUT_TYPE := "usb_output"

## The 8 three-bit words the contract streams cycle through.
const WORDS_3 := ["010", "101", "111", "000", "011", "110", "001", "100"]

static var LEVELS: Array = [
	{
		"id": "lab_l1", "title": "First Contact",
		"brief": "A stick of raw data was plugged in. Hand the words back unchanged.",
		"contract": {"kind": "deliver", "value": "010", "count": 10},
		"streams": {"bit": {"values": ["010"], "width": 3, "interval": 4}},
		"devices": ["bit"], "unlocks": [], "grow": Vector2i(20, 12),
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
		"devices": ["number"], "unlocks": ["number_encoder", "number_decoder"], "grow": Vector2i(24, 14),
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l6", "title": "Letters",
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
		"devices": ["sensor"], "unlocks": ["compare", "gate", "splitter"], "grow": Vector2i(32, 18),
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
		"unlocks": ["multiply", "merger"], "grow": Vector2i(36, 20),
		"view": ViewMode.Mode.BIN,
	},
]


static func count() -> int:
	return LEVELS.size()


static func level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


## The Contract of level `i` (fresh each call; cheap and pure).
static func contract_for(i: int) -> Contract:
	return Contract.from_level(level(i))


## The drive cell once the board is `size`: the east edge, row 5.
static func drive_cell(size: Vector2i) -> Vector2i:
	return Vector2i(size.x - 2, 5)


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
