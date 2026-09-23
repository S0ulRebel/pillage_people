extends CharacterBody3D
## Bird's-eye third-person controller: WASD moves relative to the camera, Space jumps,
## Q/E orbit, mouse wheel zooms. Beside the ship, E climbs aboard instead of turning.
## The body is the captain model when it is present, and a
## blocky stand-in built from primitives when it is not.

## Normal movement. The walk clip plays below run_above, so this sits under it.
@export var speed := 4.8
## Held-Shift movement. Shift is also the dive key, but the two never apply at once - dive
## only means anything while swimming, and this only applies on land.
@export var sprint_speed := 9.0
@export var acceleration := 12.0
@export var turn_speed := 12.0
## Turns the model on the spot, in degrees, without touching which way the body steers.
## Movement rotates the body so its +Z faces the way you are going; a model authored facing
## the other way walks backwards. Set this to 180 if the captain moonwalks.
@export var model_yaw := 0.0
## Ignore scene lighting on the character and show the texture as painted. Worth trying when
## the texture already has its lighting baked in, which generated ones do. The cost is that he
## no longer darkens under a tree or at dusk.
@export var unshaded_model := false
## NOTE: the model's size is NOT set here. It is nodes/root_scale in art/models/captain.glb
## .import, currently 1.9 to match the collider.
##
## Two settings in that .import file have to be right, and .import files are gitignored, so a
## fresh clone gets the defaults back and both have to be set again:
##   nodes/root_scale=1.9                     without it the captain is one metre tall
##   animation/remove_immutable_tracks=false  the jump clip's hips are pinned to a constant,
##                                            and that stripper drops constant tracks, which
##                                            would snap the hips to the bone rest mid-jump
##
## Scaling it in code shatters it. A generator normalises to a unit cube, so the character
## arrives 1.0 units tall and the obvious fix is to scale the node on load - but that node
## has a Skeleton3D under it, and scaling above a skeleton breaks Godot's skinning: the mesh
## tears apart into stretched fragments. The importer rescales the bone rest poses along with
## the mesh, which is why it is the only place this belongs.

@export_group("Animation")
## Clip names as they appear in the model's AnimationPlayer. Mixamo names its downloads after
## the animation ("mixamo.com" for a single clip, or the pack's own names), so these are
## exports rather than constants - set them to whatever actually arrives.
@export var clip_idle := "idle"
@export var clip_walk := "walk"
@export var clip_run := "run"
@export var clip_jump := "jump"
@export var clip_fall := "fall"
@export var clip_swim := "swim"
## Plays once and holds its last frame - the captain staggers back and ends up flat on his
## back. Unlike the others this clip keeps its root motion, because falling over is supposed
## to move him: he travels about two thirds of his own height backwards on the way down. The
## collider stays where it was, so the body comes to rest beside it rather than inside it.
@export var clip_death := "death"
## Above this ground speed the run clip is used instead of the walk. Walking at run speed
## looks like the feet are skating, which is the usual giveaway that the blend is wrong.
@export var run_above := 5.5
## Seconds to cross-fade between clips. Too short snaps, too long makes turns feel sluggish.
@export var clip_blend := 0.15

@export_group("Weapon")
## Whether he carries one at all. Turn it off for a captain who should be empty-handed.
@export var show_weapon := true
## The cutlass itself - bone, model, hitbox and the corrections that put the grip in his fist.
## See cutlass.tres, and held_item.gd for what each field means and why you cannot guess them.
@export var cutlass: HeldItem = preload("res://actors/captain/cutlass.tres")

@export_group("Guard")
## Held on the right mouse button. He is rooted-ish and cannot swing, and a blow from the
## front is turned aside.
##
## Deliberately NOT a component yet. Only the captain guards, and one user is not a pattern -
## if the grunts learn to block it can move to actors/parts then, the way health and knockback
## did once there were two of them and they had drifted.
@export var clip_block := "block"
## Seconds at the START of a guard that parry instead of merely blocking.
##
## Not invented: a grunt's blade is live from 0.20 s to 0.42 s into its 0.75 s swing, so there
## is a real 220 ms to read and answer. This is the answer being tight enough to be a skill
## and loose enough to be possible.
@export var parry_window := 0.18
## What a plain block lets through. Zero turns the blow aside completely - which is strong, but
## he is rooted, cannot swing, and it only works to the front.
@export var block_damage := 0
## How much of his speed he keeps with the guard up. Not zero: a captain who cannot back away
## while blocking is a captain being surrounded on purpose.
@export_range(0.0, 1.0) var guard_movement := 0.4
## How far round the front the guard covers, as a dot product. Matches the blade's own cone.
@export_range(0.0, 1.0) var guard_facing_dot := 0.25

