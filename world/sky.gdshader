shader_type sky;

// THE SKY: a day and a night from the two sky sheets, art/references/sky-and-clouds-v1.png
// ("day sky.png") and night-sky-and-moon-v1.png ("night sky.png"), with the golden hour
// between them. Every colour below was measured off those sheets (median of the panel's
// bands, lit and shaded cloud pixels, the discs and their halos), and tests/sky_view.gd
// measures the rendered sky the same way.
//
// No texture. The sea and the falls are drawn the same way. The big clouds are masses you can
// count, each painted from sine-waved circles in four values the way the sheet paints them;
// noise is used only where it cannot turn into grain - broad, and faded out low where the
// deck's perspective would squeeze it - for the small puffs and the cirrus. The stars are
// hashed points.
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
//      streaks and puffs on the cloud deck, the cloudlets mid-sky, the heaps round the
//      horizon, and the big cumulus masses nearest of all. The cumulus is built from rules
//      read off the day sheet - see THE PAINTED CUMULUS below the helpers.
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
// The size of the heaps round the horizon, in degrees: each is one to one and a half times
// this either side of its middle, and a third to three fifths as tall as it is wide.
uniform float bank_degrees : hint_range(0.0, 15.0) = 6.0;
// Thin high streaks - the sheet's cirrus - and how many cloudlets float mid-sky by day.
uniform float wisps : hint_range(0.0, 1.0) = 0.35;
// The weather, shared with the ground's cloud shadows - see the header. 0 is TROPICAL CLEAR,
// about 0.55 TRADE-WIND CUMULUS, 1 BRIGHT OVERCAST.
global uniform float cloud_cover;
// 0 fair, 1 APPROACHING SQUALL.
global uniform float cloud_storm;

// ---- Cloud shapes -----------------------------------------------------------------------
group_uniforms Cloud_Shapes;
// The knobs of THE PAINTED CUMULUS (below the helpers), where the rules are written out. The
// numbers inside its functions are the rest of the recipe, each commented where it is used.
//
// How much of each cloud is drawn: 2 everything, 1 without the small scallops (the white band
// along the sun edge gets plainer), 0 big blobs only (flat, cheap). The clouds are the
// expensive part of this sky; this is the first thing to turn down if the iPad needs time.
uniform int cloud_detail : hint_range(0, 2) = 2;
// Nothing smaller than this, in degrees across, is drawn: the tiniest scallops on the smallest
// clouds are skipped, as the prototype skipped them. Lower it for finer, busier outlines.
uniform float smallest_lobe : hint_range(0.0, 3.0) = 0.66;
// RULE 6: how flat the blobs sitting on a cloud's base are squashed, 1 round, lower flatter.
uniform float base_squash : hint_range(0.3, 1.0) = 0.6;
// RULE 7: each big blob's value is floor() of
//   across * value_across * light.x  +  height * value_up * light.y  +  value_bias
//   + (random -1..1) * value_jitter  +  night * night_value_lift
// where `across` is -0.5..0.5 over the cloud's width and `height` 0..1 up it. Raise value_up
// for a starker top-to-bottom split, value_across for a stronger lit side, value_bias to
// lighten every cloud by a fraction of a value, value_jitter for neighbours to differ more.
uniform float value_across : hint_range(0.0, 4.0) = 1.2;
uniform float value_up : hint_range(0.0, 8.0) = 3.3;
uniform float value_bias : hint_range(-2.0, 2.0) = 0.55;
uniform float value_jitter : hint_range(0.0, 1.0) = 0.25;
// FULL MOON's clouds are mostly the mid blue, where the day's are mostly shadow: by night every
// blob is lifted this much.
uniform float night_value_lift : hint_range(0.0, 2.0) = 0.6;

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

// =============================================================================================
// THE PAINTED CUMULUS
// =============================================================================================
// Everything from here down to cloud_deck() draws the big clouds. It is a port of the rule
// prototype that was matched side by side against art/references/sky-and-clouds-v1.png, and
// it follows the thirteen rules read off that sheet. Where a rule is used, the comment says so.
//
//   SHAPE
//    1  One cloud is one mass built from a PATH of blobs: small at both ends, biggest in the
//       middle, each nudged up or down a little.                        -> edge_profile()
//    2  The path rises to an off-centre TOWER, steps down through one or two SHOULDERS and
//       ends in a low tail.                                             -> cumulus(), part A
//    3  Three sizes, each built from the next one down: BIG BLOBS make the silhouette, each
//       big blob's outline is a run of MEDIUM BUMPS, and the bumps have small SCALLOPS along
//       their tops.                                                     -> blob_unit()
//    4  Every edge is a little irregular: circles modulated by sines.   -> lobe()
//    5  Blobs overlap heavily, so a mass has no holes in it.
//    6  The bottom is not cut straight: the lowest blobs are squashed into shallow, nearly level
//       arcs, and a SHELF of thin streaks runs out past the cloud on both sides. -> streak()
//
//   VALUES (four of them: 0 blue shadow, 1 lavender, 2 pale, 3 white)
//    7  Light from one side and above: the whole cloud runs diagonally from white at the
//       sun-side top to blue at the far-side bottom.                    -> blob_value()
//    8  White is a thick band hugging the sun-side outline. It comes from the scallops.
//    9  Front blobs are DARKER than what is behind them: a low blob in front is a blue
//       silhouette with only its sun-facing top edge lit.               -> cumulus(), part C
//   10  Inside one blob the value steps once or twice, and the step follows the bumps.
//   11  Blue is the biggest share, then lavender, pale and white (the sheet's 36/21/19/22).
//
//   COMPOSITION
//   12  Big masses step down into smaller heaps. Flat CLOUDLETS float higher: a few blobs on a
//       streaky base, white top, blue underside, trailing streaks.     -> cloudlet()
//   13  Clouds cluster, with open sky between.                          -> the tables in sky()
//
// UNITS. Everything is in DEGREES of sky. x runs across (degrees of azimuth, shrunk by the
// cosine of the elevation so a cloud high up isn't stretched) and y runs up from the cloud's
// base. A cloud of width W is built from big blobs of radius about 0.15 W. `px` is one screen
// pixel in degrees, and every edge is anti-aliased over one of them.
//
// "RANDOM" NUMBERS. There are no noise textures. Every random number is rand(key, slot, lo, hi):
// a hash of which cloud, which blob, which bump and which number of it this is. So the same
// pixel always gets the same cloud, nothing flickers, and skipping a far-away bump for speed
// doesn't shift the numbers of the next one. For a different cloud, change its seed in the
// tables in sky(). For different proportions, change the numbers in the functions below. Each
// one is commented with what it does.
//
// THE LIGHT. Every cloud is BUILT as if the sun were up and to its right (DESIGN_LIGHT), then
// half of them are mirrored, picked by their seed. So a cloud's SHAPE never changes as the sun
// goes round: it would jump every time the sun crossed behind it. Only the VALUES follow the
// real light, so the white still lands on the real sun side. A cloud built facing away from the
// sun just has its scallops in shade.
//
// COST. This is the most expensive thing in the sky. A pixel far from a cloud costs almost
// nothing: every cloud, blob, bump and scallop is skipped by a distance check before anything
// is drawn. A pixel inside a cloud evaluates a few dozen wavy circles. `cloud_detail` turns
// the scallops (2 -> 1) and the bumps (1 -> 0) off if the iPad needs the time back.

