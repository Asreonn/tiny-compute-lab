class_name HudKit
extends RefCounted
## Builders for the canonical HUD V2 (design/reference/hud_v2_geometry.md). Every panel is made
## from these: exact StyleBoxFlat fills/strokes/radii, JetBrains Mono labels and tinted icons.
## Positions are absolute px in the 1920×1080 reference canvas (canvas_items stretch scales them).

const W_MEDIUM := "Medium"
const W_BOLD := "Bold"
const W_XBOLD := "ExtraBold"

## Project-wide reduced-motion switch: when true every HUD tween snaps to its end state.
static var REDUCED_MOTION := false


## A cubic-out tween on `node`, or null under reduced motion (callers snap manually).
static func anim(node: Node) -> Tween:
	if REDUCED_MOTION:
		return null
	return node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Kill a tween (ignore null / dead handles).
static func kill(t: Tween) -> void:
	if t != null and t.is_valid():
		t.kill()


## Kill the tween stored under `key` on `node` (no error if it was never set).
static func kill_meta(node: Node, key: String) -> void:
	if node.has_meta(key):
		kill(node.get_meta(key) as Tween)


## Tween one property, or snap instantly under reduced motion. Returns the tween (nullable).
static func to(node: Node, subject: Object, prop: String, val: Variant, dur: float) -> Tween:
	if REDUCED_MOTION:
		subject.set(prop, val)
		return null
	var tw := anim(node)
	tw.tween_property(subject, prop, val, dur)
	return tw


## Tween a colour through `apply(colour)` — the only way to fade stylebox/label colours.
static func to_color(node: Node, apply: Callable, from: Color, to: Color, dur: float) -> Tween:
	if REDUCED_MOTION:
		apply.call(to)
		return null
	var tw := anim(node)
	tw.tween_method(func(t: float): apply.call(from.lerp(to, t)), 0.0, 1.0, dur)
	return tw


## Roll a number through `display(value)`; snaps under reduced motion or when unchanged.
static func roll_value(node: Node, key: String, from: float, to: float, display: Callable, dur := 0.2) -> Tween:
	if is_equal_approx(from, to):
		display.call(to)
		return null
	if REDUCED_MOTION:
		display.call(to)
		return null
	kill_meta(node, key)
	var tw := anim(node)
	node.set_meta(key, tw)
	tw.tween_method(func(t: float): display.call(lerpf(from, to, t)), 0.0, 1.0, dur)
	return tw


## Tween a progress bar's width; ignores repeats of the same target.
static func progress_bar(track: Panel, target_w: float, dur := 0.25) -> void:
	if track.has_meta("pb_target") and track.get_meta("pb_target") == target_w:
		return
	track.set_meta("pb_target", target_w)
	kill_meta(track, "pb_tw")
	if REDUCED_MOTION:
		track.size.x = target_w
		return
	var tw := anim(track)
	track.set_meta("pb_tw", tw)
	tw.tween_property(track, "size:x", target_w, dur)


## Slide + fade a panel in from its docking side. `from` is the slide offset.
static func panel_show(p: Control, from: Vector2, dur := 0.18) -> void:
	p.visible = true
	var base: Vector2 = p.position
	p.set_meta("panel_base", base)
	p.modulate.a = 0.0
	p.position = base + from
	kill_meta(p, "panel_tw")
	if REDUCED_MOTION:
		p.modulate.a = 1.0
		p.position = base
		return
	var tw := anim(p)
	p.set_meta("panel_tw", tw)
	tw.tween_property(p, "modulate:a", 1.0, dur)
	tw.parallel().tween_property(p, "position", base, dur)


## Slide + fade a panel out towards its docking side, then hide it.
static func panel_hide(p: Control, to: Vector2, dur := 0.14) -> void:
	var base: Vector2 = p.get_meta("panel_base") as Vector2 if p.has_meta("panel_base") else p.position
	kill_meta(p, "panel_tw")
	if REDUCED_MOTION:
		p.visible = false
		p.modulate.a = 1.0
		return
	var tw := anim(p)
	p.set_meta("panel_tw", tw)
	tw.tween_property(p, "modulate:a", 0.0, dur)
	tw.parallel().tween_property(p, "position", base + to, dur)
	tw.tween_callback(func():
		p.visible = false
		p.position = base  # no drift for the next show
	)


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
	var sb := style(fill, stroke, stroke_w, radius)
	p.add_theme_stylebox_override("panel", sb)
	p.set_meta("sb", sb)
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
		set_color(l, color)


## Font colour override that only touches the Label when the colour changes (an override is a
## theme change: the Label re-shapes its text, so doing it every frame is not free).
static func set_color(c: Control, color: Color, key := "font_color") -> void:
	if c.has_theme_color_override(key) and c.get_theme_color(key) == color:
		return
	c.add_theme_color_override(key, color)


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


## A square icon button with the canonical hover/press motion. Returns its Panel so callers
## can still restyle/select it. Icon rests TEXT_SECONDARY, hovers to TEXT_PRIMARY.
static func icon_button(parent: Control, pos: Vector2, size: Vector2, icon_name: String, icon_pos: Vector2, icon_size: float, on_press: Callable, tooltip := "", radius := 4) -> Panel:
	var b := box(parent, pos, size, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, radius)
	var ic := icon(b, icon_name, icon_pos, icon_size, Palette.TEXT_SECONDARY)
	b.set_meta("ib_icon", ic)
	var hb := hit(parent, pos, size, on_press, tooltip)
	hb.mouse_entered.connect(func(): _icon_hover(b, true))
	hb.mouse_exited.connect(func(): _icon_hover(b, false))
	hb.button_down.connect(func(): _icon_press(b))
	hb.button_up.connect(func(): _icon_release(b))
	return b


