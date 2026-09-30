@tool
class_name Ship
extends Node3D
## The double-deck hull from the canonical kit, moored off the beach.
##
## The mesh is the construction form with the kit's plank texture laid on it, not yet a
## finished model: no bevels, trim or ironwork. It is copied into art/models so the scene does
## not load out of the reference kit, and so a later styling pass can replace the file without
## touching the kit.
##
## The fittings are models cut from the Tripo sheets (art/models/ship/fittings, rigging),
## each placed in the node its placeholder used to fill. Where a model file is missing, the
## placeholder is built instead, so the ship never loses a part it needs.
##
## Axes and sizes are the kit's, in metres: X starboard, Y up, Z aft, keel at Y=0, bow at Z=0,
## stern at Z=14, beam 6. The gunport sills are at Y=2.82, so the keel sits two metres under
## the still waterline and the ports stay clear of the waves.
##
## This script runs in the editor so the mast, sail, guns and the other fittings — which are
## built in code, not saved into the scene — are visible on the hull while it is open.

const MODEL := "res://art/models/ship/double_deck.glb"
const LENGTH := 14.0
## The bulged stern's aftmost point. The hull, and the quarterdeck over it, reach past LENGTH,
## so standing on board is measured to here.
const STERN_Z := 16.7
const BEAM := 6.0
## Keel depth below still water. Gun deck is at 2.6, so this leaves it 0.6 m clear.
const DRAFT := 2.0
## Extra water under the keel, so a sloping seabed does not poke through the bilge.
const CLEARANCE := 0.6
## Top of the weather-deck slab. Measured off the mesh: feet land here.
const DECK_Y := 5.2
## How far from the hull a climb still counts. The collision stops him short of the planks.
const BOARD_MARGIN := 3.0
## Where a climb puts his feet: centreline, between the stair opening and the mainmast, a metre
## above the deck so he drops onto it instead of spawning in the slab.
const BOARD_SPOT := Vector3(0.0, DECK_Y + 1.0, 7.9)
## Front face of the stern castle (art/models/ship/cabin/stern_castle.glb, built by
## tools/build_stern_castle.py, whose FRONT_Z must match). The castle is the hull carried up
## one tier: its walls stand on the hull's outer edge from here round the stern. Its roof is
## the quarterdeck, and the cabin is under it.
const CASTLE_FRONT_Z := 10.4
## Tripo's arched window (art/models/ship/cabin/cabin_window.glb, used as delivered): 1 m tall,
## facing +Z, its back 0.105 m behind its origin. Scaled to 1.1 m.
const WINDOW_SCALE := 1.1
## The castle's windows are spread evenly along its wall, round the stern from the starboard
## front corner to the port one, the first and last this far along from those corners. An odd
## count puts one on the stern's centreline. Each faces out from the wall where it stands.
const CASTLE_WINDOW_COUNT := 5
const CASTLE_WINDOW_MARGIN := 0.8
## How high the windows' sills are above the weather deck.
const CASTLE_WINDOW_SILL := 0.9
## The trim round the castle's top: the wale's profile swept along its walls with its top just
## under the quarterdeck's edge, where the rail's base overhangs them.
const CASTLE_TRIM_Y := DECK_Y + 2.6 - 0.11
## Tripo's carved pillar (art/models/ship/cabin/cabin_pillar.glb, its texture shrunk to 1024
## px): 1 m tall, 0.199 m wide and 0.172 m deep, facing +Z, its foot at its origin and its flat
## back 0.086 m behind it. Scaled to stand from the deck line to just under the trim, where the
## bottom rim runs into its base and its capital carries the trim.
const PILLAR_SCALE := 2.35
const PILLAR_BACK := 0.086
const PILLAR_WIDTH := 0.199 * PILLAR_SCALE
const PILLAR_DEPTH := 0.172 * PILLAR_SCALE
## The front wall's two pillars stand at its corners, their outer sides this far proud of the
## castle's sides, so the bottom rim ends inside them.
const PILLAR_CORNER_PROUD := 0.02
## The weather deck's rail stops this short of the corner pillars, on a post of its own: run into
## them, it read as springing out of the pillar. Far narrower than anyone who would slip through,
## and the corner pillars collide.
const RAIL_PILLAR_GAP := 0.25
## Across the front wall the trim stops this far either side of the stairs' centre line and
## turns into the wall, clear of the stair rails (STAIR_RAIL_OUT, with their 0.24 m posts)
## by 2 cm, its return standing 0.2 m out toward them.
const CASTLE_TRIM_STAIRS := 0.96
## The quarterdeck's walking surface, the castle's roof: one kit tier (2.6 m) above the
## weather deck, which is exactly where STAIRS_260 lands.
const QUARTERDECK_Y := DECK_Y + 2.6
## Foot of the quarterdeck stairs, the kit's STAIRS_260: 1 m wide, rising aft over 3.25 m.
## Port of the centreline and starting just aft of the stair opening, so whoever comes up from
## the gun deck walks straight on; its top lands on the roof over the castle's front wall.
const QUARTERDECK_STAIRS_AT := Vector3(-1.0, DECK_Y, 7.26)
## Deck contact of the wheel, on the quarterdeck. The real F01_HELM drops in here.
const HELM_AT := Vector3(0.0, QUARTERDECK_Y, 13.2)
## Where his feet go: aft of the wheel, looking toward the bow.
const HELM_FEET := Vector3(0.0, QUARTERDECK_Y, 14.05)
const HELM_REACH := 1.6
## Deck contact of the mainmast, aft of the stair hatch and forward of the wheel.
const MAST_AT := Vector3(0.0, DECK_Y, 9.0)
## The mainmast's lower mast: the M01 model (5.5 m) stretched to this, and everything above it -
## the top, the course and topsail yards, the topmast and the flag - raised with it
## (MAIN_LIFT). The quarterdeck's stairs run up beside the mast, under the course: at 5.5 m the
## course hung across the stairway, into the head of anyone climbing it.
const MAIN_LOWER := 7.0
const MAIN_LIFT := MAIN_LOWER - 5.5
## The course: laced to its yard and sheeted home at its foot, as the reference's sails are, so
## it bellies but never swings back over the stairs or the castle. This deep, its foot is above
## the head of anyone on the stairs beside the mast, and above the quarterdeck's rail.
const COURSE_DROP := 2.6
## How the sails' feet are made fast, as in the reference: a block hangs from each course's clews
## (its foot's corners), and from it a sheet runs aft and a tack forward, down to the rail's
## handrail, where they are belayed: these far along the rail. The fore course's tack goes to
## its cathead instead, the rail ahead of it being taken by the fore shrouds' channels.
const MAIN_SHEET_Z := 9.45
const MAIN_TACK_Z := 6.8
const FORE_SHEET_Z := 3.2
## The jib's clew, its foot's after corner: free above the bow, clear of the head of anyone
## there, with a sheet from it down to each side's rail JIB_SHEET_Z along. Its tack is lashed
## to the bowsprit's tip.
const JIB_CLEW := Vector3(0.0, DECK_Y + 2.3, -0.9)
const JIB_SHEET_Z := -1.2
## Where a rope belayed to the rail meets it: the handrail's top is 0.75 m above the deck.
const HANDRAIL_TOP := 0.75
## The braces, from each course yard's arms aft to the rail, which swing the yards round to the
## wind: the main's to the quarterdeck's rail, the fore's to the waist, between the fore sheet
## and the main tack. Both run outboard of anywhere a man walks.
const MAIN_BRACE_Z := 12.4
const FORE_BRACE_Z := 5.5
## Deck contact of the foremast, on the bow deck forward of the hatch. Shorter than the main.
const FOREMAST_AT := Vector3(0.0, DECK_Y, 1.5)
## The foremast is built as the mainmast is (_square_mast) - lower mast, top, topmast, course and
## topsail yards and their blocks - at this scale, as the reference's foremast is a smaller
## copy of its main. Its course is sheeted home FORE_COURSE_DROP below its yard, above the head of
## anyone on the foredeck; its topsail is laced between its topsail yard and topsail foot yard;
## the jib's head is at its course yard.
const FORE_SCALE := 0.85
const FORE_COURSE_DROP := 2.6
## Heel of the bowsprit, resting on the deck just inboard of the stem. The spar's own length
## runs forward from here, over the stem head between the two knightheads the rail ends on. A
## real F03_BOWSPRIT drops in on this node; its heel is 0.3 m across.
const BOWSPRIT_AT := Vector3(0.0, DECK_Y + 0.15, -1.9)
## The bowsprit: the M07 model (3 m) lengthened to 5.2 m, reaching well out past the stem for
## the taller foremast's jib, and thickened by a tenth: about as thick as it can be and still
## pass between the knightheads, whose posts' inner faces are 0.37 m apart.
const BOWSPRIT_LENGTH := 5.2
const BOWSPRIT_GIRTH := 1.1
## The bowsprit rises this far above the horizontal as it goes forward.
const BOWSPRIT_RISE := 13.0
## Hinge of the rudder, on the stern under the counter. The blade hangs aft of this
## point. A real F04_RUDDER drops in on this node.
const RUDDER_AT := Vector3(0.0, 1.8, 14.9)
## Gun deck the ports look out of. The guns stand on it, on their wheels.
const GUN_DECK_Y := 2.6
## The straight run of the hull's side the gun deck's walls are built along, both sides, with a
## hole wherever a port is (tools/strip_game_gunports.py takes the kit's walls out). Ports are
## spread evenly along it, the first and last GUN_PORT_MARGIN in from its ends: with four, that
## puts them where the kit's bays did, at 5, 7, 9 and 11.
const GUN_WALL_FORE_Z := 4.0
const GUN_WALL_AFT_Z := 12.0
const GUN_WALL_INNER_X := 2.8
const GUN_PORT_MARGIN := 1.0
## The opening, the kit's: 1 m wide and 0.8 m tall.
const GUN_PORT_SIZE := Vector2(1.0, 0.8)
## Centre of each port's opening: level with the barrel of a gun standing on the deck, whose
## axis is 0.62 m up at its resting elevation. The 0.8 m opening then runs from 0.22 m to
## 1.02 m off the deck, room for the muzzle to rise to its full 14 degrees. (The kit's sill was
## 0.8 m up, which left the guns hanging in the air to reach it.)
const GUN_PORT_Y := GUN_DECK_Y + 0.62
## Deck contact of the capstan, on the gun deck under the cabin: the weather deck there is
## the cabin's floor now. Clear of the guns and under the beams; a real F02_CAPSTAN drops in
## on this node.
const CAPSTAN_AT := Vector3(0.0, GUN_DECK_Y, 10.8)
## Ahead of the wheel on the quarterdeck, where the helmsman can read it.
const BINNACLE_AT := Vector3(0.0, QUARTERDECK_Y, 12.15)
## On the aft face of the quarterdeck rail's stern post, on the centreline: the model's origin
## is the top of its wall plate, and the lantern hangs aft of it, out over the stern.
const LANTERN_AT := Vector3(0.0, QUARTERDECK_Y + 0.9, 16.34)
## How far each gun stands out from the ship's centreline: its carriage 5 cm short of the gun
## deck's wall, so its muzzle is run out through the port and clear of the frame, as in the
## reference. The barrel is 2 m long and the carriage 1.2 m; further in, the muzzle hid inside
## the port frame.
const GUN_OUT_X := 2.43
## Where the bow's catheads sit: the origin is the top of the timber's inboard end, 25 degrees
## forward of square. That lands the supporter's foot, 1.0 m out and 1.35 m down in the model,
## on the hull side at z=1.0, and passes the timber through the bulwark at rail height.
const CATHEAD_AT := Vector3(1.33, 6.0, 1.4)
const CATHEAD_YAW := 25.0
## The end of the cathead's fall, in its own space, where the anchor's ring hangs.
const CATHEAD_FALL := Vector3(1.44, -1.22, 0.0)
## Under the weather deck, between the gun ports, spanning the 5.6 m inside the hull. None
## over the stair shaft (z 4 to 7.25): a beam there would meet the head of anyone on the stairs.
const DECK_BEAM_Z := [8.0, 10.0, 12.0]
## Deck fittings with no role in play: [node, model, position, yaw, collides]. The position's
## Y is the deck it stands on. Laid out clear of the masts, the cabin and its stairs, the helm,
## the binnacle, the boarding spot and the stair opening (x -0.55 to 0.55, z 4 to 7.25). Cleats
## and racks sit against the bulwark's inner face, 2.8 m out; the bow narrows, so its fittings
## stay near the centreline.
const DECK_PROPS := [
	["Bitts", "fittings/bollard.glb", Vector3(0.0, DECK_Y, 2.8), 0.0, true],
	["AnchorCable", "fittings/anchor_cable.glb", Vector3(1.55, DECK_Y, 3.15), 0.0, true],
	["BowCoil", "rigging/rope_coil.glb", Vector3(-1.55, DECK_Y, 3.15), 0.0, true],
	["Hatch", "deck/hatch_coaming.glb", Vector3(1.55, DECK_Y, 5.4), 0.0, true],
	["CleatStarboardFore", "fittings/cleat.glb", Vector3(2.68, DECK_Y, 6.5), 90.0, false],
	["CleatPortFore", "fittings/cleat.glb", Vector3(-2.68, DECK_Y, 6.5), 90.0, false],
	["RackStarboard", "fittings/belaying_rack.glb", Vector3(2.68, DECK_Y, 9.0), 90.0, false],
	["RackPort", "fittings/belaying_rack.glb", Vector3(-2.68, DECK_Y, 9.0), 90.0, false],
	["CoilStarboard", "rigging/rope_coil.glb", Vector3(1.55, DECK_Y, 9.7), 0.0, true],
	["CoilQuarterdeck", "rigging/rope_coil.glb", Vector3(0.9, QUARTERDECK_Y, 11.1), 0.0, true],
	["CleatStarboardAft", "fittings/cleat.glb", Vector3(2.68, QUARTERDECK_Y, 12.5), 90.0, false],
	["CleatPortAft", "fittings/cleat.glb", Vector3(-2.68, QUARTERDECK_Y, 12.5), 90.0, false],
]
## The rail round the weather deck, which stands where the solid bulwark was (see
## tools/strip_game_bulwarks.py). The hull's wall now ends at the deck in a flat top 0.2 m
## wide; this is the centre line of that top, measured off double_deck.glb, as (x, z), at
## each corner of the hull's panels. It runs down the starboard side from the knighthead at
## the bow, round the stern to the centreline; the port side is its mirror. The knightheads
## stand either side of the bowsprit, 0.34 m out, so the spar passes between them. On the
## weather deck the rail runs only as far as the stern castle; aft of that the same line,
## up on the castle's wall top, carries the quarterdeck's rail (see _rail_legs).
const RAIL_PATH := [
	Vector2(0.34, -2.065), Vector2(1.132, -0.935), Vector2(2.115, 0.745), Vector2(2.9, 4.0),
	Vector2(2.9, 12.0), Vector2(2.845, 12.72), Vector2(2.68, 13.45), Vector2(2.41, 14.165),
	Vector2(2.05, 14.825), Vector2(1.615, 15.39), Vector2(1.11, 15.82), Vector2(0.57, 16.085),
	Vector2(0.0, 16.18),
]
## The bow's sheer, as in the reference, where the hull's side sweeps up to the stem: from
## BOW_SHEER_FROM, just forward of the catheads, the side rises along a curve that starts level,
## BOW_SHEER at the knightheads. A planked bulwark (_build_bow_bulwark) fills it on the hull's
## wall top, and the rail stands on it; the fore shrouds' channels and everything belayed to the
## rail rise with it (bow_sheer).
const BOW_SHEER_FROM := 1.0
const BOW_SHEER := 0.6
## Posts stand evenly along the whole rail, bow to stern, no more than this apart. They do not
## follow the hull's corners: the stern is eight short panels, and a post on each would crowd
## it. The handrail and base are swept through the posts and round the corners unbroken.
const RAIL_SPAN := 2.0
## The stair rails stand this far out from the stairs' centre line: 0.1 m outside each edge,
## so the whole 1 m of tread is clear for the captain, who is 0.7 m across. Each has a post at
## the foot and one at the head, with balusters all the way between.
const STAIR_RAIL_OUT := 0.6
## A turn sharper than this, in degrees, gets a post on it: the quarterdeck's front corners,
## and the top of each stair rail.
## The hull's own corners turn 16 degrees at most, and the rail laps round them.
const RAIL_CORNER := 30.0
## Balusters stand about this far apart, as on Tripo's straight rail.
const BALUSTER_PITCH := 0.45
## Height of the rail's collision: the handrail's top.
const RAIL_HEIGHT := 0.81
## The wale: the thick strake round the hull, swept from Tripo's wale (rail_sweep.glb, see
## tools/rail_profiles.py) along the hull's outer face at WALE_Y, between the gunport frames
## and the weather deck, above the port frames. Each side's outline is measured off
## double_deck.glb on its own, as (x, z) from the stem round to the stern's centreline, with the
## gun deck's rebuilt walls at x = 3: the kit's bow is not quite symmetrical, and a mirrored
## outline stood 2 cm off the port bow. The wale closes round both ends.
const WALE_Y := 4.4
const WALE_STARBOARD := [
	Vector2(0.0, -2.347), Vector2(0.294, -1.933), Vector2(1.164, -0.792), Vector2(1.22, -0.71),
	Vector2(1.417, -0.376), Vector2(2.193, 0.846), Vector2(2.36, 1.528), Vector2(3.0, 4.0),
	Vector2(3.0, 12.0), Vector2(2.945, 12.674), Vector2(2.901, 12.887), Vector2(2.775, 13.414),
	Vector2(2.722, 13.564), Vector2(2.503, 14.12), Vector2(2.377, 14.356), Vector2(2.141, 14.766),
	Vector2(2.087, 14.847), Vector2(1.711, 15.312), Vector2(1.641, 15.389), Vector2(1.164, 15.787),
	Vector2(1.075, 15.838), Vector2(0.607, 16.063), Vector2(0.507, 16.087), Vector2(0.0, 16.167),
]
const WALE_PORT := [
	Vector2(0.0, -2.347), Vector2(-0.919, -1.14), Vector2(-1.165, -0.794), Vector2(-1.996, 0.508),
	Vector2(-2.194, 0.846), Vector2(-2.754, 2.996), Vector2(-3.0, 4.0), Vector2(-3.0, 12.0),
	Vector2(-2.945, 12.674), Vector2(-2.775, 13.413), Vector2(-2.503, 14.12), Vector2(-2.141, 14.765),
	Vector2(-2.086, 14.845), Vector2(-1.641, 15.388), Vector2(-1.164, 15.786), Vector2(-1.075, 15.835),
	Vector2(-0.607, 16.062), Vector2(-0.507, 16.086), Vector2(0.0, 16.167),
]
## The shrouds and backstays are set up as a ship's are. Each rope ends in an upper deadeye, a
## lanyard DEADEYE_LANYARD long joins that to a lower deadeye, and the lower deadeye stands on
## the outer edge of a channel: a plank CHANNEL_OUT wide along the outside of the rail, its
## underside just above the rail's top, so the deadeyes and the rope above them are all clear
## of the rail. (At the deck, the ropes lean in so far toward their masts that they would pass
## through the open rail unless the channel stood out most of a metre.) An iron chain plate
## holds each lower deadeye down to the hull's side: to just above the wale, or on the castle to
## the top of its trim. The deadeye model hangs 0.35 m from its strop and is 0.2 m across.
const CHANNEL_OUT := 0.3
const CHANNEL_THICK := 0.1
const DEADEYE_LANYARD := 0.25
## How far forward of the foremast its shrouds' feet stand. Forward, as the main's are, clear of
## the fore sails, which hang aft of the mast; and forward of the catheads and the anchors under
## them.
const FORE_SHROUD_FEET := [-2.1, -1.75, -1.4]
## Where each backstay's foot stands along the castle's side: on the wall panel nearest this z,
## at the stern quarter, well aft of the mast it holds.
const BACKSTAY_Z := 13.9
## A single block under each end of both yards, where the braces and sheets would be led.
## Mast-local: [yard's height, how far out, how far aft]. The block's origin is its strop.
const YARD_BLOCKS := [[4.47 + MAIN_LIFT, 3.8, 0.0], [8.07 + MAIN_LIFT, 2.45, 0.12]]
## The flag's staff stands on the topmast head (MAIN_LOWER + 3 m up the mast) and its flag flies from the
## staff's top, above the topsail yard and the backstays' heads. The staff runs through the
## flag's three rings, whose holes are 13 mm round: FLAGSTAFF_RADIUS fits through them.
const FLAGSTAFF_HEIGHT := 1.05
const FLAGSTAFF_RADIUS := 0.011
## The mast top's platform floor stands 1.06 m above the model's lowest point; this puts that
## floor just above the placeholder's, and the model's collar clear of the course yard 0.12 below.
const MAST_TOP_Y := 4.72 + MAIN_LIFT

