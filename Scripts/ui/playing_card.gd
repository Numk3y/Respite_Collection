class_name PlayingCard
extends Control
## A playing card drawn with shapes rather than font glyphs: the web build's default font has no card-suit
## characters, so suits are drawn as polygons and circles. Face down it shows the game's card back.

const SIZE := Vector2(72, 102)
const RED := Color("#E11D48")
const BLACK := Color("#111827")

var card: Dictionary = {}
var face_up := true

func _init(c: Dictionary = {}, up: bool = true) -> void:
	card = c
	face_up = up
	custom_minimum_size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_face_up(up: bool) -> void:
	face_up = up
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, SIZE)
	if not face_up:
		draw_style_box(UITheme.box(UITheme.CARD_PRESSED, UITheme.CYAN, 2, 8), rect)
		var inner := rect.grow(-7)
		draw_style_box(UITheme.box(Color(0, 0, 0, 0), Color(UITheme.CYAN, 0.35), 1, 5), inner)
		for row in 5:
			for col in 3:
				_draw_suit(inner.position + Vector2(10 + col * 19, 10 + row * 17), 4.0, 2, Color(UITheme.CYAN, 0.25))
		return
	draw_style_box(UITheme.box(Color("#F8FAFC"), Color("#CBD5E1"), 1, 8), rect)
	var color := RED if card.suit in [1, 2] else BLACK
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(7, 22), card.rank, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
	_draw_suit(Vector2(15, 37), 7.5, card.suit, color)
	_draw_suit(SIZE * Vector2(0.5, 0.6), 17.0, card.suit, color)

func _draw_suit(c: Vector2, s: float, suit: int, color: Color) -> void:
	match suit:
		0:  # spade: an upside-down heart on a stem
			_heart(c + Vector2(0, -s * 0.15), s, color, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.2), c + Vector2(-s * 0.4, s * 1.0), c + Vector2(s * 0.4, s * 1.0)]), color)
		1:
			_heart(c, s, color, false)
		2:  # diamond
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.72, 0), c + Vector2(0, s), c + Vector2(-s * 0.72, 0)]), color)
		3:  # club: three circles on a stem
			draw_circle(c + Vector2(0, -s * 0.45), s * 0.42, color)
			draw_circle(c + Vector2(-s * 0.45, s * 0.1), s * 0.42, color)
			draw_circle(c + Vector2(s * 0.45, s * 0.1), s * 0.42, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, s * 0.1), c + Vector2(-s * 0.35, s * 0.95), c + Vector2(s * 0.35, s * 0.95)]), color)

func _heart(c: Vector2, s: float, color: Color, flipped: bool) -> void:
	var f := -1.0 if flipped else 1.0
	draw_circle(c + Vector2(-s * 0.45, -s * 0.2 * f), s * 0.5, color)
	draw_circle(c + Vector2(s * 0.45, -s * 0.2 * f), s * 0.5, color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.93, -s * 0.05 * f), c + Vector2(s * 0.93, -s * 0.05 * f), c + Vector2(0, s * 0.95 * f)]), color)
