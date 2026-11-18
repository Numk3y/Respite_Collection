@tool
class_name EndlessEvent
extends Resource
## An After Hours ❓ Event: a short story card with choices. Data/endless_events/*.tres. See the Endless autoload.
##
## Each choice is a Dictionary:
##   "text": the button, "result": what happens (shown after),
##   "cost_tips": Tips it costs (the choice is greyed out without them),
##   "effects": what it does (below),
##   "chance": 0-1 for a gamble; on a miss "fail_result" / "fail_effects" are used instead.
## Effects: "tips" (+/-), "heal" / "damage" (share of max HP, the squad; damage never knocks out),
## "energy" (share of the Ultimate gauge, the squad), "drink": "common" | "rare" | "legendary" (an offer of 3 of
## that rarity), "hangover": "mild" | "harsh" (a forced pick), "fight": "battle" | "elite", "hire": 1 (a random
## owned friend joins for free), "revive": 1 (the first KO'd friend at 50%).

@export var id: StringName
@export var title: String
@export_multiline var text: String
@export var choices: Array[Dictionary] = []
@export var min_night := 1  # first Night it can show up
@export var needs_ko := false  # only offered while a squad friend is knocked out
@export var enabled := true
