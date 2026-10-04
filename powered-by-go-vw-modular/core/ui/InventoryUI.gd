extends CanvasLayer

## Inventory presentation with a real icon-based hotbar.
## Gameplay mutations still belong to Inventory/CraftingService.

@onready var hotbar: HBoxContainer = $Hotbar
@onready var inventory_panel: PanelContainer = $InventoryPanel
@onready var item_list: ItemList = $InventoryPanel/Box/ItemList
@onready var craft_list: ItemList = $InventoryPanel/Box/CraftList
@onready var hint: Label = $InventoryPanel/Box/Hint

var inventory: Inventory
var inventory_open: bool = false
var selected_inventory_item: String = Inventory.EMPTY_ITEM_ID
var _player_spawn_callback: Callable

var slot_panels: Array[PanelContainer] = []
var slot_icons: Array[TextureRect] = []
var slot_counts: Array[Label] = []
var slot_numbers: Array[Label] = []


func _ready() -> void:
	inventory_panel.visible = false
	_rebuild_hotbar()

	_player_spawn_callback = Callable(self, "_on_player_spawned")
	GameAPI.events.subscribe(
		GameEvents.PLAYER_SPAWNED,
		_player_spawn_callback
	)

	if not item_list.item_selected.is_connected(_on_item_selected):
		item_list.item_selected.connect(_on_item_selected)

	if not craft_list.item_selected.is_connected(_on_recipe_selected):
		craft_list.item_selected.connect(_on_recipe_selected)

	call_deferred("_try_bind_local_inventory")


func _exit_tree() -> void:
	if GameAPI.events != null and _player_spawn_callback.is_valid():
		GameAPI.events.unsubscribe(
			GameEvents.PLAYER_SPAWNED,
			_player_spawn_callback
		)

	if inventory != null and inventory.changed.is_connected(_refresh):
		inventory.changed.disconnect(_refresh)


func _try_bind_local_inventory() -> void:
	for player_node: Node in get_tree().get_nodes_in_group("player_character"):
		if player_node is CharacterBody3D:
			var player: CharacterBody3D = player_node as CharacterBody3D
			if player.is_multiplayer_authority():
				_bind_player(player)
				return


func _on_player_spawned(event: Dictionary) -> Dictionary:
	var player: CharacterBody3D = event.get("player") as CharacterBody3D

	if player != null and player.is_multiplayer_authority():
		_bind_player(player)

	return event


func _bind_player(player: CharacterBody3D) -> void:
	var next_inventory: Inventory = (
		player.get_node_or_null("Inventory") as Inventory
	)

	if next_inventory == null or next_inventory == inventory:
		return

	if inventory != null and inventory.changed.is_connected(_refresh):
		inventory.changed.disconnect(_refresh)

	inventory = next_inventory
	inventory.changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_toggle"):
		inventory_open = not inventory_open
		inventory_panel.visible = inventory_open
		selected_inventory_item = Inventory.EMPTY_ITEM_ID

		if inventory_open:
			hint.text = "Select an item, then press 1-8."
			_refresh()
		return

	if not inventory_open or inventory == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_8:
			var slot: int = event.keycode - KEY_1

			if not selected_inventory_item.is_empty():
				inventory.assign_to_hotbar(
					selected_inventory_item,
					slot
				)


func _rebuild_hotbar() -> void:
	for child: Node in hotbar.get_children():
		child.queue_free()

	slot_panels.clear()
	slot_icons.clear()
	slot_counts.clear()
	slot_numbers.clear()

	for i: int in range(Inventory.HOTBAR_SIZE):
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size = Vector2(72.0, 72.0)
		hotbar.add_child(panel)
		slot_panels.append(panel)

		var box: VBoxContainer = VBoxContainer.new()
		panel.add_child(box)

		var number: Label = Label.new()
		number.text = str(i + 1)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(number)
		slot_numbers.append(number)

		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(52.0, 42.0)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		box.add_child(icon)
		slot_icons.append(icon)

		var count: Label = Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(count)
		slot_counts.append(count)


func _get_item_icon(item_id: String) -> Texture2D:
	var item: Dictionary = GameAPI.content.get_item(item_id)
	var icon_path: String = str(item.get("icon", ""))

	if icon_path.is_empty():
		return null

	var resource: Resource = ResourceLoader.load(icon_path)

	if resource is Texture2D:
		return resource as Texture2D

	if FileAccess.file_exists(icon_path):
		var image: Image = Image.load_from_file(icon_path)
		if image != null:
			return ImageTexture.create_from_image(image)

	return null


func _refresh() -> void:
	if inventory == null:
		return

	for i: int in range(Inventory.HOTBAR_SIZE):
		var item_id: String = inventory.hotbar[i]
		var selected: bool = i == inventory.selected_slot

		slot_panels[i].modulate = (
			Color(1.0, 1.0, 0.62)
			if selected
			else Color.WHITE
		)

		if item_id.is_empty():
			slot_icons[i].texture = null
			slot_counts[i].text = ""
		else:
			slot_icons[i].texture = _get_item_icon(item_id)
			slot_counts[i].text = "x%d" % inventory.get_item_count(item_id)

	if not inventory_open:
		return

	item_list.clear()

	for stack: Dictionary in inventory.items:
		var item_id: String = str(stack.get("id", ""))

		item_list.add_item(
			"%s    x%d" % [
				GameAPI.content.get_item_display_name(item_id),
				int(stack.get("count", 0)),
			],
			_get_item_icon(item_id)
		)

	_refresh_recipes()


func _refresh_recipes() -> void:
	craft_list.clear()

	var recipe_ids: Array[String] = GameAPI.content.get_recipe_ids()

	for recipe_id: String in recipe_ids:
		var recipe: Dictionary = GameAPI.content.get_recipe(recipe_id)
		var parts: Array[String] = []

		for item_id: String in recipe["ingredients"]:
			parts.append(
				"%s x%d" % [
					GameAPI.content.get_item_display_name(item_id),
					int(recipe["ingredients"][item_id]),
				]
			)

		var can_craft: bool = GameAPI.crafting.can_craft(
			inventory,
			recipe_id
		)

		var output_id: String = str(recipe["output"])

		craft_list.add_item(
			"%s -> %s x%d%s" % [
				" + ".join(parts),
				GameAPI.content.get_item_display_name(output_id),
				int(recipe["count"]),
				"" if can_craft else "  [missing]",
			],
			_get_item_icon(output_id)
		)


func _on_item_selected(index: int) -> void:
	if inventory == null:
		return

	if index < 0 or index >= inventory.items.size():
		return

	selected_inventory_item = str(
		inventory.items[index].get("id", "")
	)

	hint.text = (
		"%s selected - press 1-8."
		% GameAPI.content.get_item_display_name(
			selected_inventory_item
		)
	)


func _on_recipe_selected(index: int) -> void:
	if inventory == null:
		return

	var recipe_ids: Array[String] = GameAPI.content.get_recipe_ids()

	if index < 0 or index >= recipe_ids.size():
		return

	var recipe_id: String = recipe_ids[index]
	var player: Node = inventory.get_parent() as Node
	var result: Dictionary = GameAPI.crafting.craft(
		player,
		inventory,
		recipe_id
	)

	if not bool(result.get("success", false)):
		hint.text = str(
			result.get(
				"reason",
				"Crafting failed."
			)
		)
		_refresh()
		return

	hint.text = (
		"Crafted %s."
		% GameAPI.content.get_item_display_name(
			str(result["output"])
		)
	)

	_refresh()
