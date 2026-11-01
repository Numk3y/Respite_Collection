class_name BlackjackTab
extends VBoxContainer
## Casino game: Blackjack against Bogsy for Money. The bet is taken when the hand is dealt (so closing the game
## mid-hand can't undo a loss) and winnings are paid when it ends. Rules live in BlackjackGame.

signal back_pressed

const DEALER_ID := "bogsy"
const SIDE_WIDTH := 280
const DEAL_TIME := 0.18
const BANTER_VARIANTS := 3
const WIN_RESULTS := ["player_blackjack", "win", "dealer_bust"]

var _game: BlackjackGame
var _staked := 0  # Money taken for the current hand (doubles on Double Down)
var _busy := false  # true while cards are animating or the hand is over

var _speech: Label
var _dealer_total: Label
var _player_total: Label
var _dealer_cards: HBoxContainer
var _player_cards: HBoxContainer
var _result: Label
var _bet_row: BetPicker
var _back_button: Button
var _deal_button: Button
var _play_row: HBoxContainer
var _hit_button: Button
var _stand_button: Button
var _double_button: Button
var _hole_card: PlayingCard

func _ready() -> void:
	add_theme_constant_override("separation", 12)

	# Left column: Bogsy and his speech bubble. Right column: the table and the controls.
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_theme_constant_override("separation", 8)
	columns.add_child(side)
	var portrait := CasinoTab.npc_portrait(DEALER_ID, Terms.term("dealer_name"), CasinoTab.BOGSY_COLOR)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	side.add_child(portrait)
	var title := Label.new()
	title.text = Terms.t("bj_title")
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
	rules.text = Terms.t("bj_rules")
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(rules)
	_back_button = _button(Terms.t("casino_back"), back_pressed.emit)
	side.add_child(_back_button)

	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 12)
	columns.add_child(main)
	var table := PanelContainer.new()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", UITheme.box(Color("#0F3B2E"), Color("#1F6B4F"), 2, 14, 14))
	main.add_child(table)
	var felt := VBoxContainer.new()
	felt.alignment = BoxContainer.ALIGNMENT_CENTER
	felt.add_theme_constant_override("separation", 8)
	table.add_child(felt)
	_dealer_total = _total_label()
	felt.add_child(_dealer_total)
	_dealer_cards = _card_row()
	felt.add_child(_dealer_cards)
	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 22)
	_result.custom_minimum_size.y = 34
	felt.add_child(_result)
	_player_total = _total_label()
	felt.add_child(_player_total)
	_player_cards = _card_row()
	felt.add_child(_player_cards)

	# Betting controls (between hands) and play controls (during a hand)
	_bet_row = BetPicker.new()
	_bet_row.changed.connect(func(_bet: int): _refresh_controls())
	main.add_child(_bet_row)
	_deal_button = _button(Terms.t("bj_deal"), _deal, 22)
	_deal_button.custom_minimum_size = Vector2(180, 52)
	_bet_row.add_child(_deal_button)

	_play_row = HBoxContainer.new()
	_play_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_play_row.add_theme_constant_override("separation", 12)
	main.add_child(_play_row)
	_hit_button = _button(Terms.t("bj_hit"), _hit, 22)
	_stand_button = _button(Terms.t("bj_stand"), _stand, 22)
	_double_button = _button(Terms.t("bj_double"), _double, 22)
	for b in [_hit_button, _stand_button, _double_button]:
		b.custom_minimum_size = Vector2(170, 52)
		_play_row.add_child(b)

	GameState.money_changed.connect(_on_money_changed)
	_say("idle")
	_set_phase_betting()

func _total_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	return label

func _card_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = PlayingCard.SIZE.y
	return row

