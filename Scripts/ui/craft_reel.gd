class_name CraftReel
extends Control
## The crafting minigame: forging at the anvil. Covers the whole window. The new piece (drawn as a sword, a
## chestplate or a ring, by slot) lies on an anvil glowing hotter while a reel of quality cells runs sideways under
## a gold marker: +0 STANDARD, +1 FINE, +2 MASTERWORK. STRIKE! (or Space / Enter) brakes the reel while the hammer
## winds up; when it settles the hammer slams down, and the cell under the marker is the bonus: free upgrade levels
## on the piece. The piece is already made and paid for when this opens, so the reel can only add to it.
## It's a gamble: the reel spins far too fast to time, and braking takes a random 2.4-3.2 seconds, crawling past
## the last few cells for suspense. Odds come from STRIP: 60% STANDARD, 30% FINE, 10% MASTERWORK. Rarer gear spins
## faster. Feedback: the reel spins up and rattles, the result lands with sparks, a ring, a shake and a clang sized to
## the result; FINE adds a cyan glow and a chime, MASTERWORK a white flash, gold rays, confetti, a coin shower, a
## fanfare and a banner; landing next to a MASTERWORK says "So close!". Sounds are synthesised here (no audio files).
## Emits `finished(bonus)` once the result is closed.

signal finished(bonus: int)

## The reel, left to right; it loops. 6 x +0, 3 x +1, 1 x +2
const STRIP := [0, 1, 0, 0, 2, 0, 1, 0, 0, 1]
const SPIN_SPEED := {CharacterData.Rarity.R: 27.5, CharacterData.Rarity.SR: 35.0, CharacterData.Rarity.SSR: 42.5}  # cells per second
const SPIN_UP_SEC := 0.6
const BRAKE_SEC := Vector2(2.4, 3.2)  # how long the reel takes to stop after STRIKE (random in this range)
const BRAKE_POWER := 5.0  # quint ease-out: starts at 5x its average speed, so the last cells crawl past
const TICK_GAP_MS := 40  # at most one tick sound this often (the full-speed spin would otherwise buzz)
const CELL_COLORS := [Color("#9aa4b8"), Color("#1FD2FF"), Color("#FFE259")]
const SLAM_SHAKE := [6.0, 10.0, 18.0]

var _item: EquipmentData
var _speed := 6.0  # full spin speed for this rarity
var _spin := 0.0  # current speed (spins up from 0)
var _panel: PanelContainer
var _forge: Forge
var _reel: Reel
var _fx: CasinoFX
var _strike: Button
var _banner: Label
var _hint: Label
var _result: Label
var _stats: Label
var _continue: Button
var _state := "spin"  # spin -> braking -> landing -> done -> closed
var _bonus := 0
var _cell := 0  # the cell the reel landed on
var _last_cell := 0
var _last_tick_ms := 0
var _tick_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer

func _init(item: EquipmentData) -> void:
	_item = item
	_speed = SPIN_SPEED.get(item.rarity, 6.0)
	top_level = true  # covers the whole window, not just the tab it's added to
	z_index = 80
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_fit()
	get_viewport().size_changed.connect(_fit)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.015, 0.01, 0.9)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var accent: Color = CharArt.RARITY_COLORS.get(_item.rarity, UITheme.CYAN)
	_panel = PanelContainer.new()
	var style := UITheme.glow_box(Color(0.07, 0.05, 0.05, 0.97), 16, 18, Color("#ff8a3d"))
	style.border_color = accent
	style.set_border_width_all(2)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 600
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	box.add_child(_label(Terms.t("reel_title", {"item": CharacterDetail.gear_name(_item, 0)}), 24, accent.lightened(0.3)))
	_forge = Forge.new()
	_forge.slot = _item.slot
	_forge.custom_minimum_size = Vector2(560, 210)
	box.add_child(_forge)
	_banner = _label("", 40, CELL_COLORS[2])  # MASTERWORK! / FINE / So close! over the anvil
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 4
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.visible = false
	_forge.add_child(_banner)
	_reel = Reel.new()
	_reel.custom_minimum_size = Vector2(560, 112)
	box.add_child(_reel)
	_hint = _label(Terms.t("reel_hint"), 14, UITheme.TEXT_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	_result = _label("", 24, Color.WHITE)
	_result.visible = false
	box.add_child(_result)
	_stats = _label("", 17, Color("#86efac"))
	_stats.visible = false
	box.add_child(_stats)

	_strike = Button.new()
	_strike.text = Terms.t("reel_stop")
	_strike.theme_type_variation = &"PrimaryButton"
	_strike.custom_minimum_size = Vector2(260, 60)
	_strike.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_strike.add_theme_font_size_override("font_size", 26)
	_strike.focus_mode = Control.FOCUS_NONE
	_strike.disabled = true  # until the reel is up to speed
	_strike.pressed.connect(_stop)
	box.add_child(_strike)
	_continue = Button.new()
	_continue.text = Terms.t("reel_continue")
	_continue.custom_minimum_size = Vector2(200, 52)
	_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue.add_theme_font_size_override("font_size", 20)
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.visible = false
	_continue.pressed.connect(_close)
	box.add_child(_continue)

	_fx = CasinoFX.new()  # sparks, rings, coins, embers and casino lights over everything
	add_child(_fx)
	_tick_player = AudioStreamPlayer.new()
	_tick_player.max_polyphony = 4
	_tick_player.volume_db = -10.0
	add_child(_tick_player)
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.max_polyphony = 4
	_sfx_player.volume_db = -4.0
	add_child(_sfx_player)

	# Build the sounds now, while the window fades in, so the hit itself never hitches
	_prebuild_sounds.call_deferred()
	_reel.offset = float(randi() % STRIP.size()) + randf()  # start somewhere different each time
	_last_cell = floori(_reel.offset)
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.2)
	var spin := create_tween().set_parallel()
	spin.tween_property(self, "_spin", _speed, SPIN_UP_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	spin.tween_property(_forge, "heat", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	spin.chain().tween_callback(func(): _strike.disabled = _state != "spin")

func _prebuild_sounds() -> void:
	Sfx.tick()
	Sfx.clang()
	Sfx.chime([1046.5, 1568.0])
	Sfx.chime([783.99, 1046.5, 1318.5, 1568.0, 2093.0])

func _fit() -> void:
	global_position = Vector2.ZERO
	size = get_viewport_rect().size

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	return label

func _process(delta: float) -> void:
	if _state == "spin":
		_reel.offset += _spin * delta
	# A tick each time a cell passes the marker (spinning or braking)
	var cell := floori(_reel.offset + 0.5)
	if cell != _last_cell and (_state == "spin" or _state == "braking"):
		_last_cell = cell
		_reel.nudge()
		var now := Time.get_ticks_msec()
		if now - _last_tick_ms >= TICK_GAP_MS:
			_last_tick_ms = now
			_play(_tick_player, Sfx.tick(), randf_range(0.92, 1.08) * (1.0 if _state == "spin" else 0.85))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE):
		get_viewport().set_input_as_handled()
		if _state == "spin" and not _strike.disabled:
			_stop()
		elif _state == "done":
			_close()

## Brakes over a random BRAKE_SEC (a quint ease-out that starts at the spin speed and crawls at the end, landing
## exactly on a cell) while the hammer winds up. Where it stops is luck.
func _stop() -> void:
	if _state != "spin":
		return
	_state = "braking"
	_strike.disabled = true
	var spin := maxf(_spin, 1.0)
	var target := ceilf(_reel.offset + spin * randf_range(BRAKE_SEC.x, BRAKE_SEC.y) / BRAKE_POWER)
	var distance := target - _reel.offset
	var duration := BRAKE_POWER * distance / spin
	var t := create_tween()
	t.tween_property(_reel, "offset", target, duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	t.tween_callback(_land.bind(int(target)))
	var wind := create_tween()
	wind.tween_property(_forge, "hammer", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## The hammer comes down: sparks, a ring, a shake and a clang sized to the result, then the result text
func _land(cell: int) -> void:
	_state = "landing"
	_cell = cell
	_bonus = STRIP[posmod(cell, STRIP.size())]
	_reel.offset = cell
	_reel.lock(CELL_COLORS[_bonus])
	_strike.visible = false
	var t := create_tween()
	t.tween_property(_forge, "hammer", -0.15, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_impact)

func _impact() -> void:
	var color: Color = CELL_COLORS[_bonus]
	_forge.strike(color, _bonus)
	var anvil := _forge.global_position - _fx.global_position + _forge.item_center()
	_play(_sfx_player, Sfx.clang(), 1.0 - 0.06 * _bonus)
	_fx.shake(_panel, SLAM_SHAKE[_bonus], 0.35 + 0.1 * _bonus)
	match _bonus:
		0:
			_fx.hit(anvil, Color("#ff9a3d"))
		1:
			_fx.hit(anvil, color, false)
			_fx._ring(anvil, color, 160.0, 0.6)
			_fx._burst(anvil, 36, 1.3, [color, Color.WHITE, Color("#ff9a3d")], false)
			_play(_sfx_player, Sfx.chime([1046.5, 1568.0]), 1.0)
			_show_banner(Terms.t("reel_quality_1") + "  +1", color, 1.3)
		2:
			_fx.hit(anvil, color, true)
			_fx.aura(anvil)
			_fx._ring(anvil, Color.WHITE, 260.0, 0.8)
			_fx._burst(anvil, 60, 1.8, [color, Color.WHITE, Color("#ff9a3d"), Color("#ff6fa8")], false)
			_confetti()
			_fx.coins(Rect2(Vector2(size.x * 0.2, 0), Vector2(size.x * 0.6, 40)), 90)
			_flash()
			_play(_sfx_player, Sfx.chime([783.99, 1046.5, 1318.5, 1568.0, 2093.0]), 1.0)
			_show_banner(Terms.t("reel_quality_2") + "!", color, 1.8)
	# Landed right next to a MASTERWORK cell: say so
	if _bonus < 2:
		var n := STRIP.size()
		if STRIP[posmod(_cell - 1, n)] == 2 or STRIP[posmod(_cell + 1, n)] == 2:
			_show_banner(Terms.t("reel_close"), Color("#fca5a5"), 1.0)
	get_tree().create_timer(0.45).timeout.connect(_show_result)

func _show_banner(text: String, color: Color, pop: float) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	_banner.reset_size()
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2(pop, pop)
	_banner.modulate.a = 0.0
	var t := _banner.create_tween().set_parallel()
	t.tween_property(_banner, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_banner, "modulate:a", 1.0, 0.12)

func _show_result() -> void:
	_state = "done"
	var plus := mini(_bonus, GameState.GEAR_MAX_PLUS)
	var item_name := CharacterDetail.gear_name(_item, plus)
	_result.text = Terms.t("reel_result", {"item": item_name})
	_hint.visible = false  # the result takes its place, so the window keeps its size
	_result.add_theme_color_override("font_color", CELL_COLORS[_bonus].lightened(0.2) if _bonus > 0 else Color.WHITE)
	_result.visible = true
	# The stats it came out with, and what the bonus added
	var base := _item.modifiers(0)
	var final := _item.modifiers(plus)
	var parts: PackedStringArray = []
	for stat in final:
		if plus > 0 and final[stat] != base.get(stat, 0):
			parts.append("%s %+d → %+d" % [Terms.stat_short(stat), base.get(stat, 0), final[stat]])
		else:
			parts.append("%s %+d" % [Terms.stat_short(stat), final[stat]])
	_stats.text = "   ".join(parts)
	_stats.visible = true
	_continue.visible = true
	for node: Control in [_result, _stats, _continue]:
		node.modulate.a = 0.0
		node.create_tween().tween_property(node, "modulate:a", 1.0, 0.25)

func _close() -> void:
	if _state != "done":
		return
	_state = "closed"
	set_process_unhandled_input(false)
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(func():
		finished.emit(_bonus)
		queue_free())

func _play(player: AudioStreamPlayer, stream: AudioStream, pitch: float) -> void:
	player.stream = stream
	player.pitch_scale = pitch
	player.play()

## A white flash over the whole window (MASTERWORK)
func _flash() -> void:
	var white := ColorRect.new()
	white.color = Color(1, 0.97, 0.85, 0.85)
	white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(white)
	var t := white.create_tween()
	t.tween_property(white, "color:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	t.tween_callback(white.queue_free)

func _confetti() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(size.x / 2.0, -20)
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 120
	p.lifetime = 3.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(size.x / 2.0, 10)
	p.direction = Vector2.DOWN
	p.spread = 25.0
	p.gravity = Vector2(0, 160)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 200.0
	p.angle_max = 360.0
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	var colors := [CELL_COLORS[2], Color("#ff6fa8"), Color("#5ec8ff"), Color.WHITE, Color("#ff9a3d")]
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(colors)
	p.color_initial_ramp = ramp
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)

## The anvil scene: forge glow behind, the anvil, the piece on it (glowing with heat, then with the result's
## colour), the hammer to the right (`hammer` 0 = resting, 1 = raised, below 0 = striking), and gold rays for a
## MASTERWORK
class Forge extends Control:
	const METAL := Color("#8b93a3")
	const HOT := Color("#ff7a1a")
	var slot := EquipmentData.Slot.WEAPON
	var heat := 0.0:
		set(value):
			heat = value
			queue_redraw()
	var hammer := 0.0:
		set(value):
			hammer = value
			queue_redraw()
	var _time := 0.0
	var _squash := 0.0
	var _result_color := Color.TRANSPARENT
	var _rays := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func item_center() -> Vector2:
		return Vector2(size.x / 2.0, size.y - 78)

	## The hammer hit: the piece squashes and takes on the result's colour; MASTERWORK brings the rays
	func strike(color: Color, bonus: int) -> void:
		_result_color = Color(color, 0.0)
		var t := create_tween().set_parallel()
		t.tween_method(func(v: float): _squash = v, 1.0, 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "heat", 0.35 if bonus > 0 else 0.15, 0.8)
		t.tween_method(func(v: float): _result_color.a = v, 0.0, 1.0 if bonus > 0 else 0.0, 0.3)
		t.tween_property(self, "hammer", 0.25, 0.4).set_delay(0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if bonus >= 2:
			t.tween_method(func(v: float): _rays = v, 0.0, 1.0, 0.6)

	func _draw() -> void:
		var c := item_center()
		# Forge glow from below and drifting heat
		UITheme.draw_vertical_gradient(self, Rect2(Vector2.ZERO, size), Color(0.1, 0.04, 0.02, 0.0), Color(0.35, 0.12, 0.03, 0.55))
		UITheme.draw_glow(self, c + Vector2(0, 30), 200.0, Color(HOT, 0.12 + 0.18 * heat))
		if _rays > 0.0:
			for i in 14:
				var a := _time * 0.4 + TAU * i / 14.0
				var half := TAU / 14.0 * 0.22
				draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - half) * 400.0,
					c + Vector2.from_angle(a + half) * 400.0]), Color(CraftReel.CELL_COLORS[2], 0.12 * _rays))
			UITheme.draw_glow(self, c, 150.0, Color(CraftReel.CELL_COLORS[2], 0.4 * _rays))
		# The anvil
		var top := c.y + 26
		var anvil := Color("#2b2f38")
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - 130, top), Vector2(c.x + 110, top), Vector2(c.x + 150, top - 4),
			Vector2(c.x + 112, top + 22), Vector2(c.x + 70, top + 28), Vector2(c.x + 50, top + 62), Vector2(c.x + 90, top + 76),
			Vector2(c.x - 90, top + 76), Vector2(c.x - 50, top + 62), Vector2(c.x - 70, top + 28), Vector2(c.x - 110, top + 22)]), anvil)
		draw_line(Vector2(c.x - 130, top + 1), Vector2(c.x + 150, top - 3), Color("#6b7280"), 3.0)
		# The piece, glowing with heat, squashed by the hit
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		var glow_color := HOT if _result_color.a <= 0.0 else _result_color
		var glow := heat * (0.6 + 0.4 * pulse) if _result_color.a <= 0.0 else _result_color.a * (0.7 + 0.3 * pulse)
		UITheme.draw_glow(self, c, 70.0 + 20.0 * glow, Color(glow_color, 0.45 * glow))
		var fill := METAL.lerp(HOT.lightened(0.25), heat * (0.7 + 0.3 * pulse))
		if _result_color.a > 0.0:
			fill = fill.lerp(_result_color.lightened(0.3), _result_color.a * 0.7)
		draw_set_transform(c, 0.0, Vector2(1.0 + 0.25 * _squash, 1.0 - 0.3 * _squash))
		_draw_piece(fill, fill.darkened(0.55))
		draw_set_transform(Vector2.ZERO)
		_draw_hammer(c)

	## The piece by slot, centred on (0, 0): a sword, a chestplate or a ring with a gem
	func _draw_piece(fill: Color, edge: Color) -> void:
		match slot:
			EquipmentData.Slot.WEAPON:
				var blade := PackedVector2Array([Vector2(-70, -6), Vector2(40, -6), Vector2(62, 0), Vector2(40, 6), Vector2(-70, 6)])
				draw_colored_polygon(blade, fill)
				draw_polyline(blade + PackedVector2Array([blade[0]]), edge, 2.0)
				draw_line(Vector2(-66, 0), Vector2(40, 0), Color(1, 1, 1, 0.35), 1.5)
				draw_rect(Rect2(-80, -18, 10, 36), edge.lightened(0.3))
				draw_rect(Rect2(-108, -4, 28, 8), Color("#5b3a1e"))
				draw_circle(Vector2(-112, 0), 7, edge.lightened(0.3))
			EquipmentData.Slot.ARMOR:  # a heater shield with a boss
				var shield := PackedVector2Array([Vector2(-38, -40), Vector2(0, -46), Vector2(38, -40), Vector2(38, 2),
					Vector2(24, 26), Vector2(0, 44), Vector2(-24, 26), Vector2(-38, 2)])
				draw_colored_polygon(shield, fill)
				draw_polyline(shield + PackedVector2Array([shield[0]]), edge, 3.0)
				draw_line(Vector2(0, -42), Vector2(0, 40), edge, 2.0)
				draw_line(Vector2(-36, -6), Vector2(36, -6), edge, 2.0)
				draw_circle(Vector2(0, -6), 9, edge.lightened(0.2))
				draw_circle(Vector2(-3, -9), 3, Color(1, 1, 1, 0.4))
			_:
				draw_arc(Vector2(0, 6), 28, 0, TAU, 40, edge, 13.0)
				draw_arc(Vector2(0, 6), 28, 0, TAU, 40, fill, 9.0)
				var gem := PackedVector2Array([Vector2(0, -38), Vector2(13, -24), Vector2(0, -12), Vector2(-13, -24)])
				draw_colored_polygon(gem, Color("#ff6fa8").lerp(fill, 0.3))
				draw_polyline(gem + PackedVector2Array([gem[0]]), edge, 2.0)

	## The hammer, hinged at its handle's end down to the right of the anvil: resting over the piece at 0, raised
	## upright at 1, and down on the piece at -0.15 (the strike)
	func _draw_hammer(c: Vector2) -> void:
		const REST := -2.2
		const RAISED := -1.72
		const HIT := -2.83
		var pivot := c + Vector2(175, 35)
		var angle := lerpf(REST, RAISED, clampf(hammer, 0.0, 1.0))
		if hammer < 0.0:
			angle = lerpf(REST, HIT, clampf(-hammer / 0.15, 0.0, 1.0))
		draw_set_transform(pivot, angle, Vector2.ONE)
		draw_rect(Rect2(0, -5, 156, 10), Color("#7a4f2a"))
		draw_rect(Rect2(0, -5, 156, 3), Color("#a8743f"))
		draw_rect(Rect2(150, -26, 40, 52), Color("#3f4652"))
		draw_rect(Rect2(150, -26, 9, 52), Color("#9ca3af"))
		draw_rect(Rect2(150, -26, 40, 52), Color("#1f2329"), false, 2.0)
		draw_set_transform(Vector2.ZERO)

