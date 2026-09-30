@tool
extends StaticBody3D
## Builds a terrain mesh + collision: the heights of a Seabed child, with every TerrainStamp
## child laid on top in order - the island is one of those stamps. Without a Seabed the ground
## starts from a 16-bit height map instead (raw_path), which is how it used to be built.
##
## A height map is read at runtime rather than imported, so Godot's texture importer cannot
## quietly convert it to 8-bit or apply sRGB - both of which flatten the heights.

const ShoreField = preload("res://world/shore_field.gd")

## The heights are new: once when they are first laid down, and in the editor again after every
## edit that rebuilds the ground. For things that stand on the ground and cannot be asked to sit
## down again - a ScatterPatch replants on it. One placed under the Terrain is ready before the
## Terrain is, since children are readied first, and without this it would read the ground
## before there was any.
signal reshaped

## Raw 16-bit heights (make_heightmap.py writes these), read only when there is no Seabed child.
## Godot's Image loader converts a 16-bit PNG down to 8-bit, which shows up as visible
## terracing, so the .r16 is preferred and the PNG is only a fallback.
@export_file("*.r16") var raw_path := "res://terrain/heightmap.r16"
@export_file("*.png") var heightmap_path := "res://terrain/heightmap.png"

## Hand-painted overrides on top of the automatic biome (grass/sand/rock from height and
## slope): where a rock, or a patch of sand in the grass, is a choice rather than what the
## height map and the slope would draw on their own. Painted with addons/biome_painter, which
## reads and writes this file directly - no scene edit, no rebuild, just a live shader texture
## it hands the terrain to show while you paint (set_biome_image) and saves once a stroke ends.
##
## Two channels: red is which entry of biome_palette_path is painted here, 0 for none (the
## automatic colour stands); green is how strongly, 0 to 1, so a soft brush edge fades back to
## automatic rather than cutting to it. Not further biases on the automatic rules (an earlier
## version of this was three fixed axes - vegetation, rock, jungle - which could not add a
## biome the automatic rules have no idea about, like a painted path or a scorched patch): this
## looks up an actual colour and blends straight to it, so the palette can hold as many
## biomes, in whatever colours, as the palette is given.
##
## Blank (0 in both channels) means nothing painted; missing entirely is the same thing, with
## nothing on disk yet. Read the same raw way as the height map, for the same reason: Godot's
## texture importer may recompress a painted PNG, which for the height map would flatten it,
## and here would round a barely-painted edge back to fully neutral, or round a biome index to
## a different one entirely.
@export_file("*.png") var biome_path := "res://terrain/island_biome.png"
## The colours biome_path's red channel indexes into: column i (0-based) is the colour for
## index i + 1 (index 0 is reserved - "nothing painted" - and has no column). Sampled with
## point filtering, in the shader, so a soft brush edge blends through the strength channel
## and never through two neighbouring palette colours smearing into each other. Missing
## entirely, or on a Terrain that has never had addons/biome_painter open on it, falls back to
## this terrain's own grass, jungle, sand and rock colours, in that order - Paint works before
## anyone has added a single named biome. The names themselves (what addons/biome_painter's
## dock shows) live beside this file, in biome_palette_path with ".txt" for ".png" - the shader
## never needs a name, only a colour, so terrain.gd does not read that file at all.
@export_file("*.png") var biome_palette_path := "res://terrain/biome_palette.png"
## The settings below reshape the whole ground, so in the editor changing one rebuilds all of
## it - the partial rebuild an edit gets would leave the untouched chunks on the old setting.
@export var world_size := 400.0:   ## metres across
	set(value):
		world_size = value
		_setting_changed()
@export var height_scale := 60.0:  ## metres from lowest to highest point
	set(value):
		height_scale = value
		_setting_changed()
## Fraction of the height range that sits under water. make_heightmap.py bakes the same
## number into the island, so it has to match or the shoreline lands in the wrong place.
@export var sea_fraction := 0.10:
	set(value):
		sea_fraction = value
		_setting_changed()
## The material, so its colours can be tuned in the inspector instead of only in the shader.
## Only the values that depend on the scene (sea level, sun) are written from here.
@export var material: ShaderMaterial:
	set(value):
		material = value
		for chunk in _chunks:
			if chunk != null:
				chunk.material_override = value

## Colours, on the node itself rather than only inside the material. Buried under
## Material > Shader Parameters they are there but nobody finds them - and the caustics in
## particular are drawn on the seabed, so their colour lives on the terrain, which is not
## where anyone looks for the colour of something in the water.
@export_group("Colours")
@export var caustic_colour := Color(0.84, 1.0, 0.92):
	set(value):
		caustic_colour = value
		_push_colour("caustic_colour", value)
@export var seabed_colour := Color(0.78, 0.70, 0.50, 1):
	set(value):
		seabed_colour = value
		_push_colour("seabed_colour", value)
@export var deep_seabed_colour := Color(0.18, 0.36, 0.33, 1):
	set(value):
		deep_seabed_colour = value
		_push_colour("deep_seabed_colour", value)
@export var seabed_weed := Color(0.18, 0.40, 0.29, 1):
	set(value):
		seabed_weed = value
		_push_colour("seabed_weed", value)
@export var seabed_rock_colour := Color(0.27, 0.39, 0.39, 1):
	set(value):
		seabed_rock_colour = value
		_push_colour("seabed_rock_colour", value)
## The sand in three steps - dry, damp where run-ups can reach, wet where one just has - worked
## back from panels 9 and 10 of art/references/terrain-water-and-shore-transitions.jpg through
## the ground's lighting (the shader says how). Paler and less orange than it was.
@export var dry_sand_colour := Color(0.97, 0.805, 0.61):
	set(value):
		dry_sand_colour = value
		_push_colour("dry_sand_colour", value)
@export var damp_sand_colour := Color(0.81, 0.62, 0.485):
	set(value):
		damp_sand_colour = value
		_push_colour("damp_sand_colour", value)
@export var wet_sand_colour := Color(0.64, 0.51, 0.44):
	set(value):
		wet_sand_colour = value
		_push_colour("wet_sand_colour", value)
@export var grass_colour := Color(0.39, 0.555, 0.145):
	set(value):
		grass_colour = value
		_push_colour("grass_colour", value)
@export var jungle_colour := Color(0.155, 0.215, 0.105):
	set(value):
		jungle_colour = value
		_push_colour("jungle_colour", value)
@export var rock_colour := Color(0.45, 0.43, 0.46):
	set(value):
		rock_colour = value
		_push_colour("rock_colour", value)

@export_group("Caustics")
@export_range(0.02, 4.0) var caustic_scale := 0.90:
	set(value):
		caustic_scale = value
		_push_colour("caustic_scale", value)
@export_range(0.01, 0.8) var caustic_width := 0.012:
	set(value):
		caustic_width = value
		_push_colour("caustic_width", value)
@export_range(0.0, 3.0) var caustic_strength := 0.64:
	set(value):
		caustic_strength = value
		_push_colour("caustic_strength", value)
## How far from the camera the web survives. The shader also fades it by pixel
## footprint, so on a wide shot the lagoon loses its caustics unless this is opened up.
@export_range(10.0, 400.0) var caustic_distance_fade := 320.0:
	set(value):
		caustic_distance_fade = value
		_push_colour("caustic_distance_fade", value)
@export_range(0.05, 4.0) var caustic_footprint_fade := 1.2:
	set(value):
		caustic_footprint_fade = value
		_push_colour("caustic_footprint_fade", value)
@export_range(0.0, 2.0) var caustic_speed := 0.30:
	set(value):
		caustic_speed = value
		_push_colour("caustic_speed", value)
@export_range(0.5, 30.0) var caustic_reach := 12.0:
	set(value):
		caustic_reach = value
		_push_colour("caustic_reach", value)


func _push_colour(name: StringName, value: Variant) -> void:
	if material != null:
		material.set_shader_parameter(name, value)


@export_group("")   # closes "Caustics" - everything below is a build setting, not a colour
## Quads per side. The height map has 1025 samples per side - one mesh vertex on every second
## sample, which is why it is 1025 and not 1024 - so anything below 512 throws
## detail away: at 256 each quad swallowed sixteen height samples and the island came out
## smooth and faceted no matter what the shading did.
@export var mesh_resolution := 512:
	set(value):
		mesh_resolution = value
		_setting_changed()
@export var collision_resolution := 513  ## samples per side for the collision shape (match mesh_resolution + 1)
## Height samples per side when the ground starts from a Seabed; a height file says for itself.
## One mesh vertex on every second sample, as with the file - so 2 x mesh_resolution + 1. An
## island stamp the same size as the ground, with this many samples, lands sample on sample.
@export var height_samples := 1025:
	set(value):
		height_samples = maxi(value, 2)
		_setting_changed()
## Quads per chunk side. The mesh is built as a grid of square chunks rather than one piece,
## so that a stamp or tunnel edited in the editor only rebuilds the chunks it touches: the whole
## island takes about 2.5 s, one chunk of 32 quads about 10 ms, and a small stamp follows the
## gizmo as it moves. Chunks are also culled one by one, so ground behind the camera is not
## drawn. Neighbouring chunks are built from the same height samples by the same code, so
## their shared edges match exactly and the seams do not show.
@export_range(1, 512) var chunk_quads := 32:
	set(value):
		chunk_quads = maxi(value, 1)
		_setting_changed()

## Cut the ground mesh along every soft stamp's outline and along the foot of its bank, with
## vertices at the stamp's exact height, so a sharp edge is a real edge at any angle: a
## straight lip, a straight shadow, one flat wall, and a collider to match. Off, those cells
## are plain height-field triangles again, and an edge narrower than about two mesh cells
## (2.5 m) is drawn wherever the nearest vertices happen to fall - saw-toothed, with the wall
## lit triangle by triangle. Wider edges look much the same either way. Costs nothing per
## frame; on a rebuild it adds some tens of milliseconds per stamp, in the chunks it touches.
@export var cut_edges := true:
	set(value):
		cut_edges = value
		_setting_changed()

@export_group("Far seabed")
## How far out from the middle the ground goes on past the detailed square, in metres: a coarse
## ring of seabed round it, with a collider, which is also the bed the water reads out there.
## Past the camera's 1000 m, so the sea never shows where it stops. Only with a Seabed child.
@export_range(0.0, 5000.0, 10.0, "suffix:m") var far_extent := 1200.0:
	set(value):
		far_extent = value
		_setting_changed()
