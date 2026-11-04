@tool
class_name EquipmentData
extends Resource
## A piece of gear. Each character has one Weapon, one Armor and one Accessory slot.
## Gear has a rarity (R / SR / SSR, which sets what it scraps for and costs to craft or upgrade) and every owned
## copy has its own upgrade level, +0 to GameState.GEAR_MAX_PLUS; each + adds GEAR_PLUS_STEP of the positive
## modifiers below (at least +1 per level), negatives stay as they are. See GameState's Gear section and the Workshop tab.

enum Slot { WEAPON, ARMOR, ACCESSORY }

const SLOT_KEYS := ["weapon", "armor", "accessory"]
const MOD_STATS := ["attack", "defense", "evasion", "accuracy", "speed"]
const GEAR_PLUS_STEP := 0.1  # each upgrade level adds 10% of the item's base (positive) modifiers

@export var id: StringName
@export var display_name: String
@export var slot: Slot = Slot.WEAPON
## R, SR or SSR (N isn't used for gear)
@export var rarity: CharacterData.Rarity = CharacterData.Rarity.R
@export var icon: Texture2D
@export_multiline var description: String
@export_group("Stat Modifiers")  # the +0 values, added to the wearer's stats; negative values subtract
@export_range(-999, 999) var attack: int = 0
@export_range(-999, 999) var defense: int = 0
@export_range(-999, 999) var evasion: int = 0
@export_range(-999, 999) var accuracy: int = 0
@export_range(-999, 999) var speed: int = 0

func slot_key() -> String:
	return SLOT_KEYS[slot]

## Only the non-zero modifiers at an upgrade level, e.g. {"attack": 8, "speed": -5}
func modifiers(plus: int = 0) -> Dictionary:
	var mods := {}
	for stat in MOD_STATS:
		var value: int = get(stat)
		if value > 0 and plus > 0:
			value += maxi(roundi(value * GEAR_PLUS_STEP * plus), plus)  # at least +1 per level on small stats
		if value != 0:
			mods[stat] = value
	return mods
