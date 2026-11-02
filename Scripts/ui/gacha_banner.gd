class_name GachaBanner
extends Control
## The Recruit screen's banner, gacha-poster style. Featured friends stand large with no card frame, their edges
## melting into a blurred, darkened copy of the lead's picture (or the pool's own banner image); the rest of the
## pool drifts by smaller and dimmer behind them (BackRow). Light rays, a glow and sparkles finish the look.
## - Two featured friends ("duo"): the lead on the left edge, the second on the right edge, each with an identical
##   name plate under them; the "PICK UP" ribbon, the title logo and the rates box sit centred between them, with
##   the pull buttons (GachaTab puts them in `button_row`) at the bottom centre.
## - One featured friend ("solo"): the friend on the right, the texts and name plate on the left, buttons at the
##   bottom right.
## Featured friends without art yet get a big glowing initial in their place; others without art are left out
## of the back row.

const ART_SHADER := preload("res://Shaders/banner_art.gdshader")
const BG_SMALL_PX := 40.0  # the backdrop copy's longest side; smaller = blurrier once stretched
const LEAD_HEIGHT := 1.12  # the lead's picture height as a share of the banner's (overflows, so it's cropped)
const SECOND_HEIGHT := 1.02
const SECOND_CENTER_X := 0.85
const SOLO_CENTER_X := 0.72  # the lead's spot when only one friend is featured
const DUO_HEIGHT := 1.08  # both pictures' height in duo mode
const DUO_CENTER_X := 0.19  # the lead's spot in duo mode; the second mirrors it (1 - this)
const FRONT_MAX_ASPECT := 0.66  # front pictures are cropped no wider than this (width/height): gaps for the back row
const TEXT_WIDTH := 0.46  # share of the width the text column may use (solo: on the left)
const DUO_TEXT_WIDTH := 0.44  # the centred text column in duo mode
const PLATE_WIDTH := 0.3  # share of the width each name plate may use
const EDGE := 24.0  # margin from the banner's edges
const TITLE_FONT_SIZE := 54
const TITLE_MIN_FONT_SIZE := 30
const RAY_COUNT := 14
const STAR_COUNTS := {CharacterData.Rarity.R: 3, CharacterData.Rarity.SR: 4, CharacterData.Rarity.SSR: 5}

var button_row: HBoxContainer  # GachaTab's pull buttons go here
var pity_label: Label  # GachaTab fills it in

var _pool: GachaPool
var _featured: Array[CharacterData] = []
var _background: TextureRect
var _effects: Effects
var _back_row: BackRow
var _arts: Array[Dictionary] = []  # {"rect": TextureRect, "initial": Label, "texture": Texture2D}, lead first
var _sparkles: CPUParticles2D
var _shade: ShadeLayer
var _column: VBoxContainer
var _ribbon: PanelContainer
var _title: Label
var _rate_box: PanelContainer
var _rates_label: Label
var _plates: Array[Plate] = []  # one per featured friend shown: lead first
var _duo := false  # two featured friends: the mirrored layout
var _breath: Tween
var _blur_cache := {}
## Entrance progress of the art (0 = off to the right, 1 = in place); applied on top of the layout so a resize
## during the animation doesn't fight it
var _slide := 1.0:
	set(value):
		_slide = value
		_layout()

func _init() -> void:
	clip_contents = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 380)

	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.modulate = Color(0.55, 0.55, 0.62)
	_full(_background)
	_effects = _full(Effects.new()) as Effects
	_back_row = _full(BackRow.new()) as BackRow
	for i in 2:  # the second friend is added first so the lead draws on top
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = ART_SHADER
		rect.material = mat
		var initial := Label.new()
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_constant_override("outline_size", 24)
		initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_arts.push_front({"rect": rect, "initial": initial, "texture": null})
	for art in [_arts[1], _arts[0]]:
		add_child(art.initial)
		add_child(art.rect)
	_arts[1].rect.modulate = Color(0.93, 0.93, 0.97)  # the second friend stands just behind the lead
	# Both front pictures fade softly at the sides so the back row peeks through between and around them;
	# the second, which starts lower, also fades in from the top
	var lead := _arts[0].rect.material as ShaderMaterial
	lead.set_shader_parameter("fade_left", 0.3)
	lead.set_shader_parameter("fade_right", 0.3)
	var second := _arts[1].rect.material as ShaderMaterial
	second.set_shader_parameter("fade_left", 0.32)
	second.set_shader_parameter("fade_right", 0.1)
	second.set_shader_parameter("fade_top", 0.12)

	_sparkles = CPUParticles2D.new()
	_sparkles.amount = 46
	_sparkles.lifetime = 5.0
	_sparkles.preprocess = 5.0
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.direction = Vector2.UP
	_sparkles.spread = 25.0
	_sparkles.gravity = Vector2(0, -12)
	_sparkles.initial_velocity_min = 8.0
	_sparkles.initial_velocity_max = 28.0
	_sparkles.scale_amount_min = 0.25
	_sparkles.scale_amount_max = 0.9
	_sparkles.texture = _soft_dot()
	var twinkle := Gradient.new()
	twinkle.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	twinkle.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	_sparkles.color_ramp = twinkle
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_sparkles.material = add
	add_child(_sparkles)

	_shade = _full(ShadeLayer.new()) as ShadeLayer  # darkens the left so the text reads over any picture
	_build_column()
	_build_buttons()

