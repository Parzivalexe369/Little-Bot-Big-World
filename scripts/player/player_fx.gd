class_name PlayerFx
extends Node3D
## Presentation-only feedback around the robot: a soft contact shadow + hover glow projected
## on the ground (reads the robot's height during hops), dust kicked up while moving, an energy
## trail while boosting, and one-shot bursts for hop / land / bump / interact.

const DUST_COLORS := {
	&"meadow": Color(0.62, 0.55, 0.42, 0.42), &"forest": Color(0.42, 0.38, 0.3, 0.42),
	&"shrine": Color(0.66, 0.62, 0.55, 0.4), &"garden": Color(0.6, 0.56, 0.62, 0.4),
}
const TRAIL_COLOR := Color(0.6, 0.92, 1.0)

var player: Player
var _decal: Decal
var _dust: GPUParticles3D
var _trail: GPUParticles3D
var _dust_timer := 0.0
var _probe: ReflectionProbe


func _ready() -> void:
	player = get_parent() as Player
	_decal = Decal.new()
	# The box starts just under the robot's base, so only the ground is affected.
	_decal.size = Vector3(1.5, 4.0, 1.5)
	_decal.position = Vector3(0, -1.95, 0)
	_decal.texture_albedo = _radial(Color(0.03, 0.03, 0.05, 0.6), 0.0)
	_decal.texture_emission = _radial(Color(1.0, 0.86, 0.92, 1.0), 0.25)
	_decal.emission_energy = 0.0
	_decal.upper_fade = 0.05
	_decal.cull_mask = 0xFFFFF & ~RobotMaterials.ROBOT_LAYER
	_decal.lower_fade = 0.6
	add_child(_decal)
	_dust = FxFactory.dust_trail(DUST_COLORS[&"meadow"])
	add_child(_dust)
	_trail = FxFactory.energy_trail(TRAIL_COLOR)
	_trail.position = Vector3(0, 0.35, 0)
	add_child(_trail)
	_setup_probe()
	player.hopped.connect(_on_hopped)
	player.landed.connect(_on_landed)
	player.bonked.connect(_on_bonked)
	player.interacted_with.connect(_on_interacted)


func _process(delta: float) -> void:
	if player == null:
		return
	var pos := player.global_position
	var ground := _ground_height(pos)
	var height := maxf(pos.y - ground, 0.0)
	var awake := 0.0 if player.visual.is_sleeping() else 1.0
	# Contact shadow and glow spread and fade as the robot rises.
	var lift := clampf(height / 2.2, 0.0, 1.0)
	_decal.modulate = Color(1, 1, 1, 1.0 - lift * 0.85)
	_decal.size = Vector3(1.5 + lift * 0.8, 4.0, 1.5 + lift * 0.8)
	_decal.emission_energy = (0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.004)) * awake * (1.0 - lift)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var over_ground := height < 0.5
	_dust.emitting = over_ground and speed > 2.0 and awake > 0.0
	_dust.amount_ratio = clampf(speed / 8.0, 0.25, 1.0)
	_dust.global_position = Vector3(pos.x, ground + 0.05, pos.z)
	_dust_timer -= delta
	if _dust_timer <= 0.0:
		_dust_timer = 0.5
		(_dust.process_material as ParticleProcessMaterial).color = _dust_color(pos)
	_trail.emitting = player.is_boosting() and speed > 3.0
	if _probe and Vector2(_probe.global_position.x - pos.x, _probe.global_position.z - pos.z).length() > 10.0:
		_place_probe()


