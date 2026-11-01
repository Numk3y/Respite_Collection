@tool
extends ScrollContainer
## "Friends" dock: fill in the form to create a character .tres and add it to the ticked gacha pools

const CHAR_DIR := "res://Data/characters/"
const POOL_DIR := "res://Data/pools/"
const TERMS: Dictionary = preload("res://Scripts/autoload/terms.gd").TERMS

var _form: VBoxContainer
var _id: LineEdit
var _name: LineEdit
var _class: OptionButton
var _rarity: OptionButton
var _stats: Dictionary = {}  # stat name -> SpinBox
var _skill_fields: Dictionary = {}  # SkillData.Kind -> {"name": LineEdit, "description": LineEdit}
var _ultimate_effect: OptionButton
var _passive_effect: OptionButton
var _ultimate_max: SpinBox
var _description: TextEdit
var _starter: CheckBox
var _pool_box: VBoxContainer
var _status: Label

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_form)

	_id = _add_field("ID (lowercase letters, digits, underscores)", LineEdit.new())
	_name = _add_field("Display name", LineEdit.new())

	# The class decides the row: Tank/Warrior = vanguard, Mage/Shooter = rearguard
	_class = _add_field("Class", OptionButton.new())
	for cls in CharacterData.CharClass.values():
		var row_key := "vanguard" if CharacterData.is_vanguard_class(cls) else "rearguard"
		_class.add_item("%s (%s)" % [_term("class_" + CharacterData.CLASS_KEYS[cls]), _term(row_key)], cls)
	_class.selected = CharacterData.CharClass.WARRIOR
	_class.item_selected.connect(func(_index): _apply_class_template())

	_rarity = _add_field("Rarity", OptionButton.new())
	for rarity in CharacterData.RARITIES:
		_rarity.add_item(CharacterData.Rarity.keys()[rarity], rarity)
	_rarity.select(_rarity.get_item_index(CharacterData.Rarity.R))

	_section("Base stats (picking a class fills in suggested values)")
	for stat in CharacterData.STATS:
		var spin := SpinBox.new()
		spin.min_value = 1 if stat in ["hp", "speed"] else 0
		spin.max_value = 9999
		_stats[stat] = _add_field(_term("stat_" + stat), spin)
	_apply_class_template()

	for kind in [SkillData.Kind.PASSIVE, SkillData.Kind.ACTIVE]:
		var kind_name := _term("passive_skill" if kind == SkillData.Kind.PASSIVE else "active_skill")
		_section("%s skill" % kind_name)
		var skill_name: LineEdit = _add_field("Name", LineEdit.new())
		var skill_description: LineEdit = _add_field("Description", LineEdit.new())
		_skill_fields[kind] = {"name": skill_name, "description": skill_description}
	# Pick which coded effect each skill uses (tune their params in the Inspector)
	_passive_effect = _add_field("Passive effect", OptionButton.new())
	_passive_effect.add_item("(none yet)")
	for effect in FormationBattleEngine.PASSIVE_EFFECTS:
		_passive_effect.add_item(String(effect))
	_ultimate_effect = _add_field("Ultimate effect", OptionButton.new())
	_ultimate_effect.add_item("(none yet)")
	for effect in FormationBattleEngine.ULTIMATE_EFFECTS:
		_ultimate_effect.add_item(String(effect))
	_ultimate_max = _add_field("Ultimate gauge size", SpinBox.new())
	_ultimate_max.min_value = 1
	_ultimate_max.max_value = 1000
	_ultimate_max.value = CharacterData.new().ultimate_max

	_section("Other")
	_description = _add_field("Description", TextEdit.new())
	_description.custom_minimum_size = Vector2(0, 60)
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_starter = CheckBox.new()
	_starter.text = "Can be picked as a starter (vanguard classes only)"
	_form.add_child(_starter)

	_section("Add to gacha pools")
	_pool_box = VBoxContainer.new()
	_form.add_child(_pool_box)
	var refresh := Button.new()
	refresh.text = "Refresh pool list"
	refresh.pressed.connect(_refresh_pools)
	_form.add_child(refresh)

	var create := Button.new()
	create.text = "Create character"
	create.pressed.connect(_create)
	_form.add_child(create)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_form.add_child(_status)
	_refresh_pools()

