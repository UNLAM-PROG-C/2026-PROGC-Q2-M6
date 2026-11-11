extends Node
## Plays the game soundtrack from a dedicated concurrent thread.
##
## The main thread only enqueues commands (producer). The audio thread
## (consumer) drains the command queue, decodes the OGG stream and pushes
## the decoded frames into an AudioStreamGenerator buffer that the engine
## mixer reads. The command queue is guarded by a Mutex and a Semaphore
## wakes the thread up while the music is stopped, so it never busy-waits.

const MUSIC_PATH: String = "res://assets/audio/two_left_socks.ogg"
const GENERATOR_BUFFER_SECONDS: float = 0.5
const FILL_INTERVAL_MS: int = 20
const RATE_SCALE: float = 1.0

enum Command { PLAY_MUSIC, STOP_MUSIC, QUIT }

var _thread := Thread.new()
var _mutex := Mutex.new()
var _semaphore := Semaphore.new()
var _commands: Array[Command] = []
var _player: AudioStreamPlayer
var _output: AudioStreamGeneratorPlayback
var _music: AudioStreamPlayback
var _is_playing := false
var _is_running := true


func _ready() -> void:
	_player = _create_generator_player()
	add_child(_player)
	_player.play()
	_output = _player.get_stream_playback()
	_music = _load_music_playback()
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


func _create_generator_player() -> AudioStreamPlayer:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = AudioServer.get_mix_rate()
	generator.buffer_length = GENERATOR_BUFFER_SECONDS
	var player := AudioStreamPlayer.new()
	player.stream = generator
	return player


func _load_music_playback() -> AudioStreamPlayback:
	var stream: AudioStreamOggVorbis = load(MUSIC_PATH)
	stream.loop = true
	return stream.instantiate_playback()


# --- Audio thread -----------------------------------------------------------

func _audio_loop() -> void:
	while _is_running:
		_process_commands()
		if _is_playing:
			_fill_output_buffer()
			OS.delay_msec(FILL_INTERVAL_MS)
		elif _is_running:
			_semaphore.wait()
	_music.stop()


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
			if not _music.is_playing():
				_music.start()
			_is_playing = true
		Command.STOP_MUSIC:
			_music.stop()
			_is_playing = false
		Command.QUIT:
			_is_running = false


func _fill_output_buffer() -> void:
	var frames := _output.get_frames_available()
	if frames <= 0:
		return
	_output.push_buffer(_music.mix_audio(RATE_SCALE, frames))
