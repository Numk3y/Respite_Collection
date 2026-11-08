class_name BattleResults
extends Control
## End-of-battle screen over the whole window: a big VICTORY / DEFEAT title (gold rays and confetti on a win),
## the map's stars, the rewards, three award cards (Most Damage, Tanked the Most, Most Healing), a breakdown of every friend's
## damage dealt, damage taken and healing with bars that fill and numbers that count up, and every friend's
## remaining HP along the bottom. Battle Again / Return Home are the way out, plus Next Mission after a win when
## `next_text` is set (event missions with another one after them).
## Stats come from the engine (result.stats, one entry per unit in result.units order); only HP actually
## removed or restored counts, so overkill and overheal don't inflate them.

signal again_pressed
signal home_pressed
signal next_pressed

const GOLD := Color("#ffd75e")
const DEFEAT_RED := Color("#ff6b6b")
const STAT_COLORS := {"dealt": Color("#ff8f5a"), "taken": Color("#5aa9ff"), "healed": Color("#4ade80")}
const STAT_ORDER := ["dealt", "taken", "healed"]

var _dim: ColorRect
var _rays: Rays
var _content: VBoxContainer
var _note: Label
var next_text := ""  # e.g. "Next: 1-2 Monument Run"; empty = no Next Mission button

## An extra line under the rewards (the world boss server's answer)
func set_note(text: String) -> void:
	if _note:
		_note.text = text
		_note.visible = not text.is_empty()

func _init() -> void:
	top_level = true  # covers the whole window, not just the arena it's added to
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_STOP  # the battle underneath can't be clicked through it
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.05, 0.93)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_rays = Rays.new()
	_rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rays)

