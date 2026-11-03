class_name GachaTab
extends VBoxContainer
## Recruit screen: banner selector and balance on top, then the banner itself (GachaBanner: the Pick Up
## friends' art, the pool's title and rates, with the pull buttons and their costs at its bottom right).
## Results play as a full-screen summon animation (GachaSummon).

var _pool: GachaPool
var _pool_buttons: Array[Button] = []
var _balance_label: Label
var _banner: GachaBanner
var _pull_buttons: Dictionary = {}  # count -> Button
var _message: Label

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_top_bar()
	_banner = GachaBanner.new()
	add_child(_banner)
	_build_pull_buttons()
	GameState.money_changed.connect(func(_value): _refresh_money())
	GameState.credit_cards_changed.connect(func(_value): _refresh_money())
	if not DB.pools.is_empty():
		_select_pool(0)

func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	var group := ButtonGroup.new()
	for i in DB.pools.size():
		var button := Button.new()
		button.text = DB.pools[i].display_name
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_select_pool.bind(i))
		bar.add_child(button)
		_pool_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var history := Button.new()
	history.text = Terms.t("gacha_history")
	history.pressed.connect(_open_history)
	bar.add_child(history)
	_balance_label = Label.new()
	_balance_label.add_theme_font_size_override("font_size", 18)
	bar.add_child(_balance_label)

func _build_pull_buttons() -> void:
	for count in [1, 10]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(210, 62)
		button.add_theme_font_size_override("font_size", 17)
		button.theme_type_variation = &"PrimaryButton"
		button.pressed.connect(_on_pull.bind(count))
		_banner.button_row.add_child(button)
		_pull_buttons[count] = button
	_message = _centered_label("", 15)
	add_child(_message)

func _centered_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _select_pool(index: int) -> void:
	_pool = DB.pools[index]
	_pool_buttons[index].button_pressed = true
	_banner.set_pool(_pool, Terms.t("gacha_rates", {"rates": _rate_text(_pool)}))
	_message.text = ""
	_refresh_money()

func _refresh_money() -> void:
	_balance_label.text = Terms.t("gacha_balance", {"amount": GameState.get_money(), "cards": GameState.get_credit_cards()})
	if _pool == null:
		return
	for count in _pull_buttons:
		var cost := Gacha.money_cost(_pool, count)
		var cards := Gacha.card_cost(count)
		var button: Button = _pull_buttons[count]
		button.text = "%s\n%s" % [Terms.t("gacha_pull", {"count": count}),
			Terms.t("gacha_cost", {"cost": cost, "cards": cards, "card_word": Terms.credit_card_word(cards)})]
		button.disabled = not GameState.can_afford_pull(cost, cards)
	if _pool.pity_threshold > 0:
		_banner.pity_label.text = Terms.t("gacha_pity", {"count": _pool.pity_threshold - GameState.get_pity(_pool.id)})
	else:
		_banner.pity_label.text = ""
	_banner.pity_bar.set_progress(GameState.get_pity(_pool.id), _pool.pity_threshold)

## The last PULL_HISTORY_MAX pulls, newest first: rarity chip, portrait, name, pool and how long ago
func _open_history() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("gacha_history_title", {"count": GameState.PULL_HISTORY_MAX})
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, minf(get_viewport_rect().size.y - 200.0, 460.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var history := GameState.get_pull_history()
	if history.is_empty():
		list.add_child(_centered_label(Terms.t("gacha_history_empty"), 16))
	var now := int(Time.get_unix_time_from_system())
	for entry in history:
		var c: CharacterData = DB.characters.get(StringName(entry.char_id))
		var rarity := int(entry.rarity)
		var color: Color = GachaSummon.COLORS.get(rarity, Color.WHITE)
		var row := PanelContainer.new()
		var style := UITheme.box(Color(color, 0.12 if rarity >= CharacterData.Rarity.SR else 0.05), Color(color, 0.5), 1, 6, 4)
		row.add_theme_stylebox_override("panel", style)
		list.add_child(row)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		row.add_child(line)
		var chip := UITheme.tag(Terms.rarity_name(rarity), color)
		chip.custom_minimum_size.x = 48
		line.add_child(chip)
		var art := CharArt.new()
		art.custom_minimum_size = Vector2(32, 40)
		if c:
			art.set_character(c)
		line.add_child(art)
		var name_label := Label.new()
		name_label.text = c.display_name if c else String(entry.char_id)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", color.lightened(0.2) if rarity >= CharacterData.Rarity.SR else UITheme.TEXT)
		line.add_child(name_label)
		var pool := _pool_name(StringName(entry.pool))
		var when := Label.new()
		when.text = "%s  ·  %s" % [pool, _ago(now - int(entry.time))]
		when.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		when.add_theme_font_size_override("font_size", 13)
		line.add_child(when)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _pool_name(id: StringName) -> String:
	for p in DB.pools:
		if p.id == id:
			return p.display_name
	return String(id)

## "just now", "5m ago", "3h ago", "2d ago"
func _ago(seconds: int) -> String:
	if seconds < 60:
		return Terms.t("time_just_now")
	if seconds < 3600:
		return Terms.t("time_ago", {"time": "%dm" % (seconds / 60)})
	if seconds < 86400:
		return Terms.t("time_ago", {"time": "%dh" % (seconds / 3600)})
	return Terms.t("time_ago", {"time": "%dd" % (seconds / 86400)})

func _rate_text(pool: GachaPool) -> String:
	var weights := {}
	for entry in pool.entries:
		if entry.character and entry.character.enabled:
			weights[entry.character.rarity] = pool.weight_for(entry.character.rarity)
	var total := 0
	for w in weights.values():
		total += w
	if total == 0:
		return Terms.t("gacha_no_characters")
	var parts: PackedStringArray = []
	for rarity in [CharacterData.Rarity.SSR, CharacterData.Rarity.SR, CharacterData.Rarity.R]:
		if weights.get(rarity, 0) > 0:
			parts.append("%s %.1f%%" % [Terms.rarity_name(rarity), weights[rarity] * 100.0 / total])
	return " · ".join(parts)

func _on_pull(count: int) -> void:
	if GameState.get_credit_cards() < Gacha.card_cost(count):
		_message.text = Terms.t("gacha_no_cards", {"amount": Gacha.card_cost(count),
			"bonus": "%d %s" % [GameState.FIRST_CLEAR_CREDIT_CARDS, Terms.credit_card_word(GameState.FIRST_CLEAR_CREDIT_CARDS)]})
		return
	if GameState.get_money() < Gacha.money_cost(_pool, count):
		_message.text = Terms.t("gacha_no_money", {"amount": Gacha.money_cost(_pool, count)})
		return
	var results := Gacha.pull(_pool, count)
	if results.is_empty():
		_message.text = Terms.t("gacha_empty_pool")
		return
	_message.text = ""
	_refresh_money()
	_show_results(results)

## The full-screen summon animation (Scripts/ui/gacha_summon.gd), one reveal per result
func _show_results(results: Array[Dictionary]) -> void:
	var notes: Array[String] = []
	for r in results:
		notes.append(_result_text(r))
	var summon := GachaSummon.new()
	add_child(summon)
	summon.open(results, notes)

func _result_text(r: Dictionary) -> String:
	match r.result:
		"new":
			return Terms.t("new_badge")
		"ascend":
			return Terms.t("gacha_ascend", {"rank": r.rank, "max": GameState.MAX_ASCENSION})
		_:
			return Terms.t("gacha_overflow", {"amount": r.money})
