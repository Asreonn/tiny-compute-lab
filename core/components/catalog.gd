class_name Catalog
extends RefCounted
## Static machine definitions. Mirrors the Penpot "05 Machines" page: every machine is
## MachineShell(size) + family accent + operation icon + ports. Behaviour lives in Machine.
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

const FAMILIES := ["io", "math", "logic", "routing", "conversion", "storage", "compute"]
const CATEGORIES := [
	{"id": "io", "label": "IO"},
	{"id": "math", "label": "Math"},
	{"id": "logic", "label": "Logic"},
	{"id": "routing", "label": "Routing"},
	{"id": "storage", "label": "Storage"},
]


static func _p(id: String, dir: String, role: String, width: Variant, cell: Vector2i, side: int, label := "", bus := false) -> Dictionary:
	return {
		"id": id, "dir": dir, "role": role, "width": width, "bus": bus,
		"cell": cell, "side": side, "label": label if label != "" else id.to_upper(),
	}


## params: key -> {label, kind ("int"|"enum"), default, min, max, options}
static var DEFS := {
	"input": {
		"name": "Input", "family": "io", "size": "M", "ticks": 1, "campaign_ticks": 1, "power": 0, "icon": "io_input",
		"desc": "Feeds the mission's data stream into your machine.",
		"ports": [_p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "OUT")],
		"params": {},
	},
	"usb_input": {
		"name": "USB Input", "family": "io", "size": "M", "ticks": 1, "campaign_ticks": 1, "power": 0, "icon": "io_input",
		"desc": "Streams raw bits from the lab's USB line.",
		"ports": [_p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "OUT", true)],
		"params": {},
	},
	"output": {
		"name": "Output", "family": "io", "size": "M", "ticks": 1, "campaign_ticks": 1, "power": 0, "icon": "io_output",
		"desc": "Collects results and checks them against the expected stream.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN")],
		"params": {},
	},
	"usb_output": {
		"name": "USB Output", "family": "io", "size": "M", "ticks": 1, "campaign_ticks": 1, "power": 0, "icon": "io_output",
		"desc": "Hands processed data back out through the lab's USB line.",
		# width "*" = accepts any width (the ONE exception to the width-match rule,
		# docs/ARCHITECTURE.md §4.3): the Lab USB Output validates bits + width itself.
		"ports": [_p("in", DIR_IN, ROLE_DATA, "*", Vector2i(0, 0), Side.W, "USB", true)],
		"params": {},
	},
	"add": {
		"name": "Add", "family": "math", "size": "M", "ticks": 1, "campaign_ticks": 4, "power": 1, "icon": "op_add",
		"desc": "Adds a constant value to each packet.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "X"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "Y")],
		"params": {"k": {"label": "Constant", "kind": "int", "default": 1, "min": 0, "max": 255}},
	},
	"modulo": {
		"name": "Modulo", "family": "math", "size": "M", "ticks": 1, "campaign_ticks": 4, "power": 1, "icon": "", "glyph_text": "%",
		"desc": "Keeps the remainder after dividing by a constant.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "X"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "Y")],
		"params": {"k": {"label": "Modulus", "kind": "int", "default": 26, "min": 1, "max": 255}},
	},
	"terminal_output": {
		"name": "Terminal", "family": "io", "size": "M", "ticks": 1, "campaign_ticks": 1, "power": 0, "icon": "io_output",
		"desc": "Collects results as characters and checks them against the expected stream.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN")],
		"params": {},
	},
	"multiply": {
		"name": "Multiply", "family": "math", "size": "M", "ticks": 2, "campaign_ticks": 6, "power": 2, "icon": "op_multiply",
		"desc": "Multiplies each packet by a constant.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "X"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "Y")],
		"params": {"k": {"label": "Factor", "kind": "int", "default": 2, "min": -9, "max": 9}},
	},
	"compare": {
		"name": "Compare", "family": "logic", "size": "S", "ticks": 1, "campaign_ticks": 3, "power": 1, "icon": "op_compare",
		"desc": "Tests each value and emits a 1-bit result.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "X"), _p("out", DIR_OUT, ROLE_FLAG, 1, Vector2i(0, 0), Side.E, "?")],
		"params": {
			"op": {"label": "Operation", "kind": "enum", "default": ">", "options": [">", "<", "=", "≥", "≤", "≠"]},
			"k": {"label": "Threshold", "kind": "int", "default": 10, "min": -99, "max": 99},
		},
	},
	"gate": {
		"name": "Gate", "family": "logic", "size": "S", "ticks": 1, "campaign_ticks": 3, "power": 1, "icon": "op_gate",
		"desc": "Passes the data packet only when the control signal is TRUE; otherwise discards it.",
		"ports": [
			_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "D"),
			_p("ctrl", DIR_CTRL, ROLE_CONTROL, 1, Vector2i(0, 0), Side.N, "EN"),
			_p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(0, 0), Side.E, "Q"),
		],
		"params": {},
	},
	"splitter": {
		"name": "Splitter", "family": "routing", "size": "L", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_split",
		"desc": "One stream in, two out. Alternate balances load; Duplicate copies every packet.",
		"ports": [
			_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN"),
			_p("a", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "A"),
			_p("b", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 1), Side.E, "B"),
		],
		"params": {"mode": {"label": "Mode", "kind": "enum", "default": "Alternate", "options": ["Alternate", "Duplicate"]}},
	},
	"merger": {
		"name": "Merger", "family": "routing", "size": "L", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_merge",
		"desc": "Two streams in, one out. Takes turns fairly between inputs.",
		"ports": [
			_p("a", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "A"),
			_p("b", DIR_IN, ROLE_DATA, "W", Vector2i(0, 1), Side.W, "B"),
			_p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "OUT"),
		],
		"params": {},
	},
	"bit_splitter": {
		"name": "Bit Splitter", "family": "conversion", "size": "L", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_split",
		"desc": "Splits a word into its high bits and its low bits.",
		"ports": [
			_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN", true),
			_p("hi", DIR_OUT, ROLE_DATA, "R:lo", Vector2i(1, 0), Side.E, "HI", true),
			_p("lo", DIR_OUT, ROLE_DATA, "P:lo", Vector2i(1, 1), Side.E, "LO", true),
		],
		"params": {"lo": {"label": "Low bits", "kind": "int", "default": 3, "min": 1, "max": 63}},
	},
	"number_encoder": {
		"name": "Number Encoder", "family": "conversion", "size": "M", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_counter",
		"desc": "Turns a raw number into bits of the chosen width. A value that does not fit sets the overflow LED.",
		"ports": [
			_p("in", DIR_IN, ROLE_RAW, 0, Vector2i(0, 0), Side.W, "RAW"),
			_p("out", DIR_OUT, ROLE_DATA, "P:width", Vector2i(1, 0), Side.E, "OUT", true),
		],
		"params": {"width": {"label": "Width", "kind": "int", "default": 3, "min": 1, "max": 16}},
	},
	"char_encoder": {
		"name": "Character Encoder", "family": "conversion", "size": "M", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_counter",
		"desc": "Turns a raw character into its charset code. 5 bits use TCL-5; an unencodable char is dropped.",
		"ports": [
			_p("in", DIR_IN, ROLE_RAW, 0, Vector2i(0, 0), Side.W, "RAW"),
			_p("out", DIR_OUT, ROLE_DATA, "P:width", Vector2i(1, 0), Side.E, "OUT", true),
		],
		"params": {"width": {"label": "Width", "kind": "int", "default": 5, "min": 5, "max": 8}},
	},
	"number_decoder": {
		"name": "Number Decoder", "family": "conversion", "size": "M", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_counter",
		"desc": "Turns bits into a raw number, unsigned or signed.",
		"ports": [
			_p("in", DIR_IN, ROLE_DATA, "P:width", Vector2i(0, 0), Side.W, "IN", true),
			_p("out", DIR_OUT, ROLE_RAW, 0, Vector2i(1, 0), Side.E, "RAW"),
		],
		"params": {
			"width": {"label": "Width", "kind": "int", "default": 3, "min": 1, "max": 16},
			"signed": {"label": "Signed", "kind": "enum", "default": "Unsigned", "options": ["Unsigned", "Signed"]},
		},
	},
	"char_decoder": {
		"name": "Character Decoder", "family": "conversion", "size": "M", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_counter",
		"desc": "Turns bits into a raw character using the charset of the width.",
		"ports": [
			_p("in", DIR_IN, ROLE_DATA, "P:width", Vector2i(0, 0), Side.W, "IN", true),
			_p("out", DIR_OUT, ROLE_RAW, 0, Vector2i(1, 0), Side.E, "RAW"),
		],
		"params": {"width": {"label": "Width", "kind": "int", "default": 5, "min": 5, "max": 8}},
	},
	"demux": {
		"name": "Demux", "family": "routing", "size": "L", "ticks": 1, "campaign_ticks": 3, "power": 1, "icon": "op_split",
		"desc": "Sends each value to A when the select bit is 0, to B when it is 1.",
		"ports": [
			_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN"),
			_p("sel", DIR_CTRL, ROLE_CONTROL, 1, Vector2i(0, 0), Side.N, "SEL"),
			_p("a", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "A"),
			_p("b", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 1), Side.E, "B"),
		],
		"params": {},
	},
	"buffer": {
		"name": "Buffer", "family": "storage", "size": "M", "ticks": 1, "campaign_ticks": 2, "power": 1, "icon": "op_buffer",
		"desc": "Queues packets so bursts don't back up the line.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "OUT")],
		"params": {"capacity": {"label": "Capacity", "kind": "int", "default": 4, "min": 1, "max": 8}},
	},
	"delay": {
		"name": "Delay", "family": "storage", "size": "S", "ticks": 1, "campaign_ticks": 1, "power": 1, "icon": "op_delay",
		"desc": "Holds each packet for a fixed number of ticks.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(0, 0), Side.E, "OUT")],
		"params": {"ticks": {"label": "Delay", "kind": "int", "default": 3, "min": 1, "max": 9}},
	},
	"counter": {
		"name": "Counter", "family": "storage", "size": "S", "ticks": 1, "campaign_ticks": 3, "power": 1, "icon": "op_counter",
		"desc": "Counts packets. Emits the running count for each one received.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "IN"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(0, 0), Side.E, "N")],
		"params": {},
	},
	"processor": {
		"name": "Processor", "family": "compute", "size": "L", "ticks": 4, "campaign_ticks": 12, "power": 4, "icon": "op_processor",
		"desc": "Heavy general-purpose unit. Powerful but slow — a classic bottleneck.",
		"ports": [_p("in", DIR_IN, ROLE_DATA, "W", Vector2i(0, 0), Side.W, "X"), _p("out", DIR_OUT, ROLE_DATA, "W", Vector2i(1, 0), Side.E, "Y")],
		"params": {"op": {"label": "Function", "kind": "enum", "default": "x²", "options": ["x²", "x³", "|x|", "−x"]}},
	},
}

## Build-menu order within each category.
const ORDER := ["input", "usb_input", "output", "terminal_output", "add", "modulo", "multiply", "compare", "gate", "splitter", "merger", "bit_splitter", "number_encoder", "char_encoder", "number_decoder", "char_decoder", "demux", "buffer", "delay", "counter", "processor"]


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
	return "storage" if f == "compute" else f


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
