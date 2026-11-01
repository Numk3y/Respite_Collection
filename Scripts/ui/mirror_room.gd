class_name MirrorRoom
extends Control
## The Home lobby's stage: a procedurally drawn VRChat "Mirror Room / cozy world" with the featured character
## standing in front of a glowing full-length mirror. Wall gradient, neon skirting line, a perspective floor grid,
## the mirror with sheen streaks, two light pillars and a holo pedestal under the character. The room itself is
## redrawn only on resize; the living parts animate every frame while the stage is visible: the card floats,
## sways and breathes with a light sheen sweeping across it, light motes rise through the air and pulse rings
## ripple out from the pedestal. Call set_featured() with the character to show.

const ART_HEIGHT := 0.8  # of the room height
const MOTE_COUNT := 26
const BOB := 0.012  # float height, share of the room height
const BOB_SPEED := 1.6
const SWAY_DEG := 1.2
const SWAY_SPEED := 0.9
const BREATH := 0.008
const SHEEN_EVERY := 4.5  # seconds between sheen sweeps
const PULSE_EVERY := 2.2  # seconds per pedestal ring

var _art: CharArt
var _sheen: Sheen
var _fx: RoomFx
var _plate: PanelContainer
var _name_label: Label
var _sub_label: Label
var _time := 0.0
var _backdrop: Texture2D  # Art/backgrounds/home.* (or HomeBg.*) replaces the drawn room when it exists

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop = UITheme.background("home")
	if _backdrop == null:
		_backdrop = UITheme.background("homebg")
	_fx = RoomFx.new()
	_fx.room = self
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fx)

	_art = CharArt.new()
	add_child(_art)
	_sheen = Sheen.new()
	_sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.add_child(_sheen)

	_plate = PanelContainer.new()
	var style := UITheme.box(Color(UITheme.INSET, 0.82), Color(UITheme.CYAN, 0.7), 1, 8)
	style.border_width_left = 4
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	style.shadow_color = Color(UITheme.CYAN, 0.25)
	style.shadow_size = 8
	_plate.add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	_plate.add_child(lines)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 24)
	lines.add_child(_name_label)
	_sub_label = Label.new()
	_sub_label.add_theme_font_size_override("font_size", 14)
	_sub_label.add_theme_color_override("font_color", UITheme.CYAN)
	lines.add_child(_sub_label)
	add_child(_plate)
	resized.connect(_layout)
	visibility_changed.connect(_update_processing)

func _ready() -> void:
	_update_processing()

## Only animate while the Home tab is actually on screen
func _update_processing() -> void:
	set_process(is_visible_in_tree())

func _process(delta: float) -> void:
	_time += delta
	var r := _art_rect()
	_art.pivot_offset = Vector2(r.size.x * 0.5, r.size.y)  # sway from the feet
	_art.position = r.position + Vector2(0, sin(_time * BOB_SPEED) * size.y * BOB)
	_art.rotation = deg_to_rad(sin(_time * SWAY_SPEED) * SWAY_DEG)
	_art.scale = Vector2.ONE * (1.0 + sin(_time * BOB_SPEED + 0.6) * BREATH)
	_sheen.phase = fmod(_time, SHEEN_EVERY) / 0.9  # the sweep takes 0.9 s, then rests
	_sheen.queue_redraw()
	_fx.time = _time
	_fx.queue_redraw()

## c = null shows a "?" placeholder (e.g. an empty team)
func set_featured(c: CharacterData, title: String, subtitle: String) -> void:
	if c:
		_art.set_character(c)
	else:
		_art.set_mystery(title)
	_name_label.text = title
	_sub_label.text = subtitle
	_layout()

func _art_rect() -> Rect2:
	var h := size.y * ART_HEIGHT
	var w := h * 0.75
	return Rect2(size.x * 0.5 - w * 0.5, size.y * 0.93 - h, w, h)

func _layout() -> void:
	var r := _art_rect()
	_art.position = r.position
	_art.size = r.size
	_plate.reset_size()
	_plate.position = Vector2(18, size.y - _plate.size.y - 18)
	queue_redraw()

func _horizon() -> float:
	return size.y * 0.66

