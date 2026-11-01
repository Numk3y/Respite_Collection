extends Control
## Screen flow: starter pick -> Home (tabs: Home / Team / Recruit / Commissions / Roster / Event) -> Battle -> Map selection -> Battle screen.
## All text comes from Terms (Scripts/autoload/terms.gd).

const ROWS := ["vanguard", "rearguard"]

var _is_web := OS.has_feature("web")
var _screen: Control
var _screen_bg: TextureRect  # an optional full-screen picture behind the current screen (e.g. battles)
var _roster_dirty := false
var _backup_message: Label
var _restore_target: TextEdit
var _file_picked_callback = null  # JavaScriptObject; must stay referenced or the browser drops it

# Header
var _money_chip: CurrencyChip
var _cards_chip: CurrencyChip
var _material_chips := {}  # material key -> CurrencyChip
var _tabs: TabContainer
# Home
var _home_hint: Label
var _mirror_room: MirrorRoom
# Team
var _team_rows: Dictionary = {}  # "vanguard" / "rearguard" -> HBoxContainer
# Roster
var _collection_grid: HFlowContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_window().title = Terms.term("game_title")
	# One theme for every screen and popup (Scripts/ui/ui_theme.gd)
	get_tree().root.theme = UITheme.build()
	RenderingServer.set_default_clear_color(UITheme.BG)
	add_child(CyberBackdrop.new())  # stays behind every screen
	add_child(AmbientParticles.new())  # drifting bokeh over the backdrop, also behind every screen
	GameState.money_changed.connect(func(_value): _refresh_status())
	GameState.materials_changed.connect(_refresh_status)
	GameState.credit_cards_changed.connect(func(_value): _refresh_status())
	GameState.roster_changed.connect(_queue_roster_refresh)
	if GameState.data.starter_chosen:
		_show_main()
	else:
		_show_starter_select()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = 5  # nearly zero CPU while the window or tab isn't in focus
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = 0
		NOTIFICATION_WM_CLOSE_REQUEST:
			GameState.save_game()  # desktop builds: save on the close button (web saves after every change)

# ───────── Shared helpers ─────────

func _new_screen() -> VBoxContainer:
	if _screen:
		_screen.queue_free()
	if _screen_bg:
		_screen_bg.queue_free()
		_screen_bg = null
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	_screen = margin
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	return root

## Puts a picture behind the current screen, above the cyber backdrop and its particles, dimmed so the UI
## on top stays readable. _new_screen removes it again.
func _set_screen_background(texture: Texture2D, dim: float = 0.35) -> void:
	if texture == null:
		return
	_screen_bg = TextureRect.new()
	_screen_bg.texture = texture
	_screen_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_screen_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_bg.modulate = Color(1.0 - dim, 1.0 - dim, 1.0 - dim)
	add_child(_screen_bg)
	move_child(_screen_bg, _screen.get_index())  # just behind the screen

func _title(text: String, size: int = 28) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label

func _wrapped_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, callback: Callable, font_size: int = 0) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	if font_size > 0:
		button.add_theme_font_size_override("font_size", font_size)
	return button

func _scroll_flow() -> Array:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	scroll.add_child(flow)
	return [scroll, flow]

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _popup(dialog: Window) -> void:
	dialog.visibility_changed.connect(func(): _free_if_hidden(dialog))
	add_child(dialog)
	dialog.popup_centered()

func _free_if_hidden(dialog: Window) -> void:
	if not dialog.visible:
		dialog.queue_free()

