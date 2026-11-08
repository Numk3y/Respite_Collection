class_name HomeTile
extends Button
## A Home lobby menu tile, gacha-lobby style: a slanted card filled with a picture (or a gradient in its accent
## colour when there's none), darkened on the left so the big title and the status line under it stay readable.
## A red badge in the corner flags something waiting (a count, "!" or a short word like FREE). Hovering lifts and
## lights the tile, pressing pushes it in; a `shine` tile has a band of light sweeping across it now and then.
## Everything is drawn here (no child nodes), so containers can't undo the hover/press motion. Set the fields,
## then call queue_redraw() (the setters do it).

const SLANT := 14.0  # how far the top edge leans right of the bottom edge
const SHINE_EVERY := 3.6
const BADGE_COLOR := Color("#ff3b5c")

var title := "":
	set(value):
		title = value
		queue_redraw()
var subtitle := "":
	set(value):
		subtitle = value
		queue_redraw()
var badge := "":  # "" = none
	set(value):
		badge = value
		_update_processing()
		queue_redraw()
var picture: Texture2D:
	set(value):
		picture = value
		queue_redraw()
var picture_focus := Vector2(0.5, 0.3)  # which part of the picture stays in view when it's cropped (0-1)
var accent := UITheme.CYAN:
	set(value):
		accent = value
		queue_redraw()
var title_size := 26
var shine := false

var _hover := 0.0:
	set(value):
		_hover = value
		queue_redraw()
var _press := 0.0:
	set(value):
		_press = value
		queue_redraw()
var _time := 0.0
var _hover_tween: Tween
var _press_tween: Tween

func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	clip_contents = false
	mouse_entered.connect(_ease_hover.bind(1.0))
	mouse_exited.connect(_ease_hover.bind(0.0))
	button_down.connect(_ease_press.bind(1.0))
	button_up.connect(_ease_press.bind(0.0))
	visibility_changed.connect(_update_processing)

func _ready() -> void:
	_update_processing()

## Animates (shine sweep, badge pulse) only while there's something to animate and the tile is on screen
func _update_processing() -> void:
	set_process((shine or not badge.is_empty()) and is_inside_tree() and is_visible_in_tree())

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _ease_hover(to: float) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "_hover", to, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _ease_press(to: float) -> void:
	if _press_tween:
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "_press", to, 0.06 if to > 0.0 else 0.18)

## The card's four corners (top-left, top-right, bottom-right, bottom-left), lifted on hover, pushed in on press
func _shape() -> PackedVector2Array:
	var inset := 3.0 * _press
	var lift := Vector2(-4.0 * _hover * (1.0 - _press), -2.0 * _hover * (1.0 - _press))
	var r := Rect2(Vector2.ZERO, size).grow(-inset)
	r.position += lift
	var s := minf(SLANT, r.size.x * 0.1)
	return PackedVector2Array([r.position + Vector2(s, 0), Vector2(r.end.x, r.position.y), Vector2(r.end.x - s, r.end.y),
		Vector2(r.position.x, r.end.y)])

