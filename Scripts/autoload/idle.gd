extends Node
## Battles: manual sorties for the Battle screen, plus automatic patrols on the last map you sortied to
## (including offline progress). Autoload name: Idle

signal settled(report: Dictionary)

const BATTLE_SEC := 30  # one patrol battle every 30 seconds
const SIMULATE_CAP := 120  # beyond this many battles, the rest use the simulated win rate
const ESTIMATE_SAMPLES := 40

var engine: BattleEngine = FormationBattleEngine.new()
var offline_report: Dictionary = {}  # gains settled at launch, shown by the main screen

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	offline_report = settle()
	var t := Timer.new()
	t.wait_time = BATTLE_SEC
	t.autostart = true
	t.timeout.connect(settle)
	add_child(t)

## One recorded battle for the Battle screen. Rewards are granted immediately, and this map
## becomes the one the fleet patrols from now on. Returns the engine result plus "report".
func sortie(stage: StageData) -> Dictionary:
	settle()  # pay out the previous map's patrol first
	GameState.data.idle_stage_id = String(stage.id)
	var result := engine.simulate(GameState.get_battle_fleet(), stage.get_enemy_fleet(), _rng, true)
	result.report = _grant_rewards(stage, 1 if result.win else 0)
	GameState.save_game()
	return result

## Fight every patrol battle since the last settle in one go; returns {} if none were fought
func settle() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var last := int(GameState.data.last_tick)
	if now < last:  # the clock was turned back: no gains, just resync
		GameState.data.last_tick = now
		return {}
	var elapsed := now - last
	var battles := mini(elapsed, GameState.MAX_OFFLINE_SEC) / BATTLE_SEC
	if battles == 0:
		return {}
	# Within the cap, leftover seconds carry over; past the cap they're dropped
	GameState.data.last_tick = now if elapsed > GameState.MAX_OFFLINE_SEC else last + battles * BATTLE_SEC

	var stage := DB.get_stage(StringName(GameState.data.idle_stage_id))
	if stage == null or not GameState.has_vanguard():
		return {}
	var allies := GameState.get_battle_fleet()
	var enemies := stage.get_enemy_fleet()

	# Long offline stretches would mean thousands of battles, so simulate a sample
	# and apply its win rate to the rest
	var simulated := mini(battles, SIMULATE_CAP)
	var wins := 0
	for _i in simulated:
		if engine.simulate(allies, enemies, _rng).win:
			wins += 1
	if battles > simulated:
		wins += roundi((battles - simulated) * float(wins) / simulated)

	var report := _grant_rewards(stage, wins)
	report.battles = battles
	settled.emit(report)
	return report

func _grant_rewards(stage: StageData, wins: int) -> Dictionary:
	var report := {"wins": wins, "money": 0, "materials": {}, "drops": [], "stage": stage.display_name}
	for _i in wins:
		report.money += stage.reward_money
		for key in stage.reward_materials:
			var range_v: Vector2i = stage.reward_materials[key]
			report.materials[key] = report.materials.get(key, 0) + _rng.randi_range(range_v.x, range_v.y)
		if not stage.equipment_drops.is_empty() and _rng.randf() < stage.drop_chance:
			var drop: EquipmentData = stage.equipment_drops[_rng.randi_range(0, stage.equipment_drops.size() - 1)]
			GameState.add_equipment(drop)
			report.drops.append(drop.display_name)
	GameState.add_money(report.money)
	for key in report.materials:
		GameState.add_material(key, report.materials[key])
	return report

func estimate_win_rate(stage: StageData) -> float:
	if stage == null or not GameState.has_vanguard():
		return 0.0
	var allies := GameState.get_battle_fleet()
	var enemies := stage.get_enemy_fleet()
	var wins := 0
	for _i in ESTIMATE_SAMPLES:
		if engine.simulate(allies, enemies, _rng).win:
			wins += 1
	return float(wins) / ESTIMATE_SAMPLES
