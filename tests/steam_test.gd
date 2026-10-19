extends SceneTree
var session

func _init() -> void:
	call_deferred("run")

func run() -> void:
	session = root.get_node("Session")
	var bridge = root.get_node("SteamBridge")
	var result := {"extension": Engine.has_singleton("Steam"), "peer_class": ClassDB.can_instantiate("SteamMultiplayerPeer"), "initialized": bridge.available, "status": bridge.status, "host_created": false, "two_account_test": "not_run"}
	if bridge.ready_for_network():
		session.host_steam()
		var waited := 0.0
		while session.mode == "Steam 等待" and waited < 18:
			await create_timer(.2).timeout
			waited += .2
		result.host_created = session.mode == "Steam 主機" and bridge.lobby_id > 0
		result["network_status"] = session.status
		result["lobby_id"] = str(bridge.lobby_id)
		if result.host_created: session.start_offline()
	var file := FileAccess.open("res://test-results/steam.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("STEAM SMOKE: ", JSON.stringify(result))
	quit(0 if result.host_created else 2)
