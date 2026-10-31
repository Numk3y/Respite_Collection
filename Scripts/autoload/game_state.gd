extends Node
## Save data: money, materials, owned friends, gear and fleets. Autoload name: GameState

signal money_changed(value: int)
signal materials_changed
signal roster_changed  # owned friends, fleet or gear changed

# On the web, user:// is an IndexedDB-backed folder that every Godot game on the same site shares
# (all GitHub Pages projects of one account are the same site), so keep the save in our own subfolder.
const SAVE_DIR := "user://friend_fleet/"
const SAVE_FILE := "save.json"
const BACKUP_FILE := "save.bak.json"
const TMP_FILE := "save.tmp.json"
const LEGACY_SAVE_DIR := "user://"  # desktop builds before the web switch saved here
const SAVE_VERSION := 2
const MAX_OFFLINE_SEC := 12 * 3600
const FLEET_COUNT := 4
const FLEET_SLOTS := 6
const VANGUARD_SLOTS := 3  # slots 0-2 are vanguard, 3-5 rearguard
const STARTER_EQUIPMENT := [&"foam_bat", &"hoodie", &"lucky_charm"]

var data: Dictionary = {}
var _save_queued := false

func _ready() -> void:
	if not load_game():
		data = _new_save()
	_fix_fleet_rows()
	# Save shortly after every change. A browser tab can be closed at any moment and gives
	# no reliable warning, so don't sit on unsaved changes until the next autosave.
	money_changed.connect(func(_value): request_save())
	materials_changed.connect(request_save)
	roster_changed.connect(request_save)
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
	var fleets := []
	for i in FLEET_COUNT:
		fleets.append(_empty_fleet())
	return {
		"version": SAVE_VERSION,
		"money": 2500,
		"materials": {},
		"owned": [],  # [{uid, char_id, level, exp, affection, locked, obtained_at, equips}]
		"next_uid": 1,
		"equipment": [],  # [{uid, equip_id}]
		"next_equip_uid": 1,
		"fleets": fleets,  # each fleet is 6 uids, 0 = empty slot
		"pity": {},  # pool_id -> pulls since the last SSR
		"starter_chosen": false,
		"idle_stage_id": "",  # set by the first sortie; the fleet keeps patrolling that map
		"last_tick": int(Time.get_unix_time_from_system()),
		"expeditions": [],  # reserved
		"settings": {"minimize_on_close": true},
	}

func _empty_fleet() -> Array:
	var fleet := []
	fleet.resize(FLEET_SLOTS)
	fleet.fill(0)
	return fleet

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
	for path in [SAVE_DIR + SAVE_FILE, SAVE_DIR + BACKUP_FILE, LEGACY_SAVE_DIR + SAVE_FILE, LEGACY_SAVE_DIR + BACKUP_FILE]:
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
	_fix_fleet_rows()
	save_game()
	roster_changed.emit()
	money_changed.emit(get_money())
	materials_changed.emit()
	return ""

# Upgrade older save formats here whenever the format changes
func _migrate(d: Dictionary) -> Dictionary:
	if int(d.get("version", 1)) < 2:
		# v1 fleets were plain uid lists: the first 3 become vanguard, the rest rearguard
		var fleets := []
		for old in d.get("fleets", []):
			var fleet := _empty_fleet()
			for i in mini(old.size(), FLEET_SLOTS):
				fleet[i] = int(old[i])
			fleets.append(fleet)
		d.fleets = fleets
	var fresh := _new_save()
	for key in fresh:
		if not d.has(key):
			d[key] = fresh[key]
	while d.fleets.size() < FLEET_COUNT:
		d.fleets.append(_empty_fleet())
	for o in d.owned:
		if not o.has("equips"):
			o.equips = _empty_equips()
	d.version = SAVE_VERSION
	return d

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
	}
	data.next_uid = entry.uid + 1
	data.owned.append(entry)
	roster_changed.emit()
	return entry

