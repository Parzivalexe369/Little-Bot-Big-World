class_name World
extends Node3D
## Gameplay root. Wires the persistent world together: terrain, levels, player, camera,
## atmosphere, audio, HUD/menus and the flow from waking up to the final restoration.

enum Phase { INTRO, PLAYING, CINEMATIC }

const AREA_MUSIC := {&"meadow": &"meadow", &"forest": &"forest", &"shrine": &"shrine", &"garden": &"garden"}
const RESTORE_FLAGS := {&"meadow": &"meadow_gate_open", &"forest": &"bridge_raised", &"shrine": &"shrine_restored", &"garden": &"garden_restored"}

@onready var terrain: WorldTerrain = $Terrain
@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var atmosphere: AtmosphereController = $Atmosphere
@onready var hud: Hud = $Hud
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var completion: CompletionScreen = $CompletionScreen
@onready var director: WorldDirector = $Director

var phase := Phase.PLAYING
## Pause automatically when the window loses focus (disabled by automated tests).
var pause_on_focus_loss := true
## Restoration per area (x meadow, y forest, z shrine, w garden), mirrored to shaders.
var restore_levels := Vector4.ZERO:
	set(value):
		restore_levels = value
		RenderingServer.global_shader_parameter_set(&"restore_levels", value)
		if atmosphere:
			atmosphere.set_restoration(&"meadow", value.x)
			atmosphere.set_restoration(&"forest", value.y)
			atmosphere.set_restoration(&"shrine", value.z)
			atmosphere.set_restoration(&"garden", value.w)
var world_awake := 0.0:
	set(value):
		world_awake = value
		RenderingServer.global_shader_parameter_set(&"world_awake", value)

var _area_timer := 0.0
var _ambient_fx: Dictionary = {}
var _fx_root: Node3D


func _ready() -> void:
	($Sun as DirectionalLight3D).rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	atmosphere.setup($WorldEnvironment, $Sun)
	atmosphere.focus = player
	camera_rig.set_target(player)
	player.camera_rig = camera_rig
	hud.player = player
	director.world = self
	SaveSystem.player_snapshot_provider = player.snapshot
	_apply_saved_restoration()
	_build_ambient_fx()
	if OS.has_feature("web"):
		WebDrawDistance.apply.call_deferred($Levels)
	Events.restoration_requested.connect(director.play_restoration)
	Events.look_at_requested.connect(director.look_at)
	GameState.area_entered.connect(_on_area_entered)
	GameState.flag_changed.connect(_on_flag_changed)
	pause_menu.restart_requested.connect(respawn_at_checkpoint)
	completion.continue_exploring.connect(director.finish_finale)
	GameState.in_gameplay = true
	GameState.location = &"world"
	GameState.current_area = WorldLayout.area_at(Vector2(player.global_position.x, player.global_position.z))
	if SceneRouter.start_mode == SceneRouter.StartMode.TRAVEL and GameState.has_flag(&"robot_awake"):
		_start_travel()
	elif SceneRouter.start_mode == SceneRouter.StartMode.CONTINUE and GameState.has_flag(&"robot_awake"):
		_start_continue()
	else:
		_start_intro()
	atmosphere.snap()
	_update_audio(true)


func _apply_saved_restoration() -> void:
	var v := Vector4.ZERO
	v.x = 1.0 if GameState.has_flag(RESTORE_FLAGS[&"meadow"]) else 0.0
	v.y = 1.0 if GameState.has_flag(RESTORE_FLAGS[&"forest"]) else 0.0
	v.z = 1.0 if GameState.has_flag(RESTORE_FLAGS[&"shrine"]) else 0.0
	v.w = 1.0 if GameState.has_flag(RESTORE_FLAGS[&"garden"]) else 0.0
	if GameState.has_flag(&"garden_restored"):
		v = Vector4.ONE
		world_awake = 1.0
	else:
		world_awake = 0.0
	restore_levels = v


# --- Start flows --------------------------------------------------------------------

func _start_intro() -> void:
	phase = Phase.INTRO
	var station := get_tree().get_first_node_in_group(&"devices") as Node3D
	for node in get_tree().get_nodes_in_group(&"devices"):
		if node is ChargingStation:
			station = node
	var spawn := station.global_position if station else WorldTerrain.point_on_ground(0, 60)
	player.respawn_at(spawn + Vector3(0, 0.15, 0), 0.0)
	player.visual.sleep()
	player.input_enabled = false
	camera_rig.input_enabled = false
	camera_rig.set_yaw_behind(PI, -6.0)
	camera_rig.desired_distance = 2.3
	camera_rig.snap_to_target()
	hud.set_hud_visible(false, 0.0)
	hud.forced_prompt = "Wake up"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _wake_up() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.CINEMATIC
	hud.forced_prompt = ""
	Audio.play_sfx(&"boot_up", -2.0)
	player.visual.boot_up()
	await player.visual.boot_finished
	GameState.set_flag(&"robot_awake", true)
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera_rig, "yaw", 0.0, 2.2)
	tween.tween_property(camera_rig, "pitch", deg_to_rad(-14.0), 2.2)
	tween.tween_property(camera_rig, "desired_distance", camera_rig.default_distance, 2.2)
	player.visual.play_action(&"Victory", 1.2)
	Audio.play_sfx(&"robot_chirp", -4.0)
	await tween.finished
	phase = Phase.PLAYING
	player.input_enabled = true
	camera_rig.input_enabled = true
	hud.set_hud_visible(true)
	hud.show_hint("move", "[b]%s[/b]  Move      [b]%s[/b]  Look      [b]%s[/b]  Boost" % [InputGlyphs.label("move"), InputGlyphs.label("look"), InputGlyphs.label("boost")], 7.0)
	await get_tree().create_timer(1.0).timeout
	Events.area_banner.emit(&"meadow")
	SaveSystem.save_game()


