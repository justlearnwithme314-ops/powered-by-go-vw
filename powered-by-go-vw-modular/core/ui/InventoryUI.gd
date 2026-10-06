extends CanvasLayer

const SLOT = preload("res://core/ui/InventorySlot.gd")
const DROP_ZONE = preload("res://core/ui/InventoryDropZone.gd")
@onready var hotbar: HBoxContainer = $Hotbar
@onready var inventory_panel: PanelContainer = $InventoryPanel
var inventory: Inventory
var inventory_open := false
var hovered_slot: Control
var _player_spawn_callback: Callable
var slot_panels: Array[PanelContainer] = []
var slot_icons: Array[TextureRect] = []
var slot_counts: Array[Label] = []
var grid_slots: Array[PanelContainer] = []
var equipment_slots: Array[PanelContainer] = []
var recovery_button: Button
var craft_list: ItemList
var arrangement_grid: GridContainer
var arrangement_label: Label
var arrangement_slots: Array[PanelContainer] = []
var _grid_refreshing := false
var hint: Label
var cursor_icon: TextureRect
var cursor_count: Label
var backdrop: ColorRect
var title: Label
var _icon_cache: Dictionary = {}
var _block_icon_map: Dictionary = {}
var repair_button: Button
var _recipe_refresh_timer := 0.0

func _ready() -> void:
	add_to_group("inventory_ui")
	var mappings: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/block_textures/mapping.json"))
	if mappings is Dictionary:
		_block_icon_map = mappings
	_build_inventory()
	_build_hotbar()
	_player_spawn_callback = Callable(self, "_on_player_spawned")
	GameAPI.events.subscribe(GameEvents.PLAYER_SPAWNED, _player_spawn_callback)
	call_deferred("_try_bind_local_inventory")

func _exit_tree() -> void:
	if inventory != null and is_instance_valid(inventory):
		inventory.return_cursor()
		if inventory.changed.is_connected(_refresh):
			inventory.changed.disconnect(_refresh)
	if GameAPI.events != null and _player_spawn_callback.is_valid():
		GameAPI.events.unsubscribe(GameEvents.PLAYER_SPAWNED, _player_spawn_callback)

func _try_bind_local_inventory() -> void:
	for player in get_tree().get_nodes_in_group("player_character"):
		if player.is_multiplayer_authority():
			_bind_player(player)
			return

func _on_player_spawned(event: Dictionary) -> Dictionary:
	var player: Node = event.get("player")
	if player != null and player.is_multiplayer_authority():
		_bind_player(player)
	return event

func _bind_player(player: Node) -> void:
	var next_inventory := player.get_node_or_null("Inventory") as Inventory
	if next_inventory == null or next_inventory == inventory:
		return
	if inventory != null and is_instance_valid(inventory):
		inventory.return_cursor()
		if inventory.changed.is_connected(_refresh):
			inventory.changed.disconnect(_refresh)
	inventory = next_inventory
	inventory.changed.connect(_refresh)
	_refresh()

