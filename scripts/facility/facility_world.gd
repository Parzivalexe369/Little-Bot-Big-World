class_name FacilityWorld
extends Node3D
## Gameplay root for the three sci-fi areas (5: research facility, 6: alien reactor,
## 7: quantum lab). Same player, camera, HUD, pause menu and save system as the garden
## world; each area is its own level scene placed far apart and joined by lifts/portals.

enum Phase { PLAYING, CINEMATIC }

const AREA_MUSIC := {&"lab": &"lab", &"reactor": &"reactor", &"quantum": &"quantum"}
const DEFAULT_MOOD := {
	"ambient": Color(0.25, 0.28, 0.33), "ambient_energy": 0.4, "fog": Color(0.45, 0.55, 0.65),
	"fog_density": 0.006, "vol_fog": 0.02, "vol_albedo": Color(0.6, 0.7, 0.8), "glow": 0.8,
	"exposure": 1.0, "nebula": 0.6, "planet": 0.0, "saturation": 1.0,
	# Key light (a star outside the windows / the nebula's sun), bounce light, colour grade.
	"sun": 0.0, "sun_color": Color(0.85, 0.9, 1.0), "sun_pitch": -32.0, "sun_yaw": -60.0,
	"gi": 1.0, "shadow_tint": Color(0.95, 1.0, 1.05), "highlight_tint": Color(1.04, 1.0, 0.96),
	"contrast": 1.06, "vignette": 0.32, "grade_saturation": 1.0,
}

@onready var player: Player = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $Hud
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var levels: Node3D = $Levels

var phase := Phase.PLAYING
var pause_on_focus_loss := true
var environment: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var grade: ShaderMaterial
var areas: Array[FacilityArea] = []
var _mood := {}
var _area_timer := 0.0


func _ready() -> void:
	GameState.location = &"facility"
	GameState.in_gameplay = true
	for child in levels.get_children():
		if child is FacilityArea:
			(child as FacilityArea).facility = self
			areas.append(child)
	_setup_environment()
	camera_rig.set_target(player)
	player.camera_rig = camera_rig
	hud.player = player
	SaveSystem.player_snapshot_provider = player.snapshot
	player.fall_limit = -40.0
	player.fall_respawn = func() -> void: respawn_at_checkpoint(true)
	pause_menu.restart_requested.connect(respawn_at_checkpoint)
	Events.look_at_requested.connect(show_point)
	Settings.changed.connect(_apply_quality)
	_spawn()
	player.visual.wake_instantly()
	player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_area(true)
	_mood = _target_mood()
	_apply_mood(_mood)
	await get_tree().create_timer(0.8).timeout
	Events.area_banner.emit(GameState.current_area)


func _exit_tree() -> void:
	ScifiKit.release()
	RenderingServer.gi_set_use_half_resolution(ProjectSettings.get_setting("rendering/global_illumination/gi/use_half_resolution", false))


# --- Spawning ---------------------------------------------------------------------------

func _spawn() -> void:
	var t := Transform3D.IDENTITY
	var found := false
	if SceneRouter.start_mode == SceneRouter.StartMode.CONTINUE:
		var snap: Variant = (SaveSystem.read_save_data().get("state", {}) as Dictionary).get("player")
		if snap is Dictionary and snap.has("x"):
			var p := Vector3(float(snap["x"]), float(snap["y"]), float(snap["z"]))
			for area in areas:
				if is_finite(p.x) and area.contains(p):
					t = Transform3D(Basis(Vector3.UP, float(snap.get("yaw", 0.0))), p + Vector3.UP * 0.2)
					found = true
	if not found:
		var cp := Checkpoint.find(get_tree(), GameState.checkpoint_id)
		if cp == null:
			cp = Checkpoint.find(get_tree(), &"lab_entry")
		if cp:
			t = cp.spawn_transform()
			found = true
	var yaw := t.basis.get_euler().y
	player.respawn_at(t.origin + Vector3.UP * 0.2, yaw)
	camera_rig.set_yaw_behind(yaw)
	camera_rig.snap_to_target()


