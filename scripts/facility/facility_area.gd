class_name FacilityArea
extends Node3D
## Base for the three sci-fi areas. Each area builds its own architecture, props, lights and
## puzzles in code (the .tscn holds the gameplay objects: checkpoints, fragments, discoveries)
## and reports its bounds and atmosphere to the FacilityWorld.

@export var area_id: StringName = &"lab"
## World-space bounds of the area (relative to this node's position).
@export var bounds_size := Vector3(80, 40, 80)
@export var bounds_center := Vector3(0, 10, 0)

var facility: FacilityWorld


## Atmosphere for this area (merged with defaults by FacilityWorld).
func mood() -> Dictionary:
	return {}


func contains(point: Vector3) -> bool:
	return AABB(global_position + bounds_center - bounds_size * 0.5, bounds_size).has_point(point)


## Called when the robot respawns at a checkpoint in this area (reset hazards, etc.).
func on_respawn() -> void:
	pass


## Helper: is a step of a multi-part goal done? Steps are members of a GameState set.
func step_done(set_name: StringName, step: StringName) -> bool:
	return GameState.set_has(set_name, step)


func complete_step(set_name: StringName, step: StringName, message: String) -> void:
	if GameState.set_has(set_name, step):
		return
	GameState.add_to_set(set_name, step)
	Audio.play_sfx(&"puzzle_solved", -3.0)
	Events.toast(message, "energy")
	SaveSystem.save_game()


## A short "look over there" camera move to show the effect of solving something.
func show_effect(target: Vector3, duration := 2.6) -> void:
	Events.look_at_requested.emit(target, duration)
