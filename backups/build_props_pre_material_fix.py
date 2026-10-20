"""Procedurally models every environment prop for Little Bot, Big World and exports them
as one GLB (assets/environment/props.glb).

Run headless:
  blender -b --factory-startup --python tools/blender/build_props.py

Conventions
  * Blender Z-up, meters, origin at the prop's base center (Godot gets Y-up via glTF).
  * Material names are stable identifiers; Godot replaces them with its own shaders.
  * Vertex color: R = ambient occlusion (dark at base), G = sway weight (0 base .. 1 top),
    B = per-part variation, A = petal mask (1 = petal, folds closed when dormant).
  * UV0 on petals = horizontal offset from the flower head center (used to fold petals).
  * Moving parts are child objects with their pivot at the object origin.
"""
import bpy
import bmesh
import math
import os
import random
import sys
from mathutils import Matrix, Vector, noise

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(PROJECT, "assets", "environment", "props.glb")

# name: (base color rgb, roughness, metallic, emission strength)
MATERIALS = {
    "stem": ((0.32, 0.55, 0.18), 0.7, 0.0, 0.0),
    "leaf": ((0.3, 0.58, 0.2), 0.6, 0.0, 0.0),
    "leaf_dark": ((0.16, 0.36, 0.14), 0.6, 0.0, 0.0),
    "leaf_fern": ((0.25, 0.5, 0.18), 0.6, 0.0, 0.0),
    "leaf_clover": ((0.28, 0.56, 0.22), 0.6, 0.0, 0.0),
    "leaf_dry": ((0.45, 0.3, 0.15), 0.8, 0.0, 0.0),
    "petal_white": ((0.95, 0.95, 0.92), 0.5, 0.0, 0.0),
    "petal_pink": ((0.98, 0.62, 0.78), 0.5, 0.0, 0.0),
    "petal_red": ((0.9, 0.25, 0.3), 0.5, 0.0, 0.0),
    "petal_blue": ((0.45, 0.55, 0.95), 0.5, 0.0, 0.0),
    "petal_yellow": ((0.98, 0.82, 0.3), 0.5, 0.0, 0.0),
    "flower_center": ((0.98, 0.72, 0.15), 0.8, 0.0, 0.0),
    "seed_fluff": ((0.95, 0.95, 0.9), 0.9, 0.0, 0.0),
    "glass_petal": ((0.75, 0.85, 1.0), 0.1, 0.0, 0.0),
    "rock": ((0.5, 0.48, 0.45), 0.9, 0.0, 0.0),
    "moss": ((0.32, 0.5, 0.2), 0.95, 0.0, 0.0),
    "bark": ((0.36, 0.27, 0.2), 0.95, 0.0, 0.0),
    "wood": ((0.55, 0.42, 0.28), 0.85, 0.0, 0.0),
    "wood_painted": ((0.85, 0.8, 0.65), 0.8, 0.0, 0.0),
    "mushroom_stem": ((0.92, 0.88, 0.78), 0.8, 0.0, 0.0),
    "mushroom_cap_red": ((0.8, 0.2, 0.15), 0.5, 0.0, 0.0),
    "mushroom_cap_tan": ((0.72, 0.55, 0.36), 0.6, 0.0, 0.0),
    "mushroom_cap_glow": ((0.3, 0.85, 0.9), 0.4, 0.0, 2.0),
    "mushroom_gill": ((0.85, 0.75, 0.6), 0.9, 0.0, 0.0),
    "mushroom_spot": ((0.97, 0.95, 0.9), 0.7, 0.0, 0.0),
    "glow_bulb": ((0.6, 1.0, 0.7), 0.3, 0.0, 3.0),
    "stone": ((0.62, 0.6, 0.55), 0.9, 0.0, 0.0),
    "stone_dark": ((0.38, 0.38, 0.4), 0.85, 0.0, 0.0),
    "stone_carved": ((0.7, 0.67, 0.6), 0.9, 0.0, 0.0),
    "metal_rust": ((0.5, 0.3, 0.2), 0.8, 0.6, 0.0),
    "metal_paint": ((0.3, 0.6, 0.6), 0.6, 0.3, 0.0),
    "metal_cream": ((0.9, 0.86, 0.76), 0.45, 0.2, 0.0),
    "metal_dark": ((0.2, 0.21, 0.23), 0.4, 0.9, 0.0),
    "metal_gold": ((0.9, 0.7, 0.35), 0.3, 1.0, 0.0),
    "rubber": ((0.1, 0.1, 0.11), 0.7, 0.0, 0.0),
    "screen": ((0.05, 0.1, 0.12), 0.2, 0.0, 0.5),
    "mirror": ((0.95, 0.96, 0.98), 0.02, 1.0, 0.0),
    "energy": ((0.35, 0.95, 1.0), 0.3, 0.0, 4.0),
    "conduit_line": ((0.35, 0.95, 1.0), 0.3, 0.0, 4.0),
    "lantern_glow": ((1.0, 0.8, 0.45), 0.4, 0.0, 4.0),
    "crystal_violet": ((0.62, 0.45, 0.95), 0.1, 0.0, 0.5),
    "crystal_teal": ((0.3, 0.85, 0.85), 0.1, 0.0, 0.5),
    "crystal_pink": ((0.95, 0.55, 0.8), 0.1, 0.0, 0.5),
    "crystal_core": ((0.5, 0.9, 1.0), 0.1, 0.0, 1.0),
    "crystal_heart": ((0.95, 0.6, 0.9), 0.05, 0.0, 1.0),
    "crystal_sun": ((1.0, 0.85, 0.5), 0.1, 0.0, 1.0),
    "fragment": ((0.4, 0.95, 1.0), 0.1, 0.0, 3.0),
}


# Hard-surface materials whose boxes get small chamfers (no perfectly sharp CG edges).
BEVEL_MATS = {"stone", "stone_dark", "stone_carved", "wood", "wood_painted", "metal_rust", "metal_paint",
              "metal_cream", "metal_dark"}


def log(*args):
    print("[build_props]", *args)
    sys.stdout.flush()


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def get_material(name):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    color, rough, metal, emit = MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    return mat


