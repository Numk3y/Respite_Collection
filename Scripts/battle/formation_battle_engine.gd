class_name FormationBattleEngine
extends BattleEngine
## Vanguard / rearguard combat with class-based attacks, speed-based turn order, Ultimates, passives and buffs.
##
## Formation: Tanks, Warriors and Berserkers can only fight in the vanguard, Mages, Shooters and Healers only in the
## rearguard.
## Units placed in the wrong row are left out of the battle. Each row holds at most 3 units.
## Turn order: every unit fills an action timer at a rate equal to its Speed. Whoever fills it first acts,
## so faster units act earlier AND more often (Speed 100 acts twice for every action of Speed 50).
## Targeting: everyone has HP. While any enemy vanguard unit stands, attacks go to the vanguard; once the whole
## vanguard is down they go to the rearguard. Exceptions are explicit: attacks that hit "all enemies" (e.g. Lucky
## Break) and buffs marked "back_row" (for future skills that lock onto the back row).
## A side loses when every one of its units is down.
## Attacks: Mages hit 2-3 enemies at reduced damage; Shooters hit one enemy very hard; Healers hit one enemy weakly.
##
## Ultimates: a unit with an Ultimate gains energy each time it acts and each time it's hit. When the gauge
## is full, its next action is the Ultimate instead of an attack, and the gauge resets.
## Passives (PASSIVE_EFFECTS): react to battle events, e.g. dropping low on HP or being knocked out.
## Buffs: {"id", "name", "mods": {stat: +/- fraction}, "taunt", "remaining", "counts": "actions" | "attacks",
## "kill_heal_pct", "all_enemies", "damage_mult", "back_row", "undying", "expire_kills", "sleep", "wake"}.
## One "turn" is one action by the buff's owner; the action that applies a buff doesn't count.
##
## Combat chain (all within the same action, so playback stays in sync):
## - Off-Balance: a vanguard unit's critical hit, or a hit dealing HEAVY_HIT_PCT of the target's max HP,
##   leaves a surviving target Off-Balance for the rest of that action.
## - Assist: each living rearguard ally of the attacker then rolls (fastest first) for a free follow-up strike on
##   that target at ASSIST_DAMAGE_MULT damage. Off-Balance targets can't dodge it. At most one assist per action.
## - Guard charge: when a Tank is hit hard (raw damage before Defense of GUARD_HEAVY_PCT of its max HP) or is
##   targeted while taunting, every living rearguard ally with an Ultimate gains GUARD_CHARGE_PCT of their gauge.

const TIMER_FULL := 100.0
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
	CharacterData.CharClass.BERSERKER: 1.15,
	CharacterData.CharClass.HEALER: 0.8,  # weak single-target hits; Healers earn their spot through their skills
}
const MAGE_TARGETS := Vector2i(2, 3)
const ENERGY_PER_ACTION := 25
const ENERGY_PER_HIT_TAKEN := 10
const CRIT_CHANCE := 0.10
const CRIT_MULT := 1.5
const HEAVY_HIT_PCT := 0.20  # a hit dealing this share of the target's max HP is heavy (causes Off-Balance)
const ASSIST_BASE_CHANCE := 0.30
const ASSIST_MAX_CHANCE := 0.50
const ASSIST_CHANCE_PER_SPEED := 0.004  # each point of Speed above 50 adds 0.4%, up to the max
const ASSIST_DAMAGE_MULT := 0.5
const GUARD_HEAVY_PCT := 0.20
const GUARD_CHARGE_PCT := 0.12
const MIN_DEFENSE := -50  # negative Defense means extra damage taken; -50 doubles it

## Ultimate effects a SkillData.effect_id can use, with their default params
const ULTIMATE_EFFECTS := {
	&"guardian": {"defense": 0.5, "turns": 3},  # +Defense and taunt for N own actions
	&"booze": {"heal_pct": 0.25, "accuracy": -0.2, "attacks": 2},  # heal % max HP, then -Accuracy for N attacks
	&"self_decaying": {"attack": 0.3, "defense": -0.5, "turns": 3, "kill_heal_pct": 0.2},  # +ATK/-DEF for N actions; kills heal
	# Sleeps through the next `sleep_turns` own actions (no attacking, still targetable), then wakes at full HP
	# with every debuff removed and +Attack for N actions
	&"power_nap": {"sleep_turns": 1, "attack": 0.6, "turns": 3},
	# Taunt and +Defense for N own actions; when it ends, a shockwave of `explode_pct` of max HP hits every enemy
	&"ccp": {"defense": 0.5, "turns": 2, "explode_pct": 0.3},
	# Chugs: +`stacks` Drunk (see passive Liquid Courage), heals `heal_pct` of max HP, then smashes a bottle
	# across every enemy for `damage_mult` damage
	&"bottoms_up": {"stacks": 2, "heal_pct": 0.15, "damage_mult": 0.8},
	# Stops attacking for N own actions: right away and on each of those actions, heals the first `targets` allies in
	# healing order (hurt vanguard first, lowest HP share first) for `heal_mult` x Attack. Those actions don't charge
	# the gauge.
	&"lets_go_winnie": {"heal_mult": 0.8, "targets": 2, "turns": 3},
	# Hits up to `targets` attackable enemies (ignores taunt) for `damage_mult` x Attack each, with `sleep_chance` to
	# put each survivor to sleep for `sleep_turns` of its actions (ignores Drowsiness's cooldown; asleep enemies
	# take Drowsiness's extra damage if the caster has it)
	&"disposing_to_sleep": {"damage_mult": 1.2, "targets": 3, "sleep_chance": 0.8, "sleep_turns": 1},
	# Every living ally: +`damage` damage dealt and +`speed` Speed for N of their own actions. While the caster's buff
	# lasts, bleeds it caused deal +`bleed_bonus` damage.
	&"morale_booster": {"damage": 0.2, "speed": 0.15, "turns": 3, "bleed_bonus": 0.75},
	# Hits every living enemy for `damage_mult` x Attack each (not reduced like a Mage's spread) and strips their
	# buffs (stat boosts, taunts, healing modes, damage boosts); debuffs, sleep and bleeds stay
	&"close_instance": {"damage_mult": 0.9},
	# Every living enemy: `attack`/`defense`/`speed` for its next N actions. The caster's own vanguard catches some
	# of it too: `ally_damage` damage dealt and `ally_defense` Defense for N of their actions.
	&"brain_rot": {"attack": -0.3, "defense": -0.25, "speed": -0.2, "turns": 2, "ally_damage": -0.1, "ally_defense": -0.1},
	# One enemy, picked like a normal single-target attack (vanguard first, taunt respected), for `damage_mult` x
	# Attack
	&"balloon_boy": {"damage_mult": 2.5},
}

