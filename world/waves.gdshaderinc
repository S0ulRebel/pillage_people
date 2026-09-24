// The sea surface, as a function: where the water IS at a world point, and what it needs to
// know to say so. Included by the ocean shader, which displaces its mesh with it, and by the
// underwater shader, which has to find the same surface from below to split the screen along
// the waterline.
//
// Extracted on the third copy. ocean.gd already carries a CPU version of this sum for things
// that float, and the comment on it records what happens when two copies of the surface drift
// apart: barrels sitting in the trough while the crest goes past. A third copy, in a second
// shader, would have drifted the same way - the waterline drawn on screen sliding off the
// surface the sea is drawn with. The uniform names are the ones ocean.gd pushes, unchanged.

uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform float terrain_size = 620.0;
uniform float terrain_scale = 180.0;
uniform vec2 terrain_center = vec2(0.0);
uniform float terrain_base_y = 0.0;
uniform float sea_y = 18.0;
// The water clock, pushed from ocean.gd so the CPU and every shader agree on it. Negative
// means read TIME, which is only right for a shader nobody else has to keep in step with.
uniform float preview_time = -1.0;

group_uniforms Waves;
uniform vec4 wave_1 = vec4(1.0, 0.25, 0.72, 21.0);
uniform vec4 wave_2 = vec4(-0.5, 0.9, 0.55, 12.5);
uniform vec4 wave_3 = vec4(0.75, -0.7, 0.42, 7.0);
uniform vec4 wave_4 = vec4(-0.85, -0.3, 0.30, 3.6);
uniform float wave_height : hint_range(0.0, 3.0) = 0.32;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;
uniform float shoal_depth : hint_range(0.5, 40.0) = 2.5;
// Limits horizontal compression independently of vertical wave height.
uniform float choppiness : hint_range(0.0, 1.0) = 0.85;
group_uniforms;

float water_time() { return preview_time < 0.0 ? TIME : preview_time; }

float bed_height(vec2 p) {
    vec2 uv = (p - terrain_center) / max(terrain_size, 0.001) + 0.5;
    if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
        return sea_y - 1000.0;
    }
    return terrain_base_y + textureLod(terrain_height, uv, 0.0).r * terrain_scale;
}

// Displace geometry with Gerstner waves. Shading is evaluated independently per pixel.
void gerstner(vec4 wave, vec2 p, float scale, float horizontal_ratio,
        inout vec3 offset, inout float reach) {
    float dir_length = length(wave.xy);
    vec2 d = wave.xy / max(dir_length, 0.0001);
    float steepness = max(wave.z, 0.0) * step(0.0001, dir_length);
    float k = TAU / max(wave.w, 0.01);
    float phase = k * dot(d, p) - sqrt(9.8 * k) * water_time() * wave_speed;
    float a = steepness / k * scale;
    offset += a * vec3(horizontal_ratio * d.x * cos(phase), sin(phase), horizontal_ratio * d.y * cos(phase));
    reach += a;
}

// The horizontal share of the displacement, as the ocean's vertex shader applies it.
float horizontal_ratio() {
    float total_steepness = max(wave_1.z, 0.0) + max(wave_2.z, 0.0)
        + max(wave_3.z, 0.0) + max(wave_4.z, 0.0);
    return choppiness / max(1.0, total_steepness * wave_height);
}

void gerstner_all(vec2 p, float scale, float q, inout vec3 offset, inout float reach) {
    gerstner(wave_1, p, scale, q, offset, reach);
    gerstner(wave_2, p, scale, q, offset, reach);
    gerstner(wave_3, p, scale, q, offset, reach);
    gerstner(wave_4, p, scale, q, offset, reach);
}

// The height of the surface above a world point: the sum ocean.gd's surface_y makes on the
// CPU, with one of its two omissions put back.
//
// Still no fade with distance from the eye - the ocean's vertex shader flattens far waves
// because its mesh out there cannot carry them, and that is a concession of the mesh, not a
// property of the sea. The shoal term stays, because it is real: waves flatten as the seabed
// rises.
//
// The horizontal displacement is NOT left out here. A Gerstner wave moves water sideways as
// well as up - by up to 0.65 m with these waves - so the surface above p is the sample taken
// from somewhere else, and ocean.gd accepts what that costs a floating barrel. Measured by
// tests/underwater_view.gd against the drawn mesh, that cost was 125 mm at one spot in the
// shallows. The underwater shader cannot accept it: it draws the waterline on a near plane
// six centimetres tall, where a centimetre is a sixth of the screen.
//
// So the sample point is solved for: start at p, ask where the water at p came from, and ask
// again from there. Each step is four wave evaluations and only shrinks the error by the
// slope of the sideways displacement, which sums to about a half with these waves - so one
// step left 14 mm against the drawn mesh and three left 23 mm, on the other side of it.
// Eight steps bring it under the millimetre the mesh itself is good to. Measured, all of it,
// by tests/underwater_view.gd; with no sideways displacement the two agree to 1.6 mm, which
// is what says the rest of the sum is right.
float surface_height(vec2 p) {
    float shoal = smoothstep(0.0, max(shoal_depth, 0.001), sea_y - bed_height(p));
    float scale = shoal * wave_height;
    float q = horizontal_ratio();
    vec2 source = p;
    vec3 offset = vec3(0.0);
    float reach = 0.0;
    for (int i = 0; i < 8; i++) {
        offset = vec3(0.0);
        gerstner_all(source, scale, q, offset, reach);
        source = p - offset.xz;
    }
    offset = vec3(0.0);
    gerstner_all(source, scale, q, offset, reach);
    return sea_y + offset.y;
}
