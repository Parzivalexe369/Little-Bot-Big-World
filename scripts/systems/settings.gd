extends Node
## Player settings persisted separately from the save game, so New Game never touches them.

signal changed

const PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
const QUALITY_NAMES := ["Low", "Medium", "High"]
const TOUCH_MODES := ["Auto", "Always", "Off"]

var master_volume := 0.85
var music_volume := 0.6
var sfx_volume := 0.8
var ambient_volume := 0.75
var mouse_sensitivity := 1.0
var invert_x := false
var invert_y := false
var camera_assist := true
## On-screen touch controls: 0 Auto (shown on touch screens until a keyboard, mouse or
## gamepad is used), 1 Always, 2 Off. touch_size scales the buttons.
var touch_controls := 0
var touch_size := 1.0
var fov := 70.0
var fullscreen := false
var resolution := Vector2i(1600, 900)
var vsync := true
var quality := 1
# Browsers render the 3D view a little below the canvas resolution by default (fill rate).
var render_scale := 0.8 if OS.has_feature("web") else 1.0


func _ready() -> void:
	if OS.has_feature("web"):
		render_scale = _web_render_scale()
		get_tree().root.size_changed.connect(_update_web_ui_scale)
		_update_web_ui_scale.call_deferred()
	load_settings()
	apply_audio()
	# Display changes need a running window; defer one frame.
	apply_display.call_deferred()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		quality = _default_quality()
		return
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	ambient_volume = clampf(cfg.get_value("audio", "ambient", ambient_volume), 0.0, 1.0)
	mouse_sensitivity = clampf(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity), 0.1, 3.0)
	invert_x = bool(cfg.get_value("controls", "invert_x", invert_x))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	camera_assist = bool(cfg.get_value("controls", "camera_assist", camera_assist))
	touch_controls = clampi(int(cfg.get_value("controls", "touch_controls", touch_controls)), 0, 2)
	touch_size = clampf(cfg.get_value("controls", "touch_size", touch_size), 0.7, 1.5)
	fov = clampf(cfg.get_value("video", "fov", fov), 55.0, 95.0)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	var res: Variant = cfg.get_value("video", "resolution", resolution)
	if res is Vector2i:
		resolution = res
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	quality = clampi(int(cfg.get_value("video", "quality", quality)), 0, 2)
	render_scale = clampf(cfg.get_value("video", "render_scale", render_scale), 0.4, 1.0)


## Default 3D resolution in a browser: about 1.4 million pixels (high-density tablet screens
## have three times that), at most 80%; the 2D interface stays at full sharpness. Tablets and
## phones get about 1 million: their GPUs share power and heat with everything else, and a
## Retina iPad is 4-6 million pixels.
func _web_render_scale() -> float:
	var px := DisplayServer.window_get_size()
	var pixels := maxf(float(px.x * px.y), 1.0)
	if DisplayServer.is_touchscreen_available():
		return snappedf(clampf(sqrt(1000000.0 / pixels), 0.4, 0.75), 0.05)
	return snappedf(clampf(sqrt(1400000.0 / pixels), 0.5, 0.8), 0.05)


## The interface is laid out for a 1920 x 1080 screen and scaled to fit. On a tablet held
## upright that leaves text only a few pixels tall, so in browsers the interface is enlarged
## until one layout unit is at least 0.62 CSS pixels (desktop screens and a landscape iPad
## are already there and stay unchanged).
func _update_web_ui_scale() -> void:
	var root := get_tree().root
	var px := Vector2(root.size)
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1920), ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	var fit := minf(px.x / base.x, px.y / base.y)
	var css_per_unit := fit / maxf(DisplayServer.screen_get_scale(), 1.0)
	root.content_scale_factor = clampf(0.62 / maxf(css_per_unit, 0.01), 1.0, 1.8)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ambient", ambient_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_x", invert_x)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "camera_assist", camera_assist)
	cfg.set_value("controls", "touch_controls", touch_controls)
	cfg.set_value("controls", "touch_size", touch_size)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "render_scale", render_scale)
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Could not save settings: %s" % error_string(err))


## Call after changing any value; applies and persists everything.
func commit() -> void:
	apply_audio()
	apply_display()
	save_settings()
	changed.emit()


func apply_audio() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambient", ambient_volume)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	# In a browser the page sizes the canvas (and fullscreen needs a click), so leave it alone.
	if OS.has_feature("web"):
		pass
	elif fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	else:
		if window.mode != Window.MODE_WINDOWED:
			window.mode = Window.MODE_WINDOWED
		var screen_size := DisplayServer.screen_get_size(window.current_screen)
		var size := Vector2i(mini(resolution.x, screen_size.x), mini(resolution.y, screen_size.y))
		if window.size != size:
			window.size = size
			window.position = DisplayServer.screen_get_position(window.current_screen) + (screen_size - size) / 2
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_scale = render_scale
	# The browser (Compatibility) renderer only scales bilinearly.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.99 and not OS.has_feature("web") else Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else (Viewport.MSAA_2X if quality == 1 else Viewport.MSAA_4X)
	# FXAA is a Forward+/Mobile feature; the browser renderer warns if it is touched at all.
	if not OS.has_feature("web"):
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 0 else Viewport.SCREEN_SPACE_AA_DISABLED


## A browser on a touch screen (iPad, tablets, phones) gets the lightest setup: lower 3D
## resolution, thinner grass, and only the robot casts a sun shadow.
func is_touch_web() -> bool:
	return OS.has_feature("web") and DisplayServer.is_touchscreen_available()


## Quality-dependent tuning read by the world (shadows, vegetation density, post effects).
func quality_params() -> Dictionary:
	match quality:
		0:
			return {"shadow_distance": 60.0, "shadow_size": 2048, "ssao": false, "glow": true,
				"grass_density": 0.3 if is_touch_web() else 0.45, "detail_range": 70.0, "fog_volumetric": false, "ssr": false,
				"ssil": false, "ssil_quality": 0, "dof": false, "shadow_filter": 1}
		2:
			return {"shadow_distance": 140.0, "shadow_size": 4096, "ssao": true, "glow": true,
				"grass_density": 1.0, "detail_range": 150.0, "fog_volumetric": true, "ssr": true,
				"ssil": true, "ssil_quality": 2, "dof": true, "shadow_filter": 3}
		_:
			return {"shadow_distance": 100.0, "shadow_size": 4096, "ssao": true, "glow": true,
				"grass_density": 0.75, "detail_range": 110.0, "fog_volumetric": true, "ssr": false,
				"ssil": true, "ssil_quality": 0, "dof": false, "shadow_filter": 2}


func available_resolutions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var screen := Vector2i(3840, 2160)
	if DisplayServer.get_name() != "headless":
		screen = DisplayServer.screen_get_size()
	for r in RESOLUTIONS:
		if r.x <= screen.x and r.y <= screen.y:
			out.append(r)
	if not out.has(resolution):
		out.append(resolution)
	return out


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func _default_quality() -> int:
	if DisplayServer.get_name() == "headless":
		return 1
	if OS.has_feature("web"):
		return 0
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter.contains("intel") or adapter.contains("radeon(tm) graphics"):
		return 0
	return 1
