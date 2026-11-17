class_name DailyWindow
extends AcceptDialog
## The Daily window (Daily autoload): a header with the streak and the time to the next reset, the 7-day check-in
## calendar with its Check In button, today's day-of-week bonus (and tomorrow's, as a teaser), then two tabs:
## Daily Missions (the activity bar with its five chests over today's missions) and Weekly Missions (each with its
## reward and a Claim button). Everything rebuilds from Daily on Daily.changed, so it stays right while open.

const FLAME := Color("#fb923c")
const DONE_GREEN := Color("#4ade80")

var _cells: Array[CheckinCell] = []
var _checkin_button: Button
var _streak_label: Label
var _reset_label: Label
var _week_reset_label: Label
var _bonus_label: Label
var _tomorrow_label: Label
var _activity: ActivityBar
var _activity_label: Label
var _daily_claim_all: Button
var _daily_list: VBoxContainer
var _weekly_list: VBoxContainer
var _weekly_claim_all: Button
var _got_label: Label
var _tabs: TabContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _streak_info: Label
var _ach_list: VBoxContainer
var _ach_claim_all: Button

func _init() -> void:
	title = Terms.t("daily_title")
	ok_button_text = Terms.t("beginner_close")
	exclusive = false  # other popups (shift reports, event rewards) can open over it without a clash
	# Everything scrolls inside a box capped to the screen (see _ready), so short windows still reach Close
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(840, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	_scroll.add_child(body)
	_body = body
	body.add_child(_build_header())
	body.add_child(_build_checkin())
	_streak_info = _label("", 13, UITheme.TEXT_DIM)
	_streak_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_streak_info)
	body.add_child(_build_bonus())
	_tabs = TabContainer.new()
	body.add_child(_tabs)
	_tabs.add_child(_build_daily_tab())
	_tabs.add_child(_build_weekly_tab())
	_tabs.add_child(_build_achievements_tab())
	Daily.changed.connect(_refresh)
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_update_timers)
	add_child(timer)
	_refresh()

## Show all of the content if the screen is tall enough. Containers settle their sizes over the next frames, so
## measure after that, then let the dialog grow to fit and centre it again.
func _ready() -> void:
	_scroll.custom_minimum_size = _body.get_combined_minimum_size()
	for i in 2:
		await get_tree().process_frame
	if not is_instance_valid(_body):
		return
	var need := _body.get_combined_minimum_size()
	var room := get_tree().root.get_visible_rect().size.y - 230.0  # the title bar, Close and a margin
	_scroll.custom_minimum_size = Vector2(need.x, minf(need.y, room))
	reset_size()
	if visible:
		popup_centered()

# ───────── Building ─────────

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e11d48").darkened(0.1)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 24
	style.content_margin_right = 28
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color("#e11d48", 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_label(Terms.t("daily_banner"), 24, Color.WHITE))
	header.add_child(plate)
	var flame := FlameIcon.new()
	flame.custom_minimum_size = Vector2(22, 28)
	flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(flame)
	_streak_label = _label("", 17, FLAME.lightened(0.3))
	_streak_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_streak_label)
	# What just came in (a gold line that fades), in the free space of the header
	_got_label = _label("", 15, UITheme.GOLD)
	_got_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_got_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_got_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_got_label.clip_text = true
	_got_label.modulate.a = 0.0
	header.add_child(_got_label)
	_reset_label = _label("", 14, UITheme.TEXT_DIM)
	_reset_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_reset_label)
	return header

func _build_checkin() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in Daily.CHECKIN_REWARDS.size():
		var cell := CheckinCell.new(i + 1, Daily.CHECKIN_REWARDS[i])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)
		_cells.append(cell)
	_checkin_button = Button.new()
	_checkin_button.custom_minimum_size = Vector2(130, 0)
	_checkin_button.theme_type_variation = &"PrimaryButton"
	_checkin_button.add_theme_font_size_override("font_size", 18)
	_checkin_button.pressed.connect(_check_in)
	row.add_child(_checkin_button)
	return row

