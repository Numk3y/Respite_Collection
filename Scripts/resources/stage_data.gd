@tool
class_name StageData
extends Resource
## A map you can battle on.
## Story maps belong to a chapter: X-1 to X-4 are regular maps and X-5 is the chapter's boss.
## Chapter 0 holds maps outside the story (like Test); they're always open.

const MAPS_PER_CHAPTER := 4
const BOSS_NUMBER := 5
const ENEMY_GROWTH_PER_LEVEL := 0.09  # per enemy level; a bit over twice friends' growth (GameState.GROWTH_PER_LEVEL = 0.04)

@export var id: StringName
@export var display_name: String
@export_multiline var description: String  # shown on the map list
@export var chapter: int = 1  # 0 = outside the story, always open
@export_range(1, 5) var number: int = 1  # 1-4 regular maps, 5 = boss
@export var recommended_level: int = 1
@export var background: Texture2D
@export_group("Enemies")
## Enemies' stats grow with this level the same way friends' do (Lv.1 = their base stats).
## 0 = use recommended_level, so the same enemy gets tougher on harder maps.
@export var enemy_level: int = 0
## The mission's battles, fought back to back (FGO-style); the last is usually the mini boss.
## If empty, the single wave below is used instead.
@export var waves: Array[WaveData] = []
## Single-wave enemies (up to 3 per row), used only when `waves` is empty
@export var enemy_vanguard: Array[CharacterData] = []
@export var enemy_rearguard: Array[CharacterData] = []
@export_group("Rewards")  # for clearing the whole mission
@export var reward_money: int = 50
@export var exp_reward: int = 10  # given to every friend in the team
@export var reward_materials: Dictionary[String, Vector2i] = {}  # material key -> (min, max)
@export var equipment_drops: Array[EquipmentData] = []
@export_range(0.0, 1.0) var drop_chance: float = 0.05

func is_story() -> bool:
	return chapter > 0

func is_boss() -> bool:
	return is_story() and number == BOSS_NUMBER

## "1-3" for story maps, "" for maps outside the story
func code() -> String:
	return "%d-%d" % [chapter, number] if is_story() else ""

func get_enemy_level() -> int:
	return maxi(enemy_level if enemy_level > 0 else recommended_level, 1)

## An enemy's base stats grown to this map's enemy level (negative stats stay as they are)
func _scaled_stats(c: CharacterData) -> Dictionary:
	var stats := c.base_stats()
	var mult := 1.0 + ENEMY_GROWTH_PER_LEVEL * (get_enemy_level() - 1)
	for stat in stats:
		if stats[stat] > 0:
			stats[stat] = roundi(stats[stat] * mult)
	return stats

func wave_count() -> int:
	return maxi(waves.size(), 1)

## {"waves": [team, ...]} for BattleEngine, where each team has the same shape as GameState.get_battle_team()
## plus "boss": bool
func get_enemy_team() -> Dictionary:
	var out := []
	if waves.is_empty():
		out.append(_wave_team(enemy_vanguard, enemy_rearguard, false))
	for w in waves:
		if w:
			out.append(_wave_team(w.enemy_vanguard, w.enemy_rearguard, w.is_boss))
	return {"waves": out}

func _wave_team(vanguard: Array[CharacterData], rearguard: Array[CharacterData], boss: bool) -> Dictionary:
	var team := {"vanguard": [], "rearguard": [], "boss": boss}
	for c in vanguard.slice(0, 3):
		if c:
			team.vanguard.append(c.battle_unit(_scaled_stats(c)))
	for c in rearguard.slice(0, 3):
		if c:
			team.rearguard.append(c.battle_unit(_scaled_stats(c)))
	# Tell identical enemies apart in battle: "Drunk Person A", "Drunk Person B", ...
	var units: Array = team.vanguard + team.rearguard
	var counts := {}
	for u in units:
		counts[u.name] = counts.get(u.name, 0) + 1
	var seen := {}
	for u in units:
		var base_name: String = u.name
		if counts[base_name] > 1:
			var i: int = seen.get(base_name, 0)
			seen[base_name] = i + 1
			u.name = "%s %s" % [base_name, char(65 + i)]
	return team
