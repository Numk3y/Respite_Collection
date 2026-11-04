extends Control
## Screen flow: starter pick -> Home (tabs: Home / Team / Workshop / Recruit / Commissions / Casino / Friends / Event) -> Battle -> Map selection -> Battle screen.
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
var _account_label: Label
var _account_bar: ProgressBar
# Home
var _home_hint: Label
var _sortie_button: Button
var _recruit_button: Button  # Home's shortcut to Recruit (the tutorial points at it for the free pull)
var _gacha_tab: GachaTab
var _beginner_button: Button
var _coach: Coach  # the tutorial's speech bubble, above every screen
var _auto_run := {}  # the Auto Run series in progress (see _start_auto_run); {} when none
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
	_coach = Coach.new()
	add_child(_coach)
	_coach.skip_pressed.connect(_skip_tutorial)
	GameState.stats_changed.connect(_refresh_beginner)
	GameState.money_changed.connect(func(_value): _refresh_status())
	GameState.materials_changed.connect(_refresh_status)
	GameState.credit_cards_changed.connect(func(_value): _refresh_status())
	GameState.account_changed.connect(_refresh_status)
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
	if _coach:
		_coach.clear()
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
	# Account level with its EXP bar; hover for the team cost limit
	var account := VBoxContainer.new()
	account.add_theme_constant_override("separation", 2)
	account.alignment = BoxContainer.ALIGNMENT_CENTER
	account.custom_minimum_size.x = 150
	account.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_child(account)
	_account_label = Label.new()
	_account_label.add_theme_font_size_override("font_size", 14)
	_account_label.add_theme_color_override("font_color", UITheme.CYAN_BRIGHT)
	_account_label.mouse_filter = Control.MOUSE_FILTER_PASS
	account.add_child(_account_label)
	_account_bar = ProgressBar.new()
	_account_bar.show_percentage = false
	_account_bar.custom_minimum_size.y = 6
	_account_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	account.add_child(_account_bar)
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
	var workshop := WorkshopTab.new()
	workshop.name = Terms.term("tab_workshop")
	tabs.add_child(workshop)
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
	# Home: the lobby picture fills the whole window, blurred and darkened behind the menus; the Mirror Room
	# card shows the same picture sharp and in full colour (Scripts/ui/mirror_room.gd)
	_set_screen_background(UITheme.blurred(UITheme.home_background()), 0.5)
	tabs.tab_changed.connect(_on_main_tab_changed)
	_on_main_tab_changed(tabs.current_tab)
	_refresh_beginner()

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
	var level := GameState.get_account_level()
	var limit := GameState.team_cost_limit()
	_account_label.text = Terms.t("account_level", {"lv": level})
	var account_box: Control = _account_label.get_parent()
	if level >= GameState.ACCOUNT_MAX_LEVEL:
		_account_bar.max_value = 1
		_account_bar.value = 1
		account_box.tooltip_text = Terms.t("account_exp_max", {"limit": limit})
	else:
		var next := GameState.account_exp_to_next(level)
		_account_bar.max_value = next
		_account_bar.value = GameState.get_account_exp()
		account_box.tooltip_text = Terms.t("account_exp_tip", {"xp": GameState.get_account_exp(), "next": next,
			"limit": limit, "cap": GameState.TEAM_COST_CAP})
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
		_home_hint.text = _team_problem()
		_home_hint.visible = _home_hint.text != ""
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

	# The side column scrolls if a short window can't fit it all (otherwise the bottom rows get cut off)
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size.x = 300
	tab.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	side_scroll.add_child(side)
	var battle := _button(Terms.t("sortie_button"), _show_map_select, 30)
	_sortie_button = battle
	battle.theme_type_variation = &"PrimaryButton"
	battle.custom_minimum_size.y = 76
	side.add_child(battle)
	_home_hint = _wrapped_label("")
	_home_hint.add_theme_color_override("font_color", Color("#fca5a5"))
	_home_hint.visible = false
	side.add_child(_home_hint)
	# Beginner Missions: shows how many are ready to claim; gone once everything (and the free SSR) is claimed
	_beginner_button = _button(Terms.t("beginner_button"), _open_beginner, 18)
	_beginner_button.custom_minimum_size.y = 44
	_beginner_button.add_theme_color_override("font_color", UITheme.GOLD)
	side.add_child(_beginner_button)
	for key in ["tab_team", "tab_gacha", "tab_commission", "tab_casino"]:
		var go := _button(Terms.term(key), _go_to_tab.bind(Terms.term(key)), 20)
		go.custom_minimum_size.y = 46
		side.add_child(go)
		if key == "tab_gacha":
			_recruit_button = go

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

