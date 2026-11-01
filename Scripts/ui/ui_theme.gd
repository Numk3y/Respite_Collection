class_name UITheme
extends RefCounted
## The game's look: layered dark-navy panels with neon cyan edges and gold for rare things, in the style of
## VRChat's Quick Menu crossed with gacha-game lobbies. build() makes a Theme that Main puts on the root window,
## so every screen and popup uses it. Change the colours here to restyle the whole game.
##
## Panels sit slightly translucent over CyberBackdrop's grid (the "holographic" feel) with a soft drop shadow.
## Buttons look raised (thicker bottom edge), glow cyan on hover and sink when pressed. Give a Button
## theme_type_variation = &"PrimaryButton" for the big filled call-to-action style.

const BG := Color("#0D1220")  # window background (CyberBackdrop paints over it)
const BG_TOP := Color("#16203A")  # backdrop gradient
const BG_BOTTOM := Color("#070A13")
const CARD := Color("#1A2236")  # panels and cards
const CARD_HOVER := Color("#243150")
const CARD_PRESSED := Color("#0F3346")
const PANEL := Color(0.10, 0.135, 0.21, 0.88)  # translucent panels over the grid
const POPUP := Color("#1F2940")  # dialogs sit a shade lighter than the cards behind them
const INSET := Color("#0A0F1A")  # bar tracks, text fields, chips
const OUTLINE := Color("#2C3854")
const CYAN := Color("#1FD2FF")  # accents: active tabs, status tags, progress bars
const CYAN_BRIGHT := Color("#00F0FF")
const TEAL := Color("#14B8A6")
const VIOLET := Color("#8B5CF6")
const GOLD := Color("#FFE259")  # Credit Cards and other rare things
const TEXT := Color("#E6EDF7")
const TEXT_DIM := Color("#8A96AD")
const RADIUS := 10

## VRChat-style status colours, used by status tags
const STATUS_COLORS := {
	"in_world": CYAN,
	"mirror_mode": Color("#2EE59D"),
	"busy": Color("#FF5A6E"),
	"open": TEXT_DIM,
}

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16

	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())

	for type in ["Button", "OptionButton"]:
		_button_styles(t, type)
	_primary_button_styles(t)

	t.set_stylebox("background", "ProgressBar", box(INSET, Color(CYAN, 0.15), 1, 6))
	t.set_stylebox("fill", "ProgressBar", glow_box(CYAN, 6))
	t.set_color("font_color", "ProgressBar", TEXT)

	# Tabs: pill-shaped chips; the selected one is lit cyan with a glow
	var tab_panel := panel_box(12)
	tab_panel.corner_radius_top_left = 4
	t.set_stylebox("panel", "TabContainer", tab_panel)
	var selected := box(Color(CYAN, 0.16), CYAN, 1, 14, 8)
	selected.content_margin_left = 16
	selected.content_margin_right = 16
	selected.shadow_color = Color(CYAN, 0.35)
	selected.shadow_size = 8
	selected.expand_margin_bottom = -4
	t.set_stylebox("tab_selected", "TabContainer", selected)
	var unselected := box(Color(INSET, 0.7), Color(OUTLINE, 0.8), 1, 14, 8)
	unselected.content_margin_left = 16
	unselected.content_margin_right = 16
	unselected.expand_margin_bottom = -4
	t.set_stylebox("tab_unselected", "TabContainer", unselected)
	var hovered := unselected.duplicate() as StyleBoxFlat
	hovered.border_color = Color(CYAN, 0.6)
	hovered.bg_color = Color(CARD_HOVER, 0.8)
	t.set_stylebox("tab_hovered", "TabContainer", hovered)
	t.set_stylebox("tab_disabled", "TabContainer", unselected)
	t.set_constant("side_margin", "TabContainer", 6)
	t.set_color("font_selected_color", "TabContainer", CYAN_BRIGHT)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_color("font_disabled_color", "TabContainer", TEXT_DIM.darkened(0.4))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())

	t.set_stylebox("panel", "ItemList", box(INSET, OUTLINE, 1, RADIUS, 6))
	t.set_stylebox("selected", "ItemList", box(CARD_PRESSED, CYAN, 1, 6))
	t.set_stylebox("selected_focus", "ItemList", box(CARD_PRESSED, CYAN, 1, 6))
	t.set_stylebox("hovered", "ItemList", box(CARD_HOVER, Color.TRANSPARENT, 0, 6))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", CYAN_BRIGHT)
	t.set_color("font_disabled_color", "ItemList", TEXT_DIM.darkened(0.3))

	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, box(INSET, OUTLINE, 1, 6, 6))
		t.set_stylebox("focus", type, box(INSET, CYAN, 1, 6, 6))
		t.set_color("font_color", type, TEXT)

	t.set_stylebox("panel", "PopupMenu", box(CARD, OUTLINE, 1, RADIUS, 6))
	t.set_stylebox("hover", "PopupMenu", box(CARD_HOVER, Color.TRANSPARENT, 0, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", CYAN_BRIGHT)

	# Popups: the frame has to reach past the content to cover the title bar, or the title floats unframed
	t.set_stylebox("panel", "AcceptDialog", box(POPUP, Color.TRANSPARENT, 0, 0, 12))
	t.set_stylebox("embedded_border", "Window", _popup_frame(CYAN.darkened(0.1)))
	t.set_stylebox("embedded_unfocused_border", "Window", _popup_frame(OUTLINE))
	t.set_color("title_color", "Window", CYAN)

	t.set_stylebox("scroll", "VScrollBar", box(Color(INSET, 0.6), Color.TRANSPARENT, 0, 4))
	t.set_stylebox("grabber", "VScrollBar", box(Color(CYAN, 0.35), Color.TRANSPARENT, 0, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(CYAN, 0.6), Color.TRANSPARENT, 0, 4))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(CYAN, Color.TRANSPARENT, 0, 4))
	return t

static func _popup_frame(border: Color) -> StyleBoxFlat:
	var s := box(POPUP, border, 1, RADIUS)
	s.expand_margin_left = 8
	s.expand_margin_right = 8
	s.expand_margin_bottom = 8
	s.expand_margin_top = 40  # title bar height + padding
	s.shadow_color = Color(CYAN, 0.18) if border != OUTLINE else Color(0, 0, 0, 0.55)
	s.shadow_size = 16
	return s

## Raised buttons: a darker, thicker bottom edge reads as depth; hover lights the edge and adds a cyan glow;
## pressed swaps the thick edge to the top so the face looks pushed in
static func _button_styles(t: Theme, type: String) -> void:
	var normal := box(CARD, Color(CYAN, 0.28), 1, RADIUS, 8)
	normal.border_width_bottom = 3
	normal.border_color = Color(CYAN, 0.28)
	normal.shadow_color = Color(0, 0, 0, 0.45)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0, 2)
	t.set_stylebox("normal", type, normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = CARD_HOVER
	hover.border_color = CYAN
	hover.shadow_color = Color(CYAN, 0.4)
	hover.shadow_size = 10
	hover.shadow_offset = Vector2.ZERO
	t.set_stylebox("hover", type, hover)
	var pressed := box(CARD_PRESSED, CYAN_BRIGHT, 1, RADIUS, 8)
	pressed.border_width_top = 3
	pressed.shadow_color = Color(CYAN, 0.25)
	pressed.shadow_size = 4
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("hover_pressed", type, pressed)
	t.set_stylebox("disabled", type, box(Color(INSET, 0.8), OUTLINE, 1, RADIUS, 8))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, CYAN_BRIGHT)
	t.set_color("font_pressed_color", type, CYAN_BRIGHT)
	t.set_color("font_hover_pressed_color", type, CYAN_BRIGHT)
	t.set_color("font_disabled_color", type, TEXT_DIM.darkened(0.3))

