@tool
class_name GachaPool
extends Resource

@export var id: StringName
@export var display_name: String
@export var banner: Texture2D  # background image for the banner; leave empty to use a theme_color gradient
@export var theme_color: Color = Color("#7c3aed")
@export var cost: int = 150
@export var pity_threshold: int = 80  # pull that guarantees an SSR; 0 = no pity
@export_group("Rarity Weights")  # shares of each pull; R 82 / SR 14 / SSR 4 reads as percentages
@export var weight_r: int = 82
@export var weight_sr: int = 14
@export var weight_ssr: int = 4
@export_group("")
@export var entries: Array[PoolEntry] = []  # tick "featured" on an entry to show it as a Pick Up on the banner

func weight_for(rarity: int) -> int:
	match rarity:
		CharacterData.Rarity.R: return weight_r
		CharacterData.Rarity.SR: return weight_sr
		CharacterData.Rarity.SSR: return weight_ssr
	return 0

func featured_characters() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for entry in entries:
		if entry.featured and entry.character and entry.character.enabled:
			out.append(entry.character)
	return out
