shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Mobile-compatible transparent water. Depth colour uses the shared heightmap;
// contact uses reverse-Z scene depth. Surface detail is evaluated per pixel.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform float terrain_size = 620.0;
uniform float terrain_scale = 180.0;
uniform vec2 terrain_center = vec2(0.0);
uniform float terrain_base_y = 0.0;
uniform float sea_y = 18.0;
uniform float preview_time = -1.0; // Fixed time for repeatable material captures.

group_uniforms Colour;
uniform vec3 shallow_colour : source_color = vec3(0.15, 0.78, 0.76);
uniform vec3 lagoon_colour : source_color = vec3(0.07, 0.56, 0.65);
uniform vec3 deep_colour : source_color = vec3(0.059, 0.336, 0.477);
// Keep the lagoon floor visible while deep water becomes opaque.
uniform float depth_fade : hint_range(1.0, 60.0) = 26.0;
uniform int bands : hint_range(0, 8) = 4;
uniform float band_strength : hint_range(0.0, 1.0) = 0.12;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.52;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.94;
// Opaque, unshaded colour ramp for checking colours against your swatches.
uniform bool palette_preview = false;

group_uniforms Waves;
uniform vec4 wave_1 = vec4(1.0, 0.25, 0.72, 21.0);
uniform vec4 wave_2 = vec4(-0.5, 0.9, 0.55, 12.5);
uniform vec4 wave_3 = vec4(0.75, -0.7, 0.42, 7.0);
uniform vec4 wave_4 = vec4(-0.85, -0.3, 0.30, 3.6);
uniform float wave_height : hint_range(0.0, 3.0) = 0.32;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;
uniform float shoal_depth : hint_range(0.5, 40.0) = 2.5;
// Limits horizontal compression independently of vertical wave height.
uniform float choppiness : hint_range(0.0, 1.0) = 0.85;
uniform float detail_near = 120.0;
uniform float detail_far = 900.0;

group_uniforms Foam;
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
uniform float crest_strength : hint_range(0.0, 1.0) = 0.28;
uniform float foam_depth : hint_range(0.0, 8.0) = 0.55;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.35;
uniform float shore_softness : hint_range(0.01, 0.5) = 0.06;
uniform float contact_fade : hint_range(0.01, 2.0) = 0.12;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(-0.5, 0.7, -0.5);
uniform float wave_shading : hint_range(0.0, 1.0) = 0.18;
group_uniforms;

varying vec3 world_position;
varying float wave_activity;
varying float surface_range;

float water_time() { return preview_time < 0.0 ? TIME : preview_time; }
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
// A sparse cellular lace, used only near shore rather than across the entire sea.
float foam_cells(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    float first = 8.0;
    float second = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 o = vec2(float(x), float(y));
            vec2 jitter = vec2(hash(cell + o), hash(cell + o + vec2(39.2)));
            float d = length(o + 0.2 + 0.6 * jitter - local);
            second = max(first, min(second, d));
            first = min(first, d);
        }
    }
    float border = second - first;
    float aa = max(fwidth(border), 0.005);
    return 1.0 - smoothstep(0.070, 0.070 + aa, border);
}
// Per-pixel wave slope avoids interpolated triangle-shaped foam and lighting.
vec2 wave_slope(vec4 wave, vec2 p, float scale) {
    vec2 d = wave.xy / max(length(wave.xy), 0.0001);
    float k = TAU / max(wave.w, 0.01);
    float phase = k * dot(d, p) - sqrt(9.8 * k) * water_time() * wave_speed;
    float visible = 1.0 - smoothstep(0.5, 2.0, fwidth(phase));
    return d * max(wave.z, 0.0) * scale * cos(phase) * visible;
}

float bed_height(vec2 p) {
    vec2 uv = (p - terrain_center) / max(terrain_size, 0.001) + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
        return sea_y - 1000.0;
    }
    return terrain_base_y + textureLod(terrain_height, uv, 0.0).r * terrain_scale;
}

// x = shoaling envelope; y = distance envelope for the shorter waves.
vec2 envelopes(vec2 p, vec3 eye) {
    float depth = sea_y - bed_height(p);
    float shoal = smoothstep(0.0, max(shoal_depth, 0.001), depth);
    float range = length(vec3(p.x, sea_y, p.y) - eye);
    float detail = 1.0 - smoothstep(detail_near, max(detail_far, detail_near + 1.0), range);
    return vec2(shoal, shoal * detail);
}

