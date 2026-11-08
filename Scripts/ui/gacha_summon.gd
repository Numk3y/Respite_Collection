class_name GachaSummon
extends Control
## The full-screen recruit animation, played over the whole window after a pull.
## Each result gets its own reveal: a crystal drops in glowing in its rarity colour while light streams into it
## (longer, with the screen shaking, for an SSR), a white flash bursts it, and the friend's art fills the screen
## over turning rays (rainbow for an SSR), with a name plate: rarity, stars popping in one by one, name, class and
## NEW! / Ascension note. Every crystal glows in its own friend's rarity (no teasing with a better colour).
## A pull of several opens on a lineup first: every crystal drops into a grid in its colour. Now and then one or two
## start a tier low and, once all have landed, tremble and burst up to their real colour. That's only for show:
## a crystal never shows a colour above the friend inside, and always ends on the true one.
## The lineup and every SSR reveal always play in full. Otherwise clicking anywhere while a reveal plays jumps to its
## finished state, and clicking again plays the next one. Skip All (after the lineup) jumps to the next SSR still to
## come, or to the end when there are none. A pull of several ends on a summary grid of everything; a single pull
## closes on the next click.

signal finished

enum Phase { LINEUP, LINEUP_DONE, PLAYING, REVEALED, SUMMARY }

const COLORS := {
	CharacterData.Rarity.N: Color("#9aa3b0"),
	CharacterData.Rarity.R: Color("#e08a4f"),
	CharacterData.Rarity.SR: Color("#b9d2ff"),
	CharacterData.Rarity.SSR: Color("#ffd23f"),
}
const CHARGE_SEC := 0.75  # light streaming into the crystal
const SSR_CHARGE_SEC := 1.35
const ART_SHADER := preload("res://Shaders/banner_art.gdshader")
const LINEUP_GAP_SEC := 0.09  # between crystals dropping into the lineup
const LINEUP_SCALE := 0.42
const LINEUP_SPACING := Vector2(118, 150)
## Chance a crystal holding this rarity starts the lineup one tier low and upgrades (at most MAX_UPGRADES per pull)
const UPGRADE_CHANCE := {CharacterData.Rarity.SR: 0.08, CharacterData.Rarity.SSR: 0.15}
const MAX_UPGRADES := 2
const UPGRADE_CHARGE_SEC := 0.46  # the tremble before the burst (matches the rise of the "ultimate" sound at 1.2x)
const PING_PITCH := {CharacterData.Rarity.R: 1.0, CharacterData.Rarity.SR: 1.12, CharacterData.Rarity.SSR: 1.26}

var _results: Array[Dictionary] = []
var _notes: Array[String] = []
var _index := -1
var _phase := Phase.PLAYING
var _step: Tween  # the reveal currently playing; killed when the player clicks through

var _bg: Backdrop
var _fx: BattleFX
var _stream: CPUParticles2D
var _crystal: Crystal
var _art: TextureRect
var _plate: VBoxContainer
var _rarity: Label
var _stars: GachaBanner.StarRow
var _name: Label
var _class: Label
var _note: Label
var _counter: Label
var _hint: Label
var _skip: Button
var _flash: ColorRect
var _summary: Control
var _lineup_layer: Control
var _lineup: Array[Crystal] = []  # one per result, same index
var _shown: Array[int] = []  # the rarity each lineup crystal is showing right now

