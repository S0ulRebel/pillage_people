shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

// Falling water, drawn without a texture, in the game's toon style: flat colour bands with
// hard edges, the way the ocean and the ground are drawn.
//
// What the art sheets draw (the "Waterfall" swatch and the jungle panels in
// art/references/) and how each is got here:
//
//  * Long VERTICAL streaks, light on a mid blue. Noise stretched many times longer down the
//    fall than across it, scrolled downward, and cut into three bands and a white. The first
//    version drew sin() of the height - horizontal stripes, which is a conveyor belt.
//  * A column, not a veil. The body is nearly opaque; only its darkest band lets the rock
//    through a little. The veil sheet in front (veil = 1) draws the bright streaks alone.
//  * A white lip where the water breaks over, and a bottom that goes white and misty. Both
//    have ragged, hard edges, cut from the same noise, not soft fades.
//  * Ragged sides. The sheet is eaten back from its edges by noise, crisply - a soft-sided
//    ribbon is a ribbon.
//
// Lit, in two flat tones (water_light in waterfall.gdshaderinc), so it darkens at night with
// everything else and the sheet's bow gives it a lit and a shaded side. It also fades where it
// meets anything - see Contact.

#include "res://props/waterfall/waterfall.gdshaderinc"

// How lit the side turned away from the sun is, against the side facing it. See water_light.
uniform float shaded_side : hint_range(0.0, 1.0) = 0.6;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

group_uniforms Colour;
// The mid band. The dark band and the light one are derived from it, so one colour picks
// the whole ramp.
uniform vec3 water_colour : source_color = vec3(0.26, 0.42, 0.60);
uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
// Where the three band edges fall on the noise, low to high. Wider gaps, more of that band.
uniform vec3 band_edges = vec3(0.28, 0.54, 0.74);

group_uniforms Flow;
// Metres per second at the bottom of the fall.
uniform float speed : hint_range(0.0, 30.0) = 7.0;
// How many streaks across the fall - a count, because they fan out with the water - and how
// long one is, in metres, so a 5 m fall and a 50 m one draw streaks the same length.
uniform float streaks : hint_range(1.0, 40.0) = 10.0;
uniform float streak_length : hint_range(1.0, 40.0) = 9.0;
// Set from the curve by waterfall.gd. Without it nothing here knows how long the drop is.
uniform float fall_length = 10.0;
// How much faster the water is at the bottom than at the top. 0 is a conveyor belt.
uniform float acceleration : hint_range(0.0, 3.0) = 1.0;
// Metres the sheet sways in and out. Most at the bottom, none at the lip.
uniform float wobble : hint_range(0.0, 1.0) = 0.18;
// 0 is the body, 1 the veil in front of it. Set by waterfall.gd.
uniform float veil : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

group_uniforms Shape;
// Metres of white at the lip, and how far its lower edge wanders.
uniform float lip_metres : hint_range(0.0, 6.0) = 2.4;
// The bottom goes white over this fraction of the drop, and is solid foam over the last few
// metres.
uniform float mist_fraction : hint_range(0.0, 1.0) = 0.32;
uniform float froth_metres : hint_range(0.0, 10.0) = 2.5;
// How far in from each side the edge is eaten back, at most, in metres.
uniform float ragged_metres : hint_range(0.0, 2.0) = 0.45;

group_uniforms Contact;
// Metres. Over this distance to whatever is behind, the sheet fades out completely.
uniform float soft_contact : hint_range(0.01, 3.0) = 0.45;

varying float view_depth;


void vertex() {
	// Sway. Along the normal, so the column breathes in and out rather than sliding sideways,
	// and scaled by how far down it is: the lip is held by the rock.
	float down = UV.y;
	float sway = noise(vec2(UV2.y * 0.12 - TIME * 0.6, UV.x * 2.0 + seed)) - 0.5;
	VERTEX += NORMAL * sway * wobble * 2.0 * down;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}


void fragment() {
	float along = UV2.y;
	float edge_metres = UV2.x;
	float from_foot = fall_length - along;

	// Accelerating fall. The pattern coordinate is bunched up near the lip and stretched out
	// toward the bottom, which is what gravity does to a falling sheet - the streaks lengthen
	// and speed up as they drop.
	float fall = pow(UV.y, 1.0 + acceleration) * fall_length;
	vec2 p = vec2(UV.x * streaks + seed, (fall - TIME * speed) / streak_length);
	// Two layers at different rates and sizes, or the whole sheet moves as one pattern.
	float n = noise(p) * 0.62
		+ noise(vec2(p.x * 2.3 + 5.1, p.y * 1.7 - TIME * speed * 0.35 / streak_length)) * 0.38;
	// A fine, fast third layer only for breaking band edges up.
	float grain = noise(vec2(p.x * 6.0, p.y * 5.0 - TIME * 0.8));
	float tone = n + (grain - 0.5) * 0.12;

	// White at the lip, eaten into ragged teeth by the streak noise.
	float lip = 1.0 - band(along - n * lip_metres * 0.9, lip_metres * 0.55);
	// Whiter toward the bottom, where the fall breaks up into spray. The band edges do the
	// rest: raising the tone pushes more of the sheet over each edge, so the bottom turns
	// white in steps rather than as a gradient.
	float mist = smoothstep(fall_length * (1.0 - mist_fraction), fall_length, along);
	tone += mist * 0.55;
	float froth = 1.0 - band(from_foot - n * froth_metres * 0.8, froth_metres * 0.5);

	vec3 deep = water_colour * vec3(0.62, 0.80, 0.84);
	vec3 light = mix(water_colour, foam_colour, 0.36);
	vec3 colour = deep;
	colour = mix(colour, water_colour, band(tone, band_edges.x));
	colour = mix(colour, light, band(tone, band_edges.y));
	colour = mix(colour, foam_colour, band(tone, band_edges.z));
	colour = mix(colour, foam_colour, max(lip, froth));

	// Ragged sides: each edge eaten back by noise by up to ragged_metres, crisply.
	float bite = noise(vec2(along * 0.35 - TIME * speed * 0.08, seed * 3.0 + step(0.5, UV.x) * 11.0));
	float sides = band(edge_metres - bite * ragged_metres, 0.02);

	// The body is nearly solid, its darkest band letting a little of the rock through. The
	// veil draws only what is above the light edge.
	float body = mix(0.80, 0.97, band(tone, band_edges.x));
	float bright = band(tone, band_edges.y + 0.08) * 0.9;
	float cover = mix(body, bright, veil);
	cover = max(cover, max(lip, froth) * (1.0 - veil));
	// A ragged top, not a straight cut: the curve's first point is rarely exactly where the
	// water leaves the rock, and a ruled line there reads as the edge of a board.
	cover *= band(along - n * 0.9, 0.12);

	// Soft contact against whatever is behind, which is what stops this cutting a hard line
	// across the captain when he walks under it. Godot's depth buffer is reverse-Z, so the
	// fragment is unprojected rather than read as a distance.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 unprojected = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -(unprojected.z / unprojected.w);
	float contact = clamp((scene_depth - view_depth) / soft_contact, 0.0, 1.0);

	ALBEDO = colour;
	ALPHA = cover * sides * contact;
}


void light() {
	DIFFUSE_LIGHT += water_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, shaded_side);
}
