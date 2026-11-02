class_name GachaTab
extends VBoxContainer
## Recruit screen: banner selector and balance on top, then the banner itself (GachaBanner: the Pick Up
## friends' art, the pool's title and rates, with the pull buttons and their costs at its bottom right).
## Results open in a popup.

const FLIP_CARD_SIZE := Vector2(156, 300)
const FLIP_HALF_SEC := 0.14  # each half of a card turn
const FLIP_STAGGER_SEC := 0.2  # pause before each card turns

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

## FGO-style reveal: every result starts face down. One by one, each card squashes to zero width,
## swaps to the character, and stretches back; SR and SSR cards then flash in their rarity colour.
## "Reveal all" turns the rest over at once. Tweens belong to the dialog, so closing it stops them.
func _show_results(results: Array[Dictionary]) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Terms.t("gacha_result", {"count": results.size(), "name": _pool.display_name})
	dialog.add_button(Terms.t("gacha_reveal_all"), true, "reveal")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := ceili(results.size() / 5.0)
	scroll.custom_minimum_size = Vector2(5 * (FLIP_CARD_SIZE.x + 10), mini(rows, 2) * (FLIP_CARD_SIZE.y + 10))
	dialog.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	scroll.add_child(flow)

	var cards: Array[Dictionary] = []
	for r in results:
		var holder := Control.new()
		holder.custom_minimum_size = FLIP_CARD_SIZE
		holder.pivot_offset = FLIP_CARD_SIZE / 2
		var back := _card_back()
		holder.add_child(back)
		var front := CharCard.new()
		front.set_character(r.character, "%s\n%s" % [_result_text(r), _stats_text(r.uid)])
		front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		front.hide()
		holder.add_child(front)
		flow.add_child(holder)
		cards.append({"holder": holder, "back": back, "front": front, "rarity": r.rarity})

	var tween := dialog.create_tween()
	for card in cards:
		tween.tween_interval(FLIP_STAGGER_SEC)
		tween.tween_property(card.holder, "scale:x", 0.0, FLIP_HALF_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_callback(_turn_face_up.bind(card))
		tween.tween_property(card.holder, "scale:x", 1.0, FLIP_HALF_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if card.rarity >= CharacterData.Rarity.SR:
			var glow: Color = CharArt.RARITY_COLORS[card.rarity].lightened(0.4) * 1.6
			tween.tween_property(card.front, "modulate", glow, FLIP_HALF_SEC)
			tween.tween_property(card.front, "modulate", Color.WHITE, FLIP_HALF_SEC * 2)
	dialog.custom_action.connect(func(_action): _reveal_all(tween, cards))
	dialog.visibility_changed.connect(func(): _free_if_hidden(dialog))
	add_child(dialog)
	dialog.popup_centered()

func _turn_face_up(card: Dictionary) -> void:
	card.back.hide()
	card.front.show()

func _reveal_all(tween: Tween, cards: Array[Dictionary]) -> void:
	tween.kill()
	for card in cards:
		_turn_face_up(card)
		card.holder.scale = Vector2.ONE
		card.front.modulate = Color.WHITE

## Card back in the banner's colour with a gold frame and the game's initials
func _card_back() -> Control:
	var back := PanelContainer.new()
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = _pool.theme_color.darkened(0.55)
	style.border_color = Color("#d4af37")
	style.set_border_width_all(4)
	style.set_corner_radius_all(10)
	back.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	back.add_child(box)
	var initials := PackedStringArray()
	for word in Terms.term("game_title").split(" ", false):
		initials.append(word.left(1).to_upper())
	var mark := _centered_label("".join(initials), 56)
	mark.add_theme_color_override("font_color", Color("#d4af37"))
	box.add_child(mark)
	var title := _centered_label(Terms.term("game_title"), 13)
	title.add_theme_color_override("font_color", Color("#e5d4a1"))
	box.add_child(title)
	return back

## The friend's current stats (with level and Ascension), shown on the revealed card
func _stats_text(uid: int) -> String:
	var stats := GameState.get_unit_stats(uid)
	var parts: PackedStringArray = []
	for stat in ["hp", "attack", "defense", "speed"]:
		parts.append("%s %d" % [Terms.stat_short(stat), stats[stat]])
	return "%s\n%s" % ["  ".join(parts.slice(0, 2)), "  ".join(parts.slice(2, 4))]

func _result_text(r: Dictionary) -> String:
	match r.result:
		"new":
			return Terms.t("new_badge")
		"ascend":
			return Terms.t("gacha_ascend", {"rank": r.rank, "max": GameState.MAX_ASCENSION})
		_:
			return Terms.t("gacha_overflow", {"amount": r.money})

func _free_if_hidden(dialog: Window) -> void:
	if not dialog.visible:
		dialog.queue_free()
