extends Node3D

@export_group("World")
@export var world_seed: int = 1337
@export var save_world := true
@export var save_name := ""
@export var warn_on_content_mismatch := true

@onready var voxel_terrain: VoxelTerrain = $VoxelTerrain

var _stream = null


func _ready() -> void:
	GameAPI.ensure_ready()

	var config: Dictionary = GameAPI.saves.selected_config()
	if not config.is_empty():
		config = GameAPI.saves.select_world(str(config.save_name))
		if not config.valid:
			push_error("[World] " + str(config.error))
			get_tree().change_scene_to_file.call_deferred("res://scenes/menu/MainMenu.tscn")
			return
		save_name = str(config.save_name)
		world_seed = int(config.seed)
	else:
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			# Join terrain is transient until the protocol carries world identity.
			save_world = false
			save_name = ""
		else:
			push_warning("[World] Create and select a world in the main menu before playing.")
			NetworkManager.disconnect_game()
			get_tree().change_scene_to_file.call_deferred("res://scenes/menu/MainMenu.tscn")
			return

	GameAPI.saves.active_world_id = _safe_save_name()
	GameAPI.world_generation.world_seed = world_seed

	_check_save_compatibility()
	_configure_persistence()
	_configure_generator()
	_configure_mesher()
	GameAPI.world.attach(voxel_terrain)
	GameAPI.events.emit(GameEvents.WORLD_READY, {
		"world": self,
		"terrain": voxel_terrain,
		"seed": world_seed,
	})

	print(
		"[World] Ready. Seed=%d, content=%d blocks."
		% [world_seed, GameAPI.content.blocks.size()]
	)


func _safe_save_name() -> String:
	var safe := save_name.strip_edges()
	for character in ["/", "\\", ":", ".."]:
		safe = safe.replace(character, "_")
	return safe


func _save_metadata_path() -> String:
	return GameAPI.saves.metadata_path(_safe_save_name())


func _check_save_compatibility() -> void:
	if not save_world:
		return

	var expected := {
		"api_version": ModAPI.API_VERSION,
		"seed": world_seed,
		"mods": GameAPI.mods.get_signature(),
		"content": GameAPI.content.get_content_signature(),
	}
	var metadata_path := _save_metadata_path()

	if not FileAccess.file_exists(metadata_path):
		DirAccess.make_dir_recursive_absolute(GameAPI.saves.root_path)
		var new_file := FileAccess.open(metadata_path, FileAccess.WRITE)
		if new_file:
			new_file.store_string(JSON.stringify(expected, "\t"))
		return

	var file := FileAccess.open(metadata_path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return

	var mismatches: Array[String] = []
	for key in expected:
		var matches := int(parsed.get(key, 0)) == int(expected[key]) if key in ["seed", "api_version"] else str(parsed.get(key, "")) == str(expected[key])
		if not matches:
			mismatches.append(str(key))

	if warn_on_content_mismatch and not mismatches.is_empty():
		push_warning(
			("[World] Save '%s' was created with different %s. "
			+ "Existing voxel data may require the original mod set.")
			% [_safe_save_name(), ", ".join(mismatches)]
		)


func _configure_generator() -> void:
	var generator := voxel_terrain.generator as VoxelGeneratorScript
	if generator == null:
		push_error("[World] VoxelTerrain has no VoxelGeneratorScript generator.")
		return

	var runtime := GameAPI.world_generation.create_runtime()
	generator.set("runtime", runtime)
	print("[World] Installed generation runtime for seed ", world_seed)


func _configure_mesher() -> void:
	var library := GameAPI.content.build_voxel_library()
	var mesher := voxel_terrain.mesher as VoxelMesherBlocky

	if mesher == null:
		mesher = VoxelMesherBlocky.new()

	mesher.library = library
	voxel_terrain.mesher = mesher


func _configure_persistence() -> void:
	if not save_world:
		return

	if not ClassDB.class_exists("VoxelStreamSQLite"):
		push_warning(
			"[World] VoxelStreamSQLite is not present in this Zylann build; "
			+ "world persistence is disabled."
		)
		return

	var save_dir := GameAPI.saves.root_path
	DirAccess.make_dir_recursive_absolute(save_dir)

	_stream = ClassDB.instantiate("VoxelStreamSQLite")
	if _stream == null:
		push_warning("[World] Could not instantiate VoxelStreamSQLite.")
		return

	var database_path := "%s/%s.sqlite" % [save_dir, _safe_save_name()]
	_stream.set("database_path", database_path)
	voxel_terrain.stream = _stream

	print("[World] Saving voxel data to ", database_path)


func _exit_tree() -> void:
	GameAPI.events.emit(GameEvents.WORLD_STOPPING, {"world": self})
	if GameAPI.world != null and GameAPI.world.terrain == voxel_terrain:
		if save_world and _stream != null:
			voxel_terrain.save_modified_blocks()
			if _stream.has_method("flush"):
				_stream.flush()
		GameAPI.world.detach()
	if GameAPI.saves.active_world_id == _safe_save_name():
		GameAPI.saves.active_world_id = ""
