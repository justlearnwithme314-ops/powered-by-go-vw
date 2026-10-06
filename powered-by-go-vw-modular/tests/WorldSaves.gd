class_name WorldSavesTest
extends Node

class FailingDeleteService extends WorldSaveService:
	func _remove_save_file(path: String) -> Error:
		if path.ends_with(".sqlite-wal"):
			return ERR_FILE_NO_PERMISSION
		return super._remove_save_file(path)

var service: WorldSaveService

func setup() -> void:
	var root: String = "user://world_save_tests/%s_%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	service = WorldSaveService.new(root, root.path_join("legacy.json"))
	DirAccess.make_dir_recursive_absolute(root)

func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()

func test_creation_validation_and_collisions() -> void:
	setup()
	assert(not service.create_world(" ", "1").success)
	for invalid: String in ["", "1.2", "abc", "2147483648", "-2147483649", "99999999999999999999"]:
		assert(not service.create_world("Test", invalid).success)
	var first: Dictionary = service.create_world("../../TEST / name", "-2147483648")
	assert(first.success)
	assert(service.safe_id(first.save_name))
	var original: String = FileAccess.get_file_as_string(service.metadata_path(first.save_name))
	var second: Dictionary = service.create_world("../../TEST / name", "+2147483647")
	assert(second.success and first.save_name != second.save_name)
	assert(FileAccess.get_file_as_string(service.metadata_path(first.save_name)) == original)
	assert(service.read_world(first.save_name).seed == -2147483648)

func test_listing_and_metadata_safety() -> void:
	setup()
	_write(service.root_path.path_join("orphan.sqlite"), "test fixture, not a database")
	_write(service.metadata_path("broken"), "{bad json")
	_write(service.metadata_path("fractional"), '{"seed": 1.5}')
	_write(service.state_path("ignored"), '{}')
	var created: Dictionary = service.create_world("Listed", "42")
	assert(created.success)
	var catalog: Array[Dictionary] = service.list_worlds()
	assert(catalog.size() == 5) # Inventory-only orphan is also discoverable for cleanup.
	assert(not service.read_world("orphan").valid)
	assert(not service.read_world("broken").valid)
	assert(not service.read_world("fractional").valid)
	assert(not service.read_world("../escape").valid)
	assert(service.read_world("orphan").error.contains("original seed"))

func test_original_seed_selection_and_snapshot() -> void:
	setup()
	var created: Dictionary = service.create_world("Config", "-55", {"mods": "original"})
	assert(service.select_world(created.save_name).valid)
	var copy: Dictionary = service.selected_config()
	copy.seed = 999
	assert(service.selected_config().seed == -55)
	assert(not service.select_world("unknown").valid)
	assert(service.selected_config().seed == -55)
	service.clear_selection()
	assert(service.selected_config().is_empty())
	var reopened: WorldSaveService = WorldSaveService.new(service.root_path, service.legacy_state_path)
	assert(reopened.select_world(created.save_name).seed == -55)

func test_inventory_isolation_and_default_fallback() -> void:
	setup()
	var a: Dictionary = service.create_world("A", "1")
	var b: Dictionary = service.create_world("B", "1")
	_write(service.legacy_state_path, '{"legacy":true}')
	assert(service.state_load_path("default") == service.legacy_state_path)
	assert(not service.select_world("default").valid)
	_write(service.root_path.path_join("default.sqlite"), "legacy terrain fixture")
	assert(service.select_world("default").seed == 1337)
	assert(service.state_load_path(a.save_name) != service.legacy_state_path)
	assert(service.state_path(a.save_name) != service.state_path(b.save_name))
	_write(service.state_path(a.save_name), '{"inventory":"A"}')
	assert(not FileAccess.file_exists(service.state_load_path(b.save_name)))
	_write(service.state_path("default"), '{"inventory":"scoped"}')
	assert(service.state_load_path("default") == service.state_path("default"))
	assert(FileAccess.get_file_as_string(service.legacy_state_path) == '{"legacy":true}')
	assert(service.state_path("../bad").is_empty())

func test_delete_isolated_world_and_preserve_neighbors() -> void:
	setup()
	_write(service.legacy_state_path, "legacy inventory")
	for id: String in ["target", "neighbor", "default"]:
		for suffix: String in [".sqlite", ".sqlite-wal", ".sqlite-shm", ".player.json", ".json"]:
			_write(service.root_path.path_join(id + suffix), "corrupt metadata or fixture")
	assert(not service.read_world("target").valid)
	assert(service.delete_world("target").success)
	for suffix: String in [".sqlite", ".sqlite-wal", ".sqlite-shm", ".player.json", ".json"]:
		assert(not FileAccess.file_exists(service.root_path.path_join("target" + suffix)))
		assert(FileAccess.get_file_as_string(service.root_path.path_join("neighbor" + suffix)) == "corrupt metadata or fixture")
	assert(service.delete_world("target").success) # Missing files are idempotent.
	assert(service.delete_world("default").success)
	assert(FileAccess.get_file_as_string(service.legacy_state_path) == "legacy inventory")
	assert(not service.read_world("default").valid)
	for entry: Dictionary in service.list_worlds():
		assert(entry.save_name != "default", "Deleted default must not reappear in the menu")

