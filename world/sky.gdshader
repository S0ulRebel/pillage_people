shader_type sky;

// THE SKY: a day and a night from the two sky sheets, art/references/sky-and-clouds-v1.png
// ("day sky.png") and night-sky-and-moon-v1.png ("night sky.png"), with the golden hour
// between them. Every colour below was measured off those sheets (median of the panel's
// bands, lit and shaded cloud pixels, the discs and their halos), and tests/sky_view.gd
// measures the rendered sky the same way.
//
// No texture. The sea and the falls are drawn the same way, and a noise field at this camera
// turns into grain: the clouds are a few masses you can count, each painted from small
// brush stamps in four shades the way the sheet paints them, and the stars are hashed points.
//
// The horizon line is the scene fog colour, because that is where the sky meets the sea, and
// the sea hazes to the fog (world/ocean.gdshader). Fog itself is kept almost off the sky
// (fog_sky_affect on the environment): the far plane is kilometres out, and a full fog wash
// flattens this dome back to one pale blue.
//
// WHO SETS WHAT. world/day.gd pushes sun_direction and daylight every frame; everything else
// is the material's own (world/sky_material.tres sets nothing, so the defaults here are what
// runs - edit them here or on the material).
//
// sky() builds the picture in this order:
//   1. where this pixel looks: elevation, azimuth, and the sun and moon directions
//   2. the day and night gradients, mixed by daylight, then the golden hour laid over both
//   3. the sun: disc, soft halo, broad glow
//   4. the moon, with its phase, and its halo
//   5. the stars
//   6. the clouds, painted in the shades of the hour, in front of all of it
//   7. out

// ---- Day --------------------------------------------------------------------------------
group_uniforms Day;
// The gradient, bottom to top: the fog colour ON the horizon line, then the sheet's bright
// cyan low band by haze_degrees up, its mid blue by mid_degrees, its deep blue at the zenith.
// TROPICAL CLEAR: bottom fifth (0.47, 0.85, 0.99), middle (0.22, 0.71, 0.99), top (0.13, 0.50,
// 0.90).
uniform vec3 horizon_colour : source_color = vec3(0.70, 0.86, 0.92);
uniform vec3 low_colour : source_color = vec3(0.47, 0.85, 0.99);
uniform vec3 mid_colour : source_color = vec3(0.22, 0.71, 0.99);
uniform vec3 zenith_colour : source_color = vec3(0.13, 0.50, 0.90);
// Below the horizon the sky still feeds ambient light. Matching the pale horizon keeps
// undersides from going black; the sea is what you actually see down there.
uniform vec3 below_colour : source_color = vec3(0.55, 0.74, 0.84);
// Degrees above the horizon over which the pale line becomes the cyan band. Narrow: the
// sheet is saturated right down to the sea. (It was 7, which made everything the chase
// camera can see one pale blue.)
uniform float haze_degrees : hint_range(0.5, 10.0) = 2.0;
// Degrees above the horizon at which the cyan has become the mid blue, and at which the
// deep blue is reached. The sheet's panel is about 55 degrees tall (its sun is 9% of the
// height and ours is 5.2 degrees across), and its top row is already the deep blue.
uniform float mid_degrees : hint_range(5.0, 60.0) = 25.0;
uniform float zenith_degrees : hint_range(20.0, 90.0) = 55.0;

