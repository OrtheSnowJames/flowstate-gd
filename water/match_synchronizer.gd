# only send match state to peers whose arena is loaded
extends MultiplayerSynchronizer


func _enter_tree() -> void:
	add_visibility_filter(Net.peer_has_arena)
	public_visibility = true
	Net.arena_peers_changed.connect(update_visibility)


func _exit_tree() -> void:
	Net.arena_peers_changed.disconnect(update_visibility)
