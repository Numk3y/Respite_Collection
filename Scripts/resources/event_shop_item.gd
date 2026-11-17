@tool
class_name EventShopItem
extends Resource
## One thing in an event's shop (EventData.shop), bought with the event's currency (e.g. Scraps).
## `kind` is what you get, `amount` how much per purchase, `cost` the price in event currency, `stock` how many
## times it can be bought during the event (0 = no limit). Bought counts are kept in the save per event.

@export_enum("money", "credit_card", "parts", "snack", "coffee", "gossip", "recruit_ticket", "sr_ticket") var kind: String = "money"
@export var amount: int = 1
@export var cost: int = 100
@export var stock: int = 0

## What one purchase gives, in the reward format Daily.grant / Daily.reward_text use
func reward() -> Array:
	return [[kind, amount]]
