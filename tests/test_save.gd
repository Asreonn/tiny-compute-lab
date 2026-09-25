class_name SaveStoreTests
extends RefCounted
## Save v2 acceptance tests: the v1 → v2 lab migration (docs/SYSTEMS_EXPANSION.md §12) and the
## as-is v2 / corrupt-file behaviour. Each case calls t.check(cond, what); run() is invoked from
## tests/run_tests.gd. Uses a temp user:// path so the real save file is never touched.

const PATH := "user://test_save_migrate.json"
const BACKUP := "user://test_save_migrate.v1.json"


static func run(t) -> void:
	_migrate_v1(t)
	_v2_roundtrip(t)
	_corrupt(t)
	_cleanup()


static func _cleanup() -> void:
	SaveStore.use_file(PATH)
	SaveStore.clear()
	if FileAccess.file_exists(BACKUP):
		DirAccess.remove_absolute(BACKUP)


static func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


static func _write(p: String, text: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


static func _m(ty: String, cell: Array, locked: bool, params := {}, device := "") -> Dictionary:
	return {"type": ty, "cell": cell, "rot": 0, "width": 3, "params": params, "locked": locked,
		"channel": 0, "device": device, "last_device": device, "socket": false}


## A hand-made v1 lab at old level 4 ("Past Z"): 3 locked inputs, 1 locked output, 2 player
## machines (add + modulo) and 4 wires — one of them into a dropped input.
static func _v1() -> Dictionary:
	return {
		"version": 1, "layouts": {}, "results": {},
		"lab": {
			"level": 4, "delivered": 12, "rejected": 3, "size": [24, 14],
			"layout": {
				"size": [24, 14],
				"machines": [
					_m("usb_input", [1, 2], true, {}, ""),
					_m("usb_input", [1, 6], true, {}, "text"),
					_m("usb_input", [1, 9], true, {}, "number"),
					_m("usb_output", [22, 5], true, {}, ""),
					_m("add", [8, 5], false, {"k": 3}, ""),
					_m("modulo", [12, 5], false, {"k": 26}, ""),
				],
				"connections": [
					{"from": 0, "from_port": "out", "to": 4, "to_port": "in"},
					{"from": 4, "from_port": "out", "to": 5, "to_port": "in"},
					{"from": 5, "from_port": "out", "to": 3, "to_port": "in"},
					{"from": 1, "from_port": "out", "to": 4, "to_port": "in"},
				],
			},
		},
	}


static func _migrate_v1(t) -> void:
	_cleanup()
	var text := JSON.stringify(_v1())
	_write(PATH, text)

	# load_lab triggers the migration, writes the backup and saves v2 immediately.
	var lab := SaveStore.load_lab()
	t.check(FileAccess.file_exists(BACKUP), "the migration writes a .v1.json backup")
	t.check(_read(BACKUP) == text, "the backup is an untouched copy of the original file text")
	t.check(int(lab.get("level", -1)) == 6, "old level 4 maps to new level 6 (got %d)" % int(lab.get("level", -1)))
	t.check(int(lab.get("delivered", -1)) == 0 and int(lab.get("rejected", -1)) == 0, "migration resets delivered/rejected")
	t.check(lab.get("devices_owned", []) == ["bit", "number", "text"], "devices_owned is LabDef-derived for the new level")

	var saved: Dictionary = JSON.parse_string(_read(PATH))
	t.check(typeof(saved) == TYPE_DICTIONARY and int(saved.get("version", 0)) == 2, "the migrated file is saved as version 2")
	t.check(typeof(saved.get("layouts", null)) == TYPE_DICTIONARY and typeof(saved.get("results", null)) == TYPE_DICTIONARY, "non-lab sections are kept")

	var layout: Dictionary = lab.get("layout", {})
	var machines: Array = layout.get("machines", [])
	var locked_in := 0
	var locked_out := 0
	var has_add := false
	var has_mod := false
	for m in machines:
		if bool(m.get("locked", false)):
			if str(m.get("type", "")) == "usb_input":
				locked_in += 1
			elif str(m.get("type", "")) == "usb_output":
				locked_out += 1
		else:
			has_add = has_add or str(m.get("type", "")) == "add"
			has_mod = has_mod or str(m.get("type", "")) == "modulo"
	t.check(locked_in == 1 and locked_out == 1, "exactly one locked socket and one locked drive survive")
	t.check(has_add and has_mod, "both player machines survive")
	t.check(machines.size() == 4, "dropped locked entries are gone (got %d machines)" % machines.size())

	var sock: Dictionary = machines[0]
	t.check(str(sock.get("type", "")) == "usb_input" and bool(sock.get("socket", false)), "the kept socket comes first")
	t.check(str(sock.get("device", "")) == "bit" and str(sock.get("last_device", "")) == "bit", "the kept socket gets the Bit module")

	var conns: Array = layout.get("connections", [])
	t.check(conns.size() == 3, "the wire into a dropped input is gone (got %d wires)" % conns.size())
	var remap_ok := true
	for c in conns:
		if int(c.get("from", -1)) >= machines.size() or int(c.get("to", -1)) >= machines.size():
			remap_ok = false
	t.check(remap_ok, "surviving connections are remapped onto the new machine indices")

	# SimulationManager-free restore: build the new level-6 board and lay the layout on top.
	var sim := Simulation.new()
	var run := LabRun.new()
	run.level = int(lab["level"])
	run.build_board(sim)
	sim.load_player_layout(layout)
	var socket := -1
	var drive := -1
	var add := -1
	var mod := -1
	for id in sim.machines:
		var m: Machine = sim.machines[id]
		if m.locked and m.type == "usb_input" and m.cell.y == 1:
			socket = id
		elif m.locked and m.type == "usb_output" and m.device == "job":
			drive = id
		elif m.type == "add":
			add = id
		elif m.type == "modulo":
			mod = id
	t.check(socket >= 0 and drive >= 0 and add >= 0 and mod >= 0, "restore rebuilds the socket, drive and both player machines")
	t.check(sim.connections.size() == 3, "restore keeps the 3 surviving wires (got %d)" % sim.connections.size())
	var socket_add := false
	var add_mod := false
	var mod_drive := false
	for cid in sim.connections:
		var c: Connection = sim.connections[cid]
		if c.from_id == socket and c.to_id == add:
			socket_add = true
		elif c.from_id == add and c.to_id == mod:
			add_mod = true
		elif c.from_id == mod and c.to_id == drive:
			mod_drive = true
	t.check(socket_add and add_mod and mod_drive, "socket→add, add→modulo and modulo→drive are all reconnected")


static func _v2_roundtrip(t) -> void:
	var before := _read(PATH)
	var lab := SaveStore.load_lab()
	t.check(not lab.is_empty(), "a v2 file still loads")
	t.check(_read(PATH) == before, "a v2 file is loaded as-is, without rewriting it")


static func _corrupt(t) -> void:
	_cleanup()
	_write(PATH, "{not valid json")
	t.check(SaveStore.load_lab().is_empty(), "a corrupt file gives an empty lab")
	t.check(SaveStore.load_layout("a1_plus_two").is_empty(), "a corrupt file gives an empty layout")
