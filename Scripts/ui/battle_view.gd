class_name BattleView
extends VBoxContainer
## Kancolle-style battle playback. Your team stands on the left (rearguard behind the vanguard), the enemies on
## the right. Each action: the actor bumps forward and flashes, its targets shake and show damage numbers, then
## HP bars, Ultimate gauges and buffs update from the engine's recorded state. Ultimates open with a Kancolle-style
## cut-in (Scripts/ui/cut_in_overlay.gd). Every battle plays out in full; players pick 1x/2x speed instead of skipping (3x in test mode).
## Map battles are live (start_live): each action is worked out just before it plays, so with Auto Ultimate off
## the player clicks a friend whose gauge is full to fire their Ultimate on that friend's next turn.
## World boss fights are recorded in advance from the server's seed (start) and always fire automatically.

signal again_pressed
signal home_pressed
signal next_pressed
signal battle_finished(report: Dictionary)  # the last action has played (the results screen is about to open)

const SPEEDS := [1, 2]
const TEST_SPEEDS := [1, 2, 3]  # 3x only in test mode (GameState.is_test_mode)
const CARD_SIZE := Vector2(236, 118)
const ART_SIZE := Vector2(92, 108)
const BUMP_DISTANCE := 44.0
const STEP_SEC := 0.18  # length of one animation step at 1x
const ALLY_COLOR := Color("#3b82f6")
const ENEMY_COLOR := Color("#ef4444")
const DOWNED_ALPHA := 0.3
const NAME_FONT_SIZE := 15
const NAME_MIN_FONT_SIZE := 11
const AUTO_NEXT_SECONDS := 4  # Auto Run: the pause on the results screen before the next run starts

var _battle: Dictionary
var _speed := 1
var _views: Array[Dictionary] = []  # one per battle unit, same index
var _overlay: Control
var _banner: Label
var _cut_in: CutInOverlay
var _combo_cut_in: ComboCutIn
var _jumpscare: JumpscareOverlay
var _fx: BattleFX
var _arena: Control
var _results: BattleResults
var _log_names: Array[Dictionary] = []  # {"name", "side"}, longest first, for colouring names in the log
var _log_number := RegEx.create_from_string("\\d+")
var _stage_name := ""
var _note := ""
var _wave_label: Label
var _wave_pips: WavePips
var _clash: TeamClash
var _wave_count := 1
var _log: RichTextLabel
var _live := false  # actions come from Combat.next_event() as the battle goes (start_live)
var _manual := false  # Auto Ultimate off: full gauges wait for a click
var coach: Coach  # set by Main for the tutorial's guided first fight: it walks the player through an Ultimate
var _auto_button: CheckButton
var _guide_fired := false  # the guided fight's first hand-fired Ultimate has gone off
var auto_label := ""  # set by Main for an Auto Run battle: "AUTO RUN 1/3" in the header (no Auto Ultimate switch)
var auto_next := false  # Auto Run: after a win the results screen counts down, then presses Next by itself
var next_text := ""  # set by Main when a mission follows this one; shown as Next Mission after a win
var continue_text := ""  # set by Main (After Hours): one Continue button on the results instead of Again / Home

## A battle recorded in advance (the world boss)
func start(stage: StageData, battle: Dictionary) -> void:
	_battle = battle
	_stage_name = stage.display_name
	_speed = clampi(int(GameState.get_setting("battle_speed", 1)), 1, _speeds().back())
	_build(stage)
	_play()

## A live map battle that Combat.start_sortie() has set up; `units` is the snapshot it returned
func start_live(stage: StageData, units: Array, manual: bool) -> void:
	_live = true
	_manual = manual
	_battle = {"units": units}
	_stage_name = stage.display_name
	_speed = clampi(int(GameState.get_setting("battle_speed", 1)), 1, _speeds().back())
	_build(stage)
	_play()

# ───────── Layout ─────────

func _build(stage: StageData) -> void:
	add_theme_constant_override("separation", 8)
	Sound.prepare()  # builds the battle sounds over the next few frames

	# HUD bar: the stage (code chip + name) and the wave pips on the left, both teams' total HP facing off in the
	# middle, the Auto Ultimate switch, the log toggle and the speed pills on the right
	var hud := PanelContainer.new()
	var hud_style := UITheme.box(Color(0.03, 0.05, 0.1, 0.78), Color(UITheme.CYAN, 0.35), 1, 10)
	hud_style.border_width_bottom = 2
	hud_style.content_margin_left = 14
	hud_style.content_margin_right = 10
	hud_style.content_margin_top = 6
	hud_style.content_margin_bottom = 6
	hud_style.shadow_color = Color(0, 0, 0, 0.35)
	hud_style.shadow_size = 8
	hud.add_theme_stylebox_override("panel", hud_style)
	add_child(hud)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	hud.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(titles)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	titles.add_child(name_row)
	if stage.is_story():
		name_row.add_child(UITheme.tag(stage.code(), UITheme.CYAN, true))
	var title := Label.new()
	title.text = stage.display_name
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("outline_size", 4)
	name_row.add_child(title)
	# "Battle 1/3": which wave of the mission is being fought, with a pip per wave
	for u in _battle.units:
		_wave_count = maxi(_wave_count, int(u.wave) + 1)
	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override("separation", 6)
	wave_row.visible = _wave_count > 1
	titles.add_child(wave_row)
	_wave_label = Label.new()
	_wave_label.add_theme_font_size_override("font_size", 12)
	_wave_label.add_theme_color_override("font_color", UITheme.CYAN)
	_wave_label.text = Terms.t("battle_wave", {"current": 1, "total": _wave_count})
	wave_row.add_child(_wave_label)
	_wave_pips = WavePips.new(_wave_count)
	wave_row.add_child(_wave_pips)
	# Both sides' HP facing off
	_clash = TeamClash.new()
	_clash.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_clash)
	if not auto_label.is_empty():
		var tag := UITheme.tag(auto_label, UITheme.GOLD)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(tag)
	elif _live:
		var auto := CheckButton.new()
		auto.text = Terms.t("battle_auto_ult")
		auto.tooltip_text = Terms.t("battle_auto_ult_tip")
		auto.button_pressed = not _manual
		auto.focus_mode = Control.FOCUS_NONE
		auto.toggled.connect(_set_auto_ultimate)
		header.add_child(auto)
		_auto_button = auto
	var log_toggle := _pill(Terms.t("battle_log_button"), UITheme.TEXT_DIM)
	log_toggle.button_pressed = bool(GameState.get_setting("battle_log_big", false))
	log_toggle.tooltip_text = Terms.t("battle_log_tip")
	log_toggle.toggled.connect(_set_log_big)
	header.add_child(log_toggle)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	header.add_child(speeds)
	var group := ButtonGroup.new()
	for s in _speeds():
		var button := _pill(Terms.t("battle_speed", {"speed": s}), UITheme.CYAN)
		button.button_group = group
		button.button_pressed = s == _speed
		button.pressed.connect(_set_speed.bind(s))
		speeds.add_child(button)

	# Arena: [ally rearguard][ally vanguard]  gap  [enemy vanguard][enemy rearguard]
	var arena := Control.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.custom_minimum_size = Vector2(0, CARD_SIZE.y * 3 + 24)
	add_child(arena)
	# The stage behind the cards: a lit floor and a glowing divider (with VS) between the two sides
	var backdrop := ArenaStage.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena.add_child(backdrop)
	var sides := HBoxContainer.new()
	sides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_theme_constant_override("separation", 14)
	arena.add_child(sides)
	var columns := {}
	for key in ["ally_rear", "ally_van", "gap", "enemy_van", "enemy_rear"]:
		if key == "gap":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(40, 0)
			sides.add_child(gap)
			backdrop.gap = gap
			sides.sort_children.connect(backdrop.queue_redraw)
			continue
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 8)
		sides.add_child(column)
		columns[key] = column
	for u in _battle.units:
		var view := _unit_view(u, _views.size())
		var key := ("ally_" if u.side == 0 else "enemy_") + ("van" if u.vanguard else "rear")
		columns[key].add_child(view.slot)
		view.slot.visible = u.side == 0 or int(u.wave) == 0  # later waves' enemies wait off the field
		_views.append(view)

	_arena = arena
	# Sparks, bolts, rings and the turn marker: above the cards, below the damage numbers
	_fx = BattleFX.new()
	_fx.speed = _speed
	arena.add_child(_fx)
	# Overlay for damage numbers and the Ultimate banner, drawn above the cards
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(_overlay)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.add_theme_color_override("font_color", Color("#fde68a"))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	_overlay.add_child(_banner)
	# The animatronics' entrance darkens the arena and the cards, so it sits above them too
	_jumpscare = JumpscareOverlay.new()
	arena.add_child(_jumpscare)
	# Ultimate cut-ins go above everything else in the arena
	_cut_in = CutInOverlay.new()
	arena.add_child(_cut_in)
	_combo_cut_in = ComboCutIn.new()
	arena.add_child(_combo_cut_in)

	# The log: names coloured by side, numbers highlighted, knockouts in red (see _style_line)
	# Compact by default (the latest few lines); the HUD's Log pill makes it taller
	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.bbcode_enabled = true
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_size_override("bold_font_size", 13)
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.02, 0.04, 0.08, 0.7)
	log_style.border_color = Color(UITheme.CYAN, 0.5)
	log_style.border_width_left = 3
	log_style.set_corner_radius_all(8)
	log_style.set_content_margin_all(6)
	log_style.content_margin_left = 12
	_log.add_theme_stylebox_override("normal", log_style)
	add_child(_log)
	_set_log_big(bool(GameState.get_setting("battle_log_big", false)), false)
	_update_clash()
	var seen := {}
	for u in _battle.units:
		if not seen.has(u.name):
			seen[u.name] = true
			_log_names.append({"name": u.name, "side": u.side})
	_log_names.sort_custom(func(a, b): return a.name.length() > b.name.length())

