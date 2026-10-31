extends Node
## Gacha pulls. Autoload name: Gacha

signal pulled(results: Array[Dictionary])

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

## Returns [{character, rarity, is_new, uid}]; empty if money is short or the pool is empty
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

	if not GameState.try_spend(pool.cost * count):
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

		var is_new := not GameState.owns(entry.character.id)
		var owned := GameState.add_character(entry.character)
		results.append({"character": entry.character, "rarity": rarity, "is_new": is_new, "uid": owned.uid})

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
