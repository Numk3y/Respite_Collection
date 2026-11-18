extends Node
## After Hours: the endless roguelite mode (PLAN_AFTER_HOURS.md). Autoload name: Endless.
##
## A run starts with 2 owned friends (1 vanguard + 1 rearguard) and climbs Nights: branching maps of FLOORS floors
## whose nodes are Battles, Elites, Events, Rests, Bars and a Boss. HP, KOs and Ultimate gauges carry over. The
## squad grows by hiring owned friends at Bars (no size limit; up to 3 + 3 fight, the rest wait on the bench).
## Drinks (DrinkData, Data/drinks) are power-ups for the rest of the run; strong ones force a Hangover pick.
## A lost battle only ends the run when nobody is left standing. After each boss the squad can Call it a night.
## The end of a run pays Night Tokens (floors, Elites, bosses and leftover Tips), spent in the After Hours shop on
## Recruit Tickets and shop-only gear.
##
## Everything random is seeded from the run's seed and where it happens (_rng), so reloading the game can't reroll
## a map or an offer. Open choices wait in run.pending (a queue, front first) and are saved with the run.
## Save data: GameState.data.endless (see _data / _new_run). Text: Terms "endless_*".

signal changed

const FLOORS := 15  # per Night; the last floor is the boss
const COLUMNS := 7
const PATHS := 6
const NODE_WEIGHTS := {"battle": 45, "event": 22, "elite": 12, "rest": 10, "bar": 8}
const ELITE_FROM_FLOOR := 4  # 0-based: no Elite on the first 4 floors
const NIGHT_ONE_BAR_FLOOR := 3  # Night 1: the 4th floor is all Bars, so a 2-friend squad can hire early
const NIGHT_CHAPTERS := [[1, 2], [3, 4], [5, 6]]  # enemy pools for Nights 1-3; later Nights use every chapter
const NIGHT_LEVELS := [Vector2i(2, 6), Vector2i(8, 12), Vector2i(11, 15)]  # enemy level on floor 1 / the boss
const AFTERPARTY_LEVEL := 15  # Night 4's floor 1; each Afterparty Night starts AFTERPARTY_STEP higher
const AFTERPARTY_STEP := 2
const AFTERPARTY_RAMP := 4  # levels gained across an Afterparty Night
const ELITE_LEVELS := 2
const BOSS_LEVELS := 1

const START_TIPS := 50
const TIPS := {"battle": 20, "elite": 40, "boss": 70}
const WIN_HEAL := 0.1  # everyone standing heals this share of max HP after a won fight
const TWO_WAVES_FROM_FLOOR := 6  # 0-based: Battles from the 7th floor on have two waves
const TIPS_PER_NIGHT := 0.15  # each Night after the first pays this much more
const OFFER_SIZE := 3
## Rarity weights [Common, Rare, Legendary] of a Drink offer after each kind of fight, and at the Bar
const DRINK_WEIGHTS := {"battle": [70, 27, 3], "elite": [0, 85, 15], "boss": [0, 60, 40], "bar": [60, 32, 8]}
const BOSS_DRINK_PICKS := 2
const HANGOVER_RARE_CHANCE := 0.35
const TOLERANCE := 5  # this many Drinks without a Hangover and the next Rare brings one for sure
const REST_HEAL := 0.3
const REVIVE_HP := 0.5
const TRAIN_MULT := 1.1  # Rest: train a friend, +10% HP/Attack/Defense/Speed for the run
const BENCH_HEAL := 0.1  # per node, for friends not fielded
const BOSS_HEAL := 0.25  # when a Night is won
const PRICES := {"drink": [30, 60, 120], "heal": 30, "heal_pct": 0.25, "revive": 60, "cure": [40, 90]}
const HIRE_PRICES := {CharacterData.Rarity.N: 40, CharacterData.Rarity.R: 40, CharacterData.Rarity.SR: 80,
	CharacterData.Rarity.SSR: 150}
const BAR_HIRES := 2
const BAR_DRINKS := 3

const TOKENS := {"floor": 2, "elite": 5, "boss": [20, 30, 40], "afterparty_boss": 50, "tips_per_token": 10,
	"best_bonus": 0.25}
const CRASH_TIPS_SHARE := 0.5  # the share of Tips that converts when the run ends with everyone knocked out
## Paid once per account for winning each Night's boss for the first time (Night 4+ all use the last entry)
const MILESTONES := [
	[["credit_card", 3]],
	[["credit_card", 5]],
	[["credit_card", 8], ["sr_ticket", 1]],
	[["credit_card", 3]],
]
## The After Hours shop (Night Tokens). Tickets have a monthly limit; gear rotates weekly (GEAR_STOCK pieces,
## one of each per week). Materials have no limit.
const SHOP_TICKETS := [{"id": "recruit_ticket", "price": 150, "limit": 10}, {"id": "sr_ticket", "price": 600, "limit": 2}]
const SHOP_MATERIALS := [{"id": "coffee", "amount": 3, "price": 60}, {"id": "gossip", "amount": 1, "price": 45}]
const GEAR_PRICES := {CharacterData.Rarity.SR: 500, CharacterData.Rarity.SSR: 1200}
const GEAR_STOCK := 3

var drinks: Dictionary[StringName, DrinkData] = {}
var events: Array[EndlessEvent] = []
var _pools := {}  # chapter -> {"vanguard": [CharacterData], "rearguard": [...], "bosses": [WaveData]}
var _stage: StageData  # the fight waiting at the front of run.pending (built on demand, not saved)
var _fielded: Array[int] = []  # squad indices of the friends in the battle being played, in engine order

func _ready() -> void:
	for res in _load_all("res://Data/drinks/"):
		var d := res as DrinkData
		if d and d.enabled:
			drinks[d.id] = d
	for res in _load_all("res://Data/endless_events/"):
		var e := res as EndlessEvent
		if e and e.enabled:
			events.append(e)

