shader_type canvas_item;
// Gacha banner character art: the picture fades out toward its left, right and bottom edges so it melts into
// the banner instead of sitting in a box. Edges are measured on the TextureRect (rect_size), not the texture.

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float fade_left = 0.35;  // share of the width that fades in from the left edge
uniform float fade_right = 0.12;
uniform float fade_top = 0.0;  // share of the height that fades in from the top (0 = hard top edge)
uniform float fade_bottom = 0.2;  // share of the height that fades out at the bottom

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos / rect_size;  // 0..1 across the rect
	float alpha = smoothstep(0.0, fade_left, p.x) * smoothstep(0.0, fade_right, 1.0 - p.x)
		* smoothstep(0.0, fade_bottom, 1.0 - p.y) * (fade_top > 0.0 ? smoothstep(0.0, fade_top, p.y) : 1.0);
	COLOR = texture(TEXTURE, UV) * COLOR;
	COLOR.a *= alpha;
}
