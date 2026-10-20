"""Generates the four level scenes (scenes/levels/*.tscn) from the layout tables below.

Every gameplay object is a regular instance of a reusable scene in scenes/interactables/,
so the generated levels can be opened and tweaked in the Godot editor afterwards.
Objects snap to the terrain at runtime, so only X/Z (and yaw) matter here.

Run: python tools/gen_levels.py
"""
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "scenes", "levels")

SCENES = {
    "fragment": "res://scenes/interactables/energy_fragment.tscn",
    "checkpoint": "res://scenes/interactables/checkpoint.tscn",
    "trigger": "res://scenes/interactables/flag_trigger.tscn",
    "discovery": "res://scenes/interactables/discovery_spot.tscn",
    "old_robot": "res://scenes/interactables/old_robot.tscn",
    "station": "res://scenes/interactables/charging_station.tscn",
    "gate": "res://scenes/interactables/root_gate.tscn",
    "valve": "res://scenes/interactables/valve_switch.tscn",
    "bridge": "res://scenes/interactables/old_bridge.tscn",
    "node": "res://scenes/interactables/power_node.tscn",
    "emitter": "res://scenes/interactables/beam_emitter.tscn",
    "mirror": "res://scenes/interactables/beam_mirror.tscn",
    "receiver": "res://scenes/interactables/beam_receiver.tscn",
    "hidden_wall": "res://scenes/interactables/hidden_wall.tscn",
    "junction": "res://scenes/interactables/junction_puzzle.tscn",
    "core": "res://scenes/interactables/shrine_core.tscn",
    "door": "res://scenes/interactables/great_door.tscn",
    "waterfall": "res://scenes/interactables/waterfall.tscn",
    "resonator": "res://scenes/interactables/resonator.tscn",
    "melody": "res://scenes/interactables/melody_puzzle.tscn",
    "heart": "res://scenes/interactables/crystal_heart.tscn",
}

SHRINE_CORE = (30.0, -269.0)
HEART = (-6.0, -410.0)


def yaw_to(dx, dz):
    """Yaw (degrees) that points a node's local +Z along (dx, dz)."""
    return math.degrees(math.atan2(dx, dz))


# ----------------------------------------------------------------------------------------
# Each entry: (type, name, x, z, yaw_degrees, {property: value})
# Values: str -> StringName (prefixed '&'), 'path:..' -> NodePath, 'raw:..' -> raw text.
# ----------------------------------------------------------------------------------------

MEADOW = [
    ("station", "ChargingStation", 0.0, 60.0, 0, {"device_id": "&station"}),
    ("checkpoint", "CheckpointStation", 0.0, 59.6, 180, {"checkpoint_id": "&station", "announce": False, "radius": 3.0}),
    ("discovery", "DockPlaque", 0.0, 60.75, 0, {"discovery_id": "&dock_plaque", "prompt": "Read the plaque", "interact_radius": 1.1, "focus_offset": "raw:Vector3(0, 0.7, 0)"}),
    ("fragment", "Fragment1", 4.6, 44.0, 0, {"fragment_id": "&meadow_1"}),
    ("fragment", "Fragment2", -10.0, 17.0, 0, {"fragment_id": "&meadow_2"}),
    ("fragment", "Fragment3", -19.5, 22.5, 0, {"fragment_id": "&meadow_3"}),
    ("fragment", "Fragment4", 26.0, 2.0, 0, {"fragment_id": "&meadow_4", "ground_offset": 2.75}),
    ("fragment", "Fragment5", -38.0, -8.0, 0, {"fragment_id": "&meadow_5", "hidden_until_scanned": True}),
    ("fragment", "Fragment6", 2.4, 66.5, 0, {"fragment_id": "&meadow_6"}),
    ("fragment", "Fragment7", 41.5, 28.0, 0, {"fragment_id": "&meadow_7"}),
    ("discovery", "WateringCanStory", 38.6, 28.0, 0, {"discovery_id": "&watering_can", "prompt": "Look around", "interact_radius": 1.6}),
    ("gate", "RootGate", -2.6, -55.0, yaw_to(-7, -14), {"device_id": "&meadow_gate"}),
    ("checkpoint", "CheckpointGate", -7.0, -65.0, yaw_to(-12, -16), {"checkpoint_id": "&meadow_gate"}),
]

