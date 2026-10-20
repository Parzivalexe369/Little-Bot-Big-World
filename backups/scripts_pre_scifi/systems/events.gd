extends Node
## Global event bus for presentation-level messages (UI, camera, audio cues) so gameplay
## objects never need direct references to the HUD or the world director.

## Small toast message. kind: "info", "energy", "save", "locked", "discovery".
signal notify(text: String, kind: String)
## Show the discovery panel for a discovery id from GameData.
signal discovery_shown(discovery_id: StringName)
## Large area title card.
signal area_banner(area_id: StringName)
## A restoration milestone: the world director plays the matching sequence.
signal restoration_requested(area_id: StringName, source: Node3D)
## Camera / input lock for scripted moments.
signal cinematic_started
signal cinematic_finished
## Ask the director to show something (point of interest) with a short camera move.
signal look_at_requested(target: Vector3, duration: float)
## The game has been completed (final restoration finished).
signal game_completed


func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)
