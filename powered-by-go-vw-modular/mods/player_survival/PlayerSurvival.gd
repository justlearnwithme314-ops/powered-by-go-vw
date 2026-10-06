extends DamageReceiver

const MAX_HEALTH := 20.0
const MAX_OXYGEN := 10.0
const STATE_ID := "survival:player_survival"
var _api: ModAPI
var _player: PlayerController
var _inventory: Inventory
var _vitals: Node
var oxygen := MAX_OXYGEN
var dead := false
var _hurt_time := 0.0
var _spawn_protection := 3.0
var _drown_clock := 0.0
var _regen_clock := 0.0
var _starve_clock := 0.0
var _poison_clock := 0.0
var _save_clock := 0.0
var _fall_peak := 0.0
var _was_grounded := true
var _last_position := Vector3.ZERO
var _hud: CanvasLayer
var _health_label: Label
var _oxygen_bar: ProgressBar
var _flash: ColorRect
var _death_ui: CanvasLayer

func setup(api: ModAPI) -> void:
	_api = api
	_player = get_parent() as PlayerController
	_inventory = _player.get_node("Inventory") as Inventory
	_vitals = _player.get_node_or_null("FrontierVitals")
	var saved := api.stations.player_data(STATE_ID)
	health = _number(saved.get("health", MAX_HEALTH), 0.0, MAX_HEALTH, MAX_HEALTH)
	oxygen = _number(saved.get("oxygen", MAX_OXYGEN), 0.0, MAX_OXYGEN, MAX_OXYGEN)
	if _vitals != null:
		for field in ["hunger", "stamina", "poison_seconds"]:
			if saved.has(field):
				_vitals.set(field, _number(saved[field], 0.0, 100.0, 0.0))
	_fall_peak = _player.global_position.y
	_last_position = _player.global_position
	_build_hud()
	if health <= 0.0:
		_die({"damage_type": "saved_death"}, false)
	_refresh_hud()

func _number(value: Variant, minimum: float, maximum: float, fallback: float) -> float:
	return clampf(float(value), minimum, maximum) if (value is int or value is float) and is_finite(float(value)) else fallback

func receive_damage(amount: float, context: Dictionary) -> void:
	if _api == null or dead or not is_finite(amount) or amount <= 0.0:
		return
	var kind := str(context.get("damage_type", "physical"))
	if _spawn_protection > 0.0:
		return
	var physical := kind in ["physical", "projectile"]
	if physical and _hurt_time > 0.0:
		return
	var applied := amount
	if physical:
		var armor := 0.0
		var worn: Array[int] = []
		for index in range(4):
			var stack := _inventory.equipment.stack_at(index)
			if _api.item_instances.usable(stack):
				var value := float(_api.item_instances.stats(stack).get("armor", 0.0))
				armor += value
				if value > 0.0:
					worn.append(index)
		applied *= 1.0 - clampf(armor * 0.04, 0.0, 0.8)
		if applied < amount:
			for index in worn:
				_api.item_instances.spend_container(_inventory.equipment, index)
		_hurt_time = 0.35
	var taken := minf(health, applied)
	health -= taken
	damaged.emit(taken, context)
	_flash.color.a = 0.2
	if health <= 0.0:
		depleted.emit(context)
		_die(context)
	_persist()
	_refresh_hud()

func heal(amount: float) -> bool:
	if dead or amount <= 0.0 or not is_finite(amount) or health >= MAX_HEALTH:
		return false
	health = minf(MAX_HEALTH, health + amount)
	_refresh_hud()
	_persist()
	return true

func try_bandage() -> bool:
	if dead or health >= MAX_HEALTH or not _inventory.remove_item("survival:bandage", 1):
		return false
	return heal(6.0)

func _physics_process(delta: float) -> void:
	if _api == null or dead:
		return
	_hurt_time = maxf(_hurt_time - delta, 0.0)
	_spawn_protection = maxf(_spawn_protection - delta, 0.0)
	var head := _player.get_node("Camera3D") as Camera3D
	var block := _api.world.get_block_id(Vector3i(head.global_position.floor()))
	var underwater := block == "core:water"
	var feet_in_water := _api.world.get_block_id(Vector3i((_player.global_position + Vector3.UP * 0.1).floor())) == "core:water"
	tick_breath(delta, underwater)
	track_landing(_player.global_position.y, _player.is_on_floor(), underwater or feet_in_water, _player.global_position.distance_to(_last_position) > 30.0)
	_last_position = _player.global_position
	if _player.global_position.y < -256.0:
		receive_damage(MAX_HEALTH, {"damage_type": "void"})
	if _vitals != null:
		var hunger := float(_vitals.get("hunger"))
		if hunger >= 18.0 and health < MAX_HEALTH:
			_regen_clock += delta
			if _regen_clock >= 4.0:
				_regen_clock -= 4.0
				if heal(1.0):
					_vitals.set("hunger", maxf(hunger - 0.25, 0.0))
		else:
			_regen_clock = 0.0
		if hunger <= 0.0:
			_starve_clock += delta
			if _starve_clock >= 4.0:
				_starve_clock -= 4.0
				receive_damage(1.0, {"damage_type": "starvation"})
		else:
			_starve_clock = 0.0
		if float(_vitals.get("poison_seconds")) > 0.0:
			_poison_clock += delta
			if _poison_clock >= 1.0:
				_poison_clock -= 1.0
				receive_damage(1.0, {"damage_type": "poison"})
		else:
			_poison_clock = 0.0
	_save_clock += delta
	if _save_clock >= 1.0:
		_save_clock = 0.0
		_persist()
	_refresh_hud()

