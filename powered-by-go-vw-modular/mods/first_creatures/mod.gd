extends GameMod

func register(api: ModAPI) -> void:
	var hit_sound := api.load_asset("sounds/hit.ogg") as AudioStream
	api.register_item({"id": "creatures:raw_meat", "display_name": "Raw Pork", "stack_size": 64, "icon": api.asset("icons/raw_meat.svg"), "tags": ["food"], "properties": {"food_value": 2, "stamina_restore": 2}})
	api.register_item({"id": "creatures:cooked_meat", "display_name": "Cooked Pork", "stack_size": 64, "icon": api.asset("icons/cooked_meat.svg"), "tags": ["food"], "properties": {"food_value": 8, "stamina_restore": 12}})
	api.register_item({"id": "creatures:bone", "display_name": "Bone", "stack_size": 64, "icon": api.asset("icons/bone.svg")})
	api.register_recipe("creatures:cooked_meat", "creatures:cooked_meat", 1, {"creatures:raw_meat": 1}, {"station": "furnace", "method": "smelt", "duration": 6})
	api.register_recipe("creatures:bone_sticks", "core:stick", 2, {"creatures:bone": 1})
	api.entities.register({"id": "creatures:pig", "health": 10, "faction": "passive", "speed": 1.5, "height": 0.9, "radius": 0.4, "visual": api.load_asset("PigVisual.gd"), "loot": [{"id": "creatures:raw_meat", "count": 2}]})
	api.entities.register({"id": "creatures:skeleton", "health": 20, "faction": "hostile", "speed": 2.4, "height": 1.8, "radius": 0.3, "damage": 3, "windup": 0.4, "cooldown": 1.2, "reach": 2, "detect": 16, "visual": api.load_asset("SkeletonVisual.gd"), "model": api.load_asset("models/Skeleton_Minion.glb"), "movement": api.load_asset("models/Rig_Medium_MovementBasic.glb"), "general": api.load_asset("models/Rig_Medium_General.glb"), "loot": [{"id": "creatures:bone", "count": 2}]})
	for id in ["creatures:pig", "creatures:skeleton"]:
		api.entities.definitions[id].hit_sound = hit_sound
		api.entities.definitions[id].natural_spawn = id == "creatures:pig"
	api.entities.definitions["creatures:skeleton"].visual = api.load_asset("HumanoidVisual.gd")
	api.entities.definitions["creatures:skeleton"].skin = api.load_asset("textures/skeleton.png")
	api.entities.definitions["creatures:skeleton"].classic_limbs = true
	api.entities.definitions["creatures:skeleton"].skeleton_layout = true
	api.entities.definitions["creatures:skeleton"].flee_health_ratio = 0.2
	# Reusable example definition; opt-in spawning through api.entities.spawn().
	api.entities.register({"id": "creatures:humanoid_template", "health": 20, "faction": "passive", "speed": 1.5, "height": 2.0, "radius": 0.3, "visual": api.load_asset("HumanoidVisual.gd"), "skin": api.load_asset("textures/humanoid.png"), "body_scale": Vector3.ONE, "natural_spawn": false, "loot": []})
	for prototype in ["zombie", "creeper", "slime"]:
		api.entities.register({"id": "creatures:box_" + prototype, "health": 10, "faction": "passive", "speed": 1.2, "height": 0.55 if prototype == "slime" else 2.0 if prototype == "zombie" else 1.65, "radius": 0.3, "visual": api.load_asset("HumanoidVisual.gd" if prototype == "zombie" else "BoxMobVisual.gd"), "skin": api.load_asset("textures/" + prototype + ".png"), "classic_limbs": true, "box_shape": prototype, "natural_spawn": true, "loot": [], "hit_sound": hit_sound})
		if prototype != "slime":
			var definition: Dictionary = api.entities.definitions["creatures:box_" + prototype]
			definition.merge({"faction":"hostile", "damage":2, "detect":16, "reach":2.0, "windup":0.4, "cooldown":1.2, "flee_health_ratio":0.25}, true)
