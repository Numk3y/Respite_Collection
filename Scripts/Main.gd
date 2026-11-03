extends Control
## Screen flow: starter pick -> Home (tabs: Home / Team / Recruit / Commissions / Casino / Friends / Event) -> Battle -> Map selection -> Battle screen.
## Event tab -> event missions (Map selection in event mode) or the World Boss fight -> Battle screen.
## All text comes from Terms (Scripts/autoload/terms.gd).


var _is_web := OS.has_feature("web")
var _screen: Control
var _screen_bg: TextureRect  # an optional full-screen picture behind the current screen (e.g. battles)
var _roster_dirty := false
var _backup_message: Label
var _restore_target: TextEdit
var _file_picked_callback = null  # JavaScriptObject; must stay referenced or the browser drops it
var _boss_starting := false  # waiting for the server to hand out a World Boss attempt

# Header
var _money_chip: CurrencyChip
var _cards_chip: CurrencyChip
var _material_chips := {}  # material key -> CurrencyChip
var _tabs: TabContainer
# Home
var _home_hint: Label
var _mirror_room: MirrorRoom
# Team
var _team_tab: TeamTab
# Friends tab (the friend list)
var _collection_tab: CollectionTab

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
	tabs.current_tab = tab

	_refresh_status()
	_refresh_roster()
	# Pay out shifts that finished while the game was closed or while the player was in battle
	var reports := Commissions.resolve_finished()
	if not reports.is_empty():
		CommissionTab.show_reports(self, reports)
	_collect_event_rewards()

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
	if not is_instance_valid(_collection_tab):
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
		Terms.class_label(c.char_class), Terms.term("level"), int(o.level)], GameState.get_ascension(uid))

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
	# The dialog grows to fit its content and never shrinks back, so the friend list gets a fixed height that
	# fits the screen and scrolls; the window itself is capped too, keeping OK reachable
	var screen := get_viewport_rect().size
	dialog.max_size = Vector2i(screen * 0.95)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var hint := _wrapped_label(Terms.t("test_mode_hint"))
	hint.custom_minimum_size.x = 560  # a wrapped label measured at zero width would be very tall
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(hint)
	var currency_row := HBoxContainer.new()
	currency_row.add_theme_constant_override("separation", 8)
	box.add_child(currency_row)
	currency_row.add_child(_button(Terms.t("test_money"), GameState.add_money.bind(10000)))
	currency_row.add_child(_button(Terms.t("test_cards"), GameState.add_credit_cards.bind(10)))
	currency_row.add_child(_button(Terms.t("test_animatronics"), func(): Combat.force_animatronics = true))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = clampf(screen.y - 300.0, 150.0, 420.0)  # room left for title, hint, buttons, OK
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS  # so it's obvious the list scrolls
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

# ───────── Map selection (built by Scripts/ui/map_select.gd) ─────────

func _show_map_select() -> void:
	var root := _new_screen()
	var screen := MapSelect.new()
	root.add_child(screen)
	screen.back_pressed.connect(_show_main)
	screen.battle_pressed.connect(_show_battle)
	screen.open(GameState.has_team())


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
	var event := DB.event_of(stage)
	view.home_pressed.connect(_show_event_tab if event else _show_main)
	# Event missions: offer to go straight on to the next one (it unlocks by winning this one)
	var next := _next_event_mission(event, stage)
	if next:
		view.next_text = Terms.t("battle_next_mission", {"code": next.code(), "name": next.display_name})
		view.next_pressed.connect(_show_battle.bind(next))
	view.start(stage, battle)

## The mission after `stage` in its event, or null (not an event mission, or the last one)
func _next_event_mission(event: EventData, stage: StageData) -> StageData:
	if event == null:
		return null
	var i := event.missions.find(stage)
	return event.missions[i + 1] if i >= 0 and i + 1 < event.missions.size() else null

## The map's own Background if set, else its chapter's picture (Art/backgrounds/PoppyStreet.png for
## "Poppy Street"), else the shared Art/backgrounds/battle.*; null if none exist
func _battle_background(stage: StageData) -> Texture2D:
	if stage.background:
		return stage.background
	var chapter_bg := UITheme.background(Terms.chapter_name(stage.chapter).replace(" ", ""))
	return chapter_bg if chapter_bg else UITheme.background("battle")

# ───────── Team tab ─────────