SWITCH_MACHINE = (-3.5, -195.5)
FOREST = [
    ("checkpoint", "CheckpointForest", -15.0, -75.0, yaw_to(-12, -16), {"checkpoint_id": "&forest_entry"}),
    ("fragment", "Fragment1", -16.5, -86.0, 0, {"fragment_id": "&forest_1"}),
    ("fragment", "Fragment2", -55.0, -101.0, 0, {"fragment_id": "&forest_2", "ground_offset": 3.55}),
    ("fragment", "Fragment3", -62.0, -128.0, 0, {"fragment_id": "&forest_3", "ground_offset": 0.8}),
    ("fragment", "Fragment4", -1.5, -110.5, 0, {"fragment_id": "&forest_4"}),
    ("fragment", "Fragment5", -60.0, -160.0, 0, {"fragment_id": "&forest_5", "hidden_until_scanned": True}),
    ("fragment", "Fragment6", -9.5, -181.0, 0, {"fragment_id": "&forest_6"}),
    ("fragment", "Fragment7", -79.0, -116.0, 0, {"fragment_id": "&forest_7"}),
    ("fragment", "Fragment8", 9.0, -146.5, 0, {"fragment_id": "&forest_8"}),
    ("old_robot", "SleepingCaretaker", 7.0, -149.5, 200, {"model": "the_ball", "discovery_id": "&sleeping_caretaker"}),
    ("trigger", "MushroomRing", -80.0, -118.0, 0, {"discovery_id": "&mushroom_ring", "size": "raw:Vector3(9, 6, 9)"}),
    ("valve", "Switch1", -27.0, -166.0, 0, {"device_id": "&forest_switch_1",
        "cable_points": [(-20.0, -172.0), (-12.0, -184.0), (-6.0, -192.0), SWITCH_MACHINE]}),
    ("valve", "Switch2", 13.0, -171.0, 0, {"device_id": "&forest_switch_2",
        "cable_points": [(9.0, -181.0), (2.0, -190.0), SWITCH_MACHINE]}),
    ("valve", "Switch3", -45.0, -181.0, 0, {"device_id": "&forest_switch_3",
        "cable_points": [(-34.0, -186.0), (-20.0, -192.0), (-10.0, -195.0), SWITCH_MACHINE]}),
    ("bridge", "OldBridge", 1.0, -197.5, 0, {"device_id": "&old_bridge"}),
    ("trigger", "SawBridge", -2.0, -188.0, 0, {"flag": "&saw_bridge", "size": "raw:Vector3(18, 6, 12)",
        "message": "The bridge is folded away. Its machine has no power."}),
]

