shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, unshaded;

// Unshaded, and lit here instead. Through the engine's light path the sea came out grey:
// shallow water rendered #719296 against a #4f9ea6 swatch, and deep water #79999d against
// #0e5579 - pale blue-grey where it should be near navy. Unshaded, an albedo renders as
// itself, so the sampled water colours survive and the shading below is the only thing
// acting on them.

// Sea surface.
//
// The waves are real geometry: a sum of Gerstner waves displacing the vertices, with the
// normal taken from the analytic derivatives rather than from the mesh. Gerstner waves move
// each point in a circle rather than straight up and down, which gathers water into sharp
// crests and leaves broad flat troughs - the shape plain sine waves cannot make.
//
// Everything white on the surface is derived from that geometry:
//
//   * crest foam comes from the Jacobian of the displacement. Where the horizontal part of
//     the motion starts folding the surface over itself the determinant collapses, and that
//     is exactly where a real wave whitecaps.
//   * shore foam comes from how much water is left between the surface and the sand, so the
//     surf follows the terrain at any shoreline with nothing to place by hand.
//   * caustics come from the surface curvature focusing light onto the bottom, and fade out
//     as the water deepens because there is nothing left to cast onto.

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
// The seabed, straight from the terrain's height map. The depth buffer only knows where the
// displaced surface is, so depth read from it moves with the waves and the colour shimmers;
// the height map gives a still answer to "how deep is the water here".
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform float terrain_size = 620.0;
uniform float terrain_scale = 180.0;
uniform float sea_y = 18.0;

group_uniforms Colour;
// Sampled from the "Shallow (sand)" and "Deep ocean" swatches in the art reference.
uniform vec3 shallow_colour : source_color = vec3(0.435, 0.760, 0.745);
uniform vec3 deep_colour : source_color = vec3(0.059, 0.336, 0.477);
uniform float depth_fade : hint_range(1.0, 60.0) = 8.5;
uniform int bands : hint_range(0, 8) = 4;
// High even in the shallows: at half transparency the turquoise simply averages with the
// bright sand underneath and the whole lagoon lands on grey-green. The reference keeps its
// colour over sand and lets the bottom read through as shapes, not as its own colour.
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.42;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.96;

group_uniforms Waves;
// Each wave is (direction x, direction z, steepness, wavelength). Steepness near 1 is a wave
// on the point of breaking; past it the surface folds through itself.
uniform vec4 wave_1 = vec4(1.0, 0.25, 0.72, 21.0);
uniform vec4 wave_2 = vec4(-0.5, 0.9, 0.55, 12.5);
uniform vec4 wave_3 = vec4(0.75, -0.7, 0.42, 7.0);
uniform vec4 wave_4 = vec4(-0.85, -0.3, 0.30, 3.6);
uniform float wave_height : hint_range(0.0, 3.0) = 0.5;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;
// Swell flattens as it runs into the shallows, the way real waves do over a shelf. Without
// this the open-sea swell carries straight up the beach and slices through the sand.
uniform float shoal_depth : hint_range(0.5, 40.0) = 2.5;

group_uniforms Foam;
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
// The Jacobian value below which the surface counts as breaking.
uniform float crest_fold : hint_range(0.0, 1.5) = 0.62;
uniform float crest_sharpness : hint_range(0.01, 1.0) = 0.22;
// Where on the wave the crest streak sits, and how wide it is, as a fraction of wave height.
uniform float crest_line_height : hint_range(0.0, 1.0) = 0.72;
uniform float crest_line_width : hint_range(0.01, 0.5) = 0.06;
// Depth of water at which the shore surf starts.
uniform float foam_depth : hint_range(0.0, 8.0) = 0.35;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.35;

group_uniforms Caustics;
uniform float caustic_strength : hint_range(0.0, 2.0) = 0.5;
// Cells per metre. Sized against the reference frame rather than against the character:
// counting cells across the panel gives roughly a metre each, not the three metres that
// measuring one cell against the figure suggested.
uniform float caustic_scale : hint_range(0.02, 4.0) = 1.15;
uniform float caustic_width : hint_range(0.01, 0.8) = 0.20;
// Set from the scene's sun, so the sea is shaded by the same light as the island.
uniform vec3 sun_direction = vec3(-0.5, 0.7, -0.5);
// Water is nearly flat colour in the reference, so the sun only shapes it a little.
uniform float wave_shading : hint_range(0.0, 1.0) = 0.22;

varying vec3 world_position;
varying float sea_bed_depth;
varying vec3 wave_normal;
varying float fold;
varying float lens_power;
varying float crest_rise;
varying float swell;


