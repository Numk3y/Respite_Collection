class_name CasinoFX
extends BattleFX
## Casino effects on top of the battle ones (sparks, rings, shakes): a shower of gold coins for wins, a muzzle
## flash with smoke for the revolver, a grey "click" puff, and drifting gold/pink casino lights in the background
## instead of embers. Positions are in this node's coordinates.

const COIN := Color("#ffd23f")
const PINK := Color("#ff5fa2")

func _ready() -> void:
	super._ready()
	# Warm casino lights drifting through, on top of the embers
	for spec in [[COIN, 14], [PINK, 12]]:
		var p := CPUParticles2D.new()
		p.amount = spec[1]
		p.lifetime = 8.0
		p.preprocess = 8.0
		p.texture = _dot_texture
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.direction = Vector2.UP
		p.spread = 40.0
		p.gravity = Vector2(0, -4)
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 14.0
		p.scale_amount_min = 0.4
		p.scale_amount_max = 1.3
		p.color = spec[0]
		p.color_ramp = _fade_ramp(0.35)
		p.material = _additive()
		add_child(p)
		resized.connect(func():
			p.position = size / 2.0
			p.emission_rect_extents = size / 2.0)

## Gold coins raining down over `area` (in this node's coordinates), spinning as they fall
func coins(area: Rect2, amount: int = 60) -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(area.get_center().x, area.position.y - 10)
	p.one_shot = true
	p.explosiveness = 0.7
	p.amount = amount
	p.lifetime = 1.8
	p.speed_scale = speed
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(area.size.x / 2.0, 6)
	p.direction = Vector2.DOWN
	p.spread = 20.0
	p.gravity = Vector2(0, 520)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 160.0
	p.angle_max = 360.0
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 9.0
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array([0.0, 0.5])
	ramp.colors = PackedColorArray([COIN, COIN.darkened(0.25)])
	p.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	_burst(area.get_center(), 24, 1.0, [COIN, Color.WHITE, Color("#ffb347")], false)

## The revolver going off: a bright flash and sparks out of the muzzle along `dir`, a ring, then a smoke puff
func muzzle(pos: Vector2, dir: Vector2) -> void:
	var flash := Flash.new()
	flash.position = pos
	flash.rotation = dir.angle()
	add_child(flash)
	var t := flash.create_tween()
	t.tween_property(flash, "scale", Vector2(1.6, 1.6), _d(0.08))
	t.parallel().tween_property(flash, "modulate:a", 0.0, _d(0.25))
	t.tween_callback(flash.queue_free)
	var sparks := CPUParticles2D.new()
	sparks.position = pos
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 26
	sparks.lifetime = 0.45
	sparks.speed_scale = speed
	sparks.direction = dir
	sparks.spread = 22.0
	sparks.gravity = Vector2(0, 200)
	sparks.initial_velocity_min = 250.0
	sparks.initial_velocity_max = 520.0
	sparks.texture = _spark_texture
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 0.8
	sparks.scale_amount_max = 1.6
	sparks.color = Color("#ffd27a")
	sparks.color_ramp = _fade_ramp()
	sparks.material = _additive()
	add_child(sparks)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)
	_ring(pos, Color("#ffe08a"), 60.0, 0.3)
	smoke(pos, 1.0)

## A drifting grey puff (gun smoke, or the little puff of a dry click)
func smoke(pos: Vector2, power: float = 0.5) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = int(18 * power) + 4
	p.lifetime = 1.4
	p.speed_scale = speed
	p.texture = _dot_texture
	p.spread = 180.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 50.0 * power + 10.0
	p.damping_min = 20.0
	p.damping_max = 40.0
	p.scale_amount_min = 1.2 * power + 0.6
	p.scale_amount_max = 3.0 * power + 1.0
	p.color = Color(0.75, 0.75, 0.78)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## A blood-red burst for whoever got shot
func shot(pos: Vector2) -> void:
	_burst(pos, 34, 1.3, [Color("#ef4444"), Color("#7f1d1d"), Color("#fca5a5")], true)
	_ring(pos, Color("#ef4444"), 120.0, 0.45)

## A soft gold sparkle of relief (survived a pull, pushed a hand)
func relief(pos: Vector2, color: Color = Color("#86efac")) -> void:
	_burst(pos, 14, 0.6, [color, Color.WHITE], false)
	_ring(pos, color, 70.0, 0.35)

## The muzzle flash: a bright star pointing along +x
class Flash extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 26.0, Color(1.0, 0.85, 0.4, 0.35))
		draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.95, 0.7, 0.9))
		var cone := PackedVector2Array([Vector2(0, -12), Vector2(70, 0), Vector2(0, 12)])
		draw_colored_polygon(cone, Color(1.0, 0.8, 0.3, 0.9))
		for a in [-0.6, 0.6, -1.4, 1.4]:
			var d := Vector2.from_angle(a)
			draw_line(Vector2.ZERO, d * 34.0, Color(1, 0.9, 0.5, 0.8), 4.0, true)
