## A physics prop whose simulation lives on the host: the host runs it for real
## and replicates the result out (see the MultiplayerSynchronizer child in the
## scene), and every client freezes its own copy and just shows what arrives.
##
## Without this each client would run its own gravity, buoyancy and collisions
## on the same body and then have the host's transform written over the top of
## it every network tick. The two answers never quite agree, so the prop reads
## as jittering in place or drifting somewhere different in every window.
##
## Authority is left at its default (peer 1, the host) rather than assigned per
## peer the way player bodies are in player.gd -- world props belong to whoever
## is running the world, and the host is the only peer that qualifies.
extends RigidBody3D


func _ready() -> void:
	if is_multiplayer_authority():
		return

	# FREEZE_MODE_KINEMATIC, not STATIC: the body still shoves what it runs into
	# as the replicated transform moves it, so a cube drifting into a swimmer
	# still reads as a collision rather than passing through them.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true

	# Buoyancy applies force to this body every physics tick. On a client that's
	# both wasted work and a second opinion about where the prop should be, so
	# switch it off and let the host's result stand.
	for child in get_children():
		if child is Buoyancy:
			child.set_physics_process(false)


## Knockback from a water move, applied on the host where this prop's physics
## actually run. A client that hits the cube can't shove it directly -- its own
## copy is frozen, and the host's transform would overwrite the result anyway --
## so ocean_fluid_bridge's _knockback routes the push here instead (see its
## _send_to_owner).
@rpc("any_peer", "reliable")
func net_apply_impulse(impulse: Vector3) -> void:
	if is_multiplayer_authority():
		apply_central_impulse(impulse)
