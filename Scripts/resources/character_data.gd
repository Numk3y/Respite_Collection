@tool
class_name CharacterData
extends Resource
## A friend (or an enemy: stages reuse this resource for their enemy lineups)

## N is retired (every former N character is now R); it stays in the enum only so the stored numbers of R/SR/SSR
## don't shift. Use RARITIES for anything players or the admin tool see.
enum Rarity { N, R, SR, SSR }
const RARITIES := [Rarity.R, Rarity.SR, Rarity.SSR]
## Tank, Warrior and Berserker fight in the vanguard; Mage, Shooter and Healer in the rearguard.
## New classes go at the end so existing .tres files keep their values.
enum CharClass { TANK, WARRIOR, MAGE, SHOOTER, BERSERKER, HEALER }

const STATS := ["hp", "attack", "defense", "evasion", "accuracy", "speed"]
const CLASS_KEYS := ["tank", "warrior", "mage", "shooter", "berserker", "healer"]
## Suggested starting stats per class; the admin tool pre-fills these when a class is picked
const CLASS_TEMPLATES := {
	CharClass.TANK: {"hp": 180, "attack": 45, "defense": 90, "evasion": 10, "accuracy": 70, "speed": 40},
	CharClass.WARRIOR: {"hp": 120, "attack": 85, "defense": 55, "evasion": 25, "accuracy": 75, "speed": 65},
	CharClass.MAGE: {"hp": 80, "attack": 80, "defense": 35, "evasion": 20, "accuracy": 85, "speed": 55},
	CharClass.SHOOTER: {"hp": 80, "attack": 115, "defense": 35, "evasion": 15, "accuracy": 95, "speed": 50},
	CharClass.BERSERKER: {"hp": 120, "attack": 125, "defense": 20, "evasion": 20, "accuracy": 75, "speed": 85},
	CharClass.HEALER: {"hp": 85, "attack": 70, "defense": 35, "evasion": 15, "accuracy": 80, "speed": 55},
}
const ART_DIR := "res://Art/characters/"
const CUTIN_DIR := "res://Art/cutins/"

@export var id: StringName
@export var display_name: String
@export var title: String
@export var char_class: CharClass = CharClass.WARRIOR
@export var rarity: Rarity = Rarity.R
@export_group("Base Stats")  # level 1 values; each level adds GameState.GROWTH_PER_LEVEL
@export_range(1, 9999) var hp: int = 100  # the rearguard is only hit once the whole vanguard is down
@export_range(0, 9999) var attack: int = 50
@export_range(-50, 9999) var defense: int = 50  # below 0 the unit takes extra damage (-50 = double)
@export_range(0, 9999) var evasion: int = 20
@export_range(0, 9999) var accuracy: int = 70
@export_range(1, 9999) var speed: int = 50
## Extra growth per level on top of GameState.GROWTH_PER_LEVEL for specific stats,
## e.g. {"speed": 0.02} makes Speed grow 6% of its base per level instead of 4%
@export var growth_bonus: Dictionary = {}
@export_group("Skills")
@export var passive_skill: SkillData  # reacts to battle events; see FormationBattleEngine.PASSIVE_EFFECTS
@export var active_skill: SkillData  # the Ultimate
## Ultimate gauge capacity. The gauge fills as this character acts and takes hits;
## when full, the Ultimate fires on their next action.
@export_range(1, 1000) var ultimate_max: int = 100
@export_group("Art")
## Leave empty to auto-load Art/characters/<id>.png (or .webp/.jpg, any letter case).
## Set it only when the file is named differently. With no image, the game shows a placeholder card.
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var portrait_path: String
## Optional small image for lists; falls back to the portrait
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var avatar_path: String
## Picture for the Ultimate cut-in. Leave empty to auto-load Art/cutins/<id>.png (any extension/case);
## with no cut-in image the portrait is used.
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var cutin_path: String
@export_group("")
@export_multiline var description: String
@export var is_starter: bool = false  # vanguard classes only
@export var enabled: bool = true

static func is_vanguard_class(cls: int) -> bool:
	return cls == CharClass.TANK or cls == CharClass.WARRIOR or cls == CharClass.BERSERKER

func is_vanguard() -> bool:
	return is_vanguard_class(char_class)

func class_key() -> String:
	return CLASS_KEYS[char_class]

func base_stats() -> Dictionary:
	var stats := {}
	for stat in STATS:
		stats[stat] = get(stat)
	return stats

## The Ultimate in the shape BattleEngine expects, or {} if this character has no working Ultimate yet
func ultimate_dict() -> Dictionary:
	if active_skill == null or active_skill.effect_id == &"":
		return {}
	return {"effect": active_skill.effect_id, "name": active_skill.display_name, "params": active_skill.params}

## The passive in the shape BattleEngine expects, or {} if this character has no working passive yet
func passive_dict() -> Dictionary:
	if passive_skill == null or passive_skill.effect_id == &"":
		return {}
	return {"effect": passive_skill.effect_id, "name": passive_skill.display_name, "params": passive_skill.params}

## A battle unit for BattleEngine using these stats as-is (used for enemies; friends go through GameState)
func battle_unit(stats: Dictionary = {}) -> Dictionary:
	return {
		"name": display_name, "cls": char_class, "stats": stats if not stats.is_empty() else base_stats(),
		"energy_max": ultimate_max, "ultimate": ultimate_dict(), "passive": passive_dict(), "data": self,
	}

func default_portrait_path() -> String:
	return ART_DIR + String(id) + ".png"

## The portrait, or null if there's no image yet (the UI then draws a placeholder).
## Uses portrait_path if it points at an existing file; otherwise looks in the portrait folder
## (Art/characters/ by default) for an image named after the id: gobby.png, Gobby.webp, GOBBY.jpg ...
func get_portrait() -> Texture2D:
	var folder := ART_DIR if portrait_path.is_empty() else portrait_path.get_base_dir() + "/"
	var path := find_art(folder, portrait_path.get_file()) if not portrait_path.is_empty() else ""
	if path.is_empty():
		path = find_art(folder, String(id))
	return load(path) as Texture2D if not path.is_empty() else null

func get_avatar() -> Texture2D:
	if not avatar_path.is_empty():
		var path := find_art(avatar_path.get_base_dir() + "/", avatar_path.get_file())
		if not path.is_empty():
			return load(path) as Texture2D
	return get_portrait()

## The Ultimate cut-in picture: cutin_path, else Art/cutins/<id>.*, else the portrait (null if none at all)
func get_cutin() -> Texture2D:
	var path := ""
	if not cutin_path.is_empty():
		path = find_art(cutin_path.get_base_dir() + "/", cutin_path.get_file())
	if path.is_empty():
		path = find_art(CUTIN_DIR, String(id))
	return load(path) as Texture2D if not path.is_empty() else get_portrait()

const ART_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]
static var _art_index := {}  # folder -> {lowercase file name or name without extension: real path}

## Finds an image in a folder by file name ("goblox.png") or bare name ("spijette"), ignoring letter case
## and extension. Exported web builds are case-sensitive, so a file saved as "Spijette.png" must still be
## found when looking for "spijette". Folder listings are cached for the session.
static func find_art(folder: String, file_name: String) -> String:
	if not _art_index.has(folder):
		var index := {}
		for file in ResourceLoader.list_directory(folder):
			if file.get_extension().to_lower() in ART_EXTENSIONS:
				index[file.to_lower()] = folder + file
				index[file.get_basename().to_lower()] = folder + file
		_art_index[folder] = index
	return _art_index[folder].get(file_name.to_lower(), "")
