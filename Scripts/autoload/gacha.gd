extends Node
## Gacha pulls. Autoload name: Gacha

signal pulled(results: Array[Dictionary])

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

	var top := CharacterData.Rarity.SSR
	var since_top := GameState.get_pity(pool.id)
	for _i in count:
		var rarity: int
		if pool.pity_threshold > 0 and since_top + 1 >= pool.pity_threshold and by_rarity.has(top):
			rarity = top
		else:
			rarity = _weighted_pick(rarities, func(r): return pool.weight_for(r))
		var entry: PoolEntry = _weighted_pick(by_rarity[rarity], func(e): return e.weight)
		since_top = 0 if rarity == top else since_top + 1

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