## Passive effects a passive SkillData.effect_id can use, with their default params
const PASSIVE_EFFECTS := {
	# When a hit leaves this unit alive below `threshold` of max HP: heal up to `heal_to` and +Defense for N turns.
	# Afterwards it can't trigger again until the unit has taken `cooldown` actions (0 = no cooldown).
	&"second_wind": {"threshold": 0.2, "heal_to": 0.5, "defense": 0.2, "turns": 3, "cooldown": 0},
	# After casting Booze: `chance` that the next attack hits every enemy (both rows) for `damage_mult` damage
	&"lucky_break": {"chance": 0.5, "damage_mult": 0.7},
	# Once per battle, a lethal hit leaves this unit at 1 HP; it can't drop lower or be healed, and after
	# N of its own actions it collapses
	&"undying": {"turns": 2},
	# Takes `damage_reduction` less damage from every hit. Each single-target attack has `cleave_chance` to also
	# strike every other enemy in the target's row for `cleave_mult` damage.
	&"unfazed": {"damage_reduction": 0.1, "cleave_chance": 0.33, "cleave_mult": 0.5},
	# Each attack adds a stack of +`attack` for the next N own actions (stacks overlap). Every own action, the unit
	# also loses `drain_pct` of its max HP; this can knock it out.
	&"cancer": {"attack": 0.05, "turns": 3, "drain_pct": 0.05},
	# Each hit that lands has `chance` to Blind a surviving target: `accuracy` for its next N actions
	&"blinding": {"chance": 0.1, "accuracy": -0.5, "turns": 2},
	# Surviving a hit has `chance` to give the attacker -Attack/-Defense for N of its actions, and this unit
	# +`speed` for `speed_turns` of its own actions
	&"its_raw": {"chance": 0.4, "attack": -0.25, "defense": -0.25, "turns": 2, "speed": 0.15, "speed_turns": 1},
	# +Attack/+Speed for every 1% of max HP lost (always on). When a hit leaves it below `threshold`: Berserk
	# (+`attack`, `defense`) for N own actions, then it can't trigger again for `cooldown` own actions.
	&"desperate_scramble": {"attack_per_pct": 0.015, "speed_per_pct": 0.01, "threshold": 0.3,
		"attack": 0.4, "defense": -0.2, "turns": 3, "cooldown": 10},
	# Never attacks. Whenever it takes damage from an enemy, a random living rearguard ally instantly strikes that
	# enemy for `attack_mult` x its own Attack (can't miss, reduced by Defense; counters never chain)
	&"one_above_all": {"attack_mult": 1.0},
	# Drunk stacks (up to `max_stacks`): each gives +Attack, +Defense and -Accuracy. A swig every `swig_every`
	# own actions adds one. Once per battle, a hit leaving it below `rally_threshold` HP: heals `rally_heal` of max
	# HP and adds `rally_stacks`.
	&"liquid_courage": {"attack_per_stack": 0.1, "defense_per_stack": 0.05, "accuracy_per_stack": -0.06,
		"max_stacks": 5, "swig_every": 3, "rally_threshold": 0.4, "rally_heal": 0.2, "rally_stacks": 2},
	# After each own attack, a pet heals the first ally in healing order (hurt vanguard first, lowest HP share first)
	# for `heal_mult` x this unit's Attack
	&"winnie": {"heal_mult": 0.55},
	# Never attacks. Each own action heals the first ally in healing order (hurt vanguard first, lowest HP share
	# first) for `heal_mult` x Attack.
	&"sus_green_plants": {"heal_mult": 0.7},
	# Each hit that lands has `chance` to put a surviving enemy to sleep: it skips its next `turns` actions and takes
	# `damage_taken` more damage while asleep. After waking, Drowsiness can't put it to sleep again for `cooldown` of
	# its actions. Every own action (not asleep) also has `self_chance` to doze off and skip the next one.
	&"drowsiness": {"chance": 0.15, "turns": 1, "cooldown": 3, "damage_taken": 0.2, "self_chance": 0.05},
	# Each hit of its own attacks heals it for `lifesteal` of the damage dealt
	&"power_of_baldness": {"lifesteal": 0.3},
	# Each hit that lands makes a surviving enemy bleed: it loses `bleed_pct` x this unit's Attack (at the time of the
	# hit, ignoring Defense) at the end of each of its next N actions; a new hit refreshes it. This unit gets
	# +`attack_per_bleed` Attack for every bleeding enemy.
	&"bow_wow": {"bleed_pct": 0.2, "turns": 3, "attack_per_bleed": 0.05},
	# +`defense_per_ally` Defense for every other living ally on its side (kill the crowd to break it). Every
	# `kick_every` own actions, kicks the enemy with the highest Attack: it skips its next `kick_turns` actions.
	&"group_owner": {"defense_per_ally": 0.15, "kick_every": 3, "kick_turns": 1},
	# While this unit is alive, every vanguard ally heals `regen_pct` x this unit's Attack at the end of each of
	# its own actions
	&"chilling": {"regen_pct": 0.1},
	# Each hit that lands has `chance` to steal `steal_pct` of the target's Attack: the target loses it for its next
	# N actions and this unit gains that much Attack for its own next N actions
	&"db_grub": {"chance": 0.5, "steal_pct": 0.3, "turns": 1},
}

var _acting_index := -1  # whose action is being resolved right now
var _units: Array[Dictionary] = []  # everyone in the current battle, for effects that reach past the action
var _countering := false  # a counterattack is resolving; counters never chain into more counters

## `enemies` is either one team or {"waves": [team, ...]}. Waves are fought back to back (FGO-style): the
## allies keep their HP, energy and buffs, fallen allies stay down, and every wave starts with fresh turn order.
## The battle is won when the last wave is cleared and lost when every ally is down.
func simulate(allies: Dictionary, enemies: Dictionary, rng: RandomNumberGenerator, record: bool = false) -> Dictionary:
	_acting_index = -1
	_countering = false
	var waves: Array = enemies.get("waves", [enemies])
	var lines := PackedStringArray()
	var events: Array[Dictionary] = []
	var units: Array[Dictionary] = []
	_units = units
	_add_side(units, allies, 0, -1)
	for w in waves.size():
		_add_side(units, waves[w], 1, w)
	var snapshot := _snapshot(units) if record else []

	var win := false
	var actions := 0
	var wave_actions := 0
	var wave := 0
	var end_key := "log_timeout"
	while true:
		if not _side_standing(units, 0):
			end_key = "log_lose"
			break
		if not _side_standing(units, 1):
			if wave + 1 >= waves.size():
				win = true
				end_key = "log_win"
				break
			wave += 1
			wave_actions = 0
			_start_wave(units, wave)
			if record:
				var wave_event := {"actor": -1, "kind": "wave", "wave": wave, "wave_count": waves.size(),
					"boss": waves[wave].get("boss", false), "hits": [], "heals": [], "off_balance": [], "assists": [],
					"guard_charges": [], "lines": PackedStringArray([Terms.t("log_wave", {"current": wave + 1, "total": waves.size()})]),
					"state": _state(units)}
				events.append(wave_event)
				lines.append_array(wave_event.lines)
			continue
		if wave_actions >= MAX_ACTIONS:
			break  # stalemate: counts as a loss
		actions += 1
		wave_actions += 1
		var event := _take_turn(_next_actor(units), units, rng, record)
		if record:
			events.append(event)
			lines.append_array(event.lines)

	var result := {"win": win, "actions": actions, "log": lines, "waves_cleared": wave + (1 if win else 0), "wave_count": waves.size()}
	if record:
		var end_lines := PackedStringArray([Terms.t(end_key)])
		lines.append_array(end_lines)
		result.log = lines
		result.units = snapshot
		result.events = events
		result.end_lines = end_lines
	return result

## Brings in the enemies of `wave` and gives everyone a fresh start on turn order
func _start_wave(units: Array[Dictionary], wave: int) -> void:
	for u in units:
		if u.side == 1:
			u.active = u.wave == wave
		u.timer = 0.0

