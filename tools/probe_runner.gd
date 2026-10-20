extends Node
## Dev tool: replays the conduit-tile sequence and reports focus problems in detail.
## Usage: godot --path . res://tools/probe_runner.tscn

var player: Player


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	(world as World).pause_on_focus_loss = false
	await get_tree().process_frame
	player = world.get_node("Player") as Player
	player.input_enabled = true
	GameState.set_flag(&"robot_awake", true)
	var junction := world.find_child("JunctionPuzzle", true, false) as JunctionPuzzle
	for pair in [["A", 1], ["B", 2], ["C", 3]]:
		for k in int(pair[1]):
			var it: Interactable = junction._tiles[pair[0]]["interactable"]
			await _focus_and_use(it, "%s#%d" % [pair[0], k + 1])
			await get_tree().create_timer(0.5).timeout
	print("PROBE solved=", GameState.has_flag(&"junction_solved"), " trace=", junction.trace())
	get_tree().quit()


func _focus_and_use(it: Interactable, label: String) -> void:
	var focus := it.get_focus_point()
	for attempt in 8:
		var a := TAU * attempt / 8.0
		var p := focus + Vector3(cos(a), 0, sin(a)) * 1.79
		var pos := WorldTerrain.point_on_ground(p.x, p.z, 0.3)
		pos.y = maxf(pos.y, focus.y - 1.5)
		player.respawn_at(pos)
		player.face_toward(focus)
		for i in 6:
			await get_tree().process_frame
		if player.interactor.current == it:
			print("PROBE %s focused at attempt %d" % [label, attempt])
			it.interact(player)
			return
		var names := []
		for ar in player.interactor.get_overlapping_areas():
			names.append(ar.get_parent().name)
		print("PROBE %s attempt %d: player=%s overlaps=%s current=%s floor=%s" % [label, attempt, player.global_position.snapped(Vector3.ONE * 0.01), names,
			player.interactor.current.get_parent().name if player.interactor.current else "none", player.is_on_floor()])
	print("PROBE %s FAILED, using directly" % label)
	it.interact(player)
