class_name EventTab
extends VBoxContainer
## The Event tab, laid out like a gacha limited-event page. Shows the live event from the world boss server
## (WorldBoss autoload), so it needs a connection: without one, or with no event running, it just says so.
## A live event:
## - Hero: the event's key art across the top with a LIMITED EVENT tag, the big title, its story, the countdown,
##   and a mission track (one diamond per mission, filled as they're cleared) beside the Event Missions button.
## - World Boss: the boss's picture, name and the shared HP bar every player is draining (with a trail and a
##   DEFEATED stamp), today's attempts as pips, your damage and rank, the CHALLENGE button (opens once every
##   mission is cleared) and what the boss pays out, as currency chips per tier (everyone / 1st / 2nd / 3rd).
## - Leaderboard: the top 10 (gold / silver / bronze medals for the podium, your row highlighted), and the
##   latest hits.
## The first visit asks for the name other players will see. While visible it refreshes every REFRESH_SEC.
## Main listens to missions_pressed / challenge_pressed, and to event_over to pay out rewards.

signal missions_pressed(event: EventData)
signal challenge_pressed(event: EventData)
signal event_over  # the event shown has ended (boss defeated or out of time)

const REFRESH_SEC := 20.0
const RANK_COLORS := [Color("#ffd75e"), Color("#d8dee9"), Color("#e0a060")]  # 1st, 2nd, 3rd
const BOSS_RED := Color("#ef4444")
const LIST_FONT := 14
const RECENT_MAX := 6

var _event: EventData
var _data := {}  # the server's last answer: {event, top, recent, me, server_time}
var _fetched_at := 0  # Time.get_ticks_msec() when _data arrived
var _loading := false
var _over_sent := -1  # event id event_over was last emitted for

var _message: Label
var _body: VBoxContainer
var _hero: Hero
var _event_name: Label
var _description: Label
var _time_left: Label
var _track: MissionTrack
var _mission_progress: Label
var _missions_button: Button
var _boss_art: TextureRect
var _boss_name: Label
var _boss_bar: BossBar
var _attempts: Pips
var _attempts_label: Label
var _chips: HBoxContainer
var _challenge: Button
var _challenge_note: Label
var _join_row: HBoxContainer
var _name_edit: LineEdit
var _rewards: GridContainer  # one cell per tier, two tiers per row
var _reward_rule: Label
var _top_list: VBoxContainer
var _recent_list: VBoxContainer

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_message = _text("", 18, UITheme.TEXT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_message)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.visible = false
	add_child(_body)
	_body.add_child(_build_hero())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(row)
	row.add_child(_build_boss_panel())
	row.add_child(_build_board_panel())

	var refresh := Timer.new()
	refresh.wait_time = REFRESH_SEC
	refresh.autostart = true
	refresh.timeout.connect(func():
		if is_visible_in_tree():
			refresh_now())
	add_child(refresh)
	var clock := Timer.new()
	clock.wait_time = 1.0
	clock.autostart = true
	clock.timeout.connect(_update_clock)
	add_child(clock)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			refresh_now())
	_show_message(Terms.t("event_loading"))

