shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Mobile-compatible transparent water. Depth colour uses the shared heightmap;
// contact uses reverse-Z scene depth. Surface detail is evaluated per pixel.
// The surface itself - the wave sum, the seabed under it and the clock - is shared with the
// underwater shader, which has to find the same waterline from below.
#include "res://world/waves.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D band_mask : filter_linear, repeat_disable;
uniform vec2 band_mask_center = vec2(0.0);
uniform float band_mask_size = 144.0;
uniform vec2 band_mask_texel = vec2(0.001953125);
uniform bool band_mask_ready = false;

group_uniforms Colour;
uniform vec3 shallow_colour : source_color = vec3(0.08, 0.64, 0.68);
uniform vec3 lagoon_colour : source_color = vec3(0.025, 0.48, 0.60);
uniform vec3 deep_colour : source_color = vec3(0.059, 0.336, 0.477);
// Keep the lagoon floor visible while deep water becomes opaque.
uniform float depth_fade : hint_range(1.0, 60.0) = 26.0;
uniform int bands : hint_range(0, 8) = 4;
uniform float band_strength : hint_range(0.0, 1.0) = 0.12;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.58;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.94;
// Art-directed Beer-Lambert coefficients. Red is lost first; blue travels furthest.
uniform vec3 absorption = vec3(0.24, 0.075, 0.028);
uniform float absorption_strength : hint_range(0.0, 3.0) = 0.78;
uniform float scattering_strength : hint_range(0.0, 1.5) = 0.68;
// Opaque, unshaded colour ramp for checking colours against your swatches.
uniform bool palette_preview = false;

group_uniforms Waves;
uniform float detail_near = 70.0;
uniform float detail_far = 260.0;
// Actual exponential mesh layout, supplied by ocean.gd.
uniform float radial_growth = 1.0712;
uniform float radial_segments = 256.0;

group_uniforms Transmission;
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.008;
uniform float refraction_depth : hint_range(0.1, 8.0) = 1.8;

group_uniforms Foam;
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
uniform float crest_strength : hint_range(0.0, 1.0) = 0.28;
uniform float foam_depth : hint_range(0.0, 8.0) = 0.55;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.35;
uniform float shore_softness : hint_range(0.01, 0.5) = 0.06;
uniform float contact_fade : hint_range(0.01, 2.0) = 0.12;

group_uniforms Object_Bands;
uniform vec3 object_band_colour : source_color = vec3(0.84, 1.0, 0.94);
uniform float object_band_distance : hint_range(0.1, 3.0) = 0.22;
uniform float object_band_width : hint_range(0.05, 0.6) = 0.07;
uniform float object_band_strength : hint_range(0.0, 1.0) = 0.68;
uniform float object_band_distortion : hint_range(0.0, 0.5) = 0.24;
uniform float object_band_speed : hint_range(0.0, 3.0) = 0.8;

group_uniforms Lighting;
// Direction TO the sun. Pushed from ocean.gd, which reads it off the scene's own
// DirectionalLight - this used to be a hardcoded guess with its Z the wrong way round, so the
// water was lit from roughly the opposite bearing to everything standing on the beach.
uniform vec3 sun_direction = vec3(-0.53, 0.37, 0.76);
uniform float wave_shading : hint_range(0.0, 1.0) = 0.18;
// The bright path the sun lays across the water. Stepped rather than a smooth highlight: this
// sea bands its depth colours and the sky steps its halo, and a photographic specular here
// would be the one thing in frame obeying different rules.
uniform vec3 glitter_colour : source_color = vec3(1.0, 0.97, 0.86);
uniform float glitter_strength : hint_range(0.0, 1.0) = 0.5;
uniform float glitter_sharpness : hint_range(4.0, 400.0) = 90.0;
uniform int glitter_steps : hint_range(1, 4) = 2;
// How much wave detail the GLITTER keeps after the LOD has flattened the geometry.
//
// Zero is the old behaviour, and the old behaviour was a bug you could see from the clifftop:
// the glitter path stopped dead in open water and the sea beyond it was a flat blue sheet. The
// distance envelope exists to stop geometry and per-pixel detail from aliasing, and past
// detail_far it takes the normals to exactly (0,1,0) - so a specular sharp enough to fleck off
// wave faces finds nothing at all to fleck off. Costing nothing to fix, because wave_slope is
// linear in its amplitude: the slopes are evaluated once at full height and scaled twice.
uniform float glitter_reach : hint_range(0.0, 1.0) = 0.35;
// The lobe the glitter falls back to once the facets are smaller than a pixel. Broad, because
// that is what a sun road is at distance - you stop resolving individual wave faces and see
// one streak running to the horizon.
uniform float glitter_spread : hint_range(2.0, 60.0) = 10.0;
group_uniforms;

