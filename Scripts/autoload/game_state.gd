extends Node
## Save data: money, materials, owned friends, gear and teams. Autoload name: GameState

signal money_changed(value: int)
signal materials_changed
signal roster_changed  # owned friends, team or gear changed
signal credit_cards_changed(value: int)

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
const FREE_FRIENDS := [&"coconutbird_caster"]  # everyone owns these: new accounts with their starter, older saves on load
const MAX_LEVEL := 50
const GROWTH_PER_LEVEL := 0.04  # each level adds 4% of the level-1 base stats
const GOLD_PER_EXP := 2  # Money cost of 1 EXP when levelling up with Money
const MAX_ASCENSION := 4  # each duplicate pulled raises Ascension by 1
const ASCENSION_BONUS := 0.05  # +5% per rank to the stats below
const ASCENSION_STATS := ["hp", "attack", "defense", "speed"]
const ASCENSION_OVERFLOW_MONEY := 100  # a copy pulled after max Ascension turns into this much Money
const CREDIT_CARDS_PER_PULL := 1  # every pull costs this many Credit Cards on top of the Money cost
const FIRST_CLEAR_CREDIT_CARDS := 2  # for winning on a map for the first time
const CREDIT_CARD_DROP_CHANCE := 0.01  # 1% chance per win to find 1 Credit Card

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
	credit_cards_changed.connect(func(_value): request_save())
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
		"cleared_stages": {},  # stage_id -> true once won there (first-clear bonus already given)
		"materials": {},
		"owned": [],  # [{uid, char_id, level, exp, affection, locked, obtained_at, equips}]
		"next_uid": 1,
		"equipment": [],  # [{uid, equip_id}]
		"next_equip_uid": 1,
		"teams": teams,  # each team is 6 uids, 0 = empty slot
		"pity": {},  # pool_id -> pulls since the last SSR
		"starter_chosen": false,
		"commissions": {},  # commission_id -> {"uid", "started_at"}; see Commissions autoload
		"settings": {},
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
	return ""

## Starts over from a brand-new save. The old save is kept as the backup file until the next save overwrites it.
func reset_save() -> void:
	data = _new_save()
	save_game()
	roster_changed.emit()
	money_changed.emit(get_money())
	materials_changed.emit()
	credit_cards_changed.emit(get_credit_cards())

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
func is_chapter_unlocked(chapter: int) -> bool:
	if chapter <= 1:
		return true
	var boss := DB.get_map(chapter - 1, StageData.BOSS_NUMBER)
	return boss != null and is_stage_cleared(boss.id)

## Maps outside the story are always open. In an open chapter the maps go in order: X-1 is open, and each
## later map opens once the one before it has been cleared (X-2 after X-1, ..., the boss X-5 after X-4).
func is_stage_unlocked(stage: StageData) -> bool:
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

func add_friendship(uid: int, amount: int) -> void:
	var o := get_owned(uid)
	if o.is_empty():
		return
	o.affection = get_friendship(uid) + amount
	roster_changed.emit()

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
		var entry := add_character(c)
		var team: Array = data.teams[0]
		var slots := range(VANGUARD_SLOTS) if c.is_vanguard() else range(VANGUARD_SLOTS, TEAM_SLOTS)
		for slot in slots:
			if int(team[slot]) == 0:
				team[slot] = entry.uid
				break

## Final stats: base stats scaled by level, plus gear modifiers (unless with_equipment is false)
func get_unit_stats(uid: int, with_equipment: bool = true) -> Dictionary:
	var c := get_character(uid)
	if c == null:
		return {}
	var o := get_owned(uid)
	var stats := c.base_stats()
	var levels := int(o.level) - 1
	var ascension_mult := 1.0 + ASCENSION_BONUS * int(o.get("ascension", 0))
	for stat in stats:
		if stats[stat] < 0:
			continue  # a negative stat (e.g. Steve's Defense) stays as it is; growth would only make it worse
		var level_mult := 1.0 + (GROWTH_PER_LEVEL + float(c.growth_bonus.get(stat, 0.0))) * levels
		var mult := level_mult * (ascension_mult if stat in ASCENSION_STATS else 1.0)
		stats[stat] = roundi(stats[stat] * mult)
	if with_equipment:
		for slot_key in o.equips:
			var e := get_equipment(int(o.equips[slot_key]))
			if e == null:
				continue
			var mods := e.modifiers()
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
	while level < MAX_LEVEL and xp >= exp_to_next(level):
		xp -= exp_to_next(level)
		level += 1
		gained += 1
	if level >= MAX_LEVEL:
		xp = 0
	o.level = level
	o.exp = xp
	roster_changed.emit()
	return gained

## Money needed to raise a friend by `levels` levels right now; 0 if they're already at max level
func level_up_cost(uid: int, levels: int = 1) -> int:
	var o := get_owned(uid)
	if o.is_empty():
		return 0
	var level := int(o.level)
	var needed := -int(o.exp)  # EXP they already have toward the next level counts
	for i in levels:
		if level >= MAX_LEVEL:
			break
		needed += exp_to_next(level)
		level += 1
	return maxi(needed, 0) * GOLD_PER_EXP

## Spend Money to instantly gain levels (capped at MAX_LEVEL). Returns false if they can't afford it.
func buy_levels(uid: int, levels: int = 1) -> bool:
	var cost := level_up_cost(uid, levels)
	if cost <= 0 or not try_spend(cost):
		return false
	add_exp(uid, cost / GOLD_PER_EXP)
	return true

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
func set_team_slot(slot: int, uid: int, index: int = 0) -> bool:
	if not can_place(uid, slot):
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
	return team

# ───────── Gear ─────────

func add_equipment(e: EquipmentData) -> Dictionary:
	var entry := {"uid": int(data.next_equip_uid), "equip_id": String(e.id)}
	data.next_equip_uid = entry.uid + 1
	data.equipment.append(entry)
	roster_changed.emit()
	return entry

func get_equipment(equip_uid: int) -> EquipmentData:
	if equip_uid == 0:
		return null
	for entry in data.equipment:
		if int(entry.uid) == equip_uid:
			return DB.equipment.get(StringName(entry.equip_id))
	return null

## All owned gear that fits a slot: [{uid, data}]
func list_equipment(slot_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in data.equipment:
		var e: EquipmentData = DB.equipment.get(StringName(entry.equip_id))
		if e and e.slot_key() == slot_key:
			out.append({"uid": int(entry.uid), "data": e})
	return out

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