func _draw() -> void:
	if _backdrop:
		_draw_picture_room()
		return
	var w := size.x
	var h := size.y
	var horizon := _horizon()

	# Wall: deep navy into a violet glow near the floor
	UITheme.draw_vertical_gradient(self, Rect2(0, 0, w, horizon), Color("#111A33"), Color("#2A2150"))
	# Floor
	UITheme.draw_vertical_gradient(self, Rect2(0, horizon, w, h - horizon), Color("#141B33"), Color("#070A14"))

	# Light pillars on both sides of the wall
	for px in [w * 0.12, w * 0.88]:
		UITheme.draw_vertical_gradient(self, Rect2(px - 14, 0, 28, horizon), Color(UITheme.CYAN, 0.0), Color(UITheme.CYAN, 0.22))
		draw_line(Vector2(px, h * 0.06), Vector2(px, horizon), Color(UITheme.CYAN_BRIGHT, 0.55), 2.0)
		UITheme.draw_glow(self, Vector2(px, horizon), 60, Color(UITheme.CYAN, 0.35))

	# The mirror: a tall reflective panel with a glowing frame and diagonal sheen streaks
	# (wider than the character so its glowing frame shows on both sides)
	var mirror_w := minf(maxf(w * 0.4, _art_rect().size.x * 1.7), w * 0.66)
	var mirror := Rect2(w * 0.5 - mirror_w * 0.5, h * 0.06, mirror_w, horizon - h * 0.06 + h * 0.04)
	UITheme.draw_vertical_gradient(self, mirror, Color("#3B5B8C", 0.55), Color("#1B2A4A", 0.75))
	for i in 3:
		var sx := mirror.position.x + mirror.size.x * (0.15 + i * 0.28)
		var sw := mirror.size.x * (0.1 if i != 1 else 0.05)
		var streak := PackedVector2Array([Vector2(sx, mirror.end.y), Vector2(sx + sw, mirror.end.y),
			Vector2(sx + sw + mirror.size.x * 0.25, mirror.position.y), Vector2(sx + mirror.size.x * 0.25, mirror.position.y)])
		var clipped := Geometry2D.intersect_polygons(streak, _rect_poly(mirror))
		for poly in clipped:
			draw_colored_polygon(poly, Color(1, 1, 1, 0.06))
	for k in 4:  # frame glow: wide faint strokes under a sharp bright one
		draw_rect(mirror.grow(k * 2.0), Color(UITheme.CYAN, 0.18 - k * 0.04), false, 2.0)
	draw_rect(mirror, Color(UITheme.CYAN_BRIGHT, 0.9), false, 2.0)

	# Neon skirting line along the horizon
	draw_line(Vector2(0, horizon), Vector2(w, horizon), Color(UITheme.CYAN, 0.25), 6.0)
	draw_line(Vector2(0, horizon), Vector2(w, horizon), Color(UITheme.CYAN_BRIGHT, 0.85), 1.5)

	# Perspective floor grid toward a vanishing point above the horizon
	var vanish := Vector2(w * 0.5, horizon - h * 0.25)
	var grid := Color(UITheme.CYAN, 0.16)
	for i in range(-10, 11):
		var bottom := Vector2(w * 0.5 + i * w * 0.12, h)
		var t := (horizon - vanish.y) / (bottom.y - vanish.y)
		draw_line(vanish.lerp(bottom, t), bottom, grid, 1.0)
	for i in range(1, 9):
		var f := float(i) / 8.0
		var y := horizon + (h - horizon) * f * f
		draw_line(Vector2(0, y), Vector2(w, y), Color(UITheme.CYAN, 0.05 + 0.12 * f), 1.0)

	# Holo pedestal under the character
	var art := _art_rect()
	var feet := Vector2(art.get_center().x, art.end.y)
	draw_set_transform(feet, 0, Vector2(1, 0.22))
	UITheme.draw_glow(self, Vector2.ZERO, art.size.x * 0.75, Color(UITheme.CYAN, 0.6))
	draw_arc(Vector2.ZERO, art.size.x * 0.6, 0, TAU, 48, Color(UITheme.CYAN_BRIGHT, 0.8), 3.0, true)
	draw_arc(Vector2.ZERO, art.size.x * 0.45, 0, TAU, 48, Color(UITheme.CYAN, 0.4), 2.0, true)
	draw_set_transform(Vector2.ZERO)

	# Holographic HUD brackets around the character
	_brackets(art.grow(10), Color(UITheme.CYAN_BRIGHT, 0.8), 22.0)

