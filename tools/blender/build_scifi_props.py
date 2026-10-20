"""Procedurally models the sci-fi props for the three facility areas (research lab, alien
reactor, quantum lab) and exports them as one GLB (assets/environment/scifi_props.glb).

Run headless:
  blender -b --factory-startup --python tools/blender/build_scifi_props.py

Conventions (same as build_props.py)
  * Blender Z-up, meters, origin at the prop's base center; Godot gets Y-up via glTF.
    The prop's "front" faces Blender -Y, which is Godot +Z.
  * Material names are identifiers; Godot swaps them for its own shaders (ScifiKit).
  * Moving parts are child objects whose origin is their pivot.
"""
import bpy
import bmesh
import math
import os
import random
from mathutils import Matrix, Vector

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(PROJECT, "assets", "environment", "scifi_props.glb")

MATERIALS = {
    "sf_white": (0.82, 0.84, 0.86), "sf_grey": (0.5, 0.52, 0.55), "sf_dark": (0.12, 0.13, 0.15),
    "sf_metal": (0.6, 0.62, 0.65), "sf_chrome": (0.92, 0.93, 0.95), "sf_rubber": (0.05, 0.05, 0.06),
    "sf_glass": (0.7, 0.85, 0.9), "sf_screen": (0.1, 0.4, 0.5), "sf_light": (1.0, 0.97, 0.9),
    "sf_glow_cyan": (0.3, 0.9, 1.0), "sf_glow_orange": (1.0, 0.55, 0.15), "sf_glow_red": (1.0, 0.2, 0.15),
    "sf_glow_green": (0.3, 1.0, 0.45), "sf_hazard": (0.95, 0.75, 0.1),
    "sf_alien": (0.16, 0.14, 0.2), "sf_alien_glow": (0.4, 1.0, 0.85),
    "sf_quantum": (0.9, 0.9, 0.95), "sf_quantum_glow": (0.75, 0.5, 1.0),
}


def log(*a):
    print("[build_scifi]", *a, flush=True)


def get_material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*MATERIALS[name], 1.0)
    return m


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def R(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


class B:
    """One prop's geometry in a bmesh with per-face materials."""

    def __init__(self, name, smooth_angle=35.0):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.smooth_angle = smooth_angle
        # Per-face marker: 1 once a face has its material. (Tags and "faces after index N"
        # are unreliable: bmesh ops like bevel clear tags and reuse freed face slots.)
        self.done = self.bm.faces.layers.int.new("done")

    def _start(self):
        return 0

    def _finish(self, start, mat, flat=False):
        if mat not in self.mats:
            self.mats.append(mat)
        idx = self.mats.index(mat)
        faces = [f for f in self.bm.faces if f[self.done] == 0]
        for f in faces:
            f.material_index = idx
            f[self.done] = 1
            f.smooth = not flat
        return faces

    def box(self, mat, size, m=Matrix(), bevel=None, segs=2):
        start = self._start()
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
        if bevel is None:
            bevel = min(0.03, min(size) * 0.15)
        if bevel > 0.002:
            edges = list({e for v in res["verts"] for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=segs,
                            profile=0.5, affect="EDGES", clamp_overlap=True)
        return self._finish(start, mat)

    def cyl(self, mat, r1, r2, depth, m=Matrix(), segs=24, caps=True):
        start = self._start()
        bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs, radius1=r1, radius2=r2,
                              depth=depth, matrix=m @ T(0, 0, depth / 2))
        return self._finish(start, mat)

    def lathe(self, mat, profile, m=Matrix(), segs=32):
        start = self._start()
        rings = []
        for (r, z) in profile:
            if r <= 1e-5:
                rings.append([self.bm.verts.new(m @ Vector((0, 0, z)))])
            else:
                rings.append([self.bm.verts.new(m @ Vector((math.cos(2 * math.pi * s / segs) * r, math.sin(2 * math.pi * s / segs) * r, z))) for s in range(segs)])
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if len(a) == 1 and len(b) == 1:
                continue
            for s in range(segs):
                s2 = (s + 1) % segs
                if len(a) == 1:
                    self.bm.faces.new((a[0], b[s], b[s2]))
                elif len(b) == 1:
                    self.bm.faces.new((a[s], b[0], a[s2]))
                else:
                    self.bm.faces.new((a[s], a[s2], b[s2], b[s]))
        return self._finish(start, mat)

    def torus(self, mat, major, minor, m=Matrix(), seg_major=48, seg_minor=12, arc=360.0):
        start = self._start()
        rings = []
        n = seg_major if arc >= 360.0 else seg_major + 1
        for i in range(n):
            a = math.radians(arc) * i / seg_major
            ring = []
            for j in range(seg_minor):
                b = 2 * math.pi * j / seg_minor
                p = Vector(((major + minor * math.cos(b)) * math.cos(a), (major + minor * math.cos(b)) * math.sin(a), minor * math.sin(b)))
                ring.append(self.bm.verts.new(m @ p))
            rings.append(ring)
        count = seg_major if arc >= 360.0 else seg_major
        for i in range(count):
            a, b = rings[i], rings[(i + 1) % len(rings)]
            for j in range(seg_minor):
                j2 = (j + 1) % seg_minor
                self.bm.faces.new((a[j], b[j], b[j2], a[j2]))
        return self._finish(start, mat)

    def tube(self, mat, pts, radius, segs=12):
        start = self._start()
        rings = []
        for i, p in enumerate(pts):
            p = Vector(p)
            d = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
            up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            side = d.cross(up).normalized()
            up2 = side.cross(d).normalized()
            rings.append([self.bm.verts.new(p + (side * math.cos(2 * math.pi * s / segs) + up2 * math.sin(2 * math.pi * s / segs)) * radius) for s in range(segs)])
        for i in range(len(rings) - 1):
            for s in range(segs):
                s2 = (s + 1) % segs
                self.bm.faces.new((rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s]))
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            f = self.bm.faces.new(list(reversed(ring)) if flip else ring)
        return self._finish(start, mat)

    def gear(self, mat, r, depth, teeth=16, tooth=0.25, m=Matrix(), hole=0.0):
        start = self._start()
        pts = []
        steps = teeth * 4
        for i in range(steps):
            a = 2 * math.pi * i / steps
            rr = r + (tooth if (i % 4) in (1, 2) else 0.0)
            pts.append((math.cos(a) * rr, math.sin(a) * rr))
        bottom = [self.bm.verts.new(m @ Vector((x, y, 0))) for x, y in pts]
        top = [self.bm.verts.new(m @ Vector((x, y, depth))) for x, y in pts]
        for i in range(steps):
            i2 = (i + 1) % steps
            self.bm.faces.new((bottom[i], bottom[i2], top[i2], top[i]))
        self.bm.faces.new(list(reversed(bottom)))
        self.bm.faces.new(top)
        return self._finish(start, mat, flat=True)

    def build(self, parent=None, location=(0, 0, 0)):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0003)
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.mats:
            mesh.materials.append(get_material(m))
        try:
            mesh.set_sharp_from_angle(angle=math.radians(self.smooth_angle))
        except Exception:
            pass
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        obj.location = location
        return obj


# --- Surface detail ----------------------------------------------------------------------
# Detail lives in a separate child object "<prop>_detail" (no collision in Godot: ScifiKit only
# builds collision from the root mesh), so the props' shapes and colliders never change.

