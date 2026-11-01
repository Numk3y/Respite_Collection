class_name BlackjackGame
extends RefCounted
## Blackjack rules for one hand against the dealer (Bogsy). No UI and no money here: BlackjackTab drives it.
## A fresh shuffled 52-card deck every hand. Cards are {"rank": "A".."K", "suit": 0-3}
## (0 spades, 1 hearts, 2 diamonds, 3 clubs).

const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const DEALER_STANDS_ON := 17  # the dealer draws until reaching at least this (soft 17 stands)
const WIN_PAYOUT := 2.0  # total returned on a normal win (the bet plus 1:1)
const BLACKJACK_PAYOUT := 2.5  # total returned on a natural Blackjack (the bet plus 3:2)

var deck: Array[Dictionary] = []
var player: Array[Dictionary] = []
var dealer: Array[Dictionary] = []

## `preset` (tests only) gives the exact draw order instead of a shuffle
func _init(rng: RandomNumberGenerator = null, preset: Array = []) -> void:
	if not preset.is_empty():
		for c in preset:
			deck.append(c)
		return
	for suit in 4:
		for rank in RANKS:
			deck.append({"rank": rank, "suit": suit})
	for i in range(deck.size() - 1, 0, -1):  # Fisher-Yates
		var j := rng.randi_range(0, i) if rng else randi_range(0, i)
		var tmp := deck[i]
		deck[i] = deck[j]
		deck[j] = tmp

func draw_card() -> Dictionary:
	return deck.pop_front()

## Best total: Aces count 11 unless that would bust, then 1
static func hand_value(cards: Array) -> int:
	var total := 0
	var aces := 0
	for c in cards:
		match c.rank:
			"A":
				total += 11
				aces += 1
			"J", "Q", "K":
				total += 10
			_:
				total += int(c.rank)
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total

static func is_blackjack(cards: Array) -> bool:
	return cards.size() == 2 and hand_value(cards) == 21

static func is_bust(cards: Array) -> bool:
	return hand_value(cards) > 21

func dealer_should_draw() -> bool:
	return hand_value(dealer) < DEALER_STANDS_ON

## After the player stands (or doubles) and the dealer has finished drawing:
## "player_blackjack" | "dealer_blackjack" | "push" | "player_bust" | "dealer_bust" | "win" | "lose"
func outcome() -> String:
	var p := hand_value(player)
	var d := hand_value(dealer)
	var p_bj := is_blackjack(player)
	var d_bj := is_blackjack(dealer)
	if p_bj and d_bj:
		return "push"
	if p_bj:
		return "player_blackjack"
	if d_bj:
		return "dealer_blackjack"
	if p > 21:
		return "player_bust"
	if d > 21:
		return "dealer_bust"
	if p > d:
		return "win"
	if p < d:
		return "lose"
	return "push"

## Total Money returned for a bet with this outcome (0 when the bet is lost)
static func payout(result: String, bet: int) -> int:
	match result:
		"player_blackjack":
			return roundi(bet * BLACKJACK_PAYOUT)
		"win", "dealer_bust":
			return roundi(bet * WIN_PAYOUT)
		"push":
			return bet
	return 0
