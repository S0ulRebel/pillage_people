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

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// 0 on flat ground, 1 on a vertical face.
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(rock_begins, rock_full, slope);
	ALBEDO = mix(COLOR.rgb, rock_colour, rock);
	ROUGHNESS = 1.0;

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
