@tool
class_name AuditFixesTest
extends Node

func track(object: Node) -> Node:
	add_child(object)
	return object

func assert_true(condition: bool, message: String = "Expected true") -> void:
	assert(condition, message)

func assert_false(condition: bool, message: String = "Expected false") -> void:
	assert(not condition, message)

func assert_eq(actual: Variant, expected: Variant) -> void:
	assert(actual == expected, "Expected %s, got %s" % [expected, actual])

func assert_gt(actual: int, expected: int) -> void:
	assert(actual > expected)

func assert_contains(value: Variant, expected: Variant) -> void:
	assert(expected in value)

func suite_name() -> String:
	return "audit_fixes"

func test_capsule_samples_follow_posture() -> void:
	var controller: Script = load("res://core/player/PlayerController.gd") as Script
	for height: float in [0.8, 1.25, 1.9]:
		var samples: Array = controller.call("capsule_samples", height, 0.4)
		assert_gt(samples.size(), 0)
		for point: Vector3 in samples:
			assert_true(point.y > 0.0 and point.y < height, "Sample exceeds current collider height")
			var axis_y: float = clampf(point.y, 0.4, height - 0.4)
			assert_true(point.distance_to(Vector3(0.0, axis_y, 0.0)) < 0.4, "Sample outside capsule")

func test_damage_contract() -> void:
	var collider: Node = track(Node.new()) as Node
	var receiver: DamageReceiver = DamageReceiver.new()
	receiver.name = "DamageReceiver"
	collider.add_child(receiver)
	assert_true(DamageReceiver.deliver(collider, 25.0, {"item_id": "core:pistol"}))
	assert_eq(receiver.health, 75.0)
	DamageReceiver.deliver(collider, -10.0, {})
	assert_eq(receiver.health, 75.0)
	DamageReceiver.deliver(collider, 999.0, {})
	assert_eq(receiver.health, 0.0)
	var inert: Node = track(Node.new()) as Node
	assert_false(DamageReceiver.deliver(inert, 25.0, {}))
	assert_false(DamageReceiver.deliver(null, 25.0, {}))

func test_visual_roll_is_model_only() -> void:
	var visual: Script = load("res://core/player/PlayerVisual.gd") as Script
	var first: Transform3D = visual.call("pose_transform", {"rolling": true, "roll_progress": 0.0}, 0.8)
	var half: Transform3D = visual.call("pose_transform", {"rolling": true, "roll_progress": 0.5}, 0.8)
	var last: Transform3D = visual.call("pose_transform", {"rolling": true, "roll_progress": 1.0}, 0.8)
	assert_true(first.basis.is_equal_approx(last.basis))
	assert_false(first.basis.is_equal_approx(half.basis))
	assert_true((half * Vector3(0.0, 0.75, 0.0)).is_equal_approx(Vector3(0.0, 0.75, 0.0)))
	assert_true(is_equal_approx(half.basis.determinant(), 1.0))
	var source: String = FileAccess.get_file_as_string("res://core/player/PlayerVisual.gd")
	assert_false(source.contains("camera.rotate"))

func test_core_static_contracts() -> void:
	var controller: String = FileAccess.get_file_as_string("res://core/player/PlayerController.gd")
	assert_false(controller.contains("original_capsule"))
	assert_false(controller.contains("global_position.y +="))
	assert_false(controller.contains("func _shoot_pistol"))
	assert_false(controller.contains("func _start_dash"))
	assert_contains(controller, "func add_movement_extension")
	var content: String = FileAccess.get_file_as_string("res://content/core/mod.gd")
	assert_contains(content, '"drops": [] if block_id == AIR')
	var pistol: String = FileAccess.get_file_as_string("res://mods/player_actions/scripts/PistolActions.gd")
	assert_false(pistol.contains("func _ensure_pistol"))
	assert_contains(pistol, "debug_starting_inventory")

func test_shape_unique_once_and_feet_anchored() -> void:
	var shared: CapsuleShape3D = CapsuleShape3D.new()
	shared.radius = 0.4
	shared.height = 1.9
	var player: PlayerController = PlayerController.new()
	player.name = "2"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.shape = shared
	player.add_child(shape_node)
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	camera.position.y = 1.58
	player.add_child(camera)
	var inventory: Inventory = Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	track(player)
	# Runner may instantiate tests outside the tree; initialize references there.
	player.collision_shape = shape_node
	player.camera = camera
	player.inventory = inventory
	if shape_node.shape == shared:
		player._ready()
	var unique: Shape3D = shape_node.shape
	assert_false(unique == shared)
	var feet: Vector3 = player.position
	player.requested_height = 0.8
	for step: int in range(30):
		player._update_posture(1.0 / 60.0)
	assert_true(shape_node.shape == unique, "Capsule reallocated during posture update")
	assert_eq(player.position, feet)
	assert_true(is_equal_approx(shared.height, 1.9))
	assert_true(is_equal_approx((unique as CapsuleShape3D).height, 0.8))
	assert_true(is_equal_approx(shape_node.position.y, 0.4))

func test_pistol_inventory_clamp_without_grants() -> void:
	var player: PlayerController = PlayerController.new()
	var inventory: Inventory = Inventory.new()
	var pistol: PlayerPistolActions = PlayerPistolActions.new()
	# Keep these objects outside the tree: exercise only the deterministic clamp.
	inventory.items = [{"id": "core:pistol_ammo", "count": 3}, {"id": "core:stone", "count": 7}]
	var before: Array[Dictionary] = inventory.items.duplicate(true)
	pistol.player = player
	pistol.inventory = inventory
	pistol.magazine = 12
	pistol._inventory_changed()
	assert_eq(pistol.magazine, 3)
	assert_eq(inventory.items, before)
	assert_eq(inventory.get_item_count("core:pistol"), 0)
	pistol.free()
	inventory.free()
	player.free()

func test_manifest() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mods/player_actions/mod.json")) as Dictionary
	assert_eq(manifest.get("id"), "core:player_actions")
	assert_contains(manifest.get("dependencies", []), "core:base")
	assert_true(FileAccess.file_exists("res://mods/player_actions/" + str(manifest.get("entry"))))