// One Gerstner wave. Accumulates the displacement, the normal terms and the second-derivative
// terms the Jacobian needs, so the crest foam falls out of the same maths that makes the
// shape instead of being estimated from it afterwards.
void gerstner(vec4 wave, vec2 position, float time, float scale,
		inout vec3 offset, inout vec3 normal_sum,
		inout float jxx, inout float jzz, inout float jxz) {
	vec2 direction = normalize(wave.xy);
	float steepness = wave.z * scale;
	float wavelength = max(wave.w, 0.01);
	float k = TAU / wavelength;
	float speed = sqrt(9.8 / k);                    // deep-water dispersion
	float amplitude = steepness / k;
	float phase = k * dot(direction, position) - speed * time * wave_speed;
	float c = cos(phase);
	float s = sin(phase);

	offset += vec3(direction.x * amplitude * c, amplitude * s, direction.y * amplitude * c);

	float wa = k * amplitude;
	normal_sum += vec3(direction.x * wa * c, steepness * wa * s, direction.y * wa * c);

	jxx += steepness * direction.x * direction.x * wa * s;
	jzz += steepness * direction.y * direction.y * wa * s;
	jxz += steepness * direction.x * direction.y * wa * s;
}


// Metres of water over the seabed at a world position, from the terrain height map.
float water_over_bed(vec2 world_xz) {
	vec2 uv = world_xz / terrain_size + 0.5;
	// Outside the island's map there is only open sea, so treat it as deep.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 1000.0;
	}
	return sea_y - texture(terrain_height, uv).r * terrain_scale;
}


float warp_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


float warp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(warp_hash(i), warp_hash(i + vec2(1.0, 0.0)), f.x),
			mix(warp_hash(i + vec2(0.0, 1.0)), warp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}


vec2 cell_hash(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}


// Distance to the nearest border between cells.
//
// This is what the caustics are in the reference: a web of soft pale lines around big
// irregular cells, two or three character-heights across - not a fine interference pattern.
// An earlier attempt derived them from ripples refracting light, which is how caustics
// actually form and which produced a dense realistic shimmer that looked nothing like the
// art. The reference is drawn, so it gets drawn.
float cell_border(vec2 p, float t) {
	// Bend the coordinates before the cells are found. A plain Voronoi gives straight-edged
	// polygons; the reference web is wobbly, its lines curving between junctions, and that
	// comes from warping the space the cells sit in rather than from the cells themselves.
	// Kept well under half a cell. Warp harder and neighbouring cells stop agreeing on where
	// their shared border is, so the web tears into loose fragments instead of curving.
	p += (vec2(warp_noise(p * 0.5 + t * 0.05), warp_noise(p * 0.5 + 4.7 - t * 0.04)) - 0.5) * 0.55
			+ (vec2(warp_noise(p * 1.6 - t * 0.08), warp_noise(p * 1.6 + 9.1)) - 0.5) * 0.18;
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			// The cell centres drift, so the web slides and reshapes instead of sitting still.
			vec2 point = offset + 0.5 + 0.38 * sin(t * 0.5 + 6.2831 * cell_hash(cell + offset));
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
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sea_bed_depth = water_over_bed(world.xz);
	// Never all the way to zero: water right at the edge still moves, and with the waves
	// switched off entirely the shallows go glassy and the caustics vanish with them.
	float shoal = clamp(sea_bed_depth / shoal_depth, 0.18, 1.0);
	swell = shoal;
	float amplitude = wave_height * shoal;
	vec3 offset = vec3(0.0);
	vec3 normal_sum = vec3(0.0);
	float jxx = 0.0;
	float jzz = 0.0;
	float jxz = 0.0;

	// Quads grow with distance, so the short waves end up smaller than the quad carrying them
	// and alias into a crawling mess. Fade those out with range and keep the long swell.
	float span = length(world - CAMERA_POSITION_WORLD);
	float detail = 1.0 - smoothstep(120.0, 900.0, span);

	gerstner(wave_1, world.xz, TIME, amplitude, offset, normal_sum, jxx, jzz, jxz);
	gerstner(wave_2, world.xz, TIME, amplitude, offset, normal_sum, jxx, jzz, jxz);
	gerstner(wave_3, world.xz, TIME, amplitude * detail, offset, normal_sum, jxx, jzz, jxz);
	gerstner(wave_4, world.xz, TIME, amplitude * detail, offset, normal_sum, jxx, jzz, jxz);

	// How high this point sits within the wave, 0 in the trough and 1 on the very top. The
	// Jacobian only whitens water that is actually breaking, and a calm lagoon never is - but
	// the reference still draws thin foam streaks along the tops, so the height gives those.
	float reach = 0.0;
	reach += wave_1.z / (TAU / max(wave_1.w, 0.01));
	reach += wave_2.z / (TAU / max(wave_2.w, 0.01));
	reach += wave_3.z / (TAU / max(wave_3.w, 0.01));
	reach += wave_4.z / (TAU / max(wave_4.w, 0.01));
	crest_rise = offset.y / max(reach * amplitude, 0.0001);

	world += offset;
	world_position = world;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;

	wave_normal = normalize(vec3(-normal_sum.x, 1.0 - normal_sum.y, -normal_sum.z));
	NORMAL = wave_normal;

	// Determinant of the horizontal Jacobian: it falls towards zero where neighbouring points
	// converge, which is the fold that becomes a whitecap.
	fold = (1.0 - jxx) * (1.0 - jzz) - jxz * jxz;
	// How strongly the surface bends light at this point. jxx and jzz are the second
	// derivatives of the displacement, so their sum is the curvature of the surface: positive
	// where it is domed like a converging lens, negative in the hollows.
	lens_power = jxx + jzz;
}


