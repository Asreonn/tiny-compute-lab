class_name Charset
extends RefCounted
## Character interpretation of bits. Width decides the charset — docs/ARCHITECTURE.md §3.3.
## Widths 1-6: TCL-5 on the low 5 bits. Widths 7-64: ASCII on the low 8 bits.

## TCL-5: 0-25 = A-Z, 26 = space, 27 = ".", 28 = ",", 29 = "!", 30 = "?", 31 = "-".
const TCL5 := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", " ", ".", ",", "!", "?", "-"]


static func _tcl_index(ch: String) -> int:
	for i in range(TCL5.size()):
		if TCL5[i] == ch:
			return i
	return -1


static func decode(bv: BitVector) -> String:
	if bv == null:
		return ""
	if bv.width <= 6:
		return TCL5[bv.unsigned() & 31]
	var code := bv.unsigned() & 0xFF
	if code >= 32 and code <= 126:
		return String.chr(code)
	return "\\x%02X" % code


## Inverse of decode. Returns null when the character is not representable in
## the charset, or when the code does not fit the width.
static func encode(ch: String, width: int) -> BitVector:
	var code := -1
	if ch.length() == 1:
		var c := ch.unicode_at(0)
		if c >= 32 and c <= 126:
			code = c
	if code < 0 and ch.length() == 4 and ch.begins_with("\\x"):
		var h := ch.substr(2, 2).to_upper()
		if h.is_valid_hex_number():
			code = h.hex_to_int()
	if code < 0:
		return null
	if width <= 6:
		var i := _tcl_index(ch)
		if i < 0:
			return null
		code = i
		if code >= (1 << width):
			return null
		return BitVector.of(code, width)
	if width < 8 and code >= (1 << width):
		return null
	return BitVector.of(code, width)