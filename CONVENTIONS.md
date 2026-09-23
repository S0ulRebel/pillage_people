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
rewrites the references for you. Moving one from a shell does not: `preload("res://weapon.gd")`
is a plain string in two scripts, and it will still point at nothing afterwards. Either move in
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

## Comments

Explain **why**, not what. The code says what. A comment earns its place by recording something
the next reader cannot recover: a measurement, a constraint, or a thing that was tried and did
not work.

The useful ones in this project all look like that — the blade leaves the fist along `+X`
because the knuckles run index-to-ring along `-X` on these rigs; the foam's anti-aliasing width
may not be clamped because a pixel two hundred metres out spans metres of beach. Both were
wrong once, and the comment is what stops them being wrong again.
