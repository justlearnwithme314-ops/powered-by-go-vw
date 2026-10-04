class_name PlayerVisual
extends Node3D

## Model-independent inventory/FPS presentation.
## Body is an instanced adapter with optional update_visual(pose, height, speed,
## airborne). Tool paths are configured by the scene; core knows no rig names.
@export var held_tool_path: NodePath
@export var pistol_path: NodePath

const PISTOL_ITEM_ID: String = "core:pistol"
const TOOL_PIXEL_SIZE: float = 0.022
const FIRST_PERSON_TOOL_PIXEL_SIZE: float = 0.032

@onready var body: Node3D = $Body
@onready var held_tool: Sprite3D = get_node_or_null(held_tool_path) as Sprite3D
@onready var pistol: Sprite3D = get_node_or_null(pistol_path) as Sprite3D

var player: CharacterBody3D
var inventory: Inventory
var first_person_tool: Sprite3D
var first_person_hand: MeshInstance3D
var first_person_pistol: Sprite3D
var walk_time: float = 0.0
var last_position: Vector3 = Vector3.ZERO
var held_item_id: String = ""
var network_animation_phase: float = -1.0
var first_person_rig: Node3D
var held_block: MeshInstance3D
var view_block: MeshInstance3D
const SWING_DURATION: float = 0.32

func play_interaction_swing() -> void:
	if player is PlayerController:
		(player as PlayerController).interaction_swing = 1.0

func get_animation_phase() -> float:
	if body.has_method("get_animation_phase"):
		return float(body.call("get_animation_phase"))
	return 0.0

func set_network_animation_phase(phase: float) -> void:
	network_animation_phase = phase


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	if player == null:
		return

	last_position = player.global_position
	inventory = player.get_node_or_null("Inventory") as Inventory

	first_person_tool = player.get_node_or_null("Camera3D/FirstPersonTool") as Sprite3D
	first_person_hand = player.get_node_or_null("Camera3D/FirstPersonHand") as MeshInstance3D
	first_person_pistol = player.get_node_or_null("Camera3D/FirstPersonPistol") as Sprite3D

	if inventory != null:
		if not inventory.changed.is_connected(_on_inventory_changed):
			inventory.changed.connect(_on_inventory_changed)
		_on_inventory_changed()

	body.visible = true
	# Shadow-only keeps the complete local silhouette without camera clipping.
	for node: Node in body.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if player.is_multiplayer_authority() else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	held_block = _block_holder(held_tool.get_parent())
	if not player.is_multiplayer_authority():
		if first_person_tool != null:
			first_person_tool.visible = false
		if first_person_hand != null:
			first_person_hand.visible = false
		if first_person_pistol != null:
			first_person_pistol.visible = false
		return

	# Retain legacy scene nodes for compatibility, but never display or shadow them.
	for node: GeometryInstance3D in [first_person_tool, first_person_hand, first_person_pistol]:
		if node != null:
			node.visible = false
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if body.has_method("create_first_person_rig"):
		first_person_rig = body.call("create_first_person_rig", player.get_node("Camera3D") as Camera3D) as Node3D
		view_block = _block_holder(first_person_rig.get_node("PoseRoot/Rogue/Rig_Medium/Skeleton3D/RightHand"))
		view_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_update_tool_visuals()


func _process(delta: float) -> void:
	if player == null:
		return
	if player is PlayerController:
		var controller: PlayerController = player as PlayerController
		controller.interaction_swing = maxf(0.0, controller.interaction_swing - delta / SWING_DURATION)

	var movement: Vector3 = player.global_position - last_position
	last_position = player.global_position

	var horizontal_speed: float = Vector2(
		movement.x,
		movement.z
	).length() / maxf(delta, 0.001)

	if not player.is_multiplayer_authority():
		# Explicit motion avoids idle/walk flicker and false jumps on slopes.
		horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var walking: bool = horizontal_speed > 0.15

	if walking:
		walk_time += delta * minf(horizontal_speed, 10.0) * 1.8
	else:
		walk_time += delta * 2.0

	_update_pose(horizontal_speed)
	if first_person_rig != null:
		first_person_rig.call("update_first_person", sin((1.0 - (player as PlayerController).interaction_swing) * PI), not held_item_id.is_empty())
	# Third-person items follow the rig socket, never a hard-coded arm offset.



