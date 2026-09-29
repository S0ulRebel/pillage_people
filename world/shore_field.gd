extends RefCounted
## The distance to the shore, for every point on the island and the sea round it: step 1 of
## the foam plan (docs/foam-plan.md). The sea's foam, the shore waves and the sand's wet bands
## are all drawn from it, so they are measured in metres from the waterline rather than in
## metres of water depth - depth made the foam as wide as the beach was flat.
##
## A texture, computed once from the height map when the terrain is ready. Each texel holds:
##   R  signed metres to the still waterline: positive out to sea, negative up the land
##   G  x of the nearest point on the waterline, in world metres
##   B  z of the same point
##   A  nothing yet (kept for how exposed the shore is to the open sea, later)
## The direction to the shore is (G, B) minus where you are, and the nearest shore point also
## tells two stretches of beach apart, so each can get its own waves.
##
## How. The waterline is found between height samples, to a fraction of a sample (where the
## height crosses sea level along each edge of the grid). Every sample next to it is a seed
## and remembers its exact crossing point. The exact Euclidean distance transform of
## Felzenszwalb and Huttenlocher then finds, for every sample, the nearest seed - one pass down
## the columns, one along the rows - and the distance is measured to that seed's crossing
## point, not to the seed's own centre. Linear in the number of samples.
##
## Resolution. The height map is 1024 samples across 620 m; the field takes every
## `stride`-th of them (every second, 1.2 m apart, by default), a quarter of the work. The
## field is smooth everywhere except on the ridge lines half-way between two shores, and it is
## read with bilinear filtering, so a coarser grid costs little accuracy - and the waterline
## itself is still found to a fraction of a sample.

const FAR := 1.0e9
## Metres from the shore within which the field is refined to the true nearest crossing point
## (pass 3). Foam, shore waves and wet sand all live well inside it.
const REFINE_METRES := 45.0
## What a point with no shore anywhere reads as: far, and inside what a half float can hold.
const FAR_HALF := 60000.0

## The texture, and where it lies: (x, z) of texel 0's centre in world metres, the metres
## between texel centres, and the texels per side. What the shaders need to find a point in it.
var texture: ImageTexture
var rect := Vector4.ZERO
## Milliseconds the bake took, reported by the test and in the log.
var bake_msec := 0

var _cells := 0
var _signed := PackedFloat32Array()
var _near_x := PackedFloat32Array()
var _near_z := PackedFloat32Array()


## Bakes the field from a height map: `heights` is `size` x `size` samples, each a fraction of
## `height_scale`, laid over `world_size` metres centred on `centre`, with the ground `base_y`
## below them and the sea at `sea_y`.
## Returns this field, so `ShoreField.new().bake(...)` reads as one step.
func bake(heights: PackedFloat32Array, size: int, world_size: float, height_scale: float,
		base_y: float, sea_y: float, centre: Vector2, stride: int = 2) -> RefCounted:
	_bake(heights, size, world_size, height_scale, base_y, sea_y, centre, maxi(stride, 1))
	return self


## Signed metres to the waterline at a world point, read the way the shaders read it
## (bilinear). For tests and for scripts that want to know how far out to sea something is.
func distance_at(world_x: float, world_z: float) -> float:
	var gx := clampf((world_x - rect.x) / rect.z, 0.0, float(_cells - 1))
	var gz := clampf((world_z - rect.y) / rect.z, 0.0, float(_cells - 1))
	var x0 := mini(int(gx), _cells - 2)
	var z0 := mini(int(gz), _cells - 2)
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var i := z0 * _cells + x0
	return lerpf(lerpf(_signed[i], _signed[i + 1], fx),
		lerpf(_signed[i + _cells], _signed[i + _cells + 1], fx), fz)


