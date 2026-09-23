class_name ViewMode
extends RefCounted
## Display-time interpretation of BitVector bits. REPRESENTATION != DATA:
## these functions format bits for display and never create or modify data.
## See docs/ARCHITECTURE.md §3.2.

enum Mode { BIN, UDEC, HEX, CHAR, SDEC, TYPE }

## Penpot Readout chip labels (CHR for CHAR).
const CHIPS := ["BIN", "DEC", "HEX", "CHR", "SDEC", "TYPE"]


static func chip(mode: int) -> String:
	if mode < 0 or mode >= CHIPS.size():
		return "?"
	return CHIPS[mode]


static func format(bv: BitVector, mode: int, hint := "") -> String:
	match mode:
		Mode.BIN:
			return _bin(bv)
		Mode.UDEC:
			return str(bv.unsigned())
		Mode.HEX:
			return _hex(bv)
		Mode.SDEC:
			return _sdec(bv)
		Mode.CHAR:
			return Charset.decode(bv)
		Mode.TYPE:
			var label := "BIT" if bv.width == 1 else (hint if hint != "" else "BITS")
			return "%s\u00b7%d" % [label, bv.width]
		_:
			push_error("ViewMode.format: unknown mode %d" % mode)
			return ""


static func parse(text: String, mode: int, width: int) -> BitVector:
	match mode:
		Mode.BIN:
			return _parse_bin(text, width)
		Mode.UDEC:
			return _parse_udec(text, width)
		Mode.HEX:
			return _parse_hex(text, width)
		Mode.SDEC:
			return _parse_sdec(text, width)
		Mode.CHAR:
			return Charset.encode(text, width)
		_:
			return null


# --- BIN ---------------------------------------------------------------------

## All width digits grouped by 4 from the LSB with single spaces
## (w3 "100", w5 "1 0110", w8 "0100 0001").
static func _bin(bv: BitVector) -> String:
	var digits := ""
	for i in range(bv.width - 1, -1, -1):
		digits += "1" if bv.bit(i) != 0 else "0"
	var groups := PackedStringArray()
	var i := digits.length()
	while i > 0:
		var start := maxi(i - 4, 0)
		groups.append(digits.substr(start, i - start))
		i = start
	groups.reverse()
	return " ".join(groups)


static func _parse_bin(text: String, width: int) -> BitVector:
	var t := text.replace(" ", "").replace("_", "").replace("0b", "").replace("0B", "")
	if t.length() != width:
		return null
	for c in t:
		if c != "0" and c != "1":
			return null
	return BitVector.from_bin(t)


# --- HEX ---------------------------------------------------------------------

## "0x" + ceil(w/4) upper-case digits.
static func _hex(bv: BitVector) -> String:
	var digits := ceili(float(bv.width) / 4.0)
	var out := ""
	for i in range(digits - 1, -1, -1):
		out += "0123456789ABCDEF"[(bv.bits >> (4 * i)) & 0xF]
	return "0x" + out


static func _parse_hex(text: String, width: int) -> BitVector:
	var t := text.strip_edges().trim_prefix("0x").trim_prefix("0X")
	if t.begins_with("-") or t.begins_with("+") or not t.is_valid_hex_number():
		return null
	var v := t.hex_to_int()
	if v < 0 or (width < 64 and v >= (1 << width)):
		return null
	return BitVector.of(v, width)


# --- UDEC / SDEC ---------------------------------------------------------------

static func _sdec(bv: BitVector) -> String:
	var v := bv.signed()
	return str(v) if v >= 0 else "\u2212" + str(-v)


static func _parse_udec(text: String, width: int) -> BitVector:
	if not text.is_valid_int():
		return null
	var v := text.to_int()
	if v < 0:
		return null
	if width < 64 and v >= (1 << width):
		return null
	return BitVector.of(v, width)


static func _parse_sdec(text: String, width: int) -> BitVector:
	if not text.replace("\u2212", "-").is_valid_int():
		return null
	var v := text.replace("\u2212", "-").to_int()
	if width < 64:
		if v < -(1 << (width - 1)) or v >= (1 << (width - 1)):
			return null
	return BitVector.of(v, width)