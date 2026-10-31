@tool
class_name CharacterData
extends Resource
## A friend (or an enemy: stages reuse this resource for their enemy lineups)

enum Rarity { N, R, SR, SSR }
## Tank and Warrior fight in the vanguard; Mage and Shooter in the rearguard
enum CharClass { TANK, WARRIOR, MAGE, SHOOTER }

const STATS := ["hp", "attack", "defense", "evasion", "accuracy", "speed"]
const CLASS_KEYS := ["tank", "warrior", "mage", "shooter"]
## Suggested starting stats per class; the admin tool pre-fills these when a class is picked
const CLASS_TEMPLATES := {
	CharClass.TANK: {"hp": 180, "attack": 45, "defense": 90, "evasion": 10, "accuracy": 70, "speed": 40},
	CharClass.WARRIOR: {"hp": 120, "attack": 85, "defense": 55, "evasion": 25, "accuracy": 75, "speed": 65},
	CharClass.MAGE: {"hp": 80, "attack": 80, "defense": 35, "evasion": 20, "accuracy": 85, "speed": 55},
	CharClass.SHOOTER: {"hp": 80, "attack": 115, "defense": 35, "evasion": 15, "accuracy": 95, "speed": 50},
}

@export var id: StringName
@export var display_name: String
@export var title: String
@export var char_class: CharClass = CharClass.WARRIOR
@export var rarity: Rarity = Rarity.R
@export_group("Base Stats")
@export_range(1, 9999) var hp: int = 100  # only matters in the vanguard; rearguard units can't be hit
@export_range(0, 9999) var attack: int = 50
@export_range(0, 9999) var defense: int = 50
@export_range(0, 9999) var evasion: int = 20
@export_range(0, 9999) var accuracy: int = 70
@export_range(1, 9999) var speed: int = 50
@export_group("Skills")
@export var passive_skill: SkillData
@export var active_skill: SkillData
@export_group("Art")
@export var portrait: Texture2D  # leave empty to show the placeholder
@export var avatar: Texture2D
@export_group("")
@export_multiline var description: String
@export var is_starter: bool = false  # vanguard classes only
@export var enabled: bool = true

static func is_vanguard_class(cls: int) -> bool:
	return cls == CharClass.TANK or cls == CharClass.WARRIOR

func is_vanguard() -> bool:
	return is_vanguard_class(char_class)

func class_key() -> String:
	return CLASS_KEYS[char_class]

func base_stats() -> Dictionary:
	var stats := {}
	for stat in STATS:
		stats[stat] = get(stat)
	return stats
