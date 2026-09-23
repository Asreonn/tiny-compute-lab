class_name BitVector
extends RefCounted
## Core value model: immutable (width, bits) pair. The ONLY core value type —
## docs/ARCHITECTURE.md §0/§3.1. Pure data: no Node, no rendering.
## There is NO default width: every constructor takes an explicit width
## (except from_bin/from_bool which derive it from the input).

var width: int
var bits: int


func _init(p_width: int, p_bits: int = 0) -> void:
	width = p_width
	if width < 1:
		push_error("BitVector: invalid width %d (clamped to 1)" % width)
		width = 1
	elif width > 64:
		push_error("BitVector: invalid width %d (clamped to 64)" % width)
		width = 64
	bits = p_bits & _mask(width)


## Mask for a width: all ones for 64 bits, (1 << w) - 1 otherwise.
static func _mask(w: int) -> int:
	return -1 if w >= 64 else ((1 << w) - 1)


# --- Construct --------------------------------------------------------------

static func of(value: int, p_width: int) -> BitVector:
	return BitVector.new(p_width, value)


static func from_bin(text: String) -> BitVector:
	var t := text.replace(" ", "").replace("_", "").replace("0b", "").replace("0B", "")
	for c in t:
		if c != "0" and c != "1":
			push_error("BitVector.from_bin: invalid digit '%s' in \"%s\"" % [c, text])
			return zero(1)
	var v := 0
	for c in t:
		v = (v << 1) | (1 if c == "1" else 0)
	return BitVector.new(t.length(), v)


static func from_bool(b: bool) -> BitVector:
	return BitVector.new(1, 1 if b else 0)


static func zero(w: int) -> BitVector:
	return BitVector.new(w, 0)


# --- Read -------------------------------------------------------------------

func unsigned() -> int:
	# Raw int at width 64 (two's complement storage IS the unsigned value there).
	return bits


func signed() -> int:
	if width == 64:
		return bits
	var sign := 1 << (width - 1)
	return bits - (1 << width) if (bits & sign) != 0 else bits


## Truth value of a control signal: any bit set. (Control ports are width 1.)
func as_bool() -> bool:
	return bits != 0


func bit(i: int) -> int:
	if i < 0 or i >= width:
		push_error("BitVector.bit: index %d out of range for width %d" % [i, width])
		return 0
	return 1 if ((bits >> i) & 1) != 0 else 0


func with_bit(i: int, v: bool) -> BitVector:
	if i < 0 or i >= width:
		push_error("BitVector.with_bit: index %d out of range for width %d" % [i, width])
		return BitVector.new(width, bits)
	var b := bits | (1 << i) if v else bits & ~(1 << i)
	return BitVector.new(width, b)


func popcount() -> int:
	var n := 0
	for i in range(width):
		n += (bits >> i) & 1
	return n


func is_zero() -> bool:
	return bits == 0


func equals(other: BitVector) -> bool:
	return other != null and other.width == width and other.bits == bits


func _to_string() -> String:
	var out := ""
	for i in range(width - 1, -1, -1):
		out += "1" if ((bits >> i) & 1) != 0 else "0"
	return "%d'b%s" % [width, out]


# --- Compare ----------------------------------------------------------------

## Unsigned int64 comparison of raw storage (sign bit set => larger unsigned).
static func _u64_cmp(a: int, b: int) -> int:
	if a == b:
		return 0
	if (a < 0) != (b < 0):
		return 1 if a < 0 else -1
	return -1 if a < b else 1


func ucmp(other: Variant) -> int:
	var o := _coerce(other)
	if width == 64:
		return _u64_cmp(bits, o.bits)
	return -1 if unsigned() < o.unsigned() else (1 if unsigned() > o.unsigned() else 0)


func scmp(other: Variant) -> int:
	var o := _coerce(other)
	var a := signed()
	var b := o.signed()
	return -1 if a < b else (1 if a > b else 0)


## Int operands convert with of(int, self.width); a BitVector of another width
## is a programming error — push_error and mask its bits to self.width.
func _coerce(other: Variant) -> BitVector:
	if typeof(other) == TYPE_INT:
		return BitVector.of(other, width)
	if other is BitVector:
		if other.width != width:
			push_error("BitVector: width mismatch %d vs %d — masking operand to %d" % [width, other.width, width])
			return BitVector.new(width, other.bits)
		return other
	push_error("BitVector: cannot coerce operand of type %s" % str(typeof(other)))
	return BitVector.zero(width)


# --- Arithmetic (wraps at width) ---------------------------------------------

func add(other: Variant) -> BitVector:
	return BitVector.new(width, bits + _coerce(other).bits)


func sub(other: Variant) -> BitVector:
	return BitVector.new(width, bits - _coerce(other).bits)


func mul(other: Variant) -> BitVector:
	return BitVector.new(width, bits * _coerce(other).bits)


func neg() -> BitVector:
	return BitVector.new(width, -bits)


