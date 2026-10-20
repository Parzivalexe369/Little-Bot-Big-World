class_name DiscoverySpot
extends Node3D
## An optional environmental story: inspect it to add an entry to the journal.
## Can wrap any prop placed as a child; a glint marks undiscovered spots.

@export var discovery_id: StringName = &""
@export var prompt := "Inspect"
@export var interact_radius := 2.0
@export var focus_offset := Vector3(0, 0.6, 0)
@export var snap_to_ground := true
@export var prop := ""
@export var prop_yaw := 0.0
@export var prop_scale := 1.0

var _interactable: Interactable
var _glint: GPUParticles3D


func _ready() -> void:
	if snap_to_ground:
		WorldTerrain.snap_node(self)
	if prop != "":
		var node := PropLibrary.place(self, prop, Vector3.ZERO, prop_yaw, prop_scale, true)
		node.name = "Prop"
	_interactable = Interactable.new()
	_interactable.prompt = prompt
	_interactable.radius = interact_radius
	_interactable.focus_offset = focus_offset
	_interactable.robot_action = &""
	add_child(_interactable)
	_interactable.interacted.connect(_on_interacted)
	add_to_group(&"scannable")
	if not GameState.has_discovery(discovery_id):
		_glint = FxFactory.sparkles(Color(1.0, 0.9, 0.6), 6, 0.4, 0.07)
		_glint.position = focus_offset
		add_child(_glint)


func on_scanned(_origin: Vector3) -> void:
	if not GameState.has_discovery(discovery_id):
		ScanHighlight.flash_node(get_node_or_null("Prop"), Color(1.0, 0.85, 0.5))


func _on_interacted(player: Node) -> void:
	var robot := player as Player
	if GameState.add_discovery(discovery_id):
		Events.discovery_shown.emit(discovery_id)
		Audio.play_sfx(&"discovery", -3.0)
		if robot:
			robot.visual.play_action(&"Victory")
		if _glint:
			_glint.emitting = false
		SaveSystem.request_save()
	else:
		Events.discovery_shown.emit(discovery_id)
