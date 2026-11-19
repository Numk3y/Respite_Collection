class_name AHKit
extends RefCounted
## The After Hours look, shared by EndlessScreen and AfterHoursMap: neon-night colours, glass panels, drawn icons
## (map nodes, Drinks), portraits with HP and Ultimate bars, the neon sign and small effects. Everything is drawn
## with shapes (no emoji or symbol glyphs: the web font doesn't have them).
##
## Animation rule: anything that scales, lifts or shakes lives inside a plain Control holder, never straight in a
## Container (containers reset a child's transform on every re-layout).

const ACCENT := Color("#c084fc")  # neon purple
const PINK := Color("#f472b6")
const HOT := Color("#ff4d8d")  # warnings, bosses
const HANGOVER := Color("#f87171")
const TIPS := Color("#4ade80")
const INK := Color(0.03, 0.03, 0.07)
const NODE_COLORS := {"battle": Color("#7dd3fc"), "elite": Color("#f87171"), "event": Color("#c084fc"),
	"rest": Color("#4ade80"), "bar": Color("#fbbf24"), "boss": Color("#ff4d8d"),
	"revive": Color("#f472b6"), "train": Color("#fb923c")}  # the last two are icons only (Rest, Bar services)
const RARITY := [Color("#cbd5e1"), Color("#60a5fa"), Color("#fbbf24")]
## Liquid colours, picked per Drink from its id so each one keeps its look
const LIQUIDS := [Color("#fbbf24"), Color("#f472b6"), Color("#60a5fa"), Color("#4ade80"), Color("#f97316"),
	Color("#a78bfa"), Color("#22d3ee"), Color("#ef4444")]

# ───────── Builders ─────────

static func label(text: String, font_size: int = 15, color: Color = UITheme.TEXT, wrap := false, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## A dark glass panel with a thin neon edge and a soft glow
static func glass(glow: Color = ACCENT, margin: float = 14.0, alpha: float = 0.86, radius: int = 14) -> StyleBoxFlat:
	var s := UITheme.box(Color(0.035, 0.035, 0.08, alpha), Color(glow, 0.55), 1, radius, margin)
	s.border_width_top = 2
	s.border_color = Color(glow, 0.7)
	s.shadow_color = Color(glow, 0.22)
	s.shadow_size = 14
	return s

static func panel(glow: Color = ACCENT, margin: float = 14.0, alpha: float = 0.86) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", glass(glow, margin, alpha))
	return p

static func vbox(sep: int = 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

static func hbox(sep: int = 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b

static func spacer(vertical := true) -> Control:
	var c := Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## A slanted neon button (the big calls to action are `primary`: filled; the rest outlined)
static func button(text: String, callback: Callable, color: Color = ACCENT, primary := false, min_size := Vector2(0, 44),
		font_size := 17) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", font_size)
	var normal := UITheme.box(color.darkened(0.35) if primary else Color(color, 0.12), color.lightened(0.2), 2 if primary else 1, 6, 10)
	normal.skew = Vector2(0.18, 0)
	normal.shadow_color = Color(color, 0.35 if primary else 0.12)
	normal.shadow_size = 10 if primary else 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = color.darkened(0.15) if primary else Color(color, 0.26)
	hover.shadow_size = 16
	hover.border_color = Color.WHITE if primary else color.lightened(0.4)
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.45)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.1, 0.1, 0.14, 0.7)
	disabled.border_color = Color(1, 1, 1, 0.12)
	disabled.shadow_size = 0
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color.WHITE if primary else color.lightened(0.45))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	b.add_theme_constant_override("outline_size", 4 if primary else 0)
	b.pressed.connect(callback)
	return b

## A small rounded chip (rarity, status, target)
static func chip(text: String, color: Color, solid := false) -> PanelContainer:
	return UITheme.tag(text, color, solid)

## Fades and slides a node in. Only for nodes in a plain Control holder (see the animation rule above), or for a
## modulate-only fade (`offset` zero) on anything.
static func pop_in(node: CanvasItem, delay: float = 0.0, offset := Vector2(0, 26), seconds := 0.38) -> void:
	node.modulate.a = 0.0
	var t := node.create_tween().set_parallel()
	t.tween_property(node, "modulate:a", 1.0, seconds * 0.7).set_delay(delay)
	if offset != Vector2.ZERO and node is Control:
		# Slides by shifting all four offsets, never `position`: before the first layout a card is still squeezed to
		# its minimum size, and setting `position` then would bake that size into its offsets for good
		var c := node as Control
		var base := Vector4(c.offset_left, c.offset_top, c.offset_right, c.offset_bottom)
		_shift(c, base, offset)
		t.tween_method(func(k: float): _shift(c, base, offset * k), 1.0, 0.0, seconds).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func _shift(c: Control, base: Vector4, by: Vector2) -> void:
	c.offset_left = base.x + by.x
	c.offset_right = base.z + by.x
	c.offset_top = base.y + by.y
	c.offset_bottom = base.w + by.y

