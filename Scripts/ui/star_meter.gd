class_name StarMeter
extends Control
## A row of drawn stars, earned ones gold and the rest as dim outlines (e.g. a map's 3 stars).
## `pop` marks stars to show as newly earned: they pop in with a little bounce.

const GAP := 4.0
const GOLD := Color("#ffd75e")

var earned: Array = []:
	set(value):
		earned = value
		custom_minimum_size = Vector2(earned.size() * (_size + GAP) - GAP, _size) if not earned.is_empty() else Vector2.ZERO
		queue_redraw()
var _size := 20.0
var _scales: Array[float] = []

func _init(star_size: float = 20.0, stars: Array = []) -> void:
	_size = star_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	earned = stars

## Newly earned stars bounce in one after another
func pop(new_stars: Array) -> void:
	_scales.clear()
	for i in earned.size():
		_scales.append(0.0 if i < new_stars.size() and new_stars[i] else 1.0)
	if not _scales.has(0.0):
		return  # nothing new (an empty tween would complain)
	var t := create_tween()
	for i in earned.size():
		if _scales[i] == 0.0:
			t.tween_method(_set_scale.bind(i), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()

func _set_scale(value: float, i: int) -> void:
	_scales[i] = value
	queue_redraw()

func _draw() -> void:
	var r := _size * 0.5
	for i in earned.size():
		var center := Vector2(r + i * (_size + GAP), r)
		var scale := _scales[i] if i < _scales.size() else 1.0
		if earned[i] and scale < 1.0:
			UITheme.draw_star(self, center, r, GOLD, false)  # the empty slot under the star popping in
			if scale > 0.0:
				UITheme.draw_star(self, center, r * scale, GOLD)
		else:
			UITheme.draw_star(self, center, r, GOLD, bool(earned[i]))