func respawn_at_checkpoint(fell := false) -> void:
	var cp := Checkpoint.find(get_tree(), GameState.checkpoint_id)
	if cp == null:
		return
	if fell:
		player.input_enabled = false
		player.visual.express(&"hurt", 0.8)
		Audio.play_sfx(&"bonk", -4.0)
	await SceneRouter.fade_through(func() -> void:
		var t := cp.spawn_transform()
		player.respawn_at(t.origin + Vector3.UP * 0.2, t.basis.get_euler().y)
		camera_rig.set_yaw_behind(t.basis.get_euler().y)
		camera_rig.snap_to_target()
		for area in areas:
			if area.contains(t.origin):
				area.on_respawn())
	player.input_enabled = true


## Moves the robot between areas inside the facility (lifts, portals).
func teleport_to_checkpoint(checkpoint_id: StringName, sound: StringName = &"lift_move") -> void:
	var cp := Checkpoint.find(get_tree(), checkpoint_id)
	if cp == null:
		push_error("No checkpoint %s" % checkpoint_id)
		return
	phase = Phase.CINEMATIC
	player.input_enabled = false
	Audio.play_sfx(sound, -2.0)
	await SceneRouter.fade_through(func() -> void:
		var t := cp.spawn_transform()
		player.respawn_at(t.origin + Vector3.UP * 0.2, t.basis.get_euler().y)
		camera_rig.set_yaw_behind(t.basis.get_euler().y)
		camera_rig.snap_to_target()
		GameState.set_checkpoint(checkpoint_id)
		_update_area(true), 0.9)
	player.input_enabled = true
	phase = Phase.PLAYING
	SaveSystem.save_game()


