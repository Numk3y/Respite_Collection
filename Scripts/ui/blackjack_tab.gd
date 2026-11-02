class_name BlackjackTab
extends VBoxContainer
## Casino game: Blackjack against Bogsy for Money. The bet is taken when the hand is dealt (so closing the game
## mid-hand can't undo a loss) and winnings are paid when it ends. Rules live in BlackjackGame.
## The felt glows softly with casino lights drifting over it; every card flies out of the deck in the corner with
## a spin; the totals sit on chip badges; a win rains coins, a Blackjack bursts gold, a bust shakes your hand red.

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
var _bubble: PanelContainer
var _table: PanelContainer
var _fx: CasinoFX
var _deck: DeckStack

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
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", UITheme.box(UITheme.POPUP, UITheme.GOLD.darkened(0.2), 2, 12, 12))
	side.add_child(_bubble)
	_speech = Label.new()
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.add_theme_font_size_override("font_size", 18)
	_bubble.add_child(_speech)
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
	table.add_theme_stylebox_override("panel", UITheme.box(Color("#0b3326"), Color("#c9a227"), 3, 14, 14))
	main.add_child(table)
	_table = table
	table.add_child(FeltGlow.new())
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
	# Effects on top of the felt, with the deck the cards fly out of in its top right corner
	_fx = CasinoFX.new()
	table.add_child(_fx)
	_deck = DeckStack.new()
	_fx.add_child(_deck)
	_fx.resized.connect(func(): _deck.position = Vector2(_fx.size.x - PlayingCard.SIZE.x - 24, 14))

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

## A hand total on a chip-like badge
func _total_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_stylebox_override("normal", UITheme.box(Color(0.02, 0.12, 0.08, 0.85), UITheme.GOLD.darkened(0.15), 2, 16, 6))
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 150
	label.self_modulate.a = 0.0  # shown once its hand has a card (see _update_totals)
	return label

func _card_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = PlayingCard.SIZE.y
	return row

func _button(text: String, action: Callable, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	return b

## Bogsy speaks: the bubble pops so the new line is noticed
func _say(situation: String) -> void:
	_speech.text = "\"%s\"" % Terms.t("bogsy_%s_%d" % [situation, randi_range(1, BANTER_VARIANTS)])
	_bubble.pivot_offset = _bubble.size / 2.0
	_bubble.scale = Vector2(0.92, 0.92)
	_bubble.create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	# A badge only shows once its hand has a card (an empty chip looked broken); hidden keeps its space
	_player_total.self_modulate.a = 1.0 if not _game.player.is_empty() else 0.0
	_dealer_total.self_modulate.a = 1.0 if not shown.is_empty() else 0.0

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

## Deals one card to the player or Bogsy: it flies out of the deck with a spin and lands in the hand.
## Returns the card node.
func _give(to_player: bool, face_up: bool) -> PlayingCard:
	var c := _game.draw_card()
	(_game.player if to_player else _game.dealer).append(c)
	var node := PlayingCard.new(c, face_up)
	node.modulate.a = 0.0
	(_player_cards if to_player else _dealer_cards).add_child(node)
	await get_tree().process_frame  # let the row place it, so we know where it lands
	var landing := node.position
	node.global_position = _deck.global_position
	node.rotation = deg_to_rad(-25.0)
	node.scale = Vector2(0.8, 0.8)
	_deck.pulse()
	var tw := node.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "position", landing, DEAL_TIME * 1.6)
	tw.tween_property(node, "rotation", 0.0, DEAL_TIME * 1.6)
	tw.tween_property(node, "scale", Vector2.ONE, DEAL_TIME * 1.6)
	tw.tween_property(node, "modulate:a", 1.0, DEAL_TIME * 0.5)
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
	_celebrate(outcome)
	if outcome == "player_blackjack":
		_say("blackjack")
	elif outcome in WIN_RESULTS:
		_say("player_won")
	elif outcome == "push":
		_say("push")
	else:
		_say("player_lost")
	_set_phase_betting()

## The end of a hand on the table: the result line pops, wins rain coins over your cards (Blackjack also
## bursts gold), a bust shakes your hand red, a dealer bust bursts over Bogsy's cards
func _celebrate(outcome: String) -> void:
	_result.pivot_offset = _result.size / 2.0
	_result.scale = Vector2(1.6, 1.6)
	_result.create_tween().tween_property(_result, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var mine := _row_rect(_player_cards)
	var theirs := _row_rect(_dealer_cards)
	match outcome:
		"player_blackjack":
			_fx.coins(mine.grow(40), 90)
			_fx.aura(mine.get_center())
			_pop(mine.get_center(), Terms.t("bj_pop_blackjack"), UITheme.GOLD, 40)
		"win":
			_fx.coins(mine.grow(30))
			_pop(mine.get_center(), Terms.t("bj_pop_win"), UITheme.GOLD, 34)
		"dealer_bust":
			_fx.hit(theirs.get_center(), Color("#ef4444"), true)
			_pop(theirs.get_center(), Terms.t("bj_pop_bust"), Color("#ef4444"), 34)
			_fx.coins(mine.grow(30))
		"player_bust":
			_fx.shake(_player_cards, 10.0, 0.4)
			_fx.hit(mine.get_center(), Color("#ef4444"), true)
			_pop(mine.get_center(), Terms.t("bj_pop_bust"), Color("#ef4444"), 34)
			_dim(_player_cards)
		"push":
			_fx.relief(mine.get_center(), Color("#cbd5e1"))
		_:
			_dim(_player_cards)

## A card row's area in the effects layer's coordinates
func _row_rect(row: Control) -> Rect2:
	var cards := row.get_children()
	if cards.is_empty():
		return Rect2(row.global_position - _fx.global_position, row.size)
	var first: Control = cards[0]
	var last: Control = cards[-1]
	var start := first.global_position - _fx.global_position
	return Rect2(start, last.global_position + PlayingCard.SIZE - first.global_position)

func _dim(row: Control) -> void:
	for card in row.get_children():
		card.create_tween().tween_property(card, "modulate", Color(0.6, 0.6, 0.65), 0.5)

## Big text that pops over a spot on the table and floats away
func _pop(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(label)
	var label_size := label.get_combined_minimum_size()
	label.position = pos - label_size / 2.0
	label.pivot_offset = label_size / 2.0
	label.scale = Vector2(2.0, 2.0)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:y", label.position.y - 40, 1.6).set_delay(0.6)
	t.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(1.5)
	t.chain().tween_callback(label.queue_free)

## A soft light in the middle of the felt
class FeltGlow extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		UITheme.draw_glow(self, size / 2.0, size.x * 0.45, Color("#2fbf7a", 0.22))
		draw_arc(size / 2.0 + Vector2(0, size.y * 0.9), size.y * 0.95, PI * 1.15, PI * 1.85, 64, Color(UITheme.GOLD, 0.18), 2.0, true)

## The deck in the corner: a few card backs stacked, nudged each time a card is dealt
class DeckStack extends Control:
	func _init() -> void:
		custom_minimum_size = PlayingCard.SIZE + Vector2(8, 8)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in 4:
			var back := PlayingCard.new({}, false)
			back.position = Vector2(i * 2, -i * 2) + Vector2(0, 6)
			add_child(back)

	func pulse() -> void:
		var top: Control = get_child(get_child_count() - 1)
		var t := top.create_tween()
		t.tween_property(top, "position:x", top.position.x - 8, 0.06)
		t.tween_property(top, "position:x", top.position.x, 0.12)