// ---- Golden hour ------------------------------------------------------------------------
group_uniforms Golden_Hour;
// GOLDEN-HOUR GLOW, measured by rows relative to its sun: orange at the sun's own height
// (0.99, 0.65, 0.40), coral twelve degrees above it (0.79, 0.53, 0.58) - and the same coral
// right across the panel, twenty-eight degrees of bearing from the sun as beside it -
// violet-blue at the top (0.38, 0.45, 0.78). Its clouds cluster in four shades: violet
// (0.60, 0.50, 0.68), coral (0.77, 0.50, 0.56), salmon (0.92, 0.55, 0.47), gold (0.99, 0.69,
// 0.40). Full from one to six degrees of sun elevation, fading out by sunset_degrees up
// and by six degrees under. It rides on its own schedule, the sun's height, laid over
// whatever mix of day and night daylight gives: day.gd's daylight is 0.12 with the sun on
// the horizon, so a sunset mixed into the day side alone was drawn on a night sky.
uniform vec3 sunset_sun_colour : source_color = vec3(0.99, 0.65, 0.40);
uniform vec3 sunset_glow_colour : source_color = vec3(0.79, 0.53, 0.58);
uniform vec3 sunset_sky_colour : source_color = vec3(0.38, 0.45, 0.78);
uniform vec3 sunset_cloud_white : source_color = vec3(0.99, 0.69, 0.40);
uniform vec3 sunset_cloud_light : source_color = vec3(0.92, 0.55, 0.47);
uniform vec3 sunset_cloud_mid : source_color = vec3(0.77, 0.50, 0.56);
uniform vec3 sunset_cloud_shadow : source_color = vec3(0.60, 0.50, 0.68);
uniform float sunset_degrees : hint_range(2.0, 40.0) = 15.0;

// ---- Night ------------------------------------------------------------------------------
group_uniforms Night;
// 1 is noon, 0 is night. world/day.gd writes it; the sun, moon, stars and clouds follow.
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
// FULL MOON: bottom fifth (0.17, 0.46, 0.76), middle (0.05, 0.25, 0.56), top (0.05, 0.17,
// 0.43): a luminous blue night, four times brighter than the near-black this used to be. The
// horizon line is the same teal as the low band - the sheet has no dark rim at the sea - so
// world/day.gd's night fog, which the sea hazes to, wants to be this colour too.
uniform vec3 night_horizon : source_color = vec3(0.17, 0.46, 0.76);
uniform vec3 night_low : source_color = vec3(0.17, 0.46, 0.76);
uniform vec3 night_mid : source_color = vec3(0.05, 0.25, 0.56);
uniform vec3 night_zenith : source_color = vec3(0.05, 0.17, 0.43);
// Moonlit clouds, FULL MOON's, in four shades: lavender-white (0.78, 0.76, 0.86), pale blue
// (0.62, 0.64, 0.82), the blue most of the cloud is (0.44, 0.56, 0.84), and the shadow
// (0.37, 0.42, 0.62).
uniform vec3 night_cloud_white : source_color = vec3(0.74, 0.73, 0.86);
uniform vec3 night_cloud_light : source_color = vec3(0.62, 0.64, 0.82);
uniform vec3 night_cloud_mid : source_color = vec3(0.44, 0.56, 0.84);
uniform vec3 night_cloud_shadow : source_color = vec3(0.37, 0.42, 0.62);

// ---- Moon -------------------------------------------------------------------------------
group_uniforms Moon;
// Opposite the sun, so it rises as the sun sets. Ivory (0.99, 0.96, 0.80), a third again the
// sun's size on the sheet, with a halo like the sun's: measured as a mix toward the moon's
// colour, 0.49 at the rim, 0.29 at 1.4 radii, 0.16 at 1.9, 0.08 at 2.75, a trace at 3.5.
uniform vec3 moon_colour : source_color = vec3(0.99, 0.96, 0.80);
uniform float moon_degrees : hint_range(0.5, 12.0) = 3.5;
uniform float moon_halo_degrees : hint_range(0.0, 20.0) = 12.0;
uniform float moon_halo_strength : hint_range(0.0, 1.0) = 0.5;
// 1 full, 0.5 half, 0 new: a dark disc slid across the bright one from the side.
uniform float moon_phase : hint_range(0.0, 1.0) = 1.0;

