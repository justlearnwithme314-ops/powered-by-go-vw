extends Node

@onready var voxel_terrain: VoxelTerrain = $VoxelTerrain


func _ready() -> void:
	Global.active_terrain = voxel_terrain
	print("[World] VoxelTerrain registered to Global hub successfully.")

	var player_viewer = get_tree().current_scene.find_child("VoxelViewer", true, false)

	if player_viewer:
		print("[World] VoxelViewer found! Terrain will load chunks automatically.")
	else:
		push_warning("[World] Could not find VoxelViewer! Chunks will not load.")


func _exit_tree() -> void:
	if Global.active_terrain == voxel_terrain:
		Global.active_terrain = null
		print("[World] Cleared Global.active_terrain.")
