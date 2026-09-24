class_name LabDef
extends RefCounted
## Static data for Lab mode (docs/IMPLEMENTATION.md "Lab mode"): one persistent factory that
## grows as each "deliver N x value V" request is met. Pure data — LabRun does the ticking.
##
## A level is {id, title, brief, request, count, view, unlocks, grow, sources}:
##   request  {value: "100"}  — a BIN string whose digit count IS the width
##            {chr: "K", width: 5} — a character in an explicit width
##   count    how many exact matches the USB Output must receive
##   view     ViewMode.Mode used to display the request
##   unlocks  machine types unlocked when this level starts
##   grow     board size once this level starts (never smaller than the previous)
##   sources  [{cell, width, values (BIN strings or single chars), interval}]

const INITIAL_SIZE := Vector2i(20, 12)
const OUTPUT_CELL := Vector2i(17, 5)
const OUTPUT_TYPE := "usb_output"

static var LEVELS: Array = [
	{
		"id": "lab_l1", "title": "First Contact",
		"brief": "A stick of raw data was plugged in. Hand the words back unchanged.",
		"request": {"value": "010"}, "count": 10, "view": ViewMode.Mode.BIN,
		"unlocks": [], "grow": Vector2i(20, 12),
		"sources": [{"cell": Vector2i(1, 5), "width": 3, "values": ["010"], "interval": 4}],
	},
	{
		"id": "lab_l2", "title": "Plus Two",
		"brief": "Someone needs 100s. Your source only gives 010.",
		"request": {"value": "100"}, "count": 20, "view": ViewMode.Mode.BIN,
		"unlocks": ["add"], "grow": Vector2i(20, 12),
		"sources": [],
	},
	{
		"id": "lab_l3", "title": "Over the Top",
		"brief": "Three bits wrap around. Make 001 from 010.",
		"request": {"value": "001"}, "count": 20, "view": ViewMode.Mode.BIN,
		"unlocks": [], "grow": Vector2i(20, 12),
		"sources": [],
	},
	{
		"id": "lab_l4", "title": "Letters",
		"brief": "A second stick carries letters. Shift H to K.",
		"request": {"chr": "K", "width": 5}, "count": 30, "view": ViewMode.Mode.CHAR,
		"unlocks": [], "grow": Vector2i(28, 16),
		"sources": [{"cell": Vector2i(1, 13), "width": 5, "values": ["H"], "interval": 4}],
	},
	{
		"id": "lab_l5", "title": "Past Z",
		"brief": "X + 3 falls off the alphabet. Wrap it back to A.",
		"request": {"chr": "A", "width": 5}, "count": 30, "view": ViewMode.Mode.CHAR,
		"unlocks": ["modulo"], "grow": Vector2i(28, 16),
		"sources": [{"cell": Vector2i(1, 9), "width": 5, "values": ["X"], "interval": 4}],
	},
	{
		"id": "lab_l6", "title": "Payload",
		"brief": "Tagged words: keep only the 3-bit payload.",
		"request": {"value": "101"}, "count": 30, "view": ViewMode.Mode.BIN,
		"unlocks": ["bit_splitter"], "grow": Vector2i(36, 20),
		"sources": [{"cell": Vector2i(1, 17), "width": 5, "values": ["10101"], "interval": 4}],
	},
]


static func count() -> int:
	return LEVELS.size()


static func level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


static func request_bits(i: int) -> BitVector:
	var r: Dictionary = level(i)["request"]
	if r.has("value"):
		return BitVector.from_bin(str(r["value"]))
	return Charset.encode(str(r["chr"]), int(r["width"]))


static func request_count(i: int) -> int:
	return int(level(i)["count"])


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


## Board size once level `i` starts: the largest grow of levels 0..i.
static func size_for(i: int) -> Vector2i:
	var s := INITIAL_SIZE
	for k in range(0, clampi(i, 0, LEVELS.size() - 1) + 1):
		var g: Variant = LEVELS[k].get("grow", null)
		if g is Vector2i:
			s = Vector2i(maxi(s.x, g.x), maxi(s.y, g.y))
	return s


## Every source of levels 0..i, in level order (what a restored board must contain).
static func sources_upto(i: int) -> Array:
	var out := []
	for k in range(0, clampi(i, 0, LEVELS.size() - 1) + 1):
		for src in LEVELS[k].get("sources", []):
			out.append(src)
	return out


static func source_bits(src: Dictionary) -> Array:
	var w := int(src["width"])
	var out := []
	for v in src.get("values", []):
		out.append(value_to_bits(v, w))
	return out


## A source value is either a BIN string (its digit count is its width) or a single char.
static func value_to_bits(v: Variant, width: int) -> BitVector:
	if v is BitVector:
		return v
	var s := str(v)
	if _is_bin(s, width):
		return BitVector.from_bin(s)
	return Charset.encode(s, width)


static func _is_bin(s: String, width: int) -> bool:
	if s.length() != width:
		return false
	for c in s:
		if c != "0" and c != "1":
			return false
	return true


static func raw_bin(bv: BitVector) -> String:
	var s := ""
	for k in range(bv.width - 1, -1, -1):
		s += "1" if bv.bit(k) != 0 else "0"
	return s


## A MissionDef-shaped view of a level so the existing HUD/views can read it unchanged.
## The lab's real run is a LabRun; this is presentation data only.
static func mission_def(i: int) -> MissionDef:
	var idx := clampi(i, 0, LEVELS.size() - 1)
	var lv := level(idx)
	var want := request_bits(idx)
	var d := MissionDef.new()
	d.id = "lab"
	d.index = idx
	d.title = str(lv["title"])
	d.brief = str(lv["brief"])
	d.formula = "deliver %d × %s" % [request_count(idx), ViewMode.format(want, view_mode(idx))]
	d.board_size = size_for(idx)
	d.default_width = want.width
	d.view_modes = [view_mode(idx)]
	d.allowed = unlocks_upto(idx)
	d.unlocks = PackedStringArray(lv.get("unlocks", []))
	var inputs := []
	for src in sources_upto(idx):
		var vals := []
		for bv in source_bits(src):
			vals.append(raw_bin(bv))
		inputs.append({"cell": src["cell"], "rot": 0, "width": int(src["width"]), "values": vals, "interval": int(src.get("interval", 4)), "strict": false, "start": 1, "source": "usb_input"})
	d.inputs = inputs
	d.outputs = [{"cell": OUTPUT_CELL, "rot": 0, "width": want.width, "expected": [raw_bin(want)], "ordered": true, "view": view_mode(idx)}]
	return d
