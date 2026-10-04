extends GameMod

## AI-friendly starter mod.
## Copy this folder to user://mods/<your_mod_folder>, rename the namespace,
## and edit only this file plus assets. The _template folder itself is ignored.

const COPPER := "example:copper_ore"
const INGOT := "example:copper_ingot"


func register(api: ModAPI) -> void:
	api.register_block({
		"id": COPPER,
		"display_name": "Copper Ore",
		"model": api.load_asset("models/copper_ore.tres"),
		"hardness": 3.0,
		"tags": ["block", "ore"],
		"drops": [{"item": COPPER, "count": 1}],
	})

	api.register_item({
		"id": INGOT,
		"display_name": "Copper Ingot",
		"stack_size": 64,
		"tags": ["resource", "metal"],
	})

	api.register_item({
		"id": "example:copper_pickaxe",
		"display_name": "Copper Pickaxe",
		"stack_size": 1,
		"tags": ["tool"],
		"properties": {"break_power": 6.0},
	})

	api.register_recipe(
		"example:copper_pickaxe",
		"example:copper_pickaxe",
		1,
		{
			INGOT: 3,
			"core:stick": 2,
		}
	)

	api.register_worldgen_stage(
		"example:copper_ore",
		350,
		Callable(self, "_generate_copper")
	)

	api.on(GameEvents.AFTER_BLOCK_BREAK, Callable(self, "_on_break"))


func _generate_copper(ctx: WorldGenContext) -> void:
	var noise := ctx.noise.get_custom_3d("example:copper", 0.05, 2)
	var size := ctx.buffer.get_size()

	for z in range(size.z):
		for x in range(size.x):
			for y in range(size.y):
				var p := Vector3i(x, y, z)
				if ctx.get_block_id_local(p) != "core:stone":
					continue

				var wx := ctx.origin.x + x
				var wy := ctx.origin.y + y
				var wz := ctx.origin.z + z
				if wy < 40 and noise.get_noise_3d(wx, wy, wz) > 0.7:
					ctx.set_voxel_local(p, COPPER)


func _on_break(event: Dictionary) -> Dictionary:
	# Example hook: gameplay systems can react without editing GameManager.
	if event.get("block_id", "") == COPPER:
		print("[ExampleMod] Copper mined at ", event.get("position"))
	return event