// The light every cloud is built for, in the cloud's own (across, up): up and to the right,
// the direction the sheet's sun comes from. SUN_ANGLE is the same direction as an angle round a
// blob (0 is right, 90 straight up), for placing runs of bumps "on the sun side".
const vec2 DESIGN_LIGHT = vec2(0.62, 0.78);
const float SUN_ANGLE = 51.5;

// Dave Hoskins' hash13: three numbers in, one out, 0..1. The cloud's random numbers come from it.
float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// A random number between lo and hi: the same every time for the same key and slot. `key` says
// which thing (cloud seed, blob number), `slot` which of its numbers.
float rand(vec2 key, float slot, float lo, float hi) {
	return mix(lo, hi, hash3(vec3(key + vec2(0.37, 0.71), slot + 0.13)));
}

// RULE 1. How big a blob is at `t` along a run (0 one end, 1 the other): `lo` at the ends, `hi`
// in the middle, rising like a sine. Every run uses it: the base of a cloud, its crown, the
// bumps round a blob and the scallops on a bump.
float edge_profile(float t, float lo, float hi) {
	return lo + (hi - lo) * pow(sin(PI * clamp(t, 0.0, 1.0)), 1.2);
}

// RULE 4. How much of this pixel one wavy circle covers. Every shape in a cloud is one of these.
//   c         centre;  rx, ry  radii across and up (in its own turned frame)
//   s         0..1, which wobble pattern (how many waves round it, and where they start)
//   rot       turns it, in radians: a scallop lies along the rim it sits on
//   shear     leans it, like a brush stroke: x slides by shear * y
//   lumpy     extra, broader waves on top: the bumps UNDER a blob use it, so they read as
//             distorted lumps peeking out rather than a row of balls
// The outline is a circle whose radius is modulated by three sines: 5 to 8 gentle waves, two
// broad ones so it isn't symmetric, and a sharpened one that makes shallow facets, which is
// what makes it look hand-painted.
float lobe(vec2 p, vec2 c, float rx, float ry, float s, float rot, float shear, float lumpy,
		float px) {
	if (max(rx, ry) < smallest_lobe) {
		return 0.0;
	}
	vec2 d = p - c;
	if (rot != 0.0) {
		float cr = cos(rot);
		float sr = sin(rot);
		d = vec2(d.x * cr + d.y * sr, -d.x * sr + d.y * cr);
	}
	d.x -= shear * d.y;
	vec2 q = d / vec2(rx, ry);
	float dist = length(q);
	// How many "units of radius" one pixel is: the edge is one pixel wide whatever the size.
	float sharp = min(rx, ry) / px;
	// The waves move the rim between 0.845 - lumpy and 1.12 + lumpy of the radius. Outside
	// that it is certainly empty, well inside it certainly full, and the sines are skipped.
	if (dist > 1.12 + lumpy + 0.5 / sharp) {
		return 0.0;
	}
	if (dist < 0.845 - lumpy - 0.5 / sharp) {
		return 1.0;
	}
	float th = atan(q.y, q.x);
	float k = 5.0 + floor(s * 4.0);
	float wob = 1.0 + 0.07 * sin(k * th + s * 20.0) + 0.05 * sin(2.0 * th + s * 9.0)
		- 0.035 * abs(sin((k + 4.0) * th * 0.5 + s * 31.0));
	wob += lumpy * (sin(3.0 * th + s * 7.0) * 0.6 + sin(7.0 * th + s * 13.0) * 0.4);
	return clamp((wob - dist) * sharp + 0.5, 0.0, 1.0);
}

// Paint `here` of the value `level` over a premultiplied (shade, cover) pair. This is how one big
// blob's own parts are stacked before the blob as a whole goes in front of or behind its
// neighbours (see cumulus()).
void over(float here, float level, inout vec2 unit) {
	unit = vec2(level * here, here) + unit * (1.0 - here);
}

// RULES 1 AND 3. Bump `i` of `n` round the rim of a circle (centre c, radius r), spread from
// angle a0 to a1 in degrees (0 right, 90 up, 180 left, 270 down). Small at the two ends of the
// stretch and biggest in its middle, and on top of that their sizes rise and fall in a slow wave
// along it: one bigger bump, then two or three smaller. The sheet's scallops come in groups like
// that, not one by one.
//   lo, hi   size at the ends and in the middle, as fractions of r
// Returns (centre x, centre y, radius, angle in radians).
vec4 rim_bump(vec2 c, float r, int i, int n, float lo, float hi, float a0, float a1, vec2 key) {
	float t = (float(i) + 0.5) / float(n);
	float phase = rand(key, 200.0, 0.0, 6.28);      // where along the run the slow wave starts
	float waves = rand(key, 201.0, 1.3, 2.2);       // how many groups along the run
	float slot = float(i) * 8.0;
	float a = radians(a0 + (a1 - a0) * t + rand(key, slot, -5.0, 5.0));
	float group = 0.72 + 0.38 * sin(phase + t * waves * 6.28);
	float size = r * edge_profile(t, lo, hi) * group * rand(key, slot + 1.0, 0.9, 1.1);
	// Centred inside the rim, 74-86% of the way out, so each bump pokes out by about half.
	float out_by = r * rand(key, slot + 2.0, 0.74, 0.86);
	return vec4(c + vec2(cos(a), sin(a)) * out_by, size, a);
}