## wave = -1 for allies (always present); enemies only take part while their wave is active
func _add_side(units: Array[Dictionary], team: Dictionary, side: int, wave: int) -> void:
	for row in ["vanguard", "rearguard"]:
		var vanguard: bool = row == "vanguard"
		var placed := 0
		for u in team.get(row, []):
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
			var ultimate: Dictionary = u.get("ultimate", {})
			if not ultimate.is_empty() and not ULTIMATE_EFFECTS.has(ultimate.effect):
				push_warning("%s: unknown Ultimate effect '%s'; it won't fire." % [u.name, ultimate.effect])
				ultimate = {}
			var passive: Dictionary = u.get("passive", {})
			if not passive.is_empty() and not PASSIVE_EFFECTS.has(passive.effect):
				push_warning("%s: unknown passive effect '%s'; it won't trigger." % [u.name, passive.effect])
				passive = {}
			units.append({
				"index": units.size(),
				"name": u.name,
				"side": side,
				"wave": wave,
				"active": wave <= 0,
				"vanguard": vanguard,
				"cls": cls,
				"hp": int(s.hp),
				"max_hp": int(s.hp),
				"base": {"attack": float(s.attack), "defense": float(s.defense), "evasion": float(s.evasion),
					"accuracy": float(s.accuracy), "speed": maxf(float(s.speed), 1.0)},
				"timer": 0.0,
				"energy": 0,
				"energy_max": maxi(int(u.get("energy_max", 100)), 1),
				"ultimate": ultimate,
				"passive": passive,
				"passive_used": 0,
				"passive_cooldown": 0,  # own actions left before the passive can trigger again
				"buffs": [],
				"data": u.get("data"),
			})

func _snapshot(units: Array[Dictionary]) -> Array:
	return units.map(func(u): return {
		"name": u.name, "side": u.side, "wave": u.wave, "vanguard": u.vanguard, "cls": u.cls, "max_hp": u.max_hp,
		"energy_max": u.energy_max, "has_ultimate": not u.ultimate.is_empty(), "data": u.data})

func _state(units: Array[Dictionary]) -> Array:
	return units.map(func(u): return {"hp": u.hp, "energy": u.energy, "buffs": _buff_names(u)})

## Buff names for display; stacks of the same buff (e.g. Cancer) show once as "Cancer x3"
func _buff_names(u: Dictionary) -> PackedStringArray:
	var counts := {}
	for b in u.buffs:
		counts[b.name] = counts.get(b.name, 0) + 1
	var names := PackedStringArray()
	for buff_name: String in counts:
		names.append(buff_name if counts[buff_name] == 1 else "%s x%d" % [buff_name, counts[buff_name]])
	if int(u.get("drunk", 0)) > 0:
		names.append(Terms.t("buff_drunk", {"stacks": u.drunk}))
	return names

func _alive(u: Dictionary) -> bool:
	return u.active and u.hp > 0  # enemies of later waves aren't on the field yet

func _side_standing(units: Array[Dictionary], side: int) -> bool:
	return units.any(func(u): return u.side == side and _alive(u))

## Who normal attacks against `side` can hit: its living vanguard, or its living rearguard once the vanguard is down.
## back_row = true aims at the living rearguard first (for skills that lock onto the back row).
func _targetable(units: Array[Dictionary], side: int, back_row: bool = false) -> Array:
	var alive := units.filter(func(u): return u.side == side and _alive(u))
	var front := alive.filter(func(u): return u.vanguard)
	var back := alive.filter(func(u): return not u.vanguard)
	if back_row and not back.is_empty():
		return back
	return front if not front.is_empty() else back

## A stat with buffs applied, e.g. Defense +50% -> base * 1.5. Buffs move a negative stat up and debuffs push
## it further down (Defense -15 with +50% -> -7.5), so they always mean the same thing.
func _stat(u: Dictionary, stat: String) -> float:
	var mult := 1.0 + _scramble_bonus(u, stat) + _drunk_bonus(u, stat) + _bow_wow_bonus(u, stat) + _group_bonus(u, stat)
	for b in u.buffs:
		mult += b.get("mods", {}).get(stat, 0.0)
	var base: float = u.base[stat]
	var floor_value := 1.0 if stat == "speed" else (float(MIN_DEFENSE) if stat == "defense" else 0.0)
	return maxf(base + absf(base) * (mult - 1.0), floor_value)

## Passive Liquid Courage: each Drunk stack shifts Attack, Defense and Accuracy
func _drunk_bonus(u: Dictionary, stat: String) -> float:
	var stacks: int = u.get("drunk", 0)
	if stacks <= 0 or not stat in ["attack", "defense", "accuracy"]:
		return 0.0
	var p := _passive_params(u, &"liquid_courage")
	return 0.0 if p.is_empty() else stacks * float(p[stat + "_per_stack"])

## Adds Drunk stacks (capped) for a Liquid Courage unit
func _add_drunk(u: Dictionary, amount: int, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"liquid_courage")
	if p.is_empty():
		return
	u.drunk = mini(int(u.get("drunk", 0)) + amount, int(p.max_stacks))
	event.get_or_add("drunk", []).append(u.index)
	if record:
		event.lines.append(Terms.t("log_drunk", {"name": u.name, "stacks": u.drunk}))

## Passive Liquid Courage: a swig every few own actions
func _check_swig(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"liquid_courage")
	if p.is_empty() or u.hp <= 0:
		return
	u.swigs = int(u.get("swigs", 0)) + 1
	if u.swigs % int(p.swig_every) == 0:
		if record:
			event.lines.append(Terms.t("log_swig", {"name": u.name}))
		_add_drunk(u, 1, event, record)

## Passive Liquid Courage: once per battle, dropping low makes it order a double
func _check_rally(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"liquid_courage")
	if p.is_empty() or u.passive_used > 0 or u.hp >= u.max_hp * float(p.rally_threshold):
		return
	u.passive_used = 1
	if record:
		event.lines.append(Terms.t("log_rally", {"name": u.name, "skill": u.passive.name}))
	_heal(u, roundi(u.max_hp * float(p.rally_heal)), event, record)
	_add_drunk(u, int(p.rally_stacks), event, record)

## Passive Chilling: a vanguard unit regenerates at the end of its own action, once per living Chilling ally
func _chill_regen(u: Dictionary, event: Dictionary, record: bool) -> void:
	if not u.vanguard or u.hp <= 0 or u.hp >= u.max_hp:
		return
	for ally in _units.filter(func(a): return a.side == u.side and _alive(a)):
		var p := _passive_params(ally, &"chilling")
		if not p.is_empty():
			_heal(u, maxi(roundi(_stat(ally, "attack") * float(p.regen_pct)), 1), event, record)

## Passive Group Owner: +Defense for every other living ally
func _group_bonus(u: Dictionary, stat: String) -> float:
	if stat != "defense" or u.passive.is_empty() or u.passive.effect != &"group_owner":
		return 0.0
	var crowd := _units.filter(func(a): return a.side == u.side and a.index != u.index and _alive(a))
	return crowd.size() * float(_passive_params(u, &"group_owner").defense_per_ally)

## Passive Group Owner: every few own actions, vote-kick the enemy with the highest Attack
func _check_kick_vote(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"group_owner")
	if p.is_empty() or u.hp <= 0:
		return
	u.kick_count = int(u.get("kick_count", 0)) + 1
	if u.kick_count % int(p.kick_every) != 0:
		return
	var foes := _units.filter(func(t): return t.side != u.side and _alive(t) and not _has_flag(t, "sleep"))
	if foes.is_empty():
		return
	foes.sort_custom(func(a, b): return _stat(a, "attack") > _stat(b, "attack"))
	if record:
		event.lines.append(Terms.t("log_kick_vote", {"name": u.name, "target": foes[0].name, "skill": u.passive.name}))
	_put_to_sleep(u, foes[0], int(p.kick_turns), false, event, record, Terms.t("buff_kicked"), "log_kicked", "log_rejoined")

## Passive Bow Wow: +Attack for every bleeding enemy
func _bow_wow_bonus(u: Dictionary, stat: String) -> float:
	if stat != "attack" or u.passive.is_empty() or u.passive.effect != &"bow_wow":
		return 0.0
	var bleeding := _units.filter(func(t): return t.side != u.side and _alive(t) and _has_flag(t, "bleed"))
	return bleeding.size() * float(_passive_params(u, &"bow_wow").attack_per_bleed)