## "Lv.1 · Vanguard" plus a compact stat block for character cards
func _card_text(uid: int) -> String:
	var o := GameState.get_owned(uid)
	var text := "%s%d" % [Terms.term("level"), int(o.level)]
	if GameState.get_ascension(uid) > 0:
		text += " · " + Terms.t("asc_short", {"rank": GameState.get_ascension(uid), "max": GameState.MAX_ASCENSION})
	var slot := GameState.team_slot_of(uid)
	if slot >= 0:
		text += "\n" + Terms.t("in_team", {"row": Terms.row_name(slot)})
	var job := Commissions.worker_commission(uid)
	if job:
		text += "\n" + Terms.t("card_on_shift", {"job": job.display_name})
	var stats := GameState.get_unit_stats(uid)
	var pairs: PackedStringArray = []
	for stat in CharacterData.STATS:
		pairs.append("%s %d" % [Terms.stat_short(stat), stats[stat]])
	for i in range(0, pairs.size(), 2):
		text += "\n" + "  ".join(pairs.slice(i, i + 2))
	return text

func _mods_text(e: EquipmentData) -> String:
	var parts: PackedStringArray = []
	var mods := e.modifiers()
	for stat in mods:
		parts.append("%s %+d" % [Terms.stat_short(stat), mods[stat]])
	return "(%s)" % ", ".join(parts) if not parts.is_empty() else ""

# ───────── Starter selection ─────────

func _show_starter_select() -> void:
	Music.play_home()
	var root := _new_screen()
	var title := _title(Terms.t("starter_title"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var parts := _scroll_flow()
	root.add_child(parts[0])
	var flow: HFlowContainer = parts[1]
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	for c in DB.characters.values():
		if not (c.is_starter and c.enabled and c.is_vanguard()):
			continue
		var card := CharCard.new()
		card.set_character(c, c.description)
		card.add_action(Terms.t("starter_pick"), func(): _choose_starter(c))
		flow.add_child(card)
	if flow.get_child_count() == 0:
		root.add_child(_wrapped_label(Terms.t("starter_none")))

func _choose_starter(c: CharacterData) -> void:
	if GameState.choose_starter(c):
		_show_main()

# ───────── Main screen (Home) ─────────

func _show_main(tab: int = 0) -> void:
	Music.play_home()
	var root := _new_screen()
	# Header: glowing title on the left, gacha-style currency capsules on the right
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)
	var title := _title(Terms.term("game_title"), 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color(UITheme.CYAN, 0.6))
	title.add_theme_constant_override("shadow_outline_size", 10)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_money_chip = CurrencyChip.new("money", Terms.term("money"))
	header.add_child(_money_chip)
	_cards_chip = CurrencyChip.new("credit_card", Terms.term("credit_cards"))
	header.add_child(_cards_chip)
	_material_chips.clear()
	for key in DB.MATERIALS:
		var chip := CurrencyChip.new(key, Terms.material_name(key))
		_material_chips[key] = chip
		header.add_child(chip)
	header.add_child(_button(Terms.t("settings"), _open_settings))

	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_home_tab())
	tabs.add_child(_build_team_tab())
	tabs.add_child(_build_gacha_tab())
	var commissions := CommissionTab.new()
	commissions.name = Terms.term("tab_commission")
	tabs.add_child(commissions)
	var casino := CasinoTab.new()
	casino.name = Terms.term("tab_casino")
	tabs.add_child(casino)
	tabs.add_child(_build_collection_tab())
	tabs.add_child(_build_event_tab())
	# Events aren't designed yet: the tab is visible but can't be opened
	var event_index := tabs.get_tab_count() - 1
	tabs.set_tab_title(event_index, Terms.t("tab_locked", {"name": Terms.term("tab_event")}))
	tabs.set_tab_disabled(event_index, true)
	tabs.current_tab = tab

	_refresh_status()
	_refresh_roster()
	# Pay out shifts that finished while the game was closed or while the player was in battle
	var reports := Commissions.resolve_finished()
	if not reports.is_empty():
		CommissionTab.show_reports(self, reports)

func _refresh_status() -> void:
	if not is_instance_valid(_money_chip):
		return
	_money_chip.set_amount(GameState.get_money())
	_cards_chip.set_amount(GameState.get_credit_cards())
	for key in _material_chips:
		_material_chips[key].set_amount(GameState.get_material(key))

# A 10-pull fires roster_changed ten times; rebuild just once at the end of the frame
func _queue_roster_refresh() -> void:
	if _roster_dirty:
		return
	_roster_dirty = true
	_refresh_roster.call_deferred()

