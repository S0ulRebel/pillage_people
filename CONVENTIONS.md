# Conventions

Where things go, and how behaviour is split up. Written down now, while the game is small
enough that following it is free, because the alternative is deciding it once per file and
getting a different answer each time.

Every rule here has a reason next to it. If the reason stops applying, change the rule.

---

## Part 1 — Where files go

**Organise by thing, not by file type.** A `scenes/` folder beside a `scripts/` folder looks
tidy with nine files and is unusable with two hundred: every edit means finding the same name
in two places and keeping them in step. Instead, a thing owns a folder, and everything that
belongs only to that thing lives in it.

```
res://
├── main.tscn  main.gd            the entry point, and the orchestrator (see Part 2)
├── actors/                       things that act
│   ├── captain/    captain.gd  captain.tscn
│   ├── grunt/      grunt.gd
│   └── parts/      components shared by more than one actor
├── props/                        things placed in the world
│   ├── rock/       rock.gd  rock.tscn  rocks.gd
│   ├── cargo/  palm/  grass/  waterfall/
├── world/          terrain  ocean  tunnel  heightmaps
├── ui/             hud  health_bar  touch_controls  camera_rig
├── systems/        sfx  music  ambience
├── art/            models/  audio/  references/     data only
├── tests/
└── docs/
```

### The rules

**1. A thing owns a folder.** Its scene, its script, its shader and any resource only it uses
sit together. Never `scenes/rock.tscn` paired with `scripts/rock.gd`.

**2. `art/` is data. If it has a `.gd`, it is not art.** Imported models, audio and reference
images go there; nothing in `art/` is loaded as code. This rule exists because we broke it:
`art/props/rock.gd` is gameplay — collision shapes, scattering, a water-band layer — filed
under art because the rock's *mesh* came from there.

**3. Files are named after their folder.** `grunt/grunt.gd`, not `grunt/enemy.gd`. A folder
whose files are named something else is a folder you have to open to identify.

**4. Name a thing for what it is, not the role it currently plays.** `enemy.gd` does not
survive the second kind of enemy. `grunt.gd` does. The same goes for `player.gd`: there is one
player, but there will be other characters, and what makes him specific is that he is the
captain.

**5. `tests/` is flat and named after what it checks**, not after the file it exercises -
`coastal_smoke.gd`, `ambience_check.gd`, `outline_probe.gd`. Tests cut across folders, so
mirroring the tree would mean choosing one owner for a test that has several.

**6. Shared code moves to a `parts/` or `shared/` folder on its THIRD user, or on a bug -
never in advance.** Two users is a coincidence. See Part 3.

### Moving files

Godot tracks resources by UID, and moving a file **through the editor's FileSystem dock**
rewrites the references for you. Moving one from a shell does not: `preload("res://weapon.gd")` is a plain
string in however many scripts use it, and it will still point at nothing afterwards. Either move in
the editor, or move and fix every `preload`/`load` path in the same commit - and run the tests,
which is what proves it.

---

## Part 2 — How behaviour is split

The pattern is composition: small components that each own one thing, hung off an actor whose
script is a manager rather than a worker. `weapon.gd` already works this way, and how it got
there is the model to copy — it was the captain's alone, and moved out when the grunts needed
to swing back. Extracted on a real second user, for a real reason.

### The rules

**1. One component, one noun.** `Health`. `Knockback`. `Inventory`. If the name needs "and" or
resorts to "Manager", it is two components.

**2. Components never reference each other. The owner wires them.** A component that connects
to another component's signal knows that component exists, which is the coupling you were
trying to remove, moved one step sideways. The actor connects `health.died` to its own handler
and calls the next thing itself.

`main.gd` already does this for sound: the captain emits `attacked`, `hit`, `damaged`,
`stepped`, `splashed`, and `_start_sfx` decides what each one sounds like. Neither the captain
nor the grunts know a sound system exists, and that is why adding ambience later touched
neither of them.

**3. Depend on capabilities, never on owners.** A component may be *handed* a typed thing it
needs — `@export var body: CharacterBody3D`. It may never call `get_parent()`, walk the tree
looking for a sibling, or ask whether its owner `is Captain`. The test is not "would this run
on a rock" — a movement component needs a body and never will. It is: **could this be given to
something else of the same shape without editing it?**

**4. A component that cannot work says so, once, loudly.** Never

```gdscript
if body == null:
    return          # silently does nothing, every frame, forever
```

