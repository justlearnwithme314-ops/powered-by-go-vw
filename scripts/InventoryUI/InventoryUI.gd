extends CanvasLayer


# ============================================================
# INVENTORY
# ============================================================

@onready var inventory: Inventory = null


# ============================================================
# HOTBAR UI
# ============================================================

@onready var labels: Array[Label] = [
	$MarginContainer/HBoxContainer/Slot1,
	$MarginContainer/HBoxContainer/Slot2,
	$MarginContainer/HBoxContainer/Slot3,
	$MarginContainer/HBoxContainer/Slot4
]


# ============================================================
# INVENTORY UI
# ============================================================

@onready var inventory_panel: Control = $InventoryPanel

@onready var item_list: ItemList = (
	$InventoryPanel/MarginContainer/VBoxContainer/ItemList
)

@onready var hint_label: Label = (
	$InventoryPanel/MarginContainer/VBoxContainer/Hint
)


# ============================================================
# CRAFTING UI
# ============================================================

var craft_list: ItemList = null


# ============================================================
# STATE
# ============================================================

var inventory_open: bool = false

# -1 means no item is currently selected.
var selected_inventory_item: int = Inventory.EMPTY_ITEM_ID


# ============================================================
# ITEM IDS
# ============================================================
#
# Blocks use Block.* IDs.
#
# Normal items/tools use their own IDs.
#
# For the MVP:
#
# 1000 = Stick
#
# Later this can become:
#
# Item.STICK
#
# ============================================================

const STICK_ID: int = 1000


# ============================================================
# BLOCK NAMES
# ============================================================

