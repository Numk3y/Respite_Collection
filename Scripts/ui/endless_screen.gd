class_name EndlessScreen
extends Control
## The After Hours screen (Endless autoload). Without a run: the lobby (pick the opening pair: 1 vanguard + 1
## rearguard) and the Night Token shop; after a run: its summary. During a run: the squad on the left (click a friend
## to field or bench them), Drinks and Hangovers under it, and on the right either the Night's map or whatever
## choice is waiting (a fight, a Drink offer, a forced Hangover, the Rest, the Bar, an Event, the end of a Night).
## Main listens to fight_pressed (play the waiting fight in a BattleView) and back_pressed.

signal fight_pressed
signal back_pressed

const ACCENT := Color("#c084fc")
const NODE_COLORS := {"battle": Color("#94a3b8"), "elite": Color("#ef4444"), "event": Color("#a78bfa"),
	"rest": Color("#4ade80"), "bar": Color("#fbbf24"), "boss": Color("#f43f5e")}
const RARITY_COLORS := [Color("#cbd5e1"), Color("#60a5fa"), Color("#fbbf24")]
const HANGOVER_COLOR := Color("#f87171")

var _body: Control
var _info: Label
var _view := "lobby"  # without a run: "lobby" or "shop"
var _pick := {"vanguard": 0, "rearguard": 0}  # lobby: chosen uids

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var background := TextureRect.new()
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.28, 0.24, 0.36)
	background.texture = UITheme.background("FrennisNightClub")
	_full(background)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	content.add_child(_header())
	_body = MarginContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_body)
	refresh()

