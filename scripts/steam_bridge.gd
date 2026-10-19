extends Node
## 依既有 JY-Mini OL 的 GodotSteam 4.23 API 契約整合。
signal hosted(lobby_id: int)
signal entered(lobby_id: int, owner: int)
signal failed(reason: String)
signal invited(lobby_id: int)
var steam: Object
var available := false
var lobby_id: int = 0
var steam_id: int = 0
var status := "未載入 GodotSteam"
var pending := ""
var pending_at := 0
const TAG := "youxia_text_v2"

func _ready() -> void:
	if "--no-steam" in OS.get_cmdline_user_args():
		status = "Steam 已停用（測試模式）"
		return
	if not Engine.has_singleton("Steam"): return
	steam = Engine.get_singleton("Steam")
	var result: Dictionary = steam.call("steamInitEx", 480, false)
	if int(result.get("status", -1)) != 0:
		status = "Steam 未就緒：" + str(result.get("verbal", "請啟動 Steam"))
		return
	available = true
	steam_id = int(steam.call("getSteamID"))
	status = "Steam · " + str(steam.call("getPersonaName"))
	steam.connect("lobby_created", _created)
	steam.connect("lobby_joined", _joined)
	steam.connect("join_requested", func(id: int, _friend: int): invited.emit(id))
	var args := OS.get_cmdline_args()
	var index := args.find("+connect_lobby")
	if index >= 0 and index + 1 < args.size():
		invited.emit.call_deferred(args[index + 1].to_int())

func _process(_delta: float) -> void:
	if available: steam.call("run_callbacks")
	if pending != "" and Time.get_ticks_msec() - pending_at > 15000:
		pending = ""
		failed.emit("Steam 大廳請求逾時，請重試。")

func ready_for_network() -> bool:
	return available and ClassDB.can_instantiate("SteamMultiplayerPeer")

func host() -> void:
	if not ready_for_network():
		failed.emit(status + "；需要支援 SteamMultiplayerPeer 的 GodotSteam。")
		return
	if pending != "": return
	pending = "host"
	pending_at = Time.get_ticks_msec()
	steam.call("createLobby", 1, 8)

func join(id: int) -> void:
	if not ready_for_network() or id <= 0:
		failed.emit("請確認 Steam 已登入，並輸入有效的大廳編號。")
		return
	if pending != "": return
	pending = "join"
	pending_at = Time.get_ticks_msec()
	steam.call("joinLobby", id)

func _created(result: int, id: int) -> void:
	if pending != "host":
		if result == 1: steam.call("leaveLobby", id)
		return
	if result != 1:
		pending = ""
		failed.emit("Steam 開房失敗（%d）。" % result)
		return
	lobby_id = id
	steam.call("setLobbyData", id, "game", TAG)
	steam.call("setLobbyData", id, "name", "網金游俠 · 純文字江湖")
	steam.call("setLobbyJoinable", id, true)
	pending = ""
	hosted.emit(id)

func _joined(id: int, _permissions: int, _locked: bool, result: int) -> void:
	if result != 1:
		pending = ""
		failed.emit("Steam 加入失敗（%d）。" % result)
		return
	var owner := int(steam.call("getLobbyOwner", id))
	if owner == steam_id: return
	if pending != "join":
		steam.call("leaveLobby", id)
		return
	pending = ""
	if str(steam.call("getLobbyData", id, "game")) != TAG:
		steam.call("leaveLobby", id)
		failed.emit("這不是相容的網金游俠大廳。")
		return
	lobby_id = id
	entered.emit(id, owner)

func invite() -> void:
	if available and lobby_id > 0:
		steam.call("activateGameOverlayInviteDialog", lobby_id)
	else:
		failed.emit("請先建立 Steam 大廳。")

func leave() -> void:
	if available and lobby_id > 0: steam.call("leaveLobby", lobby_id)
	lobby_id = 0
	pending = ""

func _exit_tree() -> void:
	leave()
	if available: steam.call("steamShutdown")
