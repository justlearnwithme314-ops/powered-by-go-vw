extends Control

# Buttons
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var mods_button: Button = $CenterContainer/VBoxContainer/ModsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

# IP input field
@onready var ip_input: LineEdit = $CenterContainer/VBoxContainer/IpInput


func _ready() -> void:

	if host_button:
		host_button.pressed.connect(_on_host_button_pressed)

	if join_button:
		join_button.pressed.connect(_on_join_button_pressed)

	if mods_button:
		mods_button.pressed.connect(_on_mods_button_pressed)

	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)


func _on_host_button_pressed() -> void:

	var error := NetworkManager.host_game()

	if error == OK:
		print("[Menu] Hosting server.")
		get_tree().change_scene_to_file(
			"res://scenes/main/Game.tscn"
		)
	else:
		push_error(
			"[Menu] Failed to host server. Error: %s" % error
		)


func _on_join_button_pressed() -> void:

	var address := ip_input.text.strip_edges()

	if address.is_empty():
		address = "127.0.0.1"

	var error := NetworkManager.join_game(address)

	if error == OK:
		print("[Menu] Joining server: ", address)

		get_tree().change_scene_to_file(
			"res://scenes/main/Game.tscn"
		)
	else:
		push_error(
			"[Menu] Failed to join server. Error: %s" % error
		)


func _on_mods_button_pressed() -> void:
	print("[Menu] Mods button pressed.")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
