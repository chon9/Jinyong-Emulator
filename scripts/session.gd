extends Node
## 主機權威 RPC：不接受客戶端數值、獎勵或角色存檔。
signal updated
signal message(channel: String, text: String)
const Rules = preload("res://scripts/world.gd")
const SAVE := "user://youxia_save.json"
const PORT := 24780
const PROTOCOL := 7
var world = Rules.new()
var state: Dictionary = {}
var mode := "單機"
var status := "單機江湖"
var local_character: Dictionary = {}
var connected := false
var joining_at := 0
var limits: Dictionary = {}
var stable_ids: Dictionary = {}
var guest_saves: Dictionary = {}
var local_id := ""
var save_path := SAVE
var local_tick := 0
var chapter_data: Dictionary = {}
signal chapter_imported
var saved_clock := false
var save_import_callback: JavaScriptObject
var save_export_callback: JavaScriptObject
var reset_generation := ""
var story_migration_notice := ""
var save_revision := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--test-profile="):
			var profile := arg.trim_prefix("--test-profile=").validate_filename()
			save_path = "res://test-results/" + profile + ".json"
	local_id = _installation_id()
	for arg in args:
		if arg.begins_with("--test-profile="): local_id = arg.sha256_text()
	world.event.connect(_world_event)
	multiplayer.connected_to_server.connect(_client_connected)
	multiplayer.connection_failed.connect(func(): _network_failed("連線失敗，已返回單機。"))
	multiplayer.server_disconnected.connect(func(): _network_failed("主機已離線，已返回自己的單機江湖。"))
	multiplayer.peer_disconnected.connect(_peer_left)
	SteamBridge.hosted.connect(_steam_hosted)
	SteamBridge.entered.connect(_steam_entered)
	SteamBridge.failed.connect(func(text: String):
		if mode == "Steam 等待":
			_network_failed(text)
			return
		status = text
		message.emit("系統", text)
		updated.emit())
	SteamBridge.invited.connect(join_steam)
	if OS.has_feature("web"):
		var marker: Variant=JavaScriptBridge.eval("(()=>{try{return localStorage.getItem('youxia-reset-generation-v1')||'';}catch{return '';}})()",true)
		if marker is String:reset_generation=marker
	_load()
	migrate_story()
	start_offline()
	if OS.has_feature("web"):
		save_import_callback = JavaScriptBridge.create_callback(_browser_import)
		JavaScriptBridge.get_interface("window").youxiaImportSave = save_import_callback
		save_export_callback = JavaScriptBridge.create_callback(func(_args: Array): export_save())
		JavaScriptBridge.get_interface("window").youxiaExportSave = save_export_callback
		get_tree().root.focus_exited.connect(func(): save_game())
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()

func _installation_id() -> String:
	var path := "user://youxia_identity.cfg"
	var cfg := ConfigFile.new()
	cfg.load(path)
	var value: String = cfg.get_value("identity", "id", "")
	if value == "":
		value = Crypto.new().generate_random_bytes(16).hex_encode()
		cfg.set_value("identity", "id", value)
		cfg.save(path)
	return value

func _load() -> void:
	var newest: Dictionary={}
	for path in [save_path, save_path + ".bak"]:
		var data := _read_save(path)
		if data.is_empty(): continue
		newest=data
		if path.ends_with(".bak"): message.emit.call_deferred("系統", "主存檔損壞，已從上一份備份恢復。")
		break
	# IDBFS commits asynchronously. A small synchronous checkpoint closes the gap
	# when a player reloads immediately after a choice or quest reward.
	if OS.has_feature("web"):
		var quick: Variant=JavaScriptBridge.eval("(()=>{try{return localStorage.getItem('youxia-fast-save-v1')||'';}catch{return '';}})()",true)
		if quick is String:
			var data:=_decode_save(quick)
			if not data.is_empty() and int(data.get("save_revision",0))>int(newest.get("save_revision",-1)):newest=data
	if newest.is_empty():return
	save_revision=int(newest.get("save_revision",0))
	local_character=newest.character
	chapter_data=newest.get("chapter",{}) if newest.get("chapter",{}) is Dictionary else {}
	local_tick=maxi(0,int(newest.get("world_tick",0)))
	saved_clock=newest.has("world_tick")
	guest_saves=newest.get("guests",{})

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	return _decode_save(FileAccess.get_file_as_string(path))