func _text(text: String, font_size: int, color: Color, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", outline)
	return label

func _panel(accent: Color) -> Array:
	var panel := PanelContainer.new()
	var style := UITheme.box(Color(0.04, 0.05, 0.1, 0.92), Color(accent, 0.45), 1, 12, 14)
	style.border_width_top = 3
	style.border_color = Color(accent, 0.75)
	style.shadow_color = Color(accent, 0.18)
	style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return [panel, box]

## A small all-caps section heading with an accent bar in front
func _heading(text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var bar := ColorRect.new()
	bar.color = color
	bar.custom_minimum_size = Vector2(4, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(_text(text, 14, color.lightened(0.3)))
	return row

# ───────── Hero ─────────

func _build_hero() -> Control:
	_hero = Hero.new()
	_hero.custom_minimum_size.y = 176
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_hero.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	var tag := PanelContainer.new()
	var tag_style := StyleBoxFlat.new()
	tag_style.bg_color = UITheme.VIOLET
	tag_style.skew = Vector2(0.3, 0)
	tag_style.content_margin_left = 16
	tag_style.content_margin_right = 18
	tag_style.shadow_color = Color(UITheme.VIOLET, 0.5)
	tag_style.shadow_size = 8
	tag.add_theme_stylebox_override("panel", tag_style)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tag.add_child(_text(Terms.t("event_limited"), 15, Color.WHITE))
	left.add_child(tag)
	_event_name = _text("", 46, Color.WHITE, 10)
	_event_name.add_theme_color_override("font_shadow_color", Color(UITheme.VIOLET, 0.8))
	_event_name.add_theme_constant_override("shadow_outline_size", 16)
	_event_name.add_theme_constant_override("shadow_offset_x", 0)
	_event_name.add_theme_constant_override("shadow_offset_y", 0)
	left.add_child(_event_name)
	_description = _text("", 14, Color("#e2e8f0"), 4)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 280
	_description.max_lines_visible = 3
	left.add_child(_description)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size.x = 330
	columns.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(top)
	var clock := PanelContainer.new()
	var clock_style := UITheme.box(Color(0, 0, 0, 0.6), Color(UITheme.GOLD, 0.7), 1, 16)
	clock_style.content_margin_left = 14
	clock_style.content_margin_right = 14
	clock_style.content_margin_top = 4
	clock_style.content_margin_bottom = 4
	clock.add_theme_stylebox_override("panel", clock_style)
	_time_left = _text("", 16, UITheme.GOLD)
	clock.add_child(_time_left)
	top.add_child(clock)
	var refresh := Button.new()
	refresh.text = Terms.t("event_refresh")
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.add_theme_font_size_override("font_size", 14)
	refresh.pressed.connect(refresh_now)
	top.add_child(refresh)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(gap)
	# The mission track over a dark plate, with the button under it
	var plate := PanelContainer.new()
	var plate_style := UITheme.box(Color(0.02, 0.02, 0.06, 0.72), Color(UITheme.VIOLET, 0.6), 1, 12, 8)
	plate.add_theme_stylebox_override("panel", plate_style)
	right.add_child(plate)
	var missions := VBoxContainer.new()
	missions.add_theme_constant_override("separation", 6)
	plate.add_child(missions)
	_mission_progress = _text("", 14, Color("#ddd6fe"))
	missions.add_child(_mission_progress)
	_track = MissionTrack.new()
	_track.custom_minimum_size.y = 22
	missions.add_child(_track)
	_missions_button = Button.new()
	_missions_button.text = Terms.t("event_missions_button")
	_missions_button.focus_mode = Control.FOCUS_NONE
	_missions_button.custom_minimum_size.y = 40
	_missions_button.add_theme_font_size_override("font_size", 19)
	_violet_button(_missions_button)
	_missions_button.pressed.connect(func():
		if _event:
			missions_pressed.emit(_event))
	missions.add_child(_missions_button)
	# The hero isn't a container, so keep it at least as tall as what's inside (e.g. a three-line story)
	margin.minimum_size_changed.connect(func():
		_hero.custom_minimum_size.y = maxf(176.0, margin.get_combined_minimum_size().y))
	return _hero

func _violet_button(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var s := UITheme.box(UITheme.VIOLET, Color("#c4b5fd"), 1, 10)
		match state:
			"hover":
				s.bg_color = UITheme.VIOLET.lightened(0.15)
				s.shadow_color = Color(UITheme.VIOLET, 0.6)
				s.shadow_size = 10
			"pressed":
				s.bg_color = UITheme.VIOLET.darkened(0.2)
			"disabled":
				s.bg_color = Color("#2a2540")
				s.border_color = Color("#4c4470")
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)

# ───────── World Boss ─────────

func _build_boss_panel() -> Control:
	var parts := _panel(BOSS_RED)
	var panel: PanelContainer = parts[0]
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = parts[1]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)

	# The boss's picture in a red-lit frame
	var frame := PanelContainer.new()
	var frame_style := UITheme.box(Color(0.1, 0.02, 0.03), BOSS_RED, 2, 10, 0)
	frame_style.shadow_color = Color(BOSS_RED, 0.45)
	frame_style.shadow_size = 12
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.custom_minimum_size = Vector2(140, 164)
	frame.clip_contents = true
	row.add_child(frame)
	_boss_art = TextureRect.new()
	_boss_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	frame.add_child(_boss_art)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	info.add_child(title)
	title.add_child(UITheme.tag(Terms.t("event_world_boss"), BOSS_RED))
	_boss_name = _text("", 26, Color("#fecaca"), 6)
	title.add_child(_boss_name)
	_boss_bar = BossBar.new()
	_boss_bar.custom_minimum_size.y = 34
	info.add_child(_boss_bar)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	info.add_child(stats)
	_attempts_label = _text("", 14, UITheme.CYAN)
	stats.add_child(_attempts_label)
	_attempts = Pips.new()
	_attempts.custom_minimum_size = Vector2(110, 20)
	_attempts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.add_child(_attempts)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	stats.add_child(_chips)

	var action := HBoxContainer.new()
	action.add_theme_constant_override("separation", 12)
	info.add_child(action)
	_challenge = Button.new()
	_challenge.text = Terms.t("event_challenge")
	_challenge.focus_mode = Control.FOCUS_NONE
	_challenge.custom_minimum_size = Vector2(230, 54)
	_challenge.add_theme_font_size_override("font_size", 24)
	_challenge_style(_challenge)
	_challenge.pressed.connect(func():
		if _event:
			challenge_pressed.emit(_event))
	action.add_child(_challenge)
	_challenge_note = _text("", 14, Color("#fca5a5"))
	_challenge_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action.add_child(_challenge_note)
	# First visit: pick the name other players see, in place of the Challenge button
	_join_row = HBoxContainer.new()
	_join_row.add_theme_constant_override("separation", 8)
	_join_row.visible = false
	info.add_child(_join_row)
	_join_row.add_child(_text(Terms.t("event_name_prompt"), 15, UITheme.TEXT))
	_name_edit = LineEdit.new()
	_name_edit.max_length = WorldBoss.NAME_MAX
	_name_edit.placeholder_text = Terms.t("event_name_placeholder")
	_name_edit.custom_minimum_size.x = 180
	_name_edit.text_submitted.connect(func(_t): _join())
	_join_row.add_child(_name_edit)
	var join := Button.new()
	join.text = Terms.t("event_join")
	join.theme_type_variation = &"PrimaryButton"
	join.pressed.connect(_join)
	_join_row.add_child(join)

	# What the boss pays out, one row of chips per tier
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(_heading(Terms.t("event_rewards_heading"), UITheme.GOLD))
	_rewards = GridContainer.new()
	_rewards.columns = 2
	_rewards.add_theme_constant_override("h_separation", 18)
	_rewards.add_theme_constant_override("v_separation", 6)
	box.add_child(_rewards)
	_reward_rule = _text(Terms.t("event_reward_rule"), 12, UITheme.TEXT_DIM)
	_reward_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_reward_rule)
	return panel

## The CHALLENGE button: hot red-orange with a glow, grey when it can't be pressed
func _challenge_style(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var s := UITheme.box(Color("#e5483b"), Color("#fecaca"), 2, 12)
		s.shadow_color = Color(BOSS_RED, 0.5)
		s.shadow_size = 10
		match state:
			"hover":
				s.bg_color = Color("#f2604f")
				s.shadow_size = 16
			"pressed":
				s.bg_color = Color("#b91c1c")
				s.shadow_size = 4
			"disabled":
				s.bg_color = Color("#3a2a2e")
				s.border_color = Color("#5b4448")
				s.shadow_size = 0
		b.add_theme_stylebox_override(state, s)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color("#8a7a7e"))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	b.add_theme_constant_override("outline_size", 4)

# ───────── Leaderboard ─────────

func _build_board_panel() -> Control:
	var parts := _panel(UITheme.GOLD)
	var panel: PanelContainer = parts[0]
	panel.custom_minimum_size.x = 320
	var box: VBoxContainer = parts[1]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var lists := VBoxContainer.new()
	lists.add_theme_constant_override("separation", 6)
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lists)
	lists.add_child(_heading(Terms.t("event_top"), UITheme.GOLD))
	_top_list = VBoxContainer.new()
	_top_list.add_theme_constant_override("separation", 3)
	lists.add_child(_top_list)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	lists.add_child(gap)
	lists.add_child(_heading(Terms.t("event_recent"), UITheme.CYAN))
	_recent_list = VBoxContainer.new()
	_recent_list.add_theme_constant_override("separation", 2)
	lists.add_child(_recent_list)
	return panel

