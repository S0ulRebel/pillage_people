shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// THE SEA, seen from above and, once the camera dives, from below.
//
// A transparent surface over the already-drawn scene. It reads the seabed from the terrain's
// height map (so its colour follows the real depth), the scene's depth buffer (so it knows
// where things stand in it), and the scene's colour (so the shallows refract what is under
// them). Everything is evaluated per pixel: the waves' slopes, the foam, the glitter. Runs on
// the Mobile renderer.
//
// The surface ITSELF - the four Gerstner waves, the seabed lookup, the clock - lives in
// waves.gdshaderinc, shared with the underwater pass, which has to find the same waterline
// from below and float things on the same surface. Read that file first.
//
// WHO SETS WHAT. Every uniform in the include, and the ones marked "pushed" below, is set by
// ocean.gd from the Ocean node's exports at setup() (some every frame) - edit those on the
// Ocean node in the inspector; a value typed into ocean_material.tres is overwritten. The
// rest are the material's own: edit them on the material. sun_direction is pushed every
// frame by world/day.gd, which turns the sun.
//
// fragment() builds the picture in stages, each under its own heading:
//   1. where this pixel is: bed, water depth, the scene behind it, the shoreline edge
//   2. colour by depth: shallow, lagoon, deep, in soft bands
//   3. wave normals: one for shading, one for the sun
//   4. shore foam
//   5. object bands (the bright ring round anything standing in the water)
//   6. crest glints offshore
//   7. light and eye
//   8. transmission: refraction, absorption, scatter
//   9. sky reflection
//  10. sun glitter
//  11. composite
//  12. the underside, when the eye is under the sea
//  13. the horizon fade, and the palette preview

#include "res://world/waves.gdshaderinc"

// ---- Engine inputs ----------------------------------------------------------------------
// The opaque pass's depth and colour, as drawn before the water. They are what the water
// stands in front of.
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

// ---- Colour by depth --------------------------------------------------------------------
group_uniforms Colour;
// The three zones, pushed. Sampled from the "Shallow (sand)", lagoon and "Deep ocean"
// swatches of the art reference.
uniform vec3 shallow_colour : source_color = vec3(0.08, 0.64, 0.68);
uniform vec3 lagoon_colour : source_color = vec3(0.025, 0.48, 0.60);
uniform vec3 deep_colour : source_color = vec3(0.059, 0.336, 0.477);
// Metres of still-water depth from shallow_colour to deep_colour, pushed. Twice this also
// caps the optical path used for absorption (stage 8): deeper than that, water is water.
uniform float depth_fade : hint_range(1.0, 60.0) = 26.0;
// The depth ramp is stepped into this many bands, this strongly, so the sea reads as zones
// like the terrain rather than as a smooth gradient. Material-only.
uniform int bands : hint_range(0, 8) = 4;
uniform float band_strength : hint_range(0.0, 1.0) = 0.12;
// Opaque, unshaded colour ramp for checking colours against your swatches. Material-only.
uniform bool palette_preview = false;

// ---- Transmission -----------------------------------------------------------------------
group_uniforms Transmission;
// Beer-Lambert absorption per metre of water, per channel, pushed. Art-directed: red is lost
// first, blue travels furthest, which is what makes the shallows turquoise and the depths
// blue without a milky wash.
uniform vec3 absorption = vec3(0.24, 0.075, 0.028);
uniform float absorption_strength : hint_range(0.0, 3.0) = 0.78;
// How much of the water's own colour is added back where the scene has been absorbed, pushed.
uniform float scattering_strength : hint_range(0.0, 1.5) = 0.68;
// How far the scene behind the water is shifted by the waves, in screen fraction, pushed;
// and the depth over which that grows from nothing to full. Material-only.
uniform float refraction_strength : hint_range(0.0, 0.05) = 0.008;
uniform float refraction_depth : hint_range(0.1, 8.0) = 1.8;

