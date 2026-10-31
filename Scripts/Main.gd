extends Control
## Screen flow: starter pick -> Home (tabs: Home / Fleet / Recruit / Roster) -> Sortie -> Map selection -> Battle.
## Also handles window behaviour for background idling. All text comes from Terms (Scripts/autoload/terms.gd).

const ROWS := ["vanguard", "rearguard"]
const PLAYBACK_SEC := 0.55  # delay between battle actions on the Battle screen
const CATCH_UP_DIALOG_BATTLES := 10  # show "welcome back" after this many missed battles (5 min)

var _is_web := OS.has_feature("web")
var _screen: Control
var _tray: StatusIndicator
var _roster_dirty := false
var _backup_message: Label
var _restore_target: TextEdit
var _file_picked_callback = null  # JavaScriptObject; must stay referenced or the browser drops it

# Header
var _money_label: Label
var _materials_label: Label
# Home
var _idle_label: Label
var _report_label: Label
# Fleet
var _fleet_rows: Dictionary = {}  # "vanguard" / "rearguard" -> HBoxContainer
# Recruit
var _gacha_message: Label
var _gacha_results: HFlowContainer
var _pity_labels: Dictionary = {}  # pool_id -> Label
# Roster
var _collection_grid: HFlowContainer
# Battle playback
var _playback: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_window().title = Terms.term("game_title")
	if not _is_web:  # no tray or close button in a browser tab
		get_tree().auto_accept_quit = false  # we handle the close button ourselves
		_setup_tray()
	GameState.money_changed.connect(func(_value): _refresh_status())
	GameState.materials_changed.connect(_refresh_status)
	GameState.roster_changed.connect(_queue_roster_refresh)
	Idle.settled.connect(_on_idle_settled)
	if GameState.data.starter_chosen:
		_show_main()
	else:
		_show_starter_select()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			Engine.max_fps = 5  # nearly zero CPU while unfocused; timers keep running
		NOTIFICATION_APPLICATION_FOCUS_IN:
			Engine.max_fps = 0
			_catch_up()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if GameState.get_setting("minimize_on_close", true):
				get_window().mode = Window.MODE_MINIMIZED
			else:
				quit_game()

func quit_game() -> void:
	GameState.save_game()
	get_tree().quit()

## Browsers pause the game completely while its tab is in the background, so pay out
## the missed patrol battles as soon as the player comes back
func _catch_up() -> void:
	if not GameState.data.starter_chosen:
		return
	var report := Idle.settle()
	if report.get("battles", 0) >= CATCH_UP_DIALOG_BATTLES:
		_show_offline_dialog(report)

func _setup_tray() -> void:
	_tray = StatusIndicator.new()
	_tray.tooltip = Terms.t("tray_tooltip")
	_tray.icon = load("res://icon.svg")
	_tray.pressed.connect(func(_button, _position): _restore_window())
	add_child(_tray)

func _restore_window() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().move_to_foreground()
	get_window().grab_focus()

# ───────── Shared helpers ─────────

func _new_screen() -> VBoxContainer:
	if _screen:
		_screen.queue_free()
	_playback = {}
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
	var slot := GameState.fleet_slot_of(uid)
	if slot >= 0:
		text += " · " + Terms.t("in_fleet", {"row": Terms.row_name(slot)})
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

func _materials_text(materials: Dictionary) -> String:
	var text := ""
	for key in materials:
		if materials[key] == 0:
			continue
		text += Terms.t("report_material", {"material": Terms.material_name(key), "amount": materials[key]})
	return text

# ───────── Starter selection ─────────

func _show_starter_select() -> void:
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
		GameState.data.last_tick = int(Time.get_unix_time_from_system())
		_show_main()

# ───────── Main screen (Home) ─────────

