extends Node
## Save data: money, materials, owned friends, gear and teams. Autoload name: GameState

signal money_changed(value: int)
signal materials_changed
signal roster_changed  # owned friends, team or gear changed
signal gear_changed  # gear crafted, upgraded or scrapped, or Parts changed (gear that's gained also fires roster_changed)
signal credit_cards_changed(value: int)
signal account_changed  # account level or account EXP changed
signal stats_changed  # a lifetime counter (data.stats) or beginner mission state changed

# On the web, user:// is an IndexedDB-backed folder that every Godot game on the same site shares
# (all GitHub Pages projects of one account are the same site), so keep the save in our own subfolder.
const SAVE_DIR := "user://respite_collection/"
const SAVE_FILE := "save.json"
const BACKUP_FILE := "save.bak.json"
const TMP_FILE := "save.tmp.json"
# Older save locations, checked when there's no save in SAVE_DIR yet: the folder used while the
# game was called Friend Fleet, then desktop builds from before the web switch
const LEGACY_SAVE_DIRS := ["user://friend_fleet/", "user://"]
const SAVE_VERSION := 4
const TEAM_COUNT := 4
const TEAM_SLOTS := 6
const VANGUARD_SLOTS := 3  # slots 0-2 are vanguard, 3-5 rearguard
const STARTER_EQUIPMENT := [&"foam_bat", &"hoodie", &"lucky_charm"]
# Gear (the Workshop tab): scrap unwanted gear into Parts, spend Parts + Money to craft a chosen piece (any piece a
# cleared map drops) or to upgrade one, +1 at a time up to GEAR_MAX_PLUS. Crafting costs about 4 scraps of the same
# rarity, so farming a drop stays the quicker way and crafting is the way past bad luck.
const GEAR_MAX_PLUS := 5
const GEAR_SCRAP_PARTS := {CharacterData.Rarity.R: 1, CharacterData.Rarity.SR: 5, CharacterData.Rarity.SSR: 20}
const GEAR_CRAFT_PARTS := {CharacterData.Rarity.R: 4, CharacterData.Rarity.SR: 20, CharacterData.Rarity.SSR: 80}
const GEAR_CRAFT_MONEY := {CharacterData.Rarity.R: 200, CharacterData.Rarity.SR: 1000, CharacterData.Rarity.SSR: 4000}
# Going from +(n-1) to +n costs n times these
const GEAR_UPGRADE_PARTS := {CharacterData.Rarity.R: 1, CharacterData.Rarity.SR: 3, CharacterData.Rarity.SSR: 10}
const GEAR_UPGRADE_MONEY := {CharacterData.Rarity.R: 100, CharacterData.Rarity.SR: 400, CharacterData.Rarity.SSR: 1500}
const GEAR_SCRAP_REFUND := 0.5  # share of the Parts spent on upgrades that scrapping gives back
# Which rarity a battle drop is: weights between the rarities on the map's drop list (see Combat._roll_drop)
const GEAR_DROP_WEIGHTS := {CharacterData.Rarity.R: 70, CharacterData.Rarity.SR: 26, CharacterData.Rarity.SSR: 4}
const FREE_FRIENDS := [&"coconutbird_caster"]  # everyone owns these: new accounts with their starter, older saves on load
const MAX_LEVEL := 50
# Friends can't go more than this many levels above the account level (and never past MAX_LEVEL), so Money and
# materials can't push the team far ahead of the story: about Lv.15 / 20 / 26 at the end of Chapters 1 / 2 / 3,
# and the full Lv.50 from account Lv.40
const LEVEL_CAP_ABOVE_ACCOUNT := 10
const GROWTH_PER_LEVEL := 0.04  # each level adds 4% of the level-1 base stats
const GOLD_PER_EXP := 2  # Money cost of 1 EXP when levelling up with Money
const MATERIAL_EXP := {"snack": 60, "coffee": 200, "gossip": 500}  # EXP one of each material gives when fed
## Bond: Friendship (stored as "affection") needed for each Bond level; each level adds BOND_STAT_BONUS to
## ASCENSION_STATS. Friends gain Friendship by fighting (win or lose) and by finishing commission shifts.
const BOND_THRESHOLDS := [0, 20, 60, 120, 200, 300]  # Bond 0..5
const BOND_STAT_BONUS := 0.02
const BOND_PER_WIN := 3
const BOND_PER_LOSS := 1
const BOND_PER_SHIFT := 5
const PULL_HISTORY_MAX := 50
const MAX_ASCENSION := 4  # each duplicate pulled raises Ascension by 1
const ASCENSION_BONUS := 0.05  # +5% per rank to the stats below
const ASCENSION_STATS := ["hp", "attack", "defense", "speed"]
const ASCENSION_OVERFLOW_MONEY := 100  # a copy pulled after max Ascension turns into this much Money
const CREDIT_CARDS_PER_PULL := 1  # every pull costs this many Credit Cards on top of the Money cost
const FIRST_CLEAR_CREDIT_CARDS := 2  # for winning on a map for the first time (that's also its ★1)
const STAR_CREDIT_CARDS := 1  # for each ★2 / ★3 earned on a map for the first time
const STAR_COUNT := 3
# Tutorial steps (data.tutorial): point at Battle on Home, then at Battle on the map screen, then the guided first
# fight (manual Ultimates), then the free Beginner recruit, then at Beginner Missions on Home; DONE once finished
# or skipped
enum Tutorial { HOME_BATTLE, MAP_GO, FIRST_FIGHT, RECRUIT, MISSIONS, DONE }
const ANIMATRONIC_WAVE_CHANCE := 0.03  # 3% chance per sortie that the animatronics replace wave 2
const ANIMATRONIC_CREDIT_CARDS := 1  # for clearing the animatronic wave
# Account level: raised by account EXP from battle wins; it raises the team cost limit.
# Planned for a 7-chapter story: first clears alone reach about Lv.5 / 10 / 16 / 24 / 32 / 41 / 50 at the end of
# Chapters 1-7 (if each chapter's maps give ~600-700 more total EXP than the one before: Ch4 ~1300, Ch5 ~1900,
# Ch6 ~2600, Ch7 ~3400); Lv.50-60 is endgame grinding.
const ACCOUNT_MAX_LEVEL := 60
# Account EXP for a win, from the map's exp_reward: the first win on a map gives a lot, every repeat only a
# tiny share (at least 1)
const ACCOUNT_FIRST_CLEAR_MULT := 3
const ACCOUNT_REPEAT_SHARE := 0.1
# Team cost: every friend costs points by rarity and a team's total can't go over the limit.
# The limit starts at TEAM_COST_BASE and gains 1 at each account level in TEAM_COST_STEPS: quickly at first
# (every 2 levels up to 38 at Lv.16, the end of Chapter 3), then slower and slower up to TEAM_COST_CAP at Lv.60.
#   Lv.1  30: 4 SR + 2 R, or 1 SSR + 1 SR + 4 R        Lv.10 35: 2 SSR + 1 SR + 3 R
#   Lv.16 38: 2 SSR + 2 SR + 2 R                         Lv.21 39: 3 SSR + 3 R
#   Lv.38 42: 3 SSR + 1 SR + 2 R                         Lv.51 44: 2 SSR + 4 SR
#   Lv.60 45: 3 SSR + 2 SR + 1 R, the best team there is (3 SSR + 3 SR = 48 and 4 SSR + 2 R = 46 never fit)
const TEAM_COST := {CharacterData.Rarity.N: 3, CharacterData.Rarity.R: 3, CharacterData.Rarity.SR: 6, CharacterData.Rarity.SSR: 10}
const TEAM_COST_BASE := 30
const TEAM_COST_STEPS := [2, 4, 6, 8, 10, 12, 14, 16, 21, 26, 32, 38, 44, 51, 60]  # gaps: 2 x8, then 5 5 6 6 6 7 9
const TEAM_COST_CAP := TEAM_COST_BASE + 15  # one point per entry in TEAM_COST_STEPS

