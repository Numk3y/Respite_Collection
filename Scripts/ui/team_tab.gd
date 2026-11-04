class_name TeamTab
extends ScrollContainer
## Team screen, gacha party-formation style: a "Team 1" banner with the team's totals, then the six slots in one
## row on a lit stage (Vanguard on the left under a warm spotlight, Rearguard on the right under a cool one).
## Each member is a tall card: framed portrait, class badge, rarity stars, level, Ascension pips and stat bars
## scaled against the rest of the team. Click a card to swap that friend; Details/Remove sit under it.
## Empty slots are dashed outlines with a big "+". Main owns the picker and the details window: it listens to
## change_requested / details_requested and calls refresh() whenever the roster changes.

signal change_requested(slot: int)
signal details_requested(uid: int)

const CARD_SIZE := Vector2(164, 330)
const ART_SIZE := Vector2(148, 196)
const BAR_STATS := ["hp", "attack", "defense", "speed"]
const VANGUARD_COLOR := Color("#ff7a59")
const REARGUARD_COLOR := Color("#59b8ff")
const CLASS_LETTERS := ["T", "W", "M", "S", "B", "H"]  # CharClass order: tank, warrior, mage, shooter, berserker, healer

var _summary: Label
var _stage: Stage
var _slots: Array[Control] = []  # one holder per team slot; its child is the card that moves
var _last_uids: Array[int] = []  # to pop the card of a newly assigned friend
var _shown_once := false

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	add_child(page)
	page.add_child(_build_header())

	_stage = Stage.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(0, CARD_SIZE.y + 96)
	page.add_child(_stage)
	var rows := HBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 34)
	_stage.add_child(rows)
	rows.sort_children.connect(_stage.queue_redraw)  # the spotlights follow the groups
	for vanguard in [true, false]:
		rows.add_child(_build_group(vanguard))
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_animate_in())

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CYAN.darkened(0.35)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(UITheme.CYAN, 0.35)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	var title := _label(Terms.t("team_title").to_upper(), 24, Color.WHITE)
	plate.add_child(title)
	header.add_child(plate)
	_summary = _label("", 16, UITheme.TEXT)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_summary)
	var rules := Button.new()
	rules.text = Terms.t("team_rules_button")
	rules.tooltip_text = Terms.t("team_hint")
	rules.focus_mode = Control.FOCUS_NONE
	rules.mouse_default_cursor_shape = Control.CURSOR_HELP
	header.add_child(rules)
	return header