class Builder:
    """Accumulates geometry for one prop in a single bmesh with per-face materials."""

    def __init__(self, name, smooth_angle=35.0):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.petals = []      # (faces, center Vector)
        self.no_sway = set()  # face indices that never sway (rigid parts)
        self.smooth_angle = smooth_angle
        self.flat_faces = set()
        self.part_rnd = random.Random(sum(ord(c) for c in name))
        # Created before any geometry: adding a layer later invalidates face references.
        self.var_layer = self.bm.faces.layers.float.new("part_var")

    # -- bookkeeping ---------------------------------------------------------
    def _start(self):
        self.bm.faces.ensure_lookup_table()
        return len(self.bm.faces)

    def _finish(self, start, mat, flat=False):
        self.bm.faces.ensure_lookup_table()
        faces = list(self.bm.faces[start:])
        if mat not in self.mats:
            self.mats.append(mat)
        idx = self.mats.index(mat)
        part_var = self.part_rnd.random()
        for f in faces:
            f.material_index = idx
            f[self.var_layer] = part_var
            if flat:
                self.flat_faces.add(f.index)
        return faces

    # -- primitives ----------------------------------------------------------
    def tube(self, mat, points, radii, segs=8, cap_start=True, cap_end=True, flat=False, noise_amp=0.0, seed=0):
        start = self._start()
        bm = self.bm
        rings = []
        n = len(points)
        prev_normal = None
        for i, p in enumerate(points):
            p = Vector(p)
            if i == 0:
                tangent = (Vector(points[1]) - p).normalized()
            elif i == n - 1:
                tangent = (p - Vector(points[i - 1])).normalized()
            else:
                tangent = (Vector(points[i + 1]) - Vector(points[i - 1])).normalized()
            if prev_normal is None:
                ref = Vector((0, 0, 1)) if abs(tangent.z) < 0.9 else Vector((1, 0, 0))
                normal = tangent.cross(ref).normalized()
            else:
                normal = (prev_normal - tangent * prev_normal.dot(tangent)).normalized()
            prev_normal = normal
            binormal = tangent.cross(normal).normalized()
            r = radii[i] if isinstance(radii, (list, tuple)) else radii
            ring = []
            for s in range(segs):
                a = 2 * math.pi * s / segs
                offset = normal * math.cos(a) + binormal * math.sin(a)
                rr = r
                if noise_amp > 0:
                    rr *= 1.0 + noise_amp * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, i * 0.7 + seed)))
                ring.append(bm.verts.new(p + offset * rr))
            rings.append(ring)
        for i in range(n - 1):
            a, b = rings[i], rings[i + 1]
            for s in range(segs):
                s2 = (s + 1) % segs
                bm.faces.new((a[s], a[s2], b[s2], b[s]))
        if cap_start:
            bm.faces.new(list(reversed(rings[0])))
        if cap_end:
            bm.faces.new(rings[-1])
        return self._finish(start, mat, flat)

    def lathe(self, mat, profile, segs=16, matrix=Matrix(), flat=False, noise_amp=0.0, seed=0.0):
        """profile: list of (radius, z) from bottom to top. Radius 0 makes a pole."""
        start = self._start()
        bm = self.bm
        rings = []
        for (r, z) in profile:
            if r <= 1e-5:
                rings.append([bm.verts.new(matrix @ Vector((0, 0, z)))])
                continue
            ring = []
            for s in range(segs):
                a = 2 * math.pi * s / segs
                rr = r
                if noise_amp > 0:
                    rr *= 1.0 + noise_amp * noise.noise(Vector((math.cos(a) * 1.7, math.sin(a) * 1.7, z * 0.8 + seed)))
                ring.append(bm.verts.new(matrix @ Vector((math.cos(a) * rr, math.sin(a) * rr, z))))
            rings.append(ring)
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                for s in range(segs):
                    bm.faces.new((a[0], b[s], b[(s + 1) % segs]))
            elif len(b) == 1:
                for s in range(segs):
                    bm.faces.new((a[s], b[0], a[(s + 1) % segs]))
                    # orientation fixed below by recalc
            else:
                for s in range(segs):
                    s2 = (s + 1) % segs
                    bm.faces.new((a[s], a[s2], b[s2], b[s]))
        return self._finish(start, mat, flat)

    def ico(self, mat, radius, subdiv=2, matrix=Matrix(), noise_amp=0.0, noise_freq=1.0, seed=0.0, squash=(1, 1, 1), flat=True):
        start = self._start()
        if mat in ("moss", "rock"):
            flat = False  # organic lumps read as soft shapes, not facets
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius, matrix=Matrix())
        for v in res["verts"]:
            co = v.co.copy()
            if noise_amp > 0:
                n = noise.noise(co * noise_freq / max(radius, 0.01) + Vector((seed, seed * 1.3, seed * 0.7)))
                n2 = noise.noise(co * noise_freq * 2.3 / max(radius, 0.01) + Vector((seed * 2, 0, 0)))
                co = co * (1.0 + noise_amp * n + noise_amp * 0.4 * n2)
            co = Vector((co.x * squash[0], co.y * squash[1], co.z * squash[2]))
            v.co = matrix @ co
        return self._finish(start, mat, flat)

    def box(self, mat, size, matrix=Matrix(), flat=True, bevel=None):
        start = self._start()
        m = matrix @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        res = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        if bevel is None:
            bevel = min(0.12, min(size) * 0.08) if mat in BEVEL_MATS else 0.0
        if bevel > 0.004:
            edges = list({e for v in res["verts"] for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, offset_type="OFFSET", segments=2, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
        return self._finish(start, mat, flat)

    def cone(self, mat, r1, r2, depth, segs=12, matrix=Matrix(), flat=False):
        start = self._start()
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2,
                              depth=depth, matrix=matrix @ Matrix.Translation((0, 0, depth / 2)))
        return self._finish(start, mat, flat)

    def strip(self, mat, length, width, curl=0.3, droop=0.0, segs=6, matrix=Matrix(), taper=(0.25, 1.0, 0.0), flat=False, cup=0.0, cols=3):
        """Leaf / petal: a curved strip along +X, width along Y. taper = widths at base, middle, tip."""
        start = self._start()
        bm = self.bm
        rows = []
        for i in range(segs + 1):
            t = i / segs
            if t < 0.5:
                w = taper[0] + (taper[1] - taper[0]) * smoothstep(0, 0.5, t)
            else:
                w = taper[1] + (taper[2] - taper[1]) * smoothstep(0.5, 1.0, t)
            w *= width * 0.5
            x = t * length
            z = math.sin(t * math.pi * 0.5) * curl * length - droop * length * t * t
            row = []
            for j in range(cols):
                sj = -1.0 + 2.0 * j / (cols - 1)
                zc = z + cup * width * sj * sj
                row.append(bm.verts.new(matrix @ Vector((x, sj * w, zc))))
            rows.append(row)
        for i in range(segs):
            a, b = rows[i], rows[i + 1]
            for j in range(cols - 1):
                bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
        return self._finish(start, mat, flat)

    def crystal(self, mat, radius, height, sides=6, tip=0.35, matrix=Matrix(), jitter=0.0, seed=0):
        start = self._start()
        bm = self.bm
        rnd = random.Random(seed)
        bottom, top = [], []
        for s in range(sides):
            a = 2 * math.pi * s / sides + rnd.uniform(-jitter, jitter)
            r = radius * (1.0 + rnd.uniform(-jitter, jitter))
            bottom.append(bm.verts.new(matrix @ Vector((math.cos(a) * r, math.sin(a) * r, 0.0))))
            top.append(bm.verts.new(matrix @ Vector((math.cos(a) * r * 0.92, math.sin(a) * r * 0.92, height * (1 - tip)))))
        apex = bm.verts.new(matrix @ Vector((rnd.uniform(-0.1, 0.1) * radius, rnd.uniform(-0.1, 0.1) * radius, height)))
        for s in range(sides):
            s2 = (s + 1) % sides
            bm.faces.new((bottom[s], bottom[s2], top[s2], top[s]))
            bm.faces.new((top[s], top[s2], apex))
        bm.faces.new(list(reversed(bottom)))
        return self._finish(start, mat, flat=True)

    def mark_petals(self, faces, center):
        self.petals.append((faces, Vector(center)))

    def mark_rigid(self, faces):
        for f in faces:
            self.no_sway.add(f.index)

    # -- output ----------------------------------------------------------------
    def build(self, parent=None, location=(0, 0, 0), sway=True, ao=True):
        bm = self.bm
        bm.normal_update()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        bm.faces.ensure_lookup_table()
        zs = [v.co.z for v in bm.verts] or [0.0]
        zmin, zmax = min(zs), max(zs)
        height = max(zmax - zmin, 0.01)
        col = bm.loops.layers.float_color.new("Col")
        uv = bm.loops.layers.uv.new("UVMap")
        petal_faces = {}
        for faces, center in self.petals:
            for f in faces:
                if f.is_valid:
                    petal_faces[f.index] = center
        var_layer = bm.faces.layers.float.get("part_var")
        for f in bm.faces:
            variation = f[var_layer] if var_layer is not None else 0.5
            for loop in f.loops:
                z = loop.vert.co.z
                occl = 0.55 + 0.45 * smoothstep(zmin, zmin + max(height * 0.3, 0.4), z) if ao else 1.0
                sw = 0.0 if (not sway or f.index in self.no_sway) else max(0.0, min(1.0, (z - zmin) / height))
                petal = 0.0
                uvv = (0.0, 0.0)
                if f.index in petal_faces:
                    c = petal_faces[f.index]
                    petal = 1.0
                    uvv = (loop.vert.co.x - c.x, loop.vert.co.y - c.y)
                loop[col] = (occl, sw, variation, petal)
                loop[uv].uv = uvv
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.mats:
            mesh.materials.append(get_material(m))
        if len(mesh.color_attributes):
            mesh.color_attributes.active_color_index = 0
            mesh.color_attributes.render_color_index = 0
        for poly in mesh.polygons:
            poly.use_smooth = poly.index not in self.flat_faces
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


def rot(axis, deg):
    return Matrix.Rotation(math.radians(deg), 4, axis)


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def S(s):
    return Matrix.Diagonal((s, s, s, 1.0))


# ======================================================================================
# MEADOW
# ======================================================================================

def flower_stem_points(height, bend, lean_dir=0.0, steps=8):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        off = bend * t * t
        pts.append((math.cos(lean_dir) * off, math.sin(lean_dir) * off, t * height))
    return pts


def make_daisy(name, height, petal_mat, petal_count=16, bend=0.7, head_r=0.42, petal_len=1.15, tilt=22.0, seed=0):
    b = Builder(name)
    pts = flower_stem_points(height, bend)
    b.tube("stem", pts, [0.12 - 0.05 * (i / (len(pts) - 1)) for i in range(len(pts))], segs=10, cap_start=False)
    for i, ang in enumerate((20, 160, 260)):
        m = rot("Z", ang) @ T(0.05, 0, 0.05 + i * 0.4) @ rot("Y", -55 + i * 8)
        b.strip("leaf", 1.9 - i * 0.3, 0.42, curl=0.15, droop=0.5, segs=8, matrix=m, cup=0.08, cols=5)
    top = Vector(pts[-1])
    head = T(*top) @ rot("Y", tilt) @ rot("Z", seed * 37)
    b.lathe("flower_center", [(head_r, -0.05), (head_r * 0.95, 0.08), (head_r * 0.7, 0.18), (head_r * 0.3, 0.24), (0, 0.26)], segs=24, matrix=head)
    b.lathe("stem", [(0.13, -0.35), (head_r * 0.85, -0.08), (head_r, -0.05)], segs=16, matrix=head)
    center = head @ Vector((0, 0, 0.05))
    for k in range(petal_count):
        a = 360.0 * k / petal_count
        m = head @ rot("Z", a) @ T(head_r * 0.7, 0, 0.04) @ rot("Y", -8)
        faces = b.strip(petal_mat, petal_len, 0.3, curl=0.12, droop=0.18, segs=6, matrix=m, taper=(0.35, 1.0, 0.55), cup=0.12, cols=5)
        b.mark_petals(faces, center)
    return b.build()


def make_tulip(name, height, seed=0):
    b = Builder(name)
    pts = flower_stem_points(height, 0.35, lean_dir=1.0)
    b.tube("stem", pts, 0.1, segs=10, cap_start=False)
    for i, ang in enumerate((0, 180)):
        m = rot("Z", ang + 30) @ T(0.0, 0, 0.1) @ rot("Y", -72)
        b.strip("leaf", 2.6, 0.75, curl=0.05, droop=0.25, segs=10, matrix=m, cup=0.15, cols=5)
    top = Vector(pts[-1])
    head = T(*top)
    center = head @ Vector((0, 0, 0.0))
    for k in range(6):
        a = 60.0 * k + (30 if k % 2 else 0)
        rr = 0.18 if k % 2 == 0 else 0.24
        m = head @ rot("Z", a) @ T(rr, 0, -0.1) @ rot("Y", -78)
        faces = b.strip("petal_red", 1.2, 0.75, curl=-0.18, droop=0.0, segs=8, matrix=m, taper=(0.5, 1.0, 0.45), cup=0.16, cols=5)
        b.mark_petals(faces, center)
    b.ico("flower_center", 0.22, 2, matrix=head @ T(0, 0, 0.15), flat=False)
    return b.build()


def make_bluebell(name, height):
    b = Builder(name)
    pts = []
    for i in range(10):
        t = i / 9
        x = math.sin(t * math.pi * 0.6) * height * 0.45
        z = math.sin(t * math.pi * 0.75) * height
        pts.append((x, 0, z))
    b.tube("stem", pts, [0.08 - 0.04 * i / 9 for i in range(10)], segs=8, cap_start=False)
    for i, ang in enumerate((0, 200)):
        m = rot("Z", ang) @ rot("Y", -70)
        b.strip("leaf", 2.2, 0.35, curl=0.05, droop=0.35, segs=8, matrix=m, cup=0.1, cols=5)
    for k, t in enumerate((0.45, 0.58, 0.7, 0.82, 0.94)):
        idx = t * 9
        i0 = int(idx)
        f = idx - i0
        p = Vector(pts[i0]).lerp(Vector(pts[min(i0 + 1, 9)]), f)
        side = 0.25 if k % 2 else -0.25
        hang = T(p.x, side, p.z - 0.25)
        b.tube("stem", [p, (p.x, side, p.z - 0.2)], 0.03, segs=4)
        faces = b.lathe("petal_blue", [(0.05, 0.05), (0.16, 0.0), (0.22, -0.12), (0.26, -0.27), (0.31, -0.42), (0.37, -0.51), (0.42, -0.55)], segs=18, matrix=hang)
        b.mark_petals(faces, hang @ Vector((0, 0, 0)))
    return b.build()


def make_dandelion(name, height):
    b = Builder(name)
    pts = flower_stem_points(height, 0.5)
    b.tube("stem", pts, [0.1 - 0.03 * i / 8 for i in range(9)], segs=7, cap_start=False)
    for ang in (30, 150, 270):
        m = rot("Z", ang) @ rot("Y", -80)
        b.strip("leaf", 2.4, 0.5, curl=0.02, droop=0.1, segs=7, matrix=m, taper=(0.3, 1.0, 0.2))
    top = Vector(pts[-1])
    b.ico("flower_center", 0.28, 2, matrix=T(*top), flat=False)
    rnd = random.Random(5)
    for k in range(70):
        # Fibonacci sphere directions
        y = 1 - (k / 69) * 2
        r = math.sqrt(max(0.0, 1 - y * y))
        phi = k * math.pi * (3 - math.sqrt(5))
        d = Vector((math.cos(phi) * r, math.sin(phi) * r, y))
        if d.z < -0.55:
            continue
        p0 = top + d * 0.25
        p1 = top + d * (1.5 + rnd.uniform(-0.1, 0.1))
        b.tube("seed_fluff", [p0, p1], 0.018, segs=3, cap_start=False, cap_end=False)
        tuft = T(*p1) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        b.cone("seed_fluff", 0.02, 0.28, 0.18, segs=6, matrix=tuft)
    return b.build()


def make_clover(name):
    b = Builder(name)
    b.tube("stem", [(0, 0, 0), (0.05, 0, 0.6), (0.08, 0, 1.0)], 0.035, segs=5, cap_start=False)
    top = Vector((0.08, 0, 1.0))
    for k in range(3):
        a = 120 * k
        for side in (-1, 1):
            m = T(*top) @ rot("Z", a + side * 22) @ rot("Y", -8)
            b.strip("leaf_clover", 0.5, 0.42, curl=0.05, droop=0.05, segs=3, matrix=m, taper=(0.1, 1.0, 0.7))
    return b.build()


def make_grass_clump(name, blades=7, height=1.6, seed=0):
    """Thin blades with a folded midrib (V cross-section), varied lean, twist and droop."""
    b = Builder(name, smooth_angle=80)
    rnd = random.Random(seed)
    for k in range(blades):
        a = rnd.uniform(0, 360)
        h = height * rnd.uniform(0.55, 1.15)
        m = (rot("Z", a) @ T(rnd.uniform(0.0, 0.3), 0, 0) @ rot("Y", -90 + rnd.uniform(4, 30))
             @ rot("X", rnd.uniform(-35, 35)))
        b.strip("leaf", h, rnd.uniform(0.07, 0.1), curl=0.0, droop=rnd.uniform(-0.38, -0.05), segs=5, matrix=m,
                taper=(1.0, 0.8, 0.0), cup=0.35)
    return b.build(ao=True)


def _rock_shape(co, radius, seed, amp):
    """The original low-frequency rock silhouette (kept so props keep their dimensions)."""
    n = noise.noise(co * 1.3 / radius + Vector((seed, seed * 1.3, seed * 0.7)))
    n2 = noise.noise(co * 1.3 * 2.3 / radius + Vector((seed * 2, 0, 0)))
    return 1.0 + amp * n + amp * 0.4 * n2


def _rock_bbox(radius, seed, squash, subdiv, amp):
    """Bounding box of the original (pre-detail) rock, used to fit the detailed one."""
    bm = bmesh.new()
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius, matrix=Matrix())
    pts = []
    for v in res["verts"]:
        co = v.co * _rock_shape(v.co, radius, seed, amp)
        pts.append(Vector((co.x * squash[0], co.y * squash[1], co.z * squash[2] + radius * squash[2] * 0.55)))
    bm.free()
    return [min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]