// ---- Distance ---------------------------------------------------------------------------
group_uniforms Distance;
// Metres from the eye at which per-pixel wave detail starts to fade, and is gone. The two
// broad waves go by three quarters of detail_far, the two short ones by detail_far. Past
// that the sea is flat and only the sun glitter keeps a memory of the waves (glitter_reach).
// Material-only.
uniform float detail_near = 70.0;
uniform float detail_far = 260.0;
// The mesh's actual radial layout, pushed by ocean.gd: how much each ring grows on the last,
// and how many segments a ring has. The vertex stage needs them to stop displacing waves the
// mesh out there is too coarse to carry.
uniform float radial_growth = 1.0712;
uniform float radial_segments = 256.0;
// Where the sea stops being drawn, in metres - the mesh's extent or the camera's far plane,
// whichever is nearer; pushed by ocean.gd. The water fades out before it gets there, from
// horizon_fade_start of the way - see stage 13.
uniform float horizon = 4000.0;
uniform float horizon_fade_start : hint_range(0.1, 0.95) = 0.55;

// ---- Shoreline --------------------------------------------------------------------------
group_uniforms Shoreline;
// These set the water's ALPHA at its two kinds of edge, from above and from below.
// Metres of water thickness over which the sea fades in at the beach. Material-only.
uniform float shore_softness : hint_range(0.01, 0.5) = 0.06;
// Metres of view depth between the surface and a thing standing in it over which the sea
// fades in against that thing. Material-only.
uniform float contact_fade : hint_range(0.01, 2.0) = 0.12;

// ---- Shore foam -------------------------------------------------------------------------
group_uniforms Foam;
// The colour of every white mark on the water: shore foam and crest glints alike, pushed.
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
// Metres of still-water depth the shore foam reaches out to; it is at full strength until
// 0.44 m short of that, and fades over the rest. Zero switches the foam off. Material-only.
uniform float foam_depth : hint_range(0.0, 8.0) = 0.92;
// How fast the foam's shapes drift and the breaker advances. Material-only.
uniform float foam_speed : hint_range(0.0, 2.0) = 0.35;

// ---- Crest glints -----------------------------------------------------------------------
group_uniforms Crests;
// Short white strokes along the swell's crests offshore, drawn in foam_colour. Material-only.
uniform float crest_strength : hint_range(0.0, 1.0) = 0.28;

// ---- Object bands -----------------------------------------------------------------------
group_uniforms Object_Bands;
// A bright ring on the water round anything standing in it - hull, rock, captain. It comes
// from a separate overhead camera in ocean.gd that photographs the silhouettes of everything
// crossing the surface into band_mask; all of that is pushed.
uniform sampler2D band_mask : filter_linear, repeat_disable;
uniform vec2 band_mask_center = vec2(0.0);
uniform float band_mask_size = 144.0;
uniform vec2 band_mask_texel = vec2(0.001953125);
uniform bool band_mask_ready = false;
// The ring's colour, how far out from the silhouette it sits, how wide it is, how strong,
// how much the noise bends it, and how fast it breathes. Material-only.
uniform vec3 object_band_colour : source_color = vec3(0.84, 1.0, 0.94);
uniform float object_band_distance : hint_range(0.1, 3.0) = 0.22;
uniform float object_band_width : hint_range(0.05, 0.6) = 0.07;
uniform float object_band_strength : hint_range(0.0, 1.0) = 0.68;
uniform float object_band_distortion : hint_range(0.0, 0.5) = 0.24;
uniform float object_band_speed : hint_range(0.0, 3.0) = 0.8;

// ---- Sun --------------------------------------------------------------------------------
group_uniforms Sun;
// Direction TO the sun - the way back up the light, the DirectionalLight's own +Z. Pushed
// every frame by world/day.gd as the sun moves; ocean.gd seeds it at setup. (It used to be a
// hardcoded guess with its Z the wrong way round, so the water was lit from roughly the
// opposite bearing to everything standing on the beach.)
uniform vec3 sun_direction = vec3(-0.53, 0.37, 0.76);
// How much the water's own colour brightens on slopes facing the sun and darkens on the
// others, against flat water. Only the scattered colour; the scene seen through the water is
// untouched. Uses the shading normal, so it fades with the waves past detail_far.
// Material-only.
uniform float wave_shading : hint_range(0.0, 1.0) = 0.18;
// A broad restrained reflection of the sky at grazing angles, by fresnel. The colour is the
// sky's own pale blue; there is no daylight uniform here, so at night the sea keeps its day
// colours. Material-only. (source_color means the value is sRGB, as a colour picker gives
// it; this default is the sRGB of the linear (0.36, 0.61, 0.70) the shader used to hardcode.)
uniform vec3 sky_reflection_colour : source_color = vec3(0.634, 0.804, 0.854);
uniform float sky_reflection_strength : hint_range(0.0, 1.0) = 0.30;

