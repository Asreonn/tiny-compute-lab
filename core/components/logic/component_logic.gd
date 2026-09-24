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
		"add", "multiply", "processor", "counter", "modulo":
			return load("res://core/components/logic/math_logic.gd").new()
		"compare", "gate":
			return load("res://core/components/logic/logic_logic.gd").new()
		"splitter", "merger", "demux":
			return load("res://core/components/logic/routing_logic.gd").new()
		"bit_splitter":
			return load("res://core/components/logic/conversion_logic.gd").new()
		"buffer", "delay":
			return load("res://core/components/logic/storage_logic.gd").new()
	push_error("ComponentLogic.for_type: unknown machine type '%s'" % type)
	return ComponentLogic.new()
