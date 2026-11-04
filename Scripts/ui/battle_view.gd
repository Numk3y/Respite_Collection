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
var _jumpscare: JumpscareOverlay
var _fx: BattleFX
var _arena: Control
var _results: BattleResults
var _log_names: Array[Dictionary] = []  # {"name", "side"}, longest first, for colouring names in the log
var _log_number := RegEx.create_from_string("\\d+")
var _stage_name := ""
var _note := ""
var _wave_label: Label
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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)
	var title := Label.new()
	title.text = Terms.t("battle_title", {"name": stage.display_name})
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	# "Battle 1/3": which wave of the mission is being fought
	for u in _battle.units:
		_wave_count = maxi(_wave_count, int(u.wave) + 1)
	_wave_label = Label.new()
	_wave_label.add_theme_font_size_override("font_size", 20)
	_wave_label.add_theme_color_override("font_color", UITheme.CYAN)
	_wave_label.text = Terms.t("battle_wave", {"current": 1, "total": _wave_count})
	_wave_label.visible = _wave_count > 1
	header.add_child(_wave_label)
	if not auto_label.is_empty():
		var tag := UITheme.tag(auto_label, UITheme.GOLD)
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
	var group := ButtonGroup.new()
	for s in _speeds():
		var button := Button.new()
		button.text = Terms.t("battle_speed", {"speed": s})
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = s == _speed
		button.custom_minimum_size = Vector2(48, 0)
		button.pressed.connect(_set_speed.bind(s))
		header.add_child(button)

	# Arena: [ally rearguard][ally vanguard]  gap  [enemy vanguard][enemy rearguard]
	var arena := Control.new()
	arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena.custom_minimum_size = Vector2(0, CARD_SIZE.y * 3 + 24)
	add_child(arena)
	var sides := HBoxContainer.new()
	sides.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_theme_constant_override("separation", 14)
	arena.add_child(sides)
	var columns := {}
	for key in ["ally_rear", "ally_van", "gap", "enemy_van", "enemy_rear"]:
		if key == "gap":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(24, 0)
			sides.add_child(gap)
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

	# The log: names coloured by side, numbers highlighted, knockouts in red (see _style_line)
	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 110)
	_log.scroll_following = true
	_log.bbcode_enabled = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.add_theme_font_size_override("bold_font_size", 14)
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.03, 0.05, 0.1, 0.82)
	log_style.border_color = UITheme.CYAN.darkened(0.3)
	log_style.border_width_left = 3
	log_style.set_corner_radius_all(6)
	log_style.set_content_margin_all(8)
	log_style.content_margin_left = 12
	_log.add_theme_stylebox_override("normal", log_style)
	add_child(_log)
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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UITheme.CARD, 0.95)
	style.border_color = ALLY_COLOR if u.side == 0 else ENEMY_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	body.add_theme_stylebox_override("panel", style)
	slot.add_child(body)

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
	info.add_theme_constant_override("separation", 3)
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
	info.add_child(name_label)
	var view := {"slot": slot, "body": body, "side": u.side, "wave": int(u.wave), "vanguard": u.vanguard, "max_hp": u.max_hp,
		"hp": u.max_hp, "hp_bar": null, "hp_label": null, "energy_bar": null, "ult_label": null, "energy_full": false,
		"buffs": null, "art": art, "data": u.data, "horse": false, "style": style}
	# Everyone has HP now; the rearguard is only hit once its vanguard is down
	view.hp_bar = HpBar.new(u.max_hp)
	info.add_child(view.hp_bar)
	view.hp_label = _small_label("%d / %d" % [u.max_hp, u.max_hp])
	info.add_child(view.hp_label)
	if u.has_ultimate:
		view.ult_label = _small_label(Terms.t("battle_energy"))
		info.add_child(view.ult_label)
		if u.side == 0:
			body.gui_input.connect(_on_card_input.bind(index))
		view.energy_bar = _bar(u.energy_max, 0, Color("#facc15"), 8)
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