// ---- Stars ------------------------------------------------------------------------------
group_uniforms Stars;
// Sparse, tiny, deliberate: forty to sixty in a clear panel of the sheet, none in its
// bottom two fifths where the sky is bright. One star at most per cell of star_cell_degrees,
// in star_density of the cells (fewer toward the zenith, where a cell is smaller), fading in
// between star_low_degrees and twice that.
uniform float star_cell_degrees : hint_range(1.0, 10.0) = 3.0;
uniform float star_density : hint_range(0.0, 1.0) = 0.25;
uniform float star_low_degrees : hint_range(0.0, 45.0) = 14.0;
// Angular radius of a star, in degrees; never smaller than a pixel nor wider than three,
// so through the spyglass a star is still a point.
uniform float star_degrees : hint_range(0.02, 0.5) = 0.07;
uniform float star_strength : hint_range(0.0, 1.0) = 0.9;

// ---- Clouds -----------------------------------------------------------------------------
group_uniforms Clouds;
// The sheet's cumulus is not one shape with a shadow: it is layers of small lumpy brush
// stamps in four shades, and its outline and its underside are the stamps' own bumps. The
// shades, measured on TRADE-WIND CUMULUS's big cloud and how much of it each covers: white
// (0.98, 0.94, 0.91) 8%, light (0.94, 0.91, 0.91) 46%, a blue-lavender mid (0.74, 0.81, 0.95)
// 38%, and the shadow (0.69, 0.77, 0.91) 8%. On the sheet the outline's lumps are about a
// twentieth of the cloud apart, and the shades are mixed through its height rather than
// stacked in bands.
uniform vec3 cloud_white : source_color = vec3(0.98, 0.94, 0.91);
uniform vec3 cloud_light : source_color = vec3(0.94, 0.91, 0.91);
uniform vec3 cloud_mid : source_color = vec3(0.74, 0.81, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.69, 0.77, 0.91);
// Degrees of azimuth the clouds drift per second. Shader TIME wraps at 3600 s (the
// project's rollover), so this times 3600 has to be a whole number of turns or every cloud
// jumps on the hour: 0.1 is 360 degrees an hour exactly.
uniform float cloud_speed : hint_range(0.0, 2.0) = 0.1;
// Negative uses live drift. Fixed for captures.
uniform float preview_time = -1.0;

// ---- Sun --------------------------------------------------------------------------------
group_uniforms Sun;
// A golden disc (1.0, 0.96, 0.75), and one soft halo. The sheet's halo, measured as a mix
// toward the sun's warmth: about a half at the rim, 0.29 at 1.4 radii, 0.16 at 1.9, 0.08 at
// 2.75, a trace at 3.5 - and its blue drops below the sky's, so it is a warm colour, not a
// white. (It used to be stepped rings, to match the banded terrain and sea; the sheet's
// "restrained soft halo, no rays" overrides that.)
uniform vec3 sun_colour : source_color = vec3(1.0, 0.96, 0.75);
// Angular RADIUS in degrees, not a cosine threshold. The real sun is a quarter of a degree;
// this is a cartoon one and wants to be a shape you can see. Nine percent of the sheet's
// panel height.
uniform float sun_degrees : hint_range(0.5, 12.0) = 2.6;
uniform vec3 halo_colour : source_color = vec3(1.0, 0.93, 0.72);
// How far the halo reaches beyond the rim, in degrees: three and a half radii.
uniform float halo_degrees : hint_range(0.0, 20.0) = 9.0;
uniform float halo_strength : hint_range(0.0, 1.0) = 0.7;
// A broad warm lift across the sky around it. Small: the sheet adds a hundredth of a step
// of luminance fifteen degrees from the sun, and 0.28 here added a tenth.
uniform float sun_glow : hint_range(0.0, 1.0) = 0.08;
// Direction TO the sun, pushed by world/day.gd every frame (main.gd seeds it from the scene's
// DirectionalLight).
//
// LIGHT0_DIRECTION below is the engine's own route and is used when this is left at zero, but
// it cannot be relied on: it only arrives if the light is feeding the sky, and when it does
// not the shader silently falls back to a constant. The disc then sits at a bearing and an
// elevation that have nothing to do with the light, the shadows point one way and the sun is
// somewhere else, and nothing errors. Setting it explicitly means both agree by construction.
// (LIGHT0_DIRECTION itself points TO the light - the light's own +Z, the way Godot's
// ProceduralSkyMaterial draws its disc - and this used to negate it.)
uniform vec3 sun_direction = vec3(0.0, 0.0, 0.0);
group_uniforms;