## Bleeds lose HP at the end of each of the bleeder's own actions (ignoring Defense; this can knock it out).
## Morale Booster on whoever caused the bleed makes it hurt more.
func _bleed_tick(u: Dictionary, event: Dictionary, record: bool) -> void:
	for b in u.buffs:
		if not b.get("bleed", false) or u.hp <= 0:
			continue
		var source: Dictionary = _units[b.source]
		var amount := maxi(roundi(b.amount * (1.0 + float(_flag_buff(source, "bleed_bonus").get("bleed_bonus", 0.0)))), 1)
		u.hp = maxi(u.hp - amount, 1 if _has_flag(u, "undying") else 0)
		event.drains.append({"target": u.index, "amount": amount, "bleed": true})
		if record:
			event.lines.append(Terms.t("log_bleed", {"name": u.name, "amount": amount}))
			if u.hp <= 0:
				event.lines.append(Terms.t("log_down", {"target": u.name}))

## Passive Desperate Scramble: +Attack/+Speed for every 1% of max HP lost
func _scramble_bonus(u: Dictionary, stat: String) -> float:
	if u.passive.is_empty() or u.passive.effect != &"desperate_scramble" or not stat in ["attack", "speed"]:
		return 0.0
	var p := _passive_params(u, &"desperate_scramble")
	var lost_pct: float = (1.0 - float(u.hp) / u.max_hp) * 100.0
	return lost_pct * float(p.attack_per_pct if stat == "attack" else p.speed_per_pct)

func _has_flag(u: Dictionary, flag: String) -> bool:
	return u.buffs.any(func(b): return b.get(flag, false))

func _flag_buff(u: Dictionary, flag: String) -> Dictionary:
	for b in u.buffs:
		if b.get(flag, false):
			return b
	return {}

## Advance time until someone's timer is full. Ties go to the faster unit, then to the allies.
func _next_actor(units: Array[Dictionary]) -> Dictionary:
	var actor: Dictionary = {}
	var best_time := INF
	var best_speed := 0.0
	for u in units:
		if not _alive(u):
			continue
		var speed := _stat(u, "speed")
		var time_left: float = (TIMER_FULL - u.timer) / speed
		if time_left < best_time or (is_equal_approx(time_left, best_time) and speed > best_speed):
			best_time = time_left
			best_speed = speed
			actor = u
	for u in units:
		if _alive(u):
			u.timer += _stat(u, "speed") * best_time
	actor.timer -= TIMER_FULL
	return actor

func _take_turn(actor: Dictionary, units: Array[Dictionary], rng: RandomNumberGenerator, record: bool) -> Dictionary:
	_acting_index = actor.index
	var event := {"actor": actor.index, "kind": "attack", "skill": "", "hits": [], "heals": [],
		"off_balance": [], "assists": [], "guard_charges": [], "drains": [], "lines": PackedStringArray()}
	var sleep := _flag_buff(actor, "sleep")
	if not sleep.is_empty():
		# e.g. Power Nap: the whole action is spent asleep (no attack, no energy), waking on the last one
		event.kind = "sleep"
		if record:
			event.lines.append(Terms.t("log_sleeping", {"name": actor.name}))
		sleep.remaining -= 1
		if sleep.remaining <= 0:
			actor.buffs.erase(sleep)
			if sleep.has("wake"):
				_wake(actor, sleep.wake, event, record)
			else:
				# e.g. put to sleep by Drowsiness: just wakes up, then can't be put to sleep again for a while
				actor.sleep_immune = int(sleep.get("immune_after", 0))
				if record:
					event.lines.append(Terms.t(sleep.get("wake_log", "log_wake_plain"), {"name": actor.name}))
	elif not actor.ultimate.is_empty() and actor.energy >= actor.energy_max:
		event.kind = "ultimate"
		event.skill = actor.ultimate.name
		_cast_ultimate(actor, rng, event, record)
		actor.energy = 0
	elif _has_flag(actor, "healing"):
		# e.g. Let's Go Winnie: the turn goes to patching up allies instead of attacking
		event.kind = "heal"
		var healing := _flag_buff(actor, "healing")
		if record:
			event.lines.append(Terms.t("log_heal_turn", {"name": actor.name, "skill": healing.name}))
		_heal_lowest(actor, int(healing.heal_targets), roundi(_stat(actor, "attack") * float(healing.heal_mult)), event, record)
	elif not _passive_params(actor, &"sus_green_plants").is_empty():
		# e.g. CoconutBird never attacks; every turn goes to healing whoever is worst off
		event.kind = "heal"
		if record:
			event.lines.append(Terms.t("log_sus_plants", {"name": actor.name, "skill": actor.passive.name}))
		var plants := _passive_params(actor, &"sus_green_plants")
		_heal_lowest(actor, 1, roundi(_stat(actor, "attack") * float(plants.heal_mult)), event, record)
		_gain_energy(actor, ENERGY_PER_ACTION)
	elif not _passive_params(actor, &"one_above_all").is_empty():
		# e.g. Xi never attacks himself; the turn still charges his Ultimate
		event.kind = "idle"
		if record:
			event.lines.append(Terms.t("log_idle", {"name": actor.name}))
		_gain_energy(actor, ENERGY_PER_ACTION)
	else:
		_basic_attack(actor, units, rng, record, event)
		_check_winnie(actor, event, record)
		_tick_buffs(actor, "attacks", event, record, rng)
		_gain_energy(actor, ENERGY_PER_ACTION)
		_add_cancer_stack(actor)
	_bleed_tick(actor, event, record)
	_chill_regen(actor, event, record)
	_tick_buffs(actor, "actions", event, record, rng)
	_cancer_drain(actor, event, record)
	_check_swig(actor, event, record)
	if event.kind != "sleep":
		if int(actor.get("sleep_immune", 0)) > 0:
			actor.sleep_immune -= 1
		_check_nod_off(actor, rng, event, record)
		_check_kick_vote(actor, event, record)
	for b in actor.buffs:
		b.fresh = false
	if actor.passive_cooldown > 0:
		actor.passive_cooldown -= 1
	if record:
		event.state = _state(units)
	return event

func _gain_energy(u: Dictionary, amount: int) -> void:
	if not u.ultimate.is_empty() and u.hp > 0:
		u.energy = mini(u.energy + amount, u.energy_max)

# ───────── Ultimates, passives & buffs ─────────

