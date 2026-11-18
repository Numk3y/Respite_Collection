extends Node
## Weekly Challenge: three story boss maps replayed under this week's rules, one per tier (Normal: chapter 1-2,
## Hard: 3-4, Extreme: 5-6). Each week (Daily.this_week, Monday at Daily.RESET_HOUR) brings one team rule (who may
## fight, checked before the battle) and two battle rules (applied by FormationBattleEngine through the teams'
## "rules"; see _add_side). Everyone gets the same set, picked from the week number. A tier opens once its boss map
## is cleared in the story, and its first win of the week pays the tier's reward; later wins pay nothing.
## Autoload name: Challenge. Save data: GameState.data.challenge (see _data). Text: Terms "challenge_*".

signal changed

const TIERS := [
	{"key": "normal", "chapters": [1, 2], "reward": [["credit_card", 1], ["money", 1500], ["coffee", 2]]},
	{"key": "hard", "chapters": [3, 4], "reward": [["credit_card", 2], ["money", 3000], ["gossip", 2]]},
	{"key": "extreme", "chapters": [5, 6], "reward": [["credit_card", 3], ["money", 5000], ["gossip", 4]]},
]

## Who may fight. Text: Terms "challenge_rule_<id>" (and "challenge_bad_<id>" for why a team can't go).
const TEAM_RULES := ["no_healers", "no_tanks", "max_sr", "r_only", "small_team"]
const SMALL_TEAM := 3

## How the battle changes, as FormationBattleEngine side rules for "allies" and/or "enemies"
const BATTLE_RULES := {
	"heal_cut": {"allies": {"heal_mult": 0.5}},
	"wound": {"enemies": {"wound": {"chance": 1.0, "heal_cut": 0.5, "turns": 2}}},
	"enemy_speed": {"enemies": {"stat_mult": {"speed": 1.25}}},
	"enemy_hp": {"enemies": {"stat_mult": {"hp": 1.4}}},
	"fragile_back": {"allies": {"rear_damage_taken": 0.5}},
	"glass_cannon": {"allies": {"stat_mult": {"attack": 1.5}}, "enemies": {"stat_mult": {"attack": 1.5}}},
}
const BATTLE_RULE_COUNT := 2
## Battle rules that would barely matter with this team rule, so they aren't drawn together
const CLASHES := {"no_healers": ["heal_cut", "wound"]}

var _week_cache := -1
var _picks := {}  # this week's draw: {"team": id, "battle": [ids], "chapters": [chapter per tier]}

# ───────── This week's draw ─────────

## The week's team rule, battle rules and maps, from the week number alone
func _draw() -> Dictionary:
	var week := Daily.this_week()
	if week == _week_cache:
		return _picks
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("respite_challenge_%d" % week)
	var team: String = TEAM_RULES[rng.randi_range(0, TEAM_RULES.size() - 1)]
	var pool: Array = BATTLE_RULES.keys().filter(func(id): return not CLASHES.get(team, []).has(id))
	var battle: Array = []
	for i in BATTLE_RULE_COUNT:
		var j := rng.randi_range(0, pool.size() - 1)
		battle.append(pool[j])
		pool.remove_at(j)
	var chapters: Array = []
	for tier: Dictionary in TIERS:
		var options: Array = tier.chapters
		chapters.append(options[rng.randi_range(0, options.size() - 1)])
	_week_cache = week
	_picks = {"team": team, "battle": battle, "chapters": chapters}
	return _picks

func team_rule() -> String:
	return _draw().team

func battle_rules() -> Array:
	return _draw().battle

## Every rule of the week as a line of text, team rule first
func rule_lines() -> PackedStringArray:
	var out := PackedStringArray([rule_text(team_rule())])
	for id in battle_rules():
		out.append(rule_text(id))
	return out

func rule_text(id: String) -> String:
	return Terms.t("challenge_rule_" + id, {"members": SMALL_TEAM})

## The tier's map: its chapter's boss, under the week's rules (a copy, named for the challenge)
func tier_stage(tier: int) -> StageData:
	var boss := DB.get_map(int(_draw().chapters[tier]), StageData.BOSS_NUMBER)
	if boss == null:
		return null
	var stage: StageData = boss.duplicate()
	stage.display_name = Terms.t("challenge_stage", {"tier": tier_name(tier), "name": boss.display_name})
	return stage

