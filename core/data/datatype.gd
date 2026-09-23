class_name DataType
extends RefCounted
## Datatype registry. MVP uses NUMBER and BOOLEAN; the rest are reserved so ports,
## packets and wires can already carry them without a redesign.

enum { NUMBER, BOOLEAN, VECTOR, MATRIX, TEXT, IMAGE, INSTRUCTION }

const NAMES := ["NUMBER", "BOOLEAN", "VECTOR", "MATRIX", "TEXT", "IMAGE", "INSTRUCTION"]
## Glyph shape per datatype (mirrors Penpot "Data / Datatype Language").
const GLYPHS := ["circle", "diamond", "capsule", "matrix", "text", "image", "hexagon"]


static func name_of(t: int) -> String:
	return NAMES[t] if t >= 0 and t < NAMES.size() else "UNKNOWN"


static func compatible(from_type: int, to_type: int) -> bool:
	return from_type == to_type


static func format_value(t: int, v: Variant) -> String:
	match t:
		BOOLEAN:
			return "TRUE" if v else "FALSE"
		NUMBER:
			if typeof(v) == TYPE_FLOAT and is_equal_approx(v, round(v)):
				return str(int(v))
			return str(v)
		_:
			return str(v)
