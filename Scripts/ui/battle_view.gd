class_name BattleView
extends VBoxContainer
## Kancolle-style battle playback. Your team stands on the left (rearguard behind the vanguard), the enemies on
## the right. Each action: the actor bumps forward and flashes, its targets shake and show damage numbers, then
## HP bars, Ultimate gauges and buffs update from the engine's recorded state. Ultimates open with a Kancolle-style
## cut-in (Scripts/ui/cut_in_overlay.gd). Every battle plays out in full; players pick 1x/2x/3x speed instead of skipping.

signal again_pressed
signal home_pressed

const SPEEDS := [1, 2, 3]
const CARD_SIZE := Vector2(236, 118)
const ART_SIZE := Vector2(92, 108)
const BUMP_DISTANCE := 44.0
const STEP_SEC := 0.18  # length of one animation step at 1x
const ALLY_COLOR := Color("#3b82f6")
const ENEMY_COLOR := Color("#ef4444")
const DOWNED_ALPHA := 0.3

var _battle: Dictionary
var _speed := 1
var _views: Array[Dictionary] = []  # one per battle unit, same index
var _overlay: Control
var _banner: Label
var _cut_in: CutInOverlay
var _wave_label: Label
var _wave_count := 1
var _log: RichTextLabel
var _result_label: Label
var _after_buttons: Array[Button] = []

func start(stage: StageData, battle: Dictionary) -> void:
	_battle = battle
	_speed = clampi(int(GameState.get_setting("battle_speed", 1)), 1, SPEEDS.back())
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
	var group := ButtonGroup.new()
	for s in SPEEDS:
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
		var view := _unit_view(u)
		var key := ("ally_" if u.side == 0 else "enemy_") + ("van" if u.vanguard else "rear")
		columns[key].add_child(view.slot)
		view.slot.visible = u.side == 0 or int(u.wave) == 0  # later waves' enemies wait off the field
		_views.append(view)

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
	# Ultimate cut-ins go above everything else in the arena
	_cut_in = CutInOverlay.new()
	arena.add_child(_cut_in)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 84)
	_log.scroll_following = true
	add_child(_log)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	add_child(footer)
	_result_label = Label.new()
	_result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_font_size_override("font_size", 16)
	footer.add_child(_result_label)
	for pair in [["battle_again", again_pressed], ["battle_home", home_pressed]]:
		var button := Button.new()
		button.text = Terms.t(pair[0])
		button.pressed.connect(pair[1].emit)
		button.hide()
		footer.add_child(button)
		_after_buttons.append(button)

## A unit card. The slot holds the place in the column; the body inside it is what slides and shakes.
func _unit_view(u: Dictionary) -> Dictionary:
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
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 15)
	info.add_child(name_label)
	var view := {"slot": slot, "body": body, "side": u.side, "wave": int(u.wave), "vanguard": u.vanguard, "max_hp": u.max_hp,
		"hp_bar": null, "hp_label": null, "energy_bar": null, "buffs": null}
	# Everyone has HP now; the rearguard is only hit once its vanguard is down
	view.hp_bar = _bar(u.max_hp, u.max_hp, Color("#22c55e"), 12)
	info.add_child(view.hp_bar)
	view.hp_label = _small_label("%d / %d" % [u.max_hp, u.max_hp])
	info.add_child(view.hp_label)
	if u.has_ultimate:
		info.add_child(_small_label(Terms.t("battle_energy")))
		view.energy_bar = _bar(u.energy_max, 0, Color("#facc15"), 8)
		info.add_child(view.energy_bar)
	view.buffs = _small_label("", true)
	view.buffs.add_theme_color_override("font_color", Color("#93c5fd"))
	info.add_child(view.buffs)
	return view

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

func _set_speed(s: int) -> void:
	_speed = s
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
	for event in _battle.events:
		await _animate(event)
	_finish()

## Between waves: the cleared enemies leave, a "Battle 2/3" banner (or the boss banner) shows,
## and the next wave's enemies slide in from the right
func _animate_wave(event: Dictionary) -> void:
	var wave: int = event.wave
	_wave_label.text = Terms.t("battle_wave", {"current": wave + 1, "total": event.wave_count})
	var key := "battle_wave_boss" if event.boss else "battle_wave_banner"
	_show_banner(Terms.t(key, {"current": wave + 1, "total": event.wave_count}))
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
	await _wait(1.5)
	if not arriving.is_empty():
		var t := create_tween().set_parallel()
		for i in arriving.size():
			var body: Control = arriving[i].body
			t.tween_property(body, "position:x", 0.0, _dur(2)).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT).set_delay(_dur(0.4 * i))
			t.tween_property(body, "modulate:a", 1.0, _dur(1.2)).set_delay(_dur(0.4 * i))
		await t.finished
	await _wait(2)