varying vec3 world_position;
varying float wave_activity;
varying float surface_range;

float hash(vec2 p) {
    // Polynomial hash avoids precision-sensitive sin()*large-number noise on Mobile.
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
        mix(hash(i + vec2(0, 1)), hash(i + vec2(1)), f.x), f.y);
}

// Per-pixel wave slope avoids interpolated triangle-shaped foam and lighting.
vec2 wave_slope(vec4 wave, vec2 p, float scale) {
    vec2 d = wave.xy / max(length(wave.xy), 0.0001);
    float k = TAU / max(wave.w, 0.01);
    float phase = k * dot(d, p) - sqrt(9.8 * k) * water_time() * wave_speed;
    float visible = 1.0 - smoothstep(0.5, 2.0, fwidth(phase));
    return d * max(wave.z, 0.0) * scale * cos(phase) * visible;
}

// x = distance envelope for broad waves; y = tighter envelope for shorter waves.
// z = the shoal term alone, w = the distance term alone. The glitter needs those two apart:
// it wants to ignore the DISTANCE fade while still respecting the SHOAL one, or it would put
// a sun streak on the wet sand where there is no water to glint off.
vec4 envelopes(vec2 p, vec3 eye) {
    float depth = sea_y - bed_height(p);
    float shoal = smoothstep(0.0, max(shoal_depth, 0.001), depth);
    float range = length(vec3(p.x, sea_y, p.y) - eye);
    float broad = 1.0 - smoothstep(detail_near,
        max(detail_far * 0.75, detail_near + 1.0), range);
    float detail = 1.0 - smoothstep(detail_near,
        max(detail_far, detail_near + 1.0), range);
    return vec4(shoal * broad, shoal * detail, shoal, detail);
}

float scene_view_z(vec2 uv, mat4 inv_projection) {
    float raw_depth = texture(depth_texture, uv).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
    #endif
    vec4 scene_view = inv_projection * vec4(ndc, 1.0);
    return scene_view.z / max(abs(scene_view.w), 0.000001) * sign(scene_view.w);
}

// A radial grid gets coarser with distance. Vertex displacement must disappear before a
// cell becomes wider than half its wavelength or the triangles turn waves into stepped
// concentric bands. Fragment normals remain filtered independently by screen derivatives.
float geometry_envelope(vec2 p, vec3 eye, float wavelength) {
    float depth = sea_y - bed_height(p);
    float shoal = smoothstep(0.0, max(shoal_depth, 0.001), depth);
    float range = length(p - eye.xz);
    float radial_spacing = range * max(radial_growth - 1.0, 0.001);
    float angular_spacing = range * TAU / max(radial_segments, 3.0);
    float spacing = max(radial_spacing, angular_spacing);
    float sampled = 1.0 - smoothstep(wavelength * 0.24, wavelength * 0.48, spacing);
    return shoal * sampled * wave_height;
}

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // The undeformed ocean is explicitly the sea_y plane.
    world.y = sea_y;
    vec2 p = world.xz;
    vec3 eye = CAMERA_POSITION_WORLD;
    // Prevent open-water folding at high height settings. Terrain gradients can
    // still cause local compression; keep the height map smooth at the coast.
    float q = horizontal_ratio();
    vec3 offset = vec3(0.0);
    float reach = 0.0;
    gerstner(wave_1, p, geometry_envelope(p, eye, wave_1.w), q, offset, reach);
    gerstner(wave_2, p, geometry_envelope(p, eye, wave_2.w), q, offset, reach);
    gerstner(wave_3, p, geometry_envelope(p, eye, wave_3.w), q, offset, reach);
    gerstner(wave_4, p, geometry_envelope(p, eye, wave_4.w), q, offset, reach);
    world += offset;
    world_position = world;
    VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
    wave_activity = smoothstep(0.02, 0.18, reach);
    surface_range = length(world - eye);
}

