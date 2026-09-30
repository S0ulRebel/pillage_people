// THE SEA SURFACE, AS A FUNCTION: where the water is at a world point, and what it needs to
// know to say so. Included by the ocean shader, which displaces its mesh with it, and by the
// underwater shader, which has to find the same surface from below to split the screen along
// the waterline.
//
// Extracted on the third copy. ocean.gd already carries a CPU version of this sum for things
// that float (surface_y), and the comment on it records what happens when two copies of the
// surface drift apart: barrels sitting in the trough while the crest goes past. A third copy,
// in a second shader, would have drifted the same way - the waterline drawn on screen sliding
// off the surface the sea is drawn with.
//
// WHO SETS WHAT. Every uniform in this file belongs to the Ocean node: ocean.gd pushes them
// all into the ocean material at setup() - the terrain numbers from the Terrain node, the
// waves from its own exports - and the clock every frame; underwater.gd then copies them off
// the ocean material into its own, every frame, by these names. The defaults below are only
// what a shader shows before anyone has pushed anything. Edit the Ocean node, not these.

// ---- Seabed and sea level ---------------------------------------------------------------
// The terrain's height map and how to place it: the map is `terrain_size` metres across,
// centred on `terrain_center`, and a texel's value times `terrain_scale` above
// `terrain_base_y` is the ground. Defaults are main.tscn's Terrain (620 m, 180 m); the
// Terrain script's own defaults are smaller, but whatever the scene says is what gets pushed.
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform float terrain_size = 620.0;
uniform float terrain_scale = 180.0;
uniform vec2 terrain_center = vec2(0.0);
uniform float terrain_base_y = 0.0;
// Still-water level, world y. The Terrain node's sea_level().
uniform float sea_y = 18.0;
// The far seabed round the map, from the Terrain's far ring: `far_size` metres across, centred
// like the map, a texel being metres above `terrain_base_y`; `far_floor` is the bed's world y
// beyond it. A far_size of 0 - no far ring - leaves the old fall-off past the map's edge.
uniform sampler2D far_height : filter_linear, repeat_disable;
uniform float far_size = 0.0;
uniform float far_floor = -42.0;

// ---- Clock ------------------------------------------------------------------------------
// The water clock, pushed from ocean.gd so the CPU and every shader agree on it. Negative
// means read TIME, which is only right for a shader nobody else has to keep in step with.
uniform float preview_time = -1.0;

float water_time() { return preview_time < 0.0 ? TIME : preview_time; }

// ---- Waves ------------------------------------------------------------------------------
group_uniforms Waves;
// Four Gerstner waves, each packed as (direction x, direction z, steepness, wavelength in
// metres). The direction need not be unit length. Steepness is the Gerstner Q: how peaked the
// crest is, 0 flat, 1 a knife edge before the sum of them is limited by choppiness. From the
// long swell to the short ripple.
uniform vec4 wave_1 = vec4(1.0, 0.25, 0.72, 21.0);
uniform vec4 wave_2 = vec4(-0.5, 0.9, 0.55, 12.5);
uniform vec4 wave_3 = vec4(0.75, -0.7, 0.42, 7.0);
uniform vec4 wave_4 = vec4(-0.85, -0.3, 0.30, 3.6);
// Amplitude scale on every wave, in metres of crest-to-level for a steepness-1 wave.
uniform float wave_height : hint_range(0.0, 3.0) = 0.32;
// Multiplier on the waves' own physical speed (deep-water dispersion: sqrt(g k)). 1 is real.
uniform float wave_speed : hint_range(0.0, 40.0) = 1.0;
// Metres of water under which the waves are at full height; shallower, they flatten toward
// zero at the shore, the way real waves lose their height coming in over a rising bed.
uniform float shoal_depth : hint_range(0.5, 40.0) = 2.5;
// How much of a wave's sideways motion is kept: the fraction of full Gerstner horizontal
// displacement, 0 pure up-and-down sine, 1 the full peaked crest. See horizontal_ratio().
uniform float choppiness : hint_range(0.0, 1.0) = 0.85;