## Puts `child` in a plain Control of `min_size` so it can lift, scale and slide freely; returns the holder
static func hold(child: Control, min_size: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = min_size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(child)
	# Anchored (not sized by hand): the card always matches the holder, even after wrapping text first measured
	# itself at zero width and asked for a huge height
	child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	child.pivot_offset = min_size / 2.0
	holder.resized.connect(func(): child.pivot_offset = holder.size / 2.0)
	return holder

## Hover lift for a held card (see hold)
static func lift(card: Control, on: bool) -> void:
	var t := card.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	t.tween_property(card, "position:y", -8.0 if on else 0.0, 0.14)
	t.tween_property(card, "scale", Vector2(1.035, 1.035) if on else Vector2.ONE, 0.14)

# ───────── Drawn icons ─────────

## A map node's symbol in a disc: crossed glasses-bottles for fights... kept simple and readable at small sizes
static func draw_node_icon(ci: CanvasItem, c: Vector2, r: float, type: String, ink: Color) -> void:
	var w := maxf(r * 0.13, 1.6)
	match type:
		"battle":  # two crossed swords
			for s in [-1.0, 1.0]:
				var a := Vector2(-0.55 * s, 0.55) * r
				var b := Vector2(0.5 * s, -0.5) * r
				ci.draw_line(c + a, c + b, ink, w, true)
				var g := c + a.lerp(b, 0.22)
				var n := (b - a).normalized().orthogonal() * r * 0.2
				ci.draw_line(g - n, g + n, ink, w, true)
		"elite":  # a horned skull
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.42, -0.22) * r, c + Vector2(-0.72, -0.72) * r, c + Vector2(-0.16, -0.38) * r]), ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.42, -0.22) * r, c + Vector2(0.72, -0.72) * r, c + Vector2(0.16, -0.38) * r]), ink)
			ci.draw_circle(c + Vector2(0, -0.04) * r, r * 0.44, ink)
			ci.draw_rect(Rect2(c + Vector2(-0.24, 0.2) * r, Vector2(0.48, 0.3) * r), ink)
			ci.draw_circle(c + Vector2(-0.17, -0.06) * r, r * 0.12, INK)
			ci.draw_circle(c + Vector2(0.17, -0.06) * r, r * 0.12, INK)
			for x in [-0.1, 0.1]:
				ci.draw_line(c + Vector2(x, 0.24) * r, c + Vector2(x, 0.48) * r, INK, maxf(w * 0.6, 1.0))
		"event":  # a speech bubble with a question mark
			ci.draw_circle(c + Vector2(0, -0.06) * r, r * 0.5, ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, 0.2) * r, c + Vector2(-0.46, 0.6) * r, c + Vector2(0.02, 0.36) * r]), ink)
			var font := ThemeDB.fallback_font
			var fs := maxi(int(r * 0.8), 8)
			var sw := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			ci.draw_string(font, c + Vector2(-sw * 0.5, r * 0.2), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)
		"rest":  # a crescent moon and a little star
			ci.draw_circle(c + Vector2(-0.06, 0.02) * r, r * 0.5, ink)
			ci.draw_circle(c + Vector2(0.16, -0.12) * r, r * 0.42, INK.lerp(ink, 0.12))
			UITheme.draw_star(ci, c + Vector2(0.4, 0.34) * r, r * 0.18, ink)
		"bar":  # a cocktail glass with an olive
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.56, -0.48) * r, c + Vector2(0.56, -0.48) * r, c + Vector2(0, 0.12) * r]), ink)
			ci.draw_line(c + Vector2(0, 0.12) * r, c + Vector2(0, 0.5) * r, ink, w, true)
			ci.draw_line(c + Vector2(-0.3, 0.52) * r, c + Vector2(0.3, 0.52) * r, ink, w, true)
			ci.draw_circle(c + Vector2(0.18, -0.6) * r, r * 0.12, ink)
		"revive":  # a heart with a plus
			ci.draw_circle(c + Vector2(-0.24, -0.16) * r, r * 0.3, ink)
			ci.draw_circle(c + Vector2(0.24, -0.16) * r, r * 0.3, ink)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.52, -0.06) * r, c + Vector2(0.52, -0.06) * r, c + Vector2(0, 0.56) * r]), ink)
			ci.draw_line(c + Vector2(0, -0.26) * r, c + Vector2(0, 0.14) * r, INK, w, true)
			ci.draw_line(c + Vector2(-0.2, -0.06) * r, c + Vector2(0.2, -0.06) * r, INK, w, true)
		"train":  # a dumbbell
			ci.draw_line(c + Vector2(-0.5, 0) * r, c + Vector2(0.5, 0) * r, ink, w * 1.2, true)
			for s in [-1.0, 1.0]:
				ci.draw_rect(Rect2(c + Vector2(0.34 * s - 0.1, -0.36) * r, Vector2(0.2, 0.72) * r), ink)
				ci.draw_rect(Rect2(c + Vector2(0.56 * s - 0.07, -0.22) * r, Vector2(0.14, 0.44) * r), ink)
		"boss":  # a crown with three gems
			var crown := PackedVector2Array([c + Vector2(-0.62, 0.38) * r, c + Vector2(-0.62, -0.3) * r, c + Vector2(-0.3, 0.02) * r,
				c + Vector2(0, -0.5) * r, c + Vector2(0.3, 0.02) * r, c + Vector2(0.62, -0.3) * r, c + Vector2(0.62, 0.38) * r])
			ci.draw_colored_polygon(crown, ink)
			for x in [-0.32, 0.0, 0.32]:
				ci.draw_circle(c + Vector2(x, 0.2) * r, r * 0.09, INK)

