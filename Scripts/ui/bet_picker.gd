class_name BetPicker
extends HBoxContainer
## Bet stepper shared by the Casino games: -100 -10 [Bet: N Money] +10 +100. Each game adds its own start button after it.

signal changed(bet: int)

const BET_MIN := 10
const BET_MAX := 1000
const STEPS := [-100, -10, 10, 100]

var bet := 50
var _label: Label

func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	for step in STEPS:
		if step > 0 and _label == null:
			_label = Label.new()
			_label.custom_minimum_size.x = 170
			_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_label.add_theme_font_size_override("font_size", 20)
			add_child(_label)
		var b := Button.new()
		b.text = "%+d" % step
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_change.bind(step))
		add_child(b)
	_change(0)

func _change(step: int) -> void:
	bet = clampi(bet + step, BET_MIN, BET_MAX)
	_label.text = Terms.t("casino_bet", {"amount": bet})
	changed.emit(bet)
