extends Node
var bank
var voices: Array[AudioStreamPlayer] = []
var index := 0
var enabled := true
var volume := .65
var history: Array[String]=[]

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://youxia_sfx.cfg") == OK:
		enabled = bool(cfg.get_value("sound","enabled",true))
		volume = clampf(float(cfg.get_value("sound","volume",.65)),0,1)
	for i in 6:
		var player := AudioStreamPlayer.new()
		if OS.has_feature("web"): player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		voices.append(player)

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sound","enabled",enabled)
	cfg.set_value("sound","volume",volume)
	cfg.save("user://youxia_sfx.cfg")

func play(key: String,pitch: float=1.0) -> void:
	if not enabled or volume <= 0 or bank == null or DisplayServer.get_name() == "headless": return
	var stream: AudioStream = bank.get_asset("res://assets/sfx/"+key+".ogg")
	if stream == null: return
	var player := voices[index%voices.size()]
	index += 1
	player.stream = stream
	player.pitch_scale=clampf(pitch,.8,1.2)
	player.volume_db = linear_to_db(volume)-9
	player.play()
	history.append(key)
	if history.size()>32:history.pop_front()
