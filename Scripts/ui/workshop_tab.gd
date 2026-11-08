class_name WorkshopTab
extends VBoxContainer
## The Workshop: gear upgrades, scrapping and crafting (rules and costs in GameState's Gear section), laid out like
## a gacha inventory. A "WORKSHOP" banner with the Parts counter, a toolbar (Gear Bag / Craft pages, slot filters,
## "Scrap spare R +0"), then:
##   left  - every piece as a square GearIcon (Scripts/ui/gear_icon.gd) in its rarity colour: +level, the wearer's
##           face, a green arrow when it can be upgraded now; on the Craft page the owned count and a padlock on
##           pieces not unlocked yet. Click one to select it.
##   right - the selected piece in detail: big icon, name, rarity, upgrade pips, who wears it, its stats now and
##           after the next upgrade, the cost against what you have, and the big action buttons:
##           Gear Bag: Upgrade / Scrap.  Craft: Craft (plays the slot-reel minigame, Scripts/ui/craft_reel.gd, for a
##           free +0..+2), or which map unlocks it.
## Everything rebuilds when gear, Parts or Money change (only while the tab is visible; otherwise on the next show),
## keeping the selection.

const DETAIL_WIDTH := 350.0
const SHORT := Color("#f87171")  # a cost you can't cover

var _page := "bag"  # "bag" or "craft"
var _filter := ""  # "" = every slot, else an EquipmentData.SLOT_KEYS entry
var _parts_chip: CurrencyChip
var _flow: HFlowContainer
var _count_label: Label
var _scrap_spare: Button
var _detail: VBoxContainer
var _icons := {}  # bag: equip uid -> GearIcon; craft: equipment id -> GearIcon
var _selected_uid := -1  # Gear Bag selection
var _selected_id: StringName = &""  # Craft selection
var _pop_selected := false  # an upgrade just landed: bounce the selected piece after the rebuild
var _dirty := true

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(_build_header())
	add_child(_build_toolbar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	add_child(body)

	var stage := Control.new()  # the icons with sparkles drifting behind them
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	var sparkles := CollectionTab.Sparkles.new()
	sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(sparkles)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage.add_child(scroll)
	var pad := MarginContainer.new()  # room for the selected tile's glow and the hover lift
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	scroll.add_child(pad)
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 12)
	_flow.add_theme_constant_override("v_separation", 12)
	pad.add_child(_flow)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = DETAIL_WIDTH
	var style := UITheme.panel_box(16)
	style.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	panel.add_theme_stylebox_override("panel", style)
	body.add_child(panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	panel.add_child(_detail)

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
	plate.tooltip_text = Terms.t("workshop_intro")
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	plate.add_child(_text(Terms.t("workshop_banner"), 24, Color.WHITE))
	header.add_child(plate)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_parts_chip = CurrencyChip.new("parts", Terms.term("parts"))
	_parts_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_parts_chip)
	return header

func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	# The two pages as one segmented control
	var pages := ButtonGroup.new()
	var segment := HBoxContainer.new()
	segment.add_theme_constant_override("separation", 0)
	bar.add_child(segment)
	var keys := ["bag", "craft"]
	for i in keys.size():
		var key: String = keys[i]
		var b := _toggle(Terms.t("workshop_tab_" + key), pages, key == _page, 16)
		b.custom_minimum_size = Vector2(130, 38)
		_segment_style(b, i == 0, i == keys.size() - 1)
		b.pressed.connect(func():
			_page = key
			_rebuild())
		segment.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size.x = 16
	bar.add_child(gap)
	var filters := ButtonGroup.new()
	for key in [""] + EquipmentData.SLOT_KEYS:
		var b := _toggle(Terms.t("workshop_filter_all") if key == "" else Terms.slot_name(key), filters, key == _filter, 14)
		b.custom_minimum_size.y = 34
		_chip_style(b)
		b.pressed.connect(func():
			_filter = key
			_rebuild())
		bar.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_count_label = _text("", 14, UITheme.TEXT_DIM)
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_count_label)
	_scrap_spare = Button.new()
	_scrap_spare.focus_mode = Control.FOCUS_NONE
	_scrap_spare.add_theme_font_size_override("font_size", 14)
	_scrap_spare.pressed.connect(_confirm_scrap_spare)
	bar.add_child(_scrap_spare)
	return bar

