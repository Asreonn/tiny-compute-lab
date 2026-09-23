class_name HudKit
extends RefCounted
## Builders for the canonical HUD V2 (design/reference/hud_v2_geometry.md). Every panel is made
## from these: exact StyleBoxFlat fills/strokes/radii, JetBrains Mono labels and tinted icons.
## Positions are absolute px in the 1920×1080 reference canvas (canvas_items stretch scales them).

const W_MEDIUM := "Medium"
const W_BOLD := "Bold"
const W_XBOLD := "ExtraBold"


static func style(fill: Color, stroke := Color(0, 0, 0, 0), stroke_w := 0.0, radius := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = stroke
	s.set_border_width_all(int(ceil(stroke_w)))
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s


## A plain box (Panel) at pos/size. mouse_filter STOP so board clicks don't pass through panels.
static func box(parent: Control, pos: Vector2, size: Vector2, fill: Color, stroke := Color(0, 0, 0, 0), stroke_w := 0.0, radius := 0) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", style(fill, stroke, stroke_w, radius))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


## Restyle an existing box (state changes).
static func restyle(p: Panel, fill: Color, stroke := Color(0, 0, 0, 0), stroke_w := 0.0, radius := 0) -> void:
	var key := [fill, stroke, stroke_w, radius]
	if p.has_meta("style_key") and p.get_meta("style_key") == key:
		return  # unchanged: panels are refreshed every frame
	p.set_meta("style_key", key)
	p.add_theme_stylebox_override("panel", style(fill, stroke, stroke_w, radius))


## Label with the exact font size/weight. width 0 = auto; align for fixed-width labels.
static func label(parent: Control, text: String, pos: Vector2, size: int, weight: String, color: Color, width := 0.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", TclTheme.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 0)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0.0:
		l.size = Vector2(width, size * 1.3)
		l.clip_text = true
	parent.add_child(l)
	return l


static func set_text(l: Label, text: String, color = null) -> void:
	if l.text != text:
		l.text = text
	if color != null:
		l.add_theme_color_override("font_color", color)


## White SVG icon (assets/art/icon/*.svg) tinted with `color`, drawn at size×size.
static func icon(parent: Control, name: String, pos: Vector2, size: float, color: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.icon(name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.position = pos
	t.size = Vector2(size, size)
	t.modulate = color
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


## Invisible clickable area over a region (the visual is drawn by boxes/labels under it).
static func hit(parent: Control, pos: Vector2, size: Vector2, on_press: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = pos
	b.size = size
	b.tooltip_text = tooltip
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


## A small filled dot (state badges, "New" markers).
static func dot(parent: Control, center: Vector2, d: float, color: Color) -> Panel:
	return box(parent, center - Vector2(d, d) / 2.0, Vector2(d, d), color, Color(0, 0, 0, 0), 0.0, int(d))


static func state_color(state: String) -> Color:
	match state:
		"RUNNING": return Palette.STATE_RUNNING
		"PAUSED": return Palette.STATE_PAUSED
		"FAILED": return Palette.STATE_ERROR
		"COMPLETE": return Palette.STATE_SUCCESS
	return Palette.STATE_BUILD


## Mission-level sim state: BUILD / RUNNING / PAUSED / FAILED / COMPLETE.
static func sim_state() -> String:
	var m = Engine.get_main_loop().root.get_node_or_null("/root/SimulationManager")
	if m == null or m.run == null:
		return "BUILD"
	if m.run.status == MissionRun.Status.FAIL:
		return "FAILED"
	if m.run.status == MissionRun.Status.PASS:
		return "COMPLETE"
	if m.running:
		return "RUNNING"
	return "PAUSED" if m.sim.tick > 0 else "BUILD"


## Current display mode: the manager's view mode, else BIN.
static func view_mode() -> int:
	var m = Engine.get_main_loop().root.get_node_or_null("/root/SimulationManager")
	if m == null or int(m.view_mode) < 0:
		return ViewMode.Mode.BIN
	return int(m.view_mode)


static func fmt(bv: BitVector) -> String:
	return ViewMode.format(bv, view_mode()) if bv != null else "—"
