extends SceneTree
var failures: Array = []
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description); push_error(description)

func run() -> void:
	var music = root.get_node("Bgm")
	music.settings_path = "res://test-results/music-settings.cfg"
	for key in music.TRACKS:
		var stream: AudioStream = music.stream_for(key)
		check(stream is AudioStreamMP3 and stream.get_length() > 100.0, "Playable MP3: " + key)
	var state := {"player": {"place": "揚州城", "fight": 0, "enemy": {}}}
	check(music.context_for(state) == "town", "Town soundtrack selection")
	state.player.place = "城郊荒野"
	check(music.context_for(state) == "wild", "Wilderness soundtrack selection")
	state.player.place = "黑風寨"
	check(music.context_for(state) == "dungeon", "Dungeon soundtrack selection")
	state.player.enemy = {"name": "野犬", "level": 1}
	check(music.context_for(state) == "battle", "Encounter soundtrack selection")
	state.player.enemy = {"name": "黑風寨主", "level": 32}
	check(music.context_for(state) == "boss", "Boss soundtrack selection")
	state.player.enemy = {}
	state.player.fight = 1
	check(music.context_for(state) == "battle", "Duel and PK soundtrack selection")
	music.set_volume(.27)
	music.set_enabled(false)
	music.set_override("wild")
	music.volume = .9
	music.enabled = true
	music.override_track = ""
	music.load_settings()
	check(is_equal_approx(music.volume, .27) and not music.enabled and music.override_track == "wild", "Music preferences persist")
	music.apply_volume()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Mute controls Music bus")
	music.set_volume(4.0)
	check(music.volume == 1.0, "Volume is clamped")
	music.set_volume(0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Zero volume mutes output")
	# Force the Dummy audio driver through the real two-player playback path.
	music.audio_available = true
	for key in music.TRACKS:
		music.transition(key, 0.0, .01)
		await create_timer(.04).timeout
		check(music.players[music.active].playing, "Audio playback starts: " + key)
	music.set_override("")
	music.sync_state()
	var active: int = music.active
	music.sync_state()
	check(music.active == active, "Unchanged state does not restart music")
	music.set_volume(.5)
	music.set_enabled(true)
	var file := FileAccess.open("res://test-results/bgm.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	print("BGM TEST: ", checks, " checks, ", failures.size(), " failures")
	music.shutdown()
	await create_timer(.1).timeout
	quit(0 if failures.is_empty() else 1)
