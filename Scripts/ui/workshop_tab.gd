class_name WorkshopTab
extends VBoxContainer
## The Workshop: gear upgrades, scrapping and crafting (rules and costs in GameState's Gear section).
## A "WORKSHOP" banner with the Parts count, then two pages picked by toggles, both filtered by slot:
##   Gear Bag - every owned piece as a card in its rarity's colour: stats at its upgrade level, who wears it, and
##              Upgrade / Scrap buttons. "Scrap spare R +0" clears out the common clutter in one go.
##   Craft    - every piece in the game: unlocked ones (a cleared map drops them) can be crafted for Parts + Money,
##              which plays the slot-reel minigame (Scripts/ui/craft_reel.gd) for a free +0..+2; locked ones say
##              which map unlocks them.
## The cards rebuild when gear, Parts or Money change (only while the tab is visible; otherwise on the next show).

const COLUMNS := 3

var _page := "bag"  # "bag" or "craft"
var _filter := ""  # "" = every slot, else an EquipmentData.SLOT_KEYS entry
var _parts_label: Label
var _grid: GridContainer
var _scrap_spare: Button
var _page_buttons := {}
var _dirty := true

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_build_header())
	var intro := Label.new()
	intro.text = Terms.t("workshop_intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	intro.add_theme_font_size_override("font_size", 14)
	add_child(intro)
	add_child(_build_toolbar())

	var stage := Control.new()  # the cards with sparkles drifting behind them
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stage)
	var sparkles := CollectionTab.Sparkles.new()
	sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(sparkles)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	GameState.gear_changed.connect(_mark_dirty)
	GameState.roster_changed.connect(_mark_dirty)
	GameState.money_changed.connect(func(_value): _mark_dirty())
	visibility_changed.connect(_on_visibility_changed)
	_rebuild()

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _dirty:
		_rebuild()

func _mark_dirty() -> void:
	_dirty = true
	if is_visible_in_tree():
		_rebuild.call_deferred()

# ───────── Header and toolbar ─────────

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#d97706").darkened(0.15)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color("#f59e0b", 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_text(Terms.t("workshop_banner"), 24, Color.WHITE))
	header.add_child(plate)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.INSET, 0.85), Color("#f59e0b", 0.6), 1, 14, 6))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_parts_label = _text("", 18, Color("#fcd34d"))
	chip.add_child(_parts_label)
	header.add_child(chip)
	return header

func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var pages := ButtonGroup.new()
	for key in ["bag", "craft"]:
		var b := _toggle(Terms.t("workshop_tab_" + key), pages, key == _page)
		b.custom_minimum_size.x = 120
		b.pressed.connect(func():
			_page = key
			_rebuild())
		bar.add_child(b)
		_page_buttons[key] = b
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	bar.add_child(gap)
	var filters := ButtonGroup.new()
	for key in [""] + EquipmentData.SLOT_KEYS:
		var b := _toggle(Terms.t("workshop_filter_all") if key == "" else Terms.slot_name(key), filters, key == _filter)
		b.pressed.connect(func():
			_filter = key
			_rebuild())
		bar.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_scrap_spare = Button.new()
	_scrap_spare.focus_mode = Control.FOCUS_NONE
	_scrap_spare.add_theme_font_size_override("font_size", 14)
	_scrap_spare.pressed.connect(_confirm_scrap_spare)
	bar.add_child(_scrap_spare)
	return bar

