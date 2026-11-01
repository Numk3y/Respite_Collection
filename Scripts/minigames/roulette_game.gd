class_name RouletteGame
extends RefCounted
## Russian Roulette duel against Nilla. The player picks how many bullets go into the CHAMBERS (more bullets,
## bigger payout); the cylinder is spun once, then the player and Nilla take turns pulling the trigger (player
## first, no re-spin) until it fires. Whoever is not shot wins. See win_chance() for the exact odds.

const CHAMBERS := 6
const MIN_BULLETS := 1
const MAX_BULLETS := 5
## Total returned on a win (bet included) per bullet count, set so every choice gives back ~97% on average
## (payout = 0.97 / win_chance): 1: 50% x 1.94, 2: 40% x 2.43, 3: 35% x 2.77, 4: 26.7% x 3.64, 5: 16.7% x 5.82
const PAYOUTS := {1: 1.94, 2: 2.43, 3: 2.77, 4: 3.64, 5: 5.82}

var bullets := 2
var loaded: Array[bool] = []
var position := 0  # the chamber the next pull fires

## `preset` (tests only) gives the loaded chambers instead of a random spin
func _init(bullet_count: int = 2, rng: RandomNumberGenerator = null, preset: Array = []) -> void:
	bullets = clampi(bullet_count, MIN_BULLETS, MAX_BULLETS)
	if not preset.is_empty():
		loaded.assign(preset)
		return
	loaded.resize(CHAMBERS)
	loaded.fill(false)
	var placed := 0
	while placed < bullets:
		var i := rng.randi_range(0, CHAMBERS - 1) if rng else randi_range(0, CHAMBERS - 1)
		if not loaded[i]:
			loaded[i] = true
			placed += 1

func is_player_turn() -> bool:
	return position % 2 == 0

## Fires the current chamber; true means it went off
func pull() -> bool:
	var bang := loaded[position]
	position += 1
	return bang

static func payout_multiplier(bullet_count: int) -> float:
	return PAYOUTS[bullet_count]

static func payout(won: bool, bet: int, bullet_count: int) -> int:
	return roundi(bet * payout_multiplier(bullet_count)) if won else 0

## Exact chance the player survives, over every way the bullets can be loaded (player pulls chambers 0, 2, 4...)
static func win_chance(bullet_count: int) -> float:
	var total := 0
	var wins := 0
	for mask in 1 << CHAMBERS:
		var count := 0
		for i in CHAMBERS:
			count += (mask >> i) & 1
		if count != bullet_count:
			continue
		total += 1
		var first := 0
		while not (mask >> first) & 1:
			first += 1
		if first % 2 == 1:
			wins += 1
	return float(wins) / total