## Detail mesh quads per far ring cell. A whole number of them, so every cell corner along the
## square's edge is a vertex of the detailed mesh too - the ring is stitched to the detailed
## edge vertex for vertex, and there is no crack to hide.
@export_range(1, 64) var far_cell := 8:
	set(value):
		far_cell = maxi(value, 1)
		_setting_changed()
@export_group("")

## The Tunnel children being built: all of them in the game, the ticked ones in the editor.
## Each is asked where its tube is and the terrain is cut to exactly that shape - so an opening
## always matches its tunnel, whatever the slope, with nothing to line up by hand.
var tunnels: Array:
	get:
		return _tunnels
var _tunnels: Array = []
## Each built tunnel's reach, flattened to the ground plane: hole_field rejects a point outside
## all of them before it reads a height.
var _tunnel_rects: Array[Rect2] = []

var _heights: PackedFloat32Array
## The island as loaded, before any TerrainStamp children were added on top. Kept so a stamp
## that moves or goes away can be undone without reading the file again.
var _base_heights: PackedFloat32Array
var _size := 0
## The distance to the shore, baked from the heights the first time something asks for it
## and dropped whenever the heights change (see shore_field()).
var _shore_field: ShoreField = null
## The hand-painted overrides, always a real image even when biome_path has nothing on disk
## yet, so the shader uniform is never left unset. The paint tool holds this same Image (via
## biome_image()) and mutates it directly; set_biome_image() is how it hands back a repainted
## one for a live preview without saving.
var _biome_image: Image
var _biome_texture: ImageTexture
## The named colours biome_image()'s red channel indexes into - see biome_palette_path. Same
## live-preview/save split as the map above: biome_palette_image() to read and mutate,
## set_biome_palette_image() to show a change immediately.
var _biome_palette_image: Image
var _biome_palette_texture: ImageTexture
## The ground: one MeshInstance3D per chunk under a "Ground" node, row by row, and the cut rim
## triangles each chunk contributed, kept apart so a rebuilt chunk replaces only its own.
var _ground: Node3D
var _chunks: Array[MeshInstance3D] = []
var _rim_by_chunk: Array[PackedVector3Array] = []
## Collision samples each chunk knocks out of the height field, where a pad's outline cuts its
## cells: the rim trimesh above covers those cells with the drawn triangles instead.
var _nan_by_chunk: Array[PackedInt32Array] = []
## The stamps in force and where they reach, refreshed whenever the ground is restamped.
## Inside these rectangles height_at() evaluates the stamps exactly instead of reading the
## baked samples - see height_exact().
var _active_stamps: Array[TerrainStamp] = []
var _stamp_rects: Array[Rect2] = []
## Each active stamp's own reach, in the same order: past the square every stamp is evaluated
## where it reaches, and this is how the far ground skips the ones that do not.
var _active_rects: Array[Rect2] = []
## The Seabed the ground started from, or null when it came from a height file.
var _bed: Seabed = null
## The far ring, as of the last build: heights over a grid `_far_count` samples a side,
## `_far_step` apart and centred on the Terrain, in metres above it, NAN strictly inside the
## detailed square, where the ground is the chunks'. Empty without a Seabed.
var _far_heights := PackedFloat32Array()
var _far_count := 0
var _far_step := 0.0
## Far cells from the middle to the square's edge.
var _far_inner := 0
var _chunks_per_side := 0
## The grid as it was built. Read instead of the exports by everything that maps ground to
## chunks, so a setting changed in the inspector cannot address the old chunks with the new
## grid before the full rebuild it queues has happened.
var _built_quads := 32
var _built_resolution := 512
var _full_rebuild_wanted := false
## The TerrainStamp children in child order, as of the last rebuild. Stamps are applied in
## that order, and the scene dock's Move Up / Move Down changes it without any node entering,
## leaving or moving - so the order is compared on every child_order_changed.
var _stamp_order: Array = []
## The ground each stamp was last applied over, and each tunnel last cut for, as a world-space
## rectangle: what has to be redone when it moves or goes away. A stamp or tunnel with no
## entry has been edited since it was last built.
var _footprints := {}
## Edits gathered since the last rebuild: ground whose heights changed (stamps moved, arrived
## or left), ground that only needs its mesh redone (where tunnels used to be), and the
## tunnels and grass patches that changed themselves.
var _dirty_ground: Array[Rect2] = []
var _dirty_mesh: Array[Rect2] = []
var _changed_tunnels := {}
var _changed_grass := {}
var _connections := {}
var _rebuild_pending := false
## How many chunks rebuild_changed() rebuilt last time: how a test tells a partial rebuild
## from a full one.
var last_rebuilt := 0


func _init() -> void:
	# TerrainStamp, Tunnel and GrassPatch check for this group to warn when placed outside
	# the terrain.
	add_to_group(Groups.TERRAIN)


func _ready() -> void:
	if not _read_base():
		push_error("Could not load a height map (%s or %s)" % [raw_path, heightmap_path])
		return
	_biome_image = _load_biome_image()
	_biome_palette_image = _load_biome_palette_image()
	_built_quads = maxi(chunk_quads, 1)
	_built_resolution = mesh_resolution
	_chunks_per_side = ceili(float(_built_resolution) / _built_quads)
	# Children are ready before their parent, so every stamp has read its file by now - and
	# this runs before main.gd places anything on the ground, so props land on stamped ground.
	_restamp(0, _size - 1, 0, _size - 1)
	_read_far()
	_stamp_order = _stamps()
	child_entered_tree.connect(_on_child_entered)
	child_exiting_tree.connect(_on_child_exiting)
	child_order_changed.connect(_on_child_order_changed)
	for child in get_children():
		_watch(child)
	if Engine.is_editor_hint():
		# Preview the landscape in the editor - without it you would be drawing tunnel curves
		# against an empty viewport. Mesh only: collision is a runtime concern.
		_build_tunnels()
		_plant_grass()
		_build_ground()
	reshaped.emit()


## Builds the tunnels, then the mesh and colliders cut for them. Any stamp edited since the
## heights were laid down in _ready() is applied first - the test that moves one before
## calling this would otherwise get the ground as it was.
func generate() -> void:
	_restamp_changed()
	_read_far()
	_build_tunnels()
	_plant_grass()
	_build_ground()
	_build_collision()


## Hand-placed GrassPatch children, planted on the ground as it finally is - after the stamps
## have reshaped it, or the tufts would stand on the old surface.
func _plant_grass() -> void:
	for child in get_children():
		if child is GrassPatch:
			child.plant(self)


## The children whose edits reshape the ground or what stands on it.
func _tracked(child: Node) -> bool:
	return child is TerrainStamp or child is Tunnel or child is GrassPatch or child is Seabed


## The Seabed child the ground starts from, or null. `leaving` is one on its way out.
func _seabed(leaving: Node = null) -> Seabed:
	for child in get_children():
		if child is Seabed and child != leaving:
			return child
	return null


## Lays the ground down before any stamp, into _base_heights, and sets _size: from the Seabed
## child if there is one, else from the height file. False if there was nothing to read.
func _read_base(leaving: Node = null) -> bool:
	var seabed := _seabed(leaving)
	_bed = seabed
	if seabed == null:
		if not _load_raw() and not _load_png():
			return false
		_base_heights = _heights.duplicate()
		return true
	_size = height_samples
	_base_heights = seabed.fill(_size, world_size / float(_size - 1), -world_size * 0.5,
			sea_level(), height_scale)
	_heights = _base_heights.duplicate()
	return true


## Whether a stamp or tunnel is part of the terrain: always in the game, and in the editor
## only once its Preview box is ticked - an unticked one is still being placed.
func _included(child: Node) -> bool:
	return child.preview or not Engine.is_editor_hint()


## Every tunnel is prepared before any is built: building trims each tube against the others,
## which needs them all to know where they run.
func _build_tunnels() -> void:
	for child in get_children():
		if child is Tunnel:
			child.clear()
			_footprints.erase(child)
	_tunnels = []
	for child in get_children():
		if child is Tunnel and _included(child):
			_tunnels.append(child)
	for tunnel in _tunnels:
		tunnel.prepare(self)
	for tunnel in _tunnels:
		tunnel.build(_tunnels)
	_tunnels = _tunnels.filter(func(tunnel) -> bool: return not tunnel.is_empty())
	_tunnel_rects = []
	for tunnel in _tunnels:
		var rect := _flat(tunnel.bounds())
		_tunnel_rects.append(rect)
		_footprints[tunnel] = rect


## The stamps to apply, in child order.
func _stamps() -> Array[TerrainStamp]:
	var found: Array[TerrainStamp] = []
	for child in get_children():
		if child is TerrainStamp and _included(child):
			found.append(child)
	return found


## Puts the island back over a block of height samples (inclusive), then lays every stamp that
## reaches into it on top again, in child order - so a canyon listed after a mountain cuts into
## it. Over the whole map this is the first build; over one chunk it is how an edit is undone
## and redone without touching the rest. The stamps are applied one sample at a time, so doing
## a block of them again gives exactly what the whole map would have there.
func _restamp(x0: int, x1: int, z0: int, z1: int) -> void:
	_shore_field = null
	if x0 == 0 and z0 == 0 and x1 == _size - 1 and z1 == _size - 1:
		_heights = _base_heights.duplicate()   # one copy, not a million assignments
	else:
		for gz in range(z0, z1 + 1):
			var row := gz * _size
			for gx in range(x0, x1 + 1):
				_heights[row + gx] = _base_heights[row + gx]
	var spacing := world_size / float(_size - 1)
	var half := world_size * 0.5
	# The map holds heights as a fraction of height_scale; the stamp works in world metres,
	# so a levelling plane can be read straight off its position.
	var base := global_position.y
	_refresh_stamps()
	for stamp in _active_stamps:
		var rect := stamp.footprint()
		_footprints[stamp] = rect
		var sx0 := maxi(x0, clampi(floori((rect.position.x + half) / spacing), 0, _size - 1))
		var sx1 := mini(x1, clampi(ceili((rect.end.x + half) / spacing), 0, _size - 1))
		var sz0 := maxi(z0, clampi(floori((rect.position.y + half) / spacing), 0, _size - 1))
		var sz1 := mini(z1, clampi(ceili((rect.end.y + half) / spacing), 0, _size - 1))
		if sx0 > sx1 or sz0 > sz1:
			continue
		var offset := stamp.grid_offset(spacing, -half)
		if offset != TerrainStamp.OFF_GRID:
			# Sample on sample, as the island is: each ground sample is one image sample.
			var cells := stamp.image_size()
			_heights = stamp.reshape_grid(_heights, _size, offset,
					maxi(sx0, offset.x), mini(sx1, offset.x + cells.x - 1),
					maxi(sz0, offset.y), mini(sz1, offset.y + cells.y - 1), height_scale, base)
			continue
		for gz in range(sz0, sz1 + 1):
			var wz := gz * spacing - half
			for gx in range(sx0, sx1 + 1):
				var i := gz * _size + gx
				var height := _heights[i] * height_scale + base
				var reshaped := stamp.reshape(height, gx * spacing - half, wz)
				# Written only when it changed: the round trip through metres is not exact, and
				# ground a stamp leaves alone should stay bit-for-bit the island.
				if reshaped != height:
					_heights[i] = (reshaped - base) / height_scale