## Builds and plays the screen. `lines` are the reward/level-up lines already written for the footer.
func open(battle: Dictionary, stage_name: String, lines: PackedStringArray) -> void:
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	var boss: bool = battle.report.get("world_boss", false)
	var win: bool = battle.win or boss  # a world boss fight always ends in a show of the damage done
	_rays.color = GOLD if win else DEFEAT_RED
	_rays.visible = win
	Sound.play("victory" if win else "defeat")

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	# Scrolls when a short window can't fit everything (long reward lines on a first clear, six friends),
	# so the buttons at the bottom can always be reached
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = false  # the title's scale-in pop would otherwise get cut off at the edges
	margin.add_child(scroll)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	var title_key := "results_world_boss" if boss else ("results_victory" if win else "results_defeat")
	var title := _label(Terms.t(title_key), 52, GOLD if win else DEFEAT_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 5)
	_content.add_child(title)
	var sub_text := stage_name if boss else "%s  ·  %s" % [stage_name,
		Terms.t("results_waves", {"cleared": battle.waves_cleared, "total": battle.wave_count})]
	var sub := _label(sub_text, 16, UITheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(sub)
	# The map's 3 stars; ones earned for the first time pop in
	if not boss and battle.report.has("stars"):
		var star_row := CenterContainer.new()
		_content.add_child(star_row)
		var meter := StarMeter.new(34.0, battle.report.stars)
		star_row.add_child(meter)
		meter.pop.call_deferred(battle.report.get("new_stars", []))
	if not lines.is_empty():
		var rewards := _label(" · ".join(lines), 22 if boss else 14, GOLD if boss else UITheme.TEXT)
		rewards.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rewards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(rewards)
	_note = _label("", 15, UITheme.CYAN)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	_content.add_child(_note)

	# The friends and their numbers
	var friends: Array[Dictionary] = []
	for i in battle.units.size():
		var u: Dictionary = battle.units[i]
		if u.side == 0:
			friends.append({"name": u.name, "data": u.data, "stats": battle.stats[i]})
	var best := {}
	for key in STAT_ORDER:
		best[key] = 0
		for f in friends:
			best[key] = maxi(best[key], int(f.stats[key]))

	var awards := HBoxContainer.new()
	awards.alignment = BoxContainer.ALIGNMENT_CENTER
	awards.add_theme_constant_override("separation", 18)
	_content.add_child(awards)
	var award_keys := {"dealt": "results_most_damage", "taken": "results_most_tanked", "healed": "results_most_healing"}
	var cards: Array[Control] = []
	for key in STAT_ORDER:
		var top: Dictionary = {}
		for f in friends:
			if int(f.stats[key]) > 0 and (top.is_empty() or int(f.stats[key]) > int(top.stats[key])):
				top = f
		var card := _award_card(Terms.t(award_keys[key]), STAT_COLORS[key], top, key)
		awards.add_child(card)
		cards.append(card)

	_content.add_child(_breakdown(friends, best))
	_content.add_child(_hp_strip(friends))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_content.add_child(buttons)
	# After a win with another mission waiting, moving on is the highlighted choice
	var show_next := win and not boss and not next_text.is_empty()
	var choices := [[Terms.t("battle_again"), again_pressed, not show_next], [Terms.t("battle_home"), home_pressed, false]]
	if show_next:
		choices.append([next_text, next_pressed, true])
	for pair in choices:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size = Vector2(170, 44)
		if pair[2]:
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(pair[1].emit)
		buttons.add_child(button)

	if win:
		_confetti()
	_animate_in(title, cards)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	return label

## An award: its title, the winner's portrait and name, and the amount counting up
func _award_card(title: String, color: Color, winner: Dictionary, key: String) -> Control:
	var panel := PanelContainer.new()
	var style := UITheme.glow_box(Color(0.06, 0.08, 0.15, 0.95), 10, 10, color)
	style.border_color = color
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(250, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var art := CharArt.new()
	art.custom_minimum_size = Vector2(58, 72)
	if not winner.is_empty() and winner.data:
		art.set_character(winner.data)
	else:
		art.set_mystery("")
	row.add_child(art)
	var lines := VBoxContainer.new()
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 0)
	row.add_child(lines)
	lines.add_child(_label(title.to_upper(), 14, color))
	lines.add_child(_label(winner.name if not winner.is_empty() else Terms.t("results_nobody"), 20, Color.WHITE))
	var amount := _label("0" if not winner.is_empty() else "-", 26, color.lightened(0.25))
	amount.add_theme_constant_override("outline_size", 8)
	lines.add_child(amount)
	if not winner.is_empty():
		_count_up(amount, int(winner.stats[key]), 1.1)
	return panel

## Every friend's damage dealt / taken / healing, each as a bar against the team's best for that column
func _breakdown(friends: Array[Dictionary], best: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := UITheme.panel_box(10)
	panel.add_theme_stylebox_override("panel", style)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	panel.add_child(grid)
	grid.add_child(_label(Terms.t("results_friend"), 13, UITheme.TEXT_DIM))
	var heads := {"dealt": "results_dealt", "taken": "results_taken", "healed": "results_healed"}
	for key in STAT_ORDER:
		var head := _label(Terms.t(heads[key]), 13, STAT_COLORS[key])
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(head)
	for i in friends.size():
		var f := friends[i]
		var name_label := _label(f.name, 16, Color.WHITE)
		name_label.custom_minimum_size = Vector2(170, 0)
		name_label.clip_text = true
		grid.add_child(name_label)
		for key in STAT_ORDER:
			var bar := StatBar.new(STAT_COLORS[key])
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(bar)
			var share := float(f.stats[key]) / maxf(float(best[key]), 1.0)
			var t := bar.create_tween().set_parallel()
			t.tween_property(bar, "fill", share, 0.8).set_delay(0.5 + 0.08 * i).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			t.tween_method(bar.set_amount, 0.0, float(f.stats[key]), 0.8).set_delay(0.5 + 0.08 * i)
			bar.top = int(f.stats[key]) > 0 and int(f.stats[key]) == int(best[key])
	return panel

## Every friend's HP left at the end of the fight: a bar draining from full to what's left, the numbers, and
## DOWN for anyone knocked out
func _hp_strip(friends: Array[Dictionary]) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label(Terms.t("results_hp_left"), 13, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for i in friends.size():
		var s: Dictionary = friends[i].stats
		var cell := HpCell.new(friends[i].name, int(s.hp), int(s.max_hp))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)
		var t := cell.create_tween()
		t.tween_property(cell, "fill", float(s.hp) / maxf(float(s.max_hp), 1.0), 0.9).set_delay(0.7 + 0.06 * i) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return box

func _count_up(label: Label, to: int, seconds: float) -> void:
	var t := label.create_tween()
	t.tween_method(func(v: float): label.text = CurrencyChip._group(roundi(v)), 0.0, float(to), seconds).set_delay(0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_in(title: Label, cards: Array[Control]) -> void:
	modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.3)
	title.pivot_offset = Vector2(size.x / 2.0 - 40, 40)
	title.scale = Vector2(2.2, 2.2)
	t.tween_property(title, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in cards.size():
		var card := cards[i]
		card.modulate.a = 0.0
		t.tween_property(card, "modulate:a", 1.0, 0.3).set_delay(0.25 + 0.12 * i)

func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(size.x / 2.0, -20)
	p.amount = 90
	p.lifetime = 4.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size.x / 2.0, 10)
	p.direction = Vector2.DOWN
	p.spread = 25.0
	p.gravity = Vector2(0, 90)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 120.0
	p.angle_max = 360.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	var colors := [GOLD, Color("#ff6fa8"), Color("#5ec8ff"), Color("#7dff9b"), Color.WHITE]
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(colors)
	p.color_initial_ramp = ramp
	add_child(p)
	move_child(p, 2)  # behind the text, above the rays

## Slowly turning light rays behind the title
class Rays extends Control:
	var color := Color.WHITE
	var _angle := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if visible:
			_angle += delta * 0.12
			queue_redraw()

	func _draw() -> void:
		var center := Vector2(size.x / 2.0, 60)
		var reach := size.length()
		for i in 16:
			var a := _angle + TAU * i / 16
			var half := TAU / 16 * 0.2
			draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(a - half) * reach,
				center + Vector2.from_angle(a + half) * reach]), Color(color, 0.05))
		UITheme.draw_glow(self, center, 260.0, Color(color, 0.25))

