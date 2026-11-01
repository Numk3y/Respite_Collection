class_name CyberBackdrop
extends Control
## Full-screen procedural background behind every screen: deep navy gradient, a faint digital grid with brighter
## nodes at every fourth line, soft cyan/violet glows in the corners and a vignette. Drawn once (no per-frame
## work), so it costs nothing while the game idles.

const GRID := 40.0
const MAJOR_EVERY := 4

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	UITheme.draw_vertical_gradient(self, rect, UITheme.BG_TOP, UITheme.BG_BOTTOM)
	UITheme.draw_glow(self, Vector2(size.x * 0.08, size.y * 0.1), size.y * 0.7, Color(UITheme.CYAN, 0.16))
	UITheme.draw_glow(self, Vector2(size.x * 0.95, size.y * 0.95), size.y * 0.8, Color(UITheme.VIOLET, 0.16))

	# Grid: thin lines everywhere, slightly brighter major lines, little nodes where major lines cross
	var minor := Color(UITheme.CYAN, 0.035)
	var major := Color(UITheme.CYAN, 0.07)
	var i := 0
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), major if i % MAJOR_EVERY == 0 else minor, 1.0)
		x += GRID
		i += 1
	i = 0
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), major if i % MAJOR_EVERY == 0 else minor, 1.0)
		y += GRID
		i += 1
	var step := GRID * MAJOR_EVERY
	var node := Color(UITheme.CYAN, 0.22)
	x = 0.0
	while x <= size.x:
		y = 0.0
		while y <= size.y:
			draw_rect(Rect2(x - 1.5, y - 1.5, 3, 3), node)
			y += step
		x += step

	# Vignette: darken the edges so the centre content pops
	var edge := Color(0, 0, 0, 0.35)
	var clear := Color(0, 0, 0, 0)
	var band := size.y * 0.18
	UITheme.draw_vertical_gradient(self, Rect2(0, 0, size.x, band), edge, clear)
	UITheme.draw_vertical_gradient(self, Rect2(0, size.y - band, size.x, band), clear, edge)
