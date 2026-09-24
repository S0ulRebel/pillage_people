shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, unshaded, fog_disabled;

// The view from under the sea, drawn over the whole frame once the camera is in the water.
//
// A colour laid over the picture, not a rewrite of it. The screen texture Godot offers a
// shader holds only the opaque pass - the sea surface seen from below, the waterfall and the
// fish's transparent edges are not in it - so anything that read the frame and wrote it back
// would erase them. Fogging with alpha keeps whatever was drawn and only tints it.
//
// The waterline is found per pixel, not per camera. A camera is a point and a screen is not:
// with the eye at the surface the top of the frame is in air and the bottom is in water, and
// the line between them is where the near plane crosses the waves. So every pixel asks where
// ITS point on the near plane sits against the surface at that x/z - the same wave sum the sea
// is drawn with, via waves.gdshaderinc - and the split follows the swell, tilts with the camera,
// and never flips the whole screen at once.
//
// Colours are measured from the underwater panels in art/references/
// water-rock-wood-plant-studies.jpg: median of the top, middle and bottom thirds of the
// "Underwater (shallow)" and "Underwater (deep)" views. Bright cyan where the light comes in,
// mid blue level with the eye, navy below. Distance flattens things to silhouettes of that
// blue, in soft steps - the art has no blur.

#include "res://world/waves.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

group_uniforms Colour;
// What everything close is tinted with. "Underwater (shallow)" middle third, p50: the teal
// the sand and rocks a few metres off are seen through.
uniform vec3 water_colour : source_color = vec3(0.09, 0.68, 0.72);
// Looking up: the surface lit from above. "Underwater (deep)" top third, p50.
uniform vec3 glow_colour : source_color = vec3(0.10, 0.76, 0.95);
// Looking level, far away. Between the shallow view's top third and the deep view's middle.
uniform vec3 level_colour : source_color = vec3(0.02, 0.46, 0.75);
// Looking down, far away. "Underwater (deep)" bottom third, p50.
uniform vec3 floor_colour : source_color = vec3(0.01, 0.31, 0.52);
// What the whole palette drifts toward as the camera goes deeper. The ruins panel, mid third.
uniform vec3 abyss_colour : source_color = vec3(0.05, 0.33, 0.47);
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
group_uniforms Fog;
// Metres to 63% fog. Rocks a few metres off keep their colour; thirty metres out is flat blue.
uniform float fog_distance : hint_range(1.0, 100.0) = 14.0;
// The tint the nearest things still get. Nothing underwater is drawn in its dry colours: in
// the reference the sand under the camera is half sand and half teal, measured, not a wash.
uniform float haze : hint_range(0.0, 0.8) = 0.5;
// Depth steps, the way the sea bands its colours from above. Distant things become layered
// silhouettes rather than a smooth gradient - see the ruins panel.
uniform int bands : hint_range(0, 8) = 4;
uniform float band_strength : hint_range(0.0, 1.0) = 0.35;
// Metres of camera depth over which the glow goes and the palette turns to abyss_colour.
uniform float deep_fade : hint_range(1.0, 40.0) = 12.0;
// How much of the glow an upward look gets however close the surface is.
uniform float surface_glow : hint_range(0.0, 1.0) = 0.55;
group_uniforms Waterline;
// The bright line where the surface meets the lens, in pixels. The near plane is centimetres
// from the eye, so a width in metres would be the whole screen or nothing.
uniform float waterline_pixels : hint_range(0.0, 24.0) = 10.0;
group_uniforms Light;
// Direction TO the sun, mirrored from the ocean, which gets it from the scene's light.
uniform vec3 sun_direction = vec3(-0.53, 0.37, 0.76);
uniform float shaft_strength : hint_range(0.0, 1.0) = 0.35;
// Metres between shafts, measured across the sun's bearing at the surface.
uniform float shaft_width : hint_range(0.5, 20.0) = 6.0;
// Metres of water in front of the camera the shafts are looked for in.
uniform float shaft_range : hint_range(1.0, 60.0) = 24.0;
uniform float shaft_speed : hint_range(0.0, 2.0) = 0.25;
group_uniforms;
// Opaque: green where the near plane is under the surface, red along the waterline band.
// tests/underwater_view.gd reads it to prove the split is in the frame - the picture alone
// cannot, because a seabed the terrain already paints teal looks fogged when nothing is
// being drawn over it at all.
uniform bool split_preview = false;

// The raw depth-buffer value of the near plane. Reverse-Z on the Vulkan renderers, so near is
// one there; the Compatibility renderer keeps GL's zero.
float near_depth() {
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    return 0.0;
    #else
    return 1.0;
    #endif
}

// A world point from a screen position and a raw depth-buffer value.
vec3 unproject(vec2 uv, float raw_depth, mat4 inv_projection, mat4 inv_view) {
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
    #endif
    vec4 view = inv_projection * vec4(ndc, 1.0);
    view.xyz /= view.w;
    return (inv_view * vec4(view.xyz, 1.0)).xyz;
}

