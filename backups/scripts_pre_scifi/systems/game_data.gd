class_name GameData
extends RefCounted
## Static game data: areas, collectibles, discoveries and progression thresholds.
## Kept in one place so the HUD, journal, tests and world agree on totals.

const AREA_IDS: Array[StringName] = [&"meadow", &"forest", &"shrine", &"garden"]

const AREA_NAMES := {
	&"meadow": "The Quiet Meadow",
	&"forest": "The Mushroom Forest",
	&"shrine": "The Forgotten Shrine",
	&"garden": "The Crystal Garden",
}

## Number of energy fragments placed in each area. Fragment ids are "<area>_<n>".
const FRAGMENTS_PER_AREA := {
	&"meadow": 7,
	&"forest": 8,
	&"shrine": 7,
	&"garden": 8,
}

## Energy (total fragments collected, never spent) needed by key devices.
const GATE_ENERGY := 3
const SHRINE_NODE_ENERGY := 10
const HEART_ENERGY := 20

const SHRINE_NODE_COUNT := 4
const FOREST_SWITCH_COUNT := 3
const RESONATOR_COUNT := 3

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
}


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
