class_name BattleEngine
extends RefCounted
## Base class for battle rules. To build advanced combat later (skills, turns), extend this and swap Idle.engine.
##
## A fleet is {"vanguard": [unit, ...], "rearguard": [unit, ...]}
## and a unit is {"name": String, "cls": CharacterData.CharClass, "stats": {hp, attack, defense, evasion, accuracy, speed}}.
##
## Returns {"win": bool, "actions": int, "log": PackedStringArray}. When record is true it also returns:
##   "units":     [{name, side, vanguard, cls, max_hp}]  (side 0 = allies, 1 = enemies; index = position)
##   "events":    [{"actor": int, "hits": [{"target": int, "hit": bool, "damage": int, "hp": int}], "lines": PackedStringArray}]
##   "end_lines": PackedStringArray  (the victory/defeat line)

func simulate(_allies: Dictionary, _enemies: Dictionary, _rng: RandomNumberGenerator, _record: bool = false) -> Dictionary:
	return {"win": false, "actions": 0, "log": PackedStringArray()}