## (signed metres to the shore, nearest shore point x, z) at a world point, filtered the way
## the shaders filter it (shore_field_at in world/shore_field.gdshaderinc). The sea's surface
## on the CPU (ocean.gd) reads this so floating things ride the same shore waves the mesh draws.
func sample(world_x: float, world_z: float) -> Vector3:
	var gx := clampf((world_x - rect.x) / rect.z, 0.0, float(_cells - 1))
	var gz := clampf((world_z - rect.y) / rect.z, 0.0, float(_cells - 1))
	var x0 := mini(int(gx), _cells - 2)
	var z0 := mini(int(gz), _cells - 2)
	var fx := gx - float(x0)
	var fz := gz - float(z0)
	var i := z0 * _cells + x0
	var j := i + _cells
	return Vector3(
		lerpf(lerpf(_signed[i], _signed[i + 1], fx), lerpf(_signed[j], _signed[j + 1], fx), fz),
		lerpf(lerpf(_near_x[i], _near_x[i + 1], fx), lerpf(_near_x[j], _near_x[j + 1], fx), fz),
		lerpf(lerpf(_near_z[i], _near_z[i + 1], fx), lerpf(_near_z[j], _near_z[j + 1], fx), fz))


## The nearest waterline point to a texel, in world metres. For tests.
func nearest_shore(world_x: float, world_z: float) -> Vector2:
	var gx := clampi(roundi((world_x - rect.x) / rect.z), 0, _cells - 1)
	var gz := clampi(roundi((world_z - rect.y) / rect.z), 0, _cells - 1)
	var i := gz * _cells + gx
	return Vector2(_near_x[i], _near_z[i])


