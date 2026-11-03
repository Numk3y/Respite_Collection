class_name CommissionTab
extends VBoxContainer
## Commission board, gacha dispatch style: a "COMMISSIONS" banner with how many jobs are running, then a two-column
## grid of job cards over drifting sparkles. Each card has a header strip in its status colour, chips for the shift
## length and requirement, its story, and reward chips (Money, materials, EXP, Credit Card chance). An open job
## shows a pulsing "+ Send a friend" slot; a running one shows the worker's portrait, a countdown and a striped
## progress bar that shimmers, with a glow at its leading edge. The friend picker is a grid of portrait tiles;
## friends who are busy or don't meet the requirement are dimmed with the reason.
## Send a friend (one job each; they can still battle meanwhile), and finished shifts pay out with a summary popup.
## While the tab is visible it checks once a second; shifts that ended while it was closed are paid by Main.

const STATUS_KEYS := ["in_world", "mirror_mode", "busy"]  # CommissionData.status_tag -> Terms/UITheme key
const AVATAR_SIZE := Vector2(56, 68)
const TILE_SIZE := Vector2(118, 196)

var _panels := {}  # commission id -> {"tag", "working", "open", "avatar", "worker_label", "bar", "state"}
var _summary: Label

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_build_header())
	var intro := Label.new()
	intro.text = Terms.t("commission_intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	add_child(intro)

	var stage := Control.new()  # the board with sparkles drifting behind it
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stage)
	var sparkles := CollectionTab.Sparkles.new()
	sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(sparkles)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var i := 0
	for c in DB.commissions:
		var card := _card(c)
		grid.add_child(card)
		card.modulate.a = 0.0
		card.create_tween().tween_property(card, "modulate:a", 1.0, 0.35).set_delay(0.08 * i)
		i += 1

	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)
	visibility_changed.connect(_tick)
	GameState.roster_changed.connect(_refresh)
	_refresh()

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.TEAL.darkened(0.15)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(UITheme.TEAL, 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_text(Terms.t("commission_banner"), 24, Color.WHITE))
	header.add_child(plate)
	_summary = _text("", 15, UITheme.TEXT)
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_summary)
	return header

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _card(c: CommissionData) -> Control:
	var accent: Color = UITheme.STATUS_COLORS[STATUS_KEYS[c.status_tag]]
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UITheme.glow_box(Color(0.05, 0.07, 0.12, 0.93), 12, 0, accent)
	style.border_color = accent.darkened(0.25)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	# Header strip: the job's name over a band in its status colour, the status chip on the right
	var strip := HeaderStrip.new(accent)
	box.add_child(strip)
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	strip.add_child(header)
	var title := _text(c.display_name, 20, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	header.add_child(title)
	var tag_holder := HBoxContainer.new()
	header.add_child(tag_holder)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	var body_margin := MarginContainer.new()
	for side in ["left", "right"]:
		body_margin.add_theme_constant_override("margin_" + side, 12)
	body_margin.add_theme_constant_override("margin_bottom", 12)
	body_margin.add_child(body)
	box.add_child(body_margin)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	body.add_child(chips)
	chips.add_child(UITheme.tag(Terms.t("commission_duration", {"duration": format_duration(c.duration_seconds)}), UITheme.CYAN))
	chips.add_child(UITheme.tag(Terms.t("commission_requirement", {"requirement": _requirement_text(c)}), Color("#a78bfa")))
	var description := Label.new()
	description.text = c.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 200
	description.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	description.add_theme_font_size_override("font_size", 14)
	body.add_child(description)

	var rewards := HFlowContainer.new()
	rewards.add_theme_constant_override("h_separation", 6)
	rewards.add_theme_constant_override("v_separation", 4)
	body.add_child(rewards)
	rewards.add_child(UITheme.tag(Terms.t("commission_reward_money", {"amount": c.reward_money}), UITheme.GOLD))
	for key in c.reward_materials:
		var range_v: Vector2i = c.reward_materials[key]
		rewards.add_child(UITheme.tag(Terms.t("commission_reward_material", {"material": Terms.material_name(key), "min": range_v.x, "max": range_v.y}), Color("#fb923c")))
	if c.exp_reward > 0:
		rewards.add_child(UITheme.tag(Terms.t("commission_reward_exp", {"amount": c.exp_reward}), Color("#93c5fd")))
	if c.credit_card_chance > 0.0:
		rewards.add_child(UITheme.tag(Terms.t("commission_reward_card", {"chance": "%.1f" % (c.credit_card_chance * 100)}), Color("#ffe259")))

	# Running: the worker's portrait, a countdown and the progress bar. Open: a slot to send someone.
	var working := HBoxContainer.new()
	working.add_theme_constant_override("separation", 10)
	body.add_child(working)
	var avatar := CharArt.new()
	avatar.custom_minimum_size = AVATAR_SIZE
	working.add_child(avatar)
	var progress := VBoxContainer.new()
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.alignment = BoxContainer.ALIGNMENT_CENTER
	progress.add_theme_constant_override("separation", 6)
	working.add_child(progress)
	var worker_label := _text("", 15, Color.WHITE)
	progress.add_child(worker_label)
	var bar := ShiftBar.new(accent)
	bar.max_value = c.duration_seconds
	progress.add_child(bar)
	var recall := Button.new()
	recall.text = Terms.t("commission_recall")
	recall.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	recall.add_theme_font_size_override("font_size", 13)
	recall.pressed.connect(_confirm_recall.bind(c))
	working.add_child(recall)
	var open := SendSlot.new(accent)
	open.pressed.connect(_open_picker.bind(c))
	body.add_child(open)

	_panels[c.id] = {"tag": tag_holder, "working": working, "open": open, "avatar": avatar, "worker_label": worker_label,
		"bar": bar, "state": ""}
	return panel

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
	var running := 0
	for c in DB.commissions:
		var ui: Dictionary = _panels[c.id]
		var job := Commissions.get_job(c)
		var working := not job.is_empty()
		running += int(working)
		ui.open.visible = not working
		ui.working.visible = working
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
	_summary.text = Terms.t("commission_summary", {"running": running, "total": DB.commissions.size()})

## Every owned friend as a portrait tile; busy friends and ones who don't meet the requirement are dimmed with the
## reason. Clicking a tile sends that friend.
func _open_picker(c: CommissionData) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("commission_picker_title", {"job": c.display_name})
	dialog.ok_button_text = Terms.t("commission_picker_cancel")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(5 * (TILE_SIZE.x + 10), minf(get_viewport_rect().size.y - 200.0, 440.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var entries: Array[Dictionary] = []
	for o in GameState.data.owned:
		var uid := int(o.uid)
		var friend := GameState.get_character(uid)
		if friend:
			entries.append({"uid": uid, "c": friend, "ok": Commissions.can_assign(c, uid)})
	entries.sort_custom(func(a, b): return a.ok and not b.ok if a.ok != b.ok else a.c.rarity > b.c.rarity)
	for e in entries:
		grid.add_child(_picker_tile(c, e.uid, e.c, e.ok, dialog))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _picker_tile(c: CommissionData, uid: int, friend: CharacterData, ok: bool, dialog: Window) -> Control:
	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.disabled = not ok
	tile.focus_mode = Control.FOCUS_NONE
	if not ok:
		tile.modulate = Color(1, 1, 1, 0.45)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var art := CharArt.new()
	art.custom_minimum_size = Vector2(TILE_SIZE.x - 12, 128)
	art.set_character(friend)
	box.add_child(art)
	var level := "%s%d" % [Terms.term("level"), int(GameState.get_owned(uid).level)]
	if not c.required_stat.is_empty():
		level += "  %s %d" % [Terms.stat_short(c.required_stat), GameState.get_unit_stats(uid)[c.required_stat]]
	var line := _text(level, 12, UITheme.TEXT)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	var reason := ""
	if Commissions.worker_commission(uid):
		reason = Terms.t("commission_busy")
	elif not Commissions.requirement_met(c, uid):
		reason = Terms.t("commission_unfit_short")
	var note := _text(reason if not reason.is_empty() else Terms.class_label(friend.char_class), 12,
		Color("#fca5a5") if not reason.is_empty() else UITheme.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	tile.pressed.connect(func(): _send(c, uid, dialog))
	return tile

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
		if int(r.get("bond", -1)) > 0:
			extras += Terms.t("commission_report_bond", {"bond": r.bond})
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

## The card's header: a band in the status colour fading to the right, behind the title
class HeaderStrip extends Control:
	var _color := Color.WHITE

	func _init(color: Color) -> void:
		_color = color
		custom_minimum_size.y = 44
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var steps := 6
		for i in steps:
			var x0 := size.x * i / steps
			var x1 := size.x * (i + 1) / steps
			var a0 := 0.55 * (1.0 - float(i) / steps)
			var a1 := 0.55 * (1.0 - float(i + 1) / steps)
			draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size.y), Vector2(x0, size.y)]),
				PackedColorArray([Color(_color, a0), Color(_color, a1), Color(_color, a1), Color(_color, a0)]))
		draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(_color, 0.6), 2.0)