// ---- Sun glitter ------------------------------------------------------------------------
group_uniforms Glitter;
// The bright path the sun lays across the water toward the eye. Stepped rather than a smooth
// highlight: this sea bands its depth colours and the sky steps its halo, and a photographic
// specular here would be the one thing in frame obeying different rules. All material-only.
uniform vec3 glitter_colour : source_color = vec3(1.0, 0.97, 0.86);
uniform float glitter_strength : hint_range(0.0, 1.0) = 0.5;
// The specular exponent near the eye: high, so the road breaks into flecks off wave faces.
uniform float glitter_sharpness : hint_range(4.0, 400.0) = 90.0;
// Lit levels the flecks are stepped to (plus off).
uniform int glitter_steps : hint_range(1, 4) = 2;
// How much wave slope the glitter keeps after the distance fade has flattened the shading
// normal, 0 to 1 of the full slope.
//
// Zero is the old behaviour, and the old behaviour was a bug you could see from the
// clifftop: the glitter path stopped dead in open water and the sea beyond it was a flat
// blue sheet. The distance fade exists to stop geometry and per-pixel detail aliasing, and
// past detail_far it takes the normals to exactly (0,1,0) - so a specular sharp enough to
// fleck off wave faces finds nothing at all to fleck off. Costing nothing to fix, because
// wave_slope is linear in its amplitude: the slopes are evaluated once and scaled twice.
uniform float glitter_reach : hint_range(0.0, 1.0) = 0.35;
// The specular exponent the glitter falls back to once the facets are smaller than a pixel.
// Broad, because that is what a sun road is at distance - you stop resolving individual wave
// faces and see one streak running to the horizon.
uniform float glitter_spread : hint_range(2.0, 60.0) = 10.0;

// ---- Underside --------------------------------------------------------------------------
group_uniforms Underside;
// The surface seen from below, once the camera dives. Snell's window: looking up within
// forty-nine degrees of the vertical the sky comes through, bright; past that the surface
// mirrors the dark water under it. Colours measured off the "Underwater (deep)" panel of
// art/references/water-rock-wood-plant-studies.jpg, the strip where the surface is: p10, p50
// and p90. All material-only.
uniform vec3 underside_colour : source_color = vec3(0.02, 0.44, 0.65);
uniform vec3 window_colour : source_color = vec3(0.09, 0.76, 0.95);
// Brighter than the art's streaks read, because the fog pass will dim it again: the art's p90
// is what is left after the water's own haze.
uniform vec3 underside_shine_colour : source_color = vec3(0.55, 0.96, 1.0);
// How soft the window's rim is, in cosine of the angle from vertical.
uniform float window_softness : hint_range(0.01, 0.4) = 0.08;
// The streaks of light through the surface: how strong, and over how much short-wave slope
// they go from nothing to full. See stage 12.
uniform float underside_shine : hint_range(0.0, 1.0) = 1.0;
uniform float underside_shine_width : hint_range(0.02, 0.6) = 0.1;
group_uniforms;

// ---- From the vertex stage --------------------------------------------------------------
// The displaced surface point, world space. Every sample in fragment() is taken here.
varying vec3 world_position;
// How much wave the mesh is actually carrying at this vertex, 0 to 1 - the summed amplitude
// after the geometry fade. Gates the crest glints: no crests where the mesh draws no swell.
varying float wave_activity;
// Metres from the eye to the displaced vertex. Fades the crests and the far horizon.
varying float surface_range;
// Metres of water over the eye at its own x/z, negative in air. The same for every vertex,
// so it reaches the fragment unchanged. Decided here, from the shared wave sum, rather than
// per fragment from heights: whichever side of the surface the eye is on is the side every
// ray from it meets first, and a per-fragment "is this point higher than the eye" painted
// crest faces seen from a trough - the top of the sea - with the underside, whenever the eye
// was within a wave's height of the water. The one place a single answer is wrong is the
// near plane's few centimetres, when the eye is AT the waterline; stage 12 handles that.
varying float eye_depth;

