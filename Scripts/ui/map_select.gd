class_name MapSelect
extends Control
## The Sortie screen, gacha story-map style. The chapter's picture fills the background with sparkles drifting
## over it; tabs pick the chapter (practice maps get their own tab; the first locked chapter shows what opens it).
## The chapter's maps sit as nodes along a glowing route, light flowing along the open stretches: cleared maps
## carry a check, the next one to play bounces a NEXT tag, the boss node is bigger and red, locked ones are grey
## with a lock. Clicking a node fills the detail panel below: the map's picture, story text, recommended level,
## number of battles, the enemies you'll meet, the rewards (first-clear bonus included) and a glowing BATTLE button.
## Main listens to battle_pressed / back_pressed.

signal battle_pressed(stage: StageData)
signal auto_run_pressed(stage: StageData)  # Auto Run on a 3-star map (Main asks how many runs)
signal back_pressed

const PRACTICE := 0  # "chapter" of the maps outside the story
const ENEMY_AVATAR := Vector2(46, 56)
const MAX_ENEMIES := 8

var _background: TextureRect
var _tabs: HBoxContainer
var _tab_buttons := {}  # chapter -> Button
var _route: Route
var _detail_art: TextureRect
var _detail_code: Label
var _detail_title: Label
var _detail_text: Label
var _chips: HBoxContainer
var _enemies: HBoxContainer
var _rewards: VBoxContainer
var _stars: VBoxContainer  # the map's three star goals, earned ones lit
var _battle: Button
var _auto: Button  # Auto Run: unlocked by 3 stars on the map
var _battle_note: Label
var _chapter := -1
var _stage: StageData
var _can_battle := false
var _event: EventData  # set by open_event: the event's missions instead of the story
var _banner_label: Label
var _hint_label: Label

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.modulate = Color(0.42, 0.42, 0.5)
	_full(_background)
	_full(Shade.new())
	_full(CollectionTab.Sparkles.new())

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	_full(content)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(_build_header())
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	content.add_child(_tabs)
	_battle_note = _label("", 14, Color("#fca5a5"))
	content.add_child(_battle_note)
	_route = Route.new()
	_route.custom_minimum_size.y = 150
	_route.stage_picked.connect(_select_stage)
	content.add_child(_route)
	content.add_child(_build_detail())

func _full(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	return node

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 5)
	return label

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#ff6b4a").darkened(0.1)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color("#ff6b4a", 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	_banner_label = _label(Terms.t("map_banner").to_upper(), 24, Color.WHITE)
	plate.add_child(_banner_label)
	header.add_child(plate)
	_hint_label = _label(Terms.t("map_title"), 15, UITheme.TEXT_DIM)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_hint_label)
	var back := Button.new()
	back.text = Terms.t("back")
	back.custom_minimum_size = Vector2(110, 38)
	back.pressed.connect(back_pressed.emit)
	header.add_child(back)
	return header

