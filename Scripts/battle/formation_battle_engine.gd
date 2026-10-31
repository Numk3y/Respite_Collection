class_name FormationBattleEngine
extends BattleEngine
## Vanguard / rearguard combat with class-based attacks and speed-based turn order.
##
## Formation: Tanks and Warriors can only fight in the vanguard, Mages and Shooters only in the rearguard.
## Units placed in the wrong row are left out of the battle. Each row holds at most 3 units.
## Turn order: every unit fills an action gauge at a rate equal to its Speed. Whoever fills it first acts,
## so faster units act earlier AND more often (Speed 100 acts twice for every action of Speed 50).
## Only vanguard units have HP and can be targeted. A side loses the moment its whole vanguard is down.
## Attacks: Mages hit 2-3 enemies at reduced damage; Shooters hit one enemy very hard.

const GAUGE_FULL := 100.0
const MAX_ACTIONS := 300  # a stalemate past this counts as a loss
const ROW_SIZE := 3
const MIN_HIT_CHANCE := 0.10
const MAX_HIT_CHANCE := 0.98
const DAMAGE_VARIANCE := 0.15
const CLASS_DAMAGE_MULT := {  # a Mage's multiplier applies to each enemy it hits
	CharacterData.CharClass.TANK: 1.0,
	CharacterData.CharClass.WARRIOR: 1.0,
	CharacterData.CharClass.MAGE: 0.6,
	CharacterData.CharClass.SHOOTER: 1.4,
}
const MAGE_TARGETS := Vector2i(2, 3)

func simulate(allies: Dictionary, enemies: Dictionary, rng: RandomNumberGenerator, record: bool = false) -> Dictionary:
	var lines := PackedStringArray()
	var events: Array[Dictionary] = []
	var units: Array[Dictionary] = []
	_add_side(units, allies, 0)
	_add_side(units, enemies, 1)
	var snapshot := _snapshot(units) if record else []

	var win := false
	var actions := 0
	var end_key := "log_timeout"
	if not _vanguard_standing(units, 0):
		end_key = "log_lose"
	elif not _vanguard_standing(units, 1):
		win = true
		end_key = "log_win"
	else:
		while actions < MAX_ACTIONS:
			actions += 1
			var actor := _next_actor(units)
			var event := _take_turn(actor, units, rng, record)
			if record:
				events.append(event)
				lines.append_array(event.lines)
			if not _vanguard_standing(units, 1):
				win = true
				end_key = "log_win"
				break
			if not _vanguard_standing(units, 0):
				end_key = "log_lose"
				break

	var result := {"win": win, "actions": actions, "log": lines}
	if record:
		var end_lines := PackedStringArray([Terms.t(end_key)])
		lines.append_array(end_lines)
		result.log = lines
		result.units = snapshot
		result.events = events
		result.end_lines = end_lines
	return result

func _add_side(units: Array[Dictionary], fleet: Dictionary, side: int) -> void:
	for row in ["vanguard", "rearguard"]:
		var vanguard: bool = row == "vanguard"
		var placed := 0
		for u in fleet.get(row, []):
			var cls: int = u.get("cls", CharacterData.CharClass.WARRIOR)
			if CharacterData.is_vanguard_class(cls) != vanguard:
				push_warning("%s is a %s and can't fight in the %s; left out of the battle." % [
					u.name, CharacterData.CLASS_KEYS[cls], row])
				continue
			if placed >= ROW_SIZE:
				push_warning("%s: the %s is full; left out of the battle." % [u.name, row])
				continue
			placed += 1
			var s: Dictionary = u.stats
			units.append({
				"index": units.size(),
				"name": u.name,
				"side": side,
				"vanguard": vanguard,
				"cls": cls,
				"hp": int(s.hp),
				"max_hp": int(s.hp),
				"attack": float(s.attack),
				"defense": float(s.defense),
				"evasion": float(s.evasion),
				"accuracy": float(s.accuracy),
				"speed": maxf(float(s.speed), 1.0),
				"gauge": 0.0,
			})

func _snapshot(units: Array[Dictionary]) -> Array:
	return units.map(func(u): return {
		"name": u.name, "side": u.side, "vanguard": u.vanguard, "cls": u.cls, "max_hp": u.max_hp})

func _can_act(u: Dictionary) -> bool:
	return not u.vanguard or u.hp > 0

func _vanguard_standing(units: Array[Dictionary], side: int) -> bool:
	return units.any(func(u): return u.side == side and u.vanguard and u.hp > 0)

## Advance time until someone's gauge is full. Ties go to the faster unit, then to the allies.
func _next_actor(units: Array[Dictionary]) -> Dictionary:
	var actor: Dictionary = {}
	var best_time := INF
	for u in units:
		if not _can_act(u):
			continue
		var time_left: float = (GAUGE_FULL - u.gauge) / u.speed
		if time_left < best_time or (is_equal_approx(time_left, best_time) and u.speed > actor.speed):
			best_time = time_left
			actor = u
	for u in units:
		if _can_act(u):
			u.gauge += u.speed * best_time
	actor.gauge -= GAUGE_FULL
	return actor

func _take_turn(actor: Dictionary, units: Array[Dictionary], rng: RandomNumberGenerator, record: bool) -> Dictionary:
	var event := {"actor": actor.index, "hits": [], "lines": PackedStringArray()}
	var foes := units.filter(func(u): return u.side != actor.side and u.vanguard and u.hp > 0)
	var targets: Array = []
	if actor.cls == CharacterData.CharClass.MAGE:
		# Partial Fisher-Yates shuffle with our own rng, then take the first 2-3
		var count := mini(rng.randi_range(MAGE_TARGETS.x, MAGE_TARGETS.y), foes.size())
		for i in count:
			var j := rng.randi_range(i, foes.size() - 1)
			var tmp = foes[i]
			foes[i] = foes[j]
			foes[j] = tmp
		targets = foes.slice(0, count)
		if record:
			event.lines.append(Terms.t("log_aoe", {"attacker": actor.name}))
	else:
		targets = [foes[rng.randi_range(0, foes.size() - 1)]]

	for target in targets:
		event.hits.append(_attack(actor, target, rng, record, event.lines))
	return event

func _attack(actor: Dictionary, target: Dictionary, rng: RandomNumberGenerator, record: bool, lines: PackedStringArray) -> Dictionary:
	var total: float = actor.accuracy + target.evasion
	var hit_chance := MAX_HIT_CHANCE if total <= 0.0 else clampf(actor.accuracy / total, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	if rng.randf() >= hit_chance:
		if record:
			lines.append(Terms.t("log_miss", {"attacker": actor.name, "target": target.name}))
		return {"target": target.index, "hit": false, "damage": 0, "hp": target.hp}

	var damage: float = actor.attack * 100.0 / (100.0 + maxf(target.defense, 0.0))
	damage *= rng.randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE)
	damage *= CLASS_DAMAGE_MULT.get(actor.cls, 1.0)
	var dealt := maxi(roundi(damage), 1)
	target.hp = maxi(target.hp - dealt, 0)
	if record:
		lines.append(Terms.t("log_hit", {"attacker": actor.name, "target": target.name, "damage": dealt}))
		if target.hp == 0:
			lines.append(Terms.t("log_down", {"target": target.name}))
	return {"target": target.index, "hit": true, "damage": dealt, "hp": target.hp}
