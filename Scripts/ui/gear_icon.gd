class_name GearIcon
extends Button
## A gear inventory square, gacha style: a rounded tile washed in the piece's rarity colour with its picture (the
## EquipmentData icon, or a drawn sword / shield / ring by slot) in the middle, rarity stars and "+N" along a dark
## strip at the bottom. Corner marks: the wearer's face (top left), "x2" owned (top right, Craft page), a green
## arrow when it can be upgraded right now, and a padlock over a dimmed tile when it's locked.
## Selected tiles get a bright frame; hover lifts the tile. Everything is drawn here, so containers can't undo the
## motion. Set the fields, then queue_redraw() (set_gear does it).

const STAR_COUNTS := {CharacterData.Rarity.R: 3, CharacterData.Rarity.SR: 4, CharacterData.Rarity.SSR: 5}
const RADIUS := 10

var gear: EquipmentData
var plus := 0
var wearer: CharacterData  # null = spare
var count := -1  # -1 = don't show
var can_upgrade := false
var locked := false
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _hover := 0.0:
	set(value):
		_hover = value
		queue_redraw()
var _pop := 0.0:
	set(value):
		_pop = value
		queue_redraw()

func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(92, 104)
	mouse_entered.connect(func(): create_tween().tween_property(self, "_hover", 1.0, 0.12))
	mouse_exited.connect(func(): create_tween().tween_property(self, "_hover", 0.0, 0.15))

func set_gear(e: EquipmentData, level: int = 0) -> void:
	gear = e
	plus = level
	queue_redraw()