@export_group("Pistol")
## A flintlock in the off hand - see actors/parts/gun.gd. He keeps the cutlass: a captain with
## a sword in one hand and a pistol in the other is the whole picture, and it is less work than
## a weapon-swap besides.
@export var show_pistol := true
## Which bone, which model, and the three corrections that put the grip in his hand - all of
## it lives in flintlock.tres, so a weapon is a thing that can be handed around rather than
## eight fields spelled into whoever happens to hold it.
@export var flintlock: HeldItem = preload("res://actors/captain/flintlock.tres")
## The aiming stance, held while the flintlock is up and he is standing still.
##
## Mixamo's two pistol clips are named the opposite way round to how they read. "Pistol Idle"
## is the HOLD - both hands out, the pistol hand 28 cm from the hips and moving 1.3 cm across
## four seconds - so that is this one, renamed `aim` on the way in. "Pistol Aim" is a 3.6 s
## LOWERING that starts aimed and ends at rest, which is not a raise and is far too slow for a
## key press, so it was left out. Measured with tools/inspect_clips.py rather than guessed.
@export var clip_aim := "aim"

@export_group("Combat")
@export var clip_attack := "slash"
## How much of his own speed he keeps while swinging. Zero plants him, which is what a grunt
## does; it is a dial rather than a hard stop because a swing that kills all momentum can read
## as hitting a wall, and the right amount is a matter of feel rather than of measurement.
@export_range(0.0, 1.0) var attack_movement := 0.0
## Where the swing starts inside the clip. Mixamo's "Stable Sword Inward Slash" runs 2.23s and
## spends its first second winding up; the strike itself peaks at 1.23s. Measured from how fast
## the right hand moves through the clip - the peak is 2.4x anything before it. Playing from
## zero means pressing attack does nothing visible for a second.
@export var attack_start := 0.95
## How long the swing owns the animation before walking and idling take it back. The strike and
## its follow-through fit in this; the clip's remaining recovery is not worth waiting through.
@export var attack_length := 0.75
## Seconds after a swing before another can start. The grunts have always had one; he never
## did, so the button could be held and the cutlass never stopped moving.
@export var attack_cooldown := 0.35
## Seconds into the swing where the blade actually connects. Not guessed: the right hand's
## speed through the clip peaks at 1.23s, which is 0.28s after attack_start, and stays above
## half that peak from 1.17s to 1.37s. Those are the edges below. Outside them the blade is
## travelling to or from the strike and should pass through people harmlessly, or every swing
## lands the moment the button goes down and range stops meaning anything.
@export var hit_from := 0.20
@export var hit_to := 0.42
@export var damage := 1
@export var max_health := 5
## Seconds of grace after being hit - see health.gd. The grunts get none; this is the
## difference between being surrounded and being executed.
@export var hit_immunity := 0.55
## Sparks where the blade lands. Near-white, because the sand is warm and a gold spark measured
## only 33 luminance above it - invisible in practice. This one manages 59, at three and a half
## times the colour distance, and reads as steel besides.
@export var hit_colour := Color(0.93, 0.97, 1.0)
## Being hit shoves the captain back and takes the controls away for a moment. Deliberately
## shorter than the grunt's: losing control of your own character is far more irritating than
## watching someone else lose theirs, and a long stun turns two grunts into a death sentence.
@export var knockback := 4.2
@export var stagger := 0.22
## How fast the shove bleeds off while staggered, in metres per second squared.
@export var knock_damping := 9.0

@export_group("Jump feel")
## How high a full jump goes, in metres. The take-off speed is derived from it.
@export var jump_height := 1.6
## Gravity while rising. Real-world 9.8 feels like the moon in a game; this is ~2.5x that.
@export var rise_gravity := 26.0
## Gravity while falling. Heavier than the rise makes the arc snappy instead of floaty.
@export var fall_gravity := 38.0
## Releasing the button early cuts the jump short (this fraction of the rising speed is kept).
@export var short_hop_cut := 0.58
## Still allowed to jump this long after walking off an edge.
@export var coyote_time := 0.12
## A jump pressed this long before landing still fires on touchdown.
@export var jump_buffer := 0.15
@export var terminal_velocity := 45.0