# --- edits -----------------------------------------------------------------------------------

func _watch(child: Node) -> void:
	if child is TerrainStamp or child is Tunnel or child is Seabed:
		var on_changed := _on_child_changed.bind(child)
		_connections[child] = on_changed
		child.changed.connect(on_changed)


func _on_child_entered(child: Node) -> void:
	if not _tracked(child):
		return
	_watch(child)
	_mark(child)
	if child is TerrainStamp:
		_refresh_stamps()
	_queue_rebuild()


func _on_child_exiting(child: Node) -> void:
	if not _tracked(child):
		return
	if _connections.has(child):
		child.changed.disconnect(_connections[child])
		_connections.erase(child)
	_mark(child, true)
	if child is TerrainStamp:
		# Out of the list at once: height_at() runs every stamp in it, and one that has left the
		# tree has no transform to run with.
		_refresh_stamps(child)
	_queue_rebuild()


func _on_child_changed(child: Node) -> void:
	_mark(child)
	_queue_rebuild()


## The Seabed is under every sample, so any change to it - a setting, the noise, arriving or
## leaving - is the whole ground again, like a Terrain setting.
func _on_seabed_changed() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	_full_rebuild_wanted = true
	_queue_rebuild()


## Adding and removing children change the order too, and those are marked on their own; only
## a change in the relative order of the stamps already here is a reorder, and then every
## stamp's ground is redone, since which one is on top may have changed anywhere they overlap.
func _on_child_order_changed() -> void:
	var now := _stamps()
	var kept_before := _stamp_order.filter(func(stamp) -> bool: return is_instance_valid(stamp) and now.has(stamp))
	var kept_now := now.filter(func(stamp) -> bool: return _stamp_order.has(stamp))
	if kept_before != kept_now:
		for stamp in now:
			_mark(stamp)
		_queue_rebuild()
	_stamp_order = now


## A setting that shapes the whole ground changed in the inspector: everything is rebuilt,
## after the same short wait as an edit.
func _setting_changed() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	_full_rebuild_wanted = true
	_queue_rebuild()


## Records that a child changed: the ground it was applied over is to be redone, and so is
## wherever it is now - found at rebuild time, since a stamp being dragged moves on before the
## rebuild comes round.
func _mark(child: Node, leaving := false) -> void:
	if child is TerrainStamp:
		if _footprints.has(child):
			_dirty_ground.append(_footprints[child])
			_footprints.erase(child)
	elif child is Tunnel:
		if _footprints.has(child):
			_dirty_mesh.append(_footprints[child])
			_footprints.erase(child)
		_changed_tunnels[child] = not leaving
	elif child is GrassPatch:
		_changed_grass[child] = not leaving
	elif child is Seabed:
		_on_seabed_changed()


## Editor only: rebuilds what changed a moment after it did. A drag sends a change every
## frame; the short wait gathers a burst of them into one rebuild. In the game the ground is
## built once, and a stamp moved at runtime would leave the collider behind.
func _queue_rebuild() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or _base_heights.is_empty():
		return
	if _rebuild_pending:
		return
	_rebuild_pending = true
	await get_tree().create_timer(0.1).timeout
	_rebuild_pending = false
	if not is_inside_tree():
		return
	rebuild_changed()


## Rebuilds only what the edits since the last build touched: the ground the moved stamps
## covered before and cover now, the tunnels standing on that ground or edited themselves, the
## chunks over all of it, and the grass on it. Everything else stays as built. This is what
## makes editing live - the whole island is 3 s of work, a stamp's few chunks a fraction of
## a second - and tests/chunk_check.gd checks that it comes out the same as building from
## scratch.
func rebuild_changed() -> void:
	last_rebuilt = 0
	if _base_heights.is_empty() or not is_inside_tree():
		return
	if _full_rebuild_wanted:
		_full_rebuild_wanted = false
		_forget_edits()
		# Read again: a Seabed setting, or a Terrain one it depends on (the size, the sea
		# level), changes every sample it laid down.
		_read_base()
		_restamp(0, _size - 1, 0, _size - 1)
		_read_far()
		_stamp_order = _stamps()
		_build_tunnels()
		_plant_grass()
		_build_ground()
		last_rebuilt = _chunks.size()
		reshaped.emit()
		return
	var spacing := world_size / float(_size - 1)
	# 1. The ground.
	_restamp_changed()
	_stamp_order = _stamps()
	if _chunks.is_empty():
		_forget_edits()   # nothing built yet: the heights were all there was to do
		reshaped.emit()
		return

	# 2. The tunnels: any edited, any standing on ground that moved (a tube is trimmed to the
	# ground, and its underground run may have changed), and any crossing one of those (its
	# walls are trimmed where the two meet). Ground that moved reaches two samples further for
	# the mesh, which reads a sample's neighbours for its normal.
	# Three mesh cells: a pad's outline cuts the cells it crosses, the cells round those go into
	# the rim collider, and the normals read a sample beyond that.
	var moved_ground: Array[Rect2] = []
	for rect in _dirty_ground:
		moved_ground.append(rect.grow(3.0 * world_size / _built_resolution + 0.01))
	var tunnel_rects: Array[Rect2] = _dirty_mesh.duplicate()   # where edited tunnels were
	# A tunnel freed since it left would otherwise stay in the list with no footprint, and
	# every rebuild from then on would stop at the first lookup.
	_tunnels = _tunnels.filter(func(tunnel) -> bool:
			return is_instance_valid(tunnel) and tunnel.get_parent() == self)
	var reprepare := {}
	for tunnel in _changed_tunnels:
		if not is_instance_valid(tunnel):
			continue
		if _changed_tunnels[tunnel] and tunnel.get_parent() == self and _included(tunnel):
			reprepare[tunnel] = true
		else:
			_tunnels.erase(tunnel)
			if tunnel.get_parent() == self:
				tunnel.clear()
	# Against the whole curve's reach, not the bounds of what was built: a curve that ran above
	# a valley floor is buried by a mountain stamped over it, and the built bounds of a tunnel
	# that never went underground are nothing at all.
	for child in get_children():
		if child is Tunnel and not reprepare.has(child) and _included(child) \
				and _intersects_any(child.curve_footprint(), moved_ground):
			reprepare[child] = true
	for tunnel in _tunnels:
		if not _footprints.has(tunnel):
			reprepare[tunnel] = true
	var rebuild := {}
	for tunnel in reprepare:
		if _footprints.has(tunnel):
			tunnel_rects.append(_footprints[tunnel])
			_footprints.erase(tunnel)
		tunnel.prepare(self)
		if tunnel.is_empty():
			_tunnels.erase(tunnel)
			continue
		if not _tunnels.has(tunnel):
			_tunnels.append(tunnel)
		var rect := _flat(tunnel.bounds())
		_footprints[tunnel] = rect
		tunnel_rects.append(rect)
		rebuild[tunnel] = true
	for tunnel in _tunnels:
		if not rebuild.has(tunnel) and _intersects_any(_footprints[tunnel], tunnel_rects):
			rebuild[tunnel] = true
	for tunnel in rebuild:
		tunnel.clear()
		tunnel.build(_tunnels)
	_tunnel_rects = []
	for tunnel in _tunnels:
		_tunnel_rects.append(_footprints[tunnel])

	# 3. The chunks over all of it. The material is refreshed first: a full build used to do
	# that on every edit, and it is how a turned sun reaches the shader in the editor.
	_setup_material()
	var mesh_rects: Array[Rect2] = moved_ground.duplicate()
	mesh_rects.append_array(tunnel_rects)
	var chunks := _chunks_touching(mesh_rects, 0.01)
	for index in chunks:
		_build_chunk(index)
	last_rebuilt = chunks.size()
	# The far ring, when the ground that moved reaches the square's edge: its inner row is
	# stitched to the edge's own vertices, and past the edge a stamp shapes it directly.
	var half := world_size * 0.5
	for rect in moved_ground:
		if rect.position.x <= -half or rect.position.y <= -half or rect.end.x >= half \
				or rect.end.y >= half:
			_read_far()
			_build_far_mesh()
			break

	# 4. The grass: patches that changed, and patches on ground that did.
	for child in get_children():
		if child is GrassPatch:
			var foot := Vector2(child.global_position.x, child.global_position.z)
			var on_moved_ground := false
			for rect in moved_ground:
				on_moved_ground = on_moved_ground or rect.grow(child.radius).has_point(foot)
			if _changed_grass.get(child, false) or on_moved_ground:
				child.plant(self)
	_forget_edits()
	reshaped.emit()


## The ground under every stamp edit since the last build: put the island back and the stamps
## on again, chunk by chunk. Grown by a sample so a sample sitting exactly on a chunk's edge is
## redone whichever side it counts.
func _restamp_changed() -> void:
	# A stamp with no footprint on record is new here or was edited: where it is now is dirty.
	for stamp in _stamps():
		if not _footprints.has(stamp):
			_dirty_ground.append(stamp.footprint())
	var spacing := world_size / float(_size - 1)
	for index in _chunks_touching(_dirty_ground, spacing):
		var r := _chunk_samples(index)
		_restamp(r[0], r[1], r[2], r[3])


## The stamps in force, in child order, and where each reaches - what height_at() evaluates
## exactly. `leaving` is a child on its way out, still a child when this runs.
func _refresh_stamps(leaving: Node = null) -> void:
	_active_stamps = []
	_stamp_rects = []
	_active_rects = []
	# A sample's margin round the reach: just outside a fade the baked samples inside it still
	# lean on what is read between them, so exact and baked only agree a sample further out.
	# Without it a foot vertex right on the edge of the reach read baked ground, 0.3 m off.
	var spacing := world_size / float(maxi(_size - 1, 1))
	var margin := spacing + 0.15
	for stamp in _stamps():
		# not one on its way out, nor - when the terrain itself is leaving the tree, children
		# first - one that has already gone
		if stamp != leaving and stamp.is_inside_tree():
			_active_stamps.append(stamp)
			_active_rects.append(stamp.footprint())
			# Not an image that lands sample on sample on the grid: the baked samples are its
			# own, and read between them the same way, so the exact path would add nothing - and
			# the island is one, covering every sample, so it would send every lookup the slow
			# way. Any other image keeps it: a sharp step in one sampled finer than the ground
			# was 1.7 m out read off the baked grid.
			if stamp.has_outline() \
					or stamp.grid_offset(spacing, -world_size * 0.5) == TerrainStamp.OFF_GRID:
				_stamp_rects.append(stamp.footprint().grow(margin))