N_CORE = (SHRINE_CORE[0], SHRINE_CORE[1])
SHRINE = [
    ("checkpoint", "CheckpointBridge", 6.0, -217.0, yaw_to(6, -12), {"checkpoint_id": "&forest_bridge"}),
    ("trigger", "PlazaReached", 27.0, -255.0, 0, {"flag": "&shrine_plaza_reached", "size": "raw:Vector3(14, 8, 10)"}),
    ("checkpoint", "CheckpointPlaza", 27.0, -255.0, 180, {"checkpoint_id": "&shrine_plaza"}),
    ("core", "ShrineCore", N_CORE[0], N_CORE[1], 0, {"device_id": "&shrine_core"}),
    ("node", "NodeEnergy", 21.0, -258.0, 0, {"device_id": "&node_energy", "mode": 0, "core_position": "core"}),
    ("node", "NodeBeam", 38.5, -261.0, 0, {"device_id": "&node_beam", "mode": 2, "core_position": "core",
        "external_hint": "Dormant. It is waiting for sunlight."}),
    ("node", "NodeHidden", 8.0, -272.0, 0, {"device_id": "&node_hidden", "mode": 1, "core_position": "core"}),
    ("node", "NodeConduit", 16.2, -279.0, 0, {"device_id": "&node_conduit", "mode": 2, "core_position": "core",
        "external_hint": "Dormant. Its power line is broken."}),
    ("emitter", "SunEmitter", 46.0, -246.0, 0, {"device_id": "&sun_emitter_shrine"}),
    ("mirror", "MirrorA", 46.0, -256.0, 0, {"device_id": "&mirror_a", "start_step": 1, "ground_offset": -0.45}),
    ("mirror", "MirrorB", 36.0, -256.0, 0, {"device_id": "&mirror_b", "start_step": 5, "ground_offset": -0.45}),
    ("receiver", "BeamReceiver", 36.0, -261.5, 0, {"solved_flag": "&beam_receiver_on", "target_path": "path:../NodeBeam", "ground_offset": 1.55}),
    ("hidden_wall", "HiddenWall", 10.5, -272.0, 90, {"device_id": "&hidden_wall"}),
    ("junction", "JunctionPuzzle", 14.0, -286.0, 0, {"device_id": "&junction", "target_path": "path:../NodeConduit"}),
    ("waterfall", "Waterfall", 54.0, -279.0, yaw_to(-7, 4), {"device_id": "&waterfall"}),
    ("discovery", "Mural", 19.0, -266.0, 90, {"discovery_id": "&shrine_mural", "prop": "lore_tablet", "prop_yaw": 0.0, "focus_offset": "raw:Vector3(0, 1.4, 0)", "interact_radius": 2.2}),
    ("old_robot", "Courier", 37.0, -289.0, 160, {"model": "the_ball_v2", "discovery_id": "&wheeled_courier", "slump_degrees": 4.0}),
    ("fragment", "Fragment1", 15.5, -236.5, 0, {"fragment_id": "&shrine_1"}),
    ("fragment", "Fragment2", 42.0, -251.5, 0, {"fragment_id": "&shrine_2"}),
    ("fragment", "Fragment3", 9.4, -270.6, 0, {"fragment_id": "&shrine_3"}),
    ("fragment", "Fragment4", 14.0, -262.9, 0, {"fragment_id": "&shrine_4", "ground_offset": 3.5}),
    ("fragment", "Fragment5", 50.0, -268.0, 0, {"fragment_id": "&shrine_5"}),
    ("fragment", "Fragment6", 25.0, -251.5, 0, {"fragment_id": "&shrine_6"}),
    ("fragment", "Fragment7", 12.0, -252.0, 0, {"fragment_id": "&shrine_7", "hidden_until_scanned": True}),
    ("door", "GreatDoor", 26.4, -295.4, yaw_to(-6, -14), {"device_id": "&great_door"}),
]

GARDEN = [
    ("checkpoint", "CheckpointGarden", 19.0, -311.0, yaw_to(-8, -16), {"checkpoint_id": "&garden_entry"}),
    ("trigger", "Overlook", 19.0, -313.0, 0, {"discovery_id": "&overlook", "size": "raw:Vector3(10, 6, 8)"}),
    ("checkpoint", "CheckpointHeart", -7.0, -393.0, 180, {"checkpoint_id": "&heart"}),
    ("heart", "CrystalHeart", HEART[0], HEART[1], 0, {"device_id": "&crystal_heart"}),
    ("emitter", "SunShard", 34.0, -372.0, 90, {"device_id": "&sun_shard", "beam_color": "raw:Color(0.85, 0.7, 1, 1)"}),
    ("mirror", "PrismA", 18.0, -372.0, 0, {"device_id": "&prism_a", "start_step": 2, "crystal_style": True, "ground_offset": -0.45}),
    ("mirror", "PrismB", 18.0, -386.0, 0, {"device_id": "&prism_b", "start_step": 3, "crystal_style": True, "ground_offset": -0.45}),
    ("receiver", "PrismReceiver", 24.5, -386.0, 0, {"solved_flag": "&prism_receiver_on", "target_path": "path:../ResonatorBeam", "ground_offset": 1.55}),
    ("resonator", "ResonatorBeam", 27.5, -388.0, 0, {"device_id": "&resonator_beam", "mode": 0, "heart_position": "heart"}),
    ("resonator", "ResonatorHidden", -47.0, -410.0, 0, {"device_id": "&resonator_hidden", "mode": 1, "heart_position": "heart"}),
    ("melody", "MelodyPuzzle", -26.0, -424.0, 0, {"device_id": "&melody", "target_path": "path:../ResonatorMelody"}),
    ("resonator", "ResonatorMelody", -26.0, -436.0, 0, {"device_id": "&resonator_melody", "mode": 0, "heart_position": "heart"}),
    ("trigger", "HummingCave", -45.0, -406.0, 0, {"discovery_id": "&crystal_echo", "size": "raw:Vector3(12, 6, 12)"}),
    ("fragment", "Fragment1", 8.5, -333.0, 0, {"fragment_id": "&garden_1"}),
    ("fragment", "Fragment2", -17.0, -381.0, 0, {"fragment_id": "&garden_2"}),
    ("fragment", "Fragment3", -45.5, -404.5, 0, {"fragment_id": "&garden_3"}),
    ("fragment", "Fragment4", 25.0, -421.0, 0, {"fragment_id": "&garden_4", "hidden_until_scanned": True}),
    ("fragment", "Fragment5", -37.0, -370.0, 0, {"fragment_id": "&garden_5"}),
    ("fragment", "Fragment6", 16.0, -356.0, 0, {"fragment_id": "&garden_6", "ground_offset": 2.75}),
    ("fragment", "Fragment7", -13.0, -442.0, 0, {"fragment_id": "&garden_7", "hidden_until_scanned": True}),
    ("fragment", "Fragment8", 37.0, -365.0, 0, {"fragment_id": "&garden_8"}),
]