func _cast_ultimate(actor: Dictionary, rng: RandomNumberGenerator, event: Dictionary, record: bool) -> void:
	var effect: StringName = actor.ultimate.effect
	var p: Dictionary = ULTIMATE_EFFECTS[effect].merged(actor.ultimate.params, true)
	var skill_name: String = actor.ultimate.name
	if record:
		event.lines.append(Terms.t("log_ultimate", {"attacker": actor.name, "skill": skill_name}))
	match effect:
		&"guardian":
			_add_buff(actor, {"id": &"guardian", "name": skill_name, "mods": {"defense": float(p.defense)},
				"taunt": true, "remaining": int(p.turns), "counts": "actions"})
		&"booze":
			_heal(actor, roundi(actor.max_hp * float(p.heal_pct)), event, record)
			_add_buff(actor, {"id": &"hangover", "name": Terms.t("buff_hangover"), "mods": {"accuracy": float(p.accuracy)},
				"remaining": int(p.attacks), "counts": "attacks"})
			# Passive Lucky Break: a chance that the next attack hits every enemy
			var lucky := _passive_params(actor, &"lucky_break")
			if not lucky.is_empty() and rng.randf() < float(lucky.chance):
				_add_buff(actor, {"id": &"lucky_break", "name": actor.passive.name, "all_enemies": true,
					"damage_mult": float(lucky.damage_mult), "remaining": 1, "counts": "attacks"})
				if record:
					event.lines.append(Terms.t("log_lucky_break", {"name": actor.name, "skill": actor.passive.name}))
		&"self_decaying":
			_add_buff(actor, {"id": &"self_decaying", "name": skill_name,
				"mods": {"attack": float(p.attack), "defense": float(p.defense)},
				"remaining": int(p.turns), "counts": "actions", "kill_heal_pct": float(p.kill_heal_pct)})
		&"power_nap":
			# Counted by _take_turn itself ("sleep" never matches _tick_buffs), so the nap lasts exactly sleep_turns
			_add_buff(actor, {"id": &"asleep", "name": Terms.t("buff_asleep"), "sleep": true,
				"remaining": int(p.sleep_turns), "counts": "sleep",
				"wake": {"name": skill_name, "attack": float(p.attack), "turns": int(p.turns)}})
			if record:
				event.lines.append(Terms.t("log_fall_asleep", {"name": actor.name}))
		&"bottoms_up":
			_add_drunk(actor, int(p.stacks), event, record)
			_heal(actor, roundi(actor.max_hp * float(p.heal_pct)), event, record)
			if record:
				event.lines.append(Terms.t("log_all_enemies", {"attacker": actor.name}))
			for target in _units.filter(func(t): return t.side != actor.side and _alive(t)):
				event.hits.append(_attack(actor, target, rng, record, event, float(p.damage_mult)))
		&"ccp":
			# Taunt and harden; when it runs out, _tick_buffs sets off the shockwave
			_add_buff(actor, {"id": &"ccp", "name": skill_name, "mods": {"defense": float(p.defense)}, "taunt": true,
				"remaining": int(p.turns), "counts": "actions", "explode_pct": float(p.explode_pct)})
		&"lets_go_winnie":
			# Heals now; _take_turn spends the next N actions healing while the buff lasts
			_heal_lowest(actor, int(p.targets), roundi(_stat(actor, "attack") * float(p.heal_mult)), event, record)
			_add_buff(actor, {"id": &"lets_go_winnie", "name": skill_name, "healing": true, "remaining": int(p.turns),
				"counts": "actions", "heal_mult": float(p.heal_mult), "heal_targets": int(p.targets)})
		&"morale_booster":
			for ally in _units.filter(func(a): return a.side == actor.side and _alive(a)):
				var buff := {"id": &"morale_booster", "name": skill_name, "mods": {"speed": float(p.speed)},
					"damage_bonus": float(p.damage), "remaining": int(p.turns), "counts": "actions"}
				if ally.index == actor.index:
					buff.bleed_bonus = float(p.bleed_bonus)
				_add_buff(ally, buff)
		&"balloon_boy":
			var foes := _targetable(_units, 1 - actor.side)
			if not foes.is_empty():
				var taunting := foes.filter(func(t): return _has_flag(t, "taunt"))
				var pool := taunting if not taunting.is_empty() else foes
				if record:
					event.lines.append(Terms.t("log_balloon_boy", {"name": actor.name}))
				var target: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
				event.hits.append(_attack(actor, target, rng, record, event, float(p.damage_mult) / float(CLASS_DAMAGE_MULT.get(actor.cls, 1.0))))
		&"brain_rot":
			if record:
				event.lines.append(Terms.t("log_brain_rot", {"name": actor.name}))
			for target in _units.filter(func(t): return t.side != actor.side and _alive(t)):
				_add_buff(target, {"id": &"brain_rot", "name": Terms.t("buff_brain_rot"), "remaining": int(p.turns),
					"counts": "actions", "mods": {"attack": float(p.attack), "defense": float(p.defense), "speed": float(p.speed)}})
				event.get_or_add("decayed", []).append(target.index)
			for ally in _units.filter(func(a): return a.side == actor.side and a.vanguard and _alive(a)):
				_add_buff(ally, {"id": &"brain_rot_cringe", "name": Terms.t("buff_cringe"), "remaining": int(p.turns),
					"counts": "actions", "mods": {"defense": float(p.ally_defense)}, "damage_bonus": float(p.ally_damage)})
				event.get_or_add("cringed", []).append(ally.index)
			if record:
				event.lines.append(Terms.t("log_brain_rot_cringe", {"name": actor.name}))
		&"close_instance":
			if record:
				event.lines.append(Terms.t("log_close_instance", {"name": actor.name}))
			var mult_all := float(p.damage_mult) / float(CLASS_DAMAGE_MULT.get(actor.cls, 1.0))
			for target in _units.filter(func(t): return t.side != actor.side and _alive(t)):
				event.hits.append(_attack(actor, target, rng, record, event, mult_all))
				var kept: Array = target.buffs.filter(func(b): return not _is_boon(b))
				if kept.size() < target.buffs.size() and target.hp > 0:
					target.buffs = kept
					if record:
						event.lines.append(Terms.t("log_buffs_stripped", {"target": target.name}))
		&"disposing_to_sleep":
			# Like a Mage's attack (ignores taunt), but damage_mult is a share of Attack, not of the Mage's usual hit
			var foes := _targetable(_units, 1 - actor.side)
			for i in foes.size():
				var j := rng.randi_range(i, foes.size() - 1)
				var tmp = foes[i]
				foes[i] = foes[j]
				foes[j] = tmp
			if record:
				event.lines.append(Terms.t("log_aoe", {"attacker": actor.name}))
			var mult := float(p.damage_mult) / float(CLASS_DAMAGE_MULT.get(actor.cls, 1.0))
			for target in foes.slice(0, int(p.targets)):
				var hit := _attack(actor, target, rng, record, event, mult)
				event.hits.append(hit)
				if hit.hit and rng.randf() < float(p.sleep_chance):
					_put_to_sleep(actor, target, int(p.sleep_turns), false, event, record)

## Puts `target` to sleep for its next `turns` actions (no attack, no energy). With Drowsiness on `source`, the
## sleeper takes extra damage and is immune for a while after waking; respect_cooldown skips immune targets.
## buff_name / log_key let other "skip a turn" effects reuse this (e.g. Group Owner's vote kick).
func _put_to_sleep(source: Dictionary, target: Dictionary, turns: int, respect_cooldown: bool, event: Dictionary, record: bool,
		buff_name: String = "", log_key: String = "log_put_to_sleep", wake_key: String = "log_wake_plain") -> void:
	if target.hp <= 0 or _has_flag(target, "sleep") or _has_flag(target, "undying"):
		return
	if respect_cooldown and int(target.get("sleep_immune", 0)) > 0:
		return
	var drowsy := _passive_params(source, &"drowsiness")
	_add_buff(target, {"id": &"asleep", "name": buff_name if not buff_name.is_empty() else Terms.t("buff_asleep"),
		"sleep": true, "remaining": turns, "counts": "sleep", "damage_taken": float(drowsy.get("damage_taken", 0.0)),
		"immune_after": int(drowsy.get("cooldown", 0)), "wake_log": wake_key})
	event.get_or_add("slept", []).append(target.index)
	if record:
		event.lines.append(Terms.t(log_key, {"target": target.name, "attacker": source.name}))

