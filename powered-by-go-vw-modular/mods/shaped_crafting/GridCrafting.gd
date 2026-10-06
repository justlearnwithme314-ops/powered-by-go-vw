extends RefCounted
var api: Dictionary
var custom_patterns: Dictionary = {}

func register_pattern(recipe_id: String, rows: Array) -> void:
	custom_patterns[recipe_id] = rows.duplicate(true)

func setup(context: ModAPI) -> void:
	# Keep only required services to avoid a service/ModAPI reference cycle.
	api = {"content":context.content,"world":context.world,"stations":context.stations,"events":context.events,"item_instances":context.item_instances}

func dimensions(player: Node3D) -> Vector2i:
	var center := player.global_position + Vector3.UP * 0.5
	var cell := Vector3i(center.floor())
	var root := cell
	var nearest := 9.01
	var found := false
	for z in range(-3,4):
		for x in range(-3,4):
			for y in range(-3,4):
				var pos := cell + Vector3i(x,y,z)
				var distance := center.distance_squared_to(Vector3(pos)+Vector3.ONE*0.5)
				if distance <= 9 and distance < nearest and api.world.get_block_id(pos) == "survival:workbench":
					root = pos
					nearest = distance
					found = true
	if not found:
		return Vector2i(2,2)
	var frontier: Array[Vector3i] = [root]
	var seen := {root:true}
	var minimum := Vector2i(root.x,root.z)
	var maximum := minimum
	var index := 0
	while index < frontier.size():
		var pos := frontier[index]
		index += 1
		for offset in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			var next: Vector3i = pos + offset
			if not seen.has(next) and api.world.get_block_id(next) == "survival:workbench":
				seen[next] = true
				frontier.append(next)
				minimum.x = mini(minimum.x,next.x)
				minimum.y = mini(minimum.y,next.z)
				maximum.x = maxi(maximum.x,next.x)
				maximum.y = maxi(maximum.y,next.z)
	# The connected tabletop footprint determines both grid dimensions.
	# Rotate the footprint so a two-table row is 6x3 along either world axis.
	var footprint := maximum-minimum+Vector2i.ONE
	return Vector2i(3*maxi(footprint.x,footprint.y),3*mini(footprint.x,footprint.y))

func return_grid(inventory: Inventory) -> void:
	for i in range(inventory.crafting_grid.size()):
		var stack := inventory.crafting_grid.take(i,2147483647)
		if not stack.is_empty():
			var result := inventory.container.insert(stack)
			if not result.remainder.is_empty():
				inventory.recovery.append(result.remainder)
	inventory._emit_changed()

func command(player: Node3D, inventory: Inventory, action: String, args: Dictionary) -> Dictionary:
	inventory._ensure_storage()
	if action == "grid_return":
		return_grid(inventory)
		return {"success":true}
	var size := dimensions(player)
	if action == "grid_resize":
		if inventory.crafting_width != size.x or inventory.crafting_height != size.y:
			return_grid(inventory)
			inventory.crafting_grid = SlotContainer.new(api.content,size.x*size.y)
			inventory.crafting_grid.changed.connect(inventory._emit_changed)
			inventory.crafting_width = size.x
			inventory.crafting_height = size.y
			inventory._emit_changed()
		return {"success":true}
	if size != Vector2i(inventory.crafting_width,inventory.crafting_height):
		return {"success":false,"reason":"Workbenches changed; reopen or refresh the grid."}
	if action == "grid_click":
		var index := int(args.get("index",-1))
		var right := bool(args.get("right",false))
		var held := inventory.cursor.stack_at(0)
		if held.is_empty():
			var stack := inventory.crafting_grid.stack_at(index)
			if stack.is_empty():
				return {"success":true}
			inventory.crafting_grid.transfer_to(inventory.cursor,index,0,ceili(float(stack.count)/2) if right else int(stack.count))
			inventory.cursor_origin = -1
		else:
			inventory.cursor.transfer_to(inventory.crafting_grid,0,index,1 if right else int(held.count))
		return {"success":true}
	if action == "grid_craft":
		var id := str(args.get("recipe_id",""))
		if id not in matches(inventory):
			return {"success":false,"reason":"Arrangement or station no longer matches."}
		var recipe: Dictionary = api.content.get_recipe(id)
		var event: Dictionary = api.events.emit(GameEvents.BEFORE_CRAFT,{"player":player,"inventory":inventory,"recipe_id":id,"recipe":recipe,"cancelled":false})
		if bool(event.get("cancelled",false)):
			return {"success":false,"reason":"Craft cancelled"}
		if id not in matches(inventory):
			return {"success":false,"reason":"Ingredients changed"}
		var output := {"id":str(event.get("output",recipe.output)),"count":int(event.get("count",recipe.count))}
		if not api.content.has_item(output.id) or output.count <= 0:
			return {"success":false,"reason":"Invalid output"}
		output = api.item_instances.prepare(output) if output.count == 1 else output
		inventory._suppress_changed = true
		if inventory.container.insert(output,true).added != output.count:
			inventory._suppress_changed = false
			return {"success":false,"reason":"Inventory full"}
		for i in range(inventory.crafting_grid.size()):
			if not inventory.crafting_grid.stack_at(i).is_empty():
				inventory.crafting_grid.take(i,1)
		inventory._suppress_changed = false
		inventory._emit_changed()
		api.events.emit(GameEvents.AFTER_CRAFT,{"player":player,"inventory":inventory,"recipe_id":id,"recipe":recipe,"result":{"success":true,"output":output.id,"count":output.count}})
		return {"success":true,"output":output.id,"count":output.count}
	return {"success":false,"reason":"Unknown grid command"}