void fragment() {
    // Sample at the DISPLACED surface position, per pixel, not interpolated
    // from the undeformed vertices. Colour depth stays tied to the terrain.
    float bed = bed_height(world_position.xz);
    float thickness = world_position.y - bed;
    // How much the water thins across one pixel, and so how wide every shoreline transition
    // below has to be to land softly rather than as a hard step.
    //
    // Taken BEFORE the discard: derivatives are gathered from neighbouring pixels, and a
    // neighbour that has discarded leaves them undefined.
    float pixel_span = fwidth(thickness);
    if (thickness <= 0.0) { discard; }
    float water_depth = max(sea_y - bed, 0.0);
    float scene_z = scene_view_z(SCREEN_UV, INV_PROJECTION_MATRIX);
    float to_solid = 1000.0;
    float surface_z = (VIEW_MATRIX * vec4(world_position, 1.0)).z;
    to_solid = max(surface_z - scene_z, 0.0);
    float contact = smoothstep(0.0, max(contact_fade, 0.001), to_solid);
    // Never sharper than the pixel drawing it, or the waterline itself steps at distance.
    float edge = smoothstep(0.0, max(shore_softness, max(pixel_span, 0.001)), thickness);
    float t = clamp(water_depth / max(depth_fade, 0.001), 0.0, 1.0);
    float ramp = t;
    if (bands > 1) {
        float steps = float(bands - 1);
        float quantized = 0.0;
        float aa = max(fwidth(t), 0.0001);
        for (int i = 0; i < 7; i++) {
            if (i < bands - 1) {
                float boundary = (float(i) + 0.5) / steps;
                quantized += smoothstep(boundary - aa, boundary + aa, t) / steps;
            }
        }
        ramp = mix(t, quantized, band_strength);
    }
    // Three broad depth zones keep sand, lagoon turquoise and deep ocean distinct.
    vec3 water = mix(shallow_colour, lagoon_colour, smoothstep(0.02, 0.42, ramp));
    water = mix(water, deep_colour, smoothstep(0.34, 1.0, ramp));
    float clock = water_time();
    vec4 env = envelopes(world_position.xz, CAMERA_POSITION_WORLD);
    // Evaluated once at full amplitude and scaled after, which is exact because wave_slope is
    // linear in its scale - so the glitter gets its own, less faded, copy for free.
    vec2 broad_slope = wave_slope(wave_1, world_position.xz, 1.0)
        + wave_slope(wave_2, world_position.xz, 1.0);
    vec2 fine_slope = wave_slope(wave_3, world_position.xz, 1.0)
        + wave_slope(wave_4, world_position.xz, 1.0);
    vec2 slope = (broad_slope * env.x + fine_slope * env.y) * wave_height;
    vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
    // The surface the SUN sees. Same waves, with a floor under the distance fade so the sea
    // keeps a usable normal out to the horizon. The shading normal above stays fully faded:
    // letting it ripple at distance is what the LOD was protecting the refraction and fresnel
    // from in the first place.
    float lit_reach = max(env.w, glitter_reach);
    vec2 lit_slope = (broad_slope * env.z * lit_reach
        + fine_slope * env.z * lit_reach) * wave_height;
    vec3 lit_n = normalize(vec3(-lit_slope.x, 1.0, -lit_slope.y));
    // One deformed breaker with organic trailing strands. These are band-passed noise
    // contours, not cells, so the foam cannot be confused with seabed caustics.
    vec2 slow_flow = vec2(clock * foam_speed * 0.045,
        -clock * foam_speed * 0.030);
    float broad = noise(world_position.xz * 0.20 + slow_flow);
    broad = broad * 0.68 + noise(world_position.xz * 0.43
        - slow_flow * 0.72 + vec2(11.7, -4.2)) * 0.32;
    float detail = noise(world_position.xz * 0.82
        + vec2(-clock * 0.034, clock * 0.026));
    detail = detail * 0.70 + noise(world_position.xz * 1.67
        + vec2(clock * 0.021, -clock * 0.039) + vec2(3.1, 8.6)) * 0.30;
    // The upper clamp here used to be 0.035, and that was the white outline.
    //
    // Close to the camera a pixel spans a centimetre of beach and 0.035 is plenty. Two
    // hundred metres out, at a grazing angle, a pixel spans METRES of it - so every
    // smoothstep below was transitioning over a range far narrower than the pixel drawing
    // it, and a band that should have been soft resolved as a single hard white line. It
    // traced the waterline round every shore, every pond and every rock standing in the
    // sea, which is what read as distant objects being outlined.
    float foam_aa = max(pixel_span, 0.006);
    // Widening the transition is only half of it. Once the foam band is narrower than the
    // pixel it is drawn in, it should also LOSE contrast - a pixel covering a metre of beach
    // with four centimetres of surf in it is mostly water. Without this the band keeps full
    // white however little of the pixel it really occupies, and crawls as the camera moves.
    float foam_resolve = clamp(0.045 / max(pixel_span, 0.0001), 0.0, 1.0);
    float shore_only = 1.0 - smoothstep(0.48, 0.92, water_depth);

    float advance = 0.14 + 0.075 * (0.5 + 0.5 * sin(
        clock * foam_speed * 2.0 + broad * TAU));
    float distorted_depth = thickness - advance
        + (broad - 0.5) * 0.16 + (detail - 0.5) * 0.045;
    float breaker_width = mix(0.014, 0.034, detail);
    float breaker = 1.0 - smoothstep(breaker_width,
        breaker_width + foam_aa, abs(distorted_depth));
    breaker *= mix(0.12, 1.0, smoothstep(0.30, 0.70,
        broad * 0.62 + detail * 0.38));

    // Short secondary wash lines follow the same depth contours as the coast. Independent
    // warping and hard breakup keep them as torn fragments instead of global sine ribbons.
    float wash_shape_1 = noise(world_position.xz * 0.31
        + vec2(-clock * 0.019, clock * 0.027) + vec2(9.4, 2.7));
    float wash_mask_1 = noise(world_position.xz * 0.69
        + vec2(clock * 0.031, clock * 0.014) + vec2(-3.2, 7.6));
    float wash_distance_1 = distorted_depth - 0.13 - (wash_shape_1 - 0.5) * 0.085;
    float wash_1 = 1.0 - smoothstep(0.012, 0.026 + foam_aa,
        abs(wash_distance_1));
    wash_1 *= smoothstep(0.53, 0.69, wash_mask_1);

    float wash_shape_2 = noise(world_position.xz * 0.24
        + vec2(clock * 0.014, -clock * 0.022) + vec2(4.8, -8.1));
    float wash_mask_2 = noise(world_position.xz * 0.57
        + vec2(-clock * 0.023, clock * 0.018) + vec2(13.1, 5.3));
    float wash_distance_2 = distorted_depth - 0.27 - (wash_shape_2 - 0.5) * 0.12;
    float wash_2 = 1.0 - smoothstep(0.010, 0.023 + foam_aa,
        abs(wash_distance_2));
    wash_2 *= smoothstep(0.61, 0.76, wash_mask_2);
    float strands = max(wash_1 * 0.42, wash_2 * 0.25);

    float landward_window = smoothstep(-0.13, -0.045, distorted_depth)
        * (1.0 - smoothstep(-0.025, 0.018, distorted_depth));
    float remnants = landward_window * smoothstep(0.68, 0.82, detail);
    float surf = max(breaker * 0.82, max(strands, remnants * 0.24));
    surf *= shore_only * step(0.001, foam_depth) * foam_resolve;
	// Only the dedicated overhead camera supplies object silhouettes. Gameplay-camera depth
	// must never create outlines: that would rim dry objects merely seen against the ocean.
	vec2 band_uv = (world_position.xz - band_mask_center) / max(band_mask_size, 0.001) + 0.5;
	float capture_edge = smoothstep(0.0, 0.035, min(min(band_uv.x, band_uv.y),
		min(1.0 - band_uv.x, 1.0 - band_uv.y)));
	float moving_noise = noise(world_position.xz * 0.82
		+ vec2(clock * object_band_speed * 0.19, -clock * object_band_speed * 0.14));
	float object_band = 0.0;
	if (band_mask_ready && capture_edge > 0.0) {
		float centre_mask = textureLod(band_mask, band_uv, 0.0).a;
		float metres_per_texel = band_mask_size * band_mask_texel.x;
		float radius_metres = object_band_distance + object_band_width
			+ (moving_noise - 0.5) * object_band_distortion * 0.35
			+ sin(clock * object_band_speed * 1.7) * 0.035;
		float radius_texels = max(radius_metres / max(metres_per_texel, 0.001), 1.0);
		float nearby_mask = 0.0;
		for (int i = 0; i < 8; i++) {
			float angle = TAU * float(i) / 8.0 + moving_noise * 0.12;
			vec2 offset = vec2(cos(angle), sin(angle))
				* band_mask_texel * radius_texels;
			nearby_mask = max(nearby_mask,
				textureLod(band_mask, clamp(band_uv + offset, vec2(0.0), vec2(1.0)), 0.0).a);
		}
		object_band = smoothstep(0.04, 0.45, nearby_mask - centre_mask)
			* capture_edge * smoothstep(0.12, 0.45, water_depth);
		object_band *= mix(0.72, 1.0, moving_noise);
	}
    // Crest glints follow the dominant swell, but crossing waves and slow noise bend its
    // phase before thresholding. This produces short curved strokes instead of dashed
    // straight lines that reveal the underlying sine wave.
    vec2 crest_p = world_position.xz;
    vec2 d1 = wave_1.xy / max(length(wave_1.xy), 0.0001);
    vec2 d2 = wave_2.xy / max(length(wave_2.xy), 0.0001);
    vec2 d3 = wave_3.xy / max(length(wave_3.xy), 0.0001);
    float k1 = TAU / max(wave_1.w, 0.01);
    float k2 = TAU / max(wave_2.w, 0.01);
    float k3 = TAU / max(wave_3.w, 0.01);
    float phase1 = k1 * dot(d1, crest_p) - sqrt(9.8 * k1) * clock * wave_speed;
    float phase2 = k2 * dot(d2, crest_p) - sqrt(9.8 * k2) * clock * wave_speed;
    float phase3 = k3 * dot(d3, crest_p) - sqrt(9.8 * k3) * clock * wave_speed;
    float warp = (noise(crest_p * 0.065 + vec2(clock * 0.015, -clock * 0.011)) - 0.5) * 2.4;
    warp += sin(phase2) * 0.72 + sin(phase3) * 0.28;
    float crest = smoothstep(0.94, 0.995, sin(phase1 + warp));
    float crest_breakup = noise(crest_p * 0.21 + vec2(-clock * 0.025, clock * 0.018));
    crest_breakup = crest_breakup * 0.65 + noise(crest_p * 0.47 + vec2(7.3, -2.8)) * 0.35;
    crest *= smoothstep(0.58, 0.76, crest_breakup);
    crest *= crest_strength * smoothstep(1.5, 4.0, water_depth) * wave_activity;
    crest *= 1.0 - smoothstep(55.0, 150.0, surface_range);
    float white = clamp(max(crest, surf), 0.0, 1.0);
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    float lambert = max(dot(n, light_dir), 0.0);
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
    float fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 5.0);
	// Refract the already-rendered opaque scene. Fade distortion at contacts so foreground
	// silhouettes do not bleed into the water, and keep the effect restrained for the toon look.
	vec3 view_normal = normalize(mat3(VIEW_MATRIX) * n);
	float refraction_amount = refraction_strength
		* (1.0 - exp(-water_depth / max(refraction_depth, 0.001)))
		* smoothstep(0.12, 0.8, to_solid) * (1.0 - fresnel);
	vec2 refracted_uv = clamp(SCREEN_UV + view_normal.xy * refraction_amount,
		vec2(0.001), vec2(0.999));
	// Screen-space refraction must not step across a foreground silhouette. If the offset
	// lands on a character or prop that is closer than the opaque surface behind this water
	// pixel, fall back to the original UV instead of dragging a bright halo into the sea.
	float refracted_scene_z = scene_view_z(refracted_uv, INV_PROJECTION_MATRIX);
	float foreground_gap = refracted_scene_z - scene_z;
	float refraction_valid = 1.0 - smoothstep(0.02, 0.35, foreground_gap);
	refracted_uv = mix(SCREEN_UV, refracted_uv, refraction_valid);
	vec3 scene_colour = textureLod(screen_texture, refracted_uv, 0.0).rgb;
	// The view-space depth difference is the optical path through the water. Per-channel
	// absorption creates clear turquoise shallows and blue depths without a milky alpha wash.
	float optical_depth = min(max(to_solid, 0.0), max(depth_fade, 0.001) * 2.0);
	vec3 transmittance = exp(-max(absorption, vec3(0.0))
		* absorption_strength * optical_depth);
	vec3 water_scatter = water * max(0.0,
		1.0 + (lambert - max(light_dir.y, 0.0)) * wave_shading);
	vec3 scatter_amount = max(vec3(1.0) - transmittance, vec3(0.045));
	vec3 shaded_water = scene_colour * transmittance
		+ water_scatter * scatter_amount * scattering_strength;
    // A broad restrained sky reflection at grazing angles.
    shaded_water = mix(shaded_water, vec3(0.36, 0.61, 0.70), fresnel * 0.30);

    // Sun glitter. Half-vector specular off the wave normals, then quantised, so it breaks
    // into flecks along the wave faces pointing at the sun instead of one smooth sheen.
    vec3 half_dir = normalize(light_dir + view_dir);
    // Sharp near, broad far. wave_slope drops any wave whose phase turns faster than a pixel,
    // so far enough out the facets go anyway however high the floor is - and the honest thing
    // to draw there is one smooth streak rather than a field of aliasing specks.
    float sharpness = mix(glitter_spread, glitter_sharpness, env.w);
    float spec = pow(max(dot(lit_n, half_dir), 0.0), sharpness);
    float glitter = floor(clamp(spec, 0.0, 1.0) * float(glitter_steps) + 0.4)
        / float(glitter_steps);
    // Only where the sun is actually above the horizon, or a sunk sun still lights the sea.
    glitter *= step(0.02, light_dir.y);
    shaded_water = mix(shaded_water, glitter_colour, glitter * glitter_strength);
	vec3 banded_water = mix(shaded_water, object_band_colour,
		object_band * object_band_strength);
	ALBEDO = mix(banded_water, foam_colour, white);
	float band_opacity = object_band * object_band_strength;
	// The shader already contains the transmitted scene colour, so it composites opaquely
	// except at the shoreline. Foam and contact bands remain visible at the depth boundary.
	ALPHA = edge * max(contact, max(white, band_opacity * 0.82));
    if (palette_preview) {
        ALBEDO = water;
        ALPHA = 1.0;
    }
}