## A buff that helps its owner (stat boosts, taunt, healing mode, damage boost), as opposed to a debuff,
## sleep or bleed; Close Instance strips these
func _is_boon(b: Dictionary) -> bool:
	if b.get("sleep", false) or b.get("bleed", false) or b.get("undying", false):
		return false
	var mods: Dictionary = b.get("mods", {})
	if not mods.is_empty() and mods.values().any(func(v): return v > 0.0):
		return true
	return b.get("taunt", false) or b.get("healing", false) or float(b.get("damage_bonus", 0.0)) > 0.0

## Passive Drowsiness: after acting, a small chance to doze off and sleep through the next action
func _check_nod_off(u: Dictionary, rng: RandomNumberGenerator, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"drowsiness")
	if p.is_empty() or u.hp <= 0 or _has_flag(u, "sleep") or rng.randf() >= float(p.self_chance):
		return
	_add_buff(u, {"id": &"asleep", "name": Terms.t("buff_asleep"), "sleep": true, "remaining": 1, "counts": "sleep"})
	event.get_or_add("slept", []).append(u.index)
	if record:
		event.lines.append(Terms.t("log_nod_off", {"name": u.name, "skill": u.passive.name}))

## Who a healer on `u`'s side tends to first: hurt vanguard allies, then hurt rearguard allies (itself included),
## each row from the lowest HP share up
func _heal_order(u: Dictionary) -> Array:
	var hurt := _units.filter(func(a): return a.side == u.side and _alive(a) and a.hp < a.max_hp)
	hurt.sort_custom(func(a, b):
		if a.vanguard != b.vanguard:
			return a.vanguard
		return float(a.hp) / a.max_hp < float(b.hp) / b.max_hp)
	return hurt

## Heals the first `count` allies of `u` in healing order (see _heal_order)
func _heal_lowest(u: Dictionary, count: int, amount: int, event: Dictionary, record: bool) -> void:
	for ally in _heal_order(u).slice(0, count):
		_heal(ally, amount, event, record)

## Passive Winnie: after an attack, the pet heals the first ally in healing order
func _check_winnie(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"winnie")
	if p.is_empty() or u.hp <= 0:
		return
	var order := _heal_order(u)
	if order.is_empty():
		return
	event.get_or_add("winnie", []).append(u.index)
	if record:
		event.lines.append(Terms.t("log_winnie", {"name": u.name, "skill": u.passive.name, "target": order[0].name}))
	_heal(order[0], roundi(_stat(u, "attack") * float(p.heal_mult)), event, record)

## A buff with "explode_pct" ran out (e.g. CCP): a shockwave of that share of the unit's max HP hits every
## living enemy, reduced by each one's Defense
func _explode(u: Dictionary, pct: float, event: Dictionary, record: bool, rng: RandomNumberGenerator) -> void:
	if record:
		event.lines.append(Terms.t("log_explode", {"name": u.name}))
	for target in _units.filter(func(t): return t.side != u.side and _alive(t)):
		var dealt := _mitigate(u.max_hp * pct, target)
		event.hits.append({"target": target.index, "hit": true, "damage": dealt, "crit": false, "guard": false})
		if record:
			event.lines.append(Terms.t("log_hit", {"attacker": u.name, "target": target.name, "damage": dealt}))
		_apply_damage(u, target, dealt, event, record, rng)

## Waking from a Power Nap: full HP, debuffs gone, and an Attack buff
func _wake(u: Dictionary, wake: Dictionary, event: Dictionary, record: bool) -> void:
	_heal(u, u.max_hp - u.hp, event, record)
	u.buffs = u.buffs.filter(func(b): return not _is_debuff(b))
	_add_buff(u, {"id": &"power_nap", "name": wake.name, "mods": {"attack": float(wake.attack)},
		"remaining": int(wake.turns), "counts": "actions"})
	if record:
		event.lines.append(Terms.t("log_wake", {"name": u.name}))

## A debuff only lowers stats (e.g. Hangover); mixed buffs like SelfDecaying's trade-off don't count
func _is_debuff(b: Dictionary) -> bool:
	var mods: Dictionary = b.get("mods", {})
	return not mods.is_empty() and mods.values().all(func(v): return v < 0.0)

## The unit's passive params (defaults merged with the skill's own) if its passive is `effect`, else {}
func _passive_params(u: Dictionary, effect: StringName) -> Dictionary:
	if u.passive.is_empty() or u.passive.effect != effect:
		return {}
	return PASSIVE_EFFECTS[effect].merged(u.passive.params, true)

## Adds a buff, replacing an existing one with the same id. A buff a unit gets during its own action
## (e.g. its Ultimate) doesn't tick on that action; one it gets during someone else's action (e.g. a passive
## triggered by an enemy's hit) counts from the unit's very next action.
func _add_buff(u: Dictionary, buff: Dictionary) -> void:
	buff.fresh = u.index == _acting_index
	u.buffs = u.buffs.filter(func(b): return b.id != buff.id)
	u.buffs.append(buff)

## Count down buffs that expire on this kind of action ("actions" or "attacks")
func _tick_buffs(u: Dictionary, counts: String, event: Dictionary, record: bool, rng: RandomNumberGenerator) -> void:
	var kept := []
	var collapse := false
	var explode_pct := 0.0
	for b in u.buffs:
		if b.counts == counts and not b.fresh:
			b.remaining -= 1
			if b.remaining <= 0:
				if b.get("expire_kills", false):
					collapse = true
				elif record:
					event.lines.append(Terms.t("log_buff_end", {"target": u.name, "buff": b.name}))
				explode_pct = maxf(explode_pct, b.get("explode_pct", 0.0))
				continue
		kept.append(b)
	u.buffs = kept
	if explode_pct > 0.0 and u.hp > 0:
		_explode(u, explode_pct, event, record, rng)
	if collapse:  # e.g. Spijette's last stand runs out
		u.hp = 0
		if record:
			event.lines.append(Terms.t("log_undying_end", {"name": u.name}))

func _heal(u: Dictionary, amount: int, event: Dictionary, record: bool) -> void:
	if u.hp <= 0 or _has_flag(u, "undying"):
		return  # a unit on its last stand stays at 1 HP
	amount = mini(amount, u.max_hp - u.hp)
	if amount <= 0:
		return
	u.hp += amount
	event.heals.append({"target": u.index, "amount": amount})
	if record:
		event.lines.append(Terms.t("log_heal", {"target": u.name, "amount": amount}))

## Every point of damage goes through here, so passives that react to being hit work for attacks and assists alike
func _apply_damage(attacker: Dictionary, target: Dictionary, dealt: int, event: Dictionary, record: bool, rng: RandomNumberGenerator) -> void:
	if _has_flag(target, "undying"):
		target.hp = maxi(target.hp - dealt, 1)
		_gain_energy(target, ENERGY_PER_HIT_TAKEN)
		_check_counter(target, attacker, event, record, rng)
		return
	target.hp = maxi(target.hp - dealt, 0)
	_gain_energy(target, ENERGY_PER_HIT_TAKEN)
	_check_counter(target, attacker, event, record, rng)
	if target.hp > 0:
		_check_second_wind(target, event, record)
		_check_its_raw(target, attacker, event, record, rng)
		_check_berserk(target, event, record)
		_check_rally(target, event, record)
		return
	# Passive Undying: once per battle, a lethal hit leaves the unit hanging on at 1 HP
	var undying := _passive_params(target, &"undying")
	if not undying.is_empty() and target.passive_used == 0:
		target.passive_used = 1
		target.hp = 1
		_add_buff(target, {"id": &"undying", "name": target.passive.name, "undying": true, "expire_kills": true,
			"remaining": int(undying.turns), "counts": "actions"})
		if record:
			event.lines.append(Terms.t("log_undying", {"name": target.name, "skill": target.passive.name, "turns": int(undying.turns)}))
		return
	if record:
		event.lines.append(Terms.t("log_down", {"target": target.name}))
	# e.g. SelfDecaying: killing an enemy while the buff is active heals
	for b in attacker.buffs:
		if b.get("kill_heal_pct", 0.0) > 0.0:
			_heal(attacker, roundi(attacker.max_hp * b.kill_heal_pct), event, record)

