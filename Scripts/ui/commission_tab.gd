class_name CommissionTab
extends VBoxContainer
## Commission board: every part-time job with its shift length, requirement and pay. Send a friend (one job each;
## they can still battle meanwhile), watch the countdown, and finished shifts pay out with a summary popup.
## While the tab is visible it checks once a second; shifts that ended while it was closed are paid by Main.

const STATUS_KEYS := ["in_world", "mirror_mode", "busy"]  # CommissionData.status_tag -> Terms/UITheme key
const AVATAR_SIZE := Vector2(48, 56)

var _panels := {}  # commission id -> {"tag": HBoxContainer, "worker_row", "avatar", "worker_label", "bar", "send", "recall"}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var intro := Label.new()
	intro.text = Terms.t("commission_intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for c in DB.commissions:
		list.add_child(_panel(c))

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)
	visibility_changed.connect(_tick)
	GameState.roster_changed.connect(_refresh)
	_refresh()

func _panel(c: CommissionData) -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	# Title with the status chip on the right
	var header := HBoxContainer.new()
	info.add_child(header)
	var title := Label.new()
	title.text = c.display_name
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var tag_holder := HBoxContainer.new()
	header.add_child(tag_holder)

	var description := _label(c.description)
	description.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	info.add_child(description)
	var requirement := _label("%s    %s" % [
		Terms.t("commission_duration", {"duration": format_duration(c.duration_seconds)}),
		Terms.t("commission_requirement", {"requirement": _requirement_text(c)})])
	requirement.add_theme_color_override("font_color", UITheme.CYAN)
	info.add_child(requirement)
	var materials := ""
	for key in c.reward_materials:
		var range_v: Vector2i = c.reward_materials[key]
		materials += Terms.t("commission_material", {"material": Terms.material_name(key), "min": range_v.x, "max": range_v.y})
	info.add_child(_label(Terms.t("commission_pay", {"amount": c.reward_money, "materials": materials})))
	if c.credit_card_chance > 0.0:
		var rare := _label(Terms.t("commission_card_chance", {"chance": "%.1f" % (c.credit_card_chance * 100)}))
		rare.add_theme_color_override("font_color", UITheme.GOLD)
		info.add_child(rare)

	# While someone works: their avatar next to a glowing cyan progress bar
	var worker_row := HBoxContainer.new()
	worker_row.add_theme_constant_override("separation", 10)
	info.add_child(worker_row)
	var avatar := CharArt.new()
	avatar.custom_minimum_size = AVATAR_SIZE
	worker_row.add_child(avatar)
	var progress := VBoxContainer.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	worker_row.add_child(progress)
	var worker_label := _label("")
	progress.add_child(worker_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = c.duration_seconds
	progress.add_child(bar)

	var buttons := VBoxContainer.new()
	buttons.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(buttons)
	var send := Button.new()
	send.text = Terms.t("commission_send")
	send.custom_minimum_size = Vector2(150, 44)
	send.pressed.connect(_open_picker.bind(c))
	buttons.add_child(send)
	var recall := Button.new()
	recall.text = Terms.t("commission_recall")
	recall.pressed.connect(_confirm_recall.bind(c))
	buttons.add_child(recall)
	_panels[c.id] = {"tag": tag_holder, "worker_row": worker_row, "avatar": avatar, "worker_label": worker_label,
		"bar": bar, "send": send, "recall": recall, "state": ""}
	return panel

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _requirement_text(c: CommissionData) -> String:
	var parts: PackedStringArray = []
	if c.required_class >= 0:
		parts.append(Terms.t("commission_req_class", {"class": Terms.class_label(c.required_class)}))
	if not c.required_stat.is_empty():
		parts.append(Terms.t("commission_req_stat", {"stat": Terms.stat_name(c.required_stat), "value": c.required_value}))
	return Terms.t("commission_req_any") if parts.is_empty() else ", ".join(parts)

## "8h", "1h 30m", "12m 5s" ...
static func format_duration(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if h > 0:
		return "%dh" % h if m == 0 else "%dh %dm" % [h, m]
	if m > 0:
		return "%dm" % m if s == 0 else "%dm %ds" % [m, s]
	return "%ds" % s

func _tick() -> void:
	if not is_visible_in_tree():
		return
	var reports := Commissions.resolve_finished()
	if not reports.is_empty():
		show_reports(self, reports)
	_refresh()

func _refresh() -> void:
	for c in DB.commissions:
		var ui: Dictionary = _panels[c.id]
		var job := Commissions.get_job(c)
		var working := not job.is_empty()
		ui.send.visible = not working
		ui.recall.visible = working
		ui.worker_row.visible = working
		var worker: CharacterData = GameState.get_character(int(job.get("uid", 0))) if working else null
		# Swap the status chip and avatar only when the worker changes, not on every 1-second tick
		var state := "%s:%s" % [working, worker.id if worker else &""]
		if ui.state != state:
			ui.state = state
			for child in ui.tag.get_children():
				child.queue_free()
			var key: String = STATUS_KEYS[c.status_tag] if working else "open"
			ui.tag.add_child(UITheme.tag(Terms.t("status_" + key), UITheme.STATUS_COLORS[key]))
			if worker:
				ui.avatar.set_character(worker)
		if working:
			var left := Commissions.time_left(c)
			ui.worker_label.text = "%s  ·  %s" % [worker.display_name if worker else "?",
				Terms.t("commission_time_left", {"time": format_duration(left)})]
			ui.bar.value = c.duration_seconds - left

## Every owned friend; ones already working or not meeting the requirement are listed but disabled
func _open_picker(c: CommissionData) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Terms.t("commission_picker_title", {"job": c.display_name})
	dialog.ok_button_text = Terms.t("commission_picker_ok")
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(520, 320)
	var uids: Array[int] = []
	for o in GameState.data.owned:
		var uid := int(o.uid)
		var friend := GameState.get_character(uid)
		if friend == null:
			continue
		var text := "%s  [%s]  %s%d" % [friend.display_name, Terms.class_label(friend.char_class), Terms.term("level"), int(o.level)]
		if not c.required_stat.is_empty():
			text += "  %s %d" % [Terms.stat_short(c.required_stat), GameState.get_unit_stats(uid)[c.required_stat]]
		var busy := Commissions.worker_commission(uid)
		if busy:
			text += "  (%s)" % Terms.t("commission_busy")
		elif not Commissions.requirement_met(c, uid):
			text += "  (%s)" % Terms.t("commission_unfit")
		list.add_item(text)
		list.set_item_disabled(list.item_count - 1, not Commissions.can_assign(c, uid))
		uids.append(uid)
	dialog.add_child(list)
	dialog.confirmed.connect(func(): _send_selected(c, list, uids))
	list.item_activated.connect(func(index): _send(c, uids[index], dialog))
	_popup(dialog)

func _send_selected(c: CommissionData, list: ItemList, uids: Array[int]) -> void:
	var selected := list.get_selected_items()
	if not selected.is_empty():
		_send(c, uids[selected[0]], null)

func _send(c: CommissionData, uid: int, dialog: Window) -> void:
	if Commissions.start(c, uid):
		_refresh()
		if dialog:
			dialog.queue_free()

func _confirm_recall(c: CommissionData) -> void:
	var worker := GameState.get_character(int(Commissions.get_job(c).get("uid", 0)))
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = Terms.t("commission_recall_confirm", {"name": worker.display_name if worker else "?"})
	dialog.confirmed.connect(func(): _recall(c))
	_popup(dialog)

func _recall(c: CommissionData) -> void:
	Commissions.cancel(c)
	_refresh()

func _popup(dialog: Window) -> void:
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

## Summary popup for finished shifts; used here and by Main when shifts finished while the game was closed
static func show_reports(parent: Node, reports: Array[Dictionary]) -> void:
	var lines: PackedStringArray = []
	for r in reports:
		var extras := ""
		for key in r.materials:
			if r.materials[key] > 0:
				extras += Terms.t("report_material", {"material": Terms.material_name(key), "amount": r.materials[key]})
		if r.credit_cards > 0:
			extras += Terms.t("commission_report_cards", {"amount": r.credit_cards, "card_word": Terms.credit_card_word(r.credit_cards)})
		if r.exp > 0:
			extras += Terms.t("commission_report_exp", {"amount": r.exp})
		if r.get("friendship", 0) > 0:
			extras += Terms.t("commission_report_friendship", {"amount": r.friendship})
		if r.level > 0:
			extras += Terms.t("commission_report_level", {"lv": r.level})
		lines.append(Terms.t("commission_report", {
			"worker": r.worker, "job": r.commission, "amount": "%+d" % r.money, "extras": extras}))
		if not r.incident.is_empty():
			lines.append("    " + r.incident)
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("commission_report_title")
	dialog.dialog_text = "\n".join(lines)
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(560, 0)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	parent.add_child(dialog)
	dialog.popup_centered()
