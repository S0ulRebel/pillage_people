shader_type sky;

// THE SKY: a day and a night from the two sky sheets, art/references/sky-and-clouds-v1.png
// ("day sky.png") and night-sky-and-moon-v1.png ("night sky.png"), with the golden hour
// between them. Every colour below was measured off those sheets (median of the panel's
// bands, lit and shaded cloud pixels, the discs and their halos), and tests/sky_view.gd
// measures the rendered sky the same way.
//
// No texture. The sea and the falls are drawn the same way. The big clouds are masses you can
// count, each painted from round lobes in four shades the way the sheet paints them; noise is
// used only where it cannot turn into grain - broad, and faded out low where the deck's
// perspective would squeeze it - for the small puffs and the cirrus. The stars are hashed
// points.
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
//   6. the clouds, painted in the shades of the hour, in front of all of it: cirrus
//      streaks, small puffs on the cloud deck, the heaped bank round the horizon, and the
//      big cumulus masses nearest of all
//   7. out
//
// How much cloud there is and how dark it is are the WEATHER, and they are not this
// material's: `cloud_cover` and `cloud_storm` are global shader parameters (Project Settings
// > Shader Globals), because the ground and the sea read the same two numbers to lay the
// clouds' shadows (world/cloud_shadow.gdshaderinc). One place to turn the weather.

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
// Moonlit clouds, FULL MOON's four values the same way: lavender-white (0.75, 0.73, 0.84)
// 19%, pale blue (0.56, 0.63, 0.85) 22%, the blue most of the cloud is (0.42, 0.55, 0.83)
// 38%, and the shadow (0.32, 0.46, 0.77) 19% - a blue, where this used to be a grey.
uniform vec3 night_cloud_white : source_color = vec3(0.75, 0.73, 0.84);
uniform vec3 night_cloud_light : source_color = vec3(0.56, 0.63, 0.85);
uniform vec3 night_cloud_mid : source_color = vec3(0.42, 0.55, 0.83);
uniform vec3 night_cloud_shadow : source_color = vec3(0.32, 0.46, 0.77);

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
// The sheet's cumulus is not one shape with a shadow: it is heaps of round billows, each lit
// on its own sun side and shaded on the other, sitting on flat bases with thin streaks along
// them, and piled deepest near the horizon: TRADE-WIND CUMULUS is 27% cloud in its top third,
// 34% in the middle and 40% in the bottom.
//
// Four values, clearly apart - the sheet's cloud clusters into exactly four (k-means over its
// cloud pixels): white (0.94, 0.91, 0.91) 22%, a pale grey-lavender (0.80, 0.85, 0.94) 19%,
// lavender (0.70, 0.79, 0.95) 21%, and the blue shadow (0.57, 0.73, 0.94) 36% - the biggest
// share is the darkest. The first measurement of these took white and light 0.04 apart and
// mid and shadow 0.05 apart, so the clouds drew two values where the sheet paints four.
uniform vec3 cloud_white : source_color = vec3(0.94, 0.91, 0.91);
uniform vec3 cloud_light : source_color = vec3(0.80, 0.85, 0.94);
uniform vec3 cloud_mid : source_color = vec3(0.70, 0.79, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.57, 0.73, 0.94);
// APPROACHING SQUALL's slate, in the same four shades, darkest first measured: (0.20, 0.32,
// 0.48), (0.25, 0.39, 0.56), (0.32, 0.47, 0.63), (0.46, 0.60, 0.68). cloud_storm mixes every
// cloud toward these, and the dome toward the squall's muted teal (0.29, 0.49, 0.64).
uniform vec3 storm_white : source_color = vec3(0.46, 0.60, 0.68);
uniform vec3 storm_light : source_color = vec3(0.32, 0.47, 0.63);
uniform vec3 storm_mid : source_color = vec3(0.25, 0.39, 0.56);
uniform vec3 storm_shadow : source_color = vec3(0.20, 0.32, 0.48);
uniform vec3 storm_sky : source_color = vec3(0.29, 0.49, 0.64);
// Degrees of azimuth the clouds drift per second.
uniform float cloud_speed : hint_range(0.0, 2.0) = 0.1;
// The clouds' clock, in seconds: world/day.gd pushes its own running time here every frame,
// and a test pins it to hold the clouds still. Not TIME: a sky shader that reads TIME makes
// Godot re-render and re-filter the sky's lighting cubemap every single frame (REALTIME
// mode), which measured 27 ms a frame; without it the Sky's automatic mode picks
// INCREMENTAL, and this sky then costs what a flat colour does.
uniform float preview_time = 0.0;
// How tall the heaped bank round the horizon grows, in degrees, at full cover.
uniform float bank_degrees : hint_range(0.0, 15.0) = 5.0;
// Thin high streaks - the sheet's cirrus, and the little broken strokes beside its cumulus.
uniform float wisps : hint_range(0.0, 1.0) = 0.35;
// The weather, shared with the ground's cloud shadows - see the header. 0 is TROPICAL CLEAR,
// about 0.55 TRADE-WIND CUMULUS, 1 BRIGHT OVERCAST.
global uniform float cloud_cover;
// 0 fair, 1 APPROACHING SQUALL.
global uniform float cloud_storm;

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

