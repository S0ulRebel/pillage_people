shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

// One puff of spray, drawn on a particle's quad: the chunky white blobs a toon waterfall
// throws up where it lands, and - at low opacity and large - the mist round its foot.
//
// A lumpy disc with a hard edge, lit as if it were a ball, so the sun gives it a white side
// and a pale blue one in two flat tones like everything else. It does not fade out as it
// dies; it is eaten away, crisply, from the edge inward - a fading blob is a soft particle,
// and the art is not soft.
//
// The particle's spin (INSTANCE_CUSTOM.x) is also its seed, so no two puffs are the same
// shape; INSTANCE_CUSTOM.y is how far through its life it is.

#include "res://props/waterfall/waterfall.gdshaderinc"

// How lit the side turned away from the sun is, against the side facing it. See water_light.
uniform float shaded_side : hint_range(0.0, 1.0) = 0.6;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec3 colour : source_color = vec3(0.84, 0.93, 0.98);
// The shaded side's tint, in place of grey.
uniform vec3 shade : source_color = vec3(0.52, 0.70, 0.88);
// 1 for the splash; well under for mist, which is seen through.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// Metres over which a puff fades where it meets the ground or the water. 0 is off: the
// splash is small and brief enough that a hard line at the waterline reads as it hitting
// the surface. The mist is big and sits there, and without it every puff is cut flat.
uniform float soft_contact : hint_range(0.0, 4.0) = 0.0;
// 0 is a hard edge, for the splash. The mist's edge is soft over this much of its radius: a
// hard-edged translucent blob the size of a house reads as a soap bubble, not as spray.
uniform float softness : hint_range(0.0, 1.0) = 0.0;

varying float age;
varying float seed;
varying float view_depth;


void vertex() {
	// Face the camera: the standard particle billboard, keeping the particle's own scale and
	// spinning it by its angle about the view axis.
	mat4 facing = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float spin = INSTANCE_CUSTOM.x;
	facing = facing * mat4(vec4(cos(spin), -sin(spin), 0.0, 0.0), vec4(sin(spin), cos(spin), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	age = INSTANCE_CUSTOM.y;
	seed = INSTANCE_CUSTOM.x * 7.31;
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// A lumpy outline: the radius wanders with the angle round the centre. Sampled on a
	// circle in noise space so it closes up with no seam.
	float angle = atan(p.y, p.x);
	float lumps = noise(vec2(cos(angle), sin(angle)) * 1.6 + seed);
	float outline = 0.66 + lumps * 0.30;
	// Eaten away as it dies, holes first and then the edge.
	float eaten = smoothstep(0.35, 1.0, age);
	float holes = noise(p * 2.6 + seed * 1.7);
	float inside = outline - r - eaten * (0.35 + holes * 0.9);
	float shape = softness > 0.0 ? smoothstep(0.0, softness, inside) : band(inside, 0.0);

	// A ball's normal, in view space, so the sun lights one side and not the other.
	vec3 ball = normalize(vec3(p, sqrt(max(1.0 - min(r, 1.0) * min(r, 1.0), 0.0)) + 0.35));
	NORMAL = ball;
	// A pale blue foot on each puff, the way the sheets shade their splash.
	float foot = band(-p.y + lumps * 0.4, 0.45);
	ALBEDO = mix(colour, shade, foot * 0.8) * COLOR.rgb;

	float contact = 1.0;
	if (soft_contact > 0.0) {
		float raw = texture(depth_texture, SCREEN_UV).r;
		vec4 unprojected = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		float scene_depth = -(unprojected.z / unprojected.w);
		contact = clamp((scene_depth - view_depth) / soft_contact, 0.0, 1.0);
	}
	// Mist is stepped too: a denser core and a thinner rim, not a gradient.
	float core = mix(0.6, 1.0, band(inside, 0.12));
	ALPHA = shape * opacity * core * contact * COLOR.a;
}


void light() {
	DIFFUSE_LIGHT += water_light(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, shaded_side);
}
