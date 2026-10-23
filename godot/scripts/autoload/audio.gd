extends Node
## Music, voice-over and sound effects. Port of the web AudioManager.
## All file names are relative to res://assets/audio/.

const DIR := "res://assets/audio/"

var muted := false:
	set(v):
		muted = v
		AudioServer.set_bus_mute(0, v)

var _bgm: AudioStreamPlayer
var _bgm_name := ""
var _bgm_volume := 0.5
var _voice: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _loops := {}
var _cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm = AudioStreamPlayer.new()
	add_child(_bgm)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)


func stream(file: String) -> AudioStream:
	if _cache.has(file):
		return _cache[file]
	var path := DIR + file
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_cache[file] = s
	return s


func play_bgm(file: String, volume := 0.5) -> void:
	_bgm_volume = volume
	_bgm.volume_db = linear_to_db(volume)
	if _bgm_name == file and _bgm.playing:
		return
	_bgm_name = file
	var s := stream(file)
	if s == null:
		return
	if s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	_bgm.stream = s
	_bgm.play()


func stop_bgm() -> void:
	_bgm.stop()
	_bgm_name = ""


func set_bgm_volume(volume: float) -> void:
	_bgm_volume = volume
	_bgm.volume_db = linear_to_db(volume)


func play_sfx(file: String, volume := 0.5) -> void:
	var s := stream(file)
	if s == null:
		return
	var p: AudioStreamPlayer = null
	for candidate in _sfx:
		if not candidate.playing:
			p = candidate
			break
	if p == null:
		p = _sfx[0]
	p.stream = s
	p.volume_db = linear_to_db(volume)
	p.play()


func start_loop(file: String, volume := 0.5) -> void:
	if _loops.has(file):
		return
	var s := stream(file)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.stream = s
	p.volume_db = linear_to_db(volume)
	p.finished.connect(p.play)
	p.play()
	_loops[file] = p


func stop_loop(file: String) -> void:
	if _loops.has(file):
		_loops[file].queue_free()
		_loops.erase(file)


func stop_all_loops() -> void:
	for f in _loops.keys():
		stop_loop(f)


func play_voice(file: String, volume := 1.0) -> void:
	if file == "":
		return
	var s := stream(file)
	if s == null:
		return
	_voice.stream = s
	_voice.volume_db = linear_to_db(volume)
	_voice.play()


func stop_voice() -> void:
	_voice.stop()


## STEP-007.wav is corrupt in the original export, so it is skipped.
const STEPS := [1, 2, 3, 4, 5, 6, 8, 9, 10, 11]


func footstep(volume := 0.6) -> void:
	play_sfx("STEP-%03d.wav" % STEPS.pick_random(), volume)


func jump_sound(double_jump: bool) -> void:
	var n := randi_range(7, 9) if double_jump else randi_range(1, 6)
	play_sfx("jumb-%02d.wav" % n, 0.25)


func nut_sound() -> void:
	play_sfx("nut%d.wav" % randi_range(1, 8), 0.6)