func _build_inventory() -> void:
	for child in inventory_panel.get_children():
		inventory_panel.remove_child(child)
		child.queue_free()
	backdrop = DROP_ZONE.new()
	backdrop.owner_ui = self
	backdrop.color = Color(0.04, 0.05, 0.07, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)
	inventory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	inventory_panel.offset_left = -520
	inventory_panel.offset_top = -270
	inventory_panel.offset_right = 520
	inventory_panel.offset_bottom = 270
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	inventory_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	title = Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 22)
	left.add_child(title)
	var gear_title := Label.new()
	gear_title.text = "Equipment"
	left.add_child(gear_title)
	var gear := HBoxContainer.new()
	left.add_child(gear)
	for i in range(Inventory.EQUIPMENT_SLOTS.size()):
		var column := VBoxContainer.new()
		gear.add_child(column)
		var slot := _new_slot(column, i, true)
		equipment_slots.append(slot)
		var label := Label.new()
		label.text = str(Inventory.EQUIPMENT_SLOTS[i]).capitalize()
		label.add_theme_font_size_override("font_size", 12)
		column.add_child(label)
	var label := Label.new()
	label.text = "Backpack"
	left.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	grid_slots.resize(Inventory.CAPACITY)
	for i in range(Inventory.HOTBAR_SIZE, Inventory.CAPACITY):
		grid_slots[i] = _new_slot(grid, i)
	label = Label.new()
	label.text = "Hotbar  /  1-9, 0"
	left.add_child(label)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	left.add_child(bar)
	for i in range(Inventory.HOTBAR_SIZE):
		grid_slots[i] = _new_slot(bar, i)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	var organize := Button.new()
	organize.text = "Group & sort"
	organize.pressed.connect(_organize)
	buttons.add_child(organize)
	recovery_button = Button.new()
	recovery_button.pressed.connect(_recover_items)
	buttons.add_child(recovery_button)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): set_open(false))
	buttons.add_child(close)
	hint = Label.new()
	hint.custom_minimum_size.x = 490
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.text = "Drag / left-click: move • Right-click: split / place one\nShift-click: quick transfer • Double-click: gather matching\nQ: drop one • Ctrl+Q: drop stack • E / Esc: close"
	left.add_child(hint)
	var right := VBoxContainer.new()
	row.add_child(right)
	label = Label.new()
	label.text = "Crafting"
	label.add_theme_font_size_override("font_size", 22)
	right.add_child(label)
	arrangement_label = Label.new()
	arrangement_label.text = "Arrange ingredients • Right-click places one"
	right.add_child(arrangement_label)
	var grid_scroll := ScrollContainer.new()
	grid_scroll.custom_minimum_size = Vector2(340,205)
	right.add_child(grid_scroll)
	arrangement_grid = GridContainer.new()
	grid_scroll.add_child(arrangement_grid)
	craft_list = ItemList.new()
	craft_list.custom_minimum_size = Vector2(340, 165)
	craft_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_list.fixed_icon_size = Vector2i(24, 24)
	craft_list.item_selected.connect(_on_recipe_selected)
	right.add_child(craft_list)
	label = Label.new()
	label.text = "Arrange ingredients above, then click an output."
	right.add_child(label)
	repair_button = Button.new()
	repair_button.text = "Repair held tool"
	repair_button.pressed.connect(_repair_selected)
	right.add_child(repair_button)
	cursor_icon = TextureRect.new()
	cursor_icon.size = Vector2(42, 42)
	cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cursor_icon)
	cursor_count = Label.new()
	cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cursor_count)
	inventory_panel.hide()
	backdrop.hide()

func _new_slot(parent: Node, index: int, equipped: bool = false) -> PanelContainer:
	var slot: PanelContainer = SLOT.new()
	slot.owner_ui = self
	slot.index = index
	slot.equipped = equipped
	parent.add_child(slot)
	return slot

func _build_hotbar() -> void:
	for child in hotbar.get_children():
		hotbar.remove_child(child)
		child.queue_free()
	for i in range(Inventory.HOTBAR_SIZE):
		var panel := _new_slot(hotbar, i)
		panel.custom_minimum_size = Vector2(70, 70)
		slot_panels.append(panel)
		slot_icons.append(panel.icon)
		slot_counts.append(panel.count_label)

