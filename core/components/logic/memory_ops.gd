class_name MemoryOps
extends RefCounted
## Pure helpers shared by the memory / compute machines and the contracts that judge them.


## ALU operation by name at a's width (ADD / SUB wrap, AND / OR / XOR bitwise).
static func alu(op: String, a: BitVector, b: BitVector) -> BitVector:
	match op:
		"SUB": return a.sub(b.unsigned())
		"AND": return a.band(b)
		"OR": return a.bor(b)
		"XOR": return a.bxor(b)
	return a.add(b.unsigned())