func _show_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	_body.visible = false

## Asks the server for the latest state and redraws
func refresh_now() -> void:
	if _loading:
		return
	_loading = true
	var r := await WorldBoss.fetch()
	_loading = false
	if not is_inside_tree():
		return
	if WorldBoss.update_required:
		_show_message(Terms.t("event_update_required"))
		return
	if not r.ok:
		_show_message(Terms.t("event_offline"))
		return
	_data = r.data
	_fetched_at = Time.get_ticks_msec()
	var info = _data.get("event")
	if not info is Dictionary:
		_show_message(Terms.t("event_none"))
		return
	_event = DB.events.get(StringName(str(info.boss_key)))
	if _event == null:
		_show_message(Terms.t("event_unknown"))
		return
	_fill(info)
	if info.status != "active" and _over_sent != int(info.id):
		_over_sent = int(info.id)
		event_over.emit()

func _fill(info: Dictionary) -> void:
	_message.visible = false
	_body.visible = true
	var live: bool = info.status == "active"
	_event_name.text = _event.display_name
	_hero.texture = _banner_picture()
	_description.text = _event.description
	var total := _event.missions.filter(func(s): return s != null).size()
	var cleared := _event.missions_cleared()
	_mission_progress.text = Terms.t("event_missions_progress", {"cleared": cleared, "total": total})
	_track.set_progress(cleared, total)
	_missions_button.disabled = not live

	_boss_name.text = _event.boss_stage.display_name
	_boss_art.texture = _boss_picture()
	var hp := int(info.hp)
	var max_hp := int(info.max_hp)
	_boss_bar.set_hp(hp, max_hp, info.status == "defeated", Terms.t("event_boss_hp", {"hp": Terms.number(hp),
		"max": Terms.number(max_hp), "percent": "%.1f" % (100.0 * hp / maxf(max_hp, 1))}))

	var me = _data.get("me")
	var registered := WorldBoss.is_registered() and me is Dictionary
	for child in _chips.get_children():
		child.queue_free()
	_attempts.visible = registered
	_attempts_label.visible = registered
	if registered:
		_attempts_label.text = Terms.t("event_attempts_short")
		_attempts.set_count(int(me.attempts_left), int(info.attempts_per_day))
		_chips.add_child(UITheme.tag(Terms.t("event_your_damage", {"damage": Terms.number(int(me.damage))}), UITheme.GOLD))
		if int(me.get("rank", 0)) > 0:
			_chips.add_child(UITheme.tag(Terms.t("event_your_rank", {"rank": int(me.rank)}), Color("#f472b6")))
	_join_row.visible = live and not WorldBoss.is_registered()
	_challenge.visible = not _join_row.visible
	_challenge_note.visible = _challenge.visible

	var note := ""
	if info.status == "defeated":
		note = Terms.t("event_boss_defeated")
	elif not live:
		note = Terms.t("event_over_expired")
	elif not _event.is_boss_unlocked():
		note = Terms.t("event_boss_locked")
	elif not GameState.has_team():
		note = Terms.t("map_need_team")
	elif GameState.is_team_over_cost():
		note = Terms.t("team_over_cost", {"cost": GameState.team_cost(), "limit": GameState.team_cost_limit()})
	elif registered and int(me.attempts_left) <= 0:
		note = Terms.t("event_no_attempts")
	_challenge.disabled = not note.is_empty() or not registered
	_challenge_note.text = note
	_challenge_note.add_theme_color_override("font_color", UITheme.GOLD if info.status == "defeated" else Color("#fca5a5"))

	_fill_top(_data.get("top", []))
	_fill_recent(_data.get("recent", []))
	_fill_rewards()
	_update_clock()

