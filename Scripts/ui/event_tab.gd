class_name EventTab
extends VBoxContainer
## The Event tab. Shows the live event from the world boss server (WorldBoss autoload), so it needs a connection:
## without one, or with no event running, it just says so. A live event has two panels:
## - Missions: the event's banner and story, how many missions are cleared, and a button to the mission route.
## - World Boss: the shared HP bar every player is draining, today's attempts, your damage and rank, the top 10,
##   the latest hits, what the boss pays out, and the Challenge button (opens once every mission is cleared).
## The first visit asks for the name other players will see. While visible it refreshes every REFRESH_SEC.
## Main listens to missions_pressed / challenge_pressed, and to event_over to pay out rewards.

signal missions_pressed(event: EventData)
signal challenge_pressed(event: EventData)
signal event_over  # the event shown has ended (boss defeated or out of time)

const REFRESH_SEC := 20.0
const RANK_COLORS := [Color("#ffd75e"), Color("#d8dee9"), Color("#e0a060")]  # 1st, 2nd, 3rd
const LIST_FONT := 14

var _event: EventData
var _data := {}  # the server's last answer: {event, top, recent, me, server_time}
var _fetched_at := 0  # Time.get_ticks_msec() when _data arrived
var _loading := false
var _over_sent := -1  # event id event_over was last emitted for

var _event_name: Label
var _time_left: Label
var _message: Label
var _join_row: HBoxContainer
var _name_edit: LineEdit
var _body: HBoxContainer
var _banner: TextureRect
var _description: Label
var _mission_progress: Label
var _mission_bar: ProgressBar
var _missions_button: Button
var _boss_name: Label
var _boss_bar: BossBar
var _boss_hp: Label
var _chips: HBoxContainer
var _challenge: Button
var _challenge_note: Label
var _top_list: VBoxContainer
var _recent_list: VBoxContainer
var _reward_text: Label

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(_build_header())
	_message = _text("", 18, UITheme.TEXT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_message)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.visible = false
	add_child(_body)
	_body.add_child(_build_missions_panel())
	_body.add_child(_build_boss_panel())

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

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _panel(min_width: float) -> Array:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	panel.add_theme_stylebox_override("panel", UITheme.glow_box(Color(0.04, 0.06, 0.11, 0.9), 12, 14, UITheme.VIOLET))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return [panel, box]

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.VIOLET.darkened(0.1)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(UITheme.VIOLET, 0.45)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_text(Terms.t("event_banner"), 24, Color.WHITE))
	header.add_child(plate)
	_event_name = _text("", 22, Color.WHITE)
	_event_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_event_name)
	_time_left = _text("", 16, UITheme.GOLD)
	header.add_child(_time_left)
	var refresh := Button.new()
	refresh.text = Terms.t("event_refresh")
	refresh.pressed.connect(refresh_now)
	header.add_child(refresh)
	return header

func _build_missions_panel() -> Control:
	var parts := _panel(340)
	var box: VBoxContainer = parts[1]
	var holder := Control.new()  # the banner picture, cropped to fit
	holder.custom_minimum_size = Vector2(0, 170)
	holder.clip_contents = true
	box.add_child(holder)
	_banner = TextureRect.new()
	_banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(_banner)
	_description = _text("", 14, UITheme.TEXT)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 300
	box.add_child(_description)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_mission_progress = _text("", 15, UITheme.TEXT)
	box.add_child(_mission_progress)
	_mission_bar = ProgressBar.new()
	_mission_bar.show_percentage = false
	_mission_bar.custom_minimum_size.y = 10
	box.add_child(_mission_bar)
	_missions_button = Button.new()
	_missions_button.text = Terms.t("event_missions_button")
	_missions_button.custom_minimum_size.y = 52
	_missions_button.add_theme_font_size_override("font_size", 20)
	_missions_button.pressed.connect(func():
		if _event:
			missions_pressed.emit(_event))
	box.add_child(_missions_button)
	return parts[0]

func _build_boss_panel() -> Control:
	var parts := _panel(0)
	var panel: PanelContainer = parts[0]
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = parts[1]
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	box.add_child(title_row)
	title_row.add_child(UITheme.tag(Terms.t("event_world_boss"), Color("#ef4444")))
	_boss_name = _text("", 22, Color("#ff8a80"))
	title_row.add_child(_boss_name)
	_boss_bar = BossBar.new()
	_boss_bar.custom_minimum_size.y = 30
	box.add_child(_boss_bar)
	_boss_hp = _text("", 15, UITheme.TEXT)
	_boss_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_boss_hp)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	box.add_child(_chips)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	box.add_child(action_row)
	_challenge = Button.new()
	_challenge.text = Terms.t("event_challenge")
	_challenge.theme_type_variation = &"PrimaryButton"
	_challenge.custom_minimum_size = Vector2(220, 56)
	_challenge.add_theme_font_size_override("font_size", 22)
	_challenge.pressed.connect(func():
		if _event:
			challenge_pressed.emit(_event))
	action_row.add_child(_challenge)
	_challenge_note = _text("", 14, Color("#fca5a5"))
	_challenge_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_challenge_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_row.add_child(_challenge_note)
	# First visit: pick the name other players see, in place of the Challenge button
	_join_row = HBoxContainer.new()
	_join_row.add_theme_constant_override("separation", 8)
	_join_row.visible = false
	box.add_child(_join_row)
	_join_row.add_child(_text(Terms.t("event_name_prompt"), 15, UITheme.TEXT))
	_name_edit = LineEdit.new()
	_name_edit.max_length = WorldBoss.NAME_MAX
	_name_edit.placeholder_text = Terms.t("event_name_placeholder")
	_name_edit.custom_minimum_size.x = 200
	_name_edit.text_submitted.connect(func(_t): _join())
	_join_row.add_child(_name_edit)
	var join := Button.new()
	join.text = Terms.t("event_join")
	join.theme_type_variation = &"PrimaryButton"
	join.pressed.connect(_join)
	_join_row.add_child(join)

	var lists := HBoxContainer.new()
	lists.add_theme_constant_override("separation", 18)
	lists.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(lists)
	for pair in [["event_top", "_top_list"], ["event_recent", "_recent_list"]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 2)
		lists.add_child(column)
		column.add_child(_text(Terms.t(pair[0]), 13, UITheme.TEXT_DIM))
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 1)
		column.add_child(list)
		set(pair[1], list)
	_reward_text = _text("", 13, UITheme.TEXT_DIM)
	_reward_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_text.custom_minimum_size.x = 300
	box.add_child(_reward_text)
	return panel

