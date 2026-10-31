@tool
class_name GachaPool
extends Resource

@export var id: StringName
@export var display_name: String
@export var banner: Texture2D
@export var cost: int = 150
@export var pity_threshold: int = 80  # pull that guarantees an SSR; 0 = no pity
@export_group("Rarity Weights")
@export var weight_n: int = 0
@export var weight_r: int = 64
@export var weight_sr: int = 28
@export var weight_ssr: int = 8
@export_group("")
@export var entries: Array[PoolEntry] = []

func weight_for(rarity: int) -> int:
	match rarity:
		CharacterData.Rarity.N: return weight_n
		CharacterData.Rarity.R: return weight_r
		CharacterData.Rarity.SR: return weight_sr
		CharacterData.Rarity.SSR: return weight_ssr
	return 0
