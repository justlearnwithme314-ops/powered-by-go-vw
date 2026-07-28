extends Node

@onready var voxel_terrain: VoxelTerrain = $VoxelTerrain

func _ready() -> void:
	# 1. Register the terrain so the PlayerController can interact with it
	Global.active_terrain = voxel_terrain
	print("[World] VoxelTerrain registered to Global hub successfully.")
	
	# 2. Verify the VoxelViewer exists (Godot Voxel handles the rest automatically)
	var player_viewer = get_tree().current_scene.find_child("VoxelViewer", true, false)
	if player_viewer:
		print("[World] VoxelViewer found! Terrain will load chunks automatically.")
	else:
		push_warning("[World] Could not find VoxelViewer! Chunks will not load.")
