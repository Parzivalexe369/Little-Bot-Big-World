class_name GameData
extends RefCounted
## Static game data: areas, collectibles, discoveries and progression thresholds.
## Kept in one place so the HUD, journal, tests and world agree on totals.

## The four garden areas of the persistent world (the world's audio/atmosphere loop over these).
const AREA_IDS: Array[StringName] = [&"meadow", &"forest", &"shrine", &"garden"]
## The three sci-fi areas below the garden (scenes/facility).
const FACILITY_AREA_IDS: Array[StringName] = [&"lab", &"reactor", &"quantum"]
## All seven areas in journey order (journal, travel screen).
const ALL_AREA_IDS: Array[StringName] = [&"meadow", &"forest", &"shrine", &"garden", &"lab", &"reactor", &"quantum"]

const AREA_NAMES := {
	&"meadow": "The Quiet Meadow",
	&"forest": "The Mushroom Forest",
	&"shrine": "The Forgotten Shrine",
	&"garden": "The Crystal Garden",
	&"lab": "Abandoned Space Research Facility",
	&"reactor": "Alien Energy Reactor",
	&"quantum": "Quantum Space-Time Laboratory",
}

## Where travel (and the journal) starts each area, and the flag that unlocks it there.
const AREA_ENTRY_CHECKPOINT := {
	&"meadow": &"station", &"forest": &"forest_entry", &"shrine": &"shrine_plaza", &"garden": &"garden_entry",
	&"lab": &"lab_entry", &"reactor": &"reactor_entry", &"quantum": &"quantum_entry",
}

## Number of energy fragments placed in each area. Fragment ids are "<area>_<n>".
const FRAGMENTS_PER_AREA := {
	&"meadow": 7,
	&"forest": 8,
	&"shrine": 7,
	&"garden": 8,
	&"lab": 4,
	&"reactor": 4,
	&"quantum": 4,
}

## Energy (total fragments collected, never spent) needed by key devices.
const GATE_ENERGY := 3
const SHRINE_NODE_ENERGY := 10
const HEART_ENERGY := 20

const SHRINE_NODE_COUNT := 4
const FOREST_SWITCH_COUNT := 3
const RESONATOR_COUNT := 3
## Sci-fi areas: steps that make up each area's main puzzle.
const LAB_POWER_COUNT := 3        # conduit couplers, laser optics, terminal restart
const REACTOR_STABILITY_COUNT := 3  # balanced cores, synchronized arms, node sequence
const QUANTUM_SYSTEM_COUNT := 3   # gravity, phase, time

## Optional environmental stories. Short on purpose: the world tells the rest.
const DISCOVERIES := [
	{"id": &"dock_plaque", "area": &"meadow", "title": "Caretaker Dock 7",
		"text": "A worn plaque on the charging dock. Someone built a home for a very small helper."},
	{"id": &"watering_can", "area": &"meadow", "title": "The Giant's Watering Can",
		"text": "Taller than a house and rusted through. Somebody tended this garden, long ago."},
	{"id": &"sleeping_caretaker", "area": &"forest", "title": "A Sleeping Caretaker",
		"text": "Another helper, asleep mid-task. Its little hand still cradles a seed."},
	{"id": &"mushroom_ring", "area": &"forest", "title": "The Fairy Ring",
		"text": "Mushrooms grown in a perfect circle around a patch of warm, humming soil."},
	{"id": &"shrine_mural", "area": &"shrine", "title": "The Carried Light",
		"text": "Carvings show tiny robots carrying sparks of light to a great crystal heart."},
	{"id": &"wheeled_courier", "area": &"shrine", "title": "The Courier",
		"text": "A wheeled courier parked in its alcove, waiting for a route that never came."},
	{"id": &"crystal_echo", "area": &"garden", "title": "The Humming Cave",
		"text": "The crystals here hum a song that is older than the stones."},
	{"id": &"overlook", "area": &"garden", "title": "Everywhere You've Been",
		"text": "The crystal valley spreads out below, and far behind you the shrine still glows."},
	{"id": &"experiment_log", "area": &"lab", "title": "Experiment Seven",
		"text": "The last log entry: \"The garden seed answered the field. We opened a door we could not close.\""},
	{"id": &"helper_blueprint", "area": &"lab", "title": "Blueprint of a Small Helper",
		"text": "Schematics for a pink hover robot. A note in the margin: \"Make it brave. It will be alone a long time.\""},
	{"id": &"reactor_heart", "area": &"reactor", "title": "The Reactor's Heartbeat",
		"text": "Deep in the core the alien machine pulses slowly, like something alive and very patient."},
	{"id": &"builder_glyphs", "area": &"reactor", "title": "Glyphs of the Builders",
		"text": "Spiral marks on every pylon, counting in heartbeats. Whoever built this wanted to be understood."},
	{"id": &"time_echo", "area": &"quantum", "title": "An Echo in Time",
		"text": "For a moment a second little robot hovers beside you, waves, and flickers out of now."},
	{"id": &"folded_room", "area": &"quantum", "title": "The Folded Room",
		"text": "A staircase climbs down into the ceiling. Here, up and down are only suggestions."},
]

## Checkpoints: id -> human readable name (positions live on Checkpoint nodes in the world).
const CHECKPOINT_NAMES := {
	&"station": "Charging Dock",
	&"meadow_gate": "Meadow Gate",
	&"forest_entry": "Forest Edge",
	&"forest_bridge": "Old Bridge",
	&"shrine_plaza": "Shrine Plaza",
	&"garden_entry": "Garden Steps",
	&"heart": "Crystal Heart",
	&"garden_lift": "Research Lift",
	&"lab_entry": "Arrival Hall",
	&"lab_optics": "Optics Lab",
	&"lab_control": "Control Room",
	&"reactor_entry": "Reactor Gantry",
	&"reactor_cores": "Core Chamber",
	&"reactor_crossing": "Far Platform",
	&"quantum_entry": "Quantum Antechamber",
	&"quantum_gravity": "Gravity Well",
	&"quantum_phase": "Phase Bridge",
	&"quantum_final": "Exit Core",
}


## True if the player may travel to an area (has been there before).
static func area_unlocked(area_id: StringName) -> bool:
	return area_id == &"meadow" or GameState.has_flag(StringName("visited_%s" % area_id))


static func is_facility_area(area_id: StringName) -> bool:
	return FACILITY_AREA_IDS.has(area_id)


static func total_fragments() -> int:
	var total := 0
	for area: StringName in FRAGMENTS_PER_AREA:
		total += FRAGMENTS_PER_AREA[area]
	return total


static func area_of_fragment(fragment_id: StringName) -> StringName:
	var text := String(fragment_id)
	var cut := text.find("_")
	return StringName(text.substr(0, cut)) if cut > 0 else &""


static func discovery(discovery_id: StringName) -> Dictionary:
	for entry: Dictionary in DISCOVERIES:
		if entry["id"] == discovery_id:
			return entry
	return {}


static func area_name(area_id: StringName) -> String:
	return AREA_NAMES.get(area_id, "")
