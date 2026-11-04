class_name CharacterDetail
extends Control
## Friend details, gacha character-screen style. Covers the whole screen: the friend's splash art stands on the
## left over turning light rays in the rarity's colour, with the rarity plate, stars, name and class/row/level
## chips under it. On the right a glass panel holds five tabs:
##   Overview - stat tiles (gear bonus in green), Ascension / Bond / Ultimate chips and the profile text
##   Skills   - the passive and the Ultimate as cards
##   Level Up - level, EXP bar, Money level-ups and feeding materials
##   Gear     - one card per slot to equip, with the same stat tiles below
##   Bond     - Bond level, progress and the profile lines it unlocks
## Main adds it with add_child(CharacterDetail.new(uid)); Back or Esc closes it.

signal closed

const TABS := ["overview", "skills", "level", "gear", "bond"]
const STAT_COLORS := {
	"hp": Color("#4ade80"), "attack": Color("#f87171"), "defense": Color("#60a5fa"),
	"evasion": Color("#c084fc"), "accuracy": Color("#fb923c"), "speed": Color("#facc15"),
}
const PINK := Color("#ff6fa8")
const BUY_LEVELS := [1, 5, 10]
const FEED_COUNTS := [1, 10]

var _uid := 0
var _c: CharacterData
var _accent := Color.WHITE
var _showcase: Control
var _panel: PanelContainer
var _pages := {}  # tab key -> page
var _tab_buttons := {}  # tab key -> Button
var _level_chip: Label
var _stat_views: Array[Dictionary] = []  # {"stat", "value": Label, "mod": Label}; tiles appear on two tabs
var _level_big: Label
var _exp_label: Label
var _exp_bar: ProgressBar
var _buy_buttons := {}  # levels -> Button
var _feed := {}  # material key -> {"have": Label, 1: Button, 10: Button}
var _closing := false

func _init(uid: int) -> void:
	_uid = uid
	_c = GameState.get_character(uid)
	_accent = CharArt.RARITY_COLORS[_c.rarity]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_full(Backdrop.new(_accent, CharArt.CLASS_COLORS.get(_c.char_class, Color.GRAY)))
	_full(CollectionTab.Sparkles.new())

	_showcase = _build_showcase()
	_showcase.anchor_right = 0.5  # runs under the panel's edge; EdgeFade blends it into the backdrop
	_showcase.anchor_bottom = 1.0
	add_child(_showcase)

	_panel = _build_panel()
	_panel.anchor_left = 0.42
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8
	_panel.offset_top = 16
	_panel.offset_right = -16
	_panel.offset_bottom = -16
	add_child(_panel)

	_select_tab("overview")
	_refresh()