func _load_all(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for file in ResourceLoader.list_directory(dir_path):
		if file.ends_with(".tres") or file.ends_with(".res"):
			out.append(load(dir_path + file))
	return out

# ───────── Save data ─────────

func _data() -> Dictionary:
	var d: Dictionary = GameState.data.get_or_add("endless", {})
	for key in ["tokens", "best_floor", "best_night", "runs"]:
		if not d.has(key):
			d[key] = 0
	for key in ["milestones", "bought_month", "bought_week", "run", "last_run"]:
		if not d.has(key):
			d[key] = {}
	return d

func _save() -> void:
	GameState.request_save()
	changed.emit()

func tokens() -> int:
	return int(_data().tokens)

func best_floor() -> int:
	return int(_data().best_floor)

func last_run() -> Dictionary:
	return _data().last_run

## Open once the first chapter's boss (1-5) is cleared
func is_open() -> bool:
	var first := DB.get_map(1, StageData.BOSS_NUMBER)
	return first == null or GameState.is_stage_cleared(first.id)

func unlock_code() -> String:
	var first := DB.get_map(1, StageData.BOSS_NUMBER)
	return first.code() if first else "1-5"

func has_run() -> bool:
	return not _data().run.is_empty()

func run() -> Dictionary:
	return _data().run

# ───────── Seeded randomness ─────────

func _rng(tag: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [int(run().get("seed", 0)), tag])
	return rng

static func _pick_weighted(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += int(weights[k])
	var roll := rng.randi_range(1, maxi(total, 1))
	for k in weights:
		roll -= int(weights[k])
		if roll <= 0:
			return k
	return weights.keys()[0]

static func _shuffle(rng: RandomNumberGenerator, list: Array) -> Array:
	var out := list.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out

# ───────── Starting and ending a run ─────────

## Starts a run with one vanguard and one rearguard friend (owned uids)
func start_run(vanguard_uid: int, rearguard_uid: int) -> bool:
	var v := GameState.get_character(vanguard_uid)
	var r := GameState.get_character(rearguard_uid)
	if v == null or r == null or not v.is_vanguard() or r.is_vanguard() or has_run():
		return false
	var d := _data()
	d.run = {
		"seed": randi(), "night": 1, "floor": -1, "node": "", "map": {},
		"squad": [_member(vanguard_uid), _member(rearguard_uid)],
		"lineup": {"vanguard": [0], "rearguard": [1]},
		"drinks": [], "hangovers": [], "since_hangover": 0,
		"tips": START_TIPS, "pending": [], "cleared": 0, "fights": 0,
		"stats": {"battles": 0, "elites": 0, "bosses": 0, "tips_earned": 0, "dealt": {}, "taken": {}, "healed": {}},
	}
	d.run.map = _make_map(1)
	d.runs = int(d.runs) + 1
	GameState.add_stat("endless_runs")
	_save()
	return true

func _member(uid: int) -> Dictionary:
	return {"uid": uid, "hp": 1.0, "energy": 0, "ko": false, "train": false}

## Ends the run: pays Night Tokens and milestone rewards, keeps a summary for the run-over screen.
## `cashed_out`: Call it a night (all Tips convert) rather than everyone knocked out (CRASH_TIPS_SHARE).
func end_run(cashed_out: bool) -> Dictionary:
	var d := _data()
	var r: Dictionary = d.run
	if r.is_empty():
		return {}
	var s: Dictionary = r.stats
	var floors := int(r.cleared)
	var lines := []  # [Terms key, args, tokens]
	lines.append(["endless_tok_floors", {"count": floors}, floors * int(TOKENS.floor)])
	if int(s.elites) > 0:
		lines.append(["endless_tok_elites", {"count": int(s.elites)}, int(s.elites) * int(TOKENS.elite)])
	var boss_tokens := 0
	for i in int(s.bosses):
		boss_tokens += int(TOKENS.boss[i]) if i < TOKENS.boss.size() else int(TOKENS.afterparty_boss)
	if boss_tokens > 0:
		lines.append(["endless_tok_bosses", {"count": int(s.bosses)}, boss_tokens])
	var share := 1.0 if cashed_out else CRASH_TIPS_SHARE
	var tip_tokens := floori(int(r.tips) * share / float(TOKENS.tips_per_token))
	if tip_tokens > 0:
		lines.append(["endless_tok_tips" if cashed_out else "endless_tok_tips_crash", {"tips": int(r.tips)}, tip_tokens])
	var total := 0
	for line in lines:
		total += int(line[2])
	var new_best := floors > int(d.best_floor)
	if new_best and total > 0:
		var bonus := roundi(total * float(TOKENS.best_bonus))
		lines.append(["endless_tok_best", {}, bonus])
		total += bonus
	if new_best:
		d.best_floor = floors
	d.best_night = maxi(int(d.best_night), int(r.night))
	d.tokens = int(d.tokens) + total
	# First-time Night clears
	var rewards := []
	for night in range(1, int(s.bosses) + 1):
		var key := str(night)
		if d.milestones.has(key):
			continue
		d.milestones[key] = true
		var reward: Array = MILESTONES[mini(night - 1, MILESTONES.size() - 1)]
		Daily.grant(reward)
		rewards.append({"night": night, "reward": reward})
	# MVP: most damage over the run
	var mvp := ""
	var best_dealt := 0
	for idx in s.dealt:
		if int(s.dealt[idx]) > best_dealt:
			best_dealt = int(s.dealt[idx])
			var c := member_character(r.squad[int(idx)])
			mvp = c.display_name if c else ""
	var names := []
	for m in r.squad:
		var c := member_character(m)
		if c:
			names.append({"id": String(c.id), "ko": bool(m.ko)})
	d.last_run = {"floors": floors, "night": int(r.night), "cashed_out": cashed_out, "tokens": total,
		"lines": lines, "new_best": new_best, "milestones": rewards, "mvp": mvp, "mvp_dealt": best_dealt,
		"drinks": r.drinks.duplicate(), "hangovers": r.hangovers.duplicate(), "squad": names,
		"tips": int(r.tips), "battles": int(s.battles), "elites": int(s.elites), "bosses": int(s.bosses)}
	d.run = {}
	_stage = null
	GameState.save_game()
	changed.emit()
	return d.last_run

func clear_last_run() -> void:
	_data().last_run = {}
	_save()

# ───────── Nights and the map ─────────

func night_name(night: int = -1) -> String:
	var n := int(run().get("night", 1)) if night < 0 else night
	if n <= NIGHT_CHAPTERS.size():
		return Terms.t("endless_night", {"number": n})
	return Terms.t("endless_afterparty", {"number": n - NIGHT_CHAPTERS.size()})

## Floors climbed over the whole run, counting the one in progress (for headers)
func global_floor() -> int:
	return (int(run().night) - 1) * FLOORS + int(run().floor) + 1

func _chapters(night: int) -> Array:
	if night <= NIGHT_CHAPTERS.size():
		return NIGHT_CHAPTERS[night - 1]
	return DB.chapters().filter(func(c): return c > 0)

## The enemy level on a floor (0-based) of a Night
func enemy_level(night: int, floor: int) -> int:
	var t := float(floor) / float(FLOORS - 1)
	if night <= NIGHT_LEVELS.size():
		var range_v: Vector2i = NIGHT_LEVELS[night - 1]
		return roundi(lerpf(range_v.x, range_v.y, t))
	var start := AFTERPARTY_LEVEL + AFTERPARTY_STEP * (night - NIGHT_LEVELS.size() - 1)
	return roundi(start + AFTERPARTY_RAMP * t)

## A Night's map: PATHS paths walked up from floor 0 (each step to the same or a neighbouring column, never
## crossing another path's edge), then node types rolled by floor (see NODE_WEIGHTS and the rules below), and the
## boss on top. {"nodes": {id: {"floor", "col", "type", "next": [ids]}}, "boss": id}
func _make_map(night: int) -> Dictionary:
	var rng := _rng("map_%d" % night)
	var nodes := {}
	var edges := {}
	var first_col := -1
	for p in PATHS:
		var col := rng.randi_range(0, COLUMNS - 1)
		if p == 1:
			while col == first_col:
				col = rng.randi_range(0, COLUMNS - 1)
		if p == 0:
			first_col = col
		_map_node(nodes, 0, col)
		for f in range(0, FLOORS - 2):
			var next := clampi(col + rng.randi_range(-1, 1), 0, COLUMNS - 1)
			if next != col and edges.has("%d_%d>%d_%d" % [f, next, f + 1, col]):
				next = col  # would cross an edge going the other way
			_map_node(nodes, f + 1, next)
			edges["%d_%d>%d_%d" % [f, col, f + 1, next]] = true
			var links: Array = nodes["%d_%d" % [f, col]].next
			if not links.has("%d_%d" % [f + 1, next]):
				links.append("%d_%d" % [f + 1, next])
			col = next
	var boss_id := "%d_boss" % (FLOORS - 1)
	nodes[boss_id] = {"floor": FLOORS - 1, "col": COLUMNS / 2, "type": "boss", "next": []}
	for id in nodes:
		if int(nodes[id].floor) == FLOORS - 2:
			nodes[id].next = [boss_id]
	_assign_types(nodes, night, rng)
	return {"nodes": nodes, "boss": boss_id}

func _map_node(nodes: Dictionary, floor: int, col: int) -> void:
	var id := "%d_%d" % [floor, col]
	if not nodes.has(id):
		nodes[id] = {"floor": floor, "col": col, "type": "battle", "next": []}

func _assign_types(nodes: Dictionary, night: int, rng: RandomNumberGenerator) -> void:
	var parents := {}
	for id in nodes:
		for n in nodes[id].next:
			parents.get_or_add(n, []).append(id)
	var ids: Array = nodes.keys()
	ids.sort_custom(func(a, b): return int(nodes[a].floor) < int(nodes[b].floor) or (int(nodes[a].floor) == int(nodes[b].floor) and int(nodes[a].col) < int(nodes[b].col)))
	for id in ids:
		var node: Dictionary = nodes[id]
		var f := int(node.floor)
		if node.type == "boss":
			continue
		if f <= 1:
			node.type = "battle"
		elif f == FLOORS - 2:
			node.type = "rest" if rng.randf() < 0.7 else "bar"
		elif night == 1 and f == NIGHT_ONE_BAR_FLOOR:
			node.type = "bar"
		else:
			var type := "battle"
			for attempt in 10:
				type = _pick_weighted(rng, NODE_WEIGHTS)
				if type == "elite" and f < ELITE_FROM_FLOOR:
					continue
				if type in ["elite", "rest", "bar"] and parents.get(id, []).any(func(p): return nodes[p].type == type):
					continue
				if type == "rest" and f == FLOORS - 3:
					continue  # a Rest row comes right after
				if type == "bar" and night == 1 and absi(f - NIGHT_ONE_BAR_FLOOR) == 1:
					continue  # next to Night 1's Bar row
				break
			node.type = type
	# At least one Elite and one Rest in the middle of the Night
	for need in ["elite", "rest"]:
		if ids.any(func(id): return nodes[id].type == need):
			continue
		var spots: Array = ids.filter(func(id): return nodes[id].type == "battle" and int(nodes[id].floor) >= ELITE_FROM_FLOOR and int(nodes[id].floor) < FLOORS - 3)
		if not spots.is_empty():
			nodes[spots[rng.randi_range(0, spots.size() - 1)]].type = need

func map_nodes() -> Dictionary:
	return run().get("map", {}).get("nodes", {})

## Node ids the squad can move to now: the first floor at the start of a Night, else the current node's links.
## Empty while something is still pending.
func reachable() -> Array:
	var r := run()
	if r.is_empty() or not r.pending.is_empty():
		return []
	var nodes := map_nodes()
	if String(r.node).is_empty():
		return nodes.keys().filter(func(id): return int(nodes[id].floor) == 0)
	return nodes[r.node].next.duplicate()

## Moves to a node and opens what's there
func choose_node(id: String) -> bool:
	if not reachable().has(id):
		return false
	var r := run()
	var node: Dictionary = map_nodes()[id]
	r.node = id
	r.floor = int(node.floor)
	r.get_or_add("path", []).append(id)
	_bench_rest()
	match String(node.type):
		"battle", "elite", "boss":
			r.pending.append({"kind": "fight", "fight": node.type})
		"rest":
			r.pending.append({"kind": "rest"})
		"bar":
			r.pending.append(_bar_stock())
		"event":
			var ev := _pick_event()
			if ev:
				r.pending.append({"kind": "event", "id": String(ev.id)})
			else:
				r.pending.append({"kind": "fight", "fight": "battle"})
	_stage = null
	_save()
	return true

## A node is done once its own action resolves (a fight, the Rest choice, leaving the Bar, an Event choice)
func _complete_node() -> void:
	run().cleared = int(run().cleared) + 1

# ───────── The squad ─────────

func member_character(m: Dictionary) -> CharacterData:
	if m.has("guest"):
		return DB.characters.get(StringName(m.guest))
	return GameState.get_character(int(m.get("uid", 0)))

## The squad for the UI: [{index, data, hp (share), ko, fielded, vanguard, train, energy}]
func members() -> Array:
	var out := []
	var r := run()
	if r.is_empty():
		return out
	var fielded: Array = r.lineup.vanguard + r.lineup.rearguard
	for i in r.squad.size():
		var m: Dictionary = r.squad[i]
		var c := member_character(m)
		if c == null:
			continue
		out.append({"index": i, "data": c, "hp": float(m.hp), "ko": bool(m.ko), "fielded": fielded.has(i),
			"vanguard": c.is_vanguard(), "train": bool(m.train), "energy": int(m.energy),
			"level": int(GameState.get_owned(int(m.get("uid", 0))).get("level", 1))})
	return out

func alive_count() -> int:
	return run().get("squad", []).filter(func(m): return not m.ko and member_character(m) != null).size()

func _row_of(i: int) -> String:
	var c := member_character(run().squad[i])
	return "vanguard" if c and c.is_vanguard() else "rearguard"

## Field or bench a friend (up to 3 per row; knocked-out friends can't fight)
func toggle_fielded(i: int) -> bool:
	var r := run()
	if i < 0 or i >= r.squad.size():
		return false
	var row := _row_of(i)
	var list: Array = r.lineup[row]
	if list.has(i):
		list.erase(i)
	elif r.squad[i].ko or list.size() >= FormationBattleEngine.ROW_SIZE:
		return false
	else:
		list.append(i)
	_save()
	return true

## Takes knocked-out friends off the lineup and, if nobody standing is fielded, fields whoever can fight
func _fix_lineup() -> void:
	var r := run()
	for row in ["vanguard", "rearguard"]:
		r.lineup[row] = r.lineup[row].filter(func(i): return i < r.squad.size() and not r.squad[i].ko and member_character(r.squad[i]) != null)
	if (r.lineup.vanguard + r.lineup.rearguard).is_empty():
		for i in r.squad.size():
			var m: Dictionary = r.squad[i]
			if m.ko or member_character(m) == null:
				continue
			var list: Array = r.lineup[_row_of(i)]
			if list.size() < FormationBattleEngine.ROW_SIZE:
				list.append(i)

## Bench friends heal a little at every node they sit out
func _bench_rest() -> void:
	var r := run()
	var heal := BENCH_HEAL * run_mult("bench_heal_mult")
	if heal <= 0.0:
		return
	var fielded: Array = r.lineup.vanguard + r.lineup.rearguard
	for i in r.squad.size():
		var m: Dictionary = r.squad[i]
		if not m.ko and not fielded.has(i):
			m.hp = minf(float(m.hp) + heal, 1.0)

func _heal_squad(share: float) -> void:
	for m in run().squad:
		if not m.ko:
			m.hp = minf(float(m.hp) + share, 1.0)

func _hurt_squad(share: float) -> void:
	for m in run().squad:
		if not m.ko:
			m.hp = maxf(float(m.hp) - share, 0.01)

func _revive_first() -> bool:
	for m in run().squad:
		if m.ko and member_character(m) != null:
			m.ko = false
			m.hp = REVIVE_HP
			return true
	return false

## Adds an owned friend to the squad (fielded if their row has room)
func _add_to_squad(uid: int) -> void:
	var r := run()
	r.squad.append(_member(uid))
	var i: int = r.squad.size() - 1
	var list: Array = r.lineup[_row_of(i)]
	if list.size() < FormationBattleEngine.ROW_SIZE:
		list.append(i)

## Owned friends not in the squad yet
func _hireable() -> Array:
	var have: Array = run().squad.map(func(m): return int(m.get("uid", 0)))
	var out := []
	for o in GameState.data.owned:
		if not have.has(int(o.uid)) and GameState.get_character(int(o.uid)) != null:
			out.append(int(o.uid))
	return out

# ───────── Drinks and Hangovers ─────────

func taken_drinks() -> Array[DrinkData]:
	var out: Array[DrinkData] = []
	for id in run().get("drinks", []) + run().get("hangovers", []):
		var d: DrinkData = drinks.get(StringName(id))
		if d:
			out.append(d)
	return out

## The product of every taken Drink's and Hangover's run effect `key` (1.0 = unchanged)
func run_mult(key: String) -> float:
	var mult := 1.0
	for d in taken_drinks():
		mult *= d.run_mult(key)
	return mult

## An offer of OFFER_SIZE Drinks not taken yet. `weights` = [Common, Rare, Legendary], or `rarity` >= 0 for one rarity.
func _drink_offer(rng: RandomNumberGenerator, weights: Array, rarity: int = -1, count: int = OFFER_SIZE) -> Array:
	var taken: Array = run().drinks
	var by_rarity := [[], [], []]
	for d: DrinkData in drinks.values():
		if not d.hangover and not taken.has(String(d.id)):
			by_rarity[d.rarity].append(String(d.id))
	var out := []
	for i in count:
		var r := rarity
		if r < 0:
			r = int(_pick_weighted(rng, {"0": weights[0], "1": weights[1], "2": weights[2]}))
		# Fall back to a neighbouring rarity when one runs dry
		for step in [0, -1, 1, -2, 2]:
			var k: int = r + step
			if k >= 0 and k <= 2 and not by_rarity[k].filter(func(id): return not out.has(id)).is_empty():
				r = k
				break
		var pool: Array = by_rarity[r].filter(func(id): return not out.has(id))
		if pool.is_empty():
			continue
		out.append(pool[rng.randi_range(0, pool.size() - 1)])
	return out

## Takes a Drink; a Rare may and a Legendary always queues a Hangover pick at the front
func _take_drink(id: String, tag: String) -> void:
	var r := run()
	var d: DrinkData = drinks.get(StringName(id))
	if d == null or r.drinks.has(id):
		return
	r.drinks.append(id)
	r.since_hangover = int(r.since_hangover) + 1
	var severity := -1
	if d.rarity == DrinkData.Rarity.LEGENDARY:
		severity = DrinkData.Severity.HARSH
	elif d.rarity == DrinkData.Rarity.RARE:
		if int(r.since_hangover) > TOLERANCE or _rng("hang_" + tag).randf() < HANGOVER_RARE_CHANCE:
			severity = DrinkData.Severity.MILD
	if severity >= 0:
		var offer := _hangover_offer(severity, tag)
		if not offer.is_empty():
			r.pending.insert(0, offer)

## A forced Hangover pick: up to 3 options of that severity, one per category where possible ({} if none are left)
func _hangover_offer(severity: int, tag: String) -> Dictionary:
	var r := run()
	var rng := _rng("hangover_" + tag)
	var options := []
	var by_cat := {}
	for d: DrinkData in drinks.values():
		if d.hangover and d.severity == severity and not r.hangovers.has(String(d.id)):
			by_cat.get_or_add(int(d.category), []).append(String(d.id))
	for cat in _shuffle(rng, by_cat.keys()):
		var list: Array = by_cat[cat]
		options.append(list[rng.randi_range(0, list.size() - 1)])
	if options.size() < OFFER_SIZE:  # fewer categories left than slots: fill from what remains
		var rest := []
		for cat in by_cat:
			rest.append_array(by_cat[cat].filter(func(id): return not options.has(id)))
		for id in _shuffle(rng, rest):
			if options.size() >= OFFER_SIZE:
				break
			options.append(id)
	if options.is_empty():
		return {}  # every Hangover of that kind is already taken
	r.since_hangover = 0
	return {"kind": "hangover", "options": options.slice(0, OFFER_SIZE), "severity": severity}

## The friend-specific engine rules from every taken Drink and Hangover (plus Rest training)
func _member_rules(c: CharacterData, vanguard: bool, m: Dictionary) -> Dictionary:
	var rules := {}
	for d in taken_drinks():
		if not d.ally_rules.is_empty() and d.applies_to(c.char_class, vanguard):
			rules = FormationBattleEngine.merge_rules(rules, d.ally_rules)
	if m.get("train", false):
		rules = FormationBattleEngine.merge_rules(rules, {"stat_mult": {"hp": TRAIN_MULT, "attack": TRAIN_MULT,
			"defense": TRAIN_MULT, "speed": TRAIN_MULT}})
	return rules

func _enemy_rules() -> Dictionary:
	var rules := {}
	for d in taken_drinks():
		if not d.enemy_rules.is_empty():
			rules = FormationBattleEngine.merge_rules(rules, d.enemy_rules)
	return rules

# ───────── Fights ─────────

## Enemy pools per story chapter: every enemy used on its maps, by row, plus its boss map's boss waves
func _pool(chapter: int) -> Dictionary:
	if _pools.has(chapter):
		return _pools[chapter]
	var pool := {"vanguard": [], "rearguard": [], "bosses": []}
	for s: StageData in DB.stages:
		if s.chapter != chapter:
			continue
		var groups := []
		if s.waves.is_empty():
			groups.append(s.enemy_vanguard + s.enemy_rearguard)
		for w in s.waves:
			if w:
				groups.append(w.enemy_vanguard + w.enemy_rearguard)
				if w.is_boss and s.is_boss():
					pool.bosses.append(w)
		for g in groups:
			for c: CharacterData in g:
				if c == null:
					continue
				var row: Array = pool.vanguard if c.is_vanguard() else pool.rearguard
				if not row.has(c):
					row.append(c)
	_pools[chapter] = pool
	return pool

## The fight at the front of the queue as a map StageData (the same each time it's asked for)
func current_stage() -> StageData:
	var r := run()
	if r.is_empty() or r.pending.is_empty() or r.pending[0].kind != "fight":
		return null
	if _stage == null:
		_stage = _encounter(String(r.pending[0].fight))
	return _stage

func _encounter(kind: String) -> StageData:
	var r := run()
	var night := int(r.night)
	var floor := maxi(int(r.floor), 0)
	var rng := _rng("fight_%d_%s_%d" % [night, r.node, int(r.fights)])
	var chapters := _chapters(night)
	var chapter: int = chapters[rng.randi_range(0, chapters.size() - 1)]
	var stage := StageData.new()
	stage.chapter = chapter
	stage.number = 1
	var level := enemy_level(night, floor) + (ELITE_LEVELS if kind == "elite" else (BOSS_LEVELS if kind == "boss" else 0))
	stage.enemy_level = maxi(level, 1)
	stage.recommended_level = stage.enemy_level
	var waves: Array[WaveData] = []
	# Enemy count follows the squad's size (friends still standing, up to a full team), so a small early squad
	# meets small groups and hiring doesn't make fights easier
	var size := clampi(alive_count(), 1, FormationBattleEngine.ROW_SIZE * 2)
	match kind:
		"elite":
			var count := mini(size + 1 + (1 if night >= 2 else 0), 6)
			waves.append(_random_wave(rng, chapters, mini(ceili(count * 0.6), 3), count - mini(ceili(count * 0.6), 3), true))
			stage.display_name = Terms.t("endless_stage_elite", {"night": night_name()})
		"boss":
			var count := mini(size, 6)
			waves.append(_random_wave(rng, chapters, mini(ceili(count * 0.6), 3), count - mini(ceili(count * 0.6), 3), false))
			var bosses: Array = _pool(chapter).bosses
			if bosses.is_empty():
				waves.append(_random_wave(rng, chapters, 3, 3, true))
			else:
				waves.append(bosses[rng.randi_range(0, bosses.size() - 1)])
			stage.display_name = Terms.t("endless_stage_boss", {"night": night_name()})
		_:
			var count := clampi(size + int(floor >= 6) + (1 if night >= 2 else 0) - int(floor <= 1), 1, 6)
			var front := mini(ceili(count * 0.6), 3)
			var back := count - front
			waves.append(_random_wave(rng, chapters, front, back, false))
			if floor >= TWO_WAVES_FROM_FLOOR:
				waves.append(_random_wave(rng, chapters, front, back, false))
			stage.display_name = Terms.t("endless_stage_battle", {"night": night_name(), "floor": floor + 1})
	stage.waves = waves
	return stage

func _random_wave(rng: RandomNumberGenerator, chapters: Array, front: int, back: int, boss: bool) -> WaveData:
	var van := []
	var rear := []
	for c in chapters:
		var p := _pool(int(c))
		for e in p.vanguard:
			if not van.has(e):
				van.append(e)
		for e in p.rearguard:
			if not rear.has(e):
				rear.append(e)
	var w := WaveData.new()
	for i in front:
		if not van.is_empty():
			w.enemy_vanguard.append(van[rng.randi_range(0, van.size() - 1)])
	for i in back:
		if not rear.is_empty():
			w.enemy_rearguard.append(rear[rng.randi_range(0, rear.size() - 1)])
	if w.enemy_vanguard.is_empty() and not rear.is_empty():
		w.enemy_rearguard.append(rear[0])
	w.is_boss = boss
	return w

## The fielded squad in the shape FormationBattleEngine expects (HP, gauges and Drinks applied)
func battle_team() -> Dictionary:
	_fix_lineup()
	var r := run()
	var team := {"vanguard": [], "rearguard": []}
	_fielded.clear()
	var ids := {}
	for row in ["vanguard", "rearguard"]:
		for i in r.lineup[row]:
			var m: Dictionary = r.squad[i]
			var c := member_character(m)
			if c == null or m.ko:
				continue
			var stats := GameState.get_unit_stats(int(m.uid)) if m.has("uid") else c.stats_at(1)
			var unit := c.battle_unit(stats)
			unit.hp_share = float(m.hp)
			unit.energy = int(m.energy)
			unit.rules = _member_rules(c, row == "vanguard", m)
			team[row].append(unit)
			_fielded.append(i)
			ids[c.id] = true
	team.combos = DB.combos.values().filter(func(combo: ComboData): return combo.is_ready(ids)).map(func(combo: ComboData): return combo.battle_dict())
	return team

func enemy_team() -> Dictionary:
	var enemies := current_stage().get_enemy_team()
	enemies.rules = _enemy_rules()
	return enemies

## After the battle (Combat.finish_sortie): HP and gauges carry back, rewards are queued. Returns the report
## for the results screen.
func finish_battle(result: Dictionary) -> Dictionary:
	var r := run()
	var report := {"endless": true, "won": result.win, "money": 0, "materials": {}, "drops": [], "exp": 0,
		"level_ups": [], "first_clear_cards": 0, "card_drops": 0, "bond_ups": [], "daily_bonus": "",
		"endless_tips": 0, "endless_over": false}
	if r.is_empty() or r.pending.is_empty() or r.pending[0].kind != "fight":
		return report
	var fight: Dictionary = r.pending.pop_front()
	var kind := String(fight.fight)
	r.fights = int(r.fights) + 1
	_stage = null
	var s: Dictionary = r.stats
	var k := 0
	for i in result.units.size():
		if result.units[i].side != 0 or k >= _fielded.size():
			continue
		var idx: int = _fielded[k]
		k += 1
		var st: Dictionary = result.stats[i]
		var m: Dictionary = r.squad[idx]
		m.hp = float(st.hp) / maxf(float(st.max_hp), 1.0)
		m.energy = int(st.energy)
		m.ko = int(st.hp) <= 0
		for key in ["dealt", "taken", "healed"]:
			s[key][str(idx)] = int(s[key].get(str(idx), 0)) + int(st[key])
	s.battles = int(s.battles) + 1
	if result.win:
		var tips := roundi((int(TIPS.get(kind, TIPS.battle)) + int(fight.get("tips", 0)))
			* (1.0 + TIPS_PER_NIGHT * (int(r.night) - 1)) * run_mult("tips_mult"))
		r.tips = int(r.tips) + tips
		s.tips_earned = int(s.tips_earned) + tips
		report.endless_tips = tips
		_heal_squad(WIN_HEAL)
		var tag := "%d_%s_%d" % [int(r.night), r.node, int(r.fights)]
		var picks := BOSS_DRINK_PICKS if kind == "boss" else 1
		for p in picks:
			r.pending.insert(p, {"kind": "drinks", "options": _drink_offer(_rng("drinks_%s_%d" % [tag, p]), DRINK_WEIGHTS.get(kind, DRINK_WEIGHTS.battle)),
				"tag": "%s_%d" % [tag, p]})
		if kind == "elite":
			s.elites = int(s.elites) + 1
		if kind == "boss":
			s.bosses = int(s.bosses) + 1
			_heal_squad(BOSS_HEAL)
			r.pending.insert(picks, {"kind": "night_end"})
		_complete_node()
	elif alive_count() == 0:
		report.endless_over = true
		end_run(false)
		return report
	elif kind == "boss":
		r.pending.insert(0, {"kind": "result", "text": Terms.t("endless_boss_retry")})
		r.pending.insert(1, fight)  # the Night can't be left without beating its boss
	else:
		r.pending.insert(0, {"kind": "result", "text": Terms.t("endless_lost_fight")})
		_complete_node()
	_fix_lineup()
	_save()
	return report

# ───────── Pending choices ─────────

func pending() -> Dictionary:
	var r := run()
	return {} if r.is_empty() or r.pending.is_empty() else r.pending[0]

func _pop() -> void:
	run().pending.pop_front()
	_stage = null

## Drink offer: take one (or skip with id "")
func pick_drink(id: String) -> void:
	var p := pending()
	if p.get("kind") != "drinks" or (not id.is_empty() and not p.options.has(id)):
		return
	_pop()
	if not id.is_empty():
		_take_drink(id, String(p.get("tag", "x")))
	_save()

## Hangover: one of the options must be taken
func pick_hangover(id: String) -> void:
	var p := pending()
	if p.get("kind") != "hangover" or not p.options.has(id):
		return
	_pop()
	run().hangovers.append(id)
	_save()

func dismiss_result() -> void:
	if pending().get("kind") == "result":
		_pop()
		_save()

## Rest: "heal", "revive" (squad index) or "train" (squad index)
func rest(action: String, index: int = -1) -> bool:
	if pending().get("kind") != "rest":
		return false
	var r := run()
	match action:
		"heal":
			_heal_squad(REST_HEAL * run_mult("rest_heal_mult"))
		"revive":
			if index < 0 or index >= r.squad.size() or not r.squad[index].ko:
				return false
			r.squad[index].ko = false
			r.squad[index].hp = REVIVE_HP
		"train":
			if index < 0 or index >= r.squad.size() or r.squad[index].ko or r.squad[index].train:
				return false
			r.squad[index].train = true
		_:
			return false
	_pop()
	_complete_node()
	_fix_lineup()
	_save()
	return true

func rest_heal_share() -> float:
	return REST_HEAL * run_mult("rest_heal_mult")

## After a boss: on to the next Night, or Call it a night (ends the run, all Tips convert)
func night_end(go_on: bool) -> Dictionary:
	if pending().get("kind") != "night_end":
		return {}
	_pop()
	if not go_on:
		return end_run(true)
	var r := run()
	r.night = int(r.night) + 1
	r.floor = -1
	r.node = ""
	r.path = []
	r.map = _make_map(int(r.night))
	_save()
	return {}

## Ends the run now, as if everyone was knocked out (only CRASH_TIPS_SHARE of the Tips convert)
func give_up() -> Dictionary:
	return end_run(false)

# ───────── Events ─────────

func _pick_event() -> EndlessEvent:
	var r := run()
	var has_ko: bool = r.squad.any(func(m): return m.ko)
	var seen: Array = r.get("seen_events", [])
	var pool := events.filter(func(e: EndlessEvent): return int(r.night) >= e.min_night and (has_ko or not e.needs_ko))
	var fresh := pool.filter(func(e: EndlessEvent): return not seen.has(String(e.id)))
	if not fresh.is_empty():
		pool = fresh
	if pool.is_empty():
		return null
	var ev: EndlessEvent = pool[_rng("event_%d_%s" % [int(r.night), r.node]).randi_range(0, pool.size() - 1)]
	seen.append(String(ev.id))
	r.seen_events = seen
	return ev

func event_data(id: String) -> EndlessEvent:
	for e in events:
		if String(e.id) == id:
			return e
	return null

func can_choose(ev: EndlessEvent, i: int) -> bool:
	return int(ev.choices[i].get("cost_tips", 0)) <= int(run().tips)

## Plays an Event choice: pays, rolls a gamble, applies the effects and queues the result (and any fight or offer)
func choose_event(i: int) -> void:
	var p := pending()
	if p.get("kind") != "event":
		return
	var ev := event_data(String(p.id))
	if ev == null or i < 0 or i >= ev.choices.size() or not can_choose(ev, i):
		return
	var r := run()
	var choice: Dictionary = ev.choices[i]
	r.tips = int(r.tips) - int(choice.get("cost_tips", 0))
	var tag := "ev_%d_%s" % [int(r.night), r.node]
	var ok := not choice.has("chance") or _rng(tag).randf() < float(choice.chance)
	var effects: Dictionary = choice.get("effects", {}) if ok else choice.get("fail_effects", {})
	var text: String = choice.get("result", "") if ok else choice.get("fail_result", "")
	_pop()
	_complete_node()
	var queue := [{"kind": "result", "title": ev.title, "text": text, "effects": _effect_lines(effects)}]
	if effects.has("hangover"):
		var offer := _hangover_offer(DrinkData.Severity.HARSH if effects.hangover == "harsh" else DrinkData.Severity.MILD, tag)
		if not offer.is_empty():
			queue.append(offer)
	if effects.has("drink"):
		var rarity := ["common", "rare", "legendary"].find(String(effects.drink))
		queue.append({"kind": "drinks", "options": _drink_offer(_rng(tag + "_drink"), [1, 1, 1], maxi(rarity, 0)), "tag": tag})
	if effects.has("fight"):
		queue.append({"kind": "fight", "fight": String(effects.fight), "tips": int(effects.get("tips", 0))})
	for j in queue.size():
		r.pending.insert(j, queue[j])
	if not effects.has("fight"):
		r.tips = int(r.tips) + int(effects.get("tips", 0))
	if effects.has("heal"):
		_heal_squad(float(effects.heal))
	if effects.has("damage"):
		_hurt_squad(float(effects.damage))
	if effects.has("energy"):
		for m in r.squad:
			var c := member_character(m)
			if c and not m.ko:
				m.energy = mini(int(m.energy) + roundi(c.ultimate_max * float(effects.energy)), c.ultimate_max)
	if effects.has("revive"):
		_revive_first()
	if effects.has("hire"):
		var options := _hireable()
		if not options.is_empty():
			_add_to_squad(options[_rng(tag + "_hire").randi_range(0, options.size() - 1)])
	_save()

func _effect_lines(effects: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if effects.has("tips") and not effects.has("fight"):
		out.append(Terms.t("endless_fx_tips", {"amount": ("%+d" % int(effects.tips))}))
	if effects.has("heal"):
		out.append(Terms.t("endless_fx_heal", {"pct": roundi(float(effects.heal) * 100)}))
	if effects.has("damage"):
		out.append(Terms.t("endless_fx_damage", {"pct": roundi(float(effects.damage) * 100)}))
	if effects.has("energy"):
		out.append(Terms.t("endless_fx_energy", {"pct": roundi(float(effects.energy) * 100)}))
	if effects.has("revive"):
		out.append(Terms.t("endless_fx_revive"))
	if effects.has("hire"):
		out.append(Terms.t("endless_fx_hire"))
	return out

# ───────── The Bar ─────────

func _bar_stock() -> Dictionary:
	var r := run()
	var rng := _rng("bar_%d_%s" % [int(r.night), r.node])
	var items := []
	var bar_mult := run_mult("bar_price_mult")
	for uid in _shuffle(rng, _hireable()).slice(0, BAR_HIRES):
		var c := GameState.get_character(uid)
		items.append({"type": "hire", "uid": uid,
			"price": roundi(int(HIRE_PRICES.get(c.rarity, 80)) * run_mult("hire_price_mult") * bar_mult)})
	for id in _drink_offer(rng, DRINK_WEIGHTS.bar, -1, BAR_DRINKS):
		var d: DrinkData = drinks[StringName(id)]
		items.append({"type": "drink", "id": id, "price": roundi(int(PRICES.drink[d.rarity]) * bar_mult)})
	items.append({"type": "heal", "price": roundi(int(PRICES.heal) * bar_mult)})
	items.append({"type": "revive", "price": roundi(int(PRICES.revive) * bar_mult)})
	for id in r.hangovers:
		var h: DrinkData = drinks.get(StringName(id))
		if h:
			items.append({"type": "cure", "id": id, "price": roundi(int(PRICES.cure[h.severity]) * bar_mult)})
	return {"kind": "bar", "items": items, "cured": false}

## Whether a Bar item can be bought right now
func can_buy(i: int) -> bool:
	var p := pending()
	if p.get("kind") != "bar" or i < 0 or i >= p.items.size():
		return false
	var item: Dictionary = p.items[i]
	if item.get("sold", false) or int(item.price) > int(run().tips):
		return false
	match String(item.type):
		"revive":
			return run().squad.any(func(m): return m.ko)
		"heal":
			return run().squad.any(func(m): return not m.ko and float(m.hp) < 1.0)
		"cure":
			return not p.cured and run().hangovers.has(item.id)
	return true

func buy(i: int) -> bool:
	if not can_buy(i):
		return false
	var r := run()
	var p := pending()
	var item: Dictionary = p.items[i]
	r.tips = int(r.tips) - int(item.price)
	item.sold = true
	match String(item.type):
		"hire":
			_add_to_squad(int(item.uid))
		"drink":
			_take_drink(String(item.id), "bar_%d_%s_%d" % [int(r.night), r.node, i])
		"heal":
			_heal_squad(float(PRICES.heal_pct))
		"revive":
			_revive_first()
		"cure":
			r.hangovers.erase(item.id)
			p.cured = true
	_save()
	return true

## Leaves the Bar. A Hangover bought with a Drink there is waiting in front of it, so it's taken first.
func leave_bar() -> void:
	var r := run()
	for i in r.pending.size():
		if r.pending[i].get("kind") == "bar":
			r.pending.remove_at(i)
			break
	_complete_node()
	_save()

# ───────── The After Hours shop (Night Tokens) ─────────

func _month() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d.year) * 12 + int(d.month)

func _bought(kind: String, id: String) -> int:
	var d := _data()
	var key := "bought_" + kind
	var period := _month() if kind == "month" else Daily.this_week()
	if int(d[key].get("_period", -1)) != period:
		d[key] = {"_period": period}
	return int(d[key].get(id, 0))

func _mark_bought(kind: String, id: String) -> void:
	_bought(kind, id)
	var d: Dictionary = _data()["bought_" + kind]
	d[id] = int(d.get(id, 0)) + 1

## This week's gear: GEAR_STOCK shop-only pieces picked by the week number
func gear_stock() -> Array[EquipmentData]:
	var all: Array = DB.equipment.values().filter(func(e: EquipmentData): return e.shop_only)
	all.sort_custom(func(a, b): return String(a.id) < String(b.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("after_hours_gear_%d" % Daily.this_week())
	var out: Array[EquipmentData] = []
	out.assign(_shuffle(rng, all).slice(0, GEAR_STOCK))
	return out

func gear_price(e: EquipmentData) -> int:
	return int(GEAR_PRICES.get(e.rarity, 500))

func ticket_left(item: Dictionary) -> int:
	return int(item.limit) - _bought("month", String(item.id))

func gear_left(e: EquipmentData) -> int:
	return 1 - _bought("week", String(e.id))

func buy_ticket(i: int) -> bool:
	var item: Dictionary = SHOP_TICKETS[i]
	if ticket_left(item) <= 0 or tokens() < int(item.price):
		return false
	_data().tokens = tokens() - int(item.price)
	_mark_bought("month", String(item.id))
	GameState.add_tickets(String(item.id), 1)
	GameState.save_game()
	changed.emit()
	return true

func buy_material(i: int) -> bool:
	var item: Dictionary = SHOP_MATERIALS[i]
	if tokens() < int(item.price):
		return false
	_data().tokens = tokens() - int(item.price)
	GameState.add_material(String(item.id), int(item.amount))
	GameState.save_game()
	changed.emit()
	return true

func buy_gear(e: EquipmentData) -> bool:
	if not gear_stock().has(e) or gear_left(e) <= 0 or tokens() < gear_price(e):
		return false
	_data().tokens = tokens() - gear_price(e)
	_mark_bought("week", String(e.id))
	GameState.add_equipment(e)
	GameState.save_game()
	changed.emit()
	return true
