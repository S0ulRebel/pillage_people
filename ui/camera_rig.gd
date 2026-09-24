extends Node3D
## Bird's-eye chase camera: sits high behind the player, follows smoothly, and never clips into
## the terrain (SpringArm3D does that part).
##
## Orbits with Q/E or by holding the middle mouse button and moving sideways; tilts with the
## same middle-button drag up and down; zooms on the wheel.
##
## The spring arm casts from this pivot back toward the camera on the physics step. Following
## in _process let the pivot lag a metre behind, so walking back toward the camera stepped
## the captain into that cast. The arm treated him as a wall, collapsed, and the view dropped
## onto the beach with him behind it.

@export var follow_speed := 8.0
@export var orbit_speed := 2.0
@export var zoom_step := 2.0
@export var min_distance := 6.0
@export var max_distance := 40.0
@export var pitch_degrees := -55.0   ## -90 is straight down, -15 is nearly level
@export var min_pitch_degrees := -85.0
## Raised from 8. While dragging up meant looking DOWN, the up-stop was nearly unreachable and
## 8 degrees was plenty; now that up means up, it is the stop you meet every time you look at
## the horizon, and 8 degrees felt like the control had broken.
@export var max_pitch_degrees := 28.0
## Was the R/F keyboard tilt, which the middle-button drag does better and which was holding
## on to the R key. Kept as a setting because a gamepad stick will want it back.
@export var pitch_speed := 60.0

@export_group("Spyglass")
## Held to the captain's eye. The camera goes to his head and the field of view narrows; the
## wheel then magnifies instead of pulling the camera back.
##
## FOV rather than the spring arm, which is what the wheel normally drives. Shortening the arm
## moves the camera CLOSER - it clips through terrain and magnifies nothing. Narrowing the
## angle is what a telescope does, and it costs nothing.
@export var glass_fov := 22.0
@export var glass_zoom_min := 1.0
@export var glass_zoom_max := 5.0
@export var glass_zoom_step := 0.5
## Where his eye is, above the node origin at his feet.
@export var eye_height := 1.6
## How wide the iris sits while glassing. Not shut, or there is nothing to look through.
@export var glass_iris := 0.62
@export var glass_seconds := 0.35
## Tilt limits while glassing. The glass wants to see things level with you and slightly above,
## so it reaches higher than the chase camera does.
@export var glass_min_pitch := -70.0
@export var glass_max_pitch := 25.0
## REMOVED: glass_invert_pitch.
##
## It flipped the tilt while the glass was up, so that the chase camera orbited (drag up, swing
## up and over, end up looking down) while the glass turned like a head (drag up, look up). Both
## readings are defensible and the argument for them is why it lasted. What killed it is that
## the two flags multiplied: fixing the chase camera by setting invert_mouse_pitch broke the
## glass, so there was no combination that gave up-means-up in both. And touch consulted
## neither, so the glass already behaved differently on an iPad than on a mouse.
##
## One rule now: see tilt().