// RULE 6. One stroke of the streak shelf under a cloud, or of the trail behind a cloudlet: a long
// thin lens, centre c, half-length w, half-height h. Its top edge is lumpy and its underside
// flatter. It is pale on top and lavender underneath.
void streak(vec2 p, vec2 c, float w, float h, float s, float px, inout float cover,
		inout float shade) {
	vec2 d = p - c;
	if (abs(d.x) >= w || abs(d.y) > h * 1.6) {
		return;
	}
	float u = d.x / w;
	float v = d.y / h;
	// The top edge rises and falls along the stroke; the bottom is a plain, flatter curve.
	float wob = 1.0 + 0.35 * sin(u * 11.0 + s * 10.0) + 0.2 * sin(u * 23.0 + s * 4.0);
	float edge = v > 0.0 ? v / max(wob, 0.3) : v * 1.4;
	float here = clamp(((1.0 - u * u) - edge * edge) * h / px * 0.8, 0.0, 1.0);
	float lit = clamp((v + 0.1) * 3.0, 0.0, 1.0);
	paint(here, mix(1.0, 2.0, lit) / 3.0, cover, shade);
}

// RULE 7 (with 9 and 11). A big blob's value, 0..3, from where it sits in the cloud: lighter
// toward the light and higher up, darker low down and away from it, plus a little jitter so
// neighbours differ. The Cloud_Shapes uniforms tune it. At night everything is lifted by
// night_value_lift, because FULL MOON's cloud is mostly the mid blue, not the shadow.
int blob_value(vec3 b, float width, float top, vec2 light, float jitter, float night) {
	float g = (b.x - width * 0.5) / width * light.x * value_across
		+ b.y / max(top, 0.001) * light.y * value_up
		+ value_bias + jitter * value_jitter + night * night_value_lift;
	return int(clamp(floor(g), 0.0, 3.0));
}

// RULE 3: ONE BIG BLOB AND EVERYTHING ON IT, into a premultiplied (shade, cover), painted in
// this order:
//   a. the bumps UNDER it. They're painted first so they sit BEHIND its round bottom, lumpy and
//      pushed about by extra waves, one value darker;
//   b. its body, a slightly smaller wavy circle, in the blob's own value `v`;
//   c. on a low blob in the shaded middle of the cloud (`low_inner`), one big lighter cap on its
//      sun-top side, so each low lobe reads as its own round form (rule 10);
//   d. medium bumps round its upper rim: those facing the real light one value lighter, and
//      another on the sun edge (rules 8 and 10);
//   e. on the blobs along the sun edge and up the crown (`scalloped`), small scallops on the
//      sun-side bumps. They're shallow, stretched along the rim and leaning like brush strokes,
//      and a value lighter again where they face the light: the white band of rule 8.
// `light` is the real light in the cloud's own frame, `key` = (cloud seed, blob number).
vec2 blob_unit(vec2 p, vec3 b, int v, bool low_inner, bool sun_edge, bool scalloped,
		vec2 light, vec2 key, float px) {
	vec2 unit = vec2(0.0);
	float r = b.z;
	// RULE 6: a blob sitting on the base is squashed, so the bottom of the cloud is a row of
	// shallow, nearly level arcs rather than balls.
	float squash = b.y < r * 0.7 ? base_squash : 1.0;

	// a. Five bumps round the underside, from 200 to 340 degrees, painted behind the body.
	vec2 k_under = vec2(key.x, key.y * 8.0);
	if (cloud_detail >= 1) {
		for (int i = 0; i < 5; i++) {
			vec4 m = rim_bump(b.xy, r, i, 5, 0.25, 0.42, 200.0, 340.0, k_under);
			if (squash < 1.0) {
				m.y = b.y - (b.y - m.y) * 0.6;  // flattened along with the body
			}
			if (distance(p, m.xy) > m.z * 1.75) {
				continue;
			}
			float s = float(i) * 8.0;
			// Wider than tall (1.1 x 0.8), leaning a little either way, and lumpy.
			float here = lobe(p, m.xy, m.z * 1.1, m.z * 0.8, rand(k_under, s + 3.0, 0.0, 1.0),
				0.0, rand(k_under, s + 4.0, -0.3, 0.3), 0.12, px);
			over(here, float(max(v - 1, 0)) / 3.0, unit);
		}
	}

	// b. The body: 0.86 of the blob's radius, so the rim bumps make up the rest.
	vec2 k_self = vec2(key.x, key.y * 8.0 + 7.0);
	over(lobe(p, b.xy, r * 0.86, r * 0.86 * squash, rand(k_self, 0.0, 0.0, 1.0), 0.0, 0.0, 0.0,
		px), float(v) / 3.0, unit);

	// c. The cap. It's centred high enough that its top IS the lobe's top edge, so where a lower
	// lobe covers part of it, what shows is this lobe's lit rim and never a loose fragment.
	if (low_inner) {
		vec2 at = vec2(b.x + DESIGN_LIGHT.x * r * 0.22, b.y + r * 0.86 * squash - r * 0.5);
		over(lobe(p, at, r * 0.74, r * 0.52, rand(k_self, 1.0, 0.0, 1.0), 0.0,
			rand(k_self, 2.0, -0.15, 0.15), 0.05, px), float(min(v + 1, 3)) / 3.0, unit);
	}

	if (cloud_detail < 1) {
		return unit;
	}
	// d. Two runs of six bumps round the upper rim: the sun-side stretch (75 degrees either side
	// of SUN_ANGLE), then on round the far side down to 200 degrees.
	for (int run = 0; run < 2; run++) {
		float a0 = run == 0 ? SUN_ANGLE - 75.0 : SUN_ANGLE + 75.0;
		float a1 = run == 0 ? SUN_ANGLE + 75.0 : 200.0;
		vec2 k_run = vec2(key.x, key.y * 8.0 + 1.0 + float(run));
		// e. Scallops only on the sun-side run of a blob on the outline or the crown.
		bool with_scallops = run == 0 && !low_inner && scalloped && cloud_detail >= 2;
		for (int i = 0; i < 6; i++) {
			vec4 m = rim_bump(b.xy, r, i, 6, 0.25, 0.46, a0, a1, k_run);
			if (squash < 1.0 && m.y < b.y) {
				m.y = b.y - (b.y - m.y) * 0.6;
			}
			if (distance(p, m.xy) > m.z * (with_scallops ? 2.5 : 1.2)) {
				continue;
			}
			// How squarely this bump faces the real light, -1..1.
			float face = dot(vec2(cos(m.w), sin(m.w)), light);
			// Lit: one value up where it faces the light (within about 75 degrees), except on
			// a low inner lobe, whose cap already is its lit part.
			bool lit = !low_inner && face > 0.26;
			int mv = min(3, v + (lit ? 1 : 0) + ((lit && sun_edge && face > 0.45) ? 1 : 0));
			over(lobe(p, m.xy, m.z, m.z, rand(k_run, float(i) * 8.0 + 3.0, 0.0, 1.0), 0.0, 0.0,
				0.0, px), float(mv) / 3.0, unit);
			if (!with_scallops) {
				continue;
			}
			vec2 k_sc = vec2(key.x + 0.25, (key.y * 8.0 + 1.0 + float(run)) * 8.0 + float(i));
			int sv = min(3, mv + (face > 0.55 ? 1 : 0));
			for (int j = 0; j < 5; j++) {
				vec4 sc = rim_bump(m.xy, m.z, j, 5, 0.3, 0.55, a0, a1, k_sc);
				float s = float(j) * 8.0;
				// 1.3-1.7 times wider than tall, lying along the rim (turned to its tangent)
				// and leaning back down the outline like a brush stroke.
				float rx = sc.z * rand(k_sc, s + 3.0, 1.3, 1.7);
				float ry = sc.z * rand(k_sc, s + 4.0, 0.75, 0.95);
				if (distance(p, sc.xy) > (rx + 0.42 * ry) * 1.15) {
					continue;
				}
				float lean = cos(sc.w) > 0.0 ? -0.35 : 0.35;
				over(lobe(p, sc.xy, rx, ry, rand(k_sc, s + 5.0, 0.0, 1.0), sc.w + PI * 0.5,
					lean * rand(k_sc, s + 6.0, 0.6, 1.2), 0.0, px), float(sv) / 3.0, unit);
			}
		}
	}
	return unit;
}