## The full-screen home picture only shows on the Home tab, with a lighter tab panel so it shows through;
## the other tabs keep the usual cyber backdrop and solid panels
func _on_main_tab_changed(index: int) -> void:
	var home := index == 0
	_update_home_tutorial.call_deferred()  # after the tab has laid out, so the arrow lands on the button
	if _screen_bg:
		_screen_bg.visible = home
	if home and _screen_bg:
		var see_through := UITheme.panel_box(12)
		see_through.corner_radius_top_left = 4
		see_through.bg_color = Color(UITheme.PANEL, 0.25)
		_tabs.add_theme_stylebox_override("panel", see_through)
	else:
		_tabs.remove_theme_stylebox_override("panel")

## Why the team can't battle right now, or "" if it can
func _team_problem() -> String:
	if not GameState.has_team():
		return Terms.t("home_no_team")
	if GameState.is_team_over_cost():
		return Terms.t("team_over_cost", {"cost": GameState.team_cost(), "limit": GameState.team_cost_limit()})
	return ""

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
	return GameState.is_test_mode()

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
	currency_row.add_child(_button(Terms.t("test_parts"), GameState.add_parts.bind(100)))
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
	screen.auto_run_pressed.connect(_open_auto_run)
	screen.open(GameState.can_battle())
	# Tutorial: point at the Battle button of the first map
	if GameState.tutorial_step() <= GameState.Tutorial.MAP_GO and GameState.can_battle():
		GameState.advance_tutorial(GameState.Tutorial.MAP_GO)
		_point_coach.call_deferred(screen.battle_button(), Terms.t("tutorial_map_go"))


# ───────── Battle (built by Scripts/ui/battle_view.gd) ─────────

## `auto`: one run of the Auto Run series in _auto_run (automatic Ultimates, Auto Run EXP, and the next run
## follows from the results screen); any other battle ends a series
func _show_battle(stage: StageData, auto: bool = false) -> void:
	if not auto:
		_auto_run = {}
	var manual := not auto and not bool(GameState.get_setting("auto_ultimate", true))
	# Tutorial: the first fight is guided and always starts with manual Ultimates
	var guided := not auto and GameState.tutorial_step() < GameState.Tutorial.RECRUIT
	if guided:
		GameState.advance_tutorial(GameState.Tutorial.FIRST_FIGHT)
		manual = true
	# Live: played one action at a time, rewards at the end
	var units := Combat.start_sortie(stage, manual, Combat.AUTO_RUN_EXP if auto else 1.0)
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
	var next: StageData = _next_event_mission(event, stage) if not auto else null
	if auto:
		var run := _auto_run
		view.auto_label = Terms.t("auto_run_progress", {"current": int(run.played) + 1, "runs": run.runs})
		view.battle_finished.connect(_on_auto_run_battle)
		if int(run.played) + 1 < int(run.runs):
			view.next_text = Terms.t("auto_run_next", {"current": int(run.played) + 2, "runs": run.runs})
			view.next_pressed.connect(_show_battle.bind(stage, true))
			view.auto_next = true
	if next:
		view.next_text = Terms.t("battle_next_mission", {"code": next.code(), "name": next.display_name})
		view.next_pressed.connect(_show_battle.bind(next))
	if guided:
		view.coach = _coach
		view.battle_finished.connect(func(_report: Dictionary):
			GameState.advance_tutorial(GameState.Tutorial.RECRUIT)
			_coach.clear())
	view.start_live(stage, units, manual)

# ───────── Auto Run (Combat.can_auto_run) ─────────