func _refresh_roster() -> void:
	_roster_dirty = false
	if not is_instance_valid(_collection_grid):
		return
	_refresh_collection()
	_refresh_team()
	if is_instance_valid(_home_hint):
		_home_hint.text = "" if GameState.has_team() else Terms.t("home_no_team")
	_refresh_featured()

## Gacha-style lobby: the featured friend standing in the Mirror Room on the left, big action buttons on the right
func _build_home_tab() -> Control:
	var tab := HBoxContainer.new()
	tab.name = Terms.term("tab_home")
	tab.add_theme_constant_override("separation", 16)

	var stage := PanelContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var frame := UITheme.box(UITheme.INSET, Color(UITheme.CYAN, 0.45), 1, 12, 0)
	frame.shadow_color = Color(UITheme.CYAN, 0.18)
	frame.shadow_size = 10
	stage.add_theme_stylebox_override("panel", frame)
	tab.add_child(stage)
	_mirror_room = MirrorRoom.new()
	stage.add_child(_mirror_room)
	var welcome := _title(Terms.t("home_welcome"), 20)
	welcome.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	welcome.position = Vector2(18, 12)
	welcome.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_mirror_room.add_child(welcome)

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 300
	side.add_theme_constant_override("separation", 10)
	tab.add_child(side)
	var battle := _button(Terms.t("sortie_button"), _show_map_select, 30)
	battle.theme_type_variation = &"PrimaryButton"
	battle.custom_minimum_size.y = 92
	side.add_child(battle)
	_home_hint = _wrapped_label("")
	_home_hint.add_theme_color_override("font_color", Color("#fca5a5"))
	side.add_child(_home_hint)
	for key in ["tab_team", "tab_gacha", "tab_commission", "tab_casino"]:
		var go := _button(Terms.term(key), _go_to_tab.bind(Terms.term(key)), 20)
		go.custom_minimum_size.y = 52
		side.add_child(go)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	if not GameState.is_storage_persistent():
		var warning := _wrapped_label(Terms.t("storage_warning"))
		warning.add_theme_color_override("font_color", Color("#f87171"))
		side.add_child(warning)
	var hint := _wrapped_label(Terms.t("backup_hint_short"))
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(hint)
	var backup_row := HBoxContainer.new()
	backup_row.add_theme_constant_override("separation", 8)
	side.add_child(backup_row)
	for b in [_button(Terms.t("backup_download" if _is_web else "backup_copy"), _export_backup),
			_button(Terms.t("backup_restore"), _open_restore)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		backup_row.add_child(b)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	side.add_child(save_row)
	var save_buttons := [_button(Terms.t("reset_save"), _confirm_reset_save)]
	if _test_mode_enabled():
		save_buttons.push_front(_button(Terms.t("test_mode"), _open_test_mode))
	for b: Button in save_buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		save_row.add_child(b)
	_backup_message = Label.new()
	_backup_message.add_theme_font_size_override("font_size", 13)
	side.add_child(_backup_message)
	return tab

func _go_to_tab(tab_name: String) -> void:
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_control(i).name == tab_name:
			_tabs.current_tab = i
			return

## The lobby shows the team's first member (or the first friend owned) in the Mirror Room
func _refresh_featured() -> void:
	if not is_instance_valid(_mirror_room):
		return
	var members := GameState.team_members()
	var uid := -1
	if not members.is_empty():
		uid = members[0]
	elif not GameState.data.owned.is_empty():
		uid = int(GameState.data.owned[0].uid)
	var c: CharacterData = GameState.get_character(uid) if uid >= 0 else null
	if c == null:
		_mirror_room.set_featured(null, "?", "")
		return
	var o := GameState.get_owned(uid)
	_mirror_room.set_featured(c, c.display_name, "%s · %s · %s%d" % [Terms.rarity_name(c.rarity),
		Terms.class_label(c.char_class), Terms.term("level"), int(o.level)])

# ───────── Save backups ─────────

func _export_backup() -> void:
	var text := GameState.export_text()
	if _is_web:
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "respite_collection_save_%s.json" % stamp, "application/json")
		_backup_message.text = ""
	else:
		DisplayServer.clipboard_set(text)
		_backup_message.text = Terms.t("backup_copied")