func add_carry(other: Variant) -> Dictionary:
	var o := _coerce(other)
	if width == 64:
		# Unsigned-overflow detection: carry when the modular sum is less than
		# the addend in unsigned 64-bit terms.
		var s: int = bits + o.bits
		return {"value": BitVector.new(64, s), "carry": 1 if _u64_cmp(s, bits) < 0 else 0}
	var s: int = unsigned() + o.unsigned()
	return {"value": BitVector.new(width, s), "carry": 1 if s >= (1 << width) else 0}


func sub_borrow(other: Variant) -> Dictionary:
	var o := _coerce(other)
	if width == 64:
		var b: int = bits - o.bits
		return {"value": BitVector.new(64, b), "borrow": 1 if _u64_cmp(bits, o.bits) < 0 else 0}
	var borrow := 1 if unsigned() < o.unsigned() else 0
	return {"value": BitVector.new(width, unsigned() - o.unsigned()), "borrow": borrow}


## Unsigned division and modulo. Width 64 with the top bit set is not supported yet
## (GDScript has no unsigned 64-bit division); gameplay widths are far below that.
func umod(k: Variant) -> BitVector:
	var kv: int = _coerce(k).unsigned()
	if kv == 0:
		push_error("BitVector.umod: division by zero")
		return BitVector.zero(width)
	return BitVector.of(unsigned() % kv, width)


func udiv(k: Variant) -> BitVector:
	var kv: int = _coerce(k).unsigned()
	if kv == 0:
		push_error("BitVector.udiv: division by zero")
		return BitVector.zero(width)
	return BitVector.of(unsigned() / kv, width)


# --- Bitwise ----------------------------------------------------------------

func band(other: Variant) -> BitVector:
	return BitVector.new(width, bits & _coerce(other).bits)


func bor(other: Variant) -> BitVector:
	return BitVector.new(width, bits | _coerce(other).bits)


func bxor(other: Variant) -> BitVector:
	return BitVector.new(width, bits ^ _coerce(other).bits)


func bnot() -> BitVector:
	return BitVector.new(width, ~bits)


## Logical shift left: bits leave the width, zeros enter from the right.
func shl(n: int) -> BitVector:
	if n < 0:
		push_error("BitVector.shl: negative shift %d" % n)
		n = 0
	if n >= width:
		return BitVector.zero(width)
	return BitVector.new(width, bits << n)


## Logical shift right: zeros enter from the left.
func shr(n: int) -> BitVector:
	if n < 0:
		push_error("BitVector.shr: negative shift %d" % n)
		n = 0
	if n >= width:
		return BitVector.zero(width)
	if width == 64:
		return BitVector.new(64, (bits >> n) & _mask(64 - n))
	return BitVector.new(width, unsigned() >> n)


## Arithmetic shift right: the sign bit is replicated.
func sar(n: int) -> BitVector:
	if n < 0:
		push_error("BitVector.sar: negative shift %d" % n)
		n = 0
	if n >= width:
		return BitVector.of(-1, width) if signed() < 0 else BitVector.zero(width)
	if width == 64:
		return BitVector.new(64, bits >> n)
	return BitVector.new(width, signed() >> n)


# --- Width ops (the only way width changes) -----------------------------------

func zero_extend(w: int) -> BitVector:
	if w < width:
		push_error("BitVector.zero_extend: target width %d < %d" % [w, width])
		return BitVector.new(width, bits)
	if w > 64:
		push_error("BitVector: width %d out of range" % w)
		w = 64
	return BitVector.new(w, bits)


func sign_extend(w: int) -> BitVector:
	if w < width:
		push_error("BitVector.sign_extend: target width %d < %d" % [w, width])
		return BitVector.new(width, bits)
	if w > 64:
		push_error("BitVector: width %d out of range" % w)
		w = 64
	return BitVector.new(w, signed())


func truncate(w: int) -> BitVector:
	if w > width:
		push_error("BitVector.truncate: target width %d > %d" % [w, width])
		return BitVector.new(width, bits)
	return BitVector.new(w, bits)


## Slice count bits starting at bit lo (LSB-indexed); result width == count.
func slice(lo: int, count: int) -> BitVector:
	if lo < 0 or count < 1 or lo + count > width or lo + count > 64:
		push_error("BitVector.slice: lo %d count %d invalid for width %d" % [lo, count, width])
		return BitVector.zero(width)
	return BitVector.new(count, (bits >> lo) & _mask(count))


## Concatenate: self is the low bits, high is prepended.
func concat(high: BitVector) -> BitVector:
	if high == null:
		push_error("BitVector.concat: null operand")
		return BitVector.new(width, bits)
	var w := width + high.width
	if w > 64:
		push_error("BitVector.concat: total width %d > 64" % w)
		return BitVector.new(width, bits)
	var v: int = (high.bits << width) | bits
	return BitVector.new(w, v)