## How many runs: one button per count up to the cap
func _open_auto_run(stage: StageData) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("auto_run_title", {"code": stage.code(), "name": stage.display_name})
	dialog.ok_button_text = Terms.t("beginner_close")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size.x = 420
	dialog.add_child(box)
	box.add_child(_wrapped_label(Terms.t("auto_run_intro")))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for runs in range(1, Combat.AUTO_RUN_MAX + 1):
		var go := _button(Terms.t("auto_run_count", {"count": runs}), func():
			dialog.hide()
			_start_auto_run(stage, runs), 20)
		go.custom_minimum_size = Vector2(110, 52)
		go.theme_type_variation = &"PrimaryButton"
		row.add_child(go)
	_popup(dialog)

## Starts an Auto Run series: the first run plays right away, the rest follow from the results screen
func _start_auto_run(stage: StageData, runs: int) -> void:
	_auto_run = {"stage": stage, "runs": runs, "played": 0, "wins": 0, "money": 0, "exp": 0, "account_exp": 0,
		"materials": {}, "drops": [], "card_drops": 0, "level_ups": {}, "bond_ups": {}, "account_level_up": 0}
	_show_battle(stage, true)

## One Auto Run battle is over: add it to the series, and after the last run (or a loss) show the totals
func _on_auto_run_battle(report: Dictionary) -> void:
	if _auto_run.is_empty():
		return
	var run := _auto_run
	run.played += 1
	if report.get("won", false):
		run.wins += 1
	run.money += int(report.get("money", 0))
	run.exp += int(report.get("exp", 0))
	run.account_exp += int(report.get("account_exp", 0))
	run.card_drops += int(report.get("card_drops", 0))
	for key in report.get("materials", {}):
		run.materials[key] = int(run.materials.get(key, 0)) + int(report.materials[key])
	run.drops.append_array(report.get("drops", []))
	for up in report.get("level_ups", []):
		run.level_ups[up.name] = up.level
	for up in report.get("bond_ups", []):
		run.bond_ups[up.name] = up.bond
	run.account_level_up = maxi(int(run.account_level_up), int(report.get("account_level_up", 0)))
	if report.get("won", false) and run.played < run.runs:
		return  # the results screen counts down into the next run
	_auto_run = {}
	_show_auto_run_summary(run)

func _show_auto_run_summary(run: Dictionary) -> void:
	var lines := PackedStringArray()
	if run.wins < run.played:
		lines.append(Terms.t("auto_run_stopped"))
	if run.wins > 0:
		lines.append(Terms.t("auto_run_money", {"amount": run.money}))
		for key in run.materials:
			if int(run.materials[key]) > 0:
				lines.append("%s x%d" % [Terms.material_name(key), int(run.materials[key])])
		for item in run.drops:
			lines.append(Terms.t("auto_run_drop", {"item": item}))
		lines.append(Terms.t("auto_run_exp", {"amount": run.exp}))
		lines.append(Terms.t("auto_run_account_exp", {"amount": run.account_exp}))
	if int(run.card_drops) > 0:
		lines.append(Terms.t("auto_run_cards", {"amount": run.card_drops, "card_word": Terms.credit_card_word(run.card_drops)}))
	for friend in run.level_ups:
		lines.append(Terms.t("battle_level_up", {"name": friend, "lv": run.level_ups[friend]}))
	if int(run.account_level_up) > 0:
		lines.append(Terms.t("battle_account_level_up", {"lv": run.account_level_up,
			"limit": GameState.team_cost_limit_at(run.account_level_up)}))
	for friend in run.bond_ups:
		lines.append(Terms.t("battle_bond_up", {"name": friend, "bond": run.bond_ups[friend]}))
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("auto_run_done", {"wins": run.wins, "runs": run.played})
	dialog.dialog_text = "\n".join(lines)
	dialog.min_size = Vector2i(420, 0)
	_popup(dialog)

# ───────── Tutorial (the Coach bubble) and Beginner Missions (Scripts/beginner_missions.gd) ─────────

func _point_coach(target: Control, text: String) -> void:
	if (target == null or is_instance_valid(target)) and GameState.tutorial_step() < GameState.Tutorial.DONE:
		_coach.point(target, text)