const FITTINGS := "res://art/models/ship/fittings/"
const RIGGING := "res://art/models/ship/rigging/"
const HULL_PARTS := "res://art/models/ship/hull/"
const DECK_PARTS := "res://art/models/ship/deck/"
const CABIN_PARTS := "res://art/models/ship/cabin/"
const CannonScene := preload("res://props/cannon/cannon.tscn")
const SailScript := preload("res://props/ship/sail.gd")
const AHEAD_SPEED := 7.0
const ASTERN_SPEED := 3.5
const YAW_RATE := 0.45
## Keel to the top of the rail. The fraction of this under the surface is the buoyancy.
const HULL_HEIGHT := 6.0
## How hard a difference in submersion heels the hull, in radians per second squared.
const PITCH_RESPONSE := 6.0
const ROLL_RESPONSE := 8.0
const MAX_HEEL := 0.14

## The ocean, so the lift is taken from the waves rather than the flat sea level. Same sampler
## the barrels use. Without it the hull sits on the average.
## How far the stern castle's windows stand off its wall, in metres along each one's normal:
## positive out, negative into the wall. At 0 each window's back is on the middle of its wall
## panel; where the wall bends away under its edges, a small push in closes the gap there.
## Tune it in the inspector: the windows move as it changes.
@export_range(-0.1, 0.1, 0.001, "suffix:m") var window_offset := 0.0:
	set(value):
		window_offset = value
		var quarterdeck := get_node_or_null("Quarterdeck") as Node3D
		if quarterdeck != null and quarterdeck.get_node_or_null("Cabin") != null:
			var old := quarterdeck.get_node_or_null("Windows")
			if old != null:
				# Out of the way now, gone at the end of the frame.
				old.name = "WindowsOld"
				quarterdeck.remove_child(old)
				old.queue_free()
			_build_windows(quarterdeck, quarterdeck.get_node("Cabin") as Node3D)

## How far the castle's pillars stand off its wall, like window_offset. Tune it in the inspector.
@export_range(-0.1, 0.1, 0.001, "suffix:m") var pillar_offset := 0.0:
	set(value):
		pillar_offset = value
		var quarterdeck := get_node_or_null("Quarterdeck") as Node3D
		if quarterdeck != null and quarterdeck.get_node_or_null("Cabin") != null:
			var old := quarterdeck.get_node_or_null("Pillars")
			if old != null:
				old.name = "PillarsOld"
				quarterdeck.remove_child(old)
				old.queue_free()
			_build_pillars(quarterdeck, quarterdeck.get_node("Cabin") as Node3D)

## Gunports a side. Changing it moves the holes, the frames and the guns together.
@export_range(1, 6) var gun_port_count := 4:
	set(value):
		gun_port_count = value
		_rebuild_gun_ports()
## How far the gunport frames stand off the hull's side, in metres along its normal: positive
## out, negative into the wall. Tune it in the inspector.
@export_range(-0.1, 0.1, 0.001, "suffix:m") var gun_port_offset := 0.0:
	set(value):
		gun_port_offset = value
		_rebuild_gun_ports()

var ocean: Node3D
## Whoever is standing on deck. The hull moves, and a character body is not carried along by a
## static floor that teleports, so he is moved with it while his feet are over the deck.
var rider: Node3D

var _terrain: Node
var _sea := 0.0
## Bow origin in the horizontal, and which way aft points. Heave and heel are separate so
## steering never flattens the float.
var _planar := Vector3.ZERO
var _heading := 0.0
## Height of the keel at midships, and how fast it is rising.
var _keel_y := 0.0
var _rise := 0.0
var _pitch := 0.0
var _pitch_rate := 0.0
var _roll := 0.0
var _roll_rate := 0.0


func _ready() -> void:
	_build()
	_build_quarterdeck()
	_build_helm()
	_build_mast()
	_build_shrouds()
	_build_foremast()
	_build_bowsprit()
	_build_bobstay()
	_build_rudder()
	_build_capstan()
	_build_gun_ports()
	_build_sail()
	_build_topsail()
	_build_backstays()
	_build_sheets()
	_build_stays()
	_build_braces()
	_build_flag()
	_build_deck_fittings()
	_build_rail()
	_build_bow_bulwark()
	_build_wale()


## Floats broadside to the beach the coastal study picked, close enough to swim to.
## The study's +Z points inland, so seaward is -Z and the beach runs along X.
func moor_off(beach: Node3D, terrain: Node) -> bool:
	var sea: float = terrain.sea_level()
	var inland: Vector3 = beach.global_basis.z
	inland.y = 0.0
	if inland.length_squared() < 0.01:
		return false
	inland = inland.normalized()
	var along := Vector3.UP.cross(inland).normalized()
	# Broadside first: the ports read, and the hull stays clear of the rocks in the shallows.
	# Bow-out is the fallback where the bay is too narrow for fourteen metres of length.
	var headings: Array[Vector3] = [along, -along, inland]
	for aft in headings:
		for distance in range(36, 140, 4):
			for lateral in [0, 16, -16, 32, -32]:
				var centre := beach.global_position - inland * float(distance) + along * float(lateral)
				var origin := centre - aft * (LENGTH * 0.5)
				origin.y = sea - DRAFT
				if _afloat(origin, aft, terrain, sea):
					_planar = origin
					_heading = atan2(aft.x, aft.z)
					_keel_y = sea - DRAFT
					_terrain = terrain
					_sea = sea
					_apply_pose()
					print("ship moored at ", global_position, " draft ", DRAFT)
					return true
	push_warning("ship: no water deep enough off this beach")
	return false


## True when `who` is beside the hull and not already standing on it.
## The deck is the only way up, and there is no ladder, so this is the whole climb.
func can_board(who: Node3D) -> bool:
	var local := to_local(who.global_position)
	if _on_deck(local):
		return false
	return _hull_distance(local) <= BOARD_MARGIN


## True when he is up on the quarterdeck and within reach of the wheel. The height matters:
## the cabin under the wheel is closed, but the gangway beside it is on the weather deck.
func can_helm(who: Node3D) -> bool:
	var local := to_local(who.global_position)
	if not _on_deck(local) or local.y < HELM_AT.y - 0.6:
		return false
	return Vector2(local.x - HELM_AT.x, local.z - HELM_AT.z).length() <= HELM_REACH


func helm_feet() -> Vector3:
	return to_global(HELM_FEET)


## Bow, flat. The wheel faces this way.
func helm_facing() -> Vector3:
	var bow := -global_basis.z
	bow.y = 0.0
	return bow.normalized() if bow.length_squared() > 0.0001 else Vector3.FORWARD


## `throttle` is +1 ahead. `yaw` is +1 to starboard. Only the heading and the
## horizontal move: the draft is the buoyancy's, and writing it here pinned the hull to a
## flat sea while the waves went past it.
func drive(delta: float, throttle: float, yaw: float) -> void:
	if _terrain == null:
		return
	throttle = clampf(throttle, -1.0, 1.0)
	yaw = clampf(yaw, -1.0, 1.0)
	if absf(yaw) > 0.01:
		# Positive yaw is starboard, so the bow swings to +X.
		_heading -= yaw * YAW_RATE * delta
	var aft := _aft()
	if absf(throttle) > 0.01:
		var rate := AHEAD_SPEED if throttle > 0.0 else ASTERN_SPEED
		var candidate := _planar - aft * throttle * rate * delta
		candidate.y = _sea - DRAFT
		# A grounded move is refused. Turning still happened, so he can aim back at water.
		if _afloat(candidate, aft, _terrain, _sea):
			_planar.x = candidate.x
			_planar.z = candidate.z
	_apply_pose()


func _physics_process(delta: float) -> void:
	# The fittings are built in the editor so the mast and guns are visible there. The float
	# is not: running it would walk the saved pose off the mooring.
	if Engine.is_editor_hint():
		return
	_fly_flag()
	if _terrain == null:
		return
	var before := global_transform
	var held := Vector3.ZERO
	var riding := false
	if rider != null:
		held = before.affine_inverse() * rider.global_position
		riding = _on_deck(held)
	_buoy(delta)
	_apply_pose()
	if riding:
		rider.global_position = global_transform * held


## Lift from how much hull is under the surface, damped so it settles on the draft instead of
## bobbing forever. The same arrangement as a barrel: too deep and the lift beats gravity, too
## shallow and it does not. Pitch and roll are that difference measured along the hull.
func _buoy(delta: float) -> void:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	# Full submersion pushes this hard, so the balance sits at the designed draft rather than
	# at half the hull. Gunports are above that line; a barrel's half-submerged balance would
	# put them under.
	var lift := gravity * HULL_HEIGHT / DRAFT
	var aft := _aft()
	var starboard := Vector3(aft.z, 0.0, -aft.x)
	var bow := Vector3(_planar.x, 0.0, _planar.z)
	var mid := bow + aft * (LENGTH * 0.5)
	var stern := bow + aft * LENGTH
	var half_len := LENGTH * 0.5
	var half_beam := BEAM * 0.5
	var bow_y := _keel_y + sin(_pitch) * half_len
	var stern_y := _keel_y - sin(_pitch) * half_len
	var port_y := _keel_y - sin(_roll) * half_beam
	var star_y := _keel_y + sin(_roll) * half_beam
	var mid_sub := _submerged(_surface(mid.x, mid.z) - _keel_y)
	var bow_sub := _submerged(_surface(bow.x, bow.z) - bow_y)
	var stern_sub := _submerged(_surface(stern.x, stern.z) - stern_y)
	var port_sub := _submerged(_surface(mid.x - starboard.x * half_beam, mid.z - starboard.z * half_beam) - port_y)
	var star_sub := _submerged(_surface(mid.x + starboard.x * half_beam, mid.z + starboard.z * half_beam) - star_y)
	# The heave is the whole waterplane's, not the water at midships. Taken from one point, the
	# hull rode the long swell's full rise and fall like a barrel, so any few seconds of it sat
	# half a metre off the draft. Heel cancels out of this mean: bow and stern, port and
	# starboard move in opposite senses about the keel at midships.
	var hull_sub := (mid_sub + bow_sub + stern_sub + port_sub + star_sub) / 5.0
	_rise += (lift * hull_sub - gravity) * delta
	# Critical damping, and not only while submerged. Scaled by the submerged fraction the
	# drag vanished the moment the keel cleared a crest, so the hull fell and then launched
	# itself back out.
	var heave_omega := sqrt(lift / HULL_HEIGHT)
	_rise *= exp(-2.0 * heave_omega * delta)
	_rise = clampf(_rise, -1.2, 1.2)
	_keel_y += _rise * delta
	_pitch_rate += PITCH_RESPONSE * (bow_sub - stern_sub) * delta
	_roll_rate += ROLL_RESPONSE * (star_sub - port_sub) * delta
	var pitch_omega := sqrt(PITCH_RESPONSE * LENGTH / HULL_HEIGHT)
	var roll_omega := sqrt(ROLL_RESPONSE * BEAM / HULL_HEIGHT)
	_pitch_rate *= exp(-2.0 * pitch_omega * delta)
	_roll_rate *= exp(-2.0 * roll_omega * delta)
	_pitch = clampf(_pitch + _pitch_rate * delta, -MAX_HEEL, MAX_HEEL)
	_roll = clampf(_roll + _roll_rate * delta, -MAX_HEEL, MAX_HEEL)
	if absf(_pitch) >= MAX_HEEL - 0.0001:
		_pitch_rate = 0.0
	if absf(_roll) >= MAX_HEEL - 0.0001:
		_roll_rate = 0.0


