class_name CollectionTab
extends VBoxContainer
## Friends screen, gacha character-list style: a "FRIENDS" banner with how many of the recruitable friends are
## collected, sort buttons and class filters, then a grid of tall cards: framed portrait, class badge, level,
## gold stars, Ascension pips and In Team / Working tags. Friends in a gacha pool that aren't owned yet show
## as dark "???" cards. It's alive: sparkles drift across the page, cards rise in when the tab opens and lift
## and glow on hover, a sheen sweeps across SR/SSR cards every few seconds and gold motes circle the SSRs.
## Main owns the details window: it listens to details_requested and calls refresh() when the roster changes.

signal details_requested(uid: int)

const CARD_SIZE := Vector2(150, 240)
const ART_SIZE := Vector2(134, 178)
const SORTS := ["rarity", "level", "class", "name"]
const ALL := -1  # class filter: everyone

var _summary: Label
var _meter: Meter
var _grid: HFlowContainer
var _sort := "rarity"
var _filter := ALL
var _sort_buttons := {}
var _filter_buttons := {}
var _shown_once := false

func _init() -> void:
	add_theme_constant_override("separation", 8)
	add_child(_build_header())
	add_child(_build_controls())

	var stage := Control.new()  # the grid's scroll area with a sparkle layer behind it
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stage)
	var sparkles := Sparkles.new()
	sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(sparkles)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)  # room for the hover lift and glow
	scroll.add_child(margin)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	margin.add_child(_grid)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_animate_in())

func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#ff4f8b").darkened(0.15)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color("#ff4f8b", 0.35)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_label(Terms.term("characters").to_upper(), 24, Color.WHITE))
	header.add_child(plate)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 3)
	header.add_child(right)
	_summary = _label("", 15, UITheme.TEXT)
	right.add_child(_summary)
	_meter = Meter.new()
	_meter.custom_minimum_size = Vector2(260, 8)
	_meter.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(_meter)
	return header

## Sort buttons on the left, class filter chips on the right
func _build_controls() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label(Terms.t("collection_sort"), 13, UITheme.TEXT_DIM))
	var sort_group := ButtonGroup.new()
	for key in SORTS:
		var button := _chip(Terms.t("collection_sort_" + key), sort_group)
		button.button_pressed = key == _sort
		button.pressed.connect(func():
			_sort = key
			refresh())
		row.add_child(button)
		_sort_buttons[key] = button
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var filter_group := ButtonGroup.new()
	var classes := [ALL, CharacterData.CharClass.TANK, CharacterData.CharClass.WARRIOR, CharacterData.CharClass.BERSERKER,
		CharacterData.CharClass.MAGE, CharacterData.CharClass.SHOOTER, CharacterData.CharClass.HEALER]
	for cls in classes:
		var text := Terms.t("collection_all") if cls == ALL else Terms.class_label(cls)
		var button := _chip(text, filter_group)
		button.button_pressed = cls == _filter
		button.pressed.connect(func():
			_filter = cls
			refresh())
		row.add_child(button)
		_filter_buttons[cls] = button
	return row

func _chip(text: String, group: ButtonGroup) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	return button

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	return label

## Every friend a recruit pool can give, plus anyone owned that isn't in a pool any more
func _collectable() -> Array[CharacterData]:
	var out: Array[CharacterData] = []
	for pool in DB.pools:
		for entry in pool.entries:
			if entry.character and entry.character.enabled and not out.has(entry.character):
				out.append(entry.character)
	return out

## Rebuilds the grid from the save (owned friends first, then the uncollected ones as "???" cards)
func refresh() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var owned: Array[Dictionary] = []  # {"uid", "c"}
	var owned_chars: Array[CharacterData] = []
	for o in GameState.data.owned:
		var c := GameState.get_character(int(o.uid))
		if c:
			owned.append({"uid": int(o.uid), "c": c})
			owned_chars.append(c)
	var collectable := _collectable()
	var collected := collectable.filter(func(c): return owned_chars.has(c)).size()
	_summary.text = Terms.t("collection_summary", {"owned": collected, "total": collectable.size()})
	_meter.share = float(collected) / maxf(collectable.size(), 1.0)

	var shown: Array = owned.filter(func(o): return _filter == ALL or o.c.char_class == _filter)
	shown.sort_custom(_compare)
	for o in shown:
		_grid.add_child(_card(o.uid, o.c))
	var missing := collectable.filter(func(c): return not owned_chars.has(c) and (_filter == ALL or c.char_class == _filter))
	for c in missing:
		_grid.add_child(_mystery_card())
	if _shown_once and is_visible_in_tree():
		_animate_in.call_deferred()