## The starter joins the vanguard wearing the starter gear. Only vanguard classes can be starters,
## otherwise the first fleet would have nobody who can fight.
func choose_starter(c: CharacterData) -> bool:
	if data.starter_chosen or not c.is_starter or not c.is_vanguard():
		return false
	var entry := add_character(c)
	data.fleets[0][0] = entry.uid
	for equip_id in STARTER_EQUIPMENT:
		var e: EquipmentData = DB.equipment.get(equip_id)
		if e:
			equip(entry.uid, e.slot_key(), add_equipment(e).uid)
	data.starter_chosen = true
	save_game()
	roster_changed.emit()
	return true

## Final stats: base stats scaled by level, plus gear modifiers (unless with_equipment is false)
func get_unit_stats(uid: int, with_equipment: bool = true) -> Dictionary:
	var c := get_character(uid)
	if c == null:
		return {}
	var o := get_owned(uid)
	var stats := c.base_stats()
	var level_mult := 1.0 + 0.05 * (int(o.level) - 1)
	for stat in stats:
		stats[stat] = roundi(stats[stat] * level_mult)
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
	for stat in ["attack", "defense", "evasion", "accuracy"]:
		stats[stat] = maxi(stats[stat], 0)
	return stats

# ───────── Fleets ─────────

static func is_vanguard_slot(slot: int) -> bool:
	return slot < VANGUARD_SLOTS

func fleet_uid(slot: int, index: int = 0) -> int:
	return int(data.fleets[index][slot])

func fleet_slot_of(uid: int, index: int = 0) -> int:
	for slot in FLEET_SLOTS:
		if fleet_uid(slot, index) == uid:
			return slot
	return -1

## Vanguard slots take Tanks/Warriors only, rearguard slots Mages/Shooters only
func can_place(uid: int, slot: int) -> bool:
	var c := get_character(uid)
	return c != null and c.is_vanguard() == is_vanguard_slot(slot)

## Put a friend into a slot. If they're already elsewhere in the fleet, the two slots swap.
## Returns false (and changes nothing) if either friend would end up in a row their class can't use.
func set_fleet_slot(slot: int, uid: int, index: int = 0) -> bool:
	if not can_place(uid, slot):
		return false
	var fleet: Array = data.fleets[index]
	var previous_slot := fleet_slot_of(uid, index)
	var displaced := int(fleet[slot])
	if previous_slot >= 0 and displaced != 0 and not can_place(displaced, previous_slot):
		return false
	if previous_slot >= 0:
		fleet[previous_slot] = displaced
	fleet[slot] = uid
	roster_changed.emit()
	return true

## Move anyone sitting in a row their class can't use (old saves, or a class changed in the editor)
## to a free slot in the right row, or out of the fleet if that row is full
func _fix_fleet_rows() -> void:
	for fleet in data.fleets:
		for slot in FLEET_SLOTS:
			var uid := int(fleet[slot])
			if uid == 0 or can_place(uid, slot):
				continue
			fleet[slot] = 0
			if get_character(uid) == null:
				continue
			for target in FLEET_SLOTS:
				if int(fleet[target]) == 0 and can_place(uid, target):
					fleet[target] = uid
					break

func clear_fleet_slot(slot: int, index: int = 0) -> void:
	data.fleets[index][slot] = 0
	roster_changed.emit()

func has_vanguard(index: int = 0) -> bool:
	for slot in VANGUARD_SLOTS:
		if get_character(fleet_uid(slot, index)):
			return true
	return false

## The fleet in the shape BattleEngine expects
func get_battle_fleet(index: int = 0) -> Dictionary:
	var fleet := {"vanguard": [], "rearguard": []}
	for slot in FLEET_SLOTS:
		var uid := fleet_uid(slot, index)
		var c := get_character(uid)
		if c == null:
			continue
		var row := "vanguard" if is_vanguard_slot(slot) else "rearguard"
		fleet[row].append({"name": c.display_name, "cls": c.char_class, "stats": get_unit_stats(uid)})
	return fleet

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
