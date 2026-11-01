class_name RevolverCylinder
extends Control
## The revolver's cylinder seen from behind, drawn with shapes. The chamber under the cyan marker at the top fires
## next; set `spin` to -chamber * TAU / CHAMBERS to bring a chamber there (tween it to animate).

enum State { UNKNOWN, EMPTY, FIRED, BULLET }

const SIZE := Vector2(200, 200)

var states: Array[int] = []
var spin := 0.0:
	set(value):
		spin = value
		queue_redraw()

func _init() -> void:
	custom_minimum_size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	reset()

func reset() -> void:
	states.resize(RouletteGame.CHAMBERS)
	states.fill(State.UNKNOWN)
	queue_redraw()

func set_state(chamber: int, state: State) -> void:
	states[chamber] = state
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	draw_circle(c, r, Color("#3a3f4b"))
	draw_arc(c, r, 0, TAU, 64, Color("#6b7280"), 3.0, true)
	draw_circle(c, r * 0.14, Color("#1f2937"))
	var count := states.size()
	for i in count:
		var angle := -PI / 2 + i * TAU / count + spin
		var p := c + Vector2(cos(angle), sin(angle)) * r * 0.6
		var cr := r * 0.22
		match states[i]:
			State.UNKNOWN:
				draw_circle(p, cr, Color("#111827"))
			State.EMPTY:
				draw_circle(p, cr, Color("#111827"))
				draw_arc(p, cr, 0, TAU, 32, Color("#9ca3af"), 2.0, true)
			State.FIRED:
				draw_circle(p, cr, Color("#7f1d1d"))
				draw_circle(p, cr * 0.5, Color("#F87171"))
			State.BULLET:
				draw_circle(p, cr, Color("#B8860B"))
				draw_circle(p, cr * 0.45, UITheme.GOLD)
	var tip := c + Vector2(0, -r - 4)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-11, -16), tip + Vector2(11, -16), tip]), UITheme.CYAN)