var block_names: Dictionary = {
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


# ============================================================
# ITEM / TOOL NAMES
# ============================================================

var item_names: Dictionary = {
	STICK_ID: "Stick"
}


# ============================================================
# READY
# ============================================================

func _ready() -> void:

	# Inventory starts closed.
	inventory_panel.visible = false


	# --------------------------------------------------------
	# FIND CRAFT LIST
	# --------------------------------------------------------

	var craft_list_node: Node = get_node_or_null(
		"InventoryPanel/MarginContainer/VBoxContainer/CraftList"
	)

	if craft_list_node is ItemList:
		craft_list = craft_list_node as ItemList


	# --------------------------------------------------------
	# WAIT FOR PLAYER TO EXIST
	# --------------------------------------------------------

	await get_tree().create_timer(0.5).timeout


	# --------------------------------------------------------
	# FIND LOCAL PLAYER INVENTORY
	# --------------------------------------------------------

	var my_id: int = multiplayer.get_unique_id()

	inventory = get_node_or_null(
		"/root/Game/Players/" + str(my_id) + "/Inventory"
	) as Inventory


	if inventory == null:

		push_warning(
			"[InventoryUI] Could not find local player inventory."
		)

		return


	# --------------------------------------------------------
	# INITIALIZE INVENTORY
	# --------------------------------------------------------

	inventory.ensure_initialized()


	# --------------------------------------------------------
	# INVENTORY CHANGED SIGNAL
	# --------------------------------------------------------

	if not inventory.changed.is_connected(update_ui):

		inventory.changed.connect(update_ui)


	# --------------------------------------------------------
	# INVENTORY ITEM CLICK
	# --------------------------------------------------------

	if not item_list.item_selected.is_connected(
		_on_item_selected
	):

		item_list.item_selected.connect(
			_on_item_selected
	)


	# --------------------------------------------------------
	# CRAFTING ITEM CLICK
	# --------------------------------------------------------

	if craft_list != null:

		if not craft_list.item_selected.is_connected(
			_on_craft_selected
		):

			craft_list.item_selected.connect(
				_on_craft_selected
			)


	# --------------------------------------------------------
	# INITIAL UI UPDATE
	# --------------------------------------------------------

	update_ui()


# ============================================================
# INPUT
# ============================================================

func _unhandled_input(event: InputEvent) -> void:

	# --------------------------------------------------------
	# OPEN / CLOSE INVENTORY
	# --------------------------------------------------------

	if event.is_action_pressed("inventory_toggle"):

		toggle_inventory()

		return


	# --------------------------------------------------------
	# INVENTORY CLOSED
	# --------------------------------------------------------

	if not inventory_open:

		return


	# --------------------------------------------------------
	# NOTHING SELECTED
	# --------------------------------------------------------

	if selected_inventory_item == Inventory.EMPTY_ITEM_ID:

		return


	# --------------------------------------------------------
	# HOTBAR 1
	# --------------------------------------------------------

	if event.is_action_pressed("hotbar_1"):

		assign_selected_to_hotbar(0)


	# --------------------------------------------------------
	# HOTBAR 2
	# --------------------------------------------------------

	elif event.is_action_pressed("hotbar_2"):

		assign_selected_to_hotbar(1)


	# --------------------------------------------------------
	# HOTBAR 3
	# --------------------------------------------------------

	elif event.is_action_pressed("hotbar_3"):

		assign_selected_to_hotbar(2)


	# --------------------------------------------------------
	# HOTBAR 4
	# --------------------------------------------------------

	elif event.is_action_pressed("hotbar_4"):

		assign_selected_to_hotbar(3)


# ============================================================
# OPEN / CLOSE INVENTORY
# ============================================================

func toggle_inventory() -> void:

	inventory_open = not inventory_open

	inventory_panel.visible = inventory_open


	if inventory_open:

		# Clear current inventory selection.
		selected_inventory_item = Inventory.EMPTY_ITEM_ID

		hint_label.text = (
			"Click an item, then press 1, 2, 3 or 4"
		)

		refresh_item_list()

		refresh_crafting_list()

	else:

		# Clear selection when closing.
		selected_inventory_item = Inventory.EMPTY_ITEM_ID


# ============================================================
# INVENTORY ITEM SELECTED
# ============================================================

func _on_item_selected(index: int) -> void:

	if inventory == null:

		return


	if index < 0 or index >= inventory.items.size():

		return


	var item: Dictionary = inventory.items[index]


	var item_id: int = int(
		item.get(
			"id",
			Inventory.EMPTY_ITEM_ID
		)
	)


	# Store selected ID.
	selected_inventory_item = item_id


	# Get display name.
	var item_name: String = get_item_name(
		item_id
	)


	hint_label.text = (
		"%s selected - press 1, 2, 3 or 4"
		% item_name
	)


# ============================================================
# ASSIGN ITEM TO HOTBAR
# ============================================================

func assign_selected_to_hotbar(
	slot_index: int
) -> void:

	if inventory == null:

		return


	if selected_inventory_item == Inventory.EMPTY_ITEM_ID:

		return


	var success: bool = inventory.assign_to_hotbar(
		selected_inventory_item,
		slot_index
	)


	if not success:

		hint_label.text = (
			"Could not assign item to hotbar."
		)

		return


	var item_name: String = get_item_name(
		selected_inventory_item
	)


	hint_label.text = (
		"%s assigned to slot %d"
		% [
			item_name,
			slot_index + 1
		]
	)


	update_ui()


# ============================================================
# GET ITEM NAME
# ============================================================
#
# The inventory itself does NOT care whether something is:
#
# - Grass
# - Wood
# - Stone
# - Stick
# - Pickaxe
# - Axe
# - Sword
#
# It only stores an integer ID.
#
# This function translates that ID into a name.
#
# ============================================================

func get_item_name(item_id: int) -> String:

	# First check normal items/tools.
	if item_names.has(item_id):

		return str(
			item_names[item_id]
		)


	# Then check blocks.
	if block_names.has(item_id):

		return str(
			block_names[item_id]
		)


	return "Unknown"


# ============================================================
# REFRESH INVENTORY LIST
# ============================================================

func refresh_item_list() -> void:

	if inventory == null:

		return


	item_list.clear()


	for item: Dictionary in inventory.items:

		var item_id: int = int(
			item.get(
				"id",
				Inventory.EMPTY_ITEM_ID
			)
		)


		var count: int = int(
			item.get(
				"count",
				0
			)
		)


		var item_name: String = get_item_name(
			item_id
		)


		item_list.add_item(
			"%s    x%d"
			% [
				item_name,
				count
			]
		)


# ============================================================
# REFRESH CRAFTING LIST
# ============================================================

func refresh_crafting_list() -> void:

	if craft_list == null:

		return


	if inventory == null:

		return


	craft_list.clear()


	# ========================================================
	# STICK RECIPE
	# ========================================================
	#
	# 2 Wood -> 4 Stick
	#
	# Wood:
	#
	# Block.LOG
	#
	# Stick:
	#
	# STICK_ID
	#
	# ========================================================

	var wood_count: int = inventory.get_item_count(
		Block.LOG
	)


	if wood_count >= 2:

		craft_list.add_item(
			"Stick    2 Wood -> 4 Stick"
		)

	else:

		craft_list.add_item(
			"Stick    2 Wood -> 4 Stick    [Need Wood]"
		)


# ============================================================
# CRAFTING ITEM SELECTED
# ============================================================

func _on_craft_selected(index: int) -> void:

	if inventory == null:

		return


	# We currently have only one recipe.
	if index != 0:

		return


	# ========================================================
	# CHECK WOOD
	# ========================================================

	var wood_count: int = inventory.get_item_count(
		Block.LOG
	)


	if wood_count < 2:

		hint_label.text = (
			"Not enough Wood! Need 2 Wood."
		)

		return


	# ========================================================
	# REMOVE WOOD
	# ========================================================

	var removed: bool = inventory.remove_item(
		Block.LOG,
		2
	)


	if not removed:

		hint_label.text = (
			"Could not craft Stick."
		)

		return


	# ========================================================
	# ADD STICKS
	# ========================================================

	inventory.add_item(
		STICK_ID,
		4
	)


	# ========================================================
	# MESSAGE
	# ========================================================

	hint_label.text = (
		"Crafted 4 Sticks!"
	)


	# ========================================================
	# REFRESH
	# ========================================================

	refresh_item_list()

	refresh_crafting_list()

	update_ui()


# ============================================================
# UPDATE EVERYTHING
# ============================================================

func update_ui() -> void:

	if inventory == null:

		return


	inventory.ensure_initialized()


	# ========================================================
	# HOTBAR
	# ========================================================

	for i in range(labels.size()):


		# ----------------------------------------------------
		# SAFETY CHECK
		# ----------------------------------------------------

		if i >= inventory.hotbar.size():

			labels[i].text = "Empty"

			labels[i].modulate = Color.WHITE

			continue


		# ----------------------------------------------------
		# GET ITEM ID
		# ----------------------------------------------------

		var item_id: int = inventory.hotbar[i]


		# ----------------------------------------------------
		# EMPTY SLOT
		# ----------------------------------------------------

		if item_id == Inventory.EMPTY_ITEM_ID:

			labels[i].text = "Empty"


		# ----------------------------------------------------
		# ITEM / BLOCK / TOOL
		# ----------------------------------------------------

		else:

			var count: int = inventory.get_item_count(
				item_id
			)


			var item_name: String = get_item_name(
				item_id
			)


			labels[i].text = (
				"%s\nx%d"
				% [
					item_name,
					count
				]
			)


		# ----------------------------------------------------
		# SELECTED HOTBAR SLOT
		# ----------------------------------------------------

		if i == inventory.selected_slot:

			labels[i].modulate = Color.YELLOW

		else:

			labels[i].modulate = Color.WHITE


	# ========================================================
	# FULL INVENTORY
	# ========================================================

	if inventory_open:

		refresh_item_list()

		refresh_crafting_list()
