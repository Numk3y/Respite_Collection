class_name BattleFX
extends Control
## Battle effects drawn over the arena (between the cards and the damage numbers): hit sparks and impact rings,
## slash streaks for front-row attacks, glowing bolts for back-row ones, rising heal sparkles, a burst of
## shards on a knockout, a golden aura for Ultimates, a pulsing marker around whoever is acting, and embers
## drifting through the whole fight. Positions are in this node's coordinates (see to_local_center).
## Every timing is divided by the battle speed (set `speed` when it changes).

const ALLY_FX := Color("#5ec8ff")
const ENEMY_FX := Color("#ff6b5e")
const HEAL_FX := Color("#5dff9b")
const CRIT_FX := Color("#ffd23f")
const SPARK_COLORS := [Color.WHITE, Color("#ffe8a3")]

var speed := 1.0
var _spark_texture: Texture2D
var _dot_texture: Texture2D
var _marker: Control  # the acting card (the outline follows it as it lunges); null = no marker
var _marker_size := Vector2.ZERO
var _marker_color := Color.WHITE
var _time := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var streak := Image.create(2, 12, false, Image.FORMAT_RGBA8)
	streak.fill(Color.WHITE)
	_spark_texture = ImageTexture.create_from_image(streak)
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var dot := GradientTexture2D.new()
	dot.gradient = gradient
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 24
	dot.height = 24
	_dot_texture = dot

func _ready() -> void:
	# Embers drifting up through the arena for the whole fight
	var embers := CPUParticles2D.new()
	embers.amount = 36
	embers.lifetime = 6.0
	embers.preprocess = 6.0
	embers.texture = _dot_texture
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.direction = Vector2.UP
	embers.spread = 30.0
	embers.gravity = Vector2(0, -8)
	embers.initial_velocity_min = 10.0
	embers.initial_velocity_max = 30.0
	embers.scale_amount_min = 0.15
	embers.scale_amount_max = 0.5
	embers.color = Color("#ffb46b")
	embers.color_ramp = _fade_ramp(0.55)
	embers.material = _additive()
	add_child(embers)
	resized.connect(func():
		embers.position = size / 2.0
		embers.emission_rect_extents = size / 2.0)

func _d(seconds: float) -> float:
	return seconds / maxf(speed, 0.01)

func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

## Alpha in, hold, out; peak = the brightest point
func _fade_ramp(peak: float = 1.0) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, peak), Color(1, 1, 1, peak * 0.7), Color(1, 1, 1, 0)])
	return g

## The centre of a control in this node's coordinates
func to_local_center(node: Control, node_size: Vector2) -> Vector2:
	return node.global_position - global_position + node_size / 2.0

# ───────── One-shot effects ─────────

## Sparks flying out of a hit, an expanding impact ring, and a few embers. Crits are bigger and gold.
func hit(pos: Vector2, color: Color, crit: bool = false) -> void:
	var power := 1.5 if crit else 1.0
	_burst(pos, 30 if crit else 16, power, [color.lightened(0.4), Color.WHITE, CRIT_FX if crit else color], false)
	_ring(pos, CRIT_FX if crit else color, 70.0 * power, 0.35)
	if crit:
		_ring(pos, Color.WHITE, 110.0, 0.45)

## A quick diagonal slash across the target (front-row attacks)
func slash(pos: Vector2, color: Color, dir: float) -> void:
	var s := Slash.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.setup(pos, color, dir)
	add_child(s)
	var t := s.create_tween()
	t.tween_property(s, "progress", 1.0, _d(0.22)).set_ease(Tween.EASE_OUT)
	t.tween_callback(s.queue_free)

## A glowing bolt with a trail from one card to another (back-row attacks). Doesn't wait; returns how many
## seconds the flight takes, so the caller can wait for it to land.
func bolt(from: Vector2, to: Vector2, color: Color, size_px: float = 9.0) -> float:
	var b := Bolt.new(color, size_px)
	b.position = from
	add_child(b)
	var trail := CPUParticles2D.new()
	trail.amount = 24
	trail.lifetime = 0.35
	trail.texture = _dot_texture
	trail.scale_amount_min = 0.3
	trail.scale_amount_max = 0.6
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 15.0
	trail.spread = 180.0
	trail.color = color
	trail.color_ramp = _fade_ramp()
	trail.local_coords = false
	trail.material = _additive()
	trail.speed_scale = speed
	b.add_child(trail)
	var flight := _d(0.28)
	var t := b.create_tween()
	t.tween_property(b, "position", to, flight).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		trail.emitting = false
		b.hide_core())
	t.tween_interval(0.4)  # let the trail fade out
	t.tween_callback(b.queue_free)
	return flight

