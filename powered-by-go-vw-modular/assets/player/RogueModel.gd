class_name RoguePlayerModel
extends Node3D

## KayKit-specific adapter. Source glTF files and materials remain untouched.
const GENERAL: PackedScene = preload("res://assets/KayKit_Adventurers_2.0_FREE/Animations/gltf/Rig_Medium/Rig_Medium_General.glb")
const MOVEMENT: PackedScene = preload("res://assets/KayKit_Adventurers_2.0_FREE/Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb")
static var clips: AnimationLibrary
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var pose_root: Node3D = $PoseRoot
@onready var skeleton: Skeleton3D = $PoseRoot/Rogue/Rig_Medium/Skeleton3D
var state: StringName = &""
var crouch_weight: float = 0.0
var sit_weight: float = 0.0
var tuck_weight: float = 0.0
@onready var rogue: Node3D = $PoseRoot/Rogue

func _ready() -> void:
	if clips == null:
		clips = AnimationLibrary.new()
		_copy_clip(GENERAL, &"Idle_A", &"idle")
		_copy_clip(MOVEMENT, &"Walking_A", &"walk")
		_copy_clip(MOVEMENT, &"Jump_Idle", &"jump")
	animation_player.add_animation_library(&"", clips)
	# Sample first, then bend bones; prevent late mixer overwrites.
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	update_visual({}, 1.9, 0.0, false)

static func _copy_clip(source: PackedScene, original: StringName, target: StringName) -> void:
	var rig: Node = source.instantiate()
	var source_player: AnimationPlayer = rig.get_node("AnimationPlayer") as AnimationPlayer
	var clip: Animation = source_player.get_animation(original).duplicate() as Animation
	clip.loop_mode = Animation.LOOP_LINEAR
	# Identical medium-rig rest transforms; tracks bind by name, not bone index.
	clips.add_animation(target, clip)
	rig.free()

func update_visual(pose: Dictionary, height: float, horizontal_speed: float, airborne: bool) -> void:
	# Actual supplied AnimationPlayers contain no crouch, sit, prone or roll clips.
	var sitting: bool = bool(pose.get("sitting", false))
	var lying: bool = bool(pose.get("lying", false))
	var rolling: bool = bool(pose.get("rolling", false))
	var crouching: bool = bool(pose.get("crouching", false)) and not sitting and not lying and not rolling
	var delta: float = get_process_delta_time()
	if delta <= 0.0: delta = 1.0 / 60.0
	var blend: float = 1.0 - exp(-delta * 14.0)
	# A blocked stand-up retains a crouched skeleton until collider clearance.
	var crouch_target: float = 1.0 if crouching else clampf((1.9 - height) / 0.65, 0.0, 1.0)
	if sitting or lying or rolling: crouch_target = 0.0
	crouch_weight = lerpf(crouch_weight, crouch_target, blend)
	sit_weight = lerpf(sit_weight, 1.0 if sitting else 0.0, blend)
	tuck_weight = lerpf(tuck_weight, 1.0 if rolling else 0.0, blend)
	var next: StringName = &"jump" if airborne and not rolling else (&"walk" if horizontal_speed > 0.15 and not sitting and not lying and not rolling else &"idle")
	if state != next:
		animation_player.play(next, 0.12)
	state = next
	animation_player.speed_scale = clampf(horizontal_speed / 2.0, 0.6, 2.5) if next == &"walk" else 1.0
	animation_player.advance(delta)
	if pose.has("animation_phase"):
		# Periodic phase correction also works for peers joining mid-animation.
		var clip: Animation = animation_player.get_animation(next)
		animation_player.seek(float(pose["animation_phase"]) * clip.length, true)
	pose_root.position = Vector3.ZERO
	# Preserve sampled walk phase while entering/leaving crouch.
	var before: Vector3 = _feet_center()
	for side: String in ["l", "r"]:
		_bend("upperleg." + side, -1.05 * crouch_weight - PI * 0.5 * sit_weight - 1.9 * tuck_weight)
		_bend("lowerleg." + side, 2.0 * crouch_weight - 0.21 * sit_weight + 2.5 * tuck_weight)
		_bend("foot." + side, -0.95 * crouch_weight + (PI * 0.5 + 0.21) * sit_weight - 0.6 * tuck_weight)
	_bend("spine", 0.65 * crouch_weight + 0.8 * tuck_weight)
	_bend("chest", 0.25 * crouch_weight + 0.4 * tuck_weight)
	_bend("head", -0.7 * crouch_weight - 0.7 * tuck_weight)
	if not lying and not rolling:
		_bend("head", clampf(-float(pose.get("look_pitch", 0.0)), -0.8, 0.8))
	if bool(pose.get("holding_item", false)) or float(pose.get("swing", 0.0)) > 0.0:
		_bend("upperarm.r", -0.8 - float(pose.get("swing", 0.0)) * 1.1)
		_bend("lowerarm.r", -0.45)
	# Rigid translation lowers hips while keeping foot contact/gait, never scale.
	var after: Vector3 = _feet_center()
	pose_root.position = rogue.basis * ((before - after) * (1.0 - sit_weight))
	if sitting:
		var hips: Vector3 = rogue.transform * skeleton.get_bone_global_pose(skeleton.find_bone("hips")).origin
		pose_root.position.y = lerpf(pose_root.position.y, 0.18 - hips.y, sit_weight)
	if lying:
		pose_root.position = Vector3.ZERO

