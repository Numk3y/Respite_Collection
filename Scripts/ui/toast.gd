class_name Toast
extends Control
## Little notices that slide down at the top centre of the window ("Daily mission complete"), one at a time, over
## every screen (battles and the results screen included). Main keeps one for the whole session.
## show_toast() queues a notice; each one stays SHOW_SECONDS and slides away.

const SHOW_SECONDS := 2.6
const MAX_QUEUE := 6  # a burst (Auto Run, Claim All) never backs up for long
const TOP := 150.0

var _queue: Array[Dictionary] = []
var _busy := false

func _init() -> void:
	top_level = true
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_toast(heading: String, text: String, accent: Color = UITheme.GOLD) -> void:
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append({"heading": heading, "text": text, "accent": accent})
	if not _busy:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var item: Dictionary = _queue.pop_front()
	var panel := _build(item.heading, item.text, item.accent)
	add_child(panel)
	await get_tree().process_frame  # let the labels measure themselves
	if not is_instance_valid(panel):
		_busy = false
		return
	panel.reset_size()
	var view := get_viewport_rect().size
	var x := (view.x - panel.size.x) * 0.5
	panel.position = Vector2(x, -panel.size.y - 10)
	panel.modulate.a = 1.0
	Sound.play("toast")
	var t := panel.create_tween()
	# Just under Home's header and tab bar, so the currency chips stay visible while rewards come in
	t.tween_property(panel, "position:y", TOP, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(SHOW_SECONDS)
	t.tween_property(panel, "position:y", -panel.size.y - 10, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(panel.queue_free)
	t.tween_callback(_next)

func _build(heading: String, text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate.a = 0.0  # hidden until it's measured and placed
	var style := UITheme.box(Color(0.05, 0.07, 0.13, 0.96), accent, 2, 12)
	style.content_margin_left = 12
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(accent, 0.35)
	style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var tick := Tick.new()
	tick.color = accent
	tick.custom_minimum_size = Vector2(30, 30)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tick)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	row.add_child(lines)
	for spec in [[heading, 13, accent], [text, 17, Color.WHITE]]:
		var label := Label.new()
		label.text = spec[0]
		label.add_theme_font_size_override("font_size", spec[1])
		label.add_theme_color_override("font_color", spec[2])
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 4)
		lines.add_child(label)
	return panel

## A filled circle with a tick
class Tick extends Control:
	var color := UITheme.GOLD

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, color)
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.45, 0), c + Vector2(-r * 0.1, r * 0.35), c + Vector2(r * 0.5, -r * 0.35)]),
			Color(0.05, 0.07, 0.13), 3.5, true)