## The event's banner, else the boss fight's background, else its chapter's picture, else the home picture
func _banner_picture() -> Texture2D:
	if _event.banner:
		return _event.banner
	if _event.boss_stage.background:
		return _event.boss_stage.background
	var chapter_bg := UITheme.background(Terms.chapter_name(_event.boss_stage.chapter).replace(" ", ""))
	return chapter_bg if chapter_bg else UITheme.background("HomeBg")

## The boss's own picture: the first enemy of the boss wave (or of the first wave)
func _boss_picture() -> Texture2D:
	var waves := _event.boss_stage.waves
	var ordered := waves.filter(func(w): return w and w.is_boss) + waves.filter(func(w): return w and not w.is_boss)
	for wave: WaveData in ordered:
		for enemy in wave.enemy_vanguard + wave.enemy_rearguard:
			if enemy:
				var texture: Texture2D = enemy.get_portrait()
				if texture == null:
					texture = enemy.get_cutin()
				if texture:
					return texture
	return null

## Top damage: medal rows for the podium, plain rows after; your own row lit up
func _fill_top(rows: Array) -> void:
	for child in _top_list.get_children():
		child.queue_free()
	if rows.is_empty():
		_top_list.add_child(_text(Terms.t("event_list_empty"), LIST_FONT, UITheme.TEXT_DIM))
		return
	var mine := WorldBoss.player_name()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var podium := i < RANK_COLORS.size()
		var color: Color = RANK_COLORS[i] if podium else UITheme.TEXT
		var is_me := str(row.name) == mine
		var line := PanelContainer.new()
		var bg := Color(color, 0.12) if podium else Color(1, 1, 1, 0.03 if i % 2 == 0 else 0.0)
		var style := UITheme.box(Color(UITheme.CYAN, 0.18) if is_me else bg, Color(UITheme.CYAN, 0.8) if is_me else Color(color, 0.35 if podium else 0.0), 1, 8)
		style.content_margin_left = 6
		style.content_margin_right = 10
		style.content_margin_top = 2 if not podium else 4
		style.content_margin_bottom = 2 if not podium else 4
		line.add_theme_stylebox_override("panel", style)
		_top_list.add_child(line)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		line.add_child(h)
		var medal := Medal.new()
		medal.rank = i + 1
		medal.color = color if podium else Color("#475569")
		medal.custom_minimum_size = Vector2(26, 26) if podium else Vector2(22, 20)
		h.add_child(medal)
		var font_size := LIST_FONT + (2 if podium else 0)
		var who := _text(str(row.name), font_size, UITheme.CYAN_BRIGHT if is_me else (Color.WHITE if podium else UITheme.TEXT))
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(who)
		var dmg := _text(Terms.number(int(row.damage)), font_size, color if podium else UITheme.TEXT_DIM)
		dmg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(dmg)

