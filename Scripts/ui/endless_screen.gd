class_name EndlessScreen
extends Control
## The After Hours screen (Endless autoload), styled after gacha roguelite modes. Pages:
## - Lobby: the neon sign, the opening pair as two big slots (tap one to pick a friend for it), the record, START.
## - Shop: Night Token goods as cards.
## - Run: a HUD on top (Night, floor track, Drinks pouch, Tips), the scrolling map (AfterHoursMap) and the squad
##   dock at the bottom (tap a friend to field or bench them). Whatever the run is waiting on opens as an overlay
##   over it: the encounter (enemy lineup + formation board + FIGHT), Drink cards dealt in, the forced Hangover
##   (red flash and shake), the Rest stop, the Bar's shelves, an Event as a visual-novel scene, a result card,
##   and the end of a Night (keep going, or cash out).
## - Results: the run's grade, its floors and the Night Token breakdown counting up.
## Main listens to fight_pressed (play the waiting fight in a BattleView) and back_pressed.
## Shared look and drawn bits: AHKit (Scripts/ui/endless_kit.gd).

signal fight_pressed
signal back_pressed

const ACCENT := AHKit.ACCENT

static var _last_overlay := ""  # the overlay shown last, so a rebuild of the same one doesn't replay its entrance
static var _last_map_key := ""  # where the map last glided to

var _page: Control
var _layer: Control  # overlays
var _view := "lobby"  # without a run: "lobby" or "shop"
var _pick := {"vanguard": 0, "rearguard": 0}
var _choice := ""  # the Drink / Hangover card selected before confirming
var _pouch_open := false

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var backdrop := AHKit.Backdrop.new(UITheme.background("FrennisNightClub"))
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var sparkles := CollectionTab.Sparkles.new()
	sparkles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sparkles)
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	# Pre-pick the current team's first friend of each row, so START is one tap away
	for uid in GameState.team_members():
		var c := GameState.get_character(uid)
		if c:
			var row := "vanguard" if c.is_vanguard() else "rearguard"
			if int(_pick[row]) == 0:
				_pick[row] = uid
	refresh()

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _act(callable: Callable) -> void:
	callable.call()
	refresh()

func refresh() -> void:
	_clear(_page)
	_clear(_layer)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Endless.has_run():
		_page.add_child(_run_page())
		var p := Endless.pending()
		if not p.is_empty():
			_choice = _choice if _overlay_key(p) == _last_overlay else ""
			_overlay(p)
		elif _pouch_open:
			_pouch_overlay()
		else:
			_last_overlay = ""
	elif not Endless.last_run().is_empty():
		_page.add_child(_results_page())
	elif _view == "shop":
		_page.add_child(_shop_page())
	else:
		_page.add_child(_lobby_page())

func _margin(child: Control, m: int = 14) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m)
	margin.add_child(child)
	return margin

func _back_button(callback: Callable) -> Button:
	return AHKit.button(Terms.t("back"), callback, UITheme.CYAN, false, Vector2(96, 40), 15)

## A top bar: back button, a title, and whatever goes on the right
func _top_bar(title: String, right: Array[Control]) -> HBoxContainer:
	var bar := AHKit.hbox(12)
	bar.add_child(_back_button(back_pressed.emit))
	var t := AHKit.label(title, 22, Color.WHITE, false, 6)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(t)
	for c in right:
		bar.add_child(c)
	return bar

func _token_chip() -> CurrencyChip:
	var chip := CurrencyChip.new("night_token", Terms.t("endless_token_name"))
	chip.set_amount(Endless.tokens())
	return chip

# ═════════ Lobby ═════════

func _lobby_page() -> Control:
	var root := AHKit.vbox(10)
	root.add_child(_top_bar("", [_token_chip()]))
	var row := AHKit.hbox(18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	# The stage: the sign, the two slots, the three rules
	var stage := AHKit.vbox(8)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stage)
	stage.add_child(AHKit.NeonSign.new(Terms.t("endless_title").to_upper(), AHKit.PINK, 52))
	var tagline := AHKit.label(Terms.t("endless_tagline"), 16, AHKit.ACCENT.lightened(0.45))
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(tagline)
	var slots := AHKit.hbox(26)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(slots)
	if Endless.is_open():
		for row_key in ["vanguard", "rearguard"]:
			slots.add_child(_slot(row_key))
	else:
		var lock := AHKit.label(Terms.t("endless_locked", {"code": Endless.unlock_code()}), 20, AHKit.HANGOVER, true)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(lock)
	var rules := AHKit.hbox(10)
	rules.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_child(rules)
	for spec in [["battle", "endless_rule_carry"], ["bar", "endless_rule_drinks"], ["boss", "endless_rule_cash"]]:
		var tile := AHKit.panel(AHKit.NODE_COLORS[spec[0]], 10, 0.75)
		tile.custom_minimum_size.x = 210
		var line := AHKit.hbox(8)
		tile.add_child(line)
		line.add_child(AHKit.NodeBadge.new(spec[0], 30))
		var text := AHKit.label(Terms.t(spec[1]), 13, UITheme.TEXT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		rules.add_child(tile)

	# The side column: record, START, shop
	var side := AHKit.panel(AHKit.ACCENT, 16)
	side.custom_minimum_size.x = 320
	row.add_child(side)
	var col := AHKit.vbox(12)
	side.add_child(col)
	col.add_child(AHKit.label(Terms.t("endless_record"), 15, UITheme.TEXT_DIM))
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 10)
	col.add_child(stats)
	var d := Endless._data()
	for spec in [["endless_stat_best", str(Endless.best_floor())], ["endless_stat_night", Endless.night_name(maxi(int(d.best_night), 1)) if int(d.best_night) > 0 else "-"],
			["endless_stat_runs", str(int(d.runs))], ["endless_stat_tokens", Terms.number(Endless.tokens())]]:
		var tile := AHKit.panel(UITheme.CYAN, 8, 0.6)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := AHKit.vbox(0)
		tile.add_child(box)
		box.add_child(AHKit.label(Terms.t(spec[0]), 11, UITheme.TEXT_DIM))
		box.add_child(AHKit.label(spec[1], 19, Color.WHITE, false, 5))
		stats.add_child(tile)
	# First-clear rewards per Night, ticked once claimed
	col.add_child(AHKit.label(Terms.t("endless_lobby_milestones").to_upper(), 12, UITheme.TEXT_DIM))
	for night in range(1, Endless.MILESTONES.size()):
		var line := AHKit.hbox(8)
		col.add_child(line)
		var done: bool = d.milestones.has(str(night))
		var badge := AHKit.NodeBadge.new("boss", 22)
		badge.modulate.a = 0.45 if done else 1.0
		line.add_child(badge)
		var night_label := AHKit.label(Endless.night_name(night), 13, UITheme.TEXT_DIM if done else Color.WHITE)
		night_label.custom_minimum_size.x = 70
		line.add_child(night_label)
		var reward := AHKit.label(Terms.t("endless_lobby_done") if done else Daily.reward_text(Endless.MILESTONES[night - 1]), 13,
			UITheme.TEXT_DIM if done else UITheme.GOLD, true)
		reward.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(reward)
	col.add_child(AHKit.spacer())
	var ready := GameState.get_character(int(_pick.vanguard)) != null and GameState.get_character(int(_pick.rearguard)) != null
	var start := AHKit.button(Terms.t("endless_start").to_upper(), _start_run, AHKit.PINK, true, Vector2(0, 64), 24)
	start.disabled = not ready or not Endless.is_open()
	col.add_child(start)
	if not ready and Endless.is_open():
		var hint := AHKit.label(Terms.t("endless_pick_hint"), 13, UITheme.TEXT_DIM, true)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(hint)
	col.add_child(AHKit.button(Terms.t("endless_shop_button"), _show_view.bind("shop"), AHKit.ACCENT, false, Vector2(0, 46)))
	return _margin(root)

