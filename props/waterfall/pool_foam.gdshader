shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

// Foam on the pool where the waterfall lands: a solid white churn along the line the water
// hits, and broken rings of foam spreading out from it and thinning as they go - the
// "Waterfall" swatch's white splash band and the pool round it.
//
// Drawn on a flat plane laid a hair above the water by waterfall.gd, after the sea (its
// render priority is higher), so the sea does not sort in front of it. Where the plane runs
// into the bank or the rock behind the fall, the depth test hides it; where the bed is only
// just under it, it fades - see Contact - which leaves a line of foam at the water's edge
// rather than a disc drawn over the sand.

#include "res://props/waterfall/waterfall.gdshaderinc"

// How lit the side turned away from the sun is, against the side facing it. See water_light.
uniform float shaded_side : hint_range(0.0, 1.0) = 0.6;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

// Set by waterfall.gd: half the width of the water where it lands, how far the foam reaches
// out past that, and the plane's size, all in metres.
uniform float half_width = 4.0;
uniform float reach = 12.0;
uniform vec2 size = vec2(32.0, 24.0);

uniform vec3 foam_colour : source_color = vec3(0.95, 0.98, 1.0);
// The water round the churn is lighter - full of air - before it is foam.
uniform vec3 aerated_colour : source_color = vec3(0.62, 0.90, 0.92);
// Metres out from the landing line that are solid white.
uniform float churn_metres : hint_range(0.0, 6.0) = 1.4;
// Metres between rings, and how fast they travel outward in metres per second.
uniform float ring_spacing : hint_range(0.3, 6.0) = 2.2;
uniform float ring_speed : hint_range(0.0, 4.0) = 0.9;

group_uniforms Contact;
uniform float soft_contact : hint_range(0.01, 2.0) = 0.25;

varying float view_depth;


void vertex() {
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}


void fragment() {
	// Metres on the plane, x along the fall's width and y out from the rock.
	vec2 q = (UV - 0.5) * size;
	// Distance to the landing line, not to a point: the fall is metres wide, so the foam is a
	// stadium round the line it lands on, not a circle round its middle.
	float d = length(vec2(max(abs(q.x) - half_width, 0.0), q.y));
	float wander = noise(q * 0.45 + vec2(0.0, TIME * 0.3)) - 0.5;
	float spread = d + wander * 1.2;
	float out_of = clamp(spread / reach, 0.0, 1.0);

	float churn = 1.0 - band(spread - churn_metres, 0.0);
	// Rings, thinner the further out they have got, and broken up into strokes by a second
	// noise so they read as foam lines rather than drawn circles.
	float ring = fract(spread / ring_spacing - TIME * ring_speed / ring_spacing);
	float ring_width = mix(0.30, 0.06, out_of);
	float rings = band(ring, 1.0 - ring_width);
	float broken = band(noise(q * 0.7 + vec2(TIME * 0.2, 0.0)) + (1.0 - out_of) * 0.25, 0.62);
	rings *= broken * (1.0 - band(out_of, 0.92));
	float aerated = 1.0 - band(out_of + wander * 0.15, 0.55);

	float foam = max(churn, rings);
	vec3 colour = mix(aerated_colour, foam_colour, foam);

	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 unprojected = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	float scene_depth = -(unprojected.z / unprojected.w);
	float contact = clamp((scene_depth - view_depth) / soft_contact, 0.0, 1.0);

	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	ALBEDO = colour;
	ALPHA = max(foam * 0.95, aerated * 0.35) * contact;
}


void light() {
	DIFFUSE_LIGHT += water_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, shaded_side);
}
