class_name WorldSaveService
extends RefCounted

## Generic local save catalog. Selection is a launch configuration, not networking.
var root_path: String
var legacy_state_path: String
var _selected: Dictionary = {}
# Set by the world lifecycle, not by menu selection.
var active_world_id: String = ""

func _init(root: String = "user://worlds", legacy: String = "user://player_state.json") -> void:
	root_path = root
	legacy_state_path = legacy

func safe_id(value: String) -> bool:
	return not value.is_empty() and value != "." and not value.contains("..") and value.is_valid_filename() and not value.contains("/") and not value.contains("\\")

func seed_valid(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= -2147483648.0 and float(value) <= 2147483647.0

func metadata_path(id: String) -> String:
	return root_path.path_join(id + ".json") if safe_id(id) else ""

func read_world(id: String) -> Dictionary:
	var result: Dictionary = {"save_name": id, "display_name": id, "valid": false, "error": ""}
	if not safe_id(id):
		result.error = "Unsafe save filename. Rename a backup outside the game before loading."
		return result
	var path: String = metadata_path(id)
	if not FileAccess.file_exists(path):
		# Only the documented legacy default has a known original seed.
		if id == "default" and FileAccess.file_exists(root_path.path_join("default.sqlite")):
			result.merge({"seed": 1337, "valid": true}, true)
			return result
		result.error = "Missing metadata: restore %s from backup with its original seed; terrain was not changed." % path
		return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var parser: JSON = JSON.new()
	var data: Variant = null
	if file != null and parser.parse(file.get_as_text()) == OK:
		data = parser.data
	if not data is Dictionary or not seed_valid(data.get("seed")):
		result.error = "Invalid metadata: restore %s from backup (original integer seed required); do not recreate this save." % path
		return result
	# Preserve extension metadata, but restore catalog-owned fields afterward so
	# serialized values can never spoof the filename or validity state.
	result.merge(data, true)
	result.save_name = id
	result.seed = int(data.seed)
	result.valid = true
	result.error = ""
	result.display_name = str(data.get("display_name", id))
	return result

func list_worlds() -> Array[Dictionary]:
	# Show saved worlds only; do not recreate a virtual default after deletion.
	var ids: Array[String] = []
	if DirAccess.dir_exists_absolute(root_path):
		for filename: String in DirAccess.get_files_at(root_path):
			if filename.ends_with(".json") or filename.ends_with(".sqlite") or filename.ends_with(".sqlite-wal") or filename.ends_with(".sqlite-shm"):
				var id: String = filename.get_basename()
				if filename.ends_with(".player.json"):
					id = filename.trim_suffix(".player.json")
				elif filename.ends_with(".drops.json"):
					id = filename.trim_suffix(".drops.json")
				elif filename.ends_with(".entities.json"):
					id = filename.trim_suffix(".entities.json")
				elif filename.ends_with(".creatures.json"):
					id = filename.trim_suffix(".creatures.json")
				elif filename.ends_with(".stations.json"):
					id = filename.trim_suffix(".stations.json")
				elif filename.ends_with(".farming.json"):
					id = filename.trim_suffix(".farming.json")
				if not ids.has(id):
					ids.append(id)
	ids.sort()
	var result: Array[Dictionary] = []
	for id: String in ids:
		result.append(read_world(id))
	return result

func create_world(display_name: String, seed_text: String, compatibility: Dictionary = {}) -> Dictionary:
	var title: String = display_name.strip_edges()
	if title.is_empty() or title.length() > 80:
		return {"success": false, "error": "Enter a world name (1-80 characters)."}
	var text: String = seed_text.strip_edges()
	if not text.is_valid_int() or text.length() > 11 or not seed_valid(text.to_int()):
		return {"success": false, "error": "Enter a signed integer seed from -2147483648 to 2147483647."}
	var base: String = "world_"
	for character: String in title.to_lower():
		base += character if "abcdefghijklmnopqrstuvwxyz0123456789".contains(character) else "_"
	var id: String = base
	var suffix: int = 2
	while _occupied(id):
		id = base + "_" + str(suffix)
		suffix += 1
	var error: Error = DirAccess.make_dir_recursive_absolute(root_path)
	if error != OK:
		return {"success": false, "error": "Cannot create save directory: %s. Check permissions/disk space." % error_string(error)}
	var data: Dictionary = compatibility.duplicate(true)
	data.merge({"display_name": title, "seed": text.to_int()}, true)
	var file: FileAccess = FileAccess.open(metadata_path(id), FileAccess.WRITE)
	if file == null:
		return {"success": false, "error": "Cannot write metadata. Check permissions/disk space."}
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	if file.get_error() != OK:
		return {"success": false, "error": "Metadata write failed. Check disk space; reserved save was not overwritten."}
	file.close()
	return {"success": true, "save_name": id}

func _occupied(id: String) -> bool:
	# Include sidecars and scoped inventory, even if metadata was lost.
	if id == "default":
		return true
	for filename: String in DirAccess.get_files_at(root_path) if DirAccess.dir_exists_absolute(root_path) else PackedStringArray():
		if filename.to_lower().begins_with(id.to_lower() + "."):
			return true
	return false

func select_world(id: String) -> Dictionary:
	var config: Dictionary = read_world(id)
	if config.valid:
		_selected = config.duplicate(true)
	return config

func selected_config() -> Dictionary:
	return _selected.duplicate(true)

func clear_selection() -> void:
	_selected.clear()

## Destructive operations accept canonical catalog IDs only, never paths or metadata paths.
## Inventory is a flat <id>.player.json file, not a directory. Never recurse.
## Legacy global player_state.json is deliberately retained, even for default.
func delete_world(id: String) -> Dictionary:
	if not deletion_id_valid(id):
		return {"success": false, "error": "Unsafe world ID; no files removed."}
	if not active_world_id.is_empty() and id.to_lower() == active_world_id.to_lower():
		return {"success": false, "error": "Close the active world before deleting it."}
	var root: String = ProjectSettings.globalize_path(root_path).simplify_path().trim_suffix("/")
	# Refuse linked roots/ancestors: lexical containment alone is not sufficient.
	var probe: String = root
	while not probe.is_empty():
		var parent: String = probe.get_base_dir()
		var parent_dir: DirAccess = DirAccess.open(parent)
		if parent_dir != null and parent_dir.is_link(probe):
			return {"success": false, "error": "Linked save directories cannot be deleted safely."}
		if parent == probe:
			break
		probe = parent
	var paths: Array[String] = []
	for suffix: String in [".sqlite", ".sqlite-wal", ".sqlite-shm", ".player.json", ".player.json.tmp", ".player.json.bak", ".player.json.pre_slots.bak", ".drops.json", ".drops.json.tmp", ".drops.json.bak", ".entities.json", ".entities.json.tmp", ".entities.json.bak", ".creatures.json", ".creatures.json.tmp", ".creatures.json.bak", ".stations.json", ".stations.json.tmp", ".stations.json.bak", ".farming.json", ".farming.json.tmp", ".json"]:
		var path: String = root.path_join(id + suffix).simplify_path()
		if path.get_base_dir() != root:
			return {"success": false, "error": "Save path escaped its directory; no files removed."}
		paths.append(path)
	var directory: DirAccess = DirAccess.open(root)
	if directory == null:
		if DirAccess.dir_exists_absolute(root):
			return {"success": false, "error": "Cannot access save directory; check permissions."}
		return {"success": true, "error": "", "removed": 0}
	# Validate the whole set before touching anything; do not follow links or remove directories.
	for path: String in paths:
		if directory.is_link(path) or DirAccess.dir_exists_absolute(path):
			return {"success": false, "error": "Unexpected link/directory at %s; no files removed." % path.get_file()}
	var removed: int = 0
	for path: String in paths:
		if not FileAccess.file_exists(path):
			continue
		var error: Error = _remove_save_file(path)
		if error != OK:
			clear_selection()
			return {"success": false, "removed": removed, "error": "Deletion incomplete (%d files removed). Cannot remove %s: %s. Close other game instances/check permissions, then retry." % [removed, path.get_file(), error_string(error)]}
		removed += 1
	if str(_selected.get("save_name", "")).to_lower() == id.to_lower():
		clear_selection()
	return {"success": true, "error": "", "removed": removed}

func _remove_save_file(path: String) -> Error:
	return DirAccess.remove_absolute(path)

func deletion_id_valid(id: String) -> bool:
	if not safe_id(id):
		return false
	# Dots could alias another world's scoped inventory; trailing spaces/dots alias on Windows.
	for character: String in id:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-".contains(character):
			return false
	return true

func state_path(id: String) -> String:
	return root_path.path_join(id + ".player.json") if safe_id(id) else ""

func state_load_path(id: String) -> String:
	var path: String = state_path(id)
	if id == "default" and not FileAccess.file_exists(path):
		return legacy_state_path
	return path