## A unit card. The slot holds the place in the column; the body inside it is what slides and shakes.
func _unit_view(u: Dictionary, index: int) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = CARD_SIZE
	var body := PanelContainer.new()
	body.size = CARD_SIZE
	# Dark glass with a thick stripe on the outer edge in the side's colour and a soft glow of it underneath
	var side_color := ALLY_COLOR if u.side == 0 else ENEMY_COLOR
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.13, 0.93)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(5)
	style.shadow_color = Color(side_color, 0.22)
	style.shadow_size = 6
	_card_border(style, u.side, side_color, 1)
	body.add_theme_stylebox_override("panel", style)
	slot.add_child(body)
	# A faint wash of the side's colour from the outer edge, under the contents
	var wash := CardWash.new(side_color, u.side == 0)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.show_behind_parent = false
	body.add_child(wash)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var art := CharArt.new()
	art.custom_minimum_size = ART_SIZE
	if u.data:
		art.set_character(u.data)
	else:
		art.set_mystery(u.name)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	# A fixed text width: cards of later waves are built while hidden, and wrapping labels measured at zero
	# width would otherwise wrap one letter per line and stretch the card to the full arena height
	info.custom_minimum_size = Vector2(CARD_SIZE.x - ART_SIZE.x - 22, 0)
	# Mirror the enemy side so portraits face the centre
	if u.side == 0:
		row.add_child(art)
		row.add_child(info)
	else:
		row.add_child(info)
		row.add_child(art)

	var name_label := Label.new()
	name_label.text = u.name
	name_label.tooltip_text = u.name
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS  # so the tooltip shows
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # only if even the smallest size won't fit
	name_label.add_theme_font_size_override("font_size", _fit_font_size(u.name, info.custom_minimum_size.x))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	name_label.add_theme_constant_override("outline_size", 3)
	info.add_child(name_label)
	# Class and row under the name, in the class colour
	var role := _small_label("%s  ·  %s" % [Terms.class_label(int(u.cls)), Terms.t("battle_row_front" if u.vanguard else "battle_row_back")])
	role.add_theme_font_size_override("font_size", 11)
	var class_color: Color = CharArt.CLASS_COLORS.get(int(u.cls), UITheme.TEXT_DIM)
	role.add_theme_color_override("font_color", class_color.lightened(0.45))
	info.add_child(role)
	var start_hp := int(u.get("hp", u.max_hp))  # below max when HP carries over between battles (After Hours)
	var view := {"slot": slot, "body": body, "side": u.side, "wave": int(u.wave), "vanguard": u.vanguard, "max_hp": u.max_hp,
		"hp": start_hp, "hp_bar": null, "energy_bar": null, "ult_label": null, "energy_full": false,
		"buffs": null, "art": art, "data": u.data, "horse": false, "alt": false, "style": style}
	# Everyone has HP now; the rearguard is only hit once its vanguard is down. The numbers sit inside the bar.
	view.hp_bar = HpBar.new(u.max_hp, start_hp)
	info.add_child(view.hp_bar)
	if u.has_ultimate:
		view.ult_label = _small_label(Terms.t("battle_energy"))
		view.ult_label.add_theme_font_size_override("font_size", 11)
		view.ult_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		info.add_child(view.ult_label)
		if u.side == 0:
			body.gui_input.connect(_on_card_input.bind(index))
		view.energy_bar = UltBar.new(u.energy_max, int(u.get("energy", 0)))
		info.add_child(view.energy_bar)
	view.buffs = _small_label("", true)
	view.buffs.add_theme_color_override("font_color", Color("#93c5fd"))
	info.add_child(view.buffs)
	_pass_clicks(body)  # a click anywhere on the card reaches it (manual Ultimates)
	return view

func _pass_clicks(node: Node) -> void:
	for child in node.get_children():
		if child is Control and child.mouse_filter == Control.MOUSE_FILTER_STOP:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
		_pass_clicks(child)

