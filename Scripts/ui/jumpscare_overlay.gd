class_name JumpscareOverlay
extends Control
## The animatronics' entrance, a little jumpscare over the battle arena:
## blackout() makes the lights flicker and die over crackling static and returns once the arena is dark;
## reveal() then hits all at once: a red-white flash, a screen shake, the title slamming in with a glitchy
## cyan echo, and a burst of sparks and confetti, while the red-lit darkness slowly lifts. pop_burst() throws a
## small burst over each animatronic as its card springs onto the field.
## All timings are divided by the battle speed (1x/2x/3x).

const DARK := Color(0.02, 0.0, 0.03)
const RED_LIGHT := Color(0.3, 0.0, 0.03)
const TITLE_RED := Color("#ff3b4e")
const GHOST_CYAN := Color("#22e4ff")
const SPARK_COLORS := [Color("#ff3b4e"), Color("#ffd23f"), Color("#b26bff"), Color("#ffffff"), Color("#ff8a3d")]
const SHAKE_PX := 16.0
const NOISE_BITS := 140  # static specks per frame at full noise
const HOLD_SEC := 1.1  # how long the title stays up at 1x

var veil := 0.0  # darkness over the arena, 0-1
var veil_color := DARK
var flash := 0.0  # red-white flash on top of everything, 0-1
var noise := 0.0  # TV static, 0-1
var glitch := 0.0  # how far the title's cyan echo jitters, 0-1

var _speed := 1.0
var _shake_target: Control
var _shake_origin := Vector2.ZERO
var _title: Label
var _ghost: Label
var _subtitle: Label
var _spark_texture: Texture2D

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)

	_ghost = _label(64, GHOST_CYAN)
	_title = _label(64, TITLE_RED)
	_subtitle = _label(24, Color("#fde68a"))
	# A thin streak for sparks; particle_flag_align_y points it along its flight
	var image := Image.create(2, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_spark_texture = ImageTexture.create_from_image(image)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 14 if font_size > 30 else 8)
	label.modulate.a = 0.0
	add_child(label)
	return label

func _d(seconds: float) -> float:
	return seconds / maxf(_speed, 0.01)

## Lights flicker out over growing static; returns once the arena is pitch dark
func blackout(speed: float) -> void:
	_speed = speed
	veil = 0.0
	veil_color = DARK
	flash = 0.0
	noise = 0.0
	visible = true
	set_process(true)
	var t := create_tween()
	t.tween_property(self, "noise", 0.8, _d(0.7))
	var flicker := create_tween()
	for a in [0.7, 0.1, 0.85, 0.25, 0.95, 0.5, 1.0]:
		flicker.tween_property(self, "veil", a, _d(0.05))
		flicker.tween_interval(_d(randf_range(0.04, 0.1)))
	await flicker.finished
	noise = 0.35  # a faint hiss in the dark before the scare
	var hold := create_tween()
	hold.tween_interval(_d(0.35))
	await hold.finished

