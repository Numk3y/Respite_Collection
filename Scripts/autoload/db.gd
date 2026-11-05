extends Node
## Loads every friend, gacha pool, piece of gear, stage and commission at startup. Autoload name: DB
## (Display names for materials live in Terms.)

const MATERIALS := ["snack", "coffee", "gossip"]

var characters: Dictionary[StringName, CharacterData] = {}
var equipment: Dictionary[StringName, EquipmentData] = {}
var pools: Array[GachaPool] = []
var stages: Array[StageData] = []
var commissions: Array[CommissionData] = []
var events: Dictionary[StringName, EventData] = {}  # id -> event; Data/events/<id>/event.tres
var combos: Dictionary[StringName, ComboData] = {}  # id -> combo attack; Data/combos/*.tres

func _ready() -> void:
	for res in _load_all("res://Data/characters/"):
		var c := res as CharacterData
		if c == null:
			continue
		if characters.has(c.id):
			push_error("Duplicate character id: %s" % c.id)
		characters[c.id] = c
	for res in _load_all("res://Data/equipment/"):
		var e := res as EquipmentData
		if e == null:
			continue
		if equipment.has(e.id):
			push_error("Duplicate equipment id: %s" % e.id)
		equipment[e.id] = e
	for res in _load_all("res://Data/pools/"):
		var p := res as GachaPool
		if p:
			pools.append(p)
	for res in _load_all("res://Data/stages/"):
		var s := res as StageData
		if s:
			stages.append(s)
	for res in _load_all("res://Data/commissions/"):  # incidents live in a subfolder and aren't listed here
		var c := res as CommissionData
		if c:
			commissions.append(c)
	commissions.sort_custom(func(a, b): return a.duration_seconds < b.duration_seconds)
	# Each event has its own folder; its mission stages sit beside event.tres and aren't story maps
	for folder in ResourceLoader.list_directory("res://Data/events/"):
		if not folder.ends_with("/"):
			continue
		var path := "res://Data/events/%sevent.tres" % folder
		var ev := load(path) as EventData if ResourceLoader.exists(path) else null
		if ev == null:
			continue
		if events.has(ev.id):
			push_error("Duplicate event id: %s" % ev.id)
		if ev.boss_stage == null:
			push_error("Event %s has no boss_stage" % ev.id)
			continue
		events[ev.id] = ev
	_load_combos()
	# Maps outside the story first, then story order: 1-1 ... 1-5, 2-1 ...
	stages.sort_custom(func(a, b): return a.chapter < b.chapter or (a.chapter == b.chapter and a.number < b.number))

## Combos: every id unique, every enabled combo with its own effect (no two share one), 2+ known members
func _load_combos() -> void:
	var effect_owner := {}
	for res in _load_all("res://Data/combos/"):
		var c := res as ComboData
		if c == null:
			continue
		if combos.has(c.id):
			push_error("Duplicate combo id: %s" % c.id)
			continue
		combos[c.id] = c
		if not c.enabled:
			continue
		if c.min_size() < 2:
			push_warning("Combo %s needs at least 2 members; it can't trigger." % c.id)
		if c.any_count > c.any_of.size():
			push_warning("Combo %s wants %d of any_of but lists only %d; it can't trigger." % [c.id, c.any_count, c.any_of.size()])
		for m in c.members + c.any_of:
			if not characters.has(m):
				push_warning("Combo %s: unknown member '%s'; it can't trigger." % [c.id, m])
		if not FormationBattleEngine.COMBO_EFFECTS.has(c.effect_id):
			push_warning("Combo %s: unknown effect '%s'; it can't trigger." % [c.id, c.effect_id])
		elif effect_owner.has(c.effect_id):
			push_error("Combos %s and %s both use the effect '%s'; every combo needs its own." % [
				effect_owner[c.effect_id], c.id, c.effect_id])
		else:
			effect_owner[c.effect_id] = c.id

func get_stage(stage_id: StringName) -> StageData:
	for s in stages:
		if s.id == stage_id:
			return s
	return null

## A story map by position, e.g. get_map(1, 5) for the Chapter 1 boss; null if it doesn't exist yet
func get_map(chapter: int, number: int) -> StageData:
	for s in stages:
		if s.chapter == chapter and s.number == number:
			return s
	return null

## The event a mission belongs to, or null for story and practice maps
func event_of(stage: StageData) -> EventData:
	for ev in events.values():
		if ev.has_mission(stage):
			return ev
	return null

## Story chapter numbers that have at least one map, in order
func chapters() -> Array[int]:
	var out: Array[int] = []
	for s in stages:
		if s.is_story() and not out.has(s.chapter):
			out.append(s.chapter)
	return out

func _load_all(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	# list_directory still works after export, when .tres files become .remap
	for file in ResourceLoader.list_directory(dir_path):
		if file.ends_with(".tres") or file.ends_with(".res"):
			out.append(load(dir_path + file))
	return out