// ---- Shore waves --------------------------------------------------------------------------
// Near the island the swell hands over to waves that come straight in to the beach. Real
// waves do that by slowing in shallow water, so their crests bend round until they arrive
// parallel to the shore (refraction). Here it is drawn rather than simulated: the shore waves'
// crests are lines of equal distance to the shore (world/shore_field.gdshaderinc), so they
// run in parallel to every beach and wrap round the island by construction.
//
// They keep the long swell's period (wave_1's), so the rhythm on the beach is the rhythm out
// at sea. Each stretch of coast gets its own timing and height from where its nearest shore
// point is - smooth sines of that point, so neighbouring stretches differ without a seam and
// the crests never copy the coastline as rings round a headland - and every fourth wave or so
// is bigger: the sets surfers wait for. ocean.gd repeats all of this on the CPU (surface_y),
// so it is built from sines and nothing else.
//
// Metres between shore-wave crests as they come in: shorter than the swell, as waves get in
// shallow water.
uniform float shore_wave_length : hint_range(2.0, 40.0) = 11.0;
// The shore waves' steepness (the Gerstner Q, as for the swell). 0 switches them off.
uniform float shore_wave_steepness : hint_range(0.0, 1.0) = 0.55;
// Metres out from the waterline where the shore waves begin to take over; they are at full
// height within the nearest third of it.
uniform float shore_wave_reach : hint_range(5.0, 120.0) = 40.0;
// How much of the swell they take over from, at full: 1 leaves only the shore waves by the
// beach, 0 lays them on top of the swell.
uniform float shore_wave_calm : hint_range(0.0, 1.0) = 0.9;
// Metres of water the shore waves keep their full height down to. Much less than the swell's
// shoal_depth: the shore waves ARE the waves in the shallows, and flattened over the last
// couple of metres of depth like the swell they were gone before they reached the beach.
uniform float shore_wave_shoal : hint_range(0.05, 5.0) = 0.6;
group_uniforms;

#include "res://world/shore_field.gdshaderinc"

// ---- The seabed under a point -----------------------------------------------------------
// Ground height, world y, at a world x/z. Read the terrain's way, and continued past the map.
float bed_height(vec2 p) {
    vec2 uv = (p - terrain_center) / max(terrain_size, 0.001) + 0.5;
    // Metres past the map's edge, zero inside it. The sea goes on beyond the map, and its bed
    // has to go on too - from the border's own depth down to 60 m below sea level, over the
    // first 40 m of distance past the edge. It used to drop a thousand metres in one step at
    // the border, and the ocean's shoreline softening, which is never sharper than the pixel
    // drawing it (by fwidth(thickness)), saw that step as a thousand-metre pixel and thinned
    // the sea to nothing along the map's edge: a dashed line along the horizon from every
    // beach.
    vec2 past = max(max(-uv, uv - 1.0), vec2(0.0)) * max(terrain_size, 0.001);
    float outside = length(past);
    // Past the map there is real ground now, the Terrain's far ring, and the water reads it the
    // way it reads the map - so the colour out there is the bed you would swim down to, and
    // meets the map's at its edge, where the two are the same ground.
    if (far_size > 0.0 && outside > 0.0) {
        vec2 far_uv = (p - terrain_center) / far_size + 0.5;
        if (far_uv.x < 0.0 || far_uv.y < 0.0 || far_uv.x > 1.0 || far_uv.y > 1.0) {
            return far_floor;
        }
        vec2 far_texels = vec2(textureSize(far_height, 0));
        far_uv = (far_uv * (far_texels - 1.0) + 0.5) / far_texels;
        return terrain_base_y + textureLod(far_height, far_uv, 0.0).r;
    }
    uv = clamp(uv, vec2(0.0), vec2(1.0));
    // The height map is a grid of samples at the CORNERS of the world: terrain.gd reads it as
    // index u * (N - 1), and builds the ground from it that way. A texture keeps its samples
    // at texel centres, so read straight, this was skewed by (0.5 - u) texels: nothing at the
    // middle of the map, a third of a metre at its edge, and on a bed rising inside
    // shoal_depth a few millimetres between the surface the CPU floats things on and the one
    // the mesh draws. Measured by tests/underwater_view.gd.
    vec2 texels = vec2(textureSize(terrain_height, 0));
    uv = (uv * (texels - 1.0) + 0.5) / texels;
    float bed = terrain_base_y + textureLod(terrain_height, uv, 0.0).r * terrain_scale;
    return mix(bed, sea_y - 60.0, smoothstep(0.0, 40.0, outside));
}

