class_name CutInOverlay
extends Control
## Ultimate cut-in that takes over the whole screen, mobile-gacha style:
## a white flash, the screen dims and the caster's cut-in picture fills it twice over: a heavily blurred,
## darkened copy covers everything as the backdrop (slowly zooming out), and the sharp picture sits on top at
## full height with its left/right edges blurred and feathered into that backdrop (Shaders/cutin_feather.gdshader).
## A tilted band with speed lines streams behind the character, who dashes in trailing afterimages and lands with
## an impact (shockwave, screen shake, punch); the skill name slams in on a dark accent plate, the picture keeps
## creeping forward during the hold, then everything rockets off and play() returns so the skill can land.
## All timings are divided by the battle speed (1x/2x/3x); tweens also follow Engine.time_scale.
## The picture is the character's cut-in image (Art/cutins/<id>.png), falling back to their portrait;
## characters with neither get their placeholder card instead.

const FEATHER_SHADER := preload("res://Shaders/cutin_feather.gdshader")
const DIM_ALPHA := 0.7
const HOLD_SEC := 0.6  # time on the landed picture at 1x (plus the impact)
const ENTER_SEC := 0.22
const EXIT_SEC := 0.18
const SHAKE_PX := 14.0
const ENTER_TILT := 5.0  # degrees the picture leans into its dash
const DRIFT := 0.03  # share of the screen width the picture creeps forward during the hold
const GHOSTS := 2  # afterimages trailing the dash
const PIC_MAX_WIDTH := 0.9  # the sharp picture never gets wider than this share of the screen
const BG_ZOOM := 1.15  # the blurred backdrop starts this zoomed in and settles to 1
const BG_SMALL_PX := 48.0  # the backdrop copy's longest side; smaller = blurrier once stretched to the screen
const EDGE_BLUR_PX := 6.0  # blur step at the sharp picture's feathered edges, in screen pixels
const ENEMY_ACCENT := Color("#FF5A6E")
const TITLE_FONT_SIZE := 48  # skill name size; long names step down from here to fit
const TITLE_MIN_FONT_SIZE := 24
const TITLE_MARGIN := 24.0  # the name plate always stays this far inside the screen edges