func _submerged(depth: float) -> float:
	return clampf(depth / HULL_HEIGHT, 0.0, 1.0)


func _surface(x: float, z: float) -> float:
	if ocean != null and ocean.has_method("surface_y"):
		return ocean.surface_y(x, z)
	return _sea


func _aft() -> Vector3:
	return Vector3(sin(_heading), 0.0, cos(_heading))


func _apply_pose() -> void:
	var bow_lift := sin(_pitch) * LENGTH * 0.5
	global_position = Vector3(_planar.x, _keel_y + bow_lift, _planar.z)
	# Yaw, then heel about the ship's own axes. Built rather than read back, so the float
	# cannot accumulate a tilt the way a decomposed basis does.
	global_basis = Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3(0.0, 0.0, 1.0), _roll)


## Drops `who` onto the weather deck. The caller has already checked can_board.
func board(who: Node3D) -> void:
	who.global_position = to_global(BOARD_SPOT)
	if who is CharacterBody3D:
		(who as CharacterBody3D).velocity = Vector3.ZERO


func _on_deck(local: Vector3) -> bool:
	return local.y > DECK_Y - 0.6 and absf(local.x) <= BEAM * 0.5 and local.z >= 0.0 and local.z <= STERN_Z


## Metres from the hull's rectangular outline. Zero when he is inside it.
func _hull_distance(local: Vector3) -> float:
	var dx := maxf(absf(local.x) - BEAM * 0.5, 0.0)
	var dz := 0.0
	if local.z < 0.0:
		dz = -local.z
	elif local.z > LENGTH:
		dz = local.z - LENGTH
	return Vector2(dx, dz).length()


func _build() -> void:
	# The mesh lives in the scene so the editor can show the hull. A missing one is filled in
	# here, and either way the surfaces still need the flat toon pass and deck collision.
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		if not ResourceLoader.exists(MODEL):
			push_warning("ship: no model at %s" % MODEL)
			return
		model = (load(MODEL) as PackedScene).instantiate()
		model.name = "Model"
		add_child(model)
	for node in _descendants(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		# Layer 20 is the ocean's overhead silhouette, same as the rocks, so the hull cuts a
		# band in the surface instead of disappearing under a flat sheet of water.
		mesh_node.layers = 1 | (1 << 19)
		if mesh_node.mesh == null:
			continue
		_toon(mesh_node)
	# The deck and the stairs are part of the mesh. A box would fill the hatch.
	_walkable(model)


## Collision that follows the meshes under `node` exactly, for anything walked on or up: a box
## would fill the hatch, the stairs' steps and the rail around the quarterdeck. Skips a mesh
## that already has one: a tool script's _ready runs again on reload, and a second body would
## stack on the first.
func _walkable(node: Node3D) -> void:
	for child in _descendants(node):
		if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null:
			continue
		var mesh_node := child as MeshInstance3D
		var blocked := false
		for grandchild in mesh_node.get_children():
			if grandchild is StaticBody3D:
				blocked = true
				break
		if not blocked:
			mesh_node.create_trimesh_collision()


## The stern castle and the stairs up to its roof, the quarterdeck. The castle's model is in
## ship space, so it stands at the origin. Its door is Tripo's door leaf, shut, on the front
## wall. The castle and the stairs collide exactly, so the captain can walk up and round the
## wheel. Where a model is missing, a plain block and a ramp of the same size stand in.
func _build_quarterdeck() -> void:
	if get_node_or_null("Quarterdeck") != null:
		return
	var quarterdeck := Node3D.new()
	quarterdeck.name = "Quarterdeck"
	add_child(quarterdeck)
	var timber := _flat(Color(0.55, 0.36, 0.18))

	var cabin := Node3D.new()
	cabin.name = "Cabin"
	quarterdeck.add_child(cabin)
	if _fit_model(cabin, CABIN_PARTS + "stern_castle.glb"):
		_walkable(cabin)
	else:
		var length := STERN_Z - 0.3 - CASTLE_FRONT_Z
		_box(cabin, Vector3(0.0, QUARTERDECK_Y - 1.3, CASTLE_FRONT_Z + length * 0.5), Vector3(5.6, 2.6, length), timber)
		_solid(cabin)
	_build_windows(quarterdeck, cabin)
	_build_pillars(quarterdeck, cabin)
	_build_castle_trim(quarterdeck, cabin)
	_build_castle_rim(quarterdeck, cabin)
	# Starboard of the stairs, its back against the front wall. The model's origin is the foot
	# of its leaf, halfway through its depth.
	var door := Node3D.new()
	door.name = "Door"
	door.position = Vector3(0.6, DECK_Y, CASTLE_FRONT_Z - 0.157)
	quarterdeck.add_child(door)
	_fit_model(door, CABIN_PARTS + "cabin_door.glb")

	# The model's origin is its foot on the centreline; it climbs 2.6 m toward +Z.
	var stairs := Node3D.new()
	stairs.name = "Stairs"
	stairs.position = QUARTERDECK_STAIRS_AT
	quarterdeck.add_child(stairs)
	# Its rails are the rail's own parts, laid up the slope with the quarterdeck's (_rail_legs).
	if _fit_model(stairs, DECK_PARTS + "stairs_260.glb"):
		_walkable(stairs)
	else:
		var run := Vector2(3.25, 2.6)
		var ramp := _box(stairs, Vector3(0.0, run.y * 0.5, run.x * 0.5), Vector3(1.0, 0.1, run.length()), timber)
		ramp.rotation.x = -atan2(run.y, run.x)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(1.0, 0.1, run.length())
		shape.shape = slab
		shape.transform = ramp.transform
		body.add_child(shape)
		stairs.add_child(body)


## The flat toon pass the whole ship shares: no specular, no metal, full roughness. Each
## surface gets its own copy, so the imported material is never edited in place.
func _toon(mesh_node: MeshInstance3D) -> void:
	for surface in mesh_node.mesh.get_surface_count():
		var material := mesh_node.mesh.surface_get_material(surface)
		if material is BaseMaterial3D:
			mesh_node.set_surface_override_material(surface, _toon_copy(material))


func _toon_copy(material: BaseMaterial3D) -> BaseMaterial3D:
	var flat: BaseMaterial3D = material.duplicate()
	flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	flat.metallic = 0.0
	flat.roughness = 1.0
	flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return flat


## Puts the model at `path` under `parent` as a child named Model, toon-shaded like the hull.
## False when the file is not there, so the caller can build its placeholder instead. Each
## model's origin is already its attachment point (see art/references/ship-kit/tripo), so a
## part lands by its node's position, never by an offset measured off the mesh.
func _fit_model(parent: Node3D, path: String, at := Vector3.ZERO, degrees := Vector3.ZERO) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.position = at
	model.rotation_degrees = degrees
	parent.add_child(model)
	for node in _descendants(model):
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			_toon(node as MeshInstance3D)
	return true


## The F03 helm model, or a wheel and a stand in the kit's helm box when it is missing.
## The node is named Helm and sits on HELM_AT so the swap is a mesh, not a new place. The
## model's wheel is on its aft side, toward HELM_FEET.
func _build_helm() -> void:
	var helm := get_node_or_null("Helm") as Node3D
	if helm != null:
		helm.position = HELM_AT
		return
	helm = Node3D.new()
	helm.name = "Helm"
	helm.position = HELM_AT
	add_child(helm)
	_helm_body(helm)
	if _fit_model(helm, FITTINGS + "helm.glb"):
		return
	var timber := _flat(Color(0.55, 0.36, 0.18))
	var iron := _flat(Color(0.22, 0.22, 0.24))
	var brass := _flat(Color(0.75, 0.58, 0.22))
	_box(helm, Vector3(0.0, 0.06, 0.0), Vector3(0.7, 0.12, 0.36), timber)
	_box(helm, Vector3(-0.16, 0.48, 0.0), Vector3(0.08, 0.84, 0.08), timber)
	_box(helm, Vector3(0.16, 0.48, 0.0), Vector3(0.08, 0.84, 0.08), timber)
	_box(helm, Vector3(0.0, 0.9, 0.0), Vector3(0.4, 0.08, 0.08), iron)
	var wheel := Node3D.new()
	wheel.name = "Wheel"
	wheel.position = Vector3(0.0, 1.15, 0.08)
	helm.add_child(wheel)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var spoke := _box(wheel, Vector3(cos(ang) * 0.24, sin(ang) * 0.24, 0.0), Vector3(0.36, 0.05, 0.05), timber)
		spoke.rotation.z = ang
		var rim := _box(wheel, Vector3(cos(ang) * 0.46, sin(ang) * 0.46, 0.0), Vector3(0.2, 0.07, 0.07), timber)
		rim.rotation.z = ang + PI * 0.5
	_cylinder(wheel, Vector3.ZERO, 0.08, 0.1, brass)


## The stand collides and the wheel does not: the helmsman stands 0.4 m aft of its rim.
func _helm_body(helm: Node3D) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 1.35, 0.28)
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(shape)
	helm.add_child(body)


## Lower mast, topmast and a lookout: the M02/M03/M04 models, or spars in the kit's sizes
## when they are missing. The node is named Mast and sits on MAST_AT so the swap is a mesh,
## not a new place.
func _build_mast() -> void:
	if get_node_or_null("Mast") == null:
		_square_mast("Mast", MAST_AT, 1.0)


## A square-rigged mast at `at`, named `mast_name`, built at `scale` of the mainmast: the lower
## mast, the top on its head with the lookout's posts and rail ring, the topmast, the course yard
## under the top, the topsail yard and topsail foot yard on the topmast, a block under each yard
## arm, and the lower mast's collision. Everything is laid out in the mainmast's own measures;
## the node's scale makes the foremast of them.
func _square_mast(mast_name: String, at: Vector3, scale: float) -> Node3D:
	var mast := Node3D.new()
	mast.name = mast_name
	mast.position = at
	mast.scale = Vector3.ONE * scale
	add_child(mast)
	var timber := _flat(Color(0.55, 0.36, 0.18))
	var iron := _flat(Color(0.22, 0.22, 0.24))
	# M01: radius 0.25 at the deck narrowing to 0.18 at the head. The model is 5.5 m from its deck
	# contact, stretched to MAIN_LOWER, with the topmast's heel seated on its head.
	var lower := Node3D.new()
	lower.name = "Lower"
	mast.add_child(lower)
	if _fit_model(lower, RIGGING + "mainmast.glb"):
		(lower.get_node("Model") as Node3D).scale = Vector3(1.0, MAIN_LOWER / 5.5, 1.0)
	else:
		_spar(lower, MAIN_LOWER * 0.5, 0.25, 0.18, MAIN_LOWER, timber)
		_spar(lower, 1.4, 0.3, 0.3, 0.08, iron)
		_spar(lower, 3.6, 0.24, 0.24, 0.08, iron)
		_spar(lower, MAIN_LOWER - 0.08, 0.22, 0.22, 0.1, iron)
	var upper := Node3D.new()
	upper.name = "Topmast"
	upper.position = Vector3(0.0, MAIN_LOWER, 0.0)
	mast.add_child(upper)
	if not _fit_model(upper, RIGGING + "topmast.glb"):
		# M02 sits on that head and runs another 3 m, down to a 0.08 m tip.
		_spar(upper, 1.5, 0.18, 0.08, 3.0, timber)
	# M03 wraps the joint: a platform and a rail, not a socket in the spar. The model's hole
	# was sized to clear the 0.18 m head; the posts and ring are still the placeholder's,
	# because Tripo's platform has no rail and the lookout needs one.
	var top := Node3D.new()
	top.name = "Top"
	mast.add_child(top)
	if not _fit_model(top, RIGGING + "mast_top.glb", Vector3(0.0, MAST_TOP_Y, 0.0)):
		_spar(top, MAIN_LOWER, 1.05, 1.05, 0.18, timber)
	# Turned half a step off the centreline, so the stay from the mast aft passes between two.
	for i in 8:
		var ang := TAU * (float(i) + 0.5) / 8.0
		var post := _box(mast, Vector3(cos(ang) * 0.95, 6.05 + MAIN_LIFT, sin(ang) * 0.95), Vector3(0.08, 1.1, 0.08), timber)
		post.name = "TopPost%d" % i
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.04
	ring.rings = 24
	ring.ring_segments = 6
	var rail := MeshInstance3D.new()
	rail.name = "TopRail"
	rail.mesh = ring
	rail.position = Vector3(0.0, 6.6 + MAIN_LIFT, 0.0)
	rail.material_override = timber
	mast.add_child(rail)
	# One course yard under the top. The kit never sized one; this is the crosspiece that
	# makes the pole read as a mast. Eight metres, so it clears the six-metre beam.
	var yard := Node3D.new()
	yard.name = "Yard"
	yard.position = Vector3(0.0, 4.6 + MAIN_LIFT, 0.0)
	mast.add_child(yard)
	# The model already runs athwartships along X, from its sling at the origin.
	if not _fit_model(yard, RIGGING + "lower_yard.glb"):
		# Local up lies along starboard, so the spar runs athwartships and tapers to both tips.
		yard.rotation_degrees.z = -90.0
		_spar(yard, -2.0, 0.06, 0.12, 4.0, timber)
		_spar(yard, 2.0, 0.12, 0.06, 4.0, timber)
		_spar(yard, 0.0, 0.2, 0.2, 0.12, iron)
	# The topsail's yards: just under the topmast's tip, and just clear of the lookout's rails.
	_crossyard(mast, "TopsailYard", 8.15 + MAIN_LIFT, 2.6, 0.09, timber, iron)
	_crossyard(mast, "TopsailFoot", 6.9 + MAIN_LIFT, 2.6, 0.07, timber, iron)
	# A single block under each end of the course yard and the topsail yard (YARD_BLOCKS).
	var blocks := Node3D.new()
	blocks.name = "Blocks"
	mast.add_child(blocks)
	for spot in YARD_BLOCKS:
		for side in [1.0, -1.0]:
			var block := Node3D.new()
			block.position = Vector3(side * spot[1], spot[0], spot[2])
			blocks.add_child(block)
			_fit_model(block, RIGGING + "block_single.glb")
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.28
	col.height = MAIN_LOWER
	shape.shape = col
	shape.position = Vector3(0.0, MAIN_LOWER * 0.5, 0.0)
	body.add_child(shape)
	mast.add_child(body)
	return mast


