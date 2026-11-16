@tool
class_name SynergyData
extends Resource
## A team synergy: a bonus for putting certain friends together (see PLANS.md "Team synergies").
## One .tres per synergy in Data/synergies/. GameState.team_synergies() works out which are on; get_battle_team()
## adds the bonuses (capped at GameState.SYNERGY_CAP per stat for each friend).
##
## Who counts, by rule:
## - Friends: the friends listed in `members` (a real friend group, e.g. the Bald Squad)
## - Class: friends of any class in `classes`; with need_each_class on, it counts how many of the listed classes are
##   present instead (Healer + Tank: 2 once there's one of each)
## - Rarity: friends of `rarity` (e.g. three or more R friends)
## The count picks the tier: tiers = [2, 3] means tier 1 at 2 counted, tier 2 at 3. tier_bonuses has one
## {stat: share} per tier, e.g. {"attack": 0.05} = +5% Attack. `target` says who gets it: the counted friends or the
## whole team.

enum Rule { FRIENDS, CLASS, RARITY }
enum Target { COUNTED, TEAM }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var enabled: bool = true
@export var rule: Rule = Rule.FRIENDS
@export var members: Array[StringName] = []  # Friends rule: character ids
@export var classes: Array[int] = []  # Class rule: CharacterData.CharClass values (0 Tank, 1 Warrior, 2 Mage, 3 Marksman, 4 Berserker, 5 Healer)
@export var need_each_class: bool = false
@export var rarity: int = 1  # Rarity rule: CharacterData.Rarity (1 R, 2 SR, 3 SSR)
@export var tiers: Array[int] = [2]
@export var tier_bonuses: Array[Dictionary] = []
@export var target: Target = Target.COUNTED

## The friends in `team` (CharacterData list) this synergy counts
func counted(team: Array) -> Array:
	match rule:
		Rule.FRIENDS:
			return team.filter(func(c): return members.has(c.id))
		Rule.CLASS:
			return team.filter(func(c): return classes.has(int(c.char_class)))
		Rule.RARITY:
			return team.filter(func(c): return int(c.rarity) == rarity)
	return []

func count(team: Array) -> int:
	var hits := counted(team)
	if rule == Rule.CLASS and need_each_class:
		var seen := {}
		for c in hits:
			seen[int(c.char_class)] = true
		return seen.size()
	if rule == Rule.FRIENDS:
		var ids := {}
		for c in hits:
			ids[c.id] = true
		return ids.size()
	return hits.size()

## 0 = off, 1 = the first tier, ...
func tier_for(n: int) -> int:
	var t := 0
	for i in tiers.size():
		if n >= tiers[i]:
			t = i + 1
	return t

## The most this synergy can count (for "2/3"): the top tier's need
func top_need() -> int:
	return tiers.back() if not tiers.is_empty() else 1

func bonus(tier: int) -> Dictionary:
	return tier_bonuses[tier - 1] if tier >= 1 and tier <= tier_bonuses.size() else {}
