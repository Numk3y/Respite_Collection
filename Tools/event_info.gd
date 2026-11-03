extends Node
## Prints an event's server settings as one JSON line, for server/boss_admin.ps1 (which starts the event with them).
## Run from the Respite_Collection folder:
##   Godot_v4.7.2-stable_win64.exe --headless --path . res://Tools/event_info.tscn -- <event id>
## Output line: EVENT_JSON {"boss_key": ..., "max_hp": ..., "hours": ..., "attempts_per_day": ..., "max_hit": ...}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var event: EventData = DB.events.get(StringName(args[0])) if not args.is_empty() else null
	if event == null:
		printerr("No event '%s'. Events are folders in Data/events/ with an event.tres; found: %s" % [
			args[0] if not args.is_empty() else "", ", ".join(DB.events.keys())])
		get_tree().quit(1)
		return
	var problems := PackedStringArray()
	if event.missions.is_empty():
		problems.append("it has no missions")
	if event.reward_all == null or event.reward_all.is_empty():
		problems.append("reward_all is empty")
	for s in event.missions:
		if s and DB.get_stage(s.id):
			problems.append("mission %s is also in Data/stages/ (it would show up in the story too)" % s.id)
	for p in problems:
		print("WARNING: %s %s" % [event.id, p])
	print("EVENT_JSON " + JSON.stringify({
		"boss_key": String(event.id), "max_hp": event.boss_hp, "hours": event.hours,
		"attempts_per_day": event.attempts_per_day, "max_hit": event.damage_cap(),
		"name": event.display_name, "missions": event.missions.size(),
	}))
	get_tree().quit()
