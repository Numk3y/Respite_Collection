class_name ChallengeScreen
extends Control
## The Weekly Challenge screen (Challenge autoload): this week's rules on top, then one card per tier with its boss
## map, recommended level, reward and a Fight button. A tier is locked until its boss map is cleared in the story;
## once won this week its card says so and the button still lets you play it for fun. Main listens to
## fight_pressed / back_pressed.

signal fight_pressed(tier: int)
signal back_pressed

const ACCENT := Color("#f472b6")
const TIER_COLORS := [Color("#4ade80"), Color("#f59e0b"), Color("#ef4444")]

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var background := TextureRect.new()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.32, 0.3, 0.4)
	var last := Challenge.tier_boss(Challenge.TIERS.size() - 1)
	if last and last.background:
		background.texture = last.background
	_full(background)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	content.add_child(_header())
	content.add_child(_rules_panel())
	var problem := Challenge.team_problem()
	if problem != "":
		var note := _label(problem, 15, Color("#fca5a5"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(note)
	var tiers := HFlowContainer.new()
	tiers.add_theme_constant_override("h_separation", 12)
	tiers.add_theme_constant_override("v_separation", 12)
	content.add_child(tiers)
	for i in Challenge.TIERS.size():
		tiers.add_child(_tier_card(i, problem == ""))

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

func _header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT.darkened(0.15)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(ACCENT, 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_label(Terms.t("challenge_title").to_upper(), 24, Color.WHITE))
	header.add_child(plate)
	var hint := _label(Terms.t("challenge_resets", {"time": Daily.format_time(Challenge.seconds_left())}), 15, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(hint)
	var back := Button.new()
	back.text = Terms.t("back")
	back.custom_minimum_size = Vector2(110, 38)
	back.pressed.connect(back_pressed.emit)
	header.add_child(back)
	return header

func _rules_panel() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.glow_box(Color(0.04, 0.06, 0.11, 0.9), 12, 14, ACCENT))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_label(Terms.t("challenge_rules"), 17, ACCENT.lightened(0.3)))
	var rules := [["challenge_kind_team", Challenge.team_rule(), UITheme.CYAN]]
	for id in Challenge.battle_rules():
		rules.append(["challenge_kind_battle", id, Color("#fb923c")])
	for r in rules:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var tag := UITheme.tag(Terms.t(r[0]), r[2])
		tag.custom_minimum_size.x = 84
		line.add_child(tag)
		var text := _label(Challenge.rule_text(r[1]), 15, UITheme.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		box.add_child(line)
	var tip := _label(Terms.t("challenge_tip"), 13, UITheme.TEXT_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	return panel

func _tier_card(tier: int, team_ok: bool) -> Control:
	var color: Color = TIER_COLORS[tier]
	var boss := Challenge.tier_boss(tier)
	var unlocked := Challenge.is_unlocked(tier)
	var cleared := Challenge.is_cleared(tier)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UITheme.glow_box(Color(0.04, 0.06, 0.11, 0.92), 12, 12, color))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var art_holder := Control.new()
	art_holder.custom_minimum_size = Vector2(0, 110)
	art_holder.clip_contents = true
	box.add_child(art_holder)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if boss:
		art.texture = boss.background if boss.background else UITheme.chapter_background(boss.chapter)
	if not unlocked:
		art.modulate = Color(0.35, 0.35, 0.4)
	art_holder.add_child(art)
	var tier_label := _label(Challenge.tier_name(tier).to_upper(), 30, color)
	tier_label.add_theme_constant_override("outline_size", 10)
	tier_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tier_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tier_label.offset_left = 10
	tier_label.offset_bottom = -4
	art_holder.add_child(tier_label)

	if boss:
		box.add_child(_label("%s  %s" % [boss.code(), boss.display_name], 18, Color.WHITE))
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 6)
		chips.add_child(UITheme.tag(Terms.t("map_recommended", {"lv": boss.recommended_level}), UITheme.CYAN))
		chips.add_child(UITheme.tag(Terms.t("map_battles", {"count": boss.wave_count()}), Color("#a78bfa")))
		if cleared:
			chips.add_child(UITheme.tag(Terms.t("challenge_cleared"), Color("#4ade80")))
		box.add_child(chips)
	box.add_child(_label(Terms.t("map_rewards"), 13, UITheme.TEXT_DIM))
	var reward := _label(Daily.reward_text(Challenge.tier_reward(tier)), 15, UITheme.GOLD if not cleared else UITheme.TEXT_DIM)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reward)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(push)

	var fight := Button.new()
	fight.custom_minimum_size = Vector2(0, 50)
	fight.add_theme_font_size_override("font_size", 20)
	if not unlocked:
		fight.text = Terms.t("challenge_locked_button")
		fight.disabled = true
		var why := _label(Terms.t("challenge_locked", {"code": boss.code() if boss else "?"}), 13, Color("#fca5a5"))
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(why)
	else:
		fight.text = Terms.t("challenge_again" if cleared else "challenge_fight").to_upper()
		fight.disabled = not team_ok
		if not cleared:
			fight.theme_type_variation = &"PrimaryButton"
		fight.pressed.connect(fight_pressed.emit.bind(tier))
	box.add_child(fight)
	return panel
