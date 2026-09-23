shader_type spatial;
// A fish that swims in its own vertex shader.
//
// The model has no skeleton, and that turned out to be the right shape for a school rather
// than a problem. Bones would mean one Skeleton3D per fish and a pose written every frame; a
// vertex shader costs nothing per fish and works inside a MultiMesh, so forty of them are one
// draw call and the CPU never touches them.
//
// The bend is the same travelling wave the shark's spine does and the ocean's surface does -
// see shark.gd and ocean.gdshader. Here it is applied to the vertices directly.
//
// Nose is -Z and tail is +Z (baked into the file by tools/reorient_model.py, not corrected
// here), and the body spans about -0.5 to +0.5, so `along` runs 0 at the nose to 1 at the tail.

render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
// Tail beats per second.
uniform float beat = 2.1;
// How far the tail swings, in model units - the body is one unit long, so 0.09 is about a
// tenth of a body length each way.
uniform float sway = 0.09;
// Radians of wave across the body. This is what makes it travel from nose to tail instead of
// the whole fish wagging in one piece.
uniform float wave_spread = 5.0;
// A slow vertical drift, so a school does not look like a rigid lattice being towed along.
uniform float bob = 0.035;
uniform float bob_rate = 0.55;

const float TWO_PI = 6.2831853;

void vertex() {
	// Per-instance phase, written by fish_school.gd into the MultiMesh's custom data. Without
	// it every fish in the school beats its tail on exactly the same frame, which reads as one
	// object rather than as forty animals.
	float phase = INSTANCE_CUSTOM.x * TWO_PI;

	float along = clamp(VERTEX.z + 0.5, 0.0, 1.0);
	// Squared, so the nose is nearly still and the tail does the work. Linear makes the whole
	// fish slalom, which looks like an eel.
	float weight = along * along;
	VERTEX.x += sin(TIME * beat * TWO_PI + phase - along * wave_spread) * sway * weight;
	VERTEX.y += sin(TIME * bob_rate * TWO_PI + phase) * bob;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb;
	// Flat, like everything else in this world. A fish arriving shinier than the sea it is in
	// reads as a different game.
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