func _ready() -> void:
	# The art slides in from the left, the panel from the right
	modulate.a = 0.0
	_showcase.position.x -= 60
	_panel.position.x += 60
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.2)
	t.tween_property(_showcase, "position:x", _showcase.position.x + 60, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_panel, "position:x", _panel.position.x - 60, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(func():
		closed.emit()
		queue_free())

func _full(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	return node

func _label(text: String, font_size: int, color: Color = UITheme.TEXT, outline: int = 5) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", outline)
	return label

func _wrapped(text: String, font_size: int, color: Color = UITheme.TEXT) -> Label:
	var label := _label(text, font_size, color, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 120
	return label

## A skewed coloured plate with white text, like the screen banners
func _plate(text: String, color: Color, font_size: int = 16) -> PanelContainer:
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 14
	style.content_margin_right = 16
	style.shadow_color = Color(color, 0.45)
	style.shadow_size = 8
	plate.add_theme_stylebox_override("panel", style)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(_label(text, font_size, Color.WHITE, 4))
	return plate

## A small heading with a short accent bar in front of it
func _section(text: String, color: Color = UITheme.CYAN) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(4, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(_label(text.to_upper(), 14, color, 3))
	return row

## A dark card with a coloured left edge
func _card(color: Color, margin: float = 12) -> PanelContainer:
	var card := PanelContainer.new()
	var style := UITheme.box(Color(UITheme.INSET, 0.78), Color(color, 0.35), 1, 8, margin)
	style.border_width_left = 4
	style.border_color = color
	card.add_theme_stylebox_override("panel", style)
	return card

# ───────── Left: the showcase ─────────

func _build_showcase() -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rays := GachaBanner.Effects.new()
	rays.accent = _accent
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays.resized.connect(func(): rays.center = Vector2(rays.size.x * 0.5, rays.size.y * 0.42))
	root.add_child(rays)

	var rank := GameState.get_ascension(_uid)
	var picture := _c.get_portrait_at(rank)
	var shade_parent: Control = root
	if picture:
		# The picture is drawn through a mask that fades it out to the right, so it melts into the backdrop
		var mask := TextureRect.new()
		mask.texture = _fade_mask()
		mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mask.stretch_mode = TextureRect.STRETCH_SCALE
		mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(mask)
		var art := TextureRect.new()
		art.texture = picture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Live2D-style idle motion, as on the Home screen
		var mat := ShaderMaterial.new()
		mat.shader = CharArt.LIVING_SHADER
		mat.set_shader_parameter("living", 1.0)
		mat.set_shader_parameter("living_seed", float(_uid % 97))
		art.material = mat
		art.resized.connect(func(): mat.set_shader_parameter("rect_size", art.size))
		mask.add_child(art)
		shade_parent = mask  # the shade fades out with the picture, so it leaves no edge either
	else:
		# No picture yet: the framed placeholder card, standing above the name block
		var card := CharArt.new()
		card.set_character(_c)
		card.anchor_left = 0.5
		card.anchor_right = 0.5
		card.anchor_top = 0.42
		card.anchor_bottom = 0.42
		card.offset_left = -120
		card.offset_right = 120
		card.offset_top = -220
		card.offset_bottom = 100
		root.add_child(card)

	# The name block sits along the bottom over a shade
	var shade := MapSelect.Shade.new()
	shade.bottom_only = true
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade_parent.add_child(shade)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	info.anchor_right = 0.84  # stops where the panel begins
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.offset_left = 28
	info.offset_right = 0
	info.offset_bottom = -20
	root.add_child(info)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	info.add_child(top_row)
	top_row.add_child(_plate(Terms.rarity_name(_c.rarity), _accent.darkened(0.25), 20))
	var stars := GachaBanner.StarRow.new(22.0, _accent.lightened(0.2))
	stars.count = GachaBanner.STAR_COUNTS.get(_c.rarity, 3)
	top_row.add_child(stars)
	if rank >= GameState.MAX_ASCENSION:
		top_row.add_child(UITheme.tag(Terms.t("details_awakened"), UITheme.GOLD))

	var name_label := _label(_c.display_name, 44, Color.WHITE, 10)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 120
	info.add_child(name_label)
	if not _c.title.is_empty():
		info.add_child(_label(_c.title, 16, UITheme.TEXT_DIM))

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	info.add_child(chips)
	chips.add_child(TeamTab.ClassBadge.new(_c.char_class))
	chips.add_child(UITheme.tag(Terms.class_label(_c.char_class), CharArt.CLASS_COLORS.get(_c.char_class, Color.GRAY).lightened(0.45)))
	var row_color := TeamTab.VANGUARD_COLOR if _c.is_vanguard() else TeamTab.REARGUARD_COLOR
	chips.add_child(UITheme.tag(Terms.class_row(_c.char_class), row_color))
	var level_tag := UITheme.tag("", UITheme.CYAN)
	_level_chip = level_tag.get_child(0) as Label
	chips.add_child(level_tag)
	var pips := TeamTab.AscensionPips.new(rank, GameState.MAX_ASCENSION, _accent)
	pips.tooltip_text = Terms.t("asc_short", {"rank": rank, "max": GameState.MAX_ASCENSION})
	chips.add_child(pips)
	return root

# ───────── Right: the tabbed panel ─────────

func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UITheme.glow_box(Color(0.04, 0.06, 0.11, 0.9), 14, 16, _accent)
	style.border_color = Color(_accent, 0.5)
	style.set_border_width_all(1)
	style.border_width_top = 3
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for key: String in TABS:
		var button := Button.new()
		button.text = Terms.t("details_tab_" + key)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_select_tab.bind(key))
		tabs.add_child(button)
		_tab_buttons[key] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	var back := Button.new()
	back.text = Terms.t("back")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size.x = 90
	back.pressed.connect(close)
	tabs.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	for key: String in TABS:
		var page: Control = call("_page_" + key)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		_pages[key] = page
	return panel

func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	return page

func _select_tab(key: String) -> void:
	_tab_buttons[key].button_pressed = true
	for k in _pages:
		_pages[k].visible = k == key
	var page: Control = _pages[key]
	page.modulate.a = 0.0
	page.create_tween().tween_property(page, "modulate:a", 1.0, 0.18)

func _page_overview() -> Control:
	var page := _page()
	page.add_child(_section(Terms.t("details_stats")))
	page.add_child(_stat_grid())
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	page.add_child(chips)
	var rank := GameState.get_ascension(_uid)
	chips.add_child(UITheme.tag(Terms.t("details_ascension", {"rank": rank, "max": GameState.MAX_ASCENSION,
		"bonus": roundi(rank * GameState.ASCENSION_BONUS * 100), "stats": _ascension_stats()}), _accent.lightened(0.2)))
	var bond := GameState.get_bond(_uid)
	chips.add_child(UITheme.tag(Terms.t("details_bond", {"bond": bond, "max": GameState.max_bond(),
		"bonus": roundi(bond * GameState.BOND_STAT_BONUS * 100), "stats": _ascension_stats()}), PINK))
	chips.add_child(UITheme.tag(Terms.t("details_ultimate_gauge", {"amount": _c.ultimate_max}), UITheme.GOLD))
	if not _c.description.is_empty():
		page.add_child(_section(Terms.t("details_profile"), UITheme.VIOLET.lightened(0.3)))
		var card := _card(UITheme.VIOLET)
		card.add_child(_wrapped(_c.description, 15))
		page.add_child(card)
	return page

func _page_skills() -> Control:
	var page := _page()
	page.add_child(_skill_card(_c.passive_skill, Terms.term("passive_skill"), UITheme.CYAN, ""))
	page.add_child(_skill_card(_c.active_skill, Terms.term("ultimate"), UITheme.GOLD,
		Terms.t("details_ultimate_gauge", {"amount": _c.ultimate_max})))
	return page

func _skill_card(skill: SkillData, kind: String, color: Color, extra: String) -> Control:
	var card := _card(color, 14)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	head.add_child(_plate(kind.to_upper(), color.darkened(0.45), 14))
	var missing := skill == null or skill.display_name.is_empty()
	var name_label := _label(Terms.t("details_skill_unset") if missing else skill.display_name, 20,
		UITheme.TEXT_DIM if missing else Color.WHITE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = 120
	head.add_child(name_label)
	if not extra.is_empty() and not missing:
		var chip := UITheme.tag(extra, color)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
	if not missing:
		box.add_child(_wrapped(skill.description, 15, UITheme.TEXT))
	return card

func _page_level() -> Control:
	var page := _page()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	page.add_child(head)
	var lv := _label(Terms.term("level"), 18, UITheme.CYAN)
	lv.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(lv)
	_level_big = _label("", 46, Color.WHITE, 8)
	head.add_child(_level_big)
	var max_label := _label("/ %d" % GameState.level_cap(), 18, UITheme.TEXT_DIM)
	max_label.tooltip_text = Terms.t("details_level_cap_tip", {"above": GameState.LEVEL_CAP_ABOVE_ACCOUNT, "max": GameState.MAX_LEVEL})
	max_label.mouse_filter = Control.MOUSE_FILTER_PASS
	max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(max_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_exp_label = _label("", 15, UITheme.TEXT)
	_exp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_exp_label)
	_exp_bar = ProgressBar.new()
	_exp_bar.show_percentage = false
	_exp_bar.custom_minimum_size.y = 14
	page.add_child(_exp_bar)

	var buy := HBoxContainer.new()
	buy.add_theme_constant_override("separation", 8)
	page.add_child(buy)
	for levels: int in BUY_LEVELS:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46
		if levels == 1:
			button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(func():
			GameState.buy_levels(_uid, levels)
			_refresh(true))
		buy.add_child(button)
		_buy_buttons[levels] = button

	page.add_child(_section(Terms.t("details_feed"), Color("#4ade80")))
	for key: String in DB.MATERIALS:
		var card := _card(Color("#4ade80"), 10)
		page.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(_label(Terms.material_name(key), 16, Color.WHITE, 3))
		var have := _label("", 13, UITheme.TEXT_DIM, 0)
		text.add_child(have)
		var ui := {"have": have}
		for count: int in FEED_COUNTS:
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(84, 36)
			button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			button.pressed.connect(func():
				GameState.feed_material(_uid, key, count)
				_refresh(true))
			row.add_child(button)
			ui[count] = button
		_feed[key] = ui
	return page

func _page_gear() -> Control:
	var page := _page()
	page.add_child(_section(Terms.t("details_equipment")))
	for slot_key: String in EquipmentData.SLOT_KEYS:
		var card := _card(UITheme.CYAN, 10)
		page.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var slot_label := _label(Terms.slot_name(slot_key).to_upper(), 14, UITheme.CYAN, 3)
		slot_label.custom_minimum_size.x = 100
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(slot_label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.custom_minimum_size.y = 40
		option.focus_mode = Control.FOCUS_NONE
		_fill_equipment_options(option, slot_key)
		option.item_selected.connect(func(index: int):
			GameState.equip(_uid, slot_key, option.get_item_metadata(index))
			_refresh())
		row.add_child(option)
	page.add_child(_section(Terms.t("details_stats")))
	page.add_child(_stat_grid())
	return page

func _page_bond() -> Control:
	var page := _page()
	var bond := GameState.get_bond(_uid)
	var friendship := GameState.get_friendship(_uid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	page.add_child(head)
	head.add_child(_plate(Terms.t("details_bond_plate", {"bond": bond, "max": GameState.max_bond()}), PINK.darkened(0.25), 20))
	var hearts := TeamTab.AscensionPips.new(bond, GameState.max_bond(), PINK)
	head.add_child(hearts)
	page.add_child(_label(Terms.t("details_bond_bonus", {"bonus": roundi(bond * GameState.BOND_STAT_BONUS * 100),
		"stats": _ascension_stats()}), 15, PINK.lightened(0.3), 3))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 12
	bar.add_theme_stylebox_override("fill", UITheme.glow_box(PINK, 6, -1, PINK))
	if bond >= GameState.max_bond():
		bar.max_value = 1
		bar.value = 1
	else:
		var from: int = GameState.BOND_THRESHOLDS[bond]
		var to: int = GameState.BOND_THRESHOLDS[bond + 1]
		bar.max_value = to - from
		bar.value = friendship - from
		bar.tooltip_text = Terms.t("details_bond_next", {"amount": to - friendship})
	page.add_child(bar)
	page.add_child(_wrapped(Terms.t("details_bond_hint"), 14, UITheme.TEXT_DIM))
	if not _c.bond_lines.is_empty():
		page.add_child(_section(Terms.t("details_bond_story"), PINK))
	for i in _c.bond_lines.size():
		var unlocked := bond >= i + 1
		var card := _card(PINK if unlocked else UITheme.OUTLINE, 12)
		card.add_child(_wrapped(_c.bond_lines[i] if unlocked else Terms.t("details_bond_locked", {"bond": i + 1}), 15,
			UITheme.TEXT if unlocked else UITheme.TEXT_DIM))
		page.add_child(card)
	return page

func _ascension_stats() -> String:
	var names: PackedStringArray = []
	for stat in GameState.ASCENSION_STATS:
		names.append(Terms.stat_short(stat))
	return "/".join(names)

## Six stat tiles: name over the value, gear bonus beside it
func _stat_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for stat: String in CharacterData.STATS:
		var color: Color = STAT_COLORS[stat]
		var tile := _card(color, 10)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		tile.add_child(box)
		box.add_child(_label(Terms.stat_name(stat).to_upper(), 12, color, 0))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		box.add_child(line)
		var value := _label("", 26, Color.WHITE, 4)
		line.add_child(value)
		var mod := _label("", 14, Color("#4ade80"), 0)
		mod.size_flags_vertical = Control.SIZE_SHRINK_END
		line.add_child(mod)
		_stat_views.append({"stat": stat, "value": value, "mod": mod})
	return grid

func _fill_equipment_options(option: OptionButton, slot_key: String) -> void:
	option.clear()
	option.add_item(Terms.t("equip_none"))
	option.set_item_metadata(0, 0)
	var current := int(GameState.get_owned(_uid).equips[slot_key])
	for entry in GameState.list_equipment(slot_key):
		var text := "%s %s" % [entry.data.display_name, _mods_text(entry.data)]
		var wearer := GameState.equipped_by(entry.uid)
		if wearer != 0 and wearer != _uid:
			text = Terms.t("equip_worn_by", {"item": text, "owner": GameState.get_character(wearer).display_name})
		option.add_item(text)
		option.set_item_metadata(option.item_count - 1, entry.uid)
		if entry.uid == current:
			option.selected = option.item_count - 1
	if current == 0:
		option.selected = 0

static func _mods_text(e: EquipmentData) -> String:
	var parts: PackedStringArray = []
	var mods := e.modifiers()
	for stat in mods:
		parts.append("%s %+d" % [Terms.stat_short(stat), mods[stat]])
	return "(%s)" % ", ".join(parts) if not parts.is_empty() else ""

## Updates everything that changes with levels, materials and gear. `flash` pops the level number (a level-up).
func _refresh(flash: bool = false) -> void:
	var o := GameState.get_owned(_uid)
	var level := int(o.level)
	var at_max := level >= GameState.level_cap()
	var capped := at_max and level < GameState.MAX_LEVEL  # held back by the account level, not the true max
	var old_level := _level_big.text
	_level_big.text = str(level)
	_level_chip.text = "%s%d" % [Terms.term("level"), level]
	if at_max:
		_exp_label.text = Terms.t("details_level_capped" if capped else "details_level_max", {"lv": level,
			"account": GameState.get_account_level() + 1})
		_exp_bar.max_value = 1
		_exp_bar.value = 1
	else:
		var next := GameState.exp_to_next(level)
		_exp_label.text = Terms.t("details_exp", {"current": int(o.exp), "next": next})
		_exp_bar.max_value = next
		_exp_bar.value = int(o.exp)
	for levels: int in _buy_buttons:
		var button: Button = _buy_buttons[levels]
		var cost := GameState.level_up_cost(_uid, levels)
		button.text = Terms.t("level_up_capped" if capped else "level_up_max") if at_max \
			else Terms.t("level_up_button", {"count": levels, "cost": cost})
		button.disabled = at_max or GameState.get_money() < cost
		button.visible = not at_max or levels == 1
	for key: String in _feed:
		var ui: Dictionary = _feed[key]
		ui.have.text = Terms.t("details_feed_line", {"amount": GameState.MATERIAL_EXP[key], "have": GameState.get_material(key)})
		var limit := GameState.feed_limit(_uid, key)
		for count: int in FEED_COUNTS:
			var button: Button = ui[count]
			button.text = Terms.t("feed_button", {"count": mini(count, maxi(limit, 1)) if count > 1 else 1})
			button.disabled = limit < 1 or (count > 1 and limit < 2)
	var base := GameState.get_unit_stats(_uid, false)
	var final := GameState.get_unit_stats(_uid)
	for view in _stat_views:
		var diff: int = final[view.stat] - base[view.stat]
		view.value.text = str(final[view.stat])
		view.mod.text = "%+d" % diff if diff != 0 else ""
		view.mod.add_theme_color_override("font_color", Color("#4ade80") if diff > 0 else Color("#f87171"))
	if flash and old_level != _level_big.text:
		_level_big.pivot_offset = _level_big.size / 2.0
		_level_big.scale = Vector2(1.35, 1.35)
		_level_big.modulate = Color(1.6, 1.6, 1.0)
		var t := _level_big.create_tween().set_parallel()
		t.tween_property(_level_big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(_level_big, "modulate", Color.WHITE, 0.4)

## Opaque on the left, fading to clear toward the right edge (the showcase art's mask)
static func _fade_mask() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 0.95])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	return texture

## Dark backdrop washed with the rarity colour from the top and the class colour from the bottom, with faint
## diagonal light stripes
class Backdrop extends Control:
	var _accent := Color.WHITE
	var _class_color := Color.WHITE

	func _init(accent: Color, class_color: Color) -> void:
		_accent = accent
		_class_color = class_color
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.02, 0.03, 0.06, 0.96))
		UITheme.draw_vertical_gradient(self, r, Color(_accent, 0.16), Color(_class_color, 0.22))
		var step := 90.0
		var x := -size.y
		while x < size.x:
			draw_colored_polygon(PackedVector2Array([Vector2(x, size.y), Vector2(x + 30, size.y),
				Vector2(x + 30 + size.y * 0.6, 0), Vector2(x + size.y * 0.6, 0)]), Color(1, 1, 1, 0.018))
			x += step
		UITheme.draw_glow(self, Vector2(size.x * 0.21, size.y * 0.45), size.y * 0.55, Color(_accent, 0.18))