## A shift's progress: a fill in the job's colour with diagonal stripes sliding along it and a glow at the edge
class ShiftBar extends Control:
	var max_value := 1.0
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var _color := Color.WHITE
	var _t := 0.0

	func _init(color: Color) -> void:
		_color = color
		custom_minimum_size.y = 14
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.5))
		var w := size.x * clampf(value / maxf(max_value, 1.0), 0.0, 1.0)
		if w > 0.0:
			draw_rect(Rect2(0, 0, w, size.y), _color.darkened(0.15))
			# Stripes sliding right, clipped to the filled part
			var step := 14.0
			var x := fmod(_t * 28.0, step) - step
			while x < w:
				var a := maxf(x, 0.0)
				var b := minf(x + 6.0, w)
				if b > a:
					draw_rect(Rect2(a, 0, b - a, size.y), Color(1, 1, 1, 0.16))
				x += step
			draw_rect(Rect2(0, 0, w, size.y * 0.4), Color(1, 1, 1, 0.18))
			var pulse := 0.5 + 0.5 * sin(_t * 5.0)
			UITheme.draw_glow(self, Vector2(w, size.y / 2.0), 16.0, Color(_color.lightened(0.4), 0.4 + 0.4 * pulse))
		draw_rect(r, Color(1, 1, 1, 0.15), false, 1.0)

## An open job's slot: a dashed outline that pulses, with "+ Send a friend"
class SendSlot extends Button:
	var _color := Color.WHITE
	var _t := 0.0

	func _init(color: Color) -> void:
		_color = color
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size.y = 64
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		text = "+  " + Terms.t("commission_send")
		add_theme_font_size_override("font_size", 18)
		add_theme_color_override("font_color", color.lightened(0.3))
		add_theme_color_override("font_hover_color", Color.WHITE)

	func _process(delta: float) -> void:
		_t += delta
		if is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var glow := 0.5 + 0.5 * sin(_t * 3.0)
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		draw_rect(r, Color(_color, 0.12 if is_hovered() else 0.06))
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for i in 4:
			draw_dashed_line(corners[i], corners[(i + 1) % 4], Color(_color, 0.4 + 0.4 * glow), 2.0, 10.0)