func _forget_edits() -> void:
	_dirty_ground = []
	_dirty_mesh = []
	_changed_tunnels = {}
	_changed_grass = {}


# --- chunks ----------------------------------------------------------------------------------

## A chunk's side, in metres.
func _chunk_size() -> float:
	return _built_quads * world_size / _built_resolution


## The chunks any of the rectangles reach into, as a set of chunk indices. A rectangle off the
## island reaches none, rather than the edge chunk the clamp would give it.
func _chunks_touching(rects: Array[Rect2], grow: float) -> Dictionary:
	var found := {}
	var half := world_size * 0.5
	var size := _chunk_size()
	var last := _chunks_per_side - 1
	for rect in rects:
		var r := rect.grow(grow)
		if r.end.x < -half or r.end.y < -half or r.position.x > half or r.position.y > half:
			continue
		var cx0 := clampi(floori((r.position.x + half) / size), 0, last)
		var cx1 := clampi(floori((r.end.x + half) / size), 0, last)
		var cz0 := clampi(floori((r.position.y + half) / size), 0, last)
		var cz1 := clampi(floori((r.end.y + half) / size), 0, last)
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				found[cz * _chunks_per_side + cx] = true
	return found


## The first height sample at or past chunk edge `edge` (0 to _chunks_per_side). The chunks
## share the samples out between them, each taking those from its own edge up to the next, so
## a block of samples is redone once and only once however many chunks are dirty.
func _sample_bound(edge: int) -> int:
	if edge >= _chunks_per_side:
		return _size
	var spacing := world_size / float(_size - 1)
	return clampi(ceili(edge * _chunk_size() / spacing - 0.0001), 0, _size)


## A chunk's block of height samples: x0, x1, z0, z1, inclusive.
func _chunk_samples(index: int) -> PackedInt32Array:
	var cx := index % _chunks_per_side
	var cz := index / _chunks_per_side
	return PackedInt32Array([_sample_bound(cx), _sample_bound(cx + 1) - 1,
			_sample_bound(cz), _sample_bound(cz + 1) - 1])


func _flat(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


func _intersects_any(rect: Rect2, rects: Array[Rect2]) -> bool:
	for other in rects:
		if rect.intersects(other):
			return true
	return false


## Negative where the ground is inside a tunnel, positive outside, zero on the opening's edge:
## the contour the terrain mesh is cut along.
##
## Each tunnel is only asked inside its own bounds. Asking every tunnel about every point of
## the island - a million vertices against every segment - was most of the cost of a tunnel.
func hole_field(world_x: float, world_z: float) -> float:
	var near := false
	for rect in _tunnel_rects:
		if rect.has_point(Vector2(world_x, world_z)):
			near = true
			break
	if not near:
		return 1e9
	var point := Vector3(world_x, height_at(world_x, world_z), world_z)
	var best := 1e9
	for tunnel in _tunnels:
		if tunnel.bounds().has_point(point):
			best = minf(best, tunnel.distance_outside(point))
	return best


func _load_raw() -> bool:
	var file := FileAccess.open(raw_path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(file.get_length())
	var count := bytes.size() / 2
	_size = int(sqrt(float(count)))
	if _size * _size != count:
		push_error("%s is not square (%d samples)" % [raw_path, count])
		return false
	_heights = PackedFloat32Array()
	_heights.resize(count)
	for i in count:
		_heights[i] = bytes.decode_u16(i * 2) / 65535.0
	return true


func _load_png() -> bool:
	var image := Image.load_from_file(ProjectSettings.globalize_path(heightmap_path))
	if image == null:
		return false
	_size = image.get_width()
	_heights = PackedFloat32Array()
	_heights.resize(_size * _size)
	for y in _size:
		for x in _size:
			_heights[y * _size + x] = image.get_pixel(x, y).r
	return true


## The default size of a freshly started biome map: fine enough for a small patch of sand in
## the grass to read as a patch and not a blur, without making the painted file large.
const BIOME_MAP_SIZE := 1024

## Reads biome_path raw, the same way as the height map and for the same reason - Godot's
## import step may recompress it, which for a painted map would round a barely-painted edge
## back to fully neutral or round a biome index to a different one entirely - or hands back a
## blank one, (0, 0, *, *) everywhere: index 0, "nothing painted here" (see the biome_map
## uniform doc in the shader). Never fails: an island with nothing painted is meant to look
## exactly as it always has.
func _load_biome_image() -> Image:
	if biome_path != "" and FileAccess.file_exists(biome_path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(biome_path))
		if image != null:
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			return image
	var blank := Image.create(BIOME_MAP_SIZE, BIOME_MAP_SIZE, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 0.0, 0.0, 1.0))
	return blank


## The image the paint tool should read and mutate directly - the same one the shader is
## currently showing. Never null: _ready() always fills it in, even before this node has
## finished entering the tree, so a plugin acting the instant it selects a Terrain still gets a
## real image to paint rather than having to know about load order.
func biome_image() -> Image:
	if _biome_image == null:
		_biome_image = _load_biome_image()
	return _biome_image


## Shows a repainted image immediately: one texture upload, no mesh rebuild, no chunk touched -
## painting changes what a pixel is coloured, never where the ground or a collider is. Call
## this after every brush dab for a live preview; save the file separately once a stroke ends
## (Image.save_png), since a save is a disk write and a dab is not.
func set_biome_image(image: Image) -> void:
	_biome_image = image
	if material == null:
		return
	if _biome_texture != null and Vector2i(_biome_texture.get_size()) == image.get_size():
		_biome_texture.update(image)
	else:
		_biome_texture = ImageTexture.create_from_image(image)
	material.set_shader_parameter("biome_map", _biome_texture)


## Re-reads biome_path from disk and shows it: for picking up a save made by a previous editor
## session, or a file someone edited outside Godot. A live paint stroke does not need this -
## set_biome_image() already shows what is being painted without touching disk.
func reload_biome_map() -> void:
	set_biome_image(_load_biome_image())


## Reads biome_palette_path raw, or builds one from this terrain's own grass, jungle, sand and
## rock colours (in that order, so a fresh Terrain already has four sensible names once
## addons/biome_painter opens on it and writes biome_palette_path's sidecar .txt) when there is
## nothing on disk yet. One row (height 1), point-sampled by index in the shader.
func _load_biome_palette_image() -> Image:
	if biome_palette_path != "" and FileAccess.file_exists(biome_palette_path):
		var image := Image.load_from_file(ProjectSettings.globalize_path(biome_palette_path))
		if image != null:
			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)
			return image
	var colours := [grass_colour, jungle_colour, dry_sand_colour, rock_colour]
	var palette := Image.create(colours.size(), 1, false, Image.FORMAT_RGBA8)
	for i in colours.size():
		palette.set_pixel(i, 0, colours[i])
	return palette


## The palette the paint tool should read and mutate directly - see biome_image().
func biome_palette_image() -> Image:
	if _biome_palette_image == null:
		_biome_palette_image = _load_biome_palette_image()
	return _biome_palette_image


## Shows a repainted palette immediately - see set_biome_image(). Every painted pixel's colour
## can change at once from this (index 3 turning red everywhere it was painted, say), which is
## the point: a palette entry is a name for a colour, and renaming its colour should not mean
## repainting everything that uses it.
func set_biome_palette_image(image: Image) -> void:
	_biome_palette_image = image
	if material == null:
		return
	if _biome_palette_texture != null and Vector2i(_biome_palette_texture.get_size()) == image.get_size():
		_biome_palette_texture.update(image)
	else:
		_biome_palette_texture = ImageTexture.create_from_image(image)
	material.set_shader_parameter("biome_palette", _biome_palette_texture)


## Re-reads biome_palette_path from disk and shows it - see reload_biome_map().
func reload_biome_palette() -> void:
	set_biome_palette_image(_load_biome_palette_image())


## Bilinear sample of the height map in 0..1 texture space.
func sample_height(u: float, v: float) -> float:
	return _bilinear(_heights, u, v) * height_scale


func _bilinear(values: PackedFloat32Array, u: float, v: float) -> float:
	u = clampf(u, 0.0, 1.0) * (_size - 1)
	v = clampf(v, 0.0, 1.0) * (_size - 1)
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, _size - 1)
	var y1 := mini(y0 + 1, _size - 1)
	var fx := u - x0
	var fy := v - y0
	var h00 := values[y0 * _size + x0]
	var h10 := values[y0 * _size + x1]
	var h01 := values[y1 * _size + x0]
	var h11 := values[y1 * _size + x1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy)


## A spawn point on gentle mid-altitude ground, so the view starts somewhere interesting
## rather than on a peak or in a pit.
## Sea level in metres, the single source of truth for the ocean plane and for swimming.
func sea_level() -> float:
	return height_scale * sea_fraction


func find_spawn() -> Vector3:
	var best := Vector3.ZERO
	var best_score := -1.0
	for i in 400:
		var wx := randf_range(-world_size, world_size) * 0.35
		var wz := randf_range(-world_size, world_size) * 0.35
		var h := height_at(wx, wz)
		var t := h / height_scale
		# prefer mid heights, and flat-ish ground (small difference to neighbours)
		var slope: float = absf(height_at(wx + 4.0, wz) - h) + absf(height_at(wx, wz + 4.0) - h)
		var score: float = 1.0 - absf(t - 0.45) * 2.0 - slope * 0.25
		if score > best_score:
			best_score = score
			best = Vector3(wx, h, wz)
	return best


## Two spots near the spawn, far enough apart to be worth a tunnel between them, on ground
## that is not a cliff.
func plan_tunnel_ends(spawn: Vector3) -> Array[Vector3]:
	var best: Array[Vector3] = []
	var best_score := -1e9
	for attempt in 4000:
		var angle := randf() * TAU
		var a := Vector3(spawn.x + cos(angle) * randf_range(25.0, 45.0), 0.0,
				spawn.z + sin(angle) * randf_range(25.0, 45.0))
		var away := angle + randf_range(2.0, 4.3)
		var b := Vector3(a.x + cos(away) * randf_range(45.0, 70.0), 0.0,
				a.z + sin(away) * randf_range(45.0, 70.0))
		if maxf(absf(b.x), absf(b.z)) > world_size * 0.45:
			continue
		a.y = height_at(a.x, a.z)
		b.y = height_at(b.x, b.z)
		# gentle ground at both ends, and not too much height difference between them
		var score: float = -absf(a.y - b.y) - _roughness(a) * 2.0 - _roughness(b) * 2.0
		if score > best_score:
			best_score = score
			best = [a, b]
	return best