var data: Dictionary = {}
var _save_queued := false

func _ready() -> void:
	if not load_game():
		data = _new_save()
	_fix_team_rows()
	# Save shortly after every change. A browser tab can be closed at any moment and gives
	# no reliable warning, so don't sit on unsaved changes until the next autosave.
	money_changed.connect(func(_value): request_save())
	materials_changed.connect(request_save)
	roster_changed.connect(request_save)
	gear_changed.connect(request_save)
	credit_cards_changed.connect(func(_value): request_save())
	account_changed.connect(request_save)
	_grant_free_friends()
	var autosave := Timer.new()
	autosave.wait_time = 30.0
	autosave.autostart = true
	autosave.timeout.connect(save_game)
	add_child(autosave)

## Queue one save at the end of this frame; many changes in one frame (e.g. a 10-pull) cost one write
func request_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_flush_save.call_deferred()

func _flush_save() -> void:
	_save_queued = false
	save_game()

## False when the browser won't keep data between visits (private windows, blocked storage).
## Saving still works for the current session but is gone once the tab closes.
func is_storage_persistent() -> bool:
	return OS.is_userfs_persistent()

func _new_save() -> Dictionary:
	var teams := []
	for i in TEAM_COUNT:
		teams.append(_empty_team())
	return {
		"version": SAVE_VERSION,
		"money": 2500,
		"credit_cards": 0,
		"account_level": 1,
		"account_exp": 0,
		"cleared_stages": {},  # stage_id -> true once won there (first-clear bonus already given)
		"stage_stars": {},  # stage_id -> stars earned as bits (1 = ★1 win, 2 = ★2 nobody down, 4 = ★3 the map's goal)
		"materials": {},
		"owned": [],  # [{uid, char_id, level, exp, affection, locked, obtained_at, equips}]
		"next_uid": 1,
		"equipment": [],  # [{uid, equip_id, plus}]; older saves have no "plus" (= +0)
		"next_equip_uid": 1,
		"gear_parts": 0,  # from scrapping gear; spent in the Workshop
		"teams": teams,  # each team is 6 uids, 0 = empty slot
		"pity": {},  # pool_id -> pulls since the last SSR
		"pull_history": [],  # newest last, at most PULL_HISTORY_MAX: {char_id, rarity, pool, time}
		"starter_chosen": false,
		"commissions": {},  # commission_id -> {"uid", "started_at"}; see Commissions autoload
		# World boss: the server account, fights not yet reported, results whose event isn't in this build; see WorldBoss
		"world_boss": {"player_id": "", "token": "", "name": "", "pending": [], "unclaimed": []},
		"settings": {},
		"stats": {},  # lifetime counters: "pulls", "manual_ultimates", "commissions"
		"tutorial": Tutorial.HOME_BATTLE,
		# See BeginnerMissions; pool_pulled = the one free Beginner pool pull is used (Gacha.beginner_pull)
		"beginner": {"claimed": {}, "ssr_claimed": false, "pool_pulled": false},
	}

func _empty_team() -> Array:
	var team := []
	team.resize(TEAM_SLOTS)
	team.fill(0)
	return team

func _empty_equips() -> Dictionary:
	var equips := {}
	for key in EquipmentData.SLOT_KEYS:
		equips[key] = 0
	return equips