## A small toggle pill for the HUD (speeds, the log): dark when off, filled with `color` when on
func _pill(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(44, 32)
	b.add_theme_font_size_override("font_size", 14)
	var off := UITheme.box(Color(0, 0, 0, 0.35), Color(color, 0.45), 1, 16, 8)
	var hover := UITheme.box(Color(color, 0.15), Color(color, 0.8), 1, 16, 8)
	var on := UITheme.box(Color(color, 0.85), color.lightened(0.3), 1, 16, 8)
	on.shadow_color = Color(color, 0.45)
	on.shadow_size = 6
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", color.lightened(0.3))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(0.03, 0.05, 0.1))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.03, 0.05, 0.1))
	return b

## The log: a compact strip of the latest lines, or taller when the Log pill is on (remembered)
func _set_log_big(big: bool, remember: bool = true) -> void:
	if _log:
		_log.custom_minimum_size = Vector2(0, 170 if big else 66)
	if remember:
		GameState.set_setting("battle_log_big", big)

## Long names ("Unemployed Racist B") step down from NAME_FONT_SIZE until they fit the card's text width.
## The game uses Godot's default font (UITheme sets no custom one), so it can be measured before the card is shown.
func _fit_font_size(text: String, width: float) -> int:
	var font := ThemeDB.fallback_font
	var font_size := NAME_FONT_SIZE
	while font_size > NAME_MIN_FONT_SIZE and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	return font_size

## Short fixed texts (HP numbers, "Ultimate") shouldn't wrap: a hidden card isn't laid out, and a wrapping label
## measured at zero width would wrap one letter per line and stretch the card. Only the buff list wraps.
func _small_label(text: String, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		label.clip_text = true
	label.add_theme_font_size_override("font_size", 12)
	return label

# ───────── Playback ─────────

## The speed buttons on offer: 1x and 2x, plus 3x in test mode
func _speeds() -> Array:
	return TEST_SPEEDS if GameState.is_test_mode() else SPEEDS

func _set_speed(s: int) -> void:
	_speed = s
	if _fx:
		_fx.speed = s
	GameState.set_setting("battle_speed", s)

## Duration of n animation steps at the current speed
func _dur(steps: float) -> float:
	return STEP_SEC * steps / _speed

## Waits using a tween owned by this node, so nothing resumes after the screen is closed
func _wait(steps: float) -> void:
	var t := create_tween()
	t.tween_interval(_dur(steps))
	await t.finished

func _play() -> void:
	await _wait(2)
	_update_guide()
	if _live:
		# Each action is worked out right before it plays, so a click during this one counts for the next
		while true:
			var event := Combat.next_event()
			if event.is_empty():
				break
			await _animate(event)
		_battle = Combat.finish_sortie()
	else:
		for event in _battle.events:
			await _animate(event)
	_finish()

# ───────── Manual Ultimates ─────────

func _set_auto_ultimate(on: bool) -> void:
	_manual = not on
	GameState.set_setting("auto_ultimate", on)
	Combat.engine.set_manual(_manual)
	for i in _views.size():
		_refresh_ultimate(i)
	_update_guide()

## Clicking a friend whose gauge is full asks for their Ultimate on their next turn; clicking again cancels
func _on_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not (_live and _manual and _ultimate_ready(index)):
		return
	Combat.engine.queue_ultimate(index, not Combat.engine.is_ultimate_queued(index))
	_refresh_ultimate(index)
	_update_guide()
	_flash(_views[index].body, Color(1.7, 1.5, 0.6), 1)

func _ultimate_ready(index: int) -> bool:
	var view: Dictionary = _views[index]
	return view.side == 0 and view.energy_full and view.hp > 0

## The tutorial's guided first fight: explain the gauge, point at the first friend whose Ultimate is ready, say it's
## coming once clicked, and after it fires point at the Auto switch. Stops if the tutorial is skipped.
func _update_guide() -> void:
	if coach == null:
		return
	if GameState.tutorial_step() >= GameState.Tutorial.RECRUIT or not _manual:
		coach.clear()
		return
	var ready_i := -1
	var queued := -1
	for i in _views.size():
		if _views[i].side == 0 and _ultimate_ready(i):
			if Combat.engine.is_ultimate_queued(i):
				queued = i if queued < 0 else queued
			elif ready_i < 0:
				ready_i = i
	if queued >= 0:
		coach.point(_views[queued].body, Terms.t("tutorial_ult_queued", {"name": _battle.units[queued].name}))
	elif ready_i >= 0 and not _guide_fired:
		coach.point(_views[ready_i].body, Terms.t("tutorial_click_ult", {"name": _battle.units[ready_i].name}))
	elif _guide_fired:
		if not coach.is_pointing_at(_auto_button):
			coach.point(_auto_button, Terms.t("tutorial_ult_done"))
	else:
		coach.point(null, Terms.t("tutorial_gauge"))

## The line over a friend's gauge: "Ultimate" normally; in a manual battle with a full gauge it asks for a
## click (amber border) or says the Ultimate is coming (thicker gold border)
func _refresh_ultimate(index: int) -> void:
	var view: Dictionary = _views[index]
	if view.ult_label == null or view.side != 0:
		return
	var style: StyleBoxFlat = view.style
	var waiting := _live and _manual and _ultimate_ready(index)
	view.body.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if waiting else Control.CURSOR_ARROW
	if not waiting:
		view.ult_label.text = Terms.t("battle_ult_full") if view.energy_full else Terms.t("battle_energy")
		view.ult_label.add_theme_color_override("font_color", Color("#fde047") if view.energy_full else UITheme.TEXT_DIM)
		_card_border(style, 0, ALLY_COLOR, 1)
		return
	var queued: bool = Combat.engine.is_ultimate_queued(index)
	view.ult_label.text = Terms.t("battle_ult_queued" if queued else "battle_ult_ready")
	view.ult_label.add_theme_color_override("font_color", Color("#fde047") if queued else Color("#facc15"))
	_card_border(style, 0, Color("#fde047") if queued else Color("#f59e0b"), 3 if queued else 2)

## The card frame: `width` all round plus a thicker stripe on the outer edge (left for friends, right for enemies)
func _card_border(style: StyleBoxFlat, side: int, color: Color, width: int) -> void:
	style.border_color = color
	style.set_border_width_all(width)
	if side == 0:
		style.border_width_left = width + 3
	else:
		style.border_width_right = width + 3

## Between waves: the cleared enemies leave, a "Battle 2/3" banner (or the boss banner) shows,
## and the next wave's enemies slide in from the right. A wave with its own banner (the animatronics) gets a
## jumpscare entrance instead.
func _animate_wave(event: Dictionary) -> void:
	var wave: int = event.wave
	_wave_label.text = Terms.t("battle_wave", {"current": wave + 1, "total": event.wave_count})
	_wave_pips.current = wave
	var wave_text := Terms.t("battle_wave_boss" if event.boss else "battle_wave_banner", {"current": wave + 1, "total": event.wave_count})
	if event.banner.is_empty():
		_show_banner(wave_text)
		Sound.play("wave")
	var arriving: Array[Dictionary] = []
	for view in _views:
		if view.side != 1:
			continue
		view.slot.visible = view.wave == wave
		if view.wave == wave:
			view.body.size = CARD_SIZE  # in case anything stretched it while it was hidden
			view.body.position.x = 320.0
			view.body.modulate.a = 0.0
			arriving.append(view)
	_apply_state(event)
	_append_lines(event)
	if not event.banner.is_empty():
		await _jumpscare_entrance(arriving, Terms.t(event.banner), wave_text)
		return
	await _wait(1.5)
	if not arriving.is_empty():
		var t := create_tween().set_parallel()
		for i in arriving.size():
			var body: Control = arriving[i].body
			t.tween_property(body, "position:x", 0.0, _dur(2)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT).set_delay(_dur(0.4 * i))
			t.tween_property(body, "modulate:a", 1.0, _dur(1.2)).set_delay(_dur(0.4 * i))
		await t.finished
	await _wait(2)

## Lights out, then the scare: while the title slams in, every arriving card springs out of nowhere, glowing
## red-hot, each with its own burst of sparks
func _jumpscare_entrance(arriving: Array[Dictionary], title: String, subtitle: String) -> void:
	Sound.play("fnaf power outage")  # Audio/sfx/FNAF Power Outage.mp3, as the lights flicker out
	await _jumpscare.blackout(_speed)
	Sound.play("jumpscare")
	var total := _jumpscare.reveal(title, subtitle, _jumpscare.get_parent())
	if not arriving.is_empty():
		var t := create_tween().set_parallel()
		for i in arriving.size():
			var view: Dictionary = arriving[i]
			var body: Control = view.body
			body.position.x = 0.0
			body.pivot_offset = CARD_SIZE / 2.0
			body.scale = Vector2(0.15, 0.15)
			body.modulate = Color(2.4, 0.7, 0.7, 0.0)  # over-bright red, fading to normal
			var delay := _dur(0.5 * i)
			var center: Vector2 = view.slot.global_position - _jumpscare.global_position + CARD_SIZE / 2.0
			t.tween_callback(_jumpscare.pop_burst.bind(center)).set_delay(delay)
			t.tween_property(body, "modulate:a", 1.0, _dur(0.3)).set_delay(delay)
			t.tween_property(body, "scale", Vector2.ONE, _dur(4)).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT).set_delay(delay)
			t.tween_property(body, "modulate", Color.WHITE, _dur(3)).set_delay(delay + _dur(0.3))
		await t.finished
	# Let the title finish its hold and fade before the fight starts
	var rest := total - _dur(4 + 0.5 * maxi(arriving.size() - 1, 0))
	if rest > 0.0:
		var hold := create_tween()
		hold.tween_interval(rest)
		await hold.finished
	await _wait(1)

func _animate(event: Dictionary) -> void:
	if event.kind == "wave":
		await _animate_wave(event)
		return
	var actor: Dictionary = _views[event.actor]
	var direction := 1.0 if actor.side == 0 else -1.0
	var fx_color := BattleFX.ALLY_FX if actor.side == 0 else BattleFX.ENEMY_FX
	# A pulsing outline marks whoever is acting
	_fx.set_marker(actor.body, CARD_SIZE, fx_color)
	if event.kind == "ultimate" and actor.side == 0 and coach and _manual:
		_guide_fired = true
	if event.kind == "ultimate":
		# Everything waits for the cut-in, then the caster's card flashes gold and the skill lands
		var caster: Dictionary = _battle.units[event.actor]
		Sound.play("ultimate")
		await _cut_in.play(caster.data, caster.name, event.skill, caster.side == 0, _speed)
		_fx.aura(_center(actor))
		await _flash(actor.body, Color(1.9, 1.6, 0.5), 1.5)
	elif event.kind == "idle":
		_float_text(actor, Terms.t("battle_idle"), Color("#fde68a"), 30)
		await _flash(actor.body, Color(1.6, 1.3, 0.6), 2)
	elif event.kind == "charge":
		_float_text(actor, Terms.t("battle_atomic_charge"), Color("#c084fc"), 30)
		await _flash(actor.body, Color(1.3, 0.9, 1.8), 2)
	elif event.kind == "heal":
		_float_text(actor, Terms.t("battle_heal_turn"), Color("#86efac"), 30)
		await _flash(actor.body, Color(0.8, 1.7, 1.0), 2)
	elif event.kind == "sleep":
		var stunned: bool = event.get("stunned_turn", false)
		_float_text(actor, Terms.t("battle_stunned_turn" if stunned else "battle_sleep"), Color("#fde047") if stunned else Color("#93c5fd"), 30)
		await _flash(actor.body, Color(0.6, 0.8, 1.6), 2)
	var attacking: bool = not event.hits.is_empty()
	# Front-row fighters lunge in and slash; the back row recoils and fires glowing bolts at every target;
	# a transformed horse (Roki's Umamusume) pukes on them instead
	var melee: bool = actor.vanguard
	var puking: bool = actor.horse
	if attacking:
		var forward := create_tween().set_parallel()
		var lunge := BUMP_DISTANCE * direction * (1.0 if melee else -0.35)
		forward.tween_property(actor.body, "position:x", lunge, _dur(1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		forward.tween_property(actor.body, "modulate", Color(1.5, 1.5, 1.5), _dur(1))
		if melee and not puking:
			Sound.play("swing", -2.0)
		await forward.finished
		if puking or not melee:
			Sound.play("puke" if puking else "shoot")
			# All shots fly together; wait for them to land
			var flight := 0.0
			for hit in event.hits:
				var to := _center(_views[hit.target])
				flight = _fx.puke(_center(actor), to) if puking else _fx.bolt(_center(actor), to, fx_color)
			if puking:
				_float_text(actor, Terms.t("battle_puke"), Color("#a3e635"), 60)
			var land := create_tween()
			land.tween_interval(flight)
			await land.finished
	for hit in event.hits:
		if melee and hit.hit and not puking:
			_fx.slash(_center(_views[hit.target]), fx_color, direction)
		_react(_views[hit.target], hit, fx_color)
	for target in event.get("off_balance", []):
		_float_text(_views[target], Terms.t("battle_off_balance"), Color("#fb923c"), 34)
	for heal in event.heals:
		Sound.play("heal")
		_fx.heal(_center(_views[heal.target]))
		_float_text(_views[heal.target], "+%d" % heal.amount, Color("#4ade80"))
	for target in event.get("slept", []):
		_float_text(_views[target], Terms.t("battle_slept"), Color("#93c5fd"), 60)
	for caster in event.get("winnie", []):
		_float_text(_views[caster], Terms.t("battle_winnie"), Color("#f9a8d4"), 60)
	for target in event.get("drunk", []):
		_float_text(_views[target], Terms.t("battle_drunk"), Color("#fbbf24"), 60)
	for target in event.get("berserk", []):
		_float_text(_views[target], Terms.t("battle_berserk"), Color("#ef4444"), 60)
	for target in event.get("its_raw", []):
		_float_text(_views[target], Terms.t("battle_its_raw"), Color("#f87171"), 60)
	for target in event.get("blinded", []):
		_float_text(_views[target], Terms.t("battle_blinded"), Color("#fde047"), 60)
	for drain in event.get("drains", []):
		var drain_color := Color("#dc2626") if drain.get("bleed", false) else Color("#84cc16") if drain.get("poison", false) \
			else Color("#fb923c") if drain.get("blast", false) else Color("#c084fc")
		Sound.play("hit", -7.0, 0.8)  # a softer, duller hit for damage over time
		_fx.hit(_center(_views[drain.target]), drain_color)
		_float_text(_views[drain.target], "-%d" % drain.amount, drain_color, 30)
	for target in event.get("grubbed", []):
		_float_text(_views[target], Terms.t("battle_grubbed"), Color("#fb923c"), 60)
	for target in event.get("decayed", []):
		_float_text(_views[target], Terms.t("battle_decay"), Color("#a3e635"), 60)
	for ally in event.get("cringed", []):
		_float_text(_views[ally], Terms.t("battle_cringe"), Color("#d9f99d"), 60)
	for target in event.get("bled", []):
		_float_text(_views[target], Terms.t("battle_bleed"), Color("#dc2626"), 60)
	for target in event.get("poisoned", []):
		_float_text(_views[target], Terms.t("battle_poison"), Color("#84cc16"), 60)
	for kittay in event.get("mid_fingered", []):
		_float_text(_views[kittay], Terms.t("battle_mid_fingered"), Color("#f472b6"), 60)
	for target in event.get("deafened", []):
		_float_text(_views[target], Terms.t("battle_deafened"), Color("#facc15"), 60)
	for kittay in event.get("blended", []):
		_float_text(_views[kittay], Terms.t("battle_blender"), Color("#c084fc"), 60)
	for rat in event.get("lured", []):
		_float_text(_views[rat], Terms.t("battle_lured"), Color("#fde047"), 60)
	for rat in event.get("rat_blocked", []):
		_float_text(_views[rat], Terms.t("battle_rat_block"), Color("#93c5fd"), 34)
	for target in event.get("hatted", []):
		_float_text(_views[target], Terms.t("battle_hat"), Color("#c4b5fd"), 60)
	for target in event.get("hat_trick", []):
		_float_text(_views[target], Terms.t("battle_hat_trick"), Color("#f0abfc"), 60, 30)
		_fx.shake(_arena, 8.0, 0.3)
	for quinn in event.get("until_next_time", []):
		_float_text(_views[quinn], Terms.t("battle_until_next_time"), Color("#fde68a"), 60)
	for target in event.get("storm_splash", []):
		_float_text(_views[target], Terms.t("battle_storm_splash"), Color("#7dd3fc"), 60)
	for target in event.get("torsion", []):
		_float_text(_views[target], Terms.t("battle_torsion"), Color("#c084fc"), 34)
	for target in event.get("stunned", []):
		_float_text(_views[target], Terms.t("battle_stunned"), Color("#fde047"), 60)
	for grey in event.get("spotted", []):
		_float_text(_views[grey], Terms.t("battle_spotted"), Color("#f87171"), 60, 30)
	for ally in event.get("bird_up", []):
		_float_text(_views[ally], Terms.t("battle_bird_up"), Color("#fde68a"), 60)
	for answer in event.get("six_seven", []):
		_float_text(_views[answer], Terms.t("battle_six_seven"), Color("#facc15"), 60, 30)
	for lag in event.get("nimble_dodge", []):
		_float_text(_views[lag], Terms.t("battle_nimble_dodge"), Color("#7dd3fc"), 34)
	for lag in event.get("double_time", []):
		_float_text(_views[lag], Terms.t("battle_double_time"), Color("#38bdf8"), 60, 30)
	for shige in event.get("mind_rot", []):
		_float_text(_views[shige], Terms.t("battle_mind_rot"), Color("#a3e635"), 60, 30)
	for target in event.get("pool_splash", []):
		_float_text(_views[target], Terms.t("battle_pool_splash"), Color("#38bdf8"), 60)
	for form in event.get("protagonist", []):
		var real: bool = form.real
		_float_text(_views[int(form.unit)], Terms.t("battle_protagonist_real" if real else "battle_protagonist_fent"),
			Color("#a78bfa") if real else Color("#a3e635"), 60, 30)
	for revived in event.get("arise", []):
		_shadow_soldier(_views[revived])
	for sung in event.get("shadow_realm", []):
		_float_text(_views[sung], Terms.t("battle_shadow_realm"), Color("#a78bfa"), 60, 30)
	for sung in event.get("fent_self", []):
		_float_text(_views[sung], Terms.t("battle_fent_self"), Color("#a3e635"), 60, 30)
	for penguin in event.get("fart", []):
		_float_text(_views[penguin], Terms.t("battle_fart"), Color("#bef264"), 60, 30)
	for penguin in event.get("diarrhea", []):
		_float_text(_views[penguin], Terms.t("battle_diarrhea"), Color("#a16207"), 60, 30)
	for might in event.get("texas_smash", []):
		_float_text(_views[might], Terms.t("battle_texas_smash"), Color("#facc15"), 60, 30)
	for target in event.get("domain_splash", []):
		_float_text(_views[target], Terms.t("battle_domain_splash"), Color("#c084fc"), 60)
	for visit in event.get("mom_visit", []):
		_float_text(_views[int(visit.target)], Terms.t("battle_mom_visit", {"visit": int(visit.visit)}), Color("#f9a8d4"), 60)
	for snake in event.get("snake_mode", []):
		_float_text(_views[snake], Terms.t("battle_snake_mode"), Color("#a3a3a3"), 60, 30)
	for flame in event.get("french", []):
		_float_text(_views[flame], Terms.t("battle_french"), Color("#60a5fa"), 60, 30)
	for ally in event.get("nein", []):
		_float_text(_views[ally], Terms.t("battle_nein"), Color("#fde68a"), 60)
	for ally in event.get("nein_block", []):
		_float_text(_views[ally], Terms.t("battle_nein_block"), Color("#fde68a"), 60, 30)
	for ally in event.get("bread", []):
		_float_text(_views[ally], Terms.t("battle_bread"), Color("#d6a35c"), 34)
	for shura in event.get("deflection_counter", []):
		_float_text(_views[shura], Terms.t("battle_deflection_counter"), Color("#f87171"), 60, 30)
	for yama in event.get("i_love_gyatt", []):
		_float_text(_views[yama], Terms.t("battle_i_love_gyatt"), Color("#f472b6"), 60, 30)
	for fox in event.get("whip_crack", []):
		_float_text(_views[fox], Terms.t("battle_whip_crack"), Color("#fb923c"), 60, 30)
	for fox in event.get("fluff_reset", []):
		_float_text(_views[fox], Terms.t("battle_fluff_reset"), Color("#e5e7eb"), 34)
	for noel in event.get("atomic", []):
		_float_text(_views[noel], Terms.t("battle_atomic"), Color("#c084fc"), 60, 30)
	for noel in event.get("atomic_blast", []):
		_float_text(_views[noel], Terms.t("battle_atomic_blast"), Color("#f0abfc"), 60, 36)
		_fx.shake(_arena, 10.0, 0.4)
	for target in event.get("capy_marked", []):
		_float_text(_views[target], Terms.t("battle_capy_mark"), Color("#d6a35c"), 60)
	for target in event.get("capy_splash", []):
		_float_text(_views[target], Terms.t("battle_capy_splash"), Color("#d6a35c"), 60, 30)
	for ghost in event.get("overdrive", []):
		_float_text(_views[ghost], Terms.t("battle_overdrive"), Color("#38bdf8"), 60, 30)
	for ghost in event.get("overdrive_boom", []):
		_float_text(_views[ghost], Terms.t("battle_overdrive_boom"), Color("#fb923c"), 60, 36)
		_fx.shake(_arena, 10.0, 0.4)
	for target in event.get("provoked", []):
		_float_text(_views[target], Terms.t("battle_provoked"), Color("#ef4444"), 60)
	for target in event.get("cat_lured", []):
		_float_text(_views[target], Terms.t("battle_cat_lured"), Color("#fdba74"), 60)
	for target in event.get("headshot", []):
		_float_text(_views[target], Terms.t("battle_headshot"), Color("#f87171"), 60, 30)
		_fx.shake(_arena, 6.0, 0.25)
	for target in event.get("nearsighted_spot", []):
		_float_text(_views[target], Terms.t("battle_nearsighted_spot"), Color("#93c5fd"), 34)
	for snake in event.get("snuck", []):
		_float_text(_views[snake], Terms.t("battle_snuck"), Color("#d4d4d4"), 34)
	for horse in event.get("horse", []):
		_float_text(_views[horse], Terms.t("battle_horse"), Color("#f0abfc"), 60, 30)
	if attacking:
		var back := create_tween().set_parallel()
		back.tween_property(actor.body, "position:x", 0.0, _dur(1.2)).set_trans(Tween.TRANS_QUAD)
		back.tween_property(actor.body, "modulate", Color.WHITE, _dur(1.2))
		await back.finished
	# Chain steps happen inside the same action: assists strike, then guard charges fill backline gauges
	for assist in event.get("assists", []):
		await _animate_assist(assist)
	for charge in event.get("guard_charges", []):
		_flash(_views[charge.tank].body, Color(0.7, 1.2, 1.9), 2)
		for ally in charge.allies:
			_float_text(_views[ally], Terms.t("battle_guard_charge"), Color("#facc15"))
	if event.has("combo"):
		await _animate_combo(event.combo)
	_apply_state(event)
	_append_lines(event)
	await _wait(1.5)
	_fx.set_marker(null, Vector2.ZERO)

## A combo: the members' cards flash gold, the cut-in plays (the combo's own picture and name if it has one, else a
## split screen of the members), then its hits, heals, revives, sleeps and charged gauges land, and any counters
## it provoked play out
func _animate_combo(combo: Dictionary) -> void:
	var data: ComboData = combo.get("data")
	var members: Array[CharacterData] = []
	var names := PackedStringArray()
	var ally := true
	for i in combo.members:
		var unit: Dictionary = _battle.units[i]
		ally = unit.side == 0
		names.append(unit.name)
		if unit.data is CharacterData:
			members.append(unit.data)
		_flash(_views[i].body, Color(1.9, 1.6, 0.5), 1.5)
	var title: String = data.title() if data else combo.name
	var picture: Texture2D = data.get_cutin() if data else null
	Sound.play(data.sound.to_lower() if data and not data.sound.is_empty() else "ultimate")
	if picture:
		await _cut_in.play(null, " & ".join(names), title, ally, _speed, picture, UITheme.GOLD)
	else:
		await _combo_cut_in.play(title, members, names, ally, _speed)
	for i in combo.members:
		_fx.aura(_center(_views[i]))
	var fx_color := BattleFX.ALLY_FX if ally else BattleFX.ENEMY_FX
	if not combo.hits.is_empty():
		_fx.shake(_arena, 14.0, 0.45)
	var struck := {}
	var flurry: bool = combo.hits.size() > 8  # many quick slashes (Dismantle & Cleave): a rapid beat between them
	for hit in combo.hits:
		if struck.has(hit.target):
			struck.clear()
			await _wait(0.4 if flurry else 1.5)  # e.g. Astolfo Brothers: a second hit on the same enemy lands after the first
		struck[hit.target] = true
		var target: Dictionary = _views[hit.target]
		_fx.slash(_center(target), UITheme.GOLD, 1.0 if ally else -1.0)
		_react(target, hit, fx_color)
	for i in combo.revived:
		var view: Dictionary = _views[i]
		view.slot.modulate.a = 1.0
		view.body.modulate = Color.WHITE
		Sound.play("heal")
		_fx.aura(_center(view))
		_float_text(view, Terms.t("battle_combo_revive"), Color("#fde68a"), 30, 28)
	for heal in combo.heals:
		Sound.play("heal")
		_fx.heal(_center(_views[heal.target]))
		_float_text(_views[heal.target], "+%d" % heal.amount, Color("#4ade80"))
	for target in combo.get("slept", []):
		_float_text(_views[target], Terms.t("battle_slept"), Color("#93c5fd"), 60)
	for target in combo.get("blinded", []):
		_float_text(_views[target], Terms.t("battle_blinded"), Color("#fde047"), 60)
	for i in combo.charged:
		_float_text(_views[i], Terms.t("battle_combo_charged"), Color("#facc15"), 30)
	await _wait(2)
	for assist in combo.assists:
		await _animate_assist(assist)

## A card's centre in the effects layer's coordinates
func _center(view: Dictionary) -> Vector2:
	return _fx.to_local_center(view.body, CARD_SIZE)

## A rearguard friend leaps in: ASSIST! banner, a cyan bump toward the enemy, then the follow-up hit
func _animate_assist(assist: Dictionary) -> void:
	var helper: Dictionary = _views[assist.actor]
	var direction := 1.0 if helper.side == 0 else -1.0
	var banner_key := "battle_counter_banner" if assist.get("counter", false) else "battle_assist_banner"
	_show_banner(Terms.t(banner_key, {"name": _battle.units[assist.actor].name}))
	var forward := create_tween().set_parallel()
	forward.tween_property(helper.body, "position:x", BUMP_DISTANCE * 1.4 * direction, _dur(0.8)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	forward.tween_property(helper.body, "modulate", Color(0.6, 1.6, 1.9), _dur(0.8))
	Sound.play("swing", -2.0, 1.2)
	await forward.finished
	var color := BattleFX.ALLY_FX if helper.side == 0 else BattleFX.ENEMY_FX
	_fx.slash(_center(_views[assist.target]), Color("#7df9ff"), direction)
	_react(_views[assist.target], {"hit": true, "damage": assist.damage}, color)
	var back := create_tween().set_parallel()
	back.tween_property(helper.body, "position:x", 0.0, _dur(1)).set_trans(Tween.TRANS_QUAD)
	back.tween_property(helper.body, "modulate", Color.WHITE, _dur(1))
	await back.finished

## Target reaction: sparks and an impact ring, a shake and red flash with a damage number, or a MISS.
## Crits are gold, bigger, and shake the whole arena.
func _react(view: Dictionary, hit: Dictionary, fx_color: Color = BattleFX.ALLY_FX) -> void:
	if hit.get("blocked", false):
		return  # Nein!: the shield's own float text covers it
	if hit.get("deflected", false):
		Sound.play("miss")
		_float_text(view, Terms.t("battle_deflected"), Color("#f87171"), 0.0, 30)
		return
	if not hit.hit:
		Sound.play("miss")
		_float_text(view, Terms.t("battle_miss"), Color("#cbd5e1"))
		return
	var crit: bool = hit.get("crit", false)
	Sound.play("crit" if crit else "hit")
	_fx.hit(_center(view), fx_color, crit)
	if crit:
		_float_text(view, Terms.t("battle_crit", {"damage": hit.damage}), Color("#fde047"), 0.0, 32)
		_fx.shake(_arena, 10.0, 0.35)
	else:
		_float_text(view, "-%d" % hit.damage, Color("#fca5a5"))
	var shake := create_tween()
	for offset in [9.0, -9.0, 6.0, -4.0, 0.0]:
		shake.tween_property(view.body, "position:x", offset, _dur(0.25))
	var flash := create_tween()
	flash.tween_property(view.body, "modulate", Color(1.9, 0.5, 0.5), _dur(0.5))
	flash.tween_property(view.body, "modulate", Color.WHITE, _dur(0.8))

func _flash(node: Control, color: Color, steps: float) -> void:
	var t := create_tween()
	t.tween_property(node, "modulate", color, _dur(steps / 2))
	t.tween_property(node, "modulate", Color.WHITE, _dur(steps / 2))
	await t.finished

## Floating text over a card that pops in big and settles; y_offset stacks several labels (e.g. CRIT and
## OFF-BALANCE) without overlap. A little random sideways jitter keeps repeated numbers from stacking exactly.
func _float_text(view: Dictionary, text: String, color: Color, y_offset: float = 0.0, font_size: int = 24) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 7)
	_overlay.add_child(label)
	var body: Control = view.body
	label.position = body.global_position - _overlay.global_position \
		+ Vector2(CARD_SIZE.x * 0.3 + randf_range(-14.0, 14.0), 8 + y_offset)
	label.pivot_offset = label.get_combined_minimum_size() / 2.0
	label.scale = Vector2(1.7, 1.7)
	var t := create_tween().set_parallel()
	t.tween_property(label, "scale", Vector2.ONE, _dur(0.9)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:y", label.position.y - 42, _dur(4))
	t.tween_property(label, "modulate:a", 0.0, _dur(4)).set_delay(_dur(1.5))
	t.chain().tween_callback(label.queue_free)

func _show_banner(text: String) -> void:
	_banner.text = text
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 1.0, _dur(1))
	t.tween_interval(_dur(4))
	t.tween_property(_banner, "modulate:a", 0.0, _dur(1.5))

## Bars, gauges, buffs and knockouts from the engine's state after this action. HP bars drain smoothly with a
## red trail; a friend or enemy dropping to 0 bursts into shards and fades; a full Ultimate gauge glows.
func _apply_state(event: Dictionary) -> void:
	for i in _views.size():
		var view: Dictionary = _views[i]
		var s: Dictionary = event.state[i]
		if view.hp_bar:
			view.hp_bar.set_hp(s.hp, _dur(1.2))
			if view.hp > 0 and s.hp <= 0 and view.slot.visible:
				_knockout(view)
			elif s.hp > 0:
				view.slot.modulate.a = 1.0
			view.hp = s.hp
		var form_art: String = s.get("form_art", "")
		if form_art != view.get("form_art", "") and view.data != null:
			# A permanent transformation (e.g. SungJingWoo's Protagonist): swap in that form's picture
			view.form_art = form_art
			var path := CharacterData.find_art(CharacterData.ART_DIR, form_art)
			view.art.set_character(view.data, load(path) as Texture2D if not path.is_empty() else null)
			_fx.aura(_center(view))
			_flash(view.body, Color(2.0, 1.6, 2.0), 2)
		var alt: bool = s.get("alt", false)
		view.horse = s.get("horse", false)  # the horse pukes instead of slashing
		if alt != view.get("alt", false):
			view.alt = alt
			_transform(view, alt)
		if view.energy_bar:
			view.energy_bar.value = s.energy
			view.energy_full = s.energy >= view.energy_bar.max_value
			_refresh_ultimate(i)
		view.buffs.text = ", ".join(s.buffs)
	_update_guide()
	_update_clash()

## Both teams' HP in the HUD: friends all fight together; enemies count only the wave on the field
func _update_clash() -> void:
	if _clash == null:
		return
	var totals := [0.0, 0.0, 0.0, 0.0]  # ally hp, ally max, enemy hp, enemy max
	for view in _views:
		if view.side == 1 and not view.slot.visible:
			continue
		var k := 0 if view.side == 0 else 2
		totals[k] += maxf(float(view.hp), 0.0)
		totals[k + 1] += float(view.max_hp)
	_clash.set_values(totals[0] / maxf(totals[1], 1.0), totals[2] / maxf(totals[3], 1.0))

## A transformation starts or ends (e.g. Roki's horse form): the card flashes and bursts and its picture swaps to
## the character's alt form, or back
func _transform(view: Dictionary, on: bool) -> void:
	var data: CharacterData = view.data
	if data == null:
		return
	var alt := data.get_alt_form() if on else null
	if on and alt == null:
		return  # no transformed picture: keep the normal one
	view.art.set_character(data, alt)
	_fx.aura(_center(view))
	_flash(view.body, Color(2.0, 1.6, 2.0) if on else Color(1.6, 1.6, 1.6), 2)

## Passive Arise (SungJingWoo): the fallen friend rises as a shadow soldier. A portal and black smoke under the card,
## the card climbs out of a pitch-black silhouette, and for the rest of the fight it keeps a violet tint, a violet
## border and shadow wisps drifting off it.
func _shadow_soldier(view: Dictionary) -> void:
	Sound.play("okiro_solo_leveling")
	view.slot.modulate.a = 1.0
	_fx.shadow_rise(_center(view), CARD_SIZE)
	view.body.modulate = Color(0, 0, 0, 1)
	var t := create_tween()
	t.tween_property(view.body, "modulate", Color(0.35, 0.2, 0.6), _dur(0.6))
	t.tween_property(view.body, "modulate", Color.WHITE, _dur(0.6))
	# The tint lives on the portrait (flashes only reset the card's own colour) and the border
	view.art.modulate = Color(0.62, 0.5, 1.0)
	view.style.border_color = Color("#8b5cf6")
	view.style.shadow_color = Color(0.55, 0.36, 0.96, 0.6)
	view.style.shadow_size = 10
	if not is_instance_valid(view.get("wisps")):
		view.wisps = _fx.shadow_wisps(view.body, CARD_SIZE)
	view.wisps.emitting = true
	_float_text(view, Terms.t("battle_arise"), Color("#c4b5fd"), 30, 28)

func _knockout(view: Dictionary) -> void:
	if is_instance_valid(view.get("wisps")):
		view.wisps.emitting = false
	Sound.play("knockout")
	_fx.knockout(_center(view), BattleFX.ALLY_FX if view.side == 0 else BattleFX.ENEMY_FX)
	var t := create_tween().set_parallel()
	t.tween_property(view.slot, "modulate:a", DOWNED_ALPHA, _dur(2))
	t.tween_property(view.body, "modulate", Color(0.55, 0.55, 0.6), _dur(2))

func _append_lines(event: Dictionary) -> void:
	for line in event.lines:
		_log.append_text(_style_line(line) + "\n")

## Colours a plain log line for the RichTextLabel: names by side (blue friends, red enemies), numbers bold
## (green on heals, gold on crits), knockouts red, wave headers centred gold. Names become placeholder characters
## first so a short name can't match inside a longer one ("Drunk Person" in "Drunk Person A") or inside tags.
func _style_line(line: String) -> String:
	var text := line.replace("[", char(0xE100)).replace("]", char(0xE101))  # player text can't break the BBCode
	for i in _log_names.size():
		text = text.replace(_log_names[i].name, char(0xE000 + i))
	if text.begins_with("---"):
		return "[center][b][color=#fde68a]%s[/color][/b][/center]" % _expand_names(text)
	var number_color := "#ffb86b"
	if text.contains(" recovers "):  # log_heal
		number_color = "#6ee7a0"
	elif line.contains("critical"):
		number_color = "#fde047"
	text = _log_number.sub(text, "[b][color=%s]$0[/color][/b]" % number_color, true)
	text = text.replace(" is down!", " [color=#f87171][b]is down![/b][/color]")
	return _expand_names(text)

func _expand_names(text: String) -> String:
	for i in _log_names.size():
		var color := "#7cc4ff" if _log_names[i].side == 0 else "#ff8a80"
		var safe: String = _log_names[i].name.replace("[", "[lb]")
		text = text.replace(char(0xE000 + i), "[b][color=%s]%s[/color][/b]" % [color, safe])
	return text.replace(char(0xE100), "[lb]").replace(char(0xE101), "[rb]")

## The battle is over: the result goes in the log, then the results screen opens on top with the rewards and
## the Again / Home buttons
func _finish() -> void:
	_fx.set_marker(null, Vector2.ZERO)
	battle_finished.emit(_battle.get("report", {}))
	var win: bool = _battle.win
	_log.append_text("[center][b][font_size=18][color=%s]%s[/color][/font_size][/b][/center]" % [
		"#fde047" if win else "#f87171", "\n".join(_battle.end_lines).replace("[", "[lb]")])
	var report: Dictionary = _battle.report
	# The results screen shows what was won as icon cards (`items`, see BattleResults.RewardCard) and everything
	# else that happened as short lines of text under them (`lines`)
	var lines := PackedStringArray()
	var items: Array[Dictionary] = []
	if report.get("world_boss", false):
		lines.append(Terms.t("boss_result_damage", {"damage": Terms.number(report.damage)}))
	elif win:
		if int(report.money) > 0:
			items.append({"kind": "money", "amount": int(report.money), "label": Terms.term("money")})
		for key in report.materials:
			if int(report.materials[key]) > 0:
				items.append({"kind": key, "amount": int(report.materials[key]), "label": Terms.material_name(key, int(report.materials[key]))})
		for e: EquipmentData in report.get("drop_gear", []):
			items.append({"gear": e, "amount": 1, "label": e.display_name})
		if report.exp > 0:
			items.append({"kind": "exp", "amount": int(report.exp), "label": Terms.t("results_exp_each")})
		if report.get("account_exp", 0) > 0:
			items.append({"kind": "account_exp", "amount": int(report.account_exp), "label": Terms.t("results_account_exp"),
				"note": Terms.t("results_note_first_clear") if report.get("account_first_clear", false) else ""})
		for up in report.level_ups:
			lines.append(Terms.t("battle_level_up", {"name": up.name, "lv": up.level}))
		if report.get("account_level_up", 0) > 0:
			lines.append(Terms.t("battle_account_level_up", {"lv": report.account_level_up,
				"limit": GameState.team_cost_limit_at(report.account_level_up)}))
		if not String(report.get("daily_bonus", "")).is_empty():
			lines.append(report.daily_bonus)
		if report.get("challenge_repeat", false):
			lines.append(Terms.t("challenge_repeat"))
		if int(report.get("endless_tips", 0)) > 0:
			lines.append(Terms.t("endless_result_tips", {"amount": int(report.endless_tips)}))
	elif report.get("endless", false):
		lines.append(Terms.t("endless_result_over" if report.get("endless_over", false) else "endless_result_lost"))
	elif report.card_drops > 0:  # beat the animatronics, then lost a later wave: their card still counts
		lines.append(Terms.t("battle_defeat_partial"))
	else:
		lines.append(Terms.t("battle_defeat"))
	# Credit Cards from every source on one card, tagged with where they came from ("Bonus" for a mix)
	var card_sources := []
	for source in [["first_clear_cards", "results_note_first_clear"], ["star_cards", "results_note_stars"],
			["card_drops", "results_note_animatronics"], ["challenge_cards", "results_note_challenge"]]:
		if int(report.get(source[0], 0)) > 0:
			card_sources.append(source)
	if not card_sources.is_empty():
		var total := 0
		for source in card_sources:
			total += int(report[source[0]])
		items.insert(mini(items.size(), 1 + report.get("materials", {}).size()), {"kind": "credit_card", "amount": total,
			"label": Terms.credit_card_word(total),
			"note": Terms.t(card_sources[0][1]) if card_sources.size() == 1 else Terms.t("results_note_bonus")})
	if int(report.get("event_currency", 0)) > 0:
		items.append({"kind": "event", "amount": int(report.event_currency), "label": str(report.event_currency_name),
			"tint": report.get("event_currency_color", Color("#f59e0b"))})
	for up in report.get("bond_ups", []):
		lines.append(Terms.t("battle_bond_up", {"name": up.name, "bond": up.bond}))

	await _wait(3)  # a beat to see the final blow land
	_results = BattleResults.new()
	_arena.add_child(_results)
	_results.again_pressed.connect(again_pressed.emit)
	_results.home_pressed.connect(home_pressed.emit)
	_results.next_pressed.connect(next_pressed.emit)
	_results.next_text = next_text
	_results.continue_text = continue_text
	_results.open(_battle, _stage_name, lines, items)
	if not _note.is_empty():
		_results.set_note(_note)
	# Auto Run: after a win, the next run starts by itself (Return Home stops the series)
	if auto_next and win and not next_text.is_empty():
		_results.set_note(Terms.t("auto_run_next_in", {"seconds": AUTO_NEXT_SECONDS}))
		var t := create_tween()
		t.tween_interval(AUTO_NEXT_SECONDS)
		t.tween_callback(next_pressed.emit)

## A line under the results, e.g. the world boss server's answer, which can arrive before or after the battle ends
func set_note(text: String) -> void:
	_note = text
	if _results:
		_results.set_note(text)

## An HP bar that drains smoothly: the green fill moves first, a red "damage trail" follows a moment later
## (heals: the trail jumps up and the fill catches up)
class HpBar extends Control:
	var _max := 1.0
	var _hp := 1.0
	var _trail := 1.0
	var _tween: Tween

	func _init(max_hp: int, start_hp: int = -1) -> void:
		_max = maxf(float(max_hp), 1.0)
		_hp = _max if start_hp < 0 else clampf(float(start_hp), 0.0, _max)
		_trail = _hp
		custom_minimum_size = Vector2(0, 17)

	func set_hp(value: float, seconds: float) -> void:
		if is_equal_approx(value, _hp):
			return
		if _tween:
			_tween.kill()
		_tween = create_tween()
		if value < _hp:
			_tween.tween_method(_set_fill, _hp, value, seconds * 0.35).set_ease(Tween.EASE_OUT)
			_tween.tween_interval(seconds * 0.25)
			_tween.tween_method(_set_trail, _trail, value, seconds * 0.5).set_trans(Tween.TRANS_SINE)
		else:
			_trail = value
			_tween.tween_method(_set_fill, _hp, value, seconds * 0.6).set_trans(Tween.TRANS_SINE)

	func _set_fill(v: float) -> void:
		_hp = v
		queue_redraw()

	func _set_trail(v: float) -> void:
		_trail = v
		queue_redraw()

	## Slanted track, red trail, the fill (green / amber / red by share) with a shine, tick marks every 10%, and
	## the HP numbers inside
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UITheme.box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.14), 1, 3), r)
		var inner := r.grow(-2)
		var share := clampf(_hp / _max, 0.0, 1.0)
		var trail := clampf(_trail / _max, 0.0, 1.0)
		if trail > share:
			draw_rect(Rect2(inner.position, Vector2(inner.size.x * trail, inner.size.y)), Color("#ef4444"))
		var color := Color("#22c55e") if share > 0.5 else Color("#f59e0b") if share > 0.25 else Color("#ef4444")
		if share > 0.0:
			var fill := Rect2(inner.position, Vector2(inner.size.x * share, inner.size.y))
			UITheme.draw_vertical_gradient(self, fill, color.lightened(0.25), color.darkened(0.25))
			draw_rect(Rect2(fill.position, Vector2(fill.size.x, fill.size.y * 0.35)), Color(1, 1, 1, 0.2))
		for i in range(1, 10):
			var x := inner.position.x + inner.size.x * i / 10.0
			draw_line(Vector2(x, inner.end.y - inner.size.y * 0.4), Vector2(x, inner.end.y), Color(0, 0, 0, 0.35), 1.0)
		var font := ThemeDB.fallback_font
		var text := "%d / %d" % [roundi(_hp), roundi(_max)]
		var fs := 11
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(r.get_center().x - w / 2.0, r.get_center().y + fs * 0.36)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

