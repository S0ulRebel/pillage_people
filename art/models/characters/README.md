# Modular characters

Bodies and the pieces worn on them. The workshop (`actors/outfit/workshop.tscn`, run it with
F6) lists everything in this folder by itself, sorted by file name. Nothing has to be
registered anywhere.

## Naming

`<slot>_<name>.glb`. The slot is everything before the first underscore:

| Slot | Worn how | Examples |
| --- | --- | --- |
| `body` | the rigged base everything goes on | `body_zombie.glb`, `body_brute.glb` |
| `head` | bends at the neck | `head_zombie_a.glb` |
| `jaw` | rides the head bone | `jaw_zombie.glb` |
| `hair` | rides the head bone | `hair_zombie_messy.glb` |
| `face` | rides the head bone | `face_moustache.glb`, `face_mask_shaman.glb` |
| `hat` | rides the head bone | `hat_tricorn.glb`, `hat_bandana.glb` |
| `shirt` | bends with the body | `shirt_torn.glb` |
| `coat` | bends with the body | `coat_navy.glb`, `coat_vest.glb` |
| `trousers` | bends with the body | `trousers_striped.glb` |
| `waist` | bends with the body | `waist_sash_red.glb`, `waist_belt.glb` |
| `boots` | bends with the body | `boots_buckled.glb`, `boots_sandals.glb` |
| `accessory` | rides one bone, picked in the workshop | `accessory_pendant.glb` |

A file whose name does not start with a slot is ignored.

## Bodies

A body has to be **rigged**, with Mixamo bone names (`mixamorig:Hips`, `mixamorig:Head`, and
so on). Tripo's auto-rig produces those, and so does Mixamo itself. It needs no animations of
its own, because the workshop copies the captain's twelve onto it.

Tripo's rigged export arrives with every bone at the origin, which tears the mesh apart in
Godot. Put it through the repair tool before it goes in here, which also sets its real height:

    python tools/repair_rig.py zombie_3d_model.glb art/models/characters/body_zombie.glb --height 1.8

`tests/outfit_check.gd` fails if a body in this folder still has its bones collapsed.

## Pieces

**Generate every piece in the body's T-pose.** Sleeves must stick out at the same angle as the
body's arms, and trousers must stand with the same gap between the legs. A piece is bent by
copying the weights of the body underneath it, so a sleeve modelled hanging down would be
weighted to the ribs, not the arm.

Pieces that bend (head, shirt, coat, trousers, waist, boots) should arrive **unrigged**. The
workshop gives them the body's weights. A piece that is already rigged to the same bone names
keeps its own weights instead.

Pieces that ride a bone (jaw, hair, face, hat, accessory) are rigid, so rigging them does
nothing useful.

Scale and position do not matter on arrival. The workshop guesses a first fit from the body's
bones: cuffs to the wrists, hat onto the skull, boots on the floor around the feet. From there
you nudge it in the Fit section and press **Save piece**. The fit is saved to
`actors/outfit/pieces/`, and every outfit that wears that piece uses it.

A fit is in metres on the body it was made on. It carries over to bodies of the same build,
but a coat for a thin body will not fit a fat one; a different build wants its own coat.