This is the single most expensive failure mode in this project. In one day it cost three
debugging sessions: grunts wired to an empty scene and dying in silence, a lambda capturing a
counter by value so a test read zero while the thing under test worked, and an encoder argument
that was read, printed, and never applied. All three looked correct from every angle. A
component missing its wiring calls `push_error` once and sets a flag; where it matters, a test
asserts the connection count rather than trusting it.

**5. Wire in code, not in the inspector.** Almost everything here is built from script —
`main.gd` spawns the rocks, grass, palms, cargo, grunts, HUD and audio — and wiring done by
dragging nodes into inspector slots lives inside a `.tscn`, where it cannot be read in a diff
or reviewed. Prefab scenes authored in the editor may use `@export` slots; anything spawned
from code is wired from code.

**6. The actor script decides WHEN. Components decide HOW.** `captain.gd` owns the state — is
he swimming, staggered, mid-swing, dead — and the order things happen in. It does not own the
arithmetic. If a formula is in the actor script, it belongs in a component.

**7. Components are ordinary nodes.** Godot nodes are cheap; a hundred grunts with ten
components each is not the thing that will cost you frames.

---

## Part 3 — When to extract

Not on line count. A long file that does one job is fine; two short files doing the same job
are not.

Extract when **either** of these is true:

- **A third user appears.** One user is a feature. Two is a coincidence and might stay one.
  Three is a pattern, and by then you know which parts are really shared.
- **The same idea exists twice and has drifted.** This is the strong signal, because it has
  already cost you something. The captain and the grunt each grew their own knockback, and they
  disagreed: the captain flew **2.31 m** from a hit the grunt took for **0.43 m**. That is not
  a tidiness problem, it is a bug that only existed because one idea had two implementations.

Do **not** extract because a tutorial has a component for it. Movement and input are one user
and a half here — the captain moves camera-relative with swimming and jumping, the grunt walks
toward a target with `move_toward`. A shared movement component would buy the indirection and
none of the reuse.

## Part 4 — Engine and language practice

Standard Godot and general practice. Nothing here is invented for this project; the project
examples are only there to show where we currently break it.

**1. Call down, signal up.** A parent may call its children. A child talks back by emitting a
signal. A node never reaches upwards or sideways with `get_node("../Sibling")` — that hardcodes
where it happened to sit and breaks on any rename or re-parent.

*Broken in three places:* `world/ocean.gd` and `world/terrain.gd` both do
`get_node_or_null("../Sun")`, and `world/tunnel.gd` does it for `../Terrain`.

**2. A scene is the unit of reuse, and must run on its own.** If a scene only works when
instanced under one particular parent, it is not a scene, it is a fragment. Take external
dependencies as `@export`s and let whoever builds the scene supply them.

**3. Composition over inheritance.** Behaviour goes in nodes you attach, not in a deepening
base-class chain. This is already Part 2 of this document, and it is also the standard Godot
recommendation.

**4. Use static typing.** Typed GDScript is checked at parse time and runs faster than
untyped. Annotate parameters, returns and members.

**5. Physics work belongs in `_physics_process`.** Anything reading or writing physics state,
or moving a body, runs at the fixed tick. `_process` is for things tied to the drawn frame.

**6. Name your collision layers in Project Settings, and always set `collision_mask` on a
query.** Godot provides layer names precisely so that layer 2 is not an anonymous number.

*Currently unused:* no `layer_names` are set at all, and of the project's three spatial queries
only one sets a mask.

**7. Do not allocate in a hot path.** Reuse objects across frames instead of constructing them
per call.

*Broken:* `actors/parts/sword.gd` builds a new `SphereShape3D` and a new
`PhysicsShapeQueryParameters3D` on every call to `targets()`, which runs every physics frame of
the strike window.

**8. Prefer groups or a declared interface over probing for method names.** `has_method("x")`
is a string-keyed contract the compiler cannot check; renaming the method fails silently.
Godot's node groups are the normal way to ask "is this one of those".

*Currently:* seven method names are probed this way — `take_damage` in three files, plus
`reel`, `is_dead`, `boarding` and `set_helming`.

**9. Single responsibility.** A script owns one subject. This is not a line-count rule — see
Part 3 — but `actors/captain/captain.gd` currently owns movement, jumping, swimming, the camera
relationship, combat, the guard, weapon slots, animation, boarding and the ship's wheel.

**10. Constrain exported ranges.** An `@export_range` stops a tunable being given a value that
means nothing. `facing_dot` has one; `max_targets` does not, and at 0 it silently disables the
weapon.