LEVELS = {
    "meadow": ("Meadow", "res://scripts/world/areas/meadow_area.gd", MEADOW),
    "mushroom_forest": ("MushroomForest", "res://scripts/world/areas/forest_area.gd", FOREST),
    "forgotten_shrine": ("ForgottenShrine", "res://scripts/world/areas/shrine_area.gd", SHRINE),
    "crystal_garden": ("CrystalGarden", "res://scripts/world/areas/garden_area.gd", GARDEN),
}


def fmt(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(float(value)) if isinstance(value, float) else str(value)
    if isinstance(value, list):
        nums = []
        for (x, z) in value:
            nums += [repr(float(x)), repr(float(z))]
        return "PackedVector2Array(%s)" % ", ".join(nums)
    if isinstance(value, str):
        if value.startswith("&"):
            return '&"%s"' % value[1:]
        if value.startswith("path:"):
            return 'NodePath("%s")' % value[5:]
        if value.startswith("raw:"):
            return value[4:]
        if value == "core":
            return "Vector3(%r, 9.6, %r)" % (SHRINE_CORE[0], SHRINE_CORE[1])
        if value == "heart":
            return "Vector3(%r, 1.6, %r)" % (HEART[0], HEART[1])
        return '"%s"' % value
    raise ValueError(value)


def build(file_name, root_name, script, entries):
    used = sorted({e[0] for e in entries})
    ids = {t: "%d_%s" % (i + 2, t) for i, t in enumerate(used)}
    lines = ["[gd_scene load_steps=%d format=3]" % (len(used) + 2), ""]
    lines.append('[ext_resource type="Script" path="%s" id="1_area"]' % script)
    for t in used:
        lines.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (SCENES[t], ids[t]))
    lines += ["", '[node name="%s" type="Node3D"]' % root_name, 'script = ExtResource("1_area")', ""]
    for (t, name, x, z, yaw, props) in entries:
        lines.append('[node name="%s" parent="." instance=ExtResource("%s")]' % (name, ids[t]))
        y = 0.0
        if "ground" in props:
            y = props.pop("ground")
            lines.append("position = Vector3(%r, %r, %r)" % (x, y, z))
        else:
            lines.append("position = Vector3(%r, 0.0, %r)" % (x, z))
        if yaw:
            lines.append("rotation = Vector3(0, %r, 0)" % math.radians(yaw))
        for key, value in props.items():
            lines.append("%s = %s" % (key, fmt(value)))
        lines.append("")
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, file_name + ".tscn"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print("wrote", file_name, len(entries), "objects")


for file_name, (root_name, script, entries) in LEVELS.items():
    build(file_name, root_name, script, [tuple(e[:5]) + (dict(e[5]),) for e in entries])