func _input(event: InputEvent) -> void:
	if is_instance_valid(inventory) and bool(inventory.get_parent().get_meta("gameplay_disabled", false)):
		return
	if event.is_action_pressed("inventory_toggle") and not event.is_echo():
		set_open(not inventory_open)
		get_viewport().set_input_as_handled()
		return
	if inventory_open and event.is_action_pressed("ui_cancel"):
		set_open(false)
		get_viewport().set_input_as_handled()
		return
	if inventory == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			var player := inventory.get_parent() as CharacterBody3D
			var result: Dictionary = GameAPI.session.get_node("InventoryDrops").pickup_nearest(player)
			if not bool(result.get("success", false)):
				hint.text = str(result.get("reason", "Nothing to pick up."))
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Q and (inventory_open or Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED):
			if inventory_open and not inventory.cursor.stack_at(0).is_empty():
				drop_held(not event.ctrl_pressed)
			else:
				var index := inventory.selected_slot
				if inventory_open and hovered_slot != null and not hovered_slot.equipped:
					index = hovered_slot.index
				_drop(false, index, 2147483647 if event.ctrl_pressed else 1)
			get_viewport().set_input_as_handled()
		elif inventory_open and event.keycode >= KEY_0 and event.keycode <= KEY_9 and hovered_slot != null and not hovered_slot.equipped:
			inventory.move_stack(hovered_slot.index, 9 if event.keycode == KEY_0 else event.keycode - KEY_1)
			get_viewport().set_input_as_handled()

func set_open(value: bool) -> void:
	inventory_open = value
	inventory_panel.visible = value
	backdrop.visible = value
	hotbar.visible = not value
	if not value and inventory != null:
		if GameAPI.crafting.grid_service != null:
			GameAPI.inventory_commands.request(inventory.get_parent(),"grid_return")
		inventory.return_cursor()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED)
	_refresh()

func slot_clicked(index: int, equipped: bool, right: bool, quick: bool, gather: bool) -> void:
	if inventory == null or not inventory_open:
		return
	if quick:
		if not equipped:
			inventory.quick_transfer(index)
		else:
			for i in range(Inventory.CAPACITY):
				if inventory.get_slot(i).is_empty():
					inventory.unequip(index, i)
					break
	elif gather and not right:
		if inventory.cursor.stack_at(0).is_empty():
			inventory.click_slot(index, false, equipped)
		inventory.collect_matching()
	else:
		inventory.click_slot(index, right, equipped)
	_refresh()

func _process(_delta: float) -> void:
	if inventory_open and inventory != null:
		_recipe_refresh_timer += _delta
		if _recipe_refresh_timer >= 0.5:
			_recipe_refresh_timer = 0.0
			_refresh_recipes()
	var held := inventory.cursor.stack_at(0) if inventory != null else {}
	cursor_icon.visible = inventory_open and not held.is_empty()
	cursor_count.visible = cursor_icon.visible
	if cursor_icon.visible:
		cursor_icon.position = get_viewport().get_mouse_position() - Vector2(20, 20)
		cursor_count.position = cursor_icon.position + Vector2(28, 24)
		cursor_icon.texture = _get_item_icon(str(held.id))
		cursor_count.text = str(held.count)

func drop_held(one: bool) -> void:
	if inventory != null and not inventory.cursor.stack_at(0).is_empty():
		_drop(true, 0, 1 if one else 2147483647)

func _drop(held: bool, index: int, amount: int) -> void:
	if GameAPI.session == null or not GameAPI.session.has_node("InventoryDrops"):
		hint.text = "Dropping is available while playing a world."
		return
	var result: Dictionary = GameAPI.session.get_node("InventoryDrops").drop_stack(inventory, held, index, amount)
	if not bool(result.get("success", false)):
		hint.text = str(result.get("reason", "Cannot drop here."))

