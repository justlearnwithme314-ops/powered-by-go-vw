extends GameMod
func register(api: ModAPI) -> void:
	var service := api.load_asset("SkinService.gd").new() as Node
	service.name = "SkinService"
	Engine.get_main_loop().root.add_child.call_deferred(service)
