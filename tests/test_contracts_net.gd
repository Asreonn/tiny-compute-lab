class_name NetContractTests
extends RefCounted
## C9a: contracts over records (DATA_FACTORY §9) — route, correlate, conditions, compose / score,
## the Dump stick's source stamp, worth and max_components.


static func run(t) -> void:
	_route(t)
	_no_record(t)
	_correlate(t)
	_score(t)
	_conditions(t)
	_dump_stamp(t)
	_fields(t)


static func _rec(id: String, seq: int) -> BitVector:
	return SourceStream.record(SourceStream.source(id), SourceStream.population(), seq)


## A packet carrying one record per [source, seq] pair (origins keyed 100, 101, …).
static func _packet(entries: Array) -> Packet:
	var first: BitVector = _rec(str(entries[0][0]), int(entries[0][1]))
	var p := Packet.new(1, first, 0)
	var k := 100
	for e in entries:
		p.origins[k] = {"source": str(e[0]), "seq": int(e[1]), "value": _rec(str(e[0]), int(e[1]))}
		k += 1
	return p


static func _region(seq: int) -> int:
	return SourceStream.field(SourceStream.source("forumcache"), _rec("forumcache", seq), "REGION")


## 1. route by REGION: A takes REGION < 6, B the rest; the other output expects DROP.
static func _route(t) -> void:
	var c := Contract.from_level({"contract": {"kind": "route", "outputs": {
		"A": [{"op": "when", "cond": {"op": "lt", "a": ["forumcache", "REGION"], "k": 6}}],
		"B": [{"op": "when", "cond": {"op": "ge", "a": ["forumcache", "REGION"], "k": 6}}]}}})
	var ok := true
	for s in 40:
		var p := _packet([["forumcache", s]])
		var low := _region(s) < 6
		var ea: Variant = c.expected_for(p, [], "A")
		var eb: Variant = c.expected_for(p, [], "B")
		var a_ok: bool = (ea is BitVector and (ea as BitVector).equals(p.data)) if low else (ea is String)
		var b_ok: bool = (eb is String) if low else (eb is BitVector and (eb as BitVector).equals(p.data))
		if not (a_ok and b_ok and c.judge(p, [], "A") == low and c.judge(p, [], "B") == not low):
			ok = false
	t.check(ok, "route sends REGION < 6 to A only and the rest to B only")
	t.check(c.expected_for(_packet([["forumcache", 0]]), [], "C") is String, "an unknown output key expects DROP")
	t.check(c.describe() == "route: A, B", "route describe (%s)" % c.describe())


## 2. A value with no record origin cannot be judged.
static func _no_record(t) -> void:
	var c := Contract.from_level({"contract": {"kind": "route", "outputs": {"A": []}}})
	var p := Packet.new(1, BitVector.of(5, 16), 0)
	t.check(c.expected_for(p, [], "A") == null, "no record origin → unjudgeable (null)")


## 3. correlate Forum + Shop: TAG ≠ 0, equal TAG, equal REGION → TAG·ACTIVITY·SPEND·CAT.
static func _correlate(t) -> void:
	var c := Contract.from_level({"contract": {"kind": "correlate", "sources": ["forumcache", "shopmirror"],
		"match": [{"op": "ne", "a": ["forumcache", "USER_TAG"], "k": 0},
			{"op": "eq", "a": ["forumcache", "USER_TAG"], "b": ["shopmirror", "USER_TAG"]},
			{"op": "eq", "a": ["forumcache", "REGION"], "b": ["shopmirror", "REGION"]}],
		"compose": [["forumcache", "USER_TAG"], ["forumcache", "ACTIVITY"], ["shopmirror", "SPEND"], ["shopmirror", "CATEGORY"]]}})
	var forum := SourceStream.source("forumcache")
	var shop := SourceStream.source("shopmirror")
	var hit := -1
	var miss := -1
	for s in 300:
		var ft := SourceStream.field(forum, _rec("forumcache", s), "USER_TAG")
		var st := SourceStream.field(shop, _rec("shopmirror", s), "USER_TAG")
		var fr := SourceStream.field(forum, _rec("forumcache", s), "REGION")
		var sr := SourceStream.field(shop, _rec("shopmirror", s), "REGION")
		if hit < 0 and ft != 0 and ft == st and fr == sr:
			hit = s
		if miss < 0 and ft != st:
			miss = s
	t.check(hit >= 0 and miss >= 0, "the sample has a matching and a non-matching session (%d, %d)" % [hit, miss])
	if hit < 0 or miss < 0:
		return
	var e: Variant = c.expected_for(_packet([["forumcache", hit], ["shopmirror", hit]]), [])
	var tag := SourceStream.field(forum, _rec("forumcache", hit), "USER_TAG")
	t.check(e is BitVector and (e as BitVector).width == 17 and ((e as BitVector).unsigned() >> 11) == tag, "a match composes TAG·ACTIVITY·SPEND·CAT (17 bits, TAG on top)")
	t.check(c.expected_for(_packet([["forumcache", miss], ["shopmirror", miss]]), []) is String, "different tags → DROP")
	t.check(c.expected_for(_packet([["forumcache", hit], ["shopmirror", hit + 1]]), []) == null, "records of different sessions → unjudgeable")
	t.check(c.expected_for(_packet([["forumcache", hit]]), []) == null, "a missing source → unjudgeable")


