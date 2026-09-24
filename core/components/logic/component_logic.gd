class_name ComponentLogic
extends RefCounted
## Per-type machine behaviour. Stateless: one cached instance per machine type.
## Reads the Machine's queues/params, computes with BitVector ops only, and calls
## Machine.begin_job(). See docs/ARCHITECTURE.md §4.4.

static var _cache: Dictionary = {}


func start(_m, _sim) -> void:
	pass


static func for_type(type: String) -> ComponentLogic:
	if not _cache.has(type):
		_cache[type] = _make(type)
	return _cache[type]


static func _make(type: String) -> ComponentLogic:
	match type:
		"input", "usb_input", "output", "terminal_output", "usb_output":
			return load("res://core/components/logic/io_logic.gd").new()
		"add", "adder", "multiply", "processor", "counter", "modulo":
			return load("res://core/components/logic/math_logic.gd").new()
		"compare", "gate", "and_gate", "or_gate", "xor_gate", "not_gate", "shift_left", "shift_right":
			return load("res://core/components/logic/logic_logic.gd").new()
		"splitter", "merger", "demux", "mux", "cond_router":
			return load("res://core/components/logic/routing_logic.gd").new()
		"bit_splitter", "bus_combiner", "zero_extend", "sign_extend", "truncate":
			return load("res://core/components/logic/conversion_logic.gd").new()
		"number_encoder", "char_encoder", "number_decoder", "char_decoder":
			return load("res://core/components/logic/codec_logic.gd").new()
		"buffer", "delay":
			return load("res://core/components/logic/storage_logic.gd").new()
		"heatsink", "blower", "heat_pipe", "radiator":
			return ComponentLogic.new()  # cooling hardware: no data ports, the ThermalGrid reads it
	push_error("ComponentLogic.for_type: unknown machine type '%s'" % type)
	return ComponentLogic.new()