@export_group("Swimming")
## Sea level in metres, set by main.gd from the terrain so the two cannot disagree.
@export var water_level := 0.0
## Wading turns into swimming once the water is this deep - about chest height.
@export var swim_depth := 1.3
@export var swim_speed := 5.5
## How hard the water pushes you back to the surface when you stop diving.
@export var buoyancy := 7.0
## Water resists: momentum from running does not carry far once you are in it.
@export var water_drag := 3.0
@export var wade_slowdown := 0.55
## Metres between footfalls. Shorter than a real stride on purpose - the walk clip lands two
## feet per cycle and one sound per cycle reads as limping.
@export var stride_length := 1.5

## Set by main.gd - movement is relative to whichever way the camera is facing.
var camera_rig: Node3D
## Set by main.gd on touch devices; its stick overrides the keyboard when in use.
var touch_controls: CanvasLayer

const MODEL_PATH := "res://art/models/captain.glb"

@onready var _body: Node3D = $Body

## False when the model is missing and the blocky stand-in is standing in for it.
var _model_loaded := false
## The model's own AnimationPlayer, or null until it has clips on it.
## The model's clips - see actors/parts/clips.gd, shared with the grunt.
var _clips: Clips
## What is playing, so a clip is not restarted from the top every frame.
var _walk_time := 0.0
var _coyote := 0.0
var _buffered := 0.0
var _holding_jump := false
## Set by the touch dive button; the keyboard uses the "dive" action directly.
var _holding_dive := false
## True between die() and revive(). Checked before anything else each frame.
var _dead := false
## Seconds left in the current swing; zero when not attacking.
var _attack := 0.0
## Counts down from the start of a swing through the recovery after it.
var _cooldown := 0.0
## The placeholder blade, so it can be swapped or hidden without rebuilding the body.
## The cutlass - see actors/parts/sword.gd. Typed, so its hitbox is reachable by name.
var _sword: Sword
## Everything already struck by the current swing, so one swing cannot hit the same body twice.
var _struck: Array[Node] = []
## Health and knockback are components - see actors/parts. They were his alone and the
## grunt's alone, separately, and they drifted; the grunt now uses the same two.
var _hp: Health
var _knock: Knockback
## The flintlock, and whether it is up. Raising it is a stance rather than a held button: one
## ball and a five second reload is a weapon you commit to, not one you tap.
var _pistol: Gun
var _aiming := false
## Whether the guard is up, and how long it has been. The second is what makes a parry
## different from a block.
var _guarding := false
var _guard_time := 0.0
var _stride := 0.0
## The hull he can climb. Set from main once it is moored; nothing, until then.
var _ship: Node3D
var _was_wet := false


## Take-off speed for the requested height: v = sqrt(2 * g * h).
## Emitted the moment die() is called, before the clip starts, so whatever is listening can
## fade the screen or start a respawn timer against the same frame.
signal died
signal revived
## Emitted when the flintlock comes up or goes down, so a crosshair can appear with it.
signal aiming_changed(up: bool)
## A blow turned aside, and a blow turned aside in the parry window. Separate because they
## should not sound or look the same - one is a thud on the guard, the other is a ring of
## steel and an opening.
signal blocked(attacker: Node)
signal parried(attacker: Node)
## Emitted when a swing starts, not when it connects. Whatever deals damage should wait for
## the blade to be somewhere useful rather than firing on the keypress.
signal attacked
## The blade reached something. Carries what was hit, so scoring or effects can hang off it.
signal hit(target: Node)
signal damaged(amount: int, remaining: int)
## A footfall. Emitted by distance covered rather than on a timer, so it keeps pace with a
## sprint without anything having to know how fast he is going.
signal stepped
## Crossing into water, either way. True going in.
signal splashed(entering: bool)


func is_attacking() -> bool:
	return _attack > 0.0


## Whether a swing would start right now - false mid-swing and through the recovery after it.
## Worth exposing rather than inferring from is_attacking(), which is false during the
## cooldown too and so cannot tell "swinging" from "not ready yet".
func can_attack() -> bool:
	return not _dead and _attack <= 0.0 and _cooldown <= 0.0


func health() -> int:
	return _hp.current()


## Whether the controls are being ignored because he was just hit.
func is_staggered() -> bool:
	return _knock.staggered()


