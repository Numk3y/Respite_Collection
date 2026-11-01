@tool
class_name SkillData
extends Resource
## A skill. Every character has one passive and one active skill.
## The active skill is the character's Ultimate: it fires automatically when the Ultimate gauge is full.
## The passive reacts to battle events on its own.
## Behaviour comes from effect_id (see FormationBattleEngine.ULTIMATE_EFFECTS / PASSIVE_EFFECTS); leave it empty
## for skills whose logic hasn't been designed yet. params tunes the effect, e.g. {"defense": 0.5, "turns": 3}.

enum Kind { PASSIVE, ACTIVE }

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.PASSIVE
@export_multiline var description: String
@export var icon: Texture2D
@export var effect_id: StringName
@export var params: Dictionary = {}