func _roughness(point: Vector3) -> float:
	var h := height_at(point.x, point.z)
	var total := 0.0
	for step in 4:
		var angle := TAU * step / 4.0
		total += absf(height_at(point.x + cos(angle) * 6.0, point.z + sin(angle) * 6.0) - h)
	return total * 0.25


# --- the far seabed --------------------------------------------------------------------------

## Past the square, where there are no baked samples: the Seabed at the point itself, with every
## stamp that reaches there on it - so a pad whose fade crosses the edge carries on across it.
func _far_height(world_x: float, world_z: float) -> float:
	var base := global_position.y
	var half := world_size * 0.5
	var height := _bed.height_at(world_x, world_z, sea_level(),
			Rect2(-half, -half, world_size, world_size)) + base
	var point := Vector2(world_x, world_z)
	for k in _active_stamps.size():
		if _active_rects[k].has_point(point) and _active_stamps[k].is_inside_tree():
			height = _active_stamps[k].reshape(height, world_x, world_z)
	return height - base


## The far ring's heights, read through height_at() so they are the ground everything else
## reads. Nothing without a Seabed, or when far_extent does not reach past the square.
func _read_far() -> void:
	_far_heights = PackedFloat32Array()
	_far_count = 0
	var half := world_size * 0.5
	if _bed == null or far_extent <= half:
		return
	# The square's edge has to fall on a far sample, or the ring cannot be stitched to it.
	if _built_resolution % (2 * far_cell) != 0:
		push_error("far_cell %d does not divide mesh_resolution %d into halves - no far seabed"
				% [far_cell, _built_resolution])
		return
	_far_step = world_size / _built_resolution * far_cell
	_far_inner = _built_resolution / (2 * far_cell)
	var cells := _far_inner + ceili((far_extent - half) / _far_step)
	_far_count = cells * 2 + 1
	_far_heights.resize(_far_count * _far_count)
	for j in _far_count:
		var z := (j - cells) * _far_step
		for i in _far_count:
			var x := (i - cells) * _far_step
			var inside := absf(x) < half and absf(z) < half
			_far_heights[j * _far_count + i] = NAN if inside else height_at(x, z)


## The far ring as ground you can see: a coarse grid from the square's edge out to far_extent,
## coloured and shaded like the chunks. Its cells along the edge are stitched to the edge's
## own vertices - a fan from each of the cell's two outer corners through the eight or so
## detail vertices on its inner side - so nothing needs hiding where the two meet.
func _build_far_mesh() -> void:
	var old := get_node_or_null(^"FarSeabed")
	if old != null:
		remove_child(old)
		old.queue_free()
	if _far_count == 0:
		return
	var cells := (_far_count - 1) / 2
	var detail := world_size / _built_resolution
	var half := world_size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in _far_count - 1:
		var cj := j - cells
		for i in _far_count - 1:
			var ci := i - cells
			var across_x := ci >= -_far_inner and ci < _far_inner
			var across_z := cj >= -_far_inner and cj < _far_inner
			if across_x and across_z:
				continue                                 # inside the square: the chunks' ground
			var a := _far_vertex(i, j)
			var b := _far_vertex(i + 1, j)
			var c := _far_vertex(i + 1, j + 1)
			var d := _far_vertex(i, j + 1)
			# A cell sharing a side with the square: that side is the detailed edge instead.
			var inner: Array[Vector3] = []
			var outer: Array[Vector3] = []
			if across_z and ci == _far_inner:            # east of the square
				inner = _edge_run(half, cj * _far_step, false, detail)
				outer = [b, c]
			elif across_z and ci == -_far_inner - 1:     # west
				inner = _edge_run(-half, cj * _far_step, false, detail)
				outer = [a, d]
			elif across_x and cj == _far_inner:          # south
				inner = _edge_run(ci * _far_step, half, true, detail)
				outer = [d, c]
			elif across_x and cj == -_far_inner - 1:     # north
				inner = _edge_run(ci * _far_step, -half, true, detail)
				outer = [a, b]
			if inner.is_empty():
				_far_triangle(st, a, b, c)
				_far_triangle(st, a, c, d)
				continue
			var middle := inner.size() / 2
			for k in inner.size() - 1:
				_far_triangle(st, inner[k], inner[k + 1], outer[0] if k < middle else outer[1])
			_far_triangle(st, inner[middle], outer[1], outer[0])
	st.index()
	var instance := MeshInstance3D.new()
	instance.name = "FarSeabed"
	instance.material_override = material
	instance.mesh = st.commit()
	add_child(instance)


## A far grid sample as a point on the ground.
func _far_vertex(i: int, j: int) -> Vector3:
	var cells := (_far_count - 1) / 2
	return Vector3((i - cells) * _far_step, _far_heights[j * _far_count + i],
			(j - cells) * _far_step)


## The detailed mesh's own vertices along one far cell's side of the square's edge, from its
## low end to its high end: at the chunks' positions, (k * detail - half), so they are the very
## same points, and at height_at() there, which is what the chunks stand them at.
func _edge_run(x: float, z: float, along_x: bool, detail: float) -> Array[Vector3]:
	var half := world_size * 0.5
	var start := roundi(((x if along_x else z) + half) / detail)
	var run: Array[Vector3] = []
	for k in range(start, start + far_cell + 1):
		var t := k * detail - half
		var point := Vector3(t, 0.0, z) if along_x else Vector3(x, 0.0, t)
		point.y = height_at(point.x, point.z)
		run.append(point)
	return run


## One triangle of the far ring, wound the way the chunks wind theirs, with the chunks' colour
## and a normal read off the ground itself, and its UV held to the square's edge - the biome map
## has nothing painted out here, and read past its edge it would wrap round to the other side.
func _far_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y > 0.0:
		var swap := b
		b = c
		c = swap
	for p in [a, b, c]:
		st.set_uv(Vector2(clampf(p.x / world_size + 0.5, 0.0, 1.0),
				clampf(p.z / world_size + 0.5, 0.0, 1.0)))
		st.set_color(_terrain_colour(p.y))
		st.set_normal(_surface_normal(p.x, p.z))
		st.add_vertex(p)


## The far ring's heights as a texture, for the water: metres above the Terrain. The square's
## inside is filled in from the baked samples rather than left NAN, which filtering would
## spread across the edge; the water reads the detailed texture in there anyway. Null without
## a far ring.
func far_texture() -> ImageTexture:
	if _far_count == 0:
		return null
	var cells := (_far_count - 1) / 2
	var bytes := PackedByteArray()
	bytes.resize(_far_count * _far_count * 4)
	for j in _far_count:
		for i in _far_count:
			var h := _far_heights[j * _far_count + i]
			if is_nan(h):
				h = height_at((i - cells) * _far_step, (j - cells) * _far_step)
			bytes.encode_float((j * _far_count + i) * 4, h)
	var image := Image.create_from_data(_far_count, _far_count, false, Image.FORMAT_RF, bytes)
	return ImageTexture.create_from_image(image)


## How many metres far_texture() spans, centred on the Terrain; 0 without a far ring.
func far_size() -> float:
	return (_far_count - 1) * _far_step if _far_count > 0 else 0.0


## World height of the bed past the far ring: sea level less the Seabed's far depth.
func far_floor() -> float:
	var below := _bed.far_depth if _bed != null else 60.0
	return global_position.y + sea_level() - below


## The height map as a texture, so a shader can read the seabed.
##
## The water needs to know how deep it is at every point - to flatten the swell as it shoals,
## and to colour itself - and reading it from the depth buffer instead ties the colour to the
## displaced surface, which then shimmers as the waves move.
func height_texture() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(_heights.size() * 4)
	for i in _heights.size():
		bytes.encode_float(i * 4, _heights[i])
	var image := Image.create_from_data(_size, _size, false, Image.FORMAT_RF, bytes)
	return ImageTexture.create_from_image(image)


## The distance to the shore everywhere on the map, and the nearest point of the waterline
## (world/shore_field.gd). Baked on first use from the heights as they are then, stamps
## included, and again after any restamp. The sea's and the sand's foam both read it.
func shore_field() -> ShoreField:
	if _shore_field == null and not _heights.is_empty():
		_shore_field = ShoreField.new().bake(_heights, _size, world_size, height_scale,
				global_position.y, sea_level(),
				Vector2(global_position.x, global_position.z))
		print("shore field: %d x %d texels, %.2f m apart, baked in %d ms" % [int(_shore_field.rect.w),
				int(_shore_field.rect.w), _shore_field.rect.z, _shore_field.bake_msec])
	return _shore_field


## Hands the shore field to a material that includes world/shore_field.gdshaderinc.
func apply_shore_field(target: ShaderMaterial) -> void:
	var field := shore_field()
	if field == null or target == null:
		return
	target.set_shader_parameter("shore_field", field.texture)
	target.set_shader_parameter("shore_field_rect", field.rect)


## World-space height under a point, for dropping things onto the ground.
func height_at(world_x: float, world_z: float) -> float:
	var half := world_size * 0.5
	if _bed != null and (absf(world_x) > half or absf(world_z) > half):
		return _far_height(world_x, world_z)
	for rect in _stamp_rects:
		if rect.has_point(Vector2(world_x, world_z)):
			return height_exact(world_x, world_z)
	return sample_height(world_x / world_size + 0.5, world_z / world_size + 0.5)


## The ground with the stamps evaluated at the point itself, rather than baked into the height
## map's samples and read back between them. On a sample the two agree exactly, so this only
## differs from the baked ground between samples - which is where a pad's 0.5 m edge lives: read
## from the samples it was a slope a sample wide, wherever the samples happened to fall. The
## mesh, the props, the grass and the tunnels all read height_at(), so inside a stamp's reach
## they all see the same exact ground.
func height_exact(world_x: float, world_z: float) -> float:
	var base := global_position.y
	var height := _bilinear(_base_heights, world_x / world_size + 0.5, world_z / world_size + 0.5) \
			* height_scale + base
	for stamp in _active_stamps:
		if stamp.is_inside_tree():
			height = stamp.reshape(height, world_x, world_z)
	return height - base



