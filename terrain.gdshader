shader_type spatial;
render_mode ambient_light_disabled, specular_disabled, fog_disabled;

// Opaque toon ground with real shadow reception. No terrain displacement.
// Ambient colour is explicit so the palette stays consistent on Mobile.

group_uniforms Shading;
uniform int bands : hint_range(2, 6) = 3;
uniform float band_softness : hint_range(0.0, 0.3) = 0.06;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.40;
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.52, 0.62);
uniform float shadow_tint_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec3 sun_direction = vec3(-0.5, 0.7, -0.5);
uniform float ambient : hint_range(0.0, 1.0) = 0.16;
// Full-light threshold; level ground under the default sun retains its palette.
uniform float lit_threshold : hint_range(0.1, 1.0) = 0.70;
uniform bool palette_preview = false;

group_uniforms Ground;
// Sandy seabed stays distinct from the water tint above it.
uniform vec3 seabed_colour : source_color = vec3(0.720, 0.660, 0.480);
uniform vec3 seabed_weed : source_color = vec3(0.300, 0.460, 0.360);
uniform vec3 wet_sand_colour : source_color = vec3(0.678, 0.518, 0.384);
uniform vec3 dry_sand_colour : source_color = vec3(0.910, 0.749, 0.529);
uniform vec3 grass_colour : source_color = vec3(0.498, 0.525, 0.220);
uniform vec3 jungle_colour : source_color = vec3(0.149, 0.235, 0.173);
uniform float sea_y = 18.0;
uniform float preview_time = -1.0; // Negative uses live animation.
uniform float wet_sand_top : hint_range(0.0, 6.0) = 0.85;
uniform float dry_sand_top : hint_range(0.0, 20.0) = 3.5;
// Jungle transition height scale; never forces rock on flat hilltops.
uniform float grass_top : hint_range(0.0, 80.0) = 40.0;
uniform float edge_break : hint_range(0.0, 8.0) = 2.0;
uniform float patch_scale : hint_range(0.001, 0.5) = 0.11;
uniform float seabed_patch_scale : hint_range(0.01, 1.0) = 0.16;
uniform float vegetation_blend : hint_range(0.05, 6.0) = 1.0;
uniform float jungle_coverage : hint_range(0.0, 1.0) = 0.55;

group_uniforms Caustics;
uniform vec3 caustic_colour : source_color = vec3(0.82, 1.0, 0.86);
uniform float caustic_scale : hint_range(0.02, 4.0) = 0.90;
// Width now measures distance to a cell edge in pattern space.
uniform float caustic_width : hint_range(0.01, 0.8) = 0.018;
uniform float caustic_strength : hint_range(0.0, 2.0) = 1.1;
uniform float caustic_reach : hint_range(0.5, 30.0) = 12.0;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.30;
uniform float caustic_distance_fade : hint_range(10.0, 400.0) = 320.0;
// Pattern-space pixel size at which the web starts to fade for want of resolution.
uniform float caustic_footprint_fade : hint_range(0.05, 4.0) = 1.2;

group_uniforms Cliffs;
uniform vec3 rock_colour : source_color = vec3(0.38, 0.34, 0.30);
uniform float rock_begins : hint_range(0.0, 1.0) = 0.45;
uniform float rock_full : hint_range(0.0, 1.0) = 0.72;
uniform float rock_edge_break : hint_range(0.0, 0.2) = 0.04;

group_uniforms WetSand;
uniform vec3 sheen_colour : source_color = vec3(0.90, 0.96, 1.0);
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.12;
uniform float sheen_power : hint_range(2.0, 128.0) = 40.0;

group_uniforms Rim;
uniform vec3 rim_colour : source_color = vec3(1.0, 0.96, 0.82);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.06;
group_uniforms;

varying vec3 world_normal;
varying vec3 world_position;
varying vec3 caustic_light;