## The foremast, on the bow forward of the hatch: the mainmast again at FORE_SCALE
## (_square_mast), with three shrouds a side from its top's collar down to channels on the bow.
## The jib stays to it, not to the main.
func _build_foremast() -> void:
	if get_node_or_null("Foremast") != null:
		return
	var mast := _square_mast("Foremast", FOREMAST_AT, FORE_SCALE)
	var shrouds := _rigging_node(mast, "Shrouds")
	# As the main's: on the top's collar, forward, clear of the course yard.
	var upper_z: Array[float] = [-0.4, -0.33, -0.26]
	for side in [-1.0, 1.0]:
		var tops: Array[Vector3] = []
		var hull: Array[Vector3] = []
		for i in FORE_SHROUD_FEET.size():
			tops.append(FOREMAST_AT + Vector3(side * 0.25, 5.05 + MAIN_LIFT, upper_z[i]) * FORE_SCALE)
			hull.append(_hull_edge(FOREMAST_AT.z + FORE_SHROUD_FEET[i], side))
		var mid: float = FOREMAST_AT.z + (FORE_SHROUD_FEET[0] + FORE_SHROUD_FEET[FORE_SHROUD_FEET.size() - 1]) * 0.5
		_ratlines(shrouds, tops, _shroud_side(shrouds, tops, hull, _hull_out(mid, side), false))


## The bowsprit, BOWSPRIT_LENGTH out over the stem, rising BOWSPRIT_RISE as it goes forward.
## The node is named Bowsprit and its origin is the mount, so the swap keeps this place.
func _build_bowsprit() -> void:
	if get_node_or_null("Bowsprit") != null:
		return
	var sprit := Node3D.new()
	sprit.name = "Bowsprit"
	sprit.position = BOWSPRIT_AT
	# Local up is turned to point forward (-Z) and a little above the horizontal.
	sprit.rotation_degrees.x = BOWSPRIT_RISE - 90.0
	add_child(sprit)
	# The M07 model reaches 3 m along its own -Z from the heel at its origin; turning it 90
	# degrees about X lays that along this node's +Y, the direction the placeholder spar runs.
	# Stretched along its length to BOWSPRIT_LENGTH, and thickened.
	if _fit_model(sprit, RIGGING + "bowsprit.glb", Vector3.ZERO, Vector3(90.0, 0.0, 0.0)):
		(sprit.get_node("Model") as Node3D).scale = Vector3(BOWSPRIT_GIRTH, BOWSPRIT_GIRTH, BOWSPRIT_LENGTH / 3.0)
	else:
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		_spar(sprit, BOWSPRIT_LENGTH * 0.5, 0.19, 0.1, BOWSPRIT_LENGTH, timber)
		_spar(sprit, 0.45, 0.23, 0.23, 0.12, iron)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.16 * BOWSPRIT_GIRTH
	col.height = BOWSPRIT_LENGTH
	shape.shape = col
	shape.position = Vector3(0.0, BOWSPRIT_LENGTH * 0.5, 0.0)
	body.add_child(shape)
	sprit.add_child(body)


## From the bowsprit tip down to the stem, so the jib cannot lift the spar.
func _build_bobstay() -> void:
	if get_node_or_null("Bobstay") != null or get_node_or_null("Bowsprit") == null:
		return
	var stay := Node3D.new()
	stay.name = "Bobstay"
	add_child(stay)
	var tip := _along_bowsprit(BOWSPRIT_LENGTH - 0.1)
	_rope(stay, tip, Vector3(0.0, 2.6, -0.6), 0.02, _flat(Color(0.45, 0.34, 0.22)))


## The point `metres` out along the bowsprit's axis from its heel, in ship space.
func _along_bowsprit(metres: float) -> Vector3:
	return BOWSPRIT_AT + Basis(Vector3.RIGHT, deg_to_rad(BOWSPRIT_RISE - 90.0)) * Vector3(0.0, metres, 0.0)


## The F06 blade and its sternpost hinge strip, or a placeholder blade on an iron post.
## The node is named Rudder and its origin is the hinge, so the swap keeps this place. Both
## models share that origin: the blade reaches aft of it, the strip sits just forward.
func _build_rudder() -> void:
	if get_node_or_null("Rudder") != null:
		return
	var rudder := Node3D.new()
	rudder.name = "Rudder"
	rudder.position = RUDDER_AT
	add_child(rudder)
	var blade := FITTINGS + "rudder.glb"
	var strip := FITTINGS + "rudder_hinges.glb"
	# Both or neither: a model blade on the placeholder's iron post would hang off nothing.
	if ResourceLoader.exists(blade) and ResourceLoader.exists(strip):
		_fit_model(rudder, blade)
		var hinges := Node3D.new()
		hinges.name = "Hinges"
		rudder.add_child(hinges)
		_fit_model(hinges, strip)
	else:
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		# The hinge post. The blade's forward edge is this axis.
		_spar(rudder, -0.5, 0.08, 0.08, 2.0, iron)
		# Wider at the foot, shorter under the counter, still inside the kit's box.
		for i in 6:
			var t := float(i) / 5.0
			var y := -1.35 + t * 1.7
			var length := lerpf(0.95, 0.55, t)
			_box(rudder, Vector3(0.0, y, 0.08 + length * 0.5), Vector3(0.16, 0.26, length), timber)
		_box(rudder, Vector3(0.0, -0.5, 0.35), Vector3(0.2, 1.7, 0.06), iron)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.24, 2.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.5)
	body.add_child(shape)
	rudder.add_child(body)


## The F05 capstan model, or a drum and two bars inside the kit's capstan box.
## The node is named Capstan and sits on CAPSTAN_AT so the swap is a mesh, not a new place.
## Only the drum collides. The bars are the working radius, and a solid box that wide would
## close the gun deck's walk between the guns.
func _build_capstan() -> void:
	if get_node_or_null("Capstan") != null:
		return
	var capstan := Node3D.new()
	capstan.name = "Capstan"
	capstan.position = CAPSTAN_AT
	add_child(capstan)
	if not _fit_model(capstan, FITTINGS + "capstan.glb"):
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		_spar(capstan, 0.08, 0.55, 0.55, 0.16, timber)
		_spar(capstan, 0.52, 0.34, 0.28, 0.72, timber)
		_spar(capstan, 0.7, 0.36, 0.36, 0.06, iron)
		_spar(capstan, 0.98, 0.42, 0.5, 0.2, timber)
		# Two bars through the head, out to the 1.4 m bound on each axis.
		_box(capstan, Vector3(0.0, 0.88, 0.0), Vector3(2.8, 0.08, 0.08), timber)
		_box(capstan, Vector3(0.0, 0.88, 0.0), Vector3(0.08, 0.08, 2.8), timber)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.5
	col.height = 1.1
	shape.shape = col
	shape.position = Vector3(0.0, 0.55, 0.0)
	body.add_child(shape)
	capstan.add_child(body)


## The fittings with no placeholder to replace: a binnacle ahead of the wheel, a collar where
## each mast meets the deck, the lantern on the stern rail, and a frame and lid on every
## gunport. Each is placed only if its model is there - none of them is something the ship
## needs in order to work.
func _build_deck_fittings() -> void:
	if get_node_or_null("DeckFittings") != null:
		return
	var fittings := Node3D.new()
	fittings.name = "DeckFittings"
	add_child(fittings)

	var binnacle := Node3D.new()
	binnacle.name = "Binnacle"
	binnacle.position = BINNACLE_AT
	fittings.add_child(binnacle)
	if _fit_model(binnacle, FITTINGS + "binnacle.glb"):
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var col := CylinderShape3D.new()
		col.radius = 0.3
		col.height = 1.1
		shape.shape = col
		shape.position = Vector3(0.0, 0.55, 0.0)
		body.add_child(shape)
		binnacle.add_child(body)

	# The collar's hole is 0.52 m across, for the mainmast's 0.5 m foot; the foremast is thinner.
	for spot in [["MastCollar", MAST_AT], ["ForemastCollar", FOREMAST_AT]]:
		var collar := Node3D.new()
		collar.name = spot[0]
		collar.position = spot[1]
		fittings.add_child(collar)
		_fit_model(collar, DECK_PARTS + "mast_collar.glb")

	# The model's origin is the top of its wall plate, and the lantern hangs aft of it (+Z).
	var lantern := Node3D.new()
	lantern.name = "SternLantern"
	lantern.position = LANTERN_AT
	fittings.add_child(lantern)
	_fit_model(lantern, FITTINGS + "stern_lantern.glb")


	for entry in DECK_PROPS:
		var prop := Node3D.new()
		prop.name = entry[0]
		prop.position = entry[2]
		prop.rotation_degrees.y = entry[3]
		fittings.add_child(prop)
		if not _fit_model(prop, "res://art/models/ship/" + entry[1]):
			continue
		if prop.name == "Hatch":
			# The grating rests on the coaming and covers its opening.
			var top := _mesh_bounds(prop).end.y
			var grating := Node3D.new()
			grating.name = "Grating"
			grating.position = Vector3(0.0, top, 0.0)
			prop.add_child(grating)
			_fit_model(grating, FITTINGS + "hatch_grating.glb")
		if entry[4]:
			_solid(prop)

	# One cathead on each bow, the anchor hanging from its fall. The port one is the same model
	# turned the other way rather than mirrored, so its texture and winding stay right.
	for side in [1.0, -1.0]:
		var cathead := Node3D.new()
		cathead.name = "CatheadStarboard" if side > 0.0 else "CatheadPort"
		cathead.position = Vector3(side * CATHEAD_AT.x, CATHEAD_AT.y, CATHEAD_AT.z)
		cathead.rotation_degrees.y = CATHEAD_YAW if side > 0.0 else 180.0 - CATHEAD_YAW
		fittings.add_child(cathead)
		if _fit_model(cathead, FITTINGS + "cathead.glb"):
			var anchor := Node3D.new()
			anchor.name = "Anchor"
			anchor.position = CATHEAD_FALL
			# Flukes fore and aft, along the bow, rather than across it into the planking.
			anchor.rotation_degrees.y = 90.0
			cathead.add_child(anchor)
			_fit_model(anchor, FITTINGS + "anchor.glb")

	# Beams under the weather deck, seen from the gun deck. The model's origin is its top
	# centre, so it hangs from the underside of the 0.18 m slab.
	var beams := Node3D.new()
	beams.name = "DeckBeams"
	fittings.add_child(beams)
	for z in DECK_BEAM_Z:
		var beam := Node3D.new()
		beam.name = "Beam%d" % int(z)
		beam.position = Vector3(0.0, DECK_Y - 0.18, z)
		beams.add_child(beam)
		_fit_model(beam, DECK_PARTS + "deck_beam.glb")


## The rail along RAIL_PATH, both sides, from the posts, handrail, base and baluster in
## art/models/ship/deck (rail_post.glb, rail_parts.glb). Each part is drawn as one MultiMesh,
## so two hundred balusters are one draw call. A baluster that would stand in a cathead's
## timber is left out. Each straight length collides as one box the rail's height, so nobody
## walks off the deck; without the models, plain timber boxes stand in.
func _build_rail() -> void:
	if get_node_or_null("Rail") != null:
		return
	var rail := Node3D.new()
	rail.name = "Rail"
	add_child(rail)
	var parts := _rail_parts()
	var timber := _flat(Color(0.55, 0.36, 0.18))
	if parts.is_empty():
		parts = {"post": _box_mesh(Vector3(0.24, 0.95, 0.24), 0.475), "baluster": _box_mesh(Vector3(0.08, 0.44, 0.08), 0.38)}
		for key in parts:
			(parts[key] as Mesh).surface_set_material(0, timber)
	var post_width: float = (parts["post"] as Mesh).get_aabb().size.x

	# Anything a baluster must not stand in, in ship space.
	var clear: Array[AABB] = []
	for name in ["CatheadStarboard", "CatheadPort"]:
		var cathead := get_node_or_null("DeckFittings/" + name) as Node3D
		if cathead != null:
			clear.append(global_transform.affine_inverse() * cathead.global_transform * _mesh_bounds(cathead))
	var baluster_box: AABB = (parts["baluster"] as Mesh).get_aabb()

	var placed := {"post": [], "baluster": []}
	var body := StaticBody3D.new()
	body.name = "Body"
	rail.add_child(body)
	# The weather deck's rail stops short of the front wall's corner pillars; without them it
	# ends just clear of the wall.
	var pillars := get_node_or_null("Quarterdeck/Pillars") as Node3D
	var legs := _rail_legs(pillars != null and pillars.get_child_count() > 0 and pillars.get_child(0).get_node_or_null("Model") != null)
	var post_lines: Array = []
	for line in legs:
		post_lines.append(_lay_rail(line, post_width, baluster_box, clear, placed, body))
	# Every post, line by line, for the tests: the MultiMesh does not keep them headless.
	rail.set_meta("post_lines", post_lines)

	for key in ["post", "baluster"]:
		var mesh: Mesh = parts[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = placed[key].size()
		for n in placed[key].size():
			multi.set_instance_transform(n, placed[key][n])
		var node := MultiMeshInstance3D.new()
		node.name = key.capitalize() + "s"
		node.multimesh = multi
		# Kept on the node too: without a renderer (headless runs, the tests) the MultiMesh does
		# not hold its instances' transforms.
		node.set_meta("placed", placed[key])
		var material := mesh.surface_get_material(0)
		if material is BaseMaterial3D:
			node.material_override = _toon_copy(material)
		rail.add_child(node)

	# The handrail and base: each one profile swept along every leg, as one mesh.
	for key in ["handrail", "base"]:
		var profile := _rail_profile(key, timber)
		var sweep := SurfaceTool.new()
		sweep.begin(Mesh.PRIMITIVE_TRIANGLES)
		for line in legs:
			_sweep(sweep, line, profile)
		var node := MeshInstance3D.new()
		node.name = key.capitalize() + "s"
		node.mesh = sweep.commit()
		node.material_override = profile["material"]
		rail.add_child(node)


## CASTLE_WINDOW_COUNT windows spread evenly along the castle's wall (_castle_wall), each
## centred on the wall panel its even spacing falls on, facing out from it, and stood off it by
## window_offset.
func _build_windows(quarterdeck: Node3D, cabin: Node3D) -> void:
	var windows := Node3D.new()
	windows.name = "Windows"
	quarterdeck.add_child(windows)
	var wall := _castle_wall(cabin)
	if wall.size() < 2 or CASTLE_WINDOW_COUNT < 1:
		return
	var reach := _reach(wall)
	for k in CASTLE_WINDOW_COUNT:
		var at := _panel_spot(wall, reach, _panel_at(reach, _window_reach(reach, k)))
		var out := at.basis.z
		var window := Node3D.new()
		window.name = "Window%d" % k
		# Stood out by the depth behind the model's origin, so its back is on the wall.
		window.position = at.origin + out * (window_offset + 0.105 * WINDOW_SCALE) + Vector3.UP * CASTLE_WINDOW_SILL
		window.rotation.y = atan2(out.x, out.z)
		window.scale = Vector3.ONE * WINDOW_SCALE
		windows.add_child(window)
		_fit_model(window, CABIN_PARTS + "cabin_window.glb")


## The castle's carved pillars, framing its walls as the corner posts of a stern castle do: one
## at each corner of the front wall, facing forward, and round the stern one between each pair
## of windows, except that the two either side of the stern window stand on the panels next to
## it, framing it. Each is centred on its wall panel as the windows are, stands on the deck
## line with its back on the wall, and is stood off it by pillar_offset.
func _build_pillars(quarterdeck: Node3D, cabin: Node3D) -> void:
	var pillars := Node3D.new()
	pillars.name = "Pillars"
	quarterdeck.add_child(pillars)
	var wall := _castle_wall(cabin)
	if wall.size() < 2:
		return
	var spots: Array[Transform3D] = []
	for side in [1.0, -1.0]:
		spots.append(Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD), Vector3(side * _corner_pillar_x(wall), DECK_Y, wall[0].z)))
	var reach := _reach(wall)
	var windows: Array[int] = []
	for k in CASTLE_WINDOW_COUNT:
		windows.append(_panel_at(reach, _window_reach(reach, k)))
	var middle := CASTLE_WINDOW_COUNT / 2 if CASTLE_WINDOW_COUNT % 2 == 1 else -1
	for k in CASTLE_WINDOW_COUNT - 1:
		var panel := _panel_at(reach, (_window_reach(reach, k) + _window_reach(reach, k + 1)) * 0.5)
		if k == middle - 1:
			panel = windows[middle] - 1
		elif k == middle:
			panel = windows[middle] + 1
		spots.append(_panel_spot(wall, reach, panel))
	for k in spots.size():
		var out := spots[k].basis.z
		var pillar := Node3D.new()
		pillar.name = "Pillar%d" % k
		pillar.position = spots[k].origin + out * (pillar_offset + PILLAR_BACK * PILLAR_SCALE)
		pillar.rotation.y = atan2(out.x, out.z)
		pillar.scale = Vector3.ONE * PILLAR_SCALE
		pillars.add_child(pillar)
		_fit_model(pillar, CABIN_PARTS + "cabin_pillar.glb")
		# The corner pillars stand on the weather deck, where the rail ends short of them: solid,
		# so nobody walks through one and off the deck.
		if k < 2:
			var body := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.199, 1.0, 0.172)
			shape.shape = box
			shape.position = Vector3(0.0, 0.5, 0.0)
			body.add_child(shape)
			pillar.add_child(body)


