extends ColorRect

var owner_ui: CanvasLayer

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		owner_ui.drop_held(event.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("inventory_owner", 0) == owner_ui.get_instance_id()

func _drop_data(_position: Vector2, _data: Variant) -> void:
	owner_ui.drop_held(false)
