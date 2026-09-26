// What the waterfall's three shaders - the sheet, the splash puffs and the pool foam - share:
// value noise, the hard toon edge, and the light.
//
// The noise uses the same polynomial hash as world/ocean.gdshader, and for its reason: sin()
// of a large number loses precision on Mobile, and the sheet's streak coordinate grows with
// TIME.

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

// A hard toon edge at `edge`, anti-aliased over one pixel's worth of `x` and no more - a
// fixed softness blurs up close and shimmers far away.
float band(float x, float edge) {
	float w = max(fwidth(x), 0.0001) * 0.75;
	return smoothstep(edge - w, edge + w, x);
}

// Toon light for water, shared by the three shaders' light(). Two flat tones: the side facing
// the sun, and the side away from it at `wrap` of that - not black. Water is lit through, not
// just on, and with the plain toon diffuse a fall with the sun behind it, or standing in the
// mountain's shadow, was lit by the blue sky alone and every white in it came out a strong
// blue. For the same reason the shaders take no cast shadows (shadows_disabled): the foot of
// this fall is in the mountain's shadow most of the day, and white water in shade is still
// white. Night still falls on it, because the sun's energy does.
vec3 water_light(vec3 normal, vec3 light, vec3 light_colour, float attenuation, float wrap) {
	float facing = smoothstep(-0.05, 0.05, dot(normal, light));
	// LIGHT_COLOR carries a factor of PI for physically based models to divide out.
	return light_colour * attenuation * mix(wrap, 1.0, facing) / PI;
}