// ---- Helpers ----------------------------------------------------------------------------
// Value noise for the foam and the bands. A polynomial hash rather than sin() of a large
// number, which loses precision on Mobile.
float hash(vec2 p) {
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

// One wave's slope at a world point, per pixel - not interpolated from the vertices, which
// would give triangle-shaped foam and lighting. Returned at the wave's full steepness; the
// caller scales it. A wave whose phase turns more than about half a radian per pixel is faded
// out before it can alias into speckle - that is `visible`.
vec2 wave_slope(vec4 wave, vec2 p) {
    vec2 d = wave.xy / max(length(wave.xy), 0.0001);
    float k = TAU / max(wave.w, 0.01);
    float phase = k * dot(d, p) - sqrt(9.8 * k) * water_time() * wave_speed;
    float visible = 1.0 - smoothstep(0.5, 2.0, fwidth(phase));
    return d * max(wave.z, 0.0) * cos(phase) * visible;
}

// How much of the waves this pixel keeps, four ways:
//   x = shoal x distance fade for the two BROAD waves (gone by three quarters of detail_far)
//   y = shoal x distance fade for the two SHORT waves (gone by detail_far)
//   z = the shoal term alone: waves flatten as the seabed rises to shoal_depth
//   w = the distance term alone (the short waves' one)
// The sun glitter needs z and w apart: it keeps a floor under the distance fade so the far
// sea still has a slope to glint off, while still flattening with the seabed.
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

// View-space depth of the opaque scene at a screen position, from the depth buffer.
// Negative going into the screen, like every view-space z. Reverse-Z on the Vulkan renderers;
// the Compatibility renderer keeps GL's -1..1.
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

// How much of a wave the MESH may carry at a vertex. A radial grid gets coarser with
// distance, and vertex displacement has to disappear before a cell becomes wider than half
// the wavelength, or the triangles turn waves into stepped concentric bands. Shoaled as well.
// Fragment normals are filtered separately, by wave_slope's `visible`.
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

// ---- Vertex: displace the grid with the waves -------------------------------------------
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // The undeformed ocean is the sea_y plane, whatever the node's own height is.
    world.y = sea_y;
    vec2 p = world.xz;
    vec3 eye = CAMERA_POSITION_WORLD;
    // The sideways share of the displacement, limited so open water never folds over itself
    // at high wave heights (waves.gdshaderinc).
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
    eye_depth = surface_height(eye.xz) - eye.y;
}