func _term(key: String) -> String:
	return TERMS.get(key, key)

func _section(text: String) -> void:
	_form.add_child(HSeparator.new())
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	_form.add_child(label)

func _add_field(label_text: String, control: Control) -> Control:
	var label := Label.new()
	label.text = label_text
	_form.add_child(label)
	_form.add_child(control)
	return control

func _selected_class() -> int:
	return _class.get_selected_id()

func _apply_class_template() -> void:
	var template: Dictionary = CharacterData.CLASS_TEMPLATES[_selected_class()]
	for stat in template:
		_stats[stat].value = template[stat]

func _refresh_pools() -> void:
	for child in _pool_box.get_children():
		child.queue_free()
	for file in ResourceLoader.list_directory(POOL_DIR):
		if not file.ends_with(".tres"):
			continue
		var pool := load(POOL_DIR + file) as GachaPool
		if pool == null:
			continue
		var cb := CheckBox.new()
		cb.text = pool.display_name
		cb.set_meta("path", POOL_DIR + file)
		_pool_box.add_child(cb)

func _create() -> void:
	var id := _id.text.strip_edges().to_lower()
	var path := CHAR_DIR + id + ".tres"
	if not id.is_valid_ascii_identifier():
		_status.text = "The ID may only use letters, digits and underscores, and can't start with a digit."
		return
	if FileAccess.file_exists(path):
		_status.text = "The ID \"%s\" already exists." % id
		return
	if _name.text.strip_edges().is_empty():
		_status.text = "Please enter a display name."
		return
	if _starter.button_pressed and not CharacterData.is_vanguard_class(_selected_class()):
		_status.text = "Only vanguard classes (Tank, Warrior, Berserker) can be starters."
		return

	var c := CharacterData.new()
	c.id = id
	c.display_name = _name.text.strip_edges()
	c.char_class = _selected_class()
	c.rarity = _rarity.get_selected_id()
	for stat in CharacterData.STATS:
		c.set(stat, int(_stats[stat].value))
	c.passive_skill = _make_skill(id, SkillData.Kind.PASSIVE)
	c.active_skill = _make_skill(id, SkillData.Kind.ACTIVE)
	if _passive_effect.selected > 0:
		c.passive_skill.effect_id = StringName(_passive_effect.get_item_text(_passive_effect.selected))
	if _ultimate_effect.selected > 0:
		c.active_skill.effect_id = StringName(_ultimate_effect.get_item_text(_ultimate_effect.selected))
	c.ultimate_max = int(_ultimate_max.value)
	c.description = _description.text.strip_edges()
	c.is_starter = _starter.button_pressed

	DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	# FLAG_CHANGE_PATH makes the pools reference this file instead of embedding a copy
	var err := ResourceSaver.save(c, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		_status.text = "Save failed: %s" % error_string(err)
		return

	var added_pools: PackedStringArray = []
	for cb in _pool_box.get_children():
		if cb is CheckBox and cb.button_pressed:
			var pool: GachaPool = load(cb.get_meta("path"))
			var entry := PoolEntry.new()
			entry.character = c
			pool.entries.append(entry)
			ResourceSaver.save(pool)
			added_pools.append(pool.display_name)

	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource(c)
	_status.text = "Created %s (pools: %s). Put their picture at %s (PNG, JPG or WebP; any letter case). It loads automatically, and until then the game shows a placeholder card." % [
		c.display_name, ", ".join(added_pools) if not added_pools.is_empty() else "none", c.default_portrait_path()]
	_id.clear()
	_name.clear()
	_description.clear()
	for kind in _skill_fields:
		_skill_fields[kind].name.clear()
		_skill_fields[kind].description.clear()

## Skills are embedded in the character file; they can be saved as their own .tres later if shared
func _make_skill(char_id: String, kind: int) -> SkillData:
	var fields: Dictionary = _skill_fields[kind]
	var skill := SkillData.new()
	skill.kind = kind
	skill.id = "%s_%s" % [char_id, "passive" if kind == SkillData.Kind.PASSIVE else "active"]
	skill.display_name = fields.name.text.strip_edges()
	skill.description = fields.description.text.strip_edges()
	return skill