func _start_continue() -> void:
	phase = Phase.PLAYING
	var spawn := Transform3D.IDENTITY
	var cp := Checkpoint.find(get_tree(), GameState.checkpoint_id)
	var has_spawn := false
	var data := SaveSystem.read_save_data()
	var snap: Variant = (data.get("state", {}) as Dictionary).get("player")
	if snap is Dictionary and snap.has("x"):
		var p := Vector3(float(snap["x"]), float(snap["y"]), float(snap["z"]))
		var ground := WorldTerrain.height_at_world(p.x, p.z)
		if is_finite(p.x) and is_finite(p.z) and p.y > ground - 1.0 and p.y < ground + 12.0:
			spawn = Transform3D(Basis(Vector3.UP, float(snap.get("yaw", 0.0))), p + Vector3.UP * 0.2)
			has_spawn = true
	if not has_spawn and cp:
		spawn = cp.spawn_transform()
		has_spawn = true
	if not has_spawn:
		spawn = Transform3D(Basis.IDENTITY, WorldTerrain.point_on_ground(0, 58, 0.3))
	var yaw := spawn.basis.get_euler().y
	player.respawn_at(spawn.origin, yaw)
	camera_rig.set_yaw_behind(yaw)
	camera_rig.snap_to_target()
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	Events.area_banner.emit(GameState.current_area)


## Arriving by travel or lift: always at the chosen checkpoint.
func _start_travel() -> void:
	phase = Phase.PLAYING
	var cp := Checkpoint.find(get_tree(), GameState.checkpoint_id)
	var spawn := cp.spawn_transform() if cp else Transform3D(Basis.IDENTITY, WorldTerrain.point_on_ground(0, 58, 0.3))
	var yaw := spawn.basis.get_euler().y
	player.respawn_at(spawn.origin + Vector3.UP * 0.2, yaw)
	camera_rig.set_yaw_behind(yaw)
	camera_rig.snap_to_target()
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.current_area = WorldLayout.area_at(Vector2(player.global_position.x, player.global_position.z))
	await get_tree().create_timer(0.8).timeout
	Events.area_banner.emit(GameState.current_area)


func respawn_at_checkpoint() -> void:
	var cp := Checkpoint.find(get_tree(), GameState.checkpoint_id)
	if cp == null:
		return
	await SceneRouter.fade_through(func() -> void:
		var t := cp.spawn_transform()
		player.respawn_at(t.origin + Vector3.UP * 0.2, t.basis.get_euler().y)
		camera_rig.set_yaw_behind(t.basis.get_euler().y)
		camera_rig.snap_to_target())


# --- Per frame ------------------------------------------------------------------------

func _process(delta: float) -> void:
	RenderingServer.global_shader_parameter_set(&"player_position", player.global_position)
	if _fx_root:
		_fx_root.global_position = player.global_position
	_area_timer -= delta
	if _area_timer <= 0.0:
		_area_timer = 0.5
		var area := WorldLayout.area_at(Vector2(player.global_position.x, player.global_position.z))
		if area != GameState.current_area and phase == Phase.PLAYING:
			GameState.enter_area(area)
		_update_audio(false)
		_update_ambient_fx()
		_check_hints()
	if phase == Phase.INTRO and Input.is_action_just_pressed("interact"):
		_wake_up()


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYING or pause_menu.is_open() or completion.visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		pause_menu.open()
	elif event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		pause_menu.open(true)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and phase == Phase.PLAYING and not pause_menu.is_open() and not completion.visible:
		pause_menu.open()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_game()


# --- Areas, audio, ambience --------------------------------------------------------------

func _on_area_entered(area_id: StringName) -> void:
	Events.area_banner.emit(area_id)
	Audio.play_sfx(&"area_enter", -8.0)
	SaveSystem.request_save(1.0)


func _on_flag_changed(flag: StringName, value: Variant) -> void:
	if flag == &"robot_awake" and value:
		_update_audio(true)


