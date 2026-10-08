extends Node

const PlayerPlacementGuard = preload("res://core/world/PlayerPlacementGuard.gd")

func _ready() -> void:
	var player := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	player.add_child(collision)
	add_child(player)
	await get_tree().process_frame
	assert(PlayerPlacementGuard.overlaps_player_cell(player, Vector3i.ZERO), "must reject a block through the player's body")
	assert(not PlayerPlacementGuard.overlaps_player_cell(player, Vector3i(1, 0, 0)), "must allow a neighboring cell")
	assert(not PlayerPlacementGuard.overlaps_player_cell(player, Vector3i(0, -1, 0)), "must allow the block under the player's feet")
	print("Player placement guard smoke passed")
	get_tree().quit()
