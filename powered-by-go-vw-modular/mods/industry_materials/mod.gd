extends GameMod

func register(api: ModAPI) -> void:
	var result := api.register_content_pack("content.json")
	if not bool(result.get("success", false)):
		push_error("[IndustryMaterials] Content pack rejected: %s" % str(result.get("errors", [])))
