class_name WorldDeleteMenuFixture
extends Node

## Manual UI smoke-test scene. Never uses or deletes real user worlds.
var _original: WorldSaveService
var _fixture: WorldSaveService

func _ready() -> void:
	_original = GameAPI.saves
	var root: String = "user://world_save_tests/menu_%s" % Time.get_ticks_usec()
	_fixture = WorldSaveService.new(root, root.path_join("legacy.json"))
	DirAccess.make_dir_recursive_absolute(root)
	for filename: String in ["fixture.json", "fixture.sqlite", "fixture.sqlite-wal", "fixture.sqlite-shm", "fixture.player.json", "neighbor.json", "legacy.json"]:
		var file: FileAccess = FileAccess.open(root.path_join(filename), FileAccess.WRITE)
		file.store_string("corrupt test fixture")
		file.close()
	GameAPI.saves = _fixture
	var menu: WorldSelectionMenu = preload("res://scenes/menu/MainMenu.tscn").instantiate() as WorldSelectionMenu
	add_child(menu)
	menu._refresh_worlds("fixture")
	menu.delete_dialog.canceled.connect(_check_cancel)
	menu.delete_dialog.confirmed.connect(_check_confirm)

func _check_cancel() -> void:
	assert(FileAccess.file_exists(_fixture.metadata_path("fixture")))
	print("UI CANCEL: fixture preserved")

func _check_confirm() -> void:
	assert(not FileAccess.file_exists(_fixture.metadata_path("fixture")))
	assert(FileAccess.file_exists(_fixture.metadata_path("neighbor")))
	assert(FileAccess.file_exists(_fixture.legacy_state_path))
	print("UI CONFIRM: isolated fixture removed; neighbor and legacy preserved")

func _exit_tree() -> void:
	GameAPI.saves = _original