func _compare(a: Dictionary, b: Dictionary) -> bool:
	var ca: CharacterData = a.c
	var cb: CharacterData = b.c
	var la := int(GameState.get_owned(a.uid).level)
	var lb := int(GameState.get_owned(b.uid).level)
	match _sort:
		"level":
			if la != lb:
				return la > lb
		"class":
			if ca.char_class != cb.char_class:
				return ca.char_class < cb.char_class
		"name":
			return ca.display_name.nocasecmp_to(cb.display_name) < 0
	if ca.rarity != cb.rarity:
		return ca.rarity > cb.rarity
	if la != lb:
		return la > lb
	return ca.display_name.nocasecmp_to(cb.display_name) < 0

func _card(uid: int, c: CharacterData) -> Control:
	var rarity_color: Color = CharArt.RARITY_COLORS[c.rarity]
	var holder := Control.new()  # keeps the grid slot still while the card inside lifts and scales
	holder.custom_minimum_size = CARD_SIZE
	var card := Button.new()
	card.size = CARD_SIZE
	card.pivot_offset = CARD_SIZE / 2.0
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = Terms.t("collection_card_tip", {"name": c.display_name})
	var normal := UITheme.glow_box(Color(0.06, 0.08, 0.14, 0.94), 10, 6, rarity_color)
	normal.border_color = rarity_color
	normal.set_border_width_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.13, 0.22, 0.96)
	hover.shadow_size = 20
	hover.border_color = rarity_color.lightened(0.4)
	for state in ["normal", "focus", "disabled"]:
		card.add_theme_stylebox_override(state, normal)
	for state in ["hover", "pressed"]:
		card.add_theme_stylebox_override(state, hover)
	card.pressed.connect(details_requested.emit.bind(uid))
	card.mouse_entered.connect(_hover.bind(card, true))
	card.mouse_exited.connect(_hover.bind(card, false))
	holder.add_child(card)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var art_holder := Control.new()
	art_holder.custom_minimum_size = ART_SIZE
	art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_holder.clip_contents = true  # keeps the sheen inside the picture
	box.add_child(art_holder)
	var awakened := GameState.get_ascension(uid) >= GameState.MAX_ASCENSION
	var art := CharArt.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.set_character(c, c.get_portrait_at(GameState.get_ascension(uid)))
	art_holder.add_child(art)
	if awakened:
		art_holder.add_child(AwakenGlow.new())
	elif c.rarity >= CharacterData.Rarity.SR:
		var sheen := Sheen.new(c.rarity == CharacterData.Rarity.SSR)
		sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art_holder.add_child(sheen)
	var badge := TeamTab.ClassBadge.new(c.char_class)
	badge.position = Vector2(-3, -3)
	art_holder.add_child(badge)
	var o := GameState.get_owned(uid)
	var level := _label("%s%d" % [Terms.term("level"), int(o.level)], 16, Color.WHITE)
	level.add_theme_constant_override("outline_size", 7)
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.size = Vector2(ART_SIZE.x - 6, 22)
	level.position = Vector2(0, 2)
	art_holder.add_child(level)
	# In Team / Working tags, stacked above the name plate
	var tags: Array[Control] = []
	if GameState.team_slot_of(uid) >= 0:
		tags.append(UITheme.tag(Terms.t("collection_in_team"), UITheme.CYAN))
	var job := Commissions.worker_commission(uid)
	if job:
		var working := UITheme.tag(Terms.t("team_working"), UITheme.TEAL)
		working.tooltip_text = Terms.t("card_on_shift", {"job": job.display_name})
		tags.append(working)
	for i in tags.size():
		tags[i].position = Vector2(5, ART_SIZE.y - 48 - 24 * i)  # just above the name plate
		art_holder.add_child(tags[i])

	var marks := HBoxContainer.new()
	marks.alignment = BoxContainer.ALIGNMENT_CENTER
	marks.add_theme_constant_override("separation", 6)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(marks)
	var stars := GachaBanner.StarRow.new(12.0, rarity_color.lightened(0.15) if c.rarity < CharacterData.Rarity.SSR else UITheme.GOLD)
	stars.count = GachaBanner.STAR_COUNTS.get(c.rarity, 3)
	marks.add_child(stars)
	var rank := GameState.get_ascension(uid)
	var pips := TeamTab.AscensionPips.new(rank, GameState.MAX_ASCENSION, rarity_color)
	pips.tooltip_text = Terms.t("asc_short", {"rank": rank, "max": GameState.MAX_ASCENSION})
	marks.add_child(pips)
	var info := _label("%s · %s" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class)], 13, rarity_color.lightened(0.2))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)

	if c.rarity == CharacterData.Rarity.SSR:
		holder.add_child(_motes())
	return holder