## With a home background picture: the picture fills the stage, a shade at the bottom grounds the character,
## and the holo pedestal and HUD brackets are drawn over it as usual
func _draw_picture_room() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	UITheme.draw_texture_cover(self, _backdrop, rect)
	UITheme.draw_vertical_gradient(self, Rect2(0, size.y * 0.6, size.x, size.y * 0.4), Color(0, 0, 0, 0), Color(0, 0, 0, 0.45))
	var art := _art_rect()
	var feet := Vector2(art.get_center().x, art.end.y)
	draw_set_transform(feet, 0, Vector2(1, 0.22))
	UITheme.draw_glow(self, Vector2.ZERO, art.size.x * 0.75, Color(UITheme.CYAN, 0.6))
	draw_arc(Vector2.ZERO, art.size.x * 0.6, 0, TAU, 48, Color(UITheme.CYAN_BRIGHT, 0.8), 3.0, true)
	draw_set_transform(Vector2.ZERO)
	_brackets(art.grow(10), Color(UITheme.CYAN_BRIGHT, 0.8), 22.0)

func _brackets(r: Rect2, color: Color, arm: float) -> void:
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0), color, 2.0)
		draw_line(corner, corner + Vector2(0, arm * sy), color, 2.0)

func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

## The animated layer behind the card: light motes rising and wobbling, and rings rippling out of the pedestal
class RoomFx extends Control:
	var room: MirrorRoom
	var time := 0.0
	var _motes: Array[Vector4] = []  # x (0-1), start y (0-1), radius, rise speed (room heights per second)

	func _init() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2024  # same motes every time
		for i in MOTE_COUNT:
			_motes.append(Vector4(rng.randf(), rng.randf(), rng.randf_range(1.0, 2.6), rng.randf_range(0.015, 0.05)))

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Pedestal rings: each grows out of the base and fades; two overlap so there's always one moving
		var art := room._art_rect()
		var feet := Vector2(art.get_center().x, art.end.y)
		draw_set_transform(feet, 0, Vector2(1, 0.22))
		for k in 2:
			var t := fmod(time / PULSE_EVERY + k * 0.5, 1.0)
			draw_arc(Vector2.ZERO, art.size.x * (0.45 + 0.55 * t), 0, TAU, 48, Color(UITheme.CYAN_BRIGHT, (1.0 - t) * 0.55), 2.5, true)
		draw_set_transform(Vector2.ZERO)
		# Motes: rise from the floor to near the ceiling, wobbling sideways, fading in and out at the ends
		for i in _motes.size():
			var m := _motes[i]
			var life := fmod(m.y + time * m.w, 1.0)  # 0 = floor, 1 = top
			var p := Vector2(m.x * w + sin(time * 0.7 + i) * 10.0, lerpf(h * 0.92, h * 0.05, life))
			var fade := minf(life * 5.0, (1.0 - life) * 5.0)
			fade = clampf(fade, 0.0, 1.0) * (0.75 + 0.25 * sin(time * 3.0 + i * 1.7))
			draw_circle(p, m.z * 2.4, Color(UITheme.CYAN, 0.09 * fade))
			draw_circle(p, m.z * 0.8, Color(UITheme.CYAN_BRIGHT, 0.6 * fade))

## A diagonal band of light that sweeps across the card while phase goes 0 -> 1 (nothing outside that range)
class Sheen extends Control:
	var phase := 2.0

	func _draw() -> void:
		if phase <= 0.0 or phase >= 1.0:
			return
		var band := size.x * 0.22
		var slant := size.y * 0.35
		var x := lerpf(-band - slant, size.x + band, phase)
		var clear := Color(1, 1, 1, 0.0)
		var lit := Color(1, 1, 1, 0.22)
		for half in 2:  # fade in to the bright middle line, then back out
			var x0 := x + band * 0.5 * half
			var x1 := x0 + band * 0.5
			draw_polygon(PackedVector2Array([Vector2(x0, size.y), Vector2(x1, size.y), Vector2(x1 + slant, 0), Vector2(x0 + slant, 0)]),
				PackedColorArray([clear, lit, lit, clear] if half == 0 else [lit, clear, clear, lit]))
