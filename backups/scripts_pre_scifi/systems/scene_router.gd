extends CanvasLayer
## Scene changes with a soft fade, plus a hand-off of "how to start" between menu and world.

signal fade_finished

enum StartMode { NEW_GAME, CONTINUE }

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const WORLD := "res://scenes/world/world.tscn"

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
	go_to(WORLD)


func go_to_menu() -> void:
	GameState.in_gameplay = false
	go_to(MAIN_MENU)


func go_to(path: String, fade_time: float = 0.6) -> void:
	if _busy:
		return
	_busy = true
	await fade_out(fade_time)
	_loading.text = "Waking up..." if path == WORLD else "Returning..."
	_loading.modulate.a = 0.8
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Could not change scene to %s (%s)" % [path, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	_busy = false
	_loading.modulate.a = 0.0
	await fade_in(fade_time)


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