## Builds the whole ground from scratch: every chunk.
func _build_ground() -> void:
	_setup_material()
	# After a script reload in the editor the old Ground node is still there and this script
	# has forgotten it, so it is found by name rather than by the variable.
	var old := get_node_or_null(^"Ground")
	if old != null:
		remove_child(old)
		old.queue_free()
	_ground = Node3D.new()
	_ground.name = "Ground"
	add_child(_ground)
	_built_quads = maxi(chunk_quads, 1)
	_built_resolution = mesh_resolution
	_chunks_per_side = ceili(float(_built_resolution) / _built_quads)
	var count := _chunks_per_side * _chunks_per_side
	_chunks = []
	_rim_by_chunk = []
	_nan_by_chunk = []
	for index in count:
		_chunks.append(null)
		_rim_by_chunk.append(PackedVector3Array())
		_nan_by_chunk.append(PackedInt32Array())
	for index in count:
		_build_chunk(index)
	_build_far_mesh()
	_forget_edits()


## One chunk of the ground mesh, replacing whatever that chunk had.
##
## Most cells are two triangles straight from the corner cache. A cell that a tunnel opening
## crosses is clipped to the opening. A cell that a soft stamp's outline crosses - the crest of
## a pad, or the foot of its fade - is split along that line first, with the new vertices at
## the exact height the stamp puts there, so the crest is a real mesh edge at any angle rather
## than whatever the nearest corners happened to sample. Those cells, and the ring of cells
## round them, go to the rim collider in place of the height field's own triangles, so what is
## walked on is what is drawn.
func _build_chunk(index: int) -> void:
	var cx := index % _chunks_per_side
	var cz := index / _chunks_per_side
	var step := world_size / _built_resolution
	var half := world_size * 0.5
	var x0 := cx * _built_quads
	var z0 := cz * _built_quads
	var qx := mini(_built_quads, _built_resolution - x0)
	var qz := mini(_built_quads, _built_resolution - z0)

	# The soft stamps whose outline could cross this chunk, and their outline distance at every
	# corner - one cell out on every side, so the cells just beyond the chunk can be told apart
	# too: a cut cell there knocks out a height-field sample this chunk's cells also stand on.
	var chunk_rect := Rect2((x0 - 1) * step - half, (z0 - 1) * step - half, (qx + 2) * step, (qz + 2) * step)
	var pads: Array[TerrainStamp] = []
	for stamp in _active_stamps:
		if cut_edges and stamp.has_outline() and stamp.footprint().grow(step).intersects(chunk_rect):
			pads.append(stamp)
	# The corners one cell out on every side, and every pad's cut lines at each of them.
	var ext := qx + 3
	var ext_points := PackedVector2Array()
	ext_points.resize(ext * (qz + 3))
	for j in range(-1, qz + 2):
		for i in range(-1, qx + 2):
			ext_points[(j + 1) * ext + (i + 1)] = Vector2((x0 + i) * step - half, (z0 + j) * step - half)
	# Which cells, one out on every side, each line crosses, as that line's bit (CUT_CREST,
	# CUT_FOOT, CUT_RIDGE), per pad in order so the splits happen in child order. A line
	# crosses a cell when it has a corner on each side - the same test both cells sharing an
	# edge make, so a vertex on a chunk border always has its partner on the other side; "on
	# the line" counts as the near side, so that a side running exactly along a cell edge is
	# cut off at its corner by the cell beyond too. A line can also dip into a cell's edge and
	# out again without reaching a corner; near the line the edges are looked at along their
	# length as well. A ridge counts only where the bank is: the line runs on across the flat
	# top and out past the foot corner, where there is nothing to cut.
	var cells := qx + 2
	var cut := PackedByteArray()
	cut.resize(cells * (qz + 2))
	var cut_by: Array[PackedByteArray] = []
	var pad_lines: Array = []
	var pad_values: Array = []
	for pad in pads:
		var lines := pad.cut_lines()
		var values := pad.cut_line_values(ext_points)
		var foot: float = pad.edge_softness
		var mine := PackedByteArray()
		mine.resize(cells * (qz + 2))
		for l in lines.size():
			var bit: int = lines[l].bit
			var v: PackedFloat32Array = values[l]
			for j in range(-1, qz + 1):
				for i in range(-1, qx + 1):
					var e := (j + 1) * ext + (i + 1)
					var low := minf(minf(v[e], v[e + 1]), minf(v[e + ext], v[e + ext + 1]))
					var high := maxf(maxf(v[e], v[e + 1]), maxf(v[e + ext], v[e + ext + 1]))
					var crosses := low <= 0.0 and high > 0.0
					if not crosses and low > 0.0 and low < step * 1.5:
						crosses = _cell_edge_dips(lines[l], x0 + i, z0 + j, step, half)
					if crosses and bit == TerrainStamp.CUT_RIDGE:
						crosses = false
						for c in [e, e + 1, e + ext, e + ext + 1]:
							if values[0][c] >= -step and values[0][c] <= foot + step:
								crosses = true
								break
					if crosses:
						var cell := (j + 1) * cells + (i + 1)
						mine[cell] = mine[cell] | bit
						cut[cell] = 1
		cut_by.append(mine)
		pad_lines.append(lines)
		pad_values.append(values)

	# Every corner worked out once. A corner is shared by four quads and, with every triangle
	# carrying its own vertices, was worked out six times over when each quad did its own -
	# the normal alone reads the height map four times. A corner's normal is read over a
	# height sample each way, except near a pad's crest or foot, where it is read over no more
	# than the distance to the line: a 0.6 m step across a 0.5 m bank averaged the top, the
	# wall and the ground, and the wall was lit in wedges wherever a corner fell inside it.
	var stride := qx + 1
	var corners := stride * (qz + 1)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var fields := PackedFloat32Array()
	points.resize(corners)
	normals.resize(corners)
	colours.resize(corners)
	fields.resize(corners)
	for j in qz + 1:
		var wz := (z0 + j) * step - half
		for i in qx + 1:
			var wx := (x0 + i) * step - half
			var k := j * stride + i
			var p := _surface_point(wx, wz)
			points[k] = p
			var reach := INF
			for n in pads.size():
				var e := (j + 1) * ext + (i + 1)
				reach = minf(reach, minf(absf(pad_values[n][0][e]), absf(pad_values[n][1][e])))
			normals[k] = _surface_normal(wx, wz, reach)
			colours[k] = _terrain_colour(p.y)
			fields[k] = hole_field(wx, wz)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := PackedVector3Array()
	var knocked_out := PackedInt32Array()
	var samples_per_row := _built_resolution + 1
	for j in qz:
		for i in qx:
			var k := j * stride + i
			# the quad's corners in the order (x, z), (x + 1, z), (x + 1, z + 1), (x, z + 1)
			var corner := PackedInt32Array([k, k + 1, k + stride + 1, k + stride])
			var inside := 0
			for c in corner:
				if fields[c] < 0.0:
					inside += 1
			if inside == 4:
				continue                      # entirely inside a hole: no geometry at all
			var is_cut := cut[(j + 1) * cells + (i + 1)] == 1
			var near_cut := false
			for dj in range(-1, 2):
				for di in range(-1, 2):
					near_cut = near_cut or cut[(j + 1 + dj) * cells + (i + 1 + di)] == 1
			if inside == 0 and not is_cut:
				# two triangles, fanned from the first corner, straight from the cache
				var fan := [corner[0], corner[1], corner[2], corner[0], corner[2], corner[3]]
				for c in fan:
					var p := points[c]
					st.set_uv(Vector2(p.x / world_size + 0.5, p.z / world_size + 0.5))
					st.set_color(colours[c])
					# Every cell emits its own triangle vertices, so generated face normals would
					# expose the regular diagonal grid as dark wedges on steep coasts. The same
					# height field is sampled on both sides instead, giving duplicate vertices one
					# continuous terrain normal while preserving the actual height-map silhouette.
					st.set_normal(normals[c])
					st.add_vertex(p)
				if near_cut:
					# next to a cut cell: the height field loses this cell's triangles with the
					# knocked-out sample they share, so the rim carries them instead
					for c in fan:
						rim.append(points[c])
				continue

			var quad: Array[Vector3] = [points[corner[0]], points[corner[1]],
					points[corner[2]], points[corner[3]]]
			var pieces: Array = [quad]
			if is_cut:
				# split along each pad's lines in turn - crest, foot, ridge - in child order
				for p in pads.size():
					var flags := cut_by[p][(j + 1) * cells + (i + 1)]
					for line in pad_lines[p]:
						var bit: int = line.bit
						if flags & bit == 0:
							continue
						if bit == TerrainStamp.CUT_RIDGE:
							pieces = _split_band(pieces, pads[p], line)
						else:
							pieces = _split_by(pieces, line)
				for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
					knocked_out.append((z0 + j + offset.y) * samples_per_row + x0 + i + offset.x)
			if inside > 0:
				var clipped: Array = []
				for piece in pieces:
					var kept: Array[Vector3] = _clip_to_hole_edge(piece)
					if kept.size() >= 3:
						clipped.append(kept)
				pieces = clipped
			# The corners keep the cached normal, so the piece shades on from its neighbours; a
			# vertex the cut put on a line takes the normal of the ground just its own side of
			# the line, so a crest is a crease and not a smear.
			var corner_normals := {}
			for c in corner:
				corner_normals[points[c]] = normals[c]
			for piece in pieces:
				var centroid := Vector3.ZERO
				for p in piece:
					centroid += p
				centroid /= piece.size()
				var triangles: Array = []
				if is_cut:
					# Fanned from a vertex at the piece's centre, on the exact ground. Fanned from a
					# corner, a bank piece got long triangles from one foot vertex to two crest
					# vertices, and where the ground climbs along the bank that one foot vertex
					# stood in for it: 0.7 m out at mid-bank on a steep hillside.
					var centre := _surface_point(centroid.x, centroid.z)
					for t in piece.size():
						triangles.append([centre, piece[t], piece[(t + 1) % piece.size()]])
				else:
					# fan-triangulate: clipped shapes become 3-5 triangles
					for t in range(1, piece.size() - 1):
						triangles.append([piece[0], piece[t], piece[t + 1]])
				for tri in triangles:
					for p: Vector3 in tri:
						st.set_uv(Vector2(p.x / world_size + 0.5, p.z / world_size + 0.5))
						st.set_color(_terrain_colour(p.y))
						st.set_normal(corner_normals.get(p, _side_normal(p, centroid, pads)))
						st.add_vertex(p)
					rim.append_array(tri)      # keep the cut geometry for the precise collider
	_rim_by_chunk[index] = rim
	_nan_by_chunk[index] = knocked_out

	var instance := _chunks[index]
	if instance == null:
		instance = MeshInstance3D.new()
		instance.name = "Chunk_%d_%d" % [cx, cz]
		instance.material_override = material
		_ground.add_child(instance)
		_chunks[index] = instance
	# Indexed: every corner is shared by up to six triangles, and they are given the same
	# position, normal and colour, so the duplicates merge and the mesh takes a sixth of the
	# memory it did with a vertex per triangle corner.
	st.index()
	instance.mesh = st.commit()


