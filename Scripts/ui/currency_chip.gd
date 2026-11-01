class_name CurrencyChip
extends PanelContainer
## A gacha-style currency capsule for the header: a small procedurally drawn icon in a glowing disc, then the
## amount. Kinds: "money", "credit_card", and the material keys ("snack", "coffee", "gossip").
## The name of the currency shows as a tooltip.

const ICON_SIZE := 26.0
const KIND_COLORS := {
	"money": Color("#FCD34D"),
	"credit_card": UITheme.GOLD,
	"snack": Color("#F59E0B"),
	"coffee": Color("#C08457"),
	"gossip": Color("#F472B6"),
}

var value_label: Label

func _init(kind: String, tooltip: String) -> void:
	var color: Color = KIND_COLORS.get(kind, UITheme.CYAN)
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

func set_amount(amount: int) -> void:
	value_label.text = _group(amount)

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
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color(color, 0.22))
		draw_arc(c, r - 1, 0, TAU, 32, Color(color, 0.8), 1.5, true)
		var ink := color.lightened(0.2)
		match kind:
			"money":  # a coin with an inner ring and a vertical notch
				draw_circle(c, r * 0.58, ink)
				draw_arc(c, r * 0.4, 0, TAU, 24, Color(0, 0, 0, 0.35), 1.5, true)
				draw_line(c + Vector2(0, -r * 0.25), c + Vector2(0, r * 0.25), Color(0, 0, 0, 0.45), 2.0)
			"credit_card":  # a tilted card with a magnetic stripe and chip
				draw_set_transform(c, -0.25, Vector2.ONE)
				var card := Rect2(-r * 0.62, -r * 0.4, r * 1.24, r * 0.8)
				draw_rect(card, ink)
				draw_rect(Rect2(card.position.x, card.position.y + r * 0.14, card.size.x, r * 0.16), Color(0, 0, 0, 0.5))
				draw_rect(Rect2(card.position.x + r * 0.14, card.position.y + r * 0.42, r * 0.26, r * 0.2), Color("#B45309"))
				draw_set_transform(Vector2.ZERO)
			"snack":  # a cookie with chips
				draw_circle(c, r * 0.58, ink)
				for p in [Vector2(-0.22, -0.18), Vector2(0.2, -0.1), Vector2(-0.05, 0.22), Vector2(0.25, 0.25)]:
					draw_circle(c + p * r, r * 0.09, Color("#4A2C0A"))
			"coffee":  # a cup with a handle and steam
				var cup := Rect2(c.x - r * 0.42, c.y - r * 0.12, r * 0.64, r * 0.55)
				draw_rect(cup, ink)
				draw_arc(c + Vector2(r * 0.26, r * 0.14), r * 0.17, -PI / 2, PI / 2, 12, ink, 2.0, true)
				for dx in [-0.22, 0.02]:
					draw_line(c + Vector2(dx * r, -r * 0.24), c + Vector2(dx * r + r * 0.06, -r * 0.48), Color(ink, 0.8), 1.5, true)
			"gossip":  # a speech bubble with three dots
				draw_circle(c + Vector2(0, -r * 0.05), r * 0.52, ink)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.25), c + Vector2(-r * 0.05, r * 0.4), c + Vector2(-r * 0.45, r * 0.62)]), ink)
				for dx in [-0.22, 0.0, 0.22]:
					draw_circle(c + Vector2(dx * r, -r * 0.05), r * 0.07, Color(0, 0, 0, 0.55))