func _toggle(text: String, group: ButtonGroup, pressed: bool, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	return b

## Page buttons joined into one pill: dark when off, filled cyan when on
func _segment_style(b: Button, first: bool, last: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var on := state.contains("pressed")
		var s := UITheme.box(Color(UITheme.CYAN, 0.9) if on else Color(UITheme.INSET, 0.9 if state == "normal" else 1.0),
			Color(UITheme.CYAN, 0.8), 1, 0)
		if state == "hover" and not on:
			s.bg_color = UITheme.CARD_HOVER
		var radius := 19
		if first:
			s.corner_radius_top_left = radius
			s.corner_radius_bottom_left = radius
		if last:
			s.corner_radius_top_right = radius
			s.corner_radius_bottom_right = radius
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_pressed_color", Color("#06121f"))
	b.add_theme_color_override("font_hover_pressed_color", Color("#06121f"))

## Slot filters as small rounded chips
func _chip_style(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var on := state.contains("pressed")
		var s := UITheme.box(Color(UITheme.CYAN, 0.18) if on else Color(UITheme.INSET, 0.6), Color(UITheme.CYAN, 0.9 if on else 0.25), 1, 17)
		s.content_margin_left = 14
		s.content_margin_right = 14
		if state == "hover" and not on:
			s.bg_color = UITheme.CARD_HOVER
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_pressed_color", UITheme.CYAN_BRIGHT)
	b.add_theme_color_override("font_hover_pressed_color", UITheme.CYAN_BRIGHT)

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label

# ───────── The grid ─────────

func _rebuild() -> void:
	if not is_instance_valid(_flow):
		return
	_dirty = false
	_parts_chip.set_amount(GameState.get_parts())
	var spare := _spare_r()
	var spare_parts := 0
	for uid in spare:
		spare_parts += GameState.scrap_value(uid)
	_scrap_spare.text = Terms.t("workshop_scrap_spare", {"p": spare_parts})
	_scrap_spare.visible = _page == "bag"
	_scrap_spare.disabled = spare.is_empty()
	for child in _flow.get_children():
		child.queue_free()
	_icons.clear()
	if _page == "bag":
		var items := GameState.list_equipment(_filter)
		_count_label.text = Terms.t("workshop_count", {"count": items.size()})
		if items.is_empty():
			_flow.add_child(_text(Terms.t("workshop_empty"), 16, UITheme.TEXT_DIM))
		elif not items.any(func(entry): return int(entry.uid) == _selected_uid):
			_selected_uid = int(items[0].uid)
		for entry in items:
			var icon := GearIcon.new()
			icon.set_gear(entry.data, entry.plus)
			var wearer := GameState.equipped_by(entry.uid)
			icon.wearer = GameState.get_character(wearer) if wearer != 0 else null
			icon.can_upgrade = GameState.can_upgrade(entry.uid)
			icon.selected = int(entry.uid) == _selected_uid
			icon.pressed.connect(_select.bind(int(entry.uid)))
			_flow.add_child(icon)
			_icons[int(entry.uid)] = icon
		_show_bag_detail()
	else:
		var all: Array = DB.equipment.values().filter(func(e): return _filter.is_empty() or e.slot_key() == _filter)
		all.sort_custom(func(a, b):
			var ua := GameState.can_craft_unlocked(a)
			var ub := GameState.can_craft_unlocked(b)
			if ua != ub:
				return ua
			if a.rarity != b.rarity:
				return a.rarity > b.rarity
			if a.slot != b.slot:
				return a.slot < b.slot
			return a.display_name < b.display_name)
		var unlocked := all.filter(func(e): return GameState.can_craft_unlocked(e)).size()
		_count_label.text = Terms.t("workshop_count_craft", {"count": unlocked, "total": all.size()})
		if not all.any(func(e): return e.id == _selected_id) and not all.is_empty():
			_selected_id = all[0].id
		for e: EquipmentData in all:
			var icon := GearIcon.new()
			icon.set_gear(e)
			icon.locked = not GameState.can_craft_unlocked(e)
			icon.count = GameState.count_equipment(e.id)
			icon.selected = e.id == _selected_id
			icon.pressed.connect(_select.bind(e.id))
			_flow.add_child(icon)
			_icons[e.id] = icon
		_show_craft_detail()
	if _pop_selected:
		_pop_selected = false
		var key: Variant = _selected_uid if _page == "bag" else _selected_id
		if _icons.has(key):
			_icons[key].pop()

## Click a piece: it lights up and fills the detail panel
func _select(key: Variant) -> void:
	if _page == "bag":
		_selected_uid = key
	else:
		_selected_id = key
	for k in _icons:
		_icons[k].selected = k == key
	if _page == "bag":
		_show_bag_detail()
	else:
		_show_craft_detail()

# ───────── The detail panel ─────────

func _clear_detail() -> void:
	for child in _detail.get_children():
		child.queue_free()

func _show_bag_detail() -> void:
	_clear_detail()
	var e := GameState.get_equipment(_selected_uid) if _icons.has(_selected_uid) else null
	if e == null:
		_detail_hint()
		return
	var uid := _selected_uid
	var plus := GameState.get_plus(uid)
	var wearer := GameState.equipped_by(uid)
	var worn := GameState.get_character(wearer).display_name if wearer != 0 else ""
	_detail_top(e, plus, Terms.t("workshop_worn", {"name": worn}) if wearer != 0 else Terms.t("workshop_spare"),
		UITheme.CYAN if wearer != 0 else UITheme.TEXT_DIM, GameState.get_character(wearer) if wearer != 0 else null)
	var cost := GameState.upgrade_cost(uid)
	_stat_table(e.modifiers(plus), e.modifiers(plus + 1) if not cost.is_empty() else {})
	if not e.description.is_empty():
		_detail.add_child(_about(e.description))
	_grow()
	if cost.is_empty():
		var done := _text(Terms.t("workshop_max_reached"), 18, UITheme.GOLD)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detail.add_child(done)
	else:
		_detail.add_child(_cost_row(cost))
	var upgrade := _action(Terms.t("workshop_upgrade_btn", {"next": plus + 1}) if not cost.is_empty() else Terms.t("workshop_maxed", {"max": GameState.GEAR_MAX_PLUS}), true)
	upgrade.disabled = cost.is_empty() or not GameState.can_upgrade(uid)
	upgrade.pressed.connect(_upgrade.bind(uid))
	_detail.add_child(upgrade)
	var scrap := _action(Terms.t("workshop_scrap_btn", {"p": GameState.scrap_value(uid)}), false)
	if wearer != 0:
		scrap.disabled = true
		scrap.tooltip_text = Terms.t("workshop_scrap_worn", {"name": worn})
	scrap.pressed.connect(_confirm_scrap.bind(uid))
	_detail.add_child(scrap)

func _show_craft_detail() -> void:
	_clear_detail()
	var e: EquipmentData = DB.equipment.get(_selected_id)
	if e == null:
		_detail_hint()
		return
	var unlocked := GameState.can_craft_unlocked(e)
	_detail_top(e, 0, Terms.t("workshop_owned", {"count": GameState.count_equipment(e.id)}), UITheme.TEXT, null, not unlocked)
	_stat_table(e.modifiers(), {})
	if not e.description.is_empty():
		_detail.add_child(_about(e.description))
	_grow()
	if unlocked:
		var cost := GameState.craft_cost(e)
		_detail.add_child(_cost_row(cost))
		var craft := _action(Terms.t("workshop_craft_btn"), true)
		craft.disabled = not GameState.can_craft(e)
		craft.pressed.connect(_craft.bind(e))
		_detail.add_child(craft)
		var note := _text(Terms.t("workshop_craft_note"), 13, UITheme.TEXT_DIM)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(note)
	else:
		var stage := GameState.first_map_dropping(e)
		var lock := _action(Terms.t("workshop_locked", {"map": "%s %s" % [stage.code(), stage.display_name]}) if stage
			else Terms.t("workshop_locked_none"), false)
		lock.disabled = true
		_detail.add_child(lock)

func _detail_hint() -> void:
	var hint := _text(Terms.t("workshop_intro"), 14, UITheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(hint)

## Big icon beside the name, rarity and slot, the upgrade pips and the status line (who wears it / owned count)
func _detail_top(e: EquipmentData, plus: int, status: String, status_color: Color, wearer: CharacterData, locked := false) -> void:
	var color: Color = CharArt.RARITY_COLORS.get(e.rarity, UITheme.CYAN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_detail.add_child(row)
	var icon := GearIcon.new()
	icon.custom_minimum_size = Vector2(118, 132)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_gear(e, plus)
	icon.wearer = wearer
	icon.locked = locked
	row.add_child(icon)
	if _pop_selected:
		icon.pop.call_deferred()
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := _text(e.display_name, 22, Color.WHITE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(UITheme.tag(Terms.rarity_name(e.rarity), color))
	tags.add_child(UITheme.tag(Terms.slot_name(e.slot_key()), UITheme.TEXT_DIM))
	info.add_child(tags)
	var pips := Pips.new()
	pips.level = plus
	pips.custom_minimum_size = Vector2(0, 22)
	info.add_child(pips)
	info.add_child(_text(status, 14, status_color))

## Stat rows: name, value now and, when an upgrade is possible, "→ next" in green
func _stat_table(now: Dictionary, next: Dictionary) -> void:
	var heading := _text(Terms.t("workshop_stats"), 13, UITheme.CYAN)
	_detail.add_child(heading)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.INSET, 0.7), Color(UITheme.CYAN, 0.15), 1, 8, 10))
	_detail.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for stat in now:
		var name_label := _text(Terms.stat_short(stat), 16, UITheme.TEXT_DIM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var value: int = now[stat]
		grid.add_child(_text("%+d" % value, 17, Color("#86efac") if value > 0 else SHORT))
		var after := ""
		if next.has(stat) and next[stat] != value:
			after = "→ %+d" % next[stat]
		grid.add_child(_text(after, 17, Color("#4ade80")))

func _about(text: String) -> Label:
	var about := _text(text, 13, UITheme.TEXT_DIM)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return about

func _grow() -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)

## The cost as currency chips showing "need / have", red when there isn't enough
func _cost_row(cost: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for kind in ["parts", "money"]:
		var need: int = cost.get(kind, 0)
		var have := GameState.get_parts() if kind == "parts" else GameState.get_money()
		var chip := CurrencyChip.new(kind, Terms.term(kind))
		chip.value_label.text = "%s / %s" % [Terms.number(need), Terms.number(have)]
		chip.value_label.add_theme_font_size_override("font_size", 15)
		if have < need:
			chip.value_label.add_theme_color_override("font_color", SHORT)
		row.add_child(chip)
	return row

func _action(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 52 if primary else 40
	b.add_theme_font_size_override("font_size", 19 if primary else 15)
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	return b

# ───────── Actions ─────────

func _upgrade(uid: int) -> void:
	_pop_selected = true
	if GameState.upgrade_equipment(uid):
		Sound.play("crystal", -2.0, 1.3)
	else:
		_pop_selected = false

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

## Upgrade level as GEAR_MAX_PLUS diamonds, filled up to `level` (gold when maxed)
class Pips extends Control:
	var level := 0

	func _draw() -> void:
		var maxed := level >= GameState.GEAR_MAX_PLUS
		for i in GameState.GEAR_MAX_PLUS:
			var c := Vector2(9.0 + i * 20.0, size.y * 0.5)
			var d := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
			if i < level:
				draw_colored_polygon(d, UITheme.GOLD if maxed else UITheme.CYAN_BRIGHT)
			else:
				draw_colored_polygon(d, Color(1, 1, 1, 0.08))
			d.append(d[0])
			draw_polyline(d, Color(1, 1, 1, 0.45), 1.2, true)
		var text := "+%d / +%d" % [level, GameState.GEAR_MAX_PLUS]
		draw_string(get_theme_default_font(), Vector2(9.0 + GameState.GEAR_MAX_PLUS * 20.0, size.y * 0.5 + 6.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UITheme.GOLD if maxed else UITheme.TEXT_DIM)
