extends Node

var api: ModAPI
var panel: PanelContainer
var search: LineEdit
var item_list: VBoxContainer
var status: Label
var player: Node3D
var _old_mouse_mode := Input.MOUSE_MODE_CAPTURED
var _muted_uis: Array[Node] = []


func setup(context: ModAPI) -> void:
	api = context
	_build_ui()
	set_process_input(true)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_top = -280
	panel.offset_right = 360
	panel.offset_bottom = 280
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Creative Item Catalog  •  F6 / Esc"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	search = LineEdit.new()
	search.placeholder_text = "Search item name, ID, or tag"
	search.text_changed.connect(_refresh)
	column.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(680, 430)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	item_list = VBoxContainer.new()
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(item_list)
	status = Label.new()
	status.text = "Click an item to receive one stack."
	column.add_child(status)
	panel.hide()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not panel.visible:
		if not event.is_action_pressed("creative_catalog"):
			return
		if api.profile.mode() != "creative":
			return
		_open()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("creative_catalog") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory_toggle"):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	if api == null or api.profile.mode() != "creative":
		return
	player = null
	for candidate in get_tree().get_nodes_in_group("player_character"):
		if candidate is Node3D and candidate.is_multiplayer_authority():
			player = candidate
			break
	if player == null or not player.is_processing_unhandled_input():
		return
	for ui in get_tree().get_nodes_in_group("inventory_ui"):
		if bool(ui.get("inventory_open")):
			return
	_old_mouse_mode = Input.get_mouse_mode()
	player.set_process_unhandled_input(false)
	_muted_uis.clear()
	for ui in get_tree().get_nodes_in_group("inventory_ui"):
		ui.set_process_input(false)
		var bar = ui.get("hotbar")
		if bar is CanvasItem:
			bar.hide()
		_muted_uis.append(ui)
	panel.show()
	search.clear()
	_refresh("")
	search.grab_focus()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _close() -> void:
	panel.hide()
	if is_instance_valid(player):
		player.set_process_unhandled_input(true)
	for ui in _muted_uis:
		if not is_instance_valid(ui):
			continue
		ui.set_process_input(true)
		var bar = ui.get("hotbar")
		if bar is CanvasItem:
			bar.show()
	_muted_uis.clear()
	if _old_mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(_old_mouse_mode)
	player = null


func _refresh(value: String) -> void:
	if item_list == null:
		return
	for child in item_list.get_children():
		item_list.remove_child(child)
		child.queue_free()
	var query := value.strip_edges().to_lower()
	for item_id in api.content.get_item_ids():
		var definition: Dictionary = api.content.get_item(item_id)
		var searchable := "%s %s %s" % [
			item_id,
			str(definition.get("display_name", item_id)),
			" ".join(PackedStringArray(definition.get("tags", []))),
		]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var stack_size := int(definition.get("stack_size", 64))
		var count := 1 if api.item_instances != null and api.item_instances.durable(item_id) else stack_size
		button.text = "%s  [%s]  x%d" % [str(definition.get("display_name", item_id)), item_id, count]
		var icon = definition.get("icon")
		if icon is Texture2D:
			button.icon = icon
		elif icon is String and ResourceLoader.exists(icon):
			var loaded = load(icon)
			if loaded is Texture2D:
				button.icon = loaded
		button.pressed.connect(_grant.bind(item_id))
		item_list.add_child(button)


func _grant(item_id: String) -> void:
	if api.profile.mode() != "creative" or not is_instance_valid(player):
		status.text = "Creative mode is not active."
		return
	var runtime: Node = api.entities.runtime
	if not is_instance_valid(runtime):
		status.text = "Inventory authority is unavailable."
		return
	var result: Dictionary = runtime.call("inventory_request", player, "creative_grant", {"item_id": item_id})
	status.text = str(result.get("reason", "Grant sent to the host.")) if not bool(result.get("success", false)) else "Added %s." % item_id