func test_default_catalog_only_lists_existing_saves() -> void:
	setup()
	assert(service.list_worlds().is_empty())

	_write(service.metadata_path("default"), '{"seed":1337}')
	assert(service.list_worlds().size() == 1)
	assert(service.list_worlds()[0].save_name == "default")
	assert(service.delete_world("default").success)
	assert(WorldSaveService.new(service.root_path, service.legacy_state_path).list_worlds().is_empty())
	var created: Dictionary = service.create_world("My World", "42")
	assert(created.success)
	assert(service.list_worlds().size() == 1)
	assert(service.list_worlds()[0].save_name == created.save_name)

func test_delete_rejects_paths_aliases_and_active_world() -> void:
	setup()
	_write(service.metadata_path("keep"), '{"seed":1}')
	for id: String in ["", ".", "..", "../keep", "a/../keep", "a\\keep", "user://worlds/keep", "/keep", "C:\\keep", "keep.", "keep ", "keep.player"]:
		assert(not service.delete_world(id).success)
	assert(FileAccess.file_exists(service.metadata_path("keep")))
	service.active_world_id = "keep"
	assert(not service.delete_world("keep").success)
	assert(not service.delete_world("KEEP").success)
	service.active_world_id = ""
	assert(service.select_world("keep").valid)
	assert(service.delete_world("keep").success)
	assert(service.selected_config().is_empty())

func test_delete_partial_failure_reports_and_preserves_metadata() -> void:
	setup()
	var failing: FailingDeleteService = FailingDeleteService.new(service.root_path, service.legacy_state_path)
	for suffix: String in [".sqlite", ".sqlite-wal", ".player.json", ".json"]:
		_write(service.root_path.path_join("partial" + suffix), "fixture")
	var result: Dictionary = failing.delete_world("partial")
	assert(not result.success and result.removed == 1)
	assert(str(result.error).contains("Deletion incomplete"))
	assert(FileAccess.file_exists(service.metadata_path("partial")))
	assert(FileAccess.file_exists(service.state_path("partial")))
	assert(service.delete_world("partial").success) # Retry removes the remainder.

func test_delete_preflight_directory_preserves_files() -> void:
	setup()
	_write(service.metadata_path("blocked"), '{"seed":1}')
	_write(service.root_path.path_join("blocked.sqlite"), "terrain")
	DirAccess.make_dir_absolute(service.state_path("blocked"))
	assert(not service.delete_world("blocked").success)
	assert(FileAccess.get_file_as_string(service.root_path.path_join("blocked.sqlite")) == "terrain")
	assert(FileAccess.file_exists(service.metadata_path("blocked")))
	_write(service.root_path.path_join("orphan.sqlite-wal"), "sidecar only")
	assert(service.delete_world("orphan").success)

func test_legacy_metadata_and_launch_wiring() -> void:
	setup()
	_write(service.metadata_path("default"), '{"seed":123,"mods":"legacy","content":"original"}')
	assert(service.read_world("default").seed == 123)
	_write(service.metadata_path("default"), '{"seed":"unknown"}')
	assert(not service.read_world("default").valid)
	var world: String = FileAccess.get_file_as_string("res://scenes/world/World.gd")
	assert(world.find("selected_config()") < world.find("_check_save_compatibility()"))
	var manager: String = FileAccess.get_file_as_string("res://core/network/GameManager.gd")
	assert(manager.contains("GameAPI.saves.state_path(save_id)"))
	assert(manager.contains("GameAPI.saves.state_load_path(save_id)"))

func test_drop_sidecars_share_world_identity_and_delete() -> void:
	setup()
	var result := service.create_world("Drop fixture", "12")
	var id := str(result.save_name)
	for suffix in [".drops.json", ".drops.json.tmp", ".drops.json.bak"]:
		_write(service.root_path.path_join(id + suffix), "{}")
	assert(service.list_worlds().size() == 1)
	assert(service.list_worlds()[0].save_name == id)
	assert(service.delete_world(id).success)
	for suffix in [".drops.json", ".drops.json.tmp", ".drops.json.bak"]:
		assert(not FileAccess.file_exists(service.root_path.path_join(id + suffix)))
	assert(service.list_worlds().is_empty())

func test_station_sidecar_catalog_and_delete() -> void:
	setup()
	var created := service.create_world("Stations", "53")
	assert(created.success)
	var id := str(created.save_name)
	for suffix in [".entities.json", ".entities.json.tmp", ".entities.json.bak", ".creatures.json", ".creatures.json.tmp", ".creatures.json.bak"]:
		_write(service.root_path.path_join(id + suffix), "fixture")
	assert(service.list_worlds().size() == 1 and service.list_worlds()[0].save_name == id)
	assert(service.delete_world(id).success)
	for suffix in [".entities.json", ".entities.json.tmp", ".entities.json.bak", ".creatures.json", ".creatures.json.tmp", ".creatures.json.bak"]:
		assert(not FileAccess.file_exists(service.root_path.path_join(id + suffix)))
