shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

// Stylised sea surface.
//
// All of the read comes from how deep the water is at each pixel, which is the distance
// between the sea surface and whatever is drawn behind it. That one number drives the colour
// from turquoise shallows to deep blue, how see-through the water is, and where the foam sits
// along the shore - so the shoreline follows the terrain exactly, with nothing to line up.

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

group_uniforms Colour;
// Sampled from the "Shallow (sand)" and "Deep ocean" swatches in the art reference.
uniform vec3 shallow_colour : source_color = vec3(0.310, 0.621, 0.655);
uniform vec3 deep_colour : source_color = vec3(0.059, 0.336, 0.477);
// How many metres of water it takes to reach the deep colour.
uniform float depth_fade : hint_range(1.0, 60.0) = 8.5;
// Banded like the terrain, so the sea belongs to the same drawing.
uniform int bands : hint_range(0, 8) = 4;

group_uniforms Transparency;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.50;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.96;

group_uniforms Foam;
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
// Foam appears where the water is shallower than this, i.e. right along the shore.
uniform float foam_depth : hint_range(0.0, 8.0) = 0.45;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.35;
uniform float foam_scale : hint_range(0.5, 40.0) = 9.0;

group_uniforms Surface;
uniform float sparkle_scale : hint_range(1.0, 400.0) = 160.0;
uniform float sparkle_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.25;

varying vec3 world_position;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


// Two octaves of value noise. One octave leaves visible square cells on open water - the
// hash grid shows straight through when the surface is this flat.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


float fbm(vec2 p) {
	return noise(p) * 0.65 + noise(p * 2.17 + 13.7) * 0.35;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Distance from the camera to whatever is behind the water, and to the water itself.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	float behind = -view.z;
	float surface = -VERTEX.z;
	float water_depth = max(behind - surface, 0.0);

	float t = clamp(water_depth / depth_fade, 0.0, 1.0);
	float stepped = t;
	if (bands > 0) {
		// Quantised, but keeping a little of the smooth gradient so the bands read as
		// stylisation rather than as a broken gradient.
		stepped = mix(t, floor(t * float(bands) + 0.5) / float(bands), 0.75);
	}

	// Sparkle is per-pixel noise, so at distance it aliases into a speckled mess. Fade it out
	// with range and let the far water stay flat colour.
	float near = 1.0 - smoothstep(70.0, 350.0, surface);
	vec2 flow = world_position.xz;
	// Two scrolling layers so the surface never looks like it is sliding in one direction.
	float ripple = fbm(flow * (sparkle_scale * 0.01) + vec2(TIME * wave_speed, 0.0))
			* fbm(flow * (sparkle_scale * 0.013) - vec2(0.0, TIME * wave_speed * 0.8));

	// Foam hugs the shore, where there is almost no water between the surface and the sand.
	float shore = 1.0 - clamp(water_depth / max(foam_depth, 0.001), 0.0, 1.0);
	float foam_noise = fbm(flow * (foam_scale * 0.05) + vec2(TIME * foam_speed, TIME * foam_speed * 0.6));
	// Broken along its length rather than a solid white band: a smooth ribbon reads as a
	// painted line on the sand, not as surf.
	float foam = smoothstep(0.45, 0.92, shore * (0.35 + 1.15 * foam_noise));

	vec3 water = mix(shallow_colour, deep_colour, stepped);
	ALBEDO = mix(water, foam_colour, foam);
	ALPHA = mix(mix(shallow_alpha, deep_alpha, stepped), 1.0, foam);
	ROUGHNESS = mix(0.06, 0.35, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	// A little glitter on the open water, killed under the foam where it would look like grease.
	EMISSION = vec3(ripple * sparkle_strength * near * (1.0 - foam) * (1.0 - stepped * 0.6));
	float bump = (ripple - 0.5) * 0.08 * near;
	NORMAL_MAP = vec3(0.5 + bump, 0.5 + bump, 1.0);
}