## Snap an icon button's icon colour (used for "active/selected" states).
static func set_icon_color(b: Panel, color: Color) -> void:
	if not b.has_meta("ib_icon"):
		return
	var ic: TextureRect = b.get_meta("ib_icon")
	ic.modulate = color


static func _icon_hover(b: Panel, on: bool) -> void:
	var sb: StyleBoxFlat = b.get_meta("sb")
	var ic: TextureRect = b.get_meta("ib_icon")
	kill_meta(b, "ib_hover_tw")
	if REDUCED_MOTION:
		if on:
			_apply_btn_style(sb, ic, Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, 1.0, Palette.TEXT_PRIMARY)
		else:
			_apply_btn_style(sb, ic, Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0.0, Palette.TEXT_SECONDARY)
		return
	var tw := anim(b.get_parent())
	b.set_meta("ib_hover_tw", tw)
	var dur := 0.12
	if on:
		tw.tween_property(sb, "bg_color", Palette.SURFACE_RAISED, dur)
		tw.parallel().tween_property(sb, "border_color", Palette.SURFACE_BORDER_STRONG, dur)
		_border_w(tw, sb, 1.0, dur)
		tw.parallel().tween_property(ic, "modulate", Palette.TEXT_PRIMARY, dur)
	else:
		tw.tween_property(sb, "bg_color", Color(0, 0, 0, 0), dur)
		tw.parallel().tween_property(sb, "border_color", Color(0, 0, 0, 0), dur)
		_border_w(tw, sb, 0.0, dur)
		tw.parallel().tween_property(ic, "modulate", Palette.TEXT_SECONDARY, dur)


static func _apply_btn_style(sb: StyleBoxFlat, ic: TextureRect, bg: Color, border: Color, w: float, icon_c: Color) -> void:
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(int(ceil(w)))
	ic.modulate = icon_c


static func _border_w(tw: Tween, sb: StyleBoxFlat, w: float, dur: float) -> void:
	for prop in ["border_width_left", "border_width_right", "border_width_top", "border_width_bottom"]:
		tw.parallel().tween_property(sb, prop, w, dur)


static func _icon_press(b: Panel) -> void:
	if REDUCED_MOTION:
		return
	b.pivot_offset = b.size / 2.0
	kill_meta(b, "ib_press_tw")
	var tw := anim(b.get_parent())
	b.set_meta("ib_press_tw", tw)
	tw.tween_property(b, "scale", Vector2(0.96, 0.96), 0.08)
	tw.tween_property(b, "scale", Vector2.ONE, 0.08)


static func _icon_release(b: Panel) -> void:
	kill_meta(b, "ib_press_tw")
	b.scale = Vector2.ONE


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


## Constants (shift amounts, moduli) are amounts, not characters: CHR shows them as DEC.
## A machine constant: always bits (0/1), whatever the view mode.
static func fmt_const(bv: BitVector) -> String:
	return ViewMode.format(bv, ViewMode.Mode.BIN)


## Machine icon for palette tiles / inspector headers: the op_* icon, or the def's glyph_text
## (e.g. Modulo "%") when no icon asset exists.
static func machine_icon(parent: Control, type: String, pos: Vector2, size: float, color: Color) -> Control:
	var def := Catalog.def(type)
	if str(def.get("icon", "")) != "":
		return icon(parent, str(def["icon"]), pos, size, color)
	return label(parent, str(def.get("glyph_text", "?")), pos + Vector2(0, size * 0.1), int(size * 0.8), W_XBOLD, color, size, HORIZONTAL_ALIGNMENT_CENTER)


## Staggered entrance for menu/palette cards: fade + 12 px rise, `idx` staggers 40 ms apart.
static func card_entrance(card: Control, idx: int) -> void:
	if REDUCED_MOTION:
		return
	var base: Vector2 = card.position
	card.modulate.a = 0.0
	card.position = base + Vector2(0, 12)
	var tw := anim(card)
	tw.tween_interval(idx * 0.04)
	tw.tween_property(card, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(card, "position", base, 0.18)


## Hover lift (2 px up) + border to border-strong for palette/menu cards.
static func card_hover(card: Panel, btn: Button, base_border: Color) -> void:
	btn.mouse_entered.connect(func(): _card_hover(card, base_border, true))
	btn.mouse_exited.connect(func(): _card_hover(card, base_border, false))


static func _card_hover(card: Panel, base_border: Color, on: bool) -> void:
	var sb: StyleBoxFlat = card.get_meta("sb")
	kill_meta(card, "ch_tw")
	if REDUCED_MOTION:
		sb.border_color = Palette.SURFACE_BORDER_STRONG if on else base_border
		card.position.y = card.get_meta("ch_base_y") - (2.0 if on else 0.0)
		return
	if not card.has_meta("ch_base_y"):
		card.set_meta("ch_base_y", card.position.y)
	var base_y: float = card.get_meta("ch_base_y")
	var tw := anim(card)
	card.set_meta("ch_tw", tw)
	tw.set_parallel(true)
	tw.tween_property(sb, "border_color", Palette.SURFACE_BORDER_STRONG if on else base_border, 0.12)
	tw.tween_property(card, "position:y", base_y - (2.0 if on else 0.0), 0.12)


## Pulse a "New" dot twice (0.3 s each cycle), then hold it visible.
static func pulse_new(dot: Panel) -> void:
	if REDUCED_MOTION:
		dot.modulate.a = 1.0
		return
	dot.modulate.a = 0.0
	var tw := anim(dot)
	for i in 2:
		tw.tween_property(dot, "modulate:a", 1.0, 0.3)
		tw.tween_property(dot, "modulate:a", 0.0, 0.3)
	tw.tween_property(dot, "modulate:a", 1.0, 0.3)  # hold