## How far out from the centreline the front wall's corner pillars stand (PILLAR_CORNER_PROUD).
func _corner_pillar_x(wall: Array[Vector3]) -> float:
	return absf(wall[0].x) + PILLAR_CORNER_PROUD - PILLAR_WIDTH * 0.5


## How far along the castle's wall the `k`th window's even spacing falls, before it is centred on
## its panel.
func _window_reach(reach: PackedFloat32Array, k: int) -> float:
	var t := 0.5 if CASTLE_WINDOW_COUNT == 1 else float(k) / (CASTLE_WINDOW_COUNT - 1)
	return lerpf(CASTLE_WINDOW_MARGIN, reach[reach.size() - 1] - CASTLE_WINDOW_MARGIN, t)


## How far along `line` each of its points is, in metres.
func _reach(line: Array[Vector3]) -> PackedFloat32Array:
	var reach: PackedFloat32Array = [0.0]
	for i in line.size() - 1:
		reach.append(reach[i] + line[i].distance_to(line[i + 1]))
	return reach


## The castle wall's panel that `s` metres along it falls on.
func _panel_at(reach: PackedFloat32Array, s: float) -> int:
	var panel := 0
	while panel < reach.size() - 2 and reach[panel + 1] <= s:
		panel += 1
	return panel


## Where something flat-backed stands on the castle's wall (_castle_wall): the middle of wall
## panel `panel`, so its back lies on a flat wall, at the deck. Its basis's Z points out.
func _panel_spot(wall: Array[Vector3], reach: PackedFloat32Array, panel: int) -> Transform3D:
	var at := _rail_at(wall, reach, (reach[panel] + reach[panel + 1]) * 0.5)
	# The wall runs with the castle on its right, so out is -Z of the rail's frame.
	var out := -at.basis.z
	return Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), at.origin)


## The castle's trim, one mesh: the wale's profile swept along the castle's walls at
## CASTLE_TRIM_Y, so they end in a moulding under the quarterdeck's rail instead of a bare
## edge. It runs from the stairs across the front wall to the port corner, round the stern,
## and back across the front to the stairs' other side. At both ends it turns into the wall,
## so its open ends are inside the castle and the stairs see a returned end, as a joiner
## finishes a moulding.
func _build_castle_trim(quarterdeck: Node3D, cabin: Node3D) -> void:
	var wall := _castle_wall(cabin)
	if wall.size() < 2:
		return
	var front := wall[0].z
	var into := front + 0.25
	var port_end := QUARTERDECK_STAIRS_AT.x - CASTLE_TRIM_STAIRS
	var starboard_end := QUARTERDECK_STAIRS_AT.x + CASTLE_TRIM_STAIRS
	# Round the same way as the wale, port side aft first, so its profile stands out from the walls.
	var line: Array[Vector3] = [Vector3(port_end, CASTLE_TRIM_Y, into), Vector3(port_end, CASTLE_TRIM_Y, front)]
	for i in range(wall.size() - 1, -1, -1):
		line.append(Vector3(wall[i].x, CASTLE_TRIM_Y, wall[i].z))
	line.append_array([Vector3(starboard_end, CASTLE_TRIM_Y, front), Vector3(starboard_end, CASTLE_TRIM_Y, into)])
	var profile := _rail_profile("wale", _flat(Color(0.45, 0.28, 0.14)))
	var sweep := SurfaceTool.new()
	sweep.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sweep(sweep, line, profile)
	var trim := MeshInstance3D.new()
	trim.name = "Trim"
	trim.mesh = sweep.commit()
	trim.material_override = profile["material"]
	quarterdeck.add_child(trim)


## The castle's bottom rim, one mesh: the trim's profile swept round the castle's outside walls
## with its foot on the deck line, covering the joint where the castle stands on the hull. The
## pillars stand on the same line, and the rim runs into their bases. Not across the front wall,
## where it would be a step in the walkway: it goes round each front corner and ends inside the
## corner pillar's base.
func _build_castle_rim(quarterdeck: Node3D, cabin: Node3D) -> void:
	var wall := _castle_wall(cabin)
	if wall.size() < 2:
		return
	var profile := _rail_profile("wale", _flat(Color(0.45, 0.28, 0.14)))
	var low := INF
	for point in profile["points"] as PackedVector2Array:
		low = minf(low, point.y)
	var y := DECK_Y - low
	var tuck := _corner_pillar_x(wall)
	# Round the same way as the trim, so its profile stands out from the walls.
	var line: Array[Vector3] = [Vector3(-tuck, y, wall[0].z)]
	for i in range(wall.size() - 1, -1, -1):
		line.append(Vector3(wall[i].x, y, wall[i].z))
	line.append(Vector3(tuck, y, wall[0].z))
	var sweep := SurfaceTool.new()
	sweep.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sweep(sweep, line, profile)
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = sweep.commit()
	rim.material_override = profile["material"]
	quarterdeck.add_child(rim)


## The castle's wall round the stern, at the deck, as a line from its starboard front corner to
## its port front corner: the foot of its model's walls, less the front wall. Read off the
## model, so the windows follow the castle whatever shape it is built to.
func _castle_wall(cabin: Node3D) -> Array[Vector3]:
	var feet: Array[Vector3] = []
	var to_ship := global_transform.affine_inverse()
	for child in _descendants(cabin):
		if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null:
			continue
		var mesh_node := child as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			for v in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = to_ship * mesh_node.global_transform * v
				if absf(p.y - DECK_Y) < 0.01 and feet.all(func(q: Vector3) -> bool: return q.distance_to(p) > 0.001):
					feet.append(Vector3(p.x, DECK_Y, p.z))
	if feet.size() < 3:
		return []
	var centre := Vector3.ZERO
	for p in feet:
		centre += p
	centre /= feet.size()
	# Round the outline, starting at the starboard front corner: the front wall is left out.
	var corner := feet[0]
	for p in feet:
		if p.z < corner.z - 0.001 or (absf(p.z - corner.z) <= 0.001 and p.x > corner.x):
			corner = p
	var start := atan2(corner.z - centre.z, corner.x - centre.x) - 0.001
	var angle := func(p: Vector3) -> float: return fposmod(atan2(p.z - centre.z, p.x - centre.x) - start, TAU)
	feet.sort_custom(func(a: Vector3, b: Vector3) -> bool: return angle.call(a) < angle.call(b))
	return feet


## One leg of rail along `line`: posts spaced evenly from end to end and balusters spread
## between each pair, no baluster in anything in `clear`. Adds what it places to `placed`, and a
## collision box per straight length to `body`. Returns the posts. The handrail and base are
## swept along the leg (_sweep).
func _lay_rail(line: Array[Vector3], post_width: float, baluster_box: AABB,
		clear: Array[AABB], placed: Dictionary, body: StaticBody3D) -> Array[Transform3D]:
	var reach: PackedFloat32Array = [0.0]
	for i in line.size() - 1:
		reach.append(reach[i] + line[i].distance_to(line[i + 1]))
	var length := reach[reach.size() - 1]
	# A leg that mirrors across the centreline gets an even count, so a post stands on its
	# middle: the stern's centreline, where the lantern hangs.
	var bays := ceili(length / RAIL_SPAN - 0.001)
	var first := line[0]
	var last := line[line.size() - 1]
	if absf(first.x) > 0.01 and absf(first.x + last.x) < 0.01 and absf(first.z - last.z) < 0.01:
		bays += bays % 2
	# A leg that climbs straight, up the stairs, has a post only at its foot and its head, and
	# balusters all the way between. The rail rising with the bow's sheer keeps its spacing.
	if line.size() == 2 and absf(first.y - last.y) > 0.01:
		bays = 1
	var posts: Array[float] = []
	var standing: Array[Transform3D] = []
	for k in bays + 1:
		posts.append(length * k / bays)
		var post := _rail_at(line, reach, posts[k])
		standing.append(post)
		# Where two legs meet they share the corner's post: stand it once.
		var shared := false
		for other in placed["post"]:
			shared = shared or (other as Transform3D).origin.distance_to(post.origin) < 0.001
		if not shared:
			placed["post"].append(post)

	# Collision in straight lengths, one per hull panel between posts, each running through
	# the posts so there is no gap at either end. A box cannot shear, so up the stairs it is
	# tilted instead.
	var cuts: Array[float] = posts.duplicate()
	for i in range(1, line.size() - 1):
		var near := false
		for s in posts:
			near = near or absf(s - reach[i]) < 0.05
		if not near:
			cuts.append(reach[i])
	cuts.sort()
	for i in cuts.size() - 1:
		var half := (cuts[i] + cuts[i + 1]) * 0.5
		var mid := _rail_at(line, reach, half)
		var along := (_rail_at(line, reach, half + 0.005).origin - _rail_at(line, reach, half - 0.005).origin).normalized()
		var shape := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(cuts[i + 1] - cuts[i] + 0.1, RAIL_HEIGHT, 0.2)
		shape.shape = slab
		var side := mid.basis.z
		shape.transform = Transform3D(Basis(along, side.cross(along), side), mid.origin + Vector3.UP * RAIL_HEIGHT * 0.5)
		body.add_child(shape)

	# Balusters spread evenly between each pair of posts, round the corners with the rail.
	for k in bays:
		var inner := posts[k + 1] - posts[k] - post_width
		var count := maxi(1, roundi(inner / BALUSTER_PITCH))
		for j in count:
			var here := _rail_at(line, reach, posts[k] + post_width * 0.5 + inner * (j + 0.5) / count)
			var blocked := false
			for box in clear:
				blocked = blocked or (here * baluster_box).intersects(box)
			if not blocked:
				placed["baluster"].append(here)
	return standing


## The rail's lines, each running with the deck on its left so a post's local +Z faces out:
## - the weather deck, each side from its knighthead at the bow to the castle's front wall, or
##   with `before_pillars` to RAIL_PILLAR_GAP short of the corner pillar there;
## - the quarterdeck's: up the stairs' outboard side, across the front to the port corner,
##   round the stern on the castle's wall top, back across the front to the landing and down
##   the stairs' inboard side. The stair rails start 0.16 m up from the stairs' foot, so the
##   inboard post stays clear of the stair opening in the deck below.
## A line is split into legs wherever it turns more than RAIL_CORNER, and each leg gets its own
## evenly spaced posts, so a square corner always has a post on it.
func _rail_legs(before_pillars := false) -> Array:
	var front := CASTLE_FRONT_Z - 0.16
	if before_pillars:
		front = CASTLE_FRONT_Z - PILLAR_DEPTH - RAIL_PILLAR_GAP - 0.12
	var starboard: Array[Vector3] = [Vector3(2.9, DECK_Y, front)]
	for i in range(RAIL_PATH.size() - 1, -1, -1):
		if RAIL_PATH[i].y < front:
			starboard.append(Vector3(RAIL_PATH[i].x, DECK_Y, RAIL_PATH[i].y))
	starboard = _sheer_line(starboard)
	var port: Array[Vector3] = []
	for i in range(starboard.size() - 1, -1, -1):
		port.append(Vector3(-starboard[i].x, starboard[i].y, starboard[i].z))

	var edge := CASTLE_FRONT_Z + 0.1
	var landing := QUARTERDECK_STAIRS_AT.x
	var foot := QUARTERDECK_STAIRS_AT.z + 0.16
	var top: Array[Vector3] = [Vector3(landing - STAIR_RAIL_OUT, DECK_Y, foot),
			Vector3(landing - STAIR_RAIL_OUT, QUARTERDECK_Y, edge), Vector3(-2.9, QUARTERDECK_Y, edge)]
	for p in RAIL_PATH:
		if p.y > edge:
			top.append(Vector3(-p.x, QUARTERDECK_Y, p.y))
	for i in range(RAIL_PATH.size() - 2, -1, -1):
		if RAIL_PATH[i].y > edge:
			top.append(Vector3(RAIL_PATH[i].x, QUARTERDECK_Y, RAIL_PATH[i].y))
	top.append_array([Vector3(2.9, QUARTERDECK_Y, edge), Vector3(landing + STAIR_RAIL_OUT, QUARTERDECK_Y, edge),
			Vector3(landing + STAIR_RAIL_OUT, DECK_Y, foot)])

	var legs: Array = []
	for line in [port, starboard, top]:
		var leg: Array[Vector3] = [line[0]]
		for i in range(1, line.size()):
			leg.append(line[i])
			if i < line.size() - 1:
				var into: Vector3 = line[i] - line[i - 1]
				var turn := into.normalized().angle_to((line[i + 1] - line[i]).normalized())
				if turn > deg_to_rad(RAIL_CORNER):
					legs.append(leg)
					leg = [line[i]]
		legs.append(leg)
	return legs


## The point `s` metres along `line` (whose corners are `reach` metres along it), facing along
## the panel it is on, or along the turn when it is on a corner.
func _rail_at(line: Array[Vector3], reach: PackedFloat32Array, s: float) -> Transform3D:
	var i := 0
	while i < line.size() - 2 and reach[i + 1] <= s:
		i += 1
	var dir := (line[i + 1] - line[i]).normalized()
	if absf(s - reach[i + 1]) < 0.001 and i + 2 < line.size():
		dir = (dir + (line[i + 2] - line[i + 1]).normalized()).normalized()
	elif absf(s - reach[i]) < 0.001 and i > 0:
		dir = (dir + (line[i] - line[i - 1]).normalized()).normalized()
	var at := line[i] + (line[i + 1] - line[i]).normalized() * (s - reach[i])
	return Transform3D(_along(dir), at)


## The rail's post and baluster meshes, or empty when a model is missing.
func _rail_parts() -> Dictionary:
	if not ResourceLoader.exists(DECK_PARTS + "rail_parts.glb") or not ResourceLoader.exists(DECK_PARTS + "rail_post.glb"):
		return {}
	var parts := {}
	for file in ["rail_parts.glb", "rail_post.glb"]:
		var scene := (load(DECK_PARTS + file) as PackedScene).instantiate()
		for key in ["baluster", "post"]:
			var found := scene.find_child(key, true, false) as MeshInstance3D
			if found != null and found.mesh != null:
				parts[key] = found.mesh
		scene.free()
	return parts if parts.size() == 2 else {}