@export_group("Diving")
## Whether the camera goes under with him when he dives. Off, it stays the chase camera it
## always was: eighteen metres up, looking down at the water he disappeared into. Switched
## off mid-dive it comes back up at once; switched on mid-dive it waits for the next dive.
@export var follow_dives := true
## How far under the surface the camera keeps itself while he is diving.
@export var dive_camera_depth := 1.0
## How far behind him it sits under water. Much nearer than the chase distance: the fog is
## half strength at eight metres, and at eight metres he was a smudge in the middle of it.
@export var dive_distance := 6.0
## How quickly the view eases into a dive and back out of it, per second.
@export var dive_ease := 6.0
## Sea level, set by main.gd from the terrain so the rig and the captain cannot disagree.
@export var water_level := 0.0
## How near the camera may be pulled in while diving. Looking down under water shortens the arm
## rather than levelling the view - see _dive_length - and this is where that stops: nearer than
## this and the picture is the back of his head.
@export var dive_min_distance := 1.5
## Where the arm hangs from while diving, above his own origin. The chase camera hangs it 2.1 m
## up so the view looks over his head, and under water that offset is the single biggest thing
## standing between him and looking down: the camera must stay UNDER the sea, and a pivot 2.1 m
## above him has already spent more than the whole depth of a shallow dive - at two metres down
## it put the arm's own origin above the water, so the only way to get the camera wet was to
## swing it below him, and asking to look down snapped the view 47 degrees UP instead.
##
## Every metre here comes straight out of the look-down near the surface. Hence nought.
@export var dive_arm_height := 0.0
## Tilt limits while diving. Wider than the chase camera's at BOTH ends, and for the reason the
## glass reaches higher than the chase does: under water the two things worth looking at are the
## surface above you and the bed below, and the chase camera's 28 degrees up is a control that
## stops working just as you start to use it.
@export var dive_min_pitch := -85.0
@export var dive_max_pitch := 60.0

@export_group("Mouse look")
## Hold the middle button and move to swing the camera round and tilt it. The left button is
## deliberately left alone - it belongs to whatever the player is doing in the world. It used
## to orbit the camera, but only by accident: the project had emulate_touch_from_mouse on, so
## every left-drag arrived at the iPad controls as a finger dragging across the screen.
@export var mouse_orbit_speed := 0.006   ## radians per pixel of horizontal movement
@export var mouse_pitch_speed := 0.12    ## degrees per pixel of vertical movement
## Drag up to look UP. This is the project convention - see tilt() - and this flag is the
## player's preference switch, not a per-mode correction: it flips every mode together.
@export var invert_mouse_pitch := false

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D
var _target: Node3D
## The iris drawn while glassing. Separate from the one main.gd uses for openings and deaths:
## that one is opaque and covers everything, this one has to be looked through.
var glass: Spyglass
var _glassing := false
var _gun: Node3D = null
var _length_before_gun := 0.0
var _magnification := 1.0
var _wide_fov := 75.0
var _rested_length := 18.0
## Set by main.gd on touch devices.
var touch_controls: CanvasLayer
## True while the middle button is held.
var _mouse_looking := false
var _helm_view := false
var _length_before_helm := 18.0
var _diving := false
var _length_before_dive := 18.0
## Where the arm is easing to at either end of a dive, and whether it still is. It stops once
## it is there, so the wheel has the arm back while he is under.
var _dive_length_target := 18.0
var _settling_length := false
## The length the ease wrote last tick. The arm reading anything else means someone else -
## the wheel, the glass, a gun, the helm - has taken it, and the ease lets go.
var _eased_length := -1.0
## True from a dive's start until the tilt has eased down to the clamp. After that a rising
## clamp is taken at once, not eased - see _physics_process.
var _entering_dive := false
## How long the arm would be under water with nothing in the way, and the capped length last
## written from it. Same idiom as _eased_length: a spring_length we did not write is someone
## else's - the wheel's - and is taken as the new reach.
var _dive_reach := -1.0
var _dive_capped := -1.0
## The tilt to hand back to the chase camera when he surfaces. See set_diving.
var _pitch_before_dive := -55.0
## Where the arm hangs from with the chase camera, read from the scene rather than assumed.
var _arm_rest_y := 2.1


func _ready() -> void:
	_arm_rest_y = _arm.position.y
	_apply_pitch()
	_arm.spring_length = 18.0
	_arm.margin = 0.4
	if _camera != null:
		_wide_fov = _camera.fov


