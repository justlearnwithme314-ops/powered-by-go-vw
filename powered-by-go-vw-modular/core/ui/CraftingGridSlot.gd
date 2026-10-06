extends "InventorySlot.gd"

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and owner_ui.inventory_open and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		owner_ui.grid_clicked(index,event.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()

func _drop_data(_position: Vector2, _data: Variant) -> void:
	owner_ui.grid_clicked(index,false)
