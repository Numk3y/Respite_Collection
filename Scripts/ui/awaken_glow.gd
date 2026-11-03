class_name AwakenGlow
extends Control
## The max-Ascension ("awakened") look laid over a friend's picture: a rainbow border whose colours flow around
## it, a soft prismatic shimmer across the art, a few sparkles twinkling at random spots and a "MAX" tag in the
## top-right corner. Add it as a full-rect child over the art.

const SPARKLES := 6

var _t := 0.0
var _sparkles: Array[Vector3] = []  # x, y (0-1) and phase

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in SPARKLES:
		_sparkles.append(Vector3(randf(), randf() * 0.8, randf() * TAU))

func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# Prismatic shimmer: a faint rainbow wash drifting across
	var hue := fmod(_t * 0.15, 1.0)
	draw_rect(r, Color.from_hsv(hue, 0.6, 1.0, 0.08))
	# Rainbow border: short segments around the edge, each a hue that moves along with time
	var perimeter := 2.0 * (size.x + size.y)
	var segments := 48
	for i in segments:
		var a := _edge_point(perimeter * i / segments)
		var b := _edge_point(perimeter * (i + 1) / segments)
		var h := fmod(float(i) / segments - _t * 0.25, 1.0)
		draw_line(a, b, Color.from_hsv(h, 0.75, 1.0, 0.95), 3.0, true)
		draw_line(a, b, Color.from_hsv(h, 0.6, 1.0, 0.25), 8.0, true)
	# Twinkles: each sparkle fades in and out on its own beat
	for s in _sparkles:
		var k := maxf(sin(_t * 2.2 + s.z), 0.0)
		if k <= 0.05:
			continue
		var p := Vector2(s.x * size.x, s.y * size.y)
		var arm := 7.0 * k
		draw_line(p - Vector2(arm, 0), p + Vector2(arm, 0), Color(1, 1, 1, k), 2.0, true)
		draw_line(p - Vector2(0, arm), p + Vector2(0, arm), Color(1, 1, 1, k), 2.0, true)
		draw_circle(p, 2.0 * k, Color(1, 1, 1, k))
	# MAX tag in the top-right corner
	var font := ThemeDB.fallback_font
	var text := Terms.t("ascension_max_tag")
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var tag := Rect2(size.x - w - 14, 4, w + 10, 18)
	draw_rect(tag, Color.from_hsv(hue, 0.7, 0.9, 0.9))
	draw_string(font, tag.position + Vector2(5, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

## The point at distance d along the border, clockwise from the top-left corner
func _edge_point(d: float) -> Vector2:
	if d < size.x:
		return Vector2(d, 1)
	d -= size.x
	if d < size.y:
		return Vector2(size.x - 1, d)
	d -= size.y
	if d < size.x:
		return Vector2(size.x - d, size.y - 1)
	d -= size.x
	return Vector2(1, size.y - d)