def detail(parent, fn):
    d = B(parent.name + "_detail", smooth_angle=40)
    fn(d)
    d.build(parent=parent)
    return parent


def bolt(d, x, y, z, face, r=0.012, depth=0.012, mat="sf_metal"):
    """A bolt head on a face pointing along face = '-Y', '+Y', '+X', '-X' or '+Z'."""
    rot = {"-Y": R("X", 90), "+Y": R("X", -90), "+X": R("Y", 90), "-X": R("Y", -90), "+Z": Matrix()}[face]
    d.cyl(mat, r, r * 0.8, depth, T(x, y, z) @ rot, segs=8)


def slats(d, mat, center, size, count, step):
    cx, cy, cz = center
    for i in range(count):
        d.box(mat, size, T(cx, cy, cz + (i - (count - 1) / 2) * step), bevel=0.003)


def cable(d, pts, r=0.022, mat="sf_rubber"):
    d.tube(mat, pts, r, segs=8)


def frame(pos, xa, ya, za):
    """Matrix placing a local box: local X, Y, Z along xa, ya, za, origin at pos."""
    return Matrix(((xa[0], ya[0], za[0], pos[0]), (xa[1], ya[1], za[1], pos[1]),
                   (xa[2], ya[2], za[2], pos[2]), (0.0, 0.0, 0.0, 1.0)))


# ======================================================================================
# RESEARCH LAB
# ======================================================================================

def sf_console():
    b = B("sf_console")
    b.box("sf_white", (1.3, 0.62, 0.78), T(0, 0.04, 0.39))
    b.box("sf_dark", (1.22, 0.58, 0.06), T(0, 0.04, 0.03), bevel=0.01)
    # Sloped control deck.
    b.box("sf_grey", (1.32, 0.5, 0.08), T(0, -0.06, 0.86) @ R("X", -18))
    b.box("sf_screen", (1.1, 0.02, 0.38), T(0, -0.02, 1.12) @ R("X", -12) @ T(0, 0.15, 0.02), bevel=0.004)
    b.box("sf_white", (1.24, 0.06, 0.48), T(0, 0.18, 1.1) @ R("X", -12))
    for i in range(6):
        b.box("sf_glow_cyan" if i % 3 else "sf_glow_orange", (0.09, 0.07, 0.025), T(-0.4 + i * 0.16, -0.2, 0.9) @ R("X", -18), bevel=0.006)
    b.box("sf_dark", (0.06, 0.6, 0.7), T(-0.68, 0.04, 0.38), bevel=0.012)
    b.box("sf_dark", (0.06, 0.6, 0.7), T(0.68, 0.04, 0.38), bevel=0.012)
    return detail(b.build(), _console_detail)


def _console_detail(d):
    slats(d, "sf_dark", (0, -0.278, 0.24), (0.9, 0.02, 0.022), 6, 0.05)
    d.box("sf_grey", (0.96, 0.012, 0.34), T(0, -0.272, 0.24), bevel=0.004)
    for x in (-0.32, 0.32):
        d.box("sf_dark", (0.012, 0.012, 0.62), T(x, -0.276, 0.42), bevel=0.0)
    for x in (-0.58, 0.58):
        for z in (0.08, 0.7):
            bolt(d, x, -0.27, z, "-Y")
    for sx in (-1, 1):
        d.box("sf_chrome", (0.03, 0.34, 0.03), T(sx * 0.735, 0.04, 0.6), bevel=0.008)
        for y in (-0.11, 0.19):
            d.box("sf_chrome", (0.04, 0.025, 0.025), T(sx * 0.718, y, 0.6), bevel=0.0)
        slats(d, "sf_grey", (sx * 0.712, 0.04, 0.3), (0.012, 0.42, 0.02), 5, 0.045)
    for x, dz in ((-0.45, 0.0), (-0.32, 0.02), (0.36, 0.0)):
        d.cyl("sf_dark", 0.025, 0.02, 0.05, T(x, -0.08, 0.9 + dz) @ R("X", -18), segs=10)
    for i, x in enumerate((-0.28, -0.22, 0.24)):
        cable(d, [(x, 0.33, 0.62), (x, 0.4, 0.5), (x + 0.02 * i, 0.43, 0.25), (x + 0.04 * i, 0.45, 0.02)], 0.02)


def sf_table():
    b = B("sf_table")
    b.box("sf_white", (1.7, 0.85, 0.06), T(0, 0, 0.9))
    b.box("sf_metal", (1.66, 0.8, 0.03), T(0, 0, 0.86), bevel=0.008)
    for x in (-0.76, 0.76):
        for y in (-0.34, 0.34):
            b.box("sf_metal", (0.06, 0.06, 0.86), T(x, y, 0.43), bevel=0.01)
    b.box("sf_grey", (1.56, 0.7, 0.03), T(0, 0, 0.28), bevel=0.008)
    return detail(b.build(), _table_detail)


def _table_detail(d):
    # Sample rack with vials, an analyser with a screen, a tablet and a beaker.
    d.box("sf_grey", (0.36, 0.14, 0.05), T(-0.5, 0.18, 0.955), bevel=0.01)
    for i in range(6):
        d.cyl("sf_glass", 0.02, 0.02, 0.14, T(-0.64 + i * 0.056, 0.18, 0.96), segs=10)
        d.cyl("sf_glow_green" if i % 2 else "sf_glow_cyan", 0.016, 0.016, 0.06, T(-0.64 + i * 0.056, 0.18, 0.965), segs=8)
    d.box("sf_white", (0.42, 0.3, 0.22), T(0.38, 0.1, 1.04), bevel=0.03)
    d.box("sf_screen", (0.26, 0.012, 0.12), T(0.38, -0.052, 1.06), bevel=0.003)
    d.cyl("sf_dark", 0.05, 0.05, 0.02, T(0.27, -0.06, 0.99) @ R("X", 90), segs=12)
    d.box("sf_dark", (0.24, 0.17, 0.012), T(-0.05, -0.18, 0.937) @ R("Z", 12), bevel=0.004)
    d.box("sf_screen", (0.21, 0.14, 0.004), T(-0.05, -0.18, 0.944) @ R("Z", 12), bevel=0.0)
    d.lathe("sf_glass", [(0.0, 0.93), (0.05, 0.93), (0.055, 1.04), (0.062, 1.06), (0.0, 1.06)], segs=16)
    for i, x in enumerate((0.3, 0.42)):
        cable(d, [(x, 0.25, 0.98), (x, 0.42, 0.9), (x + 0.05, 0.4, 0.5), (x + 0.1, 0.38, 0.02)], 0.015)


def sf_chamber():
    b = B("sf_chamber", smooth_angle=50)
    b.lathe("sf_grey", [(0.0, 0.0), (0.82, 0.0), (0.82, 0.18), (0.74, 0.24), (0.74, 0.36), (0.0, 0.36)], segs=40)
    b.lathe("sf_glow_cyan", [(0.745, 0.26), (0.76, 0.26), (0.76, 0.32), (0.745, 0.32)], segs=40)
    b.lathe("sf_glass", [(0.66, 0.36), (0.66, 2.16)], segs=40)
    b.lathe("sf_white", [(0.0, 2.16), (0.78, 2.16), (0.82, 2.24), (0.82, 2.4), (0.6, 2.52), (0.0, 2.55)], segs=40)
    for i in range(4):
        a = i * 90 + 45
        b.box("sf_chrome", (0.06, 0.06, 1.82), R("Z", a) @ T(0.7, 0, 1.26), bevel=0.012)
    b.cyl("sf_dark", 0.18, 0.12, 0.25, T(0, 0, 2.5), segs=16)
    return detail(b.build(), _chamber_detail)


