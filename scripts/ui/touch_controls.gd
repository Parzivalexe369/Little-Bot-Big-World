class_name TouchControls
extends CanvasLayer
## On-screen controls for tablets and phones (part of the HUD, so both the garden and the
## facility get them):
##   * a floating stick on the left half: move; push it past its rim to boost,
##   * drag anywhere else to look around, pinch with two fingers to zoom,
##   * thumb buttons bottom right: HOP (hold for a higher hop), BOOST (hold), USE, SCAN
##     (with its cooldown ring), plus PAUSE and JOURNAL at the top,
##   * tapping an on-screen prompt (e.g. "Wake up") uses it.
## Buttons send the same input actions as the keys, so every system reacts as it does to a
## keyboard or gamepad. The controls appear on touch screens and hide as soon as a keyboard,
## mouse or gamepad is used (Settings: Auto / Always / Off), so desktop play is unchanged.
## Sizes follow the physical screen size, and the layout follows any size or orientation.

enum { HOP, BOOST, USE, SCAN, PAUSE, JOURNAL }

const ACTIONS := {HOP: "hop", BOOST: "boost", USE: "interact", SCAN: "scan", PAUSE: "pause", JOURNAL: "journal"}
const CAPTIONS := {HOP: "HOP", BOOST: "BOOST", USE: "USE", SCAN: "SCAN", PAUSE: "", JOURNAL: ""}
## Button radius in CSS pixels (about 9 mm on an iPad) before the size setting.
const BUTTON_CSS_RADIUS := 34.0
## Look speed: radians per full screen width / height of drag (times look sensitivity).
const LOOK_YAW := 3.4
const LOOK_PITCH := 2.2
## The stick boosts once dragged this far past its rim.
const BOOST_RIM := 1.15
const FILL := Color(0.05, 0.06, 0.09, 0.42)
const FILL_PRESSED := Color(0.5, 0.94, 1.0, 0.34)
const EDGE := Color(1, 1, 1, 0.28)
const ENERGY := Color(0.5, 0.94, 1.0)
const CREAM := Color(0.97, 0.94, 0.87)

## True while touch is the input in use (read by prompts; shared across scenes).
static var active := false
static var _initialised := false

var hud: Hud

var _surface: Control
var _font: Font
var _view := Vector2(1920, 1080)
var _r := 50.0
var _margin := 40.0
var _alpha := 0.0
var _use_alpha := 0.0
var _buttons := {}
var _held := {}
var _stick_radius := 95.0
var _stick_home := Vector2.ZERO
var _stick_center := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _stick_index := -1
var _stick_boost := false
var _boost_button := false
var _boost_on := false
var _move := Vector2.ZERO
var _look_index := -1
var _look_start_time := 0
var _look_moved := 0.0
var _look_on_prompt := false
var _pinch_index := -1
var _pinch_dist := 0.0
var _touch_pos := {}
var _pulse := 0.0


func _ready() -> void:
	layer = 11
	if not _initialised:
		_initialised = true
		active = Settings.touch_controls == 1 or (Settings.touch_controls == 0 and DisplayServer.is_touchscreen_available())
	_surface = Control.new()
	_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.draw.connect(_draw_controls)
	add_child(_surface)
	_font = _surface.get_theme_default_font()
	get_viewport().size_changed.connect(_layout)
	Settings.changed.connect(_on_settings_changed)
	_layout.call_deferred()


func _exit_tree() -> void:
	_release_all()


func _notification(what: int) -> void:
	# Pausing (menus) or losing focus must not leave a stick or button held down.
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()
	# Hidden under pause menus (this node stops processing, so it would stay drawn).
	if what == NOTIFICATION_PAUSED:
		visible = false


## Space the controls take at the bottom of the screen (the HUD moves its toasts above it).
func reserved_bottom() -> float:
	return _stick_radius * 2.0 + _margin + 24.0


func _on_settings_changed() -> void:
	if Settings.touch_controls == 2:
		_set_active(false)
	elif Settings.touch_controls == 1:
		_set_active(true)
	_layout()


func _set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	if not value:
		_release_all()


# --- Input ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	_observe(event)
	if not active:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		# Taps also arrive as emulated mouse clicks; in play they would only try to capture
		# the mouse. Menus (which pause the game) still get them, since this node pauses too.
		get_viewport().set_input_as_handled()