# Write a temp file first, then swap it in, so a crash mid-save can't corrupt the save.
# On the web, Godot copies user:// to IndexedDB on the next frame after a file is written.
func save_game() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_DIR + TMP_FILE, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open(SAVE_DIR)
	if dir.file_exists(SAVE_FILE):
		if dir.file_exists(BACKUP_FILE):
			dir.remove(BACKUP_FILE)
		dir.rename(SAVE_FILE, BACKUP_FILE)
	dir.rename(TMP_FILE, SAVE_FILE)

func load_game() -> bool:
	var paths := [SAVE_DIR + SAVE_FILE, SAVE_DIR + BACKUP_FILE]
	for dir in LEGACY_SAVE_DIRS:
		paths.append_array([dir + SAVE_FILE, dir + BACKUP_FILE])
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = _migrate(parsed)
			return true
		push_warning("Save file is corrupted: %s" % path)
	return false

# ───────── Backup export / import ─────────
# Browser storage can be wiped (clearing site data, Safari dropping data for sites not visited in a while),
# so players can keep a copy of their save as a file and restore it, also on another device.

func export_text() -> String:
	return JSON.stringify(data, "\t")

## Replaces the current save with a backup. Returns "" on success, otherwise a reason for the player.
func import_text(text: String) -> String:
	var json := JSON.new()  # unlike JSON.parse_string, doesn't log an engine error for bad input
	var parsed = json.data if json.parse(text.strip_edges()) == OK else null
	if not (parsed is Dictionary and parsed.has("owned") and parsed.has("money")):
		return Terms.t("backup_invalid")
	data = _migrate(parsed)
	_fix_team_rows()
	_grant_free_friends()
	save_game()
	roster_changed.emit()
	money_changed.emit(get_money())
	materials_changed.emit()
	credit_cards_changed.emit(get_credit_cards())
	account_changed.emit()
	return ""

## Starts over from a brand-new save. The old save is kept as the backup file until the next save overwrites it.
func reset_save() -> void:
	data = _new_save()
	save_game()
	roster_changed.emit()
	money_changed.emit(get_money())
	materials_changed.emit()
	credit_cards_changed.emit(get_credit_cards())
	account_changed.emit()

# Upgrade older save formats here whenever the format changes
func _migrate(d: Dictionary) -> Dictionary:
	var version := int(d.get("version", 1))
	# Saves before v4 called teams "fleets"
	var old_key := "fl" + "eets"  # split so a project-wide rename can't change it
	if d.has(old_key):
		d.teams = d[old_key]
		d.erase(old_key)
	# The patrol system and its background timer are gone; drop what it stored
	for key in ["idle_stage_id", "last_tick", "expeditions"]:
		d.erase(key)
	if d.has("settings"):
		d.settings.erase("minimize_on_close")
	if version < 2:
		# v1 teams were plain uid lists: the first 3 become vanguard, the rest rearguard
		var teams := []
		for old in d.get("teams", []):
			var team := _empty_team()
			for i in mini(old.size(), TEAM_SLOTS):
				team[i] = int(old[i])
			teams.append(team)
		d.teams = teams
	# Saves from before the tutorial: anyone who already picked a starter has seen the game
	# (and the Beginner pool is for new players only)
	if not d.has("tutorial") and d.get("starter_chosen", false):
		d.tutorial = Tutorial.DONE
		d.beginner = {"claimed": {}, "ssr_claimed": false, "pool_pulled": true}
	# The Testing Pool became the Common Pool: keep its pity count and history
	var pity: Dictionary = d.get("pity", {})
	if pity.has("friend_pool"):
		pity["common_pool"] = int(pity.get("common_pool", 0)) + int(pity["friend_pool"])
		pity.erase("friend_pool")
	for pull in d.get("pull_history", []):
		if pull.get("pool", "") == "friend_pool":
			pull.pool = "common_pool"
	var fresh := _new_save()
	for key in fresh:
		if not d.has(key):
			d[key] = fresh[key]
	while d.teams.size() < TEAM_COUNT:
		d.teams.append(_empty_team())
	for o in d.owned:
		if not o.has("equips"):
			o.equips = _empty_equips()
		if not o.has("ascension"):
			o.ascension = 0
	if version < 3:
		_merge_duplicates(d)
	d.version = SAVE_VERSION
	return d

## Saves from before Ascension can hold several copies of one friend. Keep the highest-level copy,
## turn each extra copy into an Ascension rank (or Money past the max), and point team slots at the kept copy.
## Gear worn by a removed copy simply goes back to the inventory.
func _merge_duplicates(d: Dictionary) -> void:
	var by_level: Array = d.owned.duplicate()
	by_level.sort_custom(func(a, b): return int(a.level) > int(b.level) or (int(a.level) == int(b.level) and int(a.uid) < int(b.uid)))
	var kept := {}  # char_id -> owned entry
	var replaced_by := {}  # removed uid -> kept uid
	for o in by_level:
		if not kept.has(o.char_id):
			kept[o.char_id] = o
			continue
		var keeper: Dictionary = kept[o.char_id]
		if int(keeper.ascension) < MAX_ASCENSION:
			keeper.ascension = int(keeper.ascension) + 1
		else:
			d.money = int(d.money) + ASCENSION_OVERFLOW_MONEY
		replaced_by[int(o.uid)] = int(keeper.uid)
	d.owned = d.owned.filter(func(o): return not replaced_by.has(int(o.uid)))
	for team in d.teams:
		for slot in team.size():
			var uid := int(team[slot])
			if replaced_by.has(uid):
				var keeper_uid: int = replaced_by[uid]
				team[slot] = 0 if team.any(func(u): return int(u) == keeper_uid) else keeper_uid

# ───────── Money & materials ─────────
# Numbers loaded from JSON come back as floats, so always read them through these getters

func get_money() -> int:
	return int(data.money)

