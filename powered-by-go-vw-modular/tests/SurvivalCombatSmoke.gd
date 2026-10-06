extends Node3D

var deaths := 0
var respawns := 0

func _ready() -> void:
	GameAPI.events.subscribe(GameEvents.PLAYER_DIED, _died)
	GameAPI.events.subscribe(GameEvents.PLAYER_RESPAWNED, _respawned)
	var player := load("res://scenes/player/Player.tscn").instantiate() as PlayerController
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	GameAPI.events.emit(GameEvents.PLAYER_SPAWNED, {"player": player, "peer_id": 1})
	player.set_physics_process(false)
	var survival := player.get_node("DamageReceiver") as DamageReceiver
	survival.set_physics_process(false)
	var vitals := player.get_node("FrontierVitals")
	vitals.set_physics_process(false)
	var interactor := player.get_node("VoxelInteractor") as VoxelInteractor
	interactor.set_physics_process(false)
	var inventory := player.get_node("Inventory") as Inventory
	assert(inventory.items.is_empty())
	survival._spawn_protection = 0.0
	assert(survival.health == 20.0)
	# Armor mitigates physical damage, wears individually, and ignores drowning.
	assert(inventory.add_item("survival:iron_helmet", 1))
	assert(inventory.equip(0, 0).success)
	var armor_id := str(inventory.equipment.stack_at(0).instance_id)
	survival.receive_damage(10.0, {"damage_type": "physical"})
	assert(is_equal_approx(survival.health, 10.8))
	assert(GameAPI.item_instances.condition(inventory.equipment.stack_at(0)) == 239)
	assert(inventory.equipment.stack_at(0).instance_id == armor_id)
	survival.receive_damage(10.0, {"damage_type": "physical"})
	assert(is_equal_approx(survival.health, 10.8)) # Hurt cooldown.
	survival.heal(20.0)
	survival.receive_damage(10.0, {"damage_type": "drowning"})
	assert(survival.health == 10.0)
	survival.receive_damage(NAN, {"damage_type": "drowning"})
	assert(survival.health == 10.0)
	assert(inventory.add_item("survival:bandage", 2))
	assert(survival.try_bandage() and survival.health == 16.0)
	survival.heal(20.0)
	assert(not survival.try_bandage() and inventory.get_item_count("survival:bandage") == 1)
	# Food-driven regeneration, starvation and poison share health rules.
	survival.receive_damage(10.0, {"damage_type": "fall"})
	vitals.hunger = 18.0
	survival._physics_process(4.0)
	assert(survival.health == 11.0 and vitals.hunger == 17.75)
	vitals.hunger = 0.0
	survival._physics_process(4.0)
	assert(survival.health == 10.0)
	vitals.poison_seconds = 5.0
	survival._physics_process(1.0)
	assert(survival.health == 9.0)
	vitals.poison_seconds = 0.0
	# Drowning begins after oxygen runs out; surfacing replenishes oxygen.
	survival.tick_breath(11.0, true)
	assert(survival.oxygen == 0.0 and survival.health == 7.0)
	survival.tick_breath(4.0, false)
	assert(survival.oxygen == 10.0)
	survival.heal(20.0)
	survival.track_landing(0.0, true, false, true)
	survival.track_landing(10.0, false)
	survival.track_landing(3.0, true)
	assert(survival.health == 16.0)
	survival.track_landing(100.0, false, false, true)
	survival.track_landing(100.0, true)
	assert(survival.health == 16.0)
	# Real physics ray melee: receiver first, no mining through the entity.
	assert(inventory.add_item("frontier:wood_sword", 1))
	assert(inventory.assign_to_hotbar("frontier:wood_sword", 2))
	inventory.set_selected_slot(2)
	var sword_before := GameAPI.item_instances.condition(inventory.get_slot(2))
	var target := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE
	collision.shape = shape
	target.add_child(collision)
	var receiver := DamageReceiver.new()
	receiver.name = "DamageReceiver"
	receiver.health = 20.0
	target.add_child(receiver)
	add_child(target)
	var camera := player.get_node("Camera3D") as Camera3D
	target.global_position = camera.global_position - camera.global_transform.basis.z * 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	interactor.hit_cooldown = 0.0
	interactor._handle_primary_action()
	assert(receiver.health == 15.0 and not interactor.breaking_active)
	assert(GameAPI.item_instances.condition(inventory.get_slot(2)) == sword_before - 1)
	assert(target.velocity.length() > 0.0)
	target.queue_free()
	# Death is idempotent, input is disabled and inventory remains owned.
	var total := inventory.get_snapshot()
	survival.receive_damage(100.0, {"damage_type": "void"})
	survival.receive_damage(100.0, {"damage_type": "void"})
	assert(survival.dead and survival.health == 0.0 and deaths == 1)
	assert(not player.gameplay_input_enabled() and not player.is_physics_processing())
	assert(inventory.get_snapshot() == total)
	assert(not GameAPI.inventory_commands.request(player, "organize").success)
	assert(GameAPI.stations.player_data("survival:player_survival").dead)
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://tests/death-ui-preview.png")
	# Loading a dead state rebuilds the screen without emitting another death.
	survival.free()
	survival = load("res://mods/player_survival/PlayerSurvival.gd").new() as DamageReceiver
	survival.name = "DamageReceiver"
	player.add_child(survival)
	survival.setup(GameAPI.base_mod_api)
	survival.set_physics_process(false)
	assert(survival.dead and deaths == 1)
	survival.respawn()
	player.set_physics_process(false)
	vitals.set_physics_process(false)
	assert(not survival.dead and survival.health == 20.0 and survival.oxygen == 10.0 and respawns == 1)
	assert(vitals.hunger == 18.0 and vitals.poison_seconds == 0.0)
	assert(inventory.get_snapshot() == total)
	survival.receive_damage(10.0, {"damage_type": "fall"})
	assert(survival.health == 20.0) # Spawn protection.
	player.queue_free()
	print("Survival combat PASS: health, armor/condition, hurt cooldown, healing, regen/starvation/poison, oxygen, fall/teleport, physics melee, idempotent death/reload and respawn")
	get_tree().quit()

func _died(event: Dictionary) -> Dictionary:
	deaths += 1
	return event

func _respawned(event: Dictionary) -> Dictionary:
	respawns += 1
	return event