void fragment() {
	// The sea sheet runs right under the island, and near the shore the waves drop it below
	// the sand, so water is visible passing underneath the beach. Anywhere the surface has
	// ended up beneath the ground there is no water to draw.
	float ground_y = sea_y - sea_bed_depth;
	if (world_position.y < ground_y - 0.02) {
		discard;
	}

	// Depth over the seabed for everything the eye reads as "how deep is it here", and the
	// depth buffer only for fading the water against geometry that is not the terrain.
	float water_depth = max(sea_bed_depth, 0.0);
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	view.xyz /= view.w;
	float to_solid = max(-view.z + VERTEX.z, 0.0);

	float t = clamp(water_depth / depth_fade, 0.0, 1.0);
	float stepped = t;
	if (bands > 0) {
		// Quantised, but keeping some of the gradient so it reads as stylisation rather than
		// as a broken ramp.
		stepped = mix(t, floor(t * float(bands) + 0.5) / float(bands), 0.75);
	}

	// Whitecaps where the surface is folding. This is the wave breaking, not a pattern.
	float breaking = smoothstep(crest_fold, crest_fold - crest_sharpness, fold);
	// A narrow band at a fixed height on the wave, which draws a thin line running along each
	// crest. Everything-above-a-threshold gives white caps, and on calm water there are none -
	// the marks in the reference are streaks along the crest, not breaking foam.
	float line = 1.0 - smoothstep(0.0, crest_line_width, abs(crest_rise - crest_line_height));
	float tops = line * smoothstep(0.12, 0.45, swell);
	float crest = max(breaking, tops);

	// Surf along the shore, advancing and retreating so it reads as water running up the sand.
	float surge = foam_depth * (0.75 + 0.45 * sin(TIME * foam_speed * 2.2 + world_position.x * 0.05));
	float shore = 1.0 - clamp(water_depth / max(surge, 0.001), 0.0, 1.0);
	float surf = smoothstep(0.25, 0.75, shore);

	// Caustics. Sunlight refracts through the surface and the curved parts act as lenses, so
	// neighbouring rays converge on the way down and land on the seabed bunched together.
	// How bunched depends on both the curvature and how far the light has to travel, which is
	// why the depth belongs in here - a gentle swell over deep water focuses as hard as a
	// sharp ripple over a foot of sand, and the web widens as the bottom drops away.
	float visible_bottom = 1.0 - clamp(water_depth / 7.0, 0.0, 1.0);
	float contact = smoothstep(0.0, 1.2, to_solid);   // soften where the sea meets geometry
	// Wide soft borders, as drawn: a thin hard line reads as a net laid on the sand.
	float border = cell_border(world_position.xz * caustic_scale, TIME);
	float caustic = (1.0 - smoothstep(0.0, caustic_width, border))
			* caustic_strength * visible_bottom;

	float white = clamp(max(crest, surf) + caustic, 0.0, 1.0);
	vec3 water = mix(shallow_colour, deep_colour, stepped);
	vec3 colour = mix(water, foam_colour, white);

	// Only a gentle shade off the wave normal: enough that the swell reads as a surface with
	// shape, not so much that it drags the colour away from the swatch it came from.
	float lambert = clamp(dot(normalize(wave_normal), normalize(sun_direction)), 0.0, 1.0);
	// Centred on the angle flat water sits at, so an unlit-looking swell darkens and a
	// sunward face brightens, but level water renders as exactly its own colour. Ramping from
	// 1 - shading upwards instead means every pixel is darkened and the whole sea drops below
	// the swatch it was sampled from.
	ALBEDO = colour * (1.0 + (lambert - 0.55) * wave_shading);

	ALPHA = mix(mix(shallow_alpha, deep_alpha, stepped), 1.0, max(surf, crest)) * contact;
}