func add_money(amount: int) -> void:
	data.money = get_money() + amount
	money_changed.emit(get_money())

func try_spend(amount: int) -> bool:
	if get_money() < amount:
		return false
	add_money(-amount)
	return true

# ───────── Credit Cards & map clears ─────────

func get_credit_cards() -> int:
	return int(data.credit_cards)

func add_credit_cards(amount: int) -> void:
	data.credit_cards = get_credit_cards() + amount
	credit_cards_changed.emit(get_credit_cards())

func can_afford_pull(money: int, cards: int) -> bool:
	return get_money() >= money and get_credit_cards() >= cards

## Spends both currencies together, or neither
func try_spend_pull(money: int, cards: int) -> bool:
	if not can_afford_pull(money, cards):
		return false
	add_money(-money)
	add_credit_cards(-cards)
	return true

func is_stage_cleared(stage_id: StringName) -> bool:
	return data.cleared_stages.has(String(stage_id))

## Marks a map as cleared. Returns true only the first time.
func mark_stage_cleared(stage_id: StringName) -> bool:
	if is_stage_cleared(stage_id):
		return false
	data.cleared_stages[String(stage_id)] = true
	return true

# ───────── Story progress ─────────

## Chapter 1 is always open; each later chapter opens once the previous chapter's boss (X-5) is cleared
## The stars earned on a map as bits (see STAR_COUNT); a map won before stars existed has ★1
func get_star_bits(stage_id: StringName) -> int:
	var bits := int(data.stage_stars.get(String(stage_id), 0))
	if is_stage_cleared(stage_id):
		bits |= 1
	return bits

func star_count(stage_id: StringName) -> int:
	var bits := get_star_bits(stage_id)
	var count := 0
	for i in STAR_COUNT:
		if bits & (1 << i):
			count += 1
	return count

## Records stars from a win; returns the bits that are new
func add_stars(stage_id: StringName, bits: int) -> int:
	var new_bits := bits & ~get_star_bits(stage_id)
	data.stage_stars[String(stage_id)] = get_star_bits(stage_id) | bits
	return new_bits

## Which stars a finished battle earned, as [★1, ★2, ★3]. All three need a win. `result` is the engine's
## recorded result; the team is read as it is now (it can't change during a battle).
func stars_for(stage: StageData, result: Dictionary) -> Array[bool]:
	var out: Array[bool] = [false, false, false]
	if not result.win:
		return out
	out[0] = true
	var knocked_out := false
	var members := 0
	for i in result.units.size():
		if result.units[i].side == 0:
			members += 1
			knocked_out = knocked_out or int(result.stats[i].hp) <= 0
	out[1] = not knocked_out
	match stage.star_goal:
		StageData.StarGoal.HP_LEFT:
			out[2] = result.ally_hp * 100.0 >= stage.star_goal_value - 0.001
		StageData.StarGoal.MAX_COST:
			out[2] = team_cost() <= stage.star_goal_value
		StageData.StarGoal.MAX_MEMBERS:
			out[2] = members <= stage.star_goal_value
		StageData.StarGoal.MAX_ULTIMATES:
			var fired := 0
			for event in result.events:
				if event.kind == "ultimate" and result.units[event.actor].side == 0:
					fired += 1
			out[2] = fired <= stage.star_goal_value
	return out

func is_chapter_unlocked(chapter: int) -> bool:
	if chapter <= 1:
		return true
	var boss := DB.get_map(chapter - 1, StageData.BOSS_NUMBER)
	return boss != null and is_stage_cleared(boss.id)

## Maps outside the story are always open. In an open chapter the maps go in order: X-1 is open, and each
## later map opens once the one before it has been cleared (X-2 after X-1, ..., the boss X-5 after X-4).
func is_stage_unlocked(stage: StageData) -> bool:
	var event := DB.event_of(stage)
	if event:
		return event.is_mission_unlocked(stage)  # event missions go in the event's own order
	if not stage.is_story():
		return true
	if not is_chapter_unlocked(stage.chapter):
		return false
	if stage.number <= 1:
		return true
	var previous := DB.get_map(stage.chapter, stage.number - 1)
	return previous != null and is_stage_cleared(previous.id)

func get_material(key: String) -> int:
	return int(data.materials.get(key, 0))

func add_material(key: String, amount: int) -> void:
	data.materials[key] = get_material(key) + amount
	materials_changed.emit()

func get_pity(pool_id: StringName) -> int:
	return int(data.pity.get(String(pool_id), 0))

## Every pull is logged (older saves start with an empty log)
func add_pull_history(c: CharacterData, rarity: int, pool_id: StringName) -> void:
	var log: Array = data.get_or_add("pull_history", [])
	log.append({"char_id": String(c.id), "rarity": rarity, "pool": String(pool_id), "time": int(Time.get_unix_time_from_system())})
	while log.size() > PULL_HISTORY_MAX:
		log.pop_front()

## The pull log, newest first
func get_pull_history() -> Array:
	var log: Array = data.get("pull_history", []).duplicate()
	log.reverse()
	return log

func get_setting(key: String, default_value: Variant) -> Variant:
	return data.settings.get(key, default_value)

func set_setting(key: String, value: Variant) -> void:
	data.settings[key] = value
	request_save()

# ───────── Owned friends ─────────

func owns(char_id: StringName) -> bool:
	return data.owned.any(func(o): return o.char_id == String(char_id))

func get_owned(uid: int) -> Dictionary:
	for o in data.owned:
		if int(o.uid) == uid:
			return o
	return {}

func get_character(uid: int) -> CharacterData:
	var o := get_owned(uid)
	if o.is_empty():
		return null
	return DB.characters.get(StringName(o.char_id))

