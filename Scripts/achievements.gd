class_name Achievements
extends RefCounted
## Lifetime goals in tiers (10 wins, 50 wins, 200 wins ...), each tier paid once when claimed in the Daily window's
## Achievements tab. Progress comes from GameState's lifetime counters ("stat") or is worked out from the save
## ("calc": friends owned, stars, account level ...), so anything done before a goal existed still counts.
## Save data: GameState.data.achievements = {achievement_id: tiers claimed}. Text: Terms "ach_<id>" ({goal}).
## Rewards use the Daily reward format ([kind, amount] pairs).

const LIST := [
	{"id": "wins", "stat": "wins", "tiers": [
		[10, [["credit_card", 1]]], [50, [["credit_card", 2]]], [200, [["credit_card", 3]]], [500, [["credit_card", 5]]]]},
	{"id": "flawless", "stat": "flawless_wins", "tiers": [
		[5, [["money", 2000]]], [25, [["credit_card", 2]]], [100, [["credit_card", 3]]]]},
	{"id": "friends", "calc": "friends", "tiers": [
		[5, [["credit_card", 1]]], [10, [["credit_card", 2]]], [20, [["credit_card", 3]]], [30, [["credit_card", 5]]]]},
	{"id": "stars", "calc": "stars", "tiers": [
		[10, [["credit_card", 1]]], [25, [["credit_card", 2]]], [45, [["credit_card", 3]]]]},
	{"id": "account", "calc": "account_level", "tiers": [
		[10, [["credit_card", 1]]], [20, [["credit_card", 2]]], [30, [["credit_card", 3]]], [40, [["credit_card", 5]]]]},
	{"id": "awaken", "calc": "max_ascension", "tiers": [
		[1, [["credit_card", 2]]], [3, [["credit_card", 3]]], [6, [["credit_card", 5]]]]},
	{"id": "bond", "calc": "max_bond", "tiers": [
		[1, [["gossip", 5]]], [5, [["credit_card", 2]]], [10, [["credit_card", 3]]]]},
	{"id": "shifts", "stat": "shifts_done", "tiers": [
		[5, [["money", 1500]]], [25, [["gossip", 5]]], [100, [["credit_card", 2]]], [300, [["credit_card", 3]]]]},
	{"id": "pulls", "stat": "pulls", "tiers": [
		[10, [["coffee", 5]]], [50, [["credit_card", 2]]], [150, [["credit_card", 3]]]]},
	{"id": "arena", "stat": "arena_wins", "tiers": [
		[5, [["money", 2000]]], [25, [["credit_card", 2]]], [100, [["credit_card", 3]]]]},
	{"id": "gear", "stat": "gear_work", "tiers": [
		[5, [["parts", 20]]], [25, [["parts", 60]]], [75, [["credit_card", 2]]]]},
	{"id": "ultimates", "stat": "manual_ultimates", "tiers": [
		[10, [["snack", 10]]], [100, [["credit_card", 1]]], [500, [["credit_card", 2]]]]},
	{"id": "casino", "stat": "casino_games", "tiers": [
		[10, [["money", 1000]]], [50, [["money", 3000]]], [200, [["credit_card", 1]]]]},
	{"id": "checkins", "stat": "checkins", "tiers": [
		[7, [["credit_card", 1]]], [30, [["credit_card", 3]]], [100, [["credit_card", 5]]]]},
]

static func _claimed() -> Dictionary:
	return GameState.data.get_or_add("achievements", {})

static func find(id: String) -> Dictionary:
	for a: Dictionary in LIST:
		if a.id == id:
			return a
	return {}

## The lifetime number this achievement counts
static func value(a: Dictionary) -> int:
	if a.has("stat"):
		return GameState.get_stat(String(a.stat))
	var out := 0
	match String(a.calc):
		"friends":
			out = GameState.data.owned.filter(func(o): return GameState.get_character(int(o.uid)) != null).size()
		"stars":
			for stage in DB.stages:
				if stage.is_story():
					out += GameState.star_count(stage.id)
		"account_level":
			out = GameState.get_account_level()
		"max_ascension":
			out = GameState.data.owned.filter(func(o): return int(o.get("ascension", 0)) >= GameState.MAX_ASCENSION).size()
		"max_bond":
			out = GameState.data.owned.filter(func(o): return GameState.get_bond(int(o.uid)) >= GameState.max_bond()).size()
	return out

## Tiers already claimed
static func tier(a: Dictionary) -> int:
	return int(_claimed().get(String(a.id), 0))

static func is_complete(a: Dictionary) -> bool:
	return tier(a) >= a.tiers.size()

## The goal of the next tier to claim (the last one once complete)
static func goal(a: Dictionary) -> int:
	return int(a.tiers[mini(tier(a), a.tiers.size() - 1)][0])

static func reward(a: Dictionary) -> Array:
	return a.tiers[mini(tier(a), a.tiers.size() - 1)][1]

static func is_ready(a: Dictionary) -> bool:
	return not is_complete(a) and value(a) >= goal(a)

static func title(a: Dictionary) -> String:
	return Terms.t("ach_" + String(a.id), {"goal": Terms.number(goal(a))})

## Pays the next tier; returns its reward, or [] if it isn't reached yet
static func claim(a: Dictionary) -> Array:
	if not is_ready(a):
		return []
	var got := reward(a)
	_claimed()[String(a.id)] = tier(a) + 1
	Daily.grant(got)
	GameState.request_save()
	Daily.changed.emit()
	return got

static func claim_all() -> Array:
	var out: Array = []
	for a: Dictionary in LIST:
		while is_ready(a):
			out.append_array(claim(a))
	return out

static func claimable_count() -> int:
	return LIST.filter(func(a): return is_ready(a)).size()