## One row's group: its name and classes on a coloured tab, then its three slots
func _build_group(vanguard: bool) -> Control:
	var color := VANGUARD_COLOR if vanguard else REARGUARD_COLOR
	var group := VBoxContainer.new()
	group.alignment = BoxContainer.ALIGNMENT_CENTER
	group.add_theme_constant_override("separation", 8)
	var tag := HBoxContainer.new()
	tag.alignment = BoxContainer.ALIGNMENT_CENTER
	tag.add_theme_constant_override("separation", 8)
	group.add_child(tag)
	tag.add_child(_label(Terms.term("vanguard" if vanguard else "rearguard").to_upper(), 20, color))
	tag.add_child(_label(Terms.row_classes(vanguard), 13, UITheme.TEXT_DIM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	group.add_child(row)
	var first := 0 if vanguard else GameState.VANGUARD_SLOTS
	for slot in range(first, first + GameState.VANGUARD_SLOTS):
		var holder := Control.new()
		holder.custom_minimum_size = CARD_SIZE + Vector2(0, 34)  # card + its buttons
		row.add_child(holder)
		_slots.append(holder)
	group.set_meta("color", color)
	return group

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	return label

## Rebuilds every slot from the current team (cheap: six cards)
func refresh() -> void:
	var uids: Array[int] = []
	for slot in GameState.TEAM_SLOTS:
		uids.append(GameState.team_uid(slot))
	# Stat bars are scaled to the best value in the team, so members compare at a glance
	var stats_of := {}
	var best := {}
	for uid in uids:
		if GameState.get_character(uid):
			stats_of[uid] = GameState.get_unit_stats(uid)
			for stat in BAR_STATS:
				best[stat] = maxi(best.get(stat, 1), stats_of[uid][stat])

	var total_hp := 0
	var total_atk := 0
	var levels := 0
	for uid in stats_of:
		total_hp += stats_of[uid].hp
		total_atk += stats_of[uid].attack
		levels += int(GameState.get_owned(uid).level)
	var cost := GameState.team_cost()
	var limit := GameState.team_cost_limit()
	_summary.add_theme_color_override("font_color", Color("#fca5a5") if cost > limit else UITheme.TEXT)
	_summary.mouse_filter = Control.MOUSE_FILTER_STOP  # so the cost tooltip shows
	_summary.tooltip_text = Terms.t("team_cost_tip", {"r": GameState.rarity_cost(CharacterData.Rarity.R),
		"sr": GameState.rarity_cost(CharacterData.Rarity.SR), "ssr": GameState.rarity_cost(CharacterData.Rarity.SSR),
		"limit": limit, "cap": GameState.TEAM_COST_CAP})
	_summary.text = Terms.t("team_summary", {"members": stats_of.size(), "slots": GameState.TEAM_SLOTS,
		"cost": cost, "limit": limit,
		"hp": CurrencyChip._group(total_hp), "atk": CurrencyChip._group(total_atk),
		"lv": roundi(float(levels) / stats_of.size()) if not stats_of.is_empty() else 0})

	for slot in GameState.TEAM_SLOTS:
		var holder := _slots[slot]
		for child in holder.get_children():
			child.queue_free()
		var uid := uids[slot]
		var card: Control
		if stats_of.has(uid):
			card = _member_card(slot, uid, stats_of[uid], best)
		else:
			card = _empty_card(slot)
		holder.add_child(card)
		var joined := _shown_once and is_visible_in_tree() and slot < _last_uids.size() and _last_uids[slot] != uid and uid != 0
		if joined:
			_pop(card)
	_last_uids = uids

func _member_card(slot: int, uid: int, stats: Dictionary, best: Dictionary) -> Control:
	var c := GameState.get_character(uid)
	var o := GameState.get_owned(uid)
	var rarity_color: Color = CharArt.RARITY_COLORS[c.rarity]
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.size = CARD_SIZE + Vector2(0, 34)

	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.tooltip_text = Terms.t("team_card_tip", {"name": c.display_name})
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := UITheme.glow_box(Color(0.06, 0.08, 0.14, 0.92), 10, 6, rarity_color)
	normal.border_color = rarity_color
	normal.set_border_width_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.13, 0.22, 0.95)
	hover.shadow_size = 18
	hover.border_color = rarity_color.lightened(0.35)
	for state in ["normal", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.pressed.connect(change_requested.emit.bind(slot))
	card.mouse_entered.connect(_lift.bind(card, true))
	card.mouse_exited.connect(_lift.bind(card, false))
	root.add_child(card)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	# Portrait with the class badge and level tag over its top corners
	var art_holder := Control.new()
	art_holder.custom_minimum_size = ART_SIZE
	art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(art_holder)
	var art := CharArt.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.set_character(c, c.get_portrait_at(GameState.get_ascension(uid)))
	art_holder.add_child(art)
	if GameState.get_ascension(uid) >= GameState.MAX_ASCENSION:
		art_holder.add_child(AwakenGlow.new())
	var badge := ClassBadge.new(c.char_class)
	badge.position = Vector2(-4, -4)
	art_holder.add_child(badge)
	var level := _label("%s%d" % [Terms.term("level"), int(o.level)], 17, Color.WHITE)
	level.add_theme_constant_override("outline_size", 7)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.size = Vector2(ART_SIZE.x - 6, 24)
	level.position = Vector2(0, 2)
	art_holder.add_child(level)
	var job := Commissions.worker_commission(uid)
	if job:
		var working := UITheme.tag(Terms.t("team_working"), UITheme.TEAL)
		working.position = Vector2(6, ART_SIZE.y - 58)
		working.tooltip_text = Terms.t("card_on_shift", {"job": job.display_name})
		art_holder.add_child(working)

	# Stars and Ascension pips
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", 6)
	marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(marks)
	var stars := GachaBanner.StarRow.new(13.0, rarity_color.lightened(0.15))
	stars.count = GachaBanner.STAR_COUNTS.get(c.rarity, 3)
	marks.add_child(stars)
	var pips := AscensionPips.new(GameState.get_ascension(uid), GameState.MAX_ASCENSION, rarity_color)
	pips.tooltip_text = Terms.t("asc_short", {"rank": GameState.get_ascension(uid), "max": GameState.MAX_ASCENSION})
	marks.add_child(pips)

	for stat in BAR_STATS:
		box.add_child(StatBar.new(Terms.stat_short(stat), stats[stat], best[stat], _stat_color(stat)))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	root.add_child(actions)
	for pair in [["details_button", details_requested.emit.bind(uid)], ["slot_remove", GameState.clear_team_slot.bind(slot, 0)]]:
		var button := Button.new()
		button.text = Terms.t(pair[0])
		button.add_theme_font_size_override("font_size", 13)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 30)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(pair[1])
		actions.add_child(button)
	return root

func _empty_card(slot: int) -> Control:
	var vanguard := GameState.is_vanguard_slot(slot)
	var card := EmptySlot.new(VANGUARD_COLOR if vanguard else REARGUARD_COLOR)
	card.size = CARD_SIZE
	card.tooltip_text = Terms.t("team_empty_tip", {"classes": Terms.row_classes(vanguard)})
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.pressed.connect(change_requested.emit.bind(slot))
	var label := _label(Terms.t("team_empty"), 15, UITheme.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(CARD_SIZE.x, 24)
	label.position = Vector2(0, CARD_SIZE.y * 0.5 + 34)
	card.add_child(label)
	return card

func _stat_color(stat: String) -> Color:
	match stat:
		"hp": return Color("#4ade80")
		"attack": return Color("#f87171")
		"defense": return Color("#60a5fa")
	return Color("#facc15")

## Cards rise into place one after another when the tab is opened
func _animate_in() -> void:
	_shown_once = true
	var cards := 0
	for holder in _slots:
		cards += holder.get_children().filter(func(n): return not n.is_queued_for_deletion()).size()
	if cards == 0:
		return  # not filled yet (refresh() runs after the tab is built); an empty tween would be an error
	var t := create_tween().set_parallel()
	for i in _slots.size():
		for card: Control in _slots[i].get_children():
			if card.is_queued_for_deletion():
				continue
			card.position.y = 46.0
			card.modulate.a = 0.0
			t.tween_property(card, "position:y", 0.0, 0.42).set_delay(0.05 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.05 * i)

## A newly assigned friend bounces in with a bright flash
func _pop(card: Control) -> void:
	card.pivot_offset = CARD_SIZE / 2.0
	card.scale = Vector2(0.8, 0.8)
	card.modulate = Color(1.8, 1.8, 1.8)
	var t := card.create_tween().set_parallel()
	t.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "modulate", Color.WHITE, 0.4)

## Hovered cards lift a little
func _lift(card: Control, up: bool) -> void:
	var t := card.create_tween()
	t.tween_property(card, "position:y", -6.0 if up else 0.0, 0.12).set_trans(Tween.TRANS_SINE)

## Spotlights and a glowing floor behind the formation, warm over the Vanguard, cool over the Rearguard
class Stage extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UITheme.draw_vertical_gradient(self, r, Color(0.05, 0.07, 0.13, 0.75), Color(0.02, 0.03, 0.06, 0.85))
		var rows := get_child(0) as HBoxContainer
		if rows == null or rows.get_child_count() < 2:
			return
		for group: Control in rows.get_children():
			var color: Color = group.get_meta("color", Color.WHITE)
			var g := Rect2(group.position + rows.position, group.size)
			var top := g.position.x + g.size.x * 0.5
			# A cone of light from above, wide at the floor
			var cone := PackedVector2Array([Vector2(top - 40, 0), Vector2(top + 40, 0),
				Vector2(g.end.x + 20, size.y), Vector2(g.position.x - 20, size.y)])
			draw_colored_polygon(cone, Color(color, 0.06))
			UITheme.draw_glow(self, Vector2(top, size.y - 22), g.size.x * 0.55, Color(color, 0.22))
		# Floor line with a soft shine
		draw_line(Vector2(0, size.y - 22), Vector2(size.x, size.y - 22), Color(1, 1, 1, 0.08), 2.0)

## Coloured disc with the class's letter (the default font has no class symbols, so letters it is)
class ClassBadge extends Control:
	var _cls := 0

	func _init(cls: int) -> void:
		_cls = cls
		custom_minimum_size = Vector2(30, 30)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		tooltip_text = Terms.class_label(cls)

	func _draw() -> void:
		var center := size / 2.0
		var color: Color = CharArt.CLASS_COLORS.get(_cls, Color.GRAY)
		draw_circle(center + Vector2(1, 2), 14.0, Color(0, 0, 0, 0.5))
		draw_circle(center, 14.0, color.lightened(0.1))
		draw_arc(center, 14.0, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.0, true)
		var font := ThemeDB.fallback_font
		var letter: String = CLASS_LETTERS[_cls] if _cls < CLASS_LETTERS.size() else "?"
		var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(font, center + Vector2(-text_size.x / 2.0, text_size.y * 0.32), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

## Ascension rank as small diamonds: filled up to the rank
class AscensionPips extends Control:
	var _rank := 0
	var _max := 4
	var _color := Color.WHITE

	func _init(rank: int, max_rank: int, color: Color) -> void:
		_rank = rank
		_max = max_rank
		_color = color
		custom_minimum_size = Vector2(max_rank * 12, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		for i in _max:
			var c := Vector2(6 + i * 12, 7)
			var points := PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0)])
			if i < _rank:
				draw_colored_polygon(points, _color.lightened(0.2))
			else:
				points.append(points[0])
				draw_polyline(points, Color(1, 1, 1, 0.35), 1.2, true)