func _refresh() -> void:
	if inventory == null:
		return
	for i in range(Inventory.HOTBAR_SIZE):
		var stack := inventory.get_slot(i)
		slot_icons[i].texture = _get_item_icon(str(stack.get("id", "")))
		slot_counts[i].text = "x%d" % int(stack.count) if not stack.is_empty() else ""
		slot_panels[i].modulate = Color(1.0, 1.0, 0.65) if i == inventory.selected_slot else Color.WHITE
	for i in range(Inventory.CAPACITY):
		_update_slot(grid_slots[i], inventory.get_slot(i))
	for i in range(equipment_slots.size()):
		_update_slot(equipment_slots[i], inventory.equipment.stack_at(i))
	recovery_button.visible = not inventory.recovery.is_empty()
	recovery_button.text = "Recover (%d)" % inventory.recovery.size()
	title.text = "Inventory  %d / %d" % [inventory.items.size(), Inventory.CAPACITY]
	var quote := GameAPI.item_instances.repair_quote(inventory.get_slot(inventory.selected_slot))
	repair_button.visible = bool(quote.allowed)
	if bool(quote.allowed):
		repair_button.text = "Repair held tool — %s x%d" % [GameAPI.content.get_item_display_name(str(quote.material)), int(quote.count)]
		repair_button.tooltip_text = "Restores condition at the required repair station."
	if inventory_open:
		_refresh_recipes()

func _update_slot(slot: PanelContainer, stack: Dictionary) -> void:
	var id := str(stack.get("id", ""))
	slot.icon.texture = _get_item_icon(id)
	slot.count_label.text = str(stack.count) if not stack.is_empty() and int(stack.count) > 1 else ""
	slot.tooltip_text = GameAPI.content.get_item_display_name(id) if not id.is_empty() else "Empty slot"
	var maximum := GameAPI.item_instances.maximum(stack)
	slot.condition_bar.visible = maximum > 0
	if maximum > 0:
		slot.condition_bar.max_value = maximum
		slot.condition_bar.value = GameAPI.item_instances.condition(stack)
		slot.tooltip_text += "\nCondition %d / %d%s" % [int(slot.condition_bar.value), maximum, " — Broken" if slot.condition_bar.value == 0 else ""]
		var modifier_names: Array[String] = []
		for modifier in stack.get("metadata", {}).get("modifiers", []):
			modifier_names.append(str(modifier).get_slice(":", 1).capitalize())
		if not modifier_names.is_empty():
			slot.tooltip_text += "\n" + ", ".join(modifier_names)
	elif not stack.get("metadata", {}).is_empty():
		slot.tooltip_text += "\n" + JSON.stringify(stack.metadata)

