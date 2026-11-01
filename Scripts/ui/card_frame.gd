class_name CardFrame
extends Control
## "Prism" card frame drawn over a portrait, in the game's VRChat / holo-display style:
## - a bevelled metal border with chamfered (cut) corners, each corner capped by a metal plate holding a gem
## - a hexagonal crest that breaks through the top edge, with a gem and small angled wings
## - fine tech tick marks along the inner side rails and a faint diagonal glass sheen
## - an angled dark-glass name tab along the bottom with chevrons either side of the name
## Metal by rarity: gold = SSR, silver = SR, copper = R, iron = N; each metal has its own gem colour.
## Below COMPACT_WIDTH (battle cards, avatars) only the chamfered border and corner plates are drawn.
## Everything scales with the frame's size.

enum Metal { IRON, COPPER, SILVER, GOLD }

const COMPACT_WIDTH := 100.0
const GLASS_TOP := Color(0.06, 0.09, 0.16, 0.92)
const GLASS_BOTTOM := Color(0.02, 0.03, 0.07, 0.96)
## light, mid, dark tones per metal (bevel highlight, face, shadow) and the gem colour
const METALS := {
	Metal.IRON: [Color("#D1D5DB"), Color("#7C8594"), Color("#3B414C"), Color("#9CA3AF")],
	Metal.COPPER: [Color("#FFD3B0"), Color("#C8743F"), Color("#5E2810"), Color("#FB7185")],
	Metal.SILVER: [Color("#FFFFFF"), Color("#C3CCD8"), Color("#525C6A"), Color("#67E8F9")],
	Metal.GOLD: [Color("#FFF4B8"), Color("#E5B530"), Color("#7A520C"), Color("#FBBF24")],
}

var metal := Metal.GOLD
var title := ""

static func metal_for(rarity: int) -> Metal:
	match rarity:
		CharacterData.Rarity.SSR:
			return Metal.GOLD
		CharacterData.Rarity.SR:
			return Metal.SILVER
		CharacterData.Rarity.R:
			return Metal.COPPER
	return Metal.IRON

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_style(new_metal: Metal, new_title: String) -> void:
	metal = new_metal
	title = new_title
	queue_redraw()

func is_compact() -> bool:
	return compact_at(size)

func plate_height() -> float:
	return plate_height_at(size)

static func compact_at(frame_size: Vector2) -> bool:
	return frame_size.x < COMPACT_WIDTH

## Height of the bottom name tab for a frame of this size (0 when compact), so callers can keep captions clear
static func plate_height_at(frame_size: Vector2) -> float:
	return 0.0 if compact_at(frame_size) else clampf(frame_size.y * 0.14, 22.0, 60.0)

func _draw() -> void:
	var tones: Array = METALS[metal]
	var light: Color = tones[0]
	var mid: Color = tones[1]
	var dark: Color = tones[2]
	var gem: Color = tones[3]
	var w := size.x
	var h := size.y
	var t := clampf(w * 0.03, 3.0, 9.0)  # border thickness
	var cut := clampf(w * 0.09, 8.0, 34.0)  # corner chamfer size
	if not is_compact():
		_draw_sheen(w, h)
		_draw_ticks(w, h, t, mid)
		_draw_name_tab(w, h, t, cut, light, mid, dark, gem)
	_draw_corner_plates(w, h, t, cut, light, mid, dark, gem)
	_draw_border(w, h, t, cut, light, mid, dark)
	if not is_compact():
		_draw_crest(w, t, light, mid, dark, gem)

## The outline of the chamfered frame, inset by `inset`
func _outline(w: float, h: float, cut: float, inset: float) -> PackedVector2Array:
	var c := cut + inset * 0.4
	var i := inset
	return PackedVector2Array([
		Vector2(i + c, i), Vector2(w - i - c, i), Vector2(w - i, i + c), Vector2(w - i, h - i - c),
		Vector2(w - i - c, h - i), Vector2(i + c, h - i), Vector2(i, h - i - c), Vector2(i, i + c), Vector2(i + c, i)])