def make_rock(name, radius, seed, squash=(1, 1, 0.7), moss=False, subdiv=2, amp=0.28, detail=4):
    """Fractured rock: the original silhouette plus fine bumps, thin crack grooves and a few
    chipped planar faces, smooth-shaded, then fitted to the original bounding box so stepping
    stones and collision keep their heights."""
    lo, hi = _rock_bbox(radius, seed, squash, subdiv, amp)
    b = Builder(name, smooth_angle=38)
    start = b._start()
    res = bmesh.ops.create_icosphere(b.bm, subdivisions=detail, radius=radius, matrix=Matrix())
    rnd = random.Random(seed * 7 + 3)
    planes = []
    for k in range(4):
        a = rnd.uniform(0, 2 * math.pi)
        planes.append((Vector((math.cos(a), math.sin(a), rnd.uniform(-0.35, 0.3))).normalized(), radius * rnd.uniform(0.74, 0.9)))
    verts = res["verts"]
    for v in verts:
        co = v.co.copy()
        n3 = noise.noise(co * 6.5 / radius + Vector((seed * 3.1, 1.7, 0.3)))
        ridge = 1.0 - abs(noise.noise(co * 3.1 / radius + Vector((0.5, seed * 1.7, 2.0))))
        co = co * (_rock_shape(v.co, radius, seed, amp) + amp * 0.12 * n3 - 0.035 * ridge ** 8)
        for pn, d in planes:
            dd = co.dot(pn) - d
            if dd > 0:
                co -= pn * dd * 0.85
        v.co = Vector((co.x * squash[0], co.y * squash[1], co.z * squash[2]))
    lo2 = [min(v.co[i] for v in verts) for i in range(3)]
    hi2 = [max(v.co[i] for v in verts) for i in range(3)]
    for v in verts:
        v.co = Vector([lo[i] + (v.co[i] - lo2[i]) * (hi[i] - lo[i]) / max(hi2[i] - lo2[i], 1e-6) for i in range(3)])
    faces = b._finish(start, "rock", flat=False)
    if moss:
        idx_moss = None
        for f in faces:
            f.normal_update()
            if f.normal.z > 0.55:
                if "moss" not in b.mats:
                    b.mats.append("moss")
                f.material_index = b.mats.index("moss")
    return b.build(sway=False)


def make_leaf_litter(name, count=9, seed=0):
    """Fallen leaves lying flat in a loose drift (ground clutter)."""
    b = Builder(name, smooth_angle=60)
    rnd = random.Random(seed)
    for k in range(count):
        L = rnd.uniform(0.5, 0.9)
        m = (rot("Z", rnd.uniform(0, 360)) @ T(rnd.uniform(0.0, 1.6), 0, 0.03 + k * 0.004)
             @ rot("Z", rnd.uniform(0, 360)) @ rot("X", rnd.uniform(-12, 12)) @ T(-L / 2, 0, 0))
        b.strip("leaf_dry", L, L * 0.55, curl=rnd.uniform(0.05, 0.2), droop=0.0, segs=4, matrix=m,
                taper=(0.1, 1.0, 0.0), cup=rnd.uniform(0.05, 0.25))
    return b.build(sway=False)


def make_pebble_cluster(name, seed=0):
    b = Builder(name, smooth_angle=40)
    rnd = random.Random(seed)
    for k in range(6):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0.0, 0.9)
        r = rnd.uniform(0.08, 0.22)
        b.ico("rock", r, 2, matrix=T(math.cos(a) * d, math.sin(a) * d, r * 0.3), noise_amp=0.25, noise_freq=1.3,
              seed=seed + k, squash=(1.2, 1.0, 0.6), flat=False)
    return b.build(sway=False)


def make_twig_small(name, seed=0):
    b = Builder(name, smooth_angle=60)
    rnd = random.Random(seed)
    L = rnd.uniform(1.2, 2.0)
    b.tube("bark", [(-L / 2, 0, 0.05), (0, rnd.uniform(-0.1, 0.1), 0.08), (L / 2, rnd.uniform(-0.15, 0.15), 0.05)],
           [0.05, 0.045, 0.03], segs=6)
    b.tube("bark", [(0.1, 0, 0.08), (0.45, 0.35, 0.12)], [0.03, 0.012], segs=5)
    return b.build(sway=False)


