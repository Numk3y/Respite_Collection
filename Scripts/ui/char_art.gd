class_name CharArt
extends Control
## Character art box. Shows the portrait if its image file exists; otherwise a placeholder with a
## class-coloured background, the name's first letter, and a caption.
## Either way it sits in an ornate CardFrame in the rarity's metal (gold SSR, silver SR, copper R) with the
## name on the bottom plate; small boxes get just the metal border plus a name/class caption.
## The size never changes, so real images can be dropped into Art/characters/ later without touching layout.

## Rarity accent colours (card borders and glows), matching the frame metals
const RARITY_COLORS := {
	CharacterData.Rarity.N: Color("#8a8f98"),
	CharacterData.Rarity.R: Color("#C8743F"),
	CharacterData.Rarity.SR: Color("#C3CCD8"),
	CharacterData.Rarity.SSR: Color("#E5B530"),
}
const CLASS_COLORS := {
	CharacterData.CharClass.TANK: Color("#3f5873"),
	CharacterData.CharClass.WARRIOR: Color("#9a5b1e"),
	CharacterData.CharClass.BERSERKER: Color("#9b2335"),
	CharacterData.CharClass.MAGE: Color("#6a3fb5"),
	CharacterData.CharClass.SHOOTER: Color("#2f7d5b"),
	CharacterData.CharClass.HEALER: Color("#c2507e"),
}
const MYSTERY_COLOR := Color("#2a2a3a")

var _background: PlaceholderPlate
var _initial: Label
var _caption: Label
var _portrait: TextureRect
var _frame: CardFrame
var _name := ""
var _class_text := ""

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background = _layer(PlaceholderPlate.new()) as PlaceholderPlate
	_initial = _layer(Label.new()) as Label
	_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_initial.modulate = Color(1, 1, 1, 0.35)

	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 13)
	var caption_style := StyleBoxFlat.new()
	caption_style.bg_color = Color(0, 0, 0, 0.45)
	caption_style.set_content_margin_all(4)
	_caption.add_theme_stylebox_override("normal", caption_style)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)

	_portrait = _layer(TextureRect.new()) as TextureRect
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frame = _layer(CardFrame.new()) as CardFrame

func _layer(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_initial.add_theme_font_size_override("font_size", maxi(int(size.y * 0.45), 8))
		_update_caption()

## `picture` overrides the portrait (e.g. the cut-in image); null uses the portrait
func set_character(c: CharacterData, picture: Texture2D = null) -> void:
	var texture := picture if picture else c.get_portrait()
	_portrait.texture = texture
	_portrait.visible = texture != null
	_set_colors(CLASS_COLORS.get(c.char_class, MYSTERY_COLOR), RARITY_COLORS[c.rarity])
	_frame.set_style(CardFrame.metal_for(c.rarity), c.display_name)
	_initial.text = c.display_name.left(1).to_upper()
	_name = c.display_name
	_class_text = Terms.class_label(c.char_class)
	_caption.visible = texture == null
	_update_caption()

## A "?" card, e.g. for an empty pick-up slot on a banner
func set_mystery(caption: String) -> void:
	_portrait.texture = null
	_portrait.hide()
	_set_colors(MYSTERY_COLOR, Color("#55556a"))
	_frame.set_style(CardFrame.Metal.IRON, "")
	_initial.text = "?"
	_name = ""
	_class_text = caption
	_caption.show()
	_update_caption()

## The full frame shows the name on its plate, so the placeholder caption only adds the class, just above it;
## compact boxes have no plate and show both
## (uses this box's own size: the frame child may not have been resized yet when this runs)
func _update_caption() -> void:
	if CardFrame.compact_at(size):
		_caption.text = _class_text if _name.is_empty() else "%s\n%s" % [_name, _class_text]
		_caption.offset_bottom = 0
	else:
		_caption.text = _class_text
		_caption.offset_bottom = -CardFrame.plate_height_at(size) - 2

func _set_colors(background: Color, frame: Color) -> void:
	_background.color = background
	_background.accent = frame
	_background.queue_redraw()

## Placeholder background: the class colour as a gradient (lighter top, deep bottom), faint diagonal light
## stripes, a soft rarity-coloured glow behind the initial and a bottom shade for the caption
class PlaceholderPlate extends Control:
	var color := Color("#2a2a3a")
	var accent := Color.WHITE

	func _init() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UITheme.draw_vertical_gradient(self, r, color.lightened(0.18), color.darkened(0.55))
		UITheme.draw_glow(self, size * Vector2(0.5, 0.42), size.x * 0.6, Color(accent, 0.35))
		var stripe := Color(1, 1, 1, 0.05)
		var x := -size.y
		while x < size.x:
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), stripe, 6.0)
			x += 22.0
		UITheme.draw_vertical_gradient(self, Rect2(0, size.y * 0.7, size.x, size.y * 0.3), Color(0, 0, 0, 0), Color(0, 0, 0, 0.35))