func _full(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	return node

func _build_column() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 6)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_ribbon = PanelContainer.new()
	var ribbon_style := StyleBoxFlat.new()
	ribbon_style.bg_color = Color("#ff4f8b")
	ribbon_style.skew = Vector2(0.35, 0)
	ribbon_style.content_margin_left = 22
	ribbon_style.content_margin_right = 22
	ribbon_style.content_margin_top = 2
	ribbon_style.content_margin_bottom = 2
	ribbon_style.shadow_color = Color(0, 0, 0, 0.4)
	ribbon_style.shadow_size = 6
	_ribbon.add_theme_stylebox_override("panel", ribbon_style)
	_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ribbon_text := GachaBanner._label(Terms.t("gacha_pick_up"), 20, Color.WHITE)
	ribbon_text.add_theme_constant_override("outline_size", 0)
	_ribbon.add_child(ribbon_text)
	_column.add_child(_ribbon)

	_title = GachaBanner._label("", TITLE_FONT_SIZE, Color.WHITE)
	_title.add_theme_constant_override("outline_size", 16)
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	_title.add_theme_constant_override("shadow_offset_x", 4)
	_title.add_theme_constant_override("shadow_offset_y", 5)
	_column.add_child(_title)

	_rate_box = PanelContainer.new()
	var rate_style := StyleBoxFlat.new()
	rate_style.bg_color = Color(0.04, 0.05, 0.1, 0.72)
	rate_style.border_color = UITheme.GOLD
	rate_style.border_width_left = 4
	rate_style.set_corner_radius_all(4)
	rate_style.set_content_margin_all(8)
	rate_style.content_margin_left = 14
	_rate_box.add_theme_stylebox_override("panel", rate_style)
	_rate_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var rate_lines := VBoxContainer.new()
	rate_lines.add_theme_constant_override("separation", 2)
	_rate_box.add_child(rate_lines)
	rate_lines.add_child(GachaBanner._label(Terms.t("gacha_featured"), 17, UITheme.GOLD))
	_rates_label = GachaBanner._label("", 14, UITheme.TEXT)
	rate_lines.add_child(_rates_label)
	pity_label = GachaBanner._label("", 14, Color("#fda4af"))
	rate_lines.add_child(pity_label)
	_column.add_child(_rate_box)

	# One name plate per featured friend shown, all styled the same (positioned in _layout)
	for i in 2:
		var plate := Plate.new()
		add_child(plate)
		_plates.append(plate)

func _build_buttons() -> void:
	button_row = HBoxContainer.new()  # placed in _layout: bottom centre (duo) or bottom right (solo)
	button_row.add_theme_constant_override("separation", 14)
	button_row.minimum_size_changed.connect(_layout)  # the buttons get their text after the pool is set
	add_child(button_row)

static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	return label

## A soft round dot for the sparkles
func _soft_dot() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 24
	texture.height = 24
	return texture

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

