class_name RouletteTab
extends VBoxContainer
## Casino game: Russian Roulette duel against Nilla. The bet is taken when the gun is loaded; the player and Nilla
## alternate pulls (the player presses the trigger, Nilla pulls on her own) until it fires. Rules live in RouletteGame.
## The table is a face-off: Nilla's seat on the left, yours on the right, the revolver between you. The gun swings
## to point at whoever's turn it is and their seat lights up, so it's always clear who's pulling. A dry pull puffs
## smoke and shows SAFE over that seat; a shot flashes from the muzzle, bursts red on the shooter's seat (which
## shakes, tilts and greys out under BANG!) and crowns the other seat WINNER. The cylinder below shows the chambers.

signal back_pressed

const HOST_ID := "nilla"
const SIDE_WIDTH := 260
const BANTER_VARIANTS := 3
const TENSION_TIME := 0.55  # pause between pulling and the result
const HOST_THINK_TIME := 0.8
const YOU_COLOR := Color("#5ec8ff")
const NILLA_PINK := Color("#f472b6")

var _game: RouletteGame
var _bullets := 2  # picked for the next round
var _staked := 0
var _busy := false

var _speech: Label
var _bubble: PanelContainer
var _turn_label: Label
var _cylinder: RevolverCylinder
var _gun: Gun
var _nilla_seat: Seat
var _player_seat: Seat
var _fx: CasinoFX
var _table: Control
var _log: Label
var _result: Label
var _flash: ColorRect
var _bullet_row: HBoxContainer
var _bullet_buttons: Array[Button] = []  # index = bullets - MIN_BULLETS
var _odds_label: Label
var _bet_row: BetPicker
var _back_button: Button
var _load_button: Button
var _trigger_button: Button

## Values for the lobby blurb and rules text, so they stay right if the bullet range or payouts change
static func range_args() -> Dictionary:
	return {
		"min": RouletteGame.MIN_BULLETS,
		"max": RouletteGame.MAX_BULLETS,
		"chambers": RouletteGame.CHAMBERS,
		"best": str(RouletteGame.payout_multiplier(RouletteGame.MAX_BULLETS)),
	}