// A hard toon edge at `edge`, anti-aliased over one pixel's worth of `x`.
float band(float x, float edge) {
	float w = max(fwidth(x), 0.0001) * 0.75;
	return smoothstep(edge - w, edge + w, x);
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

// Paint one layer over what is already there, the way the sheet is painted: `here` of this
// layer's shade over the shade below.
void paint(float here, float level, inout float cover, inout float shade) {
	shade = mix(shade, level, here);
	cover = max(cover, here);
}

// One billow, the unit the sheet's cumulus is built from: a round puff whose outline is a
// ring of small bumps (the scallops), lit as if it were a ball. Returns how much of this
// pixel it covers in x and its shade in y, 0 shadow to 1 white.
//
// `dp` is the pixel from the billow's centre in degrees, `squash` flattens it (the bottom row
// of a cloud is wider than it is tall, which is what gives a cloud a base without cutting
// one), `light` is the direction to the light in (across, up, toward the eye), `low` how far
// down the cloud the billow sits, 0 top to 1 bottom, and `lift` moves every shade lighter
// (the moonlit sheet carries more of its white than the day's does).
//
// The shades are bands of the ball's lighting: a white crescent on the light side of the
// crown, a light band inside it, and the blue-lavender body - most of the billow, as it is
// most of the sheet's cloud - darkening to the shadow low down on the far side. Lower
// billows are darker overall: the sheet's cloud is white on top and blue underneath.
vec2 billow(vec2 dp, float radius, float squash, float seed, vec3 light, float low, float lift,
		float sunward, float behind, float px) {
	vec2 q = vec2(dp.x, dp.y / squash);
	float d = length(q);
	if (d > radius * 1.08) {
		return vec2(0.0);
	}
	// The scallops: semicircles round the rim, so the outline is a run of small round bumps
	// meeting in cusps - not a wobble, which read as a jelly. Each billow its own count, seven
	// to fifteen, and its own depth: the same scallop on every billow was a pattern.
	float theta = atan(q.y + 1.0e-5, q.x);
	float bumps = 7.0 + floor(seed * 9.0);
	float depth = 0.05 + 0.11 * fract(seed * 7.31);
	float s = fract(theta / 6.2832 * bumps + seed * 3.1);
	float bump = sqrt(max(1.0 - (2.0 * s - 1.0) * (2.0 * s - 1.0), 0.0));
	float rim = radius * (1.0 - depth + depth * bump);
	float here = 1.0 - smoothstep(-px, px, d - rim);
	// The ball: its normal from where on the disc this pixel is.
	vec2 on_disc = q / max(rim, 0.001);
	vec3 n = normalize(vec3(on_disc, sqrt(max(1.0 - dot(on_disc, on_disc), 0.0)) + 0.15));
	float lit = dot(n, light);
	// The rim light: a light band hugging the outline on the light side. It is what separates
	// a billow from the darker one behind it - on the sheet every low billow is mostly body,
	// with its top edge lit. Without it the lower half of a tower merged into one flat slab;
	// lit as a plain ball instead, every billow grew the same white crescent and the cloud
	// read as a row of Cs.
	float edge = smoothstep(0.68, 0.9, d / max(rim, 0.001));
	float toward = dot(normalize(on_disc + vec2(0.0, 1.0e-4)), normalize(light.xy + vec2(0.0, 1.0e-4)));
	float rim_light = edge * smoothstep(0.1, 0.55, toward);
	// Height in the cloud counts as much as the ball's own light: white gathers at the top.
	// The crown's billows are mostly white on the sheet, not just rimmed: the top of the
	// cloud gets a lift of its own. Across the whole mass there is a second gradient: the side
	// toward the sun is the white side, the far side the blue one (`sunward`). And a mass
	// behind is a step darker than the clumps in front of it (`behind`) - that is the depth.
	float high = 1.0 - low;
	// Mostly by WHERE the billow is, only a little by where on the billow the pixel is: on the
	// sheet (its tone map) each billow is one flat tone, and the tones come in big patches -
	// white crowns on the sun side, pale and lavender through the middle, the blue shadow low
	// and away from the sun - with a lighter cap on the lit shoulder of some. Weighted toward
	// the ball, every billow drew the same white crescent and pale band, which read as a
	// pattern stamped over the cloud.
	float t = lit * 0.16 + high * 0.42 + high * high * 0.16 + rim_light * 0.12 + sunward * 0.2
		+ (seed - 0.5) * 0.22 - behind * 0.1 + lift - 0.02;
	// Four values by thresholds set to the sheet's own proportions on TRADE-WIND CUMULUS: the
	// shadow the biggest share, white a crown and a rim.
	float level = t > 0.405 ? 1.0 : (t > 0.30 ? 0.667 : (t > 0.19 ? 0.333 : 0.0));
	return vec2(here, level);
}

// One cumulus: rows of billows inside a heap, painted from the TOP row down, so each lower
// billow sits in front of the ones above it and its bright crown cuts across their darker
// bodies - that overlap is the cauliflower. The bottom row is squashed wide and flat, which
// gives the cloud a base that is level but still lumpy, and a shelf of thin streaks runs out
// from under it, in front.
//
// `sky` is this pixel's (azimuth, elevation) in degrees; the cloud sits at `azimuth`, its
// base at `elevation`, `width` degrees to either side and `height` degrees tall. Only the
// billows near this pixel are looked at: the rows within reach of its height, and in each
// the two or three columns within reach across.
void cumulus(vec2 sky, float azimuth, float elevation, float width, float height, float seed,
		vec3 light, float lift, float px, inout float cover, inout float shade) {
	// Degrees across and up from the base's middle, the across scaled so a degree is a
	// degree at this elevation.
	float x = azimuth_offset(sky.x, azimuth) * cos(radians(elevation));
	float y = sky.y - elevation;
	// Each cloud its own shape, from its seed: the heap leans to one side, by up to a third of
	// its width, and its top slopes. A cloud much wider than tall is a flat cloudlet - the
	// sheet's small streaky ones - squashed in every row, not just the bottom. Every cloud the
	// same symmetric dome was the uniformity.
	float lean = (hash(vec2(seed, 91.0)) - 0.5) * 0.7;
	float slope = (hash(vec2(seed, 57.0)) - 0.5) * 0.5;
	bool flat_cloud = height < width * 0.45;
	// The box everything below can reach: the leaning heap and its biggest billow round it.
	// Narrower than that and a leaning tower was cut off down one side by a straight line.
	float reach_out = max(height * 0.27, width * 0.24) * 1.4;
	if (abs(x - lean * width) > width * 1.05 + reach_out || y < -reach_out * 0.6
			|| y > height * 1.05 + reach_out) {
		return;
	}
	const int ROWS = 5;
	for (int pass = 0; pass < ROWS; pass++) {
		int row = ROWS - 1 - pass;
		float fr = float(row);
		// Never smaller than a quarter of the cloud's width: a small cloud is three or four
		// billows on the sheet, and sized by its height alone it broke into dozens of scales.
		// Shrinking only slowly up the rows: rows are a fifth of the height apart, and billows
		// smaller than that floated off the top of the cloud as separate balls.
		float radius = max(height * (0.28 - 0.012 * fr), width * 0.24);
		float squash = (row == 0 || flat_cloud) ? 0.55 : 1.0;
		float row_y = height * (0.08 + 0.2 * fr);
		if (abs(y - row_y) > radius * 1.15 + height * 0.06) {
			continue;
		}
		float row_w = width * (1.0 - 0.17 * fr);
		// Billows a little closer than touching, so they overlap into one mass.
		float spacing = radius * 1.25;
		float count = max(floor(2.0 * row_w / spacing), 1.0);
		spacing = 2.0 * row_w / count;
		int nearest = int(floor((x + row_w) / spacing + 0.5));
		for (int col = max(nearest - 1, 0); col <= min(nearest + 1, int(count)); col++) {
			float fc = float(col);
			float h1 = hash(vec2(seed * 31.0 + fr * 13.0, fc + seed));
			float h2 = hash(vec2(seed * 17.0 + fr * 7.0 + 100.0, fc));
			float h3 = hash(vec2(seed * 23.0 + 200.0 + fr, fc + seed * 0.5));
			float h4 = hash(vec2(seed * 41.0 + fr * 3.0, fc * 1.7 + 50.0));
			// A few billows left out high up, so the outline has steps. Lower down, or more of
			// them, and a cloud came apart into floating balloons.
			if (row > 1 && row < ROWS - 1 && h4 > 0.9) {
				continue;
			}
			// Jittered by more than a third of the spacing each way, or the billows line up in
			// rows and the cloud reads as stacked cushions.
			vec2 centre = vec2(-row_w + fc * spacing + (h1 - 0.5) * spacing * 0.75,
				row_y + (h2 - 0.5) * height * 0.16);
			// Only billows inside the heap: an ellipse heaped in the middle, so the cloud is a
			// tower rather than a bar.
			float ex = (centre.x - lean * width) / width;
			float ey = (centre.y - height * (0.45 + slope * ex)) / (height * 0.7);
			if (ex * ex + ey * ey > 1.05) {
				continue;
			}
			float r = radius * (0.65 + 0.7 * h3);
			float sunward = clamp((centre.x - lean * width) / width * sign(light.x) * 1.4, -1.0, 1.0)
				* abs(light.x) / max(length(light.xy), 0.001);
			vec2 b = billow(vec2(x, y) - centre, r, squash, h3, light,
				1.0 - clamp(centre.y / height, 0.0, 1.0), lift, sunward, flat_cloud ? 0.0 : 1.0, px);
			paint(b.x, b.y, cover, shade);
		}
	}
	// The clumps in front. On the sheet a big mass never stands alone: two or three small heaps
	// of billows sit in front of its lower third, on the same base, their crowns lit white
	// against the darker body behind - the bright small shape over the dark big one is most of
	// the sheet's depth. Each heap is a small dome of five billows: two low, two higher, one
	// on top. Flat cloudlets have none; they are small already.
	if (!flat_cloud) {
		for (int h = 0; h < 3; h++) {
			float fh = float(h);
			float k1 = hash(vec2(seed * 7.7 + fh, 301.0));
			float k2 = hash(vec2(seed * 3.3 + fh, 302.0));
			if (k2 > 0.8) {
				continue;
			}
			// Spread across the mass's foot, and sized a third to a half of its big billows.
			float cr = max(height * 0.1, width * 0.09) * (0.8 + 0.6 * k2);
			vec2 heap = vec2(lean * width + (fh - 1.0 + (k1 - 0.5) * 0.6) * width * 0.62,
				cr * 0.35);
			if (abs(x - heap.x) > cr * 3.2 || y > heap.y + cr * 3.2) {
				continue;
			}
			for (int j = 0; j < 5; j++) {
				float fj = float(j);
				vec2 offset = j == 0 ? vec2(-1.1, 0.0) : (j == 1 ? vec2(1.0, 0.1)
					: (j == 2 ? vec2(-0.45, 0.85) : (j == 3 ? vec2(0.55, 0.8) : vec2(0.0, 1.55))));
				float kj = hash(vec2(seed * 5.1 + fh * 3.0, fj + 310.0));
				vec2 centre = heap + offset * cr + (vec2(kj, fract(kj * 7.3)) - 0.5) * cr * 0.5;
				float r = cr * (0.75 + 0.5 * kj);
				float squash = j < 2 ? 0.6 : 1.0;
				float sunward = clamp(offset.x * 0.5 * sign(light.x), -1.0, 1.0) * 0.6;
				vec2 b = billow(vec2(x, y) - centre, r, squash, kj, light,
					1.0 - clamp((centre.y - heap.y) / (cr * 2.2), 0.0, 1.0) * 0.9, lift, sunward,
					0.0, px);
				paint(b.x, b.y, cover, shade);
			}
		}
	}
	// The shelf: a few thin streaks along the base, reaching out past the cloud on both sides
	// and lying over the bottom of it. The edge is a fixed width rather than a pixel's: this
	// runs only inside the cloud's box, and fwidth is not defined across the edge of a branch.
	// Sized by the cloud's bulk, not its height, so a flat cloudlet trails streaks as long as
	// its own body - on the sheet the small ones are as much streak as puff.
	float bulk = max(height, width * 0.35);
	float sx = x / (width * 1.6);
	float sy = (y + bulk * 0.02) / (bulk * 0.07);
	float strokes = noise(vec2(x / (bulk * 0.9), y / (bulk * 0.022)) + seed * 5.1);
	float reach = max(1.0 - sx * sx, 0.0) * max(1.0 - sy * sy, 0.0);
	float edge = mix(0.62, 0.30, wisps);
	float shelf = smoothstep(edge - 0.02, edge + 0.02, strokes * reach);
	paint(shelf, strokes > 0.75 ? 0.667 : 0.333, cover, shade);
}

// The heaped bank all the way round the horizon: two rows of billows, the far one bigger and
// slower, rising and falling round the sky on a slow noise so the bank has tall stretches and
// gaps. Everything the chase camera sees of the sky is its lowest twenty degrees, and on the
// sheet that is where most of the cloud is.
void horizon_bank(vec2 sky, float drift, vec3 light, float lift, float amount, float px,
		inout float cover, inout float shade) {
	if (sky.y > bank_degrees * 1.3 || sky.y < -1.0 || amount <= 0.0) {
		return;
	}
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		// Cell sizes that divide 360 exactly, so the bank closes up with no seam.
		float cell_degrees = layer == 0 ? 7.2 : 4.0;
		float cells = 360.0 / cell_degrees;
		float az = mod(sky.x - drift * (0.55 + 0.2 * fl) + 720.0, 360.0);
		float at = az / cell_degrees;
		for (int k = -1; k <= 1; k++) {
			float cell = floor(at) + float(k);
			float id = mod(cell, cells);
			float turn = (id + 0.5) / cells * 6.2832;
			// The envelope: how tall the bank is here. Sampled on a circle so it wraps.
			float envelope = noise(vec2(cos(turn), sin(turn)) * 2.6 + fl * 7.3);
			// High enough that the bank breaks: tall stretches, low ones and open sea between.
			envelope = smoothstep(0.88 - amount * 0.55, 0.98, envelope);
			// Wide enough that neighbours overlap into one heap: narrower than a cell and the
			// bank was a row of separate loaves along the sea.
			float r = envelope * bank_degrees * (1.0 - 0.45 * fl) * (0.45 + 0.9 * hash(vec2(id, fl)));
			if (r < 0.15) {
				continue;
			}
			// Sunk below the line, so what shows is a dome.
			vec2 centre = vec2((cell + 0.5 + (hash(vec2(id, fl + 4.0)) - 0.5) * 0.6) * cell_degrees,
				-r * (0.45 - 0.2 * hash(vec2(id + 9.0, fl))));
			vec2 b = billow(vec2(at * cell_degrees - centre.x, sky.y - centre.y), r, 1.0,
				hash(vec2(id, fl + 2.0)), light, 0.35 + 0.3 * fl, lift, 0.0, 0.5 - 0.5 * fl, px);
			paint(b.x, b.y, cover, shade);
		}
	}
}

