class_name CurrencyChip
extends PanelContainer
## A gacha-style currency capsule for the header: a small procedurally drawn icon in a glowing disc, then the
## amount. Kinds: "money", "credit_card", and the material keys ("snack", "coffee", "gossip").
## The name of the currency shows as a tooltip.

const ICON_SIZE := 26.0
const KIND_COLORS := {
	"money": Color("#FCD34D"),
	"credit_card": UITheme.GOLD,
	"snack": Color("#D4D8DE"),  # Iron Ingot
	"coffee": Color("#4FE3E0"),  # Diamond
	"gossip": Color("#A08CB0"),  # Netherite Ingot
	"exp": Color("#93C5FD"),  # friends' EXP
	"account_exp": Color("#22D3EE"),
	"recruit_ticket": Color("#60A5FA"),
	"sr_ticket": Color("#E879F9"),
	"parts": Color("#F59E0B"),
}

var value_label: Label

## `tint` colours kinds without a fixed colour, e.g. "event" (an event's currency, in its event's colour)
func _init(kind: String, tooltip: String, tint: Color = Color(0, 0, 0, 0)) -> void:
	var color: Color = tint if tint.a > 0.0 else KIND_COLORS.get(kind, UITheme.CYAN)
	_color = color
	var style := UITheme.box(Color(UITheme.INSET, 0.85), Color(color, 0.55), 1, 18)
	style.content_margin_left = 4
	style.content_margin_right = 14
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.shadow_color = Color(color, 0.18)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	tooltip_text = tooltip
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var icon := ChipIcon.new()
	icon.kind = kind
	icon.color = color
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	row.add_child(icon)
	value_label = Label.new()
	value_label.add_theme_font_size_override("font_size", 17)
	value_label.add_theme_color_override("font_color", color.lightened(0.35) if kind == "credit_card" else UITheme.TEXT)
	row.add_child(value_label)

var _amount := -1  # -1 until the first set_amount (which shows the value straight away)
var _shown := 0.0
var _count_tween: Tween
var _color := UITheme.CYAN

## Shows a new amount. A change after the first counts up or down to it, the chip flashes, and the difference
## floats off it ("+600" rising in gold, "-150" sinking in red)
func set_amount(amount: int) -> void:
	if _amount < 0 or not is_inside_tree():
		_amount = amount
		_shown = amount
		value_label.text = _group(amount)
		return
	if amount == _amount:
		return
	var delta := amount - _amount
	_amount = amount
	if _count_tween:
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.tween_method(_show_value, _shown, float(amount), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	modulate = Color(1.45, 1.4, 1.2) if delta > 0 else Color(1.35, 0.8, 0.8)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.5)
	_float_delta(delta)

func _show_value(value: float) -> void:
	_shown = value
	value_label.text = _group(roundi(value))

## The change as a little label drifting away from the chip (top level, so the header's container can't move it)
func _float_delta(delta: int) -> void:
	var label := Label.new()
	label.text = ("+" if delta > 0 else "-") + _group(absi(delta))
	label.top_level = true
	label.z_index = 50
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", _color.lightened(0.3) if delta > 0 else Color("#f87171"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	label.reset_size()
	var start := global_position + Vector2(size.x - label.size.x - 10.0, size.y - 4.0)
	label.global_position = start
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "global_position:y", start.y + (14.0 if delta > 0 else 22.0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.6)
	t.chain().tween_callback(label.queue_free)

## 12500 -> "12,500"
static func _group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## The little drawn icon: a coloured disc with a simple symbol for each currency
class ChipIcon extends Control:
	var kind := "money"
	var color := Color.WHITE

	func _draw() -> void:
		CurrencyChip.draw_kind(self, size * 0.5, minf(size.x, size.y) * 0.5, kind, color)

