@tool
class_name EventReward
extends Resource
## One reward package from an event's world boss (see EventData). Leave anything at 0 / empty to skip it.

@export var money: int = 0
@export var credit_cards: int = 0
@export var materials: Dictionary[String, int] = {}  # material key ("snack", "coffee", "gossip") -> amount
@export var equipment: Array[EquipmentData] = []  # one of each
## Friends to hand out; one you already own raises their Ascension instead, like a gacha copy
@export var characters: Array[CharacterData] = []

func is_empty() -> bool:
	return money <= 0 and credit_cards <= 0 and materials.values().all(func(n): return n <= 0) \
		and equipment.is_empty() and characters.is_empty()

## Gives everything to the player
func grant() -> void:
	if money > 0:
		GameState.add_money(money)
	if credit_cards > 0:
		GameState.add_credit_cards(credit_cards)
	for key in materials:
		if materials[key] > 0:
			GameState.add_material(key, materials[key])
	for e in equipment:
		if e:
			GameState.add_equipment(e)
	for c in characters:
		if c:
			GameState.receive_character(c)

## What's in it, one line per kind, for the event screen and the reward popup
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	if money > 0:
		out.append(Terms.t("event_reward_money", {"amount": money}))
	if credit_cards > 0:
		out.append(Terms.t("event_reward_cards", {"amount": credit_cards, "card_word": Terms.credit_card_word(credit_cards)}))
	for key in materials:
		if materials[key] > 0:
			out.append(Terms.t("event_reward_material", {"amount": materials[key], "material": Terms.material_name(key)}))
	for e in equipment:
		if e:
			out.append(e.display_name)
	for c in characters:
		if c:
			out.append(Terms.t("event_reward_friend", {"name": c.display_name}))
	return out