## A Drink as a glass in `rect`: Commons are beer mugs, Rares cocktail glasses, Legendaries a glowing bottle,
## Hangovers a cracked tumbler. `t` animates the bubbles.
static func draw_drink(ci: CanvasItem, rect: Rect2, d: DrinkData, t: float = 0.0) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var liquid: Color = LIQUIDS[absi(hash(String(d.id))) % LIQUIDS.size()] if not d.hangover else Color("#7f1d1d")
	var glass := Color(1, 1, 1, 0.85)
	var glow: Color = HANGOVER if d.hangover else RARITY[d.rarity]
	UITheme.draw_glow(ci, c, r * 0.95, Color(glow, 0.18 if d.rarity == 0 else 0.3))
	if d.hangover:
		var cup := PackedVector2Array([c + Vector2(-0.42, -0.5) * r, c + Vector2(0.42, -0.5) * r, c + Vector2(0.34, 0.55) * r, c + Vector2(-0.34, 0.55) * r])
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.38, 0.05) * r, c + Vector2(0.38, 0.05) * r, c + Vector2(0.34, 0.55) * r, c + Vector2(-0.34, 0.55) * r]), liquid)
		cup.append(cup[0])
		ci.draw_polyline(cup, glass, 2.0, true)
		ci.draw_polyline(PackedVector2Array([c + Vector2(-0.1, -0.5) * r, c + Vector2(0.02, -0.2) * r, c + Vector2(-0.12, 0.0) * r, c + Vector2(0.06, 0.24) * r]), HANGOVER.lightened(0.3), 2.0, true)
		return
	match d.rarity:
		DrinkData.Rarity.COMMON:  # a beer mug with foam
			var body := Rect2(c + Vector2(-0.4, -0.38) * r, Vector2(0.72, 0.95) * r)
			ci.draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.22), Vector2(body.size.x, body.size.y * 0.78)), liquid)
			for i in 4:
				ci.draw_circle(body.position + Vector2(body.size.x * (0.12 + 0.26 * i), body.size.y * 0.16), r * 0.15, Color(1, 1, 1, 0.95))
			ci.draw_rect(body, glass, false, 2.0)
			ci.draw_arc(c + Vector2(0.38, 0.08) * r, r * 0.2, -PI / 2, PI / 2, 12, glass, 2.0, true)
			_bubbles(ci, body, t, 3)
		DrinkData.Rarity.RARE:  # a cocktail glass with a slice
			var top_y := -0.5
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.48, top_y + 0.08) * r, c + Vector2(0.48, top_y + 0.08) * r, c + Vector2(0, 0.14) * r]), liquid)
			var cone := PackedVector2Array([c + Vector2(-0.56, top_y) * r, c + Vector2(0.56, top_y) * r, c + Vector2(0, 0.16) * r, c + Vector2(-0.56, top_y) * r])
			ci.draw_polyline(cone, glass, 2.0, true)
			ci.draw_line(c + Vector2(0, 0.16) * r, c + Vector2(0, 0.56) * r, glass, 2.0, true)
			ci.draw_line(c + Vector2(-0.28, 0.58) * r, c + Vector2(0.28, 0.58) * r, glass, 2.0, true)
			ci.draw_circle(c + Vector2(0.44, top_y) * r, r * 0.16, Color("#facc15"))
			ci.draw_circle(c + Vector2(0.44, top_y) * r, r * 0.09, Color("#fde68a"))
		_:  # a tall bottle with a shine and sparkles
			var neck := Rect2(c + Vector2(-0.1, -0.66) * r, Vector2(0.2, 0.3) * r)
			var body := PackedVector2Array([c + Vector2(-0.1, -0.36) * r, c + Vector2(0.1, -0.36) * r, c + Vector2(0.34, -0.1) * r,
				c + Vector2(0.34, 0.6) * r, c + Vector2(-0.34, 0.6) * r, c + Vector2(-0.34, -0.1) * r])
			ci.draw_colored_polygon(body, liquid.darkened(0.15))
			ci.draw_rect(neck, liquid.darkened(0.3))
			ci.draw_rect(Rect2(c + Vector2(-0.34, 0.06) * r, Vector2(0.68, 0.26) * r), Color("#fde68a"))
			body.append(body[0])
			ci.draw_polyline(body, glass, 2.0, true)
			ci.draw_line(c + Vector2(-0.2, -0.04) * r, c + Vector2(-0.2, 0.0) * r, Color(1, 1, 1, 0.7), 3.0)
			for i in 3:
				var k := fmod(t * 0.7 + i / 3.0, 1.0)
				UITheme.draw_star(ci, c + Vector2.from_angle(TAU * (i / 3.0) + t * 0.5) * r * (0.7 + 0.1 * sin(t * 3 + i)),
					r * 0.09 * sin(k * PI), Color(1, 0.95, 0.6, 0.9))

