class_name DeviceDef
extends Resource
## A USB stick kind as an asset (docs/CONTENT.md): content/devices/<id>.tres. Input sticks feed
## a socket (bits, or raw values an Encoder turns into bits); output devices sit in an output
## port (the Job stick that judges a quest, the Monitor). The STREAM a stick carries belongs to
## the quest (LevelDef.streams), never to the stick.

@export var id := ""
@export var display_name := ""
## Output-side device (plugs into an output port) instead of an input stick.
@export var output := false
## Input sticks: "bits" = already-encoded BitVectors, "raw" = RawValues of `raw_kind`.
@export_enum("bits", "raw") var out := "bits"
@export_enum("TEXT", "NUMBER", "KEY", "SENSOR") var raw_kind := 0
## The silk on the stick ("Aa", "42") and its accent: "data" (bits) or "io" (raw / devices).
@export var glyph := ""
@export_enum("data", "io") var accent := "io"


func to_dict() -> Dictionary:
	var d := {"name": display_name, "output": output, "glyph": glyph, "accent": accent}
	if not output:
		d["out"] = out
		if out == "raw":
			d["raw_kind"] = raw_kind
	return d