func pattern(recipe: Dictionary) -> Array:
	if custom_patterns.has(str(recipe.id)):
		return custom_patterns[str(recipe.id)]
	var material := ""
	for id in recipe.ingredients:
		if id != "core:stick":
			material = str(id)
			break
	var kind := str(api.content.get_item(str(recipe.output)).get("properties",{}).get("tool_type",""))
	var shape: Array = []
	match kind:
		"pickaxe": shape = ["MMM"," S "," S "]
		"axe": shape = ["MM","MS"," S"]
		"shovel": shape = ["M","S","S"]
		"sword": shape = ["M","M","S"]
	match str(recipe.output):
		"survival:workbench": shape = ["MM","MM"]
		"survival:furnace": shape = ["MMM","M M","MMM"]
		"core:stick": shape = ["M","M"] if int(recipe.ingredients.get(material,0)) == 2 else []
	if str(recipe.output).ends_with("_helmet"): shape = ["MMM","M M"]
	if str(recipe.output).ends_with("_chestplate"): shape = ["M M","MMM","MMM"]
	if str(recipe.output).ends_with("_leggings"): shape = ["MMM","M M","M M"]
	if str(recipe.output).ends_with("_boots"): shape = ["M M","M M"]
	var result: Array = []
	for row in shape:
		var cells: Array[String] = []
		for c in str(row):
			cells.append(material if c == "M" else "core:stick" if c == "S" else "")
		result.append(cells)
	# Advanced tiers can carry an extra modifier ingredient in an empty cell.
	if not kind.is_empty() and recipe.ingredients.size() > 2:
		for extra in recipe.ingredients:
			if extra == material or extra == "core:stick": continue
			var placed := false
			for row in result:
				for x in range(row.size()):
					if row[x] == "" and not placed:
						row[x] = str(extra)
						placed = true
			if not placed:
				for row in result:
					row.append("")
				result[0][result[0].size()-1] = str(extra)
	return result

func matches(inventory: Inventory) -> Array[String]:
	var matches: Array[String] = []
	var cells := inventory.crafting_grid.snapshot()
	var counts := {}
	var min_x := inventory.crafting_width
	var min_y := inventory.crafting_height
	var max_x := -1
	var max_y := -1
	for i in range(cells.size()):
		if cells[i].is_empty(): continue
		var x := i % inventory.crafting_width
		var y := i / inventory.crafting_width
		min_x = mini(min_x,x)
		max_x = maxi(max_x,x)
		min_y = mini(min_y,y)
		max_y = maxi(max_y,y)
		var id := str(cells[i].id)
		counts[id] = int(counts.get(id,0)) + 1
	if max_x < 0: return matches
	var capabilities: Array[String] = api.stations.capabilities(inventory.get_parent() as Node3D)
	for id in api.content.get_recipe_ids():
		var recipe: Dictionary = api.content.get_recipe(id)
		if str(recipe.get("method","craft")) != "craft" or str(recipe.get("station","hand")) not in capabilities:
			continue
		var resolved: Dictionary = api.content.resolve_ingredients(recipe.ingredients, counts)
		if not resolved.success or resolved.items != counts: continue
		var expected := pattern(recipe)
		if expected.is_empty():
			matches.append(id)
			continue
		if expected.size() != max_y-min_y+1 or expected[0].size() != max_x-min_x+1: continue
		for mirror in [false,true]:
			var valid := true
			for y in range(expected.size()):
				for x in range(expected[0].size()):
					var stack: Dictionary = cells[(min_y+y)*inventory.crafting_width+min_x+x]
					var value := str(stack.get("id",""))
					if not api.content.ingredient_matches(value, str(expected[y][expected[0].size()-1-x if mirror else x])): valid = false
			if valid:
				matches.append(id)
				break
	return matches
