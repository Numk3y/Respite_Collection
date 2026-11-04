extends Node
## Gacha pulls. Autoload name: Gacha

signal pulled(results: Array[Dictionary])

const GUARANTEE_PULLS := 10  # a pull this big always includes at least one SR or better

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

## Money cost of `count` pulls from this pool
func money_cost(pool: GachaPool, count: int) -> int:
	return pool.cost * count

## Credit Card cost of `count` pulls (the same on every pool)
func card_cost(count: int) -> int:
	return GameState.CREDIT_CARDS_PER_PULL * count

## Each pull costs the pool's Money price AND Credit Cards.
## Returns [{character, rarity, is_new, uid, result: "new" | "ascend" | "overflow", rank, money}];
## empty if either currency is short or the pool is empty
func pull(pool: GachaPool, count: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []

	# Group by rarity, keeping only enabled characters with weight > 0
	var by_rarity: Dictionary = {}
	for entry in pool.entries:
		if entry.character and entry.character.enabled and entry.weight > 0:
			by_rarity.get_or_add(entry.character.rarity, []).append(entry)
	# Rarities with no characters in the pool are skipped; the rest scale up proportionally
	var rarities: Array = by_rarity.keys().filter(func(r): return pool.weight_for(r) > 0)
	if rarities.is_empty():
		push_warning("Gacha pool %s has no characters to pull" % pool.id)
		return results

	if not GameState.try_spend_pull(money_cost(pool, count), card_cost(count)):
		return results
	GameState.add_stat("pulls", count)  # beginner missions

	var top := CharacterData.Rarity.SSR
	var since_top := GameState.get_pity(pool.id)
	var got_sr := false  # for the multi-pull guarantee
	for i in count:
		var rarity: int
		if pool.pity_threshold > 0 and since_top + 1 >= pool.pity_threshold and by_rarity.has(top):
			rarity = top
		else:
			rarity = _weighted_pick(rarities, func(r): return pool.weight_for(r))
		# A pull of GUARANTEE_PULLS or more always has an SR or better: if none came up, the last one becomes SR
		if count >= GUARANTEE_PULLS and i == count - 1 and not got_sr and rarity < CharacterData.Rarity.SR:
			if rarities.has(CharacterData.Rarity.SR):
				rarity = CharacterData.Rarity.SR
			elif rarities.has(top):
				rarity = top
		got_sr = got_sr or rarity >= CharacterData.Rarity.SR
		var entry: PoolEntry = _weighted_pick(by_rarity[rarity], func(e): return e.weight)
		since_top = 0 if rarity == top else since_top + 1
		GameState.add_pull_history(entry.character, rarity, pool.id)

		# Duplicates raise the owned copy's Ascension instead of adding a second card
		var received := GameState.receive_character(entry.character)
		received.character = entry.character
		received.rarity = rarity
		received.is_new = received.result == "new"
		results.append(received)

	GameState.data.pity[String(pool.id)] = since_top
	GameState.save_game()  # save right away so closing the game can't reroll a pull
	pulled.emit(results)
	return results

## The new player's free Beginner pool pull is still waiting
func beginner_available() -> bool:
	return GameState.data.starter_chosen and not bool(GameState.data.beginner.get("pool_pulled", false))

## The one free pull from a Beginner pool: no cost, no pity, and it picks among the pool's friends the player
## doesn't own yet (any of them if they own them all). The friend joins the first team if their row has room.
## Returns the same result shape as pull(), or [] if it's used up.
func beginner_pull(pool: GachaPool) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	if not pool.beginner or not beginner_available():
		return results
	var entries := pool.entries.filter(func(e): return e.character and e.character.enabled and e.weight > 0)
	if entries.is_empty():
		return results
	var fresh := entries.filter(func(e): return not GameState.owns(e.character.id))
	var pick: PoolEntry = _weighted_pick(fresh if not fresh.is_empty() else entries, func(e): return e.weight)
	GameState.data.beginner.pool_pulled = true
	GameState.add_pull_history(pick.character, pick.character.rarity, pool.id)
	var received := GameState.receive_character(pick.character)
	received.character = pick.character
	received.rarity = pick.character.rarity
	received.is_new = received.result == "new"
	received.joined_team = GameState.place_in_team(int(received.uid))
	results.append(received)
	GameState.save_game()
	pulled.emit(results)
	return results

func _weighted_pick(items: Array, weight_of: Callable) -> Variant:
	var total := 0
	for it in items:
		total += weight_of.call(it)
	var roll := _rng.randi_range(0, total - 1)
	for it in items:
		roll -= weight_of.call(it)
		if roll < 0:
			return it
	return items.back()
