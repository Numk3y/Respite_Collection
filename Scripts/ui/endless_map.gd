class_name AfterHoursMap
extends Control
## The Night's map for EndlessScreen: a tall street that scrolls, floor 1 at the bottom and the boss on top.
## Paths are soft curves; the walked route glows with light flowing along it, the ways forward pulse in their
## node's colour. The squad's leader stands on the current node as a little portrait pin, and the view glides to
## it when the map opens. Tap a glowing node to see what's there in the info card, then GO (or tap it again).

signal go(id: String)

const FLOOR_GAP := 80.0
const MARGIN_Y := 80.0  # above the boss
const BOTTOM := 200.0  # below floor 1: room for START and the info card
const SIDE := 64.0  # room each side of the node band (the floor numbers sit on the left)
const MAX_SPREAD := 640.0  # widest the seven columns spread
const RADIUS := 21.0
const BOSS_RADIUS := 36.0

var _scroll: ScrollContainer
var _canvas: MapCanvas
var _info: PanelContainer
var _info_box: VBoxContainer
var _selected := ""
var _reachable: Array = []
var _nodes := {}
var _first_layout := true
var animate := true  # glide to the squad's floor when the map opens (off: jump straight there)

func _init() -> void:
	clip_contents = true
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)
	_canvas = MapCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.picked.connect(_on_pick)
	_scroll.add_child(_canvas)
	# Info card for the selected node, floating at the bottom
	_info = AHKit.panel(AHKit.ACCENT, 12, 0.94)
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.offset_bottom = -12
	_info.custom_minimum_size = Vector2(440, 0)
	add_child(_info)
	_info_box = AHKit.vbox(6)
	_info.add_child(_info_box)
	resized.connect(_on_resized)

func setup(nodes: Dictionary, path: Array, reachable: Array, current: String, leader: CharacterData) -> void:
	_nodes = nodes
	_reachable = reachable
	_canvas.nodes = nodes
	_canvas.path = path
	_canvas.reachable = reachable
	_canvas.current = current
	_canvas.set_leader(leader)
	_canvas.custom_minimum_size.y = MARGIN_Y + BOTTOM + FLOOR_GAP * (Endless.FLOORS - 1)
	_selected = reachable[0] if reachable.size() == 1 else ""
	_canvas.selected = _selected
	_fill_info()

func _on_resized() -> void:
	if _first_layout and size.y > 0:
		_first_layout = false
		_glide.call_deferred()

