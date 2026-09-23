class_name Missions
extends RefCounted
## Campaign data. all() is the new BitVector campaign; legacy() is the pre-BitVector
## "factory" mechanics regression set. by_id searches both.

static var _cache: Array = []
static var _legacy_cache: Array = []


## The playable campaign (slice A: 3-bit).
static func all() -> Array:
	if _cache.is_empty():
		var i := 0
		for d in _data():
			_cache.append(MissionDef.from_dict(i, d))
			i += 1
	return _cache


## The ten original missions, kept unchanged as mechanics regression tests.
static func legacy() -> Array:
	if _legacy_cache.is_empty():
		var i := 0
		for d in _legacy_data():
			_legacy_cache.append(MissionDef.from_dict(i, d))
			i += 1
	return _legacy_cache


static func by_id(id: String) -> MissionDef:
	for m in all():
		if m.id == id:
			return m
	for m in legacy():
		if m.id == id:
			return m
	return null


# ------------------------------------------------------------------ helpers

## Slice A input: a USB source locked to an explicit width.
static func _usb_in(cell: Vector2i, width: int, values: Array, interval := 4, strict := false) -> Dictionary:
	return {"cell": cell, "rot": 0, "width": width, "values": values, "interval": interval, "strict": strict, "start": 1, "source": "usb_input"}


## Slice A output with an explicit width and preferred view mode.
static func _out(cell: Vector2i, width: int, expected: Array, view := ViewMode.Mode.BIN, ordered := true) -> Dictionary:
	return {"cell": cell, "rot": 0, "width": width, "expected": expected, "ordered": ordered, "view": view}


## Legacy input: width 8, fed from the classic "input" source (legacy mission data only).
static func _legacy_in(cell: Vector2i, values: Array, interval := 4, strict := false, width := 8) -> Dictionary:
	return {"cell": cell, "rot": 0, "width": width, "values": values, "interval": interval, "strict": strict, "start": 1, "source": "input"}


## Legacy output: width 8, UDEC view (legacy mission data only).
static func _legacy_out(cell: Vector2i, expected: Array, ordered := true, width := 8) -> Dictionary:
	return {"cell": cell, "rot": 0, "width": width, "expected": expected, "ordered": ordered, "view": ViewMode.Mode.UDEC}


static func _data() -> Array:
	return [
		{
			"id": "a1_plus_two", "title": "Plus Two", "teaches": "Wires + Add",
			"brief": "The lab speaks in 3-bit words. Add two to every word.",
			"formula": "x → x + 010", "size": Vector2i(14, 8),
			"default_width": 3, "view_modes": [ViewMode.Mode.BIN, ViewMode.Mode.UDEC, ViewMode.Mode.HEX],
			"inputs": [_usb_in(Vector2i(1, 3), 3, ["010", "011", "100"], 4)],
			"outputs": [_out(Vector2i(11, 3), 3, ["100", "101", "110"])],
			"allowed": ["add"], "unlocks": ["add"],
			"goals": [{"kind": "components", "max": 1, "label": "Use 1 component"}],
			"hint": "Place an Add, set its constant to 2 (010), wire USB → Add → Output.",
		},
		{
			"id": "a2_wrap", "title": "Wrap Around", "teaches": "Overflow",
			"brief": "Three bits only count to 111. Watch what happens past the top.",
			"formula": "x → x + 010 (3-bit)", "size": Vector2i(14, 8),
			"default_width": 3, "view_modes": [ViewMode.Mode.BIN, ViewMode.Mode.UDEC, ViewMode.Mode.HEX],
			"inputs": [_usb_in(Vector2i(1, 3), 3, ["101", "110", "111"], 4)],
			"outputs": [_out(Vector2i(11, 3), 3, ["111", "000", "001"])],
			"allowed": ["add"], "unlocks": [],
			"goals": [{"kind": "components", "max": 1, "label": "Use 1 component"}],
			"hint": "The same Add as before — watch the carry when the sum passes 111.",
		},
	]