## The reel: cells slide right to left; `offset` is the cell under the marker (fractional while moving)
class Reel extends Control:
	const CELL_W := 112.0
	var offset := 0.0:
		set(value):
			offset = value
			queue_redraw()
	var _bump := 0.0  # the marker's flap as a cell ticks past
	var _locked := Color.TRANSPARENT
	var _lock := 0.0
	var _time := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func nudge() -> void:
		_bump = 1.0
		create_tween().tween_property(self, "_bump", 0.0, 0.12)

	## The landed cell lights up in the result's colour
	func lock(color: Color) -> void:
		_locked = color
		create_tween().tween_property(self, "_lock", 1.0, 0.25)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.04, 0.03, 0.03))
		var mid := size.x / 2.0
		var font := ThemeDB.fallback_font
		var base := floori(offset)
		var count := CraftReel.STRIP.size()
		for k in range(-4, 6):
			var cell := base + k
			var value: int = CraftReel.STRIP[posmod(cell, count)]
			var x := mid + (cell - offset) * CELL_W - CELL_W / 2.0
			var box := Rect2(x + 4, 10, CELL_W - 8, size.y - 20)
			var color: Color = CraftReel.CELL_COLORS[value]
			var near := clampf(1.0 - absf(box.get_center().x - mid) / (CELL_W * 2.5), 0.0, 1.0)  # brighter near the marker
			draw_rect(box, Color(color, (0.1 if value > 0 else 0.05) + 0.12 * near))
			draw_rect(box, Color(color, 0.45 + 0.4 * near if value > 0 else 0.25), false, 2.0)
			if value == 2:
				UITheme.draw_glow(self, box.get_center(), 40.0 + 10.0 * sin(_time * 8.0), Color(color, 0.18 + 0.2 * near))
			var text := "+%d" % value
			var font_size := 38 if value > 0 else 30
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, Vector2(box.get_center().x - w / 2.0, box.get_center().y + 6), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color if value > 0 else Color(color, 0.8))
			var word := Terms.t("reel_quality_%d" % value)
			var word_size := 11 if value < 2 else 10
			var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, word_size).x
			draw_string(font, Vector2(box.get_center().x - ww / 2.0, box.end.y - 8), word, HORIZONTAL_ALIGNMENT_LEFT, -1,
				word_size, Color(color, 0.85))
		# Fade the ends so the reel looks like a drum
		for i in 8:
			var a := 0.85 * (1.0 - i / 8.0)
			draw_rect(Rect2(i * 10.0, 0, 10, size.y), Color(0.04, 0.03, 0.03, a))
			draw_rect(Rect2(size.x - (i + 1) * 10.0, 0, 10, size.y), Color(0.04, 0.03, 0.03, a))
		# The marker: a gold frame over the middle cell with arrows that flap as cells tick past
		var gold := UITheme.GOLD
		var frame := Rect2(mid - CELL_W / 2.0, 4, CELL_W, size.y - 8)
		if _lock > 0.0:
			draw_rect(frame, Color(_locked, 0.3 * _lock))
			UITheme.draw_glow(self, frame.get_center(), 80.0, Color(_locked, 0.45 * _lock))
		draw_rect(frame, gold, false, 3.0)
		var flap := 5.0 * _bump
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 11 + flap, 0), Vector2(mid + 11 + flap, 0), Vector2(mid + flap * 0.5, 13)]), gold)
		draw_colored_polygon(PackedVector2Array([Vector2(mid - 11 + flap, size.y), Vector2(mid + 11 + flap, size.y),
			Vector2(mid + flap * 0.5, size.y - 13)]), gold)
		draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)

