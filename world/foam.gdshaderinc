// THE SHORE FOAM (step 4 of docs/foam-plan.md): the front at the water's edge, the lace it
// leaves behind, and the wash line - drawn by the sea (ocean.gdshader) on its side of the still
// waterline and by the sand (terrain.gdshader) on the other, from the same inputs, so it runs
// across the waterline without a seam.
//
// What the references draw, and how each is got here (panels 9 and 10 of
// art/references/terrain-water-and-shore-transitions.jpg, and the "Foam patterns" swatch):
//
//  * Foam is born at the front and ages. Every point knows how long ago the run-up's edge last
//    ran over it (runup.gdshaderinc) - out past the swash, how long ago the last shore wave's
//    crest went over it - and that age is the whole story: young foam is solid white with a
//    few round windows, older foam is lace, old lace breaks into pieces and goes.
//  * The lace is round holes opening in the foam (world/foam_lace.gd): a hole is where the
//    distance to a cell's centre is under a radius that grows with age. Walls between two
//    close holes break first, junctions of three last - thin walls, fat junctions, like the
//    swatch. Cells open at different times (each has its own random number), young lace has
//    small cells and old lace larger ones.
//  * The front's leading edge is a chain of round bubbles, not a line: it is pushed out by a
//    small-celled bubble field, so it bulges round each bubble and dips between.
//  * While a run-up drains there is no fresh foam at the edge, so a thinner lobed line rides
//    it - thick and thin by turns along the shore - the way panel 10 draws calm water.
//  * The sand keeps what the last run-up left: fainter, creamier lace that pops as it dries,
//    and a beaded wash line where it reached highest.
//  * Three off-white tones, measured from panel 9: lit (229, 229, 224) on the landward, young
//    side, mid (201, 208, 205) as it ages, and the darker see-through tone (173, 184, 178) on
//    the rims of the holes. Never pure white, never cyan.

#ifndef FOAM_INCLUDED
#define FOAM_INCLUDED

#include "res://world/runup.gdshaderinc"

group_uniforms Shore_Foam;
// The lace texture, foam_lace (world/foam_lace.gd), is declared in runup.gdshaderinc, which
// shapes its tongues with it; ocean.gd makes it and hands it to both materials.
// Metres across one cell of fresh lace, and of old lace. Panel 9's grow from about 0.36 m at
// the front to about a metre as they trail out.
uniform float foam_cell : hint_range(0.1, 3.0) = 0.4;
uniform float foam_cell_old : hint_range(0.1, 5.0) = 0.95;
// Seconds lace lasts on the water, and on the sand.
uniform float foam_life : hint_range(0.3, 10.0) = 2.2;
uniform float foam_sand_life : hint_range(0.3, 20.0) = 4.5;
// How much of the fresh front has windows in it: the share of cells with a hole from the start.
uniform float foam_windows : hint_range(0.0, 1.0) = 0.4;
// Metres the bubbles on the front's leading edge push out, and across one bubble.
uniform float foam_bubble : hint_range(0.0, 1.0) = 0.3;
uniform float foam_bubble_size : hint_range(0.05, 1.0) = 0.28;
// Metres of the thinner line that rides the edge while a run-up drains; it swings between a
// third and one and a half times this along the shore.
uniform float foam_edge_line : hint_range(0.0, 1.0) = 0.16;
// Metres out past the still waterline the breaking shore waves leave lace behind their crests,
// and how many seconds it lasts there - much less than the run-up's: panel 9's lace is gone
// within three metres of the front.
uniform float foam_surf_width : hint_range(0.0, 30.0) = 3.5;
uniform float foam_surf_life : hint_range(0.1, 5.0) = 0.7;
// How strongly the sand's leftover lace and wash line show against the sand (they are thinner
// than the foam on the water).
uniform float foam_sand_strength : hint_range(0.0, 1.0) = 0.7;
uniform vec3 foam_lit : source_color = vec3(0.898, 0.898, 0.878);
uniform vec3 foam_mid : source_color = vec3(0.788, 0.816, 0.804);
uniform vec3 foam_shade : source_color = vec3(0.678, 0.722, 0.698);
group_uniforms;

// The lace at `xz` for cells `cell` metres across: (distance to the cell centre, the cell's
// random number, distance across the nearest wall - both distances in cells). The tile holds
// eight cells; the older, larger lace is turned so the two never line up.
vec3 foam_lace_at(vec2 xz, float cell, bool turned) {
	vec2 p = turned ? vec2(0.8 * xz.x - 0.6 * xz.y, 0.6 * xz.x + 0.8 * xz.y) + vec2(3.7, 1.9) : xz;
	vec4 t = texture(foam_lace, p / (cell * 8.0));
	return vec3(t.r * 0.75, t.g, t.b * 0.75);
}

