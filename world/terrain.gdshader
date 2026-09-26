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
// The ground carries its own fill light (the EMISSION below), because the shader turns the
// scene's ambient off. Left at full strength it glowed all night while everything around it
// went dark, so it follows the day: world/day.gd sets `daylight`, 1 by day and 0 at night, and
// at night the fill fades to a dim moonlit blue instead.
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 night_fill_tint : source_color = vec3(0.55, 0.62, 1.0);
uniform float night_fill : hint_range(0.0, 1.0) = 0.10;
uniform bool palette_preview = false;

group_uniforms Ground;
// Painted by hand (addons/biome_painter), on top of the automatic biome below: R pushes
// toward vegetation or sand, G toward or away from rock, B toward jungle or plain grass, each
// 0.5 = untouched (this point still reads the automatic answer), 0 or 1 = fully forced. terrain.gd
// always assigns a real texture, blank grey where nothing has been painted, so an unpainted
// island looks exactly as it did before this uniform existed.
uniform sampler2D biome_map : filter_linear;
// Sandy seabed stays distinct from the water tint above it.
uniform vec3 seabed_colour : source_color = vec3(0.780, 0.700, 0.500);
uniform vec3 deep_seabed_colour : source_color = vec3(0.180, 0.360, 0.330);
uniform vec3 seabed_weed : source_color = vec3(0.180, 0.400, 0.290);
uniform vec3 seabed_rock_colour : source_color = vec3(0.270, 0.390, 0.390);
uniform vec3 wet_sand_colour : source_color = vec3(0.600, 0.420, 0.285);
uniform vec3 dry_sand_colour : source_color = vec3(0.930, 0.735, 0.430);
uniform vec3 grass_colour : source_color = vec3(0.390, 0.555, 0.145);
uniform vec3 jungle_colour : source_color = vec3(0.155, 0.215, 0.105);
uniform float sea_y = 18.0;
uniform float preview_time = -1.0; // Negative uses live animation.
uniform float wet_sand_top : hint_range(0.0, 6.0) = 0.85;
uniform float dry_sand_top : hint_range(0.0, 20.0) = 3.5;
// Jungle transition height scale; never forces rock on flat hilltops.
uniform float grass_top : hint_range(0.0, 80.0) = 40.0;
uniform float edge_break : hint_range(0.0, 8.0) = 2.0;
uniform float patch_scale : hint_range(0.001, 0.5) = 0.11;
uniform float seabed_patch_scale : hint_range(0.01, 1.0) = 0.16;
uniform float vegetation_blend : hint_range(0.05, 6.0) = 0.42;
uniform float jungle_coverage : hint_range(0.0, 1.0) = 0.55;

group_uniforms Caustics;
uniform vec3 caustic_colour : source_color = vec3(0.84, 1.0, 0.92);
uniform float caustic_scale : hint_range(0.02, 4.0) = 0.90;
// Width now measures distance to a cell edge in pattern space.
uniform float caustic_width : hint_range(0.01, 0.8) = 0.012;
uniform float caustic_strength : hint_range(0.0, 2.0) = 0.64;
uniform float caustic_reach : hint_range(0.5, 30.0) = 12.0;
uniform float caustic_speed : hint_range(0.0, 2.0) = 0.30;
uniform float caustic_distance_fade : hint_range(10.0, 400.0) = 320.0;
// Pattern-space pixel size at which the web starts to fade for want of resolution.
uniform float caustic_footprint_fade : hint_range(0.05, 4.0) = 1.2;

group_uniforms Cliffs;
uniform vec3 rock_colour : source_color = vec3(0.45, 0.43, 0.46);
uniform float rock_begins : hint_range(0.0, 1.0) = 0.39;
uniform float rock_full : hint_range(0.0, 1.0) = 0.56;
uniform float rock_edge_break : hint_range(0.0, 0.2) = 0.055;

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
// The same (x/world_size+0.5, z/world_size+0.5) UV the ground mesh already carries for its own
// texture space (Terrain._build_chunk), reused here so biome_map lines up with the ground
// without a second world_size uniform to keep in step with the one terrain.gd already has.
varying vec2 ground_uv;

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
    ground_uv = UV;
}
// The light the ground gives itself where the sun does not reach: the day's tinted shadow
// floor by day, a dim moonlit blue at night.
vec3 ground_fill() {
    vec3 day_fill = mix(vec3(1.0), shadow_tint, shadow_tint_strength) * shadow_floor;
    return mix(night_fill_tint * night_fill, day_fill, daylight);
}

