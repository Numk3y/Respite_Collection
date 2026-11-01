class_name CasinoTab
extends VBoxContainer
## Casino lobby: pick who to gamble with. The chosen game replaces the lobby until its Back button is pressed
## (games only allow that between rounds, so a bet is never left hanging).

const NPC_ART_DIR := "res://Art/npcs/"
const PORTRAIT_SIZE := Vector2(150, 200)
const BOGSY_COLOR := Color("#5b3a1a")
const NILLA_COLOR := Color("#4a1d3f")

func _ready() -> void:
	_show_lobby()

func _show_lobby() -> void:
	for child in get_children():
		child.queue_free()
	var intro := Label.new()
	intro.text = Terms.t("casino_intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	add_child(intro)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.add_child(_game_panel("bogsy", Terms.term("dealer_name"), BOGSY_COLOR, Terms.t("bj_title"), Terms.t("bj_blurb"),
		func(): _open(BlackjackTab.new())))
	row.add_child(_game_panel("nilla", Terms.term("roulette_host"), NILLA_COLOR, Terms.t("rr_title"), Terms.t("rr_blurb", RouletteTab.range_args()),
		func(): _open(RouletteTab.new())))

func _game_panel(id: String, host: String, color: Color, title_text: String, blurb: String, play: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(npc_portrait(id, host, color))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	box.add_child(info)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	info.add_child(title)
	var text := Label.new()
	text.text = blurb
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(text)
	var button := Button.new()
	button.text = Terms.t("casino_play")
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size.y = 46
	button.pressed.connect(play)
	info.add_child(button)
	return panel

func _open(game: Control) -> void:
	for child in get_children():
		child.queue_free()
	game.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game.connect("back_pressed", _show_lobby)
	add_child(game)

## A host's picture from Art/npcs/<id>.png (or a coloured placeholder with their initial until it exists),
## set in a gold CardFrame with their name on the plate
static func npc_portrait(id: String, host: String, color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = PORTRAIT_SIZE
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := CharacterData.find_art(NPC_ART_DIR, id)
	if path != "":
		var art := TextureRect.new()
		art.texture = load(path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(art)
	else:
		var bg := ColorRect.new()
		bg.color = color
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(bg)
		var initial := Label.new()
		initial.text = host.left(1)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		initial.add_theme_font_size_override("font_size", 90)
		initial.modulate = Color(1, 1, 1, 0.35)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(initial)
	var frame := CardFrame.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.set_style(CardFrame.Metal.GOLD, host)
	holder.add_child(frame)
	return holder
