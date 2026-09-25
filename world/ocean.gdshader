shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// THE SEA, seen from above and, once the camera dives, from below.
//
// A transparent surface over the already-drawn scene. It reads the seabed from the terrain's
// height map (so its colour follows the real depth), the scene's depth buffer (so it knows
// where things stand in it), and the scene's colour (so the shallows refract what is under
// them). Everything is evaluated per pixel: the waves' slopes, the foam, the streak. Runs on
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
// frame by world/day.gd, which turns the sun; daylight comes from the same clock by way of
// the environment (see the Night group).
//
// fragment() builds the picture in stages, each under its own heading:
//   0. where on the sea plane this pixel really is (the horizon band is found by ray)
//   1. where this pixel is: bed, water depth, the scene behind it, the shoreline edge
//   2. colour by depth: shallow, lagoon, deep, in soft bands
//   3. wave normals: one for shading, one for the sun
//   4. shore foam
//   5. object bands (the bright ring round anything standing in the water)
//   6. crest glints offshore
//   7. light and eye
//   8. transmission: refraction, absorption, scatter
//   9. sky reflection
//  10. the sun's streak
//  11. composite
//  12. the underside, when the eye is under the sea
//  13. the haze toward the horizon, and the palette preview

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
// that the sea is flat but for the sun's flecks, which fade on their own as the waves
// shrink below a pixel. Material-only.
uniform float detail_near = 70.0;
uniform float detail_far = 260.0;
// The mesh's actual radial layout, pushed by ocean.gd: how much each ring grows on the last,
// and how many segments a ring has. The vertex stage needs them to stop displacing waves the
// mesh out there is too coarse to carry.
uniform float radial_growth = 1.0712;
uniform float radial_segments = 256.0;
// How far the camera sees, in metres - the mesh's extent or the camera's far plane,
// whichever is nearer; pushed by ocean.gd. The rings beyond nine tenths of it are not drawn
// where they are: the vertex stage sends them out to the horizon (see there), so the sea
// never ends at the far plane however high the camera is.
uniform float horizon = 4000.0;

// ---- Haze --------------------------------------------------------------------------------
group_uniforms Haze;
// The far sea goes to the colour of the sky at the horizon, the way every reference sheet
// draws it: saturated blue near, paler and paler out, and one soft line where it meets the
// sky. The colour is the scene fog's, which ocean.gd pushes whenever it changes - and it is
// AUTHORED in world/day.gd, which writes the environment's fog colour every frame from its
// two day and night constants; the default here and main.tscn's are overwritten. At full
// daylight it is the sky's own horizon colour, so sea and sky meet in one colour. Through
// dusk and at night they part: day.gd fogs toward (0.06, 0.10, 0.18) in sRGB, the sky mixes
// toward its night_horizon (0.06, 0.12, 0.22) in linear - two constants and two spaces
// that day.gd and sky.gdshader would have to share to meet at every hour.
uniform vec3 haze_colour : source_color = vec3(0.70, 0.86, 0.92);
// Metres to 63% haze. Half way there at 0.7 of this; the horizon itself is all haze. Fitted
// to the reference sheets' Archipelago, Cliffs and Beach panels, whose sea keeps nine tenths
// of its saturation a fifth of the way down from the horizon and seven tenths at the
// horizon line itself; 2000 m paled the far sea over the whole upper half. Material-only.
uniform float haze_distance : hint_range(100.0, 20000.0) = 5000.0;
// Degrees below the horizon over which the sea also blends to the haze whatever its
// distance. From a low eye the far sea is compressed into the last two or three rows of the
// picture, and there the distance haze alone drew the horizon as a hard pale line; the art
// draws it soft. Only for water further than a few hundred metres, so crests level with a
// low eye keep their colour. Material-only.
uniform float horizon_softness : hint_range(0.0, 3.0) = 0.4;

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
// sky's own pale blue by day; at night it darkens with everything else the sky lights (the
// Night group). Material-only. (source_color means the value is sRGB, as a colour picker gives
// it; this default is the sRGB of the linear (0.36, 0.61, 0.70) the shader used to hardcode.)
uniform vec3 sky_reflection_colour : source_color = vec3(0.634, 0.804, 0.854);
uniform float sky_reflection_strength : hint_range(0.0, 1.0) = 0.30;