## Duck-typed to match enemy.gd, so whatever ends up swinging at the captain does not need to
## know what he is either.
func take_damage(amount: int, _from: Node = null) -> void:
	if _dead:
		return
	# The guard gets first refusal, and only to the front - a block that works from behind is
	# not a guard, it is a bubble.
	if _guarding and _from is Node3D and _in_guard_arc(_from as Node3D):
		if _guard_time <= parry_window:
			parried.emit(_from)
			# The shove goes the OTHER way. This is the whole point of a parry and it costs
			# three lines, because knockback is a component: it is the same call the attacker
			# would have made, pointed back at him.
			if _from.has_method("reel"):
				_from.reel(self)
			return
		blocked.emit(_from)
		# Still shoved by the impact, just not cut by it.
		_knock.hit_from(global_position, _from)
		if block_damage <= 0:
			return
		amount = block_damage
	else:
		# Shoved directly away from whoever swung, so the push reads as coming from the blow.
		_knock.hit_from(global_position, _from)
	var finished := _hp.take(amount)
	damaged.emit(amount, _hp.current())
	if finished:
		die()


## Applies the blade to anything inside it, once per swing per body.
##
## Overlaps are read every frame rather than waiting for body_entered, because a body can
## already be inside the blade when the window opens - standing close enough that the sword
## starts the strike overlapping them - and an entered signal that fired before the window
## never comes again.
func _strike() -> void:
	if _sword == null:
		return
	var elapsed := attack_length - _attack
	if _attack <= 0.0 or elapsed < hit_from or elapsed > hit_to:
		return
	# Asked of the sword by range and facing, not by what its hitbox happens to be inside on
	# this frame. The blade is 12 cm thick and the hand moves up to 20 cm per physics step, so
	# overlap only caught somebody at about 0.4 m and swept straight through anybody further -
	# while a grunt stands off at 1.00 m. See Sword.targets.
	var facing := Vector3(sin(_body.rotation.y), 0.0, cos(_body.rotation.y)) 			if _body != null else -global_transform.basis.z
	for body in _sword.targets(self, facing, _struck):
		_struck.append(body)
		body.take_damage(damage, self)
		# On the target, at chest height, thrown back the way the blow travelled. Spawned on
		# the scene rather than on either fighter so it does not ride the follow-through or
		# vanish when a body is freed.
		var towards: Vector3 = body.global_position - global_position
		towards.y = 0.0
		var contact: Vector3 = body.global_position + Vector3.UP * 1.0 				- towards.normalized() * 0.35
		HitSpark.burst(get_parent(), contact, towards, hit_colour)
		hit.emit(body)


## Starts a swing, if one is not already running. Movement is deliberately left alone - you can
## walk while swinging, and the clip simply owns the animation until it runs out.
func attack() -> void:
	if _dead or _attack > 0.0 or _cooldown > 0.0 or _guarding:
		return
	_attack = attack_length
	_cooldown = attack_length + attack_cooldown
	_struck.clear()
	attacked.emit()


func is_dead() -> bool:
	return _dead


## Stops the captain taking input and plays the death clip. Nothing in the game calls this
## yet - there is no health anywhere - so it is here for whatever does the hurting to call.
func die() -> void:
	if _dead:
		return
	_dead = true
	_buffered = 0.0
	_holding_jump = false
	died.emit()


func revive() -> void:
	if not _dead:
		return
	_dead = false
	_hp.refill()
	_knock.clear()
	# Clearing this makes _update_animation treat the next clip as a change and play it. Without
	# it the captain stands back up still holding the last frame of his own death.
	_clips.forget()
	revived.emit()


func _jump_velocity() -> float:
	return sqrt(2.0 * rise_gravity * jump_height)


## Whether the pistol is raised.
func is_aiming() -> bool:
	return _aiming


func is_guarding() -> bool:
	return _guarding


## The guard is a HELD state, so it is polled rather than caught as an event - the same
## division as the movement stick and sprint. What the poll has to find for itself is the
## RISING edge, because that is when the parry window starts.
func _tick_guard(delta: float) -> void:
	var wanted := Input.is_action_pressed("guard") and not _aiming
	if wanted and not _guarding:
		_guard_time = 0.0
	elif wanted:
		_guard_time += delta
	_guarding = wanted


## Is `attacker` in front of the guard?
func _in_guard_arc(attacker: Node3D) -> bool:
	var towards: Vector3 = attacker.global_position - global_position
	towards.y = 0.0
	if towards.length() < 0.001:
		return true
	var facing := Vector3(sin(_body.rotation.y), 0.0, cos(_body.rotation.y)) 			if _body != null else -global_transform.basis.z
	return facing.dot(towards.normalized()) >= guard_facing_dot


## Whether the guard is still inside its parry window.
func is_parrying() -> bool:
	return _guarding and _guard_time <= parry_window