func get_animation_phase() -> float:
	var length: float = animation_player.current_animation_length
	return fposmod(animation_player.current_animation_position / length, 1.0) if length > 0.0 else 0.0

func create_first_person_rig(camera: Camera3D) -> Node3D:
	var rig: RoguePlayerModel = load("res://assets/player/RogueModel.tscn").instantiate() as RoguePlayerModel
	rig.name = "FirstPersonRig"
	camera.add_child(rig)
	# Use the source character's skinned arm, UVs and materials, not a box hand.
	for node: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if instance.skin == null:
			instance.visible = false
			continue
		var arm_mesh: ArrayMesh = ArrayMesh.new()
		for surface: int in range(instance.mesh.get_surface_count()):
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = PackedInt32Array()
			var stride: int = bones.size() / (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			for triangle: int in range(0, source_indices.size(), 3):
				var keep: bool = true
				for corner: int in range(3):
					var vertex: int = source_indices[triangle + corner]
					var arm_weight: float = 0.0
					for influence: int in range(stride):
						var bind: int = bones[vertex * stride + influence]
						var bone: int = instance.skin.get_bind_bone(bind)
						var bone_name: String = str(instance.skin.get_bind_name(bind))
						if bone_name.is_empty() and bone >= 0:
							bone_name = rig.skeleton.get_bone_name(bone)
						if bone_name in ["upperarm.r", "lowerarm.r", "hand.r", "handslot.r"]:
							arm_weight += weights[vertex * stride + influence]
					if arm_weight < 0.5:
						keep = false
				if keep:
					indices.append_array(source_indices.slice(triangle, triangle + 3))
			if not indices.is_empty():
				arrays[Mesh.ARRAY_INDEX] = indices
				arm_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				arm_mesh.surface_set_material(arm_mesh.get_surface_count() - 1, instance.mesh.surface_get_material(surface))
		instance.visible = arm_mesh.get_surface_count() > 0
		if instance.visible:
			instance.mesh = arm_mesh
	for node: Node in rig.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.scale = Vector3.ONE * 0.65
	return rig

func update_first_person(swing: float, holding: bool) -> void:
	update_visual({"holding_item": holding, "swing": swing}, 1.9, 0.0, false)
	# Align the actual hand socket with the view; shoulder exits below the screen.
	var hand: Vector3 = (pose_root.transform * rogue.transform * skeleton.get_bone_global_pose(skeleton.find_bone("handslot.r"))).origin
	var shoulder: Vector3 = (pose_root.transform * rogue.transform * skeleton.get_bone_global_pose(skeleton.find_bone("upperarm.r"))).origin
	# Keep the shoulder outside the view, with the wrist and tool in front.
	basis = Basis(Quaternion((shoulder - hand).normalized(), Vector3(0.8, -1.2, 0.4).normalized())).scaled(Vector3.ONE * 0.65)
	position = Vector3(0.30 - swing * 0.12, -0.25 + swing * 0.08, -0.72 - swing * 0.12) - basis * hand

func _bend(bone_name: String, angle: float) -> void:
	var index: int = skeleton.find_bone(bone_name)
	# Godot 4 poses include rest; compose with the sampled compatible clip.
	var sampled: Quaternion = skeleton.get_bone_pose_rotation(index)
	skeleton.set_bone_pose_rotation(index, Quaternion(Vector3.RIGHT, angle) * sampled)

func _feet_center() -> Vector3:
	var left: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("foot.l")).origin
	var right: Vector3 = skeleton.get_bone_global_pose(skeleton.find_bone("foot.r")).origin
	return (left + right) * 0.5
