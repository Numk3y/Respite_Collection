shader_type canvas_item;
// Gacha banner character art: the picture fades out toward its left, right and bottom edges so it melts into
// the banner instead of sitting in a box. Edges are measured on the TextureRect (rect_size), not the texture.
// With `living` above 0 the character also moves in a Live2D-style idle (see living.gdshaderinc).

#include "res://Shaders/living.gdshaderinc"

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float fade_left = 0.35;  // share of the width that fades in from the left edge
uniform float fade_right = 0.12;
uniform float fade_top = 0.0;  // share of the height that fades in from the top (0 = hard top edge)
uniform float fade_bottom = 0.2;  // share of the height that fades out at the bottom

varying vec2 local_pos;
varying vec4 tint;  // the vertex colour (modulate) alone: in fragment(), COLOR already has the texture in it

void vertex() {
	local_pos = VERTEX;
	tint = COLOR;
}

void fragment() {
	vec2 p = local_pos / rect_size;  // 0..1 across the rect
	float alpha = smoothstep(0.0, fade_left, p.x) * smoothstep(0.0, fade_right, 1.0 - p.x)
		* smoothstep(0.0, fade_bottom, 1.0 - p.y) * (fade_top > 0.0 ? smoothstep(0.0, fade_top, p.y) : 1.0);
	bool sized = rect_size.x > 1.0 && rect_size.y > 1.0;  // the motion needs the rect's size
	COLOR = texture(TEXTURE, living > 0.0 && sized ? living_uv(UV, p) : UV) * tint;
	COLOR.a *= alpha;
}