## Latest hits as a short feed
func _fill_recent(rows: Array) -> void:
	for child in _recent_list.get_children():
		child.queue_free()
	if rows.is_empty():
		_recent_list.add_child(_text(Terms.t("event_list_empty"), LIST_FONT, UITheme.TEXT_DIM))
		return
	var mine := WorldBoss.player_name()
	for i in mini(rows.size(), RECENT_MAX):
		var row: Dictionary = rows[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		_recent_list.add_child(h)
		var dot := ColorRect.new()
		dot.color = Color(UITheme.CYAN, 0.7)
		dot.custom_minimum_size = Vector2(6, 6)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		var who := _text(str(row.name), 13, UITheme.CYAN_BRIGHT if str(row.name) == mine else UITheme.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		h.add_child(who)
		h.add_child(_text("-" + Terms.number(int(row.damage)), 13, Color("#fca5a5")))

## One row per tier: a label (ALL, or the 1st / 2nd / 3rd medal) and the rewards as chips
func _fill_rewards() -> void:
	for child in _rewards.get_children():
		child.queue_free()
	var tiers: Array = []
	if _event.reward_all and not _event.reward_all.is_empty():
		tiers.append([0, _event.reward_all])
	for rank in range(1, _event.reward_top.size() + 1):
		var reward := _event.top_reward(rank)
		if reward and not reward.is_empty():
			tiers.append([rank, reward])
	for tier in tiers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_rewards.add_child(row)
		var rank: int = tier[0]
		var label_box := CenterContainer.new()
		label_box.custom_minimum_size.x = 44
		row.add_child(label_box)
		if rank == 0:
			label_box.add_child(UITheme.tag(Terms.t("event_reward_all"), UITheme.CYAN))
		else:
			var medal := Medal.new()
			medal.rank = rank
			medal.color = RANK_COLORS[rank - 1] if rank <= RANK_COLORS.size() else Color("#475569")
			medal.custom_minimum_size = Vector2(26, 26)
			label_box.add_child(medal)
		for chip in _reward_chips(tier[1]):
			row.add_child(chip)

func _reward_chips(reward: EventReward) -> Array[Control]:
	var out: Array[Control] = []
	if reward.money > 0:
		out.append(_amount_chip("money", Terms.term("money"), reward.money))
	if reward.credit_cards > 0:
		out.append(_amount_chip("credit_card", Terms.term("credit_cards"), reward.credit_cards))
	for key in reward.materials:
		if reward.materials[key] > 0:
			out.append(_amount_chip(key, Terms.material_name(key), reward.materials[key]))
	for e in reward.equipment:
		if e:
			out.append(UITheme.tag(e.display_name, CharArt.RARITY_COLORS.get(e.rarity, UITheme.CYAN)))
	for c in reward.characters:
		if c:
			out.append(UITheme.tag(Terms.t("event_reward_friend", {"name": c.display_name}), Color("#f472b6")))
	return out

func _amount_chip(kind: String, tooltip: String, amount: int) -> Control:
	var chip := CurrencyChip.new(kind, tooltip)
	chip.set_amount(amount)
	chip.value_label.add_theme_font_size_override("font_size", 15)
	return chip

## "2d 4h left", ticking between refreshes using the server's clock
func _update_clock() -> void:
	var info = _data.get("event")
	if not (info is Dictionary and _body.visible):
		return
	if info.status != "active":
		_time_left.text = Terms.t("event_ended")
		return
	var now := float(_data.server_time) + (Time.get_ticks_msec() - _fetched_at)
	var seconds := maxi(int((float(info.ends_at) - now) / 1000.0), 0)
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	var minutes := (seconds % 3600) / 60
	if days > 0:
		_time_left.text = Terms.t("event_time_days", {"days": days, "hours": hours})
	elif hours > 0:
		_time_left.text = Terms.t("event_time_hours", {"hours": hours, "minutes": minutes})
	else:
		_time_left.text = Terms.t("event_time_minutes", {"minutes": maxi(minutes, 1)})

func _join() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		_name_edit.grab_focus()
		return
	_join_row.visible = false
	if not await WorldBoss.register(player_name):
		_join_row.visible = true
		_challenge_note.text = Terms.t("event_offline")
		return
	refresh_now()

## The hero strip: the key art cropped to cover it, darkened toward the left and bottom so the text reads, a
## violet glow line along the bottom and light motes drifting up
class Hero extends Control:
	var texture: Texture2D:
		set(value):
			texture = value
			queue_redraw()
	var _t := 0.0

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
			set_process(is_inside_tree() and is_visible_in_tree())

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("#0b0a1a"))
		if texture:
			UITheme.draw_texture_cover(self, texture, r)
		var dark := Color(0.02, 0.02, 0.07)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
			PackedColorArray([Color(dark, 0.88), Color(dark, 0.15), Color(dark, 0.55), Color(dark, 0.92)]))
		UITheme.draw_vertical_gradient(self, Rect2(0, size.y * 0.55, size.x, size.y * 0.45), Color(dark, 0.0), Color(dark, 0.6))
		for i in 18:
			var seed_x := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
			var life := fposmod(seed_x * 3.0 + _t * (0.05 + 0.04 * fposmod(i * 0.37, 1.0)), 1.0)
			var p := Vector2(seed_x * size.x, lerpf(size.y, 0, life))
			var fade := clampf(minf(life, 1.0 - life) * 5.0, 0.0, 1.0)
			draw_circle(p, 2.0 + 1.5 * fposmod(i * 0.61, 1.0), Color("#c4b5fd", 0.5 * fade))
		draw_line(Vector2(0, size.y - 1.5), Vector2(size.x, size.y - 1.5), Color(UITheme.VIOLET, 0.9), 3.0)
		draw_rect(r, Color(UITheme.VIOLET, 0.5), false, 1.5)

