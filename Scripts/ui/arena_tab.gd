class_name ArenaTab
extends VBoxContainer
## The Arena screen: an "ARENA" banner with the player's rating, rank, record and fights left today; a join row
## (the same server name as the World Boss) or a lock note before account Lv.Arena.MIN_ACCOUNT_LEVEL; then three
## opponent cards (name, rating, power, their team's portraits and a Fight button) beside the top-10 leaderboard.
## Main plays the fight (fight_pressed) and reports it. Everything reloads from the server whenever the tab is shown.

signal fight_pressed(opponent: Dictionary)

const ACCENT := Color("#f97316")

var _summary: Label
var _status: Label
var _join_row: HBoxContainer
var _name_edit: LineEdit
var _body: HBoxContainer
var _opponents: VBoxContainer
var _board: VBoxContainer
var _defense: Label
var _refresh_button: Button
var _loading := false
var _fights_left := 0

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(_build_header())
	var intro := _label(Terms.t("arena_intro", {"win": Arena.WIN_MONEY, "loss": Arena.LOSS_MONEY}), 14, UITheme.TEXT_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)
	_status = _label("", 15, Color("#fca5a5"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_join_row = HBoxContainer.new()
	_join_row.add_theme_constant_override("separation", 8)
	add_child(_join_row)
	_join_row.add_child(_label(Terms.t("arena_join_prompt"), 15, UITheme.TEXT))
	_name_edit = LineEdit.new()
	_name_edit.max_length = WorldBoss.NAME_MAX
	_name_edit.placeholder_text = Terms.t("event_name_placeholder")
	_name_edit.custom_minimum_size.x = 180
	_name_edit.text_submitted.connect(func(_t): _join())
	_join_row.add_child(_name_edit)
	var join := Button.new()
	join.text = Terms.t("arena_join")
	join.theme_type_variation = &"PrimaryButton"
	join.pressed.connect(_join)
	_join_row.add_child(join)

	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 16)
	add_child(_body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.8
	left.add_theme_constant_override("separation", 8)
	_body.add_child(left)
	var top := HBoxContainer.new()
	left.add_child(top)
	var head := _label(Terms.t("arena_opponents"), 18, ACCENT.lightened(0.3))
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	_refresh_button = Button.new()
	_refresh_button.text = Terms.t("arena_refresh")
	_refresh_button.pressed.connect(refresh_now)
	top.add_child(_refresh_button)
	_opponents = VBoxContainer.new()
	_opponents.add_theme_constant_override("separation", 8)
	left.add_child(_opponents)
	_defense = _label("", 13, UITheme.TEXT_DIM)
	_defense.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_defense)

	var board_panel := PanelContainer.new()
	board_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_panel.add_theme_stylebox_override("panel", UITheme.panel_box(12))
	_body.add_child(board_panel)
	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 4)
	board_panel.add_child(_board)

	visibility_changed.connect(func():
		if is_visible_in_tree():
			refresh_now())

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
	header.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT.darkened(0.15)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(ACCENT, 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_label(Terms.t("arena_banner"), 24, Color.WHITE))
	header.add_child(plate)
	_summary = _label("", 16, UITheme.TEXT)
	_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_summary)
	return header

# ───────── Loading ─────────

## Reloads the rating, the leaderboard and three opponents from the server
func refresh_now() -> void:
	if _loading:
		return
	_status.text = ""
	_join_row.visible = false
	if not Arena.is_unlocked():
		_body.visible = false
		_summary.text = ""
		_status.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		_status.text = Terms.t("arena_locked", {"lv": Arena.MIN_ACCOUNT_LEVEL})
		return
	if not WorldBoss.is_registered():
		_body.visible = false
		_summary.text = ""
		_join_row.visible = true
		return
	_loading = true
	_refresh_button.disabled = true
	_summary.text = Terms.t("arena_loading")
	var state := await Arena.fetch_state()
	if not is_inside_tree():
		_loading = false
		return
	if not state.ok:
		_loading = false
		_refresh_button.disabled = false
		_body.visible = false
		_summary.text = ""
		_status.add_theme_color_override("font_color", Color("#fca5a5"))
		_status.text = Terms.t("event_update_required" if WorldBoss.update_required else "arena_offline")
		return
	var opponents := await Arena.fetch_opponents()
	_loading = false
	if not is_inside_tree():
		return
	_refresh_button.disabled = false
	_body.visible = true
	_show_state(state.data)
	_show_opponents(opponents)