static func _bubbles(ci: CanvasItem, body: Rect2, t: float, count: int) -> void:
	for i in count:
		var k := fmod(t * 0.45 + i / float(count), 1.0)
		var p := Vector2(body.position.x + body.size.x * (0.25 + 0.25 * i), lerpf(body.end.y - 4, body.position.y + body.size.y * 0.3, k))
		ci.draw_circle(p, 2.0, Color(1, 1, 1, 0.55 * sin(k * PI)))

# ───────── Small drawn controls ─────────

## A map-node symbol in a glowing disc (legends, info cards, encounter headers)
class NodeBadge extends Control:
	var type := "battle"
	func _init(t: String = "battle", px: float = 34.0) -> void:
		type = t
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 1.0
		var color: Color = AHKit.NODE_COLORS.get(type, Color.WHITE)
		draw_circle(c, r, color.darkened(0.55))
		draw_arc(c, r, 0, TAU, 32, color, 2.0, true)
		AHKit.draw_node_icon(self, c, r * 0.8, type, color.lightened(0.35))

## A Drink's glass, with bubbles and sparkles moving
class DrinkArt extends Control:
	var drink: DrinkData
	var _t := 0.0
	func _init(d: DrinkData) -> void:
		drink = d
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_t = randf() * 5.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		if drink:
			AHKit.draw_drink(self, Rect2(Vector2.ZERO, size), drink, _t)