func tick_breath(delta: float, underwater: bool) -> void:
	if dead:
		return
	if underwater:
		var exposure := maxf(delta - oxygen, 0.0)
		oxygen = maxf(oxygen - delta, 0.0)
		_drown_clock += exposure
		while _drown_clock >= 1.0 and not dead:
			_drown_clock -= 1.0
			receive_damage(2.0, {"damage_type": "drowning"})
	else:
		oxygen = minf(MAX_OXYGEN, oxygen + delta * 3.0)
		_drown_clock = 0.0

func track_landing(height: float, grounded: bool, cushioned: bool = false, teleported: bool = false) -> void:
	if dead:
		return
	if teleported or cushioned:
		_fall_peak = height
		_was_grounded = grounded
		return
	if not grounded:
		_fall_peak = maxf(_fall_peak, height)
	elif not _was_grounded:
		var distance := _fall_peak - height
		if distance > 3.0:
			receive_damage(floorf(distance - 3.0), {"damage_type": "fall"})
		_fall_peak = height
	else:
		_fall_peak = height
	_was_grounded = grounded

func _persist() -> void:
	if _api == null:
		return
	var data := {"health": health, "oxygen": oxygen, "dead": dead}
	if _vitals != null:
		for field in ["hunger", "stamina", "poison_seconds"]:
			data[field] = _vitals.get(field)
	_api.stations.set_player_data(STATE_ID, data)
	if not _api.stations.path.is_empty() and is_instance_valid(_api.stations.inventory):
		_api.stations.save()

func _die(context: Dictionary, notify: bool = true) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	_player.set_meta("gameplay_disabled", true)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	var interactor := _player.get_node("VoxelInteractor") as VoxelInteractor
	interactor._reset_breaking()
	interactor.primary_held = false
	interactor.secondary_held = false
	_inventory.return_cursor()
	_player.get_tree().call_group("station_ui", "close")
	_player.get_tree().call_group("inventory_ui", "set_open", false)
	if _vitals != null:
		_vitals.set_physics_process(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_death_screen(str(context.get("damage_type", "damage")))
	if notify:
		_api.events.emit(GameEvents.PLAYER_DIED, {"player": _player, "context": context})
	_persist()

func respawn() -> void:
	if not dead:
		return
	dead = false
	health = MAX_HEALTH
	oxygen = MAX_OXYGEN
	_hurt_time = 0.0
	_spawn_protection = 3.0
	_drown_clock = 0.0
	_regen_clock = 0.0
	_starve_clock = 0.0
	_poison_clock = 0.0
	if _vitals != null:
		_vitals.set("hunger", 18.0)
		_vitals.set("stamina", 100.0)
		_vitals.set("poison_seconds", 0.0)
		_vitals.set_physics_process(true)
	if GameAPI.session != null and GameAPI.session.has_method("get_safe_spawn_position"):
		_player.global_position = GameAPI.session.call("get_safe_spawn_position")
	else:
		_player.global_position = _last_position
	_last_position = _player.global_position
	_fall_peak = _last_position.y
	_was_grounded = true
	_player.velocity = Vector3.ZERO
	_player.set_meta("gameplay_disabled", false)
	_player.set_physics_process(true)
	if is_instance_valid(_death_ui):
		_death_ui.queue_free()
	_death_ui = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_refresh_hud()
	_persist()
	_api.events.emit(GameEvents.PLAYER_RESPAWNED, {"player": _player})

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 25
	add_child(_hud)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.8, 0.05, 0.05, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_flash)
	var box := VBoxContainer.new()
	box.position = Vector2(18, 132)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(box)
	_health_label = Label.new()
	box.add_child(_health_label)
	_oxygen_bar = ProgressBar.new()
	_oxygen_bar.custom_minimum_size = Vector2(210, 14)
	_oxygen_bar.max_value = MAX_OXYGEN
	_oxygen_bar.tooltip_text = "Oxygen"
	_oxygen_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_oxygen_bar)

func _process(delta: float) -> void:
	if _flash != null:
		_flash.color.a = maxf(_flash.color.a - delta * 0.5, 0.0)

func _refresh_hud() -> void:
	if _health_label == null:
		return
	_health_label.text = "Health %.0f / 20" % health
	_oxygen_bar.value = oxygen
	_oxygen_bar.visible = oxygen < MAX_OXYGEN

func _build_death_screen(reason: String) -> void:
	_death_ui = CanvasLayer.new()
	_death_ui.layer = 60
	add_child(_death_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_ui.add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.15, 0.02, 0.02, 0.85)
	root.add_child(shade)
	var box := VBoxContainer.new()
	root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -170
	box.offset_right = 170
	box.offset_top = -75
	box.offset_bottom = 75
	box.custom_minimum_size = Vector2(340, 0)
	var title := Label.new()
	title.text = "You died — " + reason.capitalize()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var description := Label.new()
	description.text = "Your inventory is retained."
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)
	var button := Button.new()
	button.text = "Respawn"
	button.pressed.connect(respawn)
	box.add_child(button)
