@tool
class_name RoguePlayerTest
extends Node

func test_scene_contract_and_model() -> void:
	var player: Node = load("res://scenes/player/Player.tscn").instantiate()
	assert(player is PlayerController)
	assert(player.get_node("Inventory") is Inventory)
	assert(player.get_node("VoxelInteractor").get_script() != null)
	var visual: PlayerVisual = player.get_node("PlayerVisual")
	var model: Node = visual.get_node("Body")
	assert(model is RoguePlayerModel)
	assert(not model.has_node("Torso"))
	assert(not model.has_node("LeftArm"))
	assert(model.get_node("PoseRoot/Rogue/Rig_Medium/Skeleton3D").get_bone_count() == 23)
	assert(visual.get_node(visual.held_tool_path).get_parent() is BoneAttachment3D)
	assert(visual.get_node(visual.pistol_path) is Sprite3D)
	assert(is_equal_approx(player.get_node("CollisionShape3D").shape.height, 1.9))
	assert(is_equal_approx(player.get_node("Camera3D").position.y, 1.58))
	assert(player.has_node("Camera3D/FirstPersonHand"))
	assert(player.has_node("Camera3D/FirstPersonPistol"))
	player.free()

func test_clips_match_rogue_rest_and_tracks() -> void:
	var model: Node = load("res://assets/player/RogueModel.tscn").instantiate()
	var sk: Skeleton3D = model.get_node("PoseRoot/Rogue/Rig_Medium/Skeleton3D")
	for file: String in ["General", "MovementBasic"]:
		var rig: Node = load("res://assets/KayKit_Adventurers_2.0_FREE/Animations/gltf/Rig_Medium/Rig_Medium_" + file + ".glb").instantiate()
		var other: Skeleton3D = rig.get_node("Rig_Medium/Skeleton3D")
		for index: int in sk.get_bone_count():
			assert(sk.get_bone_rest(index).is_equal_approx(other.get_bone_rest(other.find_bone(sk.get_bone_name(index)))))
		var ap: AnimationPlayer = rig.get_node("AnimationPlayer")
		for clip_name: String in ["Idle_A", "Walking_A", "Jump_Idle"]:
			if not ap.has_animation(clip_name): continue
			var clip: Animation = ap.get_animation(clip_name)
			for track_index: int in clip.get_track_count():
				var path: NodePath = clip.track_get_path(track_index)
				assert(path.get_concatenated_names() == "Rig_Medium/Skeleton3D")
				assert(sk.find_bone(path.get_concatenated_subnames()) >= 0)
		rig.free()
	var rogue: Node3D = model.get_node("PoseRoot/Rogue")
	var bounds: AABB = AABB()
	var first: bool = true
	for mesh: Node in sk.get_children():
		if not mesh is MeshInstance3D: continue
		bounds = mesh.get_aabb() if first else bounds.merge(mesh.get_aabb())
		first = false
	assert(absf(bounds.size.y * rogue.scale.y - 1.9) < 0.002)
	assert(absf(bounds.position.y * rogue.scale.y + rogue.position.y) < 0.002)
	model.free()

func test_postures_preserve_size_and_bone_lengths() -> void:
	var model: RoguePlayerModel = load("res://assets/player/RogueModel.tscn").instantiate() as RoguePlayerModel
	# Explicit setup also supports runners instantiating the suite outside a tree.
	model.animation_player = model.get_node("AnimationPlayer")
	model.pose_root = model.get_node("PoseRoot")
	model.rogue = model.get_node("PoseRoot/Rogue")
	model.skeleton = model.get_node("PoseRoot/Rogue/Rig_Medium/Skeleton3D")
	add_child(model)
	if model.state == &"": model._ready()
	var sk: Skeleton3D = model.skeleton
	var imported_basis: Basis = model.rogue.basis
	var rests: Array[Transform3D] = []
	for index: int in sk.get_bone_count(): rests.append(sk.get_bone_rest(index))
	for pose: Dictionary in [{}, {"crouching": true}, {"sitting": true}, {"lying": true}, {"rolling": true, "roll_progress": 0.5}, {}]:
		for step: int in 90: model.update_visual(pose, 1.25, 0.0, false)
		var rigid: Transform3D = PlayerVisual.pose_transform(pose, 0.8)
		assert(is_equal_approx(rigid.basis.determinant(), 1.0))
		assert(rigid.basis.is_equal_approx(rigid.basis.orthonormalized()))
		assert(model.rogue.basis.is_equal_approx(imported_basis))
		assert(model.pose_root.scale.is_equal_approx(Vector3.ONE))
		for index: int in sk.get_bone_count():
			assert(sk.get_bone_rest(index).is_equal_approx(rests[index]))
			assert(sk.get_bone_pose_scale(index).is_equal_approx(rests[index].basis.get_scale()))
			if sk.get_bone_name(index) not in ["root", "hips"]:
				assert(sk.get_bone_pose_position(index).is_equal_approx(rests[index].origin))
	for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		assert(is_equal_approx(PlayerVisual.pose_transform({"rolling": true, "roll_progress": progress}, 0.8).basis.determinant(), 1.0))
	for step: int in 90: model.update_visual({"crouching": true}, 1.25, 0.0, false)
	var crouched_feet: Vector3 = model.pose_root.position + model.rogue.basis * model._feet_center()
	var crouched_head: Vector3 = model.pose_root.position + model.rogue.basis * sk.get_bone_global_pose(sk.find_bone("head")).origin
	# Re-sample the exact same idle phase without the procedural overlay.
	model.animation_player.seek(model.animation_player.current_animation_position, true)
	var sampled_feet: Vector3 = model.rogue.basis * model._feet_center()
	var sampled_head: Vector3 = model.rogue.basis * sk.get_bone_global_pose(sk.find_bone("head")).origin
	assert(crouched_feet.distance_to(sampled_feet) < 0.003)
	assert(crouched_head.y < sampled_head.y - 0.2)
	# Crouch overlays the SAME walk clip; its timeline must not restart.
	model.update_visual({}, 1.9, 2.0, false)
	var time_before: float = model.animation_player.current_animation_position
	model.update_visual({"crouching": true}, 1.25, 2.0, false)
	assert(model.state == &"walk")
	assert(model.animation_player.current_animation_position > time_before)
	model.free()