func _build_bonus() -> Control:
	var panel := PanelContainer.new()
	var style := UITheme.box(Color(UITheme.GOLD, 0.08), Color(UITheme.GOLD, 0.6), 1, 10, 8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var head := _label(Terms.t("daily_today_bonus"), 13, UITheme.GOLD)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	_bonus_label = _label("", 19, Color.WHITE)
	_bonus_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_bonus_label)
	_tomorrow_label = _label("", 13, UITheme.TEXT_DIM)
	_tomorrow_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tomorrow_label)
	return panel

func _build_daily_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.t("daily_tab_daily")
	tab.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	tab.add_child(top)
	_activity_label = _label("", 17, UITheme.CYAN_BRIGHT)
	top.add_child(_activity_label)
	var hint := _label(Terms.t("daily_activity_hint"), 13, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.clip_text = true
	top.add_child(hint)
	_daily_claim_all = Button.new()
	_daily_claim_all.text = Terms.t("daily_claim_all")
	_daily_claim_all.pressed.connect(_claim_all_chests)
	top.add_child(_daily_claim_all)
	_activity = ActivityBar.new()
	_activity.chest_pressed.connect(_claim_chest)
	tab.add_child(_activity)
	_daily_list = VBoxContainer.new()
	_daily_list.add_theme_constant_override("separation", 5)
	tab.add_child(_daily_list)
	return tab

func _build_weekly_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.t("daily_tab_weekly")
	tab.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	tab.add_child(top)
	_week_reset_label = _label("", 14, UITheme.TEXT_DIM)
	_week_reset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_week_reset_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_week_reset_label)
	_weekly_claim_all = Button.new()
	_weekly_claim_all.text = Terms.t("daily_claim_all")
	_weekly_claim_all.pressed.connect(_claim_all_weekly)
	top.add_child(_weekly_claim_all)
	_weekly_list = VBoxContainer.new()
	_weekly_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weekly_list.add_theme_constant_override("separation", 5)
	tab.add_child(_weekly_list)
	return tab

## Achievements: a scrolling list (there are more than fit), each at its next tier
func _build_achievements_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = Terms.t("ach_tab")
	tab.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	tab.add_child(top)
	var hint := _label(Terms.t("ach_hint"), 14, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(hint)
	_ach_claim_all = Button.new()
	_ach_claim_all.text = Terms.t("daily_claim_all")
	_ach_claim_all.pressed.connect(_claim_all_achievements)
	top.add_child(_ach_claim_all)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 300
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(scroll)
	_ach_list = VBoxContainer.new()
	_ach_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_ach_list)
	return tab

