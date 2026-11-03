shader_type canvas_item;
// A character picture with the Live2D-style idle motion only (no edge fades): used on framed portraits such as
// the Home screen's featured friend. See living.gdshaderinc.

#include "res://Shaders/living.gdshaderinc"

uniform vec2 rect_size = vec2(100.0, 100.0);

varying vec2 local_pos;
varying vec4 tint;  // the vertex colour (modulate) alone: in fragment(), COLOR already has the texture in it

void vertex() {
	local_pos = VERTEX;
	tint = COLOR;
}

void fragment() {
	// Until the size is known, show the picture as it is rather than sampling nonsense
	vec2 uv = rect_size.x > 1.0 && rect_size.y > 1.0 ? living_uv(UV, local_pos / rect_size) : UV;
	COLOR = texture(TEXTURE, uv) * tint;
}
