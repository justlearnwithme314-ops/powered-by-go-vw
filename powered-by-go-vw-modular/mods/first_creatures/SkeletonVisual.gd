extends Node3D

var model: Node3D
var animation: AnimationPlayer
var skeleton: Skeleton3D
var arm := -1
var _playing := ""
var _attack_base := Quaternion.IDENTITY
var _previous_state := ""

func setup(definition: Dictionary) -> void:
	model = (definition.model as PackedScene).instantiate() as Node3D
	add_child(model)
	model.rotation.y = PI # KayKit characters face +Z; entity movement faces -Z.
	skeleton = _find_skeleton(model)
	animation = _find_animation(model)
	if animation == null:
		animation = AnimationPlayer.new()
		model.add_child(animation)
		animation.root_node = NodePath("..")
	for key in ["movement", "general"]:
		var source := (definition[key] as PackedScene).instantiate()
		var source_animation := _find_animation(source)
		if source_animation != null:
			for library_name in source_animation.get_animation_library_list():
				var original := source_animation.get_animation_library(library_name)
				var library := AnimationLibrary.new()
				for clip_name in original.get_animation_list():
					var clip := original.get_animation(clip_name).duplicate(true) as Animation
					for track in range(clip.get_track_count()):
						var track_path := clip.track_get_path(track)
						if skeleton != null and track_path.get_subname_count() > 0:
							clip.track_set_path(track, NodePath(str(model.get_path_to(skeleton)) + ":" + str(track_path.get_subname(0))))
					if str(clip_name).begins_with("Walking") or str(clip_name).begins_with("Running") or str(clip_name).begins_with("Idle"):
						clip.loop_mode = Animation.LOOP_LINEAR
					library.add_animation(clip_name, clip)
				animation.add_animation_library(key, library)
		source.free()
	if skeleton != null:
		for i in range(skeleton.get_bone_count()):
			var name := skeleton.get_bone_name(i).to_lower()
			if name.contains("upperarm") and (name.contains("right") or name.ends_with("_r") or name.ends_with(".r")):
				arm = i
		# Bone naming varies; use any right arm as a fallback.
		if arm < 0:
			for i in range(skeleton.get_bone_count()):
				var name := skeleton.get_bone_name(i).to_lower()
				if name.contains("arm") and name.contains("right"):
					arm = i

func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _find_animation(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation(child)
		if found != null:
			return found
	return null

func animate(state: String, time: float, hurt: float) -> void:
	var clip := "general/Death_A" if state == "dead" else "general/Hit_A" if hurt > 0 else "movement/Running_A" if state == "chase" else "movement/Walking_A" if state in ["wander", "return"] else "general/Idle_A"
	if (clip != _playing or (not animation.is_playing() and state not in ["windup", "recover", "dead"])) and animation.has_animation(clip):
		animation.play(clip, 0.12)
		animation.advance(0)
		_playing = clip
	# Original procedural wind-up/strike avoids depending on a missing attack pack.
	if skeleton != null and arm >= 0 and state in ["windup", "recover"]:
		if state == "windup" and _previous_state != "windup":
			_attack_base = skeleton.get_bone_pose_rotation(arm)
		animation.pause()
		var angle := -1.8 * clampf(time / 0.4, 0, 1) if state == "windup" else -1.8 + minf(time / 0.18, 1) * 2.6
		skeleton.set_bone_pose_rotation(arm, _attack_base * Quaternion(Vector3.RIGHT, angle))
	model.rotation.z = 0.05 * sin(time * 30) if hurt > 0 else 0
	_previous_state = state
