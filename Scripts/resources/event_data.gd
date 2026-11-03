@tool
class_name EventData
extends Resource
## A limited-time event: missions played in order, then the World Boss that every player fights together.
## Each event lives in its own folder, Data/events/<id>/event.tres, next to its mission stage files.
## The server only keeps the shared HP and everyone's damage; open the event with
##   server\boss_admin.ps1 start -Event <id> -Key <admin key>
## which reads boss_hp, hours, attempts_per_day and max_damage_per_fight from this file.
## The Event tab only shows the event while the server says it's live.
##
## Mission stage files: give each a unique id (e.g. "lunar_night_1_1") and set chapter / number for the code
## shown on the route (1-1 ... 1-4, 2-1 ...). They unlock in the order listed in `missions`.

@export var id: StringName  # must match the folder name; the server knows the event by it
@export var display_name: String
@export_multiline var description: String
@export var banner: Texture2D  # the Event tab's picture, also the missions' fallback background
@export var missions: Array[StageData] = []

@export_group("World Boss")
## The boss fight itself: its waves, enemy level and background. Its own rewards are ignored (see below).
## Every enemy in it counts: damage to any of them comes off the shared HP.
@export var boss_stage: StageData
@export var boss_hp: int = 1000000  # shared by every player
@export var hours: float = 72.0  # how long the event runs once opened
@export var attempts_per_day: int = 5  # boss fights per player per day (resets 00:00 UTC)
@export var actions_per_fight: int = 40  # each boss fight ends after this many actions (both sides count)
## The boss fight's enemies take their stats at the attacking team's average level (growing like friends do)
## instead of the boss stage's enemy level, so the fight stays just as dangerous for strong and weak teams
@export var boss_matches_team_level := false
## The server ignores any single fight's damage above this (a cheating guard).
## 0 = automatic: twice the total HP of the boss fight's enemies, leaving room for their heals.
@export var max_damage_per_fight: int = 0

@export_group("Rewards")
## Rewards are only given if the boss is defeated, and only to players who hit it at least once
@export var reward_all: EventReward
## Extra for the top damage dealers: the first entry for 1st place, then 2nd, then 3rd
@export var reward_top: Array[EventReward] = []

## The mission players can play: the first, then each one after the previous is cleared
func is_mission_unlocked(stage: StageData) -> bool:
	var i := missions.find(stage)
	if i <= 0:
		return i == 0
	return GameState.is_stage_cleared(missions[i - 1].id)

func missions_cleared() -> int:
	return missions.filter(func(s): return s and GameState.is_stage_cleared(s.id)).size()

## The World Boss opens once every mission is cleared
func is_boss_unlocked() -> bool:
	return missions_cleared() >= missions.filter(func(s): return s != null).size()

func has_mission(stage: StageData) -> bool:
	return missions.has(stage)

## Mission parts (stage chapter numbers) in order
func chapters() -> Array[int]:
	var out: Array[int] = []
	for s in missions:
		if s and not out.has(s.chapter):
			out.append(s.chapter)
	out.sort()
	return out

func chapter_missions(chapter: int) -> Array:
	var out := missions.filter(func(s): return s and s.chapter == chapter)
	out.sort_custom(func(a, b): return a.number < b.number)
	return out

## The boss fight's enemies for BattleEngine, with the action limit. `team_level` is the team's average level,
## used when boss_matches_team_level is on.
func boss_enemies(team_level: int = 0) -> Dictionary:
	var enemies := boss_stage.get_enemy_team(team_level if boss_matches_team_level else 0)
	enemies.max_actions = actions_per_fight
	enemies.timeout_key = "log_boss_timeout"
	return enemies

## The damage cap the server uses for one fight
func damage_cap() -> int:
	if max_damage_per_fight > 0:
		return max_damage_per_fight
	var total := 0
	for wave in boss_stage.get_enemy_team().waves:
		for u in wave.vanguard + wave.rearguard:
			total += int(u.stats.hp)
	return total * 2

## A reward for this rank (1 = first), or null past the ones set
func top_reward(rank: int) -> EventReward:
	return reward_top[rank - 1] if rank >= 1 and rank <= reward_top.size() else null
