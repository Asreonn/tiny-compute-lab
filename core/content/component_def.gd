class_name ComponentDef
extends Resource
## A machine type as an asset (docs/CONTENT.md): content/components/<family>/<id>.tres. The
## Catalog loads every one at start-up; a new machine is a new file (plus a ComponentLogic
## script when it needs new behaviour, and a layout in assets/art/machine_layouts.json for its
## art). Variants of an existing machine are ContentVariant files next to it.

const FAMILIES := ["io", "math", "logic", "routing", "conversion", "storage", "memory", "control", "compute", "thermal", "power"]

@export var id := ""
@export var display_name := ""
@export_enum("io", "math", "logic", "routing", "conversion", "storage", "memory", "control", "compute", "thermal", "power") var family := "math"
@export_enum("S", "M", "L", "X") var size := "M"
## Job length in ticks: tutorial "legacy" boards and campaign boards (readable dwell).
@export var ticks := 1
@export var campaign_ticks := 1
## Rated power; every powered machine also gets the Clock param (Catalog).
@export var power := 0
## Heat per full-rate tick in tenths of °C; -1 = derived from the power (Catalog.heat_per_power).
@export var heat := -1
## Power capacity of a power part (rail / plane / board); 0 for everything else.
@export var capacity := 0
## Airflow a blower delivers (units/tick); 0 for everything else.
@export var airflow := 0
## Airflow a radiator needs for full capacity; 0 = passive (no airflow required).
@export var airflow_need := 0
## Thermal contact capacity; -1 = derived from the size (S 600 / M 1200 / L 2400).
@export var contact_cap := -1
## Idle baseline (docs/DATA_FACTORY.md §2.0b): the share (percent) of its full-rate heat and power
## a powered part still costs while idle. Data-driven and meant to be rebalanced.
@export var idle_pct := 12
## How many parallel jobs an upgrade may give it (FACTORY_SYSTEMS §3.2); 1 = most machines.
@export var max_lanes := 1
## Operation icon (assets/art/icon/<icon>.svg) or, when empty, the glyph text.
@export var icon := ""
@export var glyph_text := ""
@export_multiline var description := ""
@export var ports: Array[PortDef] = []
@export var params: Array[ParamDef] = []
## Behaviour: a ComponentLogic script; empty = none (cooling hardware the ThermalGrid reads).
@export var logic: Script
## Build-menu position (ascending).
@export var menu_order := 0


## The ComponentDefinition dictionary the simulation reads (Catalog.def).
func to_dict() -> Dictionary:
	var pd: Array = []
	for p in ports:
		pd.append(p.to_dict())
	var pm := {}
	for p in params:
		pm[p.key] = p.to_dict()
	var d := {
		"name": display_name, "family": family, "size": size, "ticks": ticks, "campaign_ticks": campaign_ticks,
		"power": power, "icon": icon, "desc": description, "ports": pd, "params": pm,
		"logic": logic, "order": menu_order, "max_lanes": max_lanes, "idle_pct": idle_pct,
	}
	if glyph_text != "":
		d["glyph_text"] = glyph_text
	if heat >= 0:
		d["heat"] = heat
	if capacity > 0:
		d["capacity"] = capacity
	if airflow > 0:
		d["airflow"] = airflow
	if airflow_need > 0:
		d["airflow_need"] = airflow_need
	if contact_cap >= 0:
		d["contact_cap"] = contact_cap
	return d