func _show_main(tab: int = 0) -> void:
	var root := _new_screen()
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	root.add_child(header)
	header.add_child(_title(Terms.term("game_title")))
	_money_label = Label.new()
	header.add_child(_money_label)
	_materials_label = Label.new()
	header.add_child(_materials_label)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_home_tab())
	tabs.add_child(_build_fleet_tab())
	tabs.add_child(_build_gacha_tab())
	tabs.add_child(_build_collection_tab())
	tabs.current_tab = tab

	_refresh_status()
	_refresh_roster()
	if not Idle.offline_report.is_empty():
		_show_offline_dialog(Idle.offline_report)
		Idle.offline_report = {}

func _refresh_status() -> void:
	if not is_instance_valid(_money_label):
		return
	_money_label.text = Terms.t("money_label", {"amount": GameState.get_money()})
	var parts: PackedStringArray = []
	for key in DB.MATERIALS:
		parts.append("%s %d" % [Terms.material_name(key), GameState.get_material(key)])
	_materials_label.text = Terms.t("materials_label", {"list": "  ".join(parts)})

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
	_refresh_fleet()
	_refresh_idle_label()

func _build_home_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.term("tab_home")
	tab.add_theme_constant_override("separation", 14)

	tab.add_child(_title(Terms.t("home_welcome"), 22))
	var sortie := _button(Terms.t("sortie_button"), _show_map_select, 26)
	sortie.custom_minimum_size = Vector2(260, 72)
	sortie.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tab.add_child(sortie)

	_idle_label = _wrapped_label("")
	tab.add_child(_idle_label)
	_report_label = _wrapped_label(Terms.t("report_none"))
	tab.add_child(_report_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(spacer)

	if not GameState.is_storage_persistent():
		var warning := _wrapped_label(Terms.t("storage_warning"))
		warning.add_theme_color_override("font_color", Color("#f87171"))
		tab.add_child(warning)
	tab.add_child(_wrapped_label(Terms.t("backup_hint")))
	var backup_row := HBoxContainer.new()
	backup_row.add_theme_constant_override("separation", 12)
	tab.add_child(backup_row)
	backup_row.add_child(_button(Terms.t("backup_download" if _is_web else "backup_copy"), _export_backup))
	backup_row.add_child(_button(Terms.t("backup_restore"), _open_restore))
	_backup_message = Label.new()
	backup_row.add_child(_backup_message)

	if not _is_web:
		var minimize := CheckBox.new()
		minimize.text = Terms.t("minimize_on_close")
		minimize.button_pressed = GameState.get_setting("minimize_on_close", true)
		minimize.toggled.connect(func(on): GameState.set_setting("minimize_on_close", on))
		tab.add_child(minimize)
		var quit_button := _button(Terms.t("quit"), quit_game)
		quit_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tab.add_child(quit_button)
	return tab

# ───────── Save backups ─────────

func _export_backup() -> void:
	var text := GameState.export_text()
	if _is_web:
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "friend_fleet_save_%s.json" % stamp, "application/json")
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
			window.friendFleetPickFile = function (callback) {
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
	window.friendFleetPickFile(_file_picked_callback)

func _on_backup_file_picked(args: Array) -> void:
	if is_instance_valid(_restore_target) and not args.is_empty():
		_restore_target.text = str(args[0])

func _refresh_idle_label() -> void:
	if not is_instance_valid(_idle_label):
		return
	var stage := DB.get_stage(StringName(GameState.data.idle_stage_id))
	if not GameState.has_vanguard():
		_idle_label.text = Terms.t("idle_no_vanguard")
	elif stage == null:
		_idle_label.text = Terms.t("idle_not_deployed")
	else:
		_idle_label.text = Terms.t("idle_status", {
			"stage_name": stage.display_name, "seconds": Idle.BATTLE_SEC,
			"rate": roundi(Idle.estimate_win_rate(stage) * 100)})

func _on_idle_settled(report: Dictionary) -> void:
	if is_instance_valid(_report_label):
		_report_label.text = Terms.t("report_latest", {"summary": _describe_report(report)})

func _describe_report(report: Dictionary) -> String:
	var text := Terms.t("report_summary", {
		"battles": report.battles, "stage_name": report.stage, "wins": report.wins, "amount": report.money})
	text += _materials_text(report.materials)
	for item in report.drops:
		text += Terms.t("report_drop", {"item": item})
	return text

func _show_offline_dialog(report: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("welcome_title")
	dialog.dialog_text = Terms.t("welcome_body", {"summary": _describe_report(report)})
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(480, 0)
	_popup(dialog)
	_on_idle_settled(report)

# ───────── Map selection ─────────

func _show_map_select() -> void:
	var root := _new_screen()
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := _title(Terms.t("map_title"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button(Terms.t("back"), _show_main))

	var can_sortie := GameState.has_vanguard()
	if not can_sortie:
		root.add_child(_wrapped_label(Terms.t("map_need_vanguard")))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for stage in DB.stages:
		list.add_child(_map_panel(stage, can_sortie))

func _map_panel(stage: StageData, can_sortie: bool) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	info.add_child(_title(stage.display_name, 20))
	for row_key in ROWS:
		var enemies: Array[CharacterData] = stage.enemy_vanguard if row_key == "vanguard" else stage.enemy_rearguard
		if enemies.is_empty():
			continue
		var names: PackedStringArray = []
		for c in enemies:
			names.append(Terms.t("map_enemy_entry", {"name": c.display_name, "class": Terms.class_label(c.char_class)}))
		info.add_child(_wrapped_label(Terms.t("map_enemy_row", {"row": Terms.term(row_key), "list": ", ".join(names)})))
	var materials := ""
	for key in stage.reward_materials:
		var range_v: Vector2i = stage.reward_materials[key]
		materials += Terms.t("map_material", {"material": Terms.material_name(key), "min": range_v.x, "max": range_v.y})
	info.add_child(_wrapped_label(Terms.t("map_rewards", {"amount": stage.reward_money, "materials": materials})))
	if not stage.equipment_drops.is_empty():
		info.add_child(_wrapped_label(Terms.t("map_drops", {"chance": roundi(stage.drop_chance * 100)})))
	if can_sortie:
		info.add_child(_wrapped_label(Terms.t("map_win_rate", {"rate": roundi(Idle.estimate_win_rate(stage) * 100)})))

	var go := _button(Terms.t("map_go"), _show_battle.bind(stage), 20)
	go.custom_minimum_size = Vector2(140, 56)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.disabled = not can_sortie
	row.add_child(go)
	return panel

# ───────── Battle ─────────

func _show_battle(stage: StageData) -> void:
	var battle := Idle.sortie(stage)
	var root := _new_screen()
	root.add_child(_title(Terms.t("battle_title", {"name": stage.display_name}), 24))

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 32)
	root.add_child(sides)
	var widgets := []
	var columns := [VBoxContainer.new(), VBoxContainer.new()]
	for side in 2:
		var column: VBoxContainer = columns[side]
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(_title(Terms.t("battle_allies" if side == 0 else "battle_enemies"), 20))
		sides.add_child(column)
	for u in battle.units:
		var w := _battle_unit_widget(u)
		columns[u.side].add_child(w.root)
		widgets.append(w)

	var battle_log := RichTextLabel.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_log.scroll_following = true
	root.add_child(battle_log)
	var result_label := _wrapped_label("")
	result_label.add_theme_font_size_override("font_size", 20)
	root.add_child(result_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)
	var skip := _button(Terms.t("battle_skip"), _finish_playback)
	buttons.add_child(skip)
	var again := _button(Terms.t("battle_again"), _show_battle.bind(stage))
	var home := _button(Terms.t("battle_home"), _show_main)
	again.hide()
	home.hide()
	buttons.add_child(again)
	buttons.add_child(home)

	var timer := Timer.new()
	timer.wait_time = PLAYBACK_SEC
	timer.timeout.connect(_play_next_event)
	root.add_child(timer)
	_playback = {
		"battle": battle, "index": 0, "widgets": widgets, "log": battle_log, "timer": timer,
		"result_label": result_label, "skip": skip, "after": [again, home],
	}
	timer.start()

## Name, class and (vanguard only) an HP bar
func _battle_unit_widget(u: Dictionary) -> Dictionary:
	var box := VBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "%s (%s)" % [u.name, Terms.class_label(u.cls)]
	box.add_child(name_label)
	var w := {"root": box, "name": name_label, "bar": null, "hp": null}
	if u.vanguard:
		var row := HBoxContainer.new()
		box.add_child(row)
		var bar := ProgressBar.new()
		bar.max_value = u.max_hp
		bar.value = u.max_hp
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(180, 16)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var hp := Label.new()
		hp.text = "%d/%d" % [u.max_hp, u.max_hp]
		row.add_child(hp)
		w.bar = bar
		w.hp = hp
	else:
		var tag := Label.new()
		tag.text = Terms.t("battle_rear_tag")
		tag.modulate = Color(1, 1, 1, 0.6)
		box.add_child(tag)
	return w

func _play_next_event() -> void:
	if _playback.is_empty():
		return
	var events: Array = _playback.battle.events
	if _playback.index >= events.size():
		_finish_playback()
		return
	_apply_event(events[_playback.index])
	_playback.index += 1

func _apply_event(event: Dictionary) -> void:
	var widgets: Array = _playback.widgets
	for w in widgets:
		w.name.modulate = Color.WHITE
	widgets[event.actor].name.modulate = Color("#facc15")  # highlight who is acting
	for hit in event.hits:
		var w: Dictionary = widgets[hit.target]
		if w.bar:
			w.bar.value = hit.hp
			w.hp.text = "%d/%d" % [hit.hp, w.bar.max_value]
			if hit.hp == 0:
				w.root.modulate = Color(1, 1, 1, 0.35)
	_playback.log.append_text("\n".join(event.lines) + "\n")

func _finish_playback() -> void:
	if _playback.is_empty() or _playback.get("done", false):
		return
	_playback.done = true
	_playback.timer.stop()
	var events: Array = _playback.battle.events
	while _playback.index < events.size():
		_apply_event(events[_playback.index])
		_playback.index += 1
	_playback.log.append_text("\n".join(_playback.battle.end_lines))

	var report: Dictionary = _playback.battle.report
	if _playback.battle.win:
		var drops := ""
		for item in report.drops:
			drops += Terms.t("report_drop", {"item": item})
		var rewards := Terms.t("battle_rewards", {
			"amount": report.money, "materials": _materials_text(report.materials), "drops": drops})
		_playback.result_label.text = Terms.t("battle_victory", {"rewards": rewards})
	else:
		_playback.result_label.text = Terms.t("battle_defeat")
	_playback.skip.hide()
	for button in _playback.after:
		button.show()

# ───────── Fleet tab ─────────

func _build_fleet_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = Terms.term("tab_fleet")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var tab := VBoxContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 10)
	scroll.add_child(tab)

	tab.add_child(_title(Terms.t("fleet_title"), 22))
	tab.add_child(_wrapped_label(Terms.t("fleet_hint")))
	for row in ROWS:
		tab.add_child(_title("%s — %s" % [Terms.term(row), Terms.row_classes(row == "vanguard")], 18))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		tab.add_child(box)
		_fleet_rows[row] = box
	return scroll

func _refresh_fleet() -> void:
	for row in ROWS:
		_clear(_fleet_rows[row])
	for slot in GameState.FLEET_SLOTS:
		var vanguard := GameState.is_vanguard_slot(slot)
		var box: HBoxContainer = _fleet_rows[ROWS[0] if vanguard else ROWS[1]]
		var uid := GameState.fleet_uid(slot)
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
		card.add_action(Terms.t("slot_remove"), GameState.clear_fleet_slot.bind(slot, 0))
		box.add_child(card)

## Lists every owned friend; ones whose class can't use this row are shown but disabled
func _open_picker(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Terms.t("picker_title", {"row": Terms.row_name(slot)})
	dialog.ok_button_text = Terms.t("picker_ok")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(520, 340)
	var uids: Array[int] = []
	for o in GameState.data.owned:
		var uid := int(o.uid)
		var c := GameState.get_character(uid)
		if c == null:
			continue
		var text := "%s  [%s · %s]  %s%d" % [
			c.display_name, Terms.rarity_name(c.rarity), Terms.class_label(c.char_class), Terms.term("level"), int(o.level)]
		var current := GameState.fleet_slot_of(uid)
		if current >= 0:
			text += "  — " + Terms.t("in_fleet", {"row": Terms.row_name(current)})
		list.add_item(text)
		list.set_item_disabled(list.item_count - 1, not GameState.can_place(uid, slot))
		uids.append(uid)
	dialog.add_child(list)
	dialog.confirmed.connect(func(): _assign_from_list(dialog, list, uids, slot))
	list.item_activated.connect(func(index): _assign_from_list(dialog, list, uids, slot, index))
	_popup(dialog)

func _assign_from_list(dialog: Window, list: ItemList, uids: Array[int], slot: int, index: int = -1) -> void:
	if index < 0:
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		index = selected[0]
	if list.is_item_disabled(index):
		return
	GameState.set_fleet_slot(slot, uids[index])
	dialog.hide()

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
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var stats_label := Label.new()
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
	_update_stats_label(stats_label, uid)
	_popup(dialog)

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

# ───────── Recruit tab ─────────

func _build_gacha_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.term("tab_gacha")
	tab.add_theme_constant_override("separation", 10)

	for pool in DB.pools:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		tab.add_child(row)
		var info := Label.new()
		info.text = Terms.t("gacha_pool_info", {"name": pool.display_name, "cost": pool.cost, "rates": _rate_text(pool)})
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var pity := Label.new()
		_pity_labels[pool.id] = pity
		row.add_child(pity)
		for count in [1, 10]:
			row.add_child(_button(Terms.t("gacha_pull", {"count": count}), _on_pull.bind(pool, count)))

	_gacha_message = Label.new()
	tab.add_child(_gacha_message)
	var parts := _scroll_flow()
	tab.add_child(parts[0])
	_gacha_results = parts[1]
	_refresh_pity()
	return tab

func _rate_text(pool: GachaPool) -> String:
	var weights := {}
	for entry in pool.entries:
		if entry.character and entry.character.enabled:
			weights[entry.character.rarity] = pool.weight_for(entry.character.rarity)
	var total := 0
	for w in weights.values():
		total += w
	if total == 0:
		return Terms.t("gacha_no_characters")
	var parts: PackedStringArray = []
	for rarity in [CharacterData.Rarity.SSR, CharacterData.Rarity.SR, CharacterData.Rarity.R, CharacterData.Rarity.N]:
		if weights.get(rarity, 0) > 0:
			parts.append("%s %.1f%%" % [Terms.rarity_name(rarity), weights[rarity] * 100.0 / total])
	return " · ".join(parts)

func _refresh_pity() -> void:
	for pool in DB.pools:
		var label: Label = _pity_labels.get(pool.id)
		if label and pool.pity_threshold > 0:
			label.text = Terms.t("gacha_pity", {"count": GameState.get_pity(pool.id), "max": pool.pity_threshold})

func _on_pull(pool: GachaPool, count: int) -> void:
	if GameState.get_money() < pool.cost * count:
		_gacha_message.text = Terms.t("gacha_no_money", {"amount": pool.cost * count})
		return
	var results := Gacha.pull(pool, count)
	if results.is_empty():
		_gacha_message.text = Terms.t("gacha_empty_pool")
		return
	_gacha_message.text = Terms.t("gacha_result", {"count": count, "name": pool.display_name})
	_clear(_gacha_results)
	for r in results:
		var card := CharCard.new()
		card.set_character(r.character, Terms.t("new_badge") if r.is_new else "")
		_gacha_results.add_child(card)
	_refresh_pity()

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
