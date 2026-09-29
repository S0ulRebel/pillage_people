// The distance to the shore (world/shore_field.gd), shared by the sea and the sand shaders so
// that everything drawn from it - foam, shore waves, wet sand - lines up across the waterline.
// terrain.gd hands both materials the same texture (apply_shore_field()).
//
//   shore_field_at(xz).x   signed metres to the still waterline: + out to sea, - up the land
//   shore_field_at(xz).yz  the nearest point of the waterline, world x and z
//   shore_field_at(xz).w   unused yet
//
// Until the field arrives (rect.w is 0) every point reads as far out at sea, so nothing that
// hangs off it draws.

uniform sampler2D shore_field : filter_linear, repeat_disable;
// (x, z) of texel 0's centre in world metres, metres between texel centres, texels per side.
uniform vec4 shore_field_rect = vec4(0.0);
// Draws the field instead of the surface: metre bands, blue out to sea and orange up the land,
// a white line every 5 m and a red one on the waterline itself. For checking the field.
uniform bool shore_field_preview = false;

vec4 shore_field_at(vec2 xz) {
	if (shore_field_rect.w < 2.0) {
		return vec4(1.0e4, xz, 0.0);
	}
	vec2 uv = ((xz - shore_field_rect.xy) / shore_field_rect.z + 0.5) / shore_field_rect.w;
	return textureLod(shore_field, uv, 0.0);
}

// The direction from a point toward the nearest shore, flat. Zero right on the waterline.
vec2 shore_direction(vec2 xz, vec4 field) {
	vec2 to_shore = field.yz - xz;
	float len = length(to_shore);
	return len > 1.0e-3 ? to_shore / len : vec2(0.0);
}

vec3 shore_field_preview_colour(vec2 xz) {
	float d = shore_field_at(xz).x;
	float px = max(fwidth(d), 1.0e-4);
	vec3 base = d > 0.0 ? vec3(0.10, 0.30, 0.65) : vec3(0.70, 0.45, 0.15);
	// Light and dark metre bands, so the spacing reads everywhere.
	base *= 0.75 + 0.25 * step(0.5, fract(d));
	float five = 1.0 - smoothstep(0.0, px * 1.5, abs(fract(d / 5.0 + 0.5) - 0.5) * 5.0);
	float shore = 1.0 - smoothstep(0.0, px * 1.5, abs(d));
	vec3 colour = mix(base, vec3(1.0), five * 0.8);
	return mix(colour, vec3(1.0, 0.1, 0.1), shore);
}