// One big blob of a cloud's path. It's called twice for every blob, once per pass of cumulus():
// pass 0 only measures how tall the cloud is (`top`), and pass 1 paints the blob, then keeps it
// if it is one of the two NEAREST blobs at this pixel.
//
// Rule 9's painter's order: a LOWER blob is in FRONT of a higher one, so the nearest blob is
// the one whose centre is lowest. The prototype sorted its blobs and painted them top to
// bottom. A pixel only needs the front one, plus the one behind it where the front one's edge
// is anti-aliased.
void place_blob(int pass, vec3 b, vec2 p, float seed, float width, vec2 light, float night,
		float px, inout float index, inout float highest, inout float top, inout vec3 near,
		inout vec3 next) {
	index += 1.0;
	highest = max(highest, b.y);
	if (pass == 0) {
		top = max(top, b.y + b.z);
		return;
	}
	// Nothing on a blob reaches further than 2.3 radii from its centre (its scallops).
	if (distance(p, b.xy) > b.z * 2.3) {
		return;
	}
	// Which part of the cloud this blob is on. They decide what it gets:
	//   sun_edge   on the sun-side outline (right of centre in the cloud's own frame) or up
	//              in the crown: the lighter bumps get a second step there
	//   low_inner  low down and in the shaded middle: a lighter cap instead of lit bumps
	//   scalloped  on the sun edge or high up: gets the white scallops
	bool sun_edge = (b.x - width * 0.5) / width > 0.08 || b.y + b.z > top * 0.8;
	bool low_inner = b.y + b.z * 0.5 < top * 0.5 && !sun_edge;
	bool scalloped = sun_edge || b.y + b.z > top * 0.7;
	int v = blob_value(b, width, top, light, rand(vec2(seed, index), 50.0, -1.0, 1.0), night);
	vec2 unit = blob_unit(p, b, v, low_inner, sun_edge, scalloped, light, vec2(seed, index), px);
	if (unit.y <= 0.0) {
		return;
	}
	if (b.y < near.x) {
		next = near;
		near = vec3(b.y, unit);
	} else if (b.y < next.x) {
		next = vec3(b.y, unit);
	}
}