## Raises or lowers the glass. Returns what it did, so a caller can tell whether anything
## happened without tracking the state itself.
func set_glassing(looking: bool) -> bool:
	if _glassing == looking or _target == null:
		return false
	# No spyglass under water. The glass and the dive each park the arm's length and put it
	# back, and stacked in either order they put back each other's - a dive begun with the
	# glass up surfaced with the camera on the pivot. A dive lowers the glass; the glass
	# refuses while diving.
	if looking and _diving:
		return false
	_glassing = looking
	if looking:
		_rested_length = _arm.spring_length
		_magnification = 1.0
		# Arm to nothing puts the camera on the pivot, and the pivot goes to his head - so the
		# view is from his eye rather than from eighteen metres behind him. Anything else and
		# the iris is drawn over a shot of the back of his own head.
		_arm.spring_length = 0.0
	else:
		_arm.spring_length = _rested_length
	_apply_fov()
	if glass != null:
		if looking:
			glass.to(glass_iris, glass_seconds)
		else:
			# clear(), not close(). Closing takes it to fully black - which is right for a
			# transition and blacks the screen out for a captain simply lowering his glass.
			glass.clear(glass_seconds * 0.6)
	return true


func is_glassing() -> bool:
	return _glassing


## Pulls back while he has the wheel, so the hull and the water ahead are both in frame.
## Take the view to a gun, or give it back.
##
## Two shapes, chosen by the gun: a gun in a hull puts the camera AT the muzzle, which is the
## only useful angle on a gun deck and the one that frames the port. A gun in the open just
## pulls in closer - the shot there is aimed by watching the ground ahead, so the overview has
## to survive; it only tightens so that manning the thing feels like something happened.
func set_gun(gun: Node3D) -> void:
	if gun == _gun or _arm == null:
		return
	if gun != null and _gun == null:
		_length_before_gun = _arm.spring_length
	_gun = gun
	if gun == null:
		_arm.spring_length = _length_before_gun
		return
	var close: bool = gun.get("first_person")
	_arm.spring_length = 0.0 if close else minf(_length_before_gun, 9.0)


func is_gunning() -> bool:
	return _gun != null and is_instance_valid(_gun)


func set_helming(driving: bool) -> void:
	if driving == _helm_view or _arm == null:
		return
	_helm_view = driving
	if driving:
		_length_before_helm = _arm.spring_length
		_arm.spring_length = minf(max_distance, 34.0)
	else:
		_arm.spring_length = _length_before_helm


func _apply_fov() -> void:
	if _camera == null:
		return
	_camera.fov = (glass_fov / _magnification) if _glassing else _wide_fov


## Keeps the tilt inside a range where the camera neither looks up from under the ground nor
## straight down onto the top of the player's head.
## THE CONVENTION: UP MEANS UP.
##
## `up_degrees` is positive when the player asked to look UP - whatever device produced it, and
## whatever mode the camera is in. Every tilt goes through here, so no input path gets to decide
## its own sign.
##
## This exists because the project had four answers to the same question. The mouse tilted one
## way in the chase view and the other way through the glass, on purpose, flipped by two
## exported booleans multiplied together. Touch never consulted either flag, so the same drag on
## an iPad did the opposite of the mouse while glassing. The cannon's barrel disagreed with all
## of them. Each was defensible alone; together they were unlearnable, because the player cannot
## see which of four rules is in force.
##
## The cost of the rule is honest: orbiting a subject by dragging up and over is a real idiom
## and we are giving it up. One rule the hand can learn beats four that are each locally right.
func tilt(up_degrees: float) -> void:
	pitch_degrees += up_degrees
	# Under water the surface can hold the view up off what he is asking for - see _dive_length
	# - and a tilt that would take the ask below that floor is SPENT, not banked. It used to be
	# refused outright, which came to the same thing for the frame it happened on and was wrong
	# by the next one: refusing left pitch_degrees wherever it had already sunk to, and from
	# there every drag up was refused too, because it was still under the floor. Nothing moved
	# on screen again until one single event crossed the whole gap - forty degrees of mouse in
	# one frame. Parked ON the floor instead, up moves the view on the next pixel.
	#
	# Banking it was the other wrong answer, and it is why the refusal was there: unspent tilt
	# was paid the moment he surfaced, the view snapping to wherever it had silently got to.
	# Two floors are deliberately NOT parked on. Not the one in force while the way into a dive
	# is still easing: the arm there is still most of its chase length, so the floor is a
	# transient of a camera that is still arriving, and latching it threw away half the look he
	# dived in with - and near the surface it is wildly positive, so one flick of the mouse
	# swung the view from 55 degrees down to 47 UP in a frame. And never above level, for the
	# same reason: a floor above level means he is within a metre of the surface and the camera
	# has to swing BELOW him to stay wet. That is the shallows talking, not a limit on where he
	# is allowed to look, and it has no business being written into what he asked for.
	if _diving and not _settling_length:
		pitch_degrees = maxf(pitch_degrees, minf(_settled_floor(), 0.0))
	_apply_pitch()