## Bevel: dark outer line, metal face, bright highlight, dark inner rim and a faint inner glow line
func _draw_border(w: float, h: float, t: float, cut: float, light: Color, mid: Color, dark: Color) -> void:
	draw_polyline(_outline(w, h, cut, 0.75), dark, 1.5, true)
	draw_polyline(_outline(w, h, cut, t * 0.5), mid, t * 0.75, true)
	draw_polyline(_outline(w, h, cut, t * 0.3), Color(light, 0.8), maxf(t * 0.16, 1.0), true)
	draw_polyline(_outline(w, h, cut, t * 0.9), dark, maxf(t * 0.18, 1.0), true)
	draw_polyline(_outline(w, h, cut, t * 1.15), Color(light, 0.3), 1.0, true)

## Metal plates filling each cut corner (hiding the picture's square corner), each with a small gem
func _draw_corner_plates(w: float, h: float, t: float, cut: float, light: Color, mid: Color, dark: Color, gem: Color) -> void:
	var corners := [[Vector2(0, 0), Vector2(1, 1)], [Vector2(w, 0), Vector2(-1, 1)], [Vector2(w, h), Vector2(-1, -1)], [Vector2(0, h), Vector2(1, -1)]]
	var reach := cut + t * 1.2
	for corner: Array in corners:
		var o: Vector2 = corner[0]
		var d: Vector2 = corner[1]
		var plate := PackedVector2Array([o, o + Vector2(reach * d.x, 0), o + Vector2(0, reach * d.y)])
		draw_colored_polygon(plate, dark)
		var inner := PackedVector2Array([o + Vector2(t * 0.6 * d.x, t * 0.6 * d.y), o + Vector2((reach - t) * d.x, t * 0.6 * d.y), o + Vector2(t * 0.6 * d.x, (reach - t) * d.y)])
		draw_colored_polygon(inner, mid)
		draw_line(inner[1], inner[2], Color(light, 0.7), maxf(t * 0.15, 1.0), true)
		_gem(o + Vector2(reach * 0.32 * d.x, reach * 0.32 * d.y), maxf(reach * 0.13, 2.0), gem, dark)

## A hexagonal badge breaking through the top edge, with a gem in the middle and angled wings either side
func _draw_crest(w: float, t: float, light: Color, mid: Color, dark: Color, gem: Color) -> void:
	var c := Vector2(w * 0.5, t * 0.6)
	var r := clampf(w * 0.075, 7.0, 26.0)
	for side: float in [-1.0, 1.0]:  # wings: two stepped metal slats
		for k in 2:
			var x0 := c.x + side * (r * 0.9 + k * r * 0.55)
			var wing := PackedVector2Array([Vector2(x0, c.y - r * 0.35 + k * r * 0.12), Vector2(x0 + side * r * 0.5, c.y - r * 0.15 + k * r * 0.12),
				Vector2(x0 + side * r * 0.5, c.y + r * 0.2 + k * r * 0.08), Vector2(x0, c.y + r * 0.35)])
			draw_colored_polygon(wing, mid if k == 0 else Color(mid, 0.7))
			draw_polyline(wing + PackedVector2Array([wing[0]]), dark, 1.0, true)
	var hex := PackedVector2Array()
	for i in 6:
		var a := PI / 6 + i * TAU / 6
		hex.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(hex, dark)
	var hex_inner := PackedVector2Array()
	for p in hex:
		hex_inner.append(c + (p - c) * 0.78)
	draw_colored_polygon(hex_inner, mid)
	draw_polyline(hex + PackedVector2Array([hex[0]]), Color(light, 0.8), maxf(t * 0.15, 1.0), true)
	_gem(c, r * 0.42, gem, dark)