def make_twig(name):
    b = Builder(name, smooth_angle=60)
    main = [(-6, 0, 0.45), (-3, 0.3, 0.6), (0, 0, 0.7), (3, -0.4, 0.6), (6, -0.2, 0.45)]
    b.tube("bark", main, [0.62, 0.58, 0.55, 0.48, 0.38], segs=10, noise_amp=0.08, seed=3)
    b.tube("bark", [(1.0, 0, 0.7), (2.5, 1.6, 1.2), (3.6, 3.2, 1.6)], [0.32, 0.24, 0.12], segs=8)
    b.tube("bark", [(-2.0, 0.2, 0.62), (-3.0, -1.3, 1.4)], [0.22, 0.08], segs=6)
    for x in (-5.0, -1.0, 4.0):
        b.ico("moss", 0.5, 1, matrix=T(x, 0, 1.05), squash=(1.6, 0.9, 0.35), noise_amp=0.2)
    return b.build(sway=False)


def make_watering_can(name):
    b = Builder(name, smooth_angle=50)
    # Body lies on its side along +X; open end at +X. Wall made as an outer + inner lathe.
    R = 3.6
    L = 7.5
    wall = 0.25
    lay = T(0, 0, R - 0.6) @ rot("Y", 90) @ T(0, 0, -L / 2)
    b.lathe("metal_rust", [(0.0, 0.0), (R * 0.97, 0.0), (R, 0.15), (R, L * 0.62)], segs=28, matrix=lay)
    b.lathe("metal_paint", [(R, L * 0.62), (R, L * 0.85)], segs=28, matrix=lay)
    b.lathe("metal_rust", [(R, L * 0.85), (R, L), (R + 0.15, L + 0.05), (R - wall, L + 0.05), (R - wall, wall), (0.0, wall)], segs=28, matrix=lay)
    # Spout from the lower side of the body.
    spout = [(-1.0, -2.2, 0.8), (-2.5, -4.8, 1.6), (-3.6, -7.2, 3.2), (-4.2, -8.6, 4.4)]
    b.tube("metal_rust", spout, [0.75, 0.55, 0.42, 0.4], segs=12)
    b.lathe("metal_rust", [(0.4, 0.0), (0.9, 0.5), (1.0, 0.8), (0.0, 0.85)], segs=14,
            matrix=T(-4.2, -8.6, 4.4) @ rot("X", 50))
    # Handle arc on top.
    handle = [(-2.6, 0, 3.0), (-2.6, 0.9, 6.0), (0.0, 1.2, 7.1), (2.6, 0.9, 6.0), (2.6, 0, 3.0)]
    handle = [(p[0], p[1] + 2.4, p[2] + R - 0.6 - 0.2) for p in handle]
    b.tube("metal_rust", handle, 0.32, segs=10)
    return b.build(sway=False)


def make_charging_station(name):
    b = Builder(name, smooth_angle=40)
    b.lathe("metal_dark", [(0.0, 0.0), (0.82, 0.0), (0.82, 0.08), (0.75, 0.12), (0.0, 0.12)], segs=32)
    b.lathe("energy", [(0.62, 0.121), (0.7, 0.121), (0.7, 0.13), (0.62, 0.13)], segs=32)
    b.box("metal_cream", (0.34, 0.28, 1.45), T(0, 0.72, 0.725))
    b.box("metal_dark", (0.36, 0.3, 0.12), T(0, 0.72, 0.06))
    b.box("screen", (0.22, 0.02, 0.16), T(0, 0.575, 1.05))
    arc = [(0, 0.72, 1.4), (0, 0.55, 1.7), (0, 0.15, 1.82), (0, -0.2, 1.7)]
    b.tube("metal_cream", arc, 0.07, segs=8)
    b.lathe("metal_dark", [(0.0, 0.0), (0.2, 0.0), (0.24, -0.12), (0.0, -0.14)], segs=16, matrix=T(0, -0.22, 1.68))
    b.lathe("lantern_glow", [(0.0, -0.13), (0.18, -0.13), (0.0, -0.16)], segs=16, matrix=T(0, -0.22, 1.68))
    for side in (-1, 1):
        cable = [(side * 0.17, 0.8, 0.5), (side * 0.4, 1.0, 0.25), (side * 0.6, 1.4, 0.05), (side * 0.8, 1.9, -0.1)]
        b.tube("rubber", cable, 0.045, segs=6)
    b.box("metal_gold", (0.2, 0.01, 0.08), T(0, 0.575, 0.75))
    return b.build(sway=False)


def make_root_gate(name):
    b = Builder(name, smooth_angle=30)
    for side in (-1, 1):
        x = side * 4.2
        b.box("stone", (2.6, 2.6, 7.0), T(x, 0, 3.5))
        b.box("stone_dark", (3.0, 3.0, 0.6), T(x, 0, 0.3))
        b.box("stone", (3.0, 3.0, 0.5), T(x, 0, 7.25))
        b.ico("moss", 1.2, 1, matrix=T(x + side * 0.3, 0.2, 7.55), squash=(1.4, 1.3, 0.35), noise_amp=0.2)
    b.box("stone", (11.4, 2.8, 1.6), T(0, 0, 8.3))
    b.lathe("stone_carved", [(0.0, -0.2), (1.1, -0.2), (1.1, 0.2), (0.85, 0.25), (0.0, 0.25)], segs=24,
            matrix=T(0, -1.45, 8.3) @ rot("X", 90))
    b.lathe("energy", [(0.55, 0.26), (0.7, 0.26), (0.7, 0.3), (0.55, 0.3)], segs=24, matrix=T(0, -1.45, 8.3) @ rot("X", 90))
    gate = b.build(sway=False)
    # Shutter: a heavy lattice that slides up into the lintel.
    s = Builder("root_gate_shutter", smooth_angle=30)
    for i in range(7):
        x = -2.4 + i * 0.8
        s.box("metal_rust", (0.18, 0.18, 5.6), T(x, 0, 2.8))
    for z in (0.4, 2.0, 3.6, 5.2):
        s.box("metal_rust", (5.6, 0.24, 0.24), T(0, 0, z))
    s.box("metal_dark", (5.8, 0.3, 0.35), T(0, 0, 0.17))
    s.build(parent=gate, location=(0, 0, 0), sway=False)
    return gate


def make_power_pylon(name):
    b = Builder(name, smooth_angle=35)
    b.lathe("stone", [(0.0, 0.0), (0.55, 0.0), (0.55, 0.3), (0.42, 0.38), (0.0, 0.38)], segs=8, flat=True)
    b.lathe("metal_dark", [(0.0, 0.38), (0.18, 0.38), (0.15, 1.35), (0.0, 1.35)], segs=10)
    b.lathe("metal_gold", [(0.12, 1.3), (0.34, 1.38), (0.36, 1.5), (0.28, 1.55), (0.12, 1.5)], segs=16)
    b.crystal("energy", 0.11, 0.45, sides=6, tip=0.35, matrix=T(0, 0, 1.36))
    b.box("metal_gold", (0.04, 0.12, 0.6), T(0, -0.17, 0.85))
    return b.build(sway=False)


def make_plant_stake(name):
    b = Builder(name, smooth_angle=20)
    b.box("wood_painted", (1.4, 0.12, 2.2), T(0, 0, 3.6) @ rot("Y", 6))
    b.box("wood", (0.22, 0.14, 4.2), T(0, 0, 1.9) @ rot("Y", 6))
    b.tube("seed_fluff", [(-0.7, 0, 4.4), (-1.2, 0.3, 2.0), (-1.6, 0.6, 0.1)], 0.03, segs=4)
    return b.build(sway=False)


# ======================================================================================
# FOREST
# ======================================================================================

def make_mushroom(name, height, cap_r, cap_h, cap_mat, spots=True, bend=0.5, seed=0, stem_r=None):
    b = Builder(name, smooth_angle=50)
    stem_r = stem_r or cap_r * 0.16
    pts = flower_stem_points(height, bend, lean_dir=seed)
    radii = []
    for i in range(len(pts)):
        t = i / (len(pts) - 1)
        radii.append(stem_r * (1.5 - 0.6 * smoothstep(0, 0.3, t) + 0.15 * t))
    b.tube("mushroom_stem", pts, radii, segs=20, cap_start=False, noise_amp=0.04, seed=seed)
    top = Vector(pts[-1])
    head = T(*top)
    prof = [(0.0, -0.05)]
    for i in range(1, 9):
        t = i / 8
        r = cap_r * math.sin(t * math.pi * 0.5)
        z = cap_h * math.cos(t * math.pi * 0.5) ** 1.2
        prof.append((r, z))
    prof.append((cap_r * 1.02, -0.12))
    b.lathe(cap_mat, list(reversed([(r, z) for (r, z) in prof[1:]])) + [(0.0, cap_h)], segs=40, matrix=head, noise_amp=0.03, seed=seed)
    b.lathe("mushroom_gill", [(cap_r, -0.12), (cap_r * 0.6, -0.3), (stem_r * 1.3, -0.25), (0.0, -0.2)], segs=40, matrix=head)
    if spots:
        rnd = random.Random(seed + 11)
        for k in range(14):
            t = rnd.uniform(0.15, 0.85)
            a = rnd.uniform(0, 2 * math.pi)
            r = cap_r * math.sin(t * math.pi * 0.5)
            z = cap_h * math.cos(t * math.pi * 0.5) ** 1.2
            n = Vector((math.cos(a) * r / cap_r, math.sin(a) * r / cap_r, z / cap_h * 0.8)).normalized()
            m = head @ T(math.cos(a) * r, math.sin(a) * r, z) @ n.to_track_quat("Z", "Y").to_matrix().to_4x4()
            size = cap_r * rnd.uniform(0.07, 0.13)
            b.ico("mushroom_spot", size, 1, matrix=m, squash=(1, 1, 0.3), flat=False)
    return b.build(sway=False)


