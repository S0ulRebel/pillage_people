shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Godot 4.3+. Above-water material; bind the same linear height map as the terrain.
// Terrain mapping assumes an axis-aligned square. Units below are world metres.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform float terrain_size = 620.0;
uniform float terrain_scale = 180.0;
uniform vec2 terrain_center = vec2(0.0);
uniform float terrain_base_y = 0.0;
uniform float sea_y = 18.0;

group_uniforms Colour;
// Preserved from the supplied code, not newly sampled from the reference.
uniform vec3 shallow_colour : source_color = vec3(0.330, 0.870, 0.800);
uniform vec3 deep_colour : source_color = vec3(0.059, 0.336, 0.477);
// Over how many metres the water reaches its deep colour and its deep opacity. At 8.5 the
// lagoon floor at 5-12 m was already fully opaque, so the seabed and its caustics were
// hidden whatever colour they were - the seabed could be changed from teal to sand with no
// measurable difference in the render.
uniform float depth_fade : hint_range(1.0, 60.0) = 26.0;
uniform int bands : hint_range(0, 8) = 4;
uniform float band_strength : hint_range(0.0, 1.0) = 0.45;
// More body than the original 0.26; lower this to expose more seabed/caustics.
// The seabed carries the caustics, so every point of opacity here is contrast taken off
// them. Measured against the reference crop: at 0.65 the web was invisible from the shore.
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.40;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.88;
// Opaque, unshaded colour ramp for checking colours against your swatches.
uniform bool palette_preview = false;

group_uniforms Waves;
uniform vec4 wave_1 = vec4(1.0, 0.25, 0.72, 21.0);
uniform vec4 wave_2 = vec4(-0.5, 0.9, 0.55, 12.5);
uniform vec4 wave_3 = vec4(0.75, -0.7, 0.42, 7.0);
uniform vec4 wave_4 = vec4(-0.85, -0.3, 0.30, 3.6);
uniform float wave_height : hint_range(0.0, 3.0) = 0.5;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;
uniform float shoal_depth : hint_range(0.5, 40.0) = 2.5;
// Limits horizontal compression independently of vertical wave height.
uniform float choppiness : hint_range(0.0, 1.0) = 0.85;
uniform float detail_near = 120.0;
uniform float detail_far = 900.0;

group_uniforms Foam;
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
uniform float crest_fold : hint_range(0.0, 1.5) = 0.62;
uniform float crest_sharpness : hint_range(0.01, 1.0) = 0.22;
uniform float crest_line_height : hint_range(0.0, 1.0) = 0.72;
uniform float crest_line_width : hint_range(0.001, 0.5) = 0.018;
uniform float crest_strength : hint_range(0.0, 1.0) = 0.75;
uniform float foam_depth : hint_range(0.0, 8.0) = 0.35;
uniform float foam_speed : hint_range(0.0, 2.0) = 0.35;
uniform float shore_softness : hint_range(0.01, 0.5) = 0.06;
uniform float contact_fade : hint_range(0.01, 2.0) = 0.12;

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(-0.5, 0.7, -0.5);
uniform float wave_shading : hint_range(0.0, 1.0) = 0.18;
group_uniforms;

varying vec3 world_position;
varying vec3 wave_normal;
varying float fold;
varying float crest_rise;
varying float wave_activity;
varying float surface_range;

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

// Derivatives match the actual displacement, including envelope gradients.
// Horizontal Jacobian uses FIRST derivatives, not second derivatives.
void gerstner(vec4 wave, vec2 p, float scale, vec2 scale_gradient,
        float horizontal_ratio, inout vec3 offset, inout vec3 dx,
        inout vec3 dz, inout float reach) {
    float dir_length = length(wave.xy);
    vec2 d = wave.xy / max(dir_length, 0.0001);
    float steepness = max(wave.z, 0.0) * step(0.0001, dir_length);
    float k = TAU / max(wave.w, 0.01);
    float phase = k * dot(d, p) - sqrt(9.8 * k) * TIME * wave_speed;
    float s = sin(phase);
    float c = cos(phase);
    float base_amplitude = steepness / k;
    float a = base_amplitude * scale;
    vec3 orbit = vec3(horizontal_ratio * d.x * c, s, horizontal_ratio * d.y * c);
    vec3 phase_derivative = vec3(-horizontal_ratio * d.x * s, c, -horizontal_ratio * d.y * s);
    offset += a * orbit;
    dx += base_amplitude * scale_gradient.x * orbit + a * k * d.x * phase_derivative;
    dz += base_amplitude * scale_gradient.y * orbit + a * k * d.y * phase_derivative;
    reach += a;
}