// ONE CUMULUS MASS, the whole of rules 1-11.
//   sky          this pixel, (azimuth, elevation) in degrees
//   azimuth      the middle of the cloud;  elevation  its base
//   half_width   half its width, in degrees;  height  how tall, in degrees
//   seed         which cloud: change it for a different one
//   sky_light    the light in the sky's (across, up), from sky()
// Built in the cloud's own frame: x from 0 at its left end to `width` at its right, y up from
// its base, mirrored when its seed says so (see THE LIGHT above).
//
//   A. the big blobs (rules 1-2): a base run along the whole width, a tower on one side with
//      its sun side bulging, a crown across the tower's top, shoulders stepping down. Each one
//      is painted by blob_unit() with its bumps and scallops (rule 3), nearest in front;
//   B. clumps in front of the foot, darker than the mass behind (rule 9);
//   C. on a tall mass, big blue lobes stacked down its shaded side (rule 9);
//   D. the streak shelf under the base (rule 6).
void cumulus(vec2 sky, float azimuth, float elevation, float half_width, float height, float seed,
		vec2 sky_light, float night, float px, inout float cover, inout float shade) {
	float width = half_width * 2.0;
	// R: the big blobs' radius, a sixth of the width or so.
	float R = width * 0.15;
	float x = azimuth_offset(sky.x, azimuth) * cos(radians(elevation));
	float y = sky.y - elevation;
	// Outside everything the cloud can draw, including the shelf: nothing to do.
	if (abs(x) > width * 1.05 || y < -height * 0.12 - R * 0.6 || y > height + R * 2.0) {
		return;
	}
	// Half the clouds are mirrored, so they don't all have their tower on the same side.
	float facing = hash3(vec3(seed, 3.1, 7.7)) < 0.5 ? 1.0 : -1.0;
	vec2 p = vec2(x * facing + half_width, y);
	vec2 light = vec2(sky_light.x * facing, sky_light.y);
	// RULE 2: the tower is off-centre. -1 puts it on the side away from the design light (the
	// sheet's big tower), 0 in the middle (a rounded heap), 1 on the sun side.
	float which = hash3(vec3(seed, 5.3, 1.9));
	float tower_side = which < 0.4 ? -1.0 : (which < 0.7 ? 0.0 : 1.0);
	// The keys the path's own random numbers come from, apart from the blobs' keys.
	float path = seed + 0.75;

	// ---- A. The big blobs ---------------------------------------------------------------
	float top = 0.0;
	vec3 near = vec3(1.0e6, 0.0, 0.0);   // (centre y, shade, cover) of the nearest blob here
	vec3 next = vec3(1.0e6, 0.0, 0.0);   // and of the one behind it
	for (int pass = 0; pass < 2; pass++) {
		float index = 0.0;
		float highest = 0.0;
		// RULE 1: the base run. Six blobs along the whole width, small at the ends (45% of
		// R) and full size in the middle, each nudged up or down.
		for (int i = 0; i < 6; i++) {
			float t = (float(i) + 0.5) / 6.0;
			vec2 k = vec2(path, float(i));
			float r = R * edge_profile(t, 0.45, 1.0) * rand(k, 0.0, 0.9, 1.1);
			place_blob(pass, vec3(width * t, r * 0.55 + rand(k, 1.0, -0.08, 0.08) * r, r), p, seed,
				width, light, night, px, index, highest, top, near, next);
		}
		// RULE 2: the tower. A column stacked up from the base on its side of the cloud, each
		// step a little smaller. Beside it, a blob bulging out toward the sun all the way up,
		// most at mid height (the sheet's tower is a wide, bulging mass, not a column), and
		// in its lower part a smaller one on the shaded side.
		float tx = width * (tower_side < 0.0 ? 0.28 : (tower_side > 0.0 ? 0.72 : 0.5))
			+ rand(vec2(path, 19.0), 0.0, -0.04, 0.04) * width;
		float ty = R * 0.9;
		float tr = R * 1.05;
		for (int k = 0; k < 8; k++) {
			if (ty + tr > height) {
				break;
			}
			vec2 kk = vec2(path, 20.0 + float(k));
			place_blob(pass, vec3(tx + rand(kk, 0.0, -0.05, 0.05) * width, ty + tr * 0.35, tr),
				p, seed, width, light, night, px, index, highest, top, near, next);
			float up = (ty + tr) / height;
			if (up < 0.92) {
				float bulge = tr * (0.75 + 0.45 * sin(PI * min(up * 1.1, 1.0)));
				place_blob(pass, vec3(tx + bulge + rand(kk, 1.0, -0.03, 0.03) * width,
					ty + tr * 0.15, tr * rand(kk, 2.0, 0.85, 1.0)), p, seed, width, light, night,
					px, index, highest, top, near, next);
			}
			if (up < 0.6) {
				place_blob(pass, vec3(tx - tr * 0.7, ty + tr * 0.1, tr * 0.8), p, seed, width,
					light, night, px, index, highest, top, near, next);
			}
			ty += tr * 0.8;              // the next step up overlaps this one by a fifth
			tr = max(tr * 0.94, R * 0.78);
		}
		// The crown: the tower's top is a spread cluster of four billows, the middle ones
		// highest and one of them the biggest (rule 1 again), the outer ones stepping down so
		// the top is a dome and never overhangs.
		float crown_y = highest;
		int big_one = int(floor(rand(vec2(path, 39.0), 0.0, 1.0, 3.0)));
		for (int i = 0; i < 4; i++) {
			float t = (float(i) + 0.5) / 4.0;
			vec2 k = vec2(path, 40.0 + float(i));
			float cr = tr * edge_profile(t, 0.55, 1.0) * (i == big_one ? 1.3 : rand(k, 0.0, 0.7, 1.0));
			float e = (2.0 * t - 1.0) * (2.0 * t - 1.0);
			place_blob(pass, vec3(tx + (t - 0.5) * tr * 2.3 + rand(k, 1.0, -0.02, 0.02) * width,
				crown_y - tr * 0.35 - e * tr * 0.9 + rand(k, 2.0, -0.05, 0.05) * tr, cr), p, seed,
				width, light, night, px, index, highest, top, near, next);
		}
		// RULE 2: shoulders stepping down from the tower toward the tail: two on the side away
		// from the tower (or one each side of a middle tower), the second further out and lower.
		// Each is a short column of blobs up to 60% (then 40%) of the height.
		int sides = tower_side == 0.0 ? 2 : 1;
		for (int k = 0; k < 4; k++) {
			if (k >= 2 * sides) {
				break;
			}
			float side = sides == 1 ? -tower_side : (k % 2 == 0 ? -1.0 : 1.0);
			float step_out = float(k / sides);
			vec2 kk = vec2(path, 60.0 + float(k));
			float sx = tx + side * width * (0.2 + 0.18 * step_out) + rand(kk, 0.0, -0.03, 0.03) * width;
			float sh = height * (0.6 - 0.2 * step_out);
			float sr = R * (1.0 - 0.15 * step_out);
			float yy = R * 0.8;
			for (int j = 0; j < 6; j++) {
				if (yy + sr > sh) {
					break;
				}
				place_blob(pass, vec3(sx, yy + sr * 0.3, sr), p, seed, width, light, night, px,
					index, highest, top, near, next);
				yy += sr * 0.85;
			}
		}
	}
	// The nearest two blobs here, the one behind first.
	if (next.z > 0.0) {
		paint(next.z, next.y / next.z, cover, shade);
	}
	if (near.z > 0.0) {
		paint(near.z, near.y / near.z, cover, shade);
	}

	// ---- B. Clumps in front of the foot (rule 9) -----------------------------------------
	// Two or three big blobs over the lower middle of the mass: blue bodies against the lighter
	// cloud behind, a lavender rim where they face the light and a pale one where they face it
	// squarely. Most have a lighter lavender lobe inside, up toward the light, so the clump isn't
	// one flat silhouette.
	int n_front = height > width * 0.5 ? 3 : 2;
	for (int i = 0; i < 3; i++) {
		if (i >= n_front) {
			break;
		}
		float t = (float(i) + 0.5) / float(n_front);
		vec2 k = vec2(path, 80.0 + float(i));
		vec2 f = vec2(width * (0.15 + 0.7 * t) + rand(k, 0.0, -0.05, 0.05) * width,
			min(height * 0.28, R * 1.4) + rand(k, 2.0, -0.05, 0.05) * height);
		float fr = R * edge_profile(t, 0.6, 0.9) * rand(k, 1.0, 0.9, 1.1);
		if (distance(p, f) > fr * 2.2) {
			continue;
		}
		paint(lobe(p, f, fr * 0.86, fr * 0.86, rand(k, 3.0, 0.0, 1.0), 0.0, 0.0, 0.0, px), 0.0,
			cover, shade);
		if (cloud_detail < 1) {
			continue;
		}
		// Ten bumps all the way round but the bottom, so its outline is as lumpy as the rest.
		vec2 k_rim = vec2(seed, 1000.0 + float(i) * 8.0);
		for (int j = 0; j < 10; j++) {
			vec4 m = rim_bump(f, fr, j, 10, 0.25, 0.42, SUN_ANGLE - 100.0, SUN_ANGLE + 230.0, k_rim);
			if (distance(p, m.xy) > m.z * 2.5) {
				continue;
			}
			float face = dot(vec2(cos(m.w), sin(m.w)), light);
			int mv = face > 0.2 ? 1 : 0;
			paint(lobe(p, m.xy, m.z, m.z, rand(k_rim, float(j) * 8.0 + 3.0, 0.0, 1.0), 0.0, 0.0,
				0.0, px), float(mv) / 3.0, cover, shade);
			// Small pale bumps on the ones squarely toward the design light.
			if (cloud_detail >= 2 && dot(vec2(cos(m.w), sin(m.w)), DESIGN_LIGHT) > 0.75) {
				vec2 k_sc = vec2(seed + 0.25, 1000.0 + float(i) * 16.0 + float(j));
				int sv = face > 0.75 ? 2 : mv;
				for (int q = 0; q < 4; q++) {
					vec4 sc = rim_bump(m.xy, m.z, q, 4, 0.25, 0.45, SUN_ANGLE - 50.0,
						SUN_ANGLE + 50.0, k_sc);
					paint(lobe(p, sc.xy, sc.z, sc.z, rand(k_sc, float(q) * 8.0 + 3.0, 0.0, 1.0),
						0.0, 0.0, 0.0, px), float(sv) / 3.0, cover, shade);
				}
			}
		}
		// The lavender lobe inside it, three quarters of the time, with its own bumpy rim.
		if (rand(k, 4.0, 0.0, 1.0) > 0.25) {
			vec2 at = f + vec2(DESIGN_LIGHT.x * fr * rand(k, 5.0, 0.1, 0.35) + rand(k, 6.0, -0.2, 0.2) * fr,
				DESIGN_LIGHT.y * fr * rand(k, 7.0, 0.05, 0.3));
			float pr = fr * rand(k, 8.0, 0.35, 0.5);
			paint(lobe(p, at, pr, pr * 0.85, rand(k, 9.0, 0.0, 1.0), 0.0, 0.0, 0.0, px), 1.0 / 3.0,
				cover, shade);
			vec2 k_in = vec2(seed + 0.5, 1000.0 + float(i));
			for (int j = 0; j < 5; j++) {
				vec4 m = rim_bump(at, pr, j, 5, 0.3, 0.5, SUN_ANGLE - 80.0, SUN_ANGLE + 80.0, k_in);
				paint(lobe(p, m.xy, m.z, m.z, rand(k_in, float(j) * 8.0 + 3.0, 0.0, 1.0), 0.0, 0.0,
					0.0, px), 1.0 / 3.0, cover, shade);
			}
		}
	}

	// ---- C. Blue lobes down the shaded side of a tall mass (rule 9) -----------------------
	// On the sheet the tower's lower-left middle is its darkest part: big blue lobes stacked in
	// front of the lighter tower, lit only on their top edge. Three of them, back to front, each
	// lower and further out, so each overlaps the one behind and its lit rim separates the two.
	if (height > width * 0.7) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			vec2 k = vec2(path, 90.0 + fi);
			vec2 at = vec2(width * (0.5 - (0.05 + 0.16 * fi)) + rand(k, 0.0, -0.02, 0.02) * width,
				height * (0.5 - 0.12 * fi) + rand(k, 1.0, -0.02, 0.02) * height);
			float lr = R * (0.95 - 0.08 * fi) * rand(k, 2.0, 0.92, 1.08);
			if (distance(p, at) > lr * 1.5) {
				continue;
			}
			paint(lobe(p, at, lr * 0.88, lr * 0.88, rand(k, 3.0, 0.0, 1.0), 0.0, 0.0, 0.0, px), 0.0,
				cover, shade);
			if (cloud_detail < 1) {
				continue;
			}
			vec2 k_rim = vec2(seed, 2000.0 + fi * 16.0);
			for (int j = 0; j < 12; j++) {
				vec4 m = rim_bump(at, lr, j, 12, 0.22, 0.4, SUN_ANGLE - 110.0, SUN_ANGLE + 250.0,
					k_rim);
				if (distance(p, m.xy) > m.z * 1.2) {
					continue;
				}
				// Pale where it faces the light squarely, lavender where it faces it at all or
				// along its top, blue elsewhere.
				float face = dot(vec2(cos(m.w), sin(m.w)), light);
				int mv = face > 0.8 ? 2 : ((face > 0.2 || sin(m.w) > 0.55) ? 1 : 0);
				paint(lobe(p, m.xy, m.z, m.z, rand(k_rim, float(j) * 8.0 + 3.0, 0.0, 1.0), 0.0, 0.0,
					0.0, px), float(mv) / 3.0, cover, shade);
			}
		}
	}

	// ---- D. The streak shelf under the base (rule 6) --------------------------------------
	// Short broken strokes in two staggered layers under the base, the second a little lower,
	// reaching a little further out and one stroke longer; mostly blue, lit only on top.
	for (int layer = 0; layer < 2; layer++) {
		float fl = float(layer);
		int n = 2 + layer;
		for (int i = 0; i < 3; i++) {
			if (i >= n) {
				break;
			}
			vec2 k = vec2(path, 100.0 + fl * 4.0 + float(i));
			float t = (float(i) + rand(k, 0.0, 0.1, 0.9)) / float(n);
			float w = width * rand(k, 1.0, 0.14, 0.26) * (1.0 - 0.15 * fl);
			vec2 at = vec2(width * (-0.15 - 0.1 * fl + (1.3 + 0.2 * fl) * t),
				-height * (0.015 + 0.035 * fl) + rand(k, 2.0, -0.008, 0.008) * height);
			// Never thinner than half a degree, or a small cloud's shelf is a hairline.
			float h = max(height * rand(k, 3.0, 0.02, 0.035), 0.5);
			streak(p, at, w, h, rand(k, 4.0, 0.0, 1.0), px, cover, shade);
		}
	}
}

