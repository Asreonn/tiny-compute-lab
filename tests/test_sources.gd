class_name SourceTests
extends RefCounted
## Job C5 acceptance tests: structured remote-source records (DATA_FACTORY §5). The three
## fictional sources share one population, so records of the same seq correlate; the Database
## Dump stick streams the same generator. Each case calls t.check(cond, what); run() is invoked
## from tests/run_tests.gd.

static func run(t) -> void:
	_sources(t)
	_determinism(t)
	_field_ranges(t)
	_correlation(t)
	_noise(t)
	_dump_stick(t)
	_dump_socket(t)


## 1. The three sources load; widths 16/16/32; the field widths sum to the record width.
static func _sources(t) -> void:
	var forum := SourceStream.source("forumcache")
	var shop := SourceStream.source("shopmirror")
	var archive := SourceStream.source("archivenode")
	t.check(forum != null and shop != null and archive != null, "the three remote sources load")
	t.check(SourceStream.source("nope") == null, "an unknown source id is null")
	t.check(forum != null and forum.width == 16 and shop != null and shop.width == 16 and archive != null and archive.width == 32, "source widths are 16/16/32")
	var pop := SourceStream.population()
	t.check(pop != null and pop.count == 63 and pop.seed == 7741, "the shared population loads (count %d, seed %d)" % [pop.count if pop != null else -1, pop.seed if pop != null else -1])
	var defs: Array[RemoteSourceDef] = [forum, shop, archive]
	for d in defs:
		var sum := 0
		for f in d.fields:
			sum += int(f["width"])
		t.check(sum == d.width, "%s: field widths sum to the record width (%d vs %d)" % [d.id, sum, d.width])


## 2. record() is a pure function: the same seq gives the same BitVector, and consecutive
## records differ.
static func _determinism(t) -> void:
	var forum := SourceStream.source("forumcache")
	var pop := SourceStream.population()
	var a := SourceStream.record(forum, pop, 5)
	var b := SourceStream.record(forum, pop, 5)
	t.check(a.equals(b), "record(def, pop, 5) equals itself on a second call")
	var diff := 0
	for seq in range(49):
		if not SourceStream.record(forum, pop, seq).equals(SourceStream.record(forum, pop, seq + 1)):
			diff += 1
	t.check(diff >= 40, "records 0..49 differ from their successor in %d/49" % diff)


## 3. field_ranges decodes the 16-bit forum layout MSB first.
static func _field_ranges(t) -> void:
	var forum := SourceStream.source("forumcache")
	var ranges := SourceStream.field_ranges(forum)
	t.check(ranges.size() == 4, "forum has 4 fields (got %d)" % ranges.size())
	if ranges.size() != 4:
		return
	t.check(str(ranges[0]["name"]) == "USER_TAG" and int(ranges[0]["hi"]) == 15 and int(ranges[0]["lo"]) == 10, "USER_TAG is 15..10")
	t.check(str(ranges[1]["name"]) == "REGION" and int(ranges[1]["hi"]) == 9 and int(ranges[1]["lo"]) == 7, "REGION is 9..7")
	t.check(str(ranges[2]["name"]) == "ACTIVITY" and int(ranges[2]["hi"]) == 6 and int(ranges[2]["lo"]) == 3, "ACTIVITY is 6..3")
	t.check(str(ranges[3]["name"]) == "FLAGS" and int(ranges[3]["hi"]) == 2 and int(ranges[3]["lo"]) == 0, "FLAGS is 2..0")


## 4. Correlation over seq 0..399: forum USER_TAG is the session identity in >= 90 % (5 % tag
## noise); shop USER_TAG (70 % same-identity, no tag noise) matches forum in 55 %..85 %.
static func _correlation(t) -> void:
	var forum := SourceStream.source("forumcache")
	var shop := SourceStream.source("shopmirror")
	var pop := SourceStream.population()
	var same_session := 0
	var shop_matches_forum := 0
	for seq in range(400):
		var ft := SourceStream.field(forum, SourceStream.record(forum, pop, seq), "USER_TAG")
		if ft == SourceStream.session_identity(pop, seq):
			same_session += 1
		var st := SourceStream.field(shop, SourceStream.record(shop, pop, seq), "USER_TAG")
		if st == ft:
			shop_matches_forum += 1
	t.check(same_session >= 360, "forum USER_TAG matches the session identity in %d/400 (>= 360)" % same_session)
	t.check(shop_matches_forum >= 220 and shop_matches_forum <= 340, "shop USER_TAG matches forum in %d/400 (220..340)" % shop_matches_forum)


