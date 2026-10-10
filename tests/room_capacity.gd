extends Node

var failed := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(15.0).timeout.connect(func() -> void: get_tree().quit(1))
	_expect(Net.MAX_PLAYERS == 20, "room limit is twenty including host")
	_expect(Net.host_game(18092) == OK, "test host starts")
	var clients: Array[ENetMultiplayerPeer] = []
	for slot in range(20):
		var client := ENetMultiplayerPeer.new()
		_expect(client.create_client("127.0.0.1", 18092) == OK, "client starts")
		clients.append(client)
	for tick in range(180):
		for client in clients:
			client.poll()
		await get_tree().physics_frame
	_expect(multiplayer.get_peers().size() == 19, "host only accepts nineteen remote peers")
	_expect(Net.lobby_count() == 20, "roster stops at twenty")
	for client in clients:
		client.close()
	Net.leave_game()
	print("FAIL room capacity" if failed else "PASS room capacity")
	get_tree().quit(1 if failed else 0)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL " + message)