func _draw() -> void:
	var shape := _shape()
	var bounds := Rect2(shape[3].x, shape[0].y, shape[1].x - shape[3].x, shape[2].y - shape[0].y)
	var dark := Color(0.02, 0.03, 0.07)
	# Drop shadow
	var shadow := shape.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(3, 5)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
	# The picture, cropped to cover the card around picture_focus; or an accent gradient
	if picture:
		var tex := picture.get_size()
		var scale := maxf(bounds.size.x / tex.x, bounds.size.y / tex.y)
		var src := bounds.size / scale
		var origin := (tex - src) * picture_focus
		var uvs := PackedVector2Array()
		for p in shape:
			uvs.append((origin + (p - bounds.position) / scale) / tex)
		var tint := Color(1, 1, 1).lerp(Color(1.15, 1.15, 1.15), _hover)
		draw_polygon(shape, PackedColorArray([tint, tint, tint, tint]), uvs, picture)
	else:
		draw_polygon(shape, PackedColorArray([accent.darkened(0.55), accent.darkened(0.25), accent.darkened(0.6), dark]))
		for i in 3:  # faint diagonal stripes so a bare tile isn't flat
			var x := bounds.position.x + bounds.size.x * (0.45 + 0.17 * i)
			var stripe := PackedVector2Array([Vector2(x, bounds.end.y), Vector2(x + 26, bounds.end.y),
				Vector2(x + 26 + bounds.size.y * 0.5, bounds.position.y), Vector2(x + bounds.size.y * 0.5, bounds.position.y)])
			var clipped := Geometry2D.intersect_polygons(stripe, shape)
			for poly in clipped:
				draw_colored_polygon(poly, Color(1, 1, 1, 0.05))
	# Shade: darkest at the bottom left behind the text, fading toward the top right; an accent glow along the bottom
	var lit := 0.12 * _hover
	draw_polygon(shape, PackedColorArray([Color(dark, 0.72 - lit), Color(dark, 0.08), Color(dark, 0.45 - lit),
		Color(dark, 0.93 - lit)]))
	var foot := PackedVector2Array([shape[3].lerp(shape[0], 0.35), shape[2].lerp(shape[1], 0.35), shape[2], shape[3]])
	var none := Color(accent, 0.0)
	var glow := Color(accent, 0.28 + 0.2 * _hover)
	draw_polygon(foot, PackedColorArray([none, none, glow, glow]))
	# A band of light sweeping across now and then
	if shine:
		var phase := fmod(_time, SHINE_EVERY) / 0.8
		if phase < 1.0:
			var band := bounds.size.x * 0.16
			var x := lerpf(bounds.position.x - band - bounds.size.y * 0.4, bounds.end.x, phase)
			var sweep := PackedVector2Array([Vector2(x, bounds.end.y), Vector2(x + band, bounds.end.y),
				Vector2(x + band + bounds.size.y * 0.4, bounds.position.y), Vector2(x + bounds.size.y * 0.4, bounds.position.y)])
			for poly in Geometry2D.intersect_polygons(sweep, shape):
				draw_colored_polygon(poly, Color(1, 1, 1, 0.14))
	# Frame: a soft glow on hover under a crisp edge
	var outline := shape.duplicate()
	outline.append(shape[0])
	if _hover > 0.0:
		draw_polyline(outline, Color(accent, 0.3 * _hover), 6.0, true)
	draw_polyline(outline, Color(accent, 0.55 + 0.45 * _hover), 2.0, true)
	# Text: the title big, the status line under it, both clear of the slant
	var font := get_theme_default_font()
	var left := bounds.position.x + SLANT + 14.0
	var width := bounds.size.x * 0.78
	var sub_size := maxi(13, int(title_size * 0.5))
	var block := float(title_size) + (sub_size + 6.0 if not subtitle.is_empty() else 0.0)
	var base := bounds.position.y + (bounds.size.y - block) * 0.5 + title_size * 0.82
	draw_string_outline(font, Vector2(left, base), title, HORIZONTAL_ALIGNMENT_LEFT, width, title_size, 6, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(left, base), title, HORIZONTAL_ALIGNMENT_LEFT, width, title_size, Color.WHITE)
	if not subtitle.is_empty():
		var sub_base := base + sub_size + 8.0
		draw_string_outline(font, Vector2(left, sub_base), subtitle, HORIZONTAL_ALIGNMENT_LEFT, width, sub_size, 4, Color(0, 0, 0, 0.75))
		draw_string(font, Vector2(left, sub_base), subtitle, HORIZONTAL_ALIGNMENT_LEFT, width, sub_size, accent.lightened(0.45))
	# Badge in the top-right corner
	if not badge.is_empty():
		var badge_size := 14
		var text_w := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size).x
		var w := maxf(text_w + 14.0, 24.0)
		var pill := Rect2(shape[1].x - w - 4.0, shape[1].y - 8.0, w, 24.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
		UITheme.draw_glow(self, pill.get_center(), 20.0 + 4.0 * pulse, Color(BADGE_COLOR, 0.35))
		draw_style_box(UITheme.box(BADGE_COLOR, Color.WHITE, 2, 12), pill)
		draw_string(font, Vector2(pill.position.x + (w - text_w) * 0.5, pill.position.y + 17.0), badge,
			HORIZONTAL_ALIGNMENT_LEFT, -1, badge_size, Color.WHITE)
