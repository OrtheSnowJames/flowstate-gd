## Hides the gameplay-only pieces that come along for the ride when
## ocean1.tscn is instanced here purely for its pool geometry, lighting, grass
## and bathroom -- none of which the menu background wants: the HUD, the FPS
## counter, a leftover empty debug button, and the water itself. Water in
## particular isn't just hidden for looks -- MenuPlayer's ocean_path override
## (set on the node in this scene file) leaves it with no _ocean reference at
## all, so _water_height() reads 0 everywhere, which is below every floor in
## this pool -- it just walks, the same code path that already governs
## walking the dry concrete deck outside the pool during normal gameplay.
##
## The camera is untouched here too: MenuPlayer's take_over_camera = false
## (also a scene-file override) is what stops it from calling .current on its
## own camera, which leaves this scene's own high aerial Camera3D as the only
## one left claiming the view.
extends Node3D

@onready var _ocean_scene: Node = $ocean_scene

func _ready() -> void:
	for path in ["water base", "gui", "FPSLayer", "TextureButton"]:
		var n := _ocean_scene.get_node_or_null(path)
		if n:
			n.visible = false
