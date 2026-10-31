@tool
class_name StageData
extends Resource
## A map you can sortie to

@export var id: StringName
@export var display_name: String
@export var background: Texture2D
@export_group("Enemies")  # up to 3 per row; vanguard needs Tank/Warrior, rearguard needs Mage/Shooter
@export var enemy_vanguard: Array[CharacterData] = []
@export var enemy_rearguard: Array[CharacterData] = []
@export_group("Rewards")  # per battle won
@export var reward_money: int = 50
@export var reward_materials: Dictionary[String, Vector2i] = {}  # material key -> (min, max)
@export var equipment_drops: Array[EquipmentData] = []
@export_range(0.0, 1.0) var drop_chance: float = 0.05

func enemy_count() -> int:
	return enemy_vanguard.size() + enemy_rearguard.size()

## Same shape as GameState.get_battle_fleet()
func get_enemy_fleet() -> Dictionary:
	var fleet := {"vanguard": [], "rearguard": []}
	for c in enemy_vanguard.slice(0, 3):
		if c:
			fleet.vanguard.append({"name": c.display_name, "cls": c.char_class, "stats": c.base_stats()})
	for c in enemy_rearguard.slice(0, 3):
		if c:
			fleet.rearguard.append({"name": c.display_name, "cls": c.char_class, "stats": c.base_stats()})
	return fleet