## The handrail's or base's profile from art/models/ship/deck/rail_sweep.glb
## (tools/rail_profiles.py): its outline across the rail as (across, up) points in order round
## it, closed by a repeat of the first, with each point's outward normal and its V, the metres
## of rail one repeat of its texture covers, and its material. Read by V rather than by vertex
## order, which the importer need not keep. Without the model, a plain square stands in.
func _rail_profile(key: String, timber: Material) -> Dictionary:
	var profile := {"points": PackedVector2Array(), "normals": PackedVector2Array(), "v": PackedFloat32Array(),
			"tile": 1.0, "material": timber}
	var mesh: Mesh = null
	if ResourceLoader.exists(DECK_PARTS + "rail_sweep.glb"):
		var scene := (load(DECK_PARTS + "rail_sweep.glb") as PackedScene).instantiate()
		var found := scene.find_child(key, true, false) as MeshInstance3D
		if found != null:
			mesh = found.mesh
		scene.free()
	if mesh == null:
		var low := {"handrail": 0.62, "base": 0.0, "wale": -0.06}.get(key, 0.0) as float
		for corner in [Vector2(0.06, low), Vector2(0.06, low + 0.12), Vector2(-0.06, low + 0.12), Vector2(-0.06, low), Vector2(0.06, low)]:
			profile["points"].append(corner)
			profile["normals"].append(Vector2(signf(corner.x), 0.0))
			profile["v"].append(profile["v"].size() / 4.0)
		return profile
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var ring: Array[int] = []
	var far := 0.0
	for i in vertices.size():
		far = maxf(far, vertices[i].x)
	for i in vertices.size():
		if vertices[i].x < far * 0.5:
			ring.append(i)
	ring.sort_custom(func(a: int, b: int) -> bool: return uvs[a].y < uvs[b].y)
	for i in ring:
		profile["points"].append(Vector2(vertices[i].z, vertices[i].y))
		profile["normals"].append(Vector2(normals[i].z, normals[i].y))
		profile["v"].append(uvs[i].y)
	profile["tile"] = far
	var material := mesh.surface_get_material(0)
	if material is BaseMaterial3D:
		profile["material"] = _toon_copy(material)
	return profile


## The wale, one mesh round the whole hull: its two outlines closed into a loop, stem, down the port
## side, round the stern, up the starboard side and back, with the hull on its right so its
## profile stands out from the hull.
func _build_wale() -> void:
	if get_node_or_null("Wale") != null:
		return
	var loop: Array[Vector3] = []
	for p in WALE_PORT:
		loop.append(Vector3(p.x, WALE_Y, p.y))
	for i in range(WALE_STARBOARD.size() - 2, -1, -1):
		loop.append(Vector3(WALE_STARBOARD[i].x, WALE_Y, WALE_STARBOARD[i].y))
	var profile := _rail_profile("wale", _flat(Color(0.45, 0.28, 0.14)))
	var sweep := SurfaceTool.new()
	sweep.begin(Mesh.PRIMITIVE_TRIANGLES)
	_sweep(sweep, loop, profile, true)
	var wale := MeshInstance3D.new()
	wale.name = "Wale"
	wale.mesh = sweep.commit()
	wale.material_override = profile["material"]
	wale.layers = 1 | (1 << 19)
	add_child(wale)


## `profile` swept along `line` into `into`: a ring of it at every point of the line, upright,
## turned to face along the line and mitred at every corner so it keeps its thickness round
## the turn. Up a slope the ring stays upright, so the rail is sheared, like the balusters. A
## `closed` line ends where it began, and that corner is mitred too.
## U runs with the metres along the line, so the grain is the same density everywhere.
func _sweep(into: SurfaceTool, line: Array[Vector3], profile: Dictionary, closed := false) -> void:
	var points: PackedVector2Array = profile["points"]
	var normals: PackedVector2Array = profile["normals"]
	var v: PackedFloat32Array = profile["v"]
	var tile: float = profile["tile"]
	var count := points.size()
	var reach := 0.0
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	var us: Array[float] = []
	var last := line.size() - 1
	for i in line.size():
		var into_dir := line[i] - line[i - 1] if i > 0 else line[1] - line[0]
		var out_dir := line[i + 1] - line[i] if i < last else into_dir
		# A closed line's first and last points are the same corner: turn it like any other.
		if closed and (i == 0 or i == last):
			into_dir = line[last] - line[last - 1]
			out_dir = line[1] - line[0]
		var flat_in := Vector3(into_dir.x, 0.0, into_dir.z).normalized()
		var flat_out := Vector3(out_dir.x, 0.0, out_dir.z).normalized()
		var across := (flat_in + flat_out).normalized()
		var side := across.cross(Vector3.UP)
		var miter := 1.0 / maxf(flat_in.dot(across), 0.3)
		var tangent := (into_dir.normalized() + out_dir.normalized()).normalized()
		if i > 0:
			reach += line[i].distance_to(line[i - 1])
		var ring := PackedVector3Array()
		var ring_n := PackedVector3Array()
		for k in count:
			ring.append(line[i] + side * points[k].x * miter + Vector3.UP * points[k].y)
			# The surface's true normal: across the profile's own tangent and along the line.
			var around := side * -normals[k].y + Vector3.UP * normals[k].x
			var n := around.cross(tangent).normalized()
			if n.dot(side * normals[k].x + Vector3.UP * normals[k].y) < 0.0:
				n = -n
			ring_n.append(n)
		rings.append(ring)
		ring_normals.append(ring_n)
		us.append(reach / tile)
	for i in line.size() - 1:
		for k in count - 1:
			var quad := [[i, k], [i + 1, k], [i, k + 1], [i, k + 1], [i + 1, k], [i + 1, k + 1]]
			# Godot's front faces wind clockwise: the corners' own normal points away from the
			# viewer. Checked on this quad's first triangle, and flipped if it comes out wrong.
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i + 1][k]
			var c: Vector3 = rings[i][k + 1]
			if (b - a).cross(c - a).dot(ring_normals[i][k]) > 0.0:
				quad = [[i, k], [i, k + 1], [i + 1, k], [i, k + 1], [i + 1, k + 1], [i + 1, k]]
			for corner in quad:
				var r: int = corner[0]
				var p: int = corner[1]
				into.set_normal(ring_normals[r][p])
				into.set_uv(Vector2(us[r], v[p]))
				into.add_vertex(rings[r][p])


## Local X along `dir` (flat), Y up.
func _along(dir: Vector3) -> Basis:
	var x := Vector3(dir.x, 0.0, dir.z).normalized()
	return Basis(x, Vector3.UP, x.cross(Vector3.UP))


## A box mesh of `size` whose centre stands `lift` above its origin.
func _box_mesh(size: Vector3, lift: float) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		vertices[i].y += lift
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Bounds of every mesh under `node`, in `node`'s own space.
func _mesh_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_local := node.global_transform.affine_inverse()
	for child in _descendants(node):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var mesh_node := child as MeshInstance3D
			var here: AABB = to_local * mesh_node.global_transform * mesh_node.mesh.get_aabb()
			box = here if first else box.merge(here)
			first = false
	return box


## A box collider the size of the model, so a coil or a hatch cannot be walked through. Taken
## from the meshes rather than typed in, so it follows the model if the model changes.
func _solid(node: Node3D) -> void:
	var box := _mesh_bounds(node)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = box.size
	shape.shape = cube
	shape.position = box.get_center()
	body.add_child(shape)
	node.add_child(body)


## The course hangs from its yard. The jib runs from the foremast to the bowsprit.
func _build_sail() -> void:
	if get_node_or_null("Mast") == null:
		return
	var old_sail := get_node_or_null("Sail")
	if old_sail != null:
		old_sail.free()
	var sail := SailScript.new() as Node3D
	sail.name = "Sail"
	_canvas(sail, "course")
	# Laced to the course yard and sheeted home COURSE_DROP below, just aft of the mast.
	var yard_y := MAST_AT.y + 4.6 + MAIN_LIFT
	var z := MAST_AT.z + 0.12
	var half := SailScript.HALF_WIDTH
	sail.call("rig_between", Vector3(-half, yard_y, z), Vector3(half, yard_y, z),
			Vector3(-half, yard_y - COURSE_DROP, z), Vector3(half, yard_y - COURSE_DROP, z), Vector3(0.0, 0.0, 0.45))
	add_child(sail)
	if get_node_or_null("Foremast") == null or get_node_or_null("Bowsprit") == null:
		return
	var old_jib := get_node_or_null("Jib")
	if old_jib != null:
		old_jib.free()
	# The foot from the clew, free above the bow, to the tack, lashed near the bowsprit's tip.
	var foot_from := JIB_CLEW
	var foot_to := _along_bowsprit(BOWSPRIT_LENGTH * 0.95)
	# A short span on the forward side of the foremast up to its course yard, as the reference's
	# jib is: not up at the masthead.
	var fore_yard_y := FOREMAST_AT.y + (4.6 + MAIN_LIFT) * FORE_SCALE
	var ahead := Vector3(0.0, 0.0, -0.2 * FORE_SCALE - 0.02)
	var head_from := Vector3(0.0, fore_yard_y - 1.0, FOREMAST_AT.z) + ahead
	var head_to := Vector3(0.0, fore_yard_y + 0.2, FOREMAST_AT.z) + ahead
	var jib := SailScript.new() as Node3D
	jib.name = "Jib"
	_canvas(jib, "jib")
	jib.call("rig_between", head_from, head_to, foot_from, foot_to, Vector3(0.35, 0.0, 0.0))
	add_child(jib)
	_build_fore_sails()


## The fore course, laced to the fore yard and sheeted home at its foot, and above it the fore
## topsail, laced between the fore topsail yard and the fore topsail foot yard. Both just aft of
## the foremast, as the main's are.
func _build_fore_sails() -> void:
	for old_name in ["ForeCourse", "ForeTopsail"]:
		var old := get_node_or_null(old_name)
		if old != null:
			old.free()
	# As the main's, at FORE_SCALE.
	var z := FOREMAST_AT.z + 0.12 * FORE_SCALE
	var course_y := FOREMAST_AT.y + (4.6 + MAIN_LIFT) * FORE_SCALE
	var course_half := SailScript.HALF_WIDTH * FORE_SCALE
	var course := SailScript.new() as Node3D
	course.name = "ForeCourse"
	_canvas(course, "course")
	course.call("rig_between", Vector3(-course_half, course_y, z), Vector3(course_half, course_y, z),
			Vector3(-course_half, course_y - FORE_COURSE_DROP, z), Vector3(course_half, course_y - FORE_COURSE_DROP, z), Vector3(0.0, 0.0, 0.4))
	add_child(course)
	var top_y := FOREMAST_AT.y + (8.15 + MAIN_LIFT) * FORE_SCALE
	var foot_y := FOREMAST_AT.y + (6.9 + MAIN_LIFT) * FORE_SCALE
	var top_half := 2.3 * FORE_SCALE
	var topsail := SailScript.new() as Node3D
	topsail.name = "ForeTopsail"
	_canvas(topsail, "topsail")
	topsail.call("rig_between", Vector3(-top_half, top_y, z), Vector3(top_half, top_y, z),
			Vector3(-top_half, foot_y, z), Vector3(top_half, foot_y, z), Vector3(0.0, 0.0, 0.3 * FORE_SCALE))
	add_child(topsail)


## Paints `sail` with Tripo's canvas for its kind (art/models/ship/rigging/canvas_<kind>.png,
## from tools/bake_sail_canvas.py): seams, patches and hem. Left plain if the file is missing.
func _canvas(sail: Node3D, kind: String) -> void:
	var path := RIGGING + "canvas_%s.png" % kind
	if ResourceLoader.exists(path):
		sail.call("use_canvas", load(path))


## A shorter course above the lookout. The topmast was a bare pole past the platform.
func _build_topsail() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	if mast == null:
		return
	if get_node_or_null("Topsail") != null:
		return
	var head_y := MAST_AT.y + 8.15 + MAIN_LIFT
	var foot_y := MAST_AT.y + 6.9 + MAIN_LIFT
	var z := MAST_AT.z + 0.12
	var half := 2.3
	var sail := SailScript.new() as Node3D
	sail.name = "Topsail"
	_canvas(sail, "topsail")
	sail.call("rig_between", Vector3(-half, head_y, z), Vector3(half, head_y, z), Vector3(-half, foot_y, z), Vector3(half, foot_y, z), Vector3(0.0, 0.0, 0.3))
	add_child(sail)


func _crossyard(mast: Node3D, yard_name: String, y: float, half: float, thick: float, timber: Material, iron: Material) -> void:
	if mast.get_node_or_null(yard_name) != null:
		return
	var yard := Node3D.new()
	yard.name = yard_name
	yard.position = Vector3(0.0, y, 0.12)
	mast.add_child(yard)
	# The M06 model is 5.2 m, the same as 2 * half, and already runs along X from its sling.
	if _fit_model(yard, RIGGING + "topsail_yard.glb"):
		return
	yard.rotation_degrees.z = -90.0
	_spar(yard, -half * 0.5, thick * 0.55, thick, half, timber)
	_spar(yard, half * 0.5, thick, thick * 0.55, half, timber)
	_spar(yard, 0.0, thick + 0.04, thick + 0.04, 0.1, iron)


## One rope a side from the topmast head down to the stern quarters, set up to a channel of its
## own on the castle's side (_shroud_side). The shrouds hold the mast sideways; these hold it aft.
## No collision, same as the shrouds.
func _build_backstays() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	var cabin := get_node_or_null("Quarterdeck/Cabin") as Node3D
	if mast == null or cabin == null or mast.get_node_or_null("Backstays") != null:
		return
	var stays := _rigging_node(mast, "Backstays")
	var wall := _castle_wall(cabin)
	for side in [-1.0, 1.0]:
		# On the aft side of the topmast just above the topsail yard, so the rope clears its cloth.
		var head := MAST_AT + Vector3(side * 0.1, 8.4 + MAIN_LIFT, 0.12)
		var nearest := 0
		for i in wall.size() - 1:
			var mid := (wall[i] + wall[i + 1]) * 0.5
			var best := (wall[nearest] + wall[nearest + 1]) * 0.5
			if mid.x * side > 0.0 and (best.x * side <= 0.0 or absf(mid.z - BACKSTAY_Z) < absf(best.z - BACKSTAY_Z)):
				nearest = i
		var at := (wall[nearest] + wall[nearest + 1]) * 0.5
		var out := (wall[nearest + 1] - wall[nearest]).cross(Vector3.UP).normalized()
		if out.x * side < 0.0:
			out = -out
		var tops: Array[Vector3] = [head]
		var hull: Array[Vector3] = [at]
		_shroud_side(stays, tops, hull, out, true)


## Three ropes a side, from the top's collar under the lookout down to the channels on
## the hull's sides (_shroud_side), and the ratlines across them. All forward of the mast, clear of
## the sails, which hang aft of it. No collision: a solid cage here would close the deck. A real
## rope mesh can replace this node.
func _build_shrouds() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	if mast == null:
		return
	var old := mast.get_node_or_null("Shrouds")
	if old != null:
		old.free()
	var shrouds := _rigging_node(mast, "Shrouds")
	# Ship space. The tops are on the top's collar, under its platform and above the course yard,
	# and far enough forward that no rope touches the yard on its way down.
	var upper_z: Array[float] = [-0.4, -0.33, -0.26]
	var lower_z: Array[float] = [-1.15, -0.55, -0.2]
	for side in [-1.0, 1.0]:
		var tops: Array[Vector3] = []
		var hull: Array[Vector3] = []
		for i in 3:
			tops.append(MAST_AT + Vector3(side * 0.25, 5.05 + MAIN_LIFT, upper_z[i]))
			hull.append(_hull_edge(MAST_AT.z + lower_z[i], side))
		_ratlines(shrouds, tops, _shroud_side(shrouds, tops, hull, Vector3(side, 0.0, 0.0), false))