func _decode_save(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK: return {}
	var data: Variant = parser.data
	if not data is Dictionary or int(data.get("version", 0)) != 1 or not data.get("character") is Dictionary: return {}
	# A synchronous reset marker prevents an older IndexedDB snapshot from reappearing
	# if the tab reloads before the engine's asynchronous filesystem sync completes.
	if OS.has_feature("web") and reset_generation!="" and data.get("reset_generation","")!=reset_generation:return {}
	return data

func _restore(id: int, data: Dictionary) -> void:
	var p: Dictionary = world.add_player(id)
	# 存檔來自本機；只還原預設模型內的欄位，不載入戰鬥和掛機。
	for key in p:
		if data.has(key) and typeof(data[key]) == typeof(p[key]): p[key] = data[key]
	# JSON 整數讀回為 float，數值欄位需明確轉回 int。
	for key in p:
		if p[key] is int and data.get(key) is float: p[key] = int(data[key])
	p.enemy = {}
	p.party = 0
	p.follow = false
	p.fight = 0
	p.pk_enabled = false
	p.auto = "停止"
	p.travel_target = ""
	p.travel_route = []
	p.study_ticks = 0
	p.quest_restore = {}
	p.dungeon = 0
	p.life_work = {}
	p.life_hunt = {}
	p.cooldown = -1
	p.session_kills = 0
	p.session_silver = 0
	Rules.normalize_martial(p)
	p.rules_version = int(data.get("rules_version", 0))
	if not data.has("combat_xp"): p.combat_xp = int(p.exp) + 35 * int(p.level) * (int(p.level) - 1)
	Rules.Training.normalize(p)
	if not saved_clock:
		for quest in p.learning_quests.values(): quest.started = mini(int(quest.get("started", world.tick)), world.tick)
	if not preload("res://scripts/content.gd").PLACES.has(p.place): p.place = "揚州城"

func save_game() -> bool:
	if mode.ends_with("客戶端"): return false
	if world.players.has(1): local_character = world.players[1].duplicate(true)
	local_tick = world.tick
	for id in stable_ids:
		if world.players.has(id): guest_saves[stable_ids[id]] = world.players[id].duplicate(true)
	var temp := save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null: return false
	var payload: String=JSON.stringify({"version":1,"character":local_character,"guests":guest_saves,"world_tick":local_tick,"chapter":chapter_data,"reset_generation":reset_generation,"save_revision":save_revision+1})
	file.store_string(payload)
	file.close()
	# Windows 上以 replace 的方式寫入：保留前一份存檔以利恢復。
	if not _read_save(save_path).is_empty():
		var backup_error := DirAccess.copy_absolute(save_path, save_path + ".bak")
		if backup_error != OK: return false
	var replaced: bool=DirAccess.rename_absolute(temp, save_path)==OK
	if replaced:
		save_revision+=1
		if OS.has_feature("web"):
			JavaScriptBridge.eval("(()=>{try{localStorage.setItem('youxia-fast-save-v1',"+JSON.stringify(payload)+");}catch{}})()",true)
			JavaScriptBridge.force_fs_sync()
	return replaced

# The narrative rewrite deliberately starts a fresh campaign. Keep the complete
# previous save in a separate, content-addressed file before changing any state.
func migrate_story(original_text: String="") -> bool:
	story_migration_notice=""
	if chapter_data.is_empty():return false
	var old_world: Variant=chapter_data.get("open_world",{})
	if old_world is Dictionary and old_world.get("story_edition",0)==3:return false
	var payload: String=original_text if original_text!="" else JSON.stringify({"version":1,"character":local_character,"guests":guest_saves,"world_tick":local_tick,"chapter":chapter_data,"reset_generation":reset_generation})
	var path: String=save_path+".before-story-3-"+payload.sha256_text().substr(0,16)+".json"
	if not FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file==null:
			story_migration_notice="舊檔無法備份，已保留原進度。請先匯出存檔，再重新開始。"
			return false
		file.store_string(payload)
		file.flush()
		var error: Error=file.get_error()
		file.close()
		if error!=OK:
			story_migration_notice="舊檔備份未完成，已保留原進度。"
			return false
	if FileAccess.get_file_as_string(path)!=payload:
		story_migration_notice="舊檔備份驗證失敗，已保留原進度。"
		return false
	if OS.has_feature("web"):JavaScriptBridge.force_fs_sync()
	chapter_data={}
	story_migration_notice="故事已重寫，從牛家村重新出發。舊進度已完整備份，可在選項匯出。"
	return true

func story_backups() -> Array[String]:
	var result: Array[String]=[]
	var directory:=DirAccess.open(save_path.get_base_dir())
	if directory==null:return result
	var prefix: String=save_path.get_file()+".before-story-3-"
	for filename in directory.get_files():
		if filename.begins_with(prefix) and filename.ends_with(".json"):
			result.append(save_path.get_base_dir().path_join(filename))
	result.sort_custom(func(a,b):return FileAccess.get_modified_time(a)>FileAccess.get_modified_time(b))
	return result

func export_story_backup() -> void:
	var backups:=story_backups()
	if backups.is_empty():return
	if OS.has_feature("web"):
		JavaScriptBridge.get_interface("window").youxiaDownloadSave(FileAccess.get_file_as_string(backups[0]))
	else:
		message.emit("系統","重寫前完整存檔："+ProjectSettings.globalize_path(backups[0]))
		OS.shell_open(ProjectSettings.globalize_path(backups[0].get_base_dir()))

func _disconnect() -> void:
	if not mode.ends_with("客戶端") and world.players.has(1): save_game()
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	SteamBridge.leave()
	connected = false
	joining_at = 0
	stable_ids.clear()
	limits.clear()
	world.players.clear()
	world.social.reset()
	world.dungeons.reset()
	state = {}

func reset_local_progress() -> bool:
	if mode!="單機":
		status="請先返回單機，再刪除本機存檔。"
		return false
	if OS.has_feature("web"):
		var generation: String=Crypto.new().generate_random_bytes(16).hex_encode()
		var marked: Variant=JavaScriptBridge.eval("(()=>{try{localStorage.setItem('youxia-reset-generation-v1',"+JSON.stringify(generation)+");localStorage.removeItem('youxia-fast-save-v1');return true;}catch{return false;}})()",true)
		# The Web bridge can marshal JavaScript booleans as integer 0/1.
		if not bool(marked):
			status="瀏覽器未允許儲存刪檔標記，進度已保留。"
			return false
		reset_generation=generation
	# Remove recovery files too; otherwise a later load can resurrect deleted progress.
	for path in [save_path,save_path+".bak",save_path+".tmp"]+story_backups():
		if not FileAccess.file_exists(path):continue
		if OS.has_feature("web"):
			# FileAccess also marks IDBFS dirty. DirAccess deletion alone can miss
			# the browser's next persistence pass while a prior sync is in flight.
			var cleared:=FileAccess.open(path,FileAccess.WRITE)
			if cleared==null:
				status="無法清除本機存檔，請檢查瀏覽器儲存空間。"
				return false
			cleared.close()
		elif DirAccess.remove_absolute(path)!=OK:
			status="無法清除本機存檔，請檢查檔案權限。"
			return false
	chapter_data={}
	local_character={}
	local_tick=0
	saved_clock=false
	world.players.clear()
	world.social.reset()
	world.dungeons.reset()
	world.tick=0
	world.add_player(1)
	local_character=world.players[1].duplicate(true)
	_publish()
	chapter_imported.emit()
	save_game()
	if OS.has_feature("web"):JavaScriptBridge.force_fs_sync()
	return true

func start_offline() -> void:
	_disconnect()
	world.tick = local_tick
	mode = "單機"
	status = "單機江湖 · 自動存檔"
	_restore(1, local_character)
	connected = true
	_publish()

func host_lan() -> void:
	if OS.has_feature("web"):
		message.emit("系統", "瀏覽器請使用 WebSocket 聯機，無法建立 UDP 區網房間。")
		return
	_disconnect()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, 7)
	if error != OK:
		start_offline()
		status = "開房失敗：" + error_string(error)
		updated.emit()
		return
	multiplayer.multiplayer_peer = peer
	mode = "區網主機"
	status = "區網主機 · UDP %d" % PORT
	_restore(1, local_character)
	connected = true
	_publish()

