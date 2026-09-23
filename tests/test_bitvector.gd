class_name BitVectorTests
extends RefCounted
## Slice A1 acceptance tests: BitVector, ViewMode and Charset.
## Each case calls t.check(cond, what); run() is invoked from tests/run_tests.gd.

static func run(t) -> void:
	_three_bit(t)
	_five_bit(t)
	_eight_bit(t)
	_width_ops(t)
	_parse(t)
	_misc(t)


# --- 3-bit --------------------------------------------------------------------

static func _three_bit(t) -> void:
	var a := BitVector.from_bin("010")
	var b := BitVector.from_bin("010")
	var r := a.add(b)
	t.check(r.equals(BitVector.from_bin("100")), "3-bit 010+010 == 100")
	t.check(ViewMode.format(r, ViewMode.Mode.BIN) == "100", "3-bit 010+010 formats as BIN 100")
	var r2 := BitVector.from_bin("011").add(BitVector.from_bin("010"))
	t.check(r2.equals(BitVector.from_bin("101")), "3-bit 011+010 == 101")
	t.check(ViewMode.format(r2, ViewMode.Mode.BIN) == "101", "3-bit 011+010 formats as BIN 101")
	var r3 := BitVector.from_bin("100").add(BitVector.from_bin("010"))
	t.check(r3.equals(BitVector.from_bin("110")), "3-bit 100+010 == 110")
	t.check(ViewMode.format(r3, ViewMode.Mode.BIN) == "110", "3-bit 100+010 formats as BIN 110")
	var c1 := BitVector.from_bin("111").add_carry(BitVector.from_bin("001"))
	t.check(c1["value"].equals(BitVector.from_bin("000")), "add_carry(111,001) value == 000")
	t.check(c1["carry"] == 1, "add_carry(111,001) carry == 1")
	t.check(BitVector.from_bin("010").add_carry(BitVector.from_bin("010"))["carry"] == 0, "add_carry(010,010) carry == 0")
	t.check(BitVector.of(9, 3).equals(BitVector.from_bin("001")), "of(9,3) masks to 001")
	t.check(BitVector.of(-1, 3).equals(BitVector.from_bin("111")), "of(-1,3) is two's-complement 111")
	t.check(BitVector.from_bin("111").signed() == -1, "signed(111) == -1")
	var sb := BitVector.from_bin("000").sub_borrow(BitVector.from_bin("001"))
	t.check(sb["value"].equals(BitVector.from_bin("111")), "sub_borrow(000,001) value == 111")
	t.check(sb["borrow"] == 1, "sub_borrow(000,001) borrow == 1")
	t.check(BitVector.from_bin("100").ucmp(BitVector.from_bin("011")) == 1, "ucmp(100,011) == 1")
	t.check(BitVector.from_bin("100").scmp(BitVector.from_bin("011")) == -1, "scmp(100,011) == -1")
	t.check(BitVector.from_bin("111").umod(3).equals(BitVector.from_bin("001")), "umod(111,3) == 001")
	var v := BitVector.from_bin("100")
	t.check(ViewMode.format(v, ViewMode.Mode.BIN) == "100", "3-bit 100 BIN == \"100\"")
	t.check(ViewMode.format(v, ViewMode.Mode.UDEC) == "4", "3-bit 100 UDEC == \"4\"")
	t.check(ViewMode.format(v, ViewMode.Mode.HEX) == "0x4", "3-bit 100 HEX == \"0x4\"")
	t.check(ViewMode.format(v, ViewMode.Mode.SDEC) == "\u22124", "3-bit 100 SDEC == \"−4\"")
	t.check(ViewMode.format(v, ViewMode.Mode.TYPE) == "BITS\u00b73", "3-bit 100 TYPE == \"BITS·3\"")


# --- 5-bit --------------------------------------------------------------------

