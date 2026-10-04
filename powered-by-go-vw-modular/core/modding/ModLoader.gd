class_name ModLoader
extends RefCounted

## Discovers and loads built-in content, loose folders, and .pck mods.
##
## A mod is identified by manifest ID and may declare dependencies:
## {
##   "id": "example:machines",
##   "version": "1.0.0",
##   "entry": "mod.gd",
##   "dependencies": ["core:base"]
## }

signal mod_loaded(manifest: Dictionary)
signal all_mods_loaded

const USER_MODS_DIR := "user://mods"
const PROJECT_MODS_DIR := "res://mods"

var loaded_mods: Array[Dictionary] = []
var _instances: Array[GameMod] = []
var _mod_apis: Array[ModAPI] = []
var _loaded_ids: Dictionary = {}
var _api: ModAPI


func load_all(api: ModAPI) -> void:
	_api = api
	_ensure_user_mod_folder()
	_mount_user_packs()

	# The built-in game content is itself a mod, and is always the first
	# dependency available to third-party content.
	var core_manifest := _read_manifest("res://content/core/mod.json", "res://content/core")
	if not core_manifest.is_empty():
		_load_manifest(core_manifest)

	var candidates := _discover_directory_manifests(PROJECT_MODS_DIR)
	candidates.append_array(_discover_directory_manifests(USER_MODS_DIR))
	_load_with_dependencies(candidates)

	loaded_mods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["id"]) < str(b["id"])
	)
	all_mods_loaded.emit()


func _ensure_user_mod_folder() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.make_dir_recursive("mods")


func _mount_user_packs() -> void:
	var dir := DirAccess.open(USER_MODS_DIR)
	if dir == null:
		return

	var packs: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".pck"):
			packs.append(USER_MODS_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	packs.sort()

	for pck_path in packs:
		if ProjectSettings.load_resource_pack(pck_path):
			print("[ModLoader] Mounted: ", pck_path)
		else:
			push_warning("[ModLoader] Failed to mount: %s" % pck_path)


func _discover_directory_manifests(directory_path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return result

	var candidates: Array[String] = []
	dir.list_dir_begin()
	var folder := dir.get_next()
	while not folder.is_empty():
		if (
			dir.current_is_dir()
			and not folder.begins_with(".")
			and folder != "_template"
		):
			candidates.append(folder)
		folder = dir.get_next()
	dir.list_dir_end()
	candidates.sort()

	for folder_name in candidates:
		var root_path := directory_path.path_join(folder_name)
		var manifest_path := root_path.path_join("mod.json")
		if FileAccess.file_exists(manifest_path):
			var manifest := _read_manifest(manifest_path, root_path)
			if not manifest.is_empty():
				result.append(manifest)
	return result


func _read_manifest(manifest_path: String, root_path: String) -> Dictionary:
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		push_warning("[ModLoader] Cannot open manifest: %s" % manifest_path)
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("[ModLoader] Invalid manifest: %s" % manifest_path)
		return {}

	var mod_id := str(parsed.get("id", ""))
	if mod_id.is_empty() or not mod_id.contains(":"):
		push_warning("[ModLoader] Mod has no ID: %s" % manifest_path)
		return {}

	var entry := str(parsed.get("entry", "mod.gd"))
	var entry_path := entry
	if not entry_path.begins_with("res://") and not entry_path.begins_with("user://"):
		entry_path = root_path.path_join(entry)

	if not FileAccess.file_exists(entry_path):
		push_error(
			"[ModLoader] Mod '%s' entry does not exist: %s"
			% [mod_id, entry_path]
		)
		return {}

	var normalized: Dictionary = parsed.duplicate(true)
	var api_version := int(parsed.get("api_version", 1))
	if api_version != ModAPI.API_VERSION:
		push_error(
			"[ModLoader] Mod '%s' requires API v%d; this game provides v%d."
			% [mod_id, api_version, ModAPI.API_VERSION]
		)
		return {}
	normalized["id"] = mod_id
	normalized["name"] = str(parsed.get("name", mod_id))
	normalized["version"] = str(parsed.get("version", "0.0.0"))
	normalized["entry"] = entry_path
	normalized["dependencies"] = parsed.get("dependencies", [])
	normalized["_root_path"] = root_path
	return normalized


func _load_with_dependencies(candidates: Array[Dictionary]) -> void:
	var by_id: Dictionary = {}
	for manifest in candidates:
		var mod_id := str(manifest["id"])
		if _loaded_ids.has(mod_id) or by_id.has(mod_id):
			push_warning("[ModLoader] Duplicate mod ID skipped: %s" % mod_id)
			continue
		by_id[mod_id] = manifest

	var remaining: Dictionary = by_id.duplicate()

	while not remaining.is_empty():
		var progress := false
		var ready_ids: Array[String] = []

		for mod_id in remaining:
			var manifest: Dictionary = remaining[mod_id]
			var dependencies: Array = manifest.get("dependencies", [])
			var dependencies_ready := true
			for dependency in dependencies:
				if not _loaded_ids.has(str(dependency)):
					dependencies_ready = false
					break
			if dependencies_ready:
				ready_ids.append(str(mod_id))

		ready_ids.sort()
		for mod_id in ready_ids:
			_load_manifest(remaining[mod_id])
			remaining.erase(mod_id)
			progress = true

		if progress:
			continue

		# Nothing can become ready: either a missing dependency or a cycle.
		for mod_id in remaining:
			var manifest: Dictionary = remaining[mod_id]
			push_error(
				"[ModLoader] Cannot load '%s'; unresolved dependencies: %s"
				% [mod_id, str(manifest.get("dependencies", []))]
			)
		break


func _load_manifest(manifest: Dictionary) -> void:
	var mod_id := str(manifest["id"])
	if _loaded_ids.has(mod_id):
		return

	var entry_path := str(manifest["entry"])
	var script = load(entry_path)
	if script == null:
		push_error(
			"[ModLoader] Could not load entry '%s' for mod '%s'."
			% [entry_path, mod_id]
		)
		return

	var instance = script.new()
	if not instance is GameMod:
		push_error(
			"[ModLoader] '%s' must extend GameMod."
			% entry_path
		)
		return

	var normalized := manifest.duplicate(true)
	var root_path := str(normalized.get("_root_path", ""))
	normalized.erase("_root_path")
	loaded_mods.append(normalized)
	_loaded_ids[mod_id] = true
	_instances.append(instance)

	var mod_api := ModAPI.new(
		_api.content,
		_api.events,
		_api.world_generation,
		_api.world,
		_api.edits,
		_api.crafting,
		mod_id,
		str(manifest["version"]),
		root_path
	)
	mod_api.saves = _api.saves
	_mod_apis.append(mod_api)

	print(
		"[ModLoader] Registering %s %s"
		% [mod_id, str(manifest["version"])]
	)
	instance.register(mod_api)
	mod_loaded.emit(normalized)


func save_all_storage() -> void:
	for api in _mod_apis:
		api.save_storage()


func get_signature() -> String:
	var entries: Array[String] = []
	for manifest in loaded_mods:
		entries.append(
			"%s@%s"
			% [str(manifest["id"]), str(manifest["version"])]
		)
	entries.sort()
	return JSON.stringify(entries)


func get_loaded_mods() -> Array[Dictionary]:
	return loaded_mods.duplicate(true)
