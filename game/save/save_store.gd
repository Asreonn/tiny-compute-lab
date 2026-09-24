class_name SaveStore
extends RefCounted
## Per-mission save: player layouts + best results, persisted as JSON at user://tcl_save.json.
## Static, pure helpers (no Node): the SimulationManager autoload calls these; tests redirect
## the path so they never touch the real save file.
##
## File shape: {"version": 1, "layouts": {mission_id: layout_dict},
##              "results": {mission_id: {"stars": int, "best_throughput": float}}}
## Corrupt or missing files fall back to defaults — this never crashes.

const VERSION := 1

static var _path := "user://tcl_save.json"


## Point the store at a different file (tests use user://test_save.json).
static func set_path(p: String) -> void:
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
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return _default()
	for k in ["layouts", "results"]:
		if typeof(parsed.get(k, {})) != TYPE_DICTIONARY:
			parsed[k] = {}
	return parsed


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