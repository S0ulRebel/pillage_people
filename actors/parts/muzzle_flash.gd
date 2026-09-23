class_name MuzzleFlash
extends CPUParticles3D
## What comes out of the barrel: a bright flare for one or two frames, and smoke that hangs
## around after it.
##
## Two emitters rather than one, because they are opposite effects. A flare is over before you
## can look at it - that is what makes it read as a bang rather than as a flame - while the
## smoke is the part you actually see, drifting and fading for a second after. One particle
## node cannot do both: the lifetime, the colour ramp and the gravity all have to differ.
##
## A flintlock is the right weapon to bother with this for. It burns loose black powder in an
## open pan, so a real one throws a genuine cloud - the smoke here is not stylisation, it is
## the most recognisable thing about firing one.
##
## Built in code, CPUParticles3D, self-freeing: the same three choices as HitSpark, for the
## same reasons written up there.

const FLARE_LIFE := 0.07
const SMOKE_LIFE := 1.10


## Fires both effects at the muzzle. `along` is the way the barrel points.
static func burst(parent: Node, at: Vector3, along: Vector3) -> void:
	var heading := along.normalized() if along.length() > 0.001 else Vector3.FORWARD
	var flare := MuzzleFlash.new()
	flare.name = "MuzzleFlare"
	parent.add_child(flare)
	flare.global_position = at
	flare.as_flare(heading)

	var smoke := MuzzleFlash.new()
	smoke.name = "MuzzleSmoke"
	parent.add_child(smoke)
	# Started a little ahead of the pan, or the cloud is born inside his fist.
	smoke.global_position = at + heading * 0.06
	smoke.as_smoke(heading)


## The bang. Bright, forward, and gone.
func as_flare(heading: Vector3) -> void:
	_common(FLARE_LIFE)
	amount = 10
	direction = heading
	spread = 26.0
	initial_velocity_min = 2.5
	initial_velocity_max = 6.0
	gravity = Vector3.ZERO
	scale_amount_min = 0.05
	scale_amount_max = 0.16
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	scale_amount_curve = shrink
	_paint(Color(1.0, 0.92, 0.62), Color(1.0, 0.62, 0.18, 0.0))
	_finish(FLARE_LIFE)


## The powder cloud. Slow, grey, and it grows as it goes.
func as_smoke(heading: Vector3) -> void:
	_common(SMOKE_LIFE)
	amount = 18
	# Mostly forward, but lifting - hot gas does not travel in a straight line for long.
	direction = (heading + Vector3.UP * 0.45).normalized()
	spread = 42.0
	initial_velocity_min = 0.6
	initial_velocity_max = 2.2
	# Almost weightless, with a slight rise. Real gravity turns a cloud into falling dots.
	gravity = Vector3(0.0, 0.35, 0.0)
	damping_min = 1.2
	damping_max = 2.6
	scale_amount_min = 0.10
	scale_amount_max = 0.22
	# Puffing outward as it fades, which is what separates smoke from dust.
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.35))
	swell.add_point(Vector2(0.45, 1.0))
	swell.add_point(Vector2(1.0, 1.45))
	scale_amount_curve = swell
	_paint(Color(0.86, 0.85, 0.83), Color(0.72, 0.72, 0.72, 0.0))
	_finish(SMOKE_LIFE)


func _common(life: float) -> void:
	lifetime = life
	one_shot = true
	# Everything at once. A trickle reads as something burning rather than as a shot.
	explosiveness = 1.0
	# World space, so the cloud stays where it was made instead of riding the hand that fired.
	local_coords = false
	# Layer 20 is the ocean's overhead mask. Smoke is not part of the shoreline and must not
	# punch a hole in the water band - the same reasoning as HitSpark.
	layers = 1


func _paint(from: Color, to: Color) -> void:
	color = from
	var fade := Gradient.new()
	fade.set_color(0, from)
	fade.set_color(1, to)
	color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2.ONE
	var surface := StandardMaterial3D.new()
	surface.albedo_color = from
	# Unshaded and vertex-coloured for the same reasons as HitSpark: lit smoke goes darker
	# than the sand it has to read against, and without vertex colour every particle is white.
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.vertex_color_use_as_albedo = true
	surface.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Always facing the camera, or a flat quad disappears edge-on at the wrong moment.
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	surface.billboard_keep_scale = true
	puff.material = surface
	mesh = puff


func _finish(life: float) -> void:
	# restart(), not `emitting = true` - see the long note in hit_spark.gd. A one_shot node is
	# created already emitting and has spent its cycle before any of this was applied.
	restart()
	get_tree().create_timer(life * 2.0).timeout.connect(queue_free)
