class_name CasinoTab
extends VBoxContainer
## Casino lobby: pick who to gamble with. The chosen game replaces the lobby until its Back button is pressed
## (games only allow that between rounds, so a bet is never left hanging).
## The lobby is a neon-lit room: a flickering "CASINO" sign, gold and pink lights drifting behind, and a panel per
## game glowing in its host's colour that lifts on hover, with a sheen sweeping across the host's portrait.

const NPC_ART_DIR := "res://Art/npcs/"
const PORTRAIT_SIZE := Vector2(150, 200)
const BOGSY_COLOR := Color("#5b3a1a")
const NILLA_COLOR := Color("#4a1d3f")
const BOGSY_GLOW := Color("#ffc94a")
const NILLA_GLOW := Color("#ff5fa2")

func _ready() -> void:
	_show_lobby()

func _show_lobby() -> void:
	for child in get_children():
		child.queue_free()
	var stage := Control.new()  # lights drifting behind the lobby's content
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stage)
	var fx := CasinoFX.new()
	stage.add_child(fx)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 14)
	stage.add_child(content)

	content.add_child(NeonSign.new(Terms.t("casino_sign")))
	var intro := Label.new()
	intro.text = Terms.t("casino_intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	content.add_child(intro)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	var panels: Array[Control] = [
		_game_panel("bogsy", Terms.term("dealer_name"), BOGSY_COLOR, BOGSY_GLOW, Terms.t("bj_title"), Terms.t("bj_blurb"),
			func(): _open(BlackjackTab.new())),
		_game_panel("nilla", Terms.term("roulette_host"), NILLA_COLOR, NILLA_GLOW, Terms.t("rr_title"),
			Terms.t("rr_blurb", RouletteTab.range_args()), func(): _open(RouletteTab.new())),
	]
	for i in panels.size():
		var panel := panels[i]
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(panel)
		# Fade in one after the other (a fade, because the row resets its children's position and scale when it
		# lays them out)
		panel.modulate.a = 0.0
		panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.4).set_delay(0.15 * i)

func _game_panel(id: String, host: String, color: Color, glow: Color, title_text: String, blurb: String, play: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS  # hover works while the Play button inside still gets clicks
	var normal := UITheme.glow_box(Color(0.07, 0.06, 0.12, 0.92), 12, 14, glow)
	normal.border_color = glow.darkened(0.2)
	normal.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", normal)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var portrait := npc_portrait(id, host, color)
	var sheen := CollectionTab.Sheen.new(true)
	sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(sheen)
	box.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	box.add_child(info)
	var title := Label.new()
	title.text = title_text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", glow)
	title.add_theme_color_override("font_shadow_color", Color(glow, 0.5))
	title.add_theme_constant_override("shadow_outline_size", 8)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	info.add_child(title)
	var text := Label.new()
	text.text = blurb
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(text)
	var button := Button.new()
	button.text = Terms.t("casino_play")
	button.theme_type_variation = &"PrimaryButton"
	button.add_theme_font_size_override("font_size", 20)
	button.custom_minimum_size.y = 46
	button.pressed.connect(play)
	info.add_child(button)
	# Hovering anywhere on the panel lifts it and brightens its glow
	var hover := normal.duplicate() as StyleBoxFlat
	hover.shadow_size = 24
	hover.border_color = glow.lightened(0.2)
	panel.mouse_entered.connect(func():
		panel.add_theme_stylebox_override("panel", hover)
		panel.create_tween().tween_property(panel, "position:y", -6.0, 0.15).set_trans(Tween.TRANS_SINE))
	panel.mouse_exited.connect(func():
		if panel.get_global_rect().has_point(panel.get_global_mouse_position()):
			return  # moved onto the Play button inside the panel
		panel.add_theme_stylebox_override("panel", normal)
		panel.create_tween().tween_property(panel, "position:y", 0.0, 0.15).set_trans(Tween.TRANS_SINE))
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

## A neon sign: glowing pink letters that buzz and now and then flicker off for a moment
class NeonSign extends Label:
	var _t := 0.0
	var _next_flicker := 2.0

	func _init(text_value: String) -> void:
		text = text_value
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_font_size_override("font_size", 46)
		add_theme_color_override("font_color", Color("#ffd1e6"))
		add_theme_color_override("font_outline_color", Color("#ff5fa2"))
		add_theme_constant_override("outline_size", 6)
		add_theme_color_override("font_shadow_color", Color("#ff5fa2", 0.75))
		add_theme_constant_override("shadow_outline_size", 22)
		add_theme_constant_override("shadow_offset_x", 0)
		add_theme_constant_override("shadow_offset_y", 0)

	func _process(delta: float) -> void:
		_t += delta
		var hum := 0.92 + 0.08 * sin(_t * 9.0)  # the tube's steady buzz
		if _t >= _next_flicker:
			# A quick double flicker, then wait a few seconds for the next one
			var k := _t - _next_flicker
			hum = 0.35 if (k < 0.06 or (k > 0.12 and k < 0.17)) else hum
			if k > 0.25:
				_next_flicker = _t + randf_range(2.5, 6.0)
		modulate = Color(1, 1, 1, hum)