def make_mushroom_cluster(name, cap_mat, count=4, scale=1.0, seed=0, glow=False):
    b = Builder(name, smooth_angle=50)
    rnd = random.Random(seed)
    for k in range(count):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0.0, 0.6) * scale
        h = rnd.uniform(0.6, 1.6) * scale
        base = Vector((math.cos(a) * d, math.sin(a) * d, 0))
        top = base + Vector((rnd.uniform(-0.2, 0.2) * scale, rnd.uniform(-0.2, 0.2) * scale, h))
        b.tube("mushroom_stem", [base, base.lerp(top, 0.5) + Vector((0.05, 0, 0)), top], [0.09 * scale, 0.07 * scale, 0.07 * scale], segs=8, cap_start=False)
        cr = rnd.uniform(0.28, 0.5) * scale
        b.lathe(cap_mat, [(cr, -0.04), (cr * 0.9, cr * 0.25), (cr * 0.5, cr * 0.48), (0.0, cr * 0.55)], segs=18, matrix=T(*top))
        b.lathe("mushroom_gill", [(cr, -0.04), (0.0, -0.06)], segs=18, matrix=T(*top))
    return b.build(sway=False)


def make_tree_trunk(name, radius=3.6, height=46.0, seed=0):
    b = Builder(name, smooth_angle=70)
    prof = []
    for i in range(26):
        t = i / 25
        z = t * height
        r = radius * (1.0 + 0.9 * (1 - smoothstep(0, 0.12, t)) - 0.25 * t)
        prof.append((r, z - 1.0))
    b.lathe("bark", prof, segs=32, noise_amp=0.07, seed=seed)
    rnd = random.Random(seed)
    for k in range(7):
        a = k / 7 * 2 * math.pi + rnd.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        reach = radius * rnd.uniform(2.0, 2.8)
        pts = [d * radius * 0.6 + Vector((0, 0, radius * 1.4)), d * radius * 1.3 + Vector((0, 0, radius * 0.6)),
               d * reach * 0.8 + Vector((0, 0, 0.3)), d * reach + Vector((0, 0, -0.6))]
        b.tube("bark", pts, [radius * 0.5, radius * 0.38, radius * 0.22, radius * 0.1], segs=14, noise_amp=0.06, seed=seed + k)
    for k in range(3):
        a = rnd.uniform(0, 2 * math.pi)
        z = height * rnd.uniform(0.55, 0.85)
        d = Vector((math.cos(a), math.sin(a), 0.45)).normalized()
        p0 = Vector((0, 0, z))
        b.tube("bark", [p0, p0 + d * radius * 2.5, p0 + d * radius * 4.0 + Vector((0, 0, 2))], [radius * 0.5, radius * 0.35, radius * 0.2], segs=9)
    for k in range(5):
        a = rnd.uniform(0, 2 * math.pi)
        z = rnd.uniform(2.0, 9.0)
        r = radius * (1.0 + 0.9 * (1 - smoothstep(0, 0.12, (z + 1) / height)))
        m = T(math.cos(a) * r * 0.97, math.sin(a) * r * 0.97, z) @ rot("Z", math.degrees(a))
        b.lathe("mushroom_cap_tan", [(0.0, 0.0), (1.1, 0.0), (1.0, 0.18), (0.0, 0.25)], segs=10, matrix=m @ S(1.0) @ T(0.5, 0, 0))
    return b.build(sway=False)


def make_canopy_leaf(name):
    b = Builder(name)
    b.strip("leaf_dark", 12.0, 5.5, curl=0.08, droop=0.2, segs=14, taper=(0.15, 1.0, 0.05), cup=0.25, matrix=T(-6, 0, 0), cols=7)
    b.tube("stem", [(-6.5, 0, 0.0), (5.5, 0, 0.3)], 0.12, segs=5)
    return b.build(sway=True)


def make_root_arch(name):
    b = Builder(name, smooth_angle=60)
    pts = []
    for i in range(11):
        t = i / 10
        pts.append((-5.0 + t * 10.0, math.sin(t * 2.2) * 0.8, math.sin(t * math.pi) * 3.8 - 0.4))
    b.tube("bark", pts, [0.9, 0.85, 0.8, 0.75, 0.7, 0.68, 0.66, 0.65, 0.7, 0.8, 0.95], segs=10, noise_amp=0.1, seed=4)
    b.ico("moss", 0.9, 1, matrix=T(0.0, 0.2, 3.9), squash=(2.0, 0.9, 0.35), noise_amp=0.25)
    return b.build(sway=False)


def make_log_hollow(name):
    b = Builder(name, smooth_angle=60)
    Ro, Ri, L = 2.1, 1.65, 14.0
    lay = T(-L / 2, 0, Ro - 0.45) @ rot("Y", 90)
    b.lathe("bark", [(Ro * 1.05, 0.0), (Ro, 0.4), (Ro * 0.98, L * 0.5), (Ro * 1.02, L - 0.4), (Ro * 1.06, L)], segs=22, matrix=lay, noise_amp=0.05, seed=7)
    b.lathe("wood", [(Ro * 1.06, L), (Ri, L)], segs=22, matrix=lay)
    b.lathe("wood", [(Ri, L), (Ri * 1.02, L * 0.5), (Ri, 0.0)], segs=22, matrix=lay)
    b.lathe("wood", [(Ri, 0.0), (Ro * 1.05, 0.0)], segs=22, matrix=lay)
    for x in (-4.5, -1.0, 2.5, 5.5):
        b.ico("moss", 1.1, 1, matrix=T(x, 0.2, Ro * 2 - 0.55), squash=(1.8, 1.3, 0.4), noise_amp=0.25)
    b.mark_rigid([])
    return b.build(sway=False)


def make_fern(name, seed=0):
    b = Builder(name)
    rnd = random.Random(seed)
    for k in range(7):
        a = k / 7 * 360 + rnd.uniform(-15, 15)
        length = rnd.uniform(2.4, 3.2)
        pts = []
        for i in range(7):
            t = i / 6
            pts.append(Vector((t * length * 0.8, 0, math.sin(t * math.pi * 0.65) * length * 0.6)))
        m = rot("Z", a)
        pts_w = [m @ p for p in pts]
        b.tube("stem", pts_w, 0.04, segs=4)
        for i in range(1, 6):
            t = i / 6
            p = pts[i]
            for side in (-1, 1):
                lm = m @ T(p.x, 0, p.z) @ rot("Z", side * 70) @ rot("Y", 10)
                b.strip("leaf_fern", 0.7 * (1.1 - t), 0.2, curl=0.0, droop=0.3, segs=3, matrix=lm, taper=(0.4, 1.0, 0.1))
    return b.build()


def make_glow_bulb(name):
    b = Builder(name)
    pts = flower_stem_points(2.4, 0.4)
    b.tube("stem", pts, 0.05, segs=5, cap_start=False)
    top = Vector(pts[-1])
    b.ico("glow_bulb", 0.28, 2, matrix=T(*top) @ T(0, 0, -0.05), squash=(1, 1, 1.25), flat=False)
    for ang in (40, 220):
        b.strip("leaf", 1.1, 0.4, curl=0.1, droop=0.3, segs=4, matrix=rot("Z", ang) @ T(0, 0, 0.6) @ rot("Y", -30))
    return b.build()


def make_bridge_machine(name):
    b = Builder(name, smooth_angle=30)
    b.box("stone", (2.6, 2.2, 1.8), T(0, 0, 0.9))
    b.box("stone_dark", (2.8, 2.4, 0.3), T(0, 0, 1.95))
    b.box("metal_rust", (0.5, 0.5, 0.9), T(-0.8, -1.2, 0.9))
    b.box("metal_dark", (1.2, 0.1, 0.5), T(0.5, -1.12, 1.2))
    b.lathe("energy", [(0.0, 0.0), (0.14, 0.0), (0.14, 0.05), (0.0, 0.05)], segs=12, matrix=T(0.5, -1.18, 1.2) @ rot("X", 90))
    machine = b.build(sway=False)
    g = Builder("bridge_gear", smooth_angle=20)
    g.lathe("metal_rust", [(0.0, -0.12), (0.9, -0.12), (0.9, 0.12), (0.0, 0.12)], segs=24, flat=True)
    for k in range(12):
        a = k * 30
        g.box("metal_rust", (0.22, 0.28, 0.24), rot("Z", a) @ T(1.0, 0, 0))
    g.lathe("metal_dark", [(0.0, -0.2), (0.25, -0.2), (0.25, 0.2), (0.0, 0.2)], segs=12)
    g.build(parent=machine, location=(1.45, 0.0, 1.1), sway=False)
    machine.children[0].rotation_euler = (0, math.radians(90), 0)
    lever = Builder("bridge_lever", smooth_angle=20)
    lever.box("metal_dark", (0.12, 0.12, 0.9), T(0, 0, 0.45))
    lever.ico("rubber", 0.12, 1, matrix=T(0, 0, 0.92), flat=False)
    lever.build(parent=machine, location=(-0.8, -1.2, 1.35), sway=False)
    return machine


