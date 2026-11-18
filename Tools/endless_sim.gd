extends Node
## After Hours auto-play check: plays whole runs with a simple bot and prints how far they get.
## Run from the Respite_Collection folder (prints, then quits):
##   Godot_v4.7.2-stable_win64.exe --headless --path . res://Tools/endless_sim.tscn -- [runs] [level] [ids...]
## Defaults: 20 runs, friends at Lv.40, the benchmark four plus a few hires. It plays on a throwaway save in
## memory, but ending a run calls GameState.save_game(): back up and restore the desktop save around it.

const DEFAULT_IDS := ["ami", "kai", "mika", "nana", "goodname", "erik", "storm", "globox"]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var runs := int(args[0]) if args.size() > 0 else 20
	var level := int(args[1]) if args.size() > 1 else 40
	var ids: Array = Array(args.slice(2)) if args.size() > 2 else DEFAULT_IDS
	GameState.data = GameState._new_save()
	for id in ids:
		var c: CharacterData = DB.characters.get(StringName(id))
		if c:
			var o := GameState.add_character(c)
			o.level = level
	GameState.mark_stage_cleared(DB.get_map(1, 5).id)
	var engine := FormationBattleEngine.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var floors := []
	var nights := []
	var tokens := []
	var t0 := Time.get_ticks_msec()
	var deaths := {}  # fight kind -> runs that ended there
	var verbose := runs <= 10
	for run_i in runs:
		var owned: Array = GameState.data.owned
		var van: Array = owned.filter(func(o): return GameState.get_character(int(o.uid)).is_vanguard())
		var rear: Array = owned.filter(func(o): return not GameState.get_character(int(o.uid)).is_vanguard())
		Endless.start_run(int(van[0].uid), int(rear[0].uid))
		var guard := 0
		while Endless.has_run() and guard < 2000:
			guard += 1
			var p := Endless.pending()
			if p.is_empty():
				var options := Endless.reachable()
				if options.is_empty():
					push_error("stuck: nothing reachable, nothing pending")
					break
				Endless.choose_node(options[rng.randi_range(0, options.size() - 1)])
				continue
			match String(p.kind):
				"fight":
					var kind := String(p.fight)
					var where := "%s floor %d" % [Endless.night_name(), int(Endless.run().floor) + 1]
					var enemies := Endless.enemy_team()
					var count := 0
					for w in enemies.waves:
						count += w.vanguard.size() + w.rearguard.size()
					var result := engine.simulate(Endless.battle_team(), enemies, rng, true)
					Endless.finish_battle(result)
					if not Endless.has_run():
						deaths[kind] = int(deaths.get(kind, 0)) + 1
						if verbose:
							print("   died: %s at %s vs %d enemies Lv.%d" % [kind, where, count, Endless.enemy_level(1, 0)])
				"drinks":
					Endless.pick_drink(p.options[0] if not p.options.is_empty() else "")
				"hangover":
					Endless.pick_hangover(p.options[0])
				"rest":
					var ko := Endless.members().filter(func(m): return m.ko)
					if not ko.is_empty():
						Endless.rest("revive", ko[0].index)
					else:
						Endless.rest("heal")
				"bar":
					for i in p.items.size():
						if p.items[i].type in ["hire", "revive"] and Endless.can_buy(i):
							Endless.buy(i)
					for i in p.items.size():
						if p.items[i].type == "drink" and Endless.can_buy(i):
							Endless.buy(i)
					if Endless.pending().get("kind") == "bar":
						Endless.leave_bar()
				"event":
					var ev := Endless.event_data(p.id)
					var pick := 0
					while pick < ev.choices.size() - 1 and not Endless.can_choose(ev, pick):
						pick += 1
					Endless.choose_event(pick)
				"result":
					Endless.dismiss_result()
				"night_end":
					Endless.night_end(true)
				_:
					push_error("unknown pending %s" % p.kind)
					break
		var last := Endless.last_run()
		floors.append(int(last.get("floors", 0)))
		nights.append(int(last.get("night", 0)))
		tokens.append(int(last.get("tokens", 0)))
		print("run %2d: floor %3d, %s, squad %d, drinks %d, hangovers %d, tokens %d" % [run_i + 1, last.floors,
			Endless.night_name(int(last.night)), last.squad.size(), last.drinks.size(), last.hangovers.size(), last.tokens])
	print("runs ended at: ", deaths)
	floors.sort()
	print("\nfloors: median %d  min %d  max %d   tokens median %d   (%d runs, Lv.%d, %.1fs)" % [floors[floors.size() / 2],
		floors[0], floors[-1], tokens[tokens.size() / 2], runs, level, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()