func _button(text: String, action: Callable, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	return b

func _say(situation: String) -> void:
	_speech.text = "\"%s\"" % Terms.t("bogsy_%s_%d" % [situation, randi_range(1, BANTER_VARIANTS)])

# ───────── Phases ─────────

func _set_phase_betting() -> void:
	_busy = false
	_bet_row.show()
	_back_button.show()
	_play_row.hide()
	_refresh_controls()

func _set_phase_playing() -> void:
	_bet_row.hide()
	_back_button.hide()
	_play_row.show()
	_refresh_controls()

func _refresh_controls() -> void:
	var bet := _bet_row.bet
	_deal_button.text = Terms.t("bj_again" if _game != null else "bj_deal")
	_deal_button.disabled = GameState.get_money() < bet
	_hit_button.disabled = _busy
	_stand_button.disabled = _busy
	# Doubling is only allowed on the first two cards and needs Money for a second stake
	_double_button.disabled = _busy or _game == null or _game.player.size() != 2 or GameState.get_money() < _staked

func _on_money_changed(_value: int) -> void:
	_refresh_controls()

func _update_totals() -> void:
	_player_total.text = Terms.t("bj_total", {"who": Terms.t("bj_you"), "value": BlackjackGame.hand_value(_game.player)})
	var shown: Array = _game.dealer
	if _hole_card != null and not _hole_card.face_up:
		shown = _game.dealer.slice(0, 1)
	_dealer_total.text = Terms.t("bj_total", {"who": Terms.term("dealer_name"), "value": BlackjackGame.hand_value(shown)})

# ───────── A hand ─────────

func _deal() -> void:
	if _busy:
		return
	if not GameState.try_spend(_bet_row.bet):
		_result.text = Terms.t("casino_not_enough")
		_result.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		return
	_staked = _bet_row.bet
	_game = BlackjackGame.new()
	_hole_card = null
	for row in [_dealer_cards, _player_cards]:
		for child in row.get_children():
			child.queue_free()
	_result.text = ""
	_busy = true
	_set_phase_playing()
	_say("deal")

	await _give(true, true)
	await _give(false, true)
	await _give(true, true)
	_hole_card = await _give(false, false)
	_update_totals()

	# Naturals end the hand at once (Bogsy peeks at his hole card)
	if BlackjackGame.is_blackjack(_game.player) or BlackjackGame.is_blackjack(_game.dealer):
		await _finish()
		return
	_busy = false
	_refresh_controls()

## Deals one card to the player or Bogsy with a pop-in, returns the card node
func _give(to_player: bool, face_up: bool) -> PlayingCard:
	var c := _game.draw_card()
	(_game.player if to_player else _game.dealer).append(c)
	var node := PlayingCard.new(c, face_up)
	node.scale = Vector2(0.3, 0.3)
	node.modulate.a = 0.0
	(_player_cards if to_player else _dealer_cards).add_child(node)
	var tw := node.create_tween().set_parallel()
	tw.tween_property(node, "scale", Vector2.ONE, DEAL_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "modulate:a", 1.0, DEAL_TIME)
	await tw.finished
	_update_totals()
	return node

func _hit() -> void:
	if _busy:
		return
	_busy = true
	_refresh_controls()
	await _give(true, true)
	var value := BlackjackGame.hand_value(_game.player)
	if value > 21:
		await _finish()
	elif value == 21:
		await _dealer_turn()
	else:
		_busy = false
		_refresh_controls()

func _stand() -> void:
	if _busy:
		return
	_busy = true
	_refresh_controls()
	await _dealer_turn()

func _double() -> void:
	if _busy or _game.player.size() != 2 or not GameState.try_spend(_staked):
		return
	_staked *= 2
	_busy = true
	_refresh_controls()
	await _give(true, true)
	if BlackjackGame.is_bust(_game.player):
		await _finish()
	else:
		await _dealer_turn()

func _dealer_turn() -> void:
	await _reveal_hole()
	while _game.dealer_should_draw():
		await create_tween().tween_interval(0.35).finished
		await _give(false, true)
	await _finish()

func _reveal_hole() -> void:
	if _hole_card == null or _hole_card.face_up:
		return
	var tw := _hole_card.create_tween()
	tw.tween_property(_hole_card, "scale:x", 0.0, 0.12)
	tw.tween_callback(_hole_card.set_face_up.bind(true))
	tw.tween_property(_hole_card, "scale:x", 1.0, 0.12)
	await tw.finished
	_update_totals()

func _finish() -> void:
	await _reveal_hole()
	var outcome := _game.outcome()
	var paid := BlackjackGame.payout(outcome, _staked)
	if paid > 0:
		GameState.add_money(paid)
	var shown := paid - _staked if outcome in WIN_RESULTS else _staked
	_result.text = Terms.t("bj_result_" + outcome, {"amount": shown})
	var color := UITheme.GOLD if outcome in WIN_RESULTS else (UITheme.TEXT if outcome == "push" else Color("#F87171"))
	_result.add_theme_color_override("font_color", color)
	if outcome == "player_blackjack":
		_say("blackjack")
	elif outcome in WIN_RESULTS:
		_say("player_won")
	elif outcome == "push":
		_say("push")
	else:
		_say("player_lost")
	_set_phase_betting()