## Shoved and briefly robbed of control, without being hurt. What a parry does to whoever
## swung. Duck-typed the way take_damage is, so a parry does not need to know what it just
## turned aside.
##
## Named reel rather than stagger because `stagger` is already the export holding how many
## seconds one lasts.
func reel(from: Node) -> void:
	if _dead:
		return
	_knock.hit_from(global_position, from)


func pistol() -> Gun:
	return _pistol


## Raises or lowers the flintlock.
func set_aiming(up: bool) -> bool:
	if _dead or _pistol == null or _aiming == up:
		return false
	_aiming = up
	aiming_changed.emit(up)
	return true


## Fires at a point in the world, if there is a ball in it. Returns what was hit.
##
## The aim comes from OUTSIDE. Working out where the cursor points is a question about the
## camera and the screen, and the captain knows about neither - main.gd answers it.
func shoot_at(aim: Vector3) -> Node:
	if _dead or _pistol == null or not _aiming:
		return null
	return _pistol.fire(self, aim)


## Presses and releases - the things that happen once.
##
## These were polled in _physics_process with is_action_just_pressed. That works, but it asks
## a question every tick that only has an answer on the tick an event arrived, and "just
## pressed" is latched per frame: when the render rate and the physics rate differ, a press can
## be seen on two physics ticks or fall between them and be missed. An input callback fires
## once, for the event that actually happened.
##
## It also stops a click on the virtual stick from swinging the cutlass. Input consumed by the
## touch controls never reaches here, where polling saw it regardless.
##
## The HELD states stay polled in _physics_process - the movement stick, sprint, swimming up
## and diving. Those are genuinely a question asked every tick rather than a moment in time.
func _unhandled_input(event: InputEvent) -> void:
	# Nothing is read while he is dead, not even to buffer it, or he jumps the instant he
	# respawns. This is the guard the polling got by sitting after the death branch.
	if _dead:
		return
	if event.is_action_pressed("pistol"):
		set_aiming(not _aiming)
	elif event.is_action_pressed("attack"):
		# The cutlass only swings with the pistol down. Firing it is main.gd's to trigger,
		# because it needs the cursor.
		if not _aiming:
			attack()
	elif event.is_action_pressed("jump"):
		request_jump()
	elif event.is_action_released("jump"):
		release_jump()
	elif event.is_action_pressed("board"):
		try_board()


## Connected to the touch jump button by main.gd (press and release), and to the keyboard by
## _unhandled_input above.
func request_jump() -> void:
	_buffered = jump_buffer
	_holding_jump = true


func release_jump() -> void:
	_holding_jump = false


## Handed the moored hull. He does not go looking for it.
func set_ship(ship: Node3D) -> void:
	_ship = ship


## True while E would climb rather than turn the camera.
func boarding() -> bool:
	return _ship != null and _ship.can_board(self)


## Climbs aboard if he is beside the hull. Returns whether it happened.
func try_board() -> bool:
	if _ship == null or not _ship.can_board(self):
		return false
	_ship.board(self)
	return true


## Connected to the touch dive button by main.gd.
func set_diving(pressed: bool) -> void:
	_holding_dive = pressed


func _ready() -> void:
	# Tunnel ramps run at about 40 degrees, and faceted walls push some normals past Godot's
	# 45 degree default, which reads as "wall" and stops the player dead halfway out.
	floor_max_angle = deg_to_rad(55.0)
	_hp = Health.new()
	_hp.name = "Health"
	_hp.maximum = max_health
	_hp.immune_seconds = hit_immunity
	add_child(_hp)
	_knock = Knockback.new()
	_knock.name = "Knockback"
	_knock.strength = knockback
	_knock.recovery = stagger
	_knock.damping = knock_damping
	add_child(_knock)
	_clips = Clips.new()
	_clips.name = "Clips"
	_clips.blend = clip_blend
	add_child(_clips)
	_build_body()


## How deep the feet are below the surface; negative when clear of the water.
func submersion() -> float:
	return water_level - global_position.y


func is_swimming() -> bool:
	return submersion() > swim_depth