def _chamber_detail(d):
    for i in range(16):
        a = math.radians(i * 22.5)
        d.cyl("sf_metal", 0.016, 0.013, 0.014, T(math.cos(a) * 0.78, math.sin(a) * 0.78, 0.18), segs=8)
        d.cyl("sf_metal", 0.016, 0.013, 0.014, T(math.cos(a) * 0.78, math.sin(a) * 0.78, 2.4), segs=8)
    for a in (30, 150, 270):
        r = math.radians(a)
        x, y = math.cos(r), math.sin(r)
        d.tube("sf_metal", [(x * 0.84, y * 0.84, 0.1), (x * 0.92, y * 0.92, 0.14), (x * 0.96, y * 0.96, 0.0)], 0.035, segs=10)
        d.box("sf_dark", (0.12, 0.12, 0.16), T(x * 0.83, y * 0.83, 0.26) @ R("Z", a), bevel=0.02)
    for i in range(3):
        a = math.radians(i * 120 + 60)
        cable(d, [(math.cos(a) * 0.15, math.sin(a) * 0.15, 2.72), (math.cos(a) * 0.3, math.sin(a) * 0.3, 2.82), (math.cos(a) * 0.55, math.sin(a) * 0.55, 2.6)], 0.025)


def sf_rack():
    b = B("sf_rack")
    b.box("sf_dark", (0.72, 0.9, 2.05), T(0, 0, 1.025))
    b.box("sf_grey", (0.66, 0.04, 1.9), T(0, -0.45, 1.02), bevel=0.01)
    for i in range(10):
        b.box("sf_dark", (0.6, 0.02, 0.12), T(0, -0.475, 0.2 + i * 0.18), bevel=0.004)
        b.box("sf_glow_green" if (i * 7) % 3 else "sf_glow_cyan", (0.08, 0.015, 0.02), T(0.22, -0.49, 0.24 + i * 0.18), bevel=0.0)
    return detail(b.build(), _rack_detail)


def _rack_detail(d):
    for sx in (-1, 1):
        slats(d, "sf_grey", (sx * 0.368, 0.0, 1.05), (0.016, 0.62, 0.025), 14, 0.11)
        d.box("sf_chrome", (0.025, 0.025, 0.42), T(sx * 0.3, -0.5, 1.1), bevel=0.006)
        for z in (0.9, 1.3):
            d.box("sf_chrome", (0.025, 0.04, 0.025), T(sx * 0.3, -0.48, z), bevel=0.0)
        for z in (0.12, 1.95):
            bolt(d, sx * 0.31, -0.47, z, "-Y", 0.014)
    d.box("sf_grey", (0.6, 0.5, 0.05), T(0, 0.1, 2.075), bevel=0.01)
    for i in range(4):
        x = -0.2 + i * 0.13
        cable(d, [(x, 0.0, 2.08), (x, 0.05, 2.18), (x, 0.3, 2.22), (x * 0.6, 0.47, 2.2)], 0.024)


