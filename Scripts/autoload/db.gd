extends Node
## Loads every friend, gacha pool, piece of gear, stage and commission at startup. Autoload name: DB
## (Display names for materials live in Terms.)

const MATERIALS := ["snack", "coffee", "gossip"]

var characters: Dictionary[StringName, CharacterData] = {}
var equipment: Dictionary[StringName, EquipmentData] = {}
var pools: Array[GachaPool] = []
var stages: Array[StageData] = []
var commissions: Array[CommissionData] = []

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
	# Maps outside the story first, then story order: 1-1 ... 1-5, 2-1 ...
	stages.sort_custom(func(a, b): return a.chapter < b.chapter or (a.chapter == b.chapter and a.number < b.number))

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
