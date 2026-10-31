extends Node
## Loads every friend, gacha pool, piece of gear and stage at startup. Autoload name: DB
## (Display names for materials live in Terms.)

const MATERIALS := ["snack", "coffee", "gossip"]

var characters: Dictionary[StringName, CharacterData] = {}
var equipment: Dictionary[StringName, EquipmentData] = {}
var pools: Array[GachaPool] = []
var stages: Array[StageData] = []

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

func get_stage(stage_id: StringName) -> StageData:
	for s in stages:
		if s.id == stage_id:
			return s
	return null

func _load_all(dir_path: String) -> Array[Resource]:
	var out: Array[Resource] = []
	# list_directory still works after export, when .tres files become .remap
	for file in ResourceLoader.list_directory(dir_path):
		if file.ends_with(".tres") or file.ends_with(".res"):
			out.append(load(dir_path + file))
	return out
