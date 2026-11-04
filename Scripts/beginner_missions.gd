class_name BeginnerMissions
extends RefCounted
## The beginner checklist: each mission teaches one part of the game and pays Credit Cards (or Money) when
## claimed; claiming them all unlocks a free SSR of the player's choice. Progress is read from the save as it is
## (cleared maps, stars, levels, team, GameState lifetime counters), so a mission done before it was ever shown
## simply counts. Save data: GameState.data.beginner = {"claimed": {mission_id: true}, "ssr_claimed": bool}.
## Text: Terms "beginner_<id>".

## In the order they're listed (and roughly the order a new player meets them). Rewards: Credit Cards ("cards"),
## Money and EXP materials; Credit Cards are kept scarce (5 in all), the real prize is the free SSR at the end.
const MISSIONS := [
	{"id": "first_win", "goal": 1, "cards": 0, "money": 500, "materials": {}},
	{"id": "manual_ult", "goal": 1, "cards": 1, "money": 0, "materials": {}},
	{"id": "recruit", "goal": 10, "cards": 0, "money": 0, "materials": {"coffee": 3}},
	{"id": "team", "goal": 5, "cards": 0, "money": 1000, "materials": {}},
	{"id": "level", "goal": 10, "cards": 1, "money": 0, "materials": {}},
	{"id": "commission", "goal": 1, "cards": 0, "money": 500, "materials": {}},
	{"id": "three_stars", "goal": 3, "cards": 1, "money": 0, "materials": {"snack": 5}},
	{"id": "chapter_boss", "goal": 1, "cards": 2, "money": 0, "materials": {}},
]
const BOSS_MAP := &"poppy_street_boss"  # 1-5

## How far along a mission is, capped at its goal
static func progress(mission: Dictionary) -> int:
	var value := 0
	match String(mission.id):
		"first_win":
			for stage in DB.stages:
				if stage.is_story() and GameState.is_stage_cleared(stage.id):
					value = 1
		"manual_ult":
			value = GameState.get_stat("manual_ultimates")
		"recruit":
			value = GameState.get_stat("pulls")
		"team":
			value = GameState.team_members().size()
		"level":
			for o in GameState.data.owned:
				value = maxi(value, int(o.level))
		"commission":
			value = GameState.get_stat("commissions")
		"three_stars":
			for stage in DB.stages:
				value = maxi(value, GameState.star_count(stage.id))
		"chapter_boss":
			value = 1 if GameState.is_stage_cleared(BOSS_MAP) else 0
	return mini(value, int(mission.goal))

static func is_done(mission: Dictionary) -> bool:
	return progress(mission) >= int(mission.goal)

static func is_claimed(mission: Dictionary) -> bool:
	return GameState.data.beginner.claimed.has(String(mission.id))

## Pays the mission's reward once it's done; returns false if it isn't done or was already claimed
static func claim(mission: Dictionary) -> bool:
	if not is_done(mission) or is_claimed(mission):
		return false
	GameState.data.beginner.claimed[String(mission.id)] = true
	if int(mission.cards) > 0:
		GameState.add_credit_cards(int(mission.cards))
	if int(mission.money) > 0:
		GameState.add_money(int(mission.money))
	for key in mission.materials:
		GameState.add_material(key, int(mission.materials[key]))
	GameState.stats_changed.emit()
	GameState.request_save()
	return true

static func all_claimed() -> bool:
	return MISSIONS.all(func(m): return is_claimed(m))

static func ssr_claimed() -> bool:
	return bool(GameState.data.beginner.get("ssr_claimed", false))

## Finished and done with: every mission claimed and the free SSR picked (the Home button then goes away)
static func finished() -> bool:
	return all_claimed() and ssr_claimed()

## Missions ready to claim, plus the SSR pick once it's available (for the badge on Home)
static func claimable_count() -> int:
	var count := MISSIONS.filter(func(m): return is_done(m) and not is_claimed(m)).size()
	if all_claimed() and not ssr_claimed():
		count += 1
	return count

## The SSRs on offer for the free pick: every enabled SSR in a recruit pool
static func ssr_choices() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for pool in DB.pools.filter(func(p): return not p.beginner):
		for entry in pool.entries:
			var c: CharacterData = entry.character
			if c and c.enabled and c.rarity == CharacterData.Rarity.SSR and not out.has(c):
				out.append(c)
	out.sort_custom(func(a, b): return a.display_name < b.display_name)
	return out

## Gives the chosen SSR (a duplicate raises Ascension like a pull would). Returns GameState.receive_character's
## result, or {} if the pick isn't available.
static func claim_ssr(c: CharacterData) -> Dictionary:
	if not all_claimed() or ssr_claimed() or not ssr_choices().has(c):
		return {}
	GameState.data.beginner.ssr_claimed = true
	var result := GameState.receive_character(c)
	GameState.stats_changed.emit()
	GameState.save_game()
	return result