## One mission line: title over a thin progress bar, the count, and whatever goes on the right
func _mission_row(title_text: String, progress: int, goal: int, done: bool, faded: bool) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := UITheme.box(Color(UITheme.INSET, 0.75), Color(DONE_GREEN, 0.5) if done and not faded else Color(UITheme.OUTLINE, 0.8), 1, 8, 6)
	style.content_margin_left = 12
	style.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	if faded:
		panel.modulate.a = 0.55
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var title_label := _label(title_text, 15, UITheme.TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.clip_text = true
	title_label.tooltip_text = title_text
	title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(title_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(130, 7)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = goal
	bar.value = progress
	row.add_child(bar)
	var count := _label("%d/%d" % [progress, goal], 15, DONE_GREEN if done else UITheme.TEXT_DIM)
	count.custom_minimum_size.x = 50
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(count)
	row.set_meta("panel", panel)
	return row

# ───────── Refresh ─────────

func _refresh() -> void:
	# Check-in: the cycle the latest (or next) check-in falls in
	var total := Daily.checkin_total()
	var checked := Daily.checked_in_today()
	var cycle := Daily.CHECKIN_REWARDS.size()
	var start := ((total - (1 if checked else 0)) / cycle) * cycle
	for i in _cells.size():
		var n := start + i
		_cells[i].claimed = n < total
		_cells[i].today = not checked and n == total
	_checkin_button.disabled = checked
	_checkin_button.text = Terms.t("daily_checked_in") if checked else Terms.t("daily_checkin")
	_checkin_button.add_theme_font_size_override("font_size", 13 if checked else 18)
	var streak := Daily.streak()
	_streak_label.text = (Terms.t("daily_streak", {"days": streak}) if streak > 0 else Terms.t("daily_streak_none")) \
		+ ("   " + Terms.t("daily_best_streak", {"days": Daily.best_streak()}) if Daily.best_streak() > 1 else "")
	_bonus_label.text = Daily.bonus_text()
	_tomorrow_label.text = Terms.t("daily_tomorrow", {"bonus": Daily.bonus_text(Daily.today() + 1)})
	_update_timers()

	# Daily missions and the bar
	var points := Daily.points()
	_activity_label.text = Terms.t("daily_activity", {"points": points, "max": Daily.MAX_POINTS})
	_activity.queue_redraw()
	_daily_claim_all.disabled = not range(Daily.CHESTS.size()).any(func(i): return Daily.chest_ready(i))
	if _daily_claim_all.disabled:
		_daily_claim_all.theme_type_variation = &""
	else:
		_daily_claim_all.theme_type_variation = &"PrimaryButton"
	for child in _daily_list.get_children():
		child.queue_free()
	for id: String in Daily.today_missions():
		var done := Daily.mission_done(id)
		var row := _mission_row(Daily.mission_title(id), Daily.mission_progress(id), Daily.mission_goal(id), done, false)
		var tag := UITheme.tag(Terms.t("daily_done") if done else Terms.t("daily_points", {"points": Daily.mission_points(id)}),
			DONE_GREEN if done else UITheme.CYAN)
		tag.custom_minimum_size.x = 64
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
		_daily_list.add_child(row.get_meta("panel"))

	# Weekly missions
	var any_weekly := false
	for child in _weekly_list.get_children():
		child.queue_free()
	for w: Dictionary in Daily.WEEKLY:
		var done := Daily.weekly_done(w)
		var claimed := Daily.weekly_claimed(w)
		any_weekly = any_weekly or (done and not claimed)
		var row := _mission_row(Daily.weekly_title(w), Daily.weekly_progress(w), int(w.goal), done, claimed)
		var reward := _label(Daily.reward_text(w.reward), 14, UITheme.GOLD)
		reward.custom_minimum_size.x = 215
		reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(reward)
		var claim := Button.new()
		claim.custom_minimum_size.x = 92
		claim.text = Terms.t("daily_claimed" if claimed else "daily_claim")
		claim.disabled = claimed or not done
		if done and not claimed:
			claim.theme_type_variation = &"PrimaryButton"
		claim.pressed.connect(_claim_weekly.bind(w))
		row.add_child(claim)
		_weekly_list.add_child(row.get_meta("panel"))
	_weekly_claim_all.disabled = not any_weekly
	_weekly_claim_all.theme_type_variation = &"PrimaryButton" if any_weekly else &""

	# Achievements: ready ones first, then the rest in list order, finished ones last
	for child in _ach_list.get_children():
		child.queue_free()
	var ordered: Array = Achievements.LIST.duplicate()
	ordered.sort_custom(func(a, b):
		var ka := 0 if Achievements.is_ready(a) else (2 if Achievements.is_complete(a) else 1)
		var kb := 0 if Achievements.is_ready(b) else (2 if Achievements.is_complete(b) else 1)
		return ka < kb if ka != kb else Achievements.LIST.find(a) < Achievements.LIST.find(b))
	for a: Dictionary in ordered:
		var complete := Achievements.is_complete(a)
		var can_claim := Achievements.is_ready(a)
		var target := Achievements.goal(a)
		var row := _mission_row(Achievements.title(a), mini(Achievements.value(a), target), target, can_claim, complete)
		var stars := TierPips.new(Achievements.tier(a), a.tiers.size())
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stars)
		var reward := _label(Terms.t("ach_complete") if complete else Daily.reward_text(Achievements.reward(a)), 14, UITheme.GOLD)
		reward.custom_minimum_size.x = 150
		reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(reward)
		var claim := Button.new()
		claim.custom_minimum_size.x = 92
		claim.text = Terms.t("daily_claim")
		claim.disabled = not can_claim
		claim.visible = not complete
		if can_claim:
			claim.theme_type_variation = &"PrimaryButton"
		claim.pressed.connect(_claim_achievement.bind(a))
		row.add_child(claim)
		_ach_list.add_child(row.get_meta("panel"))
	var any_ach := Achievements.claimable_count() > 0
	_ach_claim_all.disabled = not any_ach
	_ach_claim_all.theme_type_variation = &"PrimaryButton" if any_ach else &""

	# Point the tabs at what's waiting
	_tabs.set_tab_title(1, Terms.t("daily_tab_weekly") + (" (!)" if any_weekly else ""))
	_tabs.set_tab_title(2, Terms.t("ach_tab") + (" (%d)" % Achievements.claimable_count() if any_ach else ""))

	# The streak line: milestone, freeze and the free daily recruit
	var next := Daily.next_milestone()
	var info := PackedStringArray([Terms.t("daily_next_milestone", {"days": int(next.days), "reward": Daily.reward_text(next.reward)})])
	info.append(Terms.t("daily_freeze_ready" if Daily.freeze_ready() else "daily_freeze_used"))
	if Daily.free_pull_available():
		info.append(Terms.t("daily_free_pull_ready"))
	elif Daily.free_pull_unlocked():
		info.append(Terms.t("daily_free_pull_used"))
	else:
		info.append(Terms.t("daily_free_pull_locked", {"days": Daily.FREE_PULL_STREAK}))
	_streak_info.text = "   ·   ".join(info)

func _update_timers() -> void:
	_reset_label.text = Terms.t("daily_resets_in", {"time": Daily.format_time(Daily.seconds_to_reset())})
	_week_reset_label.text = Terms.t("daily_week_resets_in", {"time": Daily.format_time(Daily.seconds_to_weekly_reset())})

# ───────── Claiming ─────────

func _check_in() -> void:
	var result := Daily.check_in()
	if result.is_empty():
		return
	Sound.play("claim")
	var got := Terms.t("daily_checkin_got", {"day": result.day, "reward": Daily.reward_text(result.reward)})
	if not result.milestone.is_empty():
		got += "   " + Terms.t("daily_milestone_got", {"days": result.streak, "reward": Daily.reward_text(result.milestone)})
	elif result.froze:
		got += "   " + Terms.t("daily_freeze_saved")
	_show_got(got)
	_refresh()
	var index := (int(result.day) - 1) % _cells.size()
	_cells[index].pop()

func _claim_chest(i: int) -> void:
	var reward := Daily.claim_chest(i)
	if not reward.is_empty():
		Sound.play("claim")
		_activity.pop(i)
		_show_got(Terms.t("daily_got", {"reward": Daily.reward_text(reward)}))

func _claim_all_chests() -> void:
	var waiting: Array = range(Daily.CHESTS.size()).filter(func(i): return Daily.chest_ready(i))
	var reward := Daily.claim_all_chests()
	if not reward.is_empty():
		Sound.play("claim")
		for i in waiting:
			_activity.pop(i)
		_show_got(Terms.t("daily_got", {"reward": Daily.reward_text(_merge(reward))}))

func _claim_weekly(w: Dictionary) -> void:
	var reward := Daily.claim_weekly(w)
	if not reward.is_empty():
		Sound.play("claim")
		_show_got(Terms.t("daily_got", {"reward": Daily.reward_text(reward)}))

func _claim_all_weekly() -> void:
	var reward := Daily.claim_all_weekly()
	if not reward.is_empty():
		Sound.play("claim")
		_show_got(Terms.t("daily_got", {"reward": Daily.reward_text(_merge(reward))}))

func _claim_achievement(a: Dictionary) -> void:
	var reward := Achievements.claim(a)
	if not reward.is_empty():
		Sound.play("claim")
		_show_got(Terms.t("daily_got", {"reward": Daily.reward_text(reward)}))

func _claim_all_achievements() -> void:
	var reward := Achievements.claim_all()
	if not reward.is_empty():
		Sound.play("claim")
		_show_got(Terms.t("daily_got", {"reward": Daily.reward_text(_merge(reward))}))

## Adds up rewards of the same kind: [[money, 800], [money, 1500]] -> [[money, 2300]]
static func _merge(reward: Array) -> Array:
	var totals := {}
	var order: Array = []
	for item: Array in reward:
		if not totals.has(item[0]):
			order.append(item[0])
		totals[item[0]] = int(totals.get(item[0], 0)) + int(item[1])
	return order.map(func(kind): return [kind, totals[kind]])

## A gold line under the calendar saying what just came in; it fades after a few seconds
func _show_got(text: String) -> void:
	_got_label.text = text
	var t := _got_label.create_tween()
	_got_label.modulate.a = 1.0
	t.tween_interval(3.5)
	t.tween_property(_got_label, "modulate:a", 0.0, 0.8)

# ───────── Pieces ─────────

## One day of the check-in calendar: "Day N", the reward's icon and amount; a green tick once claimed, a pulsing
## gold edge on the day that's waiting. Day 7 has a gold frame. Drawn here (a container can't undo the pop).
class CheckinCell extends Control:
	var claimed := false:
		set(value):
			claimed = value
			queue_redraw()
	var today := false:
		set(value):
			today = value
			set_process(value)
			queue_redraw()
	var _day := 1
	var _reward: Array = []
	var _pop := 0.0:
		set(value):
			_pop = value
			queue_redraw()
	var _time := 0.0

	func _init(day: int, reward: Array) -> void:
		_day = day
		_reward = reward
		custom_minimum_size = Vector2(80, 104)
		mouse_filter = Control.MOUSE_FILTER_PASS
		tooltip_text = Daily.reward_text(reward)
		set_process(false)

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func pop() -> void:
		_pop = 1.0
		create_tween().tween_property(self, "_pop", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var big := _day == Daily.CHECKIN_REWARDS.size()
		var k := 1.0 + 0.18 * _pop
		draw_set_transform(size * 0.5 * (1.0 - k), 0.0, Vector2(k, k))
		var rect := Rect2(Vector2.ZERO, size)
		var edge := UITheme.GOLD if big else Color(UITheme.CYAN, 0.35)
		var bg := Color("#2a2410") if big else UITheme.CARD
		if today:
			var pulse := 0.5 + 0.5 * sin(_time * 4.0)
			UITheme.draw_glow(self, size * 0.5, size.x * (0.65 + 0.08 * pulse), Color(UITheme.GOLD, 0.25))
			edge = UITheme.GOLD.lightened(0.3 * pulse)
		var style := UITheme.box(bg if not claimed else Color(UITheme.INSET, 0.9), edge, 3 if today else (2 if big else 1), 10)
		draw_style_box(style, rect)
		var font := ThemeDB.fallback_font
		var label := Terms.t("daily_checkin_day", {"day": _day})
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2((size.x - w) * 0.5, 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			UITheme.GOLD if (today or big) else UITheme.TEXT_DIM)
		# The reward: icon(s) in the middle, the amount under them
		var item: Array = _reward[0]
		var kind := String(item[0])
		var icon_r := 17.0 if not big else 20.0
		RewardIcon.draw_icon(self, Vector2(size.x * 0.5, 50), icon_r, kind)
		var amount := "x" + Terms.number(int(item[1]))
		var aw := font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline(font, Vector2((size.x - aw) * 0.5, 90), amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2((size.x - aw) * 0.5, 90), amount, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		if claimed:
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(0, 0, 0, 0.45))
			var c := Vector2(size.x * 0.5, 52)
			draw_circle(c, 17, Color(DONE_GREEN, 0.9))
			draw_polyline(PackedVector2Array([c + Vector2(-8, 0), c + Vector2(-2, 6), c + Vector2(9, -6)]), Color("#052e16"), 4.0, true)
		draw_set_transform(Vector2.ZERO)

## Draws a reward kind's icon (the same pictures as the header's currency chips)
class RewardIcon extends RefCounted:
	static func draw_icon(ci: CanvasItem, center: Vector2, radius: float, kind: String) -> void:
		CurrencyChip.draw_kind(ci, center, radius, kind)

## The activity bar: a track that fills with today's points and five chests along it. A chest that's ready bobs
## and glows (click it to open); an opened one sits with its lid up and a tick. Under each: its points and reward.
class ActivityBar extends Control:
	signal chest_pressed(index: int)

	const PAD := 46.0
	const TRACK_Y := 36.0
	var _time := 0.0
	var _pops := {}  # chest index -> 0-1 pop

	func _init() -> void:
		custom_minimum_size = Vector2(0, 100)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		_time += delta
		if range(Daily.CHESTS.size()).any(func(i): return Daily.chest_ready(i)) or not _pops.is_empty():
			queue_redraw()

	func pop(i: int) -> void:
		_pops[i] = 1.0
		var t := create_tween()
		t.tween_method(func(v: float): _pops[i] = v, 1.0, 0.0, 0.5)
		t.tween_callback(func(): _pops.erase(i))

	func _chest_pos(i: int) -> Vector2:
		var share := float(Daily.CHESTS[i].points) / Daily.MAX_POINTS
		return Vector2(PAD + (size.x - PAD * 2.0) * share, TRACK_Y)

	func _chest_at(at: Vector2) -> int:
		for i in Daily.CHESTS.size():
			if at.distance_to(_chest_pos(i)) < 26.0:
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var i := _chest_at(event.position)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if i >= 0 and Daily.chest_ready(i) else Control.CURSOR_ARROW
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var i := _chest_at(event.position)
			if i >= 0 and Daily.chest_ready(i):
				chest_pressed.emit(i)
				accept_event()

	func _get_tooltip(at: Vector2) -> String:
		var i := _chest_at(at)
		return Daily.reward_text(Daily.CHESTS[i].reward) if i >= 0 else ""

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var share := float(Daily.points()) / Daily.MAX_POINTS
		var track := Rect2(PAD, TRACK_Y - 5, size.x - PAD * 2.0, 10)
		draw_style_box(UITheme.box(UITheme.INSET, Color(UITheme.CYAN, 0.2), 1, 5), track)
		if share > 0.0:
			var fill := Rect2(track.position, Vector2(track.size.x * share, track.size.y))
			draw_style_box(UITheme.glow_box(UITheme.CYAN, 5), fill)
			draw_rect(Rect2(fill.position + Vector2(2, 1), Vector2(maxf(fill.size.x - 4, 0), 3)), Color(1, 1, 1, 0.25))
		# "0" at the start of the track
		draw_string(font, Vector2(PAD - 26, TRACK_Y + 5), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT_DIM)
		for i in Daily.CHESTS.size():
			var pos := _chest_pos(i)
			var is_ready := Daily.chest_ready(i)
			var opened := Daily.chest_claimed(i)
			var reached := Daily.points() >= int(Daily.CHESTS[i].points)
			var last := i == Daily.CHESTS.size() - 1
			var color := UITheme.GOLD if is_ready or (last and not opened) else (Color("#64748b") if not reached else Color("#a3e635"))
			var bob := sin(_time * 5.0 + i) * 2.5 if is_ready else 0.0
			var k := 1.0 + 0.3 * float(_pops.get(i, 0.0)) + (0.15 if last else 0.0)
			if is_ready:
				UITheme.draw_glow(self, pos, 30.0 + 4.0 * sin(_time * 4.0), Color(UITheme.GOLD, 0.35))
			_draw_chest(pos + Vector2(0, bob), k, color, opened)
			# Points, then the reward's first item under the track
			var pts := str(int(Daily.CHESTS[i].points))
			var pw := font.get_string_size(pts, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(pos.x - pw * 0.5, TRACK_Y + 34), pts, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				UITheme.CYAN_BRIGHT if reached else UITheme.TEXT_DIM)
			var reward: Array = Daily.CHESTS[i].reward
			var text := Daily.item_text(reward[0]) + (" +" if reward.size() > 1 else "")
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(pos.x - tw * 0.5, TRACK_Y + 52), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				UITheme.TEXT_DIM if opened else UITheme.GOLD.lerp(UITheme.TEXT, 0.4))

	## A little chest: a body with a band and lock, and a lid (lifted and tilted once opened)
	func _draw_chest(center: Vector2, k: float, color: Color, opened: bool) -> void:
		var w := 30.0 * k
		var h := 18.0 * k
		var body := Rect2(center.x - w * 0.5, center.y - h * 0.3, w, h)
		draw_rect(Rect2(body.position + Vector2(2, 3), body.size), Color(0, 0, 0, 0.4))
		draw_rect(body, color.darkened(0.25))
		draw_rect(Rect2(body.position.x, body.position.y + h * 0.35, w, h * 0.18), color.darkened(0.5))
		var lid_h := 9.0 * k
		if opened:
			var lid := PackedVector2Array([Vector2(body.position.x - 2, body.position.y - lid_h - 6),
				Vector2(body.end.x - 6, body.position.y - lid_h - 12), Vector2(body.end.x - 4, body.position.y - 6),
				Vector2(body.position.x, body.position.y)])
			draw_colored_polygon(lid, color)
			draw_rect(Rect2(body.position.x + 3, body.position.y, w - 6, 3), Color(1, 1, 0.8, 0.5))
			var c := center + Vector2(0, h * 0.2)
			draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-1, 5), c + Vector2(7, -5)]), Color.WHITE, 3.0, true)
		else:
			draw_rect(Rect2(body.position.x - 1, body.position.y - lid_h, w + 2, lid_h), color)
			draw_rect(Rect2(body.position.x - 1, body.position.y - lid_h, w + 2, 2), Color(1, 1, 1, 0.35))
			draw_rect(Rect2(center.x - 3 * k, body.position.y - 2 * k, 6 * k, 7 * k), color.lightened(0.5))
		draw_rect(body, Color(0, 0, 0, 0.5), false, 1.0)