def sf_crate():
    b = B("sf_crate")
    b.box("sf_grey", (0.9, 0.9, 0.9), T(0, 0, 0.45), bevel=0.04)
    for z in (0.12, 0.78):
        b.box("sf_hazard", (0.93, 0.93, 0.08), T(0, 0, z), bevel=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box("sf_dark", (0.14, 0.14, 0.92), T(sx * 0.42, sy * 0.42, 0.46), bevel=0.02)
    return detail(b.build(), _crate_detail)


def _crate_detail(d):
    for face, (nx, ny) in (("-Y", (0, -1)), ("+Y", (0, 1)), ("+X", (1, 0)), ("-X", (-1, 0))):
        o = 0.455
        along = (1, 0) if ny else (0, 1)
        cx, cy = nx * o, ny * o
        # Recessed handle, two latches, a stencil plate.
        d.box("sf_dark", (0.3 if ny else 0.03, 0.03 if ny else 0.3, 0.07), T(cx, cy, 0.62), bevel=0.01)
        for k in (-1, 1):
            d.box("sf_metal", (0.06 if ny else 0.025, 0.025 if ny else 0.06, 0.1), T(cx + along[0] * k * 0.22, cy + along[1] * k * 0.22, 0.45), bevel=0.006)
        d.box("sf_white", (0.2 if ny else 0.01, 0.01 if ny else 0.2, 0.09), T(cx + along[0] * 0.12, cy + along[1] * 0.12, 0.3), bevel=0.0)
        for k in (-1, 1):
            for z in (0.2, 0.7):
                bolt(d, cx + along[0] * k * 0.3, cy + along[1] * k * 0.3, z, face, 0.01, 0.01)


def sf_pipe():
    b = B("sf_pipe", smooth_angle=60)
    b.cyl("sf_metal", 0.12, 0.12, 2.0, T(-1.0, 0, 0) @ R("Y", 90), segs=20)
    for x in (-0.98, 0.98):
        b.cyl("sf_grey", 0.17, 0.17, 0.08, T(x - 0.04, 0, 0) @ R("Y", 90), segs=20)
    return b.build()


def sf_arm():
    root = B("sf_arm", smooth_angle=45)
    root.cyl("sf_dark", 0.55, 0.5, 0.25, segs=32)
    root.cyl("sf_hazard", 0.5, 0.5, 0.06, T(0, 0, 0.25), segs=32)
    root.cyl("sf_grey", 0.32, 0.3, 0.5, T(0, 0, 0.3), segs=24)
    base = root.build()
    lower = B("arm_lower", smooth_angle=45)
    lower.cyl("sf_dark", 0.22, 0.22, 0.5, R("X", 90) @ T(0, 0, -0.25), segs=24)
    lower.box("sf_white", (0.26, 0.3, 1.5), T(0, 0, 0.75), bevel=0.06)
    lower.cyl("sf_dark", 0.18, 0.18, 0.42, T(0, 0, 1.5) @ R("X", 90) @ T(0, 0, -0.21), segs=20)
    lower_obj = lower.build(parent=base, location=(0, 0, 0.85))
    upper = B("arm_upper", smooth_angle=45)
    upper.box("sf_white", (0.2, 0.22, 1.2), T(0, 0, 0.6), bevel=0.05)
    upper.cyl("sf_grey", 0.12, 0.1, 0.25, T(0, 0, 1.2), segs=16)
    upper_obj = upper.build(parent=lower_obj, location=(0, 0, 1.5))
    claw = B("arm_claw", smooth_angle=45)
    claw.box("sf_dark", (0.3, 0.16, 0.1), T(0, 0, 0.05), bevel=0.02)
    for sx in (-1, 1):
        claw.box("sf_metal", (0.05, 0.1, 0.3), T(sx * 0.12, 0, 0.22) @ R("Y", -sx * 15), bevel=0.012)
    claw.build(parent=upper_obj, location=(0, 0, 1.45))
    return base


def sf_lamp():
    b = B("sf_lamp")
    b.box("sf_grey", (1.3, 0.45, 0.1), T(0, 0, 0.05))
    b.box("sf_light", (1.18, 0.34, 0.02), T(0, 0, -0.002), bevel=0.004)
    return detail(b.build(), _lamp_detail)


def _lamp_detail(d):
    for sx in (-1, 1):
        d.box("sf_dark", (0.07, 0.48, 0.13), T(sx * 0.665, 0, 0.045), bevel=0.012)
    for i in range(5):
        d.box("sf_grey", (0.018, 0.36, 0.014), T(-0.4 + i * 0.2, 0, -0.016), bevel=0.0)
    d.box("sf_grey", (1.2, 0.018, 0.014), T(0, 0, -0.016), bevel=0.0)


def sf_door():
    frame = B("sf_door")
    for sx in (-1, 1):
        frame.box("sf_grey", (0.35, 0.6, 3.3), T(sx * 1.67, 0, 1.65), bevel=0.04)
        frame.box("sf_hazard", (0.08, 0.62, 2.6), T(sx * 1.52, 0, 1.3), bevel=0.01)
    frame.box("sf_grey", (3.7, 0.6, 0.5), T(0, 0, 3.15), bevel=0.04)
    frame.box("sf_glow_red", (2.4, 0.05, 0.08), T(0, -0.31, 3.15), bevel=0.01)
    fo = detail(frame.build(), _door_detail)
    for sx, nm in ((-1, "door_left"), (1, "door_right")):
        d = B(nm)
        d.box("sf_white", (1.5, 0.22, 2.9), T(-sx * 0.75, 0, 1.45), bevel=0.03)
        d.box("sf_dark", (1.3, 0.24, 0.12), T(-sx * 0.75, 0, 1.6), bevel=0.01)
        d.box("sf_hazard", (0.1, 0.24, 2.6), T(-sx * 0.05, 0, 1.4), bevel=0.01)
        d.build(parent=fo, location=(sx * 1.5, 0, 0))
    return fo


def _door_detail(d):
    for sy, face in ((-1, "-Y"), (1, "+Y")):
        y = sy * 0.305
        for sx in (-1, 1):
            # Hydraulic piston on each jamb.
            d.cyl("sf_chrome", 0.035, 0.035, 1.3, T(sx * 1.67, y + sy * 0.03, 1.1), segs=12)
            d.cyl("sf_dark", 0.06, 0.06, 0.9, T(sx * 1.67, y + sy * 0.03, 2.35), segs=12)
            for z in (0.2, 1.0, 1.8, 2.6):
                for dx in (-0.12, 0.12):
                    bolt(d, sx * 1.67 + dx, y, z, face, 0.014)
        slats(d, "sf_dark", (0.0, y + sy * 0.005, 3.28), (3.0, 0.012, 0.025), 3, 0.06)
        d.box("sf_hazard", (0.5, 0.012, 0.14), T(-1.2, y + sy * 0.006, 3.15), bevel=0.0)
        d.box("sf_hazard", (0.5, 0.012, 0.14), T(1.2, y + sy * 0.006, 3.15), bevel=0.0)


def sf_emitter():
    b = B("sf_emitter")
    b.cyl("sf_dark", 0.32, 0.28, 0.12, segs=24)
    b.cyl("sf_grey", 0.09, 0.09, 0.78, T(0, 0, 0.12), segs=16)
    b.box("sf_white", (0.34, 0.5, 0.26), T(0, 0, 1.0), bevel=0.04)
    b.cyl("sf_dark", 0.09, 0.09, 0.12, T(0, -0.25, 1.0) @ R("X", 90), segs=16)
    b.cyl("sf_glow_red", 0.055, 0.055, 0.02, T(0, -0.37, 1.0) @ R("X", 90), segs=16)
    return detail(b.build(), _emitter_detail)


def _emitter_detail(d):
    for i in range(6):
        d.box("sf_dark", (0.3, 0.022, 0.05), T(0, -0.19 + i * 0.075, 1.155), bevel=0.004)
    for sx in (-1, 1):
        for i in range(4):
            d.box("sf_dark", (0.03, 0.032, 0.18), T(sx * 0.18, -0.12 + i * 0.08, 1.0), bevel=0.003)
    d.torus("sf_dark", 0.115, 0.022, T(0, -0.34, 1.0) @ R("X", 90), seg_major=20, seg_minor=6)
    cable(d, [(0.0, 0.24, 0.95), (0.0, 0.3, 0.82), (0.05, 0.13, 0.5), (0.05, 0.2, 0.08), (0.08, 0.32, 0.01)], 0.018)
    for i in range(6):
        a = math.radians(i * 60 + 30)
        d.cyl("sf_metal", 0.016, 0.013, 0.014, T(math.cos(a) * 0.25, math.sin(a) * 0.25, 0.12), segs=8)


def sf_receiver():
    b = B("sf_receiver", smooth_angle=50)
    b.cyl("sf_dark", 0.34, 0.3, 0.12, segs=24)
    b.cyl("sf_grey", 0.1, 0.1, 0.72, T(0, 0, 0.12), segs=16)
    b.torus("sf_white", 0.24, 0.05, T(0, 0, 1.0) @ R("X", 90), seg_major=32, seg_minor=10)
    b.lathe("sf_glow_cyan", [(0.0, -0.12), (0.17, -0.03), (0.17, 0.03), (0.0, 0.12)], T(0, 0, 1.0) @ R("X", 90), segs=24)
    return detail(b.build(), _receiver_detail)


def _receiver_detail(d):
    for sx in (-1, 1):
        d.tube("sf_chrome", [(0.0, 0.0, 0.82), (sx * 0.2, 0.0, 0.85), (sx * 0.3, 0.0, 1.0)], 0.022, segs=8)
    d.cyl("sf_dark", 0.2, 0.2, 0.04, T(0, 0.07, 1.0) @ R("X", -90), segs=24)
    cable(d, [(0.0, 0.12, 0.9), (0.0, 0.2, 0.62), (0.04, 0.17, 0.2), (0.06, 0.28, 0.01)], 0.018)
    for i in range(6):
        a = math.radians(i * 60)
        d.cyl("sf_metal", 0.016, 0.013, 0.014, T(math.cos(a) * 0.27, math.sin(a) * 0.27, 0.12), segs=8)


def sf_cart():
    b = B("sf_cart")
    b.box("sf_grey", (0.7, 0.62, 0.18), T(0, 0, 0.17), bevel=0.03)
    b.box("sf_hazard", (0.72, 0.64, 0.04), T(0, 0, 0.27), bevel=0.01)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.cyl("sf_rubber", 0.08, 0.08, 0.06, T(sx * 0.26, sy * 0.33, 0.08) @ R("X", 90) @ T(0, 0, -0.03), segs=16)
        b.box("sf_metal", (0.05, 0.05, 1.05), T(sx * 0.3, 0.18, 0.78), bevel=0.01)
    b.box("sf_metal", (0.66, 0.05, 0.05), T(0, 0.18, 1.3), bevel=0.01)
    bo = b.build()
    mirror = B("cart_mirror")
    mirror.box("sf_dark", (0.6, 0.06, 0.6), T(0, 0.02, 0), bevel=0.02)
    mirror.box("sf_chrome", (0.54, 0.02, 0.54), T(0, -0.02, 0), bevel=0.004)
    mo = mirror.build(parent=bo, location=(0, 0, 1.0))
    mo.rotation_euler = (0, 0, math.radians(45))
    return bo


def sf_rail():
    b = B("sf_rail")
    for y in (-0.33, 0.33):
        b.box("sf_metal", (2.0, 0.06, 0.05), T(0, y, 0.025), bevel=0.01)
    for i in range(5):
        b.box("sf_dark", (0.1, 0.8, 0.025), T(-0.8 + i * 0.4, 0, 0.012), bevel=0.004)
    return b.build()


def sf_lever():
    b = B("sf_lever")
    b.box("sf_dark", (0.5, 0.36, 0.55), T(0, 0, 0.275), bevel=0.04)
    b.box("sf_hazard", (0.52, 0.38, 0.05), T(0, 0, 0.5), bevel=0.01)
    bo = b.build()
    h = B("lever_handle")
    h.cyl("sf_metal", 0.035, 0.035, 0.55, R("X", 0), segs=12)
    h.lathe("sf_glow_orange", [(0.0, 0.5), (0.08, 0.53), (0.08, 0.63), (0.0, 0.66)], segs=16)
    ho = h.build(parent=bo, location=(0, 0, 0.55))
    ho.rotation_euler = (math.radians(-30), 0, 0)
    return bo


def sf_coupler():
    b = B("sf_coupler", smooth_angle=50)
    b.lathe("sf_grey", [(0.0, 0.0), (0.42, 0.0), (0.42, 0.18), (0.34, 0.26), (0.0, 0.26)], R("X", -90), segs=32)
    b.cyl("sf_metal", 0.13, 0.13, 0.9, T(-0.45, 0.13, 0) @ R("Y", 90), segs=16)
    b.cyl("sf_metal", 0.13, 0.13, 0.9, T(0, 0.13, 0.0) @ R("Y", 90) @ T(0, 0, 0.0), segs=16)
    bo = b.build()
    w = B("coupler_wheel", smooth_angle=50)
    w.torus("sf_glow_orange", 0.2, 0.025, R("X", 90), seg_major=32, seg_minor=8)
    for i in range(4):
        w.box("sf_metal", (0.4, 0.03, 0.03), R("Y", i * 45), bevel=0.0)
    w.cyl("sf_dark", 0.06, 0.06, 0.06, R("X", 90) @ T(0, 0, -0.03), segs=12)
    w.build(parent=bo, location=(0, -0.32, 0))
    lamp = B("coupler_lamp")
    lamp.lathe("sf_glow_red", [(0.0, 0.0), (0.06, 0.0), (0.06, 0.03), (0.0, 0.06)], R("X", -90), segs=16)
    lamp.build(parent=bo, location=(0, -0.27, 0.32))
    return detail(bo, _coupler_detail)


def _coupler_detail(d):
    for i in range(10):
        a = math.radians(i * 36 + 18)
        bolt(d, math.cos(a) * 0.36, 0.0, math.sin(a) * 0.36, "-Y", 0.016)
    for x in (-0.36, 0.78):
        d.torus("sf_dark", 0.14, 0.024, T(x, 0.13, 0) @ R("Y", 90), seg_major=20, seg_minor=6)
    d.cyl("sf_dark", 0.075, 0.075, 0.035, T(0.27, 0.0, -0.27) @ R("X", 90), segs=16)
    d.cyl("sf_white", 0.062, 0.062, 0.006, T(0.27, -0.035, -0.27) @ R("X", 90), segs=16)
    d.box("sf_dark", (0.01, 0.006, 0.05), T(0.27, -0.042, -0.255) @ R("Y", 35), bevel=0.0)


def sf_projector():
    b = B("sf_projector", smooth_angle=50)
    b.lathe("sf_dark", [(0.0, 0.0), (0.4, 0.0), (0.4, 0.08), (0.3, 0.14), (0.0, 0.14)], segs=32)
    b.lathe("sf_glow_cyan", [(0.0, 0.14), (0.12, 0.14), (0.0, 0.17)], segs=24)
    b.torus("sf_glow_cyan", 0.33, 0.012, T(0, 0, 0.1), seg_major=40, seg_minor=6)
    return b.build()


def sf_lift():
    b = B("sf_lift")
    b.box("sf_grey", (3.2, 3.2, 0.3), T(0, 0, 0.15), bevel=0.05)
    b.box("sf_hazard", (3.24, 3.24, 0.05), T(0, 0, 0.29), bevel=0.01)
    b.box("sf_dark", (2.6, 2.6, 0.02), T(0, 0, 0.31), bevel=0.0)
    for sx in (-1, 1):
        b.box("sf_metal", (0.06, 3.0, 0.06), T(sx * 1.55, 0, 1.0), bevel=0.01)
        for y in (-1.45, 0.0, 1.45):
            b.box("sf_metal", (0.06, 0.06, 0.7), T(sx * 1.55, y, 0.65), bevel=0.01)
    b.box("sf_dark", (0.4, 0.3, 1.1), T(1.2, 1.3, 0.85), bevel=0.04)
    b.box("sf_glow_green", (0.22, 0.04, 0.14), T(1.2, 1.14, 1.2), bevel=0.01)
    return detail(b.build(), _lift_detail)


def _lift_detail(d):
    for i in range(12):
        t = -1.45 + i * (2.9 / 11)
        for face, (x, y) in (("+X", (1.605, t)), ("-X", (-1.605, t)), ("+Y", (t, 1.605)), ("-Y", (t, -1.605))):
            bolt(d, x, y, 0.16, face, 0.016)
    for k in range(6):
        y = -1.1 + k * 0.44
        d.box("sf_rubber", (2.4, 0.06, 0.008), T(0, y, 0.322), bevel=0.0)
    for sx in (-1, 1):
        for sy in (-1, 1):
            d.cyl("sf_chrome", 0.05, 0.05, 0.25, T(sx * 1.45, sy * 1.45, -0.1), segs=12)
    slats(d, "sf_grey", (1.2, 1.145, 0.7), (0.3, 0.012, 0.02), 5, 0.05)


def sf_terminal():
    b = B("sf_terminal")
    b.box("sf_white", (0.7, 0.55, 1.5), T(0, 0, 0.75), bevel=0.05)
    b.box("sf_dark", (0.6, 0.05, 0.42), T(0, -0.28, 1.15), bevel=0.02)
    b.box("sf_screen", (0.52, 0.02, 0.34), T(0, -0.305, 1.15), bevel=0.004)
    b.box("sf_dark", (0.74, 0.58, 0.08), T(0, 0, 0.04), bevel=0.02)
    b.box("sf_hazard", (0.72, 0.57, 0.05), T(0, 0, 0.62), bevel=0.01)
    bo = b.build()
    btn = B("terminal_button")
    btn.cyl("sf_dark", 0.12, 0.12, 0.05, R("X", 90), segs=24)
    btn.cyl("sf_glow_red", 0.09, 0.08, 0.06, R("X", 90) @ T(0, 0, 0.04), segs=24)
    btn.build(parent=bo, location=(0, -0.28, 0.82))
    return detail(bo, _terminal_detail)


def _terminal_detail(d):
    slats(d, "sf_dark", (0, -0.282, 0.32), (0.5, 0.014, 0.022), 6, 0.05)
    for sx in (-1, 1):
        slats(d, "sf_grey", (sx * 0.357, 0.0, 1.0), (0.012, 0.36, 0.02), 7, 0.05)
        d.box("sf_dark", (0.014, 0.42, 0.012), T(sx * 0.356, 0.0, 0.7), bevel=0.0)
        for z in (0.12, 1.42):
            bolt(d, sx * 0.29, -0.275, z, "-Y")
    for i in range(3):
        x = -0.2 + i * 0.2
        cable(d, [(x, 0.28, 1.2), (x, 0.36, 1.0), (x, 0.38, 0.4), (x, 0.4, 0.02)], 0.02)


def sf_shelf():
    b = B("sf_shelf")
    for sx in (-0.78, 0.78):
        for sy in (-0.22, 0.22):
            b.box("sf_metal", (0.05, 0.05, 2.2), T(sx, sy, 1.1), bevel=0.01)
    for z in (0.15, 0.75, 1.35, 1.95):
        b.box("sf_grey", (1.62, 0.5, 0.04), T(0, 0, z), bevel=0.01)
    return b.build()


def sf_grate():
    b = B("sf_grate")
    b.box("sf_grey", (1.3, 0.12, 0.9), T(0, 0, 0.45), bevel=0.03)
    for i in range(7):
        b.box("sf_dark", (1.1, 0.14, 0.05), T(0, -0.01, 0.12 + i * 0.11), bevel=0.0)
    return b.build()


# ======================================================================================
# ALIEN REACTOR
# ======================================================================================

def rx_core():
    b = B("rx_core", smooth_angle=50)
    b.lathe("sf_alien", [(0.0, 0.0), (1.9, 0.0), (1.9, 0.4), (1.5, 0.7), (1.3, 0.7), (0.0, 0.7)], segs=8)
    b.lathe("sf_alien_glow", [(1.92, 0.12), (1.94, 0.12), (1.94, 0.3), (1.92, 0.3)], segs=8)
    b.lathe("sf_glass", [(1.05, 0.7), (1.05, 6.4)], segs=40)
    b.lathe("sf_alien", [(0.0, 6.4), (1.4, 6.4), (1.6, 6.7), (1.2, 7.1), (0.0, 7.2)], segs=8)
    for i in range(3):
        b.torus("sf_alien", 1.12, 0.07, T(0, 0, 1.8 + i * 1.6), seg_major=40, seg_minor=8)
    for i in range(6):
        b.box("sf_alien", (0.14, 0.14, 5.7), R("Z", i * 60) @ T(1.16, 0, 3.55), bevel=0.03)
    return detail(b.build(), _rx_core_detail)


def _rx_core_detail(d):
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        x, y = math.cos(a), math.sin(a)
        d.tube("sf_dark", [(x * 1.6, y * 1.6, 0.5), (x * 1.95, y * 1.95, 0.42), (x * 2.15, y * 2.15, 0.15), (x * 2.2, y * 2.2, 0.0)], 0.09, segs=10)
    for i in range(24):
        a = math.radians(i * 15)
        d.cyl("sf_metal", 0.03, 0.025, 0.03, T(math.cos(a) * 1.7, math.sin(a) * 1.7, 0.4) @ R("Y", 0), segs=8)


def rx_ring():
    b = B("rx_ring", smooth_angle=40)
    b.torus("sf_alien", 6.0, 0.5, seg_major=72, seg_minor=8)
    b.torus("sf_alien_glow", 6.0, 0.52, R("X", 0) @ Matrix.Diagonal((1.0, 1.0, 0.12, 1.0)), seg_major=72, seg_minor=8)
    return b.build()


def rx_gear():
    b = B("rx_gear")
    b.gear("sf_alien", 3.0, 0.6, teeth=18, tooth=0.35)
    b.cyl("sf_metal", 0.6, 0.6, 0.8, T(0, 0, -0.1), segs=24)
    return b.build()


def rx_pylon():
    b = B("rx_pylon", smooth_angle=40)
    b.lathe("sf_alien", [(0.0, 0.0), (1.0, 0.0), (0.9, 0.5), (0.55, 1.0), (0.45, 5.0), (0.25, 6.2), (0.0, 6.4)], segs=6)
    for i in range(16):
        a = i * 50
        z = 1.1 + i * 0.3
        rr = 0.55 - (z - 1.0) * 0.02
        b.box("sf_alien_glow", (0.08, 0.05, 0.22), R("Z", a) @ T(rr, 0, z) @ R("Y", 20), bevel=0.0)
    b.lathe("sf_alien_glow", [(0.0, 6.3), (0.18, 6.45), (0.0, 6.7)], segs=12)
    return detail(b.build(), _pylon_detail)


def _pylon_detail(d):
    for i in range(6):
        a = math.radians(i * 60)
        c, s = math.cos(a), math.sin(a)
        d.tube("sf_dark", [(0.58 * c, 0.58 * s, 1.0), (0.53 * c, 0.53 * s, 3.0), (0.48 * c, 0.48 * s, 5.0), (0.27 * c, 0.27 * s, 6.15)], 0.04, segs=6)
    for z in (1.6, 3.0, 4.4):
        r = 0.55 - 0.025 * (z - 1.0)
        d.torus("sf_alien", r + 0.035, 0.045, T(0, 0, z), seg_major=6, seg_minor=6)
    for i in range(5):
        a = math.radians(i * 72 + 20)
        c, s = math.cos(a), math.sin(a)
        d.tube("sf_alien", [(0.8 * c, 0.8 * s, 0.25), (1.15 * c, 1.15 * s, 0.14), (1.45 * c, 1.45 * s, -0.05), (1.6 * c, 1.6 * s, -0.3)], 0.1, segs=8)
    for i in range(6):
        a = math.radians(i * 60 + 30)
        d.box("sf_alien", (0.05, 0.26, 0.5), R("Z", i * 60 + 30) @ T(0.5, 0, 2.3) @ R("Y", -2), bevel=0.01)


def rx_arm():
    b = B("rx_arm")
    b.cyl("sf_alien", 1.3, 1.3, 0.6, T(0, 0, -0.6), segs=32)
    b.cyl("sf_alien_glow", 1.32, 1.32, 0.08, T(0, 0, -0.12), segs=32)
    b.box("sf_alien", (9.0, 1.6, 0.4), T(4.5, 0, -0.2), bevel=0.06)
    for sy in (-1, 1):
        b.box("sf_alien_glow", (8.6, 0.06, 0.06), T(4.6, sy * 0.78, 0.02), bevel=0.0)
        b.box("sf_alien", (8.4, 0.1, 0.25), T(4.7, sy * 0.75, 0.12), bevel=0.02)
    b.box("sf_alien", (1.8, 1.8, 0.4), T(8.7, 0, -0.2), bevel=0.06)
    return detail(b.build(), _arm_detail)


def _arm_detail(d):
    for sy in (-0.6, 0.6):
        d.box("sf_dark", (6.6, 0.12, 0.12), T(4.75, sy, -0.86), bevel=0.02)
        for k in range(7):
            x0 = 1.45 + k * 0.95
            top, bottom = (x0, sy, -0.42), (x0 + 0.95, sy, -0.82)
            if k % 2:
                top, bottom = (x0 + 0.95, sy, -0.42), (x0, sy, -0.82)
            d.tube("sf_dark", [top, bottom], 0.045, segs=6)
        d.box("sf_dark", (8.0, 0.012, 0.05), T(4.6, sy * 1.343, -0.2), bevel=0.0)
    for k in range(7):
        d.box("sf_dark", (0.1, 1.3, 0.1), T(1.45 + k * 0.95 + (0.95 if k % 2 else 0.0), 0, -0.86), bevel=0.01)
    for i in range(16):
        d.box("sf_metal", (0.06, 0.06, 0.06), R("Z", i * 22.5) @ T(1.31, 0, -0.3), bevel=0.01)


def rx_platform():
    b = B("rx_platform", smooth_angle=30)
    b.lathe("sf_alien", [(0.0, -0.6), (2.3, -0.6), (2.6, -0.2), (2.6, 0.0), (0.0, 0.0)], segs=6)
    b.lathe("sf_alien_glow", [(2.61, -0.14), (2.63, -0.14), (2.63, -0.06), (2.61, -0.06)], segs=6)
    return b.build()


def rx_node():
    b = B("rx_node", smooth_angle=45)
    b.lathe("sf_alien", [(0.0, 0.0), (0.7, 0.0), (0.55, 0.3), (0.3, 0.9), (0.42, 1.1), (0.0, 1.1)], segs=6)
    for i in range(3):
        b.box("sf_alien", (0.1, 0.1, 0.8), R("Z", i * 120) @ T(0.42, 0, 1.4) @ R("Y", -14), bevel=0.02)
    bo = b.build()
    orb = B("node_orb")
    orb.lathe("sf_alien_glow", [(0.0, -0.32), (0.22, -0.22), (0.32, 0.0), (0.22, 0.22), (0.0, 0.32)], segs=20)
    orb.build(parent=bo, location=(0, 0, 1.55))
    return detail(bo, _node_detail)


def _node_detail(d):
    for i in range(6):
        a = math.radians(i * 60 + 30)
        c, s = math.cos(a), math.sin(a)
        d.tube("sf_alien", [(0.55 * c, 0.55 * s, 0.12), (0.8 * c, 0.8 * s, 0.06), (0.98 * c, 0.98 * s, -0.04)], 0.05, segs=6)
    for i in range(3):
        d.box("sf_dark", (0.04, 0.22, 0.32), R("Z", i * 120 + 60) @ T(0.43, 0, 0.55) @ R("Y", -22), bevel=0.008)


def rx_vent():
    b = B("rx_vent")
    b.box("sf_alien", (2.4, 2.4, 0.16), T(0, 0, 0.0), bevel=0.04)
    b.box("sf_hazard", (2.0, 2.0, 0.02), T(0, 0, 0.09), bevel=0.0)
    for i in range(7):
        b.box("sf_dark", (1.7, 0.1, 0.06), T(0, -0.75 + i * 0.25, 0.1), bevel=0.0)
    return b.build()


def rx_valve():
    b = B("rx_valve", smooth_angle=45)
    b.box("sf_alien", (0.9, 0.7, 1.0), T(0, 0, 0.5), bevel=0.06)
    b.box("sf_alien_glow", (0.6, 0.04, 0.12), T(0, -0.36, 0.86), bevel=0.0)
    bo = b.build()
    w = B("valve_wheel", smooth_angle=45)
    w.torus("sf_metal", 0.3, 0.035, R("X", 90), seg_major=32, seg_minor=8)
    for i in range(3):
        w.box("sf_metal", (0.6, 0.04, 0.04), R("Y", i * 60), bevel=0.0)
    w.build(parent=bo, location=(0, -0.42, 0.55))
    return detail(bo, _rx_valve_detail)


def _rx_valve_detail(d):
    for sx in (-1, 1):
        d.tube("sf_metal", [(sx * 0.46, 0.0, 0.7), (sx * 0.62, 0.0, 0.66), (sx * 0.7, 0.0, 0.4), (sx * 0.72, 0.0, 0.0)], 0.06, segs=10)
        d.cyl("sf_dark", 0.09, 0.09, 0.06, T(sx * 0.72, 0.0, 0.0), segs=12)
    slats(d, "sf_dark", (0.0, 0.355, 0.5), (0.6, 0.014, 0.025), 6, 0.06)


def rx_lift():
    b = B("rx_lift")
    b.box("sf_alien", (2.8, 2.8, 0.35), T(0, 0, -0.175), bevel=0.06)
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box("sf_alien_glow", (0.25, 0.25, 0.06), T(sx * 1.2, sy * 1.2, 0.0), bevel=0.0)
    return b.build()


# ======================================================================================
# QUANTUM LAB
# ======================================================================================

def qt_platform():
    b = B("qt_platform", smooth_angle=40)
    b.box("sf_quantum", (3.0, 3.0, 0.45), T(0, 0, -0.225), bevel=0.12, segs=3)
    b.lathe("sf_quantum_glow", [(0.0, -0.5), (0.9, -0.5), (0.0, -0.62)], segs=32)
    b.torus("sf_quantum_glow", 1.1, 0.03, T(0, 0, -0.47), seg_major=40, seg_minor=6)
    return detail(b.build(), _qplatform_detail)


def _qplatform_detail(d):
    for sx, sy, face in ((0, -1, "-Y"), (0, 1, "+Y"), (1, 0, "+X"), (-1, 0, "-X")):
        along = (1, 0) if sy else (0, 1)
        d.box("sf_dark", (2.3 if sy else 0.012, 0.012 if sy else 2.3, 0.04), T(sx * 1.506, sy * 1.506, -0.25), bevel=0.0)
        for k in (-1, 1):
            bolt(d, sx * 1.5 + along[0] * k * 1.15, sy * 1.5 + along[1] * k * 1.15, -0.16, face, 0.016)
    for sx in (-1, 1):
        for sy in (-1, 1):
            d.cyl("sf_dark", 0.16, 0.11, 0.12, T(sx * 1.1, sy * 1.1, -0.57), segs=16)
            d.cyl("sf_quantum", 0.08, 0.08, 0.04, T(sx * 1.1, sy * 1.1, -0.61), segs=12)
    for a in (0, 90, 180, 270):
        d.box("sf_quantum", (0.46, 0.14, 0.1), R("Z", a) @ T(1.24, 0, -0.5), bevel=0.02)


def qt_portal():
    b = B("qt_portal", smooth_angle=40)
    b.torus("sf_quantum", 2.1, 0.28, R("X", 90) @ T(0, 0, 0), seg_major=64, seg_minor=12)
    for i in range(12):
        b.box("sf_quantum_glow", (0.12, 0.6, 0.25), R("Y", i * 30) @ T(0, 0, 2.1), bevel=0.02)
    b.box("sf_quantum", (1.2, 0.8, 0.4), T(0, 0, -2.1), bevel=0.08)
    return detail(b.build(), _portal_detail)


def _portal_detail(d):
    for i in range(24):
        th = math.radians(i * 15 + 7.5)
        radial = (math.sin(th), 0.0, math.cos(th))
        tangent = (math.cos(th), 0.0, -math.sin(th))
        r = 2.36
        p = (radial[0] * r, 0.0, radial[2] * r)
        d.box("sf_quantum", (0.42, 0.64, 0.1), frame(p, tangent, (0.0, 1.0, 0.0), radial), bevel=0.02)
        if i % 2 == 0:
            q = (radial[0] * (r + 0.055), 0.0, radial[2] * (r + 0.055))
            d.box("sf_dark", (0.26, 0.46, 0.02), frame(q, tangent, (0.0, 1.0, 0.0), radial), bevel=0.0)
    for y in (-0.31, 0.31):
        d.torus("sf_dark", 2.1, 0.04, R("X", 90) @ T(0, 0, y), seg_major=64, seg_minor=8)
    for sx in (-1, 1):
        d.tube("sf_chrome", [(sx * 0.5, 0.0, -2.2), (sx * 1.0, 0.0, -1.95), (sx * 1.3, 0.0, -1.62)], 0.05, segs=10)
        for z in (-2.2, -2.0):
            bolt(d, sx * 0.45, -0.4, z, "-Y", 0.018)
            bolt(d, sx * 0.45, 0.4, z, "+Y", 0.018)


def qt_console():
    b = B("qt_console", smooth_angle=40)
    b.lathe("sf_quantum", [(0.0, 0.0), (0.45, 0.0), (0.3, 0.2), (0.18, 0.9), (0.0, 0.9)], segs=24)
    b.box("sf_quantum", (0.9, 0.6, 0.08), T(0, 0, 0.98) @ R("X", -20), bevel=0.03)
    b.box("sf_quantum_glow", (0.8, 0.5, 0.02), T(0, 0, 1.03) @ R("X", -20), bevel=0.005)
    return detail(b.build(), _qconsole_detail)


def _qconsole_detail(d):
    d.torus("sf_chrome", 0.31, 0.022, T(0, 0, 0.2), seg_major=32, seg_minor=6)
    for i in range(4):
        d.box("sf_quantum", (0.13, 0.03, 0.58), R("Z", i * 90 + 45) @ T(0.22, 0, 0.55) @ R("Y", 9), bevel=0.01)
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        d.cyl("sf_metal", 0.018, 0.015, 0.018, T(math.cos(a) * 0.4, math.sin(a) * 0.4, 0.03), segs=8)
    cable(d, [(0.0, 0.16, 0.85), (0.0, 0.3, 0.6), (0.0, 0.42, 0.2), (0.0, 0.5, 0.01)], 0.02)
    for sx in (-1, 1):
        d.box("sf_chrome", (0.03, 0.03, 0.14), T(sx * 0.42, -0.18, 0.88) @ R("X", -20), bevel=0.006)


def qt_pad():
    b = B("qt_pad", smooth_angle=40)
    b.lathe("sf_quantum", [(0.0, 0.0), (1.0, 0.0), (1.0, 0.08), (0.9, 0.12), (0.0, 0.12)], segs=40)
    b.torus("sf_quantum_glow", 0.78, 0.04, T(0, 0, 0.12), seg_major=48, seg_minor=6)
    b.lathe("sf_quantum_glow", [(0.0, 0.12), (0.35, 0.12), (0.0, 0.14)], segs=24)
    return b.build()


def qt_stairs():
    b = B("qt_stairs")
    for i in range(8):
        b.box("sf_quantum", (1.6, 0.5, 0.3), T(0, i * 0.5, 0.15 + i * 0.3), bevel=0.03)
    return b.build()


def qt_blade():
    b = B("qt_blade", smooth_angle=40)
    b.cyl("sf_quantum", 0.6, 0.5, 0.4, segs=24)
    bo = b.build()
    r = B("blade_rotor", smooth_angle=40)
    r.cyl("sf_quantum", 0.35, 0.35, 0.5, T(0, 0, -0.25), segs=20)
    for i in range(3):
        r.box("sf_quantum_glow", (2.6, 0.12, 0.4), R("Z", i * 120) @ T(1.5, 0, 0), bevel=0.04)
    r.build(parent=bo, location=(0, 0, 0.7))
    return bo


def qt_core():
    b = B("qt_core", smooth_angle=40)
    b.lathe("sf_quantum", [(0.0, 0.0), (1.1, 0.0), (0.9, 0.3), (0.5, 0.6), (0.6, 0.8), (0.0, 0.8)], segs=8)
    for i in range(4):
        b.box("sf_quantum", (0.12, 0.12, 1.6), R("Z", i * 90 + 45) @ T(0.75, 0, 1.4) @ R("Y", -10), bevel=0.03)
    bo = b.build()
    c = B("core_crystal", smooth_angle=20)
    c.lathe("sf_quantum_glow", [(0.0, -0.6), (0.32, -0.15), (0.32, 0.15), (0.0, 0.6)], segs=6)
    c.build(parent=bo, location=(0, 0, 1.7))
    return detail(bo, _qcore_detail)


def _qcore_detail(d):
    for i in range(4):
        base = R("Z", i * 90 + 45) @ T(0.75, 0, 1.4) @ R("Y", -10)
        for z in (-0.5, 0.45):
            d.box("sf_dark", (0.2, 0.2, 0.08), base @ T(0, 0, z), bevel=0.015)
    for i in range(16):
        a = math.radians(i * 22.5)
        d.cyl("sf_metal", 0.022, 0.018, 0.02, T(math.cos(a) * 1.0, math.sin(a) * 1.0, 0.08), segs=8)
    for i in range(4):
        a = math.radians(i * 90)
        c, s = math.cos(a), math.sin(a)
        d.tube("sf_dark", [(0.95 * c, 0.95 * s, 0.14), (1.25 * c, 1.25 * s, 0.08), (1.45 * c, 1.45 * s, 0.0)], 0.06, segs=8)


def qt_pillar():
    b = B("qt_pillar", smooth_angle=30)
    b.lathe("sf_quantum", [(0.0, 0.0), (0.7, 0.0), (0.55, 0.25), (0.5, 3.75), (0.7, 4.0), (0.0, 4.0)], segs=12)
    b.torus("sf_quantum_glow", 0.52, 0.025, T(0, 0, 2.0), seg_major=32, seg_minor=6)
    return detail(b.build(), _qpillar_detail)


def _qpillar_detail(d):
    for z in (0.7, 3.3):
        d.torus("sf_chrome", 0.515, 0.03, T(0, 0, z), seg_major=24, seg_minor=6)
    for k in range(6):
        d.box("sf_dark", (0.012, 0.05, 2.4), R("Z", 15 + k * 60) @ T(0.487, 0, 2.0), bevel=0.0)
    for i in range(8):
        a = math.radians(i * 45)
        d.cyl("sf_metal", 0.02, 0.016, 0.02, T(math.cos(a) * 0.6, math.sin(a) * 0.6, 0.1), segs=8)


def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    builders = [sf_console, sf_table, sf_chamber, sf_rack, sf_crate, sf_pipe, sf_arm, sf_lamp, sf_door, sf_emitter,
                sf_receiver, sf_cart, sf_rail, sf_lever, sf_coupler, sf_projector, sf_lift, sf_terminal, sf_shelf, sf_grate,
                rx_core, rx_ring, rx_gear, rx_pylon, rx_arm, rx_platform, rx_node, rx_vent, rx_valve, rx_lift,
                qt_platform, qt_portal, qt_console, qt_pad, qt_stairs, qt_blade, qt_core, qt_pillar]
    for fn in builders:
        fn()
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kwargs = dict(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
                  export_materials="EXPORT", export_animations=False)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(**{k: v for k, v in kwargs.items() if k in props})
    tri = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    roots = [o for o in bpy.data.objects if o.parent is None]
    log("exported", len(roots), "props,", tri, "triangles ->", OUT)


main()
