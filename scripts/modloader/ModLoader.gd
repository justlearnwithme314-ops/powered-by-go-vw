extends Node

signal mod_loaded(mod_name: String)
signal all_mods_loaded

var loaded_mods: Array[String] = []
const MODS_DIR: String = "user://mods"

func _ready() -> void:
	ensure_mod_folder_exists()
	load_all_mods()

func ensure_mod_folder_exists() -> void:
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("mods"):
		dir.make_dir("mods")

func load_all_mods() -> void:
	var dir = DirAccess.open(MODS_DIR)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".pck"):
			load_pck_mod(MODS_DIR + "/" + file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	all_mods_loaded.emit()

func load_pck_mod(pck_path: String) -> bool:
	var success = ProjectSettings.load_resource_pack(pck_path)
	if success:
		var mod_name = pck_path.get_file().get_basename()
		loaded_mods.append(mod_name)
		print("[ModLoader] Successfully loaded pack: ", mod_name)
		mod_loaded.emit(mod_name)
		return true
	
	printerr("[ModLoader] Failed to load pack: ", pck_path)
	return false