## Shows a pool: its featured friends (up to two on the art side; the first is the lead) and its texts,
## with a short entrance animation
func set_pool(pool: GachaPool, rates_text: String) -> void:
	_pool = pool
	_featured = pool.featured_characters()
	var accent := pool.theme_color
	_title.text = pool.display_name
	_title.add_theme_color_override("font_outline_color", accent.darkened(0.35))
	_rates_label.text = rates_text
	_effects.accent = accent.lightened(0.35)
	_sparkles.color = accent.lightened(0.6)

	for i in _arts.size():
		var art: Dictionary = _arts[i]
		var c: CharacterData = _featured[i] if i < _featured.size() else null
		var texture: Texture2D = c.get_cutin() if c else null
		art.texture = texture
		art.rect.texture = texture
		art.rect.visible = texture != null
		art.initial.visible = c != null and texture == null
		if c and texture == null:
			var color: Color = CharArt.RARITY_COLORS[c.rarity]
			art.initial.text = c.display_name.left(1).to_upper()
			art.initial.add_theme_color_override("font_color", Color(color, 0.85))
			art.initial.add_theme_color_override("font_outline_color", Color(accent.darkened(0.5), 0.9))

	# The backdrop: the pool's own banner image, else a blurred copy of the lead's picture, else a gradient
	var lead_texture: Texture2D = _arts[0].texture
	if pool.banner:
		_background.texture = pool.banner
	elif lead_texture:
		_background.texture = _blurred(lead_texture)
	else:
		_background.texture = _gradient(accent)

	_duo = _featured.size() >= 2
	for i in _plates.size():
		_plates[i].visible = i < _featured.size()
		if _plates[i].visible:
			_plates[i].set_character(_featured[i])
			_plates[i].set_right_aligned(_duo and i == 1)
	# Duo: the two stand side by side as equals; solo: the second picture slot is unused
	_arts[1].rect.modulate = Color.WHITE if _duo else Color(0.93, 0.93, 0.97)
	var second := _arts[1].rect.material as ShaderMaterial
	second.set_shader_parameter("fade_left", 0.3 if _duo else 0.32)
	second.set_shader_parameter("fade_right", 0.3 if _duo else 0.1)
	second.set_shader_parameter("fade_top", 0.0 if _duo else 0.12)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if _duo else HORIZONTAL_ALIGNMENT_LEFT
	for item: Control in [_ribbon, _rate_box]:
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if _duo else Control.SIZE_SHRINK_BEGIN

	# Everyone else in the pool who has a picture drifts by in the back row
	var back: Array[Texture2D] = []
	for entry in pool.entries:
		var c: CharacterData = entry.character
		if c and c.enabled and not _featured.slice(0, _arts.size()).has(c):
			var thumb := BackRow.thumbnail(c)
			if thumb:
				back.append(thumb)
	_back_row.set_textures(back)
	_layout()
	_animate_in()

func _layout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var h := size.y
	for i in _arts.size():
		var art: Dictionary = _arts[i]
		var height: float
		var center_x: float
		var top: float
		if _duo:
			# Mirrored: the lead on the left edge sliding in from the left, the second on the right from the right
			height = h * DUO_HEIGHT
			center_x = size.x * (DUO_CENTER_X if i == 0 else 1.0 - DUO_CENTER_X)
			center_x += (1.0 - _slide) * 110.0 * (-1.0 if i == 0 else 1.0)
			top = -h * 0.02
		else:
			height = h * (LEAD_HEIGHT if i == 0 else SECOND_HEIGHT)
			center_x = size.x * (SECOND_CENTER_X if i == 1 else SOLO_CENTER_X)
			center_x += (1.0 - _slide) * 90.0 * (1.0 + 0.6 * i)
			top = -h * 0.03 if i == 0 else h * 0.06
		var texture: Texture2D = art.texture
		var aspect := float(texture.get_width()) / texture.get_height() if texture else 0.75
		var w := height * minf(aspect, FRONT_MAX_ASPECT)
		var rect: TextureRect = art.rect
		rect.size = Vector2(w, height)
		rect.position = Vector2(center_x - w / 2.0, top)
		rect.pivot_offset = Vector2(w / 2.0, height)
		(rect.material as ShaderMaterial).set_shader_parameter("rect_size", rect.size)
		var initial: Label = art.initial
		initial.add_theme_font_size_override("font_size", int(h * (0.62 if i == 0 or _duo else 0.45)))
		initial.size = Vector2(w, h * 0.7)  # sits above the name plate and pull buttons
		initial.position = Vector2(center_x - w / 2.0, 0)
	_effects.center = Vector2(size.x * (0.5 if _duo else SOLO_CENTER_X), h * 0.38)
	_back_row.start_x = 0.0 if _duo else size.x * 0.36
	_shade.duo = _duo
	_effects.queue_redraw()
	_shade.queue_redraw()
	_sparkles.position = size / 2.0
	_sparkles.emission_rect_extents = size / 2.0

	var column_width := size.x * (DUO_TEXT_WIDTH if _duo else TEXT_WIDTH)
	_column.position = Vector2((size.x - column_width) / 2.0 if _duo else EDGE, 18)
	_column.size = Vector2(column_width, 0)
	_fit(_title, TITLE_FONT_SIZE, TITLE_MIN_FONT_SIZE, column_width)

	# Name plates along the bottom: duo = under each friend (left / right edge), solo = bottom left
	var plate_width := size.x * PLATE_WIDTH
	for i in _plates.size():
		var plate := _plates[i]
		plate.fit(plate_width)
		# Full plate width (right alignment needs the room), height from the content
		plate.size = Vector2(plate_width, plate.get_combined_minimum_size().y)
		var x := size.x - EDGE - plate_width if (_duo and i == 1) else EDGE
		plate.position = Vector2(x, h - plate.size.y - 16)

	button_row.reset_size()
	var buttons := button_row.get_combined_minimum_size()
	var bx := (size.x - buttons.x) / 2.0 if _duo else size.x - buttons.x - 20
	button_row.position = Vector2(bx, h - buttons.y - 18)

