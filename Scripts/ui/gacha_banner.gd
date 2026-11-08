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
## - Nothing featured ("common", e.g. the Common Pool): every SSR stands large across the back, and the SRs take
##   turns in front as a slideshow, two at a time (Showcase); the texts on the left, buttons at the bottom right.
## Featured friends without art yet get a big glowing initial in their place; others without art are left out
## of the back row and the showcase.

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
var pity_bar: PityBar  # GachaTab sets its progress

var _pool: GachaPool
var _featured: Array[CharacterData] = []
var _background: TextureRect
var _effects: Effects
var _back_row: BackRow
var _showcase: Showcase
var _common := false  # nothing featured: the showcase layout
var _ribbon_text: Label
var _rate_header: Label
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
	_showcase = _full(Showcase.new()) as Showcase
	for i in 2:  # the second friend is added first so the lead draws on top
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = ART_SHADER
		mat.set_shader_parameter("living", 1.0)  # Live2D-style idle (Shaders/living.gdshaderinc)
		mat.set_shader_parameter("living_seed", float(i) * 0.5)  # the two featured friends move out of step
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
	_ribbon_text = ribbon_text
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
	_rate_header = GachaBanner._label(Terms.t("gacha_featured"), 17, UITheme.GOLD)
	rate_lines.add_child(_rate_header)
	_rates_label = GachaBanner._label("", 14, UITheme.TEXT)
	rate_lines.add_child(_rates_label)
	pity_label = GachaBanner._label("", 14, Color("#fda4af"))
	rate_lines.add_child(pity_label)
	pity_bar = PityBar.new()
	rate_lines.add_child(pity_bar)
	rate_lines.add_child(GachaBanner._label(Terms.t("gacha_guarantee", {"count": Gacha.GUARANTEE_PULLS}), 13, UITheme.TEXT_DIM))
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

