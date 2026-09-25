class_name ContentVariant
extends Resource
## A variant of another content asset (docs/CONTENT.md): the base's data with a few fields
## changed. One class serves every registry — a machine (base: ComponentDef), a stick
## (DeviceDef) or a quest (LevelDef). `overrides` is deep-merged into the base's dictionary:
##   machine  {"name": "Quick Add", "campaign_ticks": 2, "power": 2, "params": {"k": {"default": 3}}}
##   quest    {"title": "Plus Three", "contract": {"count": 30}}
## A machine variant keeps its base's shape (size, ports, logic, art); only its numbers, texts
## and param defaults / ranges change. The resolved dictionary records "base": the base's id.

@export var id := ""
@export var base: Resource
@export var overrides: Dictionary = {}


## The base id (the ComponentDef / DeviceDef / LevelDef it derives from).
func base_id() -> String:
	return str(base.get("id")) if base != null else ""


## The base's dictionary with the overrides merged in (a nested variant resolves its base first).
func resolve() -> Dictionary:
	if base == null:
		push_error("ContentVariant '%s' has no base" % id)
		return {}
	var d: Dictionary = (base.resolve() if base is ContentVariant else base.to_dict()).duplicate(true)
	merge_into(d, overrides)
	d["base"] = str(d.get("base", base_id()))
	return d


## Deep merge: dictionaries merge key by key, anything else replaces.
static func merge_into(into: Dictionary, over: Dictionary) -> void:
	for k in over:
		if into.get(k) is Dictionary and over[k] is Dictionary:
			merge_into(into[k], over[k])
		else:
			into[k] = over[k].duplicate(true) if (over[k] is Dictionary or over[k] is Array) else over[k]