## A friend's picture in a rounded frame with an HP bar, an Ultimate bar, a row tag and a knocked-out cross.
## Drawn in one piece, so it can sit straight in containers.
class Portrait extends Control:
	var character: CharacterData
	var hp := 1.0
	var energy := 0.0  # share of the gauge, -1 = no Ultimate
	var ko := false
	var dim := false  # benched
	var tag := ""  # "F" / "B" corner tag
	var ring := Color(0, 0, 0, 0)  # highlight border (e.g. fielded)
	var show_bars := true
	var show_name := false  # the name on a dark strip along the bottom of the picture
	var _tex: Texture2D

	func _init(c: CharacterData = null) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		set_character(c)

	func set_character(c: CharacterData) -> void:
		character = c
		_tex = c.get_avatar() if c else null
		queue_redraw()

	func _draw() -> void:
		var bars := 14.0 if show_bars else 0.0
		var art := Rect2(Vector2.ZERO, Vector2(size.x, size.y - bars))
		var rarity: Color = CharArt.RARITY_COLORS.get(character.rarity, UITheme.CYAN) if character else UITheme.TEXT_DIM
		draw_rect(art, Color(0.08, 0.08, 0.14))
		var tint := Color(0.35, 0.35, 0.4) if ko else (Color(0.6, 0.6, 0.66) if dim else Color.WHITE)
		var font := ThemeDB.fallback_font
		if _tex:
			UITheme.draw_texture_cover(self, _tex, art.grow(-2), tint)
		elif character:
			_placeholder(art.grow(-2), tint, rarity)
		if show_name and character:
			var text := character.display_name
			var fs := clampi(int(art.size.x * 0.17), 10, 16)
			while fs > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > art.size.x - 6:
				fs -= 1  # shrink a long name to fit before it gets cut
			var strip := Rect2(art.position.x, art.end.y - fs - 8, art.size.x, fs + 8)
			UITheme.draw_vertical_gradient(self, Rect2(strip.position - Vector2(0, 10), strip.size + Vector2(0, 10)), Color(0, 0, 0, 0), Color(0, 0, 0, 0.85))
			var w := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, art.size.x - 6)
			draw_string(font, Vector2(art.position.x + (art.size.x - w) / 2.0, strip.end.y - 6), text, HORIZONTAL_ALIGNMENT_LEFT, art.size.x - 6, fs, Color.WHITE * tint)
		draw_rect(art, ring if ring.a > 0 else Color(rarity, 0.75), false, 2.0 if ring.a > 0 else 1.5)
		if not tag.is_empty():
			draw_rect(Rect2(art.position + Vector2(2, 2), Vector2(16, 16)), Color(0, 0, 0, 0.7))
			draw_string(font, art.position + Vector2(5, 15), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ring if ring.a > 0 else Color.WHITE)
		if ko:
			var p := art.grow(-art.size.x * 0.2)
			draw_line(p.position, p.end, AHKit.HANGOVER, 4.0, true)
			draw_line(Vector2(p.end.x, p.position.y), Vector2(p.position.x, p.end.y), AHKit.HANGOVER, 4.0, true)
		if show_bars:
			var y := art.end.y + 3
			var hp_rect := Rect2(0, y, size.x, 6)
			draw_rect(hp_rect, Color(0, 0, 0, 0.6))
			var share := 0.0 if ko else clampf(hp, 0.0, 1.0)
			var hp_color := Color("#4ade80") if share > 0.5 else (Color("#fbbf24") if share > 0.25 else Color("#ef4444"))
			draw_rect(Rect2(hp_rect.position, Vector2(hp_rect.size.x * share, hp_rect.size.y)), hp_color)
			if energy >= 0.0:
				var e_rect := Rect2(0, y + 7, size.x, 3)
				draw_rect(e_rect, Color(0, 0, 0, 0.6))
				draw_rect(Rect2(e_rect.position, Vector2(e_rect.size.x * clampf(energy, 0.0, 1.0), 3)), Color("#facc15"))

	## No picture yet: the class colour as a lit gradient with light stripes, a rarity glow, the initial, and the
	## class name when there's room (matches CharArt's placeholder card)
	func _placeholder(r: Rect2, tint: Color, rarity: Color) -> void:
		var base: Color = CharArt.CLASS_COLORS.get(character.char_class, CharArt.MYSTERY_COLOR)
		UITheme.draw_vertical_gradient(self, r, base.lightened(0.2) * tint, base.darkened(0.6) * tint)
		UITheme.draw_glow(self, r.position + r.size * Vector2(0.5, 0.4), r.size.x * 0.6, Color(rarity, 0.3 * tint.r), 5)
		var x := r.position.x - r.size.y
		while x < r.end.x:
			var a := Vector2(maxf(x, r.position.x), r.end.y - maxf(r.position.x - x, 0.0))
			var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + maxf(x + r.size.y - r.end.x, 0.0))
			draw_line(a, b, Color(1, 1, 1, 0.05), 4.0)
			x += 16.0
		var font := ThemeDB.fallback_font
		var fs := int(minf(r.size.y * 0.42, r.size.x * 0.6))
		var letter := character.display_name.left(1).to_upper()
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cy := r.position.y + r.size.y * (0.42 if r.size.x >= 80 else 0.5)
		draw_string_outline(font, Vector2(r.get_center().x - w / 2, cy + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.35))
		draw_string(font, Vector2(r.get_center().x - w / 2, cy + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.85) * tint)
		if r.size.x >= 80 and not show_name:
			var cls := Terms.class_label(character.char_class)
			var cfs := 12
			var cw := font.get_string_size(cls, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
			draw_string(font, Vector2(r.get_center().x - cw / 2, r.end.y - 10), cls, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Color(1, 1, 1, 0.7) * tint)

## "AFTER HOURS" as a flickering neon sign: a soft glow, a bright core, and a rare flicker
class NeonSign extends Control:
	var text := ""
	var color := AHKit.PINK
	var font_size := 64
	var _t := 0.0
	var _flicker := 0.0

	func _init(t: String = "", c: Color = AHKit.PINK, fs: int = 64) -> void:
		text = t
		color = c
		font_size = fs
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, fs * 1.25)

	func _process(delta: float) -> void:
		_t += delta
		if _flicker > 0.0:
			_flicker -= delta
		elif randf() < delta * 0.25:
			_flicker = 0.18
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2((size.x - w) / 2.0, size.y * 0.5 + font_size * 0.36)
		var on := 1.0 if _flicker <= 0.0 or fmod(_t * 30.0, 2.0) < 1.0 else 0.35
		var hum := 0.85 + 0.15 * sin(_t * 2.3)
		for spread in [6, 4, 2]:
			for dir in [Vector2(spread, 0), Vector2(-spread, 0), Vector2(0, spread), Vector2(0, -spread)]:
				draw_string(font, pos + dir, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, 0.07 * on * hum))
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(color, 0.9 * on))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.94, 0.98, on))

