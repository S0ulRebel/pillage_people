// THE RUN-UP: the sheet of water each wave sends up the beach, and its drain back (step 3 of
// docs/foam-plan.md). Shared by the sand (terrain.gdshader) and the sea (ocean.gdshader), on
// one clock (ocean.gd pushes its water clock into both), so the water's edge is one line
// across the two: above the still waterline the sand draws it, below it the sea does.
//
// Analytic - a formula of distance up the beach and time, no memory of past frames. Every
// shore wave (waves.gdshaderinc) that reaches the waterline turns into a run-up: the edge
// shoots up the beach fast and slows, stops, then drains back slowly, past the still waterline
// down to runup_drawdown, until the next one comes in. How far each one reaches changes from
// wave to wave, bigger every fourth, and bulges along the shore into tongues.
//
// Because it is a formula, it also knows its own history at any point, which is what the foam
// and the wet sand are drawn from:
//   - how long ago the edge last ran up over this point: the foam's AGE, so lace born at the
//     front erodes as it is left behind;
//   - how long ago this point last came out of the water: how far the sand has DRIED.
//
// Distances are metres ALONG the beach, up from the still waterline (the shore field's signed
// distance, turned round). How far a run-up can reach is the lesser of runup_reach and what
// runup_height of climb allows on the slope there, so on a flat beach it runs far and on
// rock it barely rises.

#ifndef RUNUP_INCLUDED
#define RUNUP_INCLUDED

#include "res://world/shore_field.gdshaderinc"

// The foam's lace (world/foam_lace.gd): its round cells also shape the run-up's tongues.
// Declared here, where it is first needed; foam.gdshaderinc cuts the lace from it.
uniform sampler2D foam_lace : filter_linear_mipmap, repeat_enable;
uniform bool foam_lace_ready = false;

group_uniforms Run_Up;
// Seconds between two shore waves: the long swell's period. ocean.gd pushes it.
uniform float runup_wave_period = 3.7;
// How many shore waves make one run-up. Waves merge in the surf, and a run-up every 3.7 s
// was frantic.
uniform float runup_waves : hint_range(1.0, 4.0) = 2.0;
// Metres up a flat beach the biggest run-up reaches.
uniform float runup_reach : hint_range(0.5, 20.0) = 5.5;
// Metres above sea level any run-up can climb: what caps it on a steep shore.
uniform float runup_height : hint_range(0.05, 2.0) = 0.6;
// Metres below the still waterline the backwash pulls the water's edge back.
uniform float runup_drawdown : hint_range(0.0, 5.0) = 1.0;
// The share of each run-up spent running up; the rest is the slower drain.
uniform float runup_rise : hint_range(0.1, 0.9) = 0.3;
// How strongly the edge bulges into tongues along the shore, and how far apart they are.
uniform float runup_tongues : hint_range(0.0, 1.0) = 0.55;
uniform float runup_tongue_spacing : hint_range(1.0, 20.0) = 4.5;
// Draws the run-up instead of the surface: blue where the water is now, white fading to grey
// with the foam's age, orange fading to sand as it dries. For checking it.
uniform bool runup_preview = false;
group_uniforms;

float runup_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float runup_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(runup_hash(i), runup_hash(i + vec2(1.0, 0.0)), f.x),
		mix(runup_hash(i + vec2(0.0, 1.0)), runup_hash(i + vec2(1.0)), f.x), f.y);
}

// How far run-up number `i` reaches, in metres up the beach, at the stretch whose nearest
// shore point is `n`, on a beach rising `slope` metres per metre.
float runup_extent(float i, vec2 n, float slope) {
	// Each wave its own size, the same along a stretch and drifting slowly along the coast.
	float wave = 0.55 + 0.45 * (0.5 + 0.5 * sin(i * 2.39 + n.x * 0.047 + n.y * 0.031));
	// Sets: every fourth run-up the biggest.
	float set = 0.8 + 0.2 * cos(i * 1.5708);
	// Tongues along the shore, a new pattern every wave: round lobes with sharp cusps between,
	// from the lace's cells at tongue size - furthest at a cell's centre, least at its walls.
	float tongue = 1.0;
	if (foam_lace_ready) {
		vec2 cells = n / (max(runup_tongue_spacing, 0.1) * 8.0) + vec2(i * 0.37, i * 0.21);
		float centre = textureLod(foam_lace, cells, 0.0).r * 0.75;
		// Squared, so each tongue's tip is round, not a point; the cusps between stay sharp.
		float lobe = 1.0 - min(centre * centre / 0.36, 1.0);
		tongue = 1.0 + runup_tongues * (lobe - 0.55) * 1.6;
	}
	float reach = min(runup_reach, runup_height / max(slope, 0.005));
	return reach * shore_stretch(n) * wave * set * tongue;
}

