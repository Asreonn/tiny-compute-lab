class_name SaveStore
extends RefCounted
## Per-mission save: player layouts + best results, persisted as JSON at user://tcl_save.json.
## Static, pure helpers (no Node): the SimulationManager autoload calls these; tests redirect
## the path so they never touch the real save file.
##
## File shape: {"version": 2, "layouts": {mission_id: layout_dict},
##              "results": {mission_id: {"stars": int, "best_throughput": float}},
##              "lab": {level, delivered, rejected, size, layout, devices_owned}}
## Corrupt or missing files fall back to defaults — this never crashes.
##
## v1 → v2 migration (docs/SYSTEMS_EXPANSION.md §12): a v1 (or unversioned) file with a
## non-empty lab section is backed up to `<path>.v1.json` (once), its lab is remapped onto the
## new level table / single socket + Contract Drive board, then it is saved as v2 immediately.

const VERSION := 2

## Old lab level index → new level index (D3a's 11-level table).
const _LEVEL_MAP := [0, 1, 2, 5, 6, 7]

static var _path := "user://tcl_save.json"


## Point the store at a different file (tests use user://test_save.json). Deliberately NOT
## named set_path: SaveStore.set_path() would call the built-in Resource.set_path() on the
## script and the store would keep writing the REAL save file.
static func use_file(p: String) -> void:
	_path = p


## Forget all saved data: used by tests and available to the UI.
static func clear() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


static func _default() -> Dictionary:
	return {"version": VERSION, "layouts": {}, "results": {}, "lab": {}}


static func _load() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return _default()
	var f := FileAccess.open(_path, FileAccess.READ)
	if f == null:
		return _default()
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _default()
	for k in ["layouts", "results"]:
		if typeof(parsed.get(k, {})) != TYPE_DICTIONARY:
			parsed[k] = {}
	var lab = parsed.get("lab", {})
	if int(parsed.get("version", 1)) < VERSION and typeof(lab) == TYPE_DICTIONARY and not (lab as Dictionary).is_empty():
		parsed = _migrate_v1(parsed, text)
	return parsed


## Back up the original text, remap the lab onto the new level table, set version 2 and save.
static func _migrate_v1(parsed: Dictionary, text: String) -> Dictionary:
	var backup := _path.replace(".json", ".v1.json")
	if not FileAccess.file_exists(backup):
		var b := FileAccess.open(backup, FileAccess.WRITE)
		if b != null:
			b.store_string(text)
			b.close()
	var lab: Dictionary = parsed["lab"]
	lab["level"] = _map_level(int(lab.get("level", 0)))
	lab["delivered"] = 0
	lab["rejected"] = 0
	var layout = lab.get("layout", {})
	if typeof(layout) == TYPE_DICTIONARY:
		lab["layout"] = _migrate_layout(layout)
	lab["devices_owned"] = Array(LabDef.devices_upto(int(lab["level"])))
	parsed["version"] = VERSION
	_save(parsed)
	return parsed


static func _map_level(old: int) -> int:
	if old < 0:
		return 0
	if old < _LEVEL_MAP.size():
		return _LEVEL_MAP[old]
	return 7