func _toggle(text: String, group: ButtonGroup, pressed: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	return b

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label

# ───────── Cards ─────────

func _rebuild() -> void:
	if not is_instance_valid(_grid):
		return
	_dirty = false
	_parts_label.text = Terms.t("workshop_parts", {"amount": Terms.number(GameState.get_parts())})
	var spare := _spare_r()
	var spare_parts := 0
	for uid in spare:
		spare_parts += GameState.scrap_value(uid)
	_scrap_spare.text = Terms.t("workshop_scrap_spare", {"p": spare_parts})
	_scrap_spare.visible = _page == "bag"
	_scrap_spare.disabled = spare.is_empty()
	for child in _grid.get_children():
		child.queue_free()
	if _page == "bag":
		var items := GameState.list_equipment(_filter)
		if items.is_empty():
			var empty := _text(Terms.t("workshop_empty"), 16, UITheme.TEXT_DIM)
			_grid.add_child(empty)
		for entry in items:
			_grid.add_child(_bag_card(entry))
	else:
		var all: Array = DB.equipment.values().filter(func(e): return _filter.is_empty() or e.slot_key() == _filter)
		all.sort_custom(func(a, b):
			var ua := GameState.can_craft_unlocked(a)
			var ub := GameState.can_craft_unlocked(b)
			if ua != ub:
				return ua
			if a.rarity != b.rarity:
				return a.rarity < b.rarity
			if a.slot != b.slot:
				return a.slot < b.slot
			return a.display_name < b.display_name)
		for e: EquipmentData in all:
			_grid.add_child(_craft_card(e))

func _card(color: Color) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UITheme.glow_box(Color(0.05, 0.07, 0.12, 0.93), 10, 12, color)
	style.shadow_size = 4
	style.shadow_color = Color(color, 0.25)
	style.border_color = Color(color, 0.8)
	style.set_border_width_all(1)
	style.border_width_left = 4
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	return [panel, box]

## Rarity chip, name and slot along the top of a card
func _title_row(e: EquipmentData, plus: int, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.tag(Terms.rarity_name(e.rarity), color))
	var name_label := _text(e.display_name + (" +%d" % plus if plus > 0 else ""), 17, Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(_text(Terms.slot_name(e.slot_key()), 13, UITheme.TEXT_DIM))
	return row

func _bag_card(entry: Dictionary) -> Control:
	var e: EquipmentData = entry.data
	var uid: int = entry.uid
	var color: Color = CharArt.RARITY_COLORS.get(e.rarity, UITheme.CYAN)
	var parts := _card(color)
	var box: VBoxContainer = parts[1]
	box.add_child(_title_row(e, entry.plus, color))
	box.add_child(_text(CharacterDetail.mods_text(e.modifiers(entry.plus)), 15, Color("#86efac")))
	var wearer := GameState.equipped_by(uid)
	var worn := GameState.get_character(wearer).display_name if wearer != 0 else ""
	box.add_child(_text(Terms.t("workshop_worn", {"name": worn}) if wearer != 0 else Terms.t("workshop_spare"), 13,
		UITheme.CYAN if wearer != 0 else UITheme.TEXT_DIM))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	var upgrade := _small_button()
	var cost := GameState.upgrade_cost(uid)
	if cost.is_empty():
		upgrade.text = Terms.t("workshop_maxed", {"max": GameState.GEAR_MAX_PLUS})
		upgrade.disabled = true
	else:
		upgrade.text = Terms.t("workshop_upgrade", {"next": entry.plus + 1, "p": cost.parts, "m": Terms.number(cost.money)})
		upgrade.disabled = not GameState.can_upgrade(uid)
		upgrade.theme_type_variation = &"PrimaryButton"
	upgrade.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade.pressed.connect(func(): GameState.upgrade_equipment(uid))
	buttons.add_child(upgrade)
	var scrap := _small_button()
	scrap.text = Terms.t("workshop_scrap", {"p": GameState.scrap_value(uid)})
	scrap.custom_minimum_size.x = 96
	if wearer != 0:
		scrap.disabled = true
		scrap.tooltip_text = Terms.t("workshop_scrap_worn", {"name": worn})
	scrap.pressed.connect(_confirm_scrap.bind(uid))
	buttons.add_child(scrap)
	return parts[0]

func _craft_card(e: EquipmentData) -> Control:
	var unlocked := GameState.can_craft_unlocked(e)
	var color: Color = CharArt.RARITY_COLORS.get(e.rarity, UITheme.CYAN)
	var parts := _card(color if unlocked else UITheme.OUTLINE)
	var panel: Control = parts[0]
	var box: VBoxContainer = parts[1]
	box.add_child(_title_row(e, 0, color))
	box.add_child(_text(CharacterDetail.mods_text(e.modifiers()), 15, Color("#86efac")))
	var about := _text(e.description, 13, UITheme.TEXT_DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = 120
	box.add_child(about)
	box.add_child(_text(Terms.t("workshop_owned", {"count": GameState.count_equipment(e.id)}), 13, UITheme.TEXT))
	var button := _small_button()
	if unlocked:
		var cost := GameState.craft_cost(e)
		button.text = Terms.t("workshop_craft", {"p": cost.parts, "m": Terms.number(cost.money)})
		button.disabled = not GameState.can_craft(e)
		button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(_craft.bind(e))
	else:
		var stage := GameState.first_map_dropping(e)
		button.text = Terms.t("workshop_locked", {"map": "%s %s" % [stage.code(), stage.display_name]}) if stage \
			else Terms.t("workshop_locked_none")
		button.disabled = true
		panel.modulate = Color(1, 1, 1, 0.6)
	box.add_child(button)
	return panel

func _small_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 44
	b.add_theme_font_size_override("font_size", 13)
	return b

# ───────── Actions ─────────

func _craft(e: EquipmentData) -> void:
	var entry := GameState.craft_equipment(e)
	if entry.is_empty():
		return
	var reel := CraftReel.new(e)
	reel.finished.connect(func(bonus: int): GameState.apply_craft_bonus(int(entry.uid), bonus))
	add_child(reel)

## R pieces at +0 nobody is wearing
func _spare_r() -> Array[int]:
	var out: Array[int] = []
	for entry in GameState.list_equipment():
		if entry.data.rarity <= CharacterData.Rarity.R and entry.plus == 0 and GameState.equipped_by(entry.uid) == 0:
			out.append(int(entry.uid))
	return out

func _confirm_scrap(uid: int) -> void:
	var e := GameState.get_equipment(uid)
	if e == null:
		return
	# Plain R +0 pieces go straight away; anything rarer or upgraded asks first
	if e.rarity <= CharacterData.Rarity.R and GameState.get_plus(uid) == 0:
		GameState.scrap_equipment(uid)
		return
	_confirm(Terms.t("workshop_scrap_title"), Terms.t("workshop_scrap_text", {
		"item": CharacterDetail.gear_name(e, GameState.get_plus(uid)), "p": GameState.scrap_value(uid)}),
		func(): GameState.scrap_equipment(uid))

func _confirm_scrap_spare() -> void:
	var spare := _spare_r()
	if spare.is_empty():
		return
	var total := 0
	for uid in spare:
		total += GameState.scrap_value(uid)
	_confirm(Terms.t("workshop_scrap_spare_title"), Terms.t("workshop_scrap_spare_text", {"count": spare.size(), "p": total}),
		_scrap_all.bind(spare))

func _scrap_all(uids: Array[int]) -> void:
	for uid in uids:
		GameState.scrap_equipment(uid)

func _confirm(title: String, text: String, action: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(440, 0)
	dialog.ok_button_text = Terms.t("workshop_scrap_ok")
	dialog.confirmed.connect(action)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()
