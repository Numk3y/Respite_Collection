@tool
class_name PoolEntry
extends Resource

@export var character: CharacterData
@export_range(1, 100000) var weight: int = 100  # weight within the same rarity; raise it for rate-up characters
@export var featured: bool = false