## The featured friends lean a little towards the mouse, easing there rather than snapping
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for art in _arts:
		var rect: TextureRect = art.rect
		if not rect.visible:
			continue
		var to_mouse := (get_local_mouse_position() - (rect.position + rect.size / 2.0)) / (rect.size * 0.5)
		var mat := rect.material as ShaderMaterial
		var stored = mat.get_shader_parameter("living_look")  # null until it's been set once
		var look: Vector2 = stored if stored is Vector2 else Vector2.ZERO
		mat.set_shader_parameter("living_look", look.lerp(to_mouse.clamp(Vector2(-1, -1), Vector2(1, 1)), minf(delta * 3.0, 1.0)))

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
	_common = _featured.is_empty()
	_ribbon_text.text = Terms.t("gacha_beginner_ribbon" if pool.beginner else ("gacha_common_ribbon" if _common else "gacha_pick_up"))
	(_ribbon.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = accent.darkened(0.1) if _common else Color("#ff4f8b")
	_rate_header.text = Terms.t("gacha_beginner_header" if pool.beginner else ("gacha_common_header" if _common else "gacha_featured"))
	_back_row.visible = not _common
	_showcase.visible = _common
	if _common:
		var ssr: Array[CharacterData] = []
		var sr: Array[CharacterData] = []
		for entry in pool.entries:
			var c: CharacterData = entry.character
			if c and c.enabled and c.rarity == CharacterData.Rarity.SSR and not ssr.has(c):
				ssr.append(c)
			elif c and c.enabled and c.rarity == CharacterData.Rarity.SR and not sr.has(c):
				sr.append(c)
		_showcase.set_characters(ssr, sr)
		if not pool.banner:
			_background.texture = _gradient(accent)
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
	_showcase.start_x = size.x * 0.36
	_showcase.lineup_width = size.x * 0.36 - EDGE - 18.0
	_showcase.lineup_top_min = _column.position.y + _column.get_combined_minimum_size().y + 8.0
	if _common:
		_effects.center = Vector2(size.x * 0.67, h * 0.4)
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
	_showcase.modulate.a = 0.0
	t.tween_property(_showcase, "modulate:a", 1.0, 0.5)
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

## The Common layout's art (pools with nothing featured), modern standard-banner style:
## - The hero: the top rarity's friends (SSRs; SRs if the pool has none) each in a tall slanted panel side by side.
##   The spotlight moves along every CYCLE seconds: that panel widens to full colour with a gold frame and a name
##   plate (rarity, stars, name, class); the rest sit narrower and dimmed.
## - The lineup: the next rarity down (SRs) as small framed cards in a strip at the bottom left, under "LINEUP",
##   scrolling slowly when they don't all fit.
## Panels clip their picture to the slanted shape (draw_polygon with UVs), so there are no hard rectangle edges.
class Showcase extends Control:
	const CYCLE := 4.0  # seconds per spotlight
	const ACTIVE_SHARE := 0.4  # the spotlit panel's share of the hero width (with 3+ panels)
	const SKEW := 0.2  # how far a panel leans, as a share of the banner height
	const GAP := 6.0
	const GOLD := Color("#ffd75e")
	const DIM_ALPHA := 0.68  # how dark the panels outside the spotlight are (bright art needs a strong veil)
	const CARD := Vector2(60, 80)
	const CARD_GAP := 8.0
	const SCROLL_SPEED := 18.0

	var start_x := 0.0  # the hero starts here (the texts are on the left)
	var lineup_width := 300.0  # set by the banner: room for the lineup strip
	var lineup_top_min := 0.0  # the lineup hides if it would climb above this (small windows)
	var _heroes: Array[Dictionary] = []  # {"texture", "name", "cls", "rarity"}
	var _widths: Array[float] = []  # current panel widths, eased toward their targets
	var _active := 0
	var _timer := 0.0
	var _plate: VBoxContainer
	var _plate_rarity: Label
	var _plate_stars: StarRow
	var _plate_name: Label
	var _plate_class: Label
	var _lineup: Control
	var _lineup_title: Label
	var _cards: Array[Control] = []
	var _scroll := 0.0

	func _init() -> void:
		_plate = VBoxContainer.new()
		_plate.add_theme_constant_override("separation", 0)
		_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plate.add_child(top)
		_plate_rarity = GachaBanner._label("", 18, GOLD)
		top.add_child(_plate_rarity)
		_plate_stars = StarRow.new(15.0, GOLD)
		top.add_child(_plate_stars)
		_plate_name = GachaBanner._label("", 34, Color.WHITE)
		_plate_name.add_theme_constant_override("outline_size", 10)
		_plate.add_child(_plate_name)
		_plate_class = GachaBanner._label("", 14, Color("#e2e8f0"))
		_plate.add_child(_plate_class)
		add_child(_plate)
		_lineup = Control.new()
		_lineup.clip_contents = true
		_lineup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lineup)
		_lineup_title = GachaBanner._label(Terms.t("gacha_lineup"), 14, Color("#d8b4fe"))
		add_child(_lineup_title)
		set_process(false)

	## `top`: the hero panels (SSRs); `lineup`: the strip (SRs). Friends without art are left out.
	func set_characters(ssr: Array[CharacterData], sr: Array[CharacterData]) -> void:
		var top := ssr if not ssr.is_empty() else sr
		var strip: Array[CharacterData] = []  # (a bare [] in a ternary is untyped and fails the typed assignment)
		if not ssr.is_empty():
			strip = sr
		_heroes.clear()
		for c in top:
			var texture := c.get_portrait()
			if texture == null:
				texture = c.get_cutin()
			if texture:
				_heroes.append({"texture": texture, "name": c.display_name, "cls": Terms.class_label(c.char_class), "rarity": c.rarity})
		_widths.clear()
		for card in _cards:
			card.queue_free()
		_cards.clear()
		for c in strip:
			var thumb := BackRow.thumbnail(c)
			if thumb:
				_cards.append(_make_card(c, thumb))
		_lineup_title.visible = not _cards.is_empty()
		_active = 0
		_timer = 0.0
		_scroll = 0.0
		_show_plate()
		set_process(true)
		queue_redraw()

	func _make_card(c: CharacterData, thumb: Texture2D) -> Control:
		var color: Color = CharArt.RARITY_COLORS[c.rarity]
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := UITheme.box(Color(0.05, 0.05, 0.1, 0.9), color, 2, 6, 0)
		style.shadow_color = Color(color, 0.35)
		style.shadow_size = 4
		card.add_theme_stylebox_override("panel", style)
		card.custom_minimum_size = CARD
		card.size = CARD
		var art := TextureRect.new()
		art.texture = thumb
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		var tag := PanelContainer.new()
		var chip := UITheme.box(color.darkened(0.25), Color.TRANSPARENT, 0, 4, 0)
		chip.content_margin_left = 5
		chip.content_margin_right = 5
		tag.add_theme_stylebox_override("panel", chip)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag_text := GachaBanner._label(Terms.rarity_name(c.rarity), 11, Color.WHITE)
		tag_text.add_theme_constant_override("outline_size", 0)
		tag.add_child(tag_text)
		tag.position = Vector2(4, CARD.y - 20)
		art.add_child(tag)
		card.tooltip_text = c.display_name
		_lineup.add_child(card)
		return card

	func _show_plate() -> void:
		_plate.visible = not _heroes.is_empty()
		if _heroes.is_empty():
			return
		var hero: Dictionary = _heroes[_active]
		_plate_rarity.text = Terms.rarity_name(hero.rarity)
		_plate_stars.count = STAR_COUNTS.get(hero.rarity, 3)
		_plate_name.text = hero.name
		_plate_class.text = hero.cls
		_plate.reset_size()
		_plate.modulate.a = 0.0
		var t := _plate.create_tween().set_parallel()
		t.tween_property(_plate, "modulate:a", 1.0, 0.35)
		_plate.set_meta("rise", 14.0)
		t.tween_method(_set_rise, 14.0, 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _set_rise(value: float) -> void:
		_plate.set_meta("rise", value)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_timer += delta
		if _timer >= CYCLE and _heroes.size() > 1:
			_timer = 0.0
			_active = (_active + 1) % _heroes.size()
			_show_plate()
		# Panels ease toward their widths, so the spotlight glides from one to the next
		var targets := _target_widths()
		if _widths.size() != targets.size():
			_widths = targets.duplicate()
		for i in _widths.size():
			_widths[i] = lerpf(_widths[i], targets[i], minf(delta * 5.0, 1.0))
		_scroll += delta * SCROLL_SPEED
		_place_lineup()
		_place_plate()
		queue_redraw()

	func _target_widths() -> Array[float]:
		var out: Array[float] = []
		var n := _heroes.size()
		var area := maxf(size.x - start_x - size.y * SKEW, 1.0)
		if n == 0:
			return out
		if n <= 2:
			for i in n:
				out.append(area / n)
			return out
		var active := area * ACTIVE_SHARE
		var rest := (area - active) / (n - 1)
		for i in n:
			out.append(active if i == _active else rest)
		return out

	## The four corners of panel i (leaning right: the top is shifted by SKEW x height)
	func _panel(i: int) -> PackedVector2Array:
		var lean := size.y * SKEW
		var x := start_x
		for k in i:
			x += _widths[k]
		var w: float = _widths[i]
		var l := x + GAP * 0.5
		var r := x + w - GAP * 0.5
		return PackedVector2Array([Vector2(l + lean, 0), Vector2(r + lean, 0), Vector2(r, size.y), Vector2(l, size.y)])

	## Drawn in passes, so overlays never sit under a neighbour's picture: pictures, then veils and fades, then the
	## spotlight's sheen, then the outlines on top
	func _draw() -> void:
		if _heroes.is_empty() or _widths.size() != _heroes.size():
			return
		var panels: Array[PackedVector2Array] = []
		for i in _heroes.size():
			panels.append(_panel(i))
		var white := Color.WHITE
		var clear := Color(0, 0, 0, 0)
		# 1. The pictures, cropped to cover each panel's bounding box (faces sit high in portraits: crop near the top)
		for i in _heroes.size():
			var pts := panels[i]
			var texture: Texture2D = _heroes[i].texture
			var box := Rect2(pts[3].x, 0, pts[1].x - pts[3].x, size.y)
			var tex := texture.get_size()
			var zoom := maxf(box.size.x / tex.x, box.size.y / tex.y)
			var src := box.size / zoom
			var origin := Vector2((tex.x - src.x) * 0.5, (tex.y - src.y) * 0.12)
			var uvs := PackedVector2Array()
			for p in pts:
				uvs.append((origin + (p - box.position) / zoom) / tex)
			draw_polygon(pts, PackedColorArray([white, white, white, white]), uvs, texture)
		# 2. A dark veil over the panels outside the spotlight, a fade along every bottom, a sheen on the spotlit one
		for i in _heroes.size():
			var pts := panels[i]
			if i != _active:
				var veil := Color(0.02, 0.03, 0.08, DIM_ALPHA)
				draw_polygon(pts, PackedColorArray([veil, veil, veil, veil]))
			var low := PackedVector2Array([pts[0].lerp(pts[3], 0.55), pts[1].lerp(pts[2], 0.55), pts[2], pts[3]])
			draw_polygon(low, PackedColorArray([clear, clear, Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.7)]))
		# 3. A sheen down the spotlit panel's left edge
		var lit := panels[_active]
		draw_polygon(PackedVector2Array([lit[0], lit[0].lerp(lit[1], 0.35), lit[3].lerp(lit[2], 0.35), lit[3]]),
			PackedColorArray([Color(1, 1, 1, 0.12), clear, clear, Color(1, 1, 1, 0.05)]))
		# 4. Outlines: faint for the rest, a gold frame with a glow for the spotlight (drawn last, on top)
		for i in _heroes.size():
			if i == _active:
				continue
			var outline := panels[i].duplicate()
			outline.append(panels[i][0])
			draw_polyline(outline, Color(1, 1, 1, 0.18), 1.5, true)
		var frame := panels[_active].duplicate()
		frame.append(panels[_active][0])
		draw_polyline(frame, Color(GOLD, 0.25), 8.0, true)
		draw_polyline(frame, GOLD, 2.5, true)

	## The name plate sits at the top of the spotlit panel
	func _place_plate() -> void:
		if _heroes.is_empty() or _widths.size() != _heroes.size():
			return
		var pts := _panel(_active)
		var rise := float(_plate.get_meta("rise", 0.0))
		_plate.position = Vector2(pts[0].x + 10.0, 16.0 + rise)
		GachaBanner._fit(_plate_name, 34, 18, maxf(pts[1].x - pts[0].x - 16.0, 60.0))

	## The lineup strip along the bottom left; it loops sideways when the cards don't all fit
	func _place_lineup() -> void:
		var top := size.y - CARD.y - 22.0
		var fits := not _cards.is_empty() and top - 18.0 >= lineup_top_min
		_lineup.visible = fits
		_lineup_title.visible = fits
		if not fits:
			return
		_lineup_title.position = Vector2(EDGE, top - 18.0)
		_lineup.position = Vector2(EDGE, top)
		_lineup.size = Vector2(lineup_width, CARD.y + 6.0)
		var step := CARD.x + CARD_GAP
		var total := _cards.size() * step
		var loop := total > lineup_width
		var period := maxf(total, lineup_width + step)
		for i in _cards.size():
			var x := i * step
			if loop:
				x = fposmod(i * step - _scroll, period) - step
			_cards[i].position = Vector2(x, 2.0)