## Built by Scripts/ui/team_tab.gd; the picker and details window stay here
func _build_team_tab() -> Control:
	_team_tab = TeamTab.new()
	_team_tab.name = Terms.term("tab_team")
	_team_tab.change_requested.connect(_open_picker)
	_team_tab.details_requested.connect(_open_details)
	return _team_tab

func _refresh_team() -> void:
	if is_instance_valid(_team_tab):
		_team_tab.refresh()

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

# ───────── Character details (Scripts/ui/character_detail.gd) ─────────

func _open_details(uid: int) -> void:
	if GameState.get_character(uid):
		add_child(CharacterDetail.new(uid))

# ───────── Event tab and the World Boss (built by Scripts/ui/event_tab.gd; server: WorldBoss) ─────────

func _build_event_tab() -> Control:
	var tab := EventTab.new()
	tab.name = Terms.term("tab_event")
	tab.missions_pressed.connect(_show_event_missions)
	tab.challenge_pressed.connect(_start_world_boss)
	tab.event_over.connect(_collect_event_rewards)
	return tab

func _show_event_tab() -> void:
	_show_main()
	_go_to_tab(Terms.term("tab_event"))

func _show_event_missions(event: EventData) -> void:
	var root := _new_screen()
	var screen := MapSelect.new()
	root.add_child(screen)
	screen.back_pressed.connect(_show_event_tab)
	screen.battle_pressed.connect(_show_battle)
	screen.open_event(event, GameState.has_team())

## Asks the server for an attempt (and its seed), plays the fight, then reports the damage. If the report can't
## get through, WorldBoss keeps it in the save and sends it later.
func _start_world_boss(event: EventData) -> void:
	if _boss_starting:
		return
	_boss_starting = true
	var attempt := await WorldBoss.start_attempt()
	_boss_starting = false
	if not attempt.ok:
		_show_event_tab()
		_show_message(Terms.t("boss_start_failed" if attempt.status == 0 else "boss_start_refused"))
		return
	var battle := Combat.world_boss_fight(event, int(attempt.data.seed))
	Music.play_chapter(event.boss_stage.chapter)
	var root := _new_screen()
	_set_screen_background(_battle_background(event.boss_stage))
	var view := BattleView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(view)
	view.again_pressed.connect(_start_world_boss.bind(event))
	view.home_pressed.connect(_show_event_tab)
	view.start(event.boss_stage, battle)
	view.set_note(Terms.t("boss_sending"))
	var answer := await WorldBoss.report_fight(str(attempt.data.attempt_id), int(battle.report.damage))
	if not is_instance_valid(view):
		return
	if answer.is_empty():
		view.set_note(Terms.t("boss_send_later"))
	elif answer.defeated:
		view.set_note(Terms.t("boss_sent_kill"))
	else:
		view.set_note(Terms.t("boss_sent", {"hp": Terms.number(int(answer.hp))}))

## Pays out finished events this player hit (WorldBoss grants them) and lists what came in
func _collect_event_rewards() -> void:
	var results := await WorldBoss.collect_rewards()
	if results.is_empty():
		return
	var lines := PackedStringArray()
	for r in results:
		lines.append(Terms.t("event_rewards_header", {"event": r.event.display_name, "damage": Terms.number(r.damage),
			"rank": r.rank, "players": r.players}))
		for reward: EventReward in r.rewards:
			lines.append(Terms.t("event_rewards_line", {"rewards": ", ".join(reward.lines())}))
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("event_rewards_title")
	dialog.dialog_text = "\n".join(lines)
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(480, 0)
	_popup(dialog)

func _show_message(text: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.dialog_text = text
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(420, 0)
	_popup(dialog)

# ───────── Recruit tab (built by Scripts/ui/gacha_tab.gd) ─────────

func _build_gacha_tab() -> Control:
	var tab := GachaTab.new()
	tab.name = Terms.term("tab_gacha")
	return tab

# ───────── Friends tab ─────────

## Built by Scripts/ui/collection_tab.gd; the details window stays here
func _build_collection_tab() -> Control:
	_collection_tab = CollectionTab.new()
	_collection_tab.name = Terms.term("tab_collection")
	_collection_tab.details_requested.connect(_open_details)
	return _collection_tab

func _refresh_collection() -> void:
	_collection_tab.refresh()
