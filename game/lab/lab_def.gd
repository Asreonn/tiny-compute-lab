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
	{
		"id": "lab_l13", "title": "Changing Key",
		"brief": "The key changes every 8 letters and the text arrives in bursts. Keep every pair in step.",
		"contract": {"kind": "paired", "pair": ["text", "key"], "ops": [{"op": "encode_char", "width": 5}, {"op": "add_src", "src": "key"}, {"op": "mod", "k": 26}, {"op": "decode_char"}], "count": 24, "accept_format": "text", "max_lost": 0},
		# 36 letters every 2 ticks (the encoder keeps up), then a long gap: the average matches the
		# steady key (1 per 8 ticks), the burst does not — about 27 letters pile up behind the
		# Adder, more than wires alone hold, and a lost letter would pair every later letter with
		# the wrong key
		"streams": {"text": {"values": ["KEEPTHEPAIRSINSTEP"], "pattern": [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 218]},
			"key": {"values": [1, 1, 1, 1, 1, 1, 1, 1, 4, 4, 4, 4, 4, 4, 4, 4, 9, 9, 9, 9, 9, 9, 9, 9, 2, 2, 2, 2, 2, 2, 2, 2], "interval": 8}},
		"unlocks": ["counter"],
		"view": ViewMode.Mode.CHAR,
	},
	{
		"id": "lab_l14", "title": "Mixed Traffic",
		"brief": "Tagged words: when the top bit is set add 1 to the payload, otherwise double it. One output.",
		"contract": {"kind": "map", "ops": [{"op": "if_bit", "bit": 4, "then": [{"op": "slice", "lo": 0, "len": 3}, {"op": "add", "k": 1}], "else": [{"op": "slice", "lo": 0, "len": 3}, {"op": "mul", "k": 2}]}], "count": 24, "accept_format": "bits", "accept_width": 3},
		"streams": {"bit": {"values": ["10011", "00101", "11110", "01010", "10001", "00111", "11100", "01011"], "width": 5, "interval": 2}},
		"unlocks": ["demux", "mux", "cond_router"],
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l15", "title": "Wider",
		"brief": "3-bit numbers in, 5-bit answers out: widen each one, then multiply it by 5.",
		"contract": {"kind": "map", "ops": [{"op": "zext", "width": 5}, {"op": "mul", "k": 5}], "count": 24, "accept_format": "bits", "accept_width": 5},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "interval": 2}},
		"unlocks": ["zero_extend", "sign_extend", "truncate"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l16", "title": "Power Cap",
		"brief": "The laptop runs on its starter adapter: 8 power. Double every value at 4/s without drawing more.",
		# Multiply costs 2 power for 1.7/s; an Adder fed x and x by a Duplicate splitter doubles
		# at 2.5/s for 2 power — two of them fit the cap, Multiplies do not
		"contract": {"kind": "map", "ops": [{"op": "mul", "k": 2}], "count": 30, "accept_format": "bits", "accept_width": 3, "min_rate": 4.0, "max_power": 8},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "interval": 1}},
		"unlocks": [], "reward": {"psu_tier": 1},
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l17", "title": "Heat",
		"brief": "8 values a second: overclock to keep up — and cool the hot parts before they throttle.",
		# at the normal clock a splitter / merger passes 5/s at most: 8/s needs overclocked routing
		# and Adds (x4 heat), which throttle unless something cools them
		"contract": {"kind": "map", "ops": [{"op": "add", "k": 1}], "count": 40, "accept_format": "bits", "accept_width": 3, "min_rate": 8.0, "max_heat": "THROTTLING"},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "interval": 1}},
		"unlocks": ["heatsink", "blower"],
		"view": ViewMode.Mode.BIN,
	},
	{
		"id": "lab_l18", "title": "BYTE",
		"brief": "Eight bits: real ASCII. The key stick now holds a mask — AND each lower-case letter with it to make it upper case.",
		"contract": {"kind": "paired", "pair": ["text", "key"], "ops": [{"op": "encode_char", "width": 8}, {"op": "and_src", "src": "key"}, {"op": "decode_char"}], "count": 24, "accept_format": "text"},
		"streams": {"text": {"values": ["hellobyteworld"]}, "key": {"values": [223]}},
		"unlocks": ["and_gate", "or_gate", "xor_gate", "not_gate", "bus_combiner"], "reward": {"psu_tier": 2},
		"view": ViewMode.Mode.CHAR,
	},
	{
		"id": "lab_l19", "title": "XOR Cipher",
		"brief": "Encrypt: XOR each ASCII letter with its own key byte and deliver the raw cipher bytes.",
		"contract": {"kind": "paired", "pair": ["text", "key"], "ops": [{"op": "encode_char", "width": 8}, {"op": "xor_src", "src": "key"}], "count": 24, "accept_format": "bits", "accept_width": 8},
		"streams": {"text": {"values": ["attackatdawn"]}, "key": {"values": [23, 5, 77, 61, 9, 88, 42, 14]}},
		"unlocks": ["shift_left", "shift_right"],
		"view": ViewMode.Mode.HEX,
	},
	{
		"id": "lab_l20", "title": "Cheap Multiply",
		"brief": "Times four at 4/s on just 6 power. Multipliers are too hungry — find a cheaper way.",
		# Multiply: 2 power for 1.7/s (two fit the cap but make 3.3/s); x4 = shift left by 2: 1 power, 5/s
		"contract": {"kind": "map", "ops": [{"op": "mul", "k": 4}], "count": 30, "accept_format": "bits", "accept_width": 5, "min_rate": 4.0, "max_power": 6},
		"streams": {"bit": {"values": ["00011", "10110", "01001", "11100", "00110", "01111", "10001", "00100"], "width": 5, "interval": 1}},
		"unlocks": [],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l21", "title": "Datacenter",
		"brief": "Times three at 8/s, and nothing may even get HOT. Overclocked Multipliers need serious cooling.",
		# an overclocked Multiply alone goes CRITICAL; a Blower leaves it HOT; a Radiator (or two
		# Blowers) keeps it WARM — and four of them on the 32-unit PSU only fit with Radiators
		"contract": {"kind": "map", "ops": [{"op": "mul", "k": 3}], "count": 40, "accept_format": "bits", "accept_width": 5, "min_rate": 8.0, "max_heat": "HOT"},
		"streams": {"bit": {"values": ["00011", "10110", "01001", "11100", "00110", "01111", "10001", "00100"], "width": 5, "interval": 1}},
		"unlocks": ["heat_pipe", "radiator"], "reward": {"psu_tier": 3},
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l22", "title": "Running Sum",
		"brief": "Deliver the total so far: each answer adds the new value to everything before it. The factory needs a memory.",
		# one value every 36 ticks: a tidy feedback loop (Adder → Register → Adder) keeps up, and a
		# lost value would spoil every total after it
		"contract": {"kind": "map", "ops": [{"op": "prefix_sum", "width": 5}], "count": 16, "accept_format": "bits", "accept_width": 5},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "interval": 36}},
		"unlocks": ["register"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l23", "title": "Lookup",
		"brief": "A secret substitution: 0→6 1→4 2→7 3→1 4→0 5→3 6→5 7→2. No arithmetic does it — a table does.",
		"contract": {"kind": "map", "ops": [{"op": "table", "values": [6, 4, 7, 1, 0, 3, 5, 2], "width": 3}], "count": 24, "accept_format": "bits", "accept_width": 3},
		"streams": {"bit": {"values": WORDS_3, "width": 3, "interval": 2}},
		"unlocks": ["rom"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l24", "title": "Calculator",
		"brief": "Three sticks: a number, a second number on the key stick, and an operation bit. Add when it is 0, subtract when it is 1.",
		"contract": {"kind": "paired", "pair": ["number", "key", "bits"], "ops": [{"op": "encode_num", "width": 5}, {"op": "alu_src", "b": "key", "sel": "bits", "ops": ["ADD", "SUB"]}], "count": 24, "accept_format": "bits", "accept_width": 5},
		# the ALU takes 4 ticks a step: the three sticks come every 6 so no stick overruns and the
		# three streams stay in step
		"streams": {"number": {"values": [9, 3, 14, 7, 20, 5, 11], "interval": 6}, "key": {"values": [4, 8, 2, 6, 1, 3], "interval": 6},
			"bit": {"values": ["0", "1", "1", "0", "1"], "width": 1, "interval": 6}},
		"unlocks": ["alu"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l25", "title": "Tiny Memory",
		"brief": "Instructions: top bit 1 = WRITE the low 3 bits to the address in bits 6-3, 0 = READ that address. Run them on RAM; deliver only what the reads return.",
		"contract": {"kind": "filter", "ops": [{"op": "ram_program", "we_bit": 7, "addr_lo": 3, "addr_len": 4, "val_lo": 0, "val_len": 3}], "count": 16, "accept_format": "bits", "accept_width": 3},
		"streams": {"bit": {"values": ["10010101", "10111011", "00010000", "10010110", "00111000", "00010000", "01001000", "11001111", "01001000"], "width": 8, "interval": 3}},
		"unlocks": ["ram", "register_bank", "instruction_decoder"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l26", "title": "Playback",
		"brief": "Play the melody 3 5 8 5 10 8 12 1 — one note per clock pulse, in order, again and again.",
		"contract": {"kind": "map", "ops": [{"op": "seq_table", "values": [3, 5, 8, 5, 10, 8, 12, 1], "width": 4}], "count": 24, "accept_format": "bits", "accept_width": 4},
		"streams": {"bit": {"values": ["1"], "width": 1, "interval": 3}},
		"unlocks": ["program_counter"],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l27", "title": "Fetch & Execute",
		"brief": "A tiny CPU. Program: ADD 5, ADD 12, SUB 3, ADD 20, SUB 7, ADD 1, SUB 30, ADD 9 (ADD k = k, SUB k = 128 + k). Each clock pulse fetches the next instruction and runs it on a 6-bit accumulator; deliver the accumulator after every step.",
		# fetch: clock → Program Counter → ROM; decode: Instruction Decoder (bit 7 = SUB) + the low
		# 6 bits; execute: ALU on the accumulator, kept by an echo Register
		"contract": {"kind": "map", "ops": [{"op": "cpu_trace", "program": [5, 12, 131, 20, 135, 1, 158, 9], "sub_bit": 7, "imm_bits": 6, "width": 6}], "count": 16, "accept_format": "bits", "accept_width": 6},
		"streams": {"bit": {"values": ["1"], "width": 1, "interval": 36}},
		"unlocks": [],
		"view": ViewMode.Mode.UDEC,
	},
	{
		"id": "lab_l28", "title": "Output Port",
		"brief": "Bit 6 is now OUT: only OUT instructions show the accumulator. Program: ADD 10, ADD 3 OUT, SUB 6, ADD 0 OUT, SUB 2 OUT, ADD 20, ADD 1 OUT, SUB 11 (OUT adds 64).",
		"contract": {"kind": "filter", "ops": [{"op": "cpu_trace", "program": [10, 67, 134, 64, 194, 20, 65, 139], "sub_bit": 7, "out_bit": 6, "imm_bits": 6, "width": 6}], "count": 12, "accept_format": "bits", "accept_width": 6, "max_rejected": 0},
		"streams": {"bit": {"values": ["1"], "width": 1, "interval": 36}},
		"unlocks": [],
		"view": ViewMode.Mode.UDEC,
	},
]


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


## The input rows open at level index `idx`: row 1 from L1, row 4 from L12, row 7 from L18.
## The input rows open at level index `idx`: rows 1 and 4 from the start (two sticks at once),
## row 7 from L18 (BYTE).
static func open_input_rows(level_idx: int) -> Array[int]:
	var out: Array[int] = [PORT_ROWS[0], PORT_ROWS[1]]
	if level_idx >= 17:
		out.append(PORT_ROWS[2])
	return out


## The output rows open at level index `idx`: rows 1 and 4 from the start, row 7 from L12.
static func open_output_rows(level_idx: int) -> Array[int]:
	var out: Array[int] = [PORT_ROWS[0], PORT_ROWS[1]]
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
		{"side": "in", "row": PORT_ROWS[1]},
		{"side": "out", "row": PORT_ROWS[1]},
	]
	if level_idx >= 11:
		out.append({"side": "out", "row": PORT_ROWS[2]})
	if level_idx >= 17:
		out.append({"side": "in", "row": PORT_ROWS[2]})
	return out


## The view label of a port slot: "USB 2 · opens at L12" or "USB 4 · sealed".
static func slot_label(side: String, row: int) -> String:
	var n := PORT_ROWS.find(row) + 1
	var open_at := -1
	if side == "in":
		if row == PORT_ROWS[2]:
			open_at = 17
	else:
		if row == PORT_ROWS[2]:
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
