class_name RouletteTab
extends VBoxContainer
## Casino game: Russian Roulette duel against Nilla. The bet is taken when the gun is loaded; the player and Nilla
## alternate pulls (the player presses the trigger, Nilla pulls on her own) until it fires. Rules live in RouletteGame.

signal back_pressed

const HOST_ID := "nilla"
const SIDE_WIDTH := 280
const BANTER_VARIANTS := 3
const TENSION_TIME := 0.55  # pause between pulling and the result
const HOST_THINK_TIME := 0.8

var _game: RouletteGame
var _bullets := 2  # picked for the next round
var _staked := 0
var _busy := false

var _speech: Label
var _turn_label: Label
var _cylinder: RevolverCylinder
var _log: Label
var _result: Label
var _flash: ColorRect
var _bullet_row: HBoxContainer
var _bullet_buttons: Array[Button] = []  # index = bullets - MIN_BULLETS
var _odds_label: Label
var _bet_row: BetPicker
var _back_button: Button
var _load_button: Button
var _trigger_button: Button

## Values for the lobby blurb and rules text, so they stay right if the bullet range or payouts change
static func range_args() -> Dictionary:
	return {
		"min": RouletteGame.MIN_BULLETS,
		"max": RouletteGame.MAX_BULLETS,
		"chambers": RouletteGame.CHAMBERS,
		"best": str(RouletteGame.payout_multiplier(RouletteGame.MAX_BULLETS)),
	}

static func odds_args(bullets: int) -> Dictionary:
	return {
		"bullets": bullets,
		"chance": "%.0f" % (RouletteGame.win_chance(bullets) * 100),
		"payout": str(RouletteGame.payout_multiplier(bullets)),
	}

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)

	# Left column: Nilla and her speech bubble
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_theme_constant_override("separation", 8)
	columns.add_child(side)
	var portrait := CasinoTab.npc_portrait(HOST_ID, Terms.term("roulette_host"), CasinoTab.NILLA_COLOR)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	side.add_child(portrait)
	var title := Label.new()
	title.text = Terms.t("rr_title")
	title.add_theme_font_size_override("font_size", 22)
	side.add_child(title)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UITheme.box(UITheme.POPUP, UITheme.CYAN, 2, 12, 12))
	side.add_child(bubble)
	_speech = Label.new()
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.add_theme_font_size_override("font_size", 18)
	bubble.add_child(_speech)
	var rules := Label.new()
	rules.text = Terms.t("rr_rules", range_args())
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(rules)
	_back_button = _button(Terms.t("casino_back"), back_pressed.emit)
	side.add_child(_back_button)

	# Right column: the table with the revolver, then the controls
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	columns.add_child(main)
	var table := PanelContainer.new()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", UITheme.box(Color("#3B0F1F"), Color("#7A1F3D"), 2, 14, 14))
	main.add_child(table)
	var felt := VBoxContainer.new()
	felt.alignment = BoxContainer.ALIGNMENT_CENTER
	felt.add_theme_constant_override("separation", 6)
	table.add_child(felt)
	_turn_label = _center_label(24)
	felt.add_child(_turn_label)
	_cylinder = RevolverCylinder.new()
	_cylinder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	felt.add_child(_cylinder)
	_log = _center_label(18)
	felt.add_child(_log)
	_result = _center_label(22)
	felt.add_child(_result)
	# Red flash over the table when the gun goes off
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.1, 0.1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(_flash)

	# Bullet count picker with the odds for the current choice
	_bullet_row = HBoxContainer.new()
	_bullet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bullet_row.add_theme_constant_override("separation", 8)
	main.add_child(_bullet_row)
	var bullets_title := Label.new()
	bullets_title.text = Terms.t("rr_bullets")
	bullets_title.add_theme_font_size_override("font_size", 18)
	_bullet_row.add_child(bullets_title)
	var group := ButtonGroup.new()
	for n in range(RouletteGame.MIN_BULLETS, RouletteGame.MAX_BULLETS + 1):
		var b := _button(str(n), _pick_bullets.bind(n), 18)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = n == _bullets
		b.custom_minimum_size = Vector2(42, 38)
		_bullet_row.add_child(b)
		_bullet_buttons.append(b)
	_odds_label = Label.new()
	_odds_label.custom_minimum_size.x = 260
	_odds_label.add_theme_font_size_override("font_size", 18)
	_odds_label.add_theme_color_override("font_color", UITheme.GOLD)
	_bullet_row.add_child(_odds_label)

	_bet_row = BetPicker.new()
	_bet_row.changed.connect(func(_bet: int): _refresh_controls())
	main.add_child(_bet_row)
	_load_button = _button(Terms.t("rr_load"), _start, 22)
	_load_button.custom_minimum_size = Vector2(190, 52)
	_bet_row.add_child(_load_button)
	_trigger_button = _button(Terms.t("rr_trigger"), _on_trigger, 22)
	_trigger_button.custom_minimum_size = Vector2(260, 52)
	_trigger_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(_trigger_button)

	GameState.money_changed.connect(_on_money_changed)
	_say("idle")
	_set_phase_betting()