## Passive Second Wind: when a hit leaves the unit below the threshold, heal up and harden, then cool down
func _check_second_wind(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"second_wind")
	if p.is_empty() or u.passive_cooldown > 0 or u.hp >= u.max_hp * float(p.threshold):
		return
	u.passive_cooldown = int(p.cooldown)
	if record:
		event.lines.append(Terms.t("log_passive", {"name": u.name, "skill": u.passive.name}))
	_heal(u, ceili(u.max_hp * float(p.heal_to)) - u.hp, event, record)
	_add_buff(u, {"id": &"second_wind", "name": u.passive.name, "mods": {"defense": float(p.defense)},
		"remaining": int(p.turns), "counts": "actions"})

## Passive One Above All: a random living rearguard ally hits back at whoever damaged this unit.
## Shown like an assist (the ally leaps in), flagged "counter" for its own banner.
func _check_counter(u: Dictionary, attacker: Dictionary, event: Dictionary, record: bool, rng: RandomNumberGenerator) -> void:
	var p := _passive_params(u, &"one_above_all")
	if p.is_empty() or _countering or attacker.side == u.side or attacker.hp <= 0:
		return
	var comrades := _units.filter(func(a): return a.side == u.side and not a.vanguard and _alive(a))
	if comrades.is_empty():
		return
	var helper: Dictionary = comrades[rng.randi_range(0, comrades.size() - 1)]
	var raw := _stat(helper, "attack") * float(p.attack_mult) * rng.randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE)
	var dealt := _mitigate(raw, attacker)
	event.assists.append({"actor": helper.index, "target": attacker.index, "damage": dealt, "counter": true})
	if record:
		event.lines.append(Terms.t("log_counter", {"attacker": helper.name, "target": attacker.name, "damage": dealt, "skill": u.passive.name}))
	_countering = true
	_apply_damage(helper, attacker, dealt, event, record, rng)
	_countering = false

## Passive Desperate Scramble: dropping below the threshold sends the unit Berserk, then it cools down
func _check_berserk(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"desperate_scramble")
	if p.is_empty() or u.passive_cooldown > 0 or u.hp >= u.max_hp * float(p.threshold):
		return
	u.passive_cooldown = int(p.cooldown)
	_add_buff(u, {"id": &"berserk", "name": Terms.t("buff_berserk"),
		"mods": {"attack": float(p.attack), "defense": float(p.defense)}, "remaining": int(p.turns), "counts": "actions"})
	event.get_or_add("berserk", []).append(u.index)
	if record:
		event.lines.append(Terms.t("log_berserk", {"name": u.name, "skill": u.passive.name}))

## Passive It's Raw: surviving a hit has a chance to chew out the attacker (-Attack/-Defense) and speed this unit up
func _check_its_raw(u: Dictionary, attacker: Dictionary, event: Dictionary, record: bool, rng: RandomNumberGenerator) -> void:
	var p := _passive_params(u, &"its_raw")
	if p.is_empty() or attacker.hp <= 0 or rng.randf() >= float(p.chance):
		return
	_add_buff(attacker, {"id": &"its_raw", "name": Terms.t("buff_its_raw"),
		"mods": {"attack": float(p.attack), "defense": float(p.defense)}, "remaining": int(p.turns), "counts": "actions"})
	_add_buff(u, {"id": &"its_raw_speed", "name": u.passive.name, "mods": {"speed": float(p.speed)},
		"remaining": int(p.speed_turns), "counts": "actions"})
	event.get_or_add("its_raw", []).append(u.index)
	if record:
		event.lines.append(Terms.t("log_its_raw", {"name": u.name, "skill": u.passive.name, "target": attacker.name}))

## Passive Cancer: every attack adds its own Attack stack (unique id, so stacks overlap instead of replacing)
func _add_cancer_stack(u: Dictionary) -> void:
	var p := _passive_params(u, &"cancer")
	if p.is_empty() or u.hp <= 0:
		return
	u.passive_used += 1
	_add_buff(u, {"id": StringName("cancer_%d" % u.passive_used), "name": u.passive.name,
		"mods": {"attack": float(p.attack)}, "remaining": int(p.turns), "counts": "actions"})

## Passive Cancer: loses a share of max HP at the end of each own action
func _cancer_drain(u: Dictionary, event: Dictionary, record: bool) -> void:
	var p := _passive_params(u, &"cancer")
	if p.is_empty() or u.hp <= 0:
		return
	var amount := maxi(roundi(u.max_hp * float(p.drain_pct)), 1)
	u.hp = maxi(u.hp - amount, 1 if _has_flag(u, "undying") else 0)
	event.drains.append({"target": u.index, "amount": amount})
	if record:
		event.lines.append(Terms.t("log_cancer", {"name": u.name, "skill": u.passive.name, "amount": amount}))
		if u.hp <= 0:
			event.lines.append(Terms.t("log_down", {"target": u.name}))

# ───────── Attacks ─────────

func _basic_attack(actor: Dictionary, units: Array[Dictionary], rng: RandomNumberGenerator, record: bool, event: Dictionary) -> void:
	var enemy_side: int = 1 - actor.side
	var targets: Array = []
	var mult := 1.0
	var all_enemies := _flag_buff(actor, "all_enemies")
	if not all_enemies.is_empty():
		# e.g. Lucky Break: this attack hits every living enemy, back row included
		targets = units.filter(func(u): return u.side == enemy_side and _alive(u))
		mult = float(all_enemies.get("damage_mult", 1.0))
		if record:
			event.lines.append(Terms.t("log_all_enemies", {"attacker": actor.name}))
	else:
		var foes := _targetable(units, enemy_side, _has_flag(actor, "back_row"))
		if foes.is_empty():
			return
		if actor.cls == CharacterData.CharClass.MAGE:
			# Area attacks ignore taunt. Partial Fisher-Yates shuffle with our own rng, then take the first 2-3.
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
			# Single-target attacks must go to a taunting enemy if there is one
			var taunting := foes.filter(func(u): return _has_flag(u, "taunt"))
			var pool := taunting if not taunting.is_empty() else foes
			targets = [pool[rng.randi_range(0, pool.size() - 1)]]
	# Passive Unfazed: a chance the swing carries through the rest of the target's row at reduced damage
	var cleaved: Array = []
	var unfazed := _passive_params(actor, &"unfazed")
	if targets.size() == 1 and all_enemies.is_empty() and not unfazed.is_empty() and rng.randf() < float(unfazed.cleave_chance):
		var main: Dictionary = targets[0]
		cleaved = units.filter(func(u): return u.side == enemy_side and _alive(u) and u.vanguard == main.vanguard and u.index != main.index)
		if not cleaved.is_empty() and record:
			event.lines.append(Terms.t("log_cleave", {"attacker": actor.name, "skill": actor.passive.name}))
	for target in targets:
		event.hits.append(_attack(actor, target, rng, record, event, mult))
	for target in cleaved:
		if _alive(target):
			event.hits.append(_attack(actor, target, rng, record, event, mult * float(unfazed.cleave_mult)))
	_resolve_chain(actor, units, rng, record, event)

## Raw damage before the target's Defense: Attack x variance x class multiplier x damage buffs (e.g. Morale Booster)
func _raw_damage(actor: Dictionary, rng: RandomNumberGenerator) -> float:
	var bonus := 1.0
	for b in actor.buffs:
		bonus += float(b.get("damage_bonus", 0.0))
	return _stat(actor, "attack") * rng.randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE) * CLASS_DAMAGE_MULT.get(actor.cls, 1.0) * bonus

