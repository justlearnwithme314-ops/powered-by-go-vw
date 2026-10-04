extends Node

func _ready() -> void:
	var suite: Node = load("res://tests/WorldSaves.gd").new()
	add_child(suite)
	var count: int = 0
	for method: Dictionary in suite.get_method_list():
		if str(method.name).begins_with("test_"):
			suite.call(method.name)
			count += 1
	print("World save suite completed: ", count, " tests (isolated fixtures only)")
	get_tree().quit()