func _get_item_icon(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var item: Dictionary = GameAPI.content.get_item(item_id)
	var icon_path: String = str(item.get("icon", ""))

	if icon_path.is_empty():
		var block_id := GameAPI.content.get_placement_block(item_id)
		var model: Resource = GameAPI.content.get_block(block_id).get("model")
		if model != null:
			var mapping: Dictionary = _block_icon_map.get(model.resource_path.trim_prefix("res://"), {})
			if not mapping.is_empty():
				icon_path = "res://assets/minecraft-inspired-textures-free/block/%s.png" % str(mapping.side)
		if icon_path.is_empty() and not item_id.is_empty():
			var candidate := "res://assets/minecraft-inspired-textures-free/item/%s.png" % item_id.get_slice(":", 1)
			if ResourceLoader.exists(candidate):
				icon_path = candidate
		if icon_path.is_empty():
			return null

	var resource: Resource = ResourceLoader.load(icon_path)

	if resource is Texture2D:
		var texture := resource as Texture2D
		if texture.get_height() > texture.get_width():
			var frame := AtlasTexture.new()
			frame.atlas = texture
			frame.region = Rect2(0, 0, texture.get_width(), texture.get_width())
			texture = frame
		_icon_cache[item_id] = texture
		return texture

	if FileAccess.file_exists(icon_path):
		var image: Image = Image.load_from_file(icon_path)
		if image != null:
			return ImageTexture.create_from_image(image)

	return null


func _refresh_recipes() -> void:
	if _grid_refreshing:
		return
	_grid_refreshing = true
	craft_list.clear()

	var recipe_ids: Array[String] = GameAPI.content.get_recipe_ids()
	if GameAPI.crafting.grid_service != null:
		var desired: Vector2i = GameAPI.crafting.grid_service.call("dimensions",inventory.get_parent())
		if desired != Vector2i(inventory.crafting_width,inventory.crafting_height):
			GameAPI.inventory_commands.request(inventory.get_parent(),"grid_resize")
		arrangement_label.text = "%d × %d grid • Right-click places one" % [inventory.crafting_width,inventory.crafting_height]
		arrangement_grid.columns = inventory.crafting_width
		if arrangement_slots.size() != inventory.crafting_grid.size():
			for slot in arrangement_slots:
				slot.free()
			arrangement_slots.clear()
			for i in range(inventory.crafting_grid.size()):
				var slot := load("res://core/ui/CraftingGridSlot.gd").new() as PanelContainer
				slot.owner_ui = self
				slot.index = i
				slot.equipped = true
				arrangement_grid.add_child(slot)
				arrangement_slots.append(slot)
		for i in range(arrangement_slots.size()):
			_update_slot(arrangement_slots[i],inventory.crafting_grid.stack_at(i))
		recipe_ids.assign(GameAPI.crafting.grid_service.call("matches",inventory))

	for recipe_id: String in recipe_ids:
		if GameAPI.crafting.grid_service == null and not GameAPI.crafting.can_craft(inventory, recipe_id):
			continue
		var recipe: Dictionary = GameAPI.content.get_recipe(recipe_id)
		var parts: Array[String] = []

		for item_id: String in recipe["ingredients"]:
			parts.append(
				"%s x%d" % [
					GameAPI.content.get_item_display_name(item_id),
					int(recipe["ingredients"][item_id]),
				]
			)

		var can_craft: bool = GameAPI.crafting.grid_service != null or GameAPI.crafting.can_craft(inventory,recipe_id)

		var output_id: String = str(recipe["output"])

		craft_list.add_item(
			"%s -> %s x%d%s" % [
				" + ".join(parts),
				GameAPI.content.get_item_display_name(output_id),
				int(recipe["count"]),
				"" if can_craft else "  [%s]" % (GameAPI.crafting.requirement(inventory, recipe_id) if not GameAPI.crafting.requirement(inventory, recipe_id).is_empty() else "missing items/space"),
			],
			_get_item_icon(output_id)
		)
		craft_list.set_item_tooltip(craft_list.item_count - 1, "%s\n%s" % [GameAPI.content.get_item_display_name(output_id), "\n".join(parts)])
		craft_list.set_item_metadata(craft_list.item_count - 1, recipe_id)
	_grid_refreshing = false

func grid_clicked(index: int, right: bool) -> void:
	if inventory != null:
		GameAPI.inventory_commands.request(inventory.get_parent(),"grid_click",{"index":index,"right":right})
		_refresh()


func _on_recipe_selected(index: int) -> void:
	if inventory == null:
		return

	if index < 0 or index >= craft_list.item_count:
		return

	var recipe_id: String = str(craft_list.get_item_metadata(index))
	var player: Node = inventory.get_parent() as Node
	var result: Dictionary = GameAPI.inventory_commands.request(player, "grid_craft" if GameAPI.crafting.grid_service != null else "craft", {"recipe_id": recipe_id})

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



func _recover_items() -> void:
	if inventory != null:
		var added := inventory.recover_available()
		hint.text = "Recovered %d items. Free slots are needed for remaining stacks." % added
		_refresh()

func _organize() -> void:
	if inventory != null:
		inventory.organize_backpack()

func _repair_selected() -> void:
	if inventory == null:
		return
	var result := GameAPI.inventory_commands.request(inventory.get_parent(), "repair", {"index": inventory.selected_slot})
	hint.text = "Tool repaired." if bool(result.get("success", false)) else str(result.get("reason", "Repair failed"))
	if result.has("persisted") and not bool(result.persisted):
		hint.text = "Repair completed, but saving failed; previous saved state retained."
	_refresh()