// The deck: small puffs and cirrus on a flat layer overhead, seen in perspective, so they
// shrink and crowd toward the horizon on their own the way a real deck does. Only cirrus in
// fair weather; past about 0.6 cover the puffs come and join into BRIGHT OVERCAST's sheet.
void cloud_deck(vec3 dir, float elevation, vec3 to_sun, float drift, float amount,
		inout float cover, inout float shade) {
	if (dir.y < 0.03) {
		return;
	}
	vec2 deck = dir.xz / dir.y + vec2(drift * 0.004, drift * 0.0015);
	// Faded out low, where the deck's perspective squeezes it into grain; the bank is there.
	float low = smoothstep(7.0, 16.0, elevation);

	// Cirrus: noise stretched along one bearing, cut thin.
	vec2 along = vec2(0.94, 0.34);
	vec2 c = vec2(dot(deck, along), dot(deck, vec2(-along.y, along.x)));
	// Long and thin, and broken by a finer layer into feathery strokes: stretched less than
	// this, each streak was a single white leaf.
	float streak = noise(c * vec2(0.45, 11.0)) * 0.6 + noise(c * vec2(1.6, 26.0) + 4.1) * 0.4;
	float cirrus = band(streak, 1.0 - wisps * 0.3) * smoothstep(14.0, 30.0, elevation);
	paint(cirrus * 0.9, 0.667 + 0.333 * step(0.8, streak), cover, shade);

	// Puffs: two octaves for the body and a third for lumpy edges; lit where the density
	// falls away toward the sun, the usual sky-shader trick for a lit top and a dark base.
	vec2 q = deck * vec2(1.6, 2.4);
	float density = noise(q) * 0.55 + noise(q * 2.2 + 3.1) * 0.3 + noise(q * 6.0 + 7.7) * 0.15;
	vec2 toward = normalize(to_sun.xz + vec2(0.0001)) * 0.18;
	float behind = noise(q + toward) * 0.55 + noise((q + toward) * 2.2 + 3.1) * 0.3;
	// None in fair weather - on their own a few noise puffs read as white leaves, nothing like
	// the sheet's cloudlets, which are the flat masses - and from past the trade-wind cover
	// they gather into the overcast sheet: most of the deck at full cover.
	float threshold = mix(1.05, 0.42, smoothstep(0.58, 1.0, amount));
	float puff = band(density, threshold) * low;
	float lit = clamp((density - behind) * 4.0 + 0.5, 0.0, 1.0);
	float level = floor(clamp(lit * 0.8 + (density - threshold) * 1.5, 0.0, 0.999) * 4.0) / 3.0;
	paint(puff, level, cover, shade);
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
	// The coral runs from the sun's height up to violet by about twenty-five degrees above
	// it, the sheet's stops; measured by elevation alone it filled the whole sky a beach
	// camera can see with one flat pink.
	float coral = golden * (1.0 - smoothstep(2.0, 24.0, elevation - max(sun_elevation, 0.0)));
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
	// Back to front: the deck overhead, the bank round the horizon, then the big masses.
	float now = preview_time;
	float drift = now * cloud_speed;
	float sun_azimuth = degrees(atan(to_sun.x, to_sun.z));
	float amount = clamp(cloud_cover, 0.0, 1.0);
	float cover = 0.0;
	float shade = 0.0;
	cloud_deck(dir, elevation, to_sun, drift, amount, cover, shade);
	// The light every lobe is lit from, in the sky's across-and-up degrees: from above, and
	// from the side the sun is on - the moon's, opposite, by night. Toward a low sun it comes
	// from the side more than from above.
	float lit_from_above = mix(0.35, 1.0, clamp(to_sun.y * 2.0, 0.0, 1.0));
	float bank_side = clamp(azimuth_offset(sun_azimuth, azimuth) / 25.0, -1.0, 1.0) * (1.0 - 2.0 * night);
	float lift_shades = 0.3 * night;
	horizon_bank(sky_at, drift, normalize(vec3(bank_side * 0.8, lit_from_above, 0.55)), lift_shades,
		amount, px, cover, shade);
	// (azimuth, base elevation, half-width, height, seed, rank). A mass is there once the
	// cover reaches its rank, growing in over the last fifth of it rather than popping.
	// Grouped, with open sky between, the way the sheet composes them: two clusters - a tower
	// with a heap beside it and a flat cloudlet above - a few loners, and small flat cloudlets
	// scattered higher. Seventeen masses spread evenly round the sky were too many and all
	// alike; the sun is at about -35.
	vec4 masses[13] = vec4[13](
		vec4(125.0, 1.5, 12.0, 26.0), vec4(152.0, 3.0, 9.0, 13.0), vec4(98.0, 11.0, 7.0, 2.4),
		vec4(8.0, 2.0, 11.0, 19.0), vec4(34.0, 5.5, 8.0, 11.0), vec4(57.0, 15.0, 8.0, 2.2),
		vec4(242.0, 2.5, 12.0, 15.0), vec4(305.0, 3.0, 8.5, 11.0), vec4(205.0, 12.0, 6.0, 1.8),
		vec4(280.0, 18.0, 7.0, 2.0), vec4(322.0, 10.0, 5.0, 1.6), vec4(178.0, 23.0, 5.0, 1.5),
		vec4(72.0, 21.0, 6.0, 1.8));
	vec2 ranks[13] = vec2[13](
		vec2(4.0, 0.05), vec2(5.0, 0.30), vec2(6.0, 0.35), vec2(7.0, 0.10), vec2(8.0, 0.40),
		vec2(9.0, 0.45), vec2(12.0, 0.20), vec2(13.0, 0.60), vec2(14.0, 0.25), vec2(15.0, 0.50),
		vec2(16.0, 0.55), vec2(17.0, 0.65), vec2(1.0, 0.50));
	for (int m = 0; m < 13; m++) {
		float grow = smoothstep(ranks[m].y - 0.2, ranks[m].y, amount);
		if (grow < 0.05) {
			continue;
		}
		vec4 at = masses[m];
		float side = clamp(azimuth_offset(sun_azimuth, at.x + drift) / 25.0, -1.0, 1.0)
			* (1.0 - 2.0 * night);
		vec3 light = normalize(vec3(side * 0.8, lit_from_above, 0.55));
		cumulus(sky_at, at.x + drift, at.y, at.z * grow, at.w * grow, ranks[m].x, light,
			lift_shades, px, cover, shade);
	}
	// Down to the horizon line and no further, so a cloud never becomes a bar lying on the sea.
	float lift = smoothstep(0.0, 0.006, up);
	cover = clamp(cover, 0.0, 1.0) * lift;
	// The four shades of the hour: the sheet's by day, the moonlit ones by night, and the
	// golden hour's laid over that mix on its own schedule, like the sky's; then the squall's
	// slate over all of it, as far as the storm goes.
	vec3 day_cloud = shade_colour(shade, cloud_shadow, cloud_mid, cloud_light, cloud_white);
	vec3 night_cloud = shade_colour(shade, night_cloud_shadow, night_cloud_mid, night_cloud_light, night_cloud_white);
	vec3 sunset_cloud = shade_colour(shade, sunset_cloud_shadow, sunset_cloud_mid, sunset_cloud_light, sunset_cloud_white);
	vec3 storm_cloud = shade_colour(shade, storm_shadow, storm_mid, storm_light, storm_white);
	vec3 cloud = mix(mix(night_cloud, day_cloud, 1.0 - night), sunset_cloud, golden);
	cloud = mix(cloud, storm_cloud * mix(0.45, 1.0, 1.0 - night), clamp(cloud_storm, 0.0, 1.0));
	// A little of the horizon's haze on the lowest cloud, so the bank sits behind the sea air
	// rather than pasted on the line.
	cloud = mix(cloud, mix(night_horizon, horizon_colour, 1.0 - night), (1.0 - smoothstep(0.0, 3.0, elevation)) * 0.2);
	col = mix(col, storm_sky * mix(0.4, 1.0, 1.0 - night), clamp(cloud_storm, 0.0, 1.0) * 0.6 * step(0.0, up));
	col = mix(col, cloud, cover);

	// ---- 7. Out -------------------------------------------------------------------------
	COLOR = col;
}