## A friend you haven't recruited yet: a dark card with a big "?" and "???"
func _mystery_card() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = CARD_SIZE
	var panel := PanelContainer.new()
	panel.size = CARD_SIZE
	panel.tooltip_text = Terms.t("collection_missing_tip")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.85)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	holder.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var art := CharArt.new()
	art.custom_minimum_size = ART_SIZE
	art.set_mystery("")
	art.modulate = Color(0.55, 0.55, 0.65)
	box.add_child(art)
	var label := _label(Terms.t("collection_missing"), 16, UITheme.TEXT_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return holder

## A few gold motes circling an SSR card
func _motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = CARD_SIZE / 2.0
	p.amount = 7
	p.lifetime = 2.4
	p.preprocess = 2.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = CARD_SIZE / 2.0 + Vector2(4, 4)
	p.direction = Vector2.UP
	p.spread = 30.0
	p.gravity = Vector2(0, -14)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 18.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.45
	p.texture = Sparkles.dot()
	p.color = UITheme.GOLD
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	return p

func _hover(card: Control, on: bool) -> void:
	var t := card.create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	t.tween_property(card, "position:y", -7.0 if on else 0.0, 0.14)
	t.tween_property(card, "scale", Vector2(1.04, 1.04) if on else Vector2.ONE, 0.14)

## Cards rise in a few at a time when the tab opens (or the list changes while it's open)
func _animate_in() -> void:
	_shown_once = true
	var cards := _grid.get_children().filter(func(n): return not n.is_queued_for_deletion())
	if cards.is_empty():
		return
	var t := create_tween().set_parallel()
	for i in cards.size():
		var inner: Control = cards[i].get_child(0)
		inner.position.y = 34.0
		inner.modulate.a = 0.0
		var delay := 0.03 * mini(i, 20)
		t.tween_property(inner, "position:y", 0.0, 0.38).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(inner, "modulate:a", 1.0, 0.25).set_delay(delay)

## Soft sparkles drifting up behind the grid
class Sparkles extends Control:
	static var _dot: Texture2D

	static func dot() -> Texture2D:
		if _dot == null:
			var gradient := Gradient.new()
			gradient.set_color(0, Color.WHITE)
			gradient.set_color(1, Color(1, 1, 1, 0))
			var texture := GradientTexture2D.new()
			texture.gradient = gradient
			texture.fill = GradientTexture2D.FILL_RADIAL
			texture.fill_from = Vector2(0.5, 0.5)
			texture.fill_to = Vector2(1.0, 0.5)
			texture.width = 24
			texture.height = 24
			_dot = texture
		return _dot

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		for spec in [[Color("#ff8fc8"), 22], [Color("#8fdcff"), 22], [UITheme.GOLD, 10]]:
			var p := CPUParticles2D.new()
			p.amount = spec[1]
			p.lifetime = 7.0
			p.preprocess = 7.0
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.direction = Vector2.UP
			p.spread = 20.0
			p.gravity = Vector2(0, -6)
			p.initial_velocity_min = 8.0
			p.initial_velocity_max = 24.0
			p.scale_amount_min = 0.2
			p.scale_amount_max = 0.7
			p.texture = dot()
			p.color = spec[0]
			var fade := Gradient.new()
			fade.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
			fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
			p.color_ramp = fade
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			p.material = add
			add_child(p)
			resized.connect(func():
				p.position = size / 2.0
				p.emission_rect_extents = size / 2.0)

## A band of light that sweeps diagonally across the picture every few seconds (brighter, more often on SSR)
class Sheen extends Control:
	var _t := 0.0
	var _period := 4.0
	var _strength := 0.22

	func _init(ssr: bool) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_period = 3.2 if ssr else 5.0
		_strength = 0.3 if ssr else 0.18
		_t = randf() * _period  # cards don't all shine at once

	func _process(delta: float) -> void:
		_t = fmod(_t + delta, _period)
		queue_redraw()

	func _draw() -> void:
		var sweep := 0.9  # seconds the band takes to cross; the rest of the period it rests off-card
		if _t > sweep:
			return
		var k := _t / sweep
		var x := lerpf(-size.x * 0.6, size.x * 1.4, k)
		var w := size.x * 0.28
		var slant := size.y * 0.35
		var band := PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w - slant, size.y), Vector2(x - slant, size.y)])
		draw_colored_polygon(band, Color(1, 1, 1, _strength * sin(k * PI)))

## The collection meter under the summary
class Meter extends Control:
	var share := 0.0:
		set(value):
			share = value
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(1, 1, 1, 0.08))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(share, 0.0, 1.0), size.y)), Color("#ff6fa8"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(share, 0.0, 1.0), size.y * 0.4)), Color(1, 1, 1, 0.25))
