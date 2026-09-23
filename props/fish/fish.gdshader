shader_type spatial;
// A fish that swims in its own vertex shader.
//
// The model has no skeleton, and that turned out to be the right shape for a school rather
// than a problem. Bones would mean one Skeleton3D per fish and a pose written every frame; a
// vertex shader costs nothing per fish and works inside a MultiMesh, so a whole school is one
// draw call and the CPU never touches a vertex.
//
// The motion is four simple motions stacked, which is the approach the Abzu developers
// described in their GDC talk. No single one of them looks like a fish:
//
//   1. the whole body yaws about its pivot
//   2. the whole body slides side to side
//   3. it rolls about its own spine, the roll LAGGING toward the tail
//   4. it yaws again, also lagging toward the tail
//
// Together they read as a living animal. The lag in 3 and 4 is what makes the motion travel
// from nose to tail instead of the fish wagging in one rigid piece, and the roll is what stops
// it looking like a cardboard cut-out on a hinge.
//
// ORDER MATTERS. The rigid yaw has to happen BEFORE the side-to-side slide. The other way
// round, the slide gets rotated too and the fish swims along a wobbling line rather than
// snaking along a straight one.
//
// Nose is -Z and tail is +Z, and the origin is the body's middle - all three baked into the
// file by tools/reorient_model.py, not corrected here. `body_half` is measured off the mesh
// AABB by fish_school.gd rather than written down, so re-baking the model at another size
// cannot silently put the bend in the wrong place.

render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;

// Half the body length in metres, along Z. Pushed in from the measured mesh.
uniform float body_half = 0.175;

// 1. Rigid yaw about the pivot.
uniform float yaw_body : hint_range(0.0, 30.0) = 4.0;
// 2. Side to side, in metres.
uniform float side_sway : hint_range(0.0, 0.5) = 0.035;
uniform float side_phase : hint_range(0.0, 6.3) = 1.6;
// 3. Roll about the spine. `spread` is how much of a wave fits across the body - this is the
// motion that gives the swim its gooey, organic feel, and it is the one nobody expects.
uniform float roll_spine : hint_range(0.0, 90.0) = 22.0;
uniform float roll_spread : hint_range(0.0, 6.3) = 2.2;
uniform float roll_phase : hint_range(0.0, 6.3) = 0.9;
// 4. The travelling yaw - a flag in the wind.
uniform float yaw_wave : hint_range(0.0, 60.0) = 17.0;
uniform float yaw_spread : hint_range(0.0, 6.3) = 3.1;

// How much of the swing the nose keeps. A fish's head barely moves while its tail does the
// work, so the travelling motions are weighted along the body; 0 would pin the nose dead still.
uniform float nose_stillness : hint_range(0.0, 1.0) = 0.75;

const float TWO_PI = 6.2831853;

// A rotation in the plane of whichever two components are handed in.
vec2 turn(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

void vertex() {
	// Phase and intensity come per fish from the MultiMesh's custom data, written by
	// fish_school.gd. Phase is ACCUMULATED on the CPU rather than derived from TIME here: the
	// beat speeds up and slows down with the fish, and `TIME * beat` jumps backwards the
	// instant beat changes, which reads as the animation stuttering.
	//
	// Without a per-fish phase every fish in the school beats its tail on the same frame, which
	// reads as one object rather than as a hundred animals.
	float t = INSTANCE_CUSTOM.x * TWO_PI;
	float intensity = INSTANCE_CUSTOM.y;

	// 0 at the nose, 1 at the tail.
	float along = clamp(VERTEX.z / (2.0 * body_half) + 0.5, 0.0, 1.0);
	float weight = mix(1.0 - nose_stillness, 1.0, along * along);

	vec3 p = VERTEX;
	vec3 n = NORMAL;

	// 1. rigid yaw, then 2. the slide. This order, for the reason at the top.
	float a1 = radians(yaw_body) * intensity * sin(t);
	p.xz = turn(p.xz, a1);
	n.xz = turn(n.xz, a1);

	p.x += side_sway * intensity * sin(t + side_phase);

	// 3. roll about the spine, lagging toward the tail.
	float a3 = radians(roll_spine) * intensity * weight * sin(t + roll_phase - along * roll_spread);
	p.xy = turn(p.xy, a3);
	n.xy = turn(n.xy, a3);

	// 4. the travelling yaw.
	float a4 = radians(yaw_wave) * intensity * weight * sin(t - along * yaw_spread);
	p.xz = turn(p.xz, a4);
	n.xz = turn(n.xz, a4);

	VERTEX = p;
	NORMAL = normalize(n);
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	// Flat, like everything else in this world. A fish arriving shinier than the sea it is in
	// reads as a different game.
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
