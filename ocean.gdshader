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

group_uniforms Waves;
// Thin white crest lines, as in the reference swatches: contours of a moving wave field,
// not a noise pattern. Noise gives speckle; the reference is long sweeping strokes.
uniform float crest_width : hint_range(0.005, 0.3) = 0.035;
uniform float crest_scale : hint_range(0.005, 0.2) = 0.055;
uniform float wave_speed : hint_range(0.0, 2.0) = 0.35;

group_uniforms Caustics;
// The web of bright lines over sand in the "Shallow (sand)" swatch: cell edges, fading out
// as the water deepens because you can only see them on the bottom.
uniform float caustic_scale : hint_range(0.01, 2.0) = 0.55;
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.30;

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


vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}


// A few sine waves crossing at different angles. Its contours are the long curved strokes the
// reference draws its crests with - a single direction gives corduroy, three reads as sea.
float wave_field(vec2 p, float t) {
	float f = sin(dot(p, normalize(vec2(1.0, 0.35))) * crest_scale + t * wave_speed);
	f += 0.62 * sin(dot(p, normalize(vec2(-0.45, 1.0))) * crest_scale * 1.7 + t * wave_speed * 0.8);
	f += 0.34 * sin(dot(p, normalize(vec2(0.8, -0.6))) * crest_scale * 2.9 - t * wave_speed * 1.2);
	return f;
}


// Distance to the nearest cell border, which is what the caustic web in the shallows is.
float cell_edge(vec2 p, float t) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 point = offset + 0.5 + 0.42 * sin(t * 0.6 + 6.2831 * hash2(cell + offset));
			float d = length(point - local);
			if (d < nearest) {
				second = nearest;
				nearest = d;
			} else if (d < second) {
				second = d;
			}
		}
	}
	return second - nearest;
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
	float field = wave_field(flow, TIME);

	// Contour lines of the wave field: zero on the contour, so a narrow band around it is a
	// thin white crest. Widened with distance so the lines do not alias into speckle.
	float far = smoothstep(60.0, 420.0, surface);
	float ring = abs(fract(field * 0.5) - 0.5) * 2.0;
	float crest = 1.0 - smoothstep(0.0, crest_width + far * 0.25, ring);
	crest *= 1.0 - far * 0.75;

	// Caustics only where the bottom is visible; in deep water there is nothing to cast onto.
	float shallowness = 1.0 - clamp(water_depth / 6.0, 0.0, 1.0);
	float caustic = 0.0;
	if (shallowness > 0.01) {
		float edge = cell_edge(flow * caustic_scale, TIME);
		caustic = (1.0 - smoothstep(0.0, 0.16, edge)) * shallowness * caustic_strength * (1.0 - far);
	}

	// The surf line advances and retreats instead of sitting still, which is what reads as a
	// wave breaking rather than a white edge painted along the sand.
	float surge = foam_depth * (0.75 + 0.45 * sin(TIME * foam_speed * 2.2 + field * 0.6));
	float shore = 1.0 - clamp(water_depth / max(surge, 0.001), 0.0, 1.0);
	float foam = smoothstep(0.25, 0.75, shore);

	vec3 water = mix(shallow_colour, deep_colour, stepped);
	water = mix(water, foam_colour, clamp(crest * 0.85 + caustic, 0.0, 1.0));
	ALBEDO = mix(water, foam_colour, foam);
	ALPHA = mix(mix(shallow_alpha, deep_alpha, stepped), 1.0, max(foam, crest * 0.6));
	ROUGHNESS = mix(0.10, 0.4, max(foam, crest));
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
