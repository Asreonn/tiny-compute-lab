class_name PortDef
extends Resource
## One port of a ComponentDef (docs/CONTENT.md, docs/ARCHITECTURE.md §4.1). Pure data; the
## Catalog turns it into the PortDefinition dictionary the simulation reads.

@export var id := ""
@export_enum("in", "out", "ctrl") var dir := "in"
@export_enum("data", "control", "flag", "raw") var role := "data"
## "W" = the instance width, a number ("1"), "P:<param>" = a param's value, "R:<param>" = the
## instance width minus a param, "*" = any width (the Lab drive), "0" for raw ports.
@export var width := "W"
## Bus port: a BusPort slot + width tag instead of a round port.
@export var bus := false
## Footprint cell (unrotated) the port sits on, and the side it faces.
@export var cell := Vector2i.ZERO
@export_enum("E", "S", "W", "N") var side := 0
## Silk label; empty = the id in capitals.
@export var label := ""


func to_dict() -> Dictionary:
	var w: Variant = int(width) if width.is_valid_int() else width
	return {
		"id": id, "dir": dir, "role": role, "width": w, "bus": bus,
		"cell": cell, "side": side, "label": label if label != "" else id.to_upper(),
	}