func _bake(heights: PackedFloat32Array, size: int, world_size: float, height_scale: float,
		base_y: float, sea_y: float, centre: Vector2, stride: int) -> void:
	var started := Time.get_ticks_msec()
	var n := (size - 1) / stride + 1
	_cells = n
	var spacing := world_size / float(size - 1) * float(stride)
	var origin := centre - Vector2(world_size, world_size) * 0.5
	rect = Vector4(origin.x, origin.y, spacing, float(n))
	var count := n * n

	# Height above the sea at each of our samples: positive is land.
	var above := PackedFloat32Array()
	above.resize(count)
	for z in n:
		var row := z * stride * size
		for x in n:
			above[z * n + x] = heights[row + x * stride] * height_scale + base_y - sea_y

	# Seeds: samples beside a sign change, each with the exact crossing point nearest to it,
	# in sample units. seed_d is the squared distance from the sample to that point, so a
	# sample on two crossings keeps the closer.
	var seed_x := PackedFloat32Array()
	var seed_z := PackedFloat32Array()
	var seed_d := PackedFloat32Array()
	seed_x.resize(count)
	seed_z.resize(count)
	seed_d.resize(count)
	seed_d.fill(FAR)
	for z in n:
		for x in n:
			var i := z * n + x
			var a := above[i]
			if x + 1 < n:
				var b := above[i + 1]
				if (a > 0.0) != (b > 0.0):
					var t := a / (a - b)
					_offer_seed(seed_x, seed_z, seed_d, i, float(x) + t, float(z), x, z)
					_offer_seed(seed_x, seed_z, seed_d, i + 1, float(x) + t, float(z), x + 1, z)
			if z + 1 < n:
				var b := above[i + n]
				if (a > 0.0) != (b > 0.0):
					var t := a / (a - b)
					_offer_seed(seed_x, seed_z, seed_d, i, float(x), float(z) + t, x, z)
					_offer_seed(seed_x, seed_z, seed_d, i + n, float(x), float(z) + t, x, z + 1)

	# Pass 1, down each column: squared distance (in samples) to the nearest seed in the same
	# column, and which row it is on.
	var column_d := PackedFloat32Array()
	var column_row := PackedInt32Array()
	column_d.resize(count)
	column_row.resize(count)
	for x in n:
		var last := -1
		for z in n:
			if seed_d[z * n + x] < FAR:
				last = z
			column_row[z * n + x] = last
		last = -1
		for z in range(n - 1, -1, -1):
			var i := z * n + x
			if seed_d[i] < FAR:
				last = z
			var up := column_row[i]
			var best := -1
			if up >= 0:
				best = up
			if last >= 0 and (best < 0 or last - z < z - best):
				best = last
			column_row[i] = best
			column_d[i] = FAR if best < 0 else float((best - z) * (best - z))

	# Pass 2, along each row: the lower envelope of the parabolas column_d[q] + (x - q)^2
	# gives the nearest seed over the whole grid - its column is the parabola's, its row the one
	# pass 1 found for that column.
	var nearest := PackedInt32Array()
	nearest.resize(count)
	nearest.fill(-1)
	var hull := PackedInt32Array()
	var bounds := PackedFloat32Array()
	hull.resize(n)
	bounds.resize(n + 1)
	for z in n:
		var row := z * n
		var k := -1
		for q in n:
			var fq := column_d[row + q]
			if fq >= FAR:
				continue
			while k >= 0:
				var p := hull[k]
				var s := ((fq + q * q) - (column_d[row + p] + p * p)) / (2.0 * (q - p))
				if s <= bounds[k]:
					k -= 1
				else:
					k += 1
					hull[k] = q
					bounds[k] = s
					bounds[k + 1] = FAR
					break
			if k < 0:
				k = 0
				hull[0] = q
				bounds[0] = -FAR
				bounds[1] = FAR
		if k < 0:
			continue
		var j := 0
		for x in n:
			while bounds[j + 1] < float(x):
				j += 1
			var q := hull[j]
			nearest[row + x] = column_row[row + q] * n + q

	# Pass 3, near the shore only: the seed nearest by grid distance is not always the one whose
	# crossing point is nearest, and where the choice flips from one texel to the next the
	# contours kink - which a foam line riding them would show. So each texel also tries its
	# neighbours' seeds, in a sweep forward and a sweep back, keeping whichever crossing point is
	# really closest.
	var reach := REFINE_METRES / spacing
	var best := PackedFloat32Array()
	best.resize(count)
	for i in count:
		var seed := nearest[i]
		best[i] = FAR if seed < 0 else \
				Vector2(seed_x[seed] - float(i % n), seed_z[seed] - float(i / n)).length()
	for sweep in 2:
		var forward := sweep == 0
		var neighbours := [-1, -n - 1, -n, -n + 1] if forward else [1, n + 1, n, n - 1]
		for step in count:
			var i := step if forward else count - 1 - step
			if best[i] > reach:
				continue
			var x := i % n
			var z := i / n
			for offset in neighbours:
				var o: int = i + offset
				if o < 0 or o >= count or absi(o % n - x) > 1:
					continue
				var seed := nearest[o]
				if seed < 0 or seed == nearest[i]:
					continue
				var d := Vector2(seed_x[seed] - float(x), seed_z[seed] - float(z)).length()
				if d < best[i]:
					best[i] = d
					nearest[i] = seed

	# Written as half floats, and read back from them: the CPU copies (distance_at, sample)
	# then hold exactly what the GPU filters, so the sea's surface computed here for things that
	# float agrees with the one the mesh draws.
	_signed.resize(count)
	_near_x.resize(count)
	_near_z.resize(count)
	var bytes := PackedByteArray()
	bytes.resize(count * 8)
	for i in count:
		var x := i % n
		var z := i / n
		var seed := nearest[i]
		var point := Vector2(float(x), float(z)) if seed < 0 else Vector2(seed_x[seed], seed_z[seed])
		var world := origin + point * spacing
		var o := i * 8
		bytes.encode_half(o, (-1.0 if above[i] > 0.0 else 1.0) * (FAR_HALF if seed < 0 else best[i] * spacing))
		bytes.encode_half(o + 2, world.x)
		bytes.encode_half(o + 4, world.y)
		bytes.encode_half(o + 6, 0.0)
		_signed[i] = bytes.decode_half(o)
		_near_x[i] = bytes.decode_half(o + 2)
		_near_z[i] = bytes.decode_half(o + 4)
	var image := Image.create_from_data(n, n, false, Image.FORMAT_RGBAH, bytes)
	texture = ImageTexture.create_from_image(image)
	bake_msec = Time.get_ticks_msec() - started


static func _offer_seed(seed_x: PackedFloat32Array, seed_z: PackedFloat32Array,
		seed_d: PackedFloat32Array, i: int, px: float, pz: float, x: int, z: int) -> void:
	var d := (px - float(x)) * (px - float(x)) + (pz - float(z)) * (pz - float(z))
	if d < seed_d[i]:
		seed_d[i] = d
		seed_x[i] = px
		seed_z[i] = pz