## Progress towards the guaranteed SSR: a pink-to-gold fill with a shine; it pulses once the guarantee is close
class PityBar extends Control:
	var _share := 0.0
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(240, 10)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_progress(current: int, total: int) -> void:
		visible = total > 0
		var target := clampf(float(current) / maxf(total, 1.0), 0.0, 1.0)
		create_tween().tween_method(func(v: float):
			_share = v
			queue_redraw(), _share, target, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _process(delta: float) -> void:
		_t += delta
		if _share > 0.8:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.5))
		var w := size.x * _share
		if w > 0.0:
			var steps := 6
			for i in steps:  # pink fading into gold along the bar
				var x0 := w * i / steps
				var x1 := w * (i + 1) / steps
				var c0 := Color("#ff6fa8").lerp(UITheme.GOLD, float(i) / steps)
				var c1 := Color("#ff6fa8").lerp(UITheme.GOLD, float(i + 1) / steps)
				draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size.y), Vector2(x0, size.y)]),
					PackedColorArray([c0, c1, c1, c0]))
			draw_rect(Rect2(0, 0, w, size.y * 0.4), Color(1, 1, 1, 0.25))
			if _share > 0.8:  # nearly there: the tip glows
				UITheme.draw_glow(self, Vector2(w, size.y / 2.0), 14.0, Color(UITheme.GOLD, 0.5 + 0.4 * sin(_t * 6.0)))
		draw_rect(r, Color(1, 1, 1, 0.2), false, 1.0)

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
