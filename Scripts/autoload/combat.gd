extends Node
## Battles the player starts from the map screen, and their rewards. Autoload name: Combat

## Freddy, Bonnie, Chica and Foxy: on missions with 2+ waves they sometimes take over wave 2
const ANIMATRONIC_WAVE: WaveData = preload("res://Data/waves/animatronics.tres")
const ANIMATRONIC_WAVE_INDEX := 1

var engine: BattleEngine = FormationBattleEngine.new()
var force_animatronics := false  # test mode: the next sortie on a 2+ wave mission meets them for sure
var force_combo := false  # test mode: in the next sortie every combo roll succeeds (each combo still fires once)

var _rng := RandomNumberGenerator.new()
var _live_stage: StageData  # the map of the live battle in progress (see start_sortie)
var _live_animatronics := false
var _live_exp_mult := 1.0  # share of the usual friend and account EXP this battle pays (Auto Run: AUTO_RUN_EXP)
var _live_arena := false  # the live battle is an Arena fight (start_arena): Arena pays it, no map rewards

func _ready() -> void:
	_rng.randomize()

## Starts a live battle on a map for the Battle screen, played one action at a time with next_event() so the
## player can fire Ultimates by hand (`manual`). Returns the unit snapshot. Rewards come from finish_sortie().
func start_sortie(stage: StageData, manual: bool, exp_mult: float = 1.0) -> Array:
	_live_exp_mult = exp_mult
	_live_arena = false
	var enemies := stage.get_enemy_team()
	_live_animatronics = false
	if enemies.waves.size() > ANIMATRONIC_WAVE_INDEX and (force_animatronics or _rng.randf() < GameState.ANIMATRONIC_WAVE_CHANCE):
		force_animatronics = false
		_live_animatronics = true
		enemies.waves[ANIMATRONIC_WAVE_INDEX] = stage.wave_team(ANIMATRONIC_WAVE)
	_live_stage = stage
	var team := GameState.get_battle_team()
	if force_combo:
		force_combo = false
		team.force_combos = true
	return engine.begin(team, enemies, _rng, true, manual)

## Starts a live Arena fight against another player's team (Arena.enemy_team). Same flow as start_sortie:
## next_event() to play it, finish_sortie() at the end, which pays the Arena reward instead of map rewards.
func start_arena(enemy: Dictionary, manual: bool) -> Array:
	_live_exp_mult = 1.0
	_live_animatronics = false
	_live_stage = null
	_live_arena = true
	return engine.begin(GameState.get_battle_team(), {"waves": [enemy]}, _rng, true, manual)

## The live battle's next event, or {} once it's over
func next_event() -> Dictionary:
	return engine.step()

## Ends the live battle: grants the rewards and returns the engine result plus "report"
func finish_sortie() -> Dictionary:
	while not engine.is_done():
		engine.step()  # nothing should be left, but never hand out rewards for half a battle
	var result := engine.result()
	GameState.add_stat("manual_ultimates", int(result.get("manual_ultimates", 0)))  # beginner missions
	if _live_arena:
		_live_arena = false
		result.report = {"arena": true, "won": result.win, "money": Arena.grant(result.win), "materials": {}, "drops": [],
			"exp": 0, "level_ups": [], "first_clear_cards": 0, "card_drops": 0, "bond_ups": [], "daily_bonus": ""}
		GameState.add_stat("battles")
		if result.win:
			GameState.add_stat("wins")
		GameState.save_game()
		return result
	result.report = _grant_rewards(_live_stage, result)
	# Daily and weekly missions
	GameState.add_stat("battles")
	if result.win:
		GameState.add_stat("wins")
		if result.report.stars[1]:  # ★2 = nobody knocked out
			GameState.add_stat("flawless_wins")
	# Beating the animatronics pays out even if a later wave is lost
	if _live_animatronics and result.waves_cleared > ANIMATRONIC_WAVE_INDEX:
		result.report.card_drops = GameState.ANIMATRONIC_CREDIT_CARDS
		GameState.add_credit_cards(result.report.card_drops)
	GameState.save_game()
	return result

## Auto Run (Azur Lane style): on a map with all 3 stars, Main plays it up to AUTO_RUN_MAX times back to back with
## the current team and automatic Ultimates. Every run is a normal battle the player watches (no skipping) and pays
## the normal rewards, except friend and account EXP at AUTO_RUN_EXP; a lost run ends the series.
const AUTO_RUN_MAX := 3
const AUTO_RUN_EXP := 0.5

func can_auto_run(stage: StageData) -> bool:
	return GameState.star_count(stage.id) >= GameState.STAR_COUNT and GameState.can_battle() \
		and GameState.is_stage_unlocked(stage)

## A whole battle at once with automatic Ultimates (tools and tests). Rewards are granted.
func sortie(stage: StageData, exp_mult: float = 1.0) -> Dictionary:
	start_sortie(stage, false, exp_mult)
	return finish_sortie()

