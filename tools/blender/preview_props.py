"""Renders a contact sheet of every prop in assets/environment/props.glb (Workbench).
blender -b --factory-startup --python tools/blender/preview_props.py
"""
import bpy
import math
import os
import numpy as np
from mathutils import Vector

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB = os.path.join(PROJECT, "assets", "environment", "props.glb")
OUT = os.path.join(PROJECT, "docs", "reference", "props_sheet.png")
TILE = 220

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=GLB)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_cavity = True
scene.render.resolution_x = TILE
scene.render.resolution_y = TILE
scene.render.film_transparent = False
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
roots = [o for o in bpy.data.objects if o.parent is None and o.name != "cam"]
roots.sort(key=lambda o: o.name)


def tree(o):
    out = [o]
    for c in o.children:
        out += tree(c)
    return out


tiles = []
names = []
for root in roots:
    for o in roots:
        for x in tree(o):
            x.hide_render = o is not root
    pts = []
    for x in tree(root):
        if x.type == "MESH":
            for c in x.bound_box:
                pts.append(x.matrix_world @ Vector(c))
    if not pts:
        continue
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (mn + mx) / 2
    size = (mx - mn).length
    direction = Vector((0.9, -1.4, 0.7)).normalized()
    cam.location = center + direction * size * 1.15
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 50
    path = os.path.join(PROJECT, "docs", "reference", "_tile.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    arr = np.array(img.pixels[:]).reshape(TILE, TILE, 4)
    bpy.data.images.remove(img)
    tiles.append(arr)
    names.append(root.name)

cols = 10
rows = math.ceil(len(tiles) / cols)
sheet = np.ones((rows * TILE, cols * TILE, 4))
for i, t in enumerate(tiles):
    r = rows - 1 - i // cols
    c = i % cols
    sheet[r * TILE:(r + 1) * TILE, c * TILE:(c + 1) * TILE] = t
out = bpy.data.images.new("sheet", cols * TILE, rows * TILE, alpha=True)
out.pixels = sheet.flatten().tolist()
out.filepath_raw = OUT
out.file_format = "PNG"
out.save()
os.remove(os.path.join(PROJECT, "docs", "reference", "_tile.png"))
print("[preview_props] order:", ", ".join(names))