// ---- Helpers ----------------------------------------------------------------------------
// Degrees between two directions.
float angle_between(vec3 a, vec3 b) {
	return degrees(acos(clamp(dot(a, b), -1.0, 1.0)));
}

// Value hash, the ocean's: a polynomial rather than sin() of a large number, which loses
// precision on Mobile.
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Value noise on the hash, for the stamps' rims.
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

// Degrees of azimuth from a to b, wrapped to -180..180.
float azimuth_offset(float a, float b) {
	return degrees(atan(sin(radians(a - b)), cos(radians(a - b))));
}

// A soft-edged disc: 1 inside radius r of a direction, 0 outside, one pixel of edge.
float disc(float away, float r, float px) {
	return 1.0 - smoothstep(r - px, r + px, away);
}

// The sheet's halo: `strength` at the rim, falling to nothing `reach` degrees out, faster
// than linearly - with strength 0.7 and reach 3.5 radii: 0.49 at 1.4 radii, 0.25 at 1.9,
// 0.04 at 2.75, against the sheet's 0.29, 0.16, 0.08.
float halo(float away, float r, float reach, float strength) {
	float t = clamp((away - r) / max(reach, 0.001), 0.0, 1.0);
	return pow(1.0 - t, 2.5) * strength * step(r, away);
}

// One brush stamp: a disc whose rim wobbles - two sines round it and a little noise - so a
// row of them reads as lumps, not as a chain of beads. `wobble` is the mass's own noise
// field, one value per pixel, shared by all its stamps.
float stamp(vec2 p, vec2 centre, float radius, float seed, float wobble, float px) {
	vec2 dp = p - centre;
	// The nudge keeps atan defined on the centre pixel itself.
	float theta = atan(dp.y + 1.0e-5, dp.x);
	float rim = radius * (1.0 + 0.09 * sin(5.0 * theta + seed * 6.2832)
		+ 0.03 * sin(9.0 * theta - seed * 4.1) + 0.12 * (wobble - 0.5));
	return 1.0 - smoothstep(-px, px, length(dp) - rim);
}