def make_valve_switch(name):
    b = Builder(name, smooth_angle=30)
    b.tube("metal_rust", [(0, 0.6, -0.3), (0, 0.3, 0.2), (0, 0.0, 0.55)], 0.16, segs=10)
    b.lathe("metal_dark", [(0.0, 0.5), (0.24, 0.5), (0.24, 0.72), (0.0, 0.72)], segs=12)
    b.lathe("energy", [(0.0, 0.72), (0.1, 0.72), (0.08, 0.8), (0.0, 0.8)], segs=10, matrix=T(0.3, 0, 0))
    b.lathe("metal_dark", [(0.0, 0.0), (0.06, 0.0), (0.06, 0.72), (0.0, 0.72)], segs=6, matrix=T(0.3, 0, 0))
    valve = b.build(sway=False)
    w = Builder("valve_wheel", smooth_angle=30)
    ring = [(math.cos(a / 16 * 2 * math.pi) * 0.42, math.sin(a / 16 * 2 * math.pi) * 0.42, 0) for a in range(17)]
    w.tube("metal_paint", ring, 0.05, segs=6, cap_start=False, cap_end=False)
    for k in range(4):
        a = k * math.pi / 2
        w.tube("metal_paint", [(0, 0, 0), (math.cos(a) * 0.42, math.sin(a) * 0.42, 0)], 0.035, segs=5)
    w.lathe("metal_dark", [(0.0, -0.06), (0.09, -0.06), (0.09, 0.06), (0.0, 0.06)], segs=10)
    w.build(parent=valve, location=(0, 0, 0.82), sway=False)
    return valve


def make_pipe_segment(name):
    b = Builder(name, smooth_angle=50)
    lay = rot("Y", 90) @ T(0, 0, -3.0)
    b.lathe("metal_rust", [(1.2, 0.0), (1.2, 6.0)], segs=20, matrix=T(0, 0, 0.9) @ lay)
    b.lathe("metal_rust", [(1.2, 6.0), (1.0, 6.0), (1.0, 0.0), (1.2, 0.0)], segs=20, matrix=T(0, 0, 0.9) @ lay)
    b.lathe("metal_dark", [(1.32, 2.6), (1.32, 3.2)], segs=20, matrix=T(0, 0, 0.9) @ lay)
    return b.build(sway=False)


# ======================================================================================
# SHRINE
# ======================================================================================

def make_pillar(name, broken=False, seed=0):
    b = Builder(name, smooth_angle=25)
    b.box("stone_dark", (1.6, 1.6, 0.5), T(0, 0, 0.25))
    b.box("stone", (1.35, 1.35, 0.3), T(0, 0, 0.65))
    h = 3.0 if broken else 5.2
    prof = [(0.6, 0.8), (0.55, 1.2), (0.52, h * 0.6), (0.5, h)]
    b.lathe("stone", prof, segs=12, flat=False, noise_amp=0.03, seed=seed)
    if broken:
        rnd = random.Random(seed)
        bm = b.bm
        top_verts = [v for v in bm.verts if abs(v.co.z - h) < 0.01]
        for v in top_verts:
            v.co.z += rnd.uniform(-0.5, 0.4)
        b.ico("stone", 0.55, 1, matrix=T(1.4, 0.6, 0.3), squash=(1.2, 0.9, 0.6), noise_amp=0.2, seed=seed)
    else:
        b.box("stone", (1.35, 1.35, 0.35), T(0, 0, h + 0.17))
        b.box("stone_dark", (1.6, 1.6, 0.25), T(0, 0, h + 0.47))
    b.ico("moss", 0.7, 1, matrix=T(0.3, 0.2, 0.55), squash=(1.4, 1.3, 0.3), noise_amp=0.3, seed=seed)
    return b.build(sway=False)


def make_arch(name):
    b = Builder(name, smooth_angle=25)
    for side in (-1, 1):
        b.box("stone_dark", (1.5, 1.5, 0.5), T(side * 3.2, 0, 0.25))
        b.box("stone", (1.2, 1.2, 4.5), T(side * 3.2, 0, 2.75))
    n = 11
    for k in range(n):
        a0 = math.pi * k / n
        a1 = math.pi * (k + 1) / n
        am = (a0 + a1) / 2
        x = math.cos(am) * 3.2
        z = 5.0 + math.sin(am) * 3.2
        b.box("stone", (0.95, 1.2, 1.0), T(x, 0, z) @ rot("Y", -math.degrees(am) + 90))
    b.ico("moss", 0.8, 1, matrix=T(-1.0, 0.0, 8.2), squash=(1.6, 1.0, 0.3), noise_amp=0.3)
    return b.build(sway=False)


def make_wall(name, broken=True, seed=0):
    b = Builder(name, smooth_angle=20)
    rnd = random.Random(seed)
    for row in range(5):
        x = -2.5 + (0.5 if row % 2 else 0.0)
        while x < 2.5:
            w = rnd.uniform(0.8, 1.3)
            w = min(w, 2.5 - x)
            if broken and row >= 3 and rnd.random() < 0.35 + row * 0.1:
                x += w
                continue
            b.box("stone", (w - 0.04, 0.9, 0.68), T(x + w / 2, rnd.uniform(-0.03, 0.03), row * 0.7 + 0.35))
            x += w
    b.ico("moss", 0.9, 1, matrix=T(rnd.uniform(-1.5, 1.5), 0, 2.1), squash=(1.8, 0.9, 0.3), noise_amp=0.3)
    return b.build(sway=False)


def make_stairs(name, steps=8, width=6.0, rise=0.32, run=0.62):
    b = Builder(name, smooth_angle=10)
    for i in range(steps):
        b.box("stone", (width, run, rise * (i + 1)), T(0, -i * run, rise * (i + 1) / 2))
    for side in (-1, 1):
        b.box("stone_dark", (0.6, run * steps, rise * steps + 0.4), T(side * (width / 2 + 0.3), -run * (steps - 1) / 2, (rise * steps + 0.4) / 2))
    return b.build(sway=False)


def make_shrine_core(name):
    b = Builder(name, smooth_angle=30)
    b.lathe("stone_dark", [(0.0, 0.0), (4.2, 0.0), (4.2, 0.4), (3.6, 0.45), (3.6, 0.85), (2.8, 0.9), (2.8, 1.3), (0.0, 1.3)], segs=32, flat=False)
    b.lathe("energy", [(3.0, 1.31), (3.1, 1.31), (3.1, 1.33), (3.0, 1.33)], segs=32)
    for k in range(8):
        a = k * 45
        b.box("stone_carved", (0.5, 0.5, 0.25), rot("Z", a) @ T(3.9, 0, 0.5))
    core = b.build(sway=False)

    def ring(rname, radius, thickness, height):
        r = Builder(rname, smooth_angle=30)
        r.lathe("metal_gold", [(radius, -height), (radius + thickness, -height), (radius + thickness, height), (radius, height), (radius, -height)], segs=40, flat=False)
        r.lathe("energy", [(radius + thickness + 0.005, -height * 0.25), (radius + thickness + 0.005, height * 0.25)], segs=40)
        return r

    ring("core_ring_outer", 2.6, 0.16, 0.18).build(parent=core, location=(0, 0, 3.6), sway=False)
    ring("core_ring_mid", 1.95, 0.14, 0.15).build(parent=core, location=(0, 0, 3.6), sway=False)
    ring("core_ring_inner", 1.35, 0.12, 0.12).build(parent=core, location=(0, 0, 3.6), sway=False)
    orb = Builder("core_orb", smooth_angle=20)
    orb.ico("crystal_core", 0.75, 1, flat=True)
    orb.build(parent=core, location=(0, 0, 3.6), sway=False)
    return core


def make_power_node(name):
    b = Builder(name, smooth_angle=20)
    b.lathe("stone_dark", [(0.0, 0.0), (1.0, 0.0), (1.0, 0.3), (0.7, 0.35), (0.6, 1.2), (0.8, 1.35), (0.8, 1.5), (0.0, 1.5)], segs=8, flat=True)
    b.lathe("energy", [(0.62, 1.0), (0.64, 1.0), (0.64, 1.08), (0.62, 1.08)], segs=8)
    node = b.build(sway=False)
    c = Builder("node_crystal")
    c.crystal("crystal_core", 0.28, 0.9, sides=6, tip=0.3, matrix=T(0, 0, -0.45))
    c.crystal("crystal_core", 0.28, 0.5, sides=6, tip=0.5, matrix=T(0, 0, -0.45) @ rot("X", 180))
    c.build(parent=node, location=(0, 0, 2.2), sway=False)
    return node


def make_mirror_pedestal(name):
    b = Builder(name, smooth_angle=20)
    b.lathe("stone", [(0.0, 0.0), (0.7, 0.0), (0.7, 0.25), (0.45, 0.3), (0.4, 0.9), (0.55, 1.0), (0.0, 1.0)], segs=8, flat=True)
    ped = b.build(sway=False)
    h = Builder("mirror_head", smooth_angle=30)
    h.box("metal_gold", (0.12, 0.12, 0.5), T(-0.75, 0, 0.25))
    h.box("metal_gold", (0.12, 0.12, 0.5), T(0.75, 0, 0.25))
    h.box("metal_gold", (1.62, 0.16, 0.12), T(0, 0, 0.06))
    h.lathe("metal_gold", [(0.0, -0.06), (0.68, -0.06), (0.68, 0.06), (0.0, 0.06)], segs=24, matrix=T(0, 0, 1.0) @ rot("X", 90))
    h.lathe("mirror", [(0.0, -0.065), (0.6, -0.065)], segs=24, matrix=T(0, 0, 1.0) @ rot("X", 90))
    h.lathe("stone_dark", [(0.0, 0.065), (0.6, 0.065)], segs=24, matrix=T(0, 0, 1.0) @ rot("X", -90))
    h.build(parent=ped, location=(0, 0, 1.0), sway=False)
    return ped


