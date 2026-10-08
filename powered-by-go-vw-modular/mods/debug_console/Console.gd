extends CanvasLayer

var api: ModAPI
var player: Node3D
var panel: PanelContainer
var output: RichTextLabel
var entry: LineEdit
var history: Array[String] = []
var history_index := 0
var old_mouse_mode := Input.MOUSE_MODE_CAPTURED
var muted_inputs: Array[Node] = []

func setup(context: ModAPI, owner_player: Node3D) -> void:
	api = context
	player = owner_player
	layer = 100
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_top = 20
	panel.offset_bottom = 320
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	output = RichTextLabel.new()
	output.custom_minimum_size.y = 240
	output.scroll_following = true
	column.add_child(output)
	entry = LineEdit.new()
	entry.placeholder_text = "help | give dirt 64 | summon zombie | time set day"
	column.add_child(entry)
	entry.text_submitted.connect(_submitted)
	entry.gui_input.connect(_entry_input)
	panel.hide()
	log_message("Testing console. Type help. Esc closes; Up/Down recall commands.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if not panel.visible and (event.keycode == KEY_SLASH or event.physical_keycode == KEY_SLASH):
			old_mouse_mode = Input.get_mouse_mode()
			panel.show()
			for ui in get_tree().get_nodes_in_group("inventory_ui"):
				if ui.is_processing_input():
					muted_inputs.append(ui)
					ui.set_process_input(false)
			player.set_process_unhandled_input(false)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			entry.text = "/"
			entry.grab_focus()
			entry.caret_column = 1
			get_viewport().set_input_as_handled()
		elif panel.visible and event.keycode == KEY_ESCAPE:
			panel.hide()
			for ui in muted_inputs:
				if is_instance_valid(ui):
					ui.set_process_input(true)
			muted_inputs.clear()
			player.set_process_unhandled_input(true)
			entry.release_focus()
			Input.set_mouse_mode(old_mouse_mode)
			get_viewport().set_input_as_handled()

func _entry_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN]:
		history_index = clampi(history_index + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		entry.text = history[history_index] if history_index < history.size() else ""
		entry.caret_column = entry.text.length()
		get_viewport().set_input_as_handled()

func log_message(message: String) -> void:
	output.add_text(message + "\n")

func _submitted(line: String) -> void:
	if line.strip_edges().trim_prefix("/").is_empty():
		return
	history.append(line)
	history_index = history.size()
	log_message("> " + line)
	log_message(execute(line))
	entry.clear()

func _resolve(value: String, ids: Array) -> String:
	if value in ids:
		return value
	var matches: Array[String] = []
	for id in ids:
		if str(id).get_slice(":", 1) == value:
			matches.append(str(id))
	if not matches.is_empty(): return matches[0] if matches.size() == 1 else ""
	for id in ids:
		if str(id).get_slice(":", 1) == "box_" + value: matches.append(str(id))
	return matches[0] if matches.size() == 1 else ""

func execute(line: String) -> String:
	var args := line.strip_edges().trim_prefix("/").split(" ", false)
	if args.is_empty():
		return "Type help."
	match args[0].to_lower():
		"skin":
			if args.size() != 2 or args[1] != "set":
				return "Usage: skin set"
			var service := get_node_or_null("/root/SkinService")
			if service == null:
				return "Skin service unavailable."
			service.open_picker()
			return "Select a 64x64 PNG skin."
		"help":
			return "give <item ID> [count]\nsummon <mob ID> [x y z]\ntime set <day|noon|night|midnight|0..23999>\nskin set (choose a 64x64 PNG)\nitems [filter] | mobs | clear\nShort names work when unambiguous. World-changing commands are for single-player or the host."
		"clear":
			output.clear()
			return "Console cleared."
		"items":
			var found: Array[String] = []
			for id in api.content.items:
				if args.size() < 2 or args[1] in str(id):
					found.append(str(id))
			return ", ".join(found)
		"mobs":
			return ", ".join(api.entities.definitions.keys())
	if player.multiplayer.has_multiplayer_peer() and not player.multiplayer.is_server():
		return "Run testing commands in single-player or on the host."
	match args[0].to_lower():
		"give":
			if args.size() not in [2,3] or (args.size() == 3 and not args[2].is_valid_int()):
				return "Usage: give <item ID> [count]"
			var id := _resolve(args[1], api.content.items.keys())
			if id.is_empty():
				return "Unknown or ambiguous item. Use items <filter>."
			var count := int(args[2]) if args.size() == 3 else 1
			if count < 1 or count > 4096:
				return "Count must be 1..4096."
			var inventory := player.get_node_or_null("Inventory") as Inventory
			var result := inventory.add_stack({"id": id, "count": count})
			return "Added %d / %d of %s." % [int(result.added), count, id]
		"summon":
			if args.size() not in [2,5]:
				return "Usage: summon <mob ID> [x y z]"
			var id := _resolve(args[1], api.entities.definitions.keys())
			if id.is_empty():
				return "Unknown or ambiguous mob. Use mobs."
			var position := player.global_position - player.global_transform.basis.z * 3.0
			if args.size() == 5:
				for i in range(2,5):
					if not args[i].is_valid_float() or not is_finite(float(args[i])):
						return "Coordinates must be finite numbers."
				position = Vector3(float(args[2]),float(args[3]),float(args[4]))
			else:
				var hit = api.world.raycast(position + Vector3.UP * 8, Vector3.DOWN, 24)
				if hit != null:
					position = Vector3(hit.position) + Vector3(0.5,1.05,0.5)
			if api.entities.spawn(id,position) != null: return "Summoned " + id
			var runtime: Node = api.entities.runtime
			return "Could not summon: " + str(runtime.get("last_spawn_error")) if is_instance_valid(runtime) else "Could not summon: world entity runtime unavailable."
		"time":
			if args.size() != 3 or args[1] != "set":
				return "Usage: time set <day|noon|night|midnight|0..23999>"
			var named := {"day":1000,"noon":6000,"night":13000,"midnight":18000}
			if not named.has(args[2]) and not args[2].is_valid_int():
				return "Unknown time."
			var ticks := int(named.get(args[2], int(args[2]) if args[2].is_valid_int() else 0))
			if ticks < 0 or ticks >= 24000:
				return "Time must be 0..23999."
			var lights := player.get_tree().current_scene.find_children("*", "DirectionalLight3D", true, false)
			if lights.is_empty():
				return "No sunlight found."
			var sun := lights[0] as DirectionalLight3D
			sun.rotation_degrees.x = -float(ticks) / 24000.0 * 360.0
			sun.light_energy = 0.0 if ticks >= 12000 else 0.8
			return "Time set to %d (testing lighting preset)." % ticks
	return "Unknown command. Type help."
