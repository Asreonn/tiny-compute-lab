class_name TieCap
extends Node2D
## Tie cap (JOB C4): a small chip next to a tie-able input port showing the value the port
## reads while nothing is wired to it (its tie param). Read-only over the machine; redraws
## only when the shown bits change.

var bits := ""


func set_bits(s: String) -> void:
	if s != bits:
		bits = s
		queue_redraw()


func _draw() -> void:
	var w := 12.0 + 5.4 * bits.length()
	var r := Rect2(-w / 2.0, -7.0, w, 14.0)
	draw_rect(r, Palette.SURFACE_SUNKEN)
	draw_rect(r, Palette.MATERIAL_FRAME, false, 1.0)
	if bits == "":
		return
	var f := ThemeDB.fallback_font
	var sz := 7.5
	var tw := f.get_string_size(bits, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var base_y := -7.0 + (14.0 - (f.get_ascent(sz) + f.get_descent(sz))) / 2.0 + f.get_ascent(sz)
	draw_string(f, Vector2(-tw / 2.0, base_y), bits, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(Palette.MATERIAL_SILK, 0.8))