func _build_detail() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.glow_box(Color(0.04, 0.06, 0.11, 0.9), 12, 14, UITheme.CYAN))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	# The map's picture with its code over it
	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(280, 0)
	art_holder.clip_contents = true
	row.add_child(art_holder)
	_detail_art = TextureRect.new()
	_detail_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_holder.add_child(_detail_art)
	var art_shade := Shade.new()
	art_shade.bottom_only = true
	art_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_holder.add_child(art_shade)
	var sheen := CollectionTab.Sheen.new(true)
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_holder.add_child(sheen)
	_detail_code = _label("", 40, Color.WHITE)
	_detail_code.add_theme_constant_override("outline_size", 10)
	_detail_code.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_detail_code.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_detail_code.offset_left = 12
	_detail_code.offset_bottom = -6
	art_holder.add_child(_detail_code)

	# Name, story, chips and enemies
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	_detail_title = _label("", 24, Color.WHITE)
	info.add_child(_detail_title)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	info.add_child(_chips)
	_detail_text = _label("", 14, UITheme.TEXT)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size.x = 200
	info.add_child(_detail_text)
	_stars = VBoxContainer.new()
	_stars.add_theme_constant_override("separation", 2)
	info.add_child(_stars)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	info.add_child(_label(Terms.t("map_enemies"), 13, UITheme.TEXT_DIM))
	_enemies = HBoxContainer.new()
	_enemies.add_theme_constant_override("separation", 6)
	info.add_child(_enemies)

	# Rewards and the Battle button
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 220
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	side.add_child(_label(Terms.t("map_rewards"), 13, UITheme.TEXT_DIM))
	_rewards = VBoxContainer.new()
	_rewards.add_theme_constant_override("separation", 3)
	side.add_child(_rewards)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(push)
	_battle = Button.new()
	_battle.text = Terms.t("map_go").to_upper()
	_battle.theme_type_variation = &"PrimaryButton"
	_battle.custom_minimum_size = Vector2(220, 62)
	_battle.add_theme_font_size_override("font_size", 24)
	_battle.pressed.connect(func():
		if _stage:
			battle_pressed.emit(_stage))
	_auto = Button.new()
	_auto.text = Terms.t("auto_run_button", {"max": Combat.AUTO_RUN_MAX})
	_auto.custom_minimum_size = Vector2(220, 40)
	_auto.pressed.connect(func():
		if _stage:
			auto_run_pressed.emit(_stage))
	side.add_child(_auto)
	side.add_child(_battle)
	# The Battle button breathes so it's the obvious next step
	var pulse := _battle.create_tween().set_loops()
	pulse.tween_property(_battle, "modulate", Color(1.18, 1.18, 1.18), 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_battle, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return panel

## Shows the selected map again (after an Auto Run changed what's earned there)
func refresh_stage() -> void:
	if _stage:
		_select_stage(_stage)

## The big Battle button (the tutorial points at it)
func battle_button() -> Button:
	return _battle

## Why the Battle button is off: an empty team, or one over the cost limit
func _need_team_text() -> String:
	if GameState.has_team() and GameState.is_team_over_cost():
		return Terms.t("team_over_cost", {"cost": GameState.team_cost(), "limit": GameState.team_cost_limit()})
	return Terms.t("map_need_team")

## Fills the screen; opens on the chapter (and map) the player is up to
func open(can_battle: bool) -> void:
	_can_battle = can_battle
	_battle_note.text = "" if can_battle else _need_team_text()
	_battle_note.visible = not can_battle
	var group := ButtonGroup.new()
	var chapters: Array[int] = []
	if DB.stages.any(func(s): return not s.is_story()):
		chapters.append(PRACTICE)
	chapters.append_array(DB.chapters())
	var current := PRACTICE
	for chapter in chapters:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = 36
		if chapter == PRACTICE:
			button.text = Terms.t("map_section_test")
		elif not GameState.is_chapter_unlocked(chapter):
			button.text = Terms.t("map_tab_locked", {"number": chapter})
			button.disabled = true
			button.tooltip_text = Terms.t("map_chapter_locked", {"previous": chapter - 1, "code": "%d-%d" % [chapter - 1, StageData.BOSS_NUMBER]})
			_tabs.add_child(button)
			break  # later chapters stay hidden
		else:
			button.text = Terms.chapter_title(chapter)
			current = chapter
		button.pressed.connect(_select_chapter.bind(chapter))
		_tabs.add_child(button)
		_tab_buttons[chapter] = button
	_select_chapter(current)

## The event's missions instead of the story: one tab per part, opening in the event's own order
func open_event(event: EventData, can_battle: bool) -> void:
	_event = event
	_banner_label.text = event.display_name.to_upper()
	_hint_label.text = Terms.t("event_map_hint")
	_can_battle = can_battle
	_battle_note.text = "" if can_battle else _need_team_text()
	_battle_note.visible = not can_battle
	var group := ButtonGroup.new()
	var current := -1
	for chapter in event.chapters():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.y = 36
		button.text = Terms.t("event_part", {"number": chapter})
		button.disabled = not event.chapter_missions(chapter).any(func(s): return GameState.is_stage_unlocked(s))
		if not button.disabled:
			current = chapter
		button.pressed.connect(_select_chapter.bind(chapter))
		_tabs.add_child(button)
		_tab_buttons[chapter] = button
	if current >= 0:
		_select_chapter(current)

func _select_chapter(chapter: int) -> void:
	_chapter = chapter
	if _tab_buttons.has(chapter):
		_tab_buttons[chapter].button_pressed = true
	var stages: Array = []  # StageData or null (a map that doesn't exist yet)
	if _event:
		stages = _event.chapter_missions(chapter)
	elif chapter == PRACTICE:
		stages = DB.stages.filter(func(s): return not s.is_story())
	else:
		for number in range(1, StageData.BOSS_NUMBER + 1):
			stages.append(DB.get_map(chapter, number))
	_route.set_stages(stages, chapter)
	# Open on the next map to play, else the last open one
	var pick: StageData = null
	for s in stages:
		if s and GameState.is_stage_unlocked(s):
			pick = s
			if not GameState.is_stage_cleared(s.id):
				break
	if pick:
		_select_stage(pick)
	# Crossfade the background to this chapter's picture
	var texture := _picture(pick if pick else null, chapter)
	if texture != _background.texture:
		var t := _background.create_tween()
		t.tween_property(_background, "modulate:a", 0.0, 0.15)
		t.tween_callback(func(): _background.texture = texture)
		t.tween_property(_background, "modulate:a", 1.0, 0.35)

## A map's own picture, else its chapter's (Art/backgrounds/PoppyStreet.png for "Poppy Street"), else the shared one
func _picture(stage: StageData, chapter: int) -> Texture2D:
	if stage and stage.background:
		return stage.background
	if _event and _event.banner:
		return _event.banner
	var chapter_bg := UITheme.background(Terms.chapter_name(chapter).replace(" ", "")) if chapter > 0 else null
	return chapter_bg if chapter_bg else UITheme.background("battle")

func _select_stage(stage: StageData) -> void:
	_stage = stage
	_route.selected = stage
	var unlocked := GameState.is_stage_unlocked(stage)
	var cleared := GameState.is_stage_cleared(stage.id)
	_detail_art.texture = _picture(stage, stage.chapter)
	_detail_code.text = stage.code() if stage.is_story() else ""
	_detail_title.text = stage.display_name
	_detail_title.add_theme_color_override("font_color", Color("#ff8a80") if stage.is_boss() else Color.WHITE)
	_detail_text.text = stage.description

	for child in _chips.get_children():
		child.queue_free()
	_chips.add_child(UITheme.tag(Terms.t("map_recommended", {"lv": stage.recommended_level}), UITheme.CYAN))
	_chips.add_child(UITheme.tag(Terms.t("map_battles", {"count": stage.wave_count()}), Color("#a78bfa")))
	if stage.is_boss():
		_chips.add_child(UITheme.tag(Terms.t("map_boss_tag"), Color("#ef4444")))
	if cleared:
		_chips.add_child(UITheme.tag(Terms.t("map_cleared"), Color("#4ade80")))

	# Star goals: a lit star for each one already earned here
	for child in _stars.get_children():
		child.queue_free()
	var bits := GameState.get_star_bits(stage.id)
	for i in GameState.STAR_COUNT:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var earned := (bits & (1 << i)) != 0
		line.add_child(StarMeter.new(15.0, [earned]))
		line.add_child(_label(Terms.star_goal(stage, i), 13, UITheme.TEXT if earned else UITheme.TEXT_DIM))
		_stars.add_child(line)
	if stage.star_goal == StageData.StarGoal.MAX_ULTIMATES and (bits & 4) == 0:
		var tip := _label(Terms.t("star_manual_hint"), 12, UITheme.CYAN)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_stars.add_child(tip)

	for child in _enemies.get_children():
		child.queue_free()
	for c in _enemy_list(stage).slice(0, MAX_ENEMIES):
		var art := CharArt.new()
		art.custom_minimum_size = ENEMY_AVATAR
		art.set_character(c)
		art.tooltip_text = c.display_name
		art.mouse_filter = Control.MOUSE_FILTER_PASS
		_enemies.add_child(art)

	for child in _rewards.get_children():
		child.queue_free()
	_rewards.add_child(_reward_line(Terms.t("map_reward_money", {"amount": stage.reward_money}), UITheme.GOLD))
	for key in stage.reward_materials:
		var range_v: Vector2i = stage.reward_materials[key]
		_rewards.add_child(_reward_line(Terms.t("map_reward_material", {"material": Terms.material_name(key), "min": range_v.x, "max": range_v.y}), UITheme.TEXT))
	if stage.exp_reward > 0:
		_rewards.add_child(_reward_line(Terms.t("map_reward_exp", {"amount": stage.exp_reward}), Color("#93c5fd")))
	if not stage.equipment_drops.is_empty():
		var rarities: Array[int] = []
		for e in stage.equipment_drops:
			if e and not rarities.has(int(e.rarity)):
				rarities.append(int(e.rarity))
		rarities.sort()
		var names := PackedStringArray(rarities.map(func(r): return Terms.rarity_name(r)))
		_rewards.add_child(_reward_line(Terms.t("map_reward_gear", {"chance": roundi(stage.drop_chance * 100),
			"rarities": "/".join(names)}), Color("#c4b5fd")))
	if not cleared:
		_rewards.add_child(_reward_line(Terms.t("map_reward_first", {"amount": GameState.FIRST_CLEAR_CREDIT_CARDS}), Color("#ffe259")))
	if (bits & 6) != 6:  # a 2nd or 3rd star still to earn
		_rewards.add_child(_reward_line(Terms.t("map_reward_star", {"amount": GameState.STAR_CREDIT_CARDS}), Color("#ffe259")))

	_battle.disabled = not _can_battle or not unlocked
	_auto.disabled = not Combat.can_auto_run(stage)
	_auto.tooltip_text = Terms.t("auto_run_tip" if not _auto.disabled else "auto_run_locked", {"max": Combat.AUTO_RUN_MAX})
	var previous := "%d-%d" % [stage.chapter, stage.number - 1]
	if _event and _event.missions.find(stage) > 0:
		previous = _event.missions[_event.missions.find(stage) - 1].code()
	_battle.tooltip_text = "" if unlocked else Terms.t("map_locked", {"previous": previous})
	# A little pop as the panel changes
	_detail_title.pivot_offset = Vector2(0, _detail_title.size.y / 2.0)
	_detail_title.modulate.a = 0.0
	_detail_title.create_tween().tween_property(_detail_title, "modulate:a", 1.0, 0.25)

func _reward_line(text: String, color: Color) -> Label:
	return _label(text, 15, color)

## Every different enemy of the map, in the order they show up
func _enemy_list(stage: StageData) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	var groups: Array = []
	if stage.waves.is_empty():
		groups.append(stage.enemy_vanguard + stage.enemy_rearguard)
	for w in stage.waves:
		if w:
			groups.append(w.enemy_vanguard + w.enemy_rearguard)
	for group in groups:
		for c in group:
			if c and not out.has(c):
				out.append(c)
	return out

## The chapter's maps as nodes along a route. Open stretches of the path have light flowing along them.
class Route extends Control:
	signal stage_picked(stage: StageData)
	const NODE := 74.0
	const BOSS_NODE := 92.0
	var selected: StageData:
		set(value):
			selected = value
			for n in _nodes:
				n.queue_redraw()
	var _nodes: Array[StageNode] = []
	var _flow := 0.0

	func _init() -> void:
		resized.connect(_place)

	func set_stages(stages: Array, chapter: int) -> void:
		for n in _nodes:
			n.queue_free()
		_nodes.clear()
		var next_found := false
		for i in stages.size():
			var stage: StageData = stages[i]
			var node := StageNode.new(stage, i + 1, chapter, self)
			if stage and GameState.is_stage_unlocked(stage) and not GameState.is_stage_cleared(stage.id) and not next_found \
					and stage.is_story():
				node.is_next = true
				next_found = true
			if stage:
				node.pressed.connect(func(): stage_picked.emit(stage))
			add_child(node)
			_nodes.append(node)
			# Nodes pop in one after another
			node.modulate.a = 0.0
			var t := node.create_tween()
			t.tween_property(node, "modulate:a", 1.0, 0.3).set_delay(0.06 * i)
		_place()

	func _place() -> void:
		var count := _nodes.size()
		if count == 0 or size.x <= 0.0:
			return
		var gap := size.x / count
		for i in count:
			var n := _nodes[i]
			var s := n.custom_minimum_size
			var center := Vector2(gap * (i + 0.5), size.y * (0.42 if i % 2 == 0 else 0.62))
			n.base_position = center - s / 2.0
			n.position = n.base_position
			n.size = s
		queue_redraw()

	func _process(delta: float) -> void:
		_flow = fmod(_flow + delta * 40.0, 24.0)
		queue_redraw()

	func _draw() -> void:
		for i in _nodes.size() - 1:
			var a := _nodes[i].base_position + _nodes[i].size / 2.0
			var b := _nodes[i + 1].base_position + _nodes[i + 1].size / 2.0
			var open: bool = _nodes[i + 1].stage != null and GameState.is_stage_unlocked(_nodes[i + 1].stage)
			draw_line(a, b, Color(1, 1, 1, 0.12), 8.0, true)
			if not open:
				continue
			draw_line(a, b, Color(UITheme.CYAN, 0.35), 3.0, true)
			# Light flowing along the open path: short bright dashes moving from a to b
			var length := a.distance_to(b)
			var dir := (b - a) / length
			var d := _flow
			while d < length:
				draw_line(a + dir * d, a + dir * minf(d + 8.0, length), Color(UITheme.CYAN_BRIGHT, 0.9), 3.0, true)
				d += 24.0

## One map on the route: a round badge with its code; cleared = check, next = bouncing NEXT tag, boss = bigger
## and red, locked = grey with a lock, not made yet = faint "?"
class StageNode extends Button:
	var stage: StageData
	var is_next := false
	var base_position := Vector2.ZERO
	var _number := 0
	var _route: Route
	var _t := 0.0

	func _init(s: StageData, number: int, chapter: int, route: Route) -> void:
		stage = s
		_number = number
		_route = route
		flat = true
		focus_mode = Control.FOCUS_NONE
		var big := s != null and s.is_boss()
		custom_minimum_size = Vector2.ONE * (Route.BOSS_NODE if big else Route.NODE)
		if s == null:
			disabled = true
			tooltip_text = Terms.t("map_coming_soon", {"code": "%d-%d" % [chapter, number]})
		else:
			tooltip_text = s.display_name
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(delta: float) -> void:
		_t += delta
		if is_next or _route.selected == stage:
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := size.x / 2.0 - 4.0
		var font := ThemeDB.fallback_font
		var unlocked := stage != null and GameState.is_stage_unlocked(stage)
		var cleared := stage != null and GameState.is_stage_cleared(stage.id)
		var boss := stage != null and stage.is_boss()
		var accent := Color("#ef4444") if boss else (Color("#4ade80") if cleared else UITheme.CYAN)
		if not unlocked:
			accent = Color(0.5, 0.52, 0.58)
		var selected := stage != null and _route.selected == stage
		var hover := is_hovered() and unlocked
		# Glow, badge and rim
		if unlocked:
			var pulse := 0.5 + 0.5 * sin(_t * 4.0) if (is_next or selected) else 0.4
			UITheme.draw_glow(self, c, r * 1.6, Color(accent, 0.25 + 0.25 * pulse))
		draw_circle(c, r, Color(0.05, 0.07, 0.12, 0.95))
		draw_circle(c, r * 0.86, Color(accent.darkened(0.55), 0.95 if unlocked else 0.6))
		draw_arc(c, r, 0, TAU, 48, accent.lightened(0.3 if hover else 0.0), 4.0 if boss else 3.0, true)
		if selected:
			draw_arc(c, r + 6.0, 0, TAU, 48, Color.WHITE, 2.5, true)
		# The code (or a lock / question mark)
		var text := stage.code() if stage and stage.is_story() else ("" if stage else "?")
		if stage and not stage.is_story():
			text = str(_number)
		var font_size := 22 if boss else 19
		if not unlocked and stage != null:
			_lock(c + Vector2(0, -2), r * 0.42)
		else:
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string_outline(font, c + Vector2(-w / 2.0, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0, 0, 0, 0.8))
			draw_string(font, c + Vector2(-w / 2.0, font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				Color.WHITE if stage else Color(1, 1, 1, 0.3))
		if cleared:
			_check(c + Vector2(r * 0.62, -r * 0.62))
		# The map's stars along the bottom of the node
		if unlocked:
			var bits := GameState.get_star_bits(stage.id)
			var star_r := 7.0
			var base := Vector2(c.x - (star_r * 2.0 + 2.0), size.y - 2.0)
			draw_rect(Rect2(base + Vector2(-star_r - 4.0, -star_r - 3.0), Vector2((star_r * 2.0 + 2.0) * 2.0 + star_r * 2.0 + 8.0, star_r * 2.0 + 6.0)),
				Color(0.02, 0.03, 0.06, 0.85))
			for i in GameState.STAR_COUNT:
				UITheme.draw_star(self, base + Vector2(i * (star_r * 2.0 + 2.0), 0), star_r, StarMeter.GOLD, (bits & (1 << i)) != 0)
		# Little tags above: BOSS, and NEXT bouncing on the map to play next
		var tag := ""
		var tag_color := Color.WHITE
		if is_next:
			tag = Terms.t("map_next")
			tag_color = UITheme.GOLD
		elif boss:
			tag = Terms.t("map_boss_tag")
			tag_color = Color("#ef4444")
		if not tag.is_empty():
			var bounce := absf(sin(_t * 3.5)) * 5.0 if is_next else 0.0
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var pos := Vector2(c.x - tw / 2.0, -4.0 - bounce)
			draw_string_outline(font, pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color(0, 0, 0, 0.9))
			draw_string(font, pos, tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tag_color)

	## A small drawn padlock
	func _lock(c: Vector2, s: float) -> void:
		var grey := Color(0.75, 0.77, 0.82)
		draw_arc(c + Vector2(0, -s * 0.3), s * 0.55, PI, TAU, 16, grey, s * 0.22, true)
		draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.3), Vector2(s * 1.6, s * 1.3)), grey)
		draw_circle(c + Vector2(0, s * 0.25), s * 0.18, Color(0.2, 0.2, 0.25))

	## A green check in a dark circle
	func _check(c: Vector2) -> void:
		draw_circle(c, 11.0, Color(0.05, 0.2, 0.1))
		draw_arc(c, 11.0, 0, TAU, 24, Color("#4ade80"), 2.0, true)
		draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(6, -4)]), Color("#4ade80"), 3.0, true)

## Darkens the picture behind: a vertical gradient (or just the bottom, behind text on art)
class Shade extends Control:
	var bottom_only := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if bottom_only:
			UITheme.draw_vertical_gradient(self, Rect2(0, size.y * 0.45, size.x, size.y * 0.55), Color(0, 0, 0, 0), Color(0, 0, 0, 0.75))
			return
		UITheme.draw_vertical_gradient(self, r, Color(0.02, 0.03, 0.07, 0.35), Color(0.02, 0.03, 0.07, 0.8))