func _full(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	return node

# ───────── Small builders ─────────

func _label(text: String, font_size: int = 15, color: Color = UITheme.TEXT, wrap := false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _panel(glow: Color = ACCENT, margin: float = 12) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.glow_box(Color(0.04, 0.05, 0.1, 0.92), 12, margin, glow))
	return panel

func _vbox(sep: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	return box

func _hbox(sep: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", sep)
	return box

func _button(text: String, callback: Callable, primary := false, min_size := Vector2(0, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(callback)
	return b

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func _show_view(view: String) -> void:
	_view = view
	refresh()

func _start_run() -> void:
	if Endless.start_run(int(_pick.vanguard), int(_pick.rearguard)):
		refresh()

## Does something to the run, then redraws
func _act(callable: Callable) -> void:
	callable.call()
	refresh()

func _header() -> Control:
	var header := _hbox(12)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ACCENT.darkened(0.35)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 26
	style.content_margin_right = 30
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(ACCENT, 0.45)
	style.shadow_size = 12
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_label(Terms.t("endless_title").to_upper(), 24, Color.WHITE))
	header.add_child(plate)
	_info = _label("", 16, UITheme.TEXT)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_info)
	header.add_child(_button(Terms.t("back"), back_pressed.emit, false, Vector2(110, 38)))
	return header

func refresh() -> void:
	_clear(_body)
	if Endless.has_run():
		var r := Endless.run()
		_info.text = Terms.t("endless_header_run", {"night": Endless.night_name(), "floor": maxi(int(r.floor) + 1, 0),
			"floors": Endless.FLOORS, "tips": int(r.tips)})
		_body.add_child(_run_view())
	elif not Endless.last_run().is_empty():
		_info.text = Terms.t("endless_header_lobby", {"best": Endless.best_floor(), "tokens": Endless.tokens()})
		_body.add_child(_run_over_view())
	else:
		_info.text = Terms.t("endless_header_lobby", {"best": Endless.best_floor(), "tokens": Endless.tokens()})
		_body.add_child(_shop_view() if _view == "shop" else _lobby_view())

# ───────── Lobby ─────────

func _lobby_view() -> Control:
	var row := _hbox(12)
	var left := _panel()
	left.custom_minimum_size.x = 330
	row.add_child(left)
	var info := _vbox(10)
	left.add_child(info)
	info.add_child(_label(Terms.t("endless_lobby_title"), 20, ACCENT.lightened(0.3)))
	info.add_child(_label(Terms.t("endless_lobby_text"), 14, UITheme.TEXT, true))
	info.add_child(_label(Terms.t("endless_best", {"best": Endless.best_floor()}), 15, UITheme.GOLD))
	info.add_child(_label(Terms.t("endless_tokens", {"tokens": Endless.tokens()}), 15, ACCENT.lightened(0.4)))
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(push)
	info.add_child(_button(Terms.t("endless_shop_button"), _show_view.bind("shop"), false, Vector2(0, 44)))

	var right := _panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var box := _vbox(8)
	right.add_child(box)
	if not Endless.is_open():
		box.add_child(_label(Terms.t("endless_locked", {"code": Endless.unlock_code()}), 18, HANGOVER_COLOR, true))
		return row
	box.add_child(_label(Terms.t("endless_pick_title"), 18, Color.WHITE))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var lists := _vbox(6)
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lists)
	for row_key in ["vanguard", "rearguard"]:
		lists.add_child(_label(Terms.t("endless_pick_" + row_key), 14, UITheme.TEXT_DIM))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		lists.add_child(flow)
		var group := ButtonGroup.new()
		var owned: Array = GameState.data.owned.duplicate()
		owned.sort_custom(func(a, b): return int(a.level) > int(b.level))
		for o in owned:
			var c := GameState.get_character(int(o.uid))
			if c == null or c.is_vanguard() != (row_key == "vanguard"):
				continue
			var card := _friend_button(c, int(o.level))
			card.toggle_mode = true
			card.button_group = group
			card.button_pressed = _pick[row_key] == int(o.uid)
			card.toggled.connect(func(on: bool):
				if on:
					_pick[row_key] = int(o.uid)
					refresh.call_deferred())
			flow.add_child(card)
	var ready := GameState.get_character(_pick.vanguard) != null and GameState.get_character(_pick.rearguard) != null
	var start := _button(Terms.t("endless_start"), _start_run, true, Vector2(0, 52))
	start.disabled = not ready
	start.add_theme_font_size_override("font_size", 20)
	box.add_child(start)
	return row

func _friend_button(c: CharacterData, level: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(92, 118)
	b.tooltip_text = "%s  Lv.%d" % [c.display_name, level]
	var box := _vbox(2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_right = -4
	box.offset_top = 4
	box.offset_bottom = -4
	b.add_child(box)
	var art := CharArt.new()
	art.custom_minimum_size = Vector2(0, 82)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_character(c)
	box.add_child(art)
	var name := _label("%s" % c.display_name, 11, UITheme.TEXT)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var lv := _label("Lv.%d" % level, 10, UITheme.TEXT_DIM)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(lv)
	return b

# ───────── Run over ─────────

func _run_over_view() -> Control:
	var last := Endless.last_run()
	var center := CenterContainer.new()
	var panel := _panel(UITheme.GOLD if last.cashed_out else HANGOVER_COLOR, 18)
	panel.custom_minimum_size.x = 560
	center.add_child(panel)
	var box := _vbox(8)
	panel.add_child(box)
	var title := _label(Terms.t("endless_over_cashed" if last.cashed_out else "endless_over_crashed"), 30,
		UITheme.GOLD if last.cashed_out else HANGOVER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label(Terms.t("endless_over_reached", {"floors": int(last.floors), "night": Endless.night_name(int(last.night))}), 17, Color.WHITE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	if last.get("new_best", false):
		var best := _label(Terms.t("endless_new_best"), 16, UITheme.GOLD)
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(best)
	# Squad portraits, knocked-out ones greyed
	var squad := HFlowContainer.new()
	squad.alignment = FlowContainer.ALIGNMENT_CENTER
	squad.add_theme_constant_override("h_separation", 6)
	box.add_child(squad)
	for s in last.get("squad", []):
		var c: CharacterData = DB.characters.get(StringName(s.id))
		if c:
			var art := CharArt.new()
			art.custom_minimum_size = Vector2(52, 64)
			art.set_character(c)
			art.tooltip_text = c.display_name
			if s.ko:
				art.modulate = Color(0.45, 0.45, 0.5)
			squad.add_child(art)
	if not String(last.get("mvp", "")).is_empty():
		box.add_child(_label(Terms.t("endless_mvp", {"name": last.mvp, "damage": Terms.number(int(last.mvp_dealt))}), 14, UITheme.CYAN))
	box.add_child(HSeparator.new())
	box.add_child(_label(Terms.t("endless_tokens_earned"), 15, ACCENT.lightened(0.3)))
	for line in last.get("lines", []):
		var row := _hbox(8)
		var text := _label(Terms.t(String(line[0]), line[1]), 14, UITheme.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		row.add_child(_label("+%d" % int(line[2]), 14, ACCENT.lightened(0.4)))
		box.add_child(row)
	var total := _label(Terms.t("endless_tokens_total", {"tokens": int(last.tokens)}), 18, ACCENT.lightened(0.5))
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(total)
	for m in last.get("milestones", []):
		box.add_child(_label(Terms.t("endless_milestone", {"night": Endless.night_name(int(m.night)),
			"reward": Daily.reward_text(m.reward)}), 15, UITheme.GOLD, true))
	var drinks := PackedStringArray()
	for id in last.get("drinks", []):
		var d: DrinkData = Endless.drinks.get(StringName(id))
		if d:
			drinks.append(d.display_name)
	if not drinks.is_empty():
		box.add_child(_label(Terms.t("endless_over_drinks", {"list": ", ".join(drinks)}), 13, UITheme.TEXT_DIM, true))
	box.add_child(_button(Terms.t("endless_over_ok"), _act.bind(Endless.clear_last_run), true, Vector2(0, 46)))
	return center

# ───────── Night Token shop ─────────

func _shop_view() -> Control:
	var panel := _panel()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := _vbox(10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var top := _hbox(10)
	var title := _label(Terms.t("endless_shop_title"), 20, ACCENT.lightened(0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(_label(Terms.t("endless_tokens", {"tokens": Endless.tokens()}), 17, ACCENT.lightened(0.5)))
	top.add_child(_button(Terms.t("endless_shop_close"), _show_view.bind("lobby"), false, Vector2(120, 38)))
	box.add_child(top)
	box.add_child(_label(Terms.t("endless_shop_tickets"), 15, UITheme.TEXT_DIM))
	for i in Endless.SHOP_TICKETS.size():
		var item: Dictionary = Endless.SHOP_TICKETS[i]
		var left := Endless.ticket_left(item)
		box.add_child(_shop_row(Terms.t(String(item.id) + "_one"), Terms.t("endless_shop_month_left", {"left": left, "limit": int(item.limit)}),
			int(item.price), left > 0, func(): _act(func(): Endless.buy_ticket(i))))
	box.add_child(_label(Terms.t("endless_shop_gear", {"time": Daily.format_time(Daily.seconds_to_weekly_reset())}), 15, UITheme.TEXT_DIM))
	for e in Endless.gear_stock():
		var mods := PackedStringArray()
		var m := e.modifiers()
		for stat in m:
			mods.append("%s %+d" % [Terms.stat_short(stat), int(m[stat])])
		var row := _shop_row("%s  (%s %s)" % [e.display_name, Terms.rarity_name(e.rarity), Terms.slot_name(e.slot_key())],
			"  ".join(mods), Endless.gear_price(e), Endless.gear_left(e) > 0, func(): _act(func(): Endless.buy_gear(e)))
		var icon := GearIcon.new()
		icon.custom_minimum_size = Vector2(48, 48)
		icon.set_gear(e)
		row.add_child(icon)
		row.move_child(icon, 0)
		box.add_child(row)
	box.add_child(_label(Terms.t("endless_shop_materials"), 15, UITheme.TEXT_DIM))
	for i in Endless.SHOP_MATERIALS.size():
		var item: Dictionary = Endless.SHOP_MATERIALS[i]
		box.add_child(_shop_row(Daily.item_text([item.id, item.amount]), "", int(item.price), true,
			func(): _act(func(): Endless.buy_material(i))))
	return panel

func _shop_row(name: String, note: String, price: int, available: bool, buy: Callable) -> HBoxContainer:
	var row := _hbox(10)
	var text := _vbox(0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(_label(name, 16, Color.WHITE))
	if not note.is_empty():
		text.add_child(_label(note, 13, UITheme.TEXT_DIM))
	row.add_child(text)
	var b := _button(Terms.t("endless_shop_buy", {"price": price}) if available else Terms.t("endless_shop_sold_out"),
		buy, available, Vector2(150, 40))
	b.disabled = not available or Endless.tokens() < price
	row.add_child(b)
	return row

# ───────── During a run ─────────

func _run_view() -> Control:
	var row := _hbox(12)
	row.add_child(_squad_panel())
	var right := _panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var p := Endless.pending()
	if p.is_empty():
		right.add_child(_map_view())
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		right.add_child(scroll)
		var holder := _vbox(10)
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(holder)
		match String(p.kind):
			"fight":
				_fight_panel(holder, p)
			"drinks":
				_drink_panel(holder, p, false)
			"hangover":
				_drink_panel(holder, p, true)
			"rest":
				_rest_panel(holder)
			"bar":
				_bar_panel(holder, p)
			"event":
				_event_panel(holder, p)
			"result":
				_result_panel(holder, p)
			"night_end":
				_night_end_panel(holder)
	return row

func _squad_panel() -> Control:
	var panel := _panel(UITheme.CYAN, 10)
	panel.custom_minimum_size.x = 300
	var box := _vbox(6)
	panel.add_child(box)
	var r := Endless.run()
	box.add_child(_label(Terms.t("endless_tips_have", {"tips": int(r.tips)}), 18, UITheme.GOLD))
	var lineup_open: bool = Endless.pending().is_empty() or Endless.pending().get("kind") == "fight"
	box.add_child(_label(Terms.t("endless_squad_hint" if lineup_open else "endless_squad_title"), 12, UITheme.TEXT_DIM, true))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := _vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var members := Endless.members()
	members.sort_custom(func(a, b): return a.vanguard and not b.vanguard)
	for m in members:
		list.add_child(_member_row(m, lineup_open))
	# Drinks and Hangovers
	var drinks := HFlowContainer.new()
	drinks.add_theme_constant_override("h_separation", 4)
	drinks.add_theme_constant_override("v_separation", 4)
	for d in Endless.taken_drinks():
		var chip := UITheme.tag(d.display_name, HANGOVER_COLOR if d.hangover else RARITY_COLORS[d.rarity])
		chip.tooltip_text = d.description
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		drinks.add_child(chip)
	if drinks.get_child_count() > 0:
		box.add_child(_label(Terms.t("endless_drinks_title"), 13, UITheme.TEXT_DIM))
		box.add_child(drinks)
	box.add_child(_button(Terms.t("endless_give_up"), _confirm_give_up, false, Vector2(0, 32)))
	return panel

func _member_row(m: Dictionary, lineup_open: bool) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 62)
	b.toggle_mode = true
	b.button_pressed = m.fielded
	b.disabled = not lineup_open or m.ko
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = Terms.t("endless_member_tip")
	b.pressed.connect(func(): _act(func(): Endless.toggle_fielded(int(m.index))))
	var row := _hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -6
	row.offset_top = 3
	row.offset_bottom = -3
	b.add_child(row)
	var art := CharArt.new()
	art.custom_minimum_size = Vector2(44, 54)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_character(m.data)
	if m.ko:
		art.modulate = Color(0.4, 0.4, 0.45)
	row.add_child(art)
	var info := _vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var name := _label("%s  Lv.%d%s" % [m.data.display_name, int(m.level), "  +" if m.train else ""], 13, Color.WHITE)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(name)
	var bar := HpStrip.new()
	bar.share = 0.0 if m.ko else float(m.hp)
	bar.custom_minimum_size = Vector2(0, 8)
	info.add_child(bar)
	var status := "endless_status_ko" if m.ko else ("endless_status_front" if m.fielded and m.vanguard
		else ("endless_status_back" if m.fielded else "endless_status_bench"))
	var color := HANGOVER_COLOR if m.ko else (UITheme.CYAN if m.fielded else UITheme.TEXT_DIM)
	info.add_child(_label(Terms.t(status) + ("" if m.ko else "  %d%%" % roundi(float(m.hp) * 100)), 11, color))
	return b

func _confirm_give_up() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = Terms.t("endless_give_up_confirm", {"tips": int(Endless.run().tips)})
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(420, 0)
	dialog.confirmed.connect(func(): _act(func(): Endless.give_up()))
	add_child(dialog)
	dialog.popup_centered()

# ───────── The map ─────────

func _map_view() -> Control:
	var box := _vbox(6)
	box.add_child(_label(Terms.t("endless_map_hint"), 14, UITheme.TEXT_DIM))
	var map := NightMap.new()
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(360, 420)
	map.setup(Endless.map_nodes(), Endless.run().get("path", []), Endless.reachable(), String(Endless.run().node))
	map.node_picked.connect(func(id: String): _act(func(): Endless.choose_node(id)))
	box.add_child(map)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 6)
	for type in ["battle", "elite", "event", "rest", "bar", "boss"]:
		legend.add_child(UITheme.tag("%s  %s" % [NightMap.SYMBOLS[type], Terms.t("endless_node_" + type)], NODE_COLORS[type]))
	box.add_child(legend)
	return box

# ───────── Choices ─────────

func _title(holder: Control, text: String, color: Color, sub: String = "") -> void:
	var t := _label(text, 26, color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(t)
	if not sub.is_empty():
		var s := _label(sub, 15, UITheme.TEXT, true)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(s)

func _fight_panel(holder: Control, p: Dictionary) -> void:
	var kind := String(p.fight)
	var stage := Endless.current_stage()
	_title(holder, Terms.t("endless_fight_" + kind), NODE_COLORS.get(kind, Color.WHITE), stage.display_name if stage else "")
	if stage:
		holder.add_child(_label(Terms.t("endless_enemy_level", {"lv": stage.enemy_level, "waves": stage.wave_count()}), 14, UITheme.TEXT_DIM))
		var enemies := HFlowContainer.new()
		enemies.add_theme_constant_override("h_separation", 6)
		var seen := []
		for w in stage.waves:
			for c in w.enemy_vanguard + w.enemy_rearguard:
				if c and not seen.has(c):
					seen.append(c)
					var art := CharArt.new()
					art.custom_minimum_size = Vector2(54, 66)
					art.set_character(c)
					art.tooltip_text = c.display_name
					enemies.add_child(art)
		holder.add_child(enemies)
	var fielded := Endless.members().filter(func(m): return m.fielded and not m.ko).size()
	holder.add_child(_label(Terms.t("endless_fight_hint", {"count": fielded}), 14, UITheme.CYAN, true))
	var go := _button(Terms.t("endless_fight_go"), fight_pressed.emit, true, Vector2(0, 56))
	go.add_theme_font_size_override("font_size", 22)
	go.disabled = fielded == 0
	holder.add_child(go)

func _drink_panel(holder: Control, p: Dictionary, hangover: bool) -> void:
	if hangover:
		_title(holder, Terms.t("endless_hangover_title"), HANGOVER_COLOR, Terms.t("endless_hangover_sub"))
	else:
		_title(holder, Terms.t("endless_drinks_pick"), UITheme.GOLD, Terms.t("endless_drinks_sub"))
	var cards := HFlowContainer.new()
	cards.alignment = FlowContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	holder.add_child(cards)
	for id in p.options:
		var d: DrinkData = Endless.drinks.get(StringName(id))
		if d == null:
			continue
		var color: Color = HANGOVER_COLOR if hangover else RARITY_COLORS[d.rarity]
		var card := _panel(color, 12)
		card.custom_minimum_size = Vector2(210, 190)
		var box := _vbox(6)
		card.add_child(box)
		if hangover:
			box.add_child(UITheme.tag(Terms.t("endless_severity_%d" % d.severity), color))
		else:
			box.add_child(UITheme.tag(Terms.t("endless_rarity_%d" % d.rarity), color))
		box.add_child(_label(d.display_name, 19, Color.WHITE, true))
		var text := _label(d.description, 14, UITheme.TEXT, true)
		text.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(text)
		if not hangover and d.rarity != DrinkData.Rarity.COMMON:
			box.add_child(_label(Terms.t("endless_hangover_warn_%d" % d.rarity), 12, HANGOVER_COLOR, true))
		box.add_child(_button(Terms.t("endless_take"), _take.bind(String(id), hangover), true))
		cards.add_child(card)
	if not hangover:
		holder.add_child(_button(Terms.t("endless_skip"), func(): _act(func(): Endless.pick_drink("")), false))

func _take(id: String, hangover: bool) -> void:
	if hangover:
		Endless.pick_hangover(id)
	else:
		Endless.pick_drink(id)
	refresh()

func _rest_panel(holder: Control) -> void:
	_title(holder, Terms.t("endless_rest_title"), NODE_COLORS.rest, Terms.t("endless_rest_sub"))
	var heal := roundi(Endless.rest_heal_share() * 100)
	var heal_button := _button(Terms.t("endless_rest_heal", {"pct": heal}), func(): _act(func(): Endless.rest("heal")), true, Vector2(0, 46))
	heal_button.disabled = heal <= 0
	holder.add_child(heal_button)
	var members := Endless.members()
	var ko := members.filter(func(m): return m.ko)
	if not ko.is_empty():
		holder.add_child(_label(Terms.t("endless_rest_revive", {"pct": roundi(Endless.REVIVE_HP * 100)}), 15, UITheme.TEXT_DIM))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		for m in ko:
			flow.add_child(_button(m.data.display_name, func(): _act(func(): Endless.rest("revive", int(m.index)))))
		holder.add_child(flow)
	var trainable := members.filter(func(m): return not m.ko and not m.train)
	if not trainable.is_empty():
		holder.add_child(_label(Terms.t("endless_rest_train", {"pct": roundi((Endless.TRAIN_MULT - 1.0) * 100)}), 15, UITheme.TEXT_DIM))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		for m in trainable:
			flow.add_child(_button(m.data.display_name, func(): _act(func(): Endless.rest("train", int(m.index)))))
		holder.add_child(flow)

func _bar_panel(holder: Control, p: Dictionary) -> void:
	_title(holder, Terms.t("endless_bar_title"), NODE_COLORS.bar, Terms.t("endless_bar_sub", {"tips": int(Endless.run().tips)}))
	for i in p.items.size():
		var item: Dictionary = p.items[i]
		var row := _hbox(10)
		var name := ""
		var note := ""
		var color := Color.WHITE
		match String(item.type):
			"hire":
				var c := GameState.get_character(int(item.uid))
				if c == null:
					continue
				var art := CharArt.new()
				art.custom_minimum_size = Vector2(44, 54)
				art.set_character(c)
				row.add_child(art)
				name = Terms.t("endless_bar_hire", {"name": c.display_name})
				note = "%s %s · Lv.%d" % [Terms.rarity_name(c.rarity), Terms.class_label(c.char_class), int(GameState.get_owned(int(item.uid)).level)]
				color = UITheme.CYAN
			"drink":
				var d: DrinkData = Endless.drinks.get(StringName(item.id))
				name = d.display_name
				note = d.description
				color = RARITY_COLORS[d.rarity]
			"heal":
				name = Terms.t("endless_bar_heal", {"pct": roundi(float(Endless.PRICES.heal_pct) * 100)})
			"revive":
				name = Terms.t("endless_bar_revive", {"pct": roundi(Endless.REVIVE_HP * 100)})
			"cure":
				var h: DrinkData = Endless.drinks.get(StringName(item.id))
				name = Terms.t("endless_bar_cure", {"name": h.display_name})
				note = h.description
				color = HANGOVER_COLOR
		var text := _vbox(0)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(_label(name, 16, color))
		if not note.is_empty():
			text.add_child(_label(note, 12, UITheme.TEXT_DIM, true))
		row.add_child(text)
		var sold: bool = item.get("sold", false)
		var b := _button(Terms.t("endless_bar_sold") if sold else Terms.t("endless_bar_buy", {"price": int(item.price)}),
			func(): _act(func(): Endless.buy(i)), false, Vector2(130, 38))
		b.disabled = not Endless.can_buy(i)
		row.add_child(b)
		holder.add_child(row)
	holder.add_child(_button(Terms.t("endless_bar_leave"), func(): _act(Endless.leave_bar), true, Vector2(0, 46)))

func _event_panel(holder: Control, p: Dictionary) -> void:
	var ev := Endless.event_data(String(p.id))
	if ev == null:
		return
	_title(holder, ev.title, NODE_COLORS.event, ev.text)
	for i in ev.choices.size():
		var choice: Dictionary = ev.choices[i]
		var text := String(choice.text)
		if int(choice.get("cost_tips", 0)) > 0:
			text += "  " + Terms.t("endless_event_cost", {"tips": int(choice.cost_tips)})
		var b := _button(text, func(): _act(func(): Endless.choose_event(i)), i == 0, Vector2(0, 46))
		b.disabled = not Endless.can_choose(ev, i)
		holder.add_child(b)

func _result_panel(holder: Control, p: Dictionary) -> void:
	_title(holder, String(p.get("title", Terms.t("endless_result_title"))), NODE_COLORS.event, String(p.get("text", "")))
	for line in p.get("effects", []):
		var l := _label(line, 15, UITheme.GOLD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(l)
	holder.add_child(_button(Terms.t("endless_ok"), func(): _act(Endless.dismiss_result), true, Vector2(0, 46)))

func _night_end_panel(holder: Control) -> void:
	var r := Endless.run()
	_title(holder, Terms.t("endless_night_won", {"night": Endless.night_name()}), UITheme.GOLD,
		Terms.t("endless_night_choice", {"tips": int(r.tips), "next": Endless.night_name(int(r.night) + 1)}))
	holder.add_child(_button(Terms.t("endless_night_go", {"next": Endless.night_name(int(r.night) + 1)}),
		func(): _act(func(): Endless.night_end(true)), true, Vector2(0, 52)))
	holder.add_child(_button(Terms.t("endless_night_cash"), func(): _act(func(): Endless.night_end(false)), false, Vector2(0, 46)))

## A thin HP bar
class HpStrip extends Control:
	var share := 1.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.5))
		var color := Color("#4ade80") if share > 0.5 else (Color("#fbbf24") if share > 0.25 else Color("#ef4444"))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(share, 0.0, 1.0), size.y)), color)

## A Night's map: floors bottom to top, the boss on top. Walked nodes are lit, the reachable ones pulse and can be
## clicked, the current one has a white ring. Hover a node for its name.
class NightMap extends Control:
	signal node_picked(id: String)

	const SYMBOLS := {"battle": "x", "elite": "!", "event": "?", "rest": "Z", "bar": "$", "boss": "B"}
	const RADIUS := 13.0
	const BOSS_RADIUS := 22.0

	var _nodes := {}
	var _path: Array = []
	var _reachable: Array = []
	var _current := ""
	var _time := 0.0

	func setup(nodes: Dictionary, path: Array, reachable: Array, current: String) -> void:
		_nodes = nodes
		_path = path
		_reachable = reachable
		_current = current
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _process(delta: float) -> void:
		_time += delta
		if not _reachable.is_empty():
			queue_redraw()

	func _pos(id: String) -> Vector2:
		var n: Dictionary = _nodes[id]
		var margin := Vector2(30, 30)
		var area := size - margin * 2.0
		var x := margin.x + area.x * float(n.col) / float(Endless.COLUMNS - 1)
		var y := size.y - margin.y - area.y * float(n.floor) / float(Endless.FLOORS - 1)
		return Vector2(x, y)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		# Edges: walked ones bright, the rest dim
		for id in _nodes:
			for n in _nodes[id].next:
				var walked := _path.has(id) and _path.has(n) and _path.find(n) == _path.find(id) + 1
				draw_line(_pos(id), _pos(n), Color(1, 1, 1, 0.75) if walked else Color(1, 1, 1, 0.14), 3.0 if walked else 1.5, true)
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		for id in _nodes:
			var n: Dictionary = _nodes[id]
			var p := _pos(id)
			var type := String(n.type)
			var color: Color = EndlessScreen.NODE_COLORS.get(type, Color.WHITE)
			var r := BOSS_RADIUS if type == "boss" else RADIUS
			var walked := _path.has(id)
			var open := _reachable.has(id)
			if open:
				draw_circle(p, r + 5.0 + 3.0 * pulse, Color(color, 0.25 + 0.25 * pulse))
			draw_circle(p, r, color.darkened(0.55) if not walked and not open else color)
			draw_arc(p, r, 0, TAU, 32, Color(1, 1, 1, 0.9) if id == _current else Color(0, 0, 0, 0.6), 2.5 if id == _current else 1.5, true)
			var symbol: String = SYMBOLS.get(type, "?")
			var font_size := 18 if type == "boss" else 14
			var text_size := font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			draw_string(font, p + Vector2(-text_size.x / 2.0, text_size.y / 3.0), symbol, HORIZONTAL_ALIGNMENT_CENTER, -1,
				font_size, Color.WHITE if walked or open else Color(1, 1, 1, 0.55))

	func _hit(at: Vector2) -> String:
		for id in _nodes:
			var r := BOSS_RADIUS if _nodes[id].type == "boss" else RADIUS
			if _pos(id).distance_to(at) <= r + 6.0:
				return id
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := _hit(event.position)
			if _reachable.has(id):
				accept_event()
				node_picked.emit(id)

	func _get_tooltip(at: Vector2) -> String:
		var id := _hit(at)
		if id.is_empty():
			return ""
		return Terms.t("endless_node_" + String(_nodes[id].type))
