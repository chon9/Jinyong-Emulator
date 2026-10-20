extends SceneTree
## Optional native host for the exact same browser game rules and RPC protocol.
func _init() -> void: call_deferred("run")

func run() -> void:
	var port := 24781
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--web-port="): port = arg.trim_prefix("--web-port=").to_int()
	if port < 1024 or port > 65535:
		push_error("WebSocket port must be 1024–65535")
		quit(1)
		return
	var session = root.get_node("Session")
	if session.host_websocket(port) != OK:
		quit(1)
		return
	print("Youxia WebSocket host ready on TCP ", port, ". Use a WSS reverse proxy for HTTPS browser clients.")