static func _legacy_data() -> Array:
	return [
		{
			"id": "boot", "title": "Boot Sequence", "teaches": "Wires", "legacy": true,
			"brief": "Your lab is cold. Route the input stream straight to the output so the validator sees data flowing.",
			"formula": "x → x", "size": Vector2i(14, 8), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 3), [3, 1, 4, 1, 5], 4)],
			"outputs": [_legacy_out(Vector2i(11, 3), [3, 1, 4, 1, 5])],
			"allowed": [], "goals": [{"kind": "latency", "max": 14, "label": "Average latency ≤ 14 ticks"}],
			"hint": "Select the WIRE tool (W), drag from the Input's output port to the Output's input port.",
		},
		{
			"id": "double", "title": "Double It", "teaches": "Multiply", "legacy": true,
			"brief": "Every value must leave the machine doubled.",
			"formula": "x → x × 2", "size": Vector2i(14, 8), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 3), [1, 2, 3, 4, 5], 4)],
			"outputs": [_legacy_out(Vector2i(11, 3), [2, 4, 6, 8, 10])],
			"allowed": ["multiply"], "unlocks": ["multiply"],
			"goals": [{"kind": "components", "max": 1, "label": "Use 1 component"}],
			"hint": "Place a Multiply between Input and Output, then wire both sides.",
		},
		{
			"id": "offset", "title": "Offset", "teaches": "Add", "legacy": true,
			"brief": "Shift every reading up by ten.",
			"formula": "x → x + 10", "size": Vector2i(14, 8), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 3), [5, 12, 20, 7, 3], 4)],
			"outputs": [_legacy_out(Vector2i(11, 3), [15, 22, 30, 17, 13])],
			"allowed": ["add", "multiply"], "unlocks": ["add"],
			"goals": [{"kind": "power", "max": 1, "label": "Power ≤ 1"}],
			"hint": "Add uses a constant — select it and change the value in the Inspector.",
		},
		{
			"id": "pipeline", "title": "Pipeline", "teaches": "Chaining", "legacy": true,
			"brief": "Chain two operations. Order matters.",
			"formula": "x → (x × 2) + 5", "size": Vector2i(16, 9), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 4), [1, 2, 3, 4, 5], 3)],
			"outputs": [_legacy_out(Vector2i(13, 4), [7, 9, 11, 13, 15])],
			"allowed": ["add", "multiply"],
			"goals": [{"kind": "components", "max": 2, "label": "Use 2 components"}, {"kind": "latency", "max": 16, "label": "Average latency ≤ 16 ticks"}],
		},
		{
			"id": "decision", "title": "Decision", "teaches": "Compare", "legacy": true,
			"brief": "Classify each reading: is it greater than 20? Answer with a BOOLEAN.",
			"formula": "x → x > 20", "size": Vector2i(14, 8), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 3), [12, 25, 20, 31, 8], 4)],
			"outputs": [_legacy_out(Vector2i(11, 3), [false, true, false, true, false], true, 1)],
			"allowed": ["compare", "add", "multiply"], "unlocks": ["compare"],
			"goals": [{"kind": "components", "max": 1, "label": "Use 1 component"}],
			"hint": "Compare turns NUMBER into BOOLEAN — note the diamond-shaped output port.",
		},
		{
			"id": "filter", "title": "Filter", "teaches": "Gate + control", "legacy": true,
			"brief": "Only values above 10 may pass. Everything else must be discarded.",
			"formula": "keep x if x > 10", "size": Vector2i(16, 10), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 4), [4, 18, 7, 25, 12, 3], 4)],
			"outputs": [_legacy_out(Vector2i(13, 4), [18, 25, 12])],
			"allowed": ["compare", "gate", "splitter", "add", "multiply"], "unlocks": ["gate", "splitter"],
			"goals": [{"kind": "components", "max": 3, "label": "Use 3 components"}, {"kind": "power", "max": 3, "label": "Power ≤ 3"}],
			"hint": "A Splitter in DUPLICATE mode sends the value to the Gate and to a Compare that drives the Gate's EN port.",
		},
		{
			"id": "fork", "title": "Fork", "teaches": "Duplicate streams", "legacy": true,
			"brief": "Two validators want different views of the same stream.",
			"formula": "A: x × 2    B: x + 1", "size": Vector2i(16, 10), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 4), [2, 5, 9, 4], 4)],
			"outputs": [_legacy_out(Vector2i(13, 1), [4, 10, 18, 8]), _legacy_out(Vector2i(13, 7), [3, 6, 10, 5])],
			"allowed": ["splitter", "add", "multiply", "compare", "gate"],
			"goals": [{"kind": "components", "max": 3, "label": "Use 3 components"}],
		},
		{
			"id": "traffic", "title": "Traffic", "teaches": "Buffer", "legacy": true,
			"brief": "A burst of 14 packets arrives back-to-back and the input cannot wait. Absorb the burst before it overflows.",
			"formula": "x → x × 3   (burst: 1 packet/tick)", "size": Vector2i(12, 7), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 3), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14], 1, true)],
			"outputs": [_legacy_out(Vector2i(9, 3), [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42])],
			"allowed": ["multiply", "add", "buffer", "delay", "counter", "splitter", "merger"], "unlocks": ["buffer", "delay", "counter"],
			"goals": [{"kind": "components", "max": 2, "label": "Use 2 components"}],
			"hint": "Multiply needs 2 ticks per packet. A Buffer in front of it stores the backlog.",
		},
		{
			"id": "parallel", "title": "Parallel Processing", "teaches": "Split + Merge", "legacy": true,
			"brief": "The Processor is slow: 4 ticks per value. The input arrives every 2 ticks. One Processor cannot keep up.",
			"formula": "x → x²   (any order)", "size": Vector2i(18, 11), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 5), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16], 2, true)],
			"outputs": [_legacy_out(Vector2i(15, 5), [1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121, 144, 169, 196, 225, 256], false)],
			"allowed": ["processor", "splitter", "merger", "buffer", "multiply", "add"], "unlocks": ["processor", "merger"],
			"goals": [{"kind": "throughput", "min": 4.5, "label": "Throughput ≥ 4.5/s"}, {"kind": "power", "max": 12, "label": "Power ≤ 12"}],
			"hint": "Splitter (ALTERNATE) → two Processors → Merger.",
		},
		{
			"id": "optimize", "title": "Optimization", "teaches": "Throughput", "legacy": true,
			"brief": "Full speed: one packet every tick, no waiting. Build a line that keeps up — then make it lean.",
			"formula": "x → (x × 3) + 1   (any order)", "size": Vector2i(20, 12), "default_width": 8, "view_modes": [ViewMode.Mode.UDEC],
			"inputs": [_legacy_in(Vector2i(1, 5), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], 1, true)],
			"outputs": [_legacy_out(Vector2i(17, 5), [4, 7, 10, 13, 16, 19, 22, 25, 28, 31, 34, 37, 40, 43, 46, 49, 52, 55, 58, 61], false)],
			"allowed": ["multiply", "add", "splitter", "merger", "buffer", "processor", "delay"],
			"goals": [{"kind": "power", "max": 7, "label": "Power ≤ 7"}, {"kind": "latency", "max": 16, "label": "Average latency ≤ 16 ticks"}],
			"hint": "Multiply takes 2 ticks. Two in parallel handle one packet per tick.",
		},
	]
