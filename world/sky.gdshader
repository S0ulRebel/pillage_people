shader_type sky;

// Daylight from the terrain sheets: clear blue overhead, a pale horizon, and a few
// clouds large enough to count. No texture — the sea and the falls are drawn the
// same way, and a noise field at this camera turns into grain.
//
// The horizon is the scene fog colour. A second colour there draws a line where the
// sky meets the sea, which is the only place this can be judged. Fog itself is kept
// almost off the sky (fog_sky_affect on the environment): the far plane is kilometres
// out, and a full fog wash flattens this dome back to one pale blue.

group_uniforms Colour;
uniform vec3 zenith_colour : source_color = vec3(0.22, 0.50, 0.88);
uniform vec3 horizon_colour : source_color = vec3(0.70, 0.86, 0.92);
// Below the horizon the sky still feeds ambient light. Matching the pale horizon
// keeps undersides from going black; the sea is what you actually see down there.
uniform vec3 below_colour : source_color = vec3(0.55, 0.74, 0.84);
// Degrees of haze above the sea. The chase camera never looks higher than about
// 18 degrees, so a tall fade leaves the whole visible sky the horizon colour.
uniform float haze_degrees : hint_range(2.0, 30.0) = 7.0;

group_uniforms Clouds;
uniform vec3 cloud_colour : source_color = vec3(0.97, 0.98, 1.0);
uniform vec3 cloud_shadow_colour : source_color = vec3(0.62, 0.75, 0.88);
uniform float cloud_softness : hint_range(0.01, 0.35) = 0.14;
uniform float cloud_speed : hint_range(0.0, 0.2) = 0.012;
uniform float preview_time = -1.0; // Negative uses live drift. Fixed for captures.

group_uniforms Sun;
uniform vec3 sun_colour : source_color = vec3(1.0, 0.97, 0.86);
// Angular RADIUS in degrees, not a cosine threshold. The real sun is a quarter of a degree;
// this is a cartoon one and wants to be a shape you can see.
uniform float sun_degrees : hint_range(0.5, 12.0) = 2.6;
// A stepped halo rather than a smooth falloff. The terrain bands its colours and the sea
// bands its depth, so a sun with a soft photographic bloom around it is the one object in the
// scene lit by a different set of rules. These are rings you can count.
uniform float halo_degrees : hint_range(0.0, 20.0) = 5.5;
uniform int halo_rings : hint_range(1, 5) = 2;
uniform float halo_strength : hint_range(0.0, 1.0) = 0.45;
// The broad warm lift across the sky around it. Kept, because that is atmosphere rather than
// a lens artifact, and it is what stops the disc looking pasted on.
uniform float sun_glow : hint_range(0.0, 1.0) = 0.28;
// Direction TO the sun, pushed from main.gd off the scene's DirectionalLight.
//
// LIGHT0_DIRECTION below is the engine's own route and is used when this is left at zero, but
// it cannot be relied on: it only arrives if the light is feeding the sky, and when it does
// not the shader silently falls back to a constant. The disc then sits at a bearing and an
// elevation that have nothing to do with the light, the shadows point one way and the sun is
// somewhere else, and nothing errors. Setting it explicitly means both agree by construction.
uniform vec3 sun_direction = vec3(0.0, 0.0, 0.0);


// One cumulus mass: three overlapping ellipses, so the outline is a lump rather
// than a circle. The sheets are masses you can count, not a field of specks.
float puff(vec2 p, vec2 centre, vec2 radius) {
	vec2 main_r = (p - centre) / radius;
	vec2 right_r = (p - centre - vec2(radius.x * 0.55, radius.y * 0.1)) / (radius * vec2(0.7, 0.58));
	vec2 left_r = (p - centre + vec2(radius.x * 0.46, -radius.y * 0.02)) / (radius * vec2(0.58, 0.5));
	float edge = min(dot(main_r, main_r), min(dot(right_r, right_r), dot(left_r, left_r)));
	return 1.0 - smoothstep(1.0 - cloud_softness, 1.0, edge);
}


