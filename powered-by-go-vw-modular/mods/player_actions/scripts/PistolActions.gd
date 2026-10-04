class_name PlayerPistolActions
extends Node

const ITEM_ID: String = "core:pistol"
const AMMO_ID: String = "core:pistol_ammo"
var player: PlayerController
var inventory: Inventory
var cooldown: float = 0.0
var magazine: int = 0
var reload_timer: float = 0.0
var reloading: bool = false
var flash_timer: float = 0.0
var recoil_offset: float = 0.0
var shot_sound: AudioStreamPlayer
var reload_sound: AudioStreamPlayer
var flash: Sprite3D
var hud: CanvasLayer
var label: Label

func setup(owner_player: PlayerController, api: ModAPI) -> void:
	player = owner_player
	inventory = player.inventory
	shot_sound = _sound(api.load_asset("sounds/pistol_shoot.mp3") as AudioStream)
	reload_sound = _sound(api.load_asset("sounds/reload.mp3") as AudioStream)
	flash = Sprite3D.new()
	flash.texture = api.load_asset("textures/muzzle_flash.png") as Texture2D
	flash.pixel_size = 0.004
	flash.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	flash.position = Vector3(0.15, 0.06, -0.8)
	flash.no_depth_test = true
	flash.render_priority = 101
	flash.visible = false
	player.camera.add_child(flash)
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	label = Label.new()
	label.anchor_left = 1.0
	label.anchor_top = 1.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = -260.0
	label.offset_top = -150.0
	label.offset_right = -32.0
	label.offset_bottom = -86.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 10)
	label.visible = false
	hud.add_child(label)
	# Explicit opt-in only, after the spawn event's inventory restoration.
	if bool(api.storage.get_value("debug_starting_inventory", false)) and inventory.items.is_empty():
		for item_id: String in ["core:grass", "core:dirt", "core:stone", "core:log"]:
			inventory.add_item(item_id, 32)
		inventory.add_item(ITEM_ID, 1)
		inventory.add_item(AMMO_ID, 16)
		inventory.assign_to_hotbar(ITEM_ID, 4)
	magazine = mini(player.pistol_mag_size, inventory.get_item_count(AMMO_ID))
	inventory.changed.connect(_inventory_changed)
	player.add_movement_extension(self)

func _sound(stream: AudioStream) -> AudioStreamPlayer:
	var sound: AudioStreamPlayer = AudioStreamPlayer.new()
	sound.stream = stream
	sound.volume_db = -2.0
	add_child(sound)
	return sound

func _exit_tree() -> void:
	if is_instance_valid(inventory) and inventory.changed.is_connected(_inventory_changed):
		inventory.changed.disconnect(_inventory_changed)
	if is_instance_valid(player):
		player.remove_movement_extension(self)
	if is_instance_valid(flash):
		flash.queue_free()

func _inventory_changed() -> void:
	magazine = clampi(magazine, 0, mini(player.pistol_mag_size, inventory.get_item_count(AMMO_ID)))

func movement_prepare(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	flash_timer = maxf(0.0, flash_timer - delta)
	flash.visible = flash_timer > 0.0
	if recoil_offset > 0.0:
		var recover: float = minf(recoil_offset, deg_to_rad(player.pistol_recoil_recover) * delta)
		recoil_offset -= recover
		player.camera.rotation.x = clampf(player.camera.rotation.x - recover, deg_to_rad(-89.0), deg_to_rad(89.0))
	if reloading:
		reload_timer = maxf(0.0, reload_timer - delta)
		if reload_timer <= 0.0:
			reloading = false
			magazine = mini(player.pistol_mag_size, inventory.get_item_count(AMMO_ID))
	var equipped: bool = inventory.get_selected_item_id() == ITEM_ID and inventory.get_item_count(ITEM_ID) > 0
	if equipped and player.gameplay_input_enabled() and not player.movement_blocked:
		if Input.is_action_just_pressed("shoot") and cooldown <= 0.0 and not reloading and magazine > 0:
			_shoot()
		if Input.is_action_just_pressed("reload"):
			_try_reload()
	label.visible = equipped
	label.text = "RELOADING..." if reloading else "%d / %d" % [magazine, maxi(0, inventory.get_item_count(AMMO_ID) - magazine)]

func _try_reload() -> void:
	if reloading or magazine >= player.pistol_mag_size or inventory.get_item_count(AMMO_ID) <= magazine:
		return
	reloading = true
	reload_timer = player.pistol_reload_time
	reload_sound.play()

func _shoot() -> void:
	cooldown = player.pistol_fire_rate
	magazine -= 1
	inventory.remove_item(AMMO_ID, 1)
	shot_sound.play()
	flash_timer = 0.12
	flash.rotation.z = randf_range(0.0, TAU)
	var before: float = player.camera.rotation.x
	player.camera.rotation.x = clampf(before + deg_to_rad(player.pistol_recoil), deg_to_rad(-89.0), deg_to_rad(89.0))
	recoil_offset += player.camera.rotation.x - before
	var origin: Vector3 = player.camera.global_position
	var direction: Vector3 = -player.camera.global_transform.basis.z
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction * player.pistol_range)
	query.exclude = [player.get_rid()]
	query.collision_mask = 0xffffffff
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider") as Object
	# No arbitrary-method calls: only the typed, opt-in public receiver contract.
	DamageReceiver.deliver(collider, player.pistol_damage, {"source": player, "item_id": ITEM_ID, "position": hit.position, "direction": direction})
	if is_instance_valid(collider) and collider is RigidBody3D:
		(collider as RigidBody3D).apply_impulse(direction * player.pistol_knockback, hit.position - (collider as RigidBody3D).global_position)