// How much of a point foam `a` (its age over its life, 0 fresh .. 1 gone) covers, from a lace
// sample: x the cover, y how near it is to a hole's rim (for the darker tone there).
//
// Panel 9's lace, from the front outward: solid foam with a few round windows; the windows
// opening into cells whose walls are thin and even, fat where three meet; the walls breaking
// into dashes and beads; nothing. So two measures at once. A WALL is foam within `w` of the
// line between two cells - even in width, like the painted hairlines. A JUNCTION is foam
// further than `k` from every cell's centre - the fat knots where walls meet. Fresh foam has
// wide walls (so it is solid) and small `k` (so the only holes are windows); with age the
// walls thin to hairlines and then each cell's half of each wall goes at its own moment,
// while `k` grows until the knots shrink to beads and go.
vec2 foam_holes(vec3 lace, float a) {
	a = clamp(a, 0.0, 1.0);
	float aa_c = max(fwidth(lace.x), 0.003);
	float aa_w = max(fwidth(lace.z), 0.003);
	// Walls: half a cell wide (solid) while fresh, a hairline by a third of the way, then
	// breaking cell by cell and gone by nine tenths.
	float w = mix(0.9, 0.12, smoothstep(0.08, 0.35, a));
	w *= 1.0 - step(mix(1.1, -0.1, smoothstep(0.45, 0.9, a)), lace.y);
	float wall = 1.0 - smoothstep(w - aa_w, w + aa_w, lace.z);
	// Knots: holes round each centre that grow from the windows (in some cells only) to the
	// whole cell.
	float windows = step(1.0 - foam_windows, lace.y) * 0.12;
	float k = mix(windows, 0.62, smoothstep(0.05, 0.4, a)) + smoothstep(0.55, 1.0, a) * 0.16
		+ (lace.y - 0.5) * 0.06;
	float knot = smoothstep(k - aa_c, k + aa_c, lace.x);
	float cover = max(wall * step(0.001, w), knot);
	float rim = (1.0 - smoothstep(k + aa_c, k + aa_c + 0.05, lace.x)) * step(0.02, k);
	return vec2(cover, rim * (1.0 - wall));
}

// The lace of foam `age` seconds old over a `life`. Holes open in two lattices at once - small
// cells from the start, larger ones from a third of the way on - and the foam is what neither
// has eaten: uneven cells, big and small together, with no seam where one size gives way to
// the other.
vec2 foam_lace_cover(vec2 xz, float age, float life) {
	float a = age / max(life, 0.01);
	if (a >= 1.0) {
		return vec2(0.0);
	}
	vec2 fine = foam_holes(foam_lace_at(xz, foam_cell, false), a);
	vec2 old = foam_holes(foam_lace_at(xz, foam_cell_old, true), max(a * 1.25 - 0.3, 0.0) / 0.95);
	return vec2(min(fine.x, old.x), max(fine.y, old.y));
}

// The shore foam at `xz`: rgb its colour, a how much of the point it covers.
//   run, last_reach  the run-up here (runup_at_reach)
//   surf_age         seconds since the last shore wave's crest went over (the sea works it
//                    out; the sand passes 1e4)
//   on_sand          true on the sand's side of the still waterline
vec4 shore_foam(vec2 xz, vec4 run, float last_reach, float surf_age, bool on_sand) {
	if (!foam_lace_ready) {
		return vec4(0.0);
	}
	vec4 field = shore_field_at(xz);
	float u = -field.x;
	float under = run.x;
	// The bubbles on the leading edge: the edge pushed out by up to foam_bubble round each
	// small cell's centre.
	float bubbles = foam_lace_at(xz, foam_bubble_size, true).x;
	float edge = under + foam_bubble * (0.42 - bubbles);
	float edge_aa = max(fwidth(edge), 0.004);
	float wet = smoothstep(-edge_aa, edge_aa, edge);

	// Foam on the water: aged from the run-up's edge in the swash, from the crests out past it.
	// The surf's lace thins out to sea and is gone by foam_surf_width.
	float surf_zone = 1.0 - smoothstep(foam_surf_width * 0.4, max(foam_surf_width, 0.01), -u);
	float surf = surf_age / max(surf_zone, 0.001) * foam_life / max(foam_surf_life, 0.01);
	float age = min(run.y, surf);
	vec2 lace = foam_lace_cover(xz, age, foam_life) * wet;

	// The line on the edge while it drains: thick and thin by turns along the shore.
	float swing = 0.33 + 1.17 * clamp(foam_lace_at(field.yz, 2.6, false).x / 0.75, 0.0, 1.0);
	float line_width = foam_edge_line * swing;
	float line = wet * (1.0 - smoothstep(line_width - edge_aa, line_width + edge_aa, edge));
	float cover = max(lace.x, line);

	// The tone: lit while fresh and on the line, mid as it ages, darker on the holes' rims.
	float a = clamp(age / max(foam_life, 0.01), 0.0, 1.0);
	vec3 colour = mix(foam_lit, foam_mid, smoothstep(0.15, 0.6, a) * (1.0 - line));
	colour = mix(colour, foam_shade, lace.y * 0.85 * (1.0 - line));

	if (on_sand) {
		// What the last run-up left on the sand once the water is off it: fainter, creamier
		// lace that pops as the sand dries, and the beaded wash line at its highest reach.
		float left = 1.0 - wet;
		vec2 residue = foam_lace_cover(xz, run.y, foam_sand_life) * left;
		float line_aa = max(fwidth(u), 0.004);
		float beads = step(0.3, foam_lace_at(xz, foam_bubble_size * 0.8, false).x);
		// Faded out where it is thinner than the pixel drawing it: from far off it would be a
		// hairline tracing the whole coast - an outline, not a wash line.
		float resolved = clamp(0.06 / max(line_aa, 0.0001), 0.0, 1.0);
		float wash = (1.0 - smoothstep(0.03, 0.03 + line_aa * 1.5, abs(u - last_reach)))
			* beads * left * exp(-run.z / 10.0) * step(0.0, u) * resolved * resolved;
		float sand_cover = max(residue.x * 0.8, wash) * foam_sand_strength;
		vec3 sand_colour = mix(foam_lit, foam_mid, 0.35);
		colour = mix(colour, sand_colour, step(cover, sand_cover));
		cover = max(cover, sand_cover);
	}
	return vec4(colour, cover);
}

#endif
