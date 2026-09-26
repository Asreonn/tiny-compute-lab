class_name LabConfig
extends Resource
## The Lab campaign as one asset (docs/CONTENT.md): content/lab/lab.tres. The quest order, the
## laptop's port racks and the progression milestones live here, so a different campaign (a
## variant with other quests, a tighter window, other PSU steps) is another LabConfig file.
## Level indices are 0-based (index 16 = "L17").

## The quests in order: LevelDef assets or ContentVariants of one.
@export var levels: Array[Resource] = []
## Board size before any quest grows it.
@export var initial_size := Vector2i(28, 16)
## The port rows on each laptop edge, top to bottom.
@export var port_rows: PackedInt32Array = PackedInt32Array([1, 4, 7, 10])
## Per port row: the level index it opens at (0 = from the start, -1 = always sealed).
@export var input_port_open: PackedInt32Array = PackedInt32Array([0, 0, 17, -1])
@export var output_port_open: PackedInt32Array = PackedInt32Array([0, 0, 11, -1])
## How many quests are active at once.
@export var quest_window := 2
## The first level with a PSU (power caps, clock modes after it), heat and the Monitor.
@export var power_level := 15
## The power network's onboard budget (0 = unlimited; the current campaign keeps 0).
@export var onboard_capacity := 0
## The board row (0-based) of the locked power input / controller fixtures.
@export var power_input_row := 12
## The level index from which the controller tier is ctrl / basic / eff / hc (the first entry is
## also when the fixtures appear; power_level picks the fixtures, these only pick the tier).
@export var controller_tier_levels: PackedInt32Array = PackedInt32Array([15, 16, 17, 20])
@export var heat_level := 16
@export var monitor_level := 8
## The PSU tiers: capacity in power units and name (LevelDef.reward psu_tier picks one).
@export var psu_capacity: PackedInt32Array = PackedInt32Array([8, 16, 32, 64])
@export var psu_names: PackedStringArray = PackedStringArray(["Starter Adapter", "Improved Adapter", "Desktop PSU", "High-Capacity PSU"])
## The level index at which max machine lanes become 2, 4, 8 (FACTORY_SYSTEMS §3.1).
@export var lane_levels: PackedInt32Array = PackedInt32Array([3, 5, 21])
## The level index at which max wire lanes become 2, 4, 8 (FACTORY_SYSTEMS §2.1).
@export var bus_lane_levels: PackedInt32Array = PackedInt32Array([5, 17, 21])
## The first level with the Efficiency upgrade (FACTORY_SYSTEMS §3.1).
@export var efficiency_level := 21
## quest_window applies from this level; before it the window is 1 (FACTORY_SYSTEMS §4).
@export var quest_window_level := 15


## The quest dictionaries in order (variants resolved).
func level_dicts() -> Array:
	var out: Array = []
	for r in levels:
		if r is ContentVariant:
			out.append((r as ContentVariant).resolve())
		elif r is LevelDef:
			out.append((r as LevelDef).to_dict())
		else:
			push_error("LabConfig: a level entry is not a LevelDef or ContentVariant")
	return out
