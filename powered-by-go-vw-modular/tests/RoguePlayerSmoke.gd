class_name RoguePlayerSmokeFixture
extends Node3D

const PLAYER: PackedScene = preload("res://scenes/player/Player.tscn")

func _ready() -> void:
	for peer_id: int in [1, 2]:
		var player: PlayerController = PLAYER.instantiate() as PlayerController
		player.name = str(peer_id)
		player.position.x = 20.0 if peer_id == 1 else 0.0
		player.rotation.y = PI
		add_child(player)
		# Static instantiation smoke, not gameplay and not a save session.
		player.set_physics_process(false)
		var visual: PlayerVisual = player.get_node("PlayerVisual")
		visual.set_process(false)
		player.get_node("VoxelInteractor").set_process(false)
		assert(visual.body.visible)
		assert(not visual.first_person_hand.visible)
		assert(visual.first_person_hand.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert((visual.first_person_rig != null) == (peer_id == 1))
		for mesh_node: Node in visual.body.find_children("*", "MeshInstance3D", true, false):
			assert((mesh_node as MeshInstance3D).cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if peer_id == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON))
		if visual.first_person_rig != null:
			var visible_arm_meshes: int = 0
			for mesh_node: Node in visual.first_person_rig.find_children("*", "MeshInstance3D", true, false):
				var mesh: MeshInstance3D = mesh_node as MeshInstance3D
				assert(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				if mesh.visible:
					visible_arm_meshes += 1
			assert(visible_arm_meshes > 0, "Viewmodel must contain source character arm geometry")
		visual.set_held_item("core:pistol")
		assert(visual.pistol.visible)
		assert(not visual.first_person_pistol.visible)
		assert(not visual.held_tool.visible)
		assert(not visual.first_person_tool.visible)
		var camera_before: Transform3D = player.camera.transform
		for pose: Dictionary in [{"sitting": true}, {"lying": true}, {"rolling": true, "roll_progress": 0.5}, {"crouching": true}, {}]:
			player.visual_pose = pose
			visual._update_pose(0.0)
			assert(player.camera.transform == camera_before)
			assert(is_equal_approx(player.collision_shape.shape.height, 1.9))
		visual.set_held_item("")
		assert(not visual.pistol.visible)
		assert(not visual.first_person_pistol.visible)
		visual.set_held_item("core:grass")
		assert(visual.held_block.visible and visual.held_block.mesh != null)
		assert(not visual.held_tool.visible)
		visual.play_interaction_swing()
		assert(player.interaction_swing == 1.0)
		if peer_id == 2:
			visual.set_held_item("core:pistol")
	$Camera3D.make_current()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Rogue smoke PASS: actual rig arm, full-body shadows, shadowless viewmodel, held block mesh, interaction swings, pistol switching, posture hooks")
	if "--validate-only" in OS.get_cmdline_user_args():
		get_tree().quit()
