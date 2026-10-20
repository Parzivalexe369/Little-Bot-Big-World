class_name WorldDirector
extends Node
## Scripted moments: short camera glances at machines, the restoration of each area,
## and the finale when the Crystal Heart wakes the whole world.

var world: World
var busy := false
var finale_music_lock := false


func _player() -> Player:
	return world.player


func _rig() -> CameraRig:
	return world.camera_rig


func _lock(on: bool) -> void:
	_player().input_enabled = not on
	_rig().input_enabled = not on
	world.hud.set_letterbox(on)
	world.hud.set_hud_visible(not on)
	world.phase = World.Phase.CINEMATIC if on else World.Phase.PLAYING
	if on:
		Events.cinematic_started.emit()
	else:
		Events.cinematic_finished.emit()


## A short glance at something that just changed (gate rising, bridge unfolding).
func look_at(target: Vector3, duration: float) -> void:
	if busy:
		return
	busy = true
	_lock(true)
	var cam_pos := _clear_view_position(target, _player().global_position, 12.0, 4.5)
	await _rig().play_shots([
		{"position": cam_pos, "look": target, "time": 1.2, "hold": maxf(duration - 1.2, 0.5)},
	])
	_lock(false)
	busy = false


func play_restoration(area: StringName, source: Node3D) -> void:
	while busy:
		await get_tree().process_frame
	match area:
		&"meadow":
			await _restore_simple(&"meadow", "The meadow remembers its colors.", Vector3.ZERO)
		&"forest":
			await _restore_simple(&"forest", "The forest begins to glow.", Vector3.ZERO)
		&"shrine":
			await _restore_shrine(source as ShrineCore)
		&"garden":
			await _finale(source as CrystalHeart)
	SaveSystem.save_game()


func _restore_simple(area: StringName, message: String, _focus: Vector3) -> void:
	Audio.play_sfx(&"restore", -1.0)
	Audio.duck_music(-6.0, 3.0)
	_player().visual.play_action(&"Victory")
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var v := world.restore_levels
		match area:
			&"meadow": v.x = maxf(v.x, t)
			&"forest": v.y = maxf(v.y, t)
		world.restore_levels = v, 0.0, 1.0, 6.0).set_trans(Tween.TRANS_SINE)
	Events.toast(message, "energy")
	await tween.finished
	world._update_audio(false)


func _restore_shrine(core: ShrineCore) -> void:
	busy = true
	_lock(true)
	var c := core.global_position if core else Vector3(30, 7, -269)
	var focus := c + Vector3(0, 4.0, 0)
	Audio.play_sfx(&"core_awaken", 0.0)
	Audio.duck_music(-12.0, 8.0)
	var core_tween := create_tween()
	if core:
		core_tween.tween_method(core.set_awake_visuals, 0.0, 1.0, 4.0)
	var pillar_holder: Array = []
	_shrine_burst(c, pillar_holder)
	await _rig().play_shots([
		{"position": c + Vector3(9.0, 3.0, 8.0), "look": focus, "time": 1.6},
		{"position": c + Vector3(-8.0, 5.5, 9.0), "look": focus, "time": 3.0, "hold": 0.6},
	], false)
	var wide := c + Vector3(-22.0, 14.0, 26.0)
	var waterfall := _find(Waterfall)
	var door := _find(GreatDoor)
	var sequence: Array = [{"position": wide, "look": c + Vector3(0, 2, -4), "time": 2.4, "hold": 1.6}]
	if waterfall:
		var wp := waterfall.global_position
		sequence.append({"position": wp + waterfall.global_basis.z * 15.0 + Vector3(-4, 4, 0), "look": wp + Vector3.UP * 6.0, "time": 2.2, "hold": 2.0})
	if door:
		var dp := door.global_position
		sequence.append({"position": dp - door.global_basis.z * 16.0 + Vector3(0, 5, 0), "look": dp + Vector3.UP * 4.0, "time": 2.4, "hold": 2.6})
	await _rig().play_shots(sequence)
	_lock(false)
	_player().visual.play_action(&"Victory")
	Events.toast("The shrine is awake. The great door stands open.", "energy")
	world._update_audio(false)
	if not pillar_holder.is_empty():
		var pillar: Node3D = pillar_holder[0]
		var fade := create_tween()
		fade.tween_interval(6.0)
		fade.tween_property(pillar, "scale:x", 0.0, 3.0)
		fade.parallel().tween_property(pillar, "scale:z", 0.0, 3.0)
		fade.tween_callback(pillar.queue_free)
	busy = false


