class_name Contract
extends RefCounted
## A Lab level's contract (docs/SYSTEMS_EXPANSION.md §3): what the Contract Drive accepts and
## the optional window constraints. Pure data + deterministic op evaluation — no Node, no RNG.
##
## A contract is built from a level Dictionary (`LabDef.level`). `kind`:
##   deliver — the payload must equal `value` (the L1–L3 behaviour)
##   map     — the payload must equal `f(origin)` for a small op chain
##   filter  — as map, but `f` may return DROP (the value must NOT arrive)
##   paired  — reserved: as map over several sockets (D3 uses map/filter)
##
## `expected_for` returns the expected BitVector/RawValue, DROP (the value must not arrive) or
## null (the packet carries no origin from the primary socket → it cannot be judged → reject).
## Ops are evaluated on the ORIGIN value (`origins[socket].value`), so lineage, not constants,
## decides acceptance.

const DROP := "DROP"

var kind := "deliver"
## "bits" | "text" | "number"
var accept_format := "bits"
## Bits contracts only: the accepted width (0 = any).
var accept_width := 0
## deliver: the expected BitVector (built from a BIN string or Charset.encode).
var value: Variant = null
var ops: Array = []
var count := 0
## Accepted values per Lab second (= per 10 ticks), rolling over the last 60 ticks. 0 = none.
var min_rate := 0.0
## Socket overruns allowed in the window. -1 = none.
var max_lost := -1
## Index into the socket list whose origin drives map/filter.
var primary_socket := 0
## The primary socket's stream kind ("bit", "number", "text", "sensor"), for describe().
var source_kind := ""


static func from_level(lv: Dictionary) -> Contract:
	var c := Contract.new()
	var d: Dictionary = lv.get("contract", {})
	c.kind = str(d.get("kind", "deliver"))
	c.count = int(d.get("count", 0))
	c.min_rate = float(d.get("min_rate", 0.0))
	c.max_lost = int(d.get("max_lost", -1))
	c.primary_socket = int(d.get("primary_socket", 0))
	c.ops = d.get("ops", [])
	var streams: Dictionary = lv.get("streams", {})
	if not streams.is_empty():
		c.source_kind = str(streams.keys()[0])
	c.accept_format = str(d.get("accept_format", ""))
	if c.kind == "deliver":
		c.accept_format = "bits"
		if d.has("value"):
			c.value = BitVector.from_bin(str(d["value"]))
			c.accept_width = (c.value as BitVector).width
		elif d.has("chr"):
			c.value = Charset.encode(str(d["chr"]), int(d.get("width", 5)))
			c.accept_format = "text"
	if c.accept_format == "":
		c.accept_format = "bits"
	if c.accept_format == "bits":
		c.accept_width = int(d.get("accept_width", c.accept_width))
	return c


# ------------------------------------------------------------------ judging

## The expected payload for `p`, DROP (it must not arrive) or null (no primary origin).
func expected_for(p: Packet, sockets: Array[int]) -> Variant:
	if kind == "deliver":
		return value
	var sid := _primary_id(sockets)
	if sid < 0 or p == null or not p.origins.has(sid):
		return null
	var entry: Dictionary = p.origins[sid]
	return expect_from(entry.get("value"))


## Apply the op chain to an origin value. Returns the expected value or DROP.
func expect_from(origin: Variant) -> Variant:
	var cur: Variant = origin
	for op in ops:
		cur = apply_op(op, cur)
		if cur is String:
			return DROP
	return cur


## True when the delivered payload matches the expectation in payload type (raw vs bits),
## width (bits) and value. DROP or null are always rejected.
func judge(p: Packet, sockets: Array[int]) -> bool:
	var exp: Variant = expected_for(p, sockets)
	if exp == null or exp is String:
		return false
	if exp is BitVector:
		return p != null and not p.is_raw() and p.data != null and p.data.equals(exp)
	if exp is RawValue:
		return p != null and p.is_raw() and p.raw.equals(exp)
	return false


## A representative BitVector for the HUD: the mapped value of the first stream element when
## it is bits (the last bits value before a trailing decode), else BitVector.zero(1).
func representative_bits(origin: Variant) -> Variant:
	var cur: Variant = origin
	var last_bits: Variant = null
	for op in ops:
		cur = apply_op(op, cur)
		if cur is BitVector:
			last_bits = cur
		if cur is String:
			break
	if cur is BitVector:
		return cur
	return last_bits if last_bits != null else DROP