## The story boss map behind the tier (to check it's cleared, show its code...)
func tier_boss(tier: int) -> StageData:
	return DB.get_map(int(_draw().chapters[tier]), StageData.BOSS_NUMBER)

func tier_name(tier: int) -> String:
	return Terms.t("challenge_tier_" + String(TIERS[tier].key))

func tier_reward(tier: int) -> Array:
	return TIERS[tier].reward

func is_unlocked(tier: int) -> bool:
	var boss := tier_boss(tier)
	return boss != null and GameState.is_stage_cleared(boss.id)

func is_cleared(tier: int) -> bool:
	return _data().cleared.has(str(tier))

## Open at all once the first tier is
func is_open() -> bool:
	return is_unlocked(0)

## Tiers open and not yet won this week (the Home badge)
func waiting_count() -> int:
	var n := 0
	for i in TIERS.size():
		if is_unlocked(i) and not is_cleared(i):
			n += 1
	return n

func seconds_left() -> int:
	return Daily.seconds_to_weekly_reset()

# ───────── Team rule ─────────

## Why the current team can't take on the challenge, or "" if it can
func team_problem() -> String:
	if not GameState.has_team():
		return Terms.t("map_need_team")
	if GameState.is_team_over_cost():
		return Terms.t("team_over_cost", {"cost": GameState.team_cost(), "limit": GameState.team_cost_limit()})
	var rule := team_rule()
	var members := GameState.team_members()
	var bad := PackedStringArray()
	for uid in members:
		var c := GameState.get_character(uid)
		if c and _breaks(rule, c):
			bad.append(c.display_name)
	if rule == "small_team" and members.size() > SMALL_TEAM:
		return Terms.t("challenge_bad_small_team", {"members": SMALL_TEAM, "count": members.size()})
	if not bad.is_empty():
		return Terms.t("challenge_bad_" + rule, {"names": ", ".join(bad)})
	return ""

func _breaks(rule: String, c: CharacterData) -> bool:
	match rule:
		"no_healers":
			return c.char_class == CharacterData.CharClass.HEALER
		"no_tanks":
			return c.char_class == CharacterData.CharClass.TANK
		"max_sr":
			return c.rarity > CharacterData.Rarity.SR
		"r_only":
			return c.rarity > CharacterData.Rarity.R
	return false

# ───────── Battle rules ─────────

## The week's battle rules merged per side, for FormationBattleEngine: {"allies": {...}, "enemies": {...}}
func battle_side_rules() -> Dictionary:
	var out := {"allies": {}, "enemies": {}}
	for id in battle_rules():
		var rule: Dictionary = BATTLE_RULES[id]
		for side in ["allies", "enemies"]:
			var into: Dictionary = out[side]
			for key in rule.get(side, {}):
				var value = rule[side][key]
				if key == "stat_mult":
					var mults: Dictionary = into.get_or_add("stat_mult", {})
					for stat in value:
						mults[stat] = float(mults.get(stat, 1.0)) * float(value[stat])
				elif key == "heal_mult":
					into.heal_mult = float(into.get("heal_mult", 1.0)) * float(value)
				elif key == "wound":
					var wound: Dictionary = value.duplicate()
					wound.name = Terms.t("challenge_wound_name")
					into.wound = wound
				else:
					into[key] = float(into.get(key, 0.0)) + float(value)
	return out

# ───────── Rewards ─────────

## After a won challenge battle: the tier's reward the first time this week (granted), else []
func claim(tier: int) -> Array:
	var d := _data()
	if d.cleared.has(str(tier)):
		return []
	d.cleared[str(tier)] = true
	var reward: Array = tier_reward(tier)
	Daily.grant(reward)
	GameState.request_save()
	changed.emit()
	return reward

# ───────── Save data ─────────

## {"week": the week it's for, "cleared": {tier as string: true}}, reset when a new week starts
func _data() -> Dictionary:
	var d: Dictionary = GameState.data.get_or_add("challenge", {})
	if int(d.get("week", -1)) != Daily.this_week() or not d.has("cleared"):
		d.week = Daily.this_week()
		d.cleared = {}
	return d