## The Ultimate gauge: gold segments that fill up, glowing and shimmering once full
class UltBar extends Control:
	const SEGMENTS := 5
	var max_value := 1.0
	var value := 0.0:
		set(v):
			value = v
			set_process(value >= max_value and is_inside_tree())
			queue_redraw()
	var _t := 0.0

	func _init(max_energy: float, start: float) -> void:
		max_value = maxf(max_energy, 1.0)
		custom_minimum_size = Vector2(0, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		value = start

	func _ready() -> void:
		set_process(value >= max_value)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var share := clampf(value / max_value, 0.0, 1.0)
		var full := share >= 1.0
		var gap := 2.0
		var seg_w := (size.x - gap * (SEGMENTS - 1)) / SEGMENTS
		var gold := Color("#facc15")
		if full:
			var pulse := 0.5 + 0.5 * sin(_t * 6.0)
			draw_style_box(UITheme.box(Color(0, 0, 0, 0), Color(gold, 0.35 + 0.35 * pulse), 2, 3), Rect2(Vector2(-2, -2), size + Vector2(4, 4)))
		for i in SEGMENTS:
			var seg := Rect2(i * (seg_w + gap), 0, seg_w, size.y)
			draw_rect(seg, Color(0, 0, 0, 0.55))
			var part := clampf(share * SEGMENTS - i, 0.0, 1.0)
			if part > 0.0:
				var fill := Rect2(seg.position, Vector2(seg.size.x * part, seg.size.y))
				var c := gold.lightened(0.3) if full else gold
				UITheme.draw_vertical_gradient(self, fill, c.lightened(0.2), c.darkened(0.3))
		if full:  # a shimmer running along the gauge
			var x := fmod(_t * 1.4, 1.6) * size.x - size.x * 0.3
			draw_rect(Rect2(clampf(x, 0, size.x), 0, clampf(size.x * 0.15, 0, size.x - clampf(x, 0, size.x)), size.y), Color(1, 1, 1, 0.45))

## A soft wash of the side's colour from the card's outer edge, so friends and enemies read at a glance
class CardWash extends Control:
	var color: Color
	var from_left := true

	func _init(c: Color, left: bool) -> void:
		color = c
		from_left = left

	func _draw() -> void:
		var w := size.x * 0.55
		var x := 0.0 if from_left else size.x - w
		var edge := Color(color, 0.16)
		var none := Color(color, 0.0)
		var cols := PackedColorArray([edge, none, none, edge] if from_left else [none, edge, edge, none])
		draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w, size.y), Vector2(x, size.y)]), cols)

