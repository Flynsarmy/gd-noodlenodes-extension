extends Node

# Godot leaks a sound's playback when the game exits while it is still playing, or
# within a few frames of it stopping, because only the audio thread frees playbacks.
const AUDIO_RELEASE_SECONDS := 0.15
const AUDIO_PLAYER_TYPES: Array[String] = ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]

var _quitting := false


func _ready() -> void:
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func quit() -> void:
	if _quitting:
		return
	_quitting = true
	# Paused scripts cannot restart a sound while the audio thread frees it.
	get_tree().paused = true
	for type in AUDIO_PLAYER_TYPES:
		for player in get_tree().root.find_children("*", type, true, false):
			player.stop()
	await get_tree().create_timer(AUDIO_RELEASE_SECONDS).timeout
	get_tree().quit()
