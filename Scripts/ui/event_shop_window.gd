class_name EventShopWindow
extends AcceptDialog
## The event shop (EventShop, EventData.shop): the event's currency balance at the top, then a card per item with
## its icon, what it gives, the price, how many are left, and Buy / Buy Max. Limited items (stock 1) get a gold
## frame and a LIMITED tag. Rebuilds after every purchase.

var _event: EventData
var _balance: CurrencyChip
var _grid: GridContainer
var _got: Label

func _init(event: EventData) -> void:
	_event = event
	title = Terms.t("shop_title", {"event": event.display_name})
	ok_button_text = Terms.t("beginner_close")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = event.currency_color.darkened(0.25)
	style.skew = Vector2(0.3, 0)
	style.content_margin_left = 22
	style.content_margin_right = 26
	style.shadow_color = Color(event.currency_color, 0.4)
	style.shadow_size = 10
	plate.add_theme_stylebox_override("panel", style)
	plate.add_child(_label(Terms.t("shop_banner"), 22, Color.WHITE))
	top.add_child(plate)
	var hint := _label(Terms.t("shop_hint", {"currency": event.currency_name}), 14, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(hint)
	_balance = CurrencyChip.new("event", event.currency_name, event.currency_color)
	_balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_balance)
	_got = _label("", 15, UITheme.GOLD)
	_got.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_got)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	box.add_child(_grid)
	_refresh()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _refresh() -> void:
	_balance.set_amount(EventShop.currency(_event))
	for child in _grid.get_children():
		child.queue_free()
	for i in _event.shop.size():
		_grid.add_child(_card(i))

func _card(i: int) -> Control:
	var item: EventShopItem = _event.shop[i]
	var limited := item.stock == 1
	var left := EventShop.left(_event, i)
	var sold_out := left == 0
	var panel := PanelContainer.new()
	var edge: Color = UITheme.GOLD if limited else Color(CurrencyChip.KIND_COLORS.get(item.kind, UITheme.CYAN), 0.6)
	var style := UITheme.box(Color(0.05, 0.07, 0.12, 0.95), edge, 2 if limited else 1, 10, 10)
	if limited:
		style.shadow_color = Color(UITheme.GOLD, 0.35)
		style.shadow_size = 10
	panel.add_theme_stylebox_override("panel", style)
	if sold_out:
		panel.modulate.a = 0.5
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := Icon.new(item.kind)
	icon.custom_minimum_size = Vector2(58, 58)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	if limited:
		info.add_child(UITheme.tag(Terms.t("shop_limited"), UITheme.GOLD, true))
	var name_label := _label(Daily.item_text(item.reward()[0]), 16, Color.WHITE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 150
	info.add_child(name_label)
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 4)
	info.add_child(price)
	var coin := Icon.new("event", _event.currency_color)
	coin.custom_minimum_size = Vector2(18, 18)
	price.add_child(coin)
	var affordable := EventShop.currency(_event) >= item.cost
	price.add_child(_label(Terms.number(item.cost), 15, _event.currency_color.lightened(0.3) if affordable else Color("#fca5a5")))
	info.add_child(_label(Terms.t("shop_sold_out") if sold_out else (Terms.t("shop_no_limit") if left < 0 else
		Terms.t("shop_left", {"left": left, "stock": item.stock})), 13, UITheme.TEXT_DIM))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	info.add_child(buttons)
	var can := EventShop.max_buyable(_event, i)
	var buy := Button.new()
	buy.text = Terms.t("shop_buy")
	buy.disabled = can <= 0
	if not buy.disabled:
		buy.theme_type_variation = &"PrimaryButton"
	buy.set_meta("silent", true)  # the purchase plays its own sound
	buy.pressed.connect(_buy.bind(i, 1))
	buttons.add_child(buy)
	if item.stock != 1:
		var most := Button.new()
		most.text = Terms.t("shop_buy_max", {"count": can})
		most.disabled = can <= 1
		most.set_meta("silent", true)
		most.pressed.connect(func(): _buy(i, EventShop.max_buyable(_event, i)))
		buttons.add_child(most)
	return panel

func _buy(i: int, count: int) -> void:
	var got := EventShop.buy(_event, i, count)
	if got.is_empty():
		return
	Sound.play("claim")
	_got.text = Terms.t("daily_got", {"reward": Daily.reward_text(got)})
	_refresh()

## An item's icon (CurrencyChip.draw_kind)
class Icon extends Control:
	var _kind := ""
	var _tint := Color(0, 0, 0, 0)

	func _init(kind: String, tint: Color = Color(0, 0, 0, 0)) -> void:
		_kind = kind
		_tint = tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		CurrencyChip.draw_kind(self, size * 0.5, minf(size.x, size.y) * 0.5, _kind, _tint)
