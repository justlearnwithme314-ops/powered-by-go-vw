extends Control

@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var mods_button: Button = $CenterContainer/VBoxContainer/ModsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton
@onready var ip_input: LineEdit = $CenterContainer/VBoxContainer/IpInput

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	mods_button.pressed.connect(_on_mods_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_host_pressed() -> void:
	NetworkManager.host_game()
	get_tree().change_scene_to_file("res://scenes/main/Game.tscn")

func _on_join_pressed() -> void:
	var target_ip = ip_input.text.strip_edges()
	if target_ip.is_empty():
		target_ip = "127.0.0.1" # Default to localhost
	NetworkManager.join_game(target_ip)
	get_tree().change_scene_to_file("res://scenes/main/Game.tscn")

func _on_mods_pressed() -> void:
	# Open OS file manager to user mods directory so users can paste files easily
	OS.shell_open(ProjectSettings.globalize_path(ModLoader.MODS_DIR))

func _on_quit_pressed() -> void:
	get_tree().quit()