## Local reflections around the robot (chrome trim, visor, clear coat, nearby water) so they
## mirror the surrounding meadow or forest instead of only the sky. The probe re-renders
## (time-sliced over a few frames) only after the robot has moved 10 m. Medium and High.
func _setup_probe() -> void:
	if Settings.quality <= 0:
		return
	_probe = ReflectionProbe.new()
	_probe.name = "LocalReflections"
	_probe.top_level = true
	_probe.size = Vector3(40, 18, 40)
	_probe.origin_offset = Vector3(0, -6.5, 0)
	_probe.box_projection = true
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	_probe.cull_mask = 0xFFFFF & ~RobotMaterials.ROBOT_LAYER
	_probe.max_distance = 90.0
	_probe.blend_distance = 6.0
	_probe.mesh_lod_threshold = 4.0
	_probe.enable_shadows = false
	add_child(_probe)
	_place_probe()


func _place_probe() -> void:
	var pos := player.global_position
	_probe.global_position = Vector3(pos.x, _ground_height(pos) + 7.0, pos.z)


## Ground below a point: the terrain in the garden world, a short ray elsewhere.
func _ground_height(pos: Vector3) -> float:
	if WorldTerrain.is_ready():
		return WorldTerrain.height_at_world(pos.x, pos.z)
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 6.0, 1)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else pos.y - 6.0


func _dust_color(pos: Vector3) -> Color:
	if not WorldTerrain.is_ready():
		return Color(0.62, 0.64, 0.68, 0.32)
	var w := WorldLayout.area_weights(Vector2(pos.x, pos.z))
	var c := Color(0, 0, 0, 0)
	for area: StringName in DUST_COLORS:
		var k: float = w.get(area, 0.0)
		var d: Color = DUST_COLORS[area]
		c = Color(c.r + d.r * k, c.g + d.g * k, c.b + d.b * k, c.a + d.a * k)
	return c if c.a > 0.05 else DUST_COLORS[&"meadow"]


func _ground_point() -> Vector3:
	var pos := player.global_position
	return Vector3(pos.x, _ground_height(pos) + 0.05, pos.z)


func _spawn(node: Node3D, at: Vector3) -> void:
	get_tree().current_scene.add_child(node)
	node.global_position = at


func _on_hopped() -> void:
	var g := _ground_point()
	if player.global_position.y - g.y < 0.6:
		_spawn(FxFactory.dust_burst(_dust_color(g), 10, 1.6, 0.4), g)


func _on_landed(strength: float) -> void:
	var g := _ground_point()
	if player.global_position.y - g.y > 0.6:
		return
	_spawn(FxFactory.dust_burst(_dust_color(g), int(12 + strength * 14), 1.8 + strength * 2.0, 0.45 + strength * 0.25), g)
	FxFactory.ring_pulse(get_tree().current_scene, g + Vector3.UP * 0.04, Color(1.0, 0.9, 0.95, 0.35), 0.9 + strength * 0.8, 0.45)


func _on_bonked(contact: Vector3) -> void:
	_spawn(FxFactory.burst(Color(1.0, 0.75, 0.45), 14, 2.5, 0.08), contact)
	_spawn(FxFactory.dust_burst(_dust_color(contact), 10, 1.5, 0.45), contact)


func _on_interacted(target: Interactable) -> void:
	if target == null:
		return
	var at := target.get_focus_point()
	FxFactory.ring_pulse(get_tree().current_scene, at, Color(0.55, 0.95, 1.0, 0.8), 0.8, 0.5, true)
	_spawn(FxFactory.burst(Color(0.55, 0.95, 1.0), 10, 1.6, 0.07), at)


static func _radial(color: Color, ring: float) -> GradientTexture2D:
	var g := Gradient.new()
	var clear := Color(color.r, color.g, color.b, 0.0)
	if ring > 0.0:
		# Emission ignores alpha, so the glow is premultiplied and fades to black.
		g.set_color(0, Color(color.r * 0.35, color.g * 0.35, color.b * 0.35, 1.0))
		g.set_color(1, Color(0, 0, 0, 1))
		g.add_point(0.45, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 1.0))
		g.add_point(0.8, Color(color.r * 0.1, color.g * 0.1, color.b * 0.1, 1.0))
	else:
		g.set_color(0, color)
		g.set_color(1, clear)
		g.add_point(0.45, Color(color.r, color.g, color.b, color.a * 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
