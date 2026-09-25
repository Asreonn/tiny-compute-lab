class_name Devices
extends RefCounted
## The lab's data modules (docs/SYSTEMS_EXPANSION.md §2): the devices the player plugs into a
## USB socket, loaded from the DeviceDef assets (content/devices). Pure data + stream builders —
## no Node, no RNG, no rendering.
##
## A module either emits already-encoded bits ("bit", the opening device) or raw semantic
## values ("number", "text", "key", "sensor") that an Encoder must turn into bits
## (docs/ARCHITECTURE.md §0 rule 7). The STREAM belongs to the contract, not the module: a
## mission supplies the spec and `make_stream` turns it into the values the socket emits.

## kind -> {name, out: "bits"|"raw", raw_kind: RawValue.Kind (raw only), glyph, accent}: the
## input sticks, from the DeviceDef assets in content/devices (docs/CONTENT.md).
static var KINDS := {}
## Output devices the player plugs into an output port (docs/SYSTEMS_EXPANSION.md §2.1). In the
## Lab every quest brings its own Job stick ("job@11"): it takes that quest's results only, fills
## up, and is the stick the player files. A plain "job" judges any quest (tests, old saves);
## "job2" only survives in old saves.
static var OUTPUT_KINDS := {}


static func _static_init() -> void:
	reload()


## (Re)load every DeviceDef / device variant from content/devices.
static func reload() -> void:
	KINDS = {}
	OUTPUT_KINDS = {}
	var table := ContentDB.table(ContentDB.DEVICES_DIR, DeviceDef)
	for k in table:
		var d: Dictionary = table[k]
		if bool(d.get("output", false)):
			OUTPUT_KINDS[k] = d
		else:
			KINDS[k] = d


## Register one more stick kind at run time (a DeviceDef or a ContentVariant of one).
static func register(r: Resource) -> bool:
	var id := ""
	var d := {}
	if r is ContentVariant:
		id = (r as ContentVariant).id
		d = (r as ContentVariant).resolve()
	elif r is DeviceDef:
		id = (r as DeviceDef).id
		d = (r as DeviceDef).to_dict()
	if id == "" or id.contains("@"):
		return false  # "@" is the quest-stick separator
	if bool(d.get("output", false)):
		OUTPUT_KINDS[id] = d
	else:
		KINDS[id] = d
	return true


## The silk on a stick of `kind` ("Aa", "42"; "" when unknown).
static func glyph(kind: String) -> String:
	var b := base(kind)
	var d: Dictionary = KINDS.get(b, OUTPUT_KINDS.get(b, {}))
	return str(d.get("glyph", ""))


## "data" (a bit stick) or "io" (raw sticks and output devices): the palette token to use.
static func accent(kind: String) -> String:
	var b := base(kind)
	var d: Dictionary = KINDS.get(b, OUTPUT_KINDS.get(b, {}))
	return str(d.get("accent", "io"))


# ------------------------------------------------------------------ quest sticks
# A quest comes with its own sticks: a module kind bound to a quest, "text@11" = quest 12's text
# stick. It carries that quest's stream and stamps the quest on every value it emits, so any
# drive can judge the result against the right quest. Plain kinds ("text") still work (tests,
# old saves): they belong to the current quest.

static func base(kind: String) -> String:
	var at := kind.find("@")
	return kind.substr(0, at) if at >= 0 else kind


## The quest index a stick belongs to, -1 for a plain module.
static func quest_of(kind: String) -> int:
	var at := kind.find("@")
	return int(kind.substr(at + 1)) if at >= 0 else -1


static func stick(kind: String, quest: int) -> String:
	return "%s@%d" % [base(kind), quest]


static func is_job(kind: String) -> bool:
	return base(kind) == "job" or kind == "job2"


static func has(kind: String) -> bool:
	return KINDS.has(base(kind))


static func has_output(kind: String) -> bool:
	return OUTPUT_KINDS.has(base(kind))


static func output_display_name(kind: String) -> String:
	if not OUTPUT_KINDS.has(base(kind)):
		return ""
	return str(OUTPUT_KINDS[base(kind)]["name"])


## "bits" or "raw" for a known kind; an unknown/absent module reads as "bits" so an empty
## socket keeps the normal data role.
static func out_kind(kind: String) -> String:
	if not KINDS.has(base(kind)):
		return "bits"
	return str(KINDS[base(kind)]["out"])


static func display_name(kind: String) -> String:
	if not KINDS.has(base(kind)):
		return ""
	return str(KINDS[base(kind)]["name"])


## Build the values a socket emits from a contract spec: {"values": [...], "width": int}. The
## stick's DeviceDef decides how:
## - bits:      BIN strings ("010") become BitVectors of their own width; single characters are
##              encoded with the charset of `width` (TCL-5 up to 6 bits).
## - raw TEXT:  one RawValue per character of every string value ("HI" -> H, I).
## - raw other: one RawValue of that kind (NUMBER, KEY, SENSOR) per int value.
static func make_stream(kind: String, spec: Dictionary) -> Array:
	var values: Array = spec.get("values", [])
	var out: Array = []
	var d: Dictionary = KINDS.get(base(kind), {})
	if d.is_empty():
		return out
	if str(d["out"]) == "bits":
		var w := int(spec.get("width", 0))
		for v in values:
			if v is BitVector:
				out.append(v)
				continue
			var s := str(v)
			if _is_bin(s, w):
				out.append(BitVector.from_bin(s))
			else:
				var bv := Charset.encode(s, w)
				if bv != null:
					out.append(bv)
	elif int(d["raw_kind"]) == RawValue.Kind.TEXT:
		for v in values:
			for ch in str(v):
				out.append(RawValue.text(ch))
	else:
		for v in values:
			out.append(RawValue.new(int(d["raw_kind"]), int(v)))
	return out


## A value is a BIN string when it is non-empty, all 0/1, and (when a width is given) exactly
## that many digits. Anything else is treated as a character.
static func _is_bin(s: String, width: int) -> bool:
	if s.is_empty():
		return false
	if width > 0 and s.length() != width:
		return false
	for c in s:
		if c != "0" and c != "1":
			return false
	return true
