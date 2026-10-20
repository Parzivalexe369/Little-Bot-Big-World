"""Generates the sci-fi facility scenes (scenes/facility/*.tscn): the facility gameplay root
and the three level scenes (Area 5 research lab, Area 6 alien reactor, Area 7 quantum lab).

Same idea as gen_levels.py (which builds the four garden levels and is not touched): the
gameplay objects that are data (checkpoints, energy fragments, discoveries) are instances
in the scenes, while each area's script builds its architecture, props, lights and puzzles.
The facility has floors, not terrain, so every object has an explicit height and
snap_to_ground = false. Positions are local to each level (levels sit far apart).

Run: python tools/gen_facility_levels.py
"""
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "scenes", "facility")

SCENES = {
    "fragment": "res://scenes/interactables/energy_fragment.tscn",
    "checkpoint": "res://scenes/interactables/checkpoint.tscn",
    "discovery": "res://scenes/interactables/discovery_spot.tscn",
}

# (type, name, x, y, z, yaw_degrees, {property: value}); values like gen_levels.py.
LAB = [
    ("checkpoint", "CheckpointEntry", 0.0, 0.05, 24.5, 0, {"checkpoint_id": "&lab_entry", "radius": 3.0}),
    ("checkpoint", "CheckpointOptics", 0.0, 0.05, 6.0, 0, {"checkpoint_id": "&lab_optics", "radius": 3.0}),
    ("checkpoint", "CheckpointControl", -6.0, 0.05, -25.5, 0, {"checkpoint_id": "&lab_control", "radius": 3.0}),
    ("fragment", "Fragment1", -5.5, 2.75, 21.0, 0, {"fragment_id": "&lab_1"}),
    ("fragment", "Fragment2", 11.0, 1.15, 5.5, 0, {"fragment_id": "&lab_2"}),
    ("fragment", "Fragment3", 23.5, 3.1, 2.0, 0, {"fragment_id": "&lab_3"}),
    ("fragment", "Fragment4", 20.5, 3.1, -6.5, 0, {"fragment_id": "&lab_4"}),
    ("discovery", "ExperimentLog", 22.0, 2.2, -2.0, 0, {"discovery_id": "&experiment_log", "prompt": "Read the log", "interact_radius": 1.8, "focus_offset": "raw:Vector3(0, 1.0, 0)"}),
    ("discovery", "Blueprint", 2.0, 0.0, -27.5, 0, {"discovery_id": "&helper_blueprint", "prompt": "Look at the hologram", "interact_radius": 2.0, "focus_offset": "raw:Vector3(0, 0.9, 0)"}),
]

REACTOR = [
    ("checkpoint", "CheckpointEntry", 0.0, 0.05, 30.5, 0, {"checkpoint_id": "&reactor_entry", "radius": 3.0}),
    ("checkpoint", "CheckpointCrossing", 0.0, 4.05, -0.6, 0, {"checkpoint_id": "&reactor_crossing", "radius": 2.4}),
    ("checkpoint", "CheckpointCores", 6.0, 4.05, -24.5, 0, {"checkpoint_id": "&reactor_cores", "radius": 2.6}),
    ("fragment", "Fragment1", 0.0, 0.9, 13.5, 0, {"fragment_id": "&reactor_1"}),
    ("fragment", "Fragment2", -10.5, 4.9, -37.5, 0, {"fragment_id": "&reactor_2"}),
    ("fragment", "Fragment3", 11.6, 8.9, -38.8, 0, {"fragment_id": "&reactor_3"}),
    ("fragment", "Fragment4", -5.8, 0.9, 35.8, 0, {"fragment_id": "&reactor_4"}),
    ("discovery", "ReactorHeart", 3.2, 4.0, -27.6, 0, {"discovery_id": "&reactor_heart", "prompt": "Look into the core", "interact_radius": 2.0, "focus_offset": "raw:Vector3(0, 0.8, 0)"}),
    ("discovery", "BuilderGlyphs", -9.2, 8.0, -38.8, 0, {"discovery_id": "&builder_glyphs", "prompt": "Study the glyphs", "interact_radius": 1.8, "focus_offset": "raw:Vector3(0, 1.0, 0)"}),
]