void fragment() {
    // ---- 1. Where this pixel is ---------------------------------------------------------
    // Two depths, and the rule for them: `thickness` is the water under the DISPLACED
    // surface, wave included, and is what the shoreline and the foam contours use, because
    // they follow the water's real edge; `water_depth` is the still-water depth, sea level
    // to bed, and is what the colour ramp and every depth gate use, because a wave passing
    // over must not change what kind of water this is.
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
    // The opaque scene behind this pixel. `to_solid` is the view-space distance from the
    // water's surface to whatever is drawn behind it - the seabed, a hull, a rock - i.e.
    // the length of the eye's path through the water. Zero where something pierces the
    // surface exactly here.
    float scene_z = scene_view_z(SCREEN_UV, INV_PROJECTION_MATRIX);
    float surface_z = (VIEW_MATRIX * vec4(world_position, 1.0)).z;
    float to_solid = max(surface_z - scene_z, 0.0);
    // The two alpha edges. `contact` fades the water in against a thing standing in it;
    // `edge` fades it in at the beach - never sharper than the pixel drawing it, or the
    // waterline itself steps at distance.
    float contact = smoothstep(0.0, max(contact_fade, 0.001), to_solid);
    float edge = smoothstep(0.0, max(shore_softness, max(pixel_span, 0.001)), thickness);

    // ---- 2. Colour by depth -------------------------------------------------------------
    // Depth as a fraction of depth_fade, stepped into `bands` soft bands and mixed with the
    // smooth ramp by band_strength. The loop bound is the slider's maximum less one; a
    // shader loop needs a constant.
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
    // Three broad zones keep sand, lagoon turquoise and deep ocean distinct.
    vec3 water = mix(shallow_colour, lagoon_colour, smoothstep(0.02, 0.42, ramp));
    water = mix(water, deep_colour, smoothstep(0.34, 1.0, ramp));

    // ---- 3. Wave normals ----------------------------------------------------------------
    // The slopes are evaluated once at full steepness and scaled twice, which is exact
    // because wave_slope is linear in its amplitude: once faded by distance for shading,
    // once with a floor under that fade for the sun.
    float clock = water_time();
    vec4 env = envelopes(world_position.xz, CAMERA_POSITION_WORLD);
    vec2 broad_slope = wave_slope(wave_1, world_position.xz)
        + wave_slope(wave_2, world_position.xz);
    vec2 fine_slope = wave_slope(wave_3, world_position.xz)
        + wave_slope(wave_4, world_position.xz);
    // `n`: the shading normal, fully faded by distance. Refraction and fresnel read this;
    // letting it ripple at distance is what the fade protects them from.
    vec2 slope = (broad_slope * env.x + fine_slope * env.y) * wave_height;
    vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
    // `lit_n`: the normal the SUN sees. Same waves, shoaled, but with glitter_reach as a
    // floor under the distance fade so the sea keeps a usable slope out to the horizon.
    float lit_reach = max(env.w, glitter_reach);
    vec2 lit_slope = (broad_slope + fine_slope) * env.z * lit_reach * wave_height;
    vec3 lit_n = normalize(vec3(-lit_slope.x, 1.0, -lit_slope.y));

    // ---- 4. Shore foam ------------------------------------------------------------------
    // One deformed breaker with organic trailing strands. These are band-passed noise
    // contours, not cells, so the foam cannot be confused with seabed caustics.
    vec2 slow_flow = vec2(clock * foam_speed * 0.045,
        -clock * foam_speed * 0.030);
    float foam_broad = noise(world_position.xz * 0.20 + slow_flow);
    foam_broad = foam_broad * 0.68 + noise(world_position.xz * 0.43
        - slow_flow * 0.72 + vec2(11.7, -4.2)) * 0.32;
    float foam_detail = noise(world_position.xz * 0.82
        + vec2(-clock * 0.034, clock * 0.026));
    foam_detail = foam_detail * 0.70 + noise(world_position.xz * 1.67
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
    // Foam lives in the shallows only: full until 0.44 m short of foam_depth, gone at it.
    float shore_only = 1.0 - smoothstep(max(foam_depth - 0.44, 0.0), max(foam_depth, 0.001), water_depth);

    // The breaker: a contour of the water's thickness, pushed up the beach by a slow
    // sine (`advance`) and bent by the noise so it is one ragged line rather than a
    // level one. Its width varies with the fine noise, its brightness with the broad.
    float advance = 0.14 + 0.075 * (0.5 + 0.5 * sin(
        clock * foam_speed * 2.0 + foam_broad * TAU));
    float distorted_depth = thickness - advance
        + (foam_broad - 0.5) * 0.16 + (foam_detail - 0.5) * 0.045;
    float breaker_width = mix(0.014, 0.034, foam_detail);
    float breaker = 1.0 - smoothstep(breaker_width,
        breaker_width + foam_aa, abs(distorted_depth));
    breaker *= mix(0.12, 1.0, smoothstep(0.30, 0.70,
        foam_broad * 0.62 + foam_detail * 0.38));

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

    // Flecks left on the wet sand just landward of the breaker, where the last wave was.
    float landward_window = smoothstep(-0.13, -0.045, distorted_depth)
        * (1.0 - smoothstep(-0.025, 0.018, distorted_depth));
    float remnants = landward_window * smoothstep(0.68, 0.82, foam_detail);
    float surf = max(breaker * 0.82, max(strands, remnants * 0.24));
    surf *= shore_only * step(0.001, foam_depth) * foam_resolve;

    // ---- 5. Object bands ----------------------------------------------------------------
    // Only the dedicated overhead camera supplies object silhouettes. Gameplay-camera depth
    // must never create outlines: that would rim dry objects merely seen against the ocean.
    // The band is where the mask is empty at this point but set within radius_metres of it -
    // eight taps round a circle - so it hugs each silhouette from the outside.
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

    // ---- 6. Crest glints ----------------------------------------------------------------
    // White strokes along the dominant swell's crests, offshore. Crossing waves and slow noise
    // bend its phase before thresholding, so they come out as short curved strokes instead of
    // dashed straight lines that reveal the sine wave underneath. Only in water deeper than
    // a few metres, only where the mesh is actually carrying a swell, and only near.
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
    // Everything white on the water, foam and crests together.
    float white = clamp(max(crest, surf), 0.0, 1.0);

    // ---- 7. Light and eye ---------------------------------------------------------------
    // `light_dir` runs from the water TO the sun, `view_dir` from the water to the eye. Both
    // leave the surface, which is what the half-vector in stage 10 needs. The fresnel is
    // taken off the shading normal, faded with distance like everything the eye sees.
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    float lambert = max(dot(n, light_dir), 0.0);
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
    float fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 5.0);

    // ---- 8. Transmission ----------------------------------------------------------------
    // Refract the already-rendered opaque scene. Fade distortion at contacts so foreground
    // silhouettes do not bleed into the water, and keep the effect restrained for the toon
    // look.
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
    // The eye's path through the water is the optical path, capped at twice depth_fade -
    // water deeper than that is just water. Per-channel absorption creates clear turquoise
    // shallows and blue depths without a milky alpha wash; what is absorbed is replaced by
    // the water's own colour, never less than a trace of it (0.045) so the shallowest water
    // still reads as water and not as wet sand.
    float optical_depth = min(max(to_solid, 0.0), max(depth_fade, 0.001) * 2.0);
    vec3 transmittance = exp(-max(absorption, vec3(0.0))
        * absorption_strength * optical_depth);
    vec3 water_scatter = water * max(0.0,
        1.0 + (lambert - max(light_dir.y, 0.0)) * wave_shading);
    vec3 scatter_amount = max(vec3(1.0) - transmittance, vec3(0.045));
    vec3 shaded_water = scene_colour * transmittance
        + water_scatter * scatter_amount * scattering_strength;

    // ---- 9. Sky reflection --------------------------------------------------------------
    shaded_water = mix(shaded_water, sky_reflection_colour, fresnel * sky_reflection_strength);

    // ---- 10. Sun glitter ----------------------------------------------------------------
    // Blinn-Phong off lit_n: the half-vector between sun and eye against the wave normal, so
    // the road lies on the water between the eye and the sun's bearing, then quantised so it
    // breaks into flecks along the wave faces pointing at the sun instead of one smooth
    // sheen.
    vec3 half_dir = normalize(light_dir + view_dir);
    // Sharp near, broad far. wave_slope drops any wave whose phase turns faster than a pixel,
    // so far enough out the facets go anyway however high glitter_reach is - and the honest
    // thing to draw there is one smooth streak rather than a field of aliasing specks.
    float sharpness = mix(glitter_spread, glitter_sharpness, env.w);
    float spec = pow(max(dot(lit_n, half_dir), 0.0), sharpness);
    // Stepped to glitter_steps lit levels plus off. The 0.4 sets where a level begins: a
    // fleck lights at 60% of the way to it, so the flecks are a little fatter than the raw
    // lobe.
    float glitter = floor(clamp(spec, 0.0, 1.0) * float(glitter_steps) + 0.4)
        / float(glitter_steps);
    // Gone with the sun, over the same window of elevation the day clock fades the sky and
    // the light through (world/day.gd): a road at full strength under a sky already gone
    // to night is the one thing that gives the sea away.
    glitter *= smoothstep(-0.05, 0.18, light_dir.y);
    shaded_water = mix(shaded_water, glitter_colour, glitter * glitter_strength);

    // ---- 11. Composite ------------------------------------------------------------------
    // The band rides on the shaded water; the foam and crests go on top in foam_colour. The
    // shader already contains the transmitted scene colour, so it composites opaquely except
    // at its two edges; foam and the band stay visible right up to those.
    vec3 banded_water = mix(shaded_water, object_band_colour,
        object_band * object_band_strength);
    ALBEDO = mix(banded_water, foam_colour, white);
    float band_opacity = object_band * object_band_strength;
    ALPHA = edge * max(contact, max(white, band_opacity * 0.82));

    // ---- 12. The underside --------------------------------------------------------------
    // Seen from below. Not FRONT_FACING, which depends on which way the radial grid is
    // wound; not the facet's normal, which at a grazing look from the beach tilts away from
    // the eye on the far side of every wave; not this point's height against the eye's, which
    // is wrong for every crest above an eye that is in air. The eye's own medium - see
    // eye_depth - except at the waterline, where the near plane straddles the surface and
    // half the frame is in air: there each pixel asks for its own point on the near plane
    // against the wave under it, the same question the underwater pass asks to place its
    // waterline, so the two agree to the pixel.
    float under_side = eye_depth > 0.0 ? 1.0 : 0.0;
    if (abs(eye_depth) < 0.2) {
        vec3 near_point = unproject(SCREEN_UV, near_depth(), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
        under_side = surface_height(near_point.xz) > near_point.y ? 1.0 : 0.0;
    }
    if (under_side > 0.5) {
        // Everything above - refraction, foam, bands, glitter - is the top of the sea, and
        // from under it none of it is there (it was all computed anyway; the cost of one
        // branch for both sides). What is there is the sky coming through, inside the
        // window. The normal n points up whichever side is drawn, and view_dir runs from
        // the surface down to the eye, so -view_dir . n is the cosine of how far from
        // straight up this pixel is being looked at; 0.661 is cos 48.6 degrees, the edge of
        // Snell's window.
        float from_vertical = max(dot(-view_dir, n), 0.0);
        float window = smoothstep(0.661 - window_softness, 0.661 + window_softness, from_vertical);
        // Streaks: light through the surface, bright along the flanks of the short waves and
        // dim between, stepped to two levels like the glitter. Nothing here reads the sun.
        // The short waves, not the swell: the swell's slope keeps one sign across the dozen
        // metres a look up takes in, so anything keyed to it - a facet facing the sun, say -
        // lit a whole frame or none. The 3.6 m and 7 m waves alternate every metre or two,
        // which is the ripple the reference draws. Shoaled, not distance-faded: the swell's
        // own `visible` term takes it out where it would alias.
        float ripple = length(fine_slope) * env.z * wave_height;
        // Threshold fitted to the ripple as it comes out: at most 0.23 by construction
        // (0.42 + 0.30 steepness, times wave_height), median 0.14 on a frame. Half of it
        // shines at least a little; the flanks shine fully.
        float shine = smoothstep(0.03, 0.03 + underside_shine_width, ripple);
        shine = floor(shine * 2.0 + 0.5) / 2.0;
        vec3 under = mix(underside_colour, window_colour, window);
        // Streaks cross the mirror as well as the window - the reference streaks the whole
        // ceiling - only a little fainter where the sky is not behind them.
        under = mix(under, underside_shine_colour, shine * underside_shine * mix(0.7, 1.0, window));
        ALBEDO = under;
        ALPHA = edge;
    }

    // ---- 13. The horizon, and the preview -----------------------------------------------
    // The sea meets the sky by becoming it. The water stops being drawn somewhere - at the
    // mesh's extent, or sooner at the camera's far plane, which at a thousand metres was
    // the one that counted - a hair below the true horizon, and with the scene fog off here
    // it stayed dark blue right up to that edge while the sky's pale horizon began on the
    // other side of it: the edge, drawn at a fraction of a pixel, rasterised as a broken row
    // of sky-coloured dashes along the horizon in every shot from the beach. Fading the water
    // out over its last stretch lets the sky show through in its own colour, at whatever
    // hour, and leaves no edge to draw. tests/sun_view.gd measures the arrival.
    float horizon_fade = smoothstep(horizon * horizon_fade_start, horizon * 0.97, surface_range);
    ALPHA *= 1.0 - horizon_fade;
    if (palette_preview) {
        ALBEDO = water;
        ALPHA = 1.0;
    }
}