## Runs alongside the opening shots: the core flares, light pours up, the shrine restores.
func _shrine_burst(c: Vector3, pillar_holder: Array) -> void:
	await get_tree().create_timer(3.4).timeout
	_rig().add_shake(0.6)
	var fx := FxFactory.fountain(Color(0.5, 0.95, 1.0), 120, 14.0, 2.5)
	world.add_child(fx)
	fx.global_position = c + Vector3.UP * 1.3
	fx.emitting = true
	pillar_holder.append(_light_pillar(c, Color(0.55, 0.95, 1.0)))
	GameState.set_flag(&"shrine_restored", true)
	var restore := create_tween()
	restore.tween_method(func(t: float) -> void:
		var v := world.restore_levels
		v.z = maxf(v.z, t)
		world.restore_levels = v, 0.0, 1.0, 5.0)
	await get_tree().create_timer(9.0).timeout
	fx.emitting = false


func _finale(heart: CrystalHeart) -> void:
	busy = true
	_lock(true)
	finale_music_lock = true
	var c := heart.global_position if heart else Vector3(-6, -3, -410)
	var focus := c + Vector3(0, 4.4, 0)
	Audio.play_music(&"finale", 3.0, -3.0)
	Audio.play_sfx(&"heart_restore", 0.0)
	var glow := create_tween()
	if heart:
		glow.tween_method(heart.set_glow, 0.4, 1.0, 4.5)
	await _rig().play_shots([
		{"position": c + Vector3(7.0, 3.0, 10.0), "look": focus, "time": 1.8},
		{"position": c + Vector3(-6.0, 6.0, 9.0), "look": focus, "time": 3.2},
	], false)
	_rig().add_shake(0.8)
	var fx := FxFactory.fountain(Color(1.0, 0.75, 0.95), 160, 18.0, 3.5)
	world.add_child(fx)
	fx.global_position = c + Vector3.UP * 1.0
	fx.emitting = true
	_light_pillar(c, Color(1.0, 0.75, 0.95))
	GameState.set_flag(&"garden_restored", true)
	var awake := create_tween()
	var start := world.restore_levels
	awake.tween_method(func(t: float) -> void:
		world.restore_levels = start.lerp(Vector4.ONE, t)
		world.world_awake = t, 0.0, 1.0, 7.0).set_trans(Tween.TRANS_SINE)
	world.atmosphere.set_override({"fog_density": 0.0016, "saturation": 1.08, "sun_energy": 1.6, "vol_fog": 0.003}, 1.0)
	await _rig().play_shots([
		{"position": c + Vector3(0.0, 26.0, 34.0), "look": c + Vector3(0, 2, -10), "time": 4.0, "hold": 0.8},
		{"position": Vector3(70.0, 95.0, -300.0), "look": Vector3(-10.0, 0.0, -150.0), "time": 6.0, "hold": 3.0},
		{"position": Vector3(-30.0, 60.0, -10.0), "look": Vector3(10.0, 0.0, 40.0), "time": 5.0, "hold": 2.5},
	], false)
	fx.emitting = false
	Events.game_completed.emit()
	world.completion.open()


## Called when the player chooses "Keep exploring" after the completion screen.
func finish_finale() -> void:
	world.atmosphere.set_override({}, 0.0)
	await _rig().end_cinematic(1.6)
	_lock(false)
	busy = false
	finale_music_lock = false
	Events.toast("The world is awake. Explore as long as you like.", "info")
	world._update_audio(false)


## Finds a camera spot around `target` with an unobstructed view, preferring the player's side.
func _clear_view_position(target: Vector3, prefer_from: Vector3, distance: float, height: float) -> Vector3:
	var base := Vector3(prefer_from.x - target.x, 0.0, prefer_from.z - target.z)
	var base_angle := atan2(base.z, base.x) if base.length() > 0.1 else 0.0
	var space := world.get_world_3d().direct_space_state
	var best := target + Vector3(cos(base_angle), 0, sin(base_angle)) * distance + Vector3.UP * height
	for i in 12:
		var offset := (float(i + 1) / 2.0) * (1.0 if i % 2 == 0 else -1.0) * 0.45
		var a := base_angle + (0.0 if i == 0 else offset)
		var p := target + Vector3(cos(a), 0, sin(a)) * distance
		p.y = maxf(WorldTerrain.height_at_world(p.x, p.z) + 1.5, target.y + height)
		var query := PhysicsRayQueryParameters3D.create(p, target, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(target) < 3.0:
			return p
	return best


func _light_pillar(at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.2
	mesh.bottom_radius = 1.2
	mesh.height = 1.0
	mesh.radial_segments = 24
	var pillar := MeshInstance3D.new()
	pillar.mesh = mesh
	pillar.material_override = BeamSegments.beam_material(color)
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(pillar)
	pillar.global_position = at + Vector3(0, 60.0, 0)
	pillar.scale = Vector3(0.01, 120.0, 0.01)
	var tween := pillar.create_tween()
	tween.tween_property(pillar, "scale", Vector3(1.0, 120.0, 1.0), 0.8).set_trans(Tween.TRANS_BACK)
	return pillar


func _find(type: Variant) -> Node3D:
	for node in get_tree().get_nodes_in_group(&"devices"):
		if is_instance_of(node, type):
			return node as Node3D
	return null