## A node under `mast` whose own space is the ship's, for rigging laid out in ship space.
func _rigging_node(mast: Node3D, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.transform = mast.transform.affine_inverse()
	node.set_meta("set_up", [])
	mast.add_child(node)
	return node


## Ratlines across three shrouds, every 0.42 m down from `tops` to `ends`.
func _ratlines(parent: Node3D, tops: Array[Vector3], ends: Array[Vector3]) -> void:
	var rope := _flat(Color(0.45, 0.34, 0.22))
	var steps := int(tops[0].distance_to(ends[0]) / 0.42)
	for s in range(1, steps):
		var t := float(s) / float(steps)
		for i in tops.size() - 1:
			_rope(parent, tops[i].lerp(ends[i], t), tops[i + 1].lerp(ends[i + 1], t), 0.012, rope)


## Where the hull's outer face is at the deck's edge, `z` along the ship on `side` (+1 starboard),
## and which way is out from it: off the rail's line (RAIL_PATH, the middle of the hull's 0.2 m
## wall top), 0.1 m outboard. Its y is the weather deck's.
func _hull_edge(z: float, side: float) -> Vector3:
	var edge := _outline_at(RAIL_PATH, z)
	var at: Vector2 = edge[0] + (edge[1] as Vector2) * 0.1
	return Vector3(side * at.x, DECK_Y, at.y)


## Which way is out from the hull at `z` on `side`, flat.
func _hull_out(z: float, side: float) -> Vector3:
	var out: Vector2 = _outline_at(RAIL_PATH, z)[1]
	return Vector3(side * out.x, 0.0, out.y)


## The point `z` along a starboard outline of (x, z) points, and its outward normal there.
func _outline_at(outline: Array, z: float) -> Array:
	for i in outline.size() - 1:
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[i + 1]
		if (z >= a.y and z <= b.y) or i == outline.size() - 2:
			var t := clampf((z - a.y) / (b.y - a.y), 0.0, 1.0) if absf(b.y - a.y) > 0.0001 else 0.0
			var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
			if normal.x < 0.0:
				normal = -normal
			return [a.lerp(b, t), normal]
	return [outline[0], Vector2.RIGHT]


## One side's ropes set up to a single channel: rope `i` from `tops[i]` down to a foot standing
## out along `out` from `hull[i]`, a point on the hull's outer face at the edge of the deck whose
## rail the channel stands above (the weather deck, or on the castle, `on_castle`, the
## quarterdeck). The channel runs along the hull through the first and last of them. Returns
## where each rope meets its upper deadeye, and lists every rope on `parent`'s "set_up" meta, in
## ship space.
func _shroud_side(parent: Node3D, tops: Array[Vector3], hull: Array[Vector3], out: Vector3, on_castle: bool) -> Array[Vector3]:
	var rope := _flat(Color(0.45, 0.34, 0.22))
	var iron := _flat(Color(0.22, 0.22, 0.24))
	var timber := _rail_profile("wale", _flat(Color(0.45, 0.28, 0.14)))["material"] as Material
	var side := signf(out.x)
	var deck_y := (QUARTERDECK_Y if on_castle else DECK_Y) + RAIL_HEIGHT + 0.02 + CHANNEL_THICK
	# On the weather deck the channel rises with the rail over the bow's sheer, as a real
	# channel follows the sheer line.
	var first := Vector3(hull[0].x, deck_y + (0.0 if on_castle else bow_sheer(hull[0].z)), hull[0].z)
	var last := Vector3(hull[hull.size() - 1].x, deck_y + (0.0 if on_castle else bow_sheer(hull[hull.size() - 1].z)), hull[hull.size() - 1].z)
	_channel(parent, first, last, out, CHANNEL_OUT, timber, "Channel%s" % ("Starboard" if side > 0.0 else "Port"))
	var ends: Array[Vector3] = []
	var listed: Array = parent.get_meta("set_up")
	for i in tops.size():
		# On the channel's line, which runs straight from its first foot to its last.
		var t := (hull[i].z - first.z) / (last.z - first.z) if absf(last.z - first.z) > 0.001 else 0.0
		var foot := Vector3(hull[i].x, lerpf(first.y, last.y, t), hull[i].z) + out * (CHANNEL_OUT - 0.08)
		var plate_end: Vector3
		if on_castle:
			# On the trim's top, near its outer edge.
			plate_end = Vector3(hull[i].x, CASTLE_TRIM_Y + 0.1, hull[i].z) + out * 0.15
		else:
			var wale: Vector2 = _outline_at(WALE_STARBOARD if side > 0.0 else _mirrored(WALE_PORT), hull[i].z)[0]
			plate_end = Vector3(side * absf(wale.x), WALE_Y + 0.15, wale.y) + out * 0.03
		var label := "%s%d" % ["Starboard" if side > 0.0 else "Port", i]
		var strop := _set_up(parent, tops[i], foot, plate_end, label, rope, iron)
		ends.append(strop)
		listed.append({"top": tops[i], "strop": strop, "foot": foot, "plate_end": plate_end, "out": out,
				"hull": Vector3(hull[i].x, foot.y, hull[i].z), "on_castle": on_castle})
	return ends


## The port wale outline as a starboard one: x made positive.
func _mirrored(outline: Array) -> Array:
	var flipped := []
	for p in outline:
		flipped.append(Vector2(absf((p as Vector2).x), (p as Vector2).y))
	return flipped


## A channel: a plank `width` wide standing out from the hull's side along `out`, from `a` to `b`
## (points on the hull's outer face at its top), and 0.25 m past each.
func _channel(parent: Node3D, a: Vector3, b: Vector3, out: Vector3, width: float, material: Material, channel_name: String) -> void:
	var run := (b - a).normalized() if a.distance_to(b) > 0.01 else out.cross(Vector3.UP).normalized()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(a.distance_to(b) + 0.5, CHANNEL_THICK, width)
	var node := MeshInstance3D.new()
	node.name = channel_name
	node.mesh = mesh
	node.material_override = material
	node.basis = Basis(run, Vector3.UP, run.cross(Vector3.UP))
	node.position = (a + b) * 0.5 + out * width * 0.5 - Vector3.UP * CHANNEL_THICK * 0.5
	parent.add_child(node)


## One rope set up to a channel, in `parent`'s space: from `top` down to its upper deadeye, a
## lanyard to the lower deadeye standing on the channel at `foot`, and an iron chain plate from
## that down to `plate_end` on the hull. The deadeyes lie in the rope's line, faces fore and aft.
## Returns the upper deadeye's strop, where the rope ends.
func _set_up(parent: Node3D, top: Vector3, foot: Vector3, plate_end: Vector3, label: String, rope: Material, iron: Material) -> Vector3:
	var up := (top - foot).normalized()
	var along := (Vector3.BACK - up * up.dot(Vector3.BACK)).normalized()
	var lower := Node3D.new()
	lower.name = "LowerDeadeye" + label
	# Upside down: its strop on the chain plate, its body up the rope.
	lower.basis = Basis(along, -up, along.cross(-up))
	lower.position = foot
	parent.add_child(lower)
	_fit_model(lower, RIGGING + "deadeye.glb")
	var lanyard := foot + up * 0.35
	var strop := lanyard + up * (DEADEYE_LANYARD + 0.35)
	var upper := Node3D.new()
	upper.name = "Deadeye" + label
	upper.basis = Basis(along, up, along.cross(up))
	upper.position = strop
	parent.add_child(upper)
	_fit_model(upper, RIGGING + "deadeye.glb")
	_rope(parent, lanyard, lanyard + up * DEADEYE_LANYARD, 0.012, rope)
	_rope(parent, strop, top, 0.02, rope)
	_rope(parent, foot, plate_end, 0.018, iron)
	return strop


## The sails' feet made fast (MAIN_SHEET_Z and the rest): a block at each course clew, a sheet
## aft and a tack forward from it, belayed to the rail's handrail (the fore tack to its
## cathead); a block at the jib's clew and a sheet from it down to each side's rail. Listed on
## the node's "sheets" meta, in ship space, for the tests. The topsails' feet are laced to the
## yards below them and need none.
func _build_sheets() -> void:
	var old := get_node_or_null("Sheets")
	if old != null:
		old.free()
	var sheets := Node3D.new()
	sheets.name = "Sheets"
	sheets.set_meta("sheets", [])
	add_child(sheets)
	var main := get_node_or_null("Sail")
	var fore := get_node_or_null("ForeCourse")
	var jib := get_node_or_null("Jib")
	for side in [-1.0, 1.0]:
		if main != null:
			var clew := _clew(main, side)
			_sheet(sheets, clew, _rail_top(MAIN_SHEET_Z, side), "rail")
			_sheet(sheets, clew, _rail_top(MAIN_TACK_Z, side), "rail")
		if fore != null:
			var clew := _clew(fore, side)
			_sheet(sheets, clew, _rail_top(FORE_SHEET_Z, side), "rail")
			# On the cathead's top, where it stands out over the bow, 1.2 m along it.
			var along := Vector3(side * cos(deg_to_rad(CATHEAD_YAW)), 0.0, -sin(deg_to_rad(CATHEAD_YAW)))
			_sheet(sheets, clew, Vector3(side * CATHEAD_AT.x, CATHEAD_AT.y, CATHEAD_AT.z) + along * 1.2, "cathead")
		if jib != null:
			_sheet(sheets, JIB_CLEW, _rail_top(JIB_SHEET_Z, side), "rail")
	for sail in [main, fore]:
		if sail != null:
			for side in [-1.0, 1.0]:
				_clew_block(sheets, _clew(sail, side))
	if jib != null:
		_clew_block(sheets, JIB_CLEW)


## The stays, which hold the masts forward as the shrouds hold them sideways: the main topmast
## stay from the main topmast's head, just above its topsail yard, forward to the fore topmast,
## just under its topsail foot yard, crossing the fore top's rail ring between two of its posts
## on the way; the fore topmast stay from the fore topmast's head, above its
## topsail yard, down to the bowsprit's tip, above the jib's luff, as in the reference. Both on
## the centreline, forward of the sails, which hang aft of their yards. Listed on the node's
## "ropes" meta, in ship space, for the tests. No collision, like the rest of the rigging.
func _build_stays() -> void:
	var old := get_node_or_null("Stays")
	if old != null:
		old.free()
	if get_node_or_null("Mast") == null or get_node_or_null("Foremast") == null:
		return
	var stays := Node3D.new()
	stays.name = "Stays"
	stays.set_meta("ropes", [])
	add_child(stays)
	# The topmast is 0.18 m in radius at MAST_AT; its head is 3 m above the lower mast's.
	var main_head := MAST_AT + Vector3(0.0, 8.4 + MAIN_LIFT, -0.18)
	# Above the fore top's floor, which it would pass through lower down, and low enough under the
	# topsail foot yard; rising aft, it is 0.14 m over the rail ring where it crosses it.
	var fore_foot := FOREMAST_AT + Vector3(0.0, MAIN_LOWER + 1.0, 0.18) * FORE_SCALE
	var fore_head := FOREMAST_AT + Vector3(0.0, 8.4 + MAIN_LIFT, -0.18) * FORE_SCALE
	_stay(stays, "MainTopmastStay", main_head, fore_foot)
	if get_node_or_null("Bowsprit") != null:
		_stay(stays, "ForeTopmastStay", fore_head, _along_bowsprit(BOWSPRIT_LENGTH - 0.1))


func _stay(parent: Node3D, label: String, from: Vector3, to: Vector3) -> void:
	_rope(parent, from, to, 0.025, _flat(Color(0.45, 0.34, 0.22)))
	var entries: Array = parent.get_meta("ropes")
	entries.append({"name": label, "from": from, "to": to})


## A brace from each course yard's arm, just outside its block, aft and down to the rail
## (MAIN_BRACE_Z, FORE_BRACE_Z). Listed on the node's "ropes" meta, in ship space, for the tests.
func _build_braces() -> void:
	var old := get_node_or_null("Braces")
	if old != null:
		old.free()
	var braces := Node3D.new()
	braces.name = "Braces"
	braces.set_meta("ropes", [])
	add_child(braces)
	var rope := _flat(Color(0.45, 0.34, 0.22))
	for side in [-1.0, 1.0]:
		for spec in [["Mast", MAST_AT, 1.0, MAIN_BRACE_Z, QUARTERDECK_Y], ["Foremast", FOREMAST_AT, FORE_SCALE, FORE_BRACE_Z, DECK_Y]]:
			if get_node_or_null(spec[0]) == null:
				continue
			var at: Vector3 = spec[1]
			var scale: float = spec[2]
			var arm := at + Vector3(side * (YARD_BLOCKS[0][1] + 0.1), 4.6 + MAIN_LIFT, 0.0) * scale
			var to := _rail_top(spec[3], side, spec[4])
			_rope(braces, arm, to, 0.015, rope)
			var entries: Array = braces.get_meta("ropes")
			entries.append({"name": "%sBrace%s" % [spec[0], "Starboard" if side > 0.0 else "Port"], "from": arm, "to": to})


## The foot corner of a sail on `side` (+1 starboard).
func _clew(sail: Node, side: float) -> Vector3:
	var from: Vector3 = sail.get("_foot_from")
	var to: Vector3 = sail.get("_foot_to")
	return to if (to.x - from.x) * side > 0.0 else from


## The top of the rail's handrail `z` along the ship, on `side`, on the rail round `deck`.
func _rail_top(z: float, side: float, deck := DECK_Y) -> Vector3:
	var at: Vector2 = _outline_at(RAIL_PATH, z)[0]
	var sheer := bow_sheer(z) if deck == DECK_Y else 0.0
	return Vector3(side * at.x, deck + sheer + HANDRAIL_TOP, z)


## How far the hull's wall top stands above the weather deck `z` along the ship: nothing aft of
## BOW_SHEER_FROM, rising on a curve that starts level to BOW_SHEER at the knightheads.
static func bow_sheer(z: float) -> float:
	var stem: float = (RAIL_PATH[0] as Vector2).y
	var t := clampf((BOW_SHEER_FROM - z) / (BOW_SHEER_FROM - stem), 0.0, 1.0)
	return BOW_SHEER * t * t


## `line`, on the weather deck, with a point every 0.25 m where it rises with the bow's sheer, and
## each point lifted by it.
func _sheer_line(line: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = [line[0] + Vector3.UP * bow_sheer(line[0].z)]
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var steps := ceili(a.distance_to(b) / 0.25) if minf(a.z, b.z) < BOW_SHEER_FROM else 1
		for k in range(1, steps + 1):
			var p := a.lerp(b, float(k) / steps)
			out.append(Vector3(p.x, a.y + bow_sheer(p.z), p.z))
	return out


## A single block hung from a clew: its strop at the clew, 0.35 m long below it.
func _clew_block(parent: Node3D, clew: Vector3) -> void:
	var block := Node3D.new()
	block.name = "Block%d" % parent.get_child_count()
	block.position = clew
	parent.add_child(block)
	_fit_model(block, RIGGING + "block_single.glb")


## One sheet or tack from the block at `clew` down to `to`, on the `onto` it is belayed to.
func _sheet(parent: Node3D, clew: Vector3, to: Vector3, onto: String) -> void:
	var from := clew - Vector3(0.0, 0.33, 0.0)
	_rope(parent, from, to, 0.015, _flat(Color(0.45, 0.34, 0.22)))
	var entries: Array = parent.get_meta("sheets")
	entries.append({"clew": clew, "from": from, "to": to, "onto": onto})


## The flag on a short staff above the topmast, held on it by its three rings, its fly out
## along +X; _fly_flag turns it downwind, the rings turning round the staff.
func _build_flag() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	if mast == null or mast.get_node_or_null("Flag") != null:
		return
	var head := MAIN_LOWER + 3.0
	_spar(mast, head + FLAGSTAFF_HEIGHT * 0.5, FLAGSTAFF_RADIUS, FLAGSTAFF_RADIUS, FLAGSTAFF_HEIGHT, _flat(Color(0.55, 0.36, 0.18)))
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.position = Vector3(0.0, head + FLAGSTAFF_HEIGHT - 0.03, 0.0)
	mast.add_child(flag)
	# tools/rig_flag.py set the model up for this: picture upright, fly out along +X, origin on
	# its rings' line at the flag's top, so the staff's axis runs through all three rings.
	if _fit_model(flag, RIGGING + "flag_rigged.glb"):
		# Seen from both sides: the model is a single sheet.
		for node in _descendants(flag):
			var mesh_node := node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_surface_override_material(surface) as BaseMaterial3D
				if material != null:
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fly_flag()


## Turns the flag's fly downwind, with the breeze the sails are blown by.
func _fly_flag() -> void:
	var flag := get_node_or_null("Mast/Flag") as Node3D
	var wind := get_tree().get_first_node_in_group("wind") if is_inside_tree() else null
	if flag == null or wind == null:
		return
	var down: Vector3 = flag.get_parent_node_3d().global_basis.inverse() * (wind.get("direction") as Vector3)
	if Vector2(down.x, down.z).length_squared() < 0.0001:
		return
	# Turning by a about Y sends the fly's +X to (cos a, 0, -sin a).
	flag.rotation.y = atan2(-down.z, down.x)


func _rope(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	var y := span / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = (a + b) * 0.5
	node.basis = Basis(x, y, x.cross(y))
	node.material_override = material
	parent.add_child(node)


## Where the gunports are along the hull's side: gun_port_count of them spread evenly along
## the gun deck's straight wall, the first and last GUN_PORT_MARGIN in from its ends.
func gun_port_z() -> Array[float]:
	var spots: Array[float] = []
	for k in gun_port_count:
		var t := 0.5 if gun_port_count == 1 else float(k) / (gun_port_count - 1)
		spots.append(lerpf(GUN_WALL_FORE_Z + GUN_PORT_MARGIN, GUN_WALL_AFT_Z - GUN_PORT_MARGIN, t))
	return spots


## Everything that goes with the gunports, under one node so a change to them rebuilds it all
## in step: the gun deck's side walls with a hole at every port, a frame on each, and a
## cannon run out through each. The ports stand open with no lid, as the reference's do: the
## model's lid, swung up, stood out from the side like a shelf over every port.
func _build_gun_ports() -> void:
	if get_node_or_null("GunPorts") != null:
		return
	var ports := Node3D.new()
	ports.name = "GunPorts"
	add_child(ports)
	var spots := gun_port_z()
	_build_gun_walls(ports, spots)

	# The frame faces +X with its back on the hull, centred on its opening; turned half round
	# it serves the port side. The model's lid is its own node, taken off.
	var frames := Node3D.new()
	frames.name = "Frames"
	ports.add_child(frames)
	var guns := Node3D.new()
	guns.name = "Guns"
	ports.add_child(guns)
	for k in spots.size():
		for side in [1.0, -1.0]:
			var port := Node3D.new()
			port.name = "Port%s%d" % ["Starboard" if side > 0.0 else "Port", k]
			port.position = Vector3(side * (BEAM * 0.5 + gun_port_offset), GUN_PORT_Y, spots[k])
			port.rotation_degrees.y = 0.0 if side > 0.0 else 180.0
			frames.add_child(port)
			if _fit_model(port, HULL_PARTS + "gunport_lid.glb"):
				var lid := port.find_child("lid", true, false)
				if lid != null:
					lid.get_parent().remove_child(lid)
					lid.free()
		# On the deck: the model's origin is under its wheels. Muzzle along local -Z and 0.62 m
		# up, level with the port. -90° yaw sends -Z to starboard.
		_gun(guns, Vector3(GUN_OUT_X, GUN_DECK_Y, spots[k]), -PI * 0.5, "Starboard%d" % k)
		_gun(guns, Vector3(-GUN_OUT_X, GUN_DECK_Y, spots[k]), PI * 0.5, "Port%d" % k)


func _rebuild_gun_ports() -> void:
	var old := get_node_or_null("GunPorts")
	if old == null:
		return
	# Out of the way now, gone at the end of the frame.
	old.name = "GunPortsOld"
	remove_child(old)
	old.queue_free()
	_build_gun_ports()


## The gun deck's side walls along the straight run of the hull, both sides, 0.2 m thick from
## the gun deck to the weather deck, with a hole at every port: the outer and inner faces
## round the holes, and each hole's sill, lintel and sides. Their ends meet the kit's bow and
## stern walls, their tops are the hull's own, and their feet stand on the tier below. Planked
## with the hull's own material and UV rule (tools/texture_kit.py: along the hull u = z/2,
## up it v = -y/2.6; flat faces u = z/2, v = x/2.6; faces across the hull u = x/2), so the
## planks run on from the kit's walls. They collide exactly, like the hull.
func _build_gun_walls(parent: Node3D, spots: Array[float]) -> void:
	var low := GUN_DECK_Y
	var high := DECK_Y
	var sill := GUN_PORT_Y - GUN_PORT_SIZE.y * 0.5
	var head := GUN_PORT_Y + GUN_PORT_SIZE.y * 0.5
	var half := GUN_PORT_SIZE.x * 0.5
	# Solid wall between the holes along the port band, as (from, to) in z.
	var gaps: Array[Vector2] = []
	var from := GUN_WALL_FORE_Z
	for z in spots:
		gaps.append(Vector2(from, z - half))
		from = z + half
	gaps.append(Vector2(from, GUN_WALL_AFT_Z))
	var material := _hull_wood()
	for side in [1.0, -1.0]:
		var wall := SurfaceTool.new()
		wall.begin(Mesh.PRIMITIVE_TRIANGLES)
		var outer: float = side * BEAM * 0.5
		var inner: float = side * GUN_WALL_INNER_X
		for x in [outer, inner]:
			var facing := Vector3(signf(x - side * (BEAM * 0.25 + GUN_WALL_INNER_X * 0.5)), 0.0, 0.0)
			_wall_quad(wall, Vector3(x, low, GUN_WALL_FORE_Z), Vector3(x, sill, GUN_WALL_AFT_Z), facing)
			_wall_quad(wall, Vector3(x, head, GUN_WALL_FORE_Z), Vector3(x, high, GUN_WALL_AFT_Z), facing)
			for gap in gaps:
				if gap.y - gap.x > 0.001:
					_wall_quad(wall, Vector3(x, sill, gap.x), Vector3(x, head, gap.y), facing)
		for z in spots:
			_wall_quad(wall, Vector3(inner, sill, z - half), Vector3(outer, sill, z + half), Vector3.UP)
			_wall_quad(wall, Vector3(inner, head, z - half), Vector3(outer, head, z + half), Vector3.DOWN)
			_wall_quad(wall, Vector3(inner, sill, z - half), Vector3(outer, head, z - half), Vector3.BACK)
			_wall_quad(wall, Vector3(inner, sill, z + half), Vector3(outer, head, z + half), Vector3.FORWARD)
		var node := MeshInstance3D.new()
		node.name = "WallStarboard" if side > 0.0 else "WallPort"
		node.mesh = wall.commit()
		node.layers = 1 | (1 << 19)
		if material != null:
			node.material_override = material
		parent.add_child(node)
		node.create_trimesh_collision()


## The hull's own planked material (its toon copy), or null without the hull.
func _hull_wood() -> Material:
	var material: Material = null
	var hull := get_node_or_null("Model")
	if hull != null:
		for node in _descendants(hull):
			var mesh_node := node as MeshInstance3D
			if mesh_node == null or mesh_node.mesh == null:
				continue
			for surface in mesh_node.mesh.get_surface_count():
				if mesh_node.mesh.surface_get_material(surface) != null and mesh_node.mesh.surface_get_material(surface).resource_name == "wood":
					material = mesh_node.get_surface_override_material(surface)
	return material


## The bow's raised side (bow_sheer): a wall on the hull's wall top each side, 0.2 m thick like
## it, its outer face flush with the hull's, from BOW_SHEER_FROM to the knighthead, its top
## rising with the sheer and the rail standing on it. Its inner and outer faces, its top and its
## end at the knighthead, planked with the hull's material; planks run along it (u is metres
## along it over 2, v height over 2.6, as the hull's side). It collides exactly, under the rail.
func _build_bow_bulwark() -> void:
	var old := get_node_or_null("BowBulwark")
	if old != null:
		old.free()
	var path: Array[Vector3] = [Vector3(RAIL_PATH[0].x, DECK_Y, RAIL_PATH[0].y)]
	for i in range(1, RAIL_PATH.size()):
		var p: Vector2 = RAIL_PATH[i]
		if p.y >= BOW_SHEER_FROM:
			var q: Vector2 = RAIL_PATH[i - 1]
			path.append(Vector3(lerpf(q.x, p.x, (BOW_SHEER_FROM - q.y) / (p.y - q.y)), DECK_Y, BOW_SHEER_FROM))
			break
		path.append(Vector3(p.x, DECK_Y, p.y))
	path = _sheer_line(path)
	var node := MeshInstance3D.new()
	node.name = "BowBulwark"
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var reach := 0.0
		var rows: Array = []
		for i in path.size():
			var p := Vector3(side * path[i].x, path[i].y, path[i].z)
			if i > 0:
				reach += path[i].distance_to(path[i - 1])
			var n := _hull_out(p.z - 0.001, side) if i == 0 else _hull_out(p.z + 0.001, side)
			if i > 0 and i < path.size() - 1:
				n = (_hull_out(p.z - 0.001, side) + _hull_out(p.z + 0.001, side)).normalized()
			rows.append({"outer": p + n * 0.1, "inner": p - n * 0.1, "n": n, "top": p.y, "u": reach / 2.0})
		for i in rows.size() - 1:
			var a: Dictionary = rows[i]
			var b: Dictionary = rows[i + 1]
			# Each face from a little down in the hull's wall top, so no seam shows at the deck.
			for face in [["outer", 1.0], ["inner", -1.0]]:
				var normal: Vector3 = ((a["n"] as Vector3) + (b["n"] as Vector3)).normalized() * face[1]
				var a0: Vector3 = a[face[0]]
				var b0: Vector3 = b[face[0]]
				_bulwark_quad(wall, [Vector3(a0.x, DECK_Y - 0.02, a0.z), Vector3(b0.x, DECK_Y - 0.02, b0.z), b0, a0],
						[Vector2(a["u"], (DECK_Y - 0.02) / -2.6), Vector2(b["u"], (DECK_Y - 0.02) / -2.6), Vector2(b["u"], b0.y / -2.6), Vector2(a["u"], a0.y / -2.6)], normal)
			var ai: Vector3 = a["inner"]
			var ao: Vector3 = a["outer"]
			var bi: Vector3 = b["inner"]
			var bo: Vector3 = b["outer"]
			_bulwark_quad(wall, [ai, bi, bo, ao], [Vector2(a["u"], ai.x / 2.6), Vector2(b["u"], bi.x / 2.6), Vector2(b["u"], bo.x / 2.6), Vector2(a["u"], ao.x / 2.6)], Vector3.UP)
		# Its end at the knighthead, facing forward along the rail.
		var end: Dictionary = rows[0]
		var ei: Vector3 = end["inner"]
		var eo: Vector3 = end["outer"]
		var ahead := (Vector3(rows[0]["outer"]) - Vector3(rows[1]["outer"]))
		ahead.y = 0.0
		_bulwark_quad(wall, [Vector3(ei.x, DECK_Y - 0.02, ei.z), Vector3(eo.x, DECK_Y - 0.02, eo.z), eo, ei],
				[Vector2(ei.x / 2.0, (DECK_Y - 0.02) / -2.6), Vector2(eo.x / 2.0, (DECK_Y - 0.02) / -2.6), Vector2(eo.x / 2.0, eo.y / -2.6), Vector2(ei.x / 2.0, ei.y / -2.6)], ahead.normalized())
	node.mesh = wall.commit()
	node.layers = 1 | (1 << 19)
	var material := _hull_wood()
	if material != null:
		node.material_override = material
	add_child(node)
	node.create_trimesh_collision()


## A four-cornered face through `corners` in order round it, with their `uvs`, facing `normal`.
## Wound clockwise from the front, as Godot draws front faces.
func _bulwark_quad(into: SurfaceTool, corners: Array, uvs: Array, normal: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	if (b - a).cross(c - a).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		into.set_normal(normal)
		into.set_uv(uvs[i])
		into.add_vertex(corners[i])


## A flat rectangle between opposite corners `a` and `b` (they share one coordinate), facing
## `normal`, with the hull's UVs. Wound clockwise from the front, as Godot draws front faces.
func _wall_quad(into: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var corners: Array[Vector3]
	if is_equal_approx(a.x, b.x):
		corners = [a, Vector3(a.x, a.y, b.z), b, Vector3(a.x, b.y, a.z)]
	elif is_equal_approx(a.y, b.y):
		corners = [a, Vector3(b.x, a.y, a.z), b, Vector3(a.x, a.y, b.z)]
	else:
		corners = [a, Vector3(b.x, a.y, a.z), b, Vector3(a.x, b.y, a.z)]
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
		corners.reverse()
	for i in [0, 1, 2, 0, 2, 3]:
		var p := corners[i]
		var uv: Vector2
		if absf(normal.y) >= 0.7071:
			uv = Vector2(p.z / 2.0, p.x / 2.6)
		elif absf(normal.x) >= absf(normal.z):
			uv = Vector2(p.z / 2.0, -p.y / 2.6)
		else:
			uv = Vector2(p.x / 2.0, -p.y / 2.6)
		into.set_normal(normal)
		into.set_uv(uv)
		into.add_vertex(p)


func _gun(parent: Node3D, at: Vector3, yaw: float, side: String) -> void:
	var gun := CannonScene.instantiate() as Node3D
	gun.name = "Cannon%s" % side
	gun.position = at
	gun.rotation.y = yaw
	gun.set("sit_on_ground", false)
	# A gun in a hull is a different weapon from the one on the hill, and these four numbers
	# are the whole difference. It swings inside its port rather than anywhere, it cannot be
	# lobbed, and it looks out through the opening instead of over the player's shoulder - so
	# a broadside is aimed by turning the ship and fired on timing, not by judging an arc.
	gun.set("traverse_limit", 22.0)
	gun.set("min_elevation", 0.0)
	gun.set("max_elevation", 14.0)
	gun.set("rest_elevation", 3.0)
	gun.set("first_person", true)
	parent.add_child(gun)


func _spar(parent: Node3D, y: float, bottom: float, top: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3(0.0, y, 0.0)
	node.material_override = material
	parent.add_child(node)


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation_degrees.x = 90.0
	node.material_override = material
	parent.add_child(node)


func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return material


## True when every sample under the hull has enough water for the draft.
func _afloat(origin: Vector3, aft: Vector3, terrain: Node, sea: float) -> bool:
	var starboard := Vector3.UP.cross(aft).normalized()
	var needed := DRAFT + CLEARANCE
	var along_hull: Array[float] = [0.4, 3.0, 6.0, 9.0, 12.0, 13.6]
	var across_hull: Array[float] = [-BEAM * 0.42, 0.0, BEAM * 0.42]
	for z in along_hull:
		for x in across_hull:
			var p := origin + aft * z + starboard * x
			if sea - terrain.height_at(p.x, p.z) < needed:
				return false
	return true


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