// RULE 12. A CLOUDLET: a few blobs on a streaky base, a bumpy white top over a lumpy blue
// underside. It leans: its blobs are biggest at the head and shrink and sink toward the tail,
// and its streaks run out from the tail, longest there. `p` is the pixel from its anchor (a
// third of the way from head to tail, on its base), already turned so the tail is to +x.
void cloudlet(vec2 p, float width, float seed, vec2 light, float px, inout float cover,
		inout float shade) {
	if (p.x < -width * 0.6 || p.x > width * 1.55 || p.y < -width * 0.14 || p.y > width * 0.36) {
		return;
	}
	// Six blobs from head to tail. The first is smaller, so the head is rounded rather than a
	// blunt end. Painted in two passes: every underside first, then every body on top, so the
	// white tops run together into one bumpy top edge.
	for (int pass = 0; pass < 2; pass++) {
		for (int i = 0; i < 6; i++) {
			float t = (float(i) + 0.5) / 6.0;
			vec2 k = vec2(seed, float(i));
			float r = width * 0.17 * (1.0 - 0.62 * t) * rand(k, 0.0, 0.85, 1.15) * (i == 0 ? 0.6 : 1.0);
			vec2 b = vec2(width * (t - 0.35) * 0.95 + rand(k, 1.0, -0.02, 0.02) * width,
				r * 0.35 - width * 0.05 * t + rand(k, 2.0, -0.1, 0.1) * r);
			if (distance(p, b) > r * 1.7) {
				continue;
			}
			if (pass == 0) {
				// The blue underside: a flat lumpy ellipse under the blob.
				paint(lobe(p, b - vec2(0.0, r * 0.15), r * 0.9, r * 0.55, rand(k, 3.0, 0.0, 1.0),
					0.0, 0.0, 0.0, px), 0.0, cover, shade);
				continue;
			}
			// The lavender body, then five bumps over its top: white facing the light, pale else.
			vec2 body = b + vec2(0.0, r * 0.1);
			paint(lobe(p, body, r * 0.8, r * 0.7, rand(k, 4.0, 0.0, 1.0), 0.0, 0.0, 0.0, px),
				1.0 / 3.0, cover, shade);
			if (cloud_detail < 1) {
				continue;
			}
			vec2 k_rim = vec2(seed + 0.25, float(i));
			for (int j = 0; j < 5; j++) {
				vec4 m = rim_bump(body, r * 0.8, j, 5, 0.3, 0.55, 15.0, 165.0, k_rim);
				float face = dot(vec2(cos(m.w), sin(m.w)), light);
				paint(lobe(p, m.xy, m.z, m.z, rand(k_rim, float(j) * 8.0 + 3.0, 0.0, 1.0), 0.0, 0.0,
					0.0, px), face > 0.45 ? 1.0 : 2.0 / 3.0, cover, shade);
			}
		}
	}
	// Four streaks trailing from the tail, each lower and longer the further back it starts.
	for (int i = 0; i < 4; i++) {
		vec2 k = vec2(seed + 0.5, float(i));
		float t = rand(k, 0.0, 0.3, 1.1);
		vec2 at = vec2(width * (t - 0.1), -width * (0.02 + 0.05 * t) + rand(k, 1.0, -0.033, 0.033) * width);
		streak(p, at, width * rand(k, 2.0, 0.18, 0.4) * (0.6 + t * 0.6),
			width * rand(k, 3.0, 0.012, 0.02), rand(k, 4.0, 0.0, 1.0), px, cover, shade);
	}
}