## The screen backdrop: a blurred picture, a purple-to-black gradient and slow drifting haze
class Backdrop extends Control:
	var texture: Texture2D
	var tint := Color(0.55, 0.45, 0.7)
	var _t := 0.0

	func _init(tex: Texture2D) -> void:
		texture = UITheme.blurred(tex, 10.0) if tex else null
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.015, 0.05))
		if texture:
			UITheme.draw_texture_cover(self, texture, r, Color(tint, 0.55))
		UITheme.draw_vertical_gradient(self, r, Color(0.08, 0.02, 0.14, 0.35), Color(0.0, 0.0, 0.03, 0.85))
		for i in 3:
			var c := Vector2(size.x * (0.2 + 0.3 * i) + sin(_t * 0.15 + i) * 60.0, size.y * (0.3 + 0.2 * i))
			UITheme.draw_glow(self, c, size.y * 0.35, Color([AHKit.ACCENT, AHKit.PINK, UITheme.CYAN][i], 0.05), 6)

## The Night's floors as a row of pips: cleared ones lit, the current one bright, the boss a bigger diamond
class FloorTrack extends Control:
	var floors := 15
	var current := -1  # 0-based floor the squad is on (-1 = not started)
	var color := AHKit.ACCENT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(240, 16)

	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (floors - 1)) / floors
		for i in floors:
			var x := i * (w + gap)
			var r := Rect2(x, size.y * 0.5 - 4, w, 8)
			var col := Color(1, 1, 1, 0.12)
			if i < current:
				col = Color(color, 0.85)
			elif i == current:
				col = Color.WHITE
			if i == floors - 1:
				var c := r.get_center()
				var d := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
				draw_colored_polygon(d, AHKit.HOT if i > current else col)
			else:
				draw_rect(r, col)

## A rubber "SOLD" stamp across an item
class Stamp extends Control:
	var text := "SOLD"
	var color := AHKit.HANGOVER
	func _init(t: String = "SOLD", c: Color = AHKit.HANGOVER) -> void:
		text = t
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var fs := int(clampf(size.y * 0.32, 14, 40))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(size / 2.0, -0.22, Vector2.ONE)
		var box := Rect2(Vector2(-w / 2 - 10, -fs * 0.75), Vector2(w + 20, fs * 1.3))
		draw_rect(box, Color(color, 0.18))
		draw_rect(box, color, false, 3.0)
		draw_string(font, Vector2(-w / 2, fs * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		draw_set_transform(Vector2.ZERO)

## Diagonal warning stripes scrolling sideways (Elite and Boss encounters)
class Hazard extends Control:
	var color := AHKit.HOT
	var _t := 0.0
	func _init(c: Color = AHKit.HOT) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 14)
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		var step := 22.0
		var off := fmod(_t * 30.0, step)
		var x := -step * 2 + off
		while x < size.x + step:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + step * 0.5, 0), Vector2(x + step, 0), Vector2(x + step * 0.5, size.y)]), Color(color, 0.85))
			x += step