## 4. score: +1 ACTIVITY ≥ 8, +4 INVALID bit, as a 4-bit field.
static func _score(t) -> void:
	var c := Contract.from_level({"contract": {"kind": "correlate", "sources": ["forumcache"], "compose": [["score", [
		[{"op": "ge", "a": ["forumcache", "ACTIVITY"], "k": 8}, 1],
		[{"op": "bit", "a": ["forumcache", "FLAGS"], "k": 0}, 4]], 4]]}})
	var forum := SourceStream.source("forumcache")
	var ok := true
	for s in 40:
		var r := _rec("forumcache", s)
		var want := (1 if SourceStream.field(forum, r, "ACTIVITY") >= 8 else 0) + (4 if SourceStream.field(forum, r, "FLAGS") & 1 == 1 else 0)
		var e: Variant = c.expected_for(_packet([["forumcache", s]]), [])
		if not (e is BitVector and (e as BitVector).width == 4 and (e as BitVector).unsigned() == want):
			ok = false
	t.check(ok, "score sums the weights of the conditions that hold")


## 5. all / any / not.
static func _conditions(t) -> void:
	var c := Contract.new()
	var p := _packet([["forumcache", 3]])
	c._recs = Contract.records_of(p)
	var region := _region(3)
	var eq := {"op": "eq", "a": ["forumcache", "REGION"], "k": region}
	var ne := {"op": "ne", "a": ["forumcache", "REGION"], "k": region}
	t.check(c.cond(eq) and not c.cond(ne), "eq / ne on a field")
	t.check(c.cond({"op": "all", "of": [eq, eq]}) and not c.cond({"op": "all", "of": [eq, ne]}), "all")
	t.check(c.cond({"op": "any", "of": [ne, eq]}) and not c.cond({"op": "any", "of": [ne]}), "any")
	t.check(c.cond({"op": "not", "c": ne}), "not")
	t.check(not c.cond({"op": "eq", "a": ["shopmirror", "REGION"], "k": 0}), "a missing record makes a comparison false")


## 6. The Dump stick stamps its records with their source.
static func _dump_stamp(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	sim.insert_device(src.id, "dump", {"source": "forumcache", "count": 4})
	var out := sim.place("usb_output", Vector2i(9, 5), 0, {}, 1)
	sim.connect_ports(src.id, "out", out.id, "in")
	sim.reset_run()
	for i in 80:
		sim.step()
		if not out.received.is_empty():
			break
	var got := not out.received.is_empty() and str(((out.received[0] as Packet).origins.get(src.id, {}) as Dictionary).get("source", "")) == "forumcache"
	t.check(got, "a dump record carries origins source = forumcache")
	if not out.received.is_empty():
		t.check(Contract.records_of(out.received[0]).has("forumcache"), "records_of finds the dump record")


## 7. worth / max_components parse with defaults.
static func _fields(t) -> void:
	var c := Contract.from_level({"contract": {"kind": "correlate", "worth": 3, "max_components": 60}})
	var d := Contract.from_level({"contract": {"kind": "deliver", "value": "010"}})
	t.check(c.worth == 3 and c.max_components == 60 and d.worth == 1 and d.max_components == -1, "worth and max_components parse (defaults 1 / -1)")