// ---- Night ------------------------------------------------------------------------------
group_uniforms Night;
// How bright the day is, 1 at noon to 0 at night, pushed: world/day.gd's own daylight, which
// it publishes as the environment's ambient_light_sky_contribution and ocean.gd reads there,
// the way the haze colour is read from the fog. Everything the SKY lights - the water's own
// colour, the sky's reflection, the foam, the object bands, the underside - fades to
// night_tint * night_level of itself as it goes to 0, the same two numbers the ground's own
// fill fades to in terrain.gdshader (night_fill_tint, night_fill), so sea and ground darken
// together. What is seen THROUGH the water - the seabed, a hull - is not touched: the
// scene's light already dims it. The streak is sunlight and goes out with the sun on its
// own; the haze follows the fog colour, which is night's already.
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 night_tint : source_color = vec3(0.55, 0.62, 1.0);
uniform float night_level : hint_range(0.0, 1.0) = 0.10;

// ---- The sun's streak -------------------------------------------------------------------
group_uniforms Streak;
// One streak of light on the water, straight out from the eye along the sun's bearing, and
// no more: the references have no sun road at all - their sparkle is short white crest
// strokes spread evenly over the sea - and the stepped specular this replaced turned into
// fans of stripes from any height. The streak is a soft cone of bearings, a faint sheen over
// its whole length and white flecks off the wave flanks that face the sun inside it, and it
// goes out with the sun. All material-only.
uniform vec3 streak_colour : source_color = vec3(1.0, 0.97, 0.86);
// The sheen: how far toward streak_colour the water inside the streak goes. Faint, or the
// cone reads as a spotlight lying on the water; near the eye the flecks are the streak, and
// from a height, where they have faded, this is all of it.
uniform float streak_strength : hint_range(0.0, 1.0) = 0.05;
// Half-width of the cone, in degrees of bearing either side of the sun's, for water seen
// streak_taper degrees or more below the horizon; nearer the horizon than that it narrows
// to nothing, so the streak tapers toward the sun the way a path of light does instead of
// standing on the water as a column of constant width.
uniform float streak_width : hint_range(0.5, 20.0) = 3.0;
uniform float streak_taper : hint_range(1.0, 45.0) = 10.0;
// The flecks: how far toward streak_colour a mirroring flank of the two SHORT waves inside
// the streak goes, and how steeply it has to lean (its slope along the sun's bearing) to
// count. The swell's flanks are left out: seen from a height they are long, and inside a
// narrow streak they came out as the rungs of a ladder. The short waves' flanks are broken
// up by noise for the same reason - a Gerstner wave is a straight line - so they come out
// as dashes, densest along the sun's line and thinning to the cone's edge.
uniform float streak_flecks : hint_range(0.0, 1.0) = 0.6;
uniform float streak_fleck_slope : hint_range(0.0, 0.3) = 0.06;

// ---- Underside --------------------------------------------------------------------------
group_uniforms Underside;
// The surface seen from below, once the camera dives. Snell's window: looking up within
// forty-nine degrees of the vertical the sky comes through, bright; past that the surface
// mirrors the dark water under it. Colours measured off the "Underwater (deep)" panel of
// art/references/water-rock-wood-plant-studies.jpg, the strip where the surface is: p10, p50
// and p90. All material-only.
uniform vec3 underside_colour : source_color = vec3(0.02, 0.44, 0.65);
uniform vec3 window_colour : source_color = vec3(0.09, 0.76, 0.95);
// Brighter than the art's streaks read, because the underwater pass's fog will dim it again:
// the art's p90 is what is left after the water's own murk.
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
// 1 on a vertex the vertex stage sent to the horizon, 0 on every other: any fragment where
// this is not exactly zero lies in the horizon band, and stage 0 finds its point by ray.
varying float horizon_weight;

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

