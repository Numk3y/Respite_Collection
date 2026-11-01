class_name CharCard
extends PanelContainer
## Character card: art (portrait or placeholder), name, rarity/class line, extra text and action buttons.
## Framed in the rarity colour with a matching glow that brightens on hover.

const RARITY_GLOW := {  # glow strength per rarity: rarer cards shine more
	CharacterData.Rarity.N: 0.0,
	CharacterData.Rarity.R: 0.25,
	CharacterData.Rarity.SR: 0.4,
	CharacterData.Rarity.SSR: 0.6,
}

var _art: CharArt
var _name_label: Label
var _info_label: Label
var _actions: VBoxContainer
var _style: StyleBoxFlat
var _hover_style: StyleBoxFlat

func _init() -> void:
	custom_minimum_size = Vector2(150, 0)
	var box := VBoxContainer.new()
	add_child(box)
	_art = CharArt.new()
	_art.custom_minimum_size = Vector2(138, 150)
	box.add_child(_art)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.visible = false  # the art's CardFrame already shows the name on its plate
	box.add_child(_name_label)
	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	box.add_child(_info_label)
	_actions = VBoxContainer.new()
	box.add_child(_actions)
	mouse_entered.connect(func(): add_theme_stylebox_override("panel", _hover_style))
	mouse_exited.connect(func(): add_theme_stylebox_override("panel", _style))

func set_character(c: CharacterData, extra: String = "") -> void:
	_art.set_character(c)
	_name_label.text = c.display_name
	var info := "%s · %s" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class)]
	if not extra.is_empty():
		info += "\n" + extra
	_info_label.text = info

	var rarity: Color = CharArt.RARITY_COLORS[c.rarity]
	var glow: float = RARITY_GLOW.get(c.rarity, 0.0)
	_style = UITheme.box(Color(UITheme.CARD, 0.95), rarity, 2, 10, 6)
	_style.border_width_top = 3
	_style.shadow_color = Color(rarity, glow) if glow > 0.0 else Color(0, 0, 0, 0.4)
	_style.shadow_size = 8
	_hover_style = _style.duplicate() as StyleBoxFlat
	_hover_style.bg_color = UITheme.CARD_HOVER
	_hover_style.border_color = rarity.lightened(0.3)
	_hover_style.shadow_color = Color(rarity, minf(glow + 0.35, 0.9))
	_hover_style.shadow_size = 16
	add_theme_stylebox_override("panel", _style)

func add_action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	_actions.add_child(button)
	return button