void sky() {
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	float above = clamp(up, 0.0, 1.0);
	float haze = smoothstep(0.0, sin(radians(haze_degrees)), above);
	vec3 col = mix(horizon_colour, zenith_colour, haze);

	// LIGHT0_DIRECTION is where the photons travel, down into the island. The disc
	// sits the other way, or the sun and the shadows disagree.
	vec3 to_sun = vec3(0.42, 0.64, 0.64);
	if (length(sun_direction) > 0.001) {
		to_sun = normalize(sun_direction);
	} else if (LIGHT0_ENABLED) {
		// LIGHT0_DIRECTION is where the photons travel, down into the island. The disc sits
		// the other way, or the sun and the shadows disagree.
		to_sun = normalize(-LIGHT0_DIRECTION);
	}
	float facing = dot(dir, to_sun);
	float glow = pow(max(facing, 0.0), 12.0) * sun_glow;
	col = mix(col, sun_colour, glow * above);

	if (up > 0.0) {
		float now = preview_time >= 0.0 ? preview_time : TIME;
		// Divide by height so the masses sit on the dome. They are parked low on
		// purpose: cot(elevation) is about 4 to 6 for the band this camera can
		// actually see, and anything nearer the zenith is out of frame.
		vec2 uv = dir.xz / max(up, 0.08);
		uv.x += now * cloud_speed;
		vec2 sun_flat = normalize(to_sun.xz + vec2(0.0001));
		float cover = 0.0;
		float lit = 0.0;
		// Two rings in the band the camera can see (about 6 to 18 degrees up).
		// Six was sparse enough that a shore view could look between them.
		for (int i = 0; i < 5; i++) {
			float a = float(i) * TAU / 5.0;
			vec2 centre = vec2(cos(a), sin(a)) * 4.5;
			vec2 radius = vec2(2.15, 1.05);
			cover += puff(uv, centre, radius);
			lit += puff(uv - sun_flat * 0.28, centre, radius);
		}
		for (int i = 0; i < 4; i++) {
			float a = float(i) * TAU / 4.0 + 0.4;
			vec2 centre = vec2(cos(a), sin(a)) * 3.15;
			vec2 radius = vec2(1.45, 0.72);
			cover += puff(uv, centre, radius);
			lit += puff(uv - sun_flat * 0.28, centre, radius);
		}
		cover = clamp(cover, 0.0, 1.0);
		lit = clamp(lit, 0.0, 1.0);
		// Gone before the sea, so a cloud never becomes a bar lying on the water.
		float lift = smoothstep(0.02, 0.1, up);
		vec3 cloud = mix(cloud_shadow_colour, cloud_colour, smoothstep(0.15, 0.7, lit));
		col = mix(col, cloud, cover * lift);
		// Worked in degrees from the sun's centre, which is what the sizes above mean.
		float away = degrees(acos(clamp(facing, -1.0, 1.0)));
		// One pixel's worth of angle, so the rim is clean rather than stair-stepped - and it
		// tracks the field of view, which matters here: through the spyglass at 4x a pixel
		// covers a hundredth of the angle it does normally, and a fixed feather that looks
		// crisp at 60 degrees is thirty pixels of blur at 5.5.
		float aa = max(fwidth(away), 0.0001);
		float disc = 1.0 - smoothstep(sun_degrees - aa, sun_degrees + aa, away);
		// Stepped rings outside the disc. floor() is what makes them rings instead of a fade.
		float out_t = clamp((away - sun_degrees) / max(halo_degrees, 0.001), 0.0, 1.0);
		float rings = 1.0 - floor(out_t * float(halo_rings)) / float(halo_rings);
		rings *= step(away, sun_degrees + halo_degrees) * halo_strength;
		col = mix(col, sun_colour, max(disc, rings));
	} else {
		col = mix(horizon_colour, below_colour, pow(clamp(-up, 0.0, 1.0), 0.45));
	}
	COLOR = col;
}