static func odds_args(bullets: int) -> Dictionary:
	return {
		"bullets": bullets,
		"chance": "%.0f" % (RouletteGame.win_chance(bullets) * 100),
		"payout": str(RouletteGame.payout_multiplier(bullets)),
	}

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)

	# Left column: the title, Nilla's speech bubble, the rules and Back (Nilla herself sits at the table)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_theme_constant_override("separation", 10)
	columns.add_child(side)
	var title := Label.new()
	title.text = Terms.t("rr_title")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", NILLA_PINK)
	side.add_child(title)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", UITheme.box(UITheme.POPUP, NILLA_PINK, 2, 12, 12))
	side.add_child(_bubble)
	_speech = Label.new()
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.add_theme_font_size_override("font_size", 17)
	_bubble.add_child(_speech)
	var rules := Label.new()
	rules.text = Terms.t("rr_rules", range_args())
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	side.add_child(rules)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	_back_button = _button(Terms.t("casino_back"), back_pressed.emit)
	side.add_child(_back_button)

	# Right column: the face-off table, then the controls
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	columns.add_child(main)
	var table := PanelContainer.new()
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", UITheme.box(Color("#2a0a16"), Color("#7A1F3D"), 2, 14, 10))
	main.add_child(table)
	_table = table
	var felt := HBoxContainer.new()
	felt.alignment = BoxContainer.ALIGNMENT_CENTER
	felt.add_theme_constant_override("separation", 10)
	table.add_child(felt)
	# Nilla's card already has her name on its plate, so her seat shows no extra name
	_nilla_seat = Seat.new(CasinoTab.npc_portrait(HOST_ID, Terms.term("roulette_host"), CasinoTab.NILLA_COLOR),
		"", NILLA_PINK)
	felt.add_child(_nilla_seat)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 2)
	felt.add_child(center)
	_turn_label = _center_label(26)
	center.add_child(_turn_label)
	_gun = Gun.new()
	_gun.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_gun)
	_cylinder = RevolverCylinder.new()
	_cylinder.custom_minimum_size = Vector2(130, 130)
	_cylinder.pivot_offset = Vector2(65, 65)
	_cylinder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_cylinder)
	_log = _center_label(18)
	center.add_child(_log)
	_result = _center_label(22)
	center.add_child(_result)
	_player_seat = Seat.new(YouAvatar.new(), Terms.t("rr_you"), YOU_COLOR)
	felt.add_child(_player_seat)
	# Red flash over the table when the gun goes off, and the effects layer on top
	_flash = ColorRect.new()
	_flash.color = Color(1, 0.1, 0.1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table.add_child(_flash)
	_fx = CasinoFX.new()
	table.add_child(_fx)

	# Bullet count picker with the odds for the current choice
	_bullet_row = HBoxContainer.new()
	_bullet_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bullet_row.add_theme_constant_override("separation", 8)
	main.add_child(_bullet_row)
	var bullets_title := Label.new()
	bullets_title.text = Terms.t("rr_bullets")
	bullets_title.add_theme_font_size_override("font_size", 18)
	_bullet_row.add_child(bullets_title)
	var group := ButtonGroup.new()
	for n in range(RouletteGame.MIN_BULLETS, RouletteGame.MAX_BULLETS + 1):
		var b := _button(str(n), _pick_bullets.bind(n), 18)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = n == _bullets
		b.custom_minimum_size = Vector2(42, 38)
		_bullet_row.add_child(b)
		_bullet_buttons.append(b)
	_odds_label = Label.new()
	_odds_label.custom_minimum_size.x = 260
	_odds_label.add_theme_font_size_override("font_size", 18)
	_odds_label.add_theme_color_override("font_color", UITheme.GOLD)
	_bullet_row.add_child(_odds_label)

	_bet_row = BetPicker.new()
	_bet_row.changed.connect(func(_bet: int): _refresh_controls())
	main.add_child(_bet_row)
	_load_button = _button(Terms.t("rr_load"), _start, 22)
	_load_button.custom_minimum_size = Vector2(190, 52)
	_load_button.theme_type_variation = &"PrimaryButton"
	_bet_row.add_child(_load_button)
	_trigger_button = _button(Terms.t("rr_trigger"), _on_trigger, 22)
	_trigger_button.custom_minimum_size = Vector2(280, 56)
	_trigger_button.theme_type_variation = &"PrimaryButton"
	_trigger_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.add_child(_trigger_button)

	GameState.money_changed.connect(_on_money_changed)
	_say("idle")
	_set_phase_betting()

func _center_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.custom_minimum_size.y = font_size + 10
	return label

func _button(text: String, action: Callable, font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	return b

## Nilla speaks: the bubble pops so the new line is noticed
func _say(situation: String) -> void:
	_speech.text = "\"%s\"" % Terms.t("nilla_%s_%d" % [situation, randi_range(1, BANTER_VARIANTS)])
	_bubble.pivot_offset = _bubble.size / 2.0
	_bubble.scale = Vector2(0.92, 0.92)
	_bubble.create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ───────── Phases ─────────

func _set_phase_betting() -> void:
	_busy = false
	_bullet_row.show()
	_bet_row.show()
	_back_button.show()
	_trigger_button.hide()
	_refresh_controls()

func _set_phase_playing() -> void:
	_bullet_row.hide()
	_bet_row.hide()
	_back_button.hide()
	_trigger_button.show()
	_refresh_controls()

func _pick_bullets(n: int) -> void:
	_bullets = n
	_bullet_buttons[n - RouletteGame.MIN_BULLETS].button_pressed = true  # the ButtonGroup releases the others
	_refresh_controls()

func _refresh_controls() -> void:
	_odds_label.text = Terms.t("rr_odds", odds_args(_bullets))
	_load_button.text = Terms.t("rr_again" if _game != null else "rr_load")
	_load_button.disabled = GameState.get_money() < _bet_row.bet
	_trigger_button.disabled = _busy or _game == null or not _game.is_player_turn()

func _on_money_changed(_value: int) -> void:
	_refresh_controls()

# ───────── A round ─────────

func _start() -> void:
	if _busy:
		return
	if not GameState.try_spend(_bet_row.bet):
		_result.text = Terms.t("casino_not_enough")
		_result.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		return
	_staked = _bet_row.bet
	_game = RouletteGame.new(_bullets)
	_cylinder.reset()
	_log.text = ""
	_result.text = ""
	_turn_label.text = ""
	_nilla_seat.set_state(Seat.State.IDLE)
	_player_seat.set_state(Seat.State.IDLE)
	_busy = true
	_set_phase_playing()
	_say("load")
	# Spin the cylinder before the first pull
	_cylinder.spin = TAU * 3
	var tw := _cylinder.create_tween()
	tw.tween_property(_cylinder, "spin", 0.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw.finished
	await _next_turn()

## Whoever's turn it is: the gun swings to point at them and their seat lights up
func _next_turn() -> void:
	var player := _game.is_player_turn()
	_player_seat.set_state(Seat.State.ACTIVE if player else Seat.State.IDLE)
	_nilla_seat.set_state(Seat.State.IDLE if player else Seat.State.ACTIVE)
	await _gun.aim(player)
	if player:
		_turn_label.text = Terms.t("rr_your_turn")
		_turn_label.add_theme_color_override("font_color", YOU_COLOR)
		_busy = false
		_refresh_controls()
		return
	_turn_label.text = Terms.t("rr_host_turn")
	_turn_label.add_theme_color_override("font_color", NILLA_PINK)
	_refresh_controls()
	_say("her_turn")
	await create_tween().tween_interval(HOST_THINK_TIME).finished
	await _fire(false)

func _on_trigger() -> void:
	if _busy or not _game.is_player_turn():
		return
	_busy = true
	_refresh_controls()
	await _fire(true)

func _fire(by_player: bool) -> void:
	var seat := _player_seat if by_player else _nilla_seat
	# Tension: the gun trembles and the cylinder squeezes while the hammer falls
	_gun.tremble(TENSION_TIME)
	var squeeze := _cylinder.create_tween()
	squeeze.tween_property(_cylinder, "scale", Vector2(0.92, 0.92), TENSION_TIME * 0.5)
	squeeze.tween_property(_cylinder, "scale", Vector2.ONE, TENSION_TIME * 0.5)
	await squeeze.finished
	var chamber := _game.position
	var seat_center := _fx.to_local_center(seat, seat.size)
	if _game.pull():
		_cylinder.set_state(chamber, RevolverCylinder.State.FIRED)
		_log.text = Terms.t("rr_bang")
		_log.add_theme_color_override("font_color", Color("#F87171"))
		_turn_label.text = ""
		_gun.kick()
		_fx.muzzle(_gun_muzzle(), (seat_center - _gun_muzzle()).normalized())
		_fx.shot(seat_center)
		_fx.shake(_table, 14.0, 0.45)
		_pop_text(seat_center, Terms.t("rr_bang"), Color("#ef4444"), 44)
		seat.set_state(Seat.State.SHOT)
		(_nilla_seat if by_player else _player_seat).set_state(Seat.State.WINNER)
		var flash := _flash.create_tween()
		flash.tween_property(_flash, "color:a", 0.5, 0.06)
		flash.tween_property(_flash, "color:a", 0.0, 0.6)
		await flash.finished
		_finish(not by_player)
		return
	_cylinder.set_state(chamber, RevolverCylinder.State.EMPTY)
	_log.text = Terms.t("rr_click_you" if by_player else "rr_click_host")
	_log.add_theme_color_override("font_color", UITheme.TEXT)
	_fx.smoke(_gun_hammer(), 0.35)
	_fx.relief(seat_center)
	_pop_text(seat_center, Terms.t("rr_safe"), Color("#86efac"), 30)
	var turn := _cylinder.create_tween()
	turn.tween_property(_cylinder, "spin", -_game.position * TAU / RouletteGame.CHAMBERS, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await turn.finished
	await create_tween().tween_interval(0.35).finished
	await _next_turn()

func _finish(won: bool) -> void:
	# Show where the other bullets were
	for i in range(_game.position, RouletteGame.CHAMBERS):
		if _game.loaded[i]:
			_cylinder.set_state(i, RevolverCylinder.State.BULLET)
	_turn_label.text = ""
	var paid := RouletteGame.payout(won, _staked, _game.bullets)
	if paid > 0:
		GameState.add_money(paid)
	if won:
		_result.text = Terms.t("rr_result_win", {"amount": paid - _staked})
		_result.add_theme_color_override("font_color", UITheme.GOLD)
		_fx.coins(Rect2(_fx.to_local_center(_player_seat, _player_seat.size) - Vector2(120, 140), Vector2(240, 280)))
		_say("player_won")
	else:
		_result.text = Terms.t("rr_result_lose", {"amount": _staked})
		_result.add_theme_color_override("font_color", Color("#F87171"))
		_say("player_lost")
	_set_phase_betting()

func _gun_muzzle() -> Vector2:
	return _gun.muzzle_global() - _fx.global_position

func _gun_hammer() -> Vector2:
	return _gun.hammer_global() - _fx.global_position

## Big text that pops over a spot on the table and floats away
func _pop_text(pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(label)
	var label_size := label.get_combined_minimum_size()
	label.position = pos - label_size / 2.0 - Vector2(0, 20)
	label.pivot_offset = label_size / 2.0
	label.scale = Vector2(2.0, 2.0)
	var t := label.create_tween().set_parallel()
	t.tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "position:y", label.position.y - 40, 1.6).set_delay(0.5)
	t.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(1.4)
	t.chain().tween_callback(label.queue_free)

## A player at the table: their picture with a glow behind it, their name and a turn tag. States: idle, active
## (pulsing glow, "TURN" tag, slightly bigger), shot (red, tilted, greyed) and winner (gold glow).
class Seat extends VBoxContainer:
	enum State { IDLE, ACTIVE, SHOT, WINNER }
	const PORTRAIT := Vector2(132, 176)
	var _color := Color.WHITE
	var _glow: Glow
	var _picture: Control
	var _holder: Control
	var _tag: Label
	var _state := State.IDLE

	func _init(picture: Control, seat_name: String, color: Color) -> void:
		_color = color
		alignment = BoxContainer.ALIGNMENT_CENTER
		add_theme_constant_override("separation", 4)
		_tag = Label.new()
		_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tag.add_theme_font_size_override("font_size", 16)
		_tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_tag.add_theme_constant_override("outline_size", 6)
		_tag.custom_minimum_size.y = 24
		add_child(_tag)
		_holder = Control.new()
		_holder.custom_minimum_size = PORTRAIT + Vector2(24, 24)
		add_child(_holder)
		_glow = Glow.new()
		_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_glow.color = color
		_holder.add_child(_glow)
		_picture = picture
		_picture.position = Vector2(12, 12)
		_picture.size = PORTRAIT
		_picture.custom_minimum_size = PORTRAIT
		_picture.pivot_offset = PORTRAIT / 2.0
		_holder.add_child(_picture)
		if seat_name.is_empty():
			return
		var name_label := Label.new()
		name_label.text = seat_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", color)
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		name_label.add_theme_constant_override("outline_size", 6)
		add_child(name_label)

	func set_state(state: State) -> void:
		_state = state
		_glow.active = state == State.ACTIVE
		_glow.color = UITheme.GOLD if state == State.WINNER else (Color("#ef4444") if state == State.SHOT else _color)
		_glow.lit = state in [State.ACTIVE, State.WINNER]
		var t := _picture.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		match state:
			State.IDLE:
				_tag.text = ""
				t.tween_property(_picture, "scale", Vector2.ONE, 0.25)
				t.tween_property(_picture, "rotation", 0.0, 0.25)
				t.tween_property(_picture, "modulate", Color.WHITE, 0.25)
			State.ACTIVE:
				_tag.text = Terms.t("rr_seat_turn")
				_tag.add_theme_color_override("font_color", _color)
				t.tween_property(_picture, "scale", Vector2(1.06, 1.06), 0.3)
				t.tween_property(_picture, "modulate", Color(1.12, 1.12, 1.12), 0.3)
			State.SHOT:
				_tag.text = Terms.t("rr_seat_shot")
				_tag.add_theme_color_override("font_color", Color("#ef4444"))
				t.tween_property(_picture, "scale", Vector2(0.96, 0.96), 0.4)
				t.tween_property(_picture, "rotation", deg_to_rad(-10.0), 0.5).set_trans(Tween.TRANS_BOUNCE)
				t.tween_property(_picture, "modulate", Color(0.75, 0.35, 0.35), 0.15)
				t.chain().tween_property(_picture, "modulate", Color(0.45, 0.4, 0.42), 0.8)
			State.WINNER:
				_tag.text = Terms.t("rr_seat_winner")
				_tag.add_theme_color_override("font_color", UITheme.GOLD)
				t.tween_property(_picture, "scale", Vector2(1.08, 1.08), 0.4)
				t.tween_property(_picture, "modulate", Color(1.2, 1.15, 0.9), 0.4)

	## A soft glow behind the picture; pulses while it's this seat's turn
	class Glow extends Control:
		var color := Color.WHITE
		var active := false
		var lit := false:
			set(value):
				lit = value
				queue_redraw()
		var _t := 0.0

		func _init() -> void:
			mouse_filter = Control.MOUSE_FILTER_IGNORE

		func _process(delta: float) -> void:
			_t += delta
			if lit:
				queue_redraw()

		func _draw() -> void:
			if not lit:
				return
			var pulse := 0.5 + 0.5 * sin(_t * 5.0) if active else 0.7
			var r := Rect2(Vector2.ZERO, size).grow(-4.0 + pulse * 4.0)
			UITheme.draw_glow(self, size / 2.0, size.x * 0.75, Color(color, 0.18 + 0.2 * pulse))
			for i in 3:
				draw_rect(r.grow(i * 3.0), Color(color, (0.75 - i * 0.22) * (0.6 + 0.4 * pulse)), false, 2.5)

## "YOU": a simple glowing silhouette (head and shoulders) on a dark plate
class YouAvatar extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		UITheme.draw_vertical_gradient(self, r, Color("#14324a"), Color("#081520"))
		var c := Color("#5ec8ff")
		var head := Vector2(size.x / 2.0, size.y * 0.38)
		draw_circle(head, size.x * 0.2, Color(c, 0.85))
		var body := PackedVector2Array()
		for i in 25:
			var a := PI + PI * i / 24.0
			body.append(Vector2(size.x / 2.0, size.y * 1.02) + Vector2(cos(a) * size.x * 0.42, sin(a) * size.y * 0.36))
		draw_colored_polygon(body, Color(c, 0.85))
		draw_rect(r, Color(c, 0.9), false, 3.0)
		draw_rect(r.grow(-6), Color(c, 0.3), false, 1.0)

## The revolver, drawn with shapes and pointing right (+x) by default. aim() swings it to point at the player's
## seat (right) or Nilla's (left); tremble() shakes it while the hammer falls; kick() is the recoil.
## The flip, tilt and lift are applied inside _draw, not as the node's scale/rotation: the gun sits in a
## container, and containers reset their children's scale and rotation whenever they lay them out.
class Gun extends Control:
	const SIZE := Vector2(240, 120)
	var flip := 1.0:  # 1 = pointing at the player's seat (right), -1 = at Nilla (left); passes through 0 as it turns
		set(value):
			flip = value
			queue_redraw()
	var tilt := 0.0:  # radians, muzzle up when positive
		set(value):
			tilt = value
			queue_redraw()
	var lift := 0.0:  # px up, during the swing
		set(value):
			lift = value
			queue_redraw()
	var _facing := 1.0

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	## Swings the barrel round to the given side; waits until it gets there
	func aim(at_player: bool) -> void:
		var target := 1.0 if at_player else -1.0
		if is_equal_approx(target, _facing) and is_equal_approx(flip, target):
			return
		_facing = target
		var t := create_tween()
		t.tween_property(self, "flip", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(self, "lift", 14.0, 0.16)
		t.tween_property(self, "flip", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(self, "lift", 0.0, 0.22)
		await t.finished

	func tremble(seconds: float) -> void:
		var t := create_tween()
		for i in int(seconds / 0.04):
			t.tween_property(self, "tilt", deg_to_rad(randf_range(-2.5, 2.5)), 0.04)
		t.tween_property(self, "tilt", 0.0, 0.04)

	func kick() -> void:
		var t := create_tween()
		t.tween_property(self, "tilt", deg_to_rad(16.0), 0.06)
		t.tween_property(self, "tilt", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	## From the unflipped drawing to this control: mirror around the centre by `flip`, tilt the muzzle up by
	## `tilt` (on whichever side it points), raise by `lift`
	func _pose() -> Transform2D:
		var side := -1.0 if flip < 0.0 else 1.0
		var around := Transform2D(-tilt * side, SIZE / 2.0 + Vector2(0, -lift))
		return around * Transform2D(0.0, Vector2(flip, 1.0), 0.0, Vector2.ZERO) * Transform2D(0.0, -SIZE / 2.0)

	## The muzzle and hammer in global coordinates (they follow the flip)
	func muzzle_global() -> Vector2:
		return get_global_transform() * (_pose() * Vector2(SIZE.x - 6, SIZE.y * 0.32))

	func hammer_global() -> Vector2:
		return get_global_transform() * (_pose() * Vector2(SIZE.x * 0.3, SIZE.y * 0.18))

	func _draw() -> void:
		draw_set_transform_matrix(_pose())
		_shapes()
		draw_set_transform_matrix(Transform2D.IDENTITY)

	## The revolver itself, pointing right, in the control's own (unflipped) coordinates
	func _shapes() -> void:
		var steel := Color("#6b7280")
		var dark := Color("#374151")
		var light := Color("#cbd5e1")
		var y := SIZE.y * 0.32
		# Barrel
		draw_rect(Rect2(SIZE.x * 0.42, y - 9, SIZE.x * 0.56, 18), steel)
		draw_rect(Rect2(SIZE.x * 0.42, y - 9, SIZE.x * 0.56, 5), light.darkened(0.2))
		draw_rect(Rect2(SIZE.x * 0.94, y - 13, 10, 6), steel)  # front sight
		# Frame and cylinder
		draw_rect(Rect2(SIZE.x * 0.18, y - 16, SIZE.x * 0.3, 40), dark)
		draw_circle(Vector2(SIZE.x * 0.34, y + 4), 24, steel)
		draw_arc(Vector2(SIZE.x * 0.34, y + 4), 24, 0, TAU, 32, light.darkened(0.3), 2.0, true)
		for i in 3:
			draw_line(Vector2(SIZE.x * 0.34 - 18 + i * 18, y - 14), Vector2(SIZE.x * 0.34 - 18 + i * 18, y + 22), dark, 2.0)
		# Hammer
		draw_colored_polygon(PackedVector2Array([Vector2(SIZE.x * 0.2, y - 16), Vector2(SIZE.x * 0.27, y - 16),
			Vector2(SIZE.x * 0.22, y - 30), Vector2(SIZE.x * 0.16, y - 26)]), dark)
		# Grip
		draw_colored_polygon(PackedVector2Array([Vector2(SIZE.x * 0.18, y + 18), Vector2(SIZE.x * 0.32, y + 18),
			Vector2(SIZE.x * 0.24, SIZE.y - 6), Vector2(SIZE.x * 0.06, SIZE.y - 14)]), Color("#7c3f1d"))
		draw_colored_polygon(PackedVector2Array([Vector2(SIZE.x * 0.2, y + 24), Vector2(SIZE.x * 0.28, y + 24),
			Vector2(SIZE.x * 0.21, SIZE.y - 16), Vector2(SIZE.x * 0.11, SIZE.y - 20)]), Color("#9a5428"))
		# Trigger guard and trigger
		draw_arc(Vector2(SIZE.x * 0.4, y + 30), 13, 0, PI, 16, dark, 4.0, true)
		draw_line(Vector2(SIZE.x * 0.4, y + 22), Vector2(SIZE.x * 0.38, y + 36), steel, 3.0, true)
