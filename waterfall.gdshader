shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

// Falling water, drawn without a texture - the same way ocean.gdshader gets its surface.
//
// Three things make this read as water rather than as a striped plane:
//
//  * The streaks accelerate. Water leaving a lip is slow and gathers speed, so the bands have
//    to stretch as they descend. Evenly spaced stripes scrolling at a constant rate read as a
//    conveyor belt, which is the usual giveaway.
//  * It fades where it meets anything. Without that, a transparent sheet cutting through the
//    captain draws a hard line straight across him, as though he had been sliced. The scene
//    depth is compared against this fragment's own, and the alpha is taken down as the two
//    approach - so the water thins out and wraps around him instead.
//  * The edges are soft and the lip is bright. A ribbon with hard sides is a ribbon.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

group_uniforms Colour;
uniform vec3 water_colour : source_color = vec3(0.62, 0.86, 0.90);
uniform vec3 foam_colour : source_color = vec3(0.95, 0.99, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.60;

group_uniforms Flow;
uniform float speed : hint_range(0.0, 8.0) = 1.7;
uniform float streaks : hint_range(1.0, 40.0) = 9.0;
// How much faster the water is at the bottom than at the top. 0 is a conveyor belt.
uniform float acceleration : hint_range(0.0, 3.0) = 1.2;
uniform float streak_contrast : hint_range(0.0, 1.0) = 0.55;
// Sideways variation, so every column of water is not the same column of water.
uniform float lanes : hint_range(1.0, 40.0) = 11.0;

group_uniforms Shape;
// How far from the lip the water is still gathering, and how far from the base it breaks up.
uniform float lip_fade : hint_range(0.0, 0.5) = 0.06;
uniform float base_froth : hint_range(0.0, 0.6) = 0.22;
uniform float edge_fade : hint_range(0.0, 0.5) = 0.16;

group_uniforms Contact;
// Metres. Over this distance to whatever is behind, the sheet fades out completely.
uniform float soft_contact : hint_range(0.01, 3.0) = 0.45;

varying float view_depth;


float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}


void vertex() {
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}


void fragment() {
	// v runs 0 at the lip to 1 at the pool.
	float v = UV.y;
	float u = UV.x;

	// Accelerating fall. Raising v to a power above one bunches the bands near the top and
	// stretches them toward the bottom, which is what gravity does to a falling sheet.
	float travelled = pow(v, 1.0 + acceleration);
	float lane = floor(u * lanes);
	float offset = hash(lane) * 6.28318;
	float phase = travelled * streaks - TIME * speed + offset;

	// Two rates of streak so the sheet does not pulse as one object.
	float streak = 0.5 + 0.5 * sin(phase * 6.28318);
	streak = mix(streak, 0.5 + 0.5 * sin(phase * 3.14159 + 1.7), 0.35);
	float brightness = mix(1.0 - streak_contrast, 1.0, streak);

	// White at the lip where it is still thin and aerated, and again at the base where it
	// breaks up on the water.
	float lip = 1.0 - smoothstep(0.0, lip_fade, v);
	float froth = smoothstep(1.0 - base_froth, 1.0, v);
	float white = clamp(lip + froth * (0.5 + 0.5 * streak), 0.0, 1.0);

	vec3 colour = mix(water_colour * brightness, foam_colour, white);

	// Soft sides. A hard-edged ribbon looks like a ribbon.
	float sides = smoothstep(0.0, edge_fade, u) * smoothstep(0.0, edge_fade, 1.0 - u);

	// Soft contact against whatever is behind, which is what stops this cutting a hard line
	// across the captain when he walks under it. Godot's depth buffer is reverse-Z, so the
	// fragment is unprojected rather than read as a distance.
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
	vec4 unprojected = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_depth = -(unprojected.z / unprojected.w);
	float contact = clamp((scene_depth - view_depth) / soft_contact, 0.0, 1.0);

	ALBEDO = colour;
	ALPHA = base_alpha * sides * contact * mix(0.75, 1.0, brightness);
}