# Only model bones move: the camera is a sibling, never part of this roll.
func _update_pose(horizontal_speed: float = 0.0) -> void:
	if not player is PlayerController:
		return
	var controller: PlayerController = player as PlayerController
	var pose: Dictionary = controller.visual_pose.duplicate()
	pose["look_pitch"] = controller.camera.rotation.x
	pose["holding_item"] = not held_item_id.is_empty()
	pose["swing"] = sin((1.0 - controller.interaction_swing) * PI)
	if not controller.is_multiplayer_authority() and network_animation_phase >= 0.0:
		pose["animation_phase"] = network_animation_phase
		network_animation_phase = -1.0
	body.transform = pose_transform(pose, controller.current_height)
	var airborne: bool = not controller.is_on_floor() if controller.is_multiplayer_authority() else controller.remote_airborne
	if body.has_method("update_visual"):
		body.call("update_visual", pose, controller.current_height, horizontal_speed, airborne)

static func pose_transform(pose: Dictionary, _height: float) -> Transform3D:
	# Rigid presentation only. Imported size stays constant; adapters bend bones.
	if bool(pose.get("rolling", false)):
		var progress: float = clampf(float(pose.get("roll_progress", 0.0)), 0.0, 1.0)
		var roll_basis: Basis = Basis(Vector3.RIGHT, -TAU * progress)
		return Transform3D(roll_basis, Vector3(0.0, 0.75, 0.0) - roll_basis * Vector3(0.0, 0.75, 0.0))
	if bool(pose.get("lying", false)):
		return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.24, 0.7))
	return Transform3D.IDENTITY

func set_held_item(item_id: String) -> void:
	if held_item_id == item_id:
		return
	held_item_id = item_id
	_update_tool_visuals()


func _on_inventory_changed() -> void:
	if inventory == null:
		return
	set_held_item(inventory.get_selected_item_id())


func _update_tool_visuals() -> void:
	var is_pistol: bool = held_item_id == PISTOL_ITEM_ID
	# Pistol uses its own oriented sprites, so keep the generic tool sprites off for it.
	var texture: Texture2D = null if is_pistol else _get_tool_texture(held_item_id)

	var item: Dictionary = GameAPI.content.get_item(held_item_id)
	var block_id: String = str(item.get("place_block", ""))
	var has_handle: bool = "tool" in item.get("tags", [])
	var block_mesh: Mesh = GameAPI.world.get_block_display_mesh(block_id) if not block_id.is_empty() else null
	if held_tool != null:
		_set_socket_item(held_tool, pistol, held_block, texture, block_mesh, is_pistol, has_handle)

	if first_person_tool != null:
		first_person_tool.texture = texture
		first_person_tool.visible = false
		first_person_tool.pixel_size = FIRST_PERSON_TOOL_PIXEL_SIZE

	if pistol != null:
		pistol.visible = is_pistol
	if first_person_pistol != null:
		first_person_pistol.visible = false
	if first_person_rig != null:
		var socket: Node = first_person_rig.get_node("PoseRoot/Rogue/Rig_Medium/Skeleton3D/RightHand")
		_set_socket_item(socket.get_node("HeldTool") as Sprite3D, socket.get_node("Pistol") as Sprite3D, view_block, texture, block_mesh, is_pistol, has_handle)

func _block_holder(socket: Node) -> MeshInstance3D:
	var holder: MeshInstance3D = MeshInstance3D.new()
	holder.name = "HeldBlock"
	holder.scale = Vector3.ONE * 0.32
	holder.position = Vector3(-0.16, 0.0, -0.16)
	socket.add_child(holder)
	if player.is_multiplayer_authority():
		holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	return holder

func _set_socket_item(tool_sprite: Sprite3D, pistol_sprite: Sprite3D, block: MeshInstance3D, texture: Texture2D, block_mesh: Mesh, is_pistol: bool, has_handle: bool) -> void:
	tool_sprite.texture = texture
	tool_sprite.visible = texture != null and block_mesh == null
	tool_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	tool_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if texture != null:
		tool_sprite.pixel_size = 0.45 / maxf(texture.get_width(), texture.get_height())
		# Icon handles lie at bottom-left: put the grip, not image center, in hand.
		tool_sprite.offset = Vector2(texture.get_width() * 0.28, texture.get_height() * 0.28) if has_handle else Vector2.ZERO
	tool_sprite.position = Vector3.ZERO
	pistol_sprite.visible = is_pistol
	pistol_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pistol_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	if block != null:
		block.mesh = block_mesh
		block.visible = block_mesh != null


func _get_tool_texture(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null

	var item: Dictionary = GameAPI.content.get_item(item_id)
	if item.is_empty():
		return null

	var tags_value: Variant = item.get("tags", [])
	if not tags_value is Array:
		return null

	var tags: Array = tags_value

	var icon_path: String = str(item.get("icon", ""))
	if icon_path.is_empty():
		return null

	var resource: Resource = ResourceLoader.load(icon_path)
	if resource is Texture2D:
		return resource as Texture2D

	if FileAccess.file_exists(icon_path):
		var image: Image = Image.load_from_file(icon_path)
		if image != null:
			return ImageTexture.create_from_image(image)

	return null
