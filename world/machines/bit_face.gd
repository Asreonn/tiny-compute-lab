class_name BitFace
extends Node2D
## Live value face (JOB C4): a small rectangle on a machine that shows the current value as
## bit cells ("cells"), DIP switches ("dip") or a field ruler ("ruler"). Read-only over the
## machine; queue_redraw() only when the shown value actually changes.

## "cells" | "dip" | "ruler"
var mode := "cells"
## Machine-local rectangle the face occupies (unrotated with the body).
var rect := Rect2()

# --- change detection (the value shown last time) ---
var _width := -1
var _value := -1
var _ruler_width := -1
var _fields: Array = []


## Show a live bit value: store a copy (width + unsigned value); redraw only on a change.
func show_bits(v: BitVector) -> void:
	if v.width == _width and v.unsigned() == _value:
		return
	_width = v.width
	_value = v.unsigned()
	queue_redraw()


## Show a field ruler: store the width + fields; redraw only on a change.
func show_ruler(width: int, fields: Array) -> void:
	if width == _ruler_width and str(fields) == str(_fields):
		return
	_ruler_width = width
	_fields = fields.duplicate()
	queue_redraw()


func _draw() -> void:
	match mode:
		"dip":
			_draw_dip()
		"ruler":
			_draw_ruler()
		_:
			_draw_cells()


## Baseline y for text vertically centred in a box of height h starting at y.
static func _vcenter(f: Font, sz: float, y: float, h: float) -> float:
	return y + (h - (f.get_ascent(sz) + f.get_descent(sz))) / 2.0 + f.get_ascent(sz)


## The LOW n bits (n = min(width, 8)), MSB of those on the left, 2 px gaps.
func _draw_cells() -> void:
	var n := mini(_width, 8)
	if n <= 0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var gap := 2.0
	var cw := (rect.size.x - gap * (n - 1)) / n
	for i in n:
		var bit := (_value >> (n - 1 - i)) & 1
		var r := Rect2(rect.position.x + i * (cw + gap), rect.position.y, cw, rect.size.y)
		if bit == 1:
			draw_rect(r, Color(Palette.DATA_NUMBER, 0.85))
		else:
			draw_rect(r, Palette.SURFACE_SUNKEN)
			draw_rect(r, Color(Palette.MATERIAL_FRAME, 1.0), false, 0.75)
	if _width > 8:
		var f := ThemeDB.fallback_font
		var txt := "…"
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7.0).x
		draw_string(f, Vector2(rect.position.x - 4.0 - tw, _vcenter(f, 7.0, rect.position.y, rect.size.y)),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7.0, Color(Palette.MATERIAL_SILK, 0.55))


## DIP switches: a sunken slot per bit with a knob at the top (1) or bottom (0).
func _draw_dip() -> void:
	var n := mini(_width, 8)
	if n <= 0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var gap := 2.0
	var cw := (rect.size.x - gap * (n - 1)) / n
	var knob_w := cw - 2.0
	var knob_h := rect.size.y * 0.45
	for i in n:
		var bit := (_value >> (n - 1 - i)) & 1
		var r := Rect2(rect.position.x + i * (cw + gap), rect.position.y, cw, rect.size.y)
		draw_rect(r, Palette.SURFACE_SUNKEN)
		draw_rect(r, Color(Palette.MATERIAL_FRAME, 1.0), false, 0.75)
		var ky := r.position.y + 1.0 if bit == 1 else r.end.y - knob_h - 1.0
		draw_rect(Rect2(r.position.x + 1.0, ky, knob_w, knob_h),
			Color(Palette.DATA_NUMBER, 0.85) if bit == 1 else Color(Palette.MACHINE_FRAME_HOVER, 0.6))


## Field ruler: MSB at the top; field i cells are DATA_NUMBER (even i 0.8, odd i 0.45);
## leftover low bits are sunken; dividers between fields; width labels on the left.
func _draw_ruler() -> void:
	var w := _ruler_width
	if w <= 0 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var field_sum := 0
	for f in _fields:
		field_sum += int(f)
	var valid := not _fields.is_empty() and field_sum <= w
	var dividers := maxi(0, _fields.size() - 1) if valid else 0
	var pitch := (rect.size.y - 8.0 - 3.0 * dividers) / w
	if pitch <= 0.0:
		return
	var cw := rect.size.x - 6.0
	var ch := pitch * 0.7
	var y := rect.position.y + 4.0
	var i := 0
	if valid:
		var f := ThemeDB.fallback_font
		for fi in _fields.size():
			var fw := int(_fields[fi])
			var field_top := y
			for k in fw:
				if i >= w:
					break
				_draw_ruler_cell(y, cw, ch, Color(Palette.DATA_NUMBER, 0.8 if fi % 2 == 0 else 0.45))
				y += pitch
				i += 1
			if i >= w:
				break
			# width label, vertically centred on the field, right-aligned at rect.x - 9
			var txt := str(fw)
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7.0).x
			draw_string(f, Vector2(rect.position.x - 9.0 - tw, _vcenter(f, 7.0, field_top, fw * pitch)),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7.0, Color(Palette.MATERIAL_SILK, 0.55))
			# divider bar, then skip 3 px
			draw_rect(Rect2(rect.position.x + 1.0, y, rect.size.x - 2.0, 1.2), Palette.FAMILY_ROUTING)
			y += 1.2 + 3.0
	else:
		for k in w:
			_draw_ruler_cell(y, cw, ch, Color(Palette.DATA_NUMBER, 0.45))
			y += pitch
			i += 1
	# leftover low bits beyond the sum of the fields: sunken outlines
	while i < w:
		_draw_ruler_cell(y, cw, ch, Palette.SURFACE_SUNKEN, true)
		y += pitch
		i += 1


func _draw_ruler_cell(y: float, cw: float, ch: float, fill: Color, outline := false) -> void:
	var r := Rect2(rect.position.x + 3.0, y, cw, ch)
	draw_rect(r, fill)
	if outline:
		draw_rect(r, Color(Palette.MATERIAL_FRAME, 1.0), false, 0.75)