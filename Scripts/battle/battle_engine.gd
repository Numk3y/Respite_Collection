class_name BattleEngine
extends RefCounted
## Base class for battle rules. To build different combat later, extend this and swap Combat.engine.
##
## A team is {"vanguard": [unit, ...], "rearguard": [unit, ...]} and a unit is
## {"name", "cls": CharacterData.CharClass, "stats": {hp, attack, defense, evasion, accuracy, speed},
##  "energy_max": int, "data": CharacterData (for the battle screen), "ultimate": {"effect": StringName, "name": String, "params": Dictionary} or {}}.
## CharacterData.battle_unit() builds one.
##
## `enemies` is one team or {"waves": [team, ...]} for missions with several battles in a row.
## Optional keys: "max_actions" (actions per wave before the battle times out) and "timeout_key"
## (Terms key of the line shown when it does); the world boss uses both.
##
## Live battles (begin / step / result, below) play the same battle one action at a time.
##
## Returns {"win": bool, "actions": int, "log": PackedStringArray, "waves_cleared": int, "wave_count": int}.
## When record is true it also returns:
##   "units":     [{name, side, wave, vanguard, cls, max_hp, energy_max, has_ultimate, data: CharacterData}]
##                (side 0 = allies with wave -1, side 1 = enemies with the wave they belong to)
##   "events":    one per action: {"actor": int, "kind": "attack" | "ultimate" | "wave", "skill": String,
##                 ("wave" events have actor -1 and add "wave", "wave_count", "boss": the next wave arrives)
##                 "hits": [{"target", "hit", "damage", "crit", "guard"}], "heals": [{"target", "amount"}],
##                 "off_balance": [target, ...], "assists": [{"actor", "target", "damage"}],
##                 "guard_charges": [{"tank", "allies": [index, ...]}], "lines": PackedStringArray,
##                 "state": [{"hp", "energy", "buffs": PackedStringArray}] (every unit, after the action)}
##   "end_lines": PackedStringArray  (the victory/defeat line)

func simulate(_allies: Dictionary, _enemies: Dictionary, _rng: RandomNumberGenerator, _record: bool = false) -> Dictionary:
	return {"win": false, "actions": 0, "log": PackedStringArray()}

# ───────── Live battles ─────────
# Play a battle one action at a time so the player can act during it (manual Ultimates). This fallback runs
# the whole battle up front and hands its events out one by one; engines that support manual play override it.

var _fallback_result := {}
var _fallback_next := 0

## Returns the unit snapshot ("units" above)
func begin(allies: Dictionary, enemies: Dictionary, rng: RandomNumberGenerator, _record: bool = true, _manual: bool = false) -> Array:
	_fallback_result = simulate(allies, enemies, rng, true)
	_fallback_next = 0
	return _fallback_result.get("units", [])

func is_done() -> bool:
	return _fallback_next >= _fallback_result.get("events", []).size()

## The next event, or {} once the battle is over
func step() -> Dictionary:
	if is_done():
		return {}
	_fallback_next += 1
	return _fallback_result.events[_fallback_next - 1]

func result() -> Dictionary:
	return _fallback_result

func set_manual(_on: bool) -> void:
	pass

func queue_ultimate(_index: int, _on: bool = true) -> void:
	pass

func is_ultimate_queued(_index: int) -> bool:
	return false