## Touch switches to touch controls; a real keyboard, mouse or gamepad switches back.
func _observe(event: InputEvent) -> void:
	if Settings.touch_controls != 0:
		return
	if event is InputEventScreenTouch:
		_set_active(true)
	elif active and (event is InputEventKey and (event as InputEventKey).pressed \
			or event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION \
			or event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and (event as InputEventMouseMotion).relative.length() > 4.0 \
			or event is InputEventJoypadButton \
			or event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_set_active(false)


func _on_touch(e: InputEventScreenTouch) -> void:
	var idx := e.index
	if e.pressed and not e.canceled:
		var mode := _mode()
		var button := _button_at(e.position, mode)
		if button >= 0:
			_held[idx] = button
			_press(button)
		elif mode == 2 and _stick_index < 0 and _in_stick_zone(e.position):
			_stick_index = idx
			_stick_center = _clamped_stick_center(e.position)
			_stick_knob = e.position
			_update_stick()
		else:
			_touch_pos[idx] = e.position
			if _look_index < 0:
				_look_index = idx
				_look_start_time = Time.get_ticks_msec()
				_look_moved = 0.0
				_look_on_prompt = hud != null and hud.prompt_rect().grow(_r * 0.4).has_point(e.position)
			elif _pinch_index < 0 and mode == 2:
				_pinch_index = idx
				_pinch_dist = (_touch_pos[_look_index] as Vector2).distance_to(e.position)
	else:
		if _held.has(idx):
			_release(_held[idx])
			_held.erase(idx)
		elif idx == _stick_index:
			_stick_index = -1
			_stick_knob = _stick_home
			_stick_center = _stick_home
			_update_stick()
		elif idx == _look_index:
			var tap := Time.get_ticks_msec() - _look_start_time < 350 and _look_moved < _r * 0.5
			if tap and _look_on_prompt:
				_tap("interact")
			_look_index = _pinch_index
			_pinch_index = -1
		elif idx == _pinch_index:
			_pinch_index = -1
		_touch_pos.erase(idx)
	_surface.queue_redraw()


func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _stick_index:
		_stick_knob = e.position
		_update_stick()
		_surface.queue_redraw()
		return
	if e.index != _look_index and e.index != _pinch_index:
		return
	_touch_pos[e.index] = e.position
	var rig := _rig()
	if _pinch_index >= 0 and _touch_pos.has(_look_index) and _touch_pos.has(_pinch_index):
		var d := (_touch_pos[_look_index] as Vector2).distance_to(_touch_pos[_pinch_index])
		if rig and _pinch_dist > 1.0 and d > 1.0:
			rig.touch_zoom(_pinch_dist / d)
		_pinch_dist = d
	elif e.index == _look_index:
		_look_moved += e.relative.length()
		if rig and _mode() == 2:
			rig.touch_look(e.relative / _view)


func _update_stick() -> void:
	var v := (_stick_knob - _stick_center) / _stick_radius if _stick_index >= 0 else Vector2.ZERO
	_stick_boost = v.length() > BOOST_RIM
	_set_move(v.limit_length(1.0))
	_update_boost()


func _set_move(v: Vector2) -> void:
	_move = v
	_axis("move_left", "move_right", v.x)
	_axis("move_forward", "move_back", v.y)


func _axis(negative: String, positive: String, value: float) -> void:
	if value < -0.001:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	elif value > 0.001:
		Input.action_press(positive, value)
		Input.action_release(negative)
	else:
		Input.action_release(negative)
		Input.action_release(positive)


func _update_boost() -> void:
	var want := _boost_button or _stick_boost
	if want == _boost_on:
		return
	_boost_on = want
	if want:
		Input.action_press("boost")
	else:
		Input.action_release("boost")


func _press(button: int) -> void:
	if button == BOOST:
		_boost_button = true
		_update_boost()
	elif button == PAUSE or button == JOURNAL:
		# Menus react to the press event itself; release at once so nothing stays held
		# while the game is paused.
		_send(ACTIONS[button], true)
		_send(ACTIONS[button], false)
	else:
		_send(ACTIONS[button], true)


func _release(button: int) -> void:
	if button == BOOST:
		_boost_button = false
		_update_boost()
	elif button != PAUSE and button != JOURNAL:
		_send(ACTIONS[button], false)


## A short press (tapping a prompt), held long enough for systems that poll each frame.
func _tap(action: String) -> void:
	_send(action, true)
	await get_tree().create_timer(0.12).timeout
	_send(action, false)


func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _release_all() -> void:
	for idx: int in _held:
		_release(_held[idx])
	_held.clear()
	_stick_index = -1
	_stick_knob = _stick_home
	_stick_center = _stick_home
	_stick_boost = false
	_boost_button = false
	_set_move(Vector2.ZERO)
	_update_boost()
	_look_index = -1
	_pinch_index = -1
	_touch_pos.clear()
	if _surface:
		_surface.queue_redraw()


# --- State and layout -------------------------------------------------------------------

## 0 hidden, 1 only USE (e.g. "Wake up" while the HUD is hidden), 2 everything.
func _mode() -> int:
	if not active or hud == null or hud.player == null:
		return 0
	if hud.is_hud_shown() and hud.player.input_enabled:
		return 2
	if hud.forced_prompt != "":
		return 1
	return 0


func _rig() -> CameraRig:
	return hud.player.camera_rig if hud and hud.player else null


func _layout() -> void:
	if _surface == null:
		return
	_view = _surface.get_viewport_rect().size
	# Canvas units per CSS pixel, so buttons keep a thumb-friendly physical size everywhere.
	var px_per_unit := get_viewport().get_final_transform().get_scale().x
	var css_per_unit := maxf(px_per_unit, 0.01) / maxf(DisplayServer.screen_get_scale(), 1.0)
	_r = clampf(BUTTON_CSS_RADIUS / css_per_unit * Settings.touch_size, 36.0, minf(_view.x, _view.y) * 0.09)
	_margin = _r * 0.55 + 18.0
	_stick_radius = _r * 1.85
	_stick_home = Vector2(_margin + _stick_radius, _view.y - _margin - _stick_radius)
	if _stick_index < 0:
		_stick_center = _stick_home
		_stick_knob = _stick_home
	var hop_r := _r * 1.3
	var gap := _r * 0.4
	var hop := Vector2(_view.x - _margin - hop_r, _view.y - _margin - hop_r)
	_buttons = {
		HOP: {"pos": hop, "r": hop_r},
		USE: {"pos": hop + Vector2(-(hop_r + _r + gap), hop_r - _r), "r": _r},
		BOOST: {"pos": hop + Vector2(hop_r - _r, -(hop_r + _r + gap)), "r": _r},
		SCAN: {"pos": hop + Vector2(-1, -1).normalized() * (hop_r + _r + gap) * 1.08, "r": _r},
	}
	var small := _r * 0.72
	var top := _margin * 0.6 + small
	_buttons[PAUSE] = {"pos": Vector2(_view.x * 0.5 + small + gap * 0.5, top), "r": small}
	_buttons[JOURNAL] = {"pos": Vector2(_view.x * 0.5 - small - gap * 0.5, top), "r": small}
	_surface.queue_redraw()


func _button_at(p: Vector2, mode: int) -> int:
	if mode == 0:
		return -1
	for id: int in _buttons:
		if mode == 1 and id != USE:
			continue
		var b: Dictionary = _buttons[id]
		if p.distance_to(b["pos"]) <= float(b["r"]) * 1.15:
			return id
	return -1


func _in_stick_zone(p: Vector2) -> bool:
	return p.x < _view.x * 0.45 and p.y > _view.y * 0.3


func _clamped_stick_center(p: Vector2) -> Vector2:
	var lo := Vector2(_margin + _stick_radius * 0.6, _view.y * 0.3)
	var hi := Vector2(_view.x * 0.45, _view.y - _margin - _stick_radius * 0.6)
	return p.clamp(lo, hi)


func _process(delta: float) -> void:
	var mode := _mode()
	if mode == 0 and (_stick_index >= 0 or not _held.is_empty()):
		_release_all()
	_alpha = move_toward(_alpha, 1.0 if mode == 2 else 0.0, delta * 4.0)
	_use_alpha = move_toward(_use_alpha, 1.0 if mode >= 1 else 0.0, delta * 4.0)
	_pulse += delta
	visible = _use_alpha > 0.0
	if visible:
		_surface.queue_redraw()


# --- Drawing ----------------------------------------------------------------------------

func _draw_controls() -> void:
	if _use_alpha <= 0.0:
		return
	var a := _alpha
	if a > 0.0:
		_draw_stick(a)
		for id: int in [HOP, BOOST, SCAN, PAUSE, JOURNAL]:
			_draw_button(id, a)
	_draw_button(USE, _use_alpha)


func _draw_stick(a: float) -> void:
	var touching := _stick_index >= 0
	var base_a := a * (1.0 if touching else 0.8)
	_surface.draw_circle(_stick_center, _stick_radius, Color(FILL, FILL.a * base_a))
	var rim := Color(ENERGY, 0.9) if _stick_boost else Color(1, 1, 1, 0.45)
	_surface.draw_arc(_stick_center, _stick_radius, 0.0, TAU, 64, Color(rim, rim.a * base_a), 3.0, true)
	# Boost hint: a faint outer ring past the rim.
	_surface.draw_arc(_stick_center, _stick_radius * BOOST_RIM, 0.0, TAU, 64, Color(ENERGY, 0.18 * base_a), 2.0, true)
	var knob := _stick_center + (_stick_knob - _stick_center).limit_length(_stick_radius * BOOST_RIM)
	_surface.draw_circle(knob, _r * 0.78, Color(CREAM, 0.30 * base_a + (0.2 * a if touching else 0.0)))
	_surface.draw_arc(knob, _r * 0.78, 0.0, TAU, 48, Color(1, 1, 1, 0.5 * base_a), 2.0, true)


func _draw_button(id: int, a: float) -> void:
	if not _buttons.has(id):
		return
	var b: Dictionary = _buttons[id]
	var c: Vector2 = b["pos"]
	var r: float = b["r"]
	var pressed := _held.values().has(id) or (id == BOOST and _boost_on)
	var ready := id == USE and hud != null and hud.prompt_active()
	_surface.draw_circle(c, r, Color(FILL_PRESSED if pressed else FILL, (FILL_PRESSED.a if pressed else FILL.a) * a))
	var edge := EDGE
	var width := 2.5
	if ready:
		edge = Color(ENERGY, 0.65 + 0.35 * sin(_pulse * 5.0))
		width = 4.0
	_surface.draw_arc(c, r, 0.0, TAU, 64, Color(edge, edge.a * a), width, true)
	var ink := Color(CREAM, 0.92 * a)
	match id:
		HOP:
			_chevron(c + Vector2(0, -r * 0.12), r * 0.34, ink)
		BOOST:
			_chevron(c + Vector2(0, -r * 0.30), r * 0.26, ink)
			_chevron(c + Vector2(0, -r * 0.05), r * 0.26, ink)
		SCAN:
			for k in 3:
				_surface.draw_arc(c + Vector2(0, -r * 0.05), r * (0.14 + 0.13 * k), deg_to_rad(-150), deg_to_rad(-30), 16, ink, 2.5, true)
			var ratio: float = hud.player.scan_ready_ratio if hud and hud.player else 1.0
			if ratio < 1.0:
				_surface.draw_arc(c, r - 3.0, -PI * 0.5, -PI * 0.5 + TAU * ratio, 64, Color(ENERGY, 0.9 * a), 4.0, true)
		USE:
			_surface.draw_circle(c + Vector2(0, -r * 0.18), r * 0.12, ink)
			_surface.draw_arc(c + Vector2(0, -r * 0.18), r * 0.26, 0.0, TAU, 32, ink, 2.5, true)
		PAUSE:
			var h := r * 0.42
			_surface.draw_rect(Rect2(c + Vector2(-r * 0.24, -h * 0.5), Vector2(r * 0.15, h)), ink)
			_surface.draw_rect(Rect2(c + Vector2(r * 0.09, -h * 0.5), Vector2(r * 0.15, h)), ink)
		JOURNAL:
			var w := r * 0.5
			var h2 := r * 0.4
			_surface.draw_rect(Rect2(c - Vector2(w, h2) * 0.5, Vector2(w, h2)), ink, false, 2.5)
			_surface.draw_line(c + Vector2(0, -h2 * 0.5), c + Vector2(0, h2 * 0.5), ink, 2.5)
	var caption: String = CAPTIONS[id]
	if caption != "" and _font:
		var size := int(r * 0.30)
		var text_w := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		_surface.draw_string(_font, c + Vector2(-text_w * 0.5, r * 0.52), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)


func _chevron(c: Vector2, s: float, color: Color) -> void:
	_surface.draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.55), c + Vector2(0, -s * 0.45), c + Vector2(s, s * 0.55)]), color, 3.0, true)