func _physics_process(delta: float) -> void:
	if _dead:
		# Gravity still applies and momentum still bleeds off, so a captain killed in mid-air
		# falls and comes to rest instead of dying where he was hit and hanging there. Input
		# is not read at all - not even to buffer it - or he would jump on respawn.
		if not is_on_floor():
			velocity.y -= fall_gravity * delta
			velocity.y = maxf(velocity.y, -terminal_velocity)
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * sprint_speed)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * sprint_speed)
		move_and_slide()
		_update_animation()
		return

	# Ticked before the swimming branch returns, or a swing started on land would never end.
	_attack = maxf(0.0, _attack - delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_hp.tick(delta)
	_tick_guard(delta)
	_knock.tick(delta)
	if _pistol != null:
		_pistol.tick(delta)
	# The captain's swing SURVIVES being hit. A grunt's does not, and that asymmetry is the
	# point: a grunt out-reaches the captain and swings every 2.15 s, so cancelling on contact
	# meant every swing died before its strike window opened. Measured, that is a captain who
	# lands one blow in six and dies - not a fight, a formality. He is still shoved and still
	# loses control for 0.22 s; he just gets to finish what he started.
	_strike()

	# --- jump feel: coyote time, buffered presses, short hops, heavier fall ---
	# The press and the release are caught in _unhandled_input; what is left here is the
	# countdown they start.
	_buffered = maxf(0.0, _buffered - delta)
	_coyote = coyote_time if is_on_floor() else maxf(0.0, _coyote - delta)

	var swimming := is_swimming()
	# Only on the crossing, not every frame spent wet.
	var wet := submersion() > 0.25
	if wet != _was_wet:
		_was_wet = wet
		splashed.emit(wet)
	if touch_controls:
		touch_controls.show_dive(swimming)
	if swimming:
		_swim(delta)
		return

	if _buffered > 0.0 and _coyote > 0.0:
		velocity.y = _jump_velocity()
		_buffered = 0.0
		_coyote = 0.0
	elif not is_on_floor():
		var rising := velocity.y > 0.0
		if rising and not _holding_jump:            # let go early -> short hop
			velocity.y *= short_hop_cut
			rising = velocity.y > 0.0
		velocity.y -= (rise_gravity if rising else fall_gravity) * delta
		velocity.y = maxf(velocity.y, -terminal_velocity)

	var direction := _move_direction()
	var wanted := sprint_speed if Input.is_action_pressed("sprint") else speed
	# Shallow water drags: wading out to the drop-off should feel different from running.
	var walk_speed := wanted * (wade_slowdown if submersion() > 0.0 else 1.0)
	var target := direction * walk_speed
	if _knock.staggered():
		# Carried by the shove rather than steered. The knockback component bleeds it off at
		# its own gentle rate; the captain's normal deceleration is 108 m/s^2, which would kill
		# it inside three frames and make a hit look like nothing happened.
		var shove: Vector3 = _knock.shove()
		velocity.x = shove.x
		velocity.z = shove.z
	else:
		velocity.x = move_toward(velocity.x, target.x, acceleration * delta * sprint_speed)
		velocity.z = move_toward(velocity.z, target.z, acceleration * delta * sprint_speed)
	move_and_slide()

	if direction.length() > 0.05:
		var yaw := atan2(direction.x, direction.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)
		_walk_time += delta * velocity.length()
		_animate_walk()
		# A footfall every stride_length of ground covered, and only with feet on it.
		if is_on_floor():
			_stride += Vector2(velocity.x, velocity.z).length() * delta
			if _stride >= stride_length:
				_stride = 0.0
				stepped.emit()
	else:
		_walk_time = 0.0
		_animate_walk(true)
	_update_animation()


## Swimming: no jump arc and no gravity, just buoyancy, drag and free vertical control.
##
## Holding jump swims up, holding dive swims down, and letting go floats back to the surface.
## Without that float the player sinks quietly to the seabed whenever they stop steering.
func _swim(delta: float) -> void:
	var direction := _move_direction()
	var target := direction * swim_speed
	velocity.x = move_toward(velocity.x, target.x, water_drag * delta * swim_speed)
	velocity.z = move_toward(velocity.z, target.z, water_drag * delta * swim_speed)

	var vertical := 0.0
	if _holding_jump or Input.is_action_pressed("jump"):
		vertical = swim_speed
	elif _holding_dive or Input.is_action_pressed("dive"):
		vertical = -swim_speed
	else:
		# Float up, but stop at the surface rather than launching out of the water.
		var above_swimming_depth: float = submersion() - swim_depth
		vertical = clampf(above_swimming_depth * buoyancy, -swim_speed, swim_speed)
	velocity.y = move_toward(velocity.y, vertical, water_drag * delta * swim_speed * 2.0)
	move_and_slide()

	if direction.length() > 0.05:
		var yaw := atan2(direction.x, direction.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)
		_walk_time += delta * velocity.length()
	_animate_walk()
	_update_animation()


## Camera-relative movement input, shared by walking and swimming.
func _move_direction() -> Vector3:
	# Nothing steers while staggered. Applied here rather than at each call site so it covers
	# swimming and walking together.
	if _knock.staggered():
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_controls and touch_controls.move.length() > 0.0:
		input = touch_controls.move
	# Planted mid-swing, the way a grunt is. Running through your own strike reads as a shove
	# rather than a cut, and it let the captain cross 4.88 m during a 0.75 s swing - a full
	# sprint, with the blade out, arriving somewhere else entirely by the time it landed.
	if _attack > 0.0:
		input *= attack_movement
	elif _guarding:
		input *= guard_movement
	var basis := camera_rig.global_transform.basis if camera_rig else global_transform.basis
	var forward := -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var direction := (right * input.x + forward * -input.y)
	return direction.normalized() if direction.length() > 1.0 else direction


## The captain, or a blocky stand-in if the model is not there.
##
## The model comes out of the pipeline in D:\code\gan: a silhouette becomes a rendered
## character, four turnaround views come off that, and a multi-view service builds the rigged
## mesh. Generators normalise to a unit cube, so it arrives 1.0 units tall and is scaled here.
##
## Scaling belongs here and not in the file. Writing a scale onto the glTF root node looks
## like it works - the bounds come out right and it loads fine - but a skinned mesh carries
## inverse-bind matrices that do not scale with it, so the character arrives visibly
## distorted. Scaling the instantiated node scales the skeleton and the skin together.
func _build_body() -> void:
	var scene: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if scene:
		var model := scene.instantiate()
		model.name = "Model"
		model.rotation.y = deg_to_rad(model_yaw)
		_body.add_child(model)
		# Layer 20 is the overhead water-interaction camera. Every visible surface has to be
		# on it or the water loses the player's footprint - see _add_part.
		for node in _all_descendants(model):
			if node is VisualInstance3D:
				node.set_layer_mask_value(20, true)
		_flatten_materials(model)
		for node in _all_descendants(model):
			if node is AnimationPlayer:
				_clips.use(node as AnimationPlayer)
				break
		_set_looping()
		_attach_weapon(model)
		_model_loaded = true
		return
	_build_primitive_body()


## Hangs the cutlass off the hand it belongs to. The awkward parts - which way a blade leaves a
## fist, and cancelling the rig's unit scale - live in actors/parts/held.gd, shared with the
## grunts; which bone and which corrections live in the item itself.
func _attach_weapon(model: Node3D) -> void:
	if not show_weapon:
		return
	var skeleton: Skeleton3D = null
	for node in _all_descendants(model):
		if node is Skeleton3D:
			skeleton = node as Skeleton3D
			break
	var blade := Sword.new()
	blade.name = "Sword"
	if not blade.mount(skeleton, cutlass):
		blade.free()
		return
	_sword = blade
	_attach_pistol(skeleton)


## The flintlock, in the other hand. Built separately from the cutlass rather than alongside it
## because a captain who has one and not the other should still work: a missing pistol model
## leaves him with a sword, not with an error.
func _attach_pistol(skeleton: Skeleton3D) -> void:
	if not show_pistol or skeleton == null:
		return
	var shot := Gun.new()
	shot.name = "Pistol"
	if not shot.mount(skeleton, flintlock):
		shot.free()
		return
	_pistol = shot


func _flatten_materials(model: Node3D) -> void:
	for node in _all_descendants(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				var flat: BaseMaterial3D = material.duplicate()
				flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				flat.metallic = 0.0
				flat.roughness = 1.0
				flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				if unshaded_model:
					# The texture is already lit, so ignoring the scene lights entirely can
					# read better - at the cost of the character not darkening in shadow.
					flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_node.set_surface_override_material(surface, flat)


func _all_descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_all_descendants(child))
	return found


## The original stand-in, kept so the project still runs with no imported assets.
func _build_primitive_body() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.20, 0.38, 0.62)
	var trousers := StandardMaterial3D.new()
	trousers.albedo_color = Color(0.22, 0.24, 0.30)
	for material in [skin, cloth, trousers]:
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.roughness = 1.0

	_add_part("Torso", CapsuleMesh.new(), Vector3(0, 0.95, 0), cloth, func(m):
		m.radius = 0.28
		m.height = 0.9)
	_add_part("Head", SphereMesh.new(), Vector3(0, 1.62, 0), skin, func(m):
		m.radius = 0.22
		m.height = 0.44)
	for side in [-1.0, 1.0]:
		var arm := _add_part("Arm%s" % ("L" if side < 0 else "R"), BoxMesh.new(),
				Vector3(side * 0.42, 1.05, 0), cloth, func(m): m.size = Vector3(0.16, 0.62, 0.16))
		arm.set_meta("swing_side", side)
		var leg := _add_part("Leg%s" % ("L" if side < 0 else "R"), BoxMesh.new(),
				Vector3(side * 0.16, 0.35, 0), trousers, func(m): m.size = Vector3(0.20, 0.7, 0.20))
		leg.set_meta("swing_side", -side)


