class_name ComboCutIn
extends Control
## Combo cut-in for combos without their own picture: the screen splits into one slanted panel per member, each
## showing that friend's cut-in art (Art/cutins/<id>.png, else their portrait, else their placeholder card).
## The panels slam in from alternating sides, bright dividers flash between them, a COMBO! plate with the combo's
## name lands in the middle, then everything slides off and play() returns so the combo can land.
## (Combos with their own picture use the full Ultimate cut-in, CutInOverlay, instead; see BattleView.)
## All timings are divided by the battle speed (1x/2x/3x).

const DIM_ALPHA := 0.75
const ENTER_SEC := 0.24
const STAGGER_SEC := 0.09  # delay between panels
const HOLD_SEC := 0.9
const EXIT_SEC := 0.22
const SLANT := 0.09  # how far each divider leans, as a share of the screen height
const SHAKE_PX := 16.0
const ENEMY_ACCENT := Color("#FF5A6E")
const TITLE_FONT_SIZE := 52
const TITLE_MIN_FONT_SIZE := 24
const TITLE_MARGIN := 24.0

var _speed := 1.0
var _dim: ColorRect
var _stage: Control  # everything that shakes on impact
var _panels: Array[Control] = []
var _dividers: Dividers
var _title_box: PanelContainer
var _title_style: StyleBoxFlat
var _combo_label: Label
var _title_label: Label
var _names_label: Label
var _flash: ColorRect

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true  # covers the whole screen, not just the arena it lives in
	z_index = 100
	clip_contents = true
	visible = false

	_dim = _full_rect(ColorRect.new()) as ColorRect
	_dim.color = Color.BLACK
	add_child(_dim)
	_stage = _full_rect(Control.new())
	add_child(_stage)
	_dividers = _full_rect(Dividers.new()) as Dividers
	_stage.add_child(_dividers)

	_title_box = PanelContainer.new()
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_style = StyleBoxFlat.new()
	_title_style.bg_color = Color(0.03, 0.05, 0.09, 0.9)
	_title_style.border_width_top = 3
	_title_style.border_width_bottom = 3
	_title_style.set_corner_radius_all(4)
	_title_style.skew = Vector2(0.18, 0)
	_title_style.content_margin_left = 28
	_title_style.content_margin_right = 28
	_title_style.content_margin_top = 6
	_title_style.content_margin_bottom = 8
	_title_style.shadow_size = 18
	_title_box.add_theme_stylebox_override("panel", _title_style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_box.add_child(lines)
	_combo_label = _line_label(22)
	_combo_label.text = Terms.t("battle_combo")
	lines.add_child(_combo_label)
	_title_label = _line_label(TITLE_FONT_SIZE)
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.9
	_title_label.add_theme_font_override("font", bold)
	_title_label.add_theme_constant_override("outline_size", 12)
	_title_label.add_theme_constant_override("shadow_offset_x", 0)
	_title_label.add_theme_constant_override("shadow_offset_y", 0)
	_title_label.add_theme_constant_override("shadow_outline_size", 18)
	lines.add_child(_title_label)
	_names_label = _line_label(18)
	lines.add_child(_names_label)
	_stage.add_child(_title_box)

	_flash = _full_rect(ColorRect.new()) as ColorRect
	_flash.color = Color.WHITE
	add_child(_flash)

func _full_rect(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node

func _line_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _d(seconds: float) -> float:
	return seconds / maxf(_speed, 0.01)

## Plays the whole split-screen cut-in and returns when it has finished. `members` are the friends in the combo
## (2 or 3, left to right), `names` their battle names. ally = true for the player's side (gold), false for enemies.
func play(title: String, members: Array[CharacterData], names: PackedStringArray, ally: bool, speed: float) -> void:
	_speed = speed
	var accent: Color = UITheme.GOLD if ally else ENEMY_ACCENT
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	var w := size.x
	var h := size.y
	visible = true
	_dim.modulate.a = 0.0
	_flash.modulate.a = 0.0
	_stage.position = Vector2.ZERO

	# One slanted panel per member; the outer edges reach past the screen so only the inner dividers show
	for panel in _panels:
		panel.queue_free()
	_panels.clear()
	var n := maxi(members.size(), 1)
	var lean := h * SLANT
	var bounds: Array[float] = []  # x of each divider at mid-height
	for i in n + 1:
		bounds.append(w * i / n)
	for i in n:
		var left := bounds[i] if i > 0 else -lean * 2.0
		var right := bounds[i + 1] if i < n - 1 else w + lean * 2.0
		var data: CharacterData = members[i] if i < members.size() else null
		var panel := _panel(data, names[i] if i < names.size() else "", left, right, lean, h, accent)
		_stage.add_child(panel)
		_stage.move_child(panel, _dividers.get_index())  # under the dividers and the plate
		panel.position.y = (-h if i % 2 == 0 else h) * 1.1
		_panels.append(panel)
	_dividers.setup(bounds.slice(1, n), lean, h, accent)
	_dividers.modulate.a = 0.0

	# Title plate: COMBO! over the combo's name over who's in it, centred low; long names shrink to fit
	_combo_label.add_theme_color_override("font_color", accent)
	_title_label.text = title
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.add_theme_color_override("font_outline_color", Color(accent.darkened(0.6), 0.95))
	_title_label.add_theme_color_override("font_shadow_color", Color(accent, 0.55))
	_names_label.text = " × ".join(names)
	_names_label.add_theme_color_override("font_color", Color(accent.lightened(0.3), 0.9))
	_title_style.border_color = accent
	_title_style.shadow_color = Color(accent, 0.4)
	var font_size := TITLE_FONT_SIZE
	var box := Vector2.ZERO
	while true:
		_title_label.add_theme_font_size_override("font_size", font_size)
		_title_box.reset_size()
		box = _title_box.get_combined_minimum_size()
		if box.x <= w - TITLE_MARGIN * 2.0 or font_size <= TITLE_MIN_FONT_SIZE:
			break
		font_size -= 4
	_title_box.size = box
	_title_box.pivot_offset = box * 0.5
	_title_box.position = Vector2((w - box.x) * 0.5, h * 0.7 - box.y * 0.5)
	_title_box.scale = Vector2(1.8, 1.8)
	_title_box.modulate.a = 0.0

	# Enter: flash, dim, the panels slam in one after another from alternating sides
	var enter := create_tween().set_parallel()
	_flash.modulate.a = 0.85
	enter.tween_property(_flash, "modulate:a", 0.0, _d(0.2))
	enter.tween_property(_dim, "modulate:a", DIM_ALPHA, _d(0.12))
	for i in _panels.size():
		enter.tween_property(_panels[i], "position:y", 0.0, _d(ENTER_SEC)).set_delay(_d(STAGGER_SEC * i)) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await enter.finished

	# Impact: shake, a second flash, the dividers light up and the plate slams in
	var impact := create_tween().set_parallel()
	_flash.modulate.a = 0.4
	impact.tween_property(_flash, "modulate:a", 0.0, _d(0.14))
	impact.tween_method(_shake, 1.0, 0.0, _d(0.25))
	impact.tween_property(_dividers, "modulate:a", 1.0, _d(0.08))
	impact.tween_property(_title_box, "modulate:a", 1.0, _d(0.08))
	impact.tween_property(_title_box, "scale", Vector2.ONE, _d(0.24)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await impact.finished

	# Hold: the panels creep toward each other so the frame never sits still
	var hold := create_tween().set_parallel()
	for i in _panels.size():
		var drift := (i - (n - 1) * 0.5) * -10.0
		hold.tween_property(_panels[i], "position:x", drift, _d(HOLD_SEC))
	hold.tween_property(_title_box, "scale", Vector2(1.04, 1.04), _d(HOLD_SEC))
	await hold.finished

	# Exit: panels shoot off the way they came, everything fades
	var leave := create_tween().set_parallel()
	for i in _panels.size():
		leave.tween_property(_panels[i], "position:y", (h if i % 2 == 0 else -h) * 1.1, _d(EXIT_SEC)) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	leave.tween_property(_dividers, "modulate:a", 0.0, _d(0.12))
	leave.tween_property(_title_box, "modulate:a", 0.0, _d(0.14))
	leave.tween_property(_dim, "modulate:a", 0.0, _d(EXIT_SEC + 0.04))
	await leave.finished
	_stage.position = Vector2.ZERO
	visible = false

## A full-screen layer holding one slanted panel: the member's picture cropped to fill the parallelogram between
## `left` and `right` (at mid-height), or a dark panel with their card if there's no picture
func _panel(data: CharacterData, member_name: String, left: float, right: float, lean: float, h: float, accent: Color) -> Control:
	var layer := _full_rect(Control.new())
	var shape := PackedVector2Array([
		Vector2(left + lean, 0), Vector2(right + lean, 0), Vector2(right - lean, h), Vector2(left - lean, h)])
	var poly := Polygon2D.new()
	poly.polygon = shape
	layer.add_child(poly)
	var texture: Texture2D = data.get_cutin() if data else null
	var box_pos := Vector2(left - lean, 0)
	var box_size := Vector2(right - left + lean * 2.0, h)
	if texture:
		# Cover-fit the picture over the panel's bounding box, biased toward the top so faces stay in frame
		var tex_size := texture.get_size()
		var fit := maxf(box_size.x / tex_size.x, box_size.y / tex_size.y)
		var offset := Vector2((box_size.x - tex_size.x * fit) * 0.5, (box_size.y - tex_size.y * fit) * 0.2)
		var uv := PackedVector2Array()
		for point in shape:
			uv.append((point - box_pos - offset) / fit)
		poly.texture = texture
		poly.uv = uv
	else:
		poly.color = accent.darkened(0.75)
		var card := CharArt.new()
		var card_size := Vector2(minf(box_size.x * 0.6, h * 0.38), h * 0.5)  # stays above the title plate
		card.size = card_size
		card.position = Vector2(left + (right - left - card_size.x) * 0.5, h * 0.06)
		layer.add_child(card)
		if data:
			card.set_character(data)
		else:
			card.set_mystery(member_name)
	return layer

func _shake(amount: float) -> void:
	_stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_PX * amount

## The bright slanted lines between the panels
class Dividers extends Control:
	var _xs: Array = []
	var _lean := 0.0
	var _h := 0.0
	var _color := Color.WHITE

	func setup(xs: Array, lean: float, h: float, color: Color) -> void:
		_xs = xs
		_lean = lean
		_h = h
		_color = color
		queue_redraw()

	func _draw() -> void:
		for x in _xs:
			var top := Vector2(x + _lean, 0)
			var bottom := Vector2(x - _lean, _h)
			draw_line(top, bottom, Color(_color, 0.9), 10.0, true)
			draw_line(top, bottom, Color.WHITE, 3.0, true)