## Whether a cut line dips into one of the cell's four edges between its two ends, both of
## which are outside it: the line's own probe says where along an edge to look.
func _cell_edge_dips(line: Dictionary, cell_x: int, cell_z: int, step: float, half: float) -> bool:
	var field: Callable = line.field
	var probe: Callable = line.probe
	var corners: Array[Vector3] = []
	for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
		corners.append(Vector3((cell_x + offset.x) * step - half, 0.0, (cell_z + offset.y) * step - half))
	for k in 4:
		# the same way round whichever cell is asking - see _canonical_lerp
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		if b.x < a.x or (b.x == a.x and b.z < a.z):
			a = corners[(k + 1) % 4]
			b = corners[k]
		for t in probe.call(a, b):
			var p: Vector3 = a.lerp(b, t)
			if field.call(p.x, p.z) <= 0.0:
				return true
	return false


## Splits along a ridge line only the pieces that lie in the pad's bank, between its crest and
## its foot - where a rectangle's corner ridge is a real crease. Elsewhere the same line runs
## across the flat top and out past the foot corner, where there is nothing to cut, and cutting
## there put vertices on chunk borders that the chunk across the border did not have.
func _split_band(pieces: Array, pad: TerrainStamp, line: Dictionary) -> Array:
	var result: Array = []
	var foot: float = pad.edge_softness
	for piece in pieces:
		var in_band := true
		for p in piece:
			var d: float = pad.edge_distance(p.x, p.z)
			if d < -0.001 or d > foot + 0.001:
				in_band = false
				break
		if in_band:
			result.append_array(_split_by([piece], line))
		else:
			result.append(piece)
	return result


## Splits every piece along a cut line (see TerrainStamp.cut_lines): into the part at or below
## 0 of its field and the part above, each with the crossings as vertices. Pieces the line
## misses come back as they are. Everything here is worked out the same way round whichever
## chunk is doing it, so the two chunks either side of a border make the same vertices on it.
func _split_by(pieces: Array, line: Dictionary) -> Array:
	var field: Callable = line.field
	var probe: Callable = line.probe
	var result: Array = []
	for piece in pieces:
		var values := PackedFloat32Array()
		var lowest := INF
		var highest := -INF
		for p in piece:
			var d: float = field.call(p.x, p.z)
			values.append(d)
			lowest = minf(lowest, d)
			highest = maxf(highest, d)
		if highest <= 0.0:
			result.append(piece)      # every vertex inside, and the inside is convex
			continue
		# The line can dip into an edge and out again between two ends both outside it; the
		# deepest point of the dip is made a vertex, so the edge is walked in two halves.
		var outline: Array[Vector3] = []
		var outline_values := PackedFloat32Array()
		var count: int = piece.size()
		var dipped := false
		for i in count:
			var current: Vector3 = piece[i]
			var next: Vector3 = piece[(i + 1) % count]
			outline.append(current)
			outline_values.append(values[i])
			if values[i] > 0.0 and values[(i + 1) % count] > 0.0:
				var a := current
				var b := next
				if b.x < a.x or (b.x == a.x and b.z < a.z):
					a = next
					b = current
				var deepest := Vector3.INF
				var d_deepest := 0.0
				for t in probe.call(a, b):
					var along: Vector3 = a.lerp(b, t)
					var d_along: float = field.call(along.x, along.z)
					if d_along <= 0.0 and absf(d_along) > absf(d_deepest):
						deepest = along
						d_deepest = d_along
				if deepest != Vector3.INF:
					outline.append(_surface_point(deepest.x, deepest.z))
					outline_values.append(d_deepest)
					dipped = true
		if lowest > 0.0 and not dipped:
			result.append(piece)      # every vertex outside, and the line never dips in
			continue
		# Sutherland-Hodgman, keeping both sides. The inside of a line is convex, so the inside
		# part is one polygon: the runs of inside vertices, each joined to the next along the
		# line from where the piece leaves it to where it comes back. The outside part can be
		# several - a corner poking in across a cell's edge leaves an outside piece either side
		# of it, and one polygon threaded through both would fan its triangles across the bank
		# - so it is one polygon per run of outside vertices, each closed along the line.
		var start := 0
		while outline_values[start] > 0.0:
			start += 1
		var below: Array[Vector3] = []
		var aboves: Array = []
		var run: Array[Vector3] = []
		var crossings := {}
		count = outline.size()
		for k in count:
			var i := (start + k) % count
			var current: Vector3 = outline[i]
			var next: Vector3 = outline[(i + 1) % count]
			var d_current := outline_values[i]
			var d_next := outline_values[(i + 1) % count]
			if d_current <= 0.0:
				below.append(current)
			else:
				run.append(current)
			if (d_current <= 0.0) != (d_next <= 0.0):
				var cut := _outline_crossing(current, next, d_current, d_next, field)
				below.append(cut)
				crossings[cut] = true
				if d_current <= 0.0:
					run = [cut]            # leaving the inside: an outside run starts here
				else:
					run.append(cut)        # back inside: the run is complete
					aboves.append(run)
					run = []
		for side in [below] + aboves:
			var polygon := _tidy(_bend_chords(side, crossings, line))
			if polygon.size() >= 3:
				result.append(polygon)
	return result


## The straight edge between two crossings stands in for the line between them, and where the
## line is not straight there that is wrong. Round a rectangle's corner it chops the corner
## off, so the corner itself is put in. Along a curve the sliver between chord and curve would
## be drawn on the wrong side, so the chord is bent onto the curve: its middle moved onto the
## line and made a vertex, and again for each half until no chord is more than a centimetre
## off the curve - a centimetre sideways on a bank that drops six metres per metre is six
## centimetres of height. Both pieces share the chord and get the same vertices, so they stay
## watertight.
func _bend_chords(polygon: Array[Vector3], crossings: Dictionary, line: Dictionary) -> Array[Vector3]:
	var bent: Array[Vector3] = []
	var count := polygon.size()
	for i in count:
		var current := polygon[i]
		var next := polygon[(i + 1) % count]
		bent.append(current)
		if not (crossings.has(current) and crossings.has(next)):
			continue
		if line.straight:
			var corner = line.corner.call(current, next)
			if corner != null:
				bent.append(_surface_point(corner.x, corner.y))
		else:
			bent.append_array(_chord_points(current, next, line.field, 3))
	return bent


## The vertices to put between a and b, both on the line, so that no chord between them is
## more than a centimetre off it: none for a straight line, up to 2^depth - 1 on a tight curve.
func _chord_points(a: Vector3, b: Vector3, field: Callable, depth: int) -> Array[Vector3]:
	var middle := _canonical_lerp(a, b, 0.5)
	var on_line := _project_to_line(middle, field)
	var sagitta := Vector2(on_line.x, on_line.z).distance_to(Vector2(middle.x, middle.z))
	if sagitta <= 0.001:
		return []
	if sagitta <= 0.01 or depth <= 1:
		return [on_line]
	var points: Array[Vector3] = _chord_points(a, on_line, field, depth - 1)
	points.append(on_line)
	points.append_array(_chord_points(on_line, b, field, depth - 1))
	return points


## The polygon without a vertex repeated next to itself: a crossing that lands on a vertex, or
## a corner reached from a crossing that already sits on it, comes in twice.
func _tidy(polygon: Array[Vector3]) -> Array[Vector3]:
	var tidy: Array[Vector3] = []
	for p in polygon:
		if tidy.is_empty() or tidy[tidy.size() - 1].distance_squared_to(p) > 0.0000000001:
			tidy.append(p)
	while tidy.size() > 1 and tidy[0].distance_squared_to(tidy[tidy.size() - 1]) <= 0.0000000001:
		tidy.pop_back()
	return tidy


## A point moved onto the line where `field` is 0, by a few Newton steps down its gradient.
func _project_to_line(from: Vector3, field: Callable) -> Vector3:
	var p := Vector2(from.x, from.z)
	for i in 4:
		var f: float = field.call(p.x, p.y)
		if absf(f) < 0.0002:
			break
		var h := 0.01
		var gradient := Vector2(field.call(p.x + h, p.y) - field.call(p.x - h, p.y),
				field.call(p.x, p.y + h) - field.call(p.x, p.y - h)) / (2.0 * h)
		if gradient.length_squared() < 0.000000001:
			break
		p -= gradient * (f / gradient.length_squared())
	return _surface_point(p.x, p.y)


## a.lerp(b, t) worked out the same way round whichever way the edge was walked. Two chunks
## share every edge on their border and walk it in opposite directions; the last bit of a
## float differs between a + (b - a) t and b + (a - b)(1 - t), and the seam check saw that as
## a crack.
func _canonical_lerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	if b.x < a.x or (b.x == a.x and b.z < a.z):
		return b.lerp(a, 1.0 - t)
	return a.lerp(b, t)


## Where the line crosses the edge from a to b: the point where its field goes from at or
## below 0 to above it. Bisection on which side each point is, from the straight guess (exact
## on a straight side), to well under a micrometre. Not on how small the field is: where a side
## runs exactly along the edge the field is 0 all the way to the corner and would have said
## "here" anywhere along it, and the vertex has to be at the corner, where the cell beyond puts
## its own. The height is the stamp's own at that point.
func _outline_crossing(a: Vector3, b: Vector3, d_a: float, d_b: float, field: Callable) -> Vector3:
	# The same way round whichever way the edge was walked - see _canonical_lerp.
	if b.x < a.x or (b.x == a.x and b.z < a.z):
		return _outline_crossing(b, a, d_b, d_a, field)
	var inside_a := d_a <= 0.0
	var low := 0.0
	var high := 1.0
	var guess := clampf(d_a / (d_a - d_b), 0.0, 1.0) if d_a != d_b else 0.5
	if guess > 0.0 and guess < 1.0:
		var g := a.lerp(b, guess)
		if (field.call(g.x, g.z) <= 0.0) == inside_a:
			low = guess
		else:
			high = guess
	for i in 22:
		var t := (low + high) * 0.5
		var p := a.lerp(b, t)
		if (field.call(p.x, p.z) <= 0.0) == inside_a:
			low = t
		else:
			high = t
	var cut := a.lerp(b, (low + high) * 0.5)
	return _surface_point(cut.x, cut.z)


