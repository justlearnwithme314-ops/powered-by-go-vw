extends CanvasLayer

@onready var inventory: Inventory = get_node_or_null("/root/Game/Players/Player/Inventory")

@onready var labels: Array = [
	$MarginContainer/HBoxContainer/Slot1,
	$MarginContainer/HBoxContainer/Slot2,
	$MarginContainer/HBoxContainer/Slot3,
	$MarginContainer/HBoxContainer/Slot4
]

var block_names := {
	Block.AIR: "Empty",
	Block.GRASS: "Grass",
	Block.DIRT: "Dirt",
	Block.STONE: "Stone",
	Block.LOG: "Wood",
	Block.LEAVES: "Leaves",
	Block.IRON: "Iron Ore",
	Block.COAL: "Coal Ore",
	Block.GOLD: "Gold Ore",
	Block.DIAMOND: "Diamond Ore",
	Block.SAND: "Sand",
	Block.SANDSTONE: "Sandstone",
	Block.WATER: "Water",
	Block.SNOW: "Snow",
	Block.GRAVEL: "Gravel",
	Block.BEDROCK: "Bedrock",
	Block.FLOWER_RED: "Red Flower",
	Block.FLOWER_YELLOW: "Yellow Flower",
	Block.TALL_GRASS: "Tall Grass",
	Block.CACTUS: "Cactus",
	Block.ICE: "Ice"
}


func _ready() -> void:
	await get_tree().create_timer(0.5).timeout

	var my_id := multiplayer.get_unique_id()
	inventory = get_node_or_null("/root/Game/Players/" + str(my_id) + "/Inventory")

	if inventory == null:
		push_warning("[InventoryUI] Could not find local player inventory.")
		return

	inventory.ensure_initialized()

	if inventory.changed.is_connected(update_ui) == false:
		inventory.changed.connect(update_ui)

	update_ui()

func update_ui() -> void:
	if inventory == null:
		return

	inventory.ensure_initialized()

	for i in range(labels.size()):

		if i >= inventory.slots.size():
			labels[i].text = "Empty"
			labels[i].modulate = Color.WHITE
			continue

		var slot = inventory.slots[i]

		if slot.id == Block.AIR:
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
