class_name RawValue
extends RefCounted
## A semantic (non-bit) value at the peripheral boundary — docs/ARCHITECTURE.md §0 rule 7,
## docs/SYSTEMS_EXPANSION.md §1. Raw values travel only on raw links (USB socket, Encoder
## input, Decoder output, Contract Drive); no compute machine ever sees one.
##
## Immutable: build one through the static factories and never mutate it, so packet lineage
## can share instances freely.

enum Kind { TEXT, NUMBER, KEY, SENSOR }

const KIND_NAMES := ["TEXT", "NUMBER", "KEY", "SENSOR"]

var kind: int
## TEXT: a 1-character String. NUMBER/KEY/SENSOR: an int.
var value: Variant


func _init(p_kind: int, p_value: Variant) -> void:
	kind = p_kind
	value = p_value


static func text(ch: String) -> RawValue:
	return RawValue.new(Kind.TEXT, ch)


static func number(n: int) -> RawValue:
	return RawValue.new(Kind.NUMBER, n)


static func key(n: int) -> RawValue:
	return RawValue.new(Kind.KEY, n)


static func sensor(n: int) -> RawValue:
	return RawValue.new(Kind.SENSOR, n)


## Same kind AND same value (a KEY 1 is never a SENSOR 1).
func equals(o: RawValue) -> bool:
	return o != null and o.kind == kind and o.value == value


## One-character display form: the char for TEXT, the decimal digits otherwise.
func glyph() -> String:
	return value if kind == Kind.TEXT else str(value)


func kind_name() -> String:
	return KIND_NAMES[kind]


func _to_string() -> String:
	return "%s(%s)" % [kind_name(), glyph()]
