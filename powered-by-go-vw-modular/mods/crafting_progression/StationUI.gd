extends CanvasLayer

var _api: ModAPI
var _player: Node3D
var _inventory: Inventory
var _id := ""
var _selected := -1
var _refresh_time := 0.0
var _inventory_buttons: Array[Button] = []
var _station_buttons: Dictionary = {}
var _progress: ProgressBar
var _burn: ProgressBar
var _hint: Label
var _status: Label

func setup(player: Node3D, id: String, api: ModAPI) -> void:
	add_to_group("station_ui")
	_player = player
	_inventory = player.get_node("Inventory") as Inventory
	_api = api
	_id = id
	layer = 40
	_inventory.return_cursor()
	_player.get_tree().call_group("inventory_ui", "set_open", false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.55)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var panel := PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -275
	panel.offset_bottom = 275
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "Furnace"
	heading.add_theme_font_size_override("font_size", 22)
	box.add_child(heading)
	_status = Label.new()
	box.add_child(_status)
	var row := HBoxContainer.new()
	box.add_child(row)
	for container_name in ["input", "fuel", "output"]:
		var column := VBoxContainer.new()
		row.add_child(column)
		var title := Label.new()
		title.text = str(container_name).capitalize()
		column.add_child(title)
		var slots := HBoxContainer.new()
		column.add_child(slots)
		var container := _api.stations.container(_id, container_name)
		var buttons: Array[Button] = []
		for index in range(container.size()):
			var button := _slot_button()
			button.gui_input.connect(_station_clicked.bind(container_name, index))
			slots.add_child(button)
			buttons.append(button)
		_station_buttons[container_name] = buttons
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(0, 14)
	box.add_child(_progress)
	_burn = ProgressBar.new()
	_burn.custom_minimum_size = Vector2(0, 12)
	box.add_child(_burn)
	var inventory_title := Label.new()
	inventory_title.text = "Inventory — select an item, then click an input or fuel slot"
	box.add_child(inventory_title)
	var grid := GridContainer.new()
	grid.columns = 10
	box.add_child(grid)
	for index in range(Inventory.CAPACITY):
		var button := _slot_button()
		button.pressed.connect(_select.bind(index))
		grid.add_child(button)
		_inventory_buttons.append(button)
	_hint = Label.new()
	_hint.text = "Left click transfers a stack; right click transfers one. Click output to collect."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	var close_button := Button.new()
	close_button.text = "Close (Esc)"
	close_button.pressed.connect(close)
	box.add_child(close_button)
	refresh()

func _slot_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(70, 58)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	return button

func _select(index: int) -> void:
	_selected = index if _selected != index else -1
	refresh()

func _station_clicked(event: InputEvent, name: String, index: int) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		return
	var into := _selected >= 0 and name != "output"
	var container := _api.stations.container(_id, name)
	var destination := index
	var source := _selected
	if not into:
		source = index
		destination = -1
		var stack := container.stack_at(index)
		for i in range(Inventory.CAPACITY):
			var existing := _inventory.get_slot(i)
			if _inventory.container.compatible(stack, existing) and int(existing.count) < _inventory.container.limit(stack):
				destination = i
				break
		if destination < 0:
			for i in range(Inventory.CAPACITY):
				if _inventory.get_slot(i).is_empty():
					destination = i
					break
	var result := _api.inventory_commands.request(_player, "station_transfer", {"station": _id, "station_revision": container.revision, "container": name, "into": into, "from": source, "to": destination, "amount": 1 if event.button_index == MOUSE_BUTTON_RIGHT else 2147483647})
	_hint.text = "Transferred." if bool(result.get("success", false)) else str(result.get("reason", "Cannot transfer that item; check slot type and inventory capacity."))
	if result.has("persisted") and not bool(result.persisted):
		_hint.text = "Save failed; previous saved state was retained."
	if into and _inventory.get_slot(_selected).is_empty():
		_selected = -1
	refresh()
	get_viewport().set_input_as_handled()

func _paint(button: Button, stack: Dictionary, prefix: String = "") -> void:
	var definition := _api.content.get_item(str(stack.get("id", "")))
	var icon := str(definition.get("icon", ""))
	if icon.is_empty():
		var fallback: Dictionary = {"core:log": "log", "core:stick": "stick"}
		if fallback.has(str(stack.get("id", ""))):
			icon = _api.asset("textures/%s.png" % fallback[str(stack.id)])
	button.icon = load(icon) as Texture2D if not icon.is_empty() and ResourceLoader.exists(icon) else null
	button.text = prefix + ("x%d" % int(stack.count) if not stack.is_empty() else "—")
	button.tooltip_text = str(definition.get("display_name", "Empty"))

func refresh() -> void:
	if _api == null or _api.stations.record(_id).is_empty():
		return
	for index in range(_inventory_buttons.size()):
		_paint(_inventory_buttons[index], _inventory.get_slot(index), "%d\n" % ((index + 1) % 10) if index < 10 else "")
		_inventory_buttons[index].modulate = Color(1, 0.85, 0.4) if _selected == index else Color.WHITE
	for name in _station_buttons:
		var container := _api.stations.container(_id, name)
		for index in range(container.size()):
			_paint(_station_buttons[name][index], container.stack_at(index))
	var state: Dictionary = _api.stations.record(_id).state
	var recipe := _api.content.get_recipe(str(state.get("recipe", "")))
	_progress.max_value = maxf(float(recipe.get("duration", 8.0)), 0.1)
	_progress.value = float(state.get("progress", 0.0))
	_burn.max_value = maxf(float(state.get("burn_total", 80.0)), 0.1)
	_burn.value = float(state.get("burn", 0.0))
	var recipe_name := _api.content.get_item_display_name(str(recipe.get("output", ""))) if not recipe.is_empty() else ""
	_status.text = "%s %s  •  Fuel %.1fs" % [str(state.get("status", "Add ingredients and fuel")), recipe_name, _burn.value]

func _process(delta: float) -> void:
	if _api == null:
		return
	if not _api.stations.accessible(_player, _id):
		close()
		return
	_refresh_time += delta
	if _refresh_time >= 0.2:
		_refresh_time = 0.0
		refresh()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _api != null:
		_api.stations.save()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()
