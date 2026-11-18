@tool
class_name DrinkData
extends Resource
## An After Hours Drink (a power-up for the rest of the run) or a Hangover (a forced debuff; `hangover` on).
## Data/drinks/*.tres. See the Endless autoload and PLAN_AFTER_HOURS.md.
##
## Battle effects are FormationBattleEngine rules (see _add_side): `ally_rules` go on every friend the Drink
## targets, `enemy_rules` on every enemy. `run_effects` change the run itself (multipliers, all default 1.0):
## "tips_mult" (Tips earned), "rest_heal_mult" (Rest heal), "bar_price_mult" (Bar prices), "hire_price_mult"
## (Bar hire prices), "bench_heal_mult" (bench healing between nodes).

enum Rarity { COMMON, RARE, LEGENDARY }
enum Target { SQUAD, VANGUARD, REARGUARD, CLASS }
enum Severity { MILD, HARSH }  # Hangovers: Rare Drinks roll Mild ones, Legendary Drinks Harsh ones
enum Category { SQUAD, ENEMIES, ECONOMY }  # Hangovers: one offer never repeats a category

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var rarity: Rarity = Rarity.COMMON
@export var target: Target = Target.SQUAD
@export var target_class: CharacterData.CharClass = CharacterData.CharClass.TANK  # with Target CLASS
@export var ally_rules: Dictionary = {}
@export var enemy_rules: Dictionary = {}
@export var run_effects: Dictionary = {}
@export_group("Hangover")
@export var hangover := false
@export var severity: Severity = Severity.MILD
@export var category: Category = Category.SQUAD
@export_group("")
@export var enabled := true

## Whether the Drink's ally rules apply to a friend of this class in this row
func applies_to(cls: int, vanguard: bool) -> bool:
	match target:
		Target.VANGUARD:
			return vanguard
		Target.REARGUARD:
			return not vanguard
		Target.CLASS:
			return cls == target_class
	return true

func run_mult(key: String) -> float:
	return float(run_effects.get(key, 1.0))