// Displace geometry with Gerstner waves. Shading is evaluated independently per pixel.
void gerstner(vec4 wave, vec2 p, float scale, float horizontal_ratio,
        inout vec3 offset, inout float reach) {
    float dir_length = length(wave.xy);
    vec2 d = wave.xy / max(dir_length, 0.0001);
    float steepness = max(wave.z, 0.0) * step(0.0001, dir_length);
    float k = TAU / max(wave.w, 0.01);
    float phase = k * dot(d, p) - sqrt(9.8 * k) * water_time() * wave_speed;
    float a = steepness / k * scale;
    offset += a * vec3(horizontal_ratio * d.x * cos(phase), sin(phase), horizontal_ratio * d.y * cos(phase));
    reach += a;
}

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // The undeformed ocean is explicitly the sea_y plane.
    world.y = sea_y;
    vec2 p = world.xz;
    vec3 eye = CAMERA_POSITION_WORLD;
    vec2 env = envelopes(p, eye) * wave_height;
    float total_steepness = max(wave_1.z, 0.0) + max(wave_2.z, 0.0) + max(wave_3.z, 0.0) + max(wave_4.z, 0.0);
    // Prevent open-water folding at high height settings. Terrain gradients can
    // still cause local compression; keep the height map smooth at the coast.
    float q = choppiness / max(1.0, total_steepness * wave_height);
    vec3 offset = vec3(0.0);
    float reach = 0.0;
    gerstner(wave_1, p, env.x, q, offset, reach);
    gerstner(wave_2, p, env.x, q, offset, reach);
    gerstner(wave_3, p, env.y, q, offset, reach);
    gerstner(wave_4, p, env.y, q, offset, reach);
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
    if (thickness <= 0.0) { discard; }
    float water_depth = max(sea_y - bed, 0.0);
    float raw = texture(depth_texture, SCREEN_UV).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
    #endif
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    float to_solid = 1000.0;
    if (abs(scene_view.w) > 0.000001) {
        float surface_z = (VIEW_MATRIX * vec4(world_position, 1.0)).z;
        to_solid = max(surface_z - scene_view.z / scene_view.w, 0.0);
    }
    float contact = smoothstep(0.0, max(contact_fade, 0.001), to_solid);
    float edge = smoothstep(0.0, max(shore_softness, 0.001), thickness);
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
    vec2 env = envelopes(world_position.xz, CAMERA_POSITION_WORLD) * wave_height;
    vec2 slope = wave_slope(wave_1, world_position.xz, env.x)
        + wave_slope(wave_2, world_position.xz, env.x)
        + wave_slope(wave_3, world_position.xz, env.y)
        + wave_slope(wave_4, world_position.xz, env.y);
    vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
    // Foam is tied to shallow water, with broken edges and open cells behind them.
    vec2 foam_uv = world_position.xz * 1.15;
    foam_uv += vec2(sin(world_position.z * 0.6 + clock * foam_speed),
        cos(world_position.x * 0.5 - clock * foam_speed)) * 0.22;
    foam_uv += 0.30 * sin(foam_uv.yx * 2.8 + vec2(clock * 0.13));
    float lace = foam_cells(foam_uv);
    float breakup = noise(world_position.xz * 0.8 + vec2(clock * foam_speed * 0.12));
    float shore_break = noise(world_position.xz * 0.31 + vec2(-clock * 0.025, clock * 0.018));
    float surge = max(foam_depth, 0.001) * (0.78 + breakup * 0.50 + 0.12 * sin(clock * foam_speed * TAU));
    float surf_zone = 1.0 - smoothstep(surge * 0.15, surge, thickness);
    float leading = 1.0 - smoothstep(0.018, 0.095 + breakup * 0.10, thickness);
    float leading_breakup = smoothstep(0.36, 0.62, mix(breakup, shore_break, 0.46));
    float surf = max(leading * leading_breakup, lace * surf_zone * smoothstep(0.28, 0.58, breakup));
    surf *= step(0.001, foam_depth);
    // Quiet, world-space glints replace the wide interpolated crest ribbons.
    vec2 d = wave_1.xy / max(length(wave_1.xy), 0.0001);
    float k = TAU / max(wave_1.w, 0.01);
    float phase = k * dot(d, world_position.xz) - sqrt(9.8 * k) * clock * wave_speed;
    float crest = smoothstep(0.965, 0.995, sin(phase));
    crest *= smoothstep(0.56, 0.76, noise(world_position.xz * 0.23));
    crest *= crest_strength * smoothstep(1.5, 4.0, water_depth) * wave_activity;
    crest *= 1.0 - smoothstep(80.0, 220.0, surface_range);
    float white = clamp(max(crest, surf), 0.0, 1.0);
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    float lambert = max(dot(n, light_dir), 0.0);
    vec3 shaded_water = water * max(0.0, 1.0 + (lambert - max(light_dir.y, 0.0)) * wave_shading);
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
    float fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 5.0);
    // A broad restrained sky reflection; shallow water stays clear from overhead.
    shaded_water = mix(shaded_water, vec3(0.36, 0.61, 0.70), fresnel * 0.30);
    ALBEDO = mix(shaded_water, foam_colour, white);
    float opacity = mix(shallow_alpha, deep_alpha, smoothstep(0.0, 1.0, t));
    opacity = mix(opacity, max(opacity, 0.75), fresnel * 0.65);
    ALPHA = mix(opacity, 1.0, white) * edge * contact;
    if (palette_preview) {
        ALBEDO = water;
        ALPHA = 1.0;
    }
}
