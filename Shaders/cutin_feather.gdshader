shader_type canvas_item;
// Ultimate cut-in picture: sharp in the middle, blurred and faded toward the left/right edges.
// The backdrop copy (edge_only = false) samples source_tex instead, a tiny pre-shrunk render that is
// stretched with linear filtering, blurs a little more everywhere and is darkened/tinted.
// rect_size must be set to the TextureRect's size so edges are measured on screen, not in texture space
// (the picture may be cropped by its stretch mode).

uniform vec2 rect_size = vec2(100.0, 100.0);
uniform float blur_px = 6.0;  // blur step in texels at the edges (or everywhere if !edge_only)
uniform bool edge_only = true;
uniform float sharp = 0.45;  // centre share (0-1 of the half width) that stays sharp
uniform float fade = 0.35;  // outer share of the half width that fades to transparent
uniform float darken = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);  // mixed in by its alpha
uniform bool use_source = false;
uniform sampler2D source_tex : filter_linear, repeat_disable;
uniform vec2 source_pixel = vec2(0.01, 0.01);  // 1 / source_tex size

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float d = abs(local_pos.x / rect_size.x - 0.5) * 2.0;  // 0 centre .. 1 edge
	float amount = edge_only ? smoothstep(sharp, 1.0, d) : 1.0;
	vec2 texel = use_source ? source_pixel : TEXTURE_PIXEL_SIZE;
	vec2 step_uv = texel * blur_px * amount;
	vec4 c = (use_source ? texture(source_tex, UV) : texture(TEXTURE, UV)) * 0.16;
	float total = 0.16;
	for (int i = 1; i <= 3; i++) {
		float f = float(i);
		float w = 0.14 - f * 0.02;
		vec2 dx = vec2(step_uv.x * f, 0.0);
		vec2 dy = vec2(0.0, step_uv.y * f * 0.6);
		if (use_source) {
			c += (texture(source_tex, UV + dx) + texture(source_tex, UV - dx)) * w;
			c += (texture(source_tex, UV + dy) + texture(source_tex, UV - dy)) * w * 0.5;
		} else {
			c += (texture(TEXTURE, UV + dx) + texture(TEXTURE, UV - dx)) * w;
			c += (texture(TEXTURE, UV + dy) + texture(TEXTURE, UV - dy)) * w * 0.5;
		}
		total += w * 3.0;
	}
	c /= total;
	c.rgb = mix(c.rgb, tint.rgb, tint.a) * (1.0 - darken);
	float alpha = edge_only ? 1.0 - smoothstep(1.0 - fade, 1.0, d) : 1.0;
	COLOR = c * COLOR;
	COLOR.a *= alpha;
}