## One recorded world boss fight. The seed comes from the server with the attempt, so the same team and seed
## always play out the same way. The damage is HP removed from the boss fight's enemies; nothing else is granted.
## Returns the engine result plus "report": {"world_boss": true, "damage": int}.
func world_boss_fight(event: EventData, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var levels := 0
	var members := GameState.team_members()
	for uid in members:
		levels += int(GameState.get_owned(uid).level)
	var team_level := roundi(float(levels) / members.size()) if not members.is_empty() else 1
	var result := engine.simulate(GameState.get_battle_team(), event.boss_enemies(team_level), rng, true)
	var damage := 0
	for i in result.units.size():
		if result.units[i].side == 1:
			damage += int(result.stats[i].taken)
	result.report = {"world_boss": true, "damage": damage}
	if event.has_shop() and event.boss_currency > 0:
		EventShop.add_currency(event, event.boss_currency)
		result.report.event_currency = event.boss_currency
		result.report.event_currency_name = event.currency_name
		result.report.event_currency_color = event.currency_color
	return result

## Which piece a map drops: first a rarity (GameState.GEAR_DROP_WEIGHTS, between the rarities on the list), then
## an even pick among the list's pieces of that rarity
func _roll_drop(list: Array[EquipmentData]) -> EquipmentData:
	var by_rarity := {}
	for e in list:
		if e:
			by_rarity.get_or_add(e.rarity, []).append(e)
	var total := 0
	for rarity in by_rarity:
		total += int(GameState.GEAR_DROP_WEIGHTS.get(rarity, 1))
	if total <= 0:
		return null
	var roll := _rng.randi_range(1, total)
	for rarity in by_rarity:
		roll -= int(GameState.GEAR_DROP_WEIGHTS.get(rarity, 1))
		if roll <= 0:
			var pieces: Array = by_rarity[rarity]
			return pieces[_rng.randi_range(0, pieces.size() - 1)]
	return null

## EXP after this battle's share (Auto Run pays half); anything above 0 stays at least 1
func _scaled_exp(amount: int) -> int:
	return 0 if amount <= 0 else maxi(roundi(amount * _live_exp_mult), 1)

func _grant_rewards(stage: StageData, result: Dictionary) -> Dictionary:
	var won: bool = result.win
	var report := {
		"won": won, "money": 0, "materials": {}, "drops": [], "stage": stage.display_name,
		"exp": 0, "level_ups": [], "first_clear_cards": 0, "card_drops": 0,  # card_drops: from the animatronics
		"bond_ups": [],  # [{name, bond}] friends whose Bond level rose
		"account_exp": 0, "account_first_clear": false, "account_level_up": 0,  # account_level_up: the new account level, 0 if it didn't rise
		"stars": [false, false, false], "new_stars": [false, false, false], "star_cards": 0,  # see GameState.stars_for
		"daily_bonus": "",  # today's day-of-week bonus line (Daily) when it raised this battle's rewards
	}
	# Fighting together builds Bond, a little even in a loss (doubled on Bond day)
	var bond_gain := roundi((GameState.BOND_PER_WIN if won else GameState.BOND_PER_LOSS) * Daily.bonus("bond"))
	for uid in GameState.team_members():
		var bond := GameState.add_friendship(uid, bond_gain)
		if bond > 0:
			report.bond_ups.append({"name": GameState.get_character(uid).display_name, "bond": bond})
	if not won:
		return report

	report.daily_bonus = Daily.battle_bonus_line()
	# Event missions also drop the event's currency (spent in its shop)
	var event := DB.event_of(stage)
	if event and event.has_shop():
		report.event_currency = EventShop.roll_drop(event, stage, _rng)
		report.event_currency_name = event.currency_name
		report.event_currency_color = event.currency_color
		EventShop.add_currency(event, int(report.event_currency))
	report.money = roundi(stage.reward_money * Daily.bonus("money"))
	report.exp = _scaled_exp(roundi(stage.exp_reward * Daily.bonus("exp")))  # friend EXP only, never account EXP
	# Every friend in the team earns EXP, including any who were knocked out
	for uid in GameState.team_members():
		if GameState.add_exp(uid, report.exp) > 0:
			report.level_ups.append({"name": GameState.get_character(uid).display_name, "level": int(GameState.get_owned(uid).level)})
	# Account EXP (account levels raise the team cost limit): a big reward for the first win on a map,
	# then only a trickle for winning there again
	report.account_first_clear = not GameState.is_stage_cleared(stage.id)
	# Stars: ★2 and ★3 pay Credit Cards the first time (★1 is the first clear, paid below)
	report.stars = GameState.stars_for(stage, result)
	var bits := 0
	for i in GameState.STAR_COUNT:
		if report.stars[i]:
			bits |= 1 << i
	var new_bits := GameState.add_stars(stage.id, bits)
	for i in GameState.STAR_COUNT:
		report.new_stars[i] = (new_bits & (1 << i)) != 0
		if i > 0 and report.new_stars[i]:
			report.star_cards += GameState.STAR_CREDIT_CARDS
	if report.star_cards > 0:
		GameState.add_credit_cards(report.star_cards)
	report.account_exp = _scaled_exp(GameState.account_exp_for(stage.exp_reward, report.account_first_clear))
	if GameState.add_account_exp(report.account_exp) > 0:
		report.account_level_up = GameState.get_account_level()
	for key in stage.reward_materials:
		var range_v: Vector2i = stage.reward_materials[key]
		report.materials[key] = roundi(_rng.randi_range(range_v.x, range_v.y) * Daily.bonus("materials"))
	if not stage.equipment_drops.is_empty() and _rng.randf() < minf(stage.drop_chance * Daily.bonus("drops"), 1.0):
		var drop := _roll_drop(stage.equipment_drops)
		if drop:
			GameState.add_equipment(drop)
			report.drops.append(Terms.t("gear_drop_name", {"rarity": Terms.rarity_name(drop.rarity), "name": drop.display_name}))
			report.get_or_add("drop_gear", []).append(drop)  # the results screen shows the piece itself
	# Credit Cards: a bonus for the first win on each map (the animatronic wave's card is granted in finish_sortie)
	if GameState.mark_stage_cleared(stage.id):
		report.first_clear_cards = GameState.FIRST_CLEAR_CREDIT_CARDS
		GameState.add_credit_cards(report.first_clear_cards)
	GameState.add_money(report.money)
	for key in report.materials:
		GameState.add_material(key, report.materials[key])
	return report
