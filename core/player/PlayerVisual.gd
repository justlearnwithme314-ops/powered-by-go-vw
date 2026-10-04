extends Node3D

## Simple block-built player model.
##
## The model intentionally uses only rectangular BoxMesh parts so it stays
## lightweight, predictable and easy to customize.

const TOOL_PIXEL_SIZE: float = 0.022
const FIRST_PERSON_TOOL_PIXEL_SIZE: float = 0.032

@onready var body: Node3D = $Body
@onready var head: MeshInstance3D = $Body/Head
@onready var hair: MeshInstance3D = $Body/Hair
@onready var left_eye: MeshInstance3D = $Body/LeftEye
@onready var right_eye: MeshInstance3D = $Body/RightEye
@onready var beard: MeshInstance3D = $Body/Beard
@onready var left_arm: Node3D = $Body/LeftArm
@onready var right_arm: Node3D = $Body/RightArm
@onready var left_leg: Node3D = $Body/LeftLeg
@onready var right_leg: Node3D = $Body/RightLeg
@onready var held_tool: Sprite3D = $Body/RightArm/RightHand/HeldTool
@onready var pistol: Sprite3D = $Body/RightArm/RightHand/Pistol

var player: CharacterBody3D
var inventory: Inventory
var first_person_tool: Sprite3D
var first_person_hand: MeshInstance3D
var first_person_pistol: Sprite3D
var walk_time: float = 0.0
var last_position: Vector3 = Vector3.ZERO
var held_item_id: String = ""
var has_pistol: bool = false


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

	if not player.is_multiplayer_authority():
		if first_person_tool != null:
			first_person_tool.visible = false
		if first_person_hand != null:
			first_person_hand.visible = false
		if first_person_pistol != null:
			first_person_pistol.visible = false
		return

	# A first-person camera should not sit inside the face.
	head.visible = false
	hair.visible = false
	left_eye.visible = false
	right_eye.visible = false
	beard.visible = false

	if first_person_tool != null:
		first_person_tool.visible = true
		first_person_tool.pixel_size = FIRST_PERSON_TOOL_PIXEL_SIZE

	if first_person_hand != null:
		first_person_hand.visible = true

	if first_person_pistol != null:
		first_person_pistol.visible = false

	_update_tool_visuals()


func _process(delta: float) -> void:
	if player == null:
		return

	var movement: Vector3 = player.global_position - last_position
	last_position = player.global_position

	var horizontal_speed: float = Vector2(
		movement.x,
		movement.z
	).length() / maxf(delta, 0.001)

	var walking: bool = horizontal_speed > 0.15

	if walking:
		walk_time += delta * minf(horizontal_speed, 10.0) * 1.8
	else:
		walk_time += delta * 2.0

	var stride: float = 0.0
	if walking:
		stride = sin(walk_time) * 0.55

	if left_leg != null:
		left_leg.rotation.x = stride
	if right_leg != null:
		right_leg.rotation.x = -stride
	if left_arm != null:
		left_arm.rotation.x = -stride * 0.8
	if right_arm != null:
		right_arm.rotation.x = stride * 0.8

	# Small tool bob makes the hand sprite feel attached to a moving arm.
	if held_tool != null and held_tool.visible:
		held_tool.position.y = -0.88 + sin(walk_time * 1.5) * 0.018

	if first_person_tool != null and first_person_tool.visible:
		first_person_tool.position.y = -0.36 + sin(walk_time * 2.0) * 0.012

	if pistol != null and pistol.visible:
		pistol.position.y = -0.07 + sin(walk_time * 1.5) * 0.01

	if first_person_pistol != null and first_person_pistol.visible:
		first_person_pistol.position.y = -0.42 + sin(walk_time * 2.0) * 0.008


func set_held_item(item_id: String) -> void:
	held_item_id = item_id
	_update_tool_visuals()


func _on_inventory_changed() -> void:
	if inventory == null:
		return
	set_held_item(inventory.get_selected_item_id())


func _update_tool_visuals() -> void:
	var texture: Texture2D = _get_tool_texture(held_item_id)
	var show_tool: bool = texture != null

	if held_tool != null:
		held_tool.texture = texture
		held_tool.visible = show_tool and not has_pistol
		held_tool.pixel_size = TOOL_PIXEL_SIZE

	if first_person_tool != null:
		first_person_tool.texture = texture
		first_person_tool.visible = (
			show_tool and not has_pistol
			and player != null
			and player.is_multiplayer_authority()
		)
		first_person_tool.pixel_size = FIRST_PERSON_TOOL_PIXEL_SIZE

	_update_pistol_visuals()


func _update_pistol_visuals() -> void:
	if pistol != null:
		pistol.visible = has_pistol
	if first_person_pistol != null:
		first_person_pistol.visible = has_pistol and player != null and player.is_multiplayer_authority()


func set_pistol(enabled: bool) -> void:
	has_pistol = enabled
	_update_pistol_visuals()
	_update_tool_visuals()


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
	if not ("tool" in tags):
		return null

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