func _show_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	_body.visible = false
	_event_name.text = ""
	_time_left.text = ""

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
	_banner.texture = _banner_picture()
	_description.text = _event.description
	var total := _event.missions.filter(func(s): return s != null).size()
	var cleared := _event.missions_cleared()
	_mission_progress.text = Terms.t("event_missions_progress", {"cleared": cleared, "total": total})
	_mission_bar.max_value = maxi(total, 1)
	_mission_bar.value = cleared
	_missions_button.disabled = not live

	_boss_name.text = _event.boss_stage.display_name
	var hp := int(info.hp)
	var max_hp := int(info.max_hp)
	_boss_bar.set_hp(hp, max_hp, info.status == "defeated")
	_boss_hp.text = Terms.t("event_boss_hp", {"hp": Terms.number(hp), "max": Terms.number(max_hp),
		"percent": "%.1f" % (100.0 * hp / maxf(max_hp, 1))})

	var me = _data.get("me")
	var registered := WorldBoss.is_registered() and me is Dictionary
	for child in _chips.get_children():
		child.queue_free()
	if registered:
		_chips.add_child(UITheme.tag(Terms.t("event_attempts", {"left": int(me.attempts_left), "max": int(info.attempts_per_day)}), UITheme.CYAN))
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

	_fill_list(_top_list, _data.get("top", []), true)
	_fill_list(_recent_list, _data.get("recent", []), false)

	var reward_lines := PackedStringArray()
	if _event.reward_all and not _event.reward_all.is_empty():
		reward_lines.append(Terms.t("event_reward_everyone", {"rewards": ", ".join(_event.reward_all.lines())}))
	for rank in range(1, _event.reward_top.size() + 1):
		var reward := _event.top_reward(rank)
		if reward and not reward.is_empty():
			reward_lines.append(Terms.t("event_reward_rank", {"rank": rank, "rewards": ", ".join(reward.lines())}))
	reward_lines.append(Terms.t("event_reward_rule"))
	_reward_text.text = "\n".join(reward_lines)
	_update_clock()

## The event's banner, else the boss fight's background, else its chapter's picture, else the home picture
func _banner_picture() -> Texture2D:
	if _event.banner:
		return _event.banner
	if _event.boss_stage.background:
		return _event.boss_stage.background
	var chapter_bg := UITheme.background(Terms.chapter_name(_event.boss_stage.chapter).replace(" ", ""))
	return chapter_bg if chapter_bg else UITheme.background("HomeBg")

func _fill_list(list: VBoxContainer, rows: Array, ranked: bool) -> void:
	for child in list.get_children():
		child.queue_free()
	if rows.is_empty():
		list.add_child(_text(Terms.t("event_list_empty"), LIST_FONT, UITheme.TEXT_DIM))
		return
	var mine := WorldBoss.player_name()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		list.add_child(line)
		var color := UITheme.TEXT
		if ranked and i < RANK_COLORS.size():
			color = RANK_COLORS[i]
		if ranked:
			var place := _text("%d." % (i + 1), LIST_FONT, color)
			place.custom_minimum_size.x = 28
			line.add_child(place)
		var who := _text(str(row.name), LIST_FONT, UITheme.CYAN if str(row.name) == mine else color)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		line.add_child(who)
		line.add_child(_text(Terms.number(int(row.damage)), LIST_FONT, color))

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

## The shared HP bar: a thick red bar with a darker trail that catches up after each refresh, and a
## DEFEATED stamp once the boss is down
class BossBar extends Control:
	var _share := 1.0
	var _trail := 1.0
	var _defeated := false
	var _tween: Tween

	func _init() -> void:
		resized.connect(queue_redraw)

	func set_hp(hp: int, max_hp: int, defeated: bool) -> void:
		_defeated = defeated
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
		draw_rect(r, Color(0, 0, 0, 0.55))
		if _trail > _share:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * _trail, size.y)), Color("#fca5a5", 0.6))
		var fill := Rect2(Vector2.ZERO, Vector2(size.x * _share, size.y))
		UITheme.draw_vertical_gradient(self, fill, Color("#f87171"), Color("#b91c1c"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * _share, size.y * 0.35)), Color(1, 1, 1, 0.15))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)
		if _defeated:
			var font := ThemeDB.fallback_font
			var text := Terms.t("event_defeated_stamp")
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			var pos := Vector2((size.x - w) / 2.0, size.y / 2.0 + 8.0)
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0, 0, 0, 0.9))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UITheme.GOLD)