func _show_state(data: Dictionary) -> void:
	var me: Dictionary = data.get("me", {}) if data.get("me") is Dictionary else {}
	_fights_left = int(me.get("fights_left", 0))
	_summary.text = Terms.t("arena_summary", {"rating": int(me.get("rating", 1000)),
		"rank": "#%d" % int(me.rank) if int(me.get("rank", 0)) > 0 else "-", "wins": int(me.get("wins", 0)),
		"losses": int(me.get("losses", 0)), "left": _fights_left, "per_day": int(me.get("fights_per_day", 5))})
	_defense.text = Terms.t("arena_defense", {"power": Terms.number(GameState.team_power())})
	for child in _board.get_children():
		child.queue_free()
	_board.add_child(_label(Terms.t("arena_leaderboard"), 17, UITheme.GOLD))
	var top: Array = data.get("top", [])
	if top.is_empty():
		_board.add_child(_label(Terms.t("arena_board_empty"), 14, UITheme.TEXT_DIM))
	for i in top.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_board.add_child(row)
		var mine := str(top[i].name) == WorldBoss.player_name()
		var color := UITheme.GOLD if i == 0 else (UITheme.CYAN_BRIGHT if mine else UITheme.TEXT)
		var place := _label("%d." % (i + 1), 15, color)
		place.custom_minimum_size.x = 28
		row.add_child(place)
		var player_name := _label(str(top[i].name), 15, color)
		player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_name.clip_text = true
		row.add_child(player_name)
		row.add_child(_label(str(int(top[i].rating)), 15, color))

func _show_opponents(list: Array) -> void:
	for child in _opponents.get_children():
		child.queue_free()
	for opponent in list:
		_opponents.add_child(_opponent_card(opponent))

## Name and rating, their team's portraits, power, and Fight
func _opponent_card(opponent: Dictionary) -> Control:
	var bot := bool(opponent.get("bot", false))
	var panel := PanelContainer.new()
	var style := UITheme.box(Color(0.06, 0.08, 0.14, 0.92), Color(ACCENT, 0.35 if bot else 0.7), 1, 10, 8)
	style.content_margin_left = 12
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 170
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	info.add_child(_label(str(opponent.name), 18, Color.WHITE))
	var sub := Terms.t("arena_bot_tag") if bot else Terms.t("arena_rating", {"rating": int(opponent.rating)})
	if int(opponent.get("power", 0)) > 0:
		sub += "  ·  " + Terms.t("arena_power", {"power": Terms.number(int(opponent.power))})
	info.add_child(_label(sub, 13, ACCENT.lightened(0.35) if not bot else UITheme.TEXT_DIM))
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 4)
	faces.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	faces.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(faces)
	for c in Arena.snapshot_characters(opponent.get("team", [])):
		var art := CharArt.new()
		art.custom_minimum_size = Vector2(46, 58)
		art.set_character(c)
		art.tooltip_text = c.display_name
		faces.add_child(art)
	var fight := Button.new()
	fight.text = Terms.t("arena_fight")
	fight.custom_minimum_size = Vector2(110, 48)
	fight.theme_type_variation = &"PrimaryButton"
	fight.disabled = _fights_left <= 0 or not GameState.can_battle()
	if _fights_left <= 0:
		fight.tooltip_text = Terms.t("arena_no_fights")
	fight.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fight.pressed.connect(func(): fight_pressed.emit(opponent))
	row.add_child(fight)
	return panel

func _join() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		_name_edit.grab_focus()
		return
	_join_row.visible = false
	if not await WorldBoss.register(player_name):
		_join_row.visible = true
		_status.text = Terms.t("arena_offline")
		return
	refresh_now()
