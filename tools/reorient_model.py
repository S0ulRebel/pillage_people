r"""Turn a rigged GLB the right way up, properly, and write a new one.

Run through Blender, not the ComfyUI python:

    "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" --background --factory-startup ^
        --python reorient_model.py -- <in.glb> <out.glb> --rotate -90 0 0 [--centre] [--scale 0.35] [--faces 800]

Why this exists rather than a rotation on the node in the game:

A skinned mesh carries inverse-bind matrices, and they do not follow a transform written onto
the glTF root. Rotate the node and the skeleton and the skin end up in different spaces, so
the mesh tears - the file still loads, the bounds still look right, and only a render shows
it. prepare_game_model.py says the same thing about SCALE and refuses to bake one onto a
rigged file. This is that lesson applied to rotation.

Done in Blender because Blender rotates the armature and the mesh together and recomputes the
bind poses on export. That is also, implicitly, what a round trip through Mixamo does - which
is why the Tripo characters that went through Mixamo for their animations came out upright and
the ones that did not, did not. Mixamo will not take a model that is not humanoid, so a fish
has to come here instead.

--centre moves the geometry so the model's own middle sits on the origin. Tripo puts the
origin at the BELLY of an animal, which is invisible until something has to rotate the model
about its own spine or place it by its centre - the shark floated 1.80 m clear of the sea for
exactly this reason. It is refused on a rigged model: moving mesh data out from under a
skeleton is the tearing bug again, and a rigged model needs its skeleton moved with it.

--scale resizes the geometry, and is refused on a rigged model for the reason
prepare_game_model.py gives: a scale above a Skeleton3D breaks skinning, so a rigged model has
to carry its size in nodes/root_scale instead. For an unrigged one, baking it into the file is
strictly better - root_scale lives in a .import file, .gitignore drops those, and a fresh clone
then gets the model at its authored size with no warning. That is how the captain arrived at
53% height once already.

--faces decimates at the same time, because every glTF round trip costs something and two
passes cost it twice. simplify_mesh.py is the wrong tool for a Tripo asset: it carries VERTEX
COLOURS across by nearest neighbour, and these models are textured with UVs, which it would
drop. Blender's decimate keeps the UVs.

Tripo in particular exports nose-up for animals. Check with a render, not with the mesh bounds:
a skinned mesh's AABB describes the UNPOSED mesh and will happily tell you a vertical shark is
lying flat.
"""
import sys
from pathlib import Path

import bpy
import mathutils


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    source = Path(argv[0])
    out = Path(argv[1])
    degrees = [0.0, 0.0, 0.0]
    if "--rotate" in argv:
        at = argv.index("--rotate")
        degrees = [float(v) for v in argv[at + 1:at + 4]]
    faces = 0
    if "--faces" in argv:
        faces = int(argv[argv.index("--faces") + 1])
    centre = "--centre" in argv
    scale = 0.0
    if "--scale" in argv:
        scale = float(argv[argv.index("--scale") + 1])

    clear()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(source))
    fresh = [o for o in set(bpy.data.objects) - before]
    if not fresh:
        raise SystemExit("nothing imported")

    from math import radians
    turn = [radians(d) for d in degrees]
    print(f"{source.name}: {len(fresh)} objects, rotating {degrees} degrees")

    # Only the roots. Rotating a child as well as its parent applies the turn twice, and an
    # armature's bones are children of the armature object.
    roots = [o for o in fresh if o.parent is None]
    for obj in roots:
        obj.rotation_mode = "XYZ"
        obj.rotation_euler = (
            obj.rotation_euler[0] + turn[0],
            obj.rotation_euler[1] + turn[1],
            obj.rotation_euler[2] + turn[2],
        )
        print(f"  root: {obj.name} ({obj.type})")

    # Applied, not left on the object. Leaving it is the same bug in a different place: the
    # rotation would be written onto the exported root node and the skin would not follow it.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in fresh:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = fresh[0]
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    if scale > 0.0:
        if any(o.type == "ARMATURE" for o in fresh):
            raise SystemExit("--scale refused: this model is rigged. A scale above a Skeleton3D"
                             " breaks skinning - set nodes/root_scale in the .import instead,"
                             " and un-ignore that .import so a clone still gets it")
        for obj in roots:
            obj.scale = (obj.scale[0] * scale, obj.scale[1] * scale, obj.scale[2] * scale)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in fresh:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = fresh[0]
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        print(f"  scale: x{scale}")

    if centre:
        if any(o.type == "ARMATURE" for o in fresh):
            raise SystemExit("--centre refused: this model is rigged. Moving the mesh out from"
                             " under its skeleton is the tearing bug in another form")
        meshes = [o for o in fresh if o.type == "MESH"]
        if not meshes:
            raise SystemExit("--centre: no mesh to centre")
        # The combined bounds, in world space, so a model split across several meshes moves as
        # one piece rather than stacking every part on the origin.
        lo = [1e30, 1e30, 1e30]
        hi = [-1e30, -1e30, -1e30]
        for obj in meshes:
            for corner in obj.bound_box:
                at = obj.matrix_world @ mathutils.Vector(corner)
                for a in range(3):
                    lo[a] = min(lo[a], at[a])
                    hi[a] = max(hi[a], at[a])
        middle = mathutils.Vector([(lo[a] + hi[a]) * 0.5 for a in range(3)])
        print(f"  centre: bounds ({lo[0]:.3f} {lo[1]:.3f} {lo[2]:.3f})"
              f" to ({hi[0]:.3f} {hi[1]:.3f} {hi[2]:.3f}), middle {tuple(round(v, 3) for v in middle)}")
        # Onto the geometry, not onto the object, for the reason in the module docstring: a
        # translation left on the root would be written into the glTF node and the next tool to
        # read the mesh would see the old, off-centre vertices.
        for obj in meshes:
            obj.location -= middle
        bpy.ops.object.select_all(action="DESELECT")
        for obj in meshes:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

    if faces > 0:
        for obj in fresh:
            if obj.type != "MESH":
                continue
            have = len(obj.data.polygons)
            if have <= faces:
                print(f"  {obj.name}: {have} faces already, left alone")
                continue
            bpy.context.view_layer.objects.active = obj
            modifier = obj.modifiers.new(name="Decimate", type="DECIMATE")
            modifier.ratio = faces / float(have)
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            print(f"  {obj.name}: {have} -> {len(obj.data.polygons)} faces")

    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB",
                              export_skins=True, export_yup=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS")
    print(f"-> {out}")


if __name__ == "__main__":
    main()
