class_name CharCard
extends PanelContainer
## Character card: shows the portrait, or a rarity-coloured block with the name's first letter if there isn't one

const RARITY_COLORS := {
	CharacterData.Rarity.N: Color("#8a8f98"),
	CharacterData.Rarity.R: Color("#3b82f6"),
	CharacterData.Rarity.SR: Color("#a855f7"),
	CharacterData.Rarity.SSR: Color("#f59e0b"),
}

var _portrait: TextureRect
var _placeholder: ColorRect
var _initial: Label
var _name_label: Label
var _info_label: Label
var _actions: VBoxContainer

func _init() -> void:
	custom_minimum_size = Vector2(150, 0)
	var box := VBoxContainer.new()
	add_child(box)

	var art := Control.new()
	art.custom_minimum_size = Vector2(138, 120)
	art.clip_contents = true
	box.add_child(art)
	_placeholder = ColorRect.new()
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(_placeholder)
	_initial = Label.new()
	_initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.add_theme_font_size_override("font_size", 56)
	art.add_child(_initial)
	_portrait = TextureRect.new()
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.add_child(_portrait)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name_label)
	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_info_label)
	_actions = VBoxContainer.new()
	box.add_child(_actions)

func set_character(c: CharacterData, extra: String = "") -> void:
	_name_label.text = c.display_name
	var info := "%s · %s" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class)]
	if not extra.is_empty():
		info += "\n" + extra
	_info_label.text = info

	if c.portrait:
		_portrait.texture = c.portrait
		_placeholder.hide()
		_initial.hide()
	else:
		_portrait.texture = null
		_placeholder.color = RARITY_COLORS[c.rarity]
		_initial.text = c.display_name.left(1)
		_placeholder.show()
		_initial.show()

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.border_color = RARITY_COLORS[c.rarity]
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)

func add_action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	_actions.add_child(button)
	return button