## "HP ███████░░ 235": a stat with a bar scaled to the team's best value for it
class StatBar extends Control:
	var _name := ""
	var _value := 0
	var _best := 1
	var _color := Color.WHITE

	func _init(stat_name: String, value: int, best: int, color: Color) -> void:
		_name = stat_name
		_value = value
		_best = maxi(best, 1)
		_color = color
		custom_minimum_size = Vector2(0, 15)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(0, 12), _name, HORIZONTAL_ALIGNMENT_LEFT, 32, 11, UITheme.TEXT_DIM)
		var value_text := str(_value)
		var value_width := font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, Vector2(size.x - value_width, 12), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UITheme.TEXT)
		var bar := Rect2(34, 5, size.x - 34 - value_width - 6, 6)
		draw_rect(bar, Color(1, 1, 1, 0.08))
		var share := clampf(float(_value) / _best, 0.0, 1.0)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), _color)

## An empty slot: dashed outline in the row's colour, a big "+" and a soft pulse
class EmptySlot extends Button:
	var _color := Color.WHITE
	var _pulse := 0.0

	func _init(color: Color) -> void:
		_color = color
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = TeamTab.CARD_SIZE
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(delta: float) -> void:
		_pulse = fmod(_pulse + delta, 2.0)
		queue_redraw()

	func _draw() -> void:
		var hovered := is_hovered()
		var glow := 0.5 + 0.5 * sin(_pulse * PI)
		var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		draw_rect(r, Color(_color, 0.1 if hovered else 0.05))
		var dash := 10.0
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], Color(_color, 0.45 + 0.35 * glow), 2.0, dash)
		var c := size * 0.5
		var arm := 22.0 if hovered else 18.0
		draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), Color(_color, 0.9), 5.0)
		draw_line(c - Vector2(0, arm), c + Vector2(0, arm), Color(_color, 0.9), 5.0)
