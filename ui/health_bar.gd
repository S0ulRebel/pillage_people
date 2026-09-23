extends Sprite3D
## A small health bar that floats above a body and always faces the camera.
##
## Placeholder art, drawn into a tiny image in code rather than imported, which is the same way
## the touch controls are built - nothing to add to the project and nothing to keep in step with
## a texture file.
##
## A Sprite3D rather than a pair of quads on purpose. Billboarding in Godot rebuilds the node's
## basis in the vertex shader, so a child offset sideways - which is how you would shrink a bar
## from one end using two meshes - gets spun around with the camera and the fill slides off the
## background. Redrawing one image instead sidesteps that entirely, and it only happens when the
## number changes, which is a few times per body.

## Pixels in the generated image. Small on purpose: it is scaled up to world size by pixel_size,
## and nearest filtering keeps the edges hard rather than smearing them.
const WIDTH := 48
const HEIGHT := 9

@export var full := Color(0.38, 0.72, 0.30)
@export var low := Color(0.80, 0.22, 0.18)
@export var backing := Color(0.09, 0.08, 0.10, 0.85)

var _image: Image
var _texture: ImageTexture


func _ready() -> void:
	# Always face the camera, ignore scene lighting, and draw over whatever is in front - a bar
	# that disappears behind the body it belongs to is worse than no bar.
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	no_depth_test = true
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Draws after the world, so it is not sorted into the middle of the character's own mesh.
	render_priority = 10
	# The camera sits high and far back on a spring arm, so a bar sized to look right standing
	# beside the grunt is a handful of pixels at play distance. 0.004 read as a dash above his
	# head and 0.008 was still only about 20 px across. This puts it at roughly 0.8 m wide -
	# half the grunt's height - which is legible from where the camera actually sits.
	pixel_size = 0.016
	_image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	texture = _texture
	set_fraction(1.0)


## 0 is empty, 1 is full. Anything outside that is clamped rather than refused, because a
## caller that overheals should not have to know about it.
func set_fraction(fraction: float) -> void:
	if _image == null:
		return
	var shown := clampf(fraction, 0.0, 1.0)
	_image.fill(backing)
	var filled := int(round((WIDTH - 2) * shown))
	var colour := low.lerp(full, shown)
	for x in range(1, 1 + filled):
		for y in range(1, HEIGHT - 1):
			_image.set_pixel(x, y, colour)
	_texture.update(_image)
