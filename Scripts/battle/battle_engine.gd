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
