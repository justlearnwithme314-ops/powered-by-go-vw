extends Control

# Grab references to all the buttons in your VBoxContainer
@onready var host_button: Button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/JoinButton
@onready var mods_button: Button = $CenterContainer/VBoxContainer/ModsButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/QuitButton

func _ready() -> void:
	# Wire up all signals entirely in code. No editor connections needed!
	if host_button:
		host_button.pressed.connect(_on_host_button_pressed)
	
	if join_button:
		join_button.pressed.connect(_on_join_button_pressed)
		
	if mods_button:
		mods_button.pressed.connect(_on_mods_button_pressed)
		
	if quit_button:
		quit_button.pressed.connect(_on_quit_button_pressed)

func _on_host_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Game.tscn")

func _on_join_button_pressed() -> void:
	# TODO: Add your logic for joining a game here
	print("Join button pressed!")

func _on_mods_button_pressed() -> void:
	# TODO: Add your logic for the mods menu here
	print("Mods button pressed!")

func _on_quit_button_pressed() -> void:
	# Safely closes the game
	get_tree().quit()
