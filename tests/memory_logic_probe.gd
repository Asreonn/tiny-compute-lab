class_name MemoryLogicProbe
extends RefCounted
## Test access to memory_logic.gd's static helpers (the logic script has no class_name).


static func parse(text: String) -> Array:
	return load("res://core/components/logic/memory_logic.gd").parse_table(text)