// ---- One wave, four waves ---------------------------------------------------------------
// One Gerstner wave's displacement at world x/z `p`, added into `offset` (world x, y, z).
//   wave              the packed (dir x, dir z, steepness, wavelength)
//   scale             amplitude multiplier: wave_height, times the shoal term, times whatever
//                     the caller fades by
//   horizontal_ratio  the sideways share, from horizontal_ratio()
//   reach             accumulates the amplitude, so the caller can tell how much wave is
//                     actually present here (the ocean gates its crest glints on it)
// The amplitude is steepness / k: that is what makes steepness the Gerstner Q, a crest shape
// independent of wavelength. Phase speed is the deep-water one, sqrt(g k) with g = 9.8, so
// long waves outrun short ones.
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

// The sideways share of the displacement. Gerstner waves fold over into loops once the
// steepnesses add up past 1, so the share is choppiness divided by the summed steepness (times
// wave_height) whenever that sum is over 1: the crests stay peaked, and open water never
// crosses itself however high the waves are turned up.
float horizontal_ratio() {
    float total_steepness = max(wave_1.z, 0.0) + max(wave_2.z, 0.0)
        + max(wave_3.z, 0.0) + max(wave_4.z, 0.0);
    return choppiness / max(1.0, total_steepness * wave_height);
}

// How far the shore waves have taken over at a point `d` metres from the shore (signed, +
// out at sea): 1 near the beach and on it, 0 beyond shore_wave_reach.
float shore_blend(float d) {
    return 1.0 - smoothstep(shore_wave_reach * 0.35, max(shore_wave_reach, 0.01), d);
}

// The shore wave's phase and its amplitude factor at a point, from the shore field there:
// x = phase, y = the stretch-and-set factor on its height. Its crests are where the phase is
// a quarter turn: they sit at fixed distances from the shore and move in at the swell's
// speed.
vec2 shore_wave_phase(vec4 field) {
    float k = TAU / max(shore_wave_length, 0.01);
    float k_swell = TAU / max(wave_1.w, 0.01);
    float omega = sqrt(9.8 * k_swell) * wave_speed;
    // Each stretch of shore its own timing (up to about a wave either way) and height.
    float stagger = shore_stagger(field.yz);
    float stretch = shore_stretch(field.yz);
    float phase = -k * field.x - omega * water_time() + stagger;
    // Sets: a slow swell of height over about four waves, riding in with them.
    float set = 0.72 + 0.28 * cos(phase * 0.25 + stagger * 0.5);
    return vec2(phase, stretch * set);
}

// The shore wave's displacement at `p`, added in like a Gerstner wave's. `scale` as there; the
// shore_blend is applied here. It moves water toward and away from the shore - at half the
// swell's sideways share, because across the line half-way between two shores (a narrow bay)
// the direction to the nearest shore turns round.
void shore_wave(vec2 p, vec4 field, float scale, float horizontal_ratio,
        inout vec3 offset, inout float reach) {
    float blend = shore_blend(field.x);
    if (blend <= 0.0 || shore_wave_steepness <= 0.0) {
        return;
    }
    vec2 toward = shore_direction(p, field);
    vec2 ph = shore_wave_phase(field);
    float k = TAU / max(shore_wave_length, 0.01);
    float a = shore_wave_steepness / k * scale * blend * ph.y;
    float sideways = a * horizontal_ratio * 0.5 * cos(ph.x);
    offset += vec3(sideways * toward.x, a * sin(ph.x), sideways * toward.y);
    reach += a;
}

// How much of its height the seabed lets the shore wave keep at a still-water `depth`.
float shore_shoal(float depth) {
    return smoothstep(0.0, max(shore_wave_shoal, 0.001), depth);
}