void vertex() {
    // The quad IS the screen. Its transform is ignored and its corners are pinned to the
    // corners of the near plane, so it never has to be placed or sized.
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    // This pixel's point on the near plane, and the first solid thing behind it.
    vec3 eye = unproject(SCREEN_UV, near_depth(), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
    float raw = texture(depth_texture, SCREEN_UV).r;
    vec3 scene = unproject(SCREEN_UV, raw, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
    vec3 to_scene = scene - eye;
    float range = length(to_scene);
    vec3 dir = to_scene / max(range, 0.0001);

    // Metres of water above this point of the near plane. Negative in air.
    float under = surface_height(eye.xz) - eye.y;
    // Gathered before anything branches on it. One pixel of the near plane is a tenth of a
    // millimetre of world, so the edge is drawn at pixel width, not at a width in metres.
    float span = max(fwidth(under), 0.00001);
    float submerged = smoothstep(-span, span, under);
    float line = (1.0 - smoothstep(0.0, span * max(waterline_pixels, 0.001), under))
        * step(0.001, waterline_pixels);
    // The near plane sits centimetres from the eye, so this is the camera's own depth too.
    float dim = smoothstep(0.0, max(deep_fade, 0.001), under);

    // How much water is between the eye and the thing behind this pixel. A ray that leaves
    // the water is fogged as far as the surface, not as far as the sky beyond it: otherwise
    // looking up is a flat sheet of glow with the surface itself lost in it.
    float wet_range = range;
    if (dir.y > 0.001) {
        wet_range = min(range, (sea_y - eye.y) / dir.y);
    }
    float f = 1.0 - exp(-max(wet_range, 0.0) / max(fog_distance, 0.001));
    // The surface seen from a few metres down is too close to be fogged, and drawn from
    // below it is the sea's top-side colour, which is not the bright ceiling the reference
    // has. So an upward look always carries at least this much glow, and the waves show
    // through the rest of it.
    float up = dir.y;
    f = max(f, smoothstep(0.0, 0.6, up) * surface_glow);

    // Where the light is: up is bright, down is dark, and both fade toward the abyss as the
    // camera goes deeper. The glow starts at the horizontal, because at a level view the
    // top of the reference frame is already the bright water the light comes in through.
    vec3 far_water = mix(level_colour, floor_colour, smoothstep(0.0, 0.75, -up));
    far_water = mix(far_water, glow_colour, smoothstep(0.0, 0.4, up) * (1.0 - dim * 0.6));
    vec3 water = mix(water_colour, far_water, f);
    water = mix(water, abyss_colour, dim * 0.7);
    if (bands > 1) {
        float steps = float(bands - 1);
        float quantized = 0.0;
        float aa = max(fwidth(f), 0.0001);
        for (int i = 0; i < 7; i++) {
            if (i < bands - 1) {
                float boundary = (float(i) + 0.5) / steps;
                quantized += smoothstep(boundary - aa, boundary + aa, f) / steps;
            }
        }
        f = mix(f, quantized, band_strength);
    }
    float alpha = mix(haze, 1.0, f);

    // Light shafts. A shaft is the column the sun's light takes down from one spot on the
    // surface, so every point in the water is dragged back up the sun's direction to where
    // its light came in, and a pattern of spots is drawn there, in the surface plane. Each
    // spot is a column in the water.
    //
    // Walked along the ray rather than sampled once. A column cut by one sphere of distance
    // is a blob - that is what a single sample drew - and a column seen through a length of
    // water is a streak, which is what twelve short steps add up to. Two sines beating
    // against each other for the spots: a few columns rather than a haze, and no noise table
    // to carry for it.
    vec3 sun = sun_direction / max(length(sun_direction), 0.0001);
    vec2 bearing = normalize(vec2(sun.x, sun.z) + vec2(0.0001, 0.0));
    vec2 across = vec2(-bearing.y, bearing.x);
    float t = water_time() * shaft_speed;
    float shaft = 0.0;
    float step_length = shaft_range / 16.0;
    for (int i = 0; i < 16; i++) {
        float d = (float(i) + 0.5) * step_length;
        // Never printed on a rock that is closer than the water being lit.
        if (d > wet_range) { break; }
        vec3 p = eye + dir * d;
        vec3 entry = p + sun * ((sea_y - p.y) / max(sun.y, 0.05));
        float u = dot(entry.xz, across) / max(shaft_width, 0.01);
        float v = dot(entry.xz, bearing) / max(shaft_width, 0.01);
        // Kept smooth here and thresholded after the sum. Sixteen steps a metre and a half
        // apart cannot resolve a hard-edged spot, and a hard edge sampled that coarsely came
        // out as speckle; a soft lobe averages to a soft streak.
        float spot = max(sin(u * TAU + t) * sin(v * TAU * 0.5 + u * 1.3 - t * 0.6), 0.0);
        // Fainter the deeper the light has come.
        float reach = 1.0 - smoothstep(0.0, max(deep_fade, 0.001) * 1.5, sea_y - p.y);
        shaft += spot * reach;
    }
    shaft = smoothstep(0.16, 0.42, shaft / 16.0);
    // Two levels, the way the sea steps its glitter.
    shaft = floor(shaft * 2.0 + 0.5) / 2.0;
    // Toward the light: strongest looking up or sunward, gone below the horizontal, and
    // fainter the deeper the camera is.
    float sunward = smoothstep(-0.1, 0.6, up * 0.6 + dot(dir, sun) * 0.4);
    shaft *= sunward * (1.0 - dim * 0.7) * shaft_strength * step(0.02, sun.y);
    water = mix(water, glow_colour, shaft);

    ALBEDO = mix(water, foam_colour, line);
    ALPHA = max(alpha, line) * submerged;
    if (split_preview) {
        ALBEDO = vec3(line, submerged, 0.0);
        ALPHA = 1.0;
    }
}