## Short camera move to show something that just happened, then hand control back.
func show_point(target: Vector3, duration: float) -> void:
	if phase == Phase.CINEMATIC:
		return
	phase = Phase.CINEMATIC
	player.input_enabled = false
	var from := player.global_position
	var dir := Vector3(from.x - target.x, 0.0, from.z - target.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	var dist := clampf(from.distance_to(target) * 0.55, 5.0, 14.0)
	var cam_pos := target + dir * dist + Vector3.UP * dist * 0.45
	hud.set_letterbox(true, 0.5)
	await camera_rig.play_shots([{"position": cam_pos, "look": target, "time": 1.2, "hold": maxf(duration - 1.2, 0.4)}])
	hud.set_letterbox(false, 0.5)
	player.input_enabled = true
	phase = Phase.PLAYING


# --- Per frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	RenderingServer.global_shader_parameter_set(&"player_position", player.global_position)
	_area_timer -= delta
	if _area_timer <= 0.0:
		_area_timer = 0.3
		_update_area(false)
	var target := _target_mood()
	var k := 1.0 - exp(-delta * 1.5)
	for key: String in target:
		var a: Variant = _mood.get(key, target[key])
		_mood[key] = (a as Color).lerp(target[key], k) if a is Color else lerpf(a, target[key], k)
	_apply_mood(_mood)


func current_area() -> FacilityArea:
	for area in areas:
		if area.contains(player.global_position):
			return area
	return null


func _update_area(instant: bool) -> void:
	var area := current_area()
	if area == null:
		return
	if area.area_id != GameState.current_area:
		if phase == Phase.PLAYING or instant:
			GameState.enter_area(area.area_id)
			if not instant:
				Events.area_banner.emit(area.area_id)
				Audio.play_sfx(&"area_enter", -8.0)
				SaveSystem.request_save(1.0)
	else:
		GameState.set_flag(StringName("visited_%s" % area.area_id), true)
	Audio.play_music(AREA_MUSIC.get(area.area_id, &"lab"), 0.5 if instant else 4.0, -7.0)
	for id: StringName in GameData.FACILITY_AREA_IDS:
		Audio.set_ambient(StringName("%s_base" % id), 1.0 if id == area.area_id else 0.0, 0.5 if instant else 2.5, -8.0)


func _target_mood() -> Dictionary:
	var m := DEFAULT_MOOD.duplicate()
	var area := current_area()
	if area:
		var extra := area.mood()
		for key: String in extra:
			m[key] = extra[key]
	return m


# --- Environment ----------------------------------------------------------------------

func _setup_environment() -> void:
	environment = Environment.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://shaders/space_sky.gdshader")
	sky_material.set_shader_parameter("noise_tex", ScifiKit.NOISE)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_white = 6.0
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 1.8
	environment.ssil_radius = 4.0
	environment.ssil_intensity = 1.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.set_glow_level(1, 0.6)
	environment.set_glow_level(2, 1.0)
	environment.set_glow_level(3, 0.8)
	environment.set_glow_level(4, 0.5)
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_sky_affect = 0.0
	environment.volumetric_fog_anisotropy = 0.5
	environment.volumetric_fog_length = 70.0
	environment.volumetric_fog_ambient_inject = 0.3
	environment.volumetric_fog_sky_affect = 0.0
	environment.volumetric_fog_temporal_reprojection_enabled = true
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	# Bounce light (Medium and High): emissive strips, screens and lamps light the rooms.
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = false
	environment.sdfgi_bounce_feedback = 0.45
	environment.sdfgi_cascades = 4
	environment.sdfgi_min_cell_size = 0.2
	environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	environment.ssao_detail = 0.6
	environment.ssao_horizon = 0.08
	environment.ssao_light_affect = 0.15
	($WorldEnvironment as WorldEnvironment).environment = environment
	# Key light: faded in only where an area's mood asks for it (lab windows, quantum lab).
	sun = DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.6
	sun.visible = false
	add_child(sun)
	# Colour grade under the HUD.
	var layer := CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = -10
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grade = ShaderMaterial.new()
	grade.shader = preload("res://shaders/scifi_grade.gdshader")
	rect.material = grade
	layer.add_child(rect)
	_apply_quality()


func _apply_quality() -> void:
	var q := Settings.quality_params()
	environment.ssao_enabled = q["ssao"]
	# High runs bounce light (SDFGI) at full resolution, which covers what SSIL adds here.
	environment.ssil_enabled = q["ssil"] and Settings.quality < 2
	environment.ssr_enabled = q["ssr"]
	environment.volumetric_fog_enabled = q["fog_volumetric"]
	environment.glow_enabled = q["glow"]
	environment.sdfgi_enabled = Settings.quality >= 1
	RenderingServer.gi_set_use_half_resolution(Settings.quality < 2)
	sun.shadow_enabled = Settings.quality >= 1
	RenderingServer.positional_soft_shadow_filter_set_quality(int(q["shadow_filter"]) as RenderingServer.ShadowQuality)


func _apply_mood(m: Dictionary) -> void:
	environment.ambient_light_color = m["ambient"]
	environment.ambient_light_energy = m["ambient_energy"]
	environment.fog_light_color = m["fog"]
	environment.fog_density = m["fog_density"]
	environment.volumetric_fog_density = m["vol_fog"]
	environment.volumetric_fog_albedo = m["vol_albedo"]
	environment.glow_intensity = m["glow"]
	environment.tonemap_exposure = m["exposure"]
	environment.adjustment_saturation = m["saturation"]
	sky_material.set_shader_parameter("nebula_amount", m["nebula"])
	sky_material.set_shader_parameter("planet_size", m["planet"])
	environment.sdfgi_energy = m["gi"]
	sun.light_energy = m["sun"]
	sun.light_color = m["sun_color"]
	sun.visible = m["sun"] > 0.01
	sun.rotation_degrees = Vector3(m["sun_pitch"], m["sun_yaw"], 0.0)
	grade.set_shader_parameter("shadow_tint", m["shadow_tint"])
	grade.set_shader_parameter("highlight_tint", m["highlight_tint"])
	grade.set_shader_parameter("contrast", m["contrast"])
	grade.set_shader_parameter("vignette", m["vignette"])
	grade.set_shader_parameter("saturation", m["grade_saturation"])


# --- Input ------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYING or pause_menu.is_open():
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and phase == Phase.PLAYING and not pause_menu.is_open():
		pause_menu.open()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_game()
