class_name Coach
extends Control
## The tutorial guide: a speech bubble with a bouncing arrow and a pulsing ring around the control it points at.
## It never blocks the game: only the bubble itself takes clicks (for its Skip button), so the player presses the
## real button underneath. Main owns one and keeps it above every screen.
## point(target, text) shows it (target may be null for a bubble at the top of the window); clear() hides it.

signal skip_pressed

const BUBBLE_WIDTH := 340.0
const GAP := 26.0  # between the target and the bubble, room for the arrow
const RING := Color("#fde047")

var _target: Control
var _bubble: PanelContainer
var _text: Label
var _skip: Button
var _t := 0.0

func _init() -> void:
	top_level = true
	z_index = 80  # above the screens, below the battle results (90)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_bubble = PanelContainer.new()
	var style := UITheme.box(Color("#101828", 0.96), RING, 2, 10, 12)
	style.shadow_color = Color(RING, 0.35)
	style.shadow_size = 10
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble.custom_minimum_size.x = BUBBLE_WIDTH
	add_child(_bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_bubble.add_child(box)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = BUBBLE_WIDTH - 24
	_text.add_theme_font_size_override("font_size", 16)
	box.add_child(_text)
	_skip = Button.new()
	_skip.text = Terms.t("tutorial_skip")
	_skip.flat = true
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_skip.pressed.connect(skip_pressed.emit)
	box.add_child(_skip)

## Shows the bubble pointing at `target` (null: a bubble near the top of the window, no arrow)
func point(target: Control, text: String) -> void:
	_target = target
	_text.text = text
	visible = true
	_bubble.reset_size()
	_place()

func clear() -> void:
	_target = null
	visible = false

func is_pointing_at(target: Control) -> bool:
	return visible and _target == target

func _process(delta: float) -> void:
	if not visible:
		return
	if _target != null and (not is_instance_valid(_target) or not _target.is_visible_in_tree()):
		clear()
		return
	_t += delta
	_place()
	queue_redraw()

## Below the target if there's room, else above; kept inside the window
func _place() -> void:
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	var b := _bubble.size
	var pos := Vector2((size.x - b.x) * 0.5, 70.0)
	if _target and is_instance_valid(_target):
		var r := _target.get_global_rect()
		pos = Vector2(r.get_center().x - b.x * 0.5, r.end.y + GAP)
		if pos.y + b.y > size.y - 8.0:
			pos.y = r.position.y - GAP - b.y
	pos.x = clampf(pos.x, 8.0, maxf(size.x - b.x - 8.0, 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(size.y - b.y - 8.0, 8.0))
	_bubble.position = pos

func _draw() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var r := _target.get_global_rect()
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	# A ring around the target that breathes
	draw_rect(r.grow(4.0 + pulse * 4.0), Color(RING, 0.35 + 0.5 * pulse), false, 3.0)
	# An arrow from the bubble to the target, bobbing toward it
	var bubble := Rect2(_bubble.position, _bubble.size)
	var below := bubble.position.y > r.get_center().y
	var tip := Vector2(r.get_center().x, (r.end.y + 4.0) if below else (r.position.y - 4.0))
	var bob := sin(_t * 6.0) * 4.0
	var dir := -1.0 if below else 1.0  # the arrow points up when the bubble is below
	tip.y -= dir * bob
	var back := tip - Vector2(0, dir * 16.0)
	draw_colored_polygon(PackedVector2Array([tip, back + Vector2(-11, 0), back + Vector2(11, 0)]), RING)