func _apply_pitch() -> void:
	# THREE ranges now. A dive used to borrow the chase camera's, which capped looking up at 28
	# degrees - so the surface, which is the one thing above you down there, was out of reach.
	var lowest := min_pitch_degrees
	var highest := max_pitch_degrees
	if _glassing:
		lowest = glass_min_pitch
		highest = glass_max_pitch
	elif _diving:
		lowest = dive_min_pitch
		highest = dive_max_pitch
	pitch_degrees = clampf(pitch_degrees, lowest, highest)
	# While a dive's way in or out is being eased, the tilt is the ease's to apply: written
	# straight here, one wobble of the mouse mid-ease cut the camera eight metres to where the
	# ease was heading. Any other time a tilt lands at once.
	if not (_settling_length or _entering_dive):
		_arm.rotation_degrees.x = _effective_pitch()


## Goes under with him when his dive starts, and comes back up when it ends. Connected by
## main.gd to the captain's dived signal. Ending is always honoured, so switching
## follow_dives off mid-dive brings the camera back up rather than leaving it clamped.
func set_diving(under: bool) -> void:
	if under == _diving or _arm == null or (under and not follow_dives):
		return
	if under and _glassing:
		set_glassing(false)
	_diving = under
	_entering_dive = under
	if under:
		# The length to come back to is read only when no transition is in flight. A re-dive
		# during the exit ease used to record the half-restored length, and bobbing at the
		# surface ratcheted the chase distance down to the dive distance a tap at a time.
		if not _settling_length:
			_length_before_dive = _arm.spring_length
			_pitch_before_dive = pitch_degrees
		_dive_length_target = minf(_length_before_dive, dive_distance)
		# Nothing has been capped yet, so the first tick of the dive reads the reach afresh
		# instead of taking the last dive's for it.
		_dive_capped = -1.0
	else:
		_dive_length_target = _length_before_dive
		# The tilt is parked and put back exactly as the length is, and for a sharper reason.
		# Under water the surface pushes the tilt about - a look held UP off what he asked for
		# near the surface, and tilt() parks his ask on that floor so the control answers. Both
		# of those are the sea's doing, not his, and carrying them back up ruined the chase
		# camera: surfacing from a shallow dive left the pitch a few degrees ABOVE level, which
		# on an eighteen metre arm is a camera four metres under the sea, looking up at him
		# through it. The dive borrows the tilt; it gives it back.
		pitch_degrees = _pitch_before_dive
	_settling_length = true
	_eased_length = _arm.spring_length
	# A dive reaches higher than the chase camera allows, so its tilt has to be brought back
	# inside the chase range on the way out. Same reason the glass does this.
	_apply_pitch()


func is_diving() -> bool:
	return _diving


## The tilt the arm actually gets: the player's own, except while diving, when it is held no
## higher than keeps the camera under the water. A dive starts with him a metre and a half
## under, and the chase camera eighteen metres up looking down sees a lot of sea and none of
## him; so the camera stays just beneath the surface, level with him or looking a little up
## from below, and takes the player's own tilt back as he goes deeper and there is room for it.
func _effective_pitch() -> float:
	if not _diving or _glassing:
		return pitch_degrees
	# Only the part the shortened arm cannot absorb. The arm comes in first - see _dive_length -
	# and the look is held up for the last of it, when he is so near the surface that even the
	# nearest camera would be out of the water.
	return clampf(maxf(pitch_degrees, _floor_pitch()), dive_min_pitch, dive_max_pitch)