## Filled call-to-action buttons (Battle!, Deal, Pull...): bright teal-cyan face, dark text, strong glow
static func _primary_button_styles(t: Theme) -> void:
	t.set_type_variation(&"PrimaryButton", &"Button")
	var normal := box(Color("#0FB5D6"), Color("#7DF3FF"), 1, RADIUS + 2, 10)
	normal.border_width_bottom = 4
	normal.border_color = Color("#06728A")
	normal.shadow_color = Color(CYAN, 0.35)
	normal.shadow_size = 10
	t.set_stylebox("normal", &"PrimaryButton", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#2BD4F2")
	hover.shadow_color = Color(CYAN_BRIGHT, 0.6)
	hover.shadow_size = 18
	t.set_stylebox("hover", &"PrimaryButton", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#0A93AF")
	pressed.border_width_bottom = 1
	pressed.border_width_top = 4
	pressed.shadow_size = 6
	t.set_stylebox("pressed", &"PrimaryButton", pressed)
	t.set_stylebox("hover_pressed", &"PrimaryButton", pressed)
	t.set_stylebox("disabled", &"PrimaryButton", box(Color("#1B3A47"), Color("#24505F"), 1, RADIUS + 2, 10))
	var dark := Color("#04121C")
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(key, &"PrimaryButton", dark)
	t.set_color("font_disabled_color", &"PrimaryButton", TEXT_DIM.darkened(0.2))

## A rounded flat box
static func box(bg: Color, border: Color, border_width: int, radius: int, margin: float = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if margin >= 0:
		s.set_content_margin_all(margin)
	return s

## The standard layered panel: translucent navy, faint cyan edge with a brighter top edge, soft drop shadow
static func panel_box(margin: float = -1) -> StyleBoxFlat:
	var s := box(PANEL, Color(CYAN, 0.16), 1, RADIUS, margin)
	s.border_width_top = 2
	s.border_color = Color(CYAN, 0.22)
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s

## A rounded box with a soft glow around it (used for hovered buttons and progress fills)
static func glow_box(bg: Color, radius: int, margin: float = -1, glow: Color = CYAN) -> StyleBoxFlat:
	var s := box(bg, Color.TRANSPARENT, 0, radius, margin)
	s.shadow_color = Color(glow, 0.45)
	s.shadow_size = 6
	return s

## A small rounded status chip, e.g. [In World]
static func tag(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := box(Color(color, 0.15), color, 1, 10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	chip.add_child(label)
	return chip

## Fills `rect` with a top-to-bottom gradient (per-vertex colours, so no texture is needed)
static func draw_vertical_gradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))

## Background pictures (Art/backgrounds/<name>.*), or null if the file isn't there
const BACKGROUND_DIR := "res://Art/backgrounds/"

static func background(bg_name: String) -> Texture2D:
	var path := CharacterData.find_art(BACKGROUND_DIR, bg_name)
	return load(path) as Texture2D if not path.is_empty() else null

## Draws a texture scaled to cover the rect (cropping the overflow, centred), like a CSS "cover" background
static func draw_texture_cover(ci: CanvasItem, texture: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var tex_size := texture.get_size()
	var scale := maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var src_size := rect.size / scale
	ci.draw_texture_rect_region(texture, rect, Rect2((tex_size - src_size) * 0.5, src_size), modulate)

## A soft radial glow: stacked translucent circles fading outward
static func draw_glow(ci: CanvasItem, center: Vector2, radius: float, color: Color, steps: int = 8) -> void:
	for i in steps:
		var f := 1.0 - float(i) / steps
		ci.draw_circle(center, radius * f, Color(color, color.a / steps))  # overlaps build up toward the centre