float hash(vec2 p) {
    // Polynomial hash avoids precision-sensitive sin()*large-number noise on Mobile.
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
const mat2 TURN = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// Normalized, with unresolved octaves fading to their mean, not to black.
// Fragment-only: derivatives are needed for the pixel footprint.
float fbm(vec2 p) {
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    float footprint = max(length(dFdx(p)), length(dFdy(p)));
    for (int i = 0; i < 4; i++) {
        float visible = 1.0 - smoothstep(0.25, 0.75, footprint);
        total += mix(0.5, value_noise(p), visible) * weight;
        weights += weight;
        p = TURN * p * 2.07 + vec2(11.3);
        footprint *= 2.07;
        weight *= 0.5;
    }
    return total / weights;
}
vec2 cell_hash(vec2 p) {
    return vec2(hash(p), hash(p + vec2(19.7, 73.1)));
}
vec2 cell_point(vec2 cell, float t) {
    // Restricted jitter avoids extreme skinny cells and bounds the search.
    return vec2(0.5) + 0.28 * sin(vec2(t) + TAU * cell_hash(cell));
}
// Actual distance to Voronoi bisectors; F2-F1 alone is not edge distance.
float cell_border(vec2 p, float t) {
    p += (vec2(value_noise(p * 0.30 + vec2(t * 0.04)),
        value_noise(p * 0.30 + vec2(4.7 - t * 0.035))) - vec2(0.5)) * 0.6;
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 nearest_offset = vec2(0.0);
    vec2 nearest_vector = vec2(0.0);
    float nearest_squared = 100.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 o = vec2(float(x), float(y));
            vec2 r = o + cell_point(cell + o, t) - local;
            float squared = dot(r, r);
            if (squared < nearest_squared) {
                nearest_squared = squared;
                nearest_offset = o;
                nearest_vector = r;
            }
        }
    }
    float border = 100.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 o = nearest_offset + vec2(float(x), float(y));
            vec2 r = o + cell_point(cell + o, t) - local;
            vec2 delta = r - nearest_vector;
            float squared = dot(delta, delta);
            if (squared > 0.00001) {
                border = min(border, dot(0.5 * (nearest_vector + r), delta * inversesqrt(squared)));
            }
        }
    }
    return max(border, 0.0);
}
float toon_ramp(float x) {
    int count = clamp(bands, 2, 6);
    float intervals = float(count - 1);
    float aa = max(fwidth(x), 0.0001);
    float softness = max(band_softness / intervals, aa);
    float result = 0.0;
    for (int i = 0; i < 5; i++) {
        if (i < count - 1) {
            float boundary = (float(i) + 0.5) / intervals;
            result += smoothstep(boundary - softness, boundary + softness, x) / intervals;
        }
    }
    return clamp(result, 0.0, 1.0);
}
void vertex() {
    // Inverse-transpose handles non-uniform mesh scale correctly.
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float clock = preview_time < 0.0 ? TIME : preview_time;
    vec3 n = normalize(world_normal);
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
    float height = world_position.y - sea_y;
    float depth = max(-height, 0.0);
    float patches = fbm(world_position.xz * patch_scale);
    float edge_patches = fbm(world_position.xz * 0.65);
    float vegetation_height = height + (patches - 0.5) * edge_break + (edge_patches - 0.5) * 0.65;
    float slope = 1.0 - clamp(n.y, 0.0, 1.0);

    // Waterline transitions use real height, never noisy vegetation height.
    float submerged = 1.0 - smoothstep(-0.45, 0.0, height);
    float dry = smoothstep(0.0, max(wet_sand_top, 0.01), height);
    vec3 sand = mix(wet_sand_colour, dry_sand_colour, dry);
    float weed = smoothstep(0.48, 0.72, fbm(world_position.xz * seabed_patch_scale));
    weed *= smoothstep(0.1, 0.7, depth);
    vec3 bottom = mix(seabed_colour, seabed_weed, weed);
    // Red light falls off first underwater; keep warm sand at the very edge.
    bottom *= mix(vec3(1.0), vec3(0.38, 0.86, 0.78), smoothstep(0.0, 7.0, depth));
    vec3 ground = mix(sand, bottom, submerged);

    // Height is only a procedural fallback for vegetation, not a canopy map.
    float vegetation = smoothstep(dry_sand_top - vegetation_blend,
        dry_sand_top + max(vegetation_blend, 0.01), vegetation_height);
    vegetation *= smoothstep(max(wet_sand_top, 0.01), max(wet_sand_top, 0.01) + 0.5, height);
    float jungle_patch = smoothstep(0.40, 0.65, fbm(world_position.xz * patch_scale * 2.6));
    float jungle = jungle_patch * jungle_coverage * smoothstep(dry_sand_top,
        max(dry_sand_top + 0.01, grass_top * 0.35), vegetation_height);
    ground = mix(ground, mix(grass_colour, jungle_colour, jungle), vegetation);

    // No altitude override. Hilltops remain vegetated if they are flat.
    float rock_slope = slope + (patches - 0.5) * rock_edge_break;
    float rock = smoothstep(rock_begins, max(rock_full, rock_begins + 0.001), rock_slope);
    ground = mix(ground, rock_colour, rock);

    float ndotl = max(dot(n, light_dir), 0.0);
    // Restrained broad patches instead of uniform biome fills or fine texture noise.
    float patch_band = smoothstep(0.42, 0.48, patches) + smoothstep(0.57, 0.63, patches);
    ground *= 0.95 + 0.045 * patch_band;
    vec3 colour = ground;

    // A restrained wet-sand sheen, lit by the same sun as the cast shadows.
    float wet = (1.0 - dry) * smoothstep(-0.04, 0.02, height) * (1.0 - rock) * (1.0 - vegetation);
    vec3 half_sum = light_dir + view_dir;
    vec3 half_dir = half_sum / max(length(half_sum), 0.0001);
    float spec = pow(max(dot(n, half_dir), 0.0), sheen_power) * ndotl;
    colour = mix(colour, sheen_colour, clamp(wet * spec * sheen_strength, 0.0, 1.0));

    // One broad, irregular web at gameplay distance. Evaluate derivatives
    // outside depth-dependent branches to keep shoreline antialiasing defined.
    vec2 caustic_uv = world_position.xz * caustic_scale;
    caustic_uv += 0.32 * sin(caustic_uv.yx * 3.1 + vec2(clock * 0.24, -clock * 0.19));
    float border = cell_border(caustic_uv, clock * caustic_speed);
    float footprint = max(length(dFdx(caustic_uv)), length(dFdy(caustic_uv)));
    float aa = max(fwidth(border), 0.0001);
    float width = max(caustic_width, 0.001) * mix(0.55, 1.35, value_noise(caustic_uv * 1.4));
    float web = 1.0 - smoothstep(width, width + aa, border);
    web = web * 0.85 + exp(-border / max(width * 3.0, 0.001)) * 0.15;
    web *= width / max(width, aa);
    // Fade only where the web is genuinely under-sampled. At a grazing angle - standing on
    // the beach looking out, which is where anyone looks at caustics - one pixel covers
    // metres of seabed, so a 0.75 cutoff zeroes them exactly there.
    web *= 1.0 - smoothstep(caustic_footprint_fade, caustic_footprint_fade * 3.0, footprint);
    web *= mix(0.35, 1.0, value_noise(world_position.xz * 0.13 + vec2(clock * caustic_speed * 0.04)));
    web *= smoothstep(0.02, 0.18, depth);
    web *= 1.0 - smoothstep(0.25, max(caustic_reach, 0.26), depth);
    web *= 1.0 - smoothstep(caustic_distance_fade * 0.5, max(caustic_distance_fade, 0.01), length(world_position - CAMERA_POSITION_WORLD));
    web *= smoothstep(0.15, 0.8, n.y) * ndotl * caustic_strength;
    // Add light after shading, including on submerged rock. Bounded so it
    // cannot clip above one or darken an already bright surface.
    caustic_light = (vec3(1.0) - colour) * caustic_colour * clamp(web, 0.0, 1.0);

    float facing = clamp(dot(n, view_dir), 0.0, 1.0);
    float rim = pow(1.0 - facing, rim_power) * rim_strength;
    rim *= smoothstep(0.30, 0.75, slope) * smoothstep(0.0, 0.4, height) * ndotl;
    colour = mix(colour, rim_colour, clamp(rim, 0.0, 1.0));
    ALBEDO = colour;
    NORMAL = normalize(mat3(VIEW_MATRIX) * n);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    vec3 fill = mix(vec3(1.0), shadow_tint, shadow_tint_strength) * shadow_floor;
    EMISSION = colour * fill;
    if (palette_preview) { ALBEDO = ground; EMISSION = ground; }
}

// Keep banding on face lighting; retain the filtered silhouette of the shadow map.
void light() {
    if (!palette_preview) {
        float level = clamp(max(dot(NORMAL, LIGHT), 0.0) / max(lit_threshold, 0.001), 0.0, 1.0);
        float toon = toon_ramp(mix(level, 1.0, ambient));
        vec3 fill = mix(vec3(1.0), shadow_tint, shadow_tint_strength) * shadow_floor;
        DIFFUSE_LIGHT += (vec3(1.0) - fill) * toon * ATTENUATION * LIGHT_COLOR / PI;
        if (LIGHT_IS_DIRECTIONAL) {
            DIFFUSE_LIGHT += caustic_light / max(ALBEDO, vec3(0.02)) * ATTENUATION * LIGHT_COLOR / PI;
        }
    }
}
