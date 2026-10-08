extends Node

func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Could not write " + path)
	file.store_string(value)
	file.flush()
	assert(file.get_error() == OK, "Failed writing " + path)
	file.close()

func _ready() -> void:
	_write("res://mods/machines/mod.json", JSON.stringify({
		"id": "industry:machines",
		"name": "Industrial Machines",
		"version": "1.0.0",
		"api_version": 1,
		"entry": "mod.gd",
		"dependencies": ["survival:crafting_progression", "crafting:shaped"]
	}, "\t") + "\n")
	var suite_path := "res://tools/smoke_suites.json"
	var suites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(suite_path))
	var content_suites: Array = suites.suites.content
	if not content_suites.any(func(entry: Dictionary) -> bool: return str(entry.get("scene", "")) == "MachineSmoke.tscn"):
		content_suites.append({"scene": "MachineSmoke.tscn", "success_marker": "Machine smoke passed:"})
	suites.suites.content = content_suites
	_write(suite_path, JSON.stringify(suites, "\t") + "\n")
	var tasks_path := "res://LUNA_TASKS.md"
	var tasks := FileAccess.get_file_as_string(tasks_path)
	tasks = tasks.replace("| T10 | Generic machine registration and processing | T02, T04, T07 | Luna Medium | Medium | TODO |", "| T10 | Generic machine registration and processing | T02, T04, T07 | Luna Medium | Medium | DONE — reusable registry/runtime; MachineSmoke passed |")
	if not tasks.contains("- T10:"):
		tasks += "\n- T10: industry:machines registers and ticks shared station-backed machines; MachineSmoke covers registry validation, tag recipes, priority, progress reset, multi-completion, feature gating, persistence and legacy furnace isolation. No networked shared-station playtest until Sol ticket T08.\n"
	_write(tasks_path, tasks)
	print("T10 manifest, smoke suite and task ledger updated.")
	get_tree().quit()