## Fine tick marks down both inner side rails, like a holo display's scale
func _draw_ticks(w: float, h: float, t: float, mid: Color) -> void:
	var top := h * 0.16
	var bottom := h * 0.78
	var step := maxf(h * 0.035, 6.0)
	var y := top
	var i := 0
	while y < bottom:
		var len := t * (1.6 if i % 4 == 0 else 0.9)
		for x: float in [t * 1.3, w - t * 1.3]:
			var dir := 1.0 if x < w * 0.5 else -1.0
			draw_line(Vector2(x, y), Vector2(x + dir * len, y), Color(mid, 0.55), 1.0)
		y += step
		i += 1

## A faint diagonal glass streak across the upper part of the picture
func _draw_sheen(w: float, h: float) -> void:
	var streak := PackedVector2Array([Vector2(w * 0.1, 0), Vector2(w * 0.32, 0), Vector2(0, h * 0.42), Vector2(0, h * 0.2)])
	draw_colored_polygon(streak, Color(1, 1, 1, 0.07))
	var thin := PackedVector2Array([Vector2(w * 0.38, 0), Vector2(w * 0.43, 0), Vector2(0, h * 0.5), Vector2(0, h * 0.46)])
	draw_colored_polygon(thin, Color(1, 1, 1, 0.05))

## Angled dark-glass tab along the bottom, outlined in metal, with the name between two chevrons
func _draw_name_tab(w: float, h: float, t: float, cut: float, light: Color, mid: Color, dark: Color, gem: Color) -> void:
	var ph := plate_height()
	var top := h - ph
	var slant := ph * 0.6
	var left := cut * 0.6
	var right := w - cut * 0.6
	var tab := PackedVector2Array([Vector2(left + slant, top), Vector2(right - slant, top), Vector2(right, h), Vector2(left, h)])
	draw_polygon(tab, PackedColorArray([GLASS_TOP, GLASS_TOP, GLASS_BOTTOM, GLASS_BOTTOM]))
	draw_polyline(PackedVector2Array([tab[3], tab[0], tab[1], tab[2]]), dark, t * 0.7, true)
	draw_polyline(PackedVector2Array([tab[3], tab[0], tab[1], tab[2]]), mid, t * 0.4, true)
	draw_line(tab[0] + Vector2(0, t * 0.35), tab[1] + Vector2(0, t * 0.35), Color(gem, 0.45), 1.0, true)

	var font := ThemeDB.fallback_font
	var font_size := int(clampf(ph * 0.48, 11.0, 32.0))
	var max_w := (right - left) - slant * 2.0 - font_size * 1.5
	while font_size > 8 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
		font_size -= 1
	var text_w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var mid_y := top + ph * 0.55
	# Chevrons pointing in at the name
	var chev := font_size * 0.32
	for side: float in [-1.0, 1.0]:
		var x := w * 0.5 + side * (text_w * 0.5 + font_size * 0.55)
		for k in 2:
			var cx := x + side * k * chev * 0.9
			draw_polyline(PackedVector2Array([Vector2(cx + side * chev * 0.5, mid_y - chev * 0.6), Vector2(cx - side * chev * 0.1, mid_y),
				Vector2(cx + side * chev * 0.5, mid_y + chev * 0.6)]), Color(gem, 0.9 - k * 0.35), maxf(chev * 0.28, 1.2), true)
	if not title.is_empty():
		var baseline := Vector2(w * 0.5 - text_w * 0.5, mid_y + font.get_ascent(font_size) * 0.38)
		draw_string_outline(font, baseline, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(int(font_size * 0.2), 2), Color(0, 0, 0, 0.85))
		draw_string(font, baseline, title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, light)

## A faceted gem: a diamond in the gem colour with a dark rim and a bright facet
func _gem(c: Vector2, r: float, color: Color, rim: Color) -> void:
	var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(outer, color.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c]), color.lightened(0.35))
	draw_polyline(outer + PackedVector2Array([outer[0]]), rim, 1.0, true)
	draw_circle(c + Vector2(-r * 0.25, -r * 0.3), maxf(r * 0.16, 0.8), Color(1, 1, 1, 0.8))