## The lowest the view may go with the camera still under the water. Once the dive has settled
## this barely bites - the arm has already come in for him, see _dive_length - but it is what
## holds the camera under for the whole second the way in is easing, while the arm is still
## most of its chase length.
##
## THE LENGTH THE ARM HAS, not the one the cap would like it to have. Asking _dive_length here
## read a length that had not been applied yet: through the whole entry ease the floor said a
## two metre arm would be fine while the arm was actually eleven, and the camera swam along
## three metres ABOVE the sea. It is also the length the arm REACHED, not the one it was asked
## for - against the crater wall the arm is short, and a short arm at a pitch worked out for a
## long one puts the camera back above the water.
func _floor_pitch() -> float:
	return _floor_for(minf(_arm.spring_length, _arm.get_hit_length()))


## The floor he will HAVE once the arm has finished coming in - see _dive_length. This is the
## one an ask is parked on, and it has to be this one: the arm comes in because he asked to
## look down, so parking the ask on the arm as it stands at that instant would park it at the
## very limit he is asking to get out of, the arm would never come in, and looking down would
## be back to being impossible.
func _settled_floor() -> float:
	return _floor_for(minf(_dive_length(), _arm.get_hit_length()))


## The lowest the view may go with a `length` arm and still leave the camera under the water.
func _floor_for(length: float) -> float:
	var lowest_sine: float = clampf(-_dive_room() / maxf(length, 0.01), -1.0, 1.0)
	return rad_to_deg(asin(lowest_sine))


## Metres between the pivot and the lowest the camera may sit and still be properly under.
## Negative when he is so near the surface that the pivot itself is above that line.
func _dive_room() -> float:
	return water_level - dive_camera_depth - (global_position.y + _arm.position.y)


## The arm length a dive allows at the tilt he is holding. The camera sits
## `-sin(pitch) * length` above the pivot, so looking DOWN lifts it: near the surface the arm
## is pulled in until the camera fits under the water.
##
## THIS IS WHAT MAKES LOOKING DOWN POSSIBLE. Holding the pitch up instead took the control away
## outright - at two metres down the view was pinned five degrees off level whatever the mouse
## did, and the look was not his own again until seven metres. Pulling the camera in costs a
## closer camera, which is a picture; wrenching the view level costs the control, which is not.
## The arm goes back out to its full reach as he descends and the room appears.
func _dive_length() -> float:
	var reach := maxf(_dive_reach, 0.0)
	var rise := -sin(deg_to_rad(pitch_degrees))
	if rise <= 0.001:
		# Level with him or below him: the camera is going down, not up, and the surface is not
		# in the way at any length.
		return reach
	return clampf(_dive_room() / rise, minf(dive_min_distance, reach), reach)