## Green sparkles and little plus signs rising from a healed card
func heal(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos + Vector2(0, 30)
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 18
	p.lifetime = 1.0
	p.speed_scale = speed
	p.texture = _dot_texture
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(60, 20)
	p.direction = Vector2.UP
	p.spread = 15.0
	p.gravity = Vector2(0, -60)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	p.color = HEAL_FX
	p.color_ramp = _fade_ramp()
	p.material = _additive()
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	for i in 3:
		var plus := Plus.new()
		plus.position = pos + Vector2(randf_range(-50, 50), randf_range(0, 30))
		add_child(plus)
		var t := plus.create_tween().set_parallel()
		t.tween_property(plus, "position:y", plus.position.y - 50, _d(0.8)).set_delay(_d(0.1 * i))
		t.tween_property(plus, "modulate:a", 0.0, _d(0.8)).set_delay(_d(0.1 * i))
		t.chain().tween_callback(plus.queue_free)

## A knocked-out card bursts into grey shards
func knockout(pos: Vector2, color: Color) -> void:
	_burst(pos, 26, 1.1, [Color("#9ca3af"), Color("#4b5563"), color.darkened(0.3)], true)
	_ring(pos, Color(0.8, 0.8, 0.8), 90.0, 0.5)

## A golden ring and sparks around an Ultimate's caster as the skill lands
func aura(pos: Vector2) -> void:
	_ring(pos, CRIT_FX, 130.0, 0.5)
	_ring(pos, Color.WHITE, 90.0, 0.35)
	_burst(pos, 28, 1.2, [CRIT_FX, Color.WHITE, Color("#ffb347")], false)

## Moves `target` around for a moment and puts it back
func shake(target: Control, strength: float, seconds: float) -> void:
	var origin := target.position
	var t := target.create_tween()
	t.tween_method(func(k: float): target.position = origin + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * k,
		1.0, 0.0, _d(seconds))
	t.tween_callback(func(): target.position = origin)

## The pulsing outline around the acting card, which follows it as it moves (null = none)
func set_marker(card: Control, card_size: Vector2, color: Color = Color.WHITE) -> void:
	_marker = card
	_marker_size = card_size
	_marker_color = color
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_marker):
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_marker):
		return
	var pulse := 0.5 + 0.5 * sin(_time * 6.0)
	var r := Rect2(_marker.global_position - global_position, _marker_size).grow(4.0 + pulse * 2.0)
	for i in 3:
		draw_rect(r.grow(i * 3.0), Color(_marker_color, (0.5 - i * 0.15) * (0.6 + 0.4 * pulse)), false, 2.0)

func _burst(pos: Vector2, amount: int, power: float, colors: Array, shards: bool) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.7 if not shards else 1.0
	p.speed_scale = speed
	p.spread = 180.0
	p.gravity = Vector2(0, 500 if shards else 220)
	p.initial_velocity_min = 120.0 * power
	p.initial_velocity_max = 380.0 * power
	p.damping_min = 80.0
	p.damping_max = 200.0
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(colors)
	p.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	if shards:
		p.scale_amount_min = 3.0
		p.scale_amount_max = 6.0
		p.angle_max = 360.0
		p.angular_velocity_min = -400.0
		p.angular_velocity_max = 400.0
	else:
		p.texture = _spark_texture
		p.particle_flag_align_y = true
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.8
		p.material = _additive()
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

func _ring(pos: Vector2, color: Color, reach: float, seconds: float) -> void:
	var ring := Ring.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.setup(pos, color, reach)
	add_child(ring)
	var t := ring.create_tween()
	t.tween_property(ring, "progress", 1.0, _d(seconds)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_callback(ring.queue_free)

## An expanding ring that thins and fades as progress goes 0 -> 1
class Ring extends Control:
	var progress := 0.0:
		set(value):
			progress = value
			queue_redraw()
	var _center := Vector2.ZERO
	var _color := Color.WHITE
	var _reach := 80.0

	func setup(center: Vector2, color: Color, reach: float) -> void:
		_center = center
		_color = color
		_reach = reach

	func _draw() -> void:
		var fade := 1.0 - progress
		draw_arc(_center, lerpf(_reach * 0.15, _reach, progress), 0.0, TAU, 48, Color(_color, fade), 2.0 + 8.0 * fade, true)

## A bright diagonal streak that sweeps across and fades
class Slash extends Control:
	var progress := 0.0:
		set(value):
			progress = value
			queue_redraw()
	var _center := Vector2.ZERO
	var _color := Color.WHITE
	var _dir := 1.0

	func setup(center: Vector2, color: Color, dir: float) -> void:
		_center = center
		_color = color
		_dir = dir

	func _draw() -> void:
		var a := _center + Vector2(-70 * _dir, -45)
		var b := _center + Vector2(70 * _dir, 45)
		var head := a.lerp(b, minf(progress * 1.4, 1.0))
		var tail := a.lerp(b, maxf(progress * 1.4 - 0.5, 0.0))
		var fade := 1.0 - progress
		draw_line(tail, head, Color(_color, 0.6 * fade), 12.0 * fade + 2.0, true)
		draw_line(tail, head, Color(1, 1, 1, fade), 4.0 * fade + 1.0, true)

## The head of a bolt: a glowing dot (the trail is a particle child)
class Bolt extends Node2D:
	var _color := Color.WHITE
	var _size := 9.0
	var _core := true

	func _init(color: Color, size_px: float) -> void:
		_color = color
		_size = size_px

	func hide_core() -> void:
		_core = false
		queue_redraw()

	func _draw() -> void:
		if not _core:
			return
		draw_circle(Vector2.ZERO, _size * 1.8, Color(_color, 0.3))
		draw_circle(Vector2.ZERO, _size, _color.lightened(0.3))
		draw_circle(Vector2.ZERO, _size * 0.5, Color.WHITE)

## A small green "+" for heals
class Plus extends Node2D:
	func _draw() -> void:
		draw_line(Vector2(-7, 0), Vector2(7, 0), HEAL_FX, 4.0)
		draw_line(Vector2(0, -7), Vector2(0, 7), HEAL_FX, 4.0)
