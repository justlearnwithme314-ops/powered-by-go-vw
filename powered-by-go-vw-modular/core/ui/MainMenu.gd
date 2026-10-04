class_name WorldSelectionMenu
extends Control

@onready var world_list: ItemList = $Center/VBox/WorldList
@onready var world_info: Label = $Center/VBox/WorldInfo
@onready var name_input: LineEdit = $Center/VBox/WorldName
@onready var seed_input: LineEdit = $Center/VBox/Seed
@onready var status_label: Label = $Center/VBox/Status
var _worlds: Array[Dictionary] = []
var _selected_id: String = ""
var _pending_delete_id: String = ""
@onready var delete_button: Button = $Center/VBox/Delete
@onready var delete_dialog: ConfirmationDialog = $DeleteConfirmation

func _refresh_worlds(preferred: String = "") -> void:
	_worlds = GameAPI.saves.list_worlds()
	world_list.clear()
	_selected_id = ""
	world_info.text = "Select a world"
	status_label.text = ""
	host_button.disabled = true
	delete_button.disabled = true
	for index: int in range(_worlds.size()):
		var entry: Dictionary = _worlds[index]
		world_list.add_item(str(entry.display_name) + (" [metadata needs repair]" if not entry.valid else ""))
		if str(entry.save_name) == preferred:
			world_list.select(index)
			_select_world(index)

func _select_world(index: int) -> void:
	var entry: Dictionary = _worlds[index]
	_selected_id = str(entry.save_name)
	host_button.disabled = not bool(entry.valid)
	delete_button.disabled = _selected_id.is_empty()
	world_info.text = "Seed: %s  •  Save: %s" % [entry.get("seed", "unknown"), _selected_id]
	status_label.text = str(entry.error)

func _request_delete() -> void:
	if _selected_id.is_empty():
		return
	_pending_delete_id = _selected_id
	var entry: Dictionary = GameAPI.saves.read_world(_pending_delete_id)
	delete_dialog.dialog_text = 'Permanently delete "%s" (save: %s)?\n\nTerrain, metadata and per-world inventory will be removed.\nThis cannot be undone. Other worlds are not affected.' % [str(entry.display_name), _pending_delete_id]
	if _pending_delete_id == "default":
		delete_dialog.dialog_text += "\nLegacy global inventory is retained. Default will disappear from the world list."
	delete_dialog.popup_centered_clamped(Vector2i(540, 220))
	delete_dialog.get_cancel_button().grab_focus.call_deferred()

func _cancel_delete() -> void:
	_pending_delete_id = ""

func _confirm_delete() -> void:
	var id: String = _pending_delete_id
	_pending_delete_id = ""
	if id.is_empty():
		return
	# A menu embedded while gameplay is running must not delete an open database.
	if GameAPI.session != null or (GameAPI.world != null and GameAPI.world.terrain != null):
		status_label.text = "Close the running game before deleting worlds."
		return
	var result: Dictionary = GameAPI.saves.delete_world(id)
	GameAPI.saves.clear_selection()
	_refresh_worlds("")
	status_label.text = ("World deleted. Select a world to continue." if result.success else str(result.error))

func _create_world() -> void:
	var result: Dictionary = GameAPI.saves.create_world(name_input.text, seed_input.text, {
		"api_version": ModAPI.API_VERSION,
		"mods": GameAPI.mods.get_signature(),
		"content": GameAPI.content.get_content_signature(),
	})
	if not result.success:
		status_label.text = str(result.error)
		return
	_refresh_worlds(str(result.save_name))
	status_label.text = "World created and selected. Click Host Selected World to play."


@onready var host_button: Button = $Center/VBox/Host
@onready var join_button: Button = $Center/VBox/Join
@onready var mods_button: Button = $Center/VBox/Mods
@onready var quit_button: Button = $Center/VBox/Quit
@onready var ip_input: LineEdit = $Center/VBox/IP
@onready var mods_label: Label = $Center/VBox/ModsInfo


func _ready() -> void:
	delete_button.pressed.connect(_request_delete)
	delete_dialog.confirmed.connect(_confirm_delete)
	delete_dialog.canceled.connect(_cancel_delete)
	host_button.pressed.connect(_host)
	join_button.pressed.connect(_join)
	mods_button.pressed.connect(_show_mods)
	quit_button.pressed.connect(_quit)
	world_list.item_selected.connect(_select_world)
	$Center/VBox/Create.pressed.connect(_create_world)
	$Center/VBox/Refresh.pressed.connect(func() -> void: _refresh_worlds(_selected_id))
	_refresh_worlds()


func _host() -> void:
	var config: Dictionary = GameAPI.saves.select_world(_selected_id)
	if not config.valid:
		status_label.text = str(config.error)
		return
	var error := NetworkManager.host_game()
	if error == OK:
		get_tree().change_scene_to_file("res://scenes/main/Game.tscn")
	else:
		push_error("[MainMenu] Failed to host: %s" % error)


func _join() -> void:
	# Existing protocol has no world-identity handshake; keep its default behavior.
	GameAPI.saves.clear_selection()
	var address := ip_input.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"

	var error := NetworkManager.join_game(address)
	if error == OK:
		get_tree().change_scene_to_file("res://scenes/main/Game.tscn")
	else:
		push_error("[MainMenu] Failed to join: %s" % error)


func _show_mods() -> void:
	mods_label.visible = not mods_label.visible
	var lines: Array[String] = []
	for manifest in GameAPI.get_loaded_mods():
		lines.append(
			"%s %s"
			% [str(manifest["name"]), str(manifest["version"])]
		)
	mods_label.text = "Loaded mods:\n" + ("\n".join(lines) if not lines.is_empty() else "None")


func _quit() -> void:
	get_tree().quit()
