extends Node
## The Arena: fight other players' saved teams for rating (Elo) on the World Boss server. Autoload name: Arena
## Each player's Team 1 is their defense team; it's sent to the server before every attack, so it stays current.
## The fight is played here like a story battle (live, Ultimates by hand if Auto is off) against the opponent's
## team rebuilt from what they sent: the same friends with the stats they had. When fewer than 3 real players are
## near your rating, practice bots made here fill the list (they move the rating less).
## Server account: the same one as the World Boss (WorldBoss.register). Fights that can't be reported right away
## wait in the save (data.arena.pending) and are sent later, like boss fights.

const MIN_ACCOUNT_LEVEL := 5
const WIN_MONEY := 600
const LOSS_MONEY := 150
const BOT_ID := "bot"
const BOT_NAMES := ["Sparring Dummy", "Training Bot", "Practice Squad", "Mirror Match"]

var last_state := {}  # the last GET /arena answer's data ({me, top, players}), for the Home tile

func _save() -> Dictionary:
	var d: Dictionary = GameState.data.get_or_add("arena", {})
	if not d.has("pending"):
		d.pending = []
	return d

func is_unlocked() -> bool:
	return GameState.get_account_level() >= MIN_ACCOUNT_LEVEL

# ───────── Team snapshots ─────────

## Team 1 the way other players will fight it: [{id, row, level, ascension, stats}]
func team_snapshot() -> Array:
	var out := []
	for slot in GameState.TEAM_SLOTS:
		var uid := GameState.team_uid(slot)
		var c := GameState.get_character(uid)
		if c == null:
			continue
		var o := GameState.get_owned(uid)
		out.append({"id": String(c.id), "row": "vanguard" if GameState.is_vanguard_slot(slot) else "rearguard",
			"level": int(o.level), "ascension": int(o.get("ascension", 0)), "stats": GameState.get_team_unit_stats(uid)})
	return out

## An opponent's snapshot as an enemy team for the battle engine. Friends this build doesn't know are left out,
## stats are clamped to sane numbers.
func enemy_team(snapshot: Array) -> Dictionary:
	var team := {"vanguard": [], "rearguard": [], "boss": false, "banner": ""}
	for entry in snapshot:
		if not (entry is Dictionary):
			continue
		var c: CharacterData = DB.characters.get(StringName(str(entry.get("id", ""))))
		if c == null:
			continue
		var given: Dictionary = entry.get("stats", {}) if entry.get("stats") is Dictionary else {}
		var stats := c.stats_at(clampi(int(entry.get("level", 1)), 1, GameState.MAX_LEVEL), clampi(int(entry.get("ascension", 0)), 0, GameState.MAX_ASCENSION))
		for stat in CharacterData.STATS:
			if given.has(stat):
				stats[stat] = clampi(int(given[stat]), -50, 99999)
		stats.hp = maxi(stats.hp, 1)
		stats.speed = maxi(stats.speed, 1)
		var row := "vanguard" if c.is_vanguard() else "rearguard"
		if team[row].size() < GameState.VANGUARD_SLOTS:
			team[row].append(c.battle_unit(stats))
	return team

## Portrait list for an opponent card: CharacterData for every known friend in a snapshot
func snapshot_characters(snapshot: Array) -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for entry in snapshot:
		if entry is Dictionary:
			var c: CharacterData = DB.characters.get(StringName(str(entry.get("id", ""))))
			if c:
				out.append(c)
	return out

## A practice team near the player's own strength: random recruitable friends at the team's average level
func make_bot(seed_value: int, rating: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var members := GameState.team_members()
	var levels := 0
	for uid in members:
		levels += int(GameState.get_owned(uid).level)
	var level := maxi(roundi(float(levels) / maxi(members.size(), 1)), 1)
	var pool: Array = DB.characters.values().filter(func(c): return c.enabled and c.rarity >= CharacterData.Rarity.R \
		and _recruitable(c))
	var front: Array = pool.filter(func(c): return c.is_vanguard())
	var back: Array = pool.filter(func(c): return not c.is_vanguard())
	var snapshot := []
	var size := clampi(members.size(), 3, GameState.TEAM_SLOTS)
	for i in size:
		var from: Array = front if i % 2 == 0 else back
		if from.is_empty():
			continue
		var c: CharacterData = from.pop_at(rng.randi_range(0, from.size() - 1))
		snapshot.append({"id": String(c.id), "row": "vanguard" if c.is_vanguard() else "rearguard", "level": level,
			"ascension": 0, "stats": c.stats_at(level)})
	return {"player_id": BOT_ID, "name": BOT_NAMES[rng.randi_range(0, BOT_NAMES.size() - 1)], "rating": rating,
		"power": 0, "team": snapshot, "bot": true}

func _recruitable(c: CharacterData) -> bool:
	for pool in DB.pools:
		if pool.beginner:
			continue
		for entry in pool.entries:
			if entry.character == c:
				return true
	return false

# ───────── Server ─────────

## {"ok", "status", "data": {me, top, players}}. Reports waiting fights first.
func fetch_state() -> Dictionary:
	await submit_pending()
	var r := await WorldBoss.call_server(HTTPClient.METHOD_GET, "/arena")
	if r.ok:
		last_state = r.data
	return r

## Sends Team 1 as the defense team
func upload_team() -> bool:
	var r := await WorldBoss.call_server(HTTPClient.METHOD_POST, "/arena/team",
		{"team": team_snapshot(), "power": GameState.team_power()})
	return r.ok

## Three opponents: real players near the rating, then bots to fill. [] if the server can't be reached.
func fetch_opponents() -> Array:
	await upload_team()  # a brand-new arena player needs a team on the server before they can be matched
	var r := await WorldBoss.call_server(HTTPClient.METHOD_GET, "/arena/opponents")
	if not r.ok:
		return []
	var out: Array = r.data.get("opponents", [])
	var rating := int(last_state.get("me", {}).get("rating", 1000)) if last_state.get("me") is Dictionary else 1000
	var day_seed := Daily.today() * 31 + out.size()
	while out.size() < 3:
		out.append(make_bot(day_seed + out.size() * 977, rating))
	return out

## Uses up one of today's fights. {"ok", "status", "data": {fight_id, seed, fights_left}}
func start_fight(opponent: Dictionary) -> Dictionary:
	await upload_team()
	return await WorldBoss.call_server(HTTPClient.METHOD_POST, "/arena/start", {"opponent_id": str(opponent.player_id)})

## Keeps the result in the save until the server has it. Returns {rating, change, wins, losses} or {} for later.
func report_fight(fight_id: String, win: bool) -> Dictionary:
	_save().pending.append({"fight_id": fight_id, "win": win})
	GameState.save_game()
	return await submit_pending(fight_id)

var _submitting := false

func submit_pending(wanted: String = "") -> Dictionary:
	if _submitting:
		return {}
	_submitting = true
	var answer := {}
	var pending: Array = _save().pending
	for fight in pending.duplicate():
		var r := await WorldBoss.call_server(HTTPClient.METHOD_POST, "/arena/submit", fight)
		if r.status == 0 or r.status >= 500 or r.status == 426:
			break
		pending.erase(fight)
		if r.ok and str(fight.fight_id) == wanted:
			answer = r.data
	GameState.save_game()
	_submitting = false
	return answer

# ───────── Rewards ─────────

## Money for a finished arena fight (win or lose), and the lifetime counters the missions use
func grant(win: bool) -> int:
	var money := WIN_MONEY if win else LOSS_MONEY
	GameState.add_money(money)
	GameState.add_stat("arena_battles")
	if win:
		GameState.add_stat("arena_wins")
	return money
