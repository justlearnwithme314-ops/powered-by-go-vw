extends Node3D

func _ready() -> void:
	var player := CharacterBody3D.new()
	player.name = "1"
	add_child(player)
	var inventory := Inventory.new()
	inventory.name = "Inventory"
	player.add_child(inventory)
	var console := load("res://mods/debug_console/Console.gd").new() as CanvasLayer
	player.add_child(console)
	var api := ModAPI.new(GameAPI.content, GameAPI.events, GameAPI.world_generation, GameAPI.world, GameAPI.edits, GameAPI.crafting)
	api.entities = GameAPI.entities
	console.setup(api, player)
	assert("Added 16" in console.execute("/give dirt 16"))
	assert(inventory.get_item_count("core:dirt") == 16)
	assert("Unknown" in console.execute("give nonexistent"))
	assert("Count" in console.execute("give dirt -1"))
	assert("box_zombie" in console.execute("mobs"))
	assert("Usage" in console.execute("summon"))
	var sun := DirectionalLight3D.new()
	add_child(sun)
	assert("Time set" in console.execute("time set night"))
	assert(sun.light_energy == 0.0)
	assert("Time set" in console.execute("time set noon"))
	assert(sun.light_energy > 0.0)
	print("Console PASS: give, validation, entity listing and time presets")
	get_tree().quit()