// RULE 12 AND 13, SPREAD OVER THE SKY. Cloudlets lie across the middle of the sky in rows: a few
// by day, and at the golden hour enough to fill its middle with GOLDEN-HOUR GLOW's bands. The
// sky between 6 and 44 degrees up is a grid of cells, ROW degrees tall and CELL degrees wide.
// Each cell holds one cloudlet or none, and `amount` is how many of them do.
void cloudlets(vec2 sky, float drift, float sun_azimuth, float night, float lit_from_above,
		float amount, float px, inout float cover, inout float shade) {
	if (amount <= 0.0 || sky.y < 4.0 || sky.y > 50.0) {
		return;
	}
	const float ROW = 5.0;
	const float CELL = 15.0;
	float row = floor((sky.y - 6.0) / ROW);
	float az = mod(sky.x - drift * 0.8 + 720.0, 360.0);
	float col = floor(az / CELL);
	float cells = 360.0 / CELL;
	// A cloudlet reaches a cell and a half along and most of a row up, so the cells round this
	// one are looked at too.
	for (int dr = -1; dr <= 1; dr++) {
		float r = row + float(dr);
		if (r < 0.0 || r > 7.0) {
			continue;
		}
		for (int dc = -2; dc <= 2; dc++) {
			float c = mod(col + float(dc), cells);
			vec2 id = vec2(c, r);
			// Denser in the lower rows, thinning out toward the zenith.
			float here_amount = amount * (1.0 - smoothstep(4.0, 7.0, r) * 0.6);
			if (hash(id + 7.1) > here_amount) {
				continue;
			}
			float h2 = hash(id * 1.3 + 17.0);
			float h3 = hash(id * 2.1 + 29.0);
			// 8 to 14 degrees from head to tail.
			float width = 8.0 + 6.0 * h2;
			vec2 at = vec2((c + 0.2 + 0.6 * h3) * CELL, 6.0 + (r + 0.15 + 0.5 * h2) * ROW);
			// Which way its tail points: half one way, half the other.
			float trail = hash(id + 3.7) < 0.5 ? 1.0 : -1.0;
			float x = azimuth_offset(az, at.x) * cos(radians(at.y)) * trail;
			float side = clamp(azimuth_offset(sun_azimuth, at.x + drift * 0.8) / 25.0, -1.0, 1.0)
				* (1.0 - 2.0 * night);
			vec2 light = normalize(vec2(side * 0.8 * trail, lit_from_above));
			cloudlet(vec2(x, sky.y - at.y), width, 300.0 + c * 7.0 + r * 3.0, light, px, cover, shade);
		}
	}
}

