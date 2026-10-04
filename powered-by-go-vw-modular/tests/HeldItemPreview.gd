extends Node3D

func _ready() -> void:
	var player: PlayerController = load("res://scenes/player/Player.tscn").instantiate() as PlayerController
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	player.camera.rotation.x = -0.15
	var visual: PlayerVisual = player.get_node("PlayerVisual")
	visual.set_held_item("frontier:wood_pickaxe")
	var remote: PlayerController = load("res://scenes/player/Player.tscn").instantiate() as PlayerController
	remote.name = "2"
	remote.position = Vector3(1.5, 0.0, -3.0)
	remote.rotation.y = PI
	add_child(remote)
	remote.set_physics_process(false)
	(remote.get_node("PlayerVisual") as PlayerVisual).set_held_item("frontier:wood_pickaxe")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://assets/player/held-item-preview.png")
		get_tree().quit()