func _add_part(name_: String, mesh: PrimitiveMesh, pos: Vector3, material: Material,
		configure: Callable) -> MeshInstance3D:
	configure.call(mesh)
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = name_
	node.mesh = mesh
	node.position = pos
	# Layer 20 is read only by the overhead water-interaction camera. It gives the water
	# the player's true top-down footprint without outlining the gameplay-camera silhouette.
	node.set_layer_mask_value(20, true)
	_body.add_child(node)
	return node


## Swings the stand-in's limbs. The captain is driven by _update_animation instead.
func _animate_walk(rest := false) -> void:
	if _model_loaded:
		return
	var swing := 0.0 if rest else sin(_walk_time * 1.6) * 0.5
	for child in _body.get_children():
		if child.has_meta("swing_side"):
			child.rotation.x = swing * child.get_meta("swing_side")


## Marks the cyclic clips as looping.
##
## glTF carries no loop flag, so Godot imports every animation as play-once. A walk cycle then
## takes a few steps, stops on its last frame, and the character glides along in that pose -
## which reads as the animation being broken rather than merely finished.
##
## Jump is deliberately left alone. It is Mixamo's "Jumping Up" cut down to its launch - the
## legs drive down and then tuck - and it runs 0.34s against the 0.35s the rise actually takes,
## so it lands on the tuck and holds there. Looping it would restart the take-off mid-air.
##
## Fall does loop. It is "Falling Idle", which is built as a cycle, and a drop from any height
## worth having outlasts its 0.73s - without the loop the character freezes into its last frame
## on the way down.
func _set_looping() -> void:
	# The two stances loop for a plainer reason than the rest: they are HELD. The aim clip runs
	# 4.03 s, so without this he freezes into its last frame the moment you hold the pistol up
	# longer than that - which looks like nothing at all until you do.
	for name_ in [clip_idle, clip_walk, clip_run, clip_swim, clip_fall, clip_aim, clip_block]:
		if not _clips.has(name_):
			continue
		var clip := _clips.animation(name_)
		if clip.loop_mode != Animation.LOOP_LINEAR:
			clip.loop_mode = Animation.LOOP_LINEAR