## A currency's icon at `center` with radius `r` (the header chips, the Daily calendar and chests). Drawn with plain
## shapes only (no draw_set_transform), so it keeps whatever transform the caller has set, e.g. a pop animation.
## The materials are Minecraft ores: snack = Iron Ingot, coffee = Diamond, gossip = Netherite Ingot.
static func draw_kind(ci: CanvasItem, c: Vector2, r: float, kind: String, tint: Color = Color(0, 0, 0, 0)) -> void:
	var color: Color = tint if tint.a > 0.0 else KIND_COLORS.get(kind, UITheme.CYAN)
	ci.draw_circle(c, r, Color(color, 0.22))
	ci.draw_arc(c, r - 1, 0, TAU, 32, Color(color, 0.8), 1.5, true)
	var ink := color.lightened(0.2)
	var dark := Color(0, 0, 0, 0.5)
	match kind:
		"money":  # a coin with an inner ring and a vertical notch
			ci.draw_circle(c, r * 0.58, ink)
			ci.draw_arc(c, r * 0.4, 0, TAU, 24, Color(0, 0, 0, 0.35), 1.5, true)
			ci.draw_line(c + Vector2(0, -r * 0.25), c + Vector2(0, r * 0.25), Color(0, 0, 0, 0.45), 2.0)
		"credit_card":  # a tilted card with a magnetic stripe and chip
			var card := _tilted(c, Rect2(-r * 0.62, -r * 0.4, r * 1.24, r * 0.8), -0.25)
			ci.draw_colored_polygon(card, ink)
			ci.draw_colored_polygon(_tilted(c, Rect2(-r * 0.62, -r * 0.26, r * 1.24, r * 0.16), -0.25), dark)
			ci.draw_colored_polygon(_tilted(c, Rect2(-r * 0.48, r * 0.02, r * 0.26, r * 0.2), -0.25), Color("#B45309"))
		"snack":  # Iron Ingot: a pale ingot
			_ingot(ci, c, r, Color("#F1F3F6"), Color("#A7ADB6"), Color("#7C838D"))
		"coffee":  # Diamond: a cut gem with facets
			var top := c + Vector2(0, -r * 0.5)
			var gem := PackedVector2Array([c + Vector2(-r * 0.56, -r * 0.14), c + Vector2(-r * 0.3, -r * 0.46),
				c + Vector2(r * 0.3, -r * 0.46), c + Vector2(r * 0.56, -r * 0.14), c + Vector2(0, r * 0.6)])
			ci.draw_colored_polygon(gem, Color("#7FF7F2"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.56, -r * 0.14), c + Vector2(r * 0.56, -r * 0.14),
				c + Vector2(0, r * 0.6)]), Color("#2CC5C2"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, -r * 0.46), c + Vector2(0, -r * 0.14),
				c + Vector2(-r * 0.56, -r * 0.14)]), Color("#D6FFFD"))
			ci.draw_line(c + Vector2(-r * 0.56, -r * 0.14), c + Vector2(r * 0.56, -r * 0.14), Color(0, 0.3, 0.3, 0.5), 1.2, true)
			gem.append(gem[0])
			ci.draw_polyline(gem, Color(0, 0.25, 0.25, 0.7), 1.2, true)
			ci.draw_circle(top + Vector2(r * 0.2, r * 0.16), r * 0.06, Color.WHITE)
		"parts":  # a cog: eight teeth round a wheel with a hole
			for i in 8:
				var a := TAU * i / 8.0
				ci.draw_colored_polygon(_tilted(c + Vector2.from_angle(a) * r * 0.5, Rect2(-r * 0.12, -r * 0.1, r * 0.24, r * 0.2), a), ink)
			ci.draw_circle(c, r * 0.46, ink)
			ci.draw_circle(c, r * 0.18, Color(0, 0, 0, 0.55))
		"exp", "account_exp":  # EXP: a star (friends) or an up arrow (the account) over the letters "EXP"
			if kind == "exp":
				UITheme.draw_star(ci, c + Vector2(0, -r * 0.16), r * 0.4, ink)
			else:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.6), c + Vector2(r * 0.38, -r * 0.16),
					c + Vector2(r * 0.14, -r * 0.16), c + Vector2(r * 0.14, r * 0.12), c + Vector2(-r * 0.14, r * 0.12),
					c + Vector2(-r * 0.14, -r * 0.16), c + Vector2(-r * 0.38, -r * 0.16)]), ink)
			var font := ThemeDB.fallback_font
			var font_size := maxi(int(r * 0.42), 7)
			var w := font.get_string_size("EXP", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			ci.draw_string(font, c + Vector2(-w * 0.5, r * 0.62), "EXP", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		"event":  # an event's currency (e.g. Scraps): a hex nut in the event's colour
			var hexagon := PackedVector2Array()
			for i in 6:
				hexagon.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r * 0.6)
			ci.draw_colored_polygon(hexagon, ink)
			ci.draw_circle(c, r * 0.24, Color(0, 0, 0, 0.6))
			hexagon.append(hexagon[0])
			ci.draw_polyline(hexagon, color.darkened(0.45), 1.5, true)
		"recruit_ticket", "sr_ticket":  # a ticket with notched sides; the SR one has a star
			var t := Rect2(c.x - r * 0.62, c.y - r * 0.36, r * 1.24, r * 0.72)
			ci.draw_rect(t, ink)
			for side in [t.position.x, t.end.x]:
				ci.draw_circle(Vector2(side, c.y), r * 0.14, Color(color, 0.22).darkened(0.6))
			ci.draw_line(Vector2(c.x - r * 0.2, t.position.y + 2), Vector2(c.x - r * 0.2, t.end.y - 2), Color(0, 0, 0, 0.35), 1.0)
			if kind == "sr_ticket":
				UITheme.draw_star(ci, c + Vector2(r * 0.16, 0), r * 0.26, Color.WHITE)
			else:
				ci.draw_circle(c + Vector2(r * 0.16, 0), r * 0.12, Color(0, 0, 0, 0.4))
		"gossip":  # Netherite Ingot: a dark ingot with a purple sheen
			_ingot(ci, c, r, Color("#7A6E84"), Color("#4E4556"), Color("#241F27"))
			ci.draw_line(c + Vector2(-r * 0.22, -r * 0.2), c + Vector2(r * 0.1, -r * 0.2), Color("#B9A3CC"), 1.5, true)

## A Minecraft-style ingot seen from the front: a lighter top face over a darker trapezoid body
static func _ingot(ci: CanvasItem, c: Vector2, r: float, light: Color, mid: Color, dark: Color) -> void:
	var top := PackedVector2Array([c + Vector2(-r * 0.36, -r * 0.32), c + Vector2(r * 0.36, -r * 0.32),
		c + Vector2(r * 0.46, -r * 0.1), c + Vector2(-r * 0.46, -r * 0.1)])
	var body := PackedVector2Array([c + Vector2(-r * 0.46, -r * 0.1), c + Vector2(r * 0.46, -r * 0.1),
		c + Vector2(r * 0.62, r * 0.34), c + Vector2(-r * 0.62, r * 0.34)])
	ci.draw_colored_polygon(body, mid)
	ci.draw_colored_polygon(top, light)
	ci.draw_line(c + Vector2(-r * 0.62, r * 0.34), c + Vector2(r * 0.62, r * 0.34), dark, 2.0)
	body.append(body[0])
	ci.draw_polyline(body, dark, 1.2, true)

## A rectangle (around the origin) rotated by `angle` and moved to `at`, as a polygon
static func _tilted(at: Vector2, rect: Rect2, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		out.append(at + (p as Vector2).rotated(angle))
	return out