static func _five_bit(t) -> void:
	t.check(Charset.decode(BitVector.of(0, 5)) == "A", "TCL-5 code 0 decodes to A")
	t.check(BitVector.of(25, 5).equals(BitVector.from_bin("11001")), "TCL-5 Z == 11001")
	t.check(ViewMode.format(BitVector.from_bin("11001"), ViewMode.Mode.BIN) == "1 1001", "5-bit 11001 BIN == \"1 1001\"")
	t.check(BitVector.of(26, 5).equals(BitVector.from_bin("11010")), "TCL-5 space == 11010")
	t.check(Charset.decode(BitVector.of(26, 5)) == " ", "TCL-5 code 26 decodes to space")
	t.check(Charset.encode("H", 5).equals(BitVector.from_bin("00111")), "encode(\"H\",5) == 00111")
	var caesar := BitVector.of(23, 5).add(BitVector.of(3, 5))
	t.check(caesar.unsigned() == 26, "X(23)+3 in 5 bits == 26")
	t.check(ViewMode.format(caesar, ViewMode.Mode.CHAR) == " ", "X+3 CHAR == \" \"")
	var modulo := caesar.umod(26)
	t.check(modulo.unsigned() == 0, "(23+3) umod 26 == 0")
	t.check(Charset.decode(modulo) == "A", "(23+3) umod 26 CHAR == \"A\"")
	var roundtrip_fails := 0
	for code in range(32):
		var ch := Charset.decode(BitVector.of(code, 5))
		var back := Charset.encode(ch, 5)
		if back == null or not back.equals(BitVector.of(code, 5)):
			roundtrip_fails += 1
	t.check(roundtrip_fails == 0, "TCL-5 decode/encode round-trips all 32 codes")


# --- 8-bit --------------------------------------------------------------------

static func _eight_bit(t) -> void:
	var a := BitVector.from_bin("01000001")
	t.check(ViewMode.format(a, ViewMode.Mode.BIN) == "0100 0001", "8-bit 01000001 BIN == \"0100 0001\"")
	t.check(ViewMode.format(a, ViewMode.Mode.UDEC) == "65", "8-bit 01000001 UDEC == \"65\"")
	t.check(ViewMode.format(a, ViewMode.Mode.HEX) == "0x41", "8-bit 01000001 HEX == \"0x41\"")
	t.check(ViewMode.format(a, ViewMode.Mode.CHAR) == "A", "8-bit 01000001 CHAR == \"A\"")
	t.check(BitVector.of(255, 8).add(BitVector.of(1, 8)).equals(BitVector.zero(8)), "8-bit 255+1 wraps to 0")
	t.check(BitVector.of(255, 8).add_carry(BitVector.of(1, 8))["carry"] == 1, "8-bit 255+1 carry == 1")
	t.check(Charset.decode(BitVector.of(10, 8)) == "\\x0A", "8-bit ASCII code 10 decodes to \"\\x0A\"")


# --- Width ops / shifts / 64-bit ------------------------------------------------

static func _width_ops(t) -> void:
	t.check(BitVector.from_bin("101").zero_extend(5).equals(BitVector.from_bin("00101")), "zero_extend 3->5 of 101 == 00101")
	t.check(BitVector.from_bin("101").sign_extend(5).equals(BitVector.from_bin("11101")), "sign_extend 3->5 of 101 == 11101")
	t.check(BitVector.from_bin("01000001").truncate(3).equals(BitVector.from_bin("001")), "truncate 8->3 of 01000001 == 001")
	var v6 := BitVector.from_bin("010011")
	t.check(v6.slice(0, 3).equals(BitVector.from_bin("011")), "slice(0,3) of 010011 == 011")
	t.check(v6.slice(3, 3).equals(BitVector.from_bin("010")), "slice(3,3) of 010011 == 010")
	t.check(BitVector.from_bin("011").concat(BitVector.from_bin("010")).equals(v6), "concat(low=011, high=010) round-trips 010011")
	t.check(BitVector.from_bin("101").shl(1).equals(BitVector.from_bin("010")), "3-bit 101 shl 1 == 010")
	t.check(BitVector.from_bin("101").shr(1).equals(BitVector.from_bin("010")), "3-bit 101 shr 1 == 010")
	t.check(BitVector.from_bin("101").sar(1).equals(BitVector.from_bin("110")), "3-bit 101 sar 1 == 110")
	t.check(BitVector.of(0x0F, 8).shl(4).equals(BitVector.of(0xF0, 8)), "8-bit 0x0F shl 4 == 0xF0")
	t.check(BitVector.of(0xF0, 8).shr(4).equals(BitVector.of(0x0F, 8)), "8-bit 0xF0 shr 4 == 0x0F")
	t.check(BitVector.of(0x80, 8).sar(7).equals(BitVector.of(0xFF, 8)), "8-bit 0x80 sar 7 == 0xFF")
	t.check(BitVector.of(-1, 64).add(1).equals(BitVector.zero(64)), "64-bit (-1)+1 wraps to zero")
	t.check(BitVector.of(-1, 64).add_carry(1)["carry"] == 1, "64-bit (-1)+1 has carry 1")


