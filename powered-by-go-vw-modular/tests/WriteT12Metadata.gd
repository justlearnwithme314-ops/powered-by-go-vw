extends Node

func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not write " + path)
	file.store_string(value)
	file.flush()
	assert(file.get_error() == OK, "Failed writing " + path)
	file.close()

func _ready() -> void:
	_write("res://mods/energy_framework/mod.json", JSON.stringify({
		"id": "industry:energy",
		"name": "Energy Framework",
		"version": "1.0.0",
		"api_version": 1,
		"entry": "mod.gd",
		"dependencies": ["industry:machines", "survival:crafting_progression"]
	}, "\t") + "\n")
	var suite_path := "res://tools/smoke_suites.json"
	var suites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(suite_path))
	var content_suites: Array = suites.suites.content
	if not content_suites.any(func(entry: Dictionary) -> bool: return str(entry.get("scene", "")) == "EnergySmoke.tscn"):
		content_suites.append({"scene": "EnergySmoke.tscn", "success_marker": "Energy smoke passed:"})
	suites.suites.content = content_suites
	_write(suite_path, JSON.stringify(suites, "\t") + "\n")
	var tasks_path := "res://LUNA_TASKS.md"
	var tasks := FileAccess.get_file_as_string(tasks_path)
	tasks = tasks.replace("| T12 | Energy ports and bounded connectivity | T10 | Luna Medium | Medium | TODO |", "| T12 | Energy ports and bounded connectivity | T10 | Luna Medium | Medium | DONE — bounded graph service and EnergySmoke passed |")
	tasks = tasks.replace("MachineSmoke covers registry validation, tag recipes, priority, progress reset, multi-completion, feature gating, persistence and legacy furnace isolation.", "MachineSmoke covers registry validation, tag recipes, priority, progress reset, multi-completion, output-full pause, save/reload, failed-save rollback, feature gating and legacy furnace isolation.")
	if not tasks.contains("- T12:"):
		tasks += "- T12: api.energy and industry:energy add validated six-face cable/device roles, sparse station records, integer local storage, bounded 64-node rebuild slices and a 512-cell graph ceiling. EnergySmoke covers deterministic connection, incompatibility, disconnection, unloaded and oversized networks, invalidation, local storage and reload. Loaded-state adapters can call notify_loaded_state_changed; the existing event bus has no chunk-stream event wired.\n"
	_write(tasks_path, tasks)
	print("T12 manifest, smoke suite and task ledger updated.")
	get_tree().quit()
