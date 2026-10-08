extends GameMod

func register(api: ModAPI) -> void:
	api.register_block({
		"id":"building:glass", "display_name":"Glass",
		"model":api.load_asset("glass.tres"), "solid":true,
		"transparent":true, "transparency_index":2, "culls_neighbors":false,
		"hardness":0.3, "tags":["block","building","glass"],
	})
	api.register_item({
		"id":"building:glass", "display_name":"Glass", "stack_size":64,
		"place_block":"building:glass", "tags":["block","building","glass"],
		"icon":api.asset("res://assets/minecraft-inspired-textures-free/block/glass.png"),
	})
	api.register_recipe("building:glass_from_sand","building:glass",1,{"core:sand":1},
		{"method":"smelt","station":"furnace","duration":8.0})