// One cumulus mass, painted the way the sheet paints it: rows of stamps from the bottom up
// inside a low blob, each stamp painted over the ones before it, the lower rows in the
// shadow shades and the top row white, a little brighter on the sun's side, with some
// jitter so no row is a row. `sky` is this pixel's (azimuth, elevation) in degrees; the mass
// sits at `azimuth`, its base near `elevation`, `width` degrees to either side and `height`
// degrees tall. `cover` gathers how much cloud is in front of the sky here and `shade`
// which shade it is, 0 shadow to 1 white.
void cumulus(vec2 sky, float azimuth, float elevation, float width, float height, float seed,
		float sun_azimuth, float night, float px, inout float cover, inout float shade) {
	// Degrees across and up from the base's middle, the across scaled so a degree is a
	// degree at this elevation.
	float x = azimuth_offset(sky.x, azimuth) * cos(radians(elevation));
	float y = sky.y - elevation;
	if (abs(x) > width * 1.3 || y < -height * 0.45 || y > height * 1.35) {
		return;
	}
	// Which side of the mass the light is on, -1 to 1, that side's stamps a shade lighter:
	// the sun's by day, the moon's (opposite) by night, and never a jump - a sign() here
	// swapped a whole mass's lit side the frame it drifted across the sun's bearing.
	float sun_side = clamp(azimuth_offset(sun_azimuth, azimuth) / 25.0, -1.0, 1.0)
		* (1.0 - 2.0 * night);
	vec2 p = vec2(x, y);
	float wobble = noise(p / max(height, 0.1) * 2.2 + seed * 3.7);
	for (int row = 0; row < 5; row++) {
		float fr = float(row);
		float row_y = height * (0.08 + 0.2 * fr);
		float row_w = width * (1.0 - 0.16 * fr);
		float radius = height * (0.20 - 0.015 * fr);
		for (int col = 0; col < 12; col++) {
			float fc = float(col);
			float h1 = hash(vec2(seed * 31.0 + fr * 13.0, fc + seed));
			float h2 = hash(vec2(seed * 17.0 + fr * 7.0 + 100.0, fc));
			float h3 = hash(vec2(seed * 23.0 + 200.0 + fr, fc + seed * 0.5));
			vec2 centre = vec2((fc / 11.0 - 0.5) * 2.0 * row_w + (h1 - 0.5) * height * 0.16,
				row_y + (h2 - 0.5) * height * 0.14);
			// Only stamps inside the mass's blob: an ellipse a little taller than wide-and-
			// low, heaped in the middle, so the mass is a tower rather than a bar.
			float ex = centre.x / width;
			float ey = (centre.y - height * 0.48) / (height * 0.72);
			if (ex * ex + ey * ey > 1.0) {
				continue;
			}
			float here = stamp(p, centre, radius * (0.85 + 0.3 * h3), h3, wobble, px);
			// Shadow low, white high, lighter toward the light, and jittered by more than a
			// shade so the shades mix through the mass instead of stacking in bands.
			float t = centre.y / height * 1.05 + 0.12 * sun_side * ex + (h1 - 0.5) * 0.55;
			float level = floor(clamp(t, 0.0, 0.999) * 4.0) / 3.0;
			shade = mix(shade, level, here);
			cover = max(cover, here);
		}
	}
}

// A shade between four colours, 0 the first to 1 the last.
vec3 shade_colour(float level, vec3 c0, vec3 c1, vec3 c2, vec3 c3) {
	if (level < 0.3334) {
		return mix(c0, c1, level * 3.0);
	}
	if (level < 0.6667) {
		return mix(c1, c2, (level - 0.3333) * 3.0);
	}
	return mix(c2, c3, (level - 0.6667) * 3.0);
}