void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // The undeformed ocean is explicitly the sea_y plane.
    world.y = sea_y;
    vec2 p = world.xz;
    vec3 eye = CAMERA_POSITION_WORLD;
    vec2 env = envelopes(p, eye) * wave_height;
    // Numerical envelope gradient, analytic wave derivatives.
    float eps = max(terrain_size / float(textureSize(terrain_height, 0).x), 0.05);
    vec2 ex = (envelopes(p + vec2(eps, 0.0), eye) - envelopes(p - vec2(eps, 0.0), eye)) * wave_height / (2.0 * eps);
    vec2 ez = (envelopes(p + vec2(0.0, eps), eye) - envelopes(p - vec2(0.0, eps), eye)) * wave_height / (2.0 * eps);
    float total_steepness = max(wave_1.z, 0.0) + max(wave_2.z, 0.0) + max(wave_3.z, 0.0) + max(wave_4.z, 0.0);
    // Prevent open-water folding at high height settings. Terrain gradients can
    // still cause local compression; keep the height map smooth at the coast.
    float q = choppiness / max(1.0, total_steepness * wave_height);
    vec3 offset = vec3(0.0);
    vec3 dx = vec3(1.0, 0.0, 0.0);
    vec3 dz = vec3(0.0, 0.0, 1.0);
    float reach = 0.0;
    gerstner(wave_1, p, env.x, vec2(ex.x, ez.x), q, offset, dx, dz, reach);
    gerstner(wave_2, p, env.x, vec2(ex.x, ez.x), q, offset, dx, dz, reach);
    gerstner(wave_3, p, env.y, vec2(ex.y, ez.y), q, offset, dx, dz, reach);
    gerstner(wave_4, p, env.y, vec2(ex.y, ez.y), q, offset, dx, dz, reach);
    world += offset;
    world_position = world;
    VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
    // Keep custom lighting in world space; do not assign this to local NORMAL.
    wave_normal = normalize(cross(dz, dx));
    fold = dx.x * dz.z - dz.x * dx.z;
    crest_rise = clamp(0.5 + 0.5 * offset.y / max(reach, 0.0001), 0.0, 1.0);
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
    vec3 water = mix(shallow_colour, deep_colour, ramp);
    // Always use increasing smoothstep edges.
    float breaking = 1.0 - smoothstep(crest_fold - max(crest_sharpness, 0.001), crest_fold, fold);
    breaking *= smoothstep(0.60, 0.85, crest_rise);
    float width = max(crest_line_width, 0.001);
    float aa = max(fwidth(crest_rise), 0.001);
    float line = 1.0 - smoothstep(width, width + aa, abs(crest_rise - crest_line_height));
    // Sparse, broad interruptions along the streaks, not high-frequency noise.
    float breakup = 0.5 + 0.5 * sin(dot(world_position.xz, vec2(0.47, 0.31)) + sin(dot(world_position.xz, vec2(-0.19, 0.38))) + TIME * 0.2 * wave_speed);
    line *= smoothstep(0.35, 0.70, breakup);
    line *= 1.0 - smoothstep(100.0, 350.0, surface_range);
    float crest = max(breaking, line * crest_strength) * wave_activity;
    // A shallow white ribbon with a moving outer edge; no foam when disabled.
    float surge = foam_depth * (0.85 + 0.15 * sin(TIME * foam_speed * TAU));
    float surf = 1.0 - smoothstep(surge * 0.35, max(surge, 0.001), thickness);
    surf *= step(0.001, foam_depth);
    float white = clamp(max(crest, surf), 0.0, 1.0);
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    float lambert = max(dot(normalize(wave_normal), light_dir), 0.0);
    float flat_lambert = max(light_dir.y, 0.0);
    vec3 shaded_water = water * max(0.0, 1.0 + (lambert - flat_lambert) * wave_shading);
    ALBEDO = mix(shaded_water, foam_colour, white);
    ALPHA = mix(mix(shallow_alpha, deep_alpha, ramp), 1.0, white) * edge * contact;
    if (palette_preview) {
        ALBEDO = water;
        ALPHA = 1.0;
    }
}
