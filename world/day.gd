class_name Day
extends Node
## Moves the scene sun through one day, and tells the sky and the sea where it is.
##
## The light already existed. This only turns it, so the shadows, the disc and the water
## stay on the same bearing. A full turn is long enough to notice and short enough to see
## night arrive in one sitting.

## Seconds from one noon to the next.
const DAY_LENGTH := 480.0
## How high the sun climbs at noon, in degrees.
const NOON := 68.0
## The light everything that is not the ground gets at night. The scene takes its ambient from
## the sky, and the night sky is near black, so rocks, palms, the ship and the captain went to
## pure silhouettes while the ground stayed readable. By day the sky alone lights them as
## before; as night falls this moonlit blue takes over.
const NIGHT_AMBIENT := Color(0.45, 0.52, 0.85)
const NIGHT_AMBIENT_ENERGY := 0.5

var _phase := 0.0
var _azimuth := 0.0
## Seconds since the day started, handed to the sky as its clouds' clock (see preview_time
## in world/sky.gdshader: the sky must not read TIME, or its lighting re-renders every frame).
var _clock := 0.0
var _sun: DirectionalLight3D
var _ocean: Ocean
var _terrain_material: ShaderMaterial


func _ready() -> void:
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	_ocean = get_parent().get_node_or_null("Ocean") as Ocean
	var terrain := get_parent().get_node_or_null("Terrain")
	if terrain != null:
		_terrain_material = terrain.get("material") as ShaderMaterial
	if _sun == null:
		return
	# Start from the light already in the scene, so the first frame is the picture we had.
	var to_sun := _sun.global_transform.basis.z
	_azimuth = atan2(to_sun.x, to_sun.z)
	var max_sine := sin(deg_to_rad(NOON))
	_phase = asin(clampf(to_sun.y / max_sine, -1.0, 1.0))
	_place(0.0)


func _process(delta: float) -> void:
	if _sun == null:
		return
	_phase += TAU * delta / DAY_LENGTH
	_clock += delta
	_place(delta)


func _place(_delta: float) -> void:
	var elevation := sin(_phase) * deg_to_rad(NOON)
	var to_sun := Vector3(sin(_azimuth) * cos(elevation), sin(elevation), cos(_azimuth) * cos(elevation)).normalized()
	var x_axis := Vector3.UP.cross(to_sun)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var y_axis := to_sun.cross(x_axis)
	_sun.global_transform = Transform3D(x_axis, y_axis, to_sun, Vector3(0.0, 60.0, 0.0))
	# Below the horizon the light is a faint cool fill, so night is dark without going black.
	var daylight := smoothstep(-0.05, 0.18, to_sun.y)
	_sun.light_energy = lerpf(0.04, 1.15, daylight)
	_sun.light_color = Color(0.62, 0.74, 1.0).lerp(Color(1.0, 0.96, 0.88), daylight)
	if _ocean != null:
		_ocean.sun_direction = to_sun
	# The ground lights its own shadows, so it has to be told when night falls or it glows.
	if _terrain_material != null:
		_terrain_material.set_shader_parameter("daylight", daylight)
		_terrain_material.set_shader_parameter("sun_direction", to_sun)
	var world := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	world.environment.fog_light_color = Color(0.06, 0.10, 0.18).lerp(Color(0.70, 0.86, 0.92), daylight)
	# 1 is the sky alone, exactly the daytime look; 0 is the moonlit colour alone.
	world.environment.ambient_light_color = NIGHT_AMBIENT
	world.environment.ambient_light_energy = NIGHT_AMBIENT_ENERGY
	world.environment.ambient_light_sky_contribution = daylight
	var sky := world.environment.sky
	if sky != null and sky.sky_material is ShaderMaterial:
		var material := sky.sky_material as ShaderMaterial
		material.set_shader_parameter("sun_direction", to_sun)
		material.set_shader_parameter("daylight", daylight)
		material.set_shader_parameter("preview_time", _clock)
