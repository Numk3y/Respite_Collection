class_name LevelUpBanner
extends Control
## A full-window celebration for an account level up: turning gold rays, a ribbon across the middle with
## "ACCOUNT LEVEL UP", the old and new level, and what the new level opened up (team cost, friends' level cap, the
## Arena). Click anywhere, or wait a few seconds, to close. Main shows it when the player gets back Home after the
## battle that levelled them up.

const GOLD := Color("#ffd75e")
const SHOW_SECONDS := 4.5

var _closing := false

## `from` and `to`: the account level before and after (several levels at once is fine)
func open(from: int, to: int) -> void:
	top_level = true
	z_index = 95
	mouse_filter = Control.MOUSE_FILTER_STOP
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var rays := BattleResults.Rays.new()
	rays.color = GOLD
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rays)
	rays.position.y = size.y * 0.5 - 60.0  # the rays come from the ribbon, not the top

	# The ribbon: a slanted gold band across the window
	var band := Band.new()
	band.size = Vector2(size.x, 190)
	band.position = Vector2(0, size.y * 0.5 - 95)
	add_child(band)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.size = Vector2(size.x, 190)
	box.position = band.position
	add_child(box)
	var title := _label(Terms.t("levelup_title"), 46, GOLD, 14)
	box.add_child(title)
	box.add_child(_label(Terms.t("levelup_levels", {"from": from, "to": to}), 26, Color.WHITE, 8))
	var unlocks := PackedStringArray()
	var cost_before := GameState.team_cost_limit_at(from)
	var cost_after := GameState.team_cost_limit_at(to)
	if cost_after > cost_before:
		unlocks.append(Terms.t("levelup_cost", {"from": cost_before, "to": cost_after}))
	unlocks.append(Terms.t("levelup_cap", {"cap": mini(to + GameState.LEVEL_CAP_ABOVE_ACCOUNT, GameState.MAX_LEVEL)}))
	if from < Arena.MIN_ACCOUNT_LEVEL and to >= Arena.MIN_ACCOUNT_LEVEL:
		unlocks.append(Terms.t("levelup_arena"))
	box.add_child(_label("   ·   ".join(unlocks), 17, Color("#fde68a"), 5))

	Sound.play("account_up")
	modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.25)
	title.pivot_offset = Vector2(size.x * 0.5, 30)
	title.scale = Vector2(1.8, 1.8)
	t.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	band.scale = Vector2(1.0, 0.0)
	band.pivot_offset = band.size * 0.5
	t.tween_property(band, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(SHOW_SECONDS).timeout.connect(_close)

func _label(text: String, font_size: int, color: Color, outline: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", outline)
	return label

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		accept_event()
		_close()

func _close() -> void:
	if _closing or not is_inside_tree():
		return
	_closing = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25)
	t.tween_callback(queue_free)

## The gold ribbon: darker edges, a bright middle line, slanted ends
class Band extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var top := Color(0.35, 0.24, 0.02, 0.92)
		var mid := Color(0.55, 0.38, 0.05, 0.95)
		UITheme.draw_vertical_gradient(self, Rect2(0, 0, size.x, size.y * 0.5), top, mid)
		UITheme.draw_vertical_gradient(self, Rect2(0, size.y * 0.5, size.x, size.y * 0.5), mid, top)
		draw_line(Vector2(0, 2), Vector2(size.x, 2), Color(1.0, 0.9, 0.5, 0.9), 3.0)
		draw_line(Vector2(0, size.y - 2), Vector2(size.x, size.y - 2), Color(1.0, 0.9, 0.5, 0.9), 3.0)
