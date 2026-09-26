// Cloud shadows: dark blobs drifting across the ground and the sea, shared by
// world/terrain.gdshader and world/ocean.gdshader so a shadow runs from the hill onto the
// water without a seam.
//
// Not the sky's clouds - those are painted on the dome at no particular distance, and have
// no position to cast from. These are the same weather: `cloud_cover` and `cloud_storm` are
// the global shader parameters the sky reads (Project Settings > Shader Globals), so an
// overcast sky shades most of the island and a clear one almost none of it. `cloud_drift` is
// how far the wind has carried them, in metres; world/wind.gd adds to it every frame.
//
// A deck of flat blobs at cloud_shadow_height, projected down along the sun: at noon the
// shadow lies under its cloud, toward evening it stretches away from the sun, and as the sun
// swings it slides across the island rather than sitting still. Hard-edged, a few metres of
// edge, in the ground's toon style - a soft shadow the size of a hill reads as a dirty patch.

global uniform float cloud_cover;
global uniform float cloud_storm;
global uniform vec2 cloud_drift;

// Metres up the deck is. Only matters for how far the shadows slide with the sun.
const float cloud_shadow_height = 400.0;
// Metres across a typical cloud's shadow. The island is 620 m across: a few shadows at once.
const float cloud_shadow_size = 150.0;
// How much of the sun a cloud takes away: most of it in a squall, half on a fair day.
const float cloud_shadow_fair = 0.6;
const float cloud_shadow_squall = 0.8;

float cloud_shadow_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float cloud_shadow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_shadow_hash(i), cloud_shadow_hash(i + vec2(1.0, 0.0)), f.x),
		mix(cloud_shadow_hash(i + vec2(0.0, 1.0)), cloud_shadow_hash(i + vec2(1.0)), f.x), f.y);
}

// How much sunlight gets through the clouds at a point: 1 in the open, less under a cloud.
// `to_sun` points from the ground to the sun.
float cloud_sun(vec3 world_point, vec3 to_sun) {
	float cover = clamp(cloud_cover, 0.0, 1.0);
	if (cover <= 0.0 || to_sun.y <= 0.02) {
		return 1.0;
	}
	// Up the sun's ray to the deck, then across to where the wind has taken the clouds.
	vec2 on_deck = world_point.xz + to_sun.xz / to_sun.y * (cloud_shadow_height - world_point.y);
	vec2 q = (on_deck - cloud_drift) / cloud_shadow_size;
	float blobs = cloud_shadow_noise(q) * 0.65 + cloud_shadow_noise(q * 2.3 + 5.2) * 0.35;
	// Thresholded to the cover: at 0.55 (TRADE-WIND CUMULUS) about a quarter of the ground is
	// in shadow at any moment; at 1, nearly all of it.
	float threshold = 0.82 - 0.45 * cover;
	// A pixel's worth of edge, but never under a few metres - too hard and it crawls as the
	// shadow moves - nor so much that it smears, which it can beside a pixel the sea threw away.
	float edge = clamp(fwidth(blobs), 0.012, 0.08);
	float shadow = smoothstep(threshold - edge, threshold + edge, blobs);
	return 1.0 - shadow * mix(cloud_shadow_fair, cloud_shadow_squall, clamp(cloud_storm, 0.0, 1.0));
}
