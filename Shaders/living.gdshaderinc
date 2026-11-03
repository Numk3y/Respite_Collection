// "Live2D-style" idle motion for a flat character picture, done by bending where the picture is sampled:
// breathing (a slow vertical stretch anchored at the bottom), sway (the top drifts sideways, more the higher up),
// hair flutter (a faster small ripple near the top), a slight head tilt of the upper part, and a lean toward
// `living_look` (e.g. the mouse). The feet stay put: every motion fades out toward the bottom edge.
// Use: include this, then in fragment() sample at living_uv(UV, p) where p is the pixel's 0-1 position on the rect.

uniform float living = 0.0;  // 0 = still, 1 = the full idle motion
uniform float living_seed = 0.0;  // offsets the timing so several pictures don't move in sync
uniform vec2 living_look = vec2(0.0);  // -1..1 on each axis: which way the character leans/looks

// How far the picture content moves at rect position p (in rect fractions; y grows downwards)
vec2 living_offset(vec2 p) {
	float t = TIME + living_seed * 7.13;
	float up = clamp(1.0 - p.y, 0.0, 1.0);  // 0 at the bottom edge, 1 at the top
	vec2 d = vec2(0.0);
	// Breathing: stretch upwards from the bottom and back
	float breath = sin(t * 1.7) * 0.012;
	d.y -= up * breath;
	// Sway: a slow drift that grows towards the top
	d.x += sin(t * 0.9) * 0.010 * up * up;
	// Hair flutter: a quicker ripple running down the top half
	d.x += sin(t * 2.6 + p.y * 9.0) * 0.004 * pow(up, 3.0);
	// Head tilt: the upper part turns a little around a point near the neck
	vec2 pivot = vec2(0.5, 0.42);
	float tilt = sin(t * 0.7 + 1.3) * 0.022 * smoothstep(0.55, 0.0, p.y);
	vec2 rel = p - pivot;
	d += vec2(rel.x * cos(tilt) - rel.y * sin(tilt), rel.x * sin(tilt) + rel.y * cos(tilt)) - rel;
	// Lean towards where the player is looking
	d += vec2(living_look.x * 0.014, living_look.y * 0.006) * up;
	return d * living;
}

// The texture coordinate to sample for the pixel at rect position p (whose plain coordinate is uv): moves the
// content by living_offset. Screen-space derivatives turn rect fractions into texture units, so it also works
// when the picture is cropped (e.g. "keep aspect covered").
vec2 living_uv(vec2 uv, vec2 p) {
	vec2 d = living_offset(p);
	vec2 dp = vec2(dFdx(p.x), dFdy(p.y));
	vec2 duv = vec2(dFdx(uv.x), dFdy(uv.y));
	vec2 per = vec2(abs(dp.x) > 1e-7 ? duv.x / dp.x : 0.0, abs(dp.y) > 1e-7 ? duv.y / dp.y : 0.0);
	return uv - d * per;
}
