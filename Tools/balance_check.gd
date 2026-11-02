extends Node
## Balance check: measures friends against the benchmark team (Ami, Kai, Mika, Nana) to spot new characters that
## are too strong or too weak for their rarity. The four are reference units only: they're in no gacha pool and
## have no working skills ("Effect to be designed"), so they fight on plain stats. Don't give them skills, or every
## past comparison shifts.
##
## Run from the Respite_Collection folder (prints a report, then quits):
##   Godot_v4.7.2-stable_win64.exe --headless --path . res://Tools/balance_check.tscn -- perby
##   ... -- perby retinazer      several friends
##   ... -- all                  every friend outside the benchmark (the default)
##
## Two measurements, each also taken for the four benchmark friends so there's something to compare with:
## - Duel: 1-on-1 against each benchmark friend at DUEL_LEVEL, both sides of the field. Win rate, 50% = even.
##   Supports (pure healers, units that never attack) duel badly by design; judge them on Team.
## - Team: the friend takes a same-row slot in the benchmark team (Ami, Kai in front; Mika, Nana behind; each
##   same-row slot in turn) and the team plays every story map. Each map is played at the level where the plain
##   benchmark team wins about half the time (found first), because a map the team always wins or always loses
##   barely reacts to a change of member. Score per battle: 1 + share of HP left on a win (1-2), share of waves
##   cleared on a loss (0-1). Averaged over everything.
## The verdict compares Team (and Duel) with the benchmark friend(s) of the same rarity: R = Nana, SR = Kai,
## SSR = Ami and Mika. More than MARGIN above or below that reference is flagged.

const BENCHMARK: Array[StringName] = [&"ami", &"kai", &"mika", &"nana"]
const VANGUARD: Array[StringName] = [&"ami", &"kai"]
const REARGUARD: Array[StringName] = [&"mika", &"nana"]
const RARITY_REFERENCE := {
	CharacterData.Rarity.N: [&"nana"],  # N is retired; treat leftovers like R
	CharacterData.Rarity.R: [&"nana"],
	CharacterData.Rarity.SR: [&"kai"],
	CharacterData.Rarity.SSR: [&"ami", &"mika"],
}
const DUEL_LEVEL := 20
const DUEL_SIMS := 200  # per opponent per side
const TEAM_SIMS := 40  # per map per slot
const MARGIN := 0.12  # within ±12% of the rarity's reference counts as "in line"
const SEED := 20261102  # fixed, so re-running gives the same numbers
const CALIBRATE_SIMS := 30  # per level tried
const CALIBRATE_STEP := 2  # levels tried: 1, 3, 5, ...
const MAX_LEVEL := 90

var _engine := FormationBattleEngine.new()
var _rng := RandomNumberGenerator.new()
var _maps: Array[StageData] = []
var _levels := {}  # map -> friend level used for it (see _calibrate)

func _ready() -> void:
	_rng.seed = SEED
	for s in DB.stages:
		if s.is_story():
			_maps.append(s)
	for id in BENCHMARK:
		if not DB.characters.has(id):
			printerr("Benchmark friend missing: %s" % id)
			get_tree().quit(1)
			return

	var targets := _targets(OS.get_cmdline_user_args())
	if targets.is_empty():
		get_tree().quit(1)
		return

	_calibrate()
	print("\nBALANCE CHECK vs benchmark (Ami SSR Warrior, Kai SR Warrior, Mika SSR Shooter, Nana R Mage)")
	print("Duel: win rate 1-on-1 at Lv.%d.  Team: score on %d story maps (0-1 = lost, 1-2 = won with HP left)." % [DUEL_LEVEL, _maps.size()])
	var levels := PackedStringArray()
	for map in _maps:
		levels.append("%s Lv.%d" % [map.code(), _levels[map]])
	print("Team levels (plain benchmark wins ~50%%): %s\n" % ", ".join(levels))
	var refs := {}
	print("Reference (benchmark):")
	_print_header()
	for id in BENCHMARK:
		refs[id] = _measure(DB.characters[id])
		_print_row(DB.characters[id], refs[id], "")
	print("")
	print("Checked:")
	_print_header()
	for c in targets:
		var m := _measure(c)
		_print_row(c, m, _verdict(c, m, refs))
	print("")
	get_tree().quit()

func _targets(args: PackedStringArray) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	if args.is_empty() or args[0] == "all":
		var all: Array = DB.characters.values().filter(func(c): return c.enabled and not BENCHMARK.has(c.id))
		all.sort_custom(func(a, b): return a.rarity > b.rarity if a.rarity != b.rarity else a.display_name < b.display_name)
		out.assign(all)
		return out
	for arg in args:
		var c: CharacterData = DB.characters.get(StringName(arg))
		if c == null:
			printerr("No character with id '%s'. Ids are the file names in Data/characters/." % arg)
			return []
		out.append(c)
	return out