# --- Parse ---------------------------------------------------------------------

static func _parse(t) -> void:
	t.check(BitVector.from_bin("10").as_bool(), "as_bool is true when any bit is set (10)")
	t.check(not BitVector.zero(3).as_bool(), "as_bool of 000 is false")
	t.check(ViewMode.parse("-1", ViewMode.Mode.HEX, 3) == null, "HEX parse rejects a sign")
	var want := BitVector.from_bin("01000001")
	t.check(ViewMode.parse("0100 0001", ViewMode.Mode.BIN, 8).equals(want), "parse BIN \"0100 0001\" == 01000001")
	t.check(ViewMode.parse("65", ViewMode.Mode.UDEC, 8).equals(want), "parse UDEC \"65\" == 01000001")
	t.check(ViewMode.parse("0x41", ViewMode.Mode.HEX, 8).equals(want), "parse HEX \"0x41\" == 01000001")
	t.check(ViewMode.parse("A", ViewMode.Mode.CHAR, 8).equals(want), "parse CHAR \"A\" == 01000001")
	t.check(ViewMode.parse("8", ViewMode.Mode.UDEC, 3) == null, "parse \"8\" UDEC width 3 is null")
	t.check(ViewMode.parse("\u22124", ViewMode.Mode.SDEC, 3).equals(BitVector.from_bin("100")), "parse SDEC \"−4\" width 3 == 100")
	t.check(ViewMode.parse("0b010", ViewMode.Mode.BIN, 3).equals(BitVector.from_bin("010")), "parse BIN \"0b010\" width 3 == 010")


# --- Misc / robustness ------------------------------------------------------------

static func _misc(t) -> void:
	t.check(BitVector.of(0b101, 3)._to_string() == "3'b101", "_to_string of 101 is \"3'b101\"")
	t.check(BitVector.of(0b101, 3).popcount() == 2, "popcount(101) == 2")
	t.check(BitVector.zero(3).is_zero(), "zero(3) is zero")
	t.check(BitVector.from_bool(true).width == 1 and BitVector.from_bool(true).as_bool(), "from_bool(true) is width-1, as_bool true")
	t.check(BitVector.zero(3).with_bit(2, true).equals(BitVector.from_bin("100")), "with_bit(2,true) of 000 == 100")
	t.check(BitVector.of(7, 3).udiv(3).equals(BitVector.of(2, 3)), "udiv(111,3) == 2")
	t.check(BitVector.of(0b101, 3).band(BitVector.of(0b011, 3)).equals(BitVector.of(0b001, 3)), "band 101&011 == 001")
	t.check(BitVector.of(0b101, 3).bor(BitVector.of(0b010, 3)).equals(BitVector.of(0b111, 3)), "bor 101|010 == 111")
	t.check(BitVector.of(0b101, 3).bxor(BitVector.of(0b011, 3)).equals(BitVector.of(0b110, 3)), "bxor 101^011 == 110")
	t.check(BitVector.zero(3).bnot().equals(BitVector.of(0b111, 3)), "bnot 000 == 111")
	t.check(BitVector.of(3, 3).mul(2).equals(BitVector.of(0b110, 3)), "mul 3*2 == 110")
	t.check(BitVector.of(1, 3).neg().equals(BitVector.of(0b111, 3)), "neg 001 == 111")
	t.check(BitVector.from_bin("100").ucmp(3) == 1, "ucmp with int operand converts via of(int, width)")
	t.check(BitVector.from_bin("111").scmp(-1) == 0, "scmp(111,-1) == 0")
	t.check(not BitVector.of(1, 3).equals(BitVector.of(1, 4)), "equals requires matching width")
	t.check(ViewMode.format(BitVector.from_bool(true), ViewMode.Mode.TYPE) == "BIT\u00b71", "TYPE of width-1 is \"BIT·1\"")
	t.check(ViewMode.format(BitVector.of(5, 5), ViewMode.Mode.TYPE, "CHR") == "CHR\u00b75", "TYPE hint replaces BITS (\"CHR·5\")")
	t.check(BitVector.zero(4).udiv(0).equals(BitVector.zero(4)), "udiv by zero returns zero")
	t.check(BitVector.zero(4).umod(0).equals(BitVector.zero(4)), "umod by zero returns zero")