## Rebuild the v1 machine list for the new board: keep every player machine plus the first
## locked usb_input (socket) and first locked usb_output (Contract Drive), in the order
## LabRun builds them (socket, then drive). Remap connection indices; drop dangling wires.
static func _migrate_layout(layout: Dictionary) -> Dictionary:
	var old_machines: Array = layout.get("machines", [])
	var socket_i := -1
	var drive_i := -1
	for i in old_machines.size():
		var md = old_machines[i]
		if typeof(md) != TYPE_DICTIONARY or not bool((md as Dictionary).get("locked", false)):
			continue
		var ty := str((md as Dictionary).get("type", ""))
		if ty == "usb_input" and socket_i < 0:
			socket_i = i
		elif ty == LabDef.OUTPUT_TYPE and drive_i < 0:
			drive_i = i
	var order: Array = []
	if socket_i >= 0:
		order.append(socket_i)
	if drive_i >= 0:
		order.append(drive_i)
	var remap := {}
	var new_machines: Array = []
	for old_i in order:
		var md: Dictionary = (old_machines[old_i] as Dictionary).duplicate(true)
		if str(md.get("type", "")) == "usb_input":
			if not bool(md.get("socket", false)):
				md["socket"] = true
			if str(md.get("device", "")) == "":
				md["device"] = "bit"
			if str(md.get("last_device", "")) == "":
				md["last_device"] = "bit"
		remap[old_i] = new_machines.size()
		new_machines.append(md)
	for i in old_machines.size():
		var md = old_machines[i]
		if typeof(md) != TYPE_DICTIONARY or bool((md as Dictionary).get("locked", false)):
			continue
		remap[i] = new_machines.size()
		new_machines.append(md)
	var new_conns: Array = []
	for cd in layout.get("connections", []):
		if typeof(cd) != TYPE_DICTIONARY:
			continue
		var a := int((cd as Dictionary).get("from", -1))
		var b := int((cd as Dictionary).get("to", -1))
		if not remap.has(a) or not remap.has(b):
			continue
		var nc: Dictionary = (cd as Dictionary).duplicate(true)
		nc["from"] = remap[a]
		nc["to"] = remap[b]
		nc["lanes"] = int(nc.get("lanes", 1))  # older layouts carried no lane count
		new_conns.append(nc)
	return {"size": layout.get("size", [28, 16]), "machines": new_machines, "connections": new_conns}


static func _save(data: Dictionary) -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveStore: cannot write %s" % _path)
		return
	f.store_string(JSON.stringify(data))
	f.close()


static func load_layout(id: String) -> Dictionary:
	var layouts: Dictionary = _load().get("layouts", {})
	var d = layouts.get(id, {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


static func save_layout(id: String, layout: Dictionary) -> void:
	var data := _load()
	data["layouts"][id] = layout
	_save(data)


## The persistent Lab: {level, delivered, size: [w, h], layout: layout_dict}.
## `layout` includes the locked USB sources/output, so a restore rebuilds the exact board.
static func load_lab() -> Dictionary:
	var lab = _load().get("lab", {})
	return lab if typeof(lab) == TYPE_DICTIONARY else {}


static func save_lab(lab: Dictionary) -> void:
	var data := _load()
	data["lab"] = lab
	_save(data)


## Player preferences that are not progress: {favourites, recents, volume, reduced_motion,
## fullscreen, intro}.
static func load_prefs() -> Dictionary:
	var p = _load().get("prefs", {})
	return p if typeof(p) == TYPE_DICTIONARY else {}


## Merges `prefs` into the stored preferences (other keys, e.g. settings, are kept).
static func save_prefs(prefs: Dictionary) -> void:
	var data := _load()
	var cur = data.get("prefs", {})
	if typeof(cur) != TYPE_DICTIONARY:
		cur = {}
	for k in prefs:
		cur[k] = prefs[k]
	data["prefs"] = cur
	_save(data)


## New Lab: forget the Lab (level, factory, desk, PSU); tutorial results and prefs stay.
static func reset_lab() -> void:
	var data := _load()
	data["lab"] = {}
	_save(data)


## Record a finished run. Stars keep the best result; throughput keeps the best value.
static func record_result(id: String, p_stars: int, throughput: float) -> void:
	var data := _load()
	var res: Dictionary = data["results"].get(id, {})
	if typeof(res) != TYPE_DICTIONARY:
		res = {}
	res["stars"] = max(int(res.get("stars", 0)), int(p_stars))
	res["best_throughput"] = max(float(res.get("best_throughput", 0.0)), float(throughput))
	data["results"][id] = res
	_save(data)


static func stars(id: String) -> int:
	var res: Dictionary = _load().get("results", {}).get(id, {})
	if typeof(res) != TYPE_DICTIONARY:
		return 0
	return int(res.get("stars", 0))


## Campaign unlock chain: the first campaign mission is always unlocked and each next one
## unlocks once the previous campaign mission has at least one star. Legacy missions (the
## mechanics regression set) are always available.
static func unlocked(id: String) -> bool:
	if id == Missions.all()[0].id:
		return true
	for m in Missions.legacy():
		if m.id == id:
			return true
	var all := Missions.all()
	for i in range(1, all.size()):
		if all[i].id == id:
			return stars(all[i - 1].id) >= 1
	return true