## On the Home tab: point at Battle before the first fight, then at Beginner Missions after it
func _update_home_tutorial() -> void:
	if not is_instance_valid(_tabs) or not is_instance_valid(_sortie_button):
		return
	var step := GameState.tutorial_step()
	if _tabs.current_tab == _gacha_tab.get_index() and step == GameState.Tutorial.RECRUIT:
		_point_coach(_gacha_tab.free_pull_button(), Terms.t("tutorial_free_pull"))
		return
	if _tabs.current_tab == _gacha_tab.get_index() and step == GameState.Tutorial.MISSIONS:
		return  # the "joined your team" bubble from the pull stays up
	if _tabs.current_tab != 0:
		_coach.clear()
		return
	if step < GameState.Tutorial.RECRUIT:
		_point_coach(_sortie_button, Terms.t("tutorial_home_battle"))
	elif step == GameState.Tutorial.RECRUIT and Gacha.beginner_available():
		_point_coach(_recruit_button, Terms.t("tutorial_go_recruit"))
	elif step <= GameState.Tutorial.MISSIONS:
		_point_coach(_beginner_button, Terms.t("tutorial_missions"))
	else:
		_coach.clear()

func _skip_tutorial() -> void:
	GameState.advance_tutorial(GameState.Tutorial.DONE)
	_coach.clear()

## The Home button's label and badge ("Beginner Missions (2!)"); hidden once everything is claimed
func _refresh_beginner() -> void:
	if not is_instance_valid(_beginner_button):
		return
	_beginner_button.visible = not BeginnerMissions.finished()
	var ready_count := BeginnerMissions.claimable_count()
	_beginner_button.text = Terms.t("beginner_button_ready", {"count": ready_count}) if ready_count > 0 else Terms.t("beginner_button")

## The checklist: each mission with its progress, reward and a Claim button; the free SSR pick at the bottom
func _open_beginner() -> void:
	if GameState.tutorial_step() == GameState.Tutorial.MISSIONS:
		_skip_tutorial()  # the tutorial ends here
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("beginner_title")
	dialog.ok_button_text = Terms.t("beginner_close")
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(620, 0)
	list.add_theme_constant_override("separation", 8)
	dialog.add_child(list)
	_fill_beginner(list, dialog)
	_popup(dialog)

func _fill_beginner(list: VBoxContainer, dialog: AcceptDialog) -> void:
	_clear(list)
	var intro := _wrapped_label(Terms.t("beginner_intro"))
	intro.add_theme_color_override("font_color", UITheme.GOLD)
	list.add_child(intro)
	for m: Dictionary in BeginnerMissions.MISSIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var claimed := BeginnerMissions.is_claimed(m)
		var done := BeginnerMissions.is_done(m)
		var title := _wrapped_label(Terms.t("beginner_" + String(m.id)))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_color_override("font_color", UITheme.TEXT_DIM if claimed else UITheme.TEXT)
		row.add_child(title)
		var count := Label.new()
		count.text = "%d/%d" % [BeginnerMissions.progress(m), int(m.goal)]
		count.custom_minimum_size.x = 56
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.add_theme_color_override("font_color", Color("#4ade80") if done else UITheme.TEXT_DIM)
		row.add_child(count)
		var reward := Label.new()
		reward.custom_minimum_size.x = 130
		var parts: PackedStringArray = []
		if int(m.cards) > 0:
			parts.append(Terms.t("beginner_reward_cards", {"amount": int(m.cards), "card_word": Terms.credit_card_word(int(m.cards))}))
		if int(m.money) > 0:
			parts.append(Terms.t("beginner_reward_money", {"amount": int(m.money)}))
		for key in m.materials:
			parts.append("%d %s" % [int(m.materials[key]), Terms.material_name(key)])
		reward.text = ", ".join(parts)
		reward.custom_minimum_size.x = 190
		reward.add_theme_color_override("font_color", UITheme.GOLD)
		row.add_child(reward)
		var claim := Button.new()
		claim.custom_minimum_size.x = 90
		claim.text = Terms.t("beginner_claimed" if claimed else "beginner_claim")
		claim.disabled = claimed or not done
		if done and not claimed:
			claim.theme_type_variation = &"PrimaryButton"
		claim.pressed.connect(func():
			if BeginnerMissions.claim(m):
				_fill_beginner(list, dialog))
		row.add_child(claim)
	# The prize: a free SSR once every mission is claimed
	list.add_child(HSeparator.new())
	var prize := HBoxContainer.new()
	prize.add_theme_constant_override("separation", 10)
	list.add_child(prize)
	var prize_text := _wrapped_label(Terms.t("beginner_ssr_row"))
	prize_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prize_text.add_theme_font_size_override("font_size", 18)
	prize_text.add_theme_color_override("font_color", UITheme.GOLD)
	prize.add_child(prize_text)
	var pick := Button.new()
	pick.text = Terms.t("beginner_claimed" if BeginnerMissions.ssr_claimed() else "beginner_ssr_pick")
	pick.custom_minimum_size = Vector2(130, 40)
	pick.disabled = not BeginnerMissions.all_claimed() or BeginnerMissions.ssr_claimed()
	if not pick.disabled:
		pick.theme_type_variation = &"PrimaryButton"
	pick.pressed.connect(func():
		dialog.hide()
		_open_ssr_pick())
	prize.add_child(pick)
	dialog.reset_size.call_deferred()