func add_character(c: CharacterData) -> Dictionary:
	var entry := {
		"uid": int(data.next_uid),
		"char_id": String(c.id),
		"level": 1,
		"exp": 0,
		"affection": 0,
		"locked": false,
		"obtained_at": int(Time.get_unix_time_from_system()),
		"equips": _empty_equips(),
		"ascension": 0,
	}
	data.next_uid = entry.uid + 1
	data.owned.append(entry)
	roster_changed.emit()
	return entry

func find_owned(char_id: StringName) -> Dictionary:
	for o in data.owned:
		if o.char_id == String(char_id):
			return o
	return {}

## Friendship is stored as each owned friend's "affection" value
func get_friendship(uid: int) -> int:
	return int(get_owned(uid).get("affection", 0))

## Returns the new Bond level if this raised it, else -1
func add_friendship(uid: int, amount: int) -> int:
	var o := get_owned(uid)
	if o.is_empty():
		return -1
	var before := get_bond(uid)
	o.affection = get_friendship(uid) + amount
	roster_changed.emit()
	var after := get_bond(uid)
	return after if after > before else -1

static func bond_for(friendship: int) -> int:
	var level := 0
	for i in BOND_THRESHOLDS.size():
		if friendship >= BOND_THRESHOLDS[i]:
			level = i
	return level

func get_bond(uid: int) -> int:
	return bond_for(get_friendship(uid))

static func max_bond() -> int:
	return BOND_THRESHOLDS.size() - 1

func get_ascension(uid: int) -> int:
	return int(get_owned(uid).get("ascension", 0))

## How a pulled character is received. A new friend joins the roster; a copy of one you already own
## raises their Ascension rank instead of adding a second card, and past the max it becomes Money.
## Returns {"result": "new" | "ascend" | "overflow", "uid", "rank", "money"}.
func receive_character(c: CharacterData) -> Dictionary:
	var o := find_owned(c.id)
	if o.is_empty():
		return {"result": "new", "uid": int(add_character(c).uid), "rank": 0, "money": 0}
	var rank := int(o.get("ascension", 0))
	if rank >= MAX_ASCENSION:
		add_money(ASCENSION_OVERFLOW_MONEY)
		return {"result": "overflow", "uid": int(o.uid), "rank": rank, "money": ASCENSION_OVERFLOW_MONEY}
	o.ascension = rank + 1
	roster_changed.emit()
	return {"result": "ascend", "uid": int(o.uid), "rank": rank + 1, "money": 0}

## The starter joins the vanguard wearing the starter gear. Only vanguard classes can be starters,
## otherwise the first team would have nobody who can fight.
func choose_starter(c: CharacterData) -> bool:
	if data.starter_chosen or not c.is_starter or not c.is_vanguard():
		return false
	var entry := add_character(c)
	data.teams[0][0] = entry.uid
	for equip_id in STARTER_EQUIPMENT:
		var e: EquipmentData = DB.equipment.get(equip_id)
		if e:
			equip(entry.uid, e.slot_key(), add_equipment(e).uid)
	data.starter_chosen = true
	_grant_free_friends()
	save_game()
	roster_changed.emit()
	return true

## Gives the FREE_FRIENDS this save doesn't have yet, each taking the first empty slot of its row in the first
## team. Waits until the starter is chosen, so a brand-new account gets them together with its starter.
func _grant_free_friends() -> void:
	if not data.get("starter_chosen", false):
		return
	for id: StringName in FREE_FRIENDS:
		var c: CharacterData = DB.characters.get(id)
		if c == null or not find_owned(id).is_empty():
			continue
		place_in_team(int(add_character(c).uid))

## Puts a friend into the first empty slot of their row in the first team; false if that row is full
func place_in_team(uid: int) -> bool:
	var c := get_character(uid)
	if c == null or team_slot_of(uid) >= 0:
		return false
	var team: Array = data.teams[0]
	var slots := range(VANGUARD_SLOTS) if c.is_vanguard() else range(VANGUARD_SLOTS, TEAM_SLOTS)
	for slot in slots:
		if int(team[slot]) == 0:
			team[slot] = uid
			roster_changed.emit()
			return true
	return false

## Final stats: base stats scaled by level, plus gear modifiers (unless with_equipment is false)
func get_unit_stats(uid: int, with_equipment: bool = true) -> Dictionary:
	var c := get_character(uid)
	if c == null:
		return {}
	var o := get_owned(uid)
	var stats := c.stats_at(int(o.level), int(o.get("ascension", 0)))
	# Bond: +BOND_STAT_BONUS per level to the Ascension stats (the balance check measures without it)
	var bond_mult := 1.0 + BOND_STAT_BONUS * get_bond(uid)
	for stat in ASCENSION_STATS:
		if stats[stat] > 0:
			stats[stat] = roundi(stats[stat] * bond_mult)
	if with_equipment:
		for slot_key in o.equips:
			var mods := equipment_mods(int(o.equips[slot_key]))
			for stat in mods:
				stats[stat] += mods[stat]
	stats.hp = maxi(stats.hp, 1)
	stats.speed = maxi(stats.speed, 1)
	for stat in ["attack", "evasion", "accuracy"]:
		stats[stat] = maxi(stats[stat], 0)
	stats.defense = maxi(stats.defense, FormationBattleEngine.MIN_DEFENSE)
	return stats

# ───────── Levels & EXP ─────────

## EXP needed to go from this level to the next
static func exp_to_next(level: int) -> int:
	return 50 * level + 50