func _bar(max_value: float, value: float, color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

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
		view.ult_label.text = Terms.t("battle_energy")
		view.ult_label.remove_theme_color_override("font_color")
		style.border_color = ALLY_COLOR
		style.set_border_width_all(2)
		return
	var queued: bool = Combat.engine.is_ultimate_queued(index)
	view.ult_label.text = Terms.t("battle_ult_queued" if queued else "battle_ult_ready")
	view.ult_label.add_theme_color_override("font_color", Color("#fde047") if queued else Color("#facc15"))
	style.border_color = Color("#fde047") if queued else Color("#f59e0b")
	style.set_border_width_all(4 if queued else 3)

## Between waves: the cleared enemies leave, a "Battle 2/3" banner (or the boss banner) shows,
## and the next wave's enemies slide in from the right. A wave with its own banner (the animatronics) gets a
## jumpscare entrance instead.
func _animate_wave(event: Dictionary) -> void:
	var wave: int = event.wave
	_wave_label.text = Terms.t("battle_wave", {"current": wave + 1, "total": event.wave_count})
	var wave_text := Terms.t("battle_wave_boss" if event.boss else "battle_wave_banner", {"current": wave + 1, "total": event.wave_count})
	if event.banner.is_empty():
		_show_banner(wave_text)
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
	await _jumpscare.blackout(_speed)
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
		await _cut_in.play(caster.data, caster.name, event.skill, caster.side == 0, _speed)
		_fx.aura(_center(actor))
		await _flash(actor.body, Color(1.9, 1.6, 0.5), 1.5)
	elif event.kind == "idle":
		_float_text(actor, Terms.t("battle_idle"), Color("#fde68a"), 30)
		await _flash(actor.body, Color(1.6, 1.3, 0.6), 2)
	elif event.kind == "heal":
		_float_text(actor, Terms.t("battle_heal_turn"), Color("#86efac"), 30)
		await _flash(actor.body, Color(0.8, 1.7, 1.0), 2)
	elif event.kind == "sleep":
		_float_text(actor, Terms.t("battle_sleep"), Color("#93c5fd"), 30)
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
		await forward.finished
		if puking or not melee:
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
		var drain_color := Color("#dc2626") if drain.get("bleed", false) else Color("#84cc16") if drain.get("poison", false) else Color("#c084fc")
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
	_apply_state(event)
	_append_lines(event)
	await _wait(1.5)
	_fx.set_marker(null, Vector2.ZERO)

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
	if not hit.hit:
		_float_text(view, Terms.t("battle_miss"), Color("#cbd5e1"))
		return
	var crit: bool = hit.get("crit", false)
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
			view.hp_label.text = "%d / %d" % [s.hp, view.max_hp]
			if view.hp > 0 and s.hp <= 0 and view.slot.visible:
				_knockout(view)
			elif s.hp > 0:
				view.slot.modulate.a = 1.0
			view.hp = s.hp
		var horse: bool = s.get("horse", false)
		if horse != view.horse:
			view.horse = horse
			_transform(view, horse)
		if view.energy_bar:
			view.energy_bar.value = s.energy
			view.energy_bar.modulate = Color(1.7, 1.5, 0.7) if s.energy >= view.energy_bar.max_value else Color.WHITE
			view.energy_full = s.energy >= view.energy_bar.max_value
			_refresh_ultimate(i)
		view.buffs.text = ", ".join(s.buffs)
	_update_guide()

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

func _knockout(view: Dictionary) -> void:
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
	var lines := PackedStringArray()  # rewards and the rest, for the results screen
	if report.get("world_boss", false):
		lines.append(Terms.t("boss_result_damage", {"damage": Terms.number(report.damage)}))
	elif win:
		var extras := ""
		for key in report.materials:
			if report.materials[key] > 0:
				extras += Terms.t("report_material", {"material": Terms.material_name(key), "amount": report.materials[key]})
		var drops := ""
		for item in report.drops:
			drops += Terms.t("report_drop", {"item": item})
		lines.append(Terms.t("battle_rewards", {"amount": report.money, "materials": extras, "drops": drops}))
		if report.exp > 0:
			lines.append(Terms.t("battle_exp", {"amount": report.exp}))
		for up in report.level_ups:
			lines.append(Terms.t("battle_level_up", {"name": up.name, "lv": up.level}))
		if report.get("account_exp", 0) > 0:
			lines.append(Terms.t("battle_account_exp_first" if report.get("account_first_clear", false) else "battle_account_exp",
				{"amount": report.account_exp}))
		if report.get("account_level_up", 0) > 0:
			lines.append(Terms.t("battle_account_level_up", {"lv": report.account_level_up,
				"limit": GameState.team_cost_limit_at(report.account_level_up)}))
		if report.first_clear_cards > 0:
			lines.append(Terms.t("battle_first_clear", {"amount": report.first_clear_cards}))
		if report.get("star_cards", 0) > 0:
			lines.append(Terms.t("battle_new_stars", {"amount": report.star_cards, "card_word": Terms.credit_card_word(report.star_cards)}))
		if report.card_drops > 0:
			lines.append(Terms.t("battle_card_drop", {"amount": report.card_drops, "card_word": Terms.credit_card_word(report.card_drops)}))
	elif report.card_drops > 0:  # beat the animatronics, then lost a later wave: their card still counts
		lines.append(Terms.t("battle_defeat_partial"))
		lines.append(Terms.t("battle_card_drop", {"amount": report.card_drops, "card_word": Terms.credit_card_word(report.card_drops)}))
	else:
		lines.append(Terms.t("battle_defeat"))
	for up in report.get("bond_ups", []):
		lines.append(Terms.t("battle_bond_up", {"name": up.name, "bond": up.bond}))

	await _wait(3)  # a beat to see the final blow land
	_results = BattleResults.new()
	_arena.add_child(_results)
	_results.again_pressed.connect(again_pressed.emit)
	_results.home_pressed.connect(home_pressed.emit)
	_results.next_pressed.connect(next_pressed.emit)
	_results.next_text = next_text
	_results.open(_battle, _stage_name, lines)
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

	func _init(max_hp: int) -> void:
		_max = maxf(float(max_hp), 1.0)
		_hp = _max
		_trail = _max
		custom_minimum_size = Vector2(0, 12)

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

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.45))
		var share := clampf(_hp / _max, 0.0, 1.0)
		var trail := clampf(_trail / _max, 0.0, 1.0)
		if trail > share:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * trail, size.y)), Color("#ef4444"))
		# Green when healthy, amber below half, red below a quarter
		var color := Color("#22c55e") if share > 0.5 else Color("#f59e0b") if share > 0.25 else Color("#ef4444")
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * share, size.y)), color)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * share, size.y * 0.4)), Color(1, 1, 1, 0.18))  # a little shine
		draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
