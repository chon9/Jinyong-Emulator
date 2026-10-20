extends Node
## Client-local soundtrack. Music choices never change world state or network traffic.
signal changed
const TRACKS := {
	"town": {"title": "群俠聚金庸・天涯循歸途", "path": "res://assets/bgm/群俠聚金庸 天涯循歸途.mp3", "gain": -5.3, "start": .55, "end": 196.2},
	"wild": {"title": "江湖路・田野風光", "path": "res://assets/bgm/江湖路 田野風光.mp3", "gain": -3.1, "start": .60, "end": 163.5},
	"battle": {"title": "天涯任我行・刀劍同行", "path": "res://assets/bgm/天涯任我行 刀劍同行.mp3", "gain": -4.6, "start": .57, "end": 150.7},
	"boss": {"title": "石破天驚撼武林", "path": "res://assets/bgm/石破天驚撼武林.mp3", "gain": -3.8, "start": .46, "end": 122.3},
	"dungeon": {"title": "風起雲湧震九州", "path": "res://assets/bgm/風起雲湧震九州.mp3", "gain": -4.4, "start": .55, "end": 102.1}
}
const SILENT := -60.0
var enabled := true
var volume := .5
var override_track := ""
var settings_path := "user://youxia_music.cfg"
var current_track := ""
var audio_available := false
var players: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var fades: Array = [null, null]
var active := 0
var ambient := "town"
var ambient_position := 0.0
var in_battle := false

func _ready() -> void:
	load_settings()
	audio_available = DisplayServer.get_name() != "headless" and not "--no-music" in OS.get_cmdline_user_args()
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "Music")
		AudioServer.set_bus_send(index, "Master")
	for i in 2:
		var player := AudioStreamPlayer.new()
		# Route Web MP3s through the mixer so the Music bus and fades remain audible.
		if OS.has_feature("web"): player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.bus = "Music"
		player.volume_db = SILENT
		add_child(player)
		players.append(player)
	apply_volume()
	Session.updated.connect(sync_state)
	sync_state()

static func context_for(state: Dictionary) -> String:
	if state.is_empty(): return "town"
	var p: Dictionary = state.player
	if int(p.get("fight", 0)) != 0 or not p.get("enemy", {}).is_empty():
		var enemy: Dictionary = p.get("enemy", {})
		if int(enemy.get("level", 0)) >= 25 or "鬼王" in str(enemy.get("name", "")) or "寨主" in str(enemy.get("name", "")): return "boss"
		return "battle"
	var place: String = p.place
	for word in ["洞", "迷宮", "古墓", "黑風寨"]:
		if word in place: return "dungeon"
	return "town" if preload("res://scripts/content.gd").PLACES.get(place, {}).get("safe", true) else "wild"

func sync_state() -> void:
	var next := context_for(Session.state)
	var fighting := next in ["battle", "boss"]
	if fighting and not in_battle:
		ambient_position = players[active].get_playback_position() if audio_available else 0.0
	elif not fighting and next != ambient:
		ambient = next
		ambient_position = 0.0
	var returning := in_battle and not fighting
	in_battle = fighting
	if not fighting: ambient = next
	if override_track != "": next = override_track
	if next != current_track:
		transition(next, ambient_position if returning and override_track == "" else 0.0, .5 if fighting else 1.6)

func stream_for(key: String) -> AudioStream:
	if not TRACKS.has(key): return null
	if not streams.has(key):
		var stream: AudioStream = load(TRACKS[key].path)
		if stream is AudioStreamMP3: stream.loop = false
		streams[key] = stream
	return streams[key]

func transition(key: String, position: float = 0.0, seconds: float = 1.6) -> void:
	if not TRACKS.has(key): return
	current_track = key
	changed.emit()
	if not audio_available: return
	var stream := stream_for(key)
	if stream == null: return
	var old := active
	active = 1 - active
	fade(old, SILENT, seconds, true)
	var player: AudioStreamPlayer = players[active]
	player.stream = stream
	player.volume_db = SILENT
	var start: float = TRACKS[key].start
	if position < start or position > float(TRACKS[key].end) - 2.0: position = start
	player.play(position)
	fade(active, float(TRACKS[key].gain), seconds, false)

func fade(index: int, destination: float, seconds: float, stop: bool) -> void:
	if fades[index] != null and fades[index].is_valid(): fades[index].kill()
	if not players[index].playing: return
	var tween := create_tween()
	tween.tween_property(players[index], "volume_db", destination, maxf(.01, seconds))
	if stop: tween.tween_callback(players[index].stop)
	fades[index] = tween

func _process(_delta: float) -> void:
	if not audio_available or current_track == "": return
	var player: AudioStreamPlayer = players[active]
	if player.playing and player.get_playback_position() >= float(TRACKS[current_track].end) - 2.0:
		transition(current_track, 0.0, 2.0)

func set_enabled(value: bool) -> void:
	enabled = value
	apply_volume()
	save_settings()
	changed.emit()

func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	apply_volume()
	save_settings()
	changed.emit()

func set_override(key: String) -> void:
	if key != "" and not TRACKS.has(key): return
	override_track = key
	save_settings()
	sync_state()

func apply_volume() -> void:
	var index := AudioServer.get_bus_index("Music")
	if index < 0: return
	AudioServer.set_bus_mute(index, not enabled or volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, .0001)))

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK: return
	enabled = bool(config.get_value("music", "enabled", true))
	volume = clampf(float(config.get_value("music", "volume", .5)), 0.0, 1.0)
	override_track = str(config.get_value("music", "track", ""))
	if not TRACKS.has(override_track): override_track = ""

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("music", "enabled", enabled)
	config.set_value("music", "volume", volume)
	config.set_value("music", "track", override_track)
	config.save(settings_path)

func shutdown() -> void:
	set_process(false)
	for tween in fades:
		if tween != null and tween.is_valid(): tween.kill()
	fades = [null, null]
	for player in players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	streams.clear()

func _exit_tree() -> void:
	shutdown()
