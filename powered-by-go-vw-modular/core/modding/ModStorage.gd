class_name ModStorage
extends RefCounted

## Small persistent JSON store for a single mod.
##
## This is intentionally simple: progression, configuration, discovered
## structures, and other mod-owned data can survive game restarts without
## sharing a file with core systems.

var mod_id := ""
var _path := ""
var _data: Dictionary = {}


func _init(p_mod_id: String) -> void:
	mod_id = p_mod_id
	_path = "user://mod_data/%s.json" % _sanitize(mod_id)
	_load()


func get_value(key: String, default_value = null):
	return _data.get(key, default_value)


func set_value(key: String, value) -> void:
	_data[key] = value


func has(key: String) -> bool:
	return _data.has(key)


func erase(key: String) -> void:
	_data.erase(key)


func snapshot() -> Dictionary:
	return _data.duplicate(true)


func save() -> bool:
	DirAccess.make_dir_recursive_absolute("user://mod_data")
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("[ModStorage] Could not save %s" % _path)
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	return true


func _load() -> void:
	if not FileAccess.file_exists(_path):
		return

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_data = parsed


func _sanitize(value: String) -> String:
	var result := value.to_lower()
	result = result.replace(":", "__")
	result = result.replace("/", "_")
	result = result.replace("\\", "_")
	return result