// How much of the waves this pixel keeps, three ways:
//   x = shoal x distance fade for the two BROAD waves (gone by three quarters of detail_far)
//   y = shoal x distance fade for the two SHORT waves (gone by detail_far)
//   z = the shoal term alone: waves flatten as the seabed rises to shoal_depth
// The sun's flecks take z alone: they are guarded against distance by wave_slope's own
// `visible`, which drops each wave as its facets shrink below a pixel, and nothing else.
vec3 envelopes(vec2 p, vec3 eye) {
    float depth = sea_y - bed_height(p);
    float shoal = smoothstep(0.0, max(shoal_depth, 0.001), depth);
    float range = length(vec3(p.x, sea_y, p.y) - eye);
    float broad = 1.0 - smoothstep(detail_near,
        max(detail_far * 0.75, detail_near + 1.0), range);
    float detail = 1.0 - smoothstep(detail_near,
        max(detail_far, detail_near + 1.0), range);
    return vec3(shoal * broad, shoal * detail, shoal);
}

// View-space depth of the opaque scene at a screen position, from the depth buffer.
// Negative going into the screen, like every view-space z. Reverse-Z on the Vulkan renderers;
// the Compatibility renderer keeps GL's -1..1. Where nothing was drawn - the depth buffer
// still holds its cleared far value - the answer is "nothing behind this pixel", further
// than any point of the sea, rather than the far plane: the horizon band (vertex stage)
// lies beyond the far plane, a thousand million metres out at the horizon itself, and
// would otherwise read as being behind the sky and go transparent.
float scene_view_z(vec2 uv, mat4 inv_projection) {
    float raw_depth = texture(depth_texture, uv).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    if (raw_depth >= 1.0) { return -1.0e12; }
    vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
    #else
    if (raw_depth <= 0.0) { return -1.0e12; }
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

// ---- Vertex: displace the grid with the waves, and send the far rings to the horizon ----
void vertex() {
    vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // The undeformed ocean is the sea_y plane, whatever the node's own height is.
    world.y = sea_y;
    vec2 p = world.xz;
    vec3 eye = CAMERA_POSITION_WORLD;
    // The horizon band. A mesh ends somewhere, and from any height the sky showed under its
    // edge: at the far plane, a thousand metres out, that was three degrees of the sky's
    // underside between the sea and the true horizon from the cannon's hill. So the rings
    // beyond nine tenths of the camera's reach are not drawn where they are. Each of their
    // vertices is sent a thousand million metres out along its own bearing, which puts it on
    // the horizon to the pixel from any height - a flat plane's horizon is at eye level - and the
    // one band of triangles from the last kept ring out to them is the sea from there to the
    // horizon, hazed to the sky (stage 13). Those vertices lie beyond the far plane, so their
    // depth is pinned just inside it; nothing real is drawn out there to be occluded, and the
    // sea writes no depth. What is interpolated across the band is not trusted, though - see
    // the top of fragment(): it finds the band's points again from each pixel's own ray.
    float radius = length(VERTEX.xz);
    bool horizon_band = radius > horizon * 0.9;
    horizon_weight = horizon_band ? 1.0 : 0.0;
    if (horizon_band) {
        vec3 bearing = vec3(VERTEX.x, 0.0, VERTEX.z) / max(radius, 0.001);
        world = vec3(eye.x, sea_y, eye.z) + bearing * 1.0e9;
        wave_activity = 0.0;
    } else {
        // The sideways share of the displacement, limited so open water never folds over
        // itself at high wave heights (waves.gdshaderinc).
        float q = horizontal_ratio();
        vec3 offset = vec3(0.0);
        float reach = 0.0;
        gerstner(wave_1, p, geometry_envelope(p, eye, wave_1.w), q, offset, reach);
        gerstner(wave_2, p, geometry_envelope(p, eye, wave_2.w), q, offset, reach);
        gerstner(wave_3, p, geometry_envelope(p, eye, wave_3.w), q, offset, reach);
        gerstner(wave_4, p, geometry_envelope(p, eye, wave_4.w), q, offset, reach);
        world += offset;
        wave_activity = smoothstep(0.02, 0.18, reach);
    }
    world_position = world;
    VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
    // Written by hand because the horizon band pins its depth below, and a shader that
    // writes POSITION anywhere has to write it everywhere. This is the engine's own formula.
    POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(world, 1.0));
    if (horizon_band) {
        // Just inside the far plane: reverse-Z on the Vulkan renderers, where the far plane
        // is zero; GL's one on Compatibility.
        #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        POSITION.z = POSITION.w * 0.999999;
        #else
        POSITION.z = POSITION.w * 0.000001;
        #endif
    }
    surface_range = length(world - eye);
    eye_depth = surface_height(eye.xz) - eye.y;
}

