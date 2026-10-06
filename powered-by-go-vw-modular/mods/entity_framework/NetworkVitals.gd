extends DamageReceiver

## Network creature combat uses server health. Client mirrors cannot apply damage.
var runtime: Node
var player: PlayerController
var dead := false
var cooldown := 0.0
var protection := 3.0
var clock := 0.0
var hud: CanvasLayer
var label: Label
var respawn_button: Button

func setup(owner_runtime: Node) -> void:
	runtime = owner_runtime
	player = get_parent() as PlayerController
	health = 20
	if player.is_multiplayer_authority():
		hud = CanvasLayer.new()
		hud.layer = 40
		add_child(hud)
		var box := VBoxContainer.new()
		box.position = Vector2(18, 132)
		hud.add_child(box)
		label = Label.new()
		box.add_child(label)
		respawn_button = Button.new()
		respawn_button.text = "Respawn (inventory retained)"
		respawn_button.pressed.connect(_request_respawn)
		box.add_child(respawn_button)
		_refresh()

func _physics_process(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	protection = maxf(0, protection - delta)
	if not runtime.authority():
		return
	clock += delta
	if clock >= 0.2:
		clock = 0
		status.rpc(health, dead, player.global_position)

func receive_damage(amount: float, context: Dictionary) -> void:
	if not runtime.authority() or dead or protection > 0 or cooldown > 0 or not is_finite(amount) or amount <= 0:
		return
	var armor := 0.0
	var inventory := player.get_node("Inventory") as Inventory
	for i in range(4):
		var stack := inventory.equipment.stack_at(i)
		if runtime.api.item_instances.usable(stack):
			var points := float(runtime.api.item_instances.stats(stack).get("armor", 0))
			armor += points
			if points > 0:
				runtime.api.item_instances.spend_container(inventory.equipment, i)
	var applied := minf(health, amount * (1 - clampf(armor * 0.04, 0, 0.8)))
	health -= applied
	cooldown = 0.35
	damaged.emit(applied, context)
	if health <= 0:
		dead = true
		player.set_meta("gameplay_disabled", true)
		depleted.emit(context)
		runtime.api.events.emit(GameEvents.PLAYER_DIED, {"player": player, "context": context})
	_apply_local()
	runtime.save_inventory(player)
	status.rpc(health, dead, player.global_position)

@rpc("authority", "reliable")
func status(value: float, is_dead: bool, position: Vector3) -> void:
	if runtime.authority():
		return
	var was_dead := dead
	health = value
	dead = is_dead
	player.set_meta("gameplay_disabled", dead)
	if was_dead and not dead:
		player.global_position = position
		if player.is_multiplayer_authority():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_apply_local()

func _apply_local() -> void:
	player.set_meta("gameplay_disabled", dead)
	if player.is_multiplayer_authority():
		player.set_physics_process(not dead)
		if dead:
			player.velocity = Vector3.ZERO
			player.get_node("VoxelInteractor").primary_held = false
			player.get_node("VoxelInteractor").secondary_held = false
			player.get_tree().call_group("inventory_ui", "set_open", false)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_refresh()

func _refresh() -> void:
	if label != null:
		label.text = "Health %.0f / 20%s" % [health, " — You died" if dead else ""]
		respawn_button.visible = dead

func _request_respawn() -> void:
	if runtime.authority():
		_respawn()
	else:
		request_respawn.rpc_id(1)

@rpc("any_peer", "reliable")
func request_respawn() -> void:
	if runtime.authority() and multiplayer.get_remote_sender_id() == player.get_multiplayer_authority():
		_respawn()

func _respawn() -> void:
	if not dead:
		return
	dead = false
	health = 20
	protection = 3
	var session := player.get_parent().get_parent()
	if session.has_method("get_safe_spawn_position"):
		player.global_position = session.call("get_safe_spawn_position")
	_apply_local()
	if player.is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	status.rpc(health, false, player.global_position)
	runtime.save_inventory(player)
	runtime.api.events.emit(GameEvents.PLAYER_RESPAWNED, {"player": player})

func restore(data: Dictionary) -> void:
	var value := float(data.get("health", 20))
	health = clampf(value, 0, 20) if is_finite(value) else 20
	dead = health <= 0
	_apply_local()