## Scrolls so the squad's floor sits in the lower part of the view, gliding up from a little below
func _glide() -> void:
	var floor := -1
	if _canvas.current != "" and _nodes.has(_canvas.current):
		floor = int(_nodes[_canvas.current].floor)
	var y := _canvas.floor_y(maxi(floor, 0))
	var target := clampf(y - size.y * 0.62, 0.0, maxf(_canvas.custom_minimum_size.y - size.y, 0.0))
	if not animate:
		_scroll.scroll_vertical = int(target)
		return
	_scroll.scroll_vertical = int(minf(target + 220.0, _canvas.custom_minimum_size.y))
	create_tween().tween_property(_scroll, "scroll_vertical", int(target), 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_pick(id: String) -> void:
	if not _reachable.has(id):
		return
	if _selected == id:
		go.emit(id)
		return
	_selected = id
	_canvas.selected = id
	_fill_info()

func _fill_info() -> void:
	for c in _info_box.get_children():
		c.queue_free()
	if _selected.is_empty():
		_info_box.add_child(AHKit.label(Terms.t("endless_map_pick"), 15, UITheme.TEXT_DIM))
		return
	var type := String(_nodes[_selected].type)
	var color: Color = AHKit.NODE_COLORS.get(type, Color.WHITE)
	var row := AHKit.hbox(12)
	_info_box.add_child(row)
	row.add_child(AHKit.NodeBadge.new(type, 46))
	var text := AHKit.vbox(2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	text.add_child(AHKit.label(Terms.t("endless_node_" + type).to_upper(), 20, color))
	text.add_child(AHKit.label(Terms.t("endless_node_desc_" + type), 13, UITheme.TEXT, true))
	if type in ["battle", "elite", "boss"]:
		var rewards := Endless.fight_rewards(type)
		text.add_child(AHKit.label(Terms.t("endless_node_reward", {"tips": int(rewards.tips),
			"drinks": int(rewards.picks), "rarity": Terms.t("endless_rarity_%d" % int(rewards.rarity))}), 13, AHKit.TIPS))
	var go_button := AHKit.button(Terms.t("endless_go"), func(): go.emit(_selected), color, true, Vector2(110, 52), 20)
	row.add_child(go_button)

## The drawn map itself (inside the scroll)
class MapCanvas extends Control:
	signal picked(id: String)

	var nodes := {}
	var path: Array = []
	var reachable: Array = []
	var current := ""
	var selected := "":
		set(v):
			selected = v
			queue_redraw()
	var _leader_tex: Texture2D
	var _leader_name := ""
	var _t := 0.0
	var _hover := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_leader(c: CharacterData) -> void:
		_leader_tex = c.get_avatar() if c else null
		_leader_name = c.display_name if c else ""

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func floor_y(f: int) -> float:
		return custom_minimum_size.y - AfterHoursMap.BOTTOM - AfterHoursMap.FLOOR_GAP * f

	## The band the columns spread across: centred, at most MAX_SPREAD wide, clear of the floor numbers
	func band() -> Vector2:
		var usable := minf(size.x - AfterHoursMap.SIDE * 2.0, AfterHoursMap.MAX_SPREAD)
		var left := (size.x - usable) / 2.0
		return Vector2(left, left + usable)

	func pos(id: String) -> Vector2:
		var n: Dictionary = nodes[id]
		var b := band()
		var x := lerpf(b.x, b.y, float(n.col) / float(Endless.COLUMNS - 1))
		# a gentle sway so the columns don't look like a grid
		x += sin(float(n.floor) * 1.7 + float(n.col)) * 10.0 if n.type != "boss" else 0.0
		return Vector2(x, floor_y(int(n.floor)))

	func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var c1 := a + Vector2(0, -AfterHoursMap.FLOOR_GAP * 0.45)
		var c2 := b + Vector2(0, AfterHoursMap.FLOOR_GAP * 0.45)
		for i in 13:
			var k := i / 12.0
			pts.append(a.bezier_interpolate(c1, c2, b, k))
		return pts

	func _draw() -> void:
		if nodes.is_empty():
			return
		var font := ThemeDB.fallback_font
		var cur_floor := int(nodes[current].floor) if current != "" and nodes.has(current) else -1
		# The street: a lit strip behind the columns, brighter towards the boss, with faint floor lines
		var b := band()
		var street := Rect2(b.x - 40.0, 0, b.y - b.x + 80.0, size.y)
		UITheme.draw_vertical_gradient(self, street, Color(AHKit.HOT, 0.07), Color(AHKit.ACCENT, 0.03))
		draw_line(Vector2(street.position.x, 0), Vector2(street.position.x, size.y), Color(AHKit.ACCENT, 0.12), 1.0)
		draw_line(Vector2(street.end.x, 0), Vector2(street.end.x, size.y), Color(AHKit.ACCENT, 0.12), 1.0)
		for f in Endless.FLOORS:
			var y := floor_y(f)
			var here := f == cur_floor + 1 or (f == 0 and cur_floor < 0)
			if here:  # the floor being picked now
				var hl := Rect2(street.position.x, y - AfterHoursMap.FLOOR_GAP / 2, street.size.x, AfterHoursMap.FLOOR_GAP)
				draw_rect(hl, Color(AHKit.ACCENT, 0.06 + 0.03 * sin(_t * 3.0)))
			else:
				draw_line(Vector2(street.position.x + 8, y), Vector2(street.end.x - 8, y), Color(1, 1, 1, 0.025), 1.0)
			if f == Endless.FLOORS - 1:
				continue  # the boss has its own label
			var label := "%d" % (f + 1)
			var col := Color.WHITE if here else (Color(AHKit.ACCENT, 0.7) if f <= cur_floor else Color(1, 1, 1, 0.2))
			var fs := 18 if here else 14
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(street.position.x - 14 - w, y + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			if here:
				draw_colored_polygon(PackedVector2Array([Vector2(street.position.x - 8, y - 6), Vector2(street.position.x - 2, y),
					Vector2(street.position.x - 8, y + 6)]), AHKit.ACCENT)
		# Edges
		var walked := {}
		for i in path.size() - 1:
			walked["%s>%s" % [path[i], path[i + 1]]] = true
		for id in nodes:
			for n in nodes[id].next:
				var pts := _curve(pos(id), pos(n))
				var key := "%s>%s" % [id, n]
				if walked.has(key):
					draw_polyline(pts, Color(AHKit.ACCENT, 0.25), 9.0, true)
					draw_polyline(pts, Color(1, 0.9, 1, 0.9), 3.0, true)
					var k := fmod(_t * 0.8, 1.0)
					draw_circle(pts[int(k * (pts.size() - 1))], 4.0, Color.WHITE)
				elif id == current and reachable.has(n):
					var color: Color = AHKit.NODE_COLORS.get(String(nodes[n].type), Color.WHITE)
					_dashed(pts, Color(color, 0.85), 3.0)
				else:
					draw_polyline(pts, Color(1, 1, 1, 0.1), 2.0, true)
		# From START to the first floor's choices
		if current == "":
			var start := Vector2(size.x / 2.0, floor_y(0) + AfterHoursMap.FLOOR_GAP * 0.62)
			for n in reachable:
				_dashed(_curve(start, pos(n)), Color(AHKit.NODE_COLORS.get(String(nodes[n].type), Color.WHITE), 0.7), 2.5)
			var w := font.get_string_size("START", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			UITheme.draw_glow(self, start, 26.0, Color(AHKit.ACCENT, 0.5))
			draw_string(font, start + Vector2(-w / 2, 6), "START", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
		# Nodes
		for id in nodes:
			var n: Dictionary = nodes[id]
			var type := String(n.type)
			var p := pos(id)
			var color: Color = AHKit.NODE_COLORS.get(type, Color.WHITE)
			var r := AfterHoursMap.BOSS_RADIUS if type == "boss" else AfterHoursMap.RADIUS
			var open: bool = reachable.has(id)
			var done: bool = path.has(id) and id != current
			if open:
				var pulse := 0.5 + 0.5 * sin(_t * 4.0 + p.x * 0.05)
				p.y -= 3.0 * pulse
				UITheme.draw_glow(self, p, r * 2.2, Color(color, 0.35 + 0.2 * pulse))
				draw_arc(p, r + 6 + 3 * pulse, 0, TAU, 40, Color(color, 0.6), 2.0, true)
			if id == selected or id == _hover and open:
				draw_arc(p, r + 11, _t * 2.0, _t * 2.0 + TAU * 0.75, 32, Color.WHITE, 2.5, true)
			var fill := color.darkened(0.55)
			var ink := color.lightened(0.35)
			if done:
				fill = color.darkened(0.7)
				ink = Color(color, 0.55)
			elif not open and id != current:
				fill = Color(0.08, 0.08, 0.13)
				ink = Color(color, 0.4)
			if type == "boss":  # a hot halo, slow rays and a nameplate
				UITheme.draw_glow(self, p, r * 2.6, Color(AHKit.HOT, 0.22))
				for i in 12:
					var a := TAU * i / 12.0 + _t * 0.25
					draw_line(p + Vector2.from_angle(a) * (r + 8), p + Vector2.from_angle(a) * (r + 22), Color(AHKit.HOT, 0.35), 2.0, true)
				var bw := font.get_string_size("BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
				var plate := Rect2(p + Vector2(-bw / 2 - 10, r + 10), Vector2(bw + 20, 22))
				draw_rect(plate, AHKit.HOT.darkened(0.5))
				draw_rect(plate, AHKit.HOT, false, 1.5)
				draw_string(font, plate.position + Vector2(10, 16), "BOSS", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
			draw_circle(p, r, fill)
			draw_arc(p, r, 0, TAU, 40, color if open or id == current else Color(color, 0.35), 2.5 if open else 1.5, true)
			AHKit.draw_node_icon(self, p, r * 0.72, type, ink)
			if done:  # a small tick
				var c := p + Vector2(r * 0.7, -r * 0.7)
				draw_circle(c, 7, Color(0.1, 0.5, 0.25))
				draw_polyline(PackedVector2Array([c + Vector2(-3.5, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Color.WHITE, 2.0, true)
		# The leader's pin on the current node
		if current != "" and nodes.has(current):
			_pin(pos(current))

	## Dots marching along the curve every few pixels (the way forward)
	func _dashed(pts: PackedVector2Array, color: Color, width: float) -> void:
		var step := 11.0
		var carry := fmod(_t * 26.0, step)  # where the first dot sits on this frame
		for i in pts.size() - 1:
			var a := pts[i]
			var seg := pts[i + 1] - a
			var length := seg.length()
			var d := carry
			while d < length:
				draw_circle(a + seg * (d / length), width * 0.75, color)
				d += step
			carry = d - length

	func _pin(at: Vector2) -> void:
		var bob := sin(_t * 3.0) * 3.0
		var box := Rect2(at + Vector2(-17, -64 + bob), Vector2(34, 38))
		draw_colored_polygon(PackedVector2Array([box.position + Vector2(10, box.size.y), box.position + Vector2(24, box.size.y),
			at + Vector2(0, -20 + bob)]), Color.WHITE)
		draw_rect(box.grow(3), Color.WHITE)
		if _leader_tex:
			UITheme.draw_texture_cover(self, _leader_tex, box)
		else:
			draw_rect(box, AHKit.ACCENT.darkened(0.4))
			var font := ThemeDB.fallback_font
			var letter := _leader_name.left(1).to_upper()
			draw_string(font, box.get_center() + Vector2(-7, 8), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		UITheme.draw_glow(self, at, 30.0, Color(1, 1, 1, 0.12))

	func _hit(at: Vector2) -> String:
		for id in nodes:
			var r := AfterHoursMap.BOSS_RADIUS if nodes[id].type == "boss" else AfterHoursMap.RADIUS
			if pos(id).distance_to(at) <= r + 8.0:
				return id
		return ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var h := _hit(event.position)
			if h != _hover:
				_hover = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if reachable.has(h) else Control.CURSOR_ARROW
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := _hit(event.position)
			if not id.is_empty():
				accept_event()
				picked.emit(id)

	func _get_tooltip(at: Vector2) -> String:
		var id := _hit(at)
		return "" if id.is_empty() else Terms.t("endless_node_" + String(nodes[id].type))
