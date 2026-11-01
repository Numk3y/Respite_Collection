class_name AmbientParticles
extends Control
## Soft particles drifting over the CyberBackdrop behind every screen: cyan, violet and white bokeh dots float
## slowly upward with a gentle sideways wobble and twinkle, plus a few brighter sparkles that blink in and out.
## One small _draw per frame; Main caps the frame rate while the window is unfocused.

const COUNT := 46
const SPARKLES := 8
const COLORS := [Color("#5EEAD4"), Color("#22D3EE"), Color("#A78BFA"), Color("#E0F2FE")]

var _time := 0.0
var _dots: Array[Dictionary] = []
var _sparkles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_scatter)

## (Re)spread everything over the current size, e.g. on the first layout or a window resize
func _scatter() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _dots.is_empty():
		for i in COUNT:
			_dots.append(_new_dot(_rng.randf() * size.y))
		for i in SPARKLES:
			_sparkles.append(_new_sparkle())
	else:
		for d in _dots:
			d.pos = Vector2(fmod(d.pos.x, size.x), fmod(d.pos.y, size.y))

func _new_dot(y: float) -> Dictionary:
	return {
		"pos": Vector2(_rng.randf() * size.x, y),
		"speed": _rng.randf_range(8.0, 26.0),  # px per second, upward
		"radius": _rng.randf_range(1.0, 3.4),
		"color": COLORS[_rng.randi_range(0, COLORS.size() - 1)],
		"alpha": _rng.randf_range(0.25, 0.65),
		"phase": _rng.randf() * TAU,
	}

func _new_sparkle() -> Dictionary:
	return {"pos": Vector2(_rng.randf() * size.x, _rng.randf() * size.y), "start": _time + _rng.randf_range(0.0, 4.0),
		"life": _rng.randf_range(0.8, 1.6), "size": _rng.randf_range(4.0, 8.0)}

func _process(delta: float) -> void:
	if _dots.is_empty():
		return
	_time += delta
	for d in _dots:
		d.pos.y -= d.speed * delta
		d.pos.x += sin(_time * 0.6 + d.phase) * 6.0 * delta
		if d.pos.y < -10.0:
			var fresh := _new_dot(size.y + 10.0)
			d.merge(fresh, true)
	for i in _sparkles.size():
		var s: Dictionary = _sparkles[i]
		if _time > s.start + s.life:
			_sparkles[i] = _new_sparkle()
			_sparkles[i].start = _time + _rng.randf_range(0.3, 3.0)
	queue_redraw()

func _draw() -> void:
	for d in _dots:
		var twinkle := 0.7 + 0.3 * sin(_time * 2.0 + d.phase)
		var a: float = d.alpha * twinkle
		draw_circle(d.pos, d.radius * 3.2, Color(d.color, a * 0.12))
		draw_circle(d.pos, d.radius, Color(d.color, a))
	# Sparkles: a four-point star that swells and fades over its short life
	for s in _sparkles:
		var t: float = (_time - s.start) / s.life
		if t <= 0.0 or t >= 1.0:
			continue
		var k := sin(t * PI)
		var arm: float = s.size * k
		var c := Color(1, 1, 1, 0.75 * k)
		draw_line(s.pos - Vector2(arm, 0), s.pos + Vector2(arm, 0), c, 1.5, true)
		draw_line(s.pos - Vector2(0, arm), s.pos + Vector2(0, arm), c, 1.5, true)
		draw_circle(s.pos, 1.6 * k + 0.5, c)
		draw_circle(s.pos, arm * 0.9, Color(UITheme.CYAN, 0.1 * k))
