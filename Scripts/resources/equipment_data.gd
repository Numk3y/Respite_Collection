@tool
class_name EquipmentData
extends Resource
## A piece of gear. Each character has one Weapon, one Armor and one Accessory slot.

enum Slot { WEAPON, ARMOR, ACCESSORY }

const SLOT_KEYS := ["weapon", "armor", "accessory"]
const MOD_STATS := ["attack", "defense", "evasion", "accuracy", "speed"]

@export var id: StringName
@export var display_name: String
@export var slot: Slot = Slot.WEAPON
@export var icon: Texture2D
@export_multiline var description: String
@export_group("Stat Modifiers")  # added to the wearer's stats; negative values subtract
@export_range(-999, 999) var attack: int = 0
@export_range(-999, 999) var defense: int = 0
@export_range(-999, 999) var evasion: int = 0
@export_range(-999, 999) var accuracy: int = 0
@export_range(-999, 999) var speed: int = 0

func slot_key() -> String:
	return SLOT_KEYS[slot]

## Only the non-zero modifiers, e.g. {"attack": 8, "speed": -5}
func modifiers() -> Dictionary:
	var mods := {}
	for stat in MOD_STATS:
		var value: int = get(stat)
		if value != 0:
			mods[stat] = value
	return mods
