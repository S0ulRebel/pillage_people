shader_type canvas_item;

// A spyglass iris: black everywhere except a circular hole that opens and closes.
//
// Drawn as a full-screen rect rather than as a post-process, so it sits above everything the
// game draws and needs nothing from the scene underneath it.
//
// Two things make it read as a spyglass rather than as a hole punched in a black card:
//
//  * The edge is soft, and the softness is a fraction of the current radius rather than a
//    fixed width. A constant feather looks like blur when the iris is wide and like a smear
//    when it is nearly shut; scaling it keeps the same apparent edge all the way through.
//  * There is a band of falloff just inside the rim, so brightness drops off towards the edge
//    the way it does down a tube. Without it the hole looks cut out.

// 0 shuts the iris completely, 1 puts its edge on the nearest screen edge, and about 1.2
// clears the corners. Driven from spyglass.gd.
uniform float openness : hint_range(0.0, 1.5) = 0.0;
// Edge feather, as a fraction of the radius.
uniform float softness : hint_range(0.001, 0.6) = 0.12;
// How far in from the rim the view starts to darken, and how much.
uniform float falloff : hint_range(0.0, 1.0) = 0.35;
uniform float falloff_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec4 surround : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Screen width over height, set from the script. Without it the iris is an ellipse on any
// screen that is not square.
uniform float aspect = 1.7777778;

void fragment() {
	// Measured from the middle, with x stretched by the aspect so the shape stays circular.
	vec2 from_centre = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	// Divided by the half-height so that a radius of 1 reaches the top and bottom edges.
	float distance_out = length(from_centre) / 0.5;

	// Fully shut is a special case: at openness 0 the feather would still leave a pinhole,
	// and a pinhole of the scene in the middle of a black screen is very visible.
	float edge = max(openness, 0.0);
	float feather = max(edge * softness, 0.0005);
	// 1 inside the iris, 0 outside it.
	float inside = 1.0 - smoothstep(edge - feather, edge + feather, distance_out);
	inside *= step(0.0001, edge);

	// The darkening towards the rim, inside the opening.
	float towards_rim = clamp((distance_out - edge * (1.0 - falloff)) / max(edge * falloff, 0.0001), 0.0, 1.0);
	float shade = 1.0 - towards_rim * falloff_strength;

	COLOR = vec4(surround.rgb, surround.a * (1.0 - inside * shade));
}