## Short sound effects made in code (16-bit mono), built once and reused
class Sfx:
	const RATE := 22050
	static var _cache := {}

	static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
		var bytes := PackedByteArray()
		bytes.resize(samples.size() * 2)
		for i in samples.size():
			bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = RATE
		w.stereo = false
		w.data = bytes
		return w

	## A short wooden click for each cell passing the marker
	static func tick() -> AudioStreamWAV:
		if not _cache.has("tick"):
			var n := int(RATE * 0.035)
			var s := PackedFloat32Array()
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				s[i] = (randf_range(-1, 1) * exp(-t * 260.0) * 0.5 + sin(TAU * 1900.0 * t) * exp(-t * 140.0) * 0.45)
			_cache.tick = _wav(s)
		return _cache.tick

	## Hammer on hot metal: a bright noisy hit, then ringing inharmonic partials
	static func clang() -> AudioStreamWAV:
		if not _cache.has("clang"):
			var n := int(RATE * 0.9)
			var s := PackedFloat32Array()
			s.resize(n)
			var partials := [[520.0, 1.0], [1185.0, 0.6], [1763.0, 0.45], [2630.0, 0.3], [3410.0, 0.2]]
			for i in n:
				var t := float(i) / RATE
				var v := randf_range(-1, 1) * exp(-t * 70.0) * 0.6
				for k in partials.size():
					v += sin(TAU * partials[k][0] * t) * partials[k][1] * exp(-t * (4.0 + k * 3.0))
				s[i] = v * 0.3
			_cache.clang = _wav(s)
		return _cache.clang

	## Bell notes rising one after another (FINE: two, MASTERWORK: a five-note fanfare)
	static func chime(freqs: Array) -> AudioStreamWAV:
		var key := "chime%d" % freqs.size()
		if not _cache.has(key):
			var gap := 0.085
			var n := int(RATE * (1.1 + gap * freqs.size()))
			var s := PackedFloat32Array()
			s.resize(n)
			for i in n:
				var t := float(i) / RATE
				var v := 0.0
				for k in freqs.size():
					var nt := t - gap * k
					if nt >= 0.0:
						var env := exp(-nt * 3.2) * minf(nt * 200.0, 1.0)
						v += (sin(TAU * freqs[k] * nt) + 0.35 * sin(TAU * freqs[k] * 2.0 * nt)) * env
				s[i] = v * 0.18
			_cache[key] = _wav(s)
		return _cache[key]