func _open_restore() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Terms.t("backup_restore_title")
	dialog.ok_button_text = Terms.t("backup_restore_ok")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 320)
	dialog.add_child(box)
	box.add_child(_wrapped_label(Terms.t("backup_restore_hint")))
	var text_edit := TextEdit.new()
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.placeholder_text = "{ ... }"
	if _is_web:
		var choose := _button(Terms.t("backup_choose_file"), _pick_backup_file.bind(text_edit))
		choose.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		box.add_child(choose)
	box.add_child(text_edit)
	dialog.confirmed.connect(func(): _restore_backup(text_edit.text))
	_popup(dialog)

func _restore_backup(text: String) -> void:
	var error := GameState.import_text(text)
	if not error.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = error
		_popup(dialog)
		return
	_show_main()
	_backup_message.text = Terms.t("backup_restored")

## Opens the browser's file picker and puts the chosen file's text into the restore dialog
func _pick_backup_file(target: TextEdit) -> void:
	_restore_target = target
	if _file_picked_callback == null:
		_file_picked_callback = JavaScriptBridge.create_callback(_on_backup_file_picked)
		JavaScriptBridge.eval("""
			window.respiteCollectionPickFile = function (callback) {
				var input = document.createElement('input');
				input.type = 'file';
				input.accept = '.json,application/json,text/plain';
				input.onchange = function () {
					if (input.files.length > 0) {
						input.files[0].text().then(function (text) { callback(text); });
					}
				};
				input.click();
			};
		""", true)
	var window = JavaScriptBridge.get_interface("window")
	window.respiteCollectionPickFile(_file_picked_callback)

func _on_backup_file_picked(args: Array) -> void:
	if is_instance_valid(_restore_target) and not args.is_empty():
		_restore_target.text = str(args[0])

# ───────── Reset save & test mode ─────────

