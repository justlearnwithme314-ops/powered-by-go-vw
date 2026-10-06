extends Node

var _api: ModAPI
var _save_timer := 0.0
var _ui_script: Script
var _ui: Node
var _configured: Dictionary = {}

func setup(api: ModAPI) -> void:
	_api = api
	_ui_script = api.load_asset("StationUI.gd") as Script

func _process(delta: float) -> void:
	if _api == null or not _api.stations.writable:
		return
	for id in _api.stations.ids():
		if _api.stations.container(str(id), "input") != null:
			tick_furnace(str(id), delta)
	_save_timer += delta
	if _save_timer >= 1.0:
		_save_timer = 0.0
		if _api.stations.dirty and is_instance_valid(_api.stations.inventory):
			_api.stations.save()

func tick_furnace(id: String, delta: float) -> void:
	var record := _api.stations.record(id)
	if record.is_empty():
		return
	var input := _api.stations.container(id, "input")
	var fuel := _api.stations.container(id, "fuel")
	var output := _api.stations.container(id, "output")
	if not _configured.has(id) or _configured[id] != input:
		fuel.set_filter(0, _accept_fuel)
		for slot in range(input.size()):
			input.set_filter(slot, _accept_input)
		_configured[id] = input
	var state: Dictionary = record.state.duplicate(true)
	var recipe_id := ""
	var ingredient_types := 0
	for candidate in _api.content.get_recipe_ids():
		var recipe := _api.content.get_recipe(candidate)
		if str(recipe.get("method", "craft")) != "smelt":
			continue
		var enough := true
		for ingredient in recipe.ingredients:
			if input.count(str(ingredient)) < int(recipe.ingredients[ingredient]):
				enough = false
		# Alloys must win over their individual metal ingredients.
		if enough and recipe.ingredients.size() > ingredient_types:
			recipe_id = candidate
			ingredient_types = recipe.ingredients.size()
	var fingerprint := JSON.stringify(input.snapshot())
	if recipe_id != str(state.get("recipe", "")) or fingerprint != str(state.get("input", "")):
		state["recipe"] = recipe_id
		state["progress"] = 0.0
	state["input"] = fingerprint
	var remaining := maxf(float(state.get("burn", 0.0)), 0.0)
	var cooking_delta := minf(delta, remaining)
	state["burn"] = maxf(remaining - delta, 0.0)
	state["status"] = "Add ingredients" if recipe_id.is_empty() else "Needs fuel"
	if not recipe_id.is_empty():
		var recipe := _api.content.get_recipe(recipe_id)
		var result_stack := {"id": str(recipe.output), "count": int(recipe.count)}
		var trial := SlotContainer.new(_api.content, output.size())
		trial.restore(output.snapshot())
		if int(trial.insert(result_stack, true).added) != int(result_stack.count):
			state.status = "Output full"
		else:
			if remaining > 0.0:
				state.status = "Smelting"
			if cooking_delta < delta:
				var fuel_stack := fuel.stack_at(0)
				var seconds := float(_api.content.get_item(str(fuel_stack.get("id", ""))).get("properties", {}).get("fuel_seconds", 0.0))
				if seconds > 0.0:
					fuel.take(0, 1)
					var used := minf(delta - cooking_delta, seconds)
					cooking_delta += used
					state.burn = seconds - used
					state["burn_total"] = seconds
			if cooking_delta > 0.0:
				state.status = "Smelting"
				state["progress"] = float(state.get("progress", 0.0)) + cooking_delta
				var duration := maxf(float(recipe.duration), 0.1)
				var completed := 0
				while float(state.progress) >= duration and completed < 16:
					if input.exchange_to(output, recipe.ingredients, result_stack):
						state.progress = maxf(float(state.progress) - duration, 0.0)
						state.input = JSON.stringify(input.snapshot())
						completed += 1
					else:
						state.status = "Ingredients or output changed"
						break
	if record.state != state:
		_api.stations.update_state(id, state)

func _accept_fuel(stack: Dictionary) -> bool:
	return float(_api.content.get_item(str(stack.get("id", ""))).get("properties", {}).get("fuel_seconds", 0.0)) > 0.0

func _accept_input(stack: Dictionary) -> bool:
	for recipe_id in _api.content.get_recipe_ids():
		var recipe := _api.content.get_recipe(recipe_id)
		if str(recipe.get("method", "craft")) == "smelt" and recipe.ingredients.has(str(stack.get("id", ""))):
			return true
	return false

func open_station(player: Node3D, id: String) -> void:
	tick_furnace(id, 0.0)
	if is_instance_valid(_ui):
		_ui.call("close")
	_ui = _ui_script.new() as Node
	player.add_child(_ui)
	_ui.call("setup", player, id, _api)
