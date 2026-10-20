extends Node
## Music, ambience and sound effects.
## All sounds are optional: a missing file simply plays nothing, so gameplay never depends on audio.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMBIENT_DIR := "res://assets/audio/ambient/"
const SFX_POOL_SIZE := 14
const SFX_3D_POOL_SIZE := 14
## Minimum seconds between two plays of the same sound, keeps bursts from stacking up loudly.
const MIN_REPEAT_INTERVAL := 0.06
const MAX_SAME_SOUND := 3

var _streams: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx3d_pool: Array[AudioStreamPlayer3D] = []
var _last_play_time: Dictionary = {}
var _music_players: Array[AudioStreamPlayer] = []
var _music_index := 0
var _music_id: StringName = &""
var _music_tween: Tween
var _ambient_layers: Dictionary = {}  # id -> {player, target, current}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)
	for i in SFX_3D_POOL_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = &"SFX"
		p3.unit_size = 6.0
		p3.max_distance = 60.0
		p3.attenuation_filter_cutoff_hz = 9000.0
		add_child(p3)
		_sfx3d_pool.append(p3)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
		_music_players.append(m)


func _process(delta: float) -> void:
	for id: StringName in _ambient_layers:
		var layer: Dictionary = _ambient_layers[id]
		var current: float = layer["current"]
		var target: float = layer["target"]
		if is_equal_approx(current, target):
			continue
		current = move_toward(current, target, delta / maxf(layer["fade"], 0.01))
		layer["current"] = current
		var player: AudioStreamPlayer = layer["player"]
		player.volume_db = linear_to_db(maxf(current, 0.0001)) + float(layer["base_db"])
		if current <= 0.0005 and player.playing:
			player.stop()
		elif current > 0.0005 and not player.playing:
			player.play(_rng.randf() * maxf(player.stream.get_length() - 1.0, 0.0))


# --- Sound effects ------------------------------------------------------------

func has_sound(sound: StringName) -> bool:
	return _get_stream(SFX_DIR, sound) != null


func play_sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0, pitch_jitter: float = 0.04, bus: StringName = &"SFX") -> void:
	var stream := _get_stream(SFX_DIR, sound)
	if stream == null or not _may_play(sound):
		return
	var player := _free_player(_sfx_pool) as AudioStreamPlayer
	player.stream = stream
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.05, pitch + _rng.randf_range(-pitch_jitter, pitch_jitter))
	player.play()


func play_ui(sound: StringName, volume_db: float = 0.0) -> void:
	play_sfx(sound, volume_db, 1.0, 0.02, &"UI")


func play_sfx_3d(sound: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, pitch_jitter: float = 0.05) -> void:
	var stream := _get_stream(SFX_DIR, sound)
	if stream == null or not _may_play(sound):
		return
	var player := _free_player(_sfx3d_pool) as AudioStreamPlayer3D
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = maxf(0.05, pitch + _rng.randf_range(-pitch_jitter, pitch_jitter))
	player.play()


## Looping positional sound owned by a world object (machines, water). Returns null if missing.
func make_loop_3d(parent: Node3D, sound: StringName, volume_db: float = -6.0, unit_size: float = 5.0, max_distance: float = 40.0) -> AudioStreamPlayer3D:
	var stream := _get_stream(AMBIENT_DIR, sound)
	if stream == null:
		return null
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = &"Ambient"
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.autoplay = true
	parent.add_child(player)
	return player


# --- Music --------------------------------------------------------------------

func play_music(track: StringName, fade_time: float = 3.0, volume_db: float = -4.0) -> void:
	if track == _music_id:
		return
	_music_id = track
	var stream := _get_stream(MUSIC_DIR, track)
	var old := _music_players[_music_index]
	_music_index = 1 - _music_index
	var new := _music_players[_music_index]
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(old, "volume_db", -80.0, fade_time).set_trans(Tween.TRANS_SINE)
	_music_tween.chain().tween_callback(old.stop)
	if stream != null:
		new.stream = stream
		new.volume_db = -60.0
		new.play()
		_music_tween.parallel().tween_property(new, "volume_db", volume_db, fade_time).set_trans(Tween.TRANS_SINE)


func stop_music(fade_time: float = 2.0) -> void:
	_music_id = &""
	for player in _music_players:
		var tween := create_tween()
		tween.tween_property(player, "volume_db", -80.0, fade_time)
		tween.tween_callback(player.stop)


func current_music() -> StringName:
	return _music_id


## Briefly lowers the music, e.g. under a discovery chime or a restoration sequence.
func duck_music(amount_db: float = -8.0, duration: float = 2.0) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return
	var base := linear_to_db(maxf(Settings.music_volume, 0.0001))
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v), base, base + amount_db, 0.3)
	tween.tween_interval(duration)
	tween.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v), base + amount_db, base, 1.2)
	tween.tween_callback(Settings.apply_audio)


# --- Ambience -----------------------------------------------------------------

## Sets the target loudness (0..1) of a looping ambience layer, fading smoothly.
func set_ambient(layer_id: StringName, level: float, fade_time: float = 3.0, base_db: float = -6.0) -> void:
	if not _ambient_layers.has(layer_id):
		var stream := _get_stream(AMBIENT_DIR, layer_id)
		if stream == null:
			return
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = &"Ambient"
		player.volume_db = -80.0
		add_child(player)
		_ambient_layers[layer_id] = {"player": player, "target": 0.0, "current": 0.0, "fade": fade_time, "base_db": base_db}
	var layer: Dictionary = _ambient_layers[layer_id]
	layer["target"] = clampf(level, 0.0, 1.0)
	layer["fade"] = fade_time
	layer["base_db"] = base_db


func stop_all_ambient(fade_time: float = 1.5) -> void:
	for id: StringName in _ambient_layers:
		set_ambient(id, 0.0, fade_time, _ambient_layers[id]["base_db"])


# --- Internals ----------------------------------------------------------------

func _get_stream(dir: String, sound: StringName) -> AudioStream:
	var key := dir + String(sound)
	if _streams.has(key):
		return _streams[key]
	var stream: AudioStream = null
	for ext: String in [".ogg", ".wav", ".mp3"]:
		var path := key + ext
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	if stream != null and dir != SFX_DIR:
		_make_looping(stream)
	_streams[key] = stream
	return stream


func _make_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


## Looping stream by name (from the ambient folder), for nodes that own their own player.
func get_loop(sound: StringName) -> AudioStream:
	return _get_stream(AMBIENT_DIR, sound)


func _may_play(sound: StringName) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_play_time.get(sound, -10.0)
	if now - last < MIN_REPEAT_INTERVAL:
		return false
	var same := 0
	for p in _sfx_pool:
		if p.playing and p.stream == _streams.get(SFX_DIR + String(sound)):
			same += 1
	for p3 in _sfx3d_pool:
		if p3.playing and p3.stream == _streams.get(SFX_DIR + String(sound)):
			same += 1
	if same >= MAX_SAME_SOUND:
		return false
	_last_play_time[sound] = now
	return true


func _free_player(pool: Array) -> Node:
	for p: Node in pool:
		if not p.playing:
			return p
	# All busy: steal the one that has played the longest.
	var best: Node = pool[0]
	var best_pos := -1.0
	for p: Node in pool:
		var pos: float = p.get_playback_position()
		if pos > best_pos:
			best_pos = pos
			best = p
	return best
