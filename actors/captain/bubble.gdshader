shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled;

// ONE BUBBLE: a thin white rim, a pale fill, a glint at the top left, on a quad that turns to
// face the camera. Every particle of actors/captain/bubbles.gd is one of these.
//
// Drawn after the underwater pass (render_priority 101, set in bubbles.gd), because that pass
// fogs by the depth buffer and a bubble writes no depth: fogged by the pass, a bubble against
// open water took the fog of the far plane and was painted out entirely. So it fogs itself
// here, by its own distance, with the pass's fog law and its level-look colour - a copy, not a
// link. Drawn after the sea's underside too, for a different reason: the sea is transparent as
// well, sorts nearer than the bubbles when the camera is a metre under it, and its underside
// is opaque, so drawn first the bubbles would be painted over.
//
// And gone before the surface. A particle system has no idea where the water ends, and the
// real surface is the swell, a hand's breadth above or below the flat level this knows - so a
// bubble pops a little early rather than ever hanging in the air over a trough as a bright
// ring with nothing to soften it.

// ---- Surface ----------------------------------------------------------------------------
group_uniforms Surface;
// Still-water level, world y: the ocean's sea_y, pushed by bubbles.gd's set_water_level() on
// the first dive. 18 is only what the shader shows before that.
uniform float water_level = 18.0;
// How far under the flat level a bubble pops: a little over the swell's height (the ocean's
// wave_height, 0.32), so none ever comes up in air over a trough. Edit both together.
uniform float pop_margin = 0.35;

// ---- Look -------------------------------------------------------------------------------
group_uniforms Look;
uniform vec3 rim_colour : source_color = vec3(0.95, 0.99, 1.0);
// The ring's thickness, as a fraction of the bubble's radius.
uniform float rim_width : hint_range(0.02, 0.4) = 0.18;
// How much the inside of the ring shows at all.
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.10;

// ---- Fog --------------------------------------------------------------------------------
group_uniforms Fog;
// The underwater pass's fog, restated: its fog_distance, and its level_colour, the blue a
// level look fades to. Copies of the Underwater node's values; nothing keeps them in step, so
// a change there is made here too.
uniform float fog_distance = 14.0;
uniform vec3 fog_colour : source_color = vec3(0.02, 0.46, 0.75);
group_uniforms;

// ---- From the vertex stage --------------------------------------------------------------
// The bubble's height, world y: against water_level for the pop.
varying float world_y;
// The particle's own alpha from its colour ramp (bubbles.gd): 1 when born, 0.6 at the end.
varying float fade;
// Metres from the bubble to the camera, for the fog.
varying float range;

void vertex() {
    // Billboard, the way StandardMaterial3D does it. INV_VIEW_MATRIX is the camera's own
    // transform, so its first three columns are the camera's right, up and back axes in world
    // space; a model matrix built from those and the bubble's own origin is a quad facing the
    // camera, wherever the bubble is. The bubble's scale was in the columns that were thrown
    // away, so it is put back.
    mat4 scale = mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
        vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
        vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
        INV_VIEW_MATRIX[2], MODEL_MATRIX[3]) * scale;
    world_y = MODEL_MATRIX[3].y;
    fade = COLOR.a;
    range = length(MODEL_MATRIX[3].xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
    // ---- 1. Only under water, and never above the pop line ------------------------------
    // From above the water the sea's top is between the eye and them, and drawn after it
    // they would sit on top of it.
    if (CAMERA_POSITION_WORLD.y > water_level || world_y > water_level - pop_margin) {
        discard;
    }

    // ---- 2. Shape: ring, fill, glint ----------------------------------------------------
    // p runs -1..1 across the quad, y down (UV y is 0 at the top); r is the distance from
    // the centre, 1 at the edge of the bubble.
    vec2 p = UV * 2.0 - 1.0;
    float r = length(p);
    // The ring is centred half a rim_width in from the edge, so it is not clipped by the quad.
    float edge = 1.0 - rim_width * 0.5;
    float rim = 1.0 - smoothstep(0.0, rim_width * 0.5, abs(r - edge));
    // The fill covers the disc, softened over its outer 15% so it never shows a hard edge.
    float inside = 1.0 - smoothstep(0.85, 1.0, r);
    // A soft spot of radius 0.25 at the top left: the reflection of the surface light.
    float glint = 1.0 - smoothstep(0.0, 0.25, length(p - vec2(-0.38, -0.38)));
    // Rim and glint at 90% - never quite solid white - plus the faint fill.
    float shape = max(rim, glint) * 0.9 + inside * fill_alpha;

    // ---- 3. Thinning out before the pop -------------------------------------------------
    // Over the last half metre before the pop line, so the pop is not a blink.
    float nearly_up = smoothstep(water_level - pop_margin - 0.5, water_level - pop_margin, world_y);

    // ---- 4. Fog: tint, then fade --------------------------------------------------------
    // The same exponential law as the pass. The colour goes to the fog's; the alpha goes
    // most of the way (85%) to nothing, so a distant bubble is a faint blue ring, not a hole.
    float fog = 1.0 - exp(-range / max(fog_distance, 0.001));
    ALBEDO = mix(rim_colour, fog_colour, fog);
    ALPHA = shape * fade * (1.0 - nearly_up) * (1.0 - fog * 0.85);
}