## The normal of a vertex of a cut piece, read off the exact ground with a step no bigger than
## the vertex's distance to the nearest cut line, so it is never read across a crease (see
## _line_reach). A vertex on a line is read a hair's breadth to its piece's side of the line -
## straight across the line, towards the piece's centre: on a crest that gives the plateau
## piece the plateau's normal and the wall piece the wall's, where the smooth normal would
## average the two and soften the edge. (Nudged towards the centroid instead, a vertex on a
## long thin bank piece moved almost along the crest and hardly off it, and the wall was lit
## in green teeth along the lip.) In the middle of a piece on open ground it is the same
## smooth normal the corners get.
func _side_normal(p: Vector3, centroid: Vector3, pads: Array[TerrainStamp]) -> Vector3:
	var sample_step := world_size / float(maxi(_size - 1, 1))
	var reach := INF
	var across := Vector2.ZERO
	for pad in pads:
		var d: float = pad.edge_distance(p.x, p.z)
		var near := minf(absf(d), absf(d - pad.edge_softness))
		if near < reach:
			reach = near
			var e := 0.01
			across = Vector2(pad.edge_distance(p.x + e, p.z) - pad.edge_distance(p.x - e, p.z),
					pad.edge_distance(p.x, p.z + e) - pad.edge_distance(p.x, p.z - e)).normalized()
	var q := p
	var h := clampf(reach, 0.03, sample_step)
	if reach < 0.04 and across != Vector2.ZERO:
		var side := signf(across.dot(Vector2(centroid.x - p.x, centroid.z - p.z)))
		if side == 0.0:
			side = 1.0
		q = p + Vector3(across.x, 0.0, across.y) * (side * 0.04)
		h = 0.03
	return Vector3(height_at(q.x - h, q.z) - height_at(q.x + h, q.z), 2.0 * h,
			height_at(q.x, q.z - h) - height_at(q.x, q.z + h)).normalized()


## How far a point is from the nearest of the pads' crest and foot lines: how far a normal may
## be read either side of it without crossing a crease.
func _line_reach(p: Vector3, pads: Array[TerrainStamp]) -> float:
	var reach := INF
	for pad in pads:
		var d: float = pad.edge_distance(p.x, p.z)
		reach = minf(reach, minf(absf(d), absf(d - pad.edge_softness)))
	return reach


## The material, with everything the scene decides written into it. Cel shading is where the
## stylised look comes from; the vertex colours only supply which biome each point is in. See
## terrain.gdshader.
func _setup_material() -> void:
	if material == null:
		material = load("res://world/terrain_material.tres")
	material.set_shader_parameter("sea_y", sea_level())
	for entry in [["caustic_colour", caustic_colour], ["seabed_colour", seabed_colour],
			["deep_seabed_colour", deep_seabed_colour], ["seabed_weed", seabed_weed],
			["seabed_rock_colour", seabed_rock_colour], ["dry_sand_colour", dry_sand_colour],
			["damp_sand_colour", damp_sand_colour], ["wet_sand_colour", wet_sand_colour], ["grass_colour", grass_colour],
			["jungle_colour", jungle_colour], ["rock_colour", rock_colour],
			["caustic_scale", caustic_scale], ["caustic_width", caustic_width],
			["caustic_strength", caustic_strength], ["caustic_reach", caustic_reach],
			["caustic_distance_fade", caustic_distance_fade], ["caustic_speed", caustic_speed],
			["caustic_footprint_fade", caustic_footprint_fade]]:
		material.set_shader_parameter(entry[0], entry[1])
	# The shader does its own shading, so it needs to know where the sun is.
	var sun := get_node_or_null("../Sun") as DirectionalLight3D
	if sun != null:
		material.set_shader_parameter("sun_direction", sun.global_transform.basis.z.normalized())
	# Every rebuild reapplies whatever is currently painted (a fresh material after a
	# script reload has forgotten the texture, same as it has forgotten every colour above).
	set_biome_image(biome_image())
	set_biome_palette_image(biome_palette_image())
	apply_shore_field(material)


## Terrain point in world space, height sampled from the map.
func _surface_point(world_x: float, world_z: float) -> Vector3:
	return Vector3(world_x, height_at(world_x, world_z), world_z)


## Continuous height-field normal. Using the source-map sample spacing retains small coastal
## forms without allowing the render mesh's arbitrary triangle diagonal to affect shading.
## Near a pad's crest or foot the spacing shrinks to `reach`, the distance to the line, so the
## normal is never read across the crease (see _line_reach).
func _surface_normal(world_x: float, world_z: float, reach: float = INF) -> Vector3:
	var sample_step := minf(world_size / float(maxi(_size - 1, 1)), maxf(reach, 0.03))
	var left := height_at(world_x - sample_step, world_z)
	var right := height_at(world_x + sample_step, world_z)
	var back := height_at(world_x, world_z - sample_step)
	var forward := height_at(world_x, world_z + sample_step)
	return Vector3(left - right, sample_step * 2.0, back - forward).normalized()


## Clips a quad to the part outside the holes (Sutherland-Hodgman against hole_field = 0).
## This is what keeps hole rims smooth: the cut follows the circle instead of the grid,
## so the outline does not go chunky at low mesh resolution.
func _clip_to_hole_edge(polygon: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count := polygon.size()
	for i in count:
		var current: Vector3 = polygon[i]
		var next: Vector3 = polygon[(i + 1) % count]
		var f_current := hole_field(current.x, current.z)
		var f_next := hole_field(next.x, next.z)
		if f_current >= 0.0:
			result.append(current)
		if (f_current >= 0.0) != (f_next >= 0.0):
			# crossing the rim: walk to the zero of the field along this edge, the same way
			# round whichever chunk is walking it (see _canonical_lerp)
			var t: float = f_current / (f_current - f_next)
			var cut: Vector3 = _canonical_lerp(current, next, clampf(t, 0.0, 1.0))
			result.append(_surface_point(cut.x, cut.z))
	return result


## Seabed -> sand -> jungle -> rock, keyed to sea level rather than to the lowest point.
##
## Keying the bands to the map's minimum painted a snowcap on a tropical island and put the
## beach underwater. Sea level is the landmark that matters here: sand belongs just above it,
## and everything below it is seabed nobody walks on.
## The colours are sampled from the material study in the art reference (sand, leaves, rock),
## toned down a little: those spheres are rendered lit, so using their values raw as albedo
## lights them twice and the beach blows out to orange.
## Vertex colours are used as linear albedo, so the sRGB values have to be converted -
## otherwise everything comes out washed out and pale.
func _terrain_colour(height_m: float) -> Color:
	var seabed := Color(0.55, 0.52, 0.40)
	var sand := Color(0.85, 0.68, 0.45)
	var jungle := Color(0.31, 0.38, 0.24)
	var rock := Color(0.46, 0.40, 0.40)
	# Metres above the waterline, not a fraction of the height range: keyed to the fraction,
	# a beach on a 180 m island covered everything from 11 m to 34 m of elevation and a third
	# of the island came out as sand.
	var above := height_m - sea_level()
	var c: Color = seabed.lerp(sand, smoothstep(-1.5, 0.3, above))
	c = c.lerp(jungle, smoothstep(1.5, 6.0, above))
	c = c.lerp(rock, smoothstep(height_scale * 0.50, height_scale * 0.80, height_m))
	return c.srgb_to_linear()


## Collision is a hybrid: a cheap height field for the bulk of the terrain, with NaN samples
## (holes - Jolt supports these) wherever a hole is, plus a small trimesh built from the cut
## rim quads so the edges line up with what is drawn instead of with the collider's grid.
func _build_collision() -> void:
	# The previous build's shapes go first, or a second build stacks its own on top of them
	# and the old rim keeps answering rays where the new one has nothing.
	for name in [^"HeightField", ^"Rim", ^"FarHeightField"]:
		var old := get_node_or_null(name)
		if old != null:
			remove_child(old)
			old.queue_free()
	var shape := HeightMapShape3D.new()
	shape.map_width = collision_resolution
	shape.map_depth = collision_resolution
	var spacing := world_size / (collision_resolution - 1)
	var data := PackedFloat32Array()
	data.resize(collision_resolution * collision_resolution)
	for z in collision_resolution:
		for x in collision_resolution:
			var wx := x * spacing - world_size * 0.5
			var wz := z * spacing - world_size * 0.5
			var height := sample_height(float(x) / (collision_resolution - 1),
					float(z) / (collision_resolution - 1))
			# Knock out every sample inside the opening. Keeping a margin of solid samples
			# there left an invisible floor across most of the hole; the cut rim quads (the
			# trimesh below) are what covers the boundary cells.
			data[z * collision_resolution + x] = NAN if hole_field(wx, wz) < 0.0 else height
	# Where a pad's outline cuts the mesh, the height field's cells are not what is drawn: the
	# rim trimesh carries the drawn triangles there, and the samples come out so the two do not
	# both answer.
	if collision_resolution == _built_resolution + 1:
		for knocked_out in _nan_by_chunk:
			for sample in knocked_out:
				data[sample] = NAN
	shape.map_data = data
	var rim_triangles := PackedVector3Array()
	for rim in _rim_by_chunk:
		rim_triangles.append_array(rim)
	if rim_triangles.size() > 0:
		var rim := ConcavePolygonShape3D.new()
		rim.set_faces(rim_triangles)
		var rim_collider := CollisionShape3D.new()
		rim_collider.name = "Rim"
		rim_collider.shape = rim
		add_child(rim_collider)
	var owner_node := CollisionShape3D.new()
	owner_node.name = "HeightField"
	owner_node.shape = shape
	# HeightMapShape3D spans one unit per sample, so scale it out to the world size.
	owner_node.scale = Vector3(world_size / (collision_resolution - 1), 1.0,
			world_size / (collision_resolution - 1))
	add_child(owner_node)
	# The far ring's own, coarse: the square's inside is NAN, holes, and the height field above
	# answers there. Its samples ON the edge are solid, so the cells just outside it are too
	# and there is no gap to fall through between the two.
	if _far_count > 0:
		var far_shape := HeightMapShape3D.new()
		far_shape.map_width = _far_count
		far_shape.map_depth = _far_count
		far_shape.map_data = _far_heights
		var far_node := CollisionShape3D.new()
		far_node.name = "FarHeightField"
		far_node.shape = far_shape
		far_node.scale = Vector3(_far_step, 1.0, _far_step)
		add_child(far_node)
