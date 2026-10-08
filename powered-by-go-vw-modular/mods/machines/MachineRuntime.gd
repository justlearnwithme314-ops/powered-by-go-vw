extends Node

const TICK_SECONDS := 0.2
const MAX_COMPLETIONS_PER_TICK := 4

var _api: ModAPI
var _tick_accumulator := 0.0
var _frozen: Dictionary = {}


func setup(api: ModAPI) -> void:
	_api = api


func _process(delta: float) -> void:
	if _api == null:
		return
	_tick_accumulator += delta
	if _tick_accumulator < TICK_SECONDS:
		return
	var elapsed := _tick_accumulator
	_tick_accumulator = 0.0
	var peer := get_tree().get_multiplayer().multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer and not get_tree().get_multiplayer().is_server():
		return
	for id in _api.stations.ids():
		tick_record(str(id), elapsed)
	if not _frozen.is_empty():
		_api.stations.mark_dirty()
		if _api.stations.save():
			_frozen.clear()


func tick_record(id: String, delta: float) -> bool:
	if _api == null or not _api.stations.writable or delta <= 0.0 or _frozen.has(id):
		return false
	var peer := get_tree().get_multiplayer().multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer and not get_tree().get_multiplayer().is_server():
		return false
	var record := _api.stations.record(id)
	if record.is_empty():
		return false
	var block_id := str(record.get("block_id", ""))
	if block_id == "survival:furnace":
		return false
	if not _api.machines.ids().has(block_id):
		return false
	var definition := _api.machines.definition(block_id)
	if definition.is_empty() or not _api.profile.enabled(str(definition.feature)):
		return false
	if _api.stations.has_method("is_locked") and _api.stations.is_locked(id):
		return false
	var input := _api.stations.container(id, "input")
	var output := _api.stations.container(id, "output")
	if input == null or output == null:
		return false
	var state: Dictionary = record.get("state", {}).duplicate(true)
	var machine: Dictionary = state.get("machine", {}).duplicate(true)
	if int(machine.get("version", 1)) != 1:
		return false
	var before_input := input.snapshot()
	var before_output := output.snapshot()
	var before_state := state.duplicate(true)
	var input_fingerprint := JSON.stringify(before_input)
	var recipe := _select_recipe(definition, before_input)
	var recipe_id := str(recipe.get("id", ""))
	var old_recipe := str(machine.get("recipe", ""))
	var old_fingerprint := str(machine.get("input_fingerprint", ""))
	var progress := maxf(float(machine.get("progress_seconds", 0.0)), 0.0)
	if recipe_id != old_recipe or input_fingerprint != old_fingerprint:
		progress = 0.0
	machine["version"] = 1
	machine["recipe"] = recipe_id
	machine["input_fingerprint"] = input_fingerprint
	machine["progress_seconds"] = progress
	machine["status"] = "No matching recipe"
	var changed := recipe_id != old_recipe or input_fingerprint != old_fingerprint
	if float(definition.energy_per_second) > 0.0:
		machine["status"] = "Needs power"
		_commit_state(id, state, machine)
		return changed or state != before_state
	if recipe.is_empty():
		_commit_state(id, state, machine)
		return changed or state != before_state
	var output_stack := {"id": str(recipe.output), "count": int(recipe.count)}
	var output_trial := SlotContainer.new(_api.content, output.size())
	output_trial.restore(before_output)
	if int(output_trial.insert(output_stack, true).added) != int(output_stack.count):
		machine["status"] = "Output full"
		_commit_state(id, state, machine)
		return changed or state != before_state
	machine["status"] = "Processing"
	progress += delta
	var completed := 0
	var did_change := true
	while completed < MAX_COMPLETIONS_PER_TICK:
		var current_input := input.snapshot()
		var current_recipe := _select_recipe(definition, current_input)
		if current_recipe.is_empty():
			machine["recipe"] = ""
			machine["input_fingerprint"] = JSON.stringify(current_input)
			machine["progress_seconds"] = 0.0
			machine["status"] = "No matching recipe"
			break
		var current_recipe_id := str(current_recipe.id)
		if current_recipe_id != str(machine.recipe):
			machine["recipe"] = current_recipe_id
			machine["input_fingerprint"] = JSON.stringify(current_input)
			machine["progress_seconds"] = 0.0
			progress = 0.0
		var fingerprint := JSON.stringify(current_input)
		# Ingredient counts changing because this runtime just completed a batch
		# must not discard the remaining time from the same tick.
		machine["input_fingerprint"] = fingerprint
		var duration := maxf(float(current_recipe.get("duration", 0.0)) * float(definition.duration_scale), 0.1)
		if progress < duration:
			break
		var ingredients := _resolve_ingredients(current_recipe, current_input)
		if not ingredients.success or not input.exchange_to(output, ingredients.items, {"id": str(current_recipe.output), "count": int(current_recipe.count)}):
			machine["status"] = "Ingredients or output changed"
			break
		progress -= duration
		completed += 1
		var after_input := input.snapshot()
		machine["input_fingerprint"] = JSON.stringify(after_input)
		var next_recipe := _select_recipe(definition, after_input)
		machine["recipe"] = str(next_recipe.get("id", ""))
		if next_recipe.is_empty():
			progress = 0.0
			machine["status"] = "No matching recipe"
			break
		if str(next_recipe.id) != str(current_recipe_id):
			progress = 0.0
			machine["status"] = "Processing"
	if completed >= MAX_COMPLETIONS_PER_TICK and progress < 0.0:
		progress = 0.0
	machine["progress_seconds"] = maxf(progress, 0.0)
	if completed > 0:
		machine["status"] = "Processing"
	_api.stations.update_state(id, _merge_machine_state(state, machine))
	if not _api.stations.save():
		input.restore(before_input)
		output.restore(before_output)
		_api.stations.update_state(id, before_state)
		_api.stations.mark_dirty()
		_frozen[id] = true
		return false
	return did_change or completed > 0 or state != before_state


