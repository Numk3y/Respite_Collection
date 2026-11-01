@tool
class_name CommissionIncident
extends Resource
## Something that can happen during a part-time shift. "{name}" in the text becomes the worker's name.
## Set character_id to make it happen only to that friend (e.g. Spijette breaking things).

@export_multiline var text: String
@export var character_id: StringName  # empty = can happen to anyone
@export_range(1, 1000) var weight: int = 10  # relative chance among the incidents that can happen
@export_group("Effects on the pay")
@export var money_multiplier: float = 1.0  # e.g. 1.2 = +20% pay
@export var money_bonus: int = 0  # negative docks pay
@export var credit_cards: int = 0
@export var materials: Dictionary[String, int] = {}
@export var exp_bonus: int = 0
@export var friendship_bonus: int = 0  # raises the worker's Friendship