## Steps a label's font size down until its text fits the width (the game uses Godot's default font)
static func _fit(label: Label, max_size: int, min_size: int, width: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := max_size
	while font_size > min_size and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 2
	label.add_theme_font_size_override("font_size", font_size)

## The pictures slide in (solo: from the right; duo: from their own edges), the ribbon/title/plates fade in,
## then the featured friends keep slowly "breathing" (a gentle zoom) while the banner is shown
func _animate_in() -> void:
	if _breath:
		_breath.kill()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide = 0.0
	t.tween_property(self, "_slide", 1.0, 0.6)
	for i in _arts.size():
		for node: Control in [_arts[i].rect, _arts[i].initial]:
			node.modulate.a = 0.0
			node.scale = Vector2.ONE
			t.tween_property(node, "modulate:a", 1.0, 0.4).set_delay(0.12 * i)
	var items: Array[Control] = [_ribbon, _title, _rate_box]
	items.append_array(_plates)
	for i in items.size():
		var item := items[i]
		item.modulate.a = 0.0
		t.tween_property(item, "modulate:a", 1.0, 0.35).set_delay(0.15 + 0.08 * i)
	_title.pivot_offset = Vector2(_title.size.x / 2.0 if _duo else 0.0, _title.size.y / 2.0)
	_title.scale = Vector2(1.25, 1.25)
	t.tween_property(_title, "scale", Vector2.ONE, 0.5).set_delay(0.25).set_trans(Tween.TRANS_BACK)
	t.chain().tween_callback(_start_breathing)

func _start_breathing() -> void:
	var pictures: Array[TextureRect] = []
	for i in (2 if _duo else 1):
		if _arts[i].rect.visible:
			pictures.append(_arts[i].rect)
	if pictures.is_empty():
		return
	_breath = create_tween().set_loops().set_parallel()
	for i in pictures.size():
		# The second breathes out of step with the first, so the two don't pulse in unison
		var a := Vector2(1.025, 1.025) if i == 0 else Vector2.ONE
		var b := Vector2.ONE if i == 0 else Vector2(1.025, 1.025)
		pictures[i].scale = b
		_breath.tween_property(pictures[i], "scale", a, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_breath.tween_property(pictures[i], "scale", b, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(2.6)

## A tiny copy of the picture (longest side BG_SMALL_PX), stretched back up with linear filtering it reads as a
## heavy blur; cached per texture. Falls back to the picture itself if its pixels can't be read.
func _blurred(texture: Texture2D) -> Texture2D:
	if _blur_cache.has(texture):
		return _blur_cache[texture]
	var image := texture.get_image()
	var result: Texture2D = texture
	if image:
		image = image.duplicate() as Image
		if image.is_compressed():
			image.decompress()
		var shrink := BG_SMALL_PX / maxf(image.get_width(), image.get_height())
		image.resize(maxi(int(image.get_width() * shrink), 4), maxi(int(image.get_height() * shrink), 4), Image.INTERPOLATE_LANCZOS)
		result = ImageTexture.create_from_image(image)
	_blur_cache[texture] = result
	return result

## Radial gradient from the pool's theme colour to a dark edge, for pools with no art at all
func _gradient(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, color.lightened(0.1))
	gradient.set_color(1, color.darkened(0.75))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.7, 0.4)
	texture.fill_to = Vector2(1.3, 1.1)
	texture.width = 256
	texture.height = 128
	return texture

## The rest of the pool, smaller and dimmer behind the featured friends, drifting slowly left in an endless loop
## so everyone passes by even when there are too many to fit. They fade in from the right edge and out toward
## the text on the left (start_x).
class BackRow extends Control:
	const HEIGHT := 0.6  # figure height as a share of the banner's
	const ASPECT := 0.75  # every figure is cropped to the same portrait shape
	const SPACING := 0.62  # gap between figures, as a share of their width (they overlap)
	const SPEED := 16.0  # px per second
	const THUMB_PX := 360.0  # thumbnails' height; full-size art would be far heavier to keep in memory
	const TINT := Color(0.6, 0.62, 0.74)

	static var _thumbs := {}  # CharacterData -> small texture (null if it has no art)

	var start_x := 0.0
	var _figures: Array[TextureRect] = []
	var _material: ShaderMaterial
	var _offset := 0.0

	func _init() -> void:
		_material = ShaderMaterial.new()
		_material.shader = ART_SHADER
		_material.set_shader_parameter("fade_left", 0.25)
		_material.set_shader_parameter("fade_right", 0.25)
		_material.set_shader_parameter("fade_top", 0.08)
		_material.set_shader_parameter("fade_bottom", 0.35)
		set_process(false)

	## A small copy of the character's cut-in (or portrait), cached for the session; null if there's no art
	static func thumbnail(c: CharacterData) -> Texture2D:
		if _thumbs.has(c):
			return _thumbs[c]
		var source := c.get_cutin()
		var result: Texture2D = source
		if source:
			var image := source.get_image()
			if image:
				image = image.duplicate() as Image
				if image.is_compressed():
					image.decompress()
				if image.get_height() > THUMB_PX:
					var shrink := THUMB_PX / image.get_height()
					image.resize(maxi(int(image.get_width() * shrink), 1), int(THUMB_PX), Image.INTERPOLATE_BILINEAR)
				result = ImageTexture.create_from_image(image)
		_thumbs[c] = result
		return result

	func set_textures(textures: Array[Texture2D]) -> void:
		for f in _figures:
			f.queue_free()
		_figures.clear()
		for texture in textures:
			var rect := TextureRect.new()
			rect.texture = texture
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rect.material = _material
			add_child(rect)
			_figures.append(rect)
		set_process(not _figures.is_empty())
		_place()

	func _process(delta: float) -> void:
		_offset += delta * SPEED
		_place()

	func _place() -> void:
		if _figures.is_empty() or size.y <= 0.0:
			return
		var h := size.y * HEIGHT
		var w := h * ASPECT
		_material.set_shader_parameter("rect_size", Vector2(w, h))
		var step := w * SPACING
		# The loop is at least as long as the visible stretch plus one figure, so the wrap happens off screen
		var loop := maxf(_figures.size() * step, size.x - start_x + w * 1.5)
		for i in _figures.size():
			var rect := _figures[i]
			var x := start_x - w * 0.5 + fposmod(i * step - _offset, loop)
			rect.size = Vector2(w, h)
			rect.position = Vector2(x, size.y * (0.02 if i % 2 == 0 else 0.1))  # staggered heights
			var center := x + w * 0.5
			var fade := smoothstep(start_x, start_x + w, center) * (1.0 - smoothstep(size.x - w * 0.2, size.x + w * 0.5, center))
			rect.modulate = Color(TINT, 0.85 * fade)

## A featured friend's name plate: rarity and gold stars, the name, then "UP!" and their title/class. Every
## plate uses the same sizes; right-aligned for the friend on the right edge.
class Plate extends VBoxContainer:
	const NAME_SIZE := 44
	var _top: HBoxContainer
	var _rarity: Label
	var _stars: StarRow
	var _name: Label
	var _bottom: HBoxContainer
	var _sub: Label

	func _init() -> void:
		add_theme_constant_override("separation", 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top = HBoxContainer.new()
		_top.add_theme_constant_override("separation", 8)
		add_child(_top)
		_rarity = GachaBanner._label("", 22, UITheme.GOLD)
		_top.add_child(_rarity)
		_stars = StarRow.new(20.0, UITheme.GOLD)
		_top.add_child(_stars)
		_name = GachaBanner._label("", NAME_SIZE, Color.WHITE)
		_name.add_theme_constant_override("outline_size", 12)
		add_child(_name)
		_bottom = HBoxContainer.new()
		_bottom.add_theme_constant_override("separation", 8)
		add_child(_bottom)
		_bottom.add_child(UITheme.tag(Terms.t("gacha_up"), Color("#ff4f8b")))
		_sub = GachaBanner._label("", 16, UITheme.TEXT)
		_bottom.add_child(_sub)

	func set_character(c: CharacterData) -> void:
		_rarity.text = Terms.rarity_name(c.rarity)
		_stars.count = STAR_COUNTS.get(c.rarity, 3)
		_name.text = c.display_name
		_sub.text = "%s · %s" % [c.title, Terms.class_label(c.char_class)] if not c.title.is_empty() \
			else Terms.class_label(c.char_class)

	func set_right_aligned(right: bool) -> void:
		var align := BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
		_top.alignment = align
		_bottom.alignment = align
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT

	## Long names step down from NAME_SIZE to fit the plate's width
	func fit(width: float) -> void:
		GachaBanner._fit(_name, NAME_SIZE, 24, width)

## Rarity stars drawn as shapes: the web build's font has no ★ glyph (desktop only borrowed one from a system
## font), so a text star showed as a box there
class StarRow extends Control:
	const GAP := 3.0
	var count := 0:
		set(value):
			count = value
			custom_minimum_size = Vector2(count * (_size + GAP) - GAP, _size) if count > 0 else Vector2.ZERO
			queue_redraw()
	var _size := 20.0
	var _color := Color.WHITE

	func _init(star_size: float, color: Color) -> void:
		_size = star_size
		_color = color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		var outer := _size * 0.5
		for i in count:
			var center := Vector2(outer + i * (_size + GAP), outer)
			var points := PackedVector2Array()
			for p in 10:
				var r := outer if p % 2 == 0 else outer * 0.45
				points.append(center + Vector2.from_angle(-PI / 2.0 + p * PI / 5.0) * r)
			var shadow := PackedVector2Array()
			for pt in points:
				shadow.append(pt + Vector2(1.5, 2.0))
			draw_colored_polygon(shadow, Color(0, 0, 0, 0.6))
			draw_colored_polygon(points, _color)

## Slowly turning light rays and a soft glow behind the lead
class Effects extends Control:
	var center := Vector2.ZERO
	var accent := Color.WHITE
	var _angle := 0.0

	func _process(delta: float) -> void:
		_angle += delta * 0.08
		queue_redraw()

	func _draw() -> void:
		var reach := size.length()
		for i in RAY_COUNT:
			var a := _angle + TAU * i / RAY_COUNT
			var half := TAU / RAY_COUNT * 0.22
			var points := PackedVector2Array([center, center + Vector2.from_angle(a - half) * reach,
				center + Vector2.from_angle(a + half) * reach])
			draw_colored_polygon(points, Color(accent, 0.07))
		UITheme.draw_glow(self, center, size.y * 0.7, Color(accent, 0.35))

## Darkens where the text sits so it reads over any picture: the left part (solo) or a band down the middle
## (duo), plus a thin gradient along the bottom (behind the name plates and buttons)
class ShadeLayer extends Control:
	var duo := false

	func _draw() -> void:
		# A few side-by-side quads with per-corner colours: smooth, no overlapping strips (which showed as lines)
		var steps := 6
		if duo:
			# Darkest in the centre, fading out toward both pictures
			var half := size.x * 0.32
			var mid := size.x * 0.5
			var shade := func(i: int) -> Color: return Color(0.02, 0.02, 0.06, 0.72 * pow(1.0 - float(i) / steps, 1.3))
			for side: float in [-1.0, 1.0]:
				for i in steps:
					var x0 := mid + side * half * i / steps
					var x1 := mid + side * half * (i + 1) / steps
					var c0: Color = shade.call(i)
					var c1: Color = shade.call(i + 1)
					draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size.y), Vector2(x0, size.y)]),
						PackedColorArray([c0, c1, c1, c0]))
		else:
			var left := size.x * 0.62
			var shade := func(i: int) -> Color: return Color(0.02, 0.02, 0.06, 0.78 * pow(1.0 - float(i) / steps, 1.4))
			for i in steps:
				var x0 := left * i / steps
				var x1 := left * (i + 1) / steps
				var c0: Color = shade.call(i)
				var c1: Color = shade.call(i + 1)
				draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size.y), Vector2(x0, size.y)]),
					PackedColorArray([c0, c1, c1, c0]))
		UITheme.draw_vertical_gradient(self, Rect2(0, size.y * 0.72, size.x, size.y * 0.28), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