func _commit_state(id: String, original_state: Dictionary, machine: Dictionary) -> void:
	var merged := _merge_machine_state(original_state, machine)
	if original_state.get("machine", {}) == machine:
		return
	_api.stations.update_state(id, merged)
	if not _api.stations.save():
		_api.stations.update_state(id, original_state)
		_api.stations.mark_dirty()
		_frozen[id] = true


func _merge_machine_state(state: Dictionary, machine: Dictionary) -> Dictionary:
	var merged := state.duplicate(true)
	merged["machine"] = machine.duplicate(true)
	return merged


func _select_recipe(definition: Dictionary, input_snapshot: Array) -> Dictionary:
	var available: Dictionary = {}
	for stack in input_snapshot:
		if stack is Dictionary and not stack.is_empty():
			var item_id := str(stack.get("id", ""))
			available[item_id] = int(available.get(item_id, 0)) + int(stack.get("count", 0))
	var candidates: Array[Dictionary] = []
	for recipe_id in _api.content.get_recipe_ids():
		var recipe := _api.content.get_recipe(str(recipe_id))
		if str(recipe.get("method", "craft")) != str(definition.get("method", "")):
			continue
		var resolved := _resolve_ingredients(recipe, input_snapshot)
		if bool(resolved.success):
			var candidate := recipe.duplicate(true)
			candidate["id"] = str(recipe_id)
			candidate["_resolved"] = resolved.items
			candidates.append(candidate)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_types := (a.get("ingredients", {}) as Dictionary).size()
		var b_types := (b.get("ingredients", {}) as Dictionary).size()
		if a_types != b_types:
			return a_types > b_types
		return str(a.id) < str(b.id)
	)
	return candidates[0] if not candidates.is_empty() else {}


func _resolve_ingredients(recipe: Dictionary, input_snapshot: Array) -> Dictionary:
	var available: Dictionary = {}
	for stack in input_snapshot:
		if stack is Dictionary and not stack.is_empty():
			var item_id := str(stack.get("id", ""))
			available[item_id] = int(available.get(item_id, 0)) + int(stack.get("count", 0))
	return _api.content.resolve_ingredients(recipe.get("ingredients", {}), available)
