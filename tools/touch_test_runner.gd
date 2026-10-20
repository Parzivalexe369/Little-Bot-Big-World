extends Node
## Dev tool: drives the garden with injected touch events and checks the touch controls.
## Usage (windowed): godot --path . res://tools/touch_test_runner.tscn -- [screenshot_dir]
## Prints "TOUCH ok/FAIL ..." lines and "TOUCH RESULT: N failures".

var world: Node
var player: Player
var hud: Hud
var tc: TouchControls
var failures := 0
var shot_dir := ""


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("TOUCH %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot_dir.path_join(name + ".png"))


## Canvas position (what the controls use) -> window pixels (what input events carry).
func _win(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _touch(index: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _win(p)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, from: Vector2, to: Vector2, steps := 8) -> void:
	var prev := from
	for i in range(1, steps + 1):
		var p := from.lerp(to, float(i) / steps)
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = _win(p)
		e.relative = _win(p) - _win(prev)
		e.screen_relative = e.relative
		Input.parse_input_event(e)
		prev = p
		await get_tree().process_frame


func _button(id: int) -> Vector2:
	return tc._buttons[id]["pos"]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		shot_dir = args[0]
	get_window().size = Vector2i(1600, 900)
	# Autosaves (waking up) go to a test slot, so the real save is untouched.
	SaveSystem.use_slot("user://touch_test_save.json")
	Settings.touch_controls = 1
	if args.has("facility"):
		await _run_facility()
		return
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("pause_on_focus_loss", false)
	player = world.get_node("Player") as Player
	hud = world.get("hud") as Hud
	await _frames(90)
	tc = hud.get("_touch") as TouchControls
	_check(tc != null and TouchControls.active, "touch controls exist and are active (Always)")
	_check(tc._mode() == 1, "intro: only USE shown while the robot sleeps (mode %d)" % tc._mode())
	_check(InputGlyphs.label("interact") == "USE", "prompt shows the touch label (%s)" % InputGlyphs.label("interact"))
	await _shot("touch_01_intro")

	# Wake up by tapping the on-screen prompt.
	var rect := hud.prompt_rect()
	_check(rect.size.x > 0.0, "wake-up prompt has a tappable rect %s" % rect)
	_touch(0, rect.get_center(), true)
	await _frames(3)
	_touch(0, rect.get_center(), false)
	var t0 := Time.get_ticks_msec()
	while not player.input_enabled and Time.get_ticks_msec() - t0 < 12000:
		await _frames(5)
	_check(player.input_enabled, "tapping the prompt woke the robot")
	await _frames(40)
	_check(tc._mode() == 2, "play: all touch controls shown (mode %d)" % tc._mode())
	_check(not hud.get("_scan_box").visible, "HUD scan ring hidden (it is on the SCAN button)")
	await _shot("touch_02_play")

	# Move: drag the stick forward and hold.
	var start := player.global_position
	var home: Vector2 = tc._stick_home
	_touch(1, home, true)
	await _drag(1, home, home + Vector2(0, -tc._stick_radius * 0.95))
	await _frames(70)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(moved > 1.5, "stick moves the robot (%.2f m in ~1.2 s)" % moved)
	_check(not player.get("_boosting"), "stick inside its rim does not boost")
	await _shot("touch_03_stick")
	# Push past the rim: boost.
	await _drag(1, home + Vector2(0, -tc._stick_radius * 0.95), home + Vector2(0, -tc._stick_radius * 1.4), 4)
	await _frames(30)
	_check(player.get("_boosting"), "stick pushed past its rim boosts")
	_touch(1, home + Vector2(0, -tc._stick_radius * 1.4), false)
	await _frames(30)
	_check(Input.get_vector("move_left", "move_right", "move_forward", "move_back") == Vector2.ZERO, "releasing the stick stops movement")
	_check(not Input.is_action_pressed("boost"), "releasing the stick ends the boost")

	# Look: drag across the right side.
	var rig := player.camera_rig
	var yaw0 := rig.yaw
	var look_from := Vector2(tc._view.x * 0.62, tc._view.y * 0.45)
	_touch(2, look_from, true)
	await _drag(2, look_from, look_from + Vector2(tc._view.x * 0.2, 0), 10)
	_touch(2, look_from + Vector2(tc._view.x * 0.2, 0), false)
	await _frames(2)
	_check(absf(angle_difference(yaw0, rig.yaw)) > 0.4, "dragging turns the camera (%.2f rad)" % angle_difference(yaw0, rig.yaw))

	# Pinch: two fingers apart = zoom in.
	var dist0 := rig.desired_distance
	var a := Vector2(tc._view.x * 0.58, tc._view.y * 0.45)
	var b := Vector2(tc._view.x * 0.72, tc._view.y * 0.45)
	_touch(3, a, true)
	_touch(4, b, true)
	await _frames(2)
	for i in range(1, 9):
		var e := InputEventScreenDrag.new()
		e.index = 4
		e.position = _win(b + Vector2(tc._view.x * 0.012 * i, 0))
		e.relative = _win(Vector2(tc._view.x * 0.012, 0)) - _win(Vector2.ZERO)
		Input.parse_input_event(e)
		await get_tree().process_frame
	_touch(4, b, false)
	_touch(3, a, false)
	await _frames(2)
	_check(rig.desired_distance < dist0 - 0.2, "pinching apart zooms in (%.2f -> %.2f)" % [dist0, rig.desired_distance])

	# Hop.
	await _frames(20)
	_touch(5, _button(TouchControls.HOP), true)
	var up := false
	for i in 20:
		await get_tree().physics_frame
		up = up or player.velocity.y > 1.0
	_touch(5, _button(TouchControls.HOP), false)
	_check(up, "HOP button hops")
	await _frames(60)

	# Scan.
	_touch(6, _button(TouchControls.SCAN), true)
	await _frames(4)
	_touch(6, _button(TouchControls.SCAN), false)
	await _frames(4)
	_check(player.scan_ready_ratio < 0.5, "SCAN button scans (cooldown %.2f)" % player.scan_ready_ratio)
	await _shot("touch_04_scan")

	# BOOST button (hold) while moving.
	_touch(7, home, true)
	await _drag(7, home, home + Vector2(0, -tc._stick_radius * 0.9), 4)
	_touch(8, _button(TouchControls.BOOST), true)
	await _frames(30)
	_check(player.get("_boosting"), "BOOST button boosts while moving")
	_touch(8, _button(TouchControls.BOOST), false)
	_touch(7, home, false)
	await _frames(10)

	# Pause and journal.
	var menu: PauseMenu = world.get("pause_menu")
	_touch(9, _button(TouchControls.PAUSE), true)
	await _frames(3)
	_touch(9, _button(TouchControls.PAUSE), false)
	await _frames(3)
	_check(menu.is_open(), "PAUSE button opens the pause menu")
	await _shot("touch_05_pause")
	menu.close()
	await _frames(10)
	_touch(10, _button(TouchControls.JOURNAL), true)
	await _frames(3)
	_touch(10, _button(TouchControls.JOURNAL), false)
	await _frames(3)
	_check(menu.is_open(), "JOURNAL button opens the journal")
	menu.close()
	await _frames(10)
	_check(Input.get_vector("move_left", "move_right", "move_forward", "move_back") == Vector2.ZERO and not Input.is_action_pressed("hop"), "nothing is left held after the menus")

	# Auto mode: a key press hands control back to the keyboard and restores the HUD.
	Settings.touch_controls = 0
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(3)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(20)
	_check(not TouchControls.active, "a key press switches touch controls off (Auto)")
	_check(hud.get("_scan_box").visible, "HUD scan ring is back for keyboard play")
	_check(InputGlyphs.label("interact") == "E", "prompts show keys again (%s)" % InputGlyphs.label("interact"))
	_touch(11, Vector2(tc._view.x * 0.6, tc._view.y * 0.5), true)
	await _frames(2)
	_touch(11, Vector2(tc._view.x * 0.6, tc._view.y * 0.5), false)
	await _frames(20)
	_check(TouchControls.active and tc._mode() == 2, "a touch brings the controls back (Auto)")

	print("TOUCH RESULT: %d failures" % failures)
	get_tree().quit()


## The sci-fi areas: same HUD, their own world script (pause, journal, arrival).
func _run_facility() -> void:
	world = (load("res://scenes/facility/facility.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	world.set("pause_on_focus_loss", false)
	player = world.get_node("Player") as Player
	hud = world.get("hud") as Hud
	var t0 := Time.get_ticks_msec()
	while not player.input_enabled and Time.get_ticks_msec() - t0 < 15000:
		await _frames(5)
	await _frames(60)
	tc = hud.get("_touch") as TouchControls
	_check(player.input_enabled and tc._mode() == 2, "facility: touch controls shown in play (mode %d)" % tc._mode())
	var start := player.global_position
	var home: Vector2 = tc._stick_home
	_touch(1, home, true)
	await _drag(1, home, home + Vector2(0, -tc._stick_radius * 0.95))
	await _frames(60)
	_touch(1, home, false)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check(moved > 1.0, "facility: stick moves the robot (%.2f m)" % moved)
	var rig := player.camera_rig
	var yaw0 := rig.yaw
	var look_from := Vector2(tc._view.x * 0.62, tc._view.y * 0.45)
	_touch(2, look_from, true)
	await _drag(2, look_from, look_from + Vector2(tc._view.x * 0.2, 0), 10)
	_touch(2, look_from, false)
	_check(absf(angle_difference(yaw0, rig.yaw)) > 0.4, "facility: dragging turns the camera")
	await _shot("touch_06_facility")
	var menu: PauseMenu = world.get("pause_menu")
	_touch(3, _button(TouchControls.PAUSE), true)
	await _frames(3)
	_touch(3, _button(TouchControls.PAUSE), false)
	await _frames(3)
	_check(menu.is_open(), "facility: PAUSE button opens the pause menu")
	_check(not tc.visible, "facility: touch controls hide under the pause menu")
	menu.close()
	await _frames(10)
	_check(tc.visible, "facility: touch controls return after the menu")
	print("TOUCH RESULT: %d failures" % failures)
	get_tree().quit()