func _init() -> void:
	top_level = true  # covers the whole window
	z_index = 95
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = _full(Backdrop.new()) as Backdrop
	_fx = _full(BattleFX.new()) as BattleFX
	_stream = CPUParticles2D.new()
	_stream.emitting = false
	_stream.amount = 70
	_stream.lifetime = 0.55
	_stream.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
	_stream.emission_ring_radius = 300.0
	_stream.emission_ring_inner_radius = 220.0
	_stream.gravity = Vector2.ZERO
	_stream.radial_accel_min = -900.0
	_stream.radial_accel_max = -700.0
	_stream.scale_amount_min = 0.3
	_stream.scale_amount_max = 0.8
	_stream.texture = CollectionTab.Sparkles.dot()
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.2)])
	_stream.color_ramp = fade
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_stream.material = add
	add_child(_stream)
	_crystal = Crystal.new()
	add_child(_crystal)
	_lineup_layer = _full(Control.new())

	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ART_SHADER
	mat.set_shader_parameter("fade_left", 0.2)
	mat.set_shader_parameter("fade_right", 0.2)
	mat.set_shader_parameter("fade_bottom", 0.22)
	mat.set_shader_parameter("fade_top", 0.12)
	mat.set_shader_parameter("living", 1.0)  # the revealed friend moves in a Live2D-style idle
	_art.material = mat
	add_child(_art)

	_plate = VBoxContainer.new()
	_plate.add_theme_constant_override("separation", 2)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	_rarity = _label(72, Color.WHITE)
	_rarity.add_theme_constant_override("outline_size", 14)
	_plate.add_child(_rarity)
	_stars = GachaBanner.StarRow.new(30.0, UITheme.GOLD)
	_plate.add_child(_stars)
	_name = _label(46, Color.WHITE)
	_name.add_theme_constant_override("outline_size", 12)
	_plate.add_child(_name)
	_class = _label(20, UITheme.TEXT)
	_plate.add_child(_class)
	_note = _label(22, Color("#ff7ab8"))
	_plate.add_child(_note)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(_flash)

	_counter = _label(20, UITheme.TEXT_DIM)
	add_child(_counter)
	_hint = _label(18, Color(1, 1, 1, 0.8))
	_hint.text = Terms.t("summon_tap")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_skip = Button.new()
	_skip.text = Terms.t("summon_skip")
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(_skip_all)
	add_child(_skip)

