class_name AccountBadge
extends Control
## The Home header's account badge: the level number inside a ring that fills with account EXP, the player's name
## beside it and "Lv. 12 · 340 / 425 EXP" under the name. Main calls set_values() whenever the account changes;
## the tooltip (team cost limit) is set by Main too.

var level := 1
var share := 0.0  # EXP toward the next level, 0-1 (1 at max level)
var player := ""
var detail := ""
var _shown := 0.0  # the ring's drawn share, eased toward `share`

func _init() -> void:
	custom_minimum_size = Vector2(170, 46)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_values(lv: int, exp_share: float, name_text: String, detail_text: String) -> void:
	level = lv
	share = clampf(exp_share, 0.0, 1.0)
	player = name_text
	detail = detail_text
	var t := create_tween() if is_inside_tree() else null
	if t:
		t.tween_method(_set_shown, _shown, share, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		_shown = share
	queue_redraw()

func _set_shown(v: float) -> void:
	_shown = v
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	var r := size.y / 2.0 - 2.0
	var c := Vector2(r + 2.0, size.y / 2.0)
	# Ring: dark track, the EXP arc in cyan from the top, a glow behind the disc
	UITheme.draw_glow(self, c, r + 6.0, Color(UITheme.CYAN, 0.2), 4)
	draw_circle(c, r, Color(0.03, 0.05, 0.1, 0.92))
	draw_arc(c, r - 2.5, 0, TAU, 48, Color(1, 1, 1, 0.12), 4.0, true)
	if _shown > 0.0:
		draw_arc(c, r - 2.5, -PI / 2.0, -PI / 2.0 + TAU * _shown, 48, UITheme.CYAN_BRIGHT, 4.0, true)
	var lv := str(level)
	var fs := 17 if lv.length() < 3 else 14
	var w := font.get_string_size(lv, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w / 2.0, fs * 0.36), lv, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# Name and level line
	var x := c.x + r + 10.0
	var room := size.x - x
	draw_string(font, Vector2(x, size.y / 2.0 - 3.0), player, HORIZONTAL_ALIGNMENT_LEFT, room, 16, Color.WHITE)
	draw_string(font, Vector2(x, size.y / 2.0 + 14.0), detail, HORIZONTAL_ALIGNMENT_LEFT, room, 12, UITheme.CYAN)