## Adds EXP and levels up automatically at each threshold. Returns how many levels were gained.
func add_exp(uid: int, amount: int) -> int:
	var o := get_owned(uid)
	if o.is_empty() or amount <= 0:
		return 0
	var level := int(o.level)
	var xp := int(o.exp) + amount
	var gained := 0
	var cap := level_cap()
	while level < cap and xp >= exp_to_next(level):
		xp -= exp_to_next(level)
		level += 1
		gained += 1
	if level >= MAX_LEVEL:
		xp = 0
	elif level >= cap:
		xp = mini(xp, exp_to_next(level) - 1)  # held just short of the next level until the account catches up
	o.level = level
	o.exp = xp
	roster_changed.emit()
	return gained

## The highest level friends can reach right now: LEVEL_CAP_ABOVE_ACCOUNT above the account level, at most
## MAX_LEVEL. Friends already above it (older saves) keep their level but gain no more until the account catches up.
func level_cap() -> int:
	return mini(get_account_level() + LEVEL_CAP_ABOVE_ACCOUNT, MAX_LEVEL)

## Money needed to raise a friend by `levels` levels right now; 0 if they're already at the level cap
func level_up_cost(uid: int, levels: int = 1) -> int:
	var o := get_owned(uid)
	if o.is_empty():
		return 0
	var level := int(o.level)
	var needed := -int(o.exp)  # EXP they already have toward the next level counts
	for i in levels:
		if level >= level_cap():
			break
		needed += exp_to_next(level)
		level += 1
	return maxi(needed, 0) * GOLD_PER_EXP

## EXP still needed to reach the level cap (feeding stops there)
func exp_to_max(uid: int) -> int:
	var o := get_owned(uid)
	if o.is_empty():
		return 0
	var needed := -int(o.exp)
	for level in range(int(o.level), level_cap()):
		needed += exp_to_next(level)
	return maxi(needed, 0)

## How many of a material can usefully be fed to a friend right now (owned, and not past max level)
func feed_limit(uid: int, key: String) -> int:
	var per: int = MATERIAL_EXP.get(key, 0)
	if per <= 0:
		return 0
	return mini(get_material(key), ceili(float(exp_to_max(uid)) / per))

## Feeds `count` of a material for EXP (MATERIAL_EXP each). Returns the levels gained, or -1 if not possible.
func feed_material(uid: int, key: String, count: int) -> int:
	count = mini(count, feed_limit(uid, key))
	if count <= 0:
		return -1
	add_material(key, -count)
	return add_exp(uid, count * int(MATERIAL_EXP[key]))

## Spend Money to instantly gain levels (up to the level cap). Returns false if they can't afford it.
func buy_levels(uid: int, levels: int = 1) -> bool:
	var cost := level_up_cost(uid, levels)
	if cost <= 0 or not try_spend(cost):
		return false
	add_exp(uid, cost / GOLD_PER_EXP)
	return true

# ───────── Test mode ─────────

var _test_mode = null  # worked out once: null until asked

## Test mode: debug builds (running from the editor), or the web build opened with "test" in the URL
## (e.g. index.html?test). Unlocks the Test Mode window and 3x battle speed.
func is_test_mode() -> bool:
	if _test_mode == null:
		_test_mode = OS.is_debug_build() or (OS.has_feature("web")
			and str(JavaScriptBridge.eval("window.location.search", true)).contains("test"))
	return _test_mode

# ───────── Lifetime counters & tutorial ─────────

func get_stat(key: String) -> int:
	return int(data.stats.get(key, 0))

