@tool
class_name CommissionData
extends Resource
## A part-time job (commission) a friend can be sent on. One friend per job, one job per friend.
## Workers can still join battles during their shift.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var duration_seconds: int = 3600
## VRChat-style status shown on the worker while they're on this shift
@export_enum("In World", "Mirror Mode", "Busy") var status_tag: int = 0
@export_group("Requirement")
## Only this class can take the job; Any = everyone
@export_enum("Any:-1", "Tank:0", "Warrior:1", "Mage:2", "Shooter:3", "Berserker:4") var required_class: int = -1
## A stat the worker needs at least required_value of (with level, Ascension and gear). Empty = none.
@export var required_stat: String = ""  # hp, attack, defense, evasion, accuracy or speed
@export var required_value: int = 0
@export_group("Rewards")
@export var reward_money: int = 100
@export var reward_materials: Dictionary[String, Vector2i] = {}  # material key -> (min, max)
@export var exp_reward: int = 0  # for the worker
@export_range(0.0, 1.0) var credit_card_chance: float = 0.0
@export_group("Incidents")
@export_range(0.0, 1.0) var incident_chance: float = 0.35  # chance that one incident happens per shift
@export var incidents: Array[CommissionIncident] = []
