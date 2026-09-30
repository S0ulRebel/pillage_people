extends RefCounted
## The lace every bit of shore foam is cut from (step 4 of docs/foam-plan.md): one tiling
## texture of rounded cells, made once at load.
##
## The references' foam is a net of cells: round holes in white foam, the holes growing as the
## foam ages until the walls between them are hairlines, then break - the walls between two
## close holes first, the fat junctions where three meet last - and then nothing. That is what
## this texture lets a shader draw with one threshold. Each texel holds:
##   R  the distance to the nearest cell centre, in cells (x 4/3, so 0.75 of a cell is 1)
##   G  a random number for that cell, so holes open at different times, not all at once
##   B  the distance to the nearest cell wall (second-nearest centre minus nearest), in cells,
##      scaled the same way
##   A  1
## A hole is where R is under a radius that grows with the foam's age (world/foam.gdshaderinc):
## near zero it is solid foam with a few windows; half a cell, lace; three quarters, gone.
##
## Built here rather than shipped as a picture: no import settings to lose between machines
## and no export filter to forget, and it takes about a tenth of a second. To draw it by hand
## instead, replace make() with a load of your own picture in the same four channels.

const SIZE := 256
## Cells across the tile; the shader scales the tile to the cell size it wants.
const CELLS := 8
## How far each cell's centre wanders from the middle of its grid square, as a fraction of the
## square. The larger, the more uneven the cells.
const JITTER := 0.42


static func make(seed_value: int = 7) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var centres := PackedVector2Array()
	var randoms := PackedFloat32Array()
	for y in CELLS:
		for x in CELLS:
			centres.append(Vector2(x + 0.5 + rng.randf_range(-JITTER, JITTER),
					y + 0.5 + rng.randf_range(-JITTER, JITTER)))
			randoms.append(rng.randf())
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 4)
	var scale := float(CELLS) / float(SIZE)
	for y in SIZE:
		for x in SIZE:
			var p := Vector2((float(x) + 0.5) * scale, (float(y) + 0.5) * scale)
			var gx := int(floor(p.x))
			var gy := int(floor(p.y))
			var f1 := 1.0e9
			var f2 := 1.0e9
			var nearest := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var cx := gx + dx
					var cy := gy + dy
					var wx := posmod(cx, CELLS)
					var wy := posmod(cy, CELLS)
					var i := wy * CELLS + wx
					# The tile repeats, so a neighbour across its edge is this tile's own cell
					# on the far side, shifted by a tile.
					var c := centres[i] + Vector2(cx - wx, cy - wy)
					var d := p.distance_to(c)
					if d < f1:
						f2 = f1
						f1 = d
						nearest = i
					elif d < f2:
						f2 = d
			var o := (y * SIZE + x) * 4
			bytes[o] = clampi(roundi(f1 / 0.75 * 255.0), 0, 255)
			bytes[o + 1] = clampi(roundi(randoms[nearest] * 255.0), 0, 255)
			bytes[o + 2] = clampi(roundi((f2 - f1) / 0.75 * 255.0), 0, 255)
			bytes[o + 3] = 255
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, bytes)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