## An achievement's tiers as a row of small diamonds: filled for each tier claimed
class TierPips extends Control:
	var _done := 0
	var _total := 1

	func _init(done: int, total: int) -> void:
		_done = done
		_total = total
		custom_minimum_size = Vector2(total * 13 + 2, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in _total:
			var c := Vector2(7 + i * 13, 7)
			var diamond := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
			if i < _done:
				draw_colored_polygon(diamond, UITheme.GOLD)
			else:
				diamond.append(diamond[0])
				draw_polyline(diamond, Color(UITheme.GOLD, 0.45), 1.2, true)

## A little flame next to the streak
class FlameIcon extends Control:
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var flicker := 0.06 * sin(_time * 9.0)
		var outer := _drop(Vector2(size.x * 0.5, size.y * 0.66), size.x * 0.46, size.y * 0.32,
			Vector2(size.x * (0.58 + flicker), 0.0))
		var inner := _drop(Vector2(size.x * 0.5, size.y * 0.78), size.x * 0.24, size.y * 0.18,
			Vector2(size.x * 0.5, size.y * (0.4 - flicker)))
		var streak := Daily.streak()
		var hot := FLAME if streak > 0 else Color("#475569")
		draw_colored_polygon(outer, hot)
		draw_colored_polygon(inner, Color("#fde68a") if streak > 0 else Color("#64748b"))

	## A teardrop: the lower half of an ellipse (right, bottom, left) and then up to `tip`
	static func _drop(center: Vector2, rx: float, ry: float, tip: Vector2) -> PackedVector2Array:
		var points := PackedVector2Array()
		for i in 17:
			var a := PI * i / 16.0
			points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
		points.append(tip)
		return points