func _open_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("settings")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var label := Label.new()
	label.text = Terms.t("settings_music")
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = roundi(Music.get_volume() * 100)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var amount := Label.new()
	amount.custom_minimum_size = Vector2(56, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(amount)
	var show_amount := func(value: float) -> void:
		amount.text = Terms.t("settings_off") if value <= 0 else "%d%%" % value
	show_amount.call(slider.value)
	slider.value_changed.connect(func(value: float) -> void:
		Music.set_volume(value / 100.0)
		show_amount.call(value))
	_popup(dialog)

func _confirm_reset_save() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Terms.t("reset_save_title")
	dialog.dialog_text = Terms.t("reset_save_text")
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(460, 0)
	dialog.ok_button_text = Terms.t("reset_save_ok")
	dialog.confirmed.connect(_reset_save)
	_popup(dialog)

func _reset_save() -> void:
	GameState.reset_save()
	_show_starter_select()

## Test mode is for the developer: always on in editor/debug runs, and on the website only when the address
## ends in ?test (e.g. https://numk3y.github.io/Respite_Collection/?test), so regular players never see it
func _test_mode_enabled() -> bool:
	if OS.is_debug_build():
		return true
	if _is_web:
		return str(JavaScriptBridge.eval("window.location.search", true)).contains("test")
	return false

func _open_test_mode() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("test_mode_title")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 380)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var hint := _wrapped_label(Terms.t("test_mode_hint"))
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(hint)
	var currency_row := HBoxContainer.new()
	currency_row.add_theme_constant_override("separation", 8)
	box.add_child(currency_row)
	currency_row.add_child(_button(Terms.t("test_money"), GameState.add_money.bind(10000)))
	currency_row.add_child(_button(Terms.t("test_cards"), GameState.add_credit_cards.bind(10)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var characters: Array = DB.characters.values().filter(func(c): return c.enabled)
	characters.sort_custom(func(a, b): return a.rarity > b.rarity if a.rarity != b.rarity else a.display_name < b.display_name)
	for c: CharacterData in characters:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var name_label := Label.new()
		name_label.text = "%s  (%s · %s)" % [c.display_name, Terms.rarity_name(c.rarity), Terms.class_label(c.char_class)]
		name_label.add_theme_color_override("font_color", CharArt.RARITY_COLORS[c.rarity])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var status := Label.new()
		status.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		row.add_child(status)
		_update_test_status(status, c)
		row.add_child(_button(Terms.t("test_add"), _test_add_character.bind(c, status)))
	_popup(dialog)

func _test_add_character(c: CharacterData, status: Label) -> void:
	GameState.receive_character(c)
	_update_test_status(status, c)

func _update_test_status(status: Label, c: CharacterData) -> void:
	var o := GameState.find_owned(c.id)
	status.text = "" if o.is_empty() else Terms.t("test_owned", {"rank": int(o.get("ascension", 0))})

# ───────── Map selection ─────────
# Test maps first, then each story chapter: X-1 to X-4, then the X-5 boss. Chapters open one after another;
# the first locked chapter is shown with what opens it, later ones stay hidden.

func _show_map_select() -> void:
	var root := _new_screen()
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _title(Terms.t("map_title"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button(Terms.t("back"), _show_main))

	var can_battle := GameState.has_team()
	if not can_battle:
		root.add_child(_wrapped_label(Terms.t("map_need_team")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)

	var test_maps := DB.stages.filter(func(s): return not s.is_story())
	if not test_maps.is_empty():
		list.add_child(_title(Terms.t("map_section_test"), 22))
		for stage in test_maps:
			list.add_child(_map_panel(stage, can_battle))

	for chapter in DB.chapters():
		list.add_child(_title(Terms.chapter_title(chapter), 22))
		if not GameState.is_chapter_unlocked(chapter):
			list.add_child(_wrapped_label(Terms.t("map_chapter_locked", {
				"previous": chapter - 1, "code": "%d-%d" % [chapter - 1, StageData.BOSS_NUMBER]})))
			break
		for number in range(1, StageData.BOSS_NUMBER + 1):
			var stage := DB.get_map(chapter, number)
			if stage:
				list.add_child(_map_panel(stage, can_battle))
			else:
				var soon := _wrapped_label(Terms.t("map_coming_soon", {"code": "%d-%d" % [chapter, number]}))
				soon.modulate.a = 0.45
				list.add_child(soon)

## Map entry: code and name, a short description, recommended level, cleared/locked status and the Battle button
func _map_panel(stage: StageData, can_battle: bool) -> Control:
	var unlocked := GameState.is_stage_unlocked(stage)
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var heading := stage.display_name
	if stage.is_story():
		heading = Terms.t("map_heading", {"code": stage.code(), "name": stage.display_name})
	if stage.is_boss():
		heading += "  " + Terms.t("map_boss_tag")
	var title := _title(heading, 20)
	if stage.is_boss():
		title.add_theme_color_override("font_color", Color("#f87171"))
	info.add_child(title)
	if not stage.description.is_empty():
		info.add_child(_wrapped_label(stage.description))
	info.add_child(_wrapped_label(Terms.t("map_recommended", {"lv": stage.recommended_level})))
	if not unlocked:
		var locked := _wrapped_label(Terms.t("map_locked", {"previous": "%d-%d" % [stage.chapter, stage.number - 1]}))
		locked.add_theme_color_override("font_color", Color("#fca5a5"))
		info.add_child(locked)
	elif GameState.is_stage_cleared(stage.id):
		var cleared := _wrapped_label(Terms.t("map_cleared"))
		cleared.add_theme_color_override("font_color", Color("#86efac"))
		info.add_child(cleared)
	if not unlocked:
		panel.modulate.a = 0.6

	var go := _button(Terms.t("map_go"), _show_battle.bind(stage), 20)
	go.custom_minimum_size = Vector2(140, 56)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.disabled = not can_battle or not unlocked
	row.add_child(go)
	return panel

# ───────── Battle (built by Scripts/ui/battle_view.gd) ─────────

func _show_battle(stage: StageData) -> void:
	var battle := Combat.sortie(stage)
	Music.play_chapter(stage.chapter)  # "Again" asks for the same track, so the song keeps playing
	var root := _new_screen()
	_set_screen_background(_battle_background(stage))
	var view := BattleView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(view)
	view.again_pressed.connect(_show_battle.bind(stage))
	view.home_pressed.connect(_show_main)
	view.start(stage, battle)

## The map's own Background if set, else its chapter's picture (Art/backgrounds/PoppyStreet.png for
## "Poppy Street"), else the shared Art/backgrounds/battle.*; null if none exist
func _battle_background(stage: StageData) -> Texture2D:
	if stage.background:
		return stage.background
	var chapter_bg := UITheme.background(Terms.chapter_name(stage.chapter).replace(" ", ""))
	return chapter_bg if chapter_bg else UITheme.background("battle")

# ───────── Team tab ─────────

func _build_team_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = Terms.term("tab_team")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var tab := VBoxContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 10)
	scroll.add_child(tab)

	tab.add_child(_title(Terms.t("team_title"), 22))
	tab.add_child(_wrapped_label(Terms.t("team_hint")))
	for row in ROWS:
		tab.add_child(_title("%s — %s" % [Terms.term(row), Terms.row_classes(row == "vanguard")], 18))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		tab.add_child(box)
		_team_rows[row] = box
	return scroll

func _refresh_team() -> void:
	for row in ROWS:
		_clear(_team_rows[row])
	for slot in GameState.TEAM_SLOTS:
		var vanguard := GameState.is_vanguard_slot(slot)
		var box: HBoxContainer = _team_rows[ROWS[0] if vanguard else ROWS[1]]
		var uid := GameState.team_uid(slot)
		var c := GameState.get_character(uid)
		if c == null:
			var empty := _button(Terms.t("slot_empty", {"classes": Terms.row_classes(vanguard)}), _open_picker.bind(slot))
			empty.custom_minimum_size = Vector2(150, 220)
			box.add_child(empty)
			continue
		var card := CharCard.new()
		card.set_character(c, _card_text(uid))
		card.add_action(Terms.t("slot_change"), _open_picker.bind(slot))
		card.add_action(Terms.t("details_button"), _open_details.bind(uid))
		card.add_action(Terms.t("slot_remove"), GameState.clear_team_slot.bind(slot, 0))
		box.add_child(card)

## A grid of every owned friend's card: click one to select it (double-click assigns right away). Friends whose
## class can't use this row are listed last, dimmed and can't be picked.
func _open_picker(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Terms.t("picker_title", {"row": Terms.row_name(slot)})
	dialog.ok_button_text = Terms.t("picker_ok")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	var uids: Array = GameState.data.owned.map(func(o): return int(o.uid)).filter(func(uid): return GameState.get_character(uid) != null)
	uids.sort_custom(func(a, b):
		var a_ok := GameState.can_place(a, slot)
		if a_ok != GameState.can_place(b, slot):
			return a_ok
		var ca := GameState.get_character(a)
		var cb := GameState.get_character(b)
		return ca.rarity > cb.rarity if ca.rarity != cb.rarity else ca.display_name < cb.display_name)
	var group := ButtonGroup.new()
	var selected := {"uid": -1}
	var assign := func(uid: int) -> void:
		if uid >= 0:
			GameState.set_team_slot(slot, uid)
			dialog.hide()
	for uid: int in uids:
		var tile := _picker_tile(uid, slot, group)
		tile.toggled.connect(func(on: bool) -> void:
			if on:
				selected.uid = uid)
		tile.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.double_click and not tile.disabled:
				assign.call(uid))
		grid.add_child(tile)
	dialog.confirmed.connect(func(): assign.call(selected.uid))
	_popup(dialog)

## One friend in the team picker: their card art, then rarity/class, level and where they already are in the team
func _picker_tile(uid: int, slot: int, group: ButtonGroup) -> Button:
	var c := GameState.get_character(uid)
	var tile := Button.new()
	tile.toggle_mode = true
	tile.button_group = group
	tile.custom_minimum_size = Vector2(128, 0)
	tile.disabled = not GameState.can_place(uid, slot)
	if tile.disabled:
		tile.modulate.a = 0.4
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	box.minimum_size_changed.connect(func(): tile.custom_minimum_size.y = box.get_combined_minimum_size().y + 12)
	var art := CharArt.new()
	art.custom_minimum_size = Vector2(116, 160)
	art.set_character(c)
	box.add_child(art)
	var lines := ["%s · %s" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class)],
		"%s%d" % [Terms.term("level"), int(GameState.get_owned(uid).level)]]
	var current := GameState.team_slot_of(uid)
	if current >= 0:
		lines.append(Terms.t("in_team", {"row": Terms.row_name(current)}))
	for i in lines.size():
		var label := Label.new()
		label.text = lines[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			label.add_theme_color_override("font_color", CharArt.RARITY_COLORS[c.rarity])
		elif i == 2:
			label.add_theme_color_override("font_color", UITheme.CYAN)
		box.add_child(label)
	return tile

# ───────── Character details: class, skills, gear, stats ─────────

func _open_details(uid: int) -> void:
	var c := GameState.get_character(uid)
	if c == null:
		return
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("details_title", {"name": c.display_name})
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(500, 0)
	dialog.add_child(box)

	box.add_child(_title(Terms.t("details_class", {
		"class": Terms.class_label(c.char_class), "row": Terms.class_row(c.char_class)}), 18))
	box.add_child(_wrapped_label(_skill_text(c.passive_skill, "passive_skill")))
	box.add_child(_wrapped_label(_skill_text(c.active_skill, "active_skill")))
	box.add_child(_wrapped_label(Terms.t("details_ultimate_gauge", {"amount": c.ultimate_max})))
	box.add_child(_wrapped_label(Terms.t("details_friendship", {"amount": GameState.get_friendship(uid)})))
	var stat_names: PackedStringArray = []
	for stat in GameState.ASCENSION_STATS:
		stat_names.append(Terms.stat_short(stat))
	var rank := GameState.get_ascension(uid)
	box.add_child(_wrapped_label(Terms.t("details_ascension", {
		"rank": rank, "max": GameState.MAX_ASCENSION, "bonus": roundi(rank * GameState.ASCENSION_BONUS * 100),
		"stats": "/".join(stat_names)})))
	box.add_child(HSeparator.new())

	# Level, EXP bar and Money level-up buttons
	var stats_label := Label.new()
	var level_ui := {"label": Label.new(), "bar": ProgressBar.new(), "buttons": {}, "stats": stats_label}
	box.add_child(level_ui.label)
	level_ui.bar.show_percentage = false
	level_ui.bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(level_ui.bar)
	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	box.add_child(buy_row)
	for levels in [1, 5, 10]:
		var button := _button("", _on_buy_levels.bind(uid, levels, level_ui))
		buy_row.add_child(button)
		level_ui.buttons[levels] = button
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for slot_key in EquipmentData.SLOT_KEYS:
		var label := Label.new()
		label.text = Terms.slot_name(slot_key)
		grid.add_child(label)
		var option := OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_fill_equipment_options(option, uid, slot_key)
		option.item_selected.connect(func(index): _on_equipment_selected(option, uid, slot_key, index, stats_label))
		grid.add_child(option)
	box.add_child(HSeparator.new())
	box.add_child(stats_label)
	_refresh_level_ui(uid, level_ui)
	_popup(dialog)

func _on_buy_levels(uid: int, levels: int, level_ui: Dictionary) -> void:
	GameState.buy_levels(uid, levels)
	_refresh_level_ui(uid, level_ui)

func _refresh_level_ui(uid: int, level_ui: Dictionary) -> void:
	var o := GameState.get_owned(uid)
	var level := int(o.level)
	var at_max := level >= GameState.MAX_LEVEL
	if at_max:
		level_ui.label.text = Terms.t("details_level_max", {"lv": level})
		level_ui.bar.max_value = 1
		level_ui.bar.value = 1
	else:
		var next := GameState.exp_to_next(level)
		level_ui.label.text = Terms.t("details_level", {"lv": level, "current": int(o.exp), "next": next})
		level_ui.bar.max_value = next
		level_ui.bar.value = int(o.exp)
	for levels in level_ui.buttons:
		var button: Button = level_ui.buttons[levels]
		var cost := GameState.level_up_cost(uid, levels)
		button.text = Terms.t("level_up_max") if at_max else Terms.t("level_up_button", {"count": levels, "cost": cost})
		button.disabled = at_max or GameState.get_money() < cost
		button.visible = not at_max or levels == 1
	_update_stats_label(level_ui.stats, uid)

func _skill_text(skill: SkillData, kind_key: String) -> String:
	if skill == null or skill.display_name.is_empty():
		return Terms.t("skill_missing", {"kind": Terms.term(kind_key)})
	return Terms.t("skill_line", {"kind": Terms.term(kind_key), "name": skill.display_name, "description": skill.description})

func _fill_equipment_options(option: OptionButton, uid: int, slot_key: String) -> void:
	option.clear()
	option.add_item(Terms.t("equip_none"))
	option.set_item_metadata(0, 0)
	var current := int(GameState.get_owned(uid).equips[slot_key])
	for entry in GameState.list_equipment(slot_key):
		var text := "%s %s" % [entry.data.display_name, _mods_text(entry.data)]
		var wearer := GameState.equipped_by(entry.uid)
		if wearer != 0 and wearer != uid:
			text = Terms.t("equip_worn_by", {"item": text, "owner": GameState.get_character(wearer).display_name})
		option.add_item(text)
		option.set_item_metadata(option.item_count - 1, entry.uid)
		if entry.uid == current:
			option.selected = option.item_count - 1
	if current == 0:
		option.selected = 0

func _on_equipment_selected(option: OptionButton, uid: int, slot_key: String, index: int, stats_label: Label) -> void:
	GameState.equip(uid, slot_key, option.get_item_metadata(index))
	_update_stats_label(stats_label, uid)

func _update_stats_label(label: Label, uid: int) -> void:
	var base := GameState.get_unit_stats(uid, false)
	var final := GameState.get_unit_stats(uid)
	var lines: PackedStringArray = []
	for stat in CharacterData.STATS:
		var diff: int = final[stat] - base[stat]
		if diff == 0:
			lines.append(Terms.t("stat_line", {"stat": Terms.stat_name(stat), "value": final[stat]}))
		else:
			lines.append(Terms.t("stat_line_mod", {"stat": Terms.stat_name(stat), "value": final[stat], "mod": "%+d" % diff}))
	label.text = "\n".join(lines)

# ───────── Event tab (locked placeholder) ─────────

func _build_event_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.term("tab_event")
	tab.add_child(_wrapped_label(Terms.t("event_locked")))
	return tab

# ───────── Recruit tab (built by Scripts/ui/gacha_tab.gd) ─────────

func _build_gacha_tab() -> Control:
	var tab := GachaTab.new()
	tab.name = Terms.term("tab_gacha")
	return tab

# ───────── Roster tab ─────────

func _build_collection_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.term("tab_collection")
	var parts := _scroll_flow()
	tab.add_child(parts[0])
	_collection_grid = parts[1]
	return tab

func _refresh_collection() -> void:
	_clear(_collection_grid)
	for o in GameState.data.owned:
		var uid := int(o.uid)
		var c := GameState.get_character(uid)
		if c == null:
			continue  # the character resource was deleted; skip this save entry
		var card := CharCard.new()
		card.set_character(c, _card_text(uid))
		card.add_action(Terms.t("details_button"), _open_details.bind(uid))
		_collection_grid.add_child(card)
