extends Node
var bank
var voices: Array[AudioStreamPlayer] = []
var index := 0
var enabled := true
var volume := .65
var history: Array[String]=[]
const BUS := "Effects"

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://youxia_sfx.cfg") == OK:
		enabled = bool(cfg.get_value("sound","enabled",true))
		volume = clampf(float(cfg.get_value("sound","volume",.65)),0,1)
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var bus_index := AudioServer.bus_count-1
		AudioServer.set_bus_name(bus_index,BUS)
		AudioServer.set_bus_send(bus_index,"Master")
	for i in 12:
		var player := AudioStreamPlayer.new()
		if OS.has_feature("web"): player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		player.bus = BUS
		player.volume_db = -3
		add_child(player)
		voices.append(player)
	apply_volume()

func audible() -> bool:
	return enabled and volume > 0

func apply_volume() -> void:
	var bus_index := AudioServer.get_bus_index(BUS)
	if bus_index < 0: return
	AudioServer.set_bus_mute(bus_index,not audible())
	AudioServer.set_bus_volume_db(bus_index,linear_to_db(maxf(volume,.0001)))

func set_volume(value: float) -> void:
	volume = clampf(value,0,1)
	apply_volume()
	save()

func toggle() -> void:
	var was_audible := audible()
	enabled = not was_audible
	if enabled and volume <= 0: volume = .65
	apply_volume()
	save()
	if enabled: play("accept")

func preview() -> void:
	if not audible():
		enabled = true
		if volume <= 0: volume = .65
		apply_volume()
		save()
	play("fx_sword_ready")
	await get_tree().create_timer(.28).timeout
	play("fx_sword_hit")

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sound","enabled",enabled)
	cfg.set_value("sound","volume",volume)
	cfg.save("user://youxia_sfx.cfg")

func play(key: String,pitch: float=1.0) -> void:
	if not audible() or bank == null or voices.is_empty() or DisplayServer.get_name() == "headless": return
	var stream: AudioStream = bank.get_asset("res://assets/sfx/"+key+".ogg")
	if stream == null: return
	var player := voices[index%voices.size()]
	# Prefer a free voice so a long dragon/ice cue survives the next actor's turn.
	for candidate in voices:
		if not candidate.playing:
			player = candidate
			break
	index += 1
	player.stream = stream
	player.pitch_scale=clampf(pitch,.8,1.2)
	player.play()
	history.append(key)
	if history.size()>32:history.pop_front()