func set_target(target: Node3D) -> void:
	_target = target
	if target == null:
		return
	global_position = target.global_position
	# The cast starts just above his head. Without this exclusion, backing into the camera
	# makes the arm hit his capsule and shorten to nothing.
	if target is CollisionObject3D:
		_arm.clear_excluded_objects()
		_arm.add_excluded_object(target.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("spyglass"):
		set_glassing(not _glassing)
		# Coming down from a steep look, the chase camera's own limits apply again and the
		# pitch has to be pulled back inside them or the view stays where the glass left it.
		_apply_pitch()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_set_mouse_looking(event.pressed)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _glassing:
				_magnify(glass_zoom_step)
			else:
				_arm.spring_length = maxf(min_distance, _arm.spring_length - zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _glassing:
				_magnify(-glass_zoom_step)
			else:
				_arm.spring_length = minf(max_distance, _arm.spring_length + zoom_step)
	elif event is InputEventMouseMotion and _mouse_looking:
		# screen_relative, not relative. The project stretches canvas items to a 1920x1080 base,
		# and relative arrives already scaled into that space - so the same physical mouse
		# movement turned the camera a different amount depending on the window size, and by
		# different amounts horizontally and vertically once the aspect stopped matching.
		# screen_relative is in real screen pixels and does not move when the window does.
		var motion: Vector2 = event.screen_relative
		# Divided by the magnification. At 4x the same hand movement sweeps four times the
		# view, and a glass that whips past what you are aiming at is unusable - this is the
		# single thing most scoped views get wrong.
		var steady := _look_scale()
		rotation.y -= motion.x * mouse_orbit_speed * steady
		# Screen Y grows DOWNWARD, so an upward drag is a negative motion.y. That single
		# negation is the whole conversion from "where the mouse went" to "which way the player
		# wants to look", and it happens once, here.
		var wants_up := -motion.y * mouse_pitch_speed * steady
		if invert_mouse_pitch:
			wants_up = -wants_up
		tilt(wants_up)


## Capturing the pointer while the button is held means a long swing keeps going instead of
## stopping when the cursor reaches the edge of the window, and the pointer comes back where
## it was left. Releasing always restores it - including when the window loses focus, because
## a middle-button release that lands on another window never arrives here and would otherwise
## leave the pointer captured with no way to get it back.
func _set_mouse_looking(looking: bool) -> void:
	if _mouse_looking == looking:
		return
	_mouse_looking = looking
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_set_mouse_looking(false)


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# Horizontal lag only. Copying Y keeps the cast origin on the ground he is standing
	# on; a trailed height puts that origin inside the beach and the arm pulls the
	# camera under it. The spring arm casts on this same physics step.
	var weight := 1.0 - exp(-follow_speed * delta)
	var followed := global_position.lerp(_target.global_position, weight)
	followed.y = _target.global_position.y
	# No lag at the eye. A pivot trailing a metre behind is unnoticeable from eighteen metres
	# back and is the whole picture swimming when the camera IS the pivot.
	if _glassing:
		followed = _target.global_position
		followed.y += eye_height
	# A manned gun takes the pivot off the player entirely. No lag, for the same reason the
	# glass has none: a pivot trailing behind is invisible from eighteen metres back and is the
	# whole picture swimming when the camera IS the pivot.
	if is_gunning():
		followed = _gun.eye() if _gun.get("first_person") else _gun.global_position
	global_position = followed
	# Look DOWN THE BARREL. The pivot alone is not enough: the rig keeps its own yaw, which is
	# the player's, so moving the camera to the gun without this leaves it staring off at
	# whatever the player last turned towards while the gun points somewhere else entirely.
	#
	# Only for the first-person guns. The gun on open ground is aimed by watching the ground
	# ahead, and wrenching the view round with every traverse would take that away.
	if is_gunning() and _gun.get("first_person"):
		var along: Vector3 = _gun.call("aim_velocity")
		along.y = 0.0
		if along.length() > 0.001:
			rotation.y = atan2(-along.x, -along.z)
	# Switched off mid-dive: come back up now, not when he surfaces.
	if _diving and not follow_dives:
		set_diving(false)
	# The way into a dive and back out of it is eased, never cut - the arm's length as well as
	# its tilt; cut, the camera jumped ten metres along the arm at each end. Other modes park
	# the arm themselves, so the length is left alone while one of them has it.
	var ease := 1.0 - exp(-dive_ease * delta)
	if _settling_length:
		if not is_equal_approx(_arm.spring_length, _eased_length):
			# Someone else has the arm - the wheel, the glass, a gun, the helm. Theirs.
			_settling_length = false
		else:
			_arm.spring_length = lerpf(_arm.spring_length, _dive_length_target, ease)
			if absf(_arm.spring_length - _dive_length_target) < 0.05:
				_arm.spring_length = _dive_length_target
				_settling_length = false
			_eased_length = _arm.spring_length
	# The arm hangs from his own origin while he is under, and from over his head the rest of the
	# time. Eased on the same curve as the length: cut, the picture dropped two metres the
	# instant he went under.
	var origin_wanted := dive_arm_height if _diving else _arm_rest_y
	if not is_equal_approx(_arm.position.y, origin_wanted):
		_arm.position.y = lerpf(_arm.position.y, origin_wanted, ease)
		if absf(_arm.position.y - origin_wanted) < 0.02:
			_arm.position.y = origin_wanted
	# Under water the arm has a ceiling: short enough that the tilt he is holding keeps the
	# camera in the sea. The wheel still sets the REACH - a length we did not write is his, and
	# he gets all of it back the moment he looks level or descends far enough for it.
	if _diving:
		# The reach is read on every tick of a dive, the way in included. Read only once the way
		# in had finished, it was nought for the whole of that ease - and a reach of nought is
		# no floor at all, so the view eased all the way down to his chase tilt and then SNAPPED
		# back up by five metres the moment the reach arrived and the floor with it.
		if not is_equal_approx(_arm.spring_length, _dive_capped):
			_dive_reach = _arm.spring_length
		if not _settling_length:
			# Eased, like everything else this camera does under water. Cut, the arm dropped
			# from six metres to one and a half on the frame the way in finished - a nine metre
			# jump, which is what the way in is eased to avoid in the first place. Nothing is
			# lost by taking half a second over it: the view is held out of the air by
			# _floor_pitch, which reads the arm as it is on each frame, not as it will be.
			var fits := _dive_length()
			_arm.spring_length = lerpf(_arm.spring_length, fits, ease)
			if absf(_arm.spring_length - fits) < 0.02:
				_arm.spring_length = fits
			_dive_capped = _arm.spring_length
	# The dive tilt follows his depth. Eased on the way in and out; but once he is under, a
	# clamp that RISES - a lower camera - is taken at once. Eased, it trailed a fast ascent by
	# seven degrees and lifted the camera into the waves. A tilt from the player still lands at
	# once, through _apply_pitch.
	var wanted := _effective_pitch()
	var current := _arm.rotation_degrees.x
	if _entering_dive and absf(wanted - current) < 0.5:
		_entering_dive = false
	if _diving and not _entering_dive and wanted > current:
		_arm.rotation_degrees.x = wanted
	elif not is_equal_approx(wanted, current):
		_arm.rotation_degrees.x = lerpf(current, wanted, ease)





## How much to slow the look by, so turning feels the same whatever the glass is doing.
func _look_scale() -> float:
	return 1.0 / _magnification if _glassing else 1.0


func _magnify(by: float) -> void:
	_magnification = clampf(_magnification + by, glass_zoom_min, glass_zoom_max)
	_apply_fov()


func _process(delta: float) -> void:
	var steady := _look_scale()
	var orbit := Input.get_axis("cam_left", "cam_right")
	# E climbs, and E takes the wheel. While either of those is what the key will do, it
	# should not also yaw the view.
	if orbit > 0.01 and _target != null and _target.has_method("boarding") and _target.boarding():
		orbit = 0.0
	if absf(orbit) > 0.01:
		rotation.y -= orbit * orbit_speed * delta * steady
	if touch_controls:
		var gesture: Dictionary = touch_controls.take_camera_input()
		rotation.y -= gesture["orbit"]
		if absf(gesture["pitch"]) > 0.0:
			# Through tilt() like everything else. This path used to add the gesture raw, which
			# is how touch ended up ignoring the glass entirely and disagreeing with the mouse.
			tilt(gesture["pitch"] * _look_scale())
		if absf(gesture["zoom"]) > 0.0:
			_arm.spring_length = clampf(_arm.spring_length + gesture["zoom"],
					min_distance, max_distance)
