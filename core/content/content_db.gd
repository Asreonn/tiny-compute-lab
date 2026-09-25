class_name ContentDB
extends RefCounted
## Finds and loads the content assets (docs/CONTENT.md). Scans are recursive and sorted by path,
## so every registry built from them is deterministic. Exported builds list converted resources
## as "<name>.tres.remap"; those are loaded by their original path.

const COMPONENTS_DIR := "res://content/components"
const DEVICES_DIR := "res://content/devices"
const LAB_CONFIG := "res://content/lab/lab.tres"


## Every resource under `dir` (and its sub-folders), in path order.
static func load_dir(dir: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for path in list(dir):
		var r := load(path)
		if r == null:
			push_error("ContentDB: cannot load %s" % path)
			continue
		out.append(r)
	return out


## The resource paths under `dir`, sorted.
static func list(dir: String) -> PackedStringArray:
	var paths := PackedStringArray()
	_scan(dir, paths)
	paths.sort()
	return paths


static func _scan(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(sub), out)
	for f in DirAccess.get_files_at(dir):
		var name := f.trim_suffix(".remap")
		if (name.ends_with(".tres") or name.ends_with(".res")) and not out.has(dir.path_join(name)):
			out.append(dir.path_join(name))


## The id → dictionary table of a registry folder: base assets through `to_dict()`, variants
## through ContentVariant.resolve(). `kind` names the asset class for the error message.
static func table(dir: String, script: Script) -> Dictionary:
	var out := {}
	for r in load_dir(dir):
		var id := ""
		var d := {}
		if r is ContentVariant:
			id = (r as ContentVariant).id
			d = (r as ContentVariant).resolve()
		elif r.get_script() == script:
			id = str(r.get("id"))
			d = r.call("to_dict")
		else:
			push_error("ContentDB: %s is not a %s or a ContentVariant" % [r.resource_path, script.get_global_name()])
			continue
		if id == "" or out.has(id):
			push_error("ContentDB: %s has an empty or duplicate id '%s'" % [r.resource_path, id])
			continue
		out[id] = d
	return out