func _full(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	return node

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	return label

## Starts the show. `notes` is one line per result (NEW!, Ascension up, ...).
func open(results: Array[Dictionary], notes: Array[String]) -> void:
	_results = results
	_notes = notes
	global_position = Vector2.ZERO
	size = get_viewport_rect().size
	_counter.position = Vector2(24, 18)
	_skip.position = Vector2(size.x - 150, 14)
	_skip.size = Vector2(130, 40)
	_skip.visible = results.size() > 1
	_hint.size = Vector2(size.x, 30)
	_hint.position = Vector2(0, size.y - 46)
	var blink := _hint.create_tween().set_loops()
	blink.tween_property(_hint, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)
	blink.tween_property(_hint, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)
	Sound.prepare(["crystal", "ultimate"])
	if results.size() > 1:
		_start_lineup()
	else:
		_next()

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			and not (event is InputEventScreenTouch and event.pressed):
		return
	accept_event()
	match _phase:
		Phase.LINEUP:
			pass  # the lineup always plays in full
		Phase.LINEUP_DONE:
			_leave_lineup()
		Phase.PLAYING:
			if not _current_is_ssr():  # an SSR's reveal always plays in full
				_finish_reveal()  # jump to the finished state of this one
		Phase.REVEALED:
			_next()

# ───────── Lineup (pulls of several) ─────────

## Every crystal drops into a grid (rows of 5) in its colour, then any that started a tier low upgrade one by one
func _start_lineup() -> void:
	_phase = Phase.LINEUP
	_hint.visible = false
	_skip.visible = false  # back once the lineup has finished
	_counter.text = ""
	for node: CanvasItem in [_crystal, _art, _plate]:  # the one-by-one reveal's pieces wait unseen
		node.modulate.a = 0.0
	_bg.set_color(COLORS[CharacterData.Rarity.R].lerp(Color.WHITE, 0.5), false)
	_bg.intensity = 0.25
	var n := _results.size()
	# Which crystals start a tier low: picked in random order so the cap doesn't favour the first slots
	_shown.clear()
	for r in _results:
		_shown.append(int(r.rarity))
	var upgraded: Array[int] = []
	var order := range(n)
	order.shuffle()
	for i: int in order:
		if upgraded.size() < MAX_UPGRADES and randf() < UPGRADE_CHANCE.get(_shown[i], 0.0):
			_shown[i] -= 1
			upgraded.append(i)
	upgraded.sort()

	_step = create_tween().set_parallel()
	for i in n:
		var crystal := Crystal.new()
		crystal.color = COLORS.get(_shown[i], Color.WHITE)
		var center := _lineup_slot(i)
		crystal.position = center - Crystal.SIZE / 2.0 + Vector2(0, -160)
		crystal.scale = Vector2.ZERO
		crystal.modulate.a = 0.0
		_lineup_layer.add_child(crystal)
		_lineup.append(crystal)
		var delay := LINEUP_GAP_SEC * i
		_step.tween_property(crystal, "position:y", center.y - Crystal.SIZE.y / 2.0, 0.3).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_step.tween_property(crystal, "scale", Vector2.ONE * LINEUP_SCALE, 0.3).set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_step.tween_property(crystal, "modulate:a", 1.0, 0.12).set_delay(delay)
		_step.tween_callback(_ping.bind(i)).set_delay(delay + 0.22)
	# Then the upgrades, one at a time: the crystal trembles and glows, then bursts into its real colour
	var t := LINEUP_GAP_SEC * n + 0.6
	for i in upgraded:
		_step.tween_callback(Sound.play.bind("ultimate", -3.0, 1.2)).set_delay(t)
		_step.tween_property(_lineup[i], "charge", 1.0, UPGRADE_CHARGE_SEC).set_delay(t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_step.tween_callback(_upgrade.bind(i)).set_delay(t + UPGRADE_CHARGE_SEC)
		t += UPGRADE_CHARGE_SEC + 0.6
	_step.tween_callback(_lineup_done).set_delay(t + 0.2)

## A crystal lands: a glassy ping, higher for rarer colours, and a little spark
func _ping(i: int) -> void:
	Sound.play("crystal", -4.0, PING_PITCH.get(_shown[i], 1.0))
	var color: Color = COLORS.get(_shown[i], Color.WHITE)
	_fx.hit(_lineup_center(i), color, _shown[i] >= CharacterData.Rarity.SR)

func _lineup_center(i: int) -> Vector2:
	return _lineup[i].position + Crystal.SIZE / 2.0

## Where crystal `i` sits in the lineup grid (rows of 5, centred on the screen)
func _lineup_slot(i: int) -> Vector2:
	var n := _results.size()
	var grid := Vector2(mini(n, 5) - 1, ceili(n / 5.0) - 1)
	return size / 2.0 - grid * LINEUP_SPACING / 2.0 + Vector2(i % 5, floori(i / 5.0)) * LINEUP_SPACING

## A crystal that started a tier low bursts up to its real colour
func _upgrade(i: int) -> void:
	var rarity := int(_results[i].rarity)
	var color: Color = COLORS.get(rarity, Color.WHITE)
	var crystal := _lineup[i]
	var center := _lineup_center(i)
	_shown[i] = rarity
	crystal.color = color
	crystal.charge = 0.0
	_fx.hit(center, color, true)
	_fx._ring(center, Color.WHITE, 150.0, 0.45)
	if rarity == CharacterData.Rarity.SSR:
		_fx.aura(center)
		_fx._burst(center, 40, 1.4, [UITheme.GOLD, Color("#ff7ab8"), Color("#7df9ff"), Color.WHITE], true)
	_bg.set_color(color, rarity == CharacterData.Rarity.SSR)
	_bg.intensity = 0.6
	var pop := crystal.create_tween()
	pop.tween_property(crystal, "scale", Vector2.ONE * LINEUP_SCALE * 1.35, 0.08)
	pop.tween_property(crystal, "scale", Vector2.ONE * LINEUP_SCALE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Everything has landed (and upgraded): the backdrop takes the best colour and waits for a click
func _lineup_done() -> void:
	_phase = Phase.LINEUP_DONE
	var best := 0
	for r in _results:
		best = maxi(best, int(r.rarity))
	_bg.set_color(COLORS.get(best, Color.WHITE), best == CharacterData.Rarity.SSR)
	_bg.intensity = maxf(_bg.intensity, 0.5)
	_hint.text = Terms.t("summon_tap")
	_hint.visible = true
	_skip.visible = true

## On to the one-by-one reveals: the lineup fades out as the first crystal drops in
func _leave_lineup() -> void:
	_fade_lineup()
	_next()

func _fade_lineup() -> void:
	if not _lineup_layer.visible:
		return
	var t := _lineup_layer.create_tween()
	t.tween_property(_lineup_layer, "modulate:a", 0.0, 0.25)
	t.tween_callback(func(): _lineup_layer.visible = false)

# ───────── One reveal ─────────

func _next() -> void:
	_index += 1
	if _index >= _results.size():
		if _results.size() > 1:
			_show_summary()
		else:
			_close()
		return
	_phase = Phase.PLAYING
	var r := _results[_index]
	var rarity: int = r.rarity
	var ssr := rarity == CharacterData.Rarity.SSR
	_counter.text = Terms.t("summon_counter", {"current": _index + 1, "total": _results.size()})
	_hint.visible = false
	_skip.disabled = ssr  # until it's revealed
	var color: Color = COLORS.get(rarity, Color.WHITE)
	var center := size / 2.0

	_place_reveal(r)  # laid out now (hidden) so the slide-in below knows where the plate ends up
	_art.modulate.a = 0.0
	_plate.modulate.a = 0.0
	_bg.set_color(color, false)
	_bg.intensity = 0.35
	_crystal.color = color
	_crystal.position = center - _crystal.size / 2.0 + Vector2(0, -60)
	_crystal.scale = Vector2.ZERO
	_crystal.charge = 0.0
	_crystal.modulate.a = 1.0
	_stream.position = center
	_stream.color = color
	var charge := SSR_CHARGE_SEC if ssr else CHARGE_SEC

	_step = create_tween()
	# The crystal drops in
	_step.tween_property(_crystal, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_step.parallel().tween_property(_crystal, "position:y", center.y - _crystal.size.y / 2.0, 0.3)
	# Light streams in while it charges up (an SSR shakes the screen as it builds)
	_step.tween_callback(func(): _stream.emitting = true)
	_step.tween_property(_crystal, "charge", 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_step.parallel().tween_property(_bg, "intensity", 1.0, charge)
	if ssr:
		_step.parallel().tween_method(func(k: float): position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 8.0 * k,
			0.0, 1.0, charge)
	# Burst: white flash, the crystal shatters, then the friend appears
	_step.tween_callback(func():
		_stream.emitting = false
		position = Vector2.ZERO
		_burst(r))
	_step.tween_property(_flash, "color:a", 0.95, 0.06)
	_step.tween_property(_flash, "color:a", 0.0, 0.45)
	_step.parallel().tween_property(_art, "modulate:a", 1.0, 0.35)
	_step.parallel().tween_property(_art, "scale", Vector2.ONE, 0.6).from(Vector2(1.15, 1.15)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_step.tween_property(_plate, "modulate:a", 1.0, 0.25)
	_step.parallel().tween_property(_plate, "position:x", _plate.position.x, 0.35).from(_plate.position.x + 80.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var stars: int = GachaBanner.STAR_COUNTS.get(rarity, 3)
	for i in stars:
		_step.tween_callback(func(): _stars.count = i + 1).set_delay(0.09 if not ssr else 0.14)
	if ssr:
		_step.tween_callback(func(): _fx.aura(_stars.global_position + _stars.size / 2.0))
	_step.tween_callback(_on_revealed)

## The crystal bursts: sparks and rings in the friend's rarity colour (an SSR also gets a golden aura and confetti)
func _burst(r: Dictionary) -> void:
	var color: Color = COLORS.get(int(r.rarity), Color.WHITE)
	var center := size / 2.0
	_crystal.modulate.a = 0.0
	_fx.hit(center, color, true)
	_fx._ring(center, Color.WHITE, 260.0, 0.5)
	if int(r.rarity) == CharacterData.Rarity.SSR:
		_fx.aura(center)
		_fx._burst(center, 60, 2.0, [UITheme.GOLD, Color("#ff7ab8"), Color("#7df9ff"), Color.WHITE], true)
	_bg.set_color(color, int(r.rarity) == CharacterData.Rarity.SSR)

## Lays out the friend's art and plate for result `r` (used by the animation and by a click-through)
func _place_reveal(r: Dictionary) -> void:
	var c: CharacterData = r.character
	var color: Color = COLORS.get(int(r.rarity), Color.WHITE)
	var texture := c.get_cutin()
	_art.texture = texture
	var h := size.y * 0.92
	var aspect := float(texture.get_width()) / texture.get_height() if texture else 0.75
	var w := h * minf(aspect, 0.8)
	_art.size = Vector2(w, h)
	_art.position = Vector2(size.x * 0.36 - w / 2.0, size.y - h)
	_art.pivot_offset = Vector2(w / 2.0, h)
	(_art.material as ShaderMaterial).set_shader_parameter("rect_size", _art.size)
	_art.visible = texture != null

	_rarity.text = Terms.rarity_name(c.rarity)
	_rarity.add_theme_color_override("font_color", color)
	_rarity.add_theme_color_override("font_shadow_color", Color(color, 0.7))
	_rarity.add_theme_constant_override("shadow_outline_size", 20)
	_rarity.add_theme_constant_override("shadow_offset_x", 0)
	_rarity.add_theme_constant_override("shadow_offset_y", 0)
	_stars.count = 0
	_name.text = c.display_name
	_class.text = "%s · %s" % [c.title, Terms.class_label(c.char_class)] if not c.title.is_empty() else Terms.class_label(c.char_class)
	_note.text = _notes[_index] if _index < _notes.size() else ""
	_note.add_theme_color_override("font_color", Color("#ff7ab8") if r.get("result", "") == "new" else UITheme.GOLD)
	_plate.reset_size()
	_plate.position = Vector2(size.x * 0.62, size.y * 0.5 - _plate.get_combined_minimum_size().y / 2.0)

func _on_revealed() -> void:
	_phase = Phase.REVEALED
	_skip.disabled = false
	_hint.visible = true
	_hint.text = Terms.t("summon_tap") if _index < _results.size() - 1 or _results.size() > 1 else Terms.t("summon_tap_close")

## Click during a reveal: drop the rest of the animation and show the result straight away
func _finish_reveal() -> void:
	if _step and _step.is_valid():
		_step.kill()
	var r := _results[_index]
	_stream.emitting = false
	position = Vector2.ZERO
	_crystal.modulate.a = 0.0
	_flash.color.a = 0.0
	_bg.set_color(COLORS.get(int(r.rarity), Color.WHITE), int(r.rarity) == CharacterData.Rarity.SSR)
	_bg.intensity = 1.0
	_place_reveal(r)
	_art.modulate.a = 1.0
	_art.scale = Vector2.ONE
	_plate.modulate.a = 1.0
	_stars.count = GachaBanner.STAR_COUNTS.get(int(r.rarity), 3)
	_on_revealed()

func _current_is_ssr() -> bool:
	return _index >= 0 and _index < _results.size() and int(_results[_index].rarity) == CharacterData.Rarity.SSR

## Skip All: on to the next SSR still to come (its reveal always plays), or to the summary when there are none.
## Does nothing during the lineup or while an SSR is being revealed.
func _skip_all() -> void:
	if _phase == Phase.LINEUP or _phase == Phase.SUMMARY or (_phase == Phase.PLAYING and _current_is_ssr()):
		return
	if _step and _step.is_valid():
		_step.kill()
	_stream.emitting = false
	position = Vector2.ZERO
	_flash.color.a = 0.0
	_fade_lineup()
	var next_ssr := -1
	for i in range(_index + 1, _results.size()):
		if int(_results[i].rarity) == CharacterData.Rarity.SSR:
			next_ssr = i
			break
	if next_ssr == -1:
		_index = _results.size() - 1
		_show_summary()
	else:
		_index = next_ssr - 1
		_next()

# ───────── Summary ─────────

## Everything from the pull in a grid that pops in tile by tile, with OK to close
func _show_summary() -> void:
	_phase = Phase.SUMMARY
	for node: CanvasItem in [_crystal, _art, _plate, _hint, _skip, _counter, _lineup_layer]:
		node.visible = false
	var best := 0
	for r in _results:
		best = maxi(best, int(r.rarity))
	_bg.set_color(COLORS.get(best, Color.WHITE), best == CharacterData.Rarity.SSR)
	_bg.intensity = 0.6
	_summary = VBoxContainer.new()
	(_summary as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_summary.add_theme_constant_override("separation", 18)
	_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_summary)
	var title := _label(34, Color.WHITE)
	title.text = Terms.t("summon_summary")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_summary.add_child(grid)
	for i in _results.size():
		var tile := _summary_tile(_results[i], _short_note(_results[i]))
		grid.add_child(tile)
		tile.modulate.a = 0.0
		var t := tile.create_tween()
		t.tween_property(tile, "modulate:a", 1.0, 0.2).set_delay(0.06 * i)
		if int(_results[i].rarity) == CharacterData.Rarity.SSR:
			t.tween_callback(func(): _fx.hit(tile.global_position + tile.size / 2.0, UITheme.GOLD, true))
	var ok := Button.new()
	ok.text = Terms.t("summon_ok")
	ok.theme_type_variation = &"PrimaryButton"
	ok.custom_minimum_size = Vector2(200, 52)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.add_theme_font_size_override("font_size", 20)
	ok.pressed.connect(_close)
	_summary.add_child(ok)

## A summary tile's note, short enough for its width: NEW!, Asc. 2/4, or +100 Money
func _short_note(r: Dictionary) -> String:
	match r.get("result", ""):
		"new":
			return Terms.t("new_badge")
		"ascend":
			return Terms.t("summon_short_ascend", {"rank": r.get("rank", 0), "max": GameState.MAX_ASCENSION})
		_:
			return Terms.t("summon_short_overflow", {"amount": r.get("money", 0)})

func _summary_tile(r: Dictionary, note: String) -> Control:
	var c: CharacterData = r.character
	var color: Color = COLORS.get(int(r.rarity), Color.WHITE)
	var panel := PanelContainer.new()
	var style := UITheme.glow_box(Color(0.05, 0.06, 0.1, 0.92), 10, 6, color)
	style.border_color = color
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var art := CharArt.new()
	art.custom_minimum_size = Vector2(112, 148)
	art.set_character(c)
	box.add_child(art)
	var line := _label(13, color.lightened(0.2) if r.get("result", "") != "new" else Color("#ff7ab8"))
	line.text = note
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.custom_minimum_size.x = 112
	line.clip_text = true
	box.add_child(line)
	return panel

func _close() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.25)
	t.tween_callback(func():
		finished.emit()
		queue_free())

## Dark backdrop with rays turning behind everything; brighter as `intensity` rises, rainbow for an SSR
class Backdrop extends Control:
	var intensity := 0.4:
		set(value):
			intensity = value
			queue_redraw()
	var _color := Color.WHITE
	var _rainbow := false
	var _angle := 0.0

	func set_color(color: Color, rainbow: bool) -> void:
		_color = color
		_rainbow = rainbow
		queue_redraw()

	func _process(delta: float) -> void:
		_angle += delta * (0.35 if _rainbow else 0.18)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UITheme.draw_vertical_gradient(self, r, Color(0.03, 0.03, 0.08, 0.96), Color(0.01, 0.01, 0.03, 0.98))
		var center := size / 2.0
		var reach := size.length()
		var count := 18
		for i in count:
			var a := _angle + TAU * i / count
			var half := TAU / count * 0.22
			var color := Color.from_hsv(fmod(i / float(count) + _angle * 0.2, 1.0), 0.6, 1.0) if _rainbow else _color
			draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(a - half) * reach,
				center + Vector2.from_angle(a + half) * reach]), Color(color, 0.05 + 0.07 * intensity))
		UITheme.draw_glow(self, center, size.y * (0.35 + 0.25 * intensity), Color(_color, 0.18 + 0.3 * intensity))

## The summon crystal: a faceted gem in the rarity colour that glows and trembles more as it charges
class Crystal extends Control:
	const SIZE := Vector2(150, 200)
	var color := Color.WHITE:
		set(value):
			color = value
			queue_redraw()
	var charge := 0.0:
		set(value):
			charge = value
			queue_redraw()
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = SIZE
		size = SIZE
		pivot_offset = SIZE / 2.0
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := SIZE / 2.0 + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 4.0 * charge
		var bob := sin(_t * 2.5) * 6.0
		c.y += bob
		UITheme.draw_glow(self, c, 90.0 + 70.0 * charge, Color(color, 0.35 + 0.45 * charge))
		var w := 52.0
		var h := 84.0
		var top := c + Vector2(0, -h)
		var bottom := c + Vector2(0, h)
		var left := c + Vector2(-w, -h * 0.15)
		var right := c + Vector2(w, -h * 0.15)
		var mid := c + Vector2(0, -h * 0.15)
		var light := color.lightened(0.45)
		var dark := color.darkened(0.25)
		draw_colored_polygon(PackedVector2Array([top, left, mid]), light)
		draw_colored_polygon(PackedVector2Array([top, mid, right]), color)
		draw_colored_polygon(PackedVector2Array([left, bottom, mid]), color)
		draw_colored_polygon(PackedVector2Array([mid, bottom, right]), dark)
		var outline := PackedVector2Array([top, right, bottom, left, top])
		draw_polyline(outline, Color(1, 1, 1, 0.6 + 0.4 * charge), 2.5, true)
		draw_line(left, right, Color(1, 1, 1, 0.35), 1.5, true)
		draw_line(top, mid, Color(1, 1, 1, 0.35), 1.5, true)
		draw_line(mid, bottom, Color(1, 1, 1, 0.25), 1.5, true)
		# A white core that swells as it charges
		draw_circle(c + Vector2(0, -h * 0.1), 6.0 + 22.0 * charge, Color(1, 1, 1, 0.25 + 0.6 * charge))
