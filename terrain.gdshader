shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

// Cel-shaded terrain.
//
// The vertex colours carry the biome bands (seabed, sand, jungle, rock) and this shader does
// three things on top: quantises the lighting into flat bands, paints steep ground as rock
// whatever height it is at, and adds a rim light so the island keeps a readable silhouette
// against the sea.

group_uniforms Shading;
// Three bands reads as stylised; more starts to look like a smooth gradient again.
uniform int bands : hint_range(2, 6) = 3;
// How soft each step between bands is. 0 is a hard edge, which crawls badly on slopes.
uniform float band_softness : hint_range(0.0, 0.3) = 0.06;
// How dark the darkest band gets. Letting it reach 0 gives near-black hillsides, which is
// the single thing that stops stylised terrain reading as stylised.
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.36;
// Shadowed ground should not be grey either - tropical bounce light keeps it colourful.
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.52, 0.62);
uniform float ambient : hint_range(0.0, 1.0) = 0.16;

group_uniforms Ground;
// Sampled from the ground material reference, which shows each surface at play distance.
// The seabed is pale sand rather than the teal the reference shows, because that teal is the
// water's doing and the water shader already tints what is under it.
uniform vec3 seabed_colour : source_color = vec3(0.72, 0.67, 0.52);
uniform vec3 wet_sand_colour : source_color = vec3(0.678, 0.518, 0.384);
uniform vec3 dry_sand_colour : source_color = vec3(0.910, 0.749, 0.529);
uniform vec3 grass_colour : source_color = vec3(0.498, 0.525, 0.220);
uniform vec3 jungle_colour : source_color = vec3(0.149, 0.235, 0.173);
uniform float sea_y = 18.0;
// Metres above the waterline where each band takes over.
uniform float wet_sand_top : hint_range(0.0, 6.0) = 0.55;
uniform float dry_sand_top : hint_range(0.0, 20.0) = 3.5;
uniform float grass_top : hint_range(0.0, 80.0) = 40.0;
// The reference never has a clean contour between materials: sand runs into jungle in
// patches. This jitters the height each pixel thinks it is at, which breaks the bands up.
uniform float edge_break : hint_range(0.0, 8.0) = 1.0;
uniform float patch_scale : hint_range(0.001, 0.5) = 0.035;

group_uniforms Cliffs;
// Slope, not height, decides rock: a cliff at the waterline is still a cliff, and keying rock
// to height alone puts grass on vertical faces and rock on flat hilltops.
uniform vec3 rock_colour : source_color = vec3(0.38, 0.34, 0.30);
uniform float rock_begins : hint_range(0.0, 1.0) = 0.45;
uniform float rock_full : hint_range(0.0, 1.0) = 0.72;

group_uniforms Rim;
uniform vec3 rim_colour : source_color = vec3(1.0, 0.96, 0.82);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.22;

varying vec3 world_normal;
varying vec3 world_position;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


// Octaves are rotated as well as scaled. Without the rotation every octave shares the same
// axis-aligned grid, the cells line up, and the noise shows as square patches wherever it
// drives a boundary.
const mat2 TURN = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));


float fbm(vec2 p) {
	float total = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 5; i++) {
		total += value_noise(p) * weight;
		p = TURN * p * 2.07 + 11.3;
		weight *= 0.5;
	}
	return total;
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Height above the waterline decides the band, jittered per pixel so the boundaries are
	// ragged rather than following a contour line exactly.
	float patchy = fbm(world_position.xz * patch_scale);
	float above = world_position.y - sea_y + (patchy - 0.5) * edge_break;

	vec3 ground = seabed_colour;
	ground = mix(ground, wet_sand_colour, smoothstep(-0.6, 0.2, above));
	ground = mix(ground, dry_sand_colour, smoothstep(wet_sand_top * 0.4, wet_sand_top, above));
	ground = mix(ground, grass_colour, smoothstep(dry_sand_top * 0.35, dry_sand_top * 1.5, above));
	// Darker jungle floor in patches through the grass, rather than one flat green.
	float undergrowth = smoothstep(0.30, 0.95, fbm(world_position.xz * patch_scale * 2.6));
	ground = mix(ground, jungle_colour, undergrowth * smoothstep(dry_sand_top, grass_top * 0.35, above));

	// 0 on flat ground, 1 on a vertical face. Slope decides rock, so a cliff is rock at any
	// height, and the reference only ever shows faceted rock on steep faces.
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(rock_begins, rock_full, slope);
	rock = max(rock, smoothstep(grass_top, grass_top * 1.6, above));
	ALBEDO = mix(ground, rock_colour, rock);

	// Wet sand is the one surface in the reference with a sheen on it.
	float wet = smoothstep(0.6, -0.2, above) * (1.0 - rock);
	ROUGHNESS = mix(1.0, 0.45, wet);
	SPECULAR = mix(0.2, 0.6, wet);

	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION = rim_colour * pow(1.0 - facing, rim_power) * rim_strength;
}

void light() {
	// Attenuation folds in before the banding, so a cast shadow becomes another flat band
	// rather than a black hole: applied afterwards it multiplies the floor away.
	float lambert = clamp(dot(normalize(NORMAL), normalize(LIGHT)), 0.0, 1.0) * ATTENUATION;
	// Quantise into flat bands, then ease each step so the edges do not shimmer when the
	// camera moves across a slope.
	float scaled = lambert * float(bands);
	float index = floor(scaled);
	float blend = smoothstep(0.5 - band_softness, 0.5 + band_softness, fract(scaled));
	float toon = (index + blend) / float(bands);
	// Lift the whole ramp: the darkest band keeps most of the albedo instead of going black,
	// and the shadow tint colours it rather than greying it out.
	toon = mix(shadow_floor, 1.0, toon);

	vec3 lit = mix(shadow_tint, LIGHT_COLOR, toon) * toon;
	DIFFUSE_LIGHT += ALBEDO * (lit + shadow_tint * ambient);
}