def make_sun_emitter(name):
    b = Builder(name, smooth_angle=20)
    b.box("stone", (2.0, 1.4, 2.6), T(0, 0.3, 1.3))
    b.box("stone_dark", (2.2, 1.6, 0.3), T(0, 0.3, 2.75))
    b.lathe("metal_gold", [(0.0, 0.0), (0.5, 0.0), (0.5, 0.2), (0.0, 0.2)], segs=16, matrix=T(0, -0.4, 1.5) @ rot("X", 90))
    b.ico("crystal_sun", 0.35, 1, matrix=T(0, -0.6, 1.5), flat=True)
    return b.build(sway=False)


def make_junction(name, elbow=False):
    b = Builder(name, smooth_angle=10)
    b.box("stone_dark", (2.0, 2.0, 0.3), T(0, 0, 0.15))
    b.box("stone", (1.8, 1.8, 0.1), T(0, 0, 0.35))
    if elbow:
        pts = [(0, -1.0, 0.42), (0, -0.4, 0.42), (0.15, -0.15, 0.42), (0.4, 0, 0.42), (1.0, 0, 0.42)]
    else:
        pts = [(0, -1.0, 0.42), (0, 0.0, 0.42), (0, 1.0, 0.42)]
    b.tube("conduit_line", pts, 0.09, segs=6)
    b.lathe("metal_gold", [(0.0, 0.4), (0.22, 0.4), (0.22, 0.48), (0.0, 0.48)], segs=12)
    return b.build(sway=False)


def make_conduit(name, length=2.0):
    b = Builder(name, smooth_angle=10)
    b.box("stone_dark", (0.5, length, 0.2), T(0, 0, 0.1))
    b.tube("conduit_line", [(0, -length / 2, 0.24), (0, length / 2, 0.24)], 0.07, segs=6)
    return b.build(sway=False)


def make_stone_lantern(name):
    b = Builder(name, smooth_angle=20)
    b.box("stone_dark", (0.9, 0.9, 0.25), T(0, 0, 0.12))
    b.lathe("stone", [(0.0, 0.25), (0.22, 0.25), (0.18, 1.2), (0.0, 1.2)], segs=8, flat=True)
    b.box("stone", (0.75, 0.75, 0.12), T(0, 0, 1.25))
    for x, y in ((-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)):
        b.box("stone", (0.1, 0.1, 0.5), T(x, y, 1.55))
    b.box("lantern_glow", (0.45, 0.45, 0.42), T(0, 0, 1.55))
    b.lathe("stone", [(0.0, 1.8), (0.65, 1.8), (0.0, 2.25)], segs=4, flat=True, matrix=rot("Z", 45))
    return b.build(sway=False)


def make_robot_statue(name):
    b = Builder(name, smooth_angle=40)
    b.box("stone_dark", (1.6, 1.6, 0.8), T(0, 0, 0.4))
    b.ico("stone_carved", 0.85, 2, matrix=T(0, 0, 1.75), flat=False)
    b.lathe("stone_dark", [(0.0, -0.05), (0.55, -0.05), (0.55, 0.05), (0.0, 0.05)], segs=20, matrix=T(0, -0.62, 1.8) @ rot("X", 70))
    for side in (-1, 1):
        b.ico("stone_carved", 0.32, 1, matrix=T(side * 0.95, 0, 1.45), squash=(0.8, 0.8, 1.2), flat=False)
        b.tube("stone_carved", [(side * 0.45, 0.1, 2.5), (side * 0.5, 0.1, 3.1)], 0.04, segs=5)
        b.ico("stone_carved", 0.07, 1, matrix=T(side * 0.5, 0.1, 3.15), flat=False)
    b.ico("moss", 0.5, 1, matrix=T(0.2, 0.1, 2.55), squash=(1.2, 1.0, 0.3), noise_amp=0.3)
    return b.build(sway=False)


def make_great_door(name):
    b = Builder(name, smooth_angle=20)
    for side in (-1, 1):
        b.box("stone", (2.6, 3.0, 10.0), T(side * 5.6, 0, 5.0))
        b.box("stone_dark", (3.0, 3.4, 0.6), T(side * 5.6, 0, 0.3))
    b.box("stone", (14.0, 3.2, 2.2), T(0, 0, 11.1))
    b.box("stone_carved", (4.0, 0.3, 1.2), T(0, -1.6, 11.1))
    frame = b.build(sway=False)
    for side, dname in ((-1, "great_door_left"), (1, "great_door_right")):
        d = Builder(dname, smooth_angle=20)
        # Origin at the hinge; leaf extends toward the center.
        d.box("stone_dark", (4.3, 0.7, 9.8), T(-side * 2.15, 0, 4.9))
        d.lathe("stone_carved", [(0.0, -0.4), (1.4, -0.4), (1.4, -0.36), (0.0, -0.36)], segs=24, matrix=T(-side * 2.6, 0, 5.4) @ rot("X", 90))
        d.box("energy", (0.08, 0.05, 8.6), T(-side * 4.25, -0.36, 4.9))
        d.build(parent=frame, location=(side * 4.3, 0, 0), sway=False)
    return frame


def make_lore_tablet(name):
    b = Builder(name, smooth_angle=20)
    b.box("stone_dark", (2.4, 1.0, 0.3), T(0, 0, 0.15))
    b.box("stone", (2.0, 0.45, 2.4), T(0, 0, 1.5) @ rot("X", -6))
    for k, (x, z, s) in enumerate(((-0.5, 1.9, 0.25), (0.1, 1.6, 0.18), (0.55, 1.95, 0.14), (-0.2, 1.1, 0.3))):
        b.ico("stone_carved", s, 1, matrix=T(x, -0.24, z), squash=(1, 0.4, 1), flat=False)
    b.box("energy", (1.4, 0.02, 0.03), T(0, -0.25, 0.75))
    return b.build(sway=False)


def make_falls_rock(name):
    b = Builder(name)
    b.ico("rock", 6.0, 3, matrix=T(0, 0, 7.0), squash=(1.0, 0.7, 1.5), noise_amp=0.3, noise_freq=1.4, seed=17)
    b.ico("rock", 3.5, 2, matrix=T(-4.0, 1.0, 2.5), squash=(1.2, 0.9, 0.8), noise_amp=0.3, seed=18)
    b.ico("moss", 3.0, 2, matrix=T(0.5, 0.3, 15.5), squash=(1.5, 1.2, 0.35), noise_amp=0.3, seed=19)
    return b.build(sway=False)


# ======================================================================================
# GARDEN
# ======================================================================================

def make_crystal_cluster(name, mat, count, size, seed):
    b = Builder(name)
    rnd = random.Random(seed)
    b.ico("rock", size * 0.3, 2, matrix=T(0, 0, -size * 0.04), squash=(1.25, 1.25, 0.65), noise_amp=0.3, seed=seed)
    for k in range(count):
        a = rnd.uniform(0, 360)
        tilt = 0 if k == 0 else rnd.uniform(15, 50)
        h = size * (1.0 if k == 0 else rnd.uniform(0.35, 0.75))
        r = h * rnd.uniform(0.12, 0.18)
        m = rot("Z", a) @ T(rnd.uniform(0.0, size * 0.25) if k else 0, 0, 0) @ rot("Y", tilt)
        b.crystal(mat, r, h, sides=6, tip=0.28, matrix=m, jitter=0.08, seed=seed + k)
    return b.build(sway=False)


def make_crystal_tree(name):
    b = Builder(name)
    trunk = [(0, 0, 0), (0.3, 0.1, 2.0), (-0.2, 0.2, 4.0), (0.2, -0.1, 6.0)]
    b.tube("crystal_teal", trunk, [0.45, 0.35, 0.28, 0.2], segs=6, flat=True)
    rnd = random.Random(8)
    for k in range(9):
        z = rnd.uniform(2.5, 6.0)
        a = rnd.uniform(0, 360)
        m = T(0, 0, z) @ rot("Z", a) @ rot("Y", rnd.uniform(35, 70))
        b.crystal("crystal_teal" if k % 3 else "crystal_violet", rnd.uniform(0.12, 0.25), rnd.uniform(1.2, 2.4), matrix=m, jitter=0.1, seed=k)
    b.crystal("crystal_violet", 0.3, 2.2, matrix=T(0.2, -0.1, 5.8), seed=99)
    return b.build(sway=False)


def make_glass_flower(name, seed=0):
    b = Builder(name)
    pts = flower_stem_points(3.4, 0.4, lean_dir=seed)
    b.tube("stem", pts, 0.07, segs=6, cap_start=False)
    top = Vector(pts[-1])
    head = T(*top) @ rot("Y", 15)
    center = head @ Vector((0, 0, 0))
    for k in range(7):
        m = head @ rot("Z", k * 360 / 7) @ T(0.1, 0, 0) @ rot("Y", -40)
        faces = b.strip("glass_petal", 0.95, 0.55, curl=0.2, segs=4, matrix=m, taper=(0.3, 1.0, 0.3), cup=0.1)
        b.mark_petals(faces, center)
    b.ico("crystal_pink", 0.15, 1, matrix=head @ T(0, 0, 0.2))
    return b.build()


