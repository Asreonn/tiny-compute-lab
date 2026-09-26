class_name SourceStream
extends RefCounted
## Deterministic record generator (DATA_FACTORY §5.3): record(def, pop, seq) is a pure function of
## (seeds, seq). No RNG state; the only stream state anywhere is the next seq.

## The sources and population are loaded lazily and cached (pure data, no Node).
static var _sources: Dictionary = {}
static var _sources_loaded := false
static var _population: PopulationDef = null


## 32-bit finaliser (MurmurHash3 fmix32). 32-bit masked arithmetic so results are identical on
## every platform.
static func h32(x: int) -> int:
	x = x & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	x = (((x >> 16) ^ x) * 0x45d9f3b) & 0xFFFFFFFF
	return ((x >> 16) ^ x) & 0xFFFFFFFF


## Hash of (seed, a, salt) -> 0 .. 2^32-1.
static func hash3(seed: int, a: int, salt: int) -> int:
	return h32(h32(h32(seed) ^ (a & 0xFFFFFFFF)) ^ ((salt * 0x9E3779B1) & 0xFFFFFFFF))


## Uniform in [0, 1).
static func unit(seed: int, a: int, salt: int) -> float:
	return float(hash3(seed, a, salt)) / 4294967296.0


## The RemoteSourceDef with `id`, null for an unknown id. Loads every resource in
## ContentDB.SOURCES_DIR once.
static func source(id: String) -> RemoteSourceDef:
	if not _sources_loaded:
		_sources_loaded = true
		for r in ContentDB.load_dir(ContentDB.SOURCES_DIR):
			if r is RemoteSourceDef:
				var def := r as RemoteSourceDef
				_sources[def.id] = def
	if not _sources.has(id):
		return null
	return _sources[id] as RemoteSourceDef


## The shared PopulationDef, loaded once (a default when the asset is missing).
static func population() -> PopulationDef:
	if _population == null:
		var p := load(ContentDB.POPULATION) as PopulationDef
		_population = p if p != null else PopulationDef.new()
	return _population


## The shared session identity of record `seq`: USER_TAG 1..count.
static func session_identity(pop: PopulationDef, seq: int) -> int:
	return 1 + hash3(pop.seed, seq, 1) % pop.count


## Which identity record `seq` is about: the shared session with probability p_same, otherwise a
## source-private identity.
static func record_identity(def: RemoteSourceDef, pop: PopulationDef, seq: int) -> int:
	if unit(def.seed, seq, 2) < def.p_same:
		return session_identity(pop, seq)
	return 1 + hash3(def.seed, seq, 3) % pop.count


## The fixed attributes of identity `ident`.
static func attributes(pop: PopulationDef, ident: int) -> Dictionary:
	return {
		"region": hash3(pop.seed, ident, 11) % (pop.region_max + 1),
		"activity": hash3(pop.seed, ident, 12) % (pop.activity_max + 1),
		"spend": hash3(pop.seed, ident, 13) % (pop.spend_max + 1),
		"category": hash3(pop.seed, ident, 14) % (pop.category_max + 1),
		"quality": hash3(pop.seed, ident, 15) % (pop.quality_max + 1),
	}


## The field values of record `seq` (field name -> int, each masked to its width).
static func field_values(def: RemoteSourceDef, pop: PopulationDef, seq: int) -> Dictionary:
	var out := {}
	var ident := record_identity(def, pop, seq)
	var a := attributes(pop, ident)
	var tag := 0
	var freshness := 0
	var quality := 0
	var check_k := -1
	var check_hit := false
	var check_j := 0
	for k in range(def.fields.size()):
		var f: Dictionary = def.fields[k]
		var n := str(f.get("name", ""))
		var w := int(f.get("width", 1))
		var mask := (1 << w) - 1
		var hit := unit(def.seed, seq, 100 + k) < float(def.noise.get(n, 0.0))
		var j := hash3(def.seed, seq, 200 + k)
		if n == "CHECK":
			check_k = k
			check_hit = hit
			check_j = j
			continue
		var v := 0
		match n:
			"USER_TAG":
				v = 0 if hit else ident
				tag = v
			"REGION":
				v = ((a.region + 1 + j % 7) % 8) if hit else a.region
			"ACTIVITY":
				v = clampi(a.activity + j % 3 - 1, 0, 15)
			"SPEND":
				v = clampi(a.spend + j % 5 - 2, 0, 31)
			"CATEGORY":
				v = a.category
			"QUALITY":
				v = a.quality
				quality = v
			"FRESHNESS":
				v = j % 16
				freshness = v
			_:
				if str(f.get("kind", "")) == "flags":
					var bits := 0
					var labels: Array = f.get("labels", [])
					for i in range(labels.size()):
						var label := str(labels[i])
						if unit(def.seed, seq, 300 + k * 8 + i) < float(def.noise.get(label, 0.0)):
							bits |= 1 << (w - 1 - i)
					v = bits
				else:
					v = j & mask
		out[n] = v & mask
	# CHECK is computed LAST, from this record's own USER_TAG / FRESHNESS / QUALITY values.
	if check_k >= 0:
		var c := ((tag ^ freshness ^ quality) + 5) & 15
		var w := int(def.fields[check_k].get("width", 1))
		var check_v: int = ((c + 1 + check_j % 15) & 15) if check_hit else c
		out["CHECK"] = check_v & ((1 << w) - 1)
	return out


## The full record BitVector of `seq`: the field values concatenated MSB first.
static func record(def: RemoteSourceDef, pop: PopulationDef, seq: int) -> BitVector:
	var fv := field_values(def, pop, seq)
	var acc := 0
	for f in def.fields:
		var n := str(f.get("name", ""))
		var w := int(f.get("width", 1))
		acc = (acc << w) | int(fv[n])
	return BitVector.of(acc, def.width)


## Records 0..count-1 of `source_id` with the shared population ([] for an unknown source).
static func stream(source_id: String, count: int) -> Array:
	var def := source(source_id)
	if def == null:
		return []
	var pop := population()
	var out: Array = []
	for seq in range(count):
		out.append(record(def, pop, seq))
	return out


## [{name, width, hi, lo}] of the record layout, MSB first.
static func field_ranges(def: RemoteSourceDef) -> Array:
	var out: Array = []
	var hi := def.width - 1
	for f in def.fields:
		var w := int(f.get("width", 1))
		out.append({"name": str(f.get("name", "")), "width": w, "hi": hi, "lo": hi - w + 1})
		hi -= w
	return out


## Decode one field of a record BitVector (-1 for an unknown name).
static func field(def: RemoteSourceDef, v: BitVector, name: String) -> int:
	for r in field_ranges(def):
		if str(r["name"]) == name:
			return (v.bits >> int(r["lo"])) & ((1 << int(r["width"])) - 1)
	return -1