## Damage after the target's Defense (and passive Unfazed's flat reduction); attacks and assists both use this
func _mitigate(raw: float, target: Dictionary) -> int:
	var damage := raw * 100.0 / (100.0 + _stat(target, "defense"))
	# e.g. put to sleep by Drowsiness: a sleeper takes extra damage
	damage *= 1.0 + float(_flag_buff(target, "sleep").get("damage_taken", 0.0))
	var unfazed := _passive_params(target, &"unfazed")
	if not unfazed.is_empty():
		damage *= 1.0 - float(unfazed.damage_reduction)
	return maxi(roundi(damage), 1)

func _attack(actor: Dictionary, target: Dictionary, rng: RandomNumberGenerator, record: bool, event: Dictionary, mult: float = 1.0) -> Dictionary:
	var hit := {"target": target.index, "hit": false, "damage": 0, "crit": false, "guard": false}
	# A Tank targeted while taunting has intercepted the attack, even if it then misses
	if target.cls == CharacterData.CharClass.TANK and _has_flag(target, "taunt"):
		hit.guard = true
	var accuracy := _stat(actor, "accuracy")
	var total := accuracy + _stat(target, "evasion")
	var hit_chance := MAX_HIT_CHANCE if total <= 0.0 else clampf(accuracy / total, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	if rng.randf() >= hit_chance:
		if record:
			event.lines.append(Terms.t("log_miss", {"attacker": actor.name, "target": target.name}))
		return hit

	var raw := _raw_damage(actor, rng) * mult
	hit.crit = rng.randf() < CRIT_CHANCE
	if hit.crit:
		raw *= CRIT_MULT
	if target.cls == CharacterData.CharClass.TANK and raw >= target.max_hp * GUARD_HEAVY_PCT:
		hit.guard = true
	var dealt := _mitigate(raw, target)
	hit.hit = true
	hit.damage = dealt
	if record:
		var key := "log_crit" if hit.crit else "log_hit"
		event.lines.append(Terms.t(key, {"attacker": actor.name, "target": target.name, "damage": dealt}))
	_apply_damage(actor, target, dealt, event, record, rng)
	# Passive Bow Wow: the hit opens a bleed (one per attacker; a new hit refreshes it)
	var bow_wow := _passive_params(actor, &"bow_wow")
	if target.hp > 0 and not bow_wow.is_empty():
		_add_buff(target, {"id": StringName("bleed_%d" % actor.index), "name": Terms.t("buff_bleed"), "bleed": true,
			"source": actor.index, "amount": _stat(actor, "attack") * float(bow_wow.bleed_pct),
			"remaining": int(bow_wow.turns), "counts": "actions"})
		event.get_or_add("bled", []).append(target.index)
	# Passive DB Grub: a chance to steal some of the target's Attack for the next turn
	var grub := _passive_params(actor, &"db_grub")
	if target.hp > 0 and not grub.is_empty() and rng.randf() < float(grub.chance):
		var stolen := _stat(target, "attack") * float(grub.steal_pct)
		_add_buff(target, {"id": &"grubbed", "name": Terms.t("buff_grubbed"), "mods": {"attack": -float(grub.steal_pct)},
			"remaining": int(grub.turns), "counts": "actions"})
		_add_buff(actor, {"id": &"grub_feast", "name": actor.passive.name,
			"mods": {"attack": stolen / maxf(absf(float(actor.base.attack)), 1.0)}, "remaining": int(grub.turns), "counts": "actions"})
		event.get_or_add("grubbed", []).append(target.index)
		if record:
			event.lines.append(Terms.t("log_grubbed", {"name": actor.name, "target": target.name, "amount": roundi(stolen)}))
	# Passive Power of Baldness: heals a share of the damage dealt
	var lifesteal := _passive_params(actor, &"power_of_baldness")
	if not lifesteal.is_empty():
		_heal(actor, roundi(dealt * float(lifesteal.lifesteal)), event, record)
	# Passive Blinding (e.g. Solar Flare Baldness): a chance the hit leaves the target half-blind
	var blinding := _passive_params(actor, &"blinding")
	if target.hp > 0 and not blinding.is_empty() and rng.randf() < float(blinding.chance):
		_add_buff(target, {"id": &"blinded", "name": Terms.t("buff_blinded"), "mods": {"accuracy": float(blinding.accuracy)},
			"remaining": int(blinding.turns), "counts": "actions"})
		event.get_or_add("blinded", []).append(target.index)
		if record:
			event.lines.append(Terms.t("log_blinded", {"target": target.name, "skill": actor.passive.name}))
	# Passive Drowsiness: a chance the hit lulls the target to sleep
	var drowsy := _passive_params(actor, &"drowsiness")
	if not drowsy.is_empty() and rng.randf() < float(drowsy.chance):
		_put_to_sleep(actor, target, int(drowsy.turns), true, event, record)
	if target.hp > 0 and actor.vanguard and (hit.crit or dealt >= target.max_hp * HEAVY_HIT_PCT):
		event.off_balance.append(target.index)
		if record:
			event.lines.append(Terms.t("log_off_balance", {"target": target.name}))
	return hit

# ───────── Combat chain: assists & guard charges ─────────

func _resolve_chain(actor: Dictionary, units: Array[Dictionary], rng: RandomNumberGenerator, record: bool, event: Dictionary) -> void:
	# Assist: the first living rearguard ally (fastest first) to pass their roll strikes the Off-Balance target
	if not event.off_balance.is_empty():
		var target: Dictionary = units[event.off_balance[0]]
		var helpers := units.filter(func(u): return u.side == actor.side and not u.vanguard and _alive(u))
		helpers.sort_custom(func(a, b): return _stat(a, "speed") > _stat(b, "speed"))
		for helper in helpers:
			if target.hp > 0 and rng.randf() < assist_chance(_stat(helper, "speed")):
				_assist(helper, target, rng, record, event)
				break
	# Guard charge: a Tank that soaked a heavy hit or intercepted one while taunting powers up the backline
	for hit in event.hits:
		if not hit.guard:
			continue
		var tank: Dictionary = units[hit.target]
		var charged := []
		for ally in units:
			if ally.side == tank.side and not ally.vanguard and _alive(ally) and not ally.ultimate.is_empty():
				_gain_energy(ally, roundi(ally.energy_max * GUARD_CHARGE_PCT))
				charged.append(ally.index)
		if not charged.is_empty():
			event.guard_charges.append({"tank": tank.index, "allies": charged})
			if record:
				event.lines.append(Terms.t("log_guard_charge", {"name": tank.name}))
		break  # once per action

static func assist_chance(speed: float) -> float:
	return clampf(ASSIST_BASE_CHANCE + (speed - 50.0) * ASSIST_CHANCE_PER_SPEED, ASSIST_BASE_CHANCE, ASSIST_MAX_CHANCE)

## A free strike at half damage that can't miss (the target is Off-Balance). It doesn't cost the helper a turn.
func _assist(helper: Dictionary, target: Dictionary, rng: RandomNumberGenerator, record: bool, event: Dictionary) -> void:
	var dealt := maxi(roundi(_mitigate(_raw_damage(helper, rng), target) * ASSIST_DAMAGE_MULT), 1)
	event.assists.append({"actor": helper.index, "target": target.index, "damage": dealt})
	if record:
		event.lines.append(Terms.t("log_assist", {"attacker": helper.name, "target": target.name, "damage": dealt}))
	_apply_damage(helper, target, dealt, event, record, rng)