## The free SSR: every recruitable SSR as a card to pick from
func _open_ssr_pick() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Terms.t("beginner_ssr_title")
	dialog.ok_button_text = Terms.t("beginner_ssr_take")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	dialog.add_child(grid)
	var group := ButtonGroup.new()
	var picked := {"c": null}
	for c: CharacterData in BeginnerMissions.ssr_choices():
		var tile := Button.new()
		tile.toggle_mode = true
		tile.button_group = group
		tile.custom_minimum_size = Vector2(140, 230)
		tile.tooltip_text = c.description
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(box)
		var art := CharArt.new()
		art.custom_minimum_size = Vector2(128, 170)
		art.set_character(c)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(art)
		for line in [c.display_name, Terms.class_label(c.char_class)]:
			var label := Label.new()
			label.text = line
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 13)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if GameState.owns(c.id) and line == c.display_name:
				label.text += " " + Terms.t("beginner_ssr_owned")
			box.add_child(label)
		tile.toggled.connect(func(on: bool):
			if on:
				picked.c = c)
		grid.add_child(tile)
	dialog.confirmed.connect(func():
		if picked.c == null:
			return
		var c: CharacterData = picked.c
		if not BeginnerMissions.claim_ssr(c).is_empty():
			_show_message(Terms.t("beginner_ssr_got", {"name": c.display_name})))
	_popup(dialog)

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
	var fits := GameState.fits_cost(uid, slot)
	tile.disabled = not GameState.can_place(uid, slot) or not fits
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
		"%s%d    %s" % [Terms.term("level"), int(GameState.get_owned(uid).level), Terms.t("picker_cost", {"cost": GameState.unit_cost(uid)})]]
	var current := GameState.team_slot_of(uid)
	if current >= 0:
		lines.append(Terms.t("in_team", {"row": Terms.row_name(current)}))
	elif not fits and GameState.can_place(uid, slot):
		lines.append(Terms.t("picker_over_cost"))
	for i in lines.size():
		var label := Label.new()
		label.text = lines[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i == 0:
			label.add_theme_color_override("font_color", CharArt.RARITY_COLORS[c.rarity])
		elif i == 2:
			label.add_theme_color_override("font_color", UITheme.CYAN if current >= 0 else Color("#fca5a5"))
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
	screen.open_event(event, GameState.can_battle())

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
	_gacha_tab = tab
	tab.beginner_pulled.connect(func(result: Dictionary):
		if GameState.tutorial_step() < GameState.Tutorial.MISSIONS:
			GameState.advance_tutorial(GameState.Tutorial.MISSIONS)
			_point_coach.call_deferred(null, Terms.t("tutorial_after_pull", {"name": result.character.display_name})))
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