## A quick bounce and flash (an upgrade just landed)
func pop() -> void:
	_pop = 1.0
	create_tween().tween_property(self, "_pop", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	if gear == null:
		return
	var color: Color = CharArt.RARITY_COLORS.get(gear.rarity, UITheme.CYAN)
	var lift := 3.0 * _hover
	var grow := 4.0 * _pop
	var r := Rect2(Vector2(0, -lift), size).grow(grow - 2.0)
	# Shadow, then the tile: rarity colour fading to dark at the bottom
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.35), Color.TRANSPARENT, 0, RADIUS), Rect2(r.position + Vector2(0, 4), r.size))
	if selected:  # the glow goes under the tile (a shadow on the see-through frame would tint the whole tile)
		var glow := UITheme.box(UITheme.CYAN, Color.TRANSPARENT, 0, RADIUS)
		glow.shadow_color = Color(UITheme.CYAN, 0.55)
		glow.shadow_size = 9
		draw_style_box(glow, r)
	var top := color.darkened(0.15) if not locked else Color("#2a3142")
	var bottom := color.darkened(0.72) if not locked else Color("#141925")
	_rounded_gradient(r, top, bottom)
	# A soft glow behind the picture
	var art_center := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.42)
	if not locked:
		UITheme.draw_glow(self, art_center, r.size.x * 0.42, Color(color.lightened(0.4), 0.35 + 0.15 * _hover))
	# The picture
	var art_scale := minf(r.size.x, r.size.y) / 150.0
	if gear.icon:
		var side := r.size.x * 0.66
		draw_texture_rect(gear.icon, Rect2(art_center - Vector2(side, side) * 0.5, Vector2(side, side)), false,
			Color(1, 1, 1, 0.35) if locked else Color.WHITE)
	else:
		var fill := Color("#e8edf5") if not locked else Color("#4b5466")
		if gear.slot == EquipmentData.Slot.WEAPON:  # the sword is long: smaller, tilted, centred on its middle
			draw_set_transform_matrix(Transform2D(-0.7, Vector2.ONE * art_scale * 0.62, 0.0, art_center) * Transform2D(0.0, Vector2(28, 0)))
		else:
			draw_set_transform(art_center, 0.0, Vector2.ONE * art_scale)
		draw_piece(self, gear.slot, fill, fill.darkened(0.55))
		draw_set_transform(Vector2.ZERO)
	# Bottom strip: stars and +N
	var strip := Rect2(r.position.x, r.end.y - 24.0, r.size.x, 24.0)
	var strip_box := UITheme.box(Color(0, 0, 0, 0.55), Color.TRANSPARENT, 0, 0)
	strip_box.corner_radius_bottom_left = RADIUS
	strip_box.corner_radius_bottom_right = RADIUS
	draw_style_box(strip_box, strip)
	var stars: int = STAR_COUNTS.get(gear.rarity, 3)
	for i in stars:
		UITheme.draw_star(self, Vector2(strip.position.x + 11.0 + i * 11.0, strip.get_center().y), 5.0,
			UITheme.GOLD if not locked else Color("#6b7280"))
	var font := get_theme_default_font()
	if plus > 0:
		var text := "+%d" % plus
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string_outline(font, Vector2(strip.end.x - w - 7.0, strip.position.y + 18.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		draw_string(font, Vector2(strip.end.x - w - 7.0, strip.position.y + 18.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			UITheme.GOLD if plus >= GameState.GEAR_MAX_PLUS else Color.WHITE)
	# Wearer's face, top left
	if wearer:
		var face := wearer.get_avatar()
		var spot := Rect2(r.position + Vector2(5, 5), Vector2(26, 26))
		draw_rect(spot.grow(2.0), UITheme.CYAN)
		if face:
			draw_texture_rect(face, spot, false)
		else:
			draw_rect(spot, UITheme.INSET)
	# Owned count, top right
	if count >= 0:
		var text := "x%d" % count
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var pill := Rect2(r.end.x - w - 14.0, r.position.y + 5.0, w + 10.0, 18.0)
		draw_style_box(UITheme.box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.25), 1, 9), pill)
		draw_string(font, Vector2(pill.position.x + 5.0, pill.position.y + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color.WHITE if count > 0 else UITheme.TEXT_DIM)
	# Upgradable: a green arrow, top right
	if can_upgrade and count < 0:
		var tip := Vector2(r.end.x - 13.0, r.position.y + 7.0)
		var bob := sin(Time.get_ticks_msec() / 250.0) * 1.5
		var arrow := PackedVector2Array([tip + Vector2(0, bob), tip + Vector2(8, 9 + bob), tip + Vector2(3, 9 + bob),
			tip + Vector2(3, 16 + bob), tip + Vector2(-3, 16 + bob), tip + Vector2(-3, 9 + bob), tip + Vector2(-8, 9 + bob)])
		draw_colored_polygon(arrow, Color("#4ade80"))
		arrow.append(arrow[0])
		draw_polyline(arrow, Color(0, 0, 0, 0.6), 1.2, true)
	# Padlock over a locked tile
	if locked:
		var c := art_center + Vector2(0, 4)
		draw_arc(c + Vector2(0, -8), 8.0, PI, TAU, 16, Color("#cbd5e1"), 3.0, true)
		draw_rect(Rect2(c + Vector2(-11, -8), Vector2(22, 17)), Color("#cbd5e1"))
		draw_circle(c + Vector2(0, 0), 2.5, Color("#1f2937"))
	# Frame: rarity edge; bright cyan with a glow when selected; a white flash on pop
	var frame := UITheme.box(Color.TRANSPARENT, Color(color, 0.7 + 0.3 * _hover) if not locked else Color("#3b4457"), 2, RADIUS)
	if selected:
		frame.border_color = UITheme.CYAN_BRIGHT
		frame.set_border_width_all(3)
	draw_style_box(frame, r)
	if _pop > 0.0:
		draw_style_box(UITheme.box(Color(1, 1, 1, 0.45 * _pop), Color.TRANSPARENT, 0, RADIUS), r)

func _process(_delta: float) -> void:
	if can_upgrade:
		queue_redraw()  # the arrow bobs

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		set_process(is_inside_tree() and is_visible_in_tree())

## A top-to-bottom gradient inside a rounded rect: horizontal bands, each inset at the corners
func _rounded_gradient(r: Rect2, top: Color, bottom: Color) -> void:
	const BANDS := 24
	for i in BANDS:
		var y0 := r.position.y + r.size.y * i / BANDS
		var y1 := r.position.y + r.size.y * (i + 1) / BANDS
		var inset := 0.0
		var from_top := y0 - r.position.y
		var from_bottom := r.end.y - y1
		var edge := minf(from_top, from_bottom)
		if edge < RADIUS:
			inset = RADIUS - sqrt(maxf(RADIUS * RADIUS - (RADIUS - edge) * (RADIUS - edge), 0.0))
		draw_rect(Rect2(r.position.x + inset, y0, r.size.x - inset * 2.0, y1 - y0 + 0.5), top.lerp(bottom, float(i) / (BANDS - 1)))

## A slot's picture centred on (0, 0) at roughly 150 px scale: a sword, a heater shield or a ring with a gem
## (shared with the crafting minigame's anvil)
static func draw_piece(ci: CanvasItem, slot: int, fill: Color, edge: Color) -> void:
	match slot:
		EquipmentData.Slot.WEAPON:
			var blade := PackedVector2Array([Vector2(-70, -6), Vector2(40, -6), Vector2(62, 0), Vector2(40, 6), Vector2(-70, 6)])
			ci.draw_colored_polygon(blade, fill)
			ci.draw_polyline(blade + PackedVector2Array([blade[0]]), edge, 2.0)
			ci.draw_line(Vector2(-66, 0), Vector2(40, 0), Color(1, 1, 1, 0.35), 1.5)
			ci.draw_rect(Rect2(-80, -18, 10, 36), edge.lightened(0.3))
			ci.draw_rect(Rect2(-108, -4, 28, 8), Color("#5b3a1e"))
			ci.draw_circle(Vector2(-112, 0), 7, edge.lightened(0.3))
		EquipmentData.Slot.ARMOR:
			var shield := PackedVector2Array([Vector2(-38, -40), Vector2(0, -46), Vector2(38, -40), Vector2(38, 2),
				Vector2(24, 26), Vector2(0, 44), Vector2(-24, 26), Vector2(-38, 2)])
			ci.draw_colored_polygon(shield, fill)
			ci.draw_polyline(shield + PackedVector2Array([shield[0]]), edge, 3.0)
			ci.draw_line(Vector2(0, -42), Vector2(0, 40), edge, 2.0)
			ci.draw_line(Vector2(-36, -6), Vector2(36, -6), edge, 2.0)
			ci.draw_circle(Vector2(0, -6), 9, edge.lightened(0.2))
			ci.draw_circle(Vector2(-3, -9), 3, Color(1, 1, 1, 0.4))
		_:
			ci.draw_arc(Vector2(0, 6), 28, 0, TAU, 40, edge, 13.0)
			ci.draw_arc(Vector2(0, 6), 28, 0, TAU, 40, fill, 9.0)
			var gem := PackedVector2Array([Vector2(0, -38), Vector2(13, -24), Vector2(0, -12), Vector2(-13, -24)])
			ci.draw_colored_polygon(gem, Color("#ff6fa8").lerp(fill, 0.3))
			ci.draw_polyline(gem + PackedVector2Array([gem[0]]), edge, 2.0)
