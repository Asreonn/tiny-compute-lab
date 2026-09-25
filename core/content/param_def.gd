class_name ParamDef
extends Resource
## One player-editable parameter of a ComponentDef (the Inspector builds its control from it).

@export var key := ""
@export var label := ""
@export_enum("int", "enum", "text") var kind := "int"
## int params: the default and the range.
@export var default_int := 0
@export var min_value := 0
@export var max_value := 0
## enum params: the choices and the default choice; text params: the default text.
@export var options: PackedStringArray = PackedStringArray()
@export var default_text := ""


func to_dict() -> Dictionary:
	match kind:
		"enum":
			return {"label": label, "kind": kind, "default": default_text, "options": Array(options)}
		"text":
			return {"label": label, "kind": kind, "default": default_text}
	return {"label": label, "kind": kind, "default": default_int, "min": min_value, "max": max_value}