func _update_audio(instant: bool) -> void:
	var p := Vector2(player.global_position.x, player.global_position.z)
	var area := WorldLayout.area_at(p)
	if GameState.has_flag(&"garden_restored") and director.finale_music_lock:
		pass
	else:
		Audio.play_music(AREA_MUSIC.get(area, &"meadow"), 0.5 if instant else 4.0, -6.0 + 2.5 * _restore_of(area))
	var weights := WorldLayout.area_weights(p)
	var fade := 0.5 if instant else 2.5
	for a: StringName in GameData.AREA_IDS:
		var w: float = weights[a]
		Audio.set_ambient(StringName("%s_base" % a), clampf(w * 1.4, 0.0, 1.0), fade, -8.0)
		Audio.set_ambient(StringName("%s_life" % a), clampf(w * 1.4, 0.0, 1.0) * _restore_of(a), fade, -9.0)


func _restore_of(area: StringName) -> float:
	match area:
		&"meadow": return restore_levels.x
		&"forest": return restore_levels.y
		&"shrine": return restore_levels.z
		&"garden": return restore_levels.w
	return 0.0


func _build_ambient_fx() -> void:
	_fx_root = Node3D.new()
	_fx_root.name = "AmbientFx"
	add_child(_fx_root)
	_ambient_fx[&"pollen"] = FxFactory.ambient_motes(Color(1.0, 0.95, 0.72, 0.9), 70, Vector3(16, 5, 16), 0.07, 0.1)
	_ambient_fx[&"butterflies"] = FxFactory.ambient_motes(Color(1.0, 0.7, 0.85, 1.0), 26, Vector3(18, 3, 18), 0.16, 0.35, 5.0)
	_ambient_fx[&"fireflies"] = FxFactory.ambient_motes(Color(0.75, 1.0, 0.45, 1.0), 60, Vector3(18, 4, 18), 0.1, 0.2, 5.0)
	_ambient_fx[&"spores"] = FxFactory.ambient_motes(Color(0.6, 0.95, 0.9, 0.8), 50, Vector3(16, 6, 16), 0.06, 0.06, 8.0)
	_ambient_fx[&"dust"] = FxFactory.ambient_motes(Color(1.0, 0.88, 0.65, 0.7), 50, Vector3(16, 5, 16), 0.05, 0.05, 7.0)
	_ambient_fx[&"sparkles"] = FxFactory.ambient_motes(Color(0.85, 0.75, 1.0, 1.0), 60, Vector3(16, 4, 16), 0.08, 0.12, 4.0)
	for key: StringName in _ambient_fx:
		var fx: GPUParticles3D = _ambient_fx[key]
		fx.position = Vector3(0, 2.0, 0)
		fx.amount_ratio = 0.0
		_fx_root.add_child(fx)


func _update_ambient_fx() -> void:
	var p := Vector2(player.global_position.x, player.global_position.z)
	var w := WorldLayout.area_weights(p)
	_set_fx(&"pollen", w[&"meadow"] * (0.4 + 0.6 * restore_levels.x))
	_set_fx(&"butterflies", w[&"meadow"] * restore_levels.x)
	_set_fx(&"spores", w[&"forest"] * (0.6 + 0.4 * restore_levels.y))
	_set_fx(&"fireflies", w[&"forest"] * restore_levels.y)
	_set_fx(&"dust", w[&"shrine"])
	_set_fx(&"sparkles", w[&"garden"] * (0.3 + 0.7 * restore_levels.w))


func _set_fx(key: StringName, level: float) -> void:
	var fx: GPUParticles3D = _ambient_fx[key]
	fx.amount_ratio = clampf(level, 0.0, 1.0)
	fx.emitting = level > 0.02


# --- Contextual hints -----------------------------------------------------------

func _check_hints() -> void:
	if phase != Phase.PLAYING:
		return
	var pos := player.global_position
	if not hud.has_shown_hint("scan"):
		for node in get_tree().get_nodes_in_group(&"scannable"):
			if node.has_method("is_hidden_unrevealed") and node.call("is_hidden_unrevealed") and (node as Node3D).global_position.distance_to(pos) < 14.0:
				hud.show_hint("scan", "Something is hidden nearby.   [b]%s[/b]  Scan" % InputGlyphs.label("scan"), 7.0)
				break
	if not hud.has_shown_hint("hop"):
		for node in get_tree().get_nodes_in_group(&"fragments"):
			var f := node as EnergyFragment
			if f and f.ground_offset > 2.0 and f.global_position.distance_to(pos) < 9.0:
				hud.show_hint("hop", "[b]%s[/b]  Hover hop  (hold for a higher hop)" % InputGlyphs.label("hop"), 6.0)
				break
	if not hud.has_shown_hint("journal") and GameState.energy() >= 2:
		hud.show_hint("journal", "[b]%s[/b]  Journal      [b]%s[/b]  Pause" % [InputGlyphs.label("journal"), InputGlyphs.label("pause")], 5.0)