var _speed := 1.0
var _dim: ColorRect
var _stage: Control  # everything that shakes on impact
var _bg: TextureRect
var _bg_mat: ShaderMaterial
var _blur_cache := {}  # picture texture -> its tiny backdrop copy
var _band: ColorRect
var _lines: SpeedLines
var _burst: Burst
var _pic_mat: ShaderMaterial
var _ghosts: Array[TextureRect] = []
var _pic: TextureRect
var _art: CharArt  # fallback when there's no picture at all
var _title_box: PanelContainer
var _title_style: StyleBoxFlat
var _caster_label: Label
var _skill_label: Label
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

	# Backdrop blur: a tiny, smoothly shrunk copy of the picture (see _blurred) stretched back up through a
	# linear-filtered sampler blurs it heavily for almost no cost; the shader smooths it further and darkens/tints it
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = FEATHER_SHADER
	_bg_mat.set_shader_parameter("edge_only", false)
	_bg_mat.set_shader_parameter("blur_px", 1.0)
	_bg_mat.set_shader_parameter("darken", 0.5)
	_bg_mat.set_shader_parameter("use_source", true)
	_bg = _picture_rect(_bg_mat)
	_stage.add_child(_bg)

	# The band carries two bright edge lines and the speed lines as children, so they tilt and open with it
	_band = ColorRect.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.clip_contents = true
	_stage.add_child(_band)
	_lines = _full_rect(SpeedLines.new()) as SpeedLines
	_band.add_child(_lines)
	for edge_anchor in [Control.PRESET_TOP_WIDE, Control.PRESET_BOTTOM_WIDE]:
		var edge := ColorRect.new()
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge.set_anchors_and_offsets_preset(edge_anchor)
		edge.custom_minimum_size = Vector2(0, 3)
		_band.add_child(edge)

	_burst = _full_rect(Burst.new()) as Burst
	_stage.add_child(_burst)
	_pic_mat = ShaderMaterial.new()
	_pic_mat.shader = FEATHER_SHADER
	_pic_mat.set_shader_parameter("sharp", 0.4)
	_pic_mat.set_shader_parameter("fade", 0.38)
	for i in GHOSTS:
		var ghost := _picture_rect(_pic_mat)
		_ghosts.append(ghost)
		_stage.add_child(ghost)
	_pic = _picture_rect(_pic_mat)
	_stage.add_child(_pic)
	_art = CharArt.new()
	_stage.add_child(_art)

	_title_box = PanelContainer.new()
	_title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_style = StyleBoxFlat.new()
	_title_style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	_title_style.border_width_left = 6
	_title_style.border_width_bottom = 2
	_title_style.set_corner_radius_all(4)
	_title_style.skew = Vector2(0.18, 0)
	_title_style.content_margin_left = 22
	_title_style.content_margin_right = 26
	_title_style.content_margin_top = 6
	_title_style.content_margin_bottom = 8
	_title_style.shadow_size = 14
	_title_box.add_theme_stylebox_override("panel", _title_style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	_title_box.add_child(lines)
	_caster_label = Label.new()
	_caster_label.add_theme_font_size_override("font_size", 20)
	lines.add_child(_caster_label)
	_skill_label = Label.new()
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.9
	_skill_label.add_theme_font_override("font", bold)
	_skill_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_skill_label.add_theme_constant_override("outline_size", 12)
	_skill_label.add_theme_constant_override("shadow_offset_x", 0)
	_skill_label.add_theme_constant_override("shadow_offset_y", 0)
	_skill_label.add_theme_constant_override("shadow_outline_size", 18)
	lines.add_child(_skill_label)
	_stage.add_child(_title_box)

	_flash = _full_rect(ColorRect.new()) as ColorRect
	_flash.color = Color.WHITE
	add_child(_flash)

func _full_rect(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node

func _picture_rect(mat: ShaderMaterial) -> TextureRect:
	var rect := TextureRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.material = mat
	return rect

func _d(seconds: float) -> float:
	return seconds / maxf(_speed, 0.01)

## Plays the whole cut-in and returns when it has finished. ally = true for the player's side
## (picture enters from the left), false for enemies (mirrored, red accent).
func play(data: CharacterData, caster_name: String, skill_name: String, ally: bool, speed: float) -> void:
	_speed = speed
	var accent: Color = UITheme.CYAN if ally else ENEMY_ACCENT
	var dir := 1.0 if ally else -1.0
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	var w := size.x
	var h := size.y
	visible = true
	_dim.modulate.a = 0.0
	_flash.modulate.a = 0.0
	_stage.position = Vector2.ZERO

	var texture: Texture2D = data.get_cutin() if data else null
	var has_pic := texture != null
	_bg.visible = has_pic
	_pic.visible = has_pic
	for ghost in _ghosts:
		ghost.visible = has_pic
	_art.visible = not has_pic

	# Blurred backdrop: fills the screen and slowly settles from a zoom
	if has_pic:
		var small := _blurred(texture)
		_bg.texture = small
		_bg_mat.set_shader_parameter("source_tex", small)
		_bg_mat.set_shader_parameter("source_pixel", Vector2.ONE / small.get_size())
		_bg.size = Vector2(w, h)
		_bg.position = Vector2.ZERO
		_bg.pivot_offset = _bg.size * 0.5
		_bg.scale = Vector2.ONE * BG_ZOOM
		_bg.modulate.a = 0.0
		_bg_mat.set_shader_parameter("rect_size", _bg.size)
		# Edge blur is measured in texels; scale it so high-res art blurs as much on screen as small art
		_pic_mat.set_shader_parameter("blur_px", EDGE_BLUR_PX * maxf(float(texture.get_height()) / h, 1.0))
		_bg_mat.set_shader_parameter("tint", Color(accent.darkened(0.3), 0.35))

	var band_h := h * 0.36
	_band.size = Vector2(w * 1.6, band_h)
	_band.position = Vector2(-w * 0.3, (h - band_h) * 0.5)
	_band.pivot_offset = _band.size * 0.5
	_band.rotation_degrees = -8.0 * dir
	_band.color = Color(accent.darkened(0.7), 0.55)
	for edge in _band.get_children():
		if edge is ColorRect:
			edge.color = Color(accent, 0.9)
	_band.scale = Vector2(1, 0)
	_lines.begin(Color(accent.lightened(0.4), 0.55), dir, _speed)

	# The character: the sharp picture at full height (feathered edges), or the placeholder card
	var mover: Control = _pic if has_pic else _art
	var pic_size: Vector2
	if has_pic:
		var aspect := float(texture.get_width()) / maxf(texture.get_height(), 1.0)
		pic_size = Vector2(minf(h * aspect * 1.25, w * PIC_MAX_WIDTH), h)
		_pic_mat.set_shader_parameter("rect_size", pic_size)
	else:
		pic_size = Vector2(h * 0.85 * 0.75, h * 0.85)
	var pic_y := (h - pic_size.y) * 0.5
	var target := (w * 0.58 if ally else w * 0.42) - pic_size.x * 0.5
	var start := -pic_size.x if ally else w
	var exit := w + 80.0 if ally else -pic_size.x - 80.0
	var movers: Array[Control] = [mover]
	if has_pic:
		for ghost in _ghosts:
			movers.append(ghost)
	for node in movers:
		node.size = pic_size
		node.pivot_offset = pic_size * 0.5
		node.scale = Vector2.ONE
		node.rotation_degrees = -ENTER_TILT * dir
		node.position = Vector2(start, pic_y)
		node.modulate = Color.WHITE
		if node is TextureRect:
			node.texture = texture
	if not has_pic:
		if data:
			_art.set_character(data)
		else:
			_art.set_mystery(caster_name)
	for i in _ghosts.size():
		_ghosts[i].modulate = Color(accent.lightened(0.4), 0.4 / (i + 1))
	_burst.setup(Vector2(target + pic_size.x * 0.5, h * 0.5), accent, h)

	# Skill name plate: sits low on the opposite side and slams in from big to normal size
	_caster_label.text = caster_name
	_caster_label.add_theme_color_override("font_color", Color(accent, 0.9))
	_skill_label.text = skill_name
	_skill_label.add_theme_color_override("font_color", Color.WHITE)
	_skill_label.add_theme_color_override("font_outline_color", Color(accent.darkened(0.5), 0.9))
	_skill_label.add_theme_color_override("font_shadow_color", Color(accent, 0.55))  # the glow
	_title_style.border_color = accent
	_title_style.shadow_color = Color(accent, 0.35)
	# Long names (e.g. Balloon Boy "A-HAHAHA-HAHA") shrink until the plate fits the screen, then the plate is kept
	# fully on screen instead of being centred off the edge
	var max_width := w - TITLE_MARGIN * 2.0
	var font_size := TITLE_FONT_SIZE
	var box := Vector2.ZERO
	while true:
		_skill_label.add_theme_font_size_override("font_size", font_size)
		_title_box.reset_size()
		box = _title_box.get_combined_minimum_size()
		if box.x <= max_width or font_size <= TITLE_MIN_FONT_SIZE:
			break
		font_size -= 4
	var title_y := h * 0.72
	var title_target := clampf((w * 0.25 if ally else w * 0.75) - box.x * 0.5, TITLE_MARGIN, maxf(w - TITLE_MARGIN - box.x, TITLE_MARGIN))
	_title_box.pivot_offset = box * 0.5
	_title_box.position = Vector2(title_target + 140.0 * dir, title_y)
	_title_box.scale = Vector2(1.7, 1.7)
	_title_box.modulate.a = 0.0

	# Enter: flash, backdrop fades in, band bursts open, the character dashes in with afterimages lagging behind
	var enter := create_tween().set_parallel()
	_flash.modulate.a = 0.8
	enter.tween_property(_flash, "modulate:a", 0.0, _d(0.2))
	enter.tween_property(_dim, "modulate:a", DIM_ALPHA, _d(0.12))
	if has_pic:
		enter.tween_property(_bg, "modulate:a", 1.0, _d(0.18))
		enter.tween_property(_bg, "scale", Vector2.ONE, _d(ENTER_SEC + 0.4 + HOLD_SEC)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	enter.tween_property(_band, "scale:y", 1.0, _d(0.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	enter.tween_property(mover, "position:x", target, _d(ENTER_SEC)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	enter.tween_property(mover, "rotation_degrees", 0.0, _d(ENTER_SEC * 1.4)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if has_pic:
		for i in _ghosts.size():
			var lag := ENTER_SEC * (1.0 + 0.45 * (i + 1))
			enter.tween_property(_ghosts[i], "position:x", target, _d(lag)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			enter.tween_property(_ghosts[i], "rotation_degrees", 0.0, _d(lag))
			enter.tween_property(_ghosts[i], "modulate:a", 0.0, _d(lag + 0.08)).set_ease(Tween.EASE_IN)
	await create_tween().tween_interval(_d(ENTER_SEC)).finished  # the impact hits as the character lands

	# Impact: shockwave, shake, punch, a small flash, and the skill name slams in
	var impact := create_tween().set_parallel()
	_flash.modulate.a = 0.35
	impact.tween_property(_flash, "modulate:a", 0.0, _d(0.12))
	impact.tween_property(_burst, "progress", 1.0, _d(0.4)).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	impact.tween_method(_shake, 1.0, 0.0, _d(0.22))
	impact.tween_property(mover, "scale", Vector2(1.08, 1.08), _d(0.06)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	impact.tween_property(mover, "scale", Vector2.ONE, _d(0.12)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT).set_delay(_d(0.06))
	impact.tween_property(_title_box, "modulate:a", 1.0, _d(0.08))
	impact.tween_property(_title_box, "scale", Vector2.ONE, _d(0.22)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	impact.tween_property(_title_box, "position:x", title_target, _d(0.22)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_lines.speed_scale = 0.45
	await impact.finished

	# Hold: the character keeps creeping forward and growing a little so the frame never sits still
	var hold := create_tween().set_parallel()
	hold.tween_property(mover, "position:x", target + w * DRIFT * dir, _d(HOLD_SEC))
	hold.tween_property(mover, "scale", Vector2(1.04, 1.04), _d(HOLD_SEC))
	hold.tween_property(_title_box, "position:x", title_target - 12.0 * dir, _d(HOLD_SEC))
	await hold.finished

	# Exit: speed lines surge, the character rockets off toward the enemy, the backdrop fades
	_lines.speed_scale = 2.5
	var leave := create_tween().set_parallel()
	leave.tween_property(mover, "position:x", exit, _d(EXIT_SEC)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	leave.tween_property(mover, "rotation_degrees", ENTER_TILT * dir, _d(EXIT_SEC)).set_ease(Tween.EASE_IN)
	leave.tween_property(mover, "modulate:a", 0.0, _d(EXIT_SEC)).set_ease(Tween.EASE_IN)
	if has_pic:
		leave.tween_property(_bg, "modulate:a", 0.0, _d(EXIT_SEC + 0.04))
	leave.tween_property(_title_box, "position:x", title_target - 220.0 * dir, _d(EXIT_SEC)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	leave.tween_property(_title_box, "modulate:a", 0.0, _d(0.14))
	leave.tween_property(_band, "scale:y", 0.0, _d(0.18)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN).set_delay(_d(0.04))
	leave.tween_property(_dim, "modulate:a", 0.0, _d(EXIT_SEC + 0.04))
	await leave.finished
	_lines.end()
	_stage.position = Vector2.ZERO
	visible = false

## A tiny copy of the picture for the backdrop (longest side BG_SMALL_PX), shrunk with smooth resampling and
## cached per texture. Falls back to the picture itself if its pixels can't be read.
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

func _shake(amount: float) -> void:
	_stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_PX * amount

## Streaks racing through the band in the dash direction; only animates while a cut-in is playing
class SpeedLines extends Control:
	const COUNT := 28
	var speed_scale := 1.0
	var _color := Color.WHITE
	var _dir := 1.0
	var _battle_speed := 1.0
	var _streaks: Array[Dictionary] = []

	func _init() -> void:
		set_process(false)

	func begin(color: Color, dir: float, battle_speed: float) -> void:
		_color = color
		_dir = dir
		_battle_speed = battle_speed
		speed_scale = 1.0
		_streaks.clear()
		for i in COUNT:
			_streaks.append({"x": randf() * size.x, "y": randf() * size.y, "len": randf_range(80.0, 280.0),
				"width": randf_range(1.5, 4.5), "v": randf_range(1400.0, 3000.0), "a": randf_range(0.3, 1.0)})
		set_process(true)

	func end() -> void:
		set_process(false)
		_streaks.clear()
		queue_redraw()

	func _process(delta: float) -> void:
		for s in _streaks:
			s.x += s.v * _dir * delta * speed_scale * _battle_speed
			if _dir > 0.0 and s.x - s.len > size.x:
				s.x = -randf() * 200.0
				s.y = randf() * size.y
			elif _dir < 0.0 and s.x + s.len < 0.0:
				s.x = size.x + randf() * 200.0
				s.y = randf() * size.y
		queue_redraw()

	func _draw() -> void:
		for s in _streaks:
			var tail := Vector2(s.x - s.len * _dir, s.y)
			draw_line(tail, Vector2(s.x, s.y), Color(_color, _color.a * s.a), s.width, true)

## Impact shockwave: an expanding ring with radial spikes that fades as progress goes 0 -> 1
class Burst extends Control:
	const SPIKES := 18
	var progress := 0.0:
		set(value):
			progress = value
			queue_redraw()
	var _center := Vector2.ZERO
	var _color := Color.WHITE
	var _reach := 300.0

	func setup(center: Vector2, color: Color, reach: float) -> void:
		_center = center
		_color = color
		_reach = reach
		progress = 0.0

	func _draw() -> void:
		if progress <= 0.0 or progress >= 1.0:
			return
		var fade := 1.0 - progress
		var r := lerpf(_reach * 0.15, _reach * 0.85, progress)
		draw_arc(_center, r, 0.0, TAU, 72, Color(_color.lightened(0.3), fade), 3.0 + 9.0 * fade, true)
		draw_arc(_center, r * 0.8, 0.0, TAU, 72, Color(1, 1, 1, fade * 0.5), 2.0, true)
		for i in SPIKES:
			var angle := TAU * i / SPIKES + 0.17
			var d := Vector2.from_angle(angle)
			var inner := r * (0.95 + 0.1 * (i % 3))
			draw_line(_center + d * inner, _center + d * (inner + _reach * 0.22 * fade), Color(1, 1, 1, fade), 2.5 + 3.0 * fade, true)