## One diamond per mission joined by a line: cleared ones filled violet, the next one pulsing; gold once all are done
class MissionTrack extends Control:
	var _cleared := 0
	var _total := 0

	func set_progress(cleared: int, total: int) -> void:
		_cleared = cleared
		_total = total
		set_process(_cleared < _total)
		queue_redraw()

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if _total <= 0:
			return
		var done := _cleared >= _total
		var lit := UITheme.GOLD if done else Color("#a78bfa")
		var step := (size.x - 24.0) / maxf(_total - 1, 1)
		var y := size.y * 0.5
		draw_line(Vector2(12, y), Vector2(size.x - 12, y), Color(1, 1, 1, 0.15), 3.0)
		if _cleared > 0:
			draw_line(Vector2(12, y), Vector2(12 + step * mini(_cleared, _total - 1), y), Color(lit, 0.85), 3.0)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
		for i in _total:
			var c := Vector2(12 + step * i, y)
			var r := 9.0
			var d := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
			if i < _cleared:
				UITheme.draw_glow(self, c, 14.0, Color(lit, 0.35))
				draw_colored_polygon(d, lit)
			elif i == _cleared:
				UITheme.draw_glow(self, c, 12.0 + 4.0 * pulse, Color("#a78bfa", 0.3 + 0.3 * pulse))
				draw_colored_polygon(d, Color("#1e1b3a"))
			else:
				draw_colored_polygon(d, Color("#1e1b3a"))
			d.append(d[0])
			draw_polyline(d, Color(1, 1, 1, 0.7 if i <= _cleared else 0.3), 1.5, true)