## 5. Noise over seq 0..999: forum INVALID (bit 0) in 6 %..14 %; archive CHECK wrong in
## 6 %..14 %; forum REGION matches its identity's region in >= 85 % of non-anonymous records.
static func _noise(t) -> void:
	var forum := SourceStream.source("forumcache")
	var archive := SourceStream.source("archivenode")
	var pop := SourceStream.population()
	var invalid := 0
	var check_wrong := 0
	var region_ok := 0
	var region_total := 0
	for seq in range(1000):
		var fr := SourceStream.record(forum, pop, seq)
		if fr.bit(0) == 1:
			invalid += 1
		var ft := SourceStream.field(forum, fr, "USER_TAG")
		if ft != 0:
			region_total += 1
			var a := SourceStream.attributes(pop, ft)
			if SourceStream.field(forum, fr, "REGION") == int(a["region"]):
				region_ok += 1
		var ar := SourceStream.record(archive, pop, seq)
		var tag := SourceStream.field(archive, ar, "USER_TAG")
		var fresh := SourceStream.field(archive, ar, "FRESHNESS")
		var qual := SourceStream.field(archive, ar, "QUALITY")
		var check := SourceStream.field(archive, ar, "CHECK")
		if check != (((tag ^ fresh ^ qual) + 5) & 15):
			check_wrong += 1
	t.check(invalid >= 60 and invalid <= 140, "forum INVALID bit set in %d/1000 (60..140)" % invalid)
	t.check(check_wrong >= 60 and check_wrong <= 140, "archive CHECK wrong in %d/1000 (60..140)" % check_wrong)
	t.check(region_total > 0 and region_ok * 100 >= region_total * 85, "forum REGION matches its identity in %d/%d (>= 85 %%)" % [region_ok, region_total])


## 6. The Database Dump stick streams the first 64 forum records, unchanged from the live feed.
static func _dump_stick(t) -> void:
	var forum := SourceStream.source("forumcache")
	var pop := SourceStream.population()
	var stream := Devices.make_stream("dump", {"source": "forumcache", "count": 64})
	t.check(stream.size() == 64, "the dump stick carries 64 records (got %d)" % stream.size())
	t.check(stream.size() == 64 and stream[0] is BitVector and (stream[0] as BitVector).width == 16, "dump records are 16-bit BitVectors")
	t.check(stream.size() > 7 and (stream[7] as BitVector).equals(SourceStream.record(forum, pop, 7)), "dump record 7 equals the live record 7")


## 7. Integration: a lab socket with the dump stick emits the records with ctx 0..3.
static func _dump_socket(t) -> void:
	var sim := Simulation.new()
	sim.size = Vector2i(20, 12)
	var src := sim.place("usb_input", Vector2i(1, 5), 0, {}, 3)
	src.socket = true
	t.check(sim.insert_device(src.id, "dump", {"source": "forumcache", "count": 4}), "the Dump stick plugs into a socket")
	t.check(src.width == 16, "the socket width becomes 16 (got %d)" % src.width)
	var out := sim.place("usb_output", Vector2i(9, 5), 0, {}, 1)
	t.check(sim.connect_ports(src.id, "out", out.id, "in") != null, "the dump socket wires to the USB Output")
	sim.reset_run()
	for i in 120:
		sim.step()
		if out.received.size() >= 4:
			break
	t.check(out.received.size() >= 4, "the socket emitted at least 4 values (got %d)" % out.received.size())
	if out.received.size() < 4:
		return
	var ctxs: Array = []
	for k in 4:
		ctxs.append((out.received[k] as Packet).ctx)
	t.check(ctxs == [0, 1, 2, 3], "the first four packets carry ctx 0..3 (got %s)" % [ctxs])