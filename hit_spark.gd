extends CPUParticles3D
## A short burst of chunky sparks where a blade actually lands.
##
## The point is to tell a hit from a miss. Swinging at nothing and swinging through someone look
## identical otherwise - the animation is the same either way, and a health bar ticking down is
## not something you are looking at while you fight.
##
## CPUParticles3D rather than GPU: this is a dozen particles a few times a second, which is
## nothing, and it costs no process material, no shader compile on the first hit, and it can be
## checked in a headless test the same as any other node.
##
## Built in code like everything else here, so there is no scene or texture to keep in step.

## The colour is the whole read at this camera distance, and it has to fight the sand. Gold was
## the first choice and measured badly: against beach sand at RGB 229,182,106 it sat only 33
## luminance above it at a colour distance of 46, which looked like mustard confetti. Cool
## white manages 163 - see player.gd. Red for the blows the captain takes, which is distinct in
## hue rather than in brightness and does not need to compete.
const LIFETIME := 0.45


## Spawns a burst at a point, thrown roughly along `away`, and frees itself when it is done.
## `scale_up` is for making a burst read from further off without changing the particle count.
static func burst(parent: Node, at: Vector3, away: Vector3, colour: Color,
		scale_up := 1.0) -> CPUParticles3D:
	var sparks: CPUParticles3D = (load("res://hit_spark.gd") as GDScript).new()
	sparks.name = "HitSpark"
	parent.add_child(sparks)
	sparks.global_position = at
	sparks.configure(away, colour, scale_up)
	return sparks


func configure(away: Vector3, colour: Color, scale_up: float) -> void:
	amount = 20
	lifetime = LIFETIME
	one_shot = true
	# Everything at once. A trickle reads as something burning; an impact is a single event.
	explosiveness = 1.0
	local_coords = false

	var flat := away
	flat.y = 0.0
	direction = (flat.normalized() + Vector3.UP * 0.7).normalized() if flat.length() > 0.01 \
			else Vector3.UP
	spread = 55.0
	initial_velocity_min = 3.5 * scale_up
	initial_velocity_max = 8.0 * scale_up
	gravity = Vector3(0.0, -11.0, 0.0)
	# Shrinking as they go, so the burst reads as a pop rather than as a spray that stops.
	# Small. At 0.16 these read as paper squares rather than as sparks from a blade.
	scale_amount_min = 0.035 * scale_up
	scale_amount_max = 0.095 * scale_up
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	scale_amount_curve = shrink

	color = colour
	# Fading out as well as shrinking, or the last frame of a shard is a hard-edged box that
	# simply stops existing.
	var fade := Gradient.new()
	fade.set_color(0, Color(colour.r, colour.g, colour.b, 1.0))
	fade.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	color_ramp = fade
	var shard := BoxMesh.new()
	shard.size = Vector3.ONE
	var surface := StandardMaterial3D.new()
	surface.albedo_color = colour
	# Unshaded, or a spark lit by the scene's sun is darker than the sand it is meant to pop
	# against. Vertex colour on, or every shard draws white whatever colour was asked for.
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.vertex_color_use_as_albedo = true
	surface.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Without this the colour ramp's alpha does nothing and the shards pop out of existence at
	# full opacity.
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard.material = surface
	mesh = shard
	# Layer 20 is the ocean's overhead mask. Sparks are deliberately NOT on it: a burst is not
	# part of the shoreline and should not punch a hole in the water band as it goes off.
	layers = 1

	# restart(), not emitting = true. CPUParticles3D is created already emitting, so a one_shot
	# node has spent its single cycle before any of the settings above are applied - and
	# assigning true to a property that is already true does nothing to bring it back. The
	# result is a node that reports emitting, amount, lifetime and mesh all correct and draws
	# absolutely nothing. restart() begins a fresh cycle, which is what a burst wants anyway.
	restart()
	# Freed rather than pooled. One burst a second at most, and a node that tidies itself up
	# cannot leak when a fight is interrupted by something else.
	get_tree().create_timer(LIFETIME * 2.0).timeout.connect(queue_free)