// Where the edge is, metres up the beach, a fraction `f` through a run-up that reaches `r`:
// from the drawdown up to r, fast then slowing, over runup_rise of the cycle; then back down
// to the drawdown, slowly at first.
float runup_edge(float f, float r) {
	float dd = runup_drawdown;
	if (f < runup_rise) {
		float x = f / runup_rise;
		return mix(-dd, r, 1.0 - (1.0 - x) * (1.0 - x));
	}
	float y = (f - runup_rise) / (1.0 - runup_rise);
	return mix(r, -dd, pow(y, 1.5));
}

// The fraction of a run-up reaching `r` at which its edge passes `u` going up (x) and going
// back down (y) - the inverses of runup_edge's two halves. Both past 1 if it never gets there.
vec2 runup_crossings(float u, float r) {
	float dd = runup_drawdown;
	float v = (u + dd) / max(r + dd, 0.0001);
	// Out past the drawdown the water never leaves, and the edge never crosses: no crossing.
	if (v > 1.0 || v <= 0.0) {
		return vec2(2.0);
	}
	float up = runup_rise * (1.0 - sqrt(max(1.0 - max(v, 0.0), 0.0)));
	float down = runup_rise + (1.0 - runup_rise) * pow(clamp((r - u) / max(r + dd, 0.0001), 0.0, 1.0), 1.0 / 1.5);
	return vec2(up, down);
}

// The run-up at a world point `xz` whose ground is `above_sea` metres above the still water,
// at time `t` (the water clock):
//   x  metres the water's edge is beyond this point: > 0 under water now, < 0 dry
//   y  seconds since the edge last ran up over this point - the foam's age (1e4: long ago)
//   z  seconds since this point last came out of the water - 0 while it is under (1e4: long)
//   w  where the edge is, metres up the beach from the still waterline
// runup_at, and also how far up the beach the last run-up to have finished climbing reached
// here: where it left its wash line.
vec4 runup_at_reach(vec2 xz, float above_sea, float t, out float last_reach) {
	vec4 field = shore_field_at(xz);
	float u = -field.x;
	vec2 n = field.yz;
	// The beach's slope from here to the waterline: height over distance, either side of it.
	float slope = max(abs(above_sea) / max(abs(u), 0.5), 0.005);
	float period = max(runup_wave_period, 0.05) * max(runup_waves, 1.0);
	// Run-ups counted since the clock started, staggered like this stretch's shore waves and
	// timed so that each starts as a crest reaches the waterline.
	float cycles = (t / max(runup_wave_period, 0.05) - (shore_stagger(n) - 1.5708) / TAU)
		/ max(runup_waves, 1.0);
	float i = floor(cycles);
	float f = cycles - i;
	float r = runup_extent(i, n, slope);
	float edge = runup_edge(f, r);
	vec2 now = runup_crossings(u, r);
	float r_before = runup_extent(i - 1.0, n, slope);
	vec2 before = runup_crossings(u, r_before);
	last_reach = f >= runup_rise ? r : r_before;
	float age = 1.0e4;
	if (f >= now.x) {
		age = (f - now.x) * period;
	} else if (before.x <= 1.0) {
		age = (f + 1.0 - before.x) * period;
	}
	float dried = 1.0e4;
	if (u < edge) {
		dried = 0.0;
	} else if (now.y <= 1.0 && f >= now.y) {
		dried = (f - now.y) * period;
	} else if (before.y <= 1.0) {
		dried = (f + 1.0 - before.y) * period;
	}
	return vec4(edge - u, age, dried, edge);
}

vec4 runup_at(vec2 xz, float above_sea, float t) {
	float last_reach;
	return runup_at_reach(xz, above_sea, t, last_reach);
}

// The run-up drawn for checking: blue under water now, white fading with the foam's age over
// 4 s, orange fading as the sand dries over 12 s.
vec3 runup_preview_colour(vec4 run, vec3 under) {
	float px = max(fwidth(run.x), 0.001);
	float water = smoothstep(-px, px, run.x);
	vec3 colour = mix(under, vec3(0.95, 0.55, 0.20), exp(-run.z / 12.0) * 0.8);
	colour = mix(colour, vec3(1.0), exp(-run.y / 4.0) * 0.9 * (1.0 - water));
	return mix(colour, vec3(0.15, 0.35, 0.85), water * 0.85);
}

#endif