// Low heaps round the horizon: the sheet's lower third is heaps sitting on the sea in long
// overlapping runs, with gaps between them (rule 13). Eighteen small cumulus, one every twenty
// degrees or so, each bank_degrees-ish tall; they come in one by one as the cover rises, so
// the gaps close up toward overcast.
void horizon_banks(vec2 sky, float drift, float sun_azimuth, float night, float lit_from_above,
		float amount, float px, inout float cover, inout float shade) {
	if (sky.y > bank_degrees * 2.6 + 2.0 || sky.y < -1.0 || amount <= 0.0) {
		return;
	}
	for (int k = 0; k < 18; k++) {
		float fk = float(k);
		float h = hash(vec2(fk, 401.0));
		float at = fk * 20.0 + (h - 0.5) * 12.0 + drift * 0.6;
		float grow = smoothstep(0.1 + h * 0.5, 0.3 + h * 0.5, amount);
		if (grow <= 0.02) {
			continue;
		}
		// Half-width 1-1.6 times bank_degrees; height a third to three fifths of the width.
		float half_width = bank_degrees * (1.0 + 0.6 * hash(vec2(fk, 402.0))) * grow;
		float height = half_width * 2.0 * (0.33 + 0.27 * hash(vec2(fk, 403.0)));
		float side = clamp(azimuth_offset(sun_azimuth, at) / 25.0, -1.0, 1.0) * (1.0 - 2.0 * night);
		vec2 light = normalize(vec2(side * 0.8, lit_from_above));
		cumulus(sky, at, -0.4, half_width, height, 200.0 + fk, light, night, px, cover, shade);
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
	// The light every cloud is lit from, in the sky's (across, up): from above, and from the
	// side the sun is on - the moon's, opposite, by night. Each cloud works out its own `side`
	// below: -1 with the sun to its left, 1 to its right, in between when the sun is behind or
	// in front of it. Toward a low sun the light comes from the side more than from above.
	float lit_from_above = mix(0.35, 1.0, clamp(to_sun.y * 2.0, 0.0, 1.0));
	// Cloudlets mid-sky: a few by day, GOLDEN-HOUR GLOW's rows of them toward sunset.
	cloudlets(sky_at, drift, sun_azimuth, night, lit_from_above,
		clamp(wisps * 0.3 + golden * 0.75, 0.0, 0.85) * mix(0.6, 1.0, amount), px, cover, shade);
	horizon_banks(sky_at, drift, sun_azimuth, night, lit_from_above, amount, px, cover, shade);
	// THE BIG MASSES (rule 13). Edit these two tables to move, resize or reseed a cloud.
	// (azimuth, base elevation, half-width, height) and (seed, rank). A mass is there once the
	// cover reaches its rank, growing in over the last fifth of it rather than popping.
	// Three rings, drawn back to front: small heaps high up, a ring of middling heaps over the
	// horizon between the towers, and the towers and big heaps standing on the horizon. The
	// sheet's sky is this full - TRADE-WIND CUMULUS is cloud over most of its lower half and a
	// quarter of its top - and thirteen masses left most of the game's sky empty. The sun is
	// at about -35.
	vec4 masses[24] = vec4[24](
		vec4(20.0, 27.0, 8.0, 6.5), vec4(70.0, 21.0, 9.0, 7.0), vec4(115.0, 31.0, 7.0, 5.5),
		vec4(165.0, 24.0, 8.5, 7.0), vec4(210.0, 30.0, 7.5, 6.0), vec4(255.0, 22.0, 9.0, 7.5),
		vec4(300.0, 27.0, 8.0, 6.5), vec4(340.0, 33.0, 7.0, 5.5),
		vec4(45.0, 8.0, 10.0, 10.0), vec4(92.0, 11.0, 9.0, 8.0), vec4(140.0, 9.0, 11.0, 12.0),
		vec4(185.0, 12.0, 9.0, 8.5), vec4(230.0, 8.5, 10.5, 11.0), vec4(275.0, 10.5, 9.0, 9.0),
		vec4(320.0, 7.5, 11.0, 10.0), vec4(0.0, 12.0, 8.0, 7.5),
		vec4(10.0, 2.0, 13.0, 21.0), vec4(60.0, 2.5, 11.0, 13.0), vec4(115.0, 1.5, 13.0, 26.0),
		vec4(160.0, 2.5, 12.0, 14.0), vec4(205.0, 2.0, 11.0, 12.0), vec4(245.0, 2.5, 13.0, 18.0),
		vec4(290.0, 3.0, 10.0, 11.0), vec4(335.0, 2.0, 12.0, 16.0));
	vec2 ranks[24] = vec2[24](
		vec2(21.0, 0.40), vec2(22.0, 0.30), vec2(23.0, 0.55), vec2(24.0, 0.35), vec2(25.0, 0.50),
		vec2(26.0, 0.30), vec2(27.0, 0.45), vec2(28.0, 0.60),
		vec2(31.0, 0.25), vec2(32.0, 0.35), vec2(33.0, 0.20), vec2(34.0, 0.40), vec2(35.0, 0.25),
		vec2(36.0, 0.30), vec2(37.0, 0.20), vec2(38.0, 0.45),
		vec2(4.0, 0.05), vec2(5.0, 0.15), vec2(6.0, 0.05), vec2(7.0, 0.20), vec2(8.0, 0.10),
		vec2(9.0, 0.10), vec2(12.0, 0.25), vec2(13.0, 0.15));
	for (int m = 0; m < 24; m++) {
		float grow = smoothstep(ranks[m].y - 0.2, ranks[m].y, amount);
		if (grow < 0.05) {
			continue;
		}
		vec4 at = masses[m];
		float side = clamp(azimuth_offset(sun_azimuth, at.x + drift) / 25.0, -1.0, 1.0)
			* (1.0 - 2.0 * night);
		vec2 light = normalize(vec2(side * 0.8, lit_from_above));
		cumulus(sky_at, at.x + drift, at.y, at.z * grow, at.w * grow, ranks[m].x, light, night, px,
			cover, shade);
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
