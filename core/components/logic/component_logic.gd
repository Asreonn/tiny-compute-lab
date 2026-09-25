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


## The behaviour script named by the type's asset (ComponentDef.logic); a variant shares its
## base's. No script: plain hardware (the cooling family), which does nothing on its own.
static func _make(type: String) -> ComponentLogic:
	if not Catalog.has(type):
		push_error("ComponentLogic.for_type: unknown machine type '%s'" % type)
		return ComponentLogic.new()
	var script := Catalog.logic_script(type)
	return script.new() if script != null else ComponentLogic.new()
