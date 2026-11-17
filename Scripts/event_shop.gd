class_name EventShop
extends RefCounted
## Event currency and the event shop (see EventData's "Event Shop" group and EventShopItem).
## Save data: GameState.data.event_currency = {event_id: amount},
##            GameState.data.event_shop = {event_id: {item index (as a string): times bought}}.
## Currency stays in the save after an event ends but can only be spent while the event's shop is open
## (the Event tab shows the event).

static func currency(event: EventData) -> int:
	return int(GameState.data.get_or_add("event_currency", {}).get(String(event.id), 0))

static func add_currency(event: EventData, amount: int) -> void:
	if amount == 0 or not event.has_shop():
		return
	var all: Dictionary = GameState.data.get_or_add("event_currency", {})
	all[String(event.id)] = maxi(currency(event) + amount, 0)
	GameState.add_stat("event_currency", maxi(amount, 0))
	GameState.request_save()
	GameState.materials_changed.emit()  # the event tab and shop show the balance

## Currency for a mission win, rolled from the event's range for that mission (0 if the event has no shop)
static func roll_drop(event: EventData, stage: StageData, rng: RandomNumberGenerator) -> int:
	if not event.has_shop():
		return 0
	var r := event.currency_drop(stage)
	return rng.randi_range(r.x, maxi(r.x, r.y))

static func bought(event: EventData, index: int) -> int:
	var shop: Dictionary = GameState.data.get_or_add("event_shop", {}).get(String(event.id), {})
	return int(shop.get(str(index), 0))

## How many more of an item can be bought (-1 = no limit)
static func left(event: EventData, index: int) -> int:
	var item := event.shop[index]
	return -1 if item.stock <= 0 else maxi(item.stock - bought(event, index), 0)

## How many of an item the player can buy right now (stock and currency both count)
static func max_buyable(event: EventData, index: int) -> int:
	var item := event.shop[index]
	var by_money := currency(event) / maxi(item.cost, 1)
	var stock := left(event, index)
	return by_money if stock < 0 else mini(by_money, stock)

## Buys `count` of an item; returns what was received ([] if it can't be bought)
static func buy(event: EventData, index: int, count: int = 1) -> Array:
	if index < 0 or index >= event.shop.size() or count <= 0 or count > max_buyable(event, index):
		return []
	var item := event.shop[index]
	var all: Dictionary = GameState.data.get_or_add("event_currency", {})
	all[String(event.id)] = currency(event) - item.cost * count
	var shops: Dictionary = GameState.data.get_or_add("event_shop", {})
	var mine: Dictionary = shops.get_or_add(String(event.id), {})
	mine[str(index)] = bought(event, index) + count
	var got := [[item.kind, item.amount * count]]
	Daily.grant(got)
	GameState.add_stat("event_shop_buys", count)
	GameState.save_game()
	GameState.materials_changed.emit()
	return got
