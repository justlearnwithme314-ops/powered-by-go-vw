extends Node

@onready var network_manager: Node = $NetworkManager


func _ready() -> void:
	var args := OS.get_cmdline_user_args()

	if "--server" in args:
		print("Running in SERVER mode")
		network_manager.start_server()
	else:
		print("Running in CLIENT mode")
		network_manager.start_client("26.127.142.160")
