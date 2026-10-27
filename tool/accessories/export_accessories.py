"""Exports Lumi's wardrobe as one small GLB per accessory.

Run headless from the package root:

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \\
        --python tool/accessories/export_accessories.py

Each head accessory is built around a head sphere of radius 0.62 at the
origin facing glTF +Z (Blender -Y), so it drops straight onto the rig's
HeadFx socket. The scarf is built around the NeckFx socket instead. Spring
nodes keep stable names (Pom, ScarfTail, Star, Flower0..8) so the app can
give them secondary motion.
"""

import os
import sys

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import lumi_lib as L  # noqa: E402

OUT = os.path.abspath("assets/accessories")
os.makedirs(OUT, exist_ok=True)

# Mobile-friendly tessellation: smaller spheres, and every piece decimated to
# a few hundred triangles at most.
L.sphere.__defaults__ = ((1, 1, 1), (0, 0, 0), 28, None)
MAX_TRIS_PER_PIECE = 600

HEAD = ["star_sprout", "beanie", "flower_crown", "headphones", "cat_ears", "party_hat"]


def export(name, build):
    L.reset_scene()
    head = bpy.data.objects.new("HeadSocket", None)
    bpy.context.collection.objects.link(head)
    root = bpy.data.objects.new("Root", None)
    bpy.context.collection.objects.link(root)
    # The scarf is placed relative to the body; put the neck point at the
    # origin so it lands on the NeckFx socket.
    pose = dict(L.BASE)
    pose["body"] = (0.0, 0.0, -0.26)
    build(head, root, pose, "aurora")
    # Smooth shading everywhere, and decimate heavy pieces.
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        for p in o.data.polygons:
            p.use_smooth = True
        o.data.calc_loop_triangles()
        tris = len(o.data.loop_triangles)
        if tris > MAX_TRIS_PER_PIECE:
            mod = o.modifiers.new("Decimate", "DECIMATE")
            mod.ratio = MAX_TRIS_PER_PIECE / tris
    path = f"{OUT}/{name}.glb"
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    total = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            total += len(m.loop_triangles)
            ev.to_mesh_clear()
    print(f"EXPORTED {name}: {total} triangles")


def main():
    for name in HEAD:
        export(name, L.ACCESSORIES[name])
    export("scarf", L.ACCESSORIES["scarf"])


main()