// How much of the swell is left at a point: all of it out at sea, 1 - shore_wave_calm by the
// beach.
float swell_share(vec4 field) {
    return 1.0 - shore_wave_calm * shore_blend(field.x) * step(0.0001, shore_wave_steepness);
}

// All four waves and the shore wave at `p`, `height` (wave_height, or less) scaling all of
// them. Each is shoaled here by the depth at p: the swell by shoal_depth, the shore wave by
// shore_wave_shoal.
void gerstner_all(vec2 p, float height, float q, inout vec3 offset, inout float reach) {
    vec4 field = shore_field_at(p);
    float depth = sea_y - bed_height(p);
    float swell = height * smoothstep(0.0, max(shoal_depth, 0.001), depth) * swell_share(field);
    gerstner(wave_1, p, swell, q, offset, reach);
    gerstner(wave_2, p, swell, q, offset, reach);
    gerstner(wave_3, p, swell, q, offset, reach);
    gerstner(wave_4, p, swell, q, offset, reach);
    shore_wave(p, field, height * shore_shoal(depth), q, offset, reach);
}

// ---- The surface above a point ----------------------------------------------------------
// How much wave the seabed allows here: 0 on the beach, 1 in water deeper than shoal_depth.
float shoal_at(vec2 p) {
    return smoothstep(0.0, max(shoal_depth, 0.001), sea_y - bed_height(p));
}

// The height of the surface above a world point: the same sum ocean.gd's surface_y makes on
// the CPU, solved the same way, so the two agree to the millimetre. The one thing left out on
// both sides is the fade with distance from the eye - the ocean's vertex shader flattens far
// waves because its mesh out there cannot carry them, and that is a concession of the mesh,
// not a property of the sea. The shoal term stays, because it is real.
//
// Why it is a solve and not a sum. A Gerstner wave moves water sideways as well as up - by up
// to 0.65 m with these waves - so the surface above p is the sample taken from somewhere else.
// The underwater shader cannot ignore that: it draws the waterline on a near plane six
// centimetres tall, where a centimetre is a sixth of the screen. So the sample point is solved
// for: start at p, ask where the water at p came from, and ask again from there. Each step is
// four wave evaluations and only shrinks the error by the slope of the sideways displacement,
// which sums to about a half with these waves - so one step left 14 mm against the drawn mesh
// and three left 23 mm, on the other side of it. Eight steps bring it under the millimetre
// the mesh itself is good to. Measured, all of it, by tests/underwater_view.gd; with no
// sideways displacement the two agree to 1.6 mm, which is what says the rest of the sum is
// right.
//
// The shoal is taken at the SOURCE, every step, not once at p. A vertex of the mesh flattens
// by the depth under where it started, not under where the wave carries it, and the two are
// up to 0.65 m apart. Deep water does not care; on a bed rising inside shoal_depth - where he
// wades, and where the camera is half in most often - reading the depth at p is worth
// centimetres. One seabed sample per step buys exactness there.
float surface_height(vec2 p) {
    float q = horizontal_ratio();
    vec2 source = p;
    vec3 offset = vec3(0.0);
    float reach = 0.0;
    // Eight refinements of the source point ...
    for (int i = 0; i < 8; i++) {
        offset = vec3(0.0);
        gerstner_all(source, wave_height, q, offset, reach);
        source = p - offset.xz;
    }
    // ... and a ninth evaluation at the point they arrive at, whose height is the answer.
    // `reach` is only accumulated because gerstner() insists on it; nothing reads it here.
    offset = vec3(0.0);
    gerstner_all(source, wave_height, q, offset, reach);
    return sea_y + offset.y;
}

// ---- The screen ---------------------------------------------------------------------------
// Not sea maths: two helpers for asking where the surface is against the screen. Both shaders
// need a pixel's own point on the near plane - the underwater pass to split the frame along
// the waterline, the sea to know which side of itself a pixel sees when the eye is at the
// waterline.

// The raw depth-buffer value of the near plane. Reverse-Z on the Vulkan renderers, so near is
// one there; the Compatibility renderer keeps GL's zero.
float near_depth() {
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    return 0.0;
    #else
    return 1.0;
    #endif
}

// A world point from a screen position (0..1) and a raw depth-buffer value.
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
