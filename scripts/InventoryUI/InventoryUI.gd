extends CanvasLayer

@onready var inventory: Inventory = get_node("/root/Game/Players/Player/Inventory")

@onready var labels = [
	$MarginContainer/HBoxContainer/Slot1,
	$MarginContainer/HBoxContainer/Slot2,
	$MarginContainer/HBoxContainer/Slot3,
	$MarginContainer/HBoxContainer/Slot4
]

var block_names := {
	0: "Empty",
	1: "Grass",
	2: "Dirt",
	3: "Stone",
	4: "Wood",
	5: "Leaves",
	6: "Iron Ore",
	7: "Coal Ore",
	8: "Gold Ore",
	9: "Diamond Ore",
	10: "Sand",
	11: "Sandstone",
	12: "Water",
	13: "Snow",
	14: "Gravel",
	15: "Bedrock"
}

func _process(_delta: float) -> void:
	if inventory == null:
		return

	for i in range(4):
		var slot = inventory.slots[i]

		if slot.id == 0:
			labels[i].text = "Empty"
		else:
			labels[i].text = "%s\nx%d" % [
				block_names.get(slot.id, "Unknown"),
				slot.count
			]

		if i == inventory.selected_slot:
			labels[i].modulate = Color.YELLOW
		else:
			labels[i].modulate = Color.WHITE
