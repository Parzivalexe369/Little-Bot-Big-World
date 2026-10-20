extends CanvasLayer
## Scene changes with a soft fade, plus a hand-off of "how to start" between menu and world.

signal fade_finished

enum StartMode { NEW_GAME, CONTINUE, TRAVEL }

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const WORLD := "res://scenes/world/world.tscn"
## The three sci-fi areas below the garden.
const FACILITY := "res://scenes/facility/facility.tscn"

var start_mode: StartMode = StartMode.NEW_GAME
var _fade: ColorRect
var _loading: Label
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.035, 0.05, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_loading = Label.new()
	_loading.text = "Waking up..."
	_loading.theme_type_variation = &"HintLabel"
	_loading.anchor_left = 1.0
	_loading.anchor_right = 1.0
	_loading.anchor_top = 1.0
	_loading.anchor_bottom = 1.0
	_loading.offset_left = -320
	_loading.offset_top = -80
	_loading.offset_right = -48
	_loading.offset_bottom = -40
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Longer (two-line) messages grow up and to the left, staying inside the screen.
	_loading.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_loading.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_loading.modulate.a = 0.0
	add_child(_loading)


func _exit_tree() -> void:
	PropLibrary.release()


func is_busy() -> bool:
	return _busy


func start_new_game() -> void:
	SaveSystem.delete_save()
	GameState.reset()
	start_mode = StartMode.NEW_GAME
	go_to(WORLD)


func continue_game() -> void:
	if not SaveSystem.load_game():
		start_new_game()
		return
	start_mode = StartMode.CONTINUE
	go_to(FACILITY if GameState.location == &"facility" else WORLD)


## Moves the robot to an area's entry checkpoint (or a given checkpoint), switching scenes
## when needed. Used by the travel screen and by the lifts between the garden and facility.
func travel_to(area_id: StringName, checkpoint: StringName = &"") -> void:
	if _busy:
		return
	GameState.checkpoint_id = checkpoint if checkpoint != &"" else GameData.AREA_ENTRY_CHECKPOINT.get(area_id, &"station")
	GameState.location = &"facility" if GameData.is_facility_area(area_id) else &"world"
	GameState.current_area = area_id
	start_mode = StartMode.TRAVEL
	# Saved without a live snapshot so a reload lands on the checkpoint, not the old spot.
	var provider := SaveSystem.player_snapshot_provider
	SaveSystem.player_snapshot_provider = Callable()
	SaveSystem.save_game()
	SaveSystem.player_snapshot_provider = provider
	go_to(FACILITY if GameState.location == &"facility" else WORLD)


func go_to_menu() -> void:
	GameState.in_gameplay = false
	go_to(MAIN_MENU)


func go_to(path: String, fade_time: float = 0.6) -> void:
	if _busy:
		return
	_busy = true
	await fade_out(fade_time)
	_loading.text = {WORLD: "Waking up...", FACILITY: "Descending..."}.get(path, "Returning...")
	if OS.has_feature("web") and path != MAIN_MENU:
		_loading.text += "\nThe first visit can take a minute or two."
	_loading.modulate.a = 0.8
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Could not change scene to %s (%s)" % [path, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.has_feature("web") and path != MAIN_MENU:
		await _settle_shaders()
	_busy = false
	_loading.modulate.a = 0.0
	await fade_in(fade_time)


## Browsers compile each shader the first time it is drawn, which freezes the page for a while
## on a first visit. Keep the loading screen up, with the game paused, until frames come
## smoothly again, so the scene does not start (or fade in) in jerks.
func _settle_shaders() -> void:
	get_tree().paused = true
	# Draw the whole level and the common effects once now, so their shaders do not compile
	# (and freeze the game) the first time each one appears in play.
	var scene := get_tree().current_scene
	if scene is Node3D:
		await ShaderWarmup.run(scene as Node3D)
	var smooth := 0
	var start := Time.get_ticks_msec()
	var last := start
	# Compile stalls last seconds; a merely slow device (a few fps) still counts as smooth.
	while smooth < 30 and Time.get_ticks_msec() - start < 240000:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		smooth = smooth + 1 if now - last < 500 else 0
		last = now
	# Leave the game paused if its pause menu opened meanwhile (e.g. the tab lost focus).
	var menu := get_tree().current_scene.get("pause_menu") as PauseMenu if get_tree().current_scene else null
	if menu == null or not menu.is_open():
		get_tree().paused = false


func fade_out(duration: float = 0.6) -> void:
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, duration)
	await tween.finished
	fade_finished.emit()


func fade_in(duration: float = 0.8) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, duration)
	await tween.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_finished.emit()


## Fade to black, run a callback (e.g. respawn), fade back.
func fade_through(callback: Callable, duration: float = 0.45) -> void:
	await fade_out(duration)
	callback.call()
	await get_tree().process_frame
	await fade_in(duration)