## "WAVE" pips in the HUD: done waves filled, the current one lit, later ones hollow
class WavePips extends Control:
	var count := 1
	var current := 0:
		set(v):
			current = v
			queue_redraw()

	func _init(n: int) -> void:
		count = n
		custom_minimum_size = Vector2(n * 16, 14)

	func _draw() -> void:
		for i in count:
			var c := Vector2(7 + i * 16, size.y / 2)
			if i == current:
				UITheme.draw_glow(self, c, 9, Color(UITheme.CYAN, 0.5), 4)
				draw_circle(c, 5, UITheme.CYAN_BRIGHT)
			elif i < current:
				draw_circle(c, 4, Color(UITheme.CYAN, 0.6))
			else:
				draw_arc(c, 4, 0, TAU, 16, Color(1, 1, 1, 0.35), 1.5, true)

## Both teams' total HP facing off in the HUD: blue from the left, red from the right, VS in the middle
class TeamClash extends Control:
	var _ally := 1.0
	var _enemy := 1.0
	var _tween: Tween

	func _init() -> void:
		custom_minimum_size = Vector2(220, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(ally: float, enemy: float) -> void:
		if _tween:
			_tween.kill()
		_tween = create_tween().set_parallel()
		_tween.tween_method(_set_ally, _ally, ally, 0.4)
		_tween.tween_method(_set_enemy, _enemy, enemy, 0.4)

	func _set_ally(v: float) -> void:
		_ally = v
		queue_redraw()

	func _set_enemy(v: float) -> void:
		_enemy = v
		queue_redraw()

	func _draw() -> void:
		var w := minf(size.x, 460.0)
		var left := (size.x - w) / 2.0
		var mid := left + w / 2.0
		var h := 12.0
		var y := size.y / 2.0 - h / 2.0
		var half := w / 2.0 - 22.0
		var font := ThemeDB.fallback_font
		# Ally bar grows out from the VS badge to the left, enemy bar to the right
		var ally_track := Rect2(mid - 22.0 - half, y, half, h)
		var enemy_track := Rect2(mid + 22.0, y, half, h)
		for t in [ally_track, enemy_track]:
			draw_style_box(UITheme.box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.12), 1, 3), t.grow(1))
		var a := ally_track.size.x * clampf(_ally, 0, 1)
		UITheme.draw_vertical_gradient(self, Rect2(ally_track.end.x - a, y, a, h), Color("#60a5fa"), Color("#1d4ed8"))
		var e := enemy_track.size.x * clampf(_enemy, 0, 1)
		UITheme.draw_vertical_gradient(self, Rect2(enemy_track.position.x, y, e, h), Color("#f87171"), Color("#b91c1c"))
		# Percentages at the outer ends
		var fs := 11
		var at := "%d%%" % roundi(_ally * 100)
		var et := "%d%%" % roundi(_enemy * 100)
		draw_string_outline(font, Vector2(ally_track.position.x + 4, y + h - 2), at, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(ally_track.position.x + 4, y + h - 2), at, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var ew := font.get_string_size(et, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(font, Vector2(enemy_track.end.x - ew - 4, y + h - 2), et, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(enemy_track.end.x - ew - 4, y + h - 2), et, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		# The VS badge: a diamond in the middle
		var c := Vector2(mid, size.y / 2.0)
		var r := 16.0
		UITheme.draw_glow(self, c, 22, Color(UITheme.GOLD, 0.25), 4)
		var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(diamond, Color(0.06, 0.08, 0.14))
		diamond.append(diamond[0])
		draw_polyline(diamond, UITheme.GOLD, 2.0, true)
		var vs := "VS"
		var vw := font.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, c + Vector2(-vw / 2.0, 5), vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.GOLD)

## Behind the cards: a lit floor band and a glowing divider down the gap between the two sides
class ArenaStage extends Control:
	var gap: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Vignette top and bottom so the cards pop off the background picture
		UITheme.draw_vertical_gradient(self, Rect2(0, 0, w, h * 0.5), Color(0, 0, 0, 0.32), Color(0, 0, 0, 0.08))
		UITheme.draw_vertical_gradient(self, Rect2(0, h * 0.5, w, h * 0.5), Color(0, 0, 0, 0.08), Color(0, 0, 0, 0.4))
		if gap == null or not is_instance_valid(gap):
			return
		var x := gap.global_position.x - global_position.x + gap.size.x / 2.0
		# Each side's half tinted faintly in its colour
		var blue := Color(ALLY_COLOR, 0.07)
		var red := Color(ENEMY_COLOR, 0.06)
		var clear := Color(0, 0, 0, 0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(x, 0), Vector2(x, h), Vector2(0, h)]),
			PackedColorArray([clear, blue, blue, clear]))
		draw_polygon(PackedVector2Array([Vector2(x, 0), Vector2(w, 0), Vector2(w, h), Vector2(x, h)]),
			PackedColorArray([red, clear, clear, red]))
		# The divider: a thin line with a faint halo, brightest in the middle and fading out at both ends
		var steps := 16
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var fade := sin(PI * (t0 + t1) / 2.0)
			var a := Vector2(x, lerpf(h * 0.04, h * 0.96, t0))
			var b := Vector2(x, lerpf(h * 0.04, h * 0.96, t1))
			draw_line(a, b, Color(UITheme.GOLD, 0.05 * fade), 7.0)
			draw_line(a, b, Color(UITheme.GOLD, 0.35 * fade), 1.0)
