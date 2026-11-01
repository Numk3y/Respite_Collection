extends Node
## Battles the player starts from the map screen, and their rewards. Autoload name: Combat

var engine: BattleEngine = FormationBattleEngine.new()

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

## One recorded battle for the Battle screen. Rewards are granted immediately.
## Returns the engine result plus "report".
func sortie(stage: StageData) -> Dictionary:
	var result := engine.simulate(GameState.get_battle_team(), stage.get_enemy_team(), _rng, true)
	result.report = _grant_rewards(stage, result.win)
	GameState.save_game()
	return result

func _grant_rewards(stage: StageData, won: bool) -> Dictionary:
	var report := {
		"won": won, "money": 0, "materials": {}, "drops": [], "stage": stage.display_name,
		"exp": 0, "level_ups": [], "first_clear_cards": 0, "card_drops": 0,
	}
	if not won:
		return report

	report.money = stage.reward_money
	report.exp = stage.exp_reward
	# Every friend in the team earns EXP, including any who were knocked out
	for uid in GameState.team_members():
		if GameState.add_exp(uid, report.exp) > 0:
			report.level_ups.append({"name": GameState.get_character(uid).display_name, "level": int(GameState.get_owned(uid).level)})
	for key in stage.reward_materials:
		var range_v: Vector2i = stage.reward_materials[key]
		report.materials[key] = _rng.randi_range(range_v.x, range_v.y)
	if not stage.equipment_drops.is_empty() and _rng.randf() < stage.drop_chance:
		var drop: EquipmentData = stage.equipment_drops[_rng.randi_range(0, stage.equipment_drops.size() - 1)]
		GameState.add_equipment(drop)
		report.drops.append(drop.display_name)
	# Credit Cards: a bonus for the first win on each map, plus a 1% drop on every win
	if GameState.mark_stage_cleared(stage.id):
		report.first_clear_cards = GameState.FIRST_CLEAR_CREDIT_CARDS
	if _rng.randf() < GameState.CREDIT_CARD_DROP_CHANCE:
		report.card_drops = 1
	if report.first_clear_cards + report.card_drops > 0:
		GameState.add_credit_cards(report.first_clear_cards + report.card_drops)
	GameState.add_money(report.money)
	for key in report.materials:
		GameState.add_material(key, report.materials[key])
	return report
