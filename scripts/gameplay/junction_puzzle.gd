class_name JunctionPuzzle
extends Device
## Broken power line across three rotatable stone tiles. Energy flows from the source crystal
## through every correctly aligned tile (they light up as it reaches them); when it reaches
## the far end the linked node wakes. Each use rotates a tile 90 degrees.
##
## Grid (local X = east, local +Z = south, 2.2 m cells):
##   source -> [A](0,0) -> [B](1,0)
##                          [C](1,1) -> exit south -> target

const CELL := 2.2
const DIRS := {"N": Vector2i(0, -1), "E": Vector2i(1, 0), "S": Vector2i(0, 1), "W": Vector2i(-1, 0)}
const OPPOSITE := {"N": "S", "S": "N", "E": "W", "W": "E"}
## tile id -> [cell, kind, start rotation]
const TILES := {
	"A": [Vector2i(0, 0), "straight", 0],
	"B": [Vector2i(1, 0), "elbow", 1],
	"C": [Vector2i(1, 1), "straight", 1],
}
const SOURCE_CELL := Vector2i(-1, 0)
const SOURCE_DIR := "E"
const EXIT_CELL := Vector2i(1, 2)

@export var target_path: NodePath

var _tiles: Dictionary = {}       # id -> {node, rot, kind, cell, interactable}
var _rotations: Dictionary = {}
var _solved := false
var _source: Node3D
var _exit_line: Node3D


func _build() -> void:
	_source = PropLibrary.place(self, "power_pylon", _cell_pos(SOURCE_CELL), 0.0, 1.0, true)
	PropLibrary.set_power(_source, 1.0)
	var saved: Variant = GameState.get_puzzle_state(device_id, {})
	for id: String in TILES:
		var info: Array = TILES[id]
		var cell: Vector2i = info[0]
		var kind: String = info[1]
		var rot: int = int((saved as Dictionary).get(id, info[2])) if saved is Dictionary else int(info[2])
		var pivot := Node3D.new()
		pivot.name = "Tile_" + id
		add_child(pivot)
		pivot.position = _cell_pos(cell)
		var prop := PropLibrary.place(pivot, "junction_" + kind, Vector3.ZERO, 0.0, 1.0, true)
		prop.rotation.y = rot * PI * 0.5
		var it := make_interactable("Rotate the tile", 1.3, Vector3(0, 0.8, 0), pivot)
		it.interacted.connect(_on_tile_used.bind(id))
		_tiles[id] = {"node": prop, "rot": rot, "kind": kind, "cell": cell, "interactable": it}
	_exit_line = PropLibrary.place(self, "conduit", _cell_pos(EXIT_CELL) - Vector3(0, 0, CELL * 0.25), 0.0, 1.0, false)
	add_to_group(&"scannable")


func _restore_state() -> void:
	_solved = GameState.has_flag(flag_name("solved"))
	_evaluate(false)


func on_scanned(_origin: Vector3) -> void:
	for id: String in _tiles:
		ScanHighlight.flash_node(_tiles[id]["node"])


func _cell_pos(cell: Vector2i) -> Vector3:
	var local := Vector3(cell.x * CELL, 0.0, cell.y * CELL)
	var world := global_transform * local
	var h := WorldTerrain.height_at_world(world.x, world.z)
	return Vector3(local.x, h - global_position.y - 0.22, local.z)


static func connections(kind: String, rot: int) -> Array:
	if kind == "straight":
		return ["N", "S"] if rot % 2 == 0 else ["E", "W"]
	var order := ["S", "E", "N", "W"]
	return [order[rot % 4], order[(rot + 1) % 4]]


func _on_tile_used(_player: Node, id: String) -> void:
	if _solved:
		return
	var tile: Dictionary = _tiles[id]
	tile["rot"] = (int(tile["rot"]) + 1) % 4
	_rotations[id] = tile["rot"]
	var save := {}
	for tid: String in _tiles:
		save[tid] = _tiles[tid]["rot"]
	GameState.set_puzzle_state(device_id, save)
	Audio.play_sfx_3d(&"tile_turn", (tile["node"] as Node3D).global_position, -2.0)
	var node: Node3D = tile["node"]
	var tween := create_tween()
	tween.tween_property(node, "rotation:y", node.rotation.y + PI * 0.5, 0.3).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _evaluate(true))
	SaveSystem.request_save(3.0)


## Follows energy from the source; lights reached tiles; returns true when it exits.
func trace() -> Array:
	var lit: Array = []
	var cell := SOURCE_CELL + DIRS[SOURCE_DIR]
	var entering: String = OPPOSITE[SOURCE_DIR]
	for guard in 6:
		if cell == EXIT_CELL:
			lit.append("EXIT")
			return lit
		var tile_id := ""
		for id: String in _tiles:
			if _tiles[id]["cell"] == cell:
				tile_id = id
		if tile_id == "":
			return lit
		var conns := connections(_tiles[tile_id]["kind"], _tiles[tile_id]["rot"])
		if not conns.has(entering):
			return lit
		lit.append(tile_id)
		var exit_dir: String = conns[0] if conns[1] == entering else conns[1]
		cell += DIRS[exit_dir]
		entering = OPPOSITE[exit_dir]
	return lit


func _evaluate(animate: bool) -> void:
	var lit := trace() if not _solved else ["A", "B", "C", "EXIT"]
	for id: String in _tiles:
		PropLibrary.set_power(_tiles[id]["node"], 1.0 if lit.has(id) else 0.0)
		(_tiles[id]["interactable"] as Interactable).enabled = not _solved
	PropLibrary.set_power(_exit_line, 1.0 if lit.has("EXIT") else 0.0)
	if lit.has("EXIT") and not _solved:
		_solved = true
		GameState.set_flag(flag_name("solved"), true)
		for id: String in _tiles:
			(_tiles[id]["interactable"] as Interactable).enabled = false
		if animate:
			Audio.play_sfx_3d(&"puzzle_solved", global_position, 0.0)
		var target := get_node_or_null(target_path)
		if target and target.has_method("activate"):
			target.call("activate", animate)
	elif animate and lit.size() > 0:
		Audio.play_sfx_3d(&"switch_on", global_position, -8.0, 0.8 + lit.size() * 0.15)
