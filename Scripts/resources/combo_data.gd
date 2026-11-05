@tool
class_name ComboData
extends Resource
## A combo attack: when every member is in the team (and fighting), each time one of them acts there's a small chance
## the whole group unleashes the combo right after that action. It doesn't use up anyone's turn.
## Members: everyone in `members` is required, plus at least `any_count` of the friends in `any_of` (e.g. ShadowKittay
## and any 2 of the 3 bald friends). Every `any_of` friend who's fighting and alive joins in when it fires.
## Put one .tres per combo in Data/combos/.
##
## Chance: base_chance per roll, or comeback_chance while the team's total HP share is below comeback_hp, so a combo
## is most likely to turn things around when the team is losing. A combo fires at most once per battle (or once
## per wave with per_wave on).
##
## Every combo has its own effect: effect_id names one entry in FormationBattleEngine.COMBO_EFFECTS, and no two
## combos may share one. params tunes it, e.g. {"damage_mult": 3.0}.
##
## Cut-in: cutin_path (or Art/combos/<id>.png) is a special picture for this combo, shown with cutin_title.
## Without a picture the cut-in is a split screen of every member's own cut-in art.

enum Once { BATTLE, WAVE }

const ART_DIR := "res://Art/combos/"

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var members: Array[StringName] = []  # character ids; all of them are required
@export var any_of: Array[StringName] = []  # character ids; at least any_count of them are required too
@export_range(0, 6) var any_count: int = 0
@export var enabled: bool = true
@export_group("Trigger")
@export_range(0.0, 1.0, 0.0025) var base_chance: float = 0.0125
@export_range(0.0, 1.0, 0.0025) var comeback_chance: float = 0.12
@export_range(0.0, 1.0, 0.01) var comeback_hp: float = 0.30  # team HP share below which comeback_chance applies
@export var once_per: Once = Once.BATTLE
@export_group("Effect")
@export var effect_id: StringName
@export var params: Dictionary = {}
@export_group("Cut-in")
@export_file("*.png", "*.jpg", "*.jpeg", "*.webp") var cutin_path: String  # empty: Art/combos/<id>.*, else split screen
@export var cutin_title: String  # the name on the cut-in; empty uses display_name

## True when every member is among `ids` (a set of character ids: {id: true})
func is_ready(ids: Dictionary) -> bool:
	if not enabled or min_size() < 2 or effect_id == &"":
		return false
	for m in members:
		if not ids.has(m):
			return false
	return any_of.filter(func(m): return ids.has(m)).size() >= any_count

## The fewest friends who can pull this combo off
func min_size() -> int:
	return members.size() + mini(any_count, any_of.size())

func title() -> String:
	return cutin_title if not cutin_title.is_empty() else display_name

## The combo in the shape FormationBattleEngine expects (see begin(): allies.combos)
func battle_dict() -> Dictionary:
	return {"id": id, "name": display_name, "members": members.duplicate(), "any_of": any_of.duplicate(),
		"any_count": any_count, "effect": effect_id, "params": params,
		"chance": base_chance, "comeback_chance": comeback_chance, "comeback_hp": comeback_hp,
		"per_wave": once_per == Once.WAVE, "data": self}

## The combo's own cut-in picture, or null to use the split screen of its members
func get_cutin() -> Texture2D:
	var path := ""
	if not cutin_path.is_empty():
		path = CharacterData.find_art(cutin_path.get_base_dir() + "/", cutin_path.get_file())
	if path.is_empty() and DirAccess.dir_exists_absolute(ART_DIR):
		path = CharacterData.find_art(ART_DIR, String(id))
	return load(path) as Texture2D if not path.is_empty() else null

## Every friend who can take part (required ones first), as CharacterData; missing ids are skipped
func member_data() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for m in members + any_of:
		var c: CharacterData = DB.characters.get(m)
		if c:
			out.append(c)
	return out