def make_resonator(name):
    b = Builder(name, smooth_angle=25)
    b.lathe("stone", [(0.0, 0.0), (1.3, 0.0), (1.3, 0.35), (1.0, 0.45), (0.0, 0.45)], segs=10, flat=True)
    for k in range(3):
        a = k * 2 * math.pi / 3
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [d * 0.85 + Vector((0, 0, 0.4)), d * 1.0 + Vector((0, 0, 1.4)), d * 0.75 + Vector((0, 0, 2.5)), d * 0.45 + Vector((0, 0, 3.0))]
        b.tube("stone_carved", pts, [0.2, 0.17, 0.12, 0.07], segs=7)
    b.lathe("energy", [(1.02, 0.46), (1.12, 0.46), (1.12, 0.48), (1.02, 0.48)], segs=24)
    res = b.build(sway=False)
    c = Builder("resonator_crystal")
    c.crystal("crystal_violet", 0.3, 0.9, sides=6, tip=0.35, matrix=T(0, 0, -0.2))
    c.crystal("crystal_violet", 0.3, 0.5, sides=6, tip=0.6, matrix=T(0, 0, -0.2) @ rot("X", 180))
    c.build(parent=res, location=(0, 0, 2.1), sway=False)
    return res


def make_singing_crystal(name):
    b = Builder(name, smooth_angle=25)
    b.ico("rock", 0.9, 1, matrix=T(0, 0, 0.25), squash=(1.3, 1.3, 0.45), noise_amp=0.25, seed=3)
    base = b.build(sway=False)
    g = Builder("singing_gem")
    g.crystal("crystal_teal", 0.32, 2.6, sides=6, tip=0.25, jitter=0.05, seed=4)
    g.crystal("crystal_teal", 0.16, 1.2, sides=6, tip=0.3, matrix=rot("Z", 40) @ T(0.35, 0, 0) @ rot("Y", 25), seed=5)
    g.build(parent=base, location=(0, 0, 0.4), sway=False)
    return base


def make_melody_stone(name):
    b = Builder(name, smooth_angle=20)
    b.box("stone_dark", (2.6, 1.2, 0.3), T(0, 0, 0.15))
    b.box("stone", (2.3, 0.5, 1.6), T(0, 0, 1.1) @ rot("X", -10))
    for k in range(3):
        b.lathe("stone_dark", [(0.0, 0.0), (0.26, 0.0), (0.26, 0.05), (0.0, 0.05)], segs=16, matrix=T(-0.7 + k * 0.7, -0.33, 1.2) @ rot("X", 80))
    return b.build(sway=False)


def make_crystal_heart(name):
    b = Builder(name, smooth_angle=50)
    b.lathe("stone_dark", [(0.0, 0.0), (5.0, 0.0), (5.0, 0.4), (4.2, 0.5), (4.2, 0.9), (0.0, 0.9)], segs=36)
    rnd = random.Random(12)
    for k in range(7):
        a = k / 7 * 2 * math.pi
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [d * 4.4 + Vector((0, 0, 0.6)), d * 4.2 + Vector((0, 0, 2.5)), d * 3.2 + Vector((0, 0, 5.0)), d * 2.2 + Vector((0, 0, 6.4)),
               d * 1.6 + Vector((0, 0, 6.9))]
        b.tube("bark", pts, [0.55, 0.45, 0.35, 0.22, 0.1], segs=8, noise_amp=0.08, seed=k)
    b.lathe("energy", [(4.25, 0.91), (4.35, 0.91), (4.35, 0.93), (4.25, 0.93)], segs=36)
    heart = b.build(sway=False)
    g = Builder("heart_gem")
    g.crystal("crystal_heart", 1.3, 2.4, sides=8, tip=0.5, matrix=T(0, 0, 0.0), jitter=0.0)
    g.crystal("crystal_heart", 1.3, 1.6, sides=8, tip=0.75, matrix=rot("X", 180), jitter=0.0)
    g.build(parent=heart, location=(0, 0, 4.4), sway=False)
    return heart


def make_fragment(name):
    b = Builder(name)
    b.crystal("fragment", 0.12, 0.36, sides=5, tip=0.45, matrix=T(0, 0, 0.0))
    b.crystal("fragment", 0.12, 0.2, sides=5, tip=0.8, matrix=rot("X", 180))
    return b.build(sway=False, ao=False)


# ======================================================================================

def main():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    random.seed(1)
    # Meadow
    make_daisy("daisy_a", 6.4, "petal_white", seed=1)
    make_daisy("daisy_b", 4.8, "petal_white", bend=1.2, tilt=35, seed=2)
    make_daisy("daisy_pink", 5.6, "petal_pink", petal_count=14, seed=3)
    make_daisy("sunflower", 9.0, "petal_yellow", petal_count=20, head_r=0.9, petal_len=1.4, tilt=30, bend=0.9, seed=4)
    make_tulip("tulip_a", 5.0)
    make_bluebell("bluebell_a", 4.2)
    make_dandelion("dandelion_a", 7.5)
    make_clover("clover_a")
    make_grass_clump("grass_a", blades=11, height=1.5, seed=1)
    make_grass_clump("grass_b", blades=8, height=2.3, seed=2)
    make_grass_clump("grass_tall", blades=9, height=4.5, seed=3)
    make_rock("rock_a", 1.4, seed=1)
    make_rock("rock_b", 0.8, seed=2, squash=(1.3, 1.0, 0.5))
    make_rock("rock_c", 3.2, seed=3, squash=(1.1, 1.0, 0.75), subdiv=3)
    make_rock("rock_moss_a", 2.2, seed=4, moss=True, subdiv=3)
    make_rock("rock_moss_b", 4.0, seed=5, moss=True, squash=(1.3, 1.0, 0.6), subdiv=3)
    make_rock("pebble", 0.35, seed=6, squash=(1.2, 1.0, 0.6), subdiv=1, detail=3)
    make_pebble_cluster("pebble_cluster", seed=21)
    make_leaf_litter("leaf_litter", seed=22)
    make_twig_small("twig_small", seed=23)
    make_twig("twig_a")
    make_watering_can("watering_can")
    make_charging_station("charging_station")
    make_root_gate("root_gate")
    make_power_pylon("power_pylon")
    make_plant_stake("plant_stake")
    # Forest
    make_mushroom("mushroom_red", 9.0, 3.8, 2.2, "mushroom_cap_red", seed=1)
    make_mushroom("mushroom_red_small", 4.5, 2.0, 1.2, "mushroom_cap_red", seed=2, bend=0.8)
    make_mushroom("mushroom_tan", 6.5, 3.4, 0.9, "mushroom_cap_tan", spots=False, seed=3, bend=1.0)
    make_mushroom("mushroom_step", 1.6, 1.6, 0.35, "mushroom_cap_tan", spots=False, seed=4, bend=0.1, stem_r=0.35)
    make_mushroom_cluster("mushroom_cluster", "mushroom_cap_tan", count=5, scale=1.0, seed=3)
    make_mushroom_cluster("mushroom_glow", "mushroom_cap_glow", count=6, scale=0.8, seed=5)
    make_tree_trunk("tree_trunk_a", seed=1)
    make_tree_trunk("tree_trunk_b", radius=2.6, height=40.0, seed=2)
    make_canopy_leaf("canopy_leaf")
    make_root_arch("root_arch")
    make_log_hollow("log_hollow")
    make_fern("fern_a", seed=1)
    make_glow_bulb("glow_bulb")
    make_bridge_machine("bridge_machine")
    make_valve_switch("valve_switch")
    make_pipe_segment("pipe_segment")
    # Shrine
    make_pillar("pillar", seed=1)
    make_pillar("pillar_broken", broken=True, seed=2)
    make_arch("arch")
    make_wall("wall_broken", seed=3)
    make_wall("wall_full", broken=False, seed=4)
    make_stairs("stairs")
    make_shrine_core("shrine_core")
    make_power_node("power_node")
    make_mirror_pedestal("mirror_pedestal")
    make_sun_emitter("sun_emitter")
    make_junction("junction_straight")
    make_junction("junction_elbow", elbow=True)
    make_conduit("conduit")
    make_stone_lantern("stone_lantern")
    make_robot_statue("robot_statue")
    make_great_door("great_door")
    make_lore_tablet("lore_tablet")
    make_falls_rock("falls_rock")
    # Garden
    make_crystal_cluster("crystal_violet_a", "crystal_violet", 6, 4.0, 1)
    make_crystal_cluster("crystal_teal_a", "crystal_teal", 5, 3.0, 2)
    make_crystal_cluster("crystal_pink_a", "crystal_pink", 7, 2.2, 3)
    make_crystal_cluster("crystal_spire", "crystal_violet", 9, 26.0, 4)
    make_crystal_cluster("crystal_small", "crystal_teal", 3, 1.0, 5)
    make_crystal_tree("crystal_tree")
    make_glass_flower("glass_flower", seed=1)
    make_resonator("resonator")
    make_singing_crystal("singing_crystal")
    make_melody_stone("melody_stone")
    make_crystal_heart("crystal_heart")
    make_fragment("energy_fragment")

    # Spread props out (purely for previewing in Blender; Godot uses each root by name).
    roots = [o for o in bpy.data.objects if o.parent is None]
    for i, o in enumerate(roots):
        o.location.x += (i % 10) * 0.0
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kwargs = dict(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True, export_yup=True,
                  export_materials="EXPORT", export_animations=False)
    if "export_vertex_color" in props:
        kwargs["export_vertex_color"] = "ACTIVE"
    if "export_all_vertex_colors" in props:
        kwargs["export_all_vertex_colors"] = True
    if "export_active_vertex_color_when_no_material" in props:
        kwargs["export_active_vertex_color_when_no_material"] = True
    if "export_colors" in props:
        kwargs["export_colors"] = True
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(**{k: v for k, v in kwargs.items() if k in props})
    tri = 0
    for o in bpy.data.objects:
        if o.type == "MESH":
            tri += sum(len(p.vertices) - 2 for p in o.data.polygons)
    log("exported", len(roots), "props,", tri, "triangles total ->", OUT)


main()