## The scare itself. Doesn't wait; returns how many seconds (at this speed) the whole reveal takes.
## shake_target is moved around for the screen shake and put back afterwards.
func reveal(title: String, subtitle: String, shake_target: Control) -> float:
	noise = 0.0
	flash = 1.0
	veil = 0.55
	veil_color = RED_LIGHT
	glitch = 1.0

	var center := size / 2.0
	for label: Label in [_title, _ghost]:
		label.text = title
		label.size = Vector2(size.x, 96)
		label.position = center - label.size / 2.0 - Vector2(0, 14)
		label.pivot_offset = label.size / 2.0
		label.scale = Vector2(3.2, 3.2)
		label.rotation = deg_to_rad(-6.0)
		label.modulate.a = 0.0
	_subtitle.text = subtitle
	_subtitle.size = Vector2(size.x, 36)
	_subtitle.position = Vector2(0, center.y + 40)
	_subtitle.modulate.a = 0.0

	_burst(center, 120, 1.0)
	_burst(center, 40, 1.4, true)
	_shake_target = shake_target
	_shake_origin = shake_target.position

	var hold := _d(HOLD_SEC)
	var t := create_tween().set_parallel()
	t.tween_property(self, "flash", 0.0, _d(0.45)).set_ease(Tween.EASE_OUT)
	t.tween_method(_shake, 1.0, 0.0, _d(0.55))
	for label: Label in [_title, _ghost]:
		t.tween_property(label, "scale", Vector2.ONE, _d(0.32)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(label, "rotation", 0.0, _d(0.32)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(label, "modulate:a", 1.0 if label == _title else 0.7, _d(0.08))
	# A heartbeat thump once it lands
	t.tween_property(_title, "scale", Vector2(1.12, 1.12), _d(0.1)).set_delay(_d(0.45))
	t.tween_property(_title, "scale", Vector2.ONE, _d(0.2)).set_delay(_d(0.55)).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "glitch", 0.15, _d(0.7)).set_delay(_d(0.1))
	t.tween_property(_subtitle, "modulate:a", 1.0, _d(0.25)).set_delay(_d(0.3))
	# The red-lit dark lifts while the title holds, then everything fades
	t.tween_property(self, "veil", 0.0, _d(0.9)).set_delay(_d(0.4))
	var out := _d(0.35) + hold
	for label: Label in [_title, _ghost, _subtitle]:
		t.tween_property(label, "modulate:a", 0.0, _d(0.35)).set_delay(out)
	var total := out + _d(0.35)
	t.chain().tween_callback(_finish)
	return total

## A small burst over a card as it pops in (pos in this overlay's coordinates)
func pop_burst(pos: Vector2) -> void:
	_burst(pos, 26, 0.55)
	_burst(pos, 10, 0.7, true)

func _finish() -> void:
	glitch = 0.0
	veil = 0.0
	if _shake_target:
		_shake_target.position = _shake_origin
		_shake_target = null
	set_process(false)
	visible = false

func _shake(amount: float) -> void:
	if _shake_target:
		_shake_target.position = _shake_origin + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_PX * amount

## One-shot particles from pos. Sparks are thin streaks flying along their path; confetti are tumbling squares.
## power scales their speed and reach.
func _burst(pos: Vector2, amount: int, power: float, confetti: bool = false) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 1.3 if confetti else 0.8
	p.speed_scale = _speed
	p.spread = 180.0
	p.gravity = Vector2(0, 420 if confetti else 260)
	p.initial_velocity_min = 180.0 * power
	p.initial_velocity_max = 620.0 * power
	p.damping_min = 60.0
	p.damping_max = 160.0
	# Each particle picks one of SPARK_COLORS (constant steps, no blending between them)
	var offsets := PackedFloat32Array()
	for i in SPARK_COLORS.size():
		offsets.append(float(i) / SPARK_COLORS.size())
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = offsets
	colors.colors = PackedColorArray(SPARK_COLORS)
	p.color_initial_ramp = colors
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	if confetti:
		p.scale_amount_min = 5.0
		p.scale_amount_max = 9.0
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
	else:
		p.texture = _spark_texture
		p.particle_flag_align_y = true
		p.scale_amount_min = 1.0
		p.scale_amount_max = 2.2
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

func _process(_delta: float) -> void:
	if glitch > 0.0:
		_ghost.position = _title.position + Vector2(randf_range(-1.0, 1.0) * 14.0, randf_range(-1.0, 1.0) * 5.0) * glitch
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if veil > 0.0:
		draw_rect(rect, Color(veil_color, veil))
	if noise > 0.0:
		# Static: scattered grey specks plus a few torn scanlines
		for i in int(NOISE_BITS * noise):
			var g := randf()
			draw_rect(Rect2(randf() * size.x, randf() * size.y, randf_range(2.0, 9.0), randf_range(1.0, 3.0)),
				Color(g, g, g, randf_range(0.25, 0.7) * noise))
		for i in 3:
			draw_rect(Rect2(0, randf() * size.y, size.x, randf_range(1.0, 4.0)), Color(1, 1, 1, 0.12 * noise))
	if glitch > 0.3:
		# Torn red/cyan bars while the title is still glitching in
		for i in 4:
			var bar_color: Color = TITLE_RED if i % 2 == 0 else GHOST_CYAN
			draw_rect(Rect2(randf_range(-40.0, size.x * 0.6), randf() * size.y, randf_range(80.0, size.x * 0.5), randf_range(2.0, 6.0)),
				Color(bar_color, 0.35 * glitch))
	if flash > 0.0:
		draw_rect(rect, Color(1.0, 0.82, 0.82, flash))
