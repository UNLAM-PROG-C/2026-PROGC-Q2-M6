extends Node
## Plays the game soundtrack from a dedicated concurrent thread.
##
## The main thread only enqueues commands (producer). The audio thread
## (consumer) drains the command queue guarded by a Mutex; a Semaphore wakes
## it up when there is nothing to stream, so it never busy-waits.
##
## Streaming mode (Godot 4.4+): the audio thread decodes the OGG stream with
## AudioStreamPlayback.mix_audio() and pushes the frames into an
## AudioStreamGenerator buffer that the engine mixer reads.
## Fallback mode (Godot < 4.4, no mix_audio()): the audio thread still consumes
## the commands but delegates playback to an AudioStreamPlayer, deferring the
## node calls to the main thread because the scene tree is not thread-safe.

const MUSIC_PATH: String = "res://assets/audio/two_left_socks.ogg"
const GENERATOR_BUFFER_SECONDS: float = 0.5
const FILL_INTERVAL_MS: int = 20
const RATE_SCALE: float = 1.0
const STREAMING_METHOD: StringName = &"mix_audio"

enum Command { PLAY_MUSIC, STOP_MUSIC, QUIT }

var _thread := Thread.new()
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _commands: Array[Command] = []
var _player := AudioStreamPlayer.new()
var _output: AudioStreamGeneratorPlayback
# Untyped on purpose: start()/stop()/mix_audio() do not exist before Godot 4.4,
# so the calls must be resolved at runtime to keep the script parseable there.
var _music
var _is_streaming := false
var _is_playing := false
var _is_running := true


func _ready() -> void:
	var stream := _load_music_stream()
	_is_streaming = ClassDB.class_has_method("AudioStreamPlayback", STREAMING_METHOD)
	if _is_streaming:
		_setup_streaming(stream)
	else:
		_player.stream = stream
		add_child(_player)
	_thread.start(_audio_loop)
	play_music()


func _exit_tree() -> void:
	_enqueue(Command.QUIT)
	if _thread.is_started():
		_thread.wait_to_finish()


func play_music() -> void:
	_enqueue(Command.PLAY_MUSIC)


func stop_music() -> void:
	_enqueue(Command.STOP_MUSIC)


func _enqueue(command: Command) -> void:
	_mutex.lock()
	_commands.append(command)
	_mutex.unlock()
	_semaphore.post()


func _load_music_stream() -> AudioStreamOggVorbis:
	var stream: AudioStreamOggVorbis = load(MUSIC_PATH)
	stream.loop = true
	return stream


func _setup_streaming(stream: AudioStream) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = AudioServer.get_mix_rate()
	generator.buffer_length = GENERATOR_BUFFER_SECONDS
	_player.stream = generator
	add_child(_player)
	_player.play()
	_output = _player.get_stream_playback()
	_music = stream.instantiate_playback()


# --- Audio thread -----------------------------------------------------------

func _audio_loop() -> void:
	while _is_running:
		_process_commands()
		if _is_running and _is_playing and _is_streaming:
			_fill_output_buffer()
			OS.delay_msec(FILL_INTERVAL_MS)
		elif _is_running:
			_semaphore.wait()
	_stop_playback()


func _process_commands() -> void:
	_mutex.lock()
	var pending := _commands.duplicate()
	_commands.clear()
	_mutex.unlock()
	for command in pending:
		_apply_command(command)


func _apply_command(command: Command) -> void:
	match command:
		Command.PLAY_MUSIC:
			if not _is_playing:
				_start_playback()
			_is_playing = true
		Command.STOP_MUSIC:
			_stop_playback()
			_is_playing = false
		Command.QUIT:
			_is_running = false


func _start_playback() -> void:
	if _is_streaming:
		_music.start()
	else:
		_player.call_deferred("play")


func _stop_playback() -> void:
	if _is_streaming:
		_music.stop()
	else:
		_player.call_deferred("stop")


func _fill_output_buffer() -> void:
	var frames := _output.get_frames_available()
	if frames <= 0:
		return
	_output.push_buffer(_music.mix_audio(RATE_SCALE, frames))