func join_lan(address: String) -> void:
	if OS.has_feature("web"):
		message.emit("系統", "瀏覽器請使用 WebSocket 聯機網址。")
		return
	_disconnect()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), PORT)
	if error != OK:
		start_offline()
		status = "連線失敗：" + error_string(error)
		updated.emit()
		return
	multiplayer.multiplayer_peer = peer
	mode = "區網客戶端"
	status = "正在連線 " + address
	joining_at = Time.get_ticks_msec()
	updated.emit()

func host_websocket(port: int = 24781, bind_address: String = "*") -> Error:
	if OS.has_feature("web"): return ERR_UNAVAILABLE
	_disconnect()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port, bind_address)
	if error != OK:
		_network_failed("WebSocket 開房失敗：" + error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	mode = "WebSocket 主機"
	status = "WebSocket 主機 · TCP %d" % port
	_restore(1, local_character)
	connected = true
	_publish()
	return OK

func join_websocket(url: String) -> void:
	url = url.strip_edges()
	if not url.begins_with("wss://") and not url.begins_with("ws://"):
		message.emit("系統", "請輸入 ws:// 或 wss:// 開頭的房主網址。")
		return
	if OS.has_feature("web") and JavaScriptBridge.get_interface("window").location.protocol == "https:" and not url.begins_with("wss://"):
		message.emit("系統", "此頁使用 HTTPS，請連接 wss:// 加密房主網址。")
		return
	_disconnect()
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client(url)
	if error != OK:
		_network_failed("WebSocket 連線失敗：" + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	mode = "WebSocket 客戶端"
	status = "正在連線 WebSocket 房主"
	joining_at = Time.get_ticks_msec()
	updated.emit()

func export_save() -> void:
	if mode.ends_with("客戶端"):
		message.emit("系統", "聯機角色由房主保存；返回單機後可匯出自己的角色。")
		return
	if not save_game():
		message.emit("系統", "存檔失敗，請稍後重試。")
		return
	if OS.has_feature("web"):
		var payload := JSON.stringify({"version": 1, "character": local_character, "world_tick": local_tick, "chapter": chapter_data})
		JavaScriptBridge.get_interface("window").youxiaDownloadSave(payload)
	else: message.emit("系統", "存檔位置：" + ProjectSettings.globalize_path(save_path))

func import_save_text(text: String) -> bool:
	if mode != "單機":
		message.emit("系統", "請先返回單機，再匯入角色存檔。")
		return false
	if text.length() > 2 * 1024 * 1024: return false
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or data.get("version") != 1 or not data.get("character") is Dictionary:
		message.emit("系統", "這不是相容的網金游俠存檔。")
		return false
	var character: Dictionary = data.character
	if data.has("chapter") and not preload("res://scripts/journey/chapter.gd").valid_save(data.chapter): return false
	var clock: Variant = data.get("world_tick", 0)
	if not (clock is int or clock is float) or not is_finite(float(clock)) or float(clock) < 0 or float(clock) > 1000000000000: return false
	# Reject malformed containers before trusted local-save migration touches nested fields.
	var defaults := Rules.new().add_player(1)
	for field in character:
		if defaults.has(field) and defaults[field] is Dictionary and not character[field] is Dictionary: return false
		if defaults.has(field) and (defaults[field] is int or defaults[field] is float):
			var value: Variant = character[field]
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 1000000000000: return false
	for field in ["skills", "skill_xp", "inventory", "life_levels", "life_prof", "attrs"]:
		for value in character.get(field, {}).values():
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or float(value) > 1000000000000: return false
	save_game()  # Preserve the previous character in the regular backup.
	local_character = character
	chapter_data = data.get("chapter", {})
	local_tick = maxi(0, int(data.get("world_tick", 0)))
	migrate_story(text)
	saved_clock = data.has("world_tick")
	world.tick = local_tick
	_restore(1, character)
	save_game()
	_publish()
	chapter_imported.emit()
	message.emit("系統", "已匯入角色存檔；未完成的戰鬥、行程及掛機已停止。")
	return true

func _browser_import(args: Array) -> void:
	if args.size() == 1 and not import_save_text(str(args[0])): message.emit("系統", "存檔內容不相容，未替換目前角色。")

func host_steam() -> void:
	if not SteamBridge.ready_for_network():
		message.emit("系統", SteamBridge.status)
		return
	_disconnect()
	mode = "Steam 等待"
	status = "正在建立 Steam 大廳…"
	SteamBridge.host()
	updated.emit()

func join_steam(id: int) -> void:
	if not SteamBridge.ready_for_network():
		message.emit("系統", SteamBridge.status)
		return
	_disconnect()
	mode = "Steam 等待"
	status = "正在加入 Steam 大廳…"
	SteamBridge.join(id)
	updated.emit()

func _steam_hosted(id: int) -> void:
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	var error: int = peer.call("create_host", 0)
	if error != OK:
		_network_failed("Steam 開房失敗：" + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	mode = "Steam 主機"
	status = "Steam 大廳 %d" % id
	_restore(1, local_character)
	connected = true
	_publish()

func _steam_entered(id: int, owner: int) -> void:
	var peer := ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
	var error: int = peer.call("create_client", owner, 0)
	if error != OK:
		_network_failed("Steam 連線失敗：" + error_string(error))
		return
	multiplayer.multiplayer_peer = peer
	mode = "Steam 客戶端"
	status = "Steam 大廳 %d · 正在連線" % id
	joining_at = Time.get_ticks_msec()
	updated.emit()

func _client_connected() -> void:
	_register.rpc_id(1, str(local_character.get("name", "遠來少俠")), local_id, PROTOCOL)
	status = mode + " · 已連線"
	updated.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register(title: String, token: String, protocol: int = 0) -> void:
	if not multiplayer.is_server(): return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or world.players.has(id): return
	if protocol != PROTOCOL:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	if world.players.size() >= 8:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# Steam 使用傳輸層驗證的 SteamID。區網以本機安裝代碼識別，適用信任的朋友。
	var identity := "lan_" + token.left(64)
	if mode == "Steam 主機":
		var steam_id: int = multiplayer.multiplayer_peer.call("get_steam_id_for_peer_id", id)
		if steam_id <= 0: return
		identity = "steam_" + str(steam_id)
	if identity in stable_ids.values(): return
	stable_ids[id] = identity
	if guest_saves.has(identity):
		_restore(id, guest_saves[identity])
	else:
		world.add_player(id, title)
	_broadcast("系統", "%s踏入了江湖。" % world.players[id].name)
	_publish()

func send(command: String, arg: String = "") -> void:
	if not connected: return
	if multiplayer.is_server():
		_handle(1, command, arg)
	else:
		_intent.rpc_id(1, command.left(20), arg.left(240))

@rpc("any_peer", "call_remote", "reliable")
func _intent(command: String, arg: String) -> void:
	if not multiplayer.is_server() or command.length() > 20 or arg.length() > 240: return
	var id := multiplayer.get_remote_sender_id()
	if not world.players.has(id): return
	var now := Time.get_ticks_msec()
	var limit: Dictionary = limits.get(id, {"start": now, "count": 0})
	if now - int(limit.start) >= 1000: limit = {"start": now, "count": 0}
	limit.count += 1
	limits[id] = limit
	if limit.count > 8: return
	_handle(id, command, arg)

func _handle(id: int, command: String, arg: String) -> void:
	if command == "說":
		var text := arg.strip_edges().replace("\n", " ").replace("\r", " ").left(240)
		if text != "": _broadcast("世界", "%s：%s" % [world.players[id].name, text])
	else:
		world.act(id, command, arg)
	_publish()

func _tick() -> void:
	if joining_at > 0 and Time.get_ticks_msec() - joining_at > 15000:
		_network_failed("連線主機逾時，已返回單機。")
	if not connected or not multiplayer.is_server(): return
	world.step()
	_publish()
	if world.tick % 30 == 0 and not save_game(): message.emit("系統", "存檔失敗，請檢查磁碟空間或權限。")

func _publish() -> void:
	for id in world.players:
		var snapshot: Dictionary = world.snapshot(id)
		if id == 1:
			_snapshot(snapshot)
		elif id in multiplayer.get_peers():
			_snapshot.rpc_id(id, snapshot)

@rpc("authority", "call_remote", "reliable")
func _snapshot(value: Dictionary) -> void:
	state = value
	connected = true
	joining_at = 0
	updated.emit()

func _world_event(id: int, channel: String, text: String) -> void:
	if id == 1: message.emit(channel, text)
	elif id in multiplayer.get_peers(): _notice.rpc_id(id, channel, text)

@rpc("authority", "call_remote", "reliable")
func _notice(channel: String, text: String) -> void:
	message.emit(channel, text)

func _broadcast(channel: String, text: String) -> void:
	message.emit(channel, text)
	if mode != "單機": _notice.rpc(channel, text)

func _peer_left(id: int) -> void:
	if not multiplayer.is_server(): return
	if world.players.has(id):
		world.social.disconnect_peer(id)
		if stable_ids.has(id): guest_saves[stable_ids[id]] = world.players[id].duplicate(true)
		_broadcast("系統", "%s暫別江湖。" % world.players[id].name)
	world.players.erase(id)
	stable_ids.erase(id)
	limits.erase(id)
	save_game()
	_publish()

func _network_failed(text: String) -> void:
	start_offline()
	status = text
	message.emit("系統", text)
	updated.emit()

func _exit_tree() -> void:
	save_game()
	if multiplayer.multiplayer_peer: multiplayer.multiplayer_peer.close()
