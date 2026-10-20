"""Export the robots from the source .blend into Godot-ready GLB files.

Run with:
  blender -b pink_ball_robot_with_THE_BALL_v2.blend --factory-startup --python tools/blender/export_robots.py

The source .blend is never saved; all changes happen in memory only.

Outputs (relative to the project root):
  assets/characters/pink_robot/pink_robot.glb       player robot, all 12 actions baked
  assets/characters/pink_robot/eye_glow.json        per-action eye_glow curve (drives eye emission)
  assets/characters/old_robots/the_ball.glb         static yellow caretaker robot (no actions)
  assets/characters/old_robots/the_ball_v2.glb      static wheeled courier robot (no actions)
"""
import bpy
import json
import os
import sys

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def log(*a):
    print("[export_robots]", *a)
    sys.stdout.flush()


def descendants(obj):
    out = []
    for child in obj.children:
        out.append(child)
        out.extend(descendants(child))
    return out


def fcurves_of(action):
    curves = []
    try:
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    curves.extend(bag.fcurves)
    except AttributeError:
        curves = list(action.fcurves)
    return curves


def convert_curves_to_mesh(objs):
    for o in objs:
        if o.type in ("CURVE", "FONT", "SURFACE"):
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target="MESH")
            log("converted curve to mesh:", o.name)


def isolate_and_export(rig_name, out_path, with_animation):
    rig = bpy.data.objects[rig_name]
    objs = [rig] + descendants(rig)
    convert_curves_to_mesh(objs)
    objs = [rig] + descendants(rig)
    old_loc = rig.location.copy()
    rig.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig

    if not with_animation:
        if rig.animation_data:
            rig.animation_data.action = None
            for t in rig.animation_data.nla_tracks:
                t.mute = True
        for pb in rig.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
            pb.scale = (1, 1, 1)

    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kwargs = dict(
        filepath=out_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_animations=with_animation,
        export_skins=True,
        export_def_bones=False,
    )
    if with_animation:
        if "export_animation_mode" in props:
            kwargs["export_animation_mode"] = "ACTIONS"
        if "export_force_sampling" in props:
            kwargs["export_force_sampling"] = True
        if "export_frame_step" in props:
            kwargs["export_frame_step"] = 1
        if "export_anim_slide_to_zero" in props:
            kwargs["export_anim_slide_to_zero"] = True
        if "export_optimize_animation_size" in props:
            kwargs["export_optimize_animation_size"] = False
        if "export_bake_animation" in props:
            kwargs["export_bake_animation"] = False
        if "export_negative_frame" in props:
            kwargs["export_negative_frame"] = "SLIDE"
    kwargs = {k: v for k, v in kwargs.items() if k in props}
    log("exporting", rig_name, "->", out_path, "objects:", len(objs))
    bpy.ops.export_scene.gltf(**kwargs)
    rig.location = old_loc
    return objs


def eye_glow_curves(rig_name, out_path):
    rig = bpy.data.objects[rig_name]
    fps = bpy.context.scene.render.fps
    data = {"fps": fps, "actions": {}}
    for action in bpy.data.actions:
        curve = None
        for fc in fcurves_of(action):
            if fc.data_path == '["eye_glow"]':
                curve = fc
        if curve is None:
            continue
        start, end = action.frame_range
        values = []
        f = start
        while f <= end + 0.001:
            values.append(round(curve.evaluate(f), 4))
            f += 1.0
        data["actions"][action.name] = values
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    log("wrote eye glow curves for", len(data["actions"]), "actions")


def bounds_report(objs):
    import mathutils
    mn = mathutils.Vector((1e9, 1e9, 1e9))
    mx = mathutils.Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for corner in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(corner)
            mn = mathutils.Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = mathutils.Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return [round(v, 3) for v in mn], [round(v, 3) for v in mx]


def main():
    pink_dir = os.path.join(PROJECT, "assets", "characters", "pink_robot")
    old_dir = os.path.join(PROJECT, "assets", "characters", "old_robots")
    os.makedirs(pink_dir, exist_ok=True)
    os.makedirs(old_dir, exist_ok=True)

    report = {}
    eye_glow_curves("RIG_PinkRobot", os.path.join(pink_dir, "eye_glow.json"))

    objs = isolate_and_export("RIG_PinkRobot", os.path.join(pink_dir, "pink_robot.glb"), True)
    report["pink_robot_bounds"] = bounds_report(objs)

    objs = isolate_and_export("RIG_TheBall", os.path.join(old_dir, "the_ball.glb"), False)
    report["the_ball_bounds"] = bounds_report(objs)

    objs = isolate_and_export("RIG_TheBall_V2", os.path.join(old_dir, "the_ball_v2.glb"), False)
    report["the_ball_v2_bounds"] = bounds_report(objs)

    mats = {}
    for name in ("RIG_TheBall", "RIG_TheBall_V2"):
        used = set()
        for o in descendants(bpy.data.objects[name]):
            if o.type == "MESH":
                for s in o.material_slots:
                    if s.material:
                        used.add(s.material.name)
        mats[name] = sorted(used)
    report["old_robot_materials"] = mats

    ramp = {}
    for m in bpy.data.materials:
        if m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == "VALTORGB":
                    ramp[m.name] = [[round(e.position, 3), [round(c, 3) for c in e.color]] for e in n.color_ramp.elements]
    report["color_ramps"] = ramp

    glass = {}
    for mname in ("M_BlackGlass",):
        m = bpy.data.materials.get(mname)
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                vals = {}
                for i in n.inputs:
                    if hasattr(i, "default_value"):
                        v = i.default_value
                        try:
                            v = [round(x, 3) for x in v]
                        except TypeError:
                            try:
                                v = round(v, 3)
                            except TypeError:
                                v = str(v)
                        vals[i.name] = v
                glass[n.name] = vals
    report["black_glass"] = glass

    with open(os.path.join(pink_dir, "export_report.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)
    log("done")


main()