func add_stat(key: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	data.stats[key] = get_stat(key) + amount
	stats_changed.emit()
	request_save()

func tutorial_step() -> int:
	return int(data.tutorial)

## Moves the tutorial on to `step`, never backwards
func advance_tutorial(step: int) -> void:
	if step > tutorial_step():
		data.tutorial = step
		request_save()

# ───────── Account level ─────────

func get_account_level() -> int:
	return int(data.account_level)

func get_account_exp() -> int:
	return int(data.account_exp)

## Half a friend's curve: the account only earns EXP from battle wins, while friends also level from
## materials and Money, so this keeps account level close to the maps' recommended levels
static func account_exp_to_next(level: int) -> int:
	return 25 * level + 25

## Account EXP for winning on a map with this exp_reward, the first time or again
static func account_exp_for(map_exp: int, first_clear: bool) -> int:
	if map_exp <= 0:
		return 0
	if first_clear:
		return map_exp * ACCOUNT_FIRST_CLEAR_MULT
	return maxi(roundi(map_exp * ACCOUNT_REPEAT_SHARE), 1)

## Adds account EXP and levels up at each threshold. Returns how many account levels were gained.
func add_account_exp(amount: int) -> int:
	if amount <= 0:
		return 0
	var level := get_account_level()
	var xp := get_account_exp() + amount
	var gained := 0
	while level < ACCOUNT_MAX_LEVEL and xp >= account_exp_to_next(level):
		xp -= account_exp_to_next(level)
		level += 1
		gained += 1
	if level >= ACCOUNT_MAX_LEVEL:
		xp = 0
	data.account_level = level
	data.account_exp = xp
	account_changed.emit()
	return gained

## The most team cost allowed at an account level (the current one by default)
static func team_cost_limit_at(level: int) -> int:
	var limit := TEAM_COST_BASE
	for step: int in TEAM_COST_STEPS:
		if level >= step:
			limit += 1
	return limit

func team_cost_limit() -> int:
	return team_cost_limit_at(get_account_level())

static func rarity_cost(rarity: int) -> int:
	return int(TEAM_COST.get(rarity, 3))

## What one friend costs in a team (0 for an empty slot)
func unit_cost(uid: int) -> int:
	var c := get_character(uid)
	return rarity_cost(c.rarity) if c else 0

func team_cost(index: int = 0) -> int:
	var total := 0
	for uid in team_members(index):
		total += unit_cost(uid)
	return total

func is_team_over_cost(index: int = 0) -> bool:
	return team_cost(index) > team_cost_limit()

## Whether putting this friend into the slot keeps the team within the cost limit
## (moving someone already in the team only swaps places, so the total doesn't change)
func fits_cost(uid: int, slot: int, index: int = 0) -> bool:
	if team_slot_of(uid, index) >= 0:
		return true
	return team_cost(index) - unit_cost(team_uid(slot, index)) + unit_cost(uid) <= team_cost_limit()

## A team can head out when it has anyone in it and is within the cost limit
func can_battle(index: int = 0) -> bool:
	return has_team(index) and not is_team_over_cost(index)

# ───────── Teams ─────────

static func is_vanguard_slot(slot: int) -> bool:
	return slot < VANGUARD_SLOTS

func team_uid(slot: int, index: int = 0) -> int:
	return int(data.teams[index][slot])

func team_slot_of(uid: int, index: int = 0) -> int:
	for slot in TEAM_SLOTS:
		if team_uid(slot, index) == uid:
			return slot
	return -1

## Vanguard slots take Tanks/Warriors only, rearguard slots Mages/Shooters only
func can_place(uid: int, slot: int) -> bool:
	var c := get_character(uid)
	return c != null and c.is_vanguard() == is_vanguard_slot(slot)

## Put a friend into a slot. If they're already elsewhere in the team, the two slots swap.
## Returns false (and changes nothing) if either friend would end up in a row their class can't use.
## Also returns false if the team would go over the cost limit.
func set_team_slot(slot: int, uid: int, index: int = 0) -> bool:
	if not can_place(uid, slot) or not fits_cost(uid, slot, index):
		return false
	var team: Array = data.teams[index]
	var previous_slot := team_slot_of(uid, index)
	var displaced := int(team[slot])
	if previous_slot >= 0 and displaced != 0 and not can_place(displaced, previous_slot):
		return false
	if previous_slot >= 0:
		team[previous_slot] = displaced
	team[slot] = uid
	roster_changed.emit()
	return true

## Move anyone sitting in a row their class can't use (old saves, or a class changed in the editor)
## to a free slot in the right row, or out of the team if that row is full
func _fix_team_rows() -> void:
	for team in data.teams:
		for slot in TEAM_SLOTS:
			var uid := int(team[slot])
			if uid == 0 or can_place(uid, slot):
				continue
			team[slot] = 0
			if get_character(uid) == null:
				continue
			for target in TEAM_SLOTS:
				if int(team[target]) == 0 and can_place(uid, target):
					team[target] = uid
					break

func clear_team_slot(slot: int, index: int = 0) -> void:
	data.teams[index][slot] = 0
	roster_changed.emit()

## uids of every friend currently in the team
func team_members(index: int = 0) -> Array[int]:
	var out: Array[int] = []
	for slot in TEAM_SLOTS:
		var uid := team_uid(slot, index)
		if get_character(uid):
			out.append(uid)
	return out

## A team can battle as long as it has anyone in it; it loses only when every member is down
func has_team(index: int = 0) -> bool:
	return not team_members(index).is_empty()

## The team in the shape BattleEngine expects
func get_battle_team(index: int = 0) -> Dictionary:
	var team := {"vanguard": [], "rearguard": []}
	for slot in TEAM_SLOTS:
		var uid := team_uid(slot, index)
		var c := get_character(uid)
		if c == null:
			continue
		var row := "vanguard" if is_vanguard_slot(slot) else "rearguard"
		team[row].append(c.battle_unit(get_unit_stats(uid)))
	team.combos = active_combos(index).map(func(combo: ComboData): return combo.battle_dict())
	return team

## Combos whose members are all in team `index` (the battle still checks that each one actually fights)
func active_combos(index: int = 0) -> Array[ComboData]:
	var ids := {}
	for slot in TEAM_SLOTS:
		var c := get_character(team_uid(slot, index))
		if c != null:
			ids[c.id] = true
	var out: Array[ComboData] = []
	for combo: ComboData in DB.combos.values():
		if combo.is_ready(ids):
			out.append(combo)
	return out

# ───────── Gear ─────────

func add_equipment(e: EquipmentData, plus: int = 0) -> Dictionary:
	var entry := {"uid": int(data.next_equip_uid), "equip_id": String(e.id), "plus": clampi(plus, 0, GEAR_MAX_PLUS)}
	data.next_equip_uid = entry.uid + 1
	data.equipment.append(entry)
	roster_changed.emit()
	gear_changed.emit()
	return entry

func _equipment_entry(equip_uid: int) -> Dictionary:
	if equip_uid == 0:
		return {}
	for entry in data.equipment:
		if int(entry.uid) == equip_uid:
			return entry
	return {}

func get_equipment(equip_uid: int) -> EquipmentData:
	var entry := _equipment_entry(equip_uid)
	return DB.equipment.get(StringName(entry.equip_id)) if not entry.is_empty() else null

## A piece of gear's upgrade level (+0 .. GEAR_MAX_PLUS)
func get_plus(equip_uid: int) -> int:
	return int(_equipment_entry(equip_uid).get("plus", 0))

## The stats a piece of gear adds at its upgrade level ({} for none)
func equipment_mods(equip_uid: int) -> Dictionary:
	var e := get_equipment(equip_uid)
	return e.modifiers(get_plus(equip_uid)) if e else {}

## All owned gear that fits a slot ("" = every slot): [{uid, data, plus}], best first (rarity, then +, then name)
func list_equipment(slot_key: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in data.equipment:
		var e: EquipmentData = DB.equipment.get(StringName(entry.equip_id))
		if e and (slot_key.is_empty() or e.slot_key() == slot_key):
			out.append({"uid": int(entry.uid), "data": e, "plus": int(entry.get("plus", 0))})
	out.sort_custom(func(a, b):
		if a.data.rarity != b.data.rarity:
			return a.data.rarity > b.data.rarity
		if a.plus != b.plus:
			return a.plus > b.plus
		return a.data.display_name < b.data.display_name)
	return out

## How many copies of a piece of gear are owned
func count_equipment(equip_id: StringName) -> int:
	return data.equipment.filter(func(entry): return entry.equip_id == String(equip_id)).size()

func get_parts() -> int:
	return int(data.get("gear_parts", 0))

func add_parts(amount: int) -> void:
	data.gear_parts = maxi(get_parts() + amount, 0)
	gear_changed.emit()

## Parts a piece gives when scrapped: its rarity's share plus GEAR_SCRAP_REFUND of what its upgrades cost
func scrap_value(equip_uid: int) -> int:
	var e := get_equipment(equip_uid)
	if e == null:
		return 0
	var spent := 0
	for level in range(1, get_plus(equip_uid) + 1):
		spent += int(GEAR_UPGRADE_PARTS.get(e.rarity, 1)) * level
	return int(GEAR_SCRAP_PARTS.get(e.rarity, 1)) + floori(spent * GEAR_SCRAP_REFUND)

## Breaks gear down into Parts. Gear someone is wearing can't be scrapped. Returns the Parts gained, or -1.
func scrap_equipment(equip_uid: int) -> int:
	var entry := _equipment_entry(equip_uid)
	if entry.is_empty() or equipped_by(equip_uid) != 0:
		return -1
	var parts := scrap_value(equip_uid)
	data.equipment.erase(entry)
	add_parts(parts)
	roster_changed.emit()
	return parts

## Parts and Money to go from the current upgrade level to the next ({} once at the max)
func upgrade_cost(equip_uid: int) -> Dictionary:
	var e := get_equipment(equip_uid)
	var next := get_plus(equip_uid) + 1
	if e == null or next > GEAR_MAX_PLUS:
		return {}
	return {"parts": int(GEAR_UPGRADE_PARTS.get(e.rarity, 1)) * next, "money": int(GEAR_UPGRADE_MONEY.get(e.rarity, 100)) * next}

func can_upgrade(equip_uid: int) -> bool:
	var cost := upgrade_cost(equip_uid)
	return not cost.is_empty() and get_parts() >= cost.parts and get_money() >= cost.money

## +1 to a piece of gear for its upgrade_cost. Returns false if it can't be done.
func upgrade_equipment(equip_uid: int) -> bool:
	if not can_upgrade(equip_uid):
		return false
	var cost := upgrade_cost(equip_uid)
	add_money(-int(cost.money))
	add_parts(-int(cost.parts))
	var entry := _equipment_entry(equip_uid)
	entry.plus = get_plus(equip_uid) + 1
	roster_changed.emit()  # the wearer's stats changed
	return true

## A piece can be crafted once any cleared map drops it (the starter gear always can)
func can_craft_unlocked(e: EquipmentData) -> bool:
	if STARTER_EQUIPMENT.has(e.id):
		return true
	for stage in DB.stages:
		if is_stage_cleared(stage.id) and stage.equipment_drops.has(e):
			return true
	return false

## The first map that drops a piece (to tell the player where to unlock it), or null
func first_map_dropping(e: EquipmentData) -> StageData:
	for stage in DB.stages:
		if stage.is_story() and stage.equipment_drops.has(e):
			return stage
	return null

func craft_cost(e: EquipmentData) -> Dictionary:
	return {"parts": int(GEAR_CRAFT_PARTS.get(e.rarity, 4)), "money": int(GEAR_CRAFT_MONEY.get(e.rarity, 200))}

func can_craft(e: EquipmentData) -> bool:
	var cost := craft_cost(e)
	return can_craft_unlocked(e) and get_parts() >= cost.parts and get_money() >= cost.money

## Pays for and makes a piece at +0 (the crafting minigame's bonus is added after with apply_craft_bonus, so
## closing the game mid-minigame never loses what was paid). Returns the new entry, or {} if it can't be done.
func craft_equipment(e: EquipmentData) -> Dictionary:
	if not can_craft(e):
		return {}
	var cost := craft_cost(e)
	add_money(-int(cost.money))
	add_parts(-int(cost.parts))
	add_stat("crafts")
	return add_equipment(e)

## The crafting minigame's result: free upgrade levels on the piece just made (capped at GEAR_MAX_PLUS)
func apply_craft_bonus(equip_uid: int, bonus: int) -> void:
	var entry := _equipment_entry(equip_uid)
	if entry.is_empty() or bonus <= 0:
		return
	entry.plus = clampi(get_plus(equip_uid) + bonus, 0, GEAR_MAX_PLUS)
	roster_changed.emit()
	gear_changed.emit()

## uid of the friend wearing this gear, or 0
func equipped_by(equip_uid: int) -> int:
	for o in data.owned:
		for slot_key in o.equips:
			if int(o.equips[slot_key]) == equip_uid:
				return int(o.uid)
	return 0

## equip_uid 0 empties the slot. Gear worn by someone else is taken off them first.
func equip(char_uid: int, slot_key: String, equip_uid: int) -> bool:
	var o := get_owned(char_uid)
	if o.is_empty() or not o.equips.has(slot_key):
		return false
	if equip_uid != 0:
		var e := get_equipment(equip_uid)
		if e == null or e.slot_key() != slot_key:
			return false
		var wearer := equipped_by(equip_uid)
		if wearer != 0:
			get_owned(wearer).equips[slot_key] = 0
	o.equips[slot_key] = equip_uid
	roster_changed.emit()
	return true
