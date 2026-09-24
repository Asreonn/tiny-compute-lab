class_name TclTheme
extends RefCounted
## Builds the Godot Theme from design tokens (Palette). Mirrors Penpot "06 HUD Components".
## Type variations used by the HUD: PanelHUD, PanelSunken, PanelChip, ButtonPrimary,
## ButtonIcon, ButtonTool, ButtonSegment, ButtonCard, LabelTitle, LabelHeading, LabelCaption,
## LabelMicro, LabelValue, LabelMuted.

const FONT_DIR := "res://assets/fonts/"

static var _theme: Theme
static var fonts := {}


static func font(weight: String = "Medium") -> Font:
	if not fonts.has(weight):
		var f := FontFile.new()
		f.load_dynamic_font(FONT_DIR + "JetBrainsMono-%s.ttf" % weight)
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_LIGHT
		# MSDF: glyphs stay crisp at any camera zoom (machine text is drawn in world space)
		f.multichannel_signed_distance_field = true
		f.msdf_pixel_range = 8
		fonts[weight] = f
	return fonts[weight]


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw := 0, radius := Palette.RADIUS_CONTROL, pad := Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


static func panel_box() -> StyleBoxFlat:
	var s := box(Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, Palette.RADIUS_PANEL, Vector4(16, 14, 16, 14))
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 6)
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("Medium")
	t.default_font_size = Palette.FONT_BODY

	# ---- Label
	t.set_color("font_color", "Label", Palette.TEXT_PRIMARY)
	for v in [["LabelTitle", "ExtraBold", Palette.FONT_TITLE, Palette.TEXT_PRIMARY],
			["LabelHeading", "ExtraBold", Palette.FONT_LABEL, Palette.TEXT_PRIMARY],
			["LabelCaption", "Medium", Palette.FONT_CAPTION, Palette.TEXT_SECONDARY],
			["LabelMicro", "ExtraBold", Palette.FONT_MICRO, Palette.TEXT_MUTED],
			["LabelValue", "ExtraBold", Palette.FONT_LABEL, Palette.TEXT_PRIMARY],
			["LabelMuted", "Medium", Palette.FONT_CAPTION, Palette.TEXT_MUTED],
			["LabelDisplay", "ExtraBold", Palette.FONT_DISPLAY, Palette.TEXT_PRIMARY],
			["LabelHero", "ExtraBold", Palette.FONT_HERO, Palette.TEXT_PRIMARY]]:
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], font(v[1]))
		t.set_font_size("font_size", v[0], v[2])
		t.set_color("font_color", v[0], v[3])
	t.set_constant("line_spacing", "LabelCaption", 2)

	# ---- Panels
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	t.set_type_variation("PanelHUD", "PanelContainer")
	t.set_stylebox("panel", "PanelHUD", panel_box())
	t.set_type_variation("PanelBar", "PanelContainer")
	t.set_stylebox("panel", "PanelBar", box(Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 0, 0, Vector4(16, 8, 16, 8)))
	t.set_type_variation("PanelSunken", "PanelContainer")
	t.set_stylebox("panel", "PanelSunken", box(Palette.SURFACE_SUNKEN, Palette.SURFACE_BORDER, 1, Palette.RADIUS_CONTROL, Vector4(10, 8, 10, 8)))
	t.set_type_variation("PanelChip", "PanelContainer")
	t.set_stylebox("panel", "PanelChip", box(Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, 1, Palette.RADIUS_CONTROL, Vector4(12, 6, 12, 6)))

	# ---- Buttons
	_button(t, "Button", Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, Palette.TEXT_PRIMARY,
		Palette.MACHINE_BODY_HI, Palette.MACHINE_FRAME_HOVER, Palette.SURFACE_SUNKEN, Palette.DATA_NUMBER)
	t.set_font("font", "Button", font("ExtraBold"))
	t.set_font_size("font_size", "Button", Palette.FONT_CAPTION)
	t.set_type_variation("ButtonPrimary", "Button")
	_button(t, "ButtonPrimary", Palette.DATA_NUMBER, Palette.DATA_NUMBER, Palette.TEXT_INVERSE,
		Palette.STATE_VALID, Palette.STATE_VALID, Palette.DATA_NUMBER_DIM, Palette.DATA_NUMBER)
	t.set_type_variation("ButtonIcon", "Button")
	_button(t, "ButtonIcon", Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, Palette.TEXT_PRIMARY,
		Palette.MACHINE_BODY_HI, Palette.MACHINE_FRAME_HOVER, Palette.DATA_NUMBER_DIM, Palette.DATA_NUMBER, Vector4(6, 6, 6, 6))
	t.set_type_variation("ButtonTool", "Button")
	_button(t, "ButtonTool", Color(0, 0, 0, 0), Color(0, 0, 0, 0), Palette.TEXT_SECONDARY,
		Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, Palette.DATA_NUMBER_DIM, Palette.DATA_NUMBER, Vector4(12, 12, 12, 12), Palette.RADIUS_SHELL)
	t.set_type_variation("ButtonSegment", "Button")
	_button(t, "ButtonSegment", Color(0, 0, 0, 0), Color(0, 0, 0, 0), Palette.TEXT_MUTED,
		Palette.SURFACE_RAISED, Palette.SURFACE_BORDER, Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, Vector4(10, 4, 10, 4), 3)
	t.set_color("font_pressed_color", "ButtonSegment", Palette.TEXT_PRIMARY)
	t.set_type_variation("ButtonCard", "Button")
	_button(t, "ButtonCard", Palette.SURFACE_SUNKEN, Palette.SURFACE_BORDER, Palette.TEXT_PRIMARY,
		Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, Palette.SURFACE_RAISED, Palette.FAMILY_ROUTING, Vector4(10, 10, 10, 10))

	# ---- Inputs
	var le := box(Palette.SURFACE_SUNKEN, Palette.SURFACE_BORDER_STRONG, 1)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", box(Palette.SURFACE_SUNKEN, Palette.STATE_BUILD, 1))
	t.set_font("font", "LineEdit", font("ExtraBold"))
	t.set_color("font_color", "LineEdit", Palette.TEXT_PRIMARY)
	t.set_stylebox("normal", "OptionButton", box(Palette.SURFACE_RAISED, Palette.SURFACE_BORDER_STRONG, 1))
	t.set_stylebox("hover", "OptionButton", box(Palette.MACHINE_BODY_HI, Palette.MACHINE_FRAME_HOVER, 1))
	t.set_stylebox("pressed", "OptionButton", box(Palette.SURFACE_SUNKEN, Palette.SURFACE_BORDER_STRONG, 1))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	t.set_font("font", "OptionButton", font("ExtraBold"))
	t.set_stylebox("panel", "PopupMenu", box(Palette.SURFACE_PANEL, Palette.SURFACE_BORDER_STRONG, 1, Palette.RADIUS_CONTROL, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", box(Palette.SURFACE_RAISED, Color(0, 0, 0, 0), 0, 3))
	t.set_color("font_color", "PopupMenu", Palette.TEXT_PRIMARY)
	t.set_color("font_hover_color", "PopupMenu", Palette.TEXT_PRIMARY)
	t.set_stylebox("panel", "TooltipPanel", box(Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, Palette.RADIUS_PANEL, Vector4(10, 8, 10, 8)))
	t.set_color("font_color", "TooltipLabel", Palette.TEXT_PRIMARY)
	t.set_font_size("font_size", "TooltipLabel", Palette.FONT_CAPTION)

	# ---- Misc
	var sep := StyleBoxLine.new()
	sep.color = Palette.SURFACE_BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	t.set_stylebox("background", "ProgressBar", box(Palette.SURFACE_SUNKEN, Color(0, 0, 0, 0), 0, 2, Vector4.ZERO))
	t.set_stylebox("fill", "ProgressBar", box(Palette.STATE_VALID, Color(0, 0, 0, 0), 0, 2, Vector4.ZERO))
	t.set_constant("separation", "VBoxContainer", Palette.SPACE_SM)
	t.set_constant("separation", "HBoxContainer", Palette.SPACE_SM)
	_theme = t
	return t


static func _button(t: Theme, type: String, bg: Color, border: Color, fg: Color, hbg: Color, hborder: Color,
		pbg: Color, pborder: Color, pad := Vector4(14, 8, 14, 8), radius := Palette.RADIUS_CONTROL) -> void:
	t.set_stylebox("normal", type, box(bg, border, 1, radius, pad))
	t.set_stylebox("hover", type, box(hbg, hborder, 1, radius, pad))
	t.set_stylebox("pressed", type, box(pbg, pborder, 1, radius, pad))
	t.set_stylebox("hover_pressed", type, box(pbg, pborder, 1, radius, pad))
	t.set_stylebox("disabled", type, box(Palette.SURFACE_PANEL, Palette.SURFACE_BORDER, 1, radius, pad))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg if type != "ButtonTool" else Palette.TEXT_PRIMARY)
	t.set_color("font_pressed_color", type, pborder if type in ["ButtonTool", "ButtonIcon"] else fg)
	t.set_color("font_hover_pressed_color", type, pborder if type in ["ButtonTool", "ButtonIcon"] else fg)
	t.set_color("font_disabled_color", type, Palette.TEXT_MUTED)
	t.set_color("icon_normal_color", type, fg)
	t.set_color("icon_hover_color", type, Palette.TEXT_PRIMARY)
	t.set_color("icon_pressed_color", type, pborder if type in ["ButtonTool", "ButtonIcon"] else fg)
	t.set_color("icon_hover_pressed_color", type, pborder if type in ["ButtonTool", "ButtonIcon"] else fg)
	t.set_color("icon_disabled_color", type, Palette.TEXT_MUTED)