func _center_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.custom_minimum_size.y = font_size + 10
	return label

func _button(text: String, action: Callable, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	return b

func _say(situation: String) -> void:
	_speech.text = "\"%s\"" % Terms.t("nilla_%s_%d" % [situation, randi_range(1, BANTER_VARIANTS)])

# ───────── Phases ─────────

func _set_phase_betting() -> void:
	_busy = false
	_bullet_row.show()
	_bet_row.show()
	_back_button.show()
	_trigger_button.hide()
	_refresh_controls()

func _set_phase_playing() -> void:
	_bullet_row.hide()
	_bet_row.hide()
	_back_button.hide()
	_trigger_button.show()
	_refresh_controls()

func _pick_bullets(n: int) -> void:
	_bullets = n
	_bullet_buttons[n - RouletteGame.MIN_BULLETS].button_pressed = true  # the ButtonGroup releases the others
	_refresh_controls()

func _refresh_controls() -> void:
	_odds_label.text = Terms.t("rr_odds", odds_args(_bullets))
	_load_button.text = Terms.t("rr_again" if _game != null else "rr_load")
	_load_button.disabled = GameState.get_money() < _bet_row.bet
	_trigger_button.disabled = _busy or _game == null or not _game.is_player_turn()

func _on_money_changed(_value: int) -> void:
	_refresh_controls()

# ───────── A round ─────────

func _start() -> void:
	if _busy:
		return
	if not GameState.try_spend(_bet_row.bet):
		_result.text = Terms.t("casino_not_enough")
		_result.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		return
	_staked = _bet_row.bet
	_game = RouletteGame.new(_bullets)
	_cylinder.reset()
	_log.text = ""
	_result.text = ""
	_turn_label.text = ""
	_busy = true
	_set_phase_playing()
	_say("load")
	# Spin the cylinder before the first pull
	_cylinder.spin = TAU * 3
	var tw := _cylinder.create_tween()
	tw.tween_property(_cylinder, "spin", 0.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	await _next_turn()

func _next_turn() -> void:
	if _game.is_player_turn():
		_turn_label.text = Terms.t("rr_your_turn")
		_turn_label.add_theme_color_override("font_color", UITheme.CYAN)
		_busy = false
		_refresh_controls()
		return
	_turn_label.text = Terms.t("rr_host_turn")
	_turn_label.add_theme_color_override("font_color", Color("#F472B6"))
	_refresh_controls()
	_say("her_turn")
	await create_tween().tween_interval(HOST_THINK_TIME).finished
	await _fire(false)

func _on_trigger() -> void:
	if _busy or not _game.is_player_turn():
		return
	_busy = true
	_refresh_controls()
	await _fire(true)

func _fire(by_player: bool) -> void:
	# A small squeeze of the cylinder while the hammer falls
	var squeeze := _cylinder.create_tween()
	squeeze.tween_property(_cylinder, "scale", Vector2(0.94, 0.94), TENSION_TIME * 0.5)
	squeeze.tween_property(_cylinder, "scale", Vector2.ONE, TENSION_TIME * 0.5)
	await squeeze.finished
	var chamber := _game.position
	if _game.pull():
		_cylinder.set_state(chamber, RevolverCylinder.State.FIRED)
		_log.text = Terms.t("rr_bang")
		_log.add_theme_color_override("font_color", Color("#F87171"))
		var flash := _flash.create_tween()
		flash.tween_property(_flash, "color:a", 0.55, 0.06)
		flash.tween_property(_flash, "color:a", 0.0, 0.5)
		await flash.finished
		_finish(not by_player)
		return
	_cylinder.set_state(chamber, RevolverCylinder.State.EMPTY)
	_log.text = Terms.t("rr_click_you" if by_player else "rr_click_host")
	_log.add_theme_color_override("font_color", UITheme.TEXT)
	var turn := _cylinder.create_tween()
	turn.tween_property(_cylinder, "spin", -_game.position * TAU / RouletteGame.CHAMBERS, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await turn.finished
	await _next_turn()

func _finish(won: bool) -> void:
	# Show where the other bullets were
	for i in range(_game.position, RouletteGame.CHAMBERS):
		if _game.loaded[i]:
			_cylinder.set_state(i, RevolverCylinder.State.BULLET)
	_turn_label.text = ""
	var paid := RouletteGame.payout(won, _staked, _game.bullets)
	if paid > 0:
		GameState.add_money(paid)
	if won:
		_result.text = Terms.t("rr_result_win", {"amount": paid - _staked})
		_result.add_theme_color_override("font_color", UITheme.GOLD)
		_say("player_won")
	else:
		_result.text = Terms.t("rr_result_lose", {"amount": _staked})
		_result.add_theme_color_override("font_color", Color("#F87171"))
		_say("player_lost")
	_set_phase_betting()