## Picks the clip that matches what the player is doing.
##
## Nothing here assumes the clips exist. A model with a skeleton and no animations - which is
## what a generator gives you - simply stands in its rest pose, and each clip starts working
## the moment it is added. That way the states can be got right before the animations arrive.
func _update_animation() -> void:
	var wanted := ""
	if _dead:
		wanted = clip_death
	elif _attack > 0.0:
		wanted = clip_attack
	elif _guarding:
		wanted = clip_block
	elif is_swimming():
		wanted = clip_swim
	elif not is_on_floor():
		wanted = clip_jump if velocity.y > 0.0 else clip_fall
	else:
		var ground_speed := Vector2(velocity.x, velocity.z).length()
		if ground_speed < 0.2:
			# Standing still only. There is no aiming-walk clip and no upper-body blend, so
			# aiming on the move keeps the walk and lets the flintlock ride the arm swing -
			# the pistol is a mesh on a hand bone and stays visible either way. The stance
			# has both feet planted, and playing it while he travels would skate them.
			wanted = clip_aim if _aiming else clip_idle
		else:
			wanted = clip_run if ground_speed > run_above else clip_walk

	# Falls back through to something that does exist, so a half-finished set still animates
	# rather than freezing: no run clip yet means walking, no fall clip means the jump.
	var fallbacks: Array[String] = [clip_walk, clip_idle]
	if wanted == clip_block or wanted == clip_aim:
		# A STANCE takes idle first. With the shared order a missing block clip fell back to
		# walk, so guarding while standing still played a walk cycle on the spot - and it
		# will, until a block clip exists. The same trap was waiting for the aim pose.
		fallbacks = [clip_idle, clip_walk]
	var was := _clips.current()
	var playing := _clips.play(wanted, fallbacks)
	# The swing is entered part-way in. See attack_start: the clip's first second is a wind-up,
	# and starting at zero makes the button feel like it is not wired.
	if playing == clip_attack and playing != was and _attack > 0.0:
		_clips.seek(attack_start)