## Attempts left as a row of pips
class Pips extends Control:
	var _left := 0
	var _max := 0

	func set_count(left: int, max_count: int) -> void:
		_left = left
		_max = max_count
		custom_minimum_size.x = maxf(max_count * 18.0, 18.0)
		queue_redraw()

	func _draw() -> void:
		for i in _max:
			var c := Vector2(8.0 + i * 18.0, size.y * 0.5)
			if i < _left:
				UITheme.draw_glow(self, c, 10.0, Color(UITheme.CYAN, 0.35))
				draw_circle(c, 6.0, UITheme.CYAN_BRIGHT)
			else:
				draw_circle(c, 6.0, Color(1, 1, 1, 0.08))
			draw_arc(c, 6.0, 0, TAU, 20, Color(1, 1, 1, 0.5), 1.2, true)

## A round medal with the rank number (gold / silver / bronze on the podium, slate after)
class Medal extends Control:
	var rank := 1
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.0
		if rank <= 3:
			UITheme.draw_glow(self, c, r * 1.5, Color(color, 0.3))
		draw_circle(c, r, color.darkened(0.25))
		draw_circle(c, r * 0.78, color)
		draw_arc(c, r, 0, TAU, 24, Color(1, 1, 1, 0.6), 1.2, true)
		var font := get_theme_default_font()
		var font_size := int(r * 1.1)
		var text := str(rank)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(c.x - w * 0.5, c.y + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
			Color("#1a1a1a") if rank <= 3 else Color.WHITE)

## The shared HP bar: a thick red bar with a darker trail that catches up after each refresh, the HP numbers
## written across it, and a DEFEATED stamp once the boss is down
class BossBar extends Control:
	var _share := 1.0
	var _trail := 1.0
	var _defeated := false
	var _label := ""
	var _tween: Tween

	func _init() -> void:
		resized.connect(queue_redraw)

	func set_hp(hp: int, max_hp: int, defeated: bool, label: String = "") -> void:
		_defeated = defeated
		_label = label
		var share := clampf(float(hp) / maxf(max_hp, 1), 0.0, 1.0)
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_share = share
		_tween.tween_method(_set_trail, maxf(_trail, share), share, 0.8).set_delay(0.3).set_trans(Tween.TRANS_SINE)
		queue_redraw()

	func _set_trail(v: float) -> void:
		_trail = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UITheme.box(Color(0, 0, 0, 0.6), Color.TRANSPARENT, 0, 6), r)
		var inner := r.grow(-3.0)
		if _trail > _share:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * _trail, inner.size.y)), Color("#fca5a5", 0.6))
		var fill := Rect2(inner.position, Vector2(inner.size.x * _share, inner.size.y))
		UITheme.draw_vertical_gradient(self, fill, Color("#f87171"), Color("#991b1b"))
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.35)), Color(1, 1, 1, 0.18))
		for i in range(1, 10):  # tick marks every 10%
			var x := inner.position.x + inner.size.x * i / 10.0
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0, 0, 0, 0.3), 1.0)
		draw_style_box(UITheme.box(Color.TRANSPARENT, Color(1, 1, 1, 0.35), 2, 6), r)
		var font := get_theme_default_font()
		var text := Terms.t("event_defeated_stamp") if _defeated else _label
		var font_size := 22 if _defeated else 15
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2((size.x - w) / 2.0, size.y / 2.0 + font_size * 0.36)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UITheme.GOLD if _defeated else Color.WHITE)