void fragment() {
    // ---- 0. Where on the plane this pixel really is ---------------------------------------
    // The mesh's own answer, except across the horizon band. The band's far vertices are a
    // thousand million metres out, and the perspective weights the rasteriser interpolates
    // with are the reciprocals of that: at the band's top row they cancelled to a NEGATIVE
    // distance, which made a negative haze, which drew one darker row along the whole
    // horizon (measured: tagging the haze red made that row bluer, not redder). The band is
    // the flat sea_y plane, so its points are found again exactly: this pixel's ray from the
    // eye, cut with the plane. A band fragment is known by horizon_weight, which is zero on
    // every vertex the mesh kept and so exactly zero on every fragment between them - and
    // as a second net, by an interpolated range that is not a sane one. (It was first
    // decided by the ray alone, "anything whose ray hits the plane that far out", and from
    // under the water the ray down to the seabed misses the plane entirely: every near
    // fragment was sent to the horizon and the wading waterline read 15 cm low.)
    vec3 world_point = world_position;
    float range_here = surface_range;
    bool in_band = horizon_weight != 0.0 || !(surface_range >= 0.0 && surface_range < horizon);
    if (in_band) {
        vec3 eye = CAMERA_POSITION_WORLD;
        vec3 ray = normalize(unproject(SCREEN_UV, near_depth(), INV_PROJECTION_MATRIX, INV_VIEW_MATRIX) - eye);
        float drop = sea_y - eye.y;
        if (ray.y * drop > 0.0) {
            float t = min(drop / ray.y, 1.0e9);
            world_point = eye + ray * t;
            range_here = t;
        } else {
            // A ray that does not reach the plane - the eye exactly at sea level, or a pixel
            // whose centre is a hair above the horizon while one of its samples is sea -
            // stands for the horizon ON the plane: a thousand million metres out along its
            // bearing, at sea level. Not a point up the ray: that gave the sea's top row a
            // neighbour with a million metres of "water" under it, and the fwidth of the
            // thickness across that pair thinned the row to nothing.
            vec2 heading = ray.xz / max(length(ray.xz), 1.0e-6);
            world_point = vec3(eye.x + heading.x * 1.0e9, sea_y, eye.z + heading.y * 1.0e9);
            range_here = 1.0e9;
        }
    }

    // ---- 1. Where this pixel is ---------------------------------------------------------
    // Two depths, and the rule for them: `thickness` is the water under the DISPLACED
    // surface, wave included, and is what the shoreline and the foam contours use, because
    // they follow the water's real edge; `water_depth` is the still-water depth, sea level
    // to bed, and is what the colour ramp and every depth gate use, because a wave passing
    // over must not change what kind of water this is.
    float bed = bed_height(world_point.xz);
    float thickness = world_point.y - bed;
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
    float surface_z = (VIEW_MATRIX * vec4(world_point, 1.0)).z;
    float ahead = surface_z - scene_z;
    float to_solid = max(ahead, 0.0);
    // The two alpha edges. `contact` fades the water in against a thing standing in it -
    // a thing just BELOW the surface, that is; a thing in FRONT of the surface covers the
    // water by the depth test and the water stays whole beside it. It used to fade against
    // those too, and with MSAA the pixel on a palm's edge takes the palm's depth: the water
    // went transparent across that whole pixel and whatever was behind it showed as a
    // one-pixel fringe round every silhouette over the sea - the sky, at night, luminous.
    // `edge` fades it in at the beach - never sharper than the pixel drawing it, or the
    // waterline itself steps at distance.
    float contact = ahead < 0.0 ? 1.0 : smoothstep(0.0, max(contact_fade, 0.001), ahead);
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
    // once shoaled only, for the sun.
    float clock = water_time();
    vec3 env = envelopes(world_point.xz, CAMERA_POSITION_WORLD);
    vec2 broad_slope = wave_slope(wave_1, world_point.xz)
        + wave_slope(wave_2, world_point.xz);
    vec2 fine_slope = wave_slope(wave_3, world_point.xz)
        + wave_slope(wave_4, world_point.xz);
    // `n`: the shading normal, fully faded by distance. Refraction and fresnel read this;
    // letting it ripple at distance is what the fade protects them from.
    vec2 slope = (broad_slope * env.x + fine_slope * env.y) * wave_height;
    vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
    // `lit_slope`: the slope the SUN sees - the two short waves, shoaled but not faded with
    // distance; the streak fades its flecks by pixel size itself (stage 10). It is the
    // gradient of the height: it points uphill.
    vec2 lit_slope = fine_slope * env.z * wave_height;

    // ---- 4. Shore foam ------------------------------------------------------------------
    // One deformed breaker with organic trailing strands. These are band-passed noise
    // contours, not cells, so the foam cannot be confused with seabed caustics.
    vec2 slow_flow = vec2(clock * foam_speed * 0.045,
        -clock * foam_speed * 0.030);
    float foam_broad = noise(world_point.xz * 0.20 + slow_flow);
    foam_broad = foam_broad * 0.68 + noise(world_point.xz * 0.43
        - slow_flow * 0.72 + vec2(11.7, -4.2)) * 0.32;
    float foam_detail = noise(world_point.xz * 0.82
        + vec2(-clock * 0.034, clock * 0.026));
    foam_detail = foam_detail * 0.70 + noise(world_point.xz * 1.67
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
    float wash_shape_1 = noise(world_point.xz * 0.31
        + vec2(-clock * 0.019, clock * 0.027) + vec2(9.4, 2.7));
    float wash_mask_1 = noise(world_point.xz * 0.69
        + vec2(clock * 0.031, clock * 0.014) + vec2(-3.2, 7.6));
    float wash_distance_1 = distorted_depth - 0.13 - (wash_shape_1 - 0.5) * 0.085;
    float wash_1 = 1.0 - smoothstep(0.012, 0.026 + foam_aa,
        abs(wash_distance_1));
    wash_1 *= smoothstep(0.53, 0.69, wash_mask_1);

    float wash_shape_2 = noise(world_point.xz * 0.24
        + vec2(clock * 0.014, -clock * 0.022) + vec2(4.8, -8.1));
    float wash_mask_2 = noise(world_point.xz * 0.57
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
    vec2 band_uv = (world_point.xz - band_mask_center) / max(band_mask_size, 0.001) + 0.5;
    float capture_edge = smoothstep(0.0, 0.035, min(min(band_uv.x, band_uv.y),
        min(1.0 - band_uv.x, 1.0 - band_uv.y)));
    float moving_noise = noise(world_point.xz * 0.82
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
    vec2 crest_p = world_point.xz;
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
    crest *= 1.0 - smoothstep(55.0, 150.0, range_here);
    // Everything white on the water, foam and crests together.
    float white = clamp(max(crest, surf), 0.0, 1.0);

    // ---- 7. Light and eye ---------------------------------------------------------------
    // `light_dir` runs from the water TO the sun - its xz is the bearing the streak (stage 10)
    // is keyed to, its y the sun's height; `view_dir` from the water to the eye, for the
    // fresnel here and the underside's window (stage 12). The fresnel is taken off the
    // shading normal, faded with distance like everything the eye sees.
    vec3 light_dir = sun_direction / max(length(sun_direction), 0.0001);
    float lambert = max(dot(n, light_dir), 0.0);
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_point);
    float fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 5.0);
    // How much light the sky gives the water right now: all of it by day, a dim moonlit blue
    // at night (the Night group). Multiplied into everything the sky lights from here on.
    vec3 sky_light = mix(night_tint * night_level, vec3(1.0), clamp(daylight, 0.0, 1.0));

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
        + water_scatter * scatter_amount * scattering_strength * sky_light;

    // ---- 9. Sky reflection --------------------------------------------------------------
    shaded_water = mix(shaded_water, sky_reflection_colour * sky_light, fresnel * sky_reflection_strength);

    // ---- 10. The sun's streak -----------------------------------------------------------
    // A cone of bearings from the eye, centred on the sun's. `aside` is the sine of the
    // angle between this point's bearing and the sun's (the 2D cross product - exact near
    // zero, where a cosine has run out of digits), and the bell across the cone is one minus
    // a smoothstep of it against sin(width): full on the sun's line, nothing at the width,
    // nothing behind the eye. The width tapers with the angle of depression - how far below
    // the horizon this point is seen - to nothing at the horizon, so on the screen the
    // streak is a wedge pointing at the sun from any height, the way a path of light on
    // water is drawn, instead of a column of constant width standing on the sea. (The sun's
    // height does not enter: a real glitter path sits around the point that mirrors the sun,
    // at the sun's elevation below the horizon, and at a 68 degree noon that is at your
    // feet; this one runs to the horizon at any hour by choice, as one streak of light.)
    vec2 to_here = world_point.xz - CAMERA_POSITION_WORLD.xz;
    float flat_range = max(length(to_here), 0.001);
    vec2 here_bearing = to_here / flat_range;
    vec2 sun_bearing = normalize(light_dir.xz + vec2(0.0001, 0.0));
    float along = dot(here_bearing, sun_bearing);
    float aside = abs(here_bearing.x * sun_bearing.y - here_bearing.y * sun_bearing.x);
    float depression = degrees(atan(CAMERA_POSITION_WORLD.y - world_point.y, flat_range));
    float width = radians(streak_width) * clamp(depression / max(streak_taper, 0.1), 0.0, 1.0);
    float across = clamp(aside / max(sin(width), 1.0e-6), 0.0, 1.0);
    float streak = (1.0 - across * across * (3.0 - 2.0 * across)) * step(0.0, along);
    // Gone with the sun, over the same window of elevation the day clock fades the sky and
    // the light through (world/day.gd): a streak at full strength under a sky already gone
    // to night is the one thing that gives the sea away.
    streak *= smoothstep(-0.05, 0.18, light_dir.y);
    // The flecks: the flank that mirrors the sun into the eye. Its normal is the half-way
    // direction between the sun and the eye, and along the bearing that leans toward the
    // sun only where the sun is LOWER than the line of sight (cos(elevation) greater than
    // cos(depression): nearer the eye than the point that mirrors the sun exactly) and
    // toward the eye beyond it - which, from anywhere but a wave trough, is most of the
    // streak. The gradient points uphill, so a flank leaning toward the sun has its gradient
    // pointing away from it. On or off at streak_fleck_slope, one pixel of slope either
    // side so the edge stays clean; the pixel width is clamped because it is read after the
    // discard, and beside a discarded pixel it is anything at all.
    float lean = sign(sqrt(max(1.0 - light_dir.y * light_dir.y, 0.0)) - cos(radians(depression)));
    float facing = -dot(lit_slope, sun_bearing) * lean;
    float fleck_aa = clamp(fwidth(facing), 0.003, 0.03);
    float flecks = smoothstep(streak_fleck_slope - fleck_aa, streak_fleck_slope + fleck_aa, facing);
    // Torn into dashes by a noise mask about two metres across, drifting slowly, and thinned
    // toward the cone's edge by the bell (times streak). Gone once a pixel spans more than
    // about a metre of sea: the mask cannot be resolved there and shimmered, and the bare
    // flanks behind it were the ladder.
    float fleck_breakup = noise(world_point.xz * 0.5 + vec2(clock * 0.03, -clock * 0.02));
    float metres_per_pixel = length(vec2(fwidth(world_point.x), fwidth(world_point.z)));
    flecks *= smoothstep(0.42, 0.62, fleck_breakup) * streak
        * (1.0 - smoothstep(0.6, 1.2, metres_per_pixel));
    float sun_light = streak * streak_strength + flecks * streak_flecks;
    shaded_water = mix(shaded_water, streak_colour, clamp(sun_light, 0.0, 1.0));

    // ---- 11. Composite ------------------------------------------------------------------
    // The band rides on the shaded water; the foam and crests go on top in foam_colour. The
    // shader already contains the transmitted scene colour, so it composites opaquely except
    // at its two edges; foam and the band stay visible right up to those.
    vec3 banded_water = mix(shaded_water, object_band_colour * sky_light,
        object_band * object_band_strength);
    ALBEDO = mix(banded_water, foam_colour * sky_light, white);
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
        // Everything above - refraction, foam, bands, streak - is the top of the sea, and
        // from under it none of it is there (it was all computed anyway; the cost of one
        // branch for both sides). What is there is the sky coming through, inside the
        // window. The normal n points up whichever side is drawn, and view_dir runs from
        // the surface down to the eye, so -view_dir . n is the cosine of how far from
        // straight up this pixel is being looked at; 0.661 is cos 48.6 degrees, the edge of
        // Snell's window.
        float from_vertical = max(dot(-view_dir, n), 0.0);
        float window = smoothstep(0.661 - window_softness, 0.661 + window_softness, from_vertical);
        // Streaks: light through the surface, bright along the flanks of the short waves and
        // dim between, stepped to two levels like the fog's bands. Nothing here reads the sun.
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
        // Lit by the sky through the surface, so it goes with the sky at night.
        ALBEDO = under * sky_light;
        ALPHA = edge;
    }

    // ---- 13. The haze, and the preview --------------------------------------------------
    // The sea meets the sky by becoming it: with distance, everything drawn above - water,
    // foam, streak, underside - goes to the scene fog's colour, and the horizon band (vertex
    // stage) arrives there fully hazed, so the line where sea and sky meet is one colour on
    // both sides from any height - at every hour at which the fog and the sky's horizon are
    // the same colour, which today is full daylight (see the Haze group). The scene fog is
    // off in this shader (render_mode) because it would fog the transparent water twice,
    // once here and once on the seabed behind it; this is the sea's own, with the fog's
    // colour. tests/sun_view.gd measures the arrival.
    float haze = 1.0 - exp(-range_here / max(haze_distance, 1.0));
    // And the soft line at the horizon itself, by angle (`depression` is stage 10's; its
    // sign is dropped so the surface seen from below, which lies above the eye, gets the
    // same treatment at a grazing look), for water beyond a few hundred metres only.
    float horizon_blend = (1.0 - smoothstep(0.0, max(horizon_softness, 0.001), abs(depression)))
        * smoothstep(150.0, 300.0, range_here);
    haze = max(haze, horizon_blend);
    ALBEDO = mix(ALBEDO, haze_colour, haze);
    if (palette_preview) {
        ALBEDO = water;
        ALPHA = 1.0;
    }
}