void fragment() {
    float clock = preview_time < 0.0 ? TIME : preview_time;
    vec3 n = normalize(world_normal);
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    vec3 view_dir = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
    float height = world_position.y - sea_y;
    float depth = max(-height, 0.0);
    // One broad field defines the coastline materials. A smaller field only roughens
    // the boundary, so distant terrain reads as large authored regions rather than noise.
    float macro = fbm(world_position.xz * patch_scale * 0.28 + vec2(17.0, -9.0));
    float patches = fbm(world_position.xz * patch_scale);
    float edge_patches = fbm(world_position.xz * 0.42);
    float coast_offset = (macro - 0.5) * edge_break + (edge_patches - 0.5) * 0.42;
    // Hand-painted push on top of the automatic biome: -1 at fully painted "away", 0 wherever
    // nothing has been painted (biome_map reads 0.5 there), +1 at fully painted "toward". Added
    // straight onto the masks below rather than replacing the final colour, so a painted patch
    // keeps the same noise texture and soft transitions as everywhere else - only which side of
    // the line it falls on is forced. Full magnitude always wins outright: each mask below is
    // already 0 to 1, so +-1 pushes it to the clamped end whatever the automatic answer was.
    vec3 biome_bias = (texture(biome_map, ground_uv).rgb - 0.5) * 2.0;
    float slope = 1.0 - clamp(n.y, 0.0, 1.0);
    // The face's own slope, from how the position changes across the pixel. The vertex normals
    // are smoothed from the height map, and on a wall narrower than the mesh's 1.2 m vertex
    // spacing - a flattened pad's edge - they read flat on some of the wall's triangles and
    // steep on others, which painted the wall in alternating green and grey wedges. So below,
    // a triangle that is itself steeper than a cliff is rock whatever its vertices say.
    vec3 face = cross(dFdx(world_position), dFdy(world_position));
    float face_slope = 1.0 - clamp(abs(face.y) / max(length(face), 0.0001), 0.0, 1.0);

    // Waterline transitions use real height, never noisy vegetation height.
    float submerged = 1.0 - smoothstep(-0.45, 0.0, height);
    float wet_edge = wet_sand_top + coast_offset * 0.16;
    float dry = smoothstep(wet_edge - 0.18, wet_edge + 0.20, height);
    vec3 sand = mix(wet_sand_colour, dry_sand_colour, dry);
    float sand_marks = smoothstep(0.58, 0.72, patches) * (1.0 - smoothstep(0.0, 0.75, abs(height - 1.8)));
    sand *= 1.0 - sand_marks * 0.055;
    float weed = smoothstep(0.48, 0.72, fbm(world_position.xz * seabed_patch_scale));
    weed *= smoothstep(0.35, 1.2, depth) * (1.0 - smoothstep(8.0, 14.0, depth));
    vec3 bottom = mix(seabed_colour, deep_seabed_colour, smoothstep(2.5, 16.0, depth));
    bottom = mix(bottom, seabed_weed, weed * 0.72);
    vec3 ground = mix(sand, bottom, submerged);

    // Graphic sand/grass contour with a few detached grass islands on the dry beach.
    float grass_line = dry_sand_top + coast_offset;
    float vegetation = smoothstep(grass_line - vegetation_blend,
        grass_line + max(vegetation_blend, 0.01), height);
    vegetation *= smoothstep(wet_sand_top + 0.18, wet_sand_top + 0.55, height);
    float grass_islands = smoothstep(0.70, 0.78, macro) * smoothstep(1.15, 2.2, height)
        * (1.0 - smoothstep(grass_line - 1.25, grass_line - 0.25, height));
    vegetation = max(vegetation, grass_islands);
    vegetation = clamp(vegetation + biome_bias.r, 0.0, 1.0);

    // Jungle floor is an inland material, not green noise scattered across the beach.
    float jungle_line = max(dry_sand_top + 2.8, grass_top * 0.22) + (macro - 0.5) * 4.0;
    float jungle_shape = smoothstep(jungle_line - 0.65, jungle_line + 0.65, height);
    float jungle_patch = smoothstep(0.46, 0.61, fbm(world_position.xz * patch_scale * 0.62 + vec2(-4.0, 12.0)));
    float jungle = jungle_shape * mix(0.55, 1.0, jungle_patch) * jungle_coverage;
    jungle = clamp(jungle + biome_bias.b, 0.0, 1.0);
    vec3 vegetation_colour = mix(grass_colour, jungle_colour, jungle);
    float grass_value = mix(0.91, 1.06, smoothstep(0.38, 0.64, patches));
    ground = mix(ground, vegetation_colour * grass_value, vegetation);

    // No altitude override. Hilltops remain vegetated if they are flat.
    float rock_slope = max(slope, face_slope) + (macro - 0.5) * rock_edge_break;
    float rock = smoothstep(rock_begins, max(rock_full, rock_begins + 0.001), rock_slope);
    rock = max(rock, smoothstep(rock_full, min(rock_full + 0.2, 1.0), face_slope));
    rock = clamp(rock + biome_bias.g, 0.0, 1.0);
    float rock_plane = dot(n.xz, normalize(vec2(0.68, -0.73))) * 0.5 + 0.5;
    rock_plane = floor(clamp(rock_plane + (macro - 0.5) * 0.25, 0.0, 0.999) * 3.0) / 2.0;
    float rock_detail = fbm(world_position.xz * 0.045 + vec2(height * 0.035, -height * 0.025));
    rock_detail = floor(clamp(rock_detail, 0.0, 0.999) * 3.0) / 2.0;
    vec3 rock_base = mix(rock_colour, seabed_rock_colour, submerged);
    vec3 cliff = rock_base * mix(0.78, 1.15, rock_plane) * mix(0.88, 1.10, rock_detail);
    ground = mix(ground, cliff, rock);

    float ndotl = max(dot(n, light_dir), 0.0);
    // Restrained broad patches instead of uniform biome fills or fine texture noise.
    float patch_band = smoothstep(0.44, 0.50, patches) + smoothstep(0.61, 0.67, patches);
    ground *= 0.965 + 0.028 * patch_band;
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
    EMISSION = colour * ground_fill();
    if (palette_preview) { ALBEDO = ground; EMISSION = ground; }
}

// Keep banding on face lighting; retain the filtered silhouette of the shadow map.
void light() {
    if (!palette_preview) {
        float level = clamp(max(dot(NORMAL, LIGHT), 0.0) / max(lit_threshold, 0.001), 0.0, 1.0);
        float toon = toon_ramp(mix(level, 1.0, ambient));
        vec3 fill = ground_fill();
        DIFFUSE_LIGHT += (vec3(1.0) - fill) * toon * ATTENUATION * LIGHT_COLOR / PI;
        if (LIGHT_IS_DIRECTIONAL) {
            DIFFUSE_LIGHT += caustic_light / max(ALBEDO, vec3(0.02)) * ATTENUATION * LIGHT_COLOR / PI;
        }
    }
}
