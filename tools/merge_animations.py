r"""Bake a character and a folder of Mixamo clips into one GLB with all its animations.

Run through Blender, not the ComfyUI python:

    "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" --background --factory-startup ^
        --python merge_animations.py -- <character.glb> <animations folder> <out.glb>

The alternative is doing it in the Godot editor: import each clip, build a BoneMap against
SkeletonProfileHumanoid, set the Bone Renamer's skeleton name, reimport, then collect the
results into an AnimationLibrary on the character. Six clips of that is an hour of clicking
that has to be repeated for every character and cannot be checked into the repo.

This works because a Blender action addresses bones by name, and Mixamo's clips and Tripo's
rig use the same mixamorig names - so an action imported with one armature applies to another
without retargeting. Bone names are compared before anything is written, and the export is
refused if they do not line up, because an action that silently matches nothing produces a
character that simply stands still.
"""
import sys
from pathlib import Path

import bpy

# Blender's factory scene runs at 24 fps and the FBX importer OVERWRITES the scene rate from
# whatever file it is reading. So the character arrived keyed at 24 fps and left exported at
# 30, and every clip it already had came out 20% shorter - a captain whose idle, walk and
# slash all silently ran 25% fast, in a file that was otherwise correct. Import and export
# only round-trip when the rate is the same at both ends, so it is pinned here and checked
# again before the write.
FPS = 30


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pin_fps()


def pin_fps():
    """Returns the rate it displaced, or 0 if it was already right."""
    was = bpy.context.scene.render.fps
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    return 0 if was == FPS else was


def armature_in(objects):
    for obj in objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    character = Path(argv[0])
    folder = Path(argv[1])
    out = Path(argv[2])

    clear()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(character))
    rig = armature_in(set(bpy.data.objects) - before)
    if rig is None:
        raise SystemExit("no armature in the character file")
    bones = {b.name for b in rig.data.bones}
    print(f"character: {character.name}, {len(bones)} bones")

    clips = sorted(p for p in folder.iterdir() if p.suffix.lower() in (".fbx", ".glb", ".gltf"))
    if not clips:
        raise SystemExit(f"no clips in {folder}")

    added = []
    for clip in clips:
        existing = set(bpy.data.objects)
        existing_actions = set(bpy.data.actions)
        if clip.suffix.lower() == ".fbx":
            # automatic_bone_orientation MUST stay off. On it, Blender recomputes each
            # bone's roll, so the action's rotations stop meaning the same thing on the
            # character's original bones and the mesh tears apart - while every bone name
            # still matches, so a name check passes and the file looks fine until drawn.
            bpy.ops.import_scene.fbx(filepath=str(clip), ignore_leaf_bones=False,
                                     automatic_bone_orientation=False)
        else:
            bpy.ops.import_scene.gltf(filepath=str(clip))
        fresh = set(bpy.data.objects) - existing
        new_actions = list(set(bpy.data.actions) - existing_actions)

        imported_rig = armature_in(fresh)
        their_bones = {b.name for b in imported_rig.data.bones} if imported_rig else set()
        shared = bones & their_bones
        if not new_actions:
            print(f"  {clip.name}: no animation in this file, skipped")
        elif len(shared) < len(their_bones) * 0.8:
            print(f"  {clip.name}: only {len(shared)} of {len(their_bones)} bones match, skipped")
        else:
            action = new_actions[0]
            action.name = clip.stem
            # A fake user keeps the action alive after the armature it arrived on is deleted;
            # without it Blender drops unused actions and the export comes out empty.
            action.use_fake_user = True
            added.append((clip.stem, action, len(shared), len(their_bones)))

        # The clip's own skeleton and mesh are not wanted - only its motion.
        for obj in fresh:
            bpy.data.objects.remove(obj, do_unlink=True)

    if not added:
        raise SystemExit("nothing matched the character's bones - refusing to write a file "
                         "whose animations would do nothing")

    # Each action goes on its own NLA track so the glTF exporter emits them as separate,
    # named animations rather than one merged timeline.
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = None
    for name, action, _, _ in added:
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, int(action.frame_range[0]), action)

    for name, _, shared, total in added:
        print(f"  {name}: {shared}/{total} bones matched")

    moved = pin_fps()
    if moved:
        print(f"  note: an import moved the scene to {moved} fps; exporting at {FPS}")

    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB",
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_skins=True, export_yup=True)
    print(f"\n{len(added)} animations -> {out}")


if __name__ == "__main__":
    main()
