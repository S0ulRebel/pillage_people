shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled;

// One bubble: a thin white rim, a pale fill, a glint at the top left, on a quad that turns to
// face the camera.
//
// Drawn after the underwater pass (render_priority 101, set in bubbles.gd), because that
// pass fogs by the depth buffer and a bubble writes no depth: fogged by the pass, a bubble
// against open water took the fog of the far plane and was painted out entirely. So it fogs
// itself here, by its own distance, with the same law and colours the pass uses. Drawn after
// the sea's underside for the same reason: the sea is transparent too, sorts nearer than the
// bubbles when the camera is a metre under it, and its underside is opaque.
//
// And gone before the surface. A particle system has no idea where the water ends, and the
// real surface is the swell, a hand's breadth above or below the flat level this knows - so
// a bubble pops a little early rather than ever hanging in the air over a trough as a bright
// ring with nothing to soften it.

uniform float water_level = 18.0;
// How far under the flat level a bubble pops: the swell's height, so it never comes up in air.
uniform float pop_margin = 0.35;
uniform vec3 rim_colour : source_color = vec3(0.95, 0.99, 1.0);
uniform float rim_width : hint_range(0.02, 0.4) = 0.18;
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.10;
// The underwater pass's fog, restated: fog_distance and the colour a level look fades to,
// from world/underwater.gdshader.
uniform float fog_distance = 14.0;
uniform vec3 fog_colour : source_color = vec3(0.02, 0.46, 0.75);

varying float world_y;
varying float fade;
varying float range;

void vertex() {
    // Billboard, the way StandardMaterial3D does it: the instance's origin with the camera's
    // axes, and the instance's own scale put back, since the axes replaced it.
    mat4 scale = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * scale;
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
    world_y = MODEL_MATRIX[3].y;
    fade = COLOR.a;
    range = length(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
    // Only from under the water. From above, the sea's top is between the eye and them, and
    // drawn after it they would sit on top of it.
    if (CAMERA_POSITION_WORLD.y > water_level || world_y > water_level - pop_margin) {
        discard;
    }
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    float edge = 1.0 - rim_width * 0.5;
    float rim = 1.0 - smoothstep(0.0, rim_width * 0.5, abs(r - edge));
    float inside = 1.0 - smoothstep(0.85, 1.0, r);
    float glint = 1.0 - smoothstep(0.0, 0.25, length(p - vec2(-0.38, 0.38)));
    float shape = max(rim, glint) * 0.9 + inside * fill_alpha;
    // Thinning out over the last half metre before the pop, so the pop is not a blink.
    float nearly_up = smoothstep(water_level - pop_margin - 0.5, water_level - pop_margin, world_y);
    float fog = 1.0 - exp(-range / max(fog_distance, 0.001));
    ALBEDO = mix(rim_colour, fog_colour, fog);
    ALPHA = shape * fade * (1.0 - nearly_up) * (1.0 - fog * 0.85);
}