## A big FRONT / BACK slot: the picked friend standing in it, or an empty outline to tap
func _slot(row_key: String) -> Control:
	var size := Vector2(200, 268)
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var color := AHKit.NODE_COLORS.battle if row_key == "vanguard" else AHKit.ACCENT
	var style := AHKit.glass(color, 8, 0.7)
	card.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.shadow_size = 24
	hover.border_color = Color.WHITE
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("focus", style)
	card.pressed.connect(_open_picker.bind(row_key))
	var holder := AHKit.hold(card, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.mouse_entered.connect(AHKit.lift.bind(card, true))
	card.mouse_exited.connect(AHKit.lift.bind(card, false))
	var box := AHKit.vbox(6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10
	box.offset_right = -10
	box.offset_top = 10
	box.offset_bottom = -10
	card.add_child(box)
	box.add_child(AHKit.label(Terms.t("endless_slot_" + row_key).to_upper(), 14, color.lightened(0.3)))
	var c := GameState.get_character(int(_pick[row_key]))
	if c:
		var portrait := AHKit.Portrait.new(c)
		portrait.show_bars = false
		portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(portrait)
		box.add_child(AHKit.label(c.display_name, 17, Color.WHITE))
		box.add_child(AHKit.label("%s %s · %s%d" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class), Terms.term("level"),
			int(GameState.get_owned(int(_pick[row_key])).level)], 12, CharArt.RARITY_COLORS.get(c.rarity, UITheme.TEXT)))
	else:
		box.add_child(AHKit.spacer())
		var plus := AHKit.label("+", 64, Color(color, 0.8))
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(plus)
		var t := AHKit.label(Terms.t("endless_slot_empty"), 14, UITheme.TEXT_DIM, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
		box.add_child(AHKit.spacer())
	return holder

## The friend picker for one slot: every owned friend of that row as a card
func _open_picker(row_key: String) -> void:
	var content := AHKit.panel(AHKit.ACCENT, 18, 0.95)
	content.custom_minimum_size = Vector2(760, 480)
	var box := AHKit.vbox(10)
	content.add_child(box)
	var head := AHKit.hbox(10)
	box.add_child(head)
	var title := AHKit.label(Terms.t("endless_pick_" + row_key), 20, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(AHKit.button(Terms.t("endless_close"), refresh, UITheme.CYAN, false, Vector2(100, 38), 14))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var owned: Array = GameState.data.owned.duplicate()
	owned.sort_custom(func(a, b): return int(a.level) > int(b.level))
	var i := 0
	for o in owned:
		var c := GameState.get_character(int(o.uid))
		if c == null or c.is_vanguard() != (row_key == "vanguard"):
			continue
		var card := _friend_card(c, int(o.level), int(o.uid) == int(_pick[row_key]))
		card.get_child(0).pressed.connect(func():
			_pick[row_key] = int(o.uid)
			refresh())
		grid.add_child(card)
		AHKit.pop_in(card.get_child(0), 0.02 * mini(i, 16), Vector2(0, 18), 0.3)
		i += 1
	_open_layer(content, "picker_" + row_key)

## A friend as a pickable card (held, so it can lift on hover); the Button is the holder's first child
func _friend_card(c: CharacterData, level: int, chosen := false, size := Vector2(118, 168)) -> Control:
	var rarity: Color = CharArt.RARITY_COLORS.get(c.rarity, UITheme.TEXT)
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s  %s%d" % [c.display_name, Terms.term("level"), level]
	var style := UITheme.box(Color(0.05, 0.05, 0.1, 0.95), Color.WHITE if chosen else rarity, 3 if chosen else 1, 8, 4)
	style.shadow_color = Color(rarity, 0.35)
	style.shadow_size = 12 if chosen else 4
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("focus", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.shadow_size = 18
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	var holder := AHKit.hold(card, size)
	card.mouse_entered.connect(AHKit.lift.bind(card, true))
	card.mouse_exited.connect(AHKit.lift.bind(card, false))
	var box := AHKit.vbox(2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 5
	box.offset_right = -5
	box.offset_top = 5
	box.offset_bottom = -5
	card.add_child(box)
	var portrait := AHKit.Portrait.new(c)
	portrait.show_bars = false
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(portrait)
	var name := AHKit.label(c.display_name, 12, Color.WHITE)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var lv := AHKit.label("%s · %s%d" % [Terms.rarity_name(c.rarity), Terms.term("level"), level], 11, rarity)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lv)
	return holder

func _show_view(view: String) -> void:
	_view = view
	refresh()

func _start_run() -> void:
	if Endless.start_run(int(_pick.vanguard), int(_pick.rearguard)):
		_last_map_key = ""
		refresh()

# ═════════ Shop ═════════

func _shop_page() -> Control:
	var root := AHKit.vbox(12)
	var bar := AHKit.hbox(12)
	bar.add_child(_back_button(_show_view.bind("lobby")))
	var title := AHKit.label(Terms.t("endless_shop_title").to_upper(), 24, AHKit.PINK, false, 6)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	bar.add_child(_token_chip())
	root.add_child(bar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	var box := AHKit.vbox(14)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var cards := []
	# Tickets
	box.add_child(_section(Terms.t("endless_shop_tickets")))
	var tickets := HFlowContainer.new()
	tickets.add_theme_constant_override("h_separation", 12)
	tickets.add_theme_constant_override("v_separation", 12)
	box.add_child(tickets)
	for i in Endless.SHOP_TICKETS.size():
		var item: Dictionary = Endless.SHOP_TICKETS[i]
		var left := Endless.ticket_left(item)
		var icon := CurrencyChip.ChipIcon.new()
		icon.kind = String(item.id)
		icon.color = CurrencyChip.KIND_COLORS.get(String(item.id), UITheme.CYAN)
		var card := _goods_card(icon, Terms.t(String(item.id) + "_one"), Terms.t("endless_shop_month_left", {"left": left, "limit": int(item.limit)}),
			int(item.price), left > 0, func(): _act(func(): Endless.buy_ticket(i)), icon.color)
		tickets.add_child(card)
		cards.append(card)
	# Gear
	box.add_child(_section(Terms.t("endless_shop_gear", {"time": Daily.format_time(Daily.seconds_to_weekly_reset())})))
	var gear := HFlowContainer.new()
	gear.add_theme_constant_override("h_separation", 12)
	gear.add_theme_constant_override("v_separation", 12)
	box.add_child(gear)
	for e in Endless.gear_stock():
		var icon := GearIcon.new()
		icon.set_gear(e)
		var mods := PackedStringArray()
		var m := e.modifiers()
		for stat in m:
			mods.append("%s %+d" % [Terms.stat_short(stat), int(m[stat])])
		var card := _goods_card(icon, e.display_name, "%s %s\n%s" % [Terms.rarity_name(e.rarity), Terms.slot_name(e.slot_key()), "  ".join(mods)],
			Endless.gear_price(e), Endless.gear_left(e) > 0, func(): _act(func(): Endless.buy_gear(e)), CharArt.RARITY_COLORS.get(e.rarity, UITheme.CYAN))
		gear.add_child(card)
		cards.append(card)
	# Materials
	box.add_child(_section(Terms.t("endless_shop_materials")))
	var mats := HFlowContainer.new()
	mats.add_theme_constant_override("h_separation", 12)
	box.add_child(mats)
	for i in Endless.SHOP_MATERIALS.size():
		var item: Dictionary = Endless.SHOP_MATERIALS[i]
		var icon := CurrencyChip.ChipIcon.new()
		icon.kind = String(item.id)
		icon.color = CurrencyChip.KIND_COLORS.get(String(item.id), UITheme.CYAN)
		var card := _goods_card(icon, Daily.item_text([item.id, item.amount]), Terms.t("endless_shop_no_limit"), int(item.price), true,
			func(): _act(func(): Endless.buy_material(i)), icon.color)
		mats.add_child(card)
		cards.append(card)
	for i in cards.size():
		AHKit.pop_in(cards[i].get_child(0), 0.04 * i, Vector2(0, 20), 0.32)
	return _margin(root)

func _section(text: String) -> Control:
	var row := AHKit.hbox(10)
	var bar := ColorRect.new()
	bar.color = AHKit.PINK
	bar.custom_minimum_size = Vector2(4, 20)
	row.add_child(bar)
	row.add_child(AHKit.label(text.to_upper(), 15, Color.WHITE))
	return row

## A shop item: its icon on a glowing plate, name, note, and a price button with the Token icon
func _goods_card(icon: Control, name: String, note: String, price: int, available: bool, buy: Callable, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AHKit.glass(color, 12, 0.88))
	var holder := AHKit.hold(panel, Vector2(210, 250))
	var box := AHKit.vbox(6)
	panel.add_child(box)
	var plate := Control.new()
	plate.custom_minimum_size = Vector2(0, 92)
	box.add_child(plate)
	icon.custom_minimum_size = Vector2(76, 76)
	icon.size = Vector2(76, 76)
	plate.resized.connect(func(): icon.position = Vector2((plate.size.x - 76) / 2.0, 8))
	plate.add_child(icon)
	var title := AHKit.label(name, 16, Color.WHITE, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := AHKit.label(note, 12, UITheme.TEXT_DIM, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sub)
	var b := AHKit.button(Terms.t("endless_shop_buy", {"price": price}) if available else Terms.t("endless_shop_sold_out"), buy,
		AHKit.ACCENT, available, Vector2(0, 40), 15)
	b.disabled = not available or Endless.tokens() < price
	box.add_child(b)
	if not available:
		var stamp := AHKit.Stamp.new(Terms.t("endless_sold_stamp"))
		stamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(stamp)
	panel.mouse_entered.connect(AHKit.lift.bind(panel, true))
	panel.mouse_exited.connect(AHKit.lift.bind(panel, false))
	return holder

# ═════════ Run: HUD, map, dock ═════════

func _run_page() -> Control:
	var r := Endless.run()
	var root := AHKit.vbox(8)
	# HUD
	var hud := AHKit.hbox(14)
	root.add_child(hud)
	hud.add_child(_back_button(back_pressed.emit))
	var night := AHKit.vbox(2)
	night.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(night)
	var title := AHKit.hbox(10)
	night.add_child(title)
	title.add_child(AHKit.label(Endless.night_name().to_upper(), 24, AHKit.PINK, false, 6))
	title.add_child(AHKit.label(Terms.t("endless_floor_of", {"floor": int(r.floor) + 1, "floors": Endless.FLOORS}) if int(r.floor) >= 0
		else Terms.t("endless_floor_start"), 15, UITheme.TEXT_DIM))
	var track := AHKit.FloorTrack.new()
	track.current = int(r.floor)
	track.custom_minimum_size.x = 330
	track.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	night.add_child(track)
	var tips := CurrencyChip.new("tips", Terms.t("endless_tips_name"))
	tips.set_amount(int(r.tips))
	hud.add_child(tips)
	hud.add_child(AHKit.button(Terms.t("endless_give_up_short"), _confirm_give_up, AHKit.HANGOVER, false, Vector2(96, 40), 13))
	# Squad | map | Drinks
	var body := AHKit.hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	body.add_child(_squad_panel())
	var map := AfterHoursMap.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var leader: CharacterData = null
	for m in Endless.members():
		if not m.ko:
			leader = m.data
			break
	map.setup(Endless.map_nodes(), r.get("path", []), Endless.reachable(), String(r.node), leader)
	var key := "%d|%s" % [int(r.night), String(r.node)]
	map.animate = key != _last_map_key  # glide only when the squad has moved
	_last_map_key = key
	map.go.connect(func(id: String): _act(func(): Endless.choose_node(id)))
	body.add_child(map)
	body.add_child(_drinks_panel())
	return _margin(root, 12)

## The squad down the left side: one row per friend (portrait, name, place in the lineup, HP and Ultimate bars);
## tap a row to field or bench that friend
func _squad_panel() -> Control:
	var members := Endless.members()
	var panel := AHKit.panel(UITheme.CYAN, 10, 0.84)
	panel.custom_minimum_size.x = 236
	var box := AHKit.vbox(6)
	panel.add_child(box)
	var head := AHKit.hbox(6)
	box.add_child(head)
	head.add_child(AHKit.label(Terms.t("endless_squad").to_upper(), 16, UITheme.CYAN, false, 5))
	head.add_child(AHKit.spacer(false))
	var fielded := members.filter(func(m): return m.fielded).size()
	head.add_child(AHKit.chip(Terms.t("endless_fielded", {"n": fielded, "max": FormationBattleEngine.ROW_SIZE * 2}), UITheme.CYAN))
	box.add_child(AHKit.label(Terms.t("endless_dock_hint"), 11, UITheme.TEXT_DIM))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := AHKit.vbox(5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	members.sort_custom(func(a, b): return (a.fielded and not b.fielded) or (a.fielded == b.fielded and a.vanguard and not b.vanguard))
	for m in members:
		list.add_child(_squad_row(m))
	return panel

func _squad_row(m: Dictionary) -> Control:
	var c: CharacterData = m.data
	var status := "ko" if m.ko else ("front" if m.fielded and m.vanguard else ("back" if m.fielded else "bench"))
	var colors := {"front": AHKit.NODE_COLORS.battle, "back": AHKit.ACCENT, "bench": UITheme.TEXT_DIM, "ko": AHKit.HANGOVER}
	var color: Color = colors[status]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 62)
	b.disabled = m.ko
	b.tooltip_text = "%s  %s%d%s" % [c.display_name, Terms.term("level"), int(m.level), ("\n" + Terms.t("endless_trained")) if m.train else ""]
	var style := UITheme.box(Color(color, 0.1) if m.fielded else Color(0, 0, 0, 0.25), Color(color, 0.5 if m.fielded else 0.15), 1, 8, 4)
	style.border_width_left = 4 if m.fielded else 1
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("focus", style)
	b.add_theme_stylebox_override("disabled", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(color, 0.22)
	hover.border_color = color.lightened(0.3)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(func(): _act(func(): Endless.toggle_fielded(int(m.index))))
	var row := AHKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 7
	row.offset_right = -6
	row.offset_top = 4
	row.offset_bottom = -4
	b.add_child(row)
	var portrait := AHKit.Portrait.new(c)
	portrait.custom_minimum_size = Vector2(44, 0)
	portrait.show_bars = false
	portrait.ko = m.ko
	portrait.dim = not m.fielded
	row.add_child(portrait)
	var info := AHKit.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var top := AHKit.hbox(4)
	info.add_child(top)
	var name := AHKit.label(c.display_name, 14, Color.WHITE if not m.ko else UITheme.TEXT_DIM)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name)
	if m.train:
		top.add_child(AHKit.chip("+10%", AHKit.NODE_COLORS.train, true))
	info.add_child(AHKit.label("%s · %s%d" % [Terms.t("endless_status_" + status), Terms.term("level"), int(m.level)], 11, color.lightened(0.2)))
	var bars := Bars.new()
	bars.hp = 0.0 if m.ko else float(m.hp)
	bars.energy = float(m.energy) / maxf(float(c.ultimate_max), 1.0) if c.active_skill and c.active_skill.effect_id != &"" else -1.0
	info.add_child(bars)
	return b

## An HP bar with its percentage, and a thin Ultimate bar under it
class Bars extends Control:
	var hp := 1.0
	var energy := -1.0
	func _init() -> void:
		custom_minimum_size = Vector2(0, 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var label := "%d%%" % roundi(hp * 100)
		var lw := 34.0
		var bar := Rect2(0, 2, size.x - lw, 7)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		var col := Color("#4ade80") if hp > 0.5 else (Color("#fbbf24") if hp > 0.25 else Color("#ef4444"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(hp, 0, 1), bar.size.y)), col)
		draw_string(font, Vector2(size.x - lw + 4, 11), label, HORIZONTAL_ALIGNMENT_LEFT, lw, 11, col.lightened(0.3))
		if energy >= 0.0:
			var e := Rect2(0, 11, bar.size.x, 3)
			draw_rect(e, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(e.position, Vector2(e.size.x * clampf(energy, 0, 1), 3)), Color("#facc15"))

## The right side: every Drink taken as a glass on a shelf (Hangovers in red below), how far the boss is, and a
## button to read them all
func _drinks_panel() -> Control:
	var r := Endless.run()
	var panel := AHKit.panel(AHKit.NODE_COLORS.bar, 10, 0.84)
	panel.custom_minimum_size.x = 212
	var box := AHKit.vbox(8)
	panel.add_child(box)
	# The boss countdown
	var boss := AHKit.panel(AHKit.HOT, 8, 0.7)
	box.add_child(boss)
	var brow := AHKit.hbox(8)
	boss.add_child(brow)
	brow.add_child(AHKit.NodeBadge.new("boss", 40))
	var btext := AHKit.vbox(0)
	brow.add_child(btext)
	var left := Endless.FLOORS - 1 - (int(r.floor) + 1)
	btext.add_child(AHKit.label(Terms.t("endless_boss_next") if left <= 0 else Terms.t("endless_boss_in", {"n": left}), 14, AHKit.HOT.lightened(0.3)))
	btext.add_child(AHKit.label(Terms.t("endless_boss_level", {"lv": Endless.enemy_level(int(r.night), Endless.FLOORS - 1) + Endless.BOSS_LEVELS}), 12, UITheme.TEXT_DIM))
	# The shelf
	var drinks := Endless.taken_drinks()
	var good := drinks.filter(func(d): return not d.hangover)
	var bad := drinks.filter(func(d): return d.hangover)
	var head := AHKit.hbox(6)
	box.add_child(head)
	head.add_child(AHKit.label(Terms.t("endless_panel_drinks").to_upper(), 15, AHKit.NODE_COLORS.bar, false, 5))
	head.add_child(AHKit.spacer(false))
	head.add_child(AHKit.chip(str(good.size()), AHKit.NODE_COLORS.bar, true))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var shelf := AHKit.vbox(6)
	shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(shelf)
	if good.is_empty():
		shelf.add_child(AHKit.label(Terms.t("endless_panel_none"), 12, UITheme.TEXT_DIM, true))
	else:
		shelf.add_child(_glass_grid(good))
	if not bad.is_empty():
		shelf.add_child(AHKit.label(Terms.t("endless_panel_hangovers").to_upper(), 13, AHKit.HANGOVER))
		shelf.add_child(_glass_grid(bad))
	box.add_child(AHKit.button(Terms.t("endless_see_all"), _set_pouch.bind(true), AHKit.NODE_COLORS.bar, false, Vector2(0, 38), 14))
	return panel

## Drinks as small glasses in a 4-wide grid, each with its details on hover
func _glass_grid(list: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for d in list:
		var color: Color = AHKit.HANGOVER if d.hangover else AHKit.RARITY[d.rarity]
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(44, 44)
		cell.add_theme_stylebox_override("panel", UITheme.box(Color(color, 0.1), Color(color, 0.5), 1, 6))
		cell.tooltip_text = "%s\n%s" % [d.display_name, d.description]
		var art := AHKit.DrinkArt.new(d)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cell.add_child(art)
		grid.add_child(cell)
	return grid

func _member_chip(m: Dictionary, interactive: bool, size := Vector2(62, 84)) -> Control:
	var c: CharacterData = m.data
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.disabled = not interactive or m.ko
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "%s  %s%d  ·  %s %d%%%s" % [c.display_name, Terms.term("level"), int(m.level),
		Terms.t("endless_status_ko") if m.ko else Terms.t("endless_status_" + ("front" if m.fielded and m.vanguard else ("back" if m.fielded else "bench"))),
		roundi(float(m.hp) * 100), ("\n" + Terms.t("endless_trained")) if m.train else ""]
	b.pressed.connect(func(): _act(func(): Endless.toggle_fielded(int(m.index))))
	var portrait := AHKit.Portrait.new(c)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.hp = float(m.hp)
	portrait.ko = m.ko
	portrait.dim = not m.fielded
	portrait.tag = ("F" if m.vanguard else "B") if m.fielded else ""
	portrait.ring = UITheme.CYAN if m.fielded and not m.ko else Color(0, 0, 0, 0)
	portrait.energy = float(m.energy) / maxf(float(c.ultimate_max), 1.0) if c.active_skill and c.active_skill.effect_id != &"" else -1.0
	b.add_child(portrait)
	return b

func _confirm_give_up() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = Terms.t("endless_give_up_confirm", {"tips": int(Endless.run().tips),
		"tokens": int(Endless.token_tally(false).total)})
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(440, 0)
	dialog.confirmed.connect(func(): _act(func(): Endless.give_up()))
	add_child(dialog)
	dialog.popup_centered()

# ═════════ Overlays ═════════

func _overlay_key(p: Dictionary) -> String:
	var r := Endless.run()
	return "%s|%d|%s|%d|%d" % [String(p.get("kind", "")), int(r.night), String(r.node), int(r.get("fights", 0)), r.pending.size()]

## Shows `content` over a dimmed screen. The first time a given overlay shows, it fades and slides in.
func _open_layer(content: Control, key: String, dim := 0.72, flash := Color(0, 0, 0, 0)) -> Control:
	_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.03, dim)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(shade)
	var slider := Control.new()  # plain holder: its position can tween without a container resetting it
	slider.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(slider)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slider.add_child(center)
	center.add_child(content)
	if key != _last_overlay:
		_last_overlay = key
		shade.modulate.a = 0.0
		shade.create_tween().tween_property(shade, "modulate:a", 1.0, 0.25)
		slider.modulate.a = 0.0
		slider.position.y = 40.0
		var t := slider.create_tween().set_parallel()
		t.tween_property(slider, "modulate:a", 1.0, 0.3)
		t.tween_property(slider, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if flash.a > 0.0:
			var f := ColorRect.new()
			f.color = flash
			f.mouse_filter = Control.MOUSE_FILTER_IGNORE
			f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_layer.add_child(f)
			f.create_tween().tween_property(f, "modulate:a", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC)
			var shake := slider.create_tween()
			for i in 6:
				shake.tween_property(slider, "position:x", (12.0 - i * 2.0) * (1 if i % 2 == 0 else -1), 0.04)
			shake.tween_property(slider, "position:x", 0.0, 0.05)
	return slider

func _overlay(p: Dictionary) -> void:
	var key := _overlay_key(p)
	match String(p.kind):
		"fight":
			_fight_overlay(p, key)
		"drinks":
			_drink_overlay(p, key, false)
		"hangover":
			_drink_overlay(p, key, true)
		"rest":
			_rest_overlay(key)
		"bar":
			_bar_overlay(p, key)
		"event":
			_event_overlay(p, key)
		"result":
			_result_overlay(p, key)
		"night_end":
			_night_end_overlay(key)

## A big centred title with an optional subtitle
func _heading(box: Control, title: String, color: Color, sub: String = "", size := 34) -> void:
	var t := AHKit.label(title, size, color, false, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if not sub.is_empty():
		var s := AHKit.label(sub, 15, UITheme.TEXT, true)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)

# ───────── Encounter ─────────

func _fight_overlay(p: Dictionary, key: String) -> void:
	var kind := String(p.fight)
	var color: Color = AHKit.NODE_COLORS.get(kind, Color.WHITE)
	var stage := Endless.current_stage()
	var content := AHKit.panel(color, 0, 0.95)
	content.custom_minimum_size = Vector2(980, 0)
	var outer := AHKit.vbox(0)
	content.add_child(outer)
	if kind != "battle":
		outer.add_child(AHKit.Hazard.new(color))
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 18)
	outer.add_child(inner)
	var box := AHKit.vbox(12)
	inner.add_child(box)
	# Header
	var head := AHKit.hbox(14)
	box.add_child(head)
	head.add_child(AHKit.NodeBadge.new(kind, 58))
	var titles := AHKit.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(AHKit.label(Terms.t("endless_fight_" + kind).to_upper(), 34, color, false, 8))
	if stage:
		titles.add_child(AHKit.label("%s  ·  %s" % [stage.display_name, Terms.t("endless_enemy_level", {"lv": stage.enemy_level, "waves": stage.wave_count()})], 14, UITheme.TEXT_DIM))
	var rewards := Endless.fight_rewards(kind)
	var reward_box := AHKit.vbox(4)
	head.add_child(reward_box)
	reward_box.add_child(AHKit.label(Terms.t("endless_rewards"), 12, UITheme.TEXT_DIM))
	var tips := CurrencyChip.new("tips", Terms.t("endless_tips_name"))
	tips.set_amount(int(rewards.tips))
	reward_box.add_child(tips)
	reward_box.add_child(AHKit.label(Terms.t("endless_reward_drinks", {"count": int(rewards.picks),
		"rarity": Terms.t("endless_rarity_%d" % int(rewards.rarity))}), 13, AHKit.RARITY[int(rewards.rarity)]))
	# Enemies vs your formation
	var vs := AHKit.hbox(12)
	box.add_child(vs)
	var enemy_panel := AHKit.panel(color, 12, 0.6)
	enemy_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vs.add_child(enemy_panel)
	var eb := AHKit.vbox(8)
	enemy_panel.add_child(eb)
	eb.add_child(AHKit.label(Terms.t("endless_enemies").to_upper(), 14, color.lightened(0.3)))
	eb.add_child(AHKit.spacer())
	var widest := 1
	if stage:
		for wave in stage.waves:
			widest = maxi(widest, (wave.enemy_vanguard + wave.enemy_rearguard).filter(func(c): return c != null).size())
	var face_w := clampf(470.0 / widest - 6.0, 54.0, 92.0)
	if stage and stage.waves.size() > 1:
		face_w = minf(face_w, 64.0)
	if stage:
		for w in stage.waves.size():
			var wave: WaveData = stage.waves[w]
			var line := AHKit.hbox(6)
			eb.add_child(line)
			var wave_name := Terms.t("endless_wave", {"n": w + 1})
			if wave.is_boss:
				wave_name = Terms.t("endless_wave_boss" if kind == "boss" else "endless_wave_elite")
			var tag := AHKit.label(wave_name, 12, AHKit.HOT if wave.is_boss else UITheme.TEXT_DIM)
			tag.custom_minimum_size.x = 56
			line.add_child(tag)
			for c in wave.enemy_vanguard + wave.enemy_rearguard:
				if c == null:
					continue
				var face := AHKit.Portrait.new(c)
				face.show_bars = false
				face.show_name = true
				face.ring = Color(AHKit.HOT, 0.9) if wave.is_boss else Color(0, 0, 0, 0)
				face.custom_minimum_size = Vector2(face_w, face_w * 1.28)
				face.tooltip_text = "%s  ·  %s" % [c.display_name, Terms.class_label(c.char_class)]
				face.mouse_filter = Control.MOUSE_FILTER_PASS
				line.add_child(face)
	eb.add_child(AHKit.spacer())
	var vs_label := AHKit.label("VS", 34, Color.WHITE, false, 10)
	vs_label.add_theme_color_override("font_outline_color", Color(color, 0.9))
	vs_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vs.add_child(vs_label)
	vs.add_child(_formation_board())
	# Go
	var go_row := AHKit.hbox(12)
	box.add_child(go_row)
	var fielded := Endless.members().filter(func(m): return m.fielded and not m.ko).size()
	var hint := AHKit.label(Terms.t("endless_board_hint", {"count": fielded}), 13, UITheme.CYAN, true)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_row.add_child(hint)
	var go := AHKit.button(Terms.t("endless_fight_go"), _press_fight, color, true, Vector2(260, 60), 26)
	go.disabled = fielded == 0 or _fight_sent
	go_row.add_child(go)
	_open_layer(content, key, 0.7, Color(color, 0.25) if kind == "boss" else Color(0, 0, 0, 0))

var _fight_sent := false  # one FIGHT press = one battle, however fast the clicks

func _press_fight() -> void:
	if _fight_sent:
		return
	_fight_sent = true
	fight_pressed.emit()

## Your lineup as a 2 x 3 board (front row on the right, facing the enemies) plus the bench; tap to move people
func _formation_board() -> Control:
	var panel := AHKit.panel(UITheme.CYAN, 12, 0.6)
	panel.custom_minimum_size.x = 380
	var box := AHKit.vbox(6)
	panel.add_child(box)
	box.add_child(AHKit.label(Terms.t("endless_your_lineup").to_upper(), 14, UITheme.CYAN))
	var members := Endless.members()
	for row_key in ["vanguard", "rearguard"]:
		var line := AHKit.hbox(6)
		box.add_child(line)
		var tag := AHKit.label(Terms.t("endless_slot_" + row_key), 12, UITheme.TEXT_DIM)
		tag.custom_minimum_size.x = 64
		line.add_child(tag)
		var fielded := members.filter(func(m): return m.fielded and m.vanguard == (row_key == "vanguard"))
		for i in FormationBattleEngine.ROW_SIZE:
			if i < fielded.size():
				line.add_child(_member_chip(fielded[i], true, Vector2(62, 80)))
			else:
				var empty := Panel.new()
				empty.custom_minimum_size = Vector2(62, 80)
				var s := UITheme.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.15), 1, 6)
				empty.add_theme_stylebox_override("panel", s)
				line.add_child(empty)
	var bench := members.filter(func(m): return not m.fielded)
	if not bench.is_empty():
		box.add_child(AHKit.label(Terms.t("endless_bench"), 12, UITheme.TEXT_DIM))
		var line := HFlowContainer.new()
		line.add_theme_constant_override("h_separation", 6)
		box.add_child(line)
		for m in bench:
			line.add_child(_member_chip(m, true, Vector2(52, 68)))
	return panel

# ───────── Drinks and Hangovers ─────────

func _drink_overlay(p: Dictionary, key: String, hangover: bool) -> void:
	var color := AHKit.HANGOVER if hangover else AHKit.NODE_COLORS.bar
	var content := AHKit.vbox(16)
	content.custom_minimum_size = Vector2(900, 0)
	if hangover:
		content.add_child(AHKit.Hazard.new(AHKit.HANGOVER))
		_heading(content, Terms.t("endless_hangover_title").to_upper(), AHKit.HANGOVER, Terms.t("endless_hangover_sub"), 46)
	else:
		_heading(content, Terms.t("endless_drinks_pick").to_upper(), AHKit.NODE_COLORS.bar, Terms.t("endless_drinks_sub"), 40)
	var row := AHKit.hbox(22)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var fresh := key != _last_overlay
	var i := 0
	for id in p.options:
		var d: DrinkData = Endless.drinks.get(StringName(id))
		if d == null:
			continue
		var card := _drink_card(d, String(id) == _choice, hangover)
		row.add_child(card)
		if fresh:
			var inner: Control = card.get_child(0)
			inner.scale = Vector2(0.0, 1.0)
			inner.modulate.a = 0.0
			var t := inner.create_tween().set_parallel()
			t.tween_property(inner, "scale:x", 1.0, 0.32).set_delay(0.25 + 0.14 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			t.tween_property(inner, "modulate:a", 1.0, 0.2).set_delay(0.25 + 0.14 * i)
		i += 1
	var buttons := AHKit.hbox(14)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(buttons)
	var chosen: DrinkData = Endless.drinks.get(StringName(_choice))
	var confirm := AHKit.button(Terms.t("endless_take_named", {"name": chosen.display_name}) if chosen else Terms.t("endless_pick_one"),
		_confirm_drink.bind(hangover), color, true, Vector2(340, 56), 20)
	confirm.disabled = chosen == null
	buttons.add_child(confirm)
	if not hangover:
		buttons.add_child(AHKit.button(Terms.t("endless_skip"), _skip_drink, UITheme.TEXT_DIM, false, Vector2(120, 56), 15))
	_open_layer(content, key, 0.8, Color(AHKit.HANGOVER, 0.45) if hangover else Color(0, 0, 0, 0))

## A Drink as a tall gacha card: rarity chip, the glass, name, who it affects, what it does
func _drink_card(d: DrinkData, selected: bool, hangover: bool) -> Control:
	var color: Color = AHKit.HANGOVER if hangover else AHKit.RARITY[d.rarity]
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := AHKit.glass(color, 12, 0.95)
	style.border_color = Color.WHITE if selected else color
	style.set_border_width_all(3 if selected else 1)
	style.shadow_size = 28 if selected else (16 if d.rarity == DrinkData.Rarity.LEGENDARY else 10)
	style.shadow_color = Color(color, 0.55 if selected else 0.3)
	card.add_theme_stylebox_override("normal", style)
	card.add_theme_stylebox_override("focus", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.shadow_size = 26
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.pressed.connect(func():
		_choice = String(d.id)
		refresh())
	var holder := AHKit.hold(card, Vector2(250, 370))
	card.mouse_entered.connect(AHKit.lift.bind(card, true))
	card.mouse_exited.connect(AHKit.lift.bind(card, false))
	if selected:  # raised (offsets, not position: see AHKit.pop_in)
		card.offset_top = -14.0
		card.offset_bottom = -14.0
	var box := AHKit.vbox(6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 12
	box.offset_bottom = -12
	card.add_child(box)
	var top := AHKit.hbox(6)
	box.add_child(top)
	top.add_child(AHKit.chip(Terms.t("endless_severity_%d" % d.severity) if hangover else Terms.t("endless_rarity_%d" % d.rarity), color, true))
	top.add_child(AHKit.spacer(false))
	top.add_child(AHKit.chip(_target_text(d), UITheme.CYAN if not hangover else AHKit.HANGOVER))
	var art := AHKit.DrinkArt.new(d)
	art.custom_minimum_size = Vector2(0, 130)
	box.add_child(art)
	if d.rarity == DrinkData.Rarity.LEGENDARY and not hangover:
		var sheen := CollectionTab.Sheen.new(true)
		sheen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(sheen)
	var name := AHKit.label(d.display_name, 22, Color.WHITE, true, 5)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var text := AHKit.label(d.description, 14, UITheme.TEXT, true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	if not hangover and d.rarity != DrinkData.Rarity.COMMON:
		var warn := AHKit.label(Terms.t("endless_hangover_warn_%d" % d.rarity), 12, AHKit.HANGOVER, true)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(warn)
	if selected:
		var tick := AHKit.chip(Terms.t("endless_selected"), Color.WHITE, true)
		tick.position = Vector2(80, -12)
		card.add_child(tick)
	return holder

func _target_text(d: DrinkData) -> String:
	if not d.ally_rules.is_empty():
		match d.target:
			DrinkData.Target.VANGUARD:
				return Terms.t("endless_target_front")
			DrinkData.Target.REARGUARD:
				return Terms.t("endless_target_back")
			DrinkData.Target.CLASS:
				return Terms.class_label(d.target_class)
		return Terms.t("endless_target_squad")
	if not d.enemy_rules.is_empty():
		return Terms.t("endless_target_enemies")
	return Terms.t("endless_target_run")

func _skip_drink() -> void:
	_choice = ""
	Endless.pick_drink("")
	refresh()

func _set_pouch(open: bool) -> void:
	_pouch_open = open
	refresh()

func _confirm_drink(hangover: bool) -> void:
	var id := _choice
	_choice = ""
	if hangover:
		Endless.pick_hangover(id)
	else:
		Endless.pick_drink(id)
	refresh()

# ───────── Rest ─────────

func _rest_overlay(key: String) -> void:
	var color: Color = AHKit.NODE_COLORS.rest
	var content := AHKit.vbox(16)
	_heading(content, Terms.t("endless_rest_title").to_upper(), color, Terms.t("endless_rest_sub"), 40)
	var row := AHKit.hbox(20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var members := Endless.members()
	var heal := roundi(Endless.rest_heal_share() * 100)
	# Heal: the whole card is the button
	var heal_card := _option_card(color, "rest", Terms.t("endless_rest_heal_title"), Terms.t("endless_rest_heal", {"pct": heal}))
	var heal_go := AHKit.button(Terms.t("endless_rest_heal_go", {"pct": heal}), func(): _act(func(): Endless.rest("heal")), color, true, Vector2(0, 48))
	heal_go.disabled = heal <= 0
	heal_card.get_meta("box").add_child(heal_go)
	row.add_child(heal_card)
	# Revive: pick a knocked-out friend
	var ko := members.filter(func(m): return m.ko)
	var revive_card := _option_card(AHKit.PINK, "revive", Terms.t("endless_rest_revive_title"), Terms.t("endless_rest_revive", {"pct": roundi(Endless.REVIVE_HP * 100)}))
	revive_card.get_meta("box").add_child(_member_pick(ko, _rest_on.bind("revive"), Terms.t("endless_rest_none_ko")))
	row.add_child(revive_card)
	# Train
	var trainable := members.filter(func(m): return not m.ko and not m.train)
	var train_card := _option_card(AHKit.NODE_COLORS.train, "train", Terms.t("endless_rest_train_title"), Terms.t("endless_rest_train", {"pct": roundi((Endless.TRAIN_MULT - 1.0) * 100)}))
	train_card.get_meta("box").add_child(_member_pick(trainable, _rest_on.bind("train"), Terms.t("endless_rest_none_train")))
	row.add_child(train_card)
	var cards := [heal_card, revive_card, train_card]
	if key != _last_overlay:
		for i in cards.size():
			AHKit.pop_in(cards[i].get_child(0), 0.2 + 0.1 * i, Vector2(0, 30))
	_open_layer(content, key)

## Rest on a friend: `m` comes from _member_pick, `action` is bound ("revive" / "train")
func _rest_on(m: Dictionary, action: String) -> void:
	Endless.rest(action, int(m.index))
	refresh()

## A tall option card (Rest): icon, title, text; the caller adds its action into get_meta("box")
func _option_card(color: Color, icon: String, title: String, text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AHKit.glass(color, 16, 0.94))
	var holder := AHKit.hold(panel, Vector2(270, 330))
	var box := AHKit.vbox(10)
	panel.add_child(box)
	var badge := AHKit.NodeBadge.new(icon, 70)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(badge)
	var t := AHKit.label(title.to_upper(), 22, color.lightened(0.2), true, 6)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := AHKit.label(text, 14, UITheme.TEXT, true)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(s)
	holder.set_meta("box", box)
	panel.mouse_entered.connect(AHKit.lift.bind(panel, true))
	panel.mouse_exited.connect(AHKit.lift.bind(panel, false))
	return holder

## Small friend portraits to tap (Rest revive / train), or a note when nobody fits
func _member_pick(list: Array, on_pick: Callable, none_text: String) -> Control:
	if list.is_empty():
		var l := AHKit.label(none_text, 13, UITheme.TEXT_DIM, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for m in list:
		var b := Button.new()
		b.custom_minimum_size = Vector2(52, 68)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = m.data.display_name
		b.pressed.connect(on_pick.bind(m))
		var p := AHKit.Portrait.new(m.data)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		p.hp = float(m.hp)
		p.ko = m.ko
		p.energy = -1.0
		b.add_child(p)
		flow.add_child(b)
	return flow

# ───────── Bar ─────────

func _bar_overlay(p: Dictionary, key: String) -> void:
	var color: Color = AHKit.NODE_COLORS.bar
	var content := AHKit.panel(color, 18, 0.95)
	content.custom_minimum_size = Vector2(1060, 0)
	var box := AHKit.vbox(10)
	content.add_child(box)
	var head := AHKit.hbox(12)
	box.add_child(head)
	var sign := AHKit.NeonSign.new(Terms.t("endless_bar_title").to_upper(), color, 36)
	sign.custom_minimum_size = Vector2(260, 46)
	head.add_child(sign)
	var sub := AHKit.label(Terms.t("endless_bar_welcome"), 14, UITheme.TEXT_DIM, true)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)
	var tips := CurrencyChip.new("tips", Terms.t("endless_tips_name"))
	tips.set_amount(int(Endless.run().tips))
	head.add_child(tips)
	var fresh := key != _last_overlay
	# The shelf: friends to hire, then Drinks on tap, as cards in one row
	var shelf := AHKit.hbox(12)
	box.add_child(shelf)
	var n := 0
	for group in ["hire", "drink"]:
		var col := AHKit.vbox(6)
		shelf.add_child(col)
		col.add_child(_section(Terms.t("endless_shelf_" + group)))
		var cards := AHKit.hbox(10)
		col.add_child(cards)
		for i in p.items.size():
			if String(p.items[i].type) != group:
				continue
			var card := _bar_card(p, i)
			if card == null:
				continue
			cards.add_child(card)
			if fresh:
				AHKit.pop_in(card.get_child(0), 0.15 + 0.05 * n, Vector2(0, 22), 0.3)
			n += 1
		if cards.get_child_count() == 0:
			col.add_child(AHKit.label(Terms.t("endless_shelf_empty"), 13, UITheme.TEXT_DIM))
	# Services as compact tiles
	box.add_child(_section(Terms.t("endless_shelf_service")))
	var services := HFlowContainer.new()
	services.add_theme_constant_override("h_separation", 10)
	services.add_theme_constant_override("v_separation", 8)
	box.add_child(services)
	for i in p.items.size():
		if String(p.items[i].type) in ["heal", "revive", "cure"]:
			services.add_child(_service_tile(p, i))
	box.add_child(AHKit.spacer())
	var leave := AHKit.button(Terms.t("endless_bar_leave"), func(): _act(Endless.leave_bar), color, true, Vector2(0, 50), 18)
	box.add_child(leave)
	_open_layer(content, key)

func _bar_card(p: Dictionary, i: int) -> Control:
	var item: Dictionary = p.items[i]
	var kind := String(item.type)
	var sold: bool = item.get("sold", false)
	var color: Color = AHKit.NODE_COLORS.bar
	var size := Vector2(148, 222)
	var art: Control
	var name := ""
	var note := ""
	match kind:
		"hire":
			var c := GameState.get_character(int(item.uid))
			if c == null:
				return null
			color = CharArt.RARITY_COLORS.get(c.rarity, color)
			var portrait := AHKit.Portrait.new(c)
			portrait.show_bars = false
			art = portrait
			name = c.display_name
			note = "%s %s · %s%d" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class), Terms.term("level"), int(GameState.get_owned(int(item.uid)).level)]
		"drink":
			var d: DrinkData = Endless.drinks.get(StringName(item.id))
			color = AHKit.RARITY[d.rarity]
			art = AHKit.DrinkArt.new(d)
			name = d.display_name
			note = d.description
			size = Vector2(176, 222)
		_:
			size = Vector2(170, 200)
			var icon := "rest" if kind == "heal" else ("event" if kind == "revive" else "elite")
			art = AHKit.NodeBadge.new(icon, 0)
			match kind:
				"heal":
					name = Terms.t("endless_bar_heal_short")
					note = Terms.t("endless_bar_heal", {"pct": roundi(float(Endless.PRICES.heal_pct) * 100)})
					color = AHKit.NODE_COLORS.rest
				"revive":
					name = Terms.t("endless_bar_revive_short")
					note = Terms.t("endless_bar_revive", {"pct": roundi(Endless.REVIVE_HP * 100)})
					color = AHKit.PINK
				"cure":
					var h: DrinkData = Endless.drinks.get(StringName(item.id))
					name = Terms.t("endless_bar_cure", {"name": h.display_name})
					note = h.description
					color = AHKit.HANGOVER
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", AHKit.glass(color, 10, 0.9))
	var holder := AHKit.hold(panel, size)
	var box := AHKit.vbox(4)
	panel.add_child(box)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size.y = 70
	box.add_child(art)
	var title := AHKit.label(name, 15, Color.WHITE, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := AHKit.label(note, 11, UITheme.TEXT_DIM, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var buy := AHKit.button(Terms.t("endless_bar_buy", {"price": int(item.price)}), func(): _act(func(): Endless.buy(i)),
		AHKit.TIPS, Endless.can_buy(i), Vector2(0, 36), 15)
	buy.disabled = sold or not Endless.can_buy(i)
	box.add_child(buy)
	if sold:
		var stamp := AHKit.Stamp.new(Terms.t("endless_sold_stamp"))
		stamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(stamp)
		panel.modulate = Color(0.75, 0.75, 0.8)
	panel.mouse_entered.connect(AHKit.lift.bind(panel, true))
	panel.mouse_exited.connect(AHKit.lift.bind(panel, false))
	return holder

## A Bar service (heal, revive, cure) as a compact tile: icon, name, what it does, price
func _service_tile(p: Dictionary, i: int) -> Control:
	var item: Dictionary = p.items[i]
	var kind := String(item.type)
	var icon := "rest"
	var color: Color = AHKit.NODE_COLORS.rest
	var name := Terms.t("endless_bar_heal_short")
	var note := Terms.t("endless_bar_heal", {"pct": roundi(float(Endless.PRICES.heal_pct) * 100)})
	if kind == "revive":
		icon = "revive"
		color = AHKit.PINK
		name = Terms.t("endless_bar_revive_short")
		note = Terms.t("endless_bar_revive", {"pct": roundi(Endless.REVIVE_HP * 100)})
	elif kind == "cure":
		var h: DrinkData = Endless.drinks.get(StringName(item.id))
		icon = "elite"
		color = AHKit.HANGOVER
		name = Terms.t("endless_bar_cure", {"name": h.display_name if h else "?"})
		note = h.description if h else ""
	var panel := AHKit.panel(color, 8, 0.85)
	panel.custom_minimum_size = Vector2(320, 0)
	var row := AHKit.hbox(8)
	panel.add_child(row)
	row.add_child(AHKit.NodeBadge.new(icon, 38))
	var text := AHKit.vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(AHKit.label(name, 14, Color.WHITE))
	text.add_child(AHKit.label(note, 11, UITheme.TEXT_DIM, true))
	var sold: bool = item.get("sold", false)
	var buy := AHKit.button(Terms.t("endless_bar_sold") if sold else Terms.t("endless_bar_buy", {"price": int(item.price)}),
		func(): _act(func(): Endless.buy(i)), AHKit.TIPS, Endless.can_buy(i), Vector2(96, 36), 14)
	buy.disabled = sold or not Endless.can_buy(i)
	row.add_child(buy)
	return panel

# ───────── Event ─────────

func _event_overlay(p: Dictionary, key: String) -> void:
	var ev := Endless.event_data(String(p.id))
	if ev == null:
		return
	var color: Color = AHKit.NODE_COLORS.event
	var fresh := key != _last_overlay
	var content := AHKit.hbox(24)
	content.custom_minimum_size = Vector2(1060, 520)
	# The narrator: whoever is standing first in the squad, reacting to the scene
	var narrator: CharacterData = null
	for m in Endless.members():
		if not m.ko:
			narrator = m.data
			break
	var stand := Control.new()
	stand.custom_minimum_size = Vector2(300, 0)
	content.add_child(stand)
	if narrator:
		var portrait := AHKit.Portrait.new(narrator)
		portrait.show_bars = false
		portrait.position = Vector2(10, 40)
		portrait.size = Vector2(280, 380)
		stand.add_child(portrait)
		var name_plate := AHKit.panel(color, 8, 0.95)
		name_plate.position = Vector2(20, 400)
		name_plate.add_child(AHKit.label(narrator.display_name, 18, Color.WHITE))
		stand.add_child(name_plate)
		if fresh:
			portrait.position.x = -80
			portrait.modulate.a = 0.0
			var t := portrait.create_tween().set_parallel()
			t.tween_property(portrait, "position:x", 10.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			t.tween_property(portrait, "modulate:a", 1.0, 0.35)
	var right := AHKit.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)
	right.add_child(AHKit.spacer())
	var dialog := AHKit.panel(color, 18, 0.95)
	right.add_child(dialog)
	var dbox := AHKit.vbox(8)
	dialog.add_child(dbox)
	var title_row := AHKit.hbox(10)
	dbox.add_child(title_row)
	title_row.add_child(AHKit.NodeBadge.new("event", 34))
	title_row.add_child(AHKit.label(ev.title.to_upper(), 24, color.lightened(0.3), false, 6))
	var text := AHKit.label(ev.text, 17, Color.WHITE, true)
	text.custom_minimum_size.x = 640
	dbox.add_child(text)
	if fresh:
		text.visible_ratio = 0.0
		text.create_tween().tween_property(text, "visible_ratio", 1.0, clampf(ev.text.length() * 0.022, 0.4, 1.6))
	for i in ev.choices.size():
		var choice: Dictionary = ev.choices[i]
		right.add_child(_choice_button(ev, i, choice, color, fresh))
	right.add_child(AHKit.spacer())
	_open_layer(content, key, 0.82)

## An Event choice: the line, then chips for what it costs, how risky it is and what it can bring
func _choice_button(ev: EndlessEvent, i: int, choice: Dictionary, color: Color, fresh: bool) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 58)
	var style := AHKit.glass(color, 10, 0.9, 8)
	style.skew = Vector2(0.12, 0)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("focus", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(color, 0.25)
	hover.shadow_size = 22
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var disabled := style.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.05, 0.05, 0.08, 0.8)
	disabled.border_color = Color(1, 1, 1, 0.1)
	b.add_theme_stylebox_override("disabled", disabled)
	b.disabled = not Endless.can_choose(ev, i)
	b.pressed.connect(func(): _act(func(): Endless.choose_event(i)))
	var row := AHKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -14
	b.add_child(row)
	var line := AHKit.label(String(choice.text), 17, Color.WHITE if not b.disabled else UITheme.TEXT_DIM)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(line)
	for spec in _choice_hints(choice):
		var c := AHKit.chip(spec[0], spec[1])
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(c)
	var holder := AHKit.hold(b, Vector2(0, 58))
	if fresh:
		AHKit.pop_in(b, 0.35 + 0.1 * i, Vector2(40, 0), 0.35)
	return holder

func _choice_hints(choice: Dictionary) -> Array:
	var out := []
	if int(choice.get("cost_tips", 0)) > 0:
		out.append([Terms.t("endless_hint_cost", {"tips": int(choice.cost_tips)}), AHKit.TIPS])
	if choice.has("chance"):
		out.append([Terms.t("endless_hint_chance", {"pct": roundi(float(choice.chance) * 100)}), AHKit.NODE_COLORS.bar])
	var fx: Dictionary = choice.get("effects", {})
	if fx.has("drink"):
		out.append([Terms.t("endless_hint_drink", {"rarity": Terms.t("endless_rarity_%d" % maxi(["common", "rare", "legendary"].find(String(fx.drink)), 0))}), AHKit.RARITY[maxi(["common", "rare", "legendary"].find(String(fx.drink)), 0)]])
	if fx.has("fight"):
		out.append([Terms.t("endless_hint_fight_" + String(fx.fight)), AHKit.NODE_COLORS.elite])
	if fx.has("heal"):
		out.append([Terms.t("endless_hint_heal"), AHKit.NODE_COLORS.rest])
	if fx.has("hire"):
		out.append([Terms.t("endless_hint_hire"), UITheme.CYAN])
	if fx.has("revive"):
		out.append([Terms.t("endless_hint_revive"), AHKit.PINK])
	if fx.has("tips") and int(fx.tips) > 0 and not fx.has("fight"):
		out.append([Terms.t("endless_hint_tips", {"tips": int(fx.tips)}), AHKit.TIPS])
	if fx.has("energy"):
		out.append([Terms.t("endless_hint_energy"), Color("#facc15")])
	if fx.has("hangover") or fx.has("damage") or choice.get("fail_effects", {}).has("hangover"):
		out.append([Terms.t("endless_hint_risk"), AHKit.HANGOVER])
	return out

func _result_overlay(p: Dictionary, key: String) -> void:
	var content := AHKit.panel(AHKit.NODE_COLORS.event, 22, 0.95)
	content.custom_minimum_size = Vector2(620, 0)
	var box := AHKit.vbox(12)
	content.add_child(box)
	_heading(box, String(p.get("title", Terms.t("endless_result_title"))).to_upper(), AHKit.NODE_COLORS.event, String(p.get("text", "")), 26)
	var fx := HFlowContainer.new()
	fx.alignment = FlowContainer.ALIGNMENT_CENTER
	fx.add_theme_constant_override("h_separation", 8)
	box.add_child(fx)
	for line in p.get("effects", []):
		fx.add_child(AHKit.chip(line, AHKit.NODE_COLORS.bar, true))
	box.add_child(AHKit.button(Terms.t("endless_ok"), func(): _act(Endless.dismiss_result), AHKit.ACCENT, true, Vector2(0, 50), 18))
	_open_layer(content, key)

# ───────── End of a Night ─────────

func _night_end_overlay(key: String) -> void:
	var r := Endless.run()
	var content := Control.new()
	content.custom_minimum_size = Vector2(1000, 520)
	var rays := BattleResults.Rays.new()
	rays.color = UITheme.GOLD
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(rays)
	var box := AHKit.vbox(16)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(box)
	box.add_child(AHKit.spacer())
	_heading(box, Terms.t("endless_night_won", {"night": Endless.night_name()}).to_upper(), UITheme.GOLD, Terms.t("endless_night_choice"), 46)
	var row := AHKit.hbox(26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var next := Endless.night_name(int(r.night) + 1)
	var go := _option_card(AHKit.PINK, "boss", Terms.t("endless_night_go", {"next": next}), Terms.t("endless_night_go_text", {"pct": roundi(Endless.TIPS_PER_NIGHT * 100)}))
	go.get_meta("box").add_child(AHKit.button(Terms.t("endless_night_go_button"), func(): _act(func(): Endless.night_end(true)), AHKit.PINK, true, Vector2(0, 50), 18))
	row.add_child(go)
	var cash := _option_card(UITheme.GOLD, "bar", Terms.t("endless_night_cash"), Terms.t("endless_night_cash_text", {"tips": int(r.tips),
		"tokens": int(Endless.token_tally(true).total), "crash": int(Endless.token_tally(false).total)}))
	cash.get_meta("box").add_child(AHKit.button(Terms.t("endless_night_cash_button"), func(): _act(func(): Endless.night_end(false)), UITheme.GOLD, false, Vector2(0, 50), 18))
	row.add_child(cash)
	box.add_child(AHKit.spacer())
	if key != _last_overlay:
		AHKit.pop_in(go.get_child(0), 0.35, Vector2(-40, 0))
		AHKit.pop_in(cash.get_child(0), 0.45, Vector2(40, 0))
	_open_layer(content, key, 0.85, Color(UITheme.GOLD, 0.3))

# ───────── Drinks pouch ─────────

func _pouch_overlay() -> void:
	var content := AHKit.panel(AHKit.NODE_COLORS.bar, 18, 0.96)
	content.custom_minimum_size = Vector2(900, 480)
	var box := AHKit.vbox(10)
	content.add_child(box)
	var head := AHKit.hbox(10)
	box.add_child(head)
	var title := AHKit.label(Terms.t("endless_pouch_title").to_upper(), 24, AHKit.NODE_COLORS.bar, false, 6)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(AHKit.button(Terms.t("endless_close"), _set_pouch.bind(false), UITheme.CYAN, false, Vector2(100, 38), 14))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(flow)
	var drinks := Endless.taken_drinks()
	if drinks.is_empty():
		flow.add_child(AHKit.label(Terms.t("endless_pouch_empty"), 15, UITheme.TEXT_DIM))
	for d in drinks:
		var color: Color = AHKit.HANGOVER if d.hangover else AHKit.RARITY[d.rarity]
		var panel := AHKit.panel(color, 10, 0.9)
		panel.custom_minimum_size = Vector2(200, 0)
		var col := AHKit.vbox(4)
		panel.add_child(col)
		var art := AHKit.DrinkArt.new(d)
		art.custom_minimum_size = Vector2(0, 70)
		col.add_child(art)
		col.add_child(AHKit.label(d.display_name, 15, color.lightened(0.2), true))
		col.add_child(AHKit.label(d.description, 12, UITheme.TEXT, true))
		flow.add_child(panel)
	_open_layer(content, "pouch")

# ═════════ Results ═════════

func _results_page() -> Control:
	var last := Endless.last_run()
	var cashed: bool = last.cashed_out
	var color := UITheme.GOLD if cashed else AHKit.HANGOVER
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var rays := BattleResults.Rays.new()
	rays.color = color
	rays.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(rays)
	var row := AHKit.hbox(30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_margin(row, 24))
	# Left: the title, grade and squad
	var left := AHKit.vbox(10)
	left.custom_minimum_size.x = 440
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(left)
	var title := AHKit.label(Terms.t("endless_over_cashed" if cashed else "endless_over_crashed").to_upper(), 40, color, false, 9)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(title)
	var grade := AHKit.NeonSign.new(Endless.grade(int(last.floors)), color, 120)
	grade.custom_minimum_size = Vector2(0, 150)
	left.add_child(grade)
	var floors := AHKit.label("", 22, Color.WHITE, false, 6)
	floors.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(floors)
	_count_up(floors, int(last.floors), 0.9, func(v): return Terms.t("endless_over_reached", {"floors": v, "night": Endless.night_name(int(last.night))}))
	if last.get("new_best", false):
		var best := AHKit.chip(Terms.t("endless_new_best"), UITheme.GOLD, true)
		best.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		left.add_child(best)
	var squad := HFlowContainer.new()
	squad.alignment = FlowContainer.ALIGNMENT_CENTER
	squad.add_theme_constant_override("h_separation", 6)
	squad.add_theme_constant_override("v_separation", 6)
	left.add_child(squad)
	for s in last.get("squad", []):
		var c: CharacterData = DB.characters.get(StringName(s.id))
		if c == null:
			continue
		var p := AHKit.Portrait.new(c)
		p.show_bars = false
		p.ko = s.ko
		p.custom_minimum_size = Vector2(58, 72)
		p.ring = UITheme.GOLD if c.display_name == String(last.get("mvp", "")) else Color(0, 0, 0, 0)
		p.tooltip_text = c.display_name
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		squad.add_child(p)
	if not String(last.get("mvp", "")).is_empty():
		var mvp := AHKit.label(Terms.t("endless_mvp", {"name": last.mvp, "damage": Terms.number(int(last.mvp_dealt))}), 14, UITheme.GOLD)
		mvp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		left.add_child(mvp)
	# Right: the Token breakdown
	var panel := AHKit.panel(AHKit.ACCENT, 20, 0.92)
	panel.custom_minimum_size.x = 460
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	var box := AHKit.vbox(8)
	panel.add_child(box)
	box.add_child(AHKit.label(Terms.t("endless_tokens_earned").to_upper(), 16, AHKit.ACCENT.lightened(0.3)))
	var lines: Array = last.get("lines", [])
	for i in lines.size():
		var line: Array = lines[i]
		var r := AHKit.hbox(8)
		var text := AHKit.label(Terms.t(String(line[0]), line[1]), 15, UITheme.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(text)
		r.add_child(AHKit.label("+%d" % int(line[2]), 15, AHKit.ACCENT.lightened(0.4)))
		box.add_child(r)
		r.modulate.a = 0.0
		r.create_tween().tween_property(r, "modulate:a", 1.0, 0.25).set_delay(0.4 + 0.18 * i)
	box.add_child(HSeparator.new())
	var total_row := AHKit.hbox(10)
	box.add_child(total_row)
	var total_label := AHKit.label(Terms.t("endless_tokens_total_label"), 18, Color.WHITE)
	total_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_row.add_child(total_label)
	var total := CurrencyChip.new("night_token", Terms.t("endless_token_name"))
	total.set_amount(0)
	total_row.add_child(total)
	var t := total.create_tween()
	t.tween_interval(0.5 + 0.18 * lines.size())
	t.tween_callback(func(): total.set_amount(int(last.tokens)))
	for m in last.get("milestones", []):
		box.add_child(AHKit.label(Terms.t("endless_milestone", {"night": Endless.night_name(int(m.night)), "reward": Daily.reward_text(m.reward)}), 14, UITheme.GOLD, true))
	var drinks := HFlowContainer.new()
	drinks.add_theme_constant_override("h_separation", 2)
	for id in last.get("drinks", []) + last.get("hangovers", []):
		var d: DrinkData = Endless.drinks.get(StringName(id))
		if d:
			var art := AHKit.DrinkArt.new(d)
			art.custom_minimum_size = Vector2(36, 36)
			art.tooltip_text = "%s: %s" % [d.display_name, d.description]
			art.mouse_filter = Control.MOUSE_FILTER_PASS
			drinks.add_child(art)
	if drinks.get_child_count() > 0:
		box.add_child(AHKit.label(Terms.t("endless_over_drinks_title"), 12, UITheme.TEXT_DIM))
		box.add_child(drinks)
	box.add_child(AHKit.button(Terms.t("endless_over_ok"), func(): _act(Endless.clear_last_run), AHKit.PINK, true, Vector2(0, 54), 18))
	return root

## Counts a label up to `to` over `seconds`, formatting each value with `fmt`
func _count_up(label: Label, to: int, seconds: float, fmt: Callable) -> void:
	label.text = fmt.call(0)
	var t := label.create_tween()
	t.tween_method(func(v: float): label.text = fmt.call(roundi(v)), 0.0, float(to), seconds).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