void sky() {
	// ---- 1. Where this pixel looks ------------------------------------------------------
	vec3 dir = normalize(EYEDIR);
	float up = dir.y;
	float above = clamp(up, 0.0, 1.0);
	float elevation = degrees(asin(clamp(up, -1.0, 1.0)));
	float azimuth = degrees(atan(dir.x, dir.z));
	vec2 sky_at = vec2(azimuth, elevation);
	// One pixel's worth of angle, so every rim is clean rather than stair-stepped - and it
	// tracks the field of view, which matters here: through the spyglass (5.5 degrees) a
	// pixel covers an eleventh of the angle it does at 60, and a fixed feather that looks
	// crisp at 60 degrees is eleven pixels of blur at 5.5.
	float px = max(fwidth(elevation), 0.0001);

	// LIGHT0_DIRECTION is where the photons travel, down into the island. The disc sits the
	// other way, or the sun and the shadows disagree.
	vec3 to_sun = vec3(0.42, 0.64, 0.64);
	if (length(sun_direction) > 0.001) {
		to_sun = normalize(sun_direction);
	} else if (LIGHT0_ENABLED) {
		to_sun = normalize(LIGHT0_DIRECTION);
	}
	vec3 to_moon = -to_sun;
	vec2 sun_flat = normalize(to_sun.xz + vec2(0.0001));
	float sun_elevation = degrees(asin(clamp(to_sun.y, -1.0, 1.0)));
	float night = 1.0 - clamp(daylight, 0.0, 1.0);
	// The golden hour: full from one to six degrees of sun elevation, gone by sunset_degrees
	// up and by six degrees under.
	float golden = (1.0 - smoothstep(sunset_degrees * 0.4, sunset_degrees, sun_elevation))
		* smoothstep(-6.0, 1.0, sun_elevation);

	// ---- 2. The gradients ---------------------------------------------------------------
	float to_low = smoothstep(0.0, haze_degrees, elevation);
	float to_mid = smoothstep(haze_degrees, mid_degrees, elevation);
	float to_zenith = smoothstep(mid_degrees, max(zenith_degrees, mid_degrees + 1.0), elevation);
	vec3 day = mix(mix(mix(horizon_colour, low_colour, to_low), mid_colour, to_mid), zenith_colour, to_zenith);
	vec3 dark = mix(mix(mix(night_horizon, night_low, to_low), night_mid, to_mid), night_zenith, to_zenith);
	if (up <= 0.0) {
		float under = pow(clamp(-up, 0.0, 1.0), 0.45);
		day = mix(horizon_colour, below_colour, under);
		dark = mix(night_horizon, night_horizon * 0.6, under);
	}
	vec3 col = mix(dark, day, 1.0 - night);
	// Golden hour, laid over whatever the hour's mix is: violet-blue over the whole dome,
	// coral over the lower third of it all round (the sheet's coral band is as strong
	// twenty-eight degrees from the sun as beside it), and orange at the sun's own height.
	float coral = golden * (1.0 - smoothstep(5.0, 32.0, elevation));
	float orange = golden * (1.0 - smoothstep(2.0, 12.0, abs(elevation - sun_elevation)))
		* (0.5 + 0.5 * max(dot(normalize(dir.xz + vec2(0.0001)), sun_flat), 0.0));
	col = mix(col, sunset_sky_colour, golden * 0.75);
	col = mix(col, sunset_glow_colour, coral);
	col = mix(col, sunset_sun_colour, orange * 0.8);

	// ---- 3. The sun ---------------------------------------------------------------------
	float sun_away = angle_between(dir, to_sun);
	float glow = pow(max(dot(dir, to_sun), 0.0), 12.0) * sun_glow;
	col = mix(col, sun_colour, glow * above * (1.0 - night));
	col = mix(col, halo_colour, halo(sun_away, sun_degrees, halo_degrees, halo_strength) * step(0.0, up));
	col = mix(col, sun_colour, disc(sun_away, sun_degrees, px) * step(0.0, up));

	// ---- 4. The moon --------------------------------------------------------------------
	// Its phase is a dark disc slid across it from the side: full when slid clear, half at
	// one radius, new when they coincide.
	float moon_away = angle_between(dir, to_moon);
	// Slid sideways along the sky by that many degrees exactly - a turn about the vertical
	// would slide it only cos(elevation) as far, and left a bite in a full moon - with a
	// tenth of a radius to spare so a full moon is whole to the last pixel.
	float slide = radians(moon_phase * 2.2 * moon_degrees);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), to_moon) + vec3(0.0001, 0.0, 0.0));
	vec3 shadow_dir = normalize(to_moon * cos(slide) + side * sin(slide));
	float moon_lit = disc(moon_away, moon_degrees, px) * (1.0 - disc(angle_between(dir, shadow_dir), moon_degrees, px));
	float moon_shape = max(moon_lit, halo(moon_away, moon_degrees, moon_halo_degrees, moon_halo_strength)
		* (0.4 + 0.6 * moon_phase));
	col = mix(col, moon_colour, moon_shape * night * step(0.0, up));

	// ---- 5. The stars -------------------------------------------------------------------
	// One star at most in each cell of the (azimuth, elevation) grid, in star_density of
	// them, placed inside the cell's middle so no star needs its neighbours' cells. Never
	// below a pixel across, and never under the moon.
	float stars = 0.0;
	if (up > 0.03 && night > 0.001 && elevation < 80.0) {
		vec2 cell = floor(sky_at / star_cell_degrees);
		float cell_elevation = (cell.y + 0.5) * star_cell_degrees;
		float here = hash(cell + vec2(11.3, 27.9));
		// A cell of the (azimuth, elevation) grid shrinks toward the zenith, so fewer of them
		// get a star up there: the same number of stars per patch of sky at any height. The
		// cell's own elevation decides, not the pixel's, or a star could be cut in half by
		// the line where the pixels stop qualifying. Above eighty degrees the cells are too
		// narrow for a star to stay inside its own, and nobody looks straight up.
		if (here < star_density * cos(radians(cell_elevation))) {
			vec2 at = (cell + 0.2 + 0.6 * vec2(hash(cell + vec2(3.1, 5.7)), hash(cell + vec2(9.2, 1.4)))) * star_cell_degrees;
			vec2 off = vec2(azimuth_offset(sky_at.x, at.x) * cos(radians(at.y)), sky_at.y - at.y);
			float radius = clamp(star_degrees * (0.6 + 0.8 * hash(cell + vec2(6.6, 2.2))), px, 3.0 * px);
			stars = disc(length(off), radius, px) * star_strength * (0.5 + 0.5 * hash(cell + vec2(1.8, 8.3)));
		}
	}
	// Cubed: the stars come out only once it is properly dark, not through the golden hour;
	// and none low over the sea, where the sheet's sky is bright.
	stars *= night * night * night * (1.0 - golden) * smoothstep(star_low_degrees, star_low_degrees * 2.0, elevation);
	col = mix(col, vec3(0.95, 0.96, 1.0), stars * (1.0 - disc(moon_away, moon_degrees + 0.3, px)));

	// ---- 6. The clouds ------------------------------------------------------------------
	// Nine masses: six big ones low round the whole sky, three small ones higher. They sit
	// where the chase camera looks (bases six to fourteen degrees up), and drift together.
	float now = preview_time >= 0.0 ? preview_time : TIME;
	float drift = now * cloud_speed;
	float sun_azimuth = degrees(atan(to_sun.x, to_sun.z));
	float cover = 0.0;
	float shade = 0.0;
	// (azimuth, base elevation, half-width, height, seed) - the small ones first, the big
	// ones last so they draw in front.
	// The sheet's single clouds are one to two times as wide as tall; the two big towers
	// here are nearly square, the rest wider.
	cumulus(sky_at, 32.0 + drift, 19.0, 5.5, 3.6, 1.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 158.0 + drift, 21.0, 6.5, 4.4, 2.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 281.0 + drift, 18.0, 5.0, 3.4, 3.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 0.0 + drift, 8.0, 17.0, 14.0, 4.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 57.0 + drift, 11.0, 13.0, 9.0, 5.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 122.0 + drift, 7.0, 19.0, 17.0, 6.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 191.0 + drift, 12.0, 14.0, 9.5, 7.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 249.0 + drift, 9.0, 16.0, 12.0, 8.0, sun_azimuth, night, px, cover, shade);
	cumulus(sky_at, 306.0 + drift, 13.0, 12.0, 8.5, 9.0, sun_azimuth, night, px, cover, shade);
	// Gone before the sea, so a cloud never becomes a bar lying on the water.
	float lift = smoothstep(0.02, 0.1, up);
	cover = clamp(cover, 0.0, 1.0) * lift;
	// The four shades of the hour: the sheet's by day, the moonlit ones by night, and the
	// golden hour's laid over that mix on its own schedule, like the sky's.
	vec3 day_cloud = shade_colour(shade, cloud_shadow, cloud_mid, cloud_light, cloud_white);
	vec3 night_cloud = shade_colour(shade, night_cloud_shadow, night_cloud_mid, night_cloud_light, night_cloud_white);
	vec3 sunset_cloud = shade_colour(shade, sunset_cloud_shadow, sunset_cloud_mid, sunset_cloud_light, sunset_cloud_white);
	vec3 cloud = mix(mix(night_cloud, day_cloud, 1.0 - night), sunset_cloud, golden);
	col = mix(col, cloud, cover);

	// ---- 7. Out -------------------------------------------------------------------------
	COLOR = col;
}