func _primary_id(sockets: Array[int]) -> int:
	if primary_socket < 0 or primary_socket >= sockets.size():
		return -1
	return sockets[primary_socket]


# ------------------------------------------------------------------ ops

## One pure op: Variant -> Variant, DROP on a wrong payload type or a failed predicate.
func apply_op(op: Dictionary, v: Variant) -> Variant:
	match str(op.get("op", "")):
		"add":
			return (v as BitVector).add(int(op.get("k", 0))) if v is BitVector else DROP
		"sub":
			return (v as BitVector).sub(int(op.get("k", 0))) if v is BitVector else DROP
		"mul":
			return (v as BitVector).mul(int(op.get("k", 0))) if v is BitVector else DROP
		"mod":
			return (v as BitVector).umod(int(op.get("k", 1))) if v is BitVector else DROP
		"slice":
			return (v as BitVector).slice(int(op.get("lo", 0)), int(op.get("len", 1))) if v is BitVector else DROP
		"encode_num":
			return BitVector.of(int((v as RawValue).value), int(op.get("width", 1))) if v is RawValue else DROP
		"encode_char":
			if not (v is RawValue):
				return DROP
			var bv := Charset.encode(str((v as RawValue).value), int(op.get("width", 5)))
			return bv if bv != null else DROP
		"decode_num":
			if not (v is BitVector):
				return DROP
			var b := v as BitVector
			return RawValue.number(b.signed() if bool(op.get("signed", false)) else b.unsigned())
		"decode_char":
			return RawValue.text(Charset.decode(v as BitVector)) if v is BitVector else DROP
		"keep_if":
			return v if _keep(v, op) else DROP
	return DROP


func _keep(v: Variant, op: Dictionary) -> bool:
	var cmp := str(op.get("cmp", "="))
	var k := int(op.get("k", 0))
	if v is BitVector:
		var b := v as BitVector
		var c := b.ucmp(BitVector.of(k, b.width))
		match cmp:
			">": return c > 0
			"<": return c < 0
			"=": return c == 0
		return false
	if v is RawValue:
		var n := int((v as RawValue).value)
		match cmp:
			">": return n > k
			"<": return n < k
			"=": return n == k
		return false
	return false


# ------------------------------------------------------------------ text

## Short HUD text, e.g. "deliver 010 × 20", "map x → x + 3 (3-bit)", "Caesar +3 (text)".
func describe() -> String:
	match kind:
		"deliver":
			return "deliver %s × %d" % [_bin(value), count]
		"filter":
			var ki := _first_op("keep_if")
			var src := source_kind if source_kind != "" else "x"
			if ki.is_empty():
				return "filter × %d" % count
			return "keep %s %s %d" % [src, str(ki.get("cmp", ">")), int(ki.get("k", 0))]
		"paired":
			return "paired × %d" % count
		_:
			if _is_caesar():
				return "Caesar +%d (%s)" % [int(_first_op("add").get("k", 0)), _format_name()]
			return "map x → %s (%s)" % [_expr(), _format_name()]


func _format_name() -> String:
	match accept_format:
		"text": return "text"
		"number": return "number"
		_: return "%d-bit" % accept_width


func _is_caesar() -> bool:
	if ops.size() < 3 or ops.size() > 4:
		return false
	if str(ops[0].get("op", "")) != "encode_char" or str(ops[1].get("op", "")) != "add":
		return false
	return str(ops[ops.size() - 1].get("op", "")) == "decode_char"


func _expr() -> String:
	var e := "x"
	for op in ops:
		var k := int(op.get("k", 0))
		match str(op.get("op", "")):
			"add": e = "%s + %d" % [e, k]
			"sub": e = "%s − %d" % [e, k]
			"mul": e = "%s × %d" % [e, k]
			"mod": e = "%s mod %d" % [e, k]
			"slice": e = "low %d bits of %s" % [int(op.get("len", 1)), e]
			"encode_num": e = "enc%d(%s)" % [int(op.get("width", 1)), e]
			"encode_char": e = "chr(%s)" % e
			"decode_num": e = "num(%s)" % e
			"decode_char": e = "chr(%s)" % e
	return e


func _first_op(op_name: String) -> Dictionary:
	for op in ops:
		if str(op.get("op", "")) == op_name:
			return op
	return {}


func _bin(v: Variant) -> String:
	if not (v is BitVector):
		return "?"
	var b := v as BitVector
	var s := ""
	for k in range(b.width - 1, -1, -1):
		s += "1" if b.bit(k) != 0 else "0"
	return s