QUANTUM = [
    ("checkpoint", "CheckpointEntry", 0.0, 0.05, 25.5, 0, {"checkpoint_id": "&quantum_entry", "radius": 2.6}),
    ("checkpoint", "CheckpointGravity", 0.0, 10.05, -3.2, 0, {"checkpoint_id": "&quantum_gravity", "radius": 2.6}),
    ("checkpoint", "CheckpointPhase", 5.0, 10.05, -40.5, -90, {"checkpoint_id": "&quantum_phase", "radius": 2.4}),
    ("checkpoint", "CheckpointFinal", 33.0, 10.05, -38.0, 0, {"checkpoint_id": "&quantum_final", "radius": 2.6}),
    ("fragment", "Fragment1", 5.0, 7.6, 9.0, 0, {"fragment_id": "&quantum_1"}),
    ("fragment", "Fragment2", -8.5, 10.9, -21.0, 0, {"fragment_id": "&quantum_2"}),
    ("fragment", "Fragment3", 21.75, 10.9, -41.25, 0, {"fragment_id": "&quantum_3"}),
    ("fragment", "Fragment4", -6.6, 6.7, 15.5, 0, {"fragment_id": "&quantum_4"}),
    ("discovery", "TimeEcho", 2.5, 10.0, -42.2, 0, {"discovery_id": "&time_echo", "prompt": "Wave hello", "interact_radius": 1.8, "focus_offset": "raw:Vector3(0, 0.6, 0)"}),
    ("discovery", "FoldedRoom", -3.5, 0.0, 29.0, 0, {"discovery_id": "&folded_room", "prompt": "Look up", "interact_radius": 2.0, "focus_offset": "raw:Vector3(0, 1.2, 0)"}),
]

LEVELS = {
    "research_lab": ("ResearchLab", "res://scripts/facility/areas/lab_area.gd", "lab", LAB),
    "alien_reactor": ("AlienReactor", "res://scripts/facility/areas/reactor_area.gd", "reactor", REACTOR),
    "quantum_lab": ("QuantumLab", "res://scripts/facility/areas/quantum_area.gd", "quantum", QUANTUM),
}
LEVEL_OFFSETS = {"research_lab": (0.0, 0.0, 0.0), "alien_reactor": (300.0, 0.0, 0.0), "quantum_lab": (600.0, 0.0, 0.0)}


def fmt(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(float(value)) if isinstance(value, float) else str(value)
    if isinstance(value, str):
        if value.startswith("&"):
            return '&"%s"' % value[1:]
        if value.startswith("raw:"):
            return value[4:]
        return '"%s"' % value
    raise ValueError(value)


def build_level(file_name, root_name, script, area_id, entries):
    used = sorted({e[0] for e in entries})
    ids = {t: "%d_%s" % (i + 2, t) for i, t in enumerate(used)}
    lines = ["[gd_scene load_steps=%d format=3]" % (len(used) + 2), ""]
    lines.append('[ext_resource type="Script" path="%s" id="1_area"]' % script)
    for t in used:
        lines.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (SCENES[t], ids[t]))
    lines += ["", '[node name="%s" type="Node3D"]' % root_name, 'script = ExtResource("1_area")',
              'area_id = &"%s"' % area_id, ""]
    for (t, name, x, y, z, yaw, props) in entries:
        lines.append('[node name="%s" parent="." instance=ExtResource("%s")]' % (name, ids[t]))
        lines.append("position = Vector3(%r, %r, %r)" % (x, y, z))
        if yaw:
            lines.append("rotation = Vector3(0, %r, 0)" % math.radians(yaw))
        lines.append("snap_to_ground = false")
        for key, value in props.items():
            lines.append("%s = %s" % (key, fmt(value)))
        lines.append("")
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, file_name + ".tscn"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print("wrote", file_name, len(entries), "objects")


def build_facility():
    res = [
        ("Script", "res://scripts/facility/facility_world.gd", "1_world"),
        ("PackedScene", "res://scenes/player/player.tscn", "2_player"),
        ("Script", "res://scripts/player/camera_rig.gd", "3_camera"),
        ("PackedScene", "res://scenes/ui/hud.tscn", "4_hud"),
        ("PackedScene", "res://scenes/ui/pause_menu.tscn", "5_pause"),
    ]
    for i, name in enumerate(LEVELS):
        res.append(("PackedScene", "res://scenes/facility/%s.tscn" % name, "%d_%s" % (6 + i, name)))
    lines = ["[gd_scene load_steps=%d format=3]" % (len(res) + 1), ""]
    for kind, path, rid in res:
        lines.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
    lines += ["", '[node name="Facility" type="Node3D"]', 'script = ExtResource("1_world")', "",
              '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]', "",
              '[node name="Levels" type="Node3D" parent="."]', ""]
    for i, (name, (root_name, _s, _a, _e)) in enumerate(LEVELS.items()):
        ox, oy, oz = LEVEL_OFFSETS[name]
        lines.append('[node name="%s" parent="Levels" instance=ExtResource("%d_%s")]' % (root_name, 6 + i, name))
        lines.append("position = Vector3(%r, %r, %r)" % (ox, oy, oz))
        lines.append("")
    lines += ['[node name="Player" parent="." instance=ExtResource("2_player")]', "",
              '[node name="CameraRig" type="Node3D" parent="."]', 'script = ExtResource("3_camera")', "",
              '[node name="Hud" parent="." instance=ExtResource("4_hud")]', "",
              '[node name="PauseMenu" parent="." instance=ExtResource("5_pause")]', ""]
    with open(os.path.join(OUT, "facility.tscn"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print("wrote facility")


for file_name, (root_name, script, area_id, entries) in LEVELS.items():
    build_level(file_name, root_name, script, area_id, [tuple(e[:6]) + (dict(e[6]),) for e in entries])
build_facility()
