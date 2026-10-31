@tool
class_name SkillData
extends Resource
## Skill placeholder. Every character has one passive and one active skill.
## Only the descriptive fields exist for now; skill logic will be added later.

enum Kind { PASSIVE, ACTIVE }

@export var id: StringName
@export var display_name: String
@export var kind: Kind = Kind.PASSIVE
@export_multiline var description: String
@export var icon: Texture2D
@export var params: Dictionary = {}  # tuning values for when skill effects are implemented