## {"duel": win rate 0-1, "team": average team score 0-2}
func _measure(c: CharacterData) -> Dictionary:
	var wins := 0
	var fights := 0
	for id in BENCHMARK:
		var other: CharacterData = DB.characters[id]
		for i in DUEL_SIMS * 2:
			var mine := _solo(c, DUEL_LEVEL)
			var theirs := _solo(other, DUEL_LEVEL)
			var as_ally := i % 2 == 0  # both sides of the field, in case it matters
			var r := _engine.simulate(mine if as_ally else theirs, theirs if as_ally else mine, _rng, false)
			wins += int(r.win == as_ally)
			fights += 1

	var total := 0.0
	var battles := 0
	var slots := VANGUARD if c.is_vanguard() else REARGUARD
	for map in _maps:
		var level: int = _levels[map]
		for slot in slots:
			for i in TEAM_SIMS:
				var r := _engine.simulate(_team(c, slot, level), map.get_enemy_team(), _rng, false)
				total += 1.0 + r.ally_hp if r.win else float(r.waves_cleared) / r.wave_count
				battles += 1
	return {"duel": float(wins) / fights, "team": total / battles}

## For each map, the friend level where the plain benchmark team's win rate is closest to 50%. Win rate rises
## with level, so the search stops once the team wins almost always.
func _calibrate() -> void:
	var plain: CharacterData = DB.characters[BENCHMARK[0]]  # "replacing Ami with Ami" = the plain team
	for map in _maps:
		var best_level := map.recommended_level
		var best_gap := 1.0
		for level in range(1, MAX_LEVEL + 1, CALIBRATE_STEP):
			var wins := 0
			for i in CALIBRATE_SIMS:
				wins += int(_engine.simulate(_team(plain, BENCHMARK[0], level), map.get_enemy_team(), _rng, false).win)
			var rate := float(wins) / CALIBRATE_SIMS
			if absf(rate - 0.5) < best_gap:
				best_gap = absf(rate - 0.5)
				best_level = level
			if rate >= 0.95:
				break
		_levels[map] = best_level

func _solo(c: CharacterData, level: int) -> Dictionary:
	var unit := c.battle_unit(c.stats_at(level))
	return {"vanguard": [unit], "rearguard": []} if c.is_vanguard() else {"vanguard": [], "rearguard": [unit]}

## The benchmark team with `c` in place of the benchmark friend `slot`
func _team(c: CharacterData, slot: StringName, level: int) -> Dictionary:
	var team := {"vanguard": [], "rearguard": []}
	for row in [["vanguard", VANGUARD], ["rearguard", REARGUARD]]:
		for id: StringName in row[1]:
			var member: CharacterData = c if id == slot else DB.characters[id]
			team[row[0]].append(member.battle_unit(member.stats_at(level)))
	return team

func _verdict(c: CharacterData, m: Dictionary, refs: Dictionary) -> String:
	var ref_ids: Array = RARITY_REFERENCE.get(c.rarity, [&"nana"])
	var ref_team := 0.0
	var ref_duel := 0.0
	for id in ref_ids:
		ref_team += refs[id].team / ref_ids.size()
		ref_duel += refs[id].duel / ref_ids.size()
	var team_ratio: float = m.team / ref_team
	var verdict := "in line"
	if team_ratio > 1.0 + MARGIN:
		verdict = "TOO STRONG"
	elif team_ratio < 1.0 - MARGIN:
		verdict = "TOO WEAK"
	var duel_note := ""
	if m.duel > ref_duel + 0.2:
		duel_note = ", duels far above"
	elif m.duel < ref_duel - 0.2:
		duel_note = ", duels far below"
	return "%s for %s (team %+d%% vs %s%s)" % [verdict, Terms.rarity_name(c.rarity), roundi((team_ratio - 1.0) * 100),
		" & ".join(ref_ids.map(func(id): return DB.characters[id].display_name)), duel_note]

func _print_header() -> void:
	print("  %-20s %-4s %-10s %6s %6s   %s" % ["Friend", "Rar", "Class", "Duel", "Team", "Verdict"])

func _print_row(c: CharacterData, m: Dictionary, verdict: String) -> void:
	print("  %-20s %-4s %-10s %5d%% %6.2f   %s" % [c.display_name.left(20), Terms.rarity_name(c.rarity),
		Terms.class_label(c.char_class), roundi(m.duel * 100), m.team, verdict])
