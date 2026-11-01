@tool
class_name WaveData
extends Resource
## One battle (wave) of a mission. Waves are fought back to back: the team's HP, Ultimate gauges and buffs
## carry over, and knocked-out friends stay down. Up to 3 enemies per row, same row rules as friends.

@export var enemy_vanguard: Array[CharacterData] = []
@export var enemy_rearguard: Array[CharacterData] = []
@export var is_boss := false  # shows the boss banner when this wave starts
