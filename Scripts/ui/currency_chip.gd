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
	"parts": Color("#F59E0B"),
}

var value_label: Label

func _init(kind: String, tooltip: String) -> void:
	var color: Color = KIND_COLORS.get(kind, UITheme.CYAN)
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
			"parts":  # a cog: eight teeth round a wheel with a hole
				for i in 8:
					var a := TAU * i / 8.0
					draw_set_transform(c + Vector2.from_angle(a) * r * 0.5, a, Vector2.ONE)
					draw_rect(Rect2(-r * 0.12, -r * 0.1, r * 0.24, r * 0.2), ink)
				draw_set_transform(Vector2.ZERO)
				draw_circle(c, r * 0.46, ink)
				draw_circle(c, r * 0.18, Color(0, 0, 0, 0.55))
			"gossip":  # a speech bubble with three dots
				draw_circle(c + Vector2(0, -r * 0.05), r * 0.52, ink)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.3, r * 0.25), c + Vector2(-r * 0.05, r * 0.4), c + Vector2(-r * 0.45, r * 0.62)]), ink)
				for dx in [-0.22, 0.0, 0.22]:
					draw_circle(c + Vector2(dx * r, -r * 0.05), r * 0.07, Color(0, 0, 0, 0.55))