func _animate(event: Dictionary) -> void:
	if event.kind == "wave":
		await _animate_wave(event)
		return
	var actor: Dictionary = _views[event.actor]
	var direction := 1.0 if actor.side == 0 else -1.0
	if event.kind == "ultimate":
		# Everything waits for the cut-in, then the caster's card flashes gold and the skill lands
		var caster: Dictionary = _battle.units[event.actor]
		await _cut_in.play(caster.data, caster.name, event.skill, caster.side == 0, _speed)
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
	if attacking:
		var forward := create_tween().set_parallel()
		forward.tween_property(actor.body, "position:x", BUMP_DISTANCE * direction, _dur(1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		forward.tween_property(actor.body, "modulate", Color(1.5, 1.5, 1.5), _dur(1))
		await forward.finished
	for hit in event.hits:
		_react(_views[hit.target], hit)
	for target in event.get("off_balance", []):
		_float_text(_views[target], Terms.t("battle_off_balance"), Color("#fb923c"), 34)
	for heal in event.heals:
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
		_float_text(_views[drain.target], "-%d" % drain.amount, Color("#dc2626") if drain.get("bleed", false) else Color("#c084fc"), 30)
	for target in event.get("grubbed", []):
		_float_text(_views[target], Terms.t("battle_grubbed"), Color("#fb923c"), 60)
	for target in event.get("decayed", []):
		_float_text(_views[target], Terms.t("battle_decay"), Color("#a3e635"), 60)
	for ally in event.get("cringed", []):
		_float_text(_views[ally], Terms.t("battle_cringe"), Color("#d9f99d"), 60)
	for target in event.get("bled", []):
		_float_text(_views[target], Terms.t("battle_bleed"), Color("#dc2626"), 60)
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
	_react(_views[assist.target], {"hit": true, "damage": assist.damage})
	var back := create_tween().set_parallel()
	back.tween_property(helper.body, "position:x", 0.0, _dur(1)).set_trans(Tween.TRANS_QUAD)
	back.tween_property(helper.body, "modulate", Color.WHITE, _dur(1))
	await back.finished

## Target reaction: shake and red flash with a damage number (gold on a crit), or a MISS
func _react(view: Dictionary, hit: Dictionary) -> void:
	if not hit.hit:
		_float_text(view, Terms.t("battle_miss"), Color("#cbd5e1"))
		return
	if hit.get("crit", false):
		_float_text(view, Terms.t("battle_crit", {"damage": hit.damage}), Color("#fde047"))
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

## Floating text over a card; y_offset stacks several labels (e.g. CRIT and OFF-BALANCE) without overlap
func _float_text(view: Dictionary, text: String, color: Color, y_offset: float = 0.0) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	_overlay.add_child(label)
	var body: Control = view.body
	label.position = body.global_position - _overlay.global_position + Vector2(CARD_SIZE.x * 0.3, 8 + y_offset)
	var t := create_tween().set_parallel()
	t.tween_property(label, "position:y", label.position.y - 42, _dur(4))
	t.tween_property(label, "modulate:a", 0.0, _dur(4)).set_delay(_dur(1.5))
	t.chain().tween_callback(label.queue_free)

func _show_banner(text: String) -> void:
	_banner.text = text
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 1.0, _dur(1))
	t.tween_interval(_dur(4))
	t.tween_property(_banner, "modulate:a", 0.0, _dur(1.5))

## Bars, gauges, buffs and knocked-out fading from the engine's state after this action
func _apply_state(event: Dictionary) -> void:
	for i in _views.size():
		var view: Dictionary = _views[i]
		var s: Dictionary = event.state[i]
		if view.hp_bar:
			view.hp_bar.value = s.hp
			view.hp_label.text = "%d / %d" % [s.hp, view.max_hp]
			view.slot.modulate.a = DOWNED_ALPHA if s.hp <= 0 else 1.0
		if view.energy_bar:
			view.energy_bar.value = s.energy
		view.buffs.text = ", ".join(s.buffs)

func _append_lines(event: Dictionary) -> void:
	if not event.lines.is_empty():
		_log.append_text("\n".join(event.lines) + "\n")

func _finish() -> void:
	_log.append_text("\n".join(_battle.end_lines))
	var report: Dictionary = _battle.report
	if _battle.win:
		var extras := ""
		for key in report.materials:
			if report.materials[key] > 0:
				extras += Terms.t("report_material", {"material": Terms.material_name(key), "amount": report.materials[key]})
		var drops := ""
		for item in report.drops:
			drops += Terms.t("report_drop", {"item": item})
		var lines := PackedStringArray([Terms.t("battle_victory", {
			"rewards": Terms.t("battle_rewards", {"amount": report.money, "materials": extras, "drops": drops})})])
		if report.exp > 0:
			lines.append(Terms.t("battle_exp", {"amount": report.exp}))
		for up in report.level_ups:
			lines.append(Terms.t("battle_level_up", {"name": up.name, "lv": up.level}))
		if report.first_clear_cards > 0:
			lines.append(Terms.t("battle_first_clear", {"amount": report.first_clear_cards}))
		if report.card_drops > 0:
			lines.append(Terms.t("battle_card_drop", {"amount": report.card_drops, "card_word": Terms.credit_card_word(report.card_drops)}))
		_result_label.text = "\n".join(lines)
	else:
		_result_label.text = Terms.t("battle_defeat")
	for button in _after_buttons:
		button.show()