**11. Keep data in Resources, not in code.** Tunables and item definitions belong in `.tres`
files that can be edited and swapped without touching a script — as `HeldItem` now does.

## Comments

Explain **why**, not what. The code says what. A comment earns its place by recording something
the next reader cannot recover: a measurement, a constraint, or a thing that was tried and did
not work.

The useful ones in this project all look like that — the blade leaves the fist along `+X`
because the knuckles run index-to-ring along `-X` on these rigs; the foam's anti-aliasing width
may not be clamped because a pixel two hundred metres out spans metres of beach. Both were
wrong once, and the comment is what stops them being wrong again.

---

## Part 5 — Directions

One rule, and it is not a matter of taste.

### Up means up

**Dragging up makes the thing go up.** The camera, the spyglass, a cannon barrel, anything a
player points. Down means down, forward means forward, backward means backward. There is no
per-system exception and no mode where it reverses.

This is written down because the project had four answers at once, each defensible on its own:

- the chase camera orbited — drag up, swing up and over, end up looking *down* at him
- the spyglass turned like a head — drag up, look *up* — flipped by a second exported flag
  multiplied against the first
- **touch consulted neither flag**, so the same drag on an iPad did the opposite of the mouse
  while glassing
- the cannon's barrel disagreed with all three

Every one had a reason. Together they were unlearnable, because nothing on screen tells the
player which of four rules is in force. The orbit idiom is a real one and we gave it up
deliberately: one rule a hand can learn beats four that are each locally right.

**A limit is not an exception.** Each mode may stop the tilt somewhere different - the chase
camera, the spyglass and a dive all have their own pair of stops, and a dive under water also
has a moving floor, because the camera has to stay in the sea. What none of them may do is
change what the gesture MEANS. Up is up in all of them; they only differ in how far it goes.
If a mode ever wants to hold the view somewhere the player did not ask for, it spends the
picture first - a dive pulls the camera in until the look he asked for fits - and only holds
the view as the very last resort.

### Where the sign belongs

**Screen Y grows downward.** That is the source of almost every inversion here, so convert once,
at the edge, and never again. `ui/touch_controls.gd` subtracts `(last - now)` so that what it
hands on already means *degrees up*; the mouse path negates `motion.y` once. After that point
a positive number means up everywhere, and nothing downstream is allowed to flip it.

**Funnel it.** `CameraRig.tilt(up_degrees)` is the only way the camera pitches. An input path
that applies its own rotation is how touch ended up ignoring the spyglass entirely.

**An `invert` setting is a player preference, not a correction.** It flips every mode together.
Two invert flags multiplied against each other is how the project reached a state where no
combination of them produced up-means-up in both modes.

### Models point -Z

Godot points a node's `-Z` forward, so **a model's front faces `-Z` in the file**. Fix it with
`tools/reorient_model.py`, not with a compensating rotation in code — the same rule the rest of
this document applies to scale and pivots.

The cannon is the worked example. Its muzzle came out of Tripo facing `+Z`, and the code that
elevates the barrel turns it about `+X`, which lifts whatever lies along `-Z`. So pulling up
dropped the muzzle. Nothing in the arithmetic was wrong; the asset was backwards.

**Measure which end is which — do not infer it from shape.** The muzzle was first identified as
the *thinner* end, which is right for a fish's tail and wrong for a cannon: the breech carries a
narrow cascabel knob and the muzzle a wide reinforcing swell. The reliable test was geometric —
trunnions sit nearer the breech, so the muzzle is the end further from the pivot.

That mistake also went into the test, which measured the `-Z` face and asserted it rose. On a
backwards model that face is the breech, and the breech rising is exactly what a dipping muzzle
does. **The check passed on the reported bug.** A test that names the wrong end is worse than no
test at all.

### The two yaw idioms

The project has two, and they differ only by two minus signs: `atan2(v.x, v.z)` points a node's
`+Z` at a target (`actors/captain/captain.gd`, `actors/grunt/grunt.gd`, `world/coastal_study.gd`,
`props/ship/ship.gd`), while `main.gd`'s camera framing and `look_at` point `-Z`. Both are
self-consistent today and nothing moonwalks, so this is recorded rather than fixed — but new
code should use `-Z`, and a sign that silently depends on the old idiom should say so. The one
that does: a dead grunt topples by rotating `-90` about `X`, which lands him on his back only
because `+Z` is his face.