## One friend's remaining HP: name and "126 / 184" (or DOWN) above a bar coloured by how much is left
class HpCell extends Control:
	var fill := 1.0:  # starts full and drains to what's left
		set(value):
			fill = value
			queue_redraw()
	var _name := ""
	var _hp := 0
	var _max := 1

	func _init(friend_name: String, hp: int, max_hp: int) -> void:
		_name = friend_name
		_hp = hp
		_max = maxi(max_hp, 1)
		custom_minimum_size = Vector2(100, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = friend_name

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var down := _hp <= 0
		var right := Terms.t("results_down") if down else "%d / %d" % [_hp, _max]
		var right_w := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(0, 13), _name, HORIZONTAL_ALIGNMENT_LEFT, size.x - right_w - 6, 13, Color.WHITE)
		draw_string(font, Vector2(size.x - right_w, 13), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color("#f87171") if down else UITheme.TEXT)
		var bar := Rect2(0, 20, size.x, 10)
		draw_rect(bar, Color(0, 0, 0, 0.5))
		var share := clampf(fill, 0.0, 1.0)
		var color := Color("#22c55e") if share > 0.5 else Color("#f59e0b") if share > 0.25 else Color("#ef4444")
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), color)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y * 0.4)), Color(1, 1, 1, 0.18))
		draw_rect(bar, Color(1, 1, 1, 0.15), false, 1.0)

## A bar with its amount at the right; the team's best in a column gets a bright edge
class StatBar extends Control:
	var fill := 0.0:
		set(value):
			fill = value
			queue_redraw()
	var top := false
	var _amount := 0
	var _color := Color.WHITE

	func _init(color: Color) -> void:
		_color = color
		custom_minimum_size = Vector2(150, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_amount(value: float) -> void:
		_amount = roundi(value)
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var text := CurrencyChip._group(_amount)
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var bar := Rect2(0, 6, size.x - text_w - 10, 9)
		draw_rect(bar, Color(1, 1, 1, 0.07))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), _color)
		if top and fill > 0.0:
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * fill, bar.size.y)), Color(1, 1, 1, 0.8), false, 1.5)
		draw_string(font, Vector2(size.x - text_w, 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color.WHITE if _amount > 0 else UITheme.TEXT_DIM)
