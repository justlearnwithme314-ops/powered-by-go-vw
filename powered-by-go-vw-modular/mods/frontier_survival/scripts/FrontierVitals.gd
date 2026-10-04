extends Node

## Local survival state for one authoritative player.
##
## This node is intentionally mod-owned. It adds survival pressure without
## making the core Inventory or PlayerController depend on a specific mod.

const MAX_HUNGER: float = 20.0
const MAX_STAMINA: float = 100.0
const NORMAL_SPEED: float = 6.0
const SPRINT_SPEED: float = 9.0

var player: CharacterBody3D
var inventory: Inventory

var hunger: float = 18.0
var stamina: float = MAX_STAMINA
var poison_seconds: float = 0.0

var _ui_layer: CanvasLayer
var _hunger_label: Label
var _stamina_bar: TextureProgressBar
var _status_label: Label
var _base_speed: float = NORMAL_SPEED
var _ui_update_timer: float = 0.0


func _ready() -> void:
	player = get_parent() as CharacterBody3D

	if player == null:
		queue_free()
		return

	inventory = player.get_node_or_null("Inventory") as Inventory

	if not player.is_multiplayer_authority():
		return

	var speed_value: Variant = player.get("speed")
	_base_speed = float(speed_value)

	if _base_speed <= 0.0:
		_base_speed = NORMAL_SPEED

	_build_hud()
	_refresh_hud()


func initialize_state(initial_hunger: float) -> void:
	hunger = clampf(
		initial_hunger,
		0.0,
		MAX_HUNGER
	)

	stamina = MAX_STAMINA
	_refresh_hud()


func _physics_process(delta: float) -> void:
	if player == null:
		return

	if not player.is_multiplayer_authority():
		return

	var horizontal_velocity: Vector2 = Vector2(
		player.velocity.x,
		player.velocity.z
	)

	var moving: bool = horizontal_velocity.length() > 0.2

	var wants_sprint: bool = (
		Input.is_key_pressed(KEY_SHIFT)
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		and moving
		and player.is_on_floor()
	)

	var sprinting: bool = (
		wants_sprint
		and stamina > 1.0
		and hunger > 1.0
	)

	if sprinting:
		player.set(
			"speed",
			SPRINT_SPEED
		)

		stamina = move_toward(
			stamina,
			0.0,
			22.0 * delta
		)

	else:
		stamina = move_toward(
			stamina,
			MAX_STAMINA,
			15.0 * delta
		)

		var movement_speed: float = _base_speed

		if hunger <= 0.0:
			movement_speed *= 0.58

		elif hunger < 5.0:
			movement_speed *= 0.78

		player.set(
			"speed",
			movement_speed
		)

	hunger -= 0.012 * delta

	if moving:
		hunger -= 0.008 * delta

	if sprinting:
		hunger -= 0.020 * delta

	if poison_seconds > 0.0:
		poison_seconds = maxf(
			poison_seconds - delta,
			0.0
		)

		hunger -= 0.025 * delta

		stamina = move_toward(
			stamina,
			0.0,
			5.0 * delta
		)

	hunger = clampf(
		hunger,
		0.0,
		MAX_HUNGER
	)

	_ui_update_timer -= delta

	if _ui_update_timer <= 0.0:
		_ui_update_timer = 0.15
		_refresh_hud()


func try_eat(item_id: String) -> bool:
	if inventory == null:
		return false

	var item: Dictionary = GameAPI.content.get_item(item_id)

	var properties_value: Variant = item.get(
		"properties",
		{}
	)

	var properties: Dictionary = {}

	if properties_value is Dictionary:
		properties = properties_value

	var tags_value: Variant = item.get(
		"tags",
		[]
	)

	if not (tags_value is Array):
		return false

	var tags: Array = tags_value

	if not ("food" in tags):
		return false

	var food_value: float = float(
		properties.get(
			"food_value",
			0.0
		)
	)

	var stamina_restore: float = float(
		properties.get(
			"stamina_restore",
			0.0
		)
	)

	var poison_time: float = float(
		properties.get(
			"poison_seconds",
			0.0
		)
	)

	if (
		food_value > 0.0
		and hunger >= MAX_HUNGER - 0.05
	):
		return false

	if not inventory.remove_item(
		item_id,
		1
	):
		return false

	hunger = clampf(
		hunger + food_value,
		0.0,
		MAX_HUNGER
	)

	stamina = clampf(
		stamina + stamina_restore,
		0.0,
		MAX_STAMINA
	)

	if poison_time > 0.0:
		poison_seconds = maxf(
			poison_seconds,
			poison_time
		)

	_refresh_hud()

	return true


func _build_hud() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 20
	_ui_layer.name = "FrontierSurvivalHUD"

	player.add_child(_ui_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(
		18.0,
		18.0
	)

	panel.custom_minimum_size = Vector2(
		250.0,
		96.0
	)

	_ui_layer.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)

	var hunger_row: HBoxContainer = HBoxContainer.new()
	box.add_child(hunger_row)

	var heart: TextureRect = TextureRect.new()
	heart.custom_minimum_size = Vector2(
		18.0,
		18.0
	)

	heart.texture = _load_texture(
		str(
			player.get_meta(
				"frontier_heart_texture",
				""
			)
		)
	)

	heart.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)

	hunger_row.add_child(heart)

	_hunger_label = Label.new()
	hunger_row.add_child(_hunger_label)

	_stamina_bar = TextureProgressBar.new()

	_stamina_bar.custom_minimum_size = Vector2(
		216.0,
		14.0
	)

	_stamina_bar.min_value = 0.0
	_stamina_bar.max_value = MAX_STAMINA
	_stamina_bar.value = stamina

	# Do NOT use show_percentage here.
	# The current project/Godot build rejects that property.

	_stamina_bar.texture_under = _load_texture(
		str(
			player.get_meta(
				"frontier_stamina_bg",
				""
			)
		)
	)

	_stamina_bar.texture_progress = _load_texture(
		str(
			player.get_meta(
				"frontier_stamina_fg",
				""
			)
		)
	)

	box.add_child(_stamina_bar)

	_status_label = Label.new()
	box.add_child(_status_label)


func _refresh_hud() -> void:
	if _hunger_label == null:
		return

	_hunger_label.text = (
		"Hunger %d / 20"
		% roundi(hunger)
	)

	if _stamina_bar != null:
		_stamina_bar.value = stamina

	if _status_label == null:
		return

	if poison_seconds > 0.0:
		_status_label.text = (
			"POISONED  %.0fs"
			% poison_seconds
		)

	elif hunger <= 0.0:
		_status_label.text = (
			"STARVING  •  movement impaired"
		)

	elif hunger < 5.0:
		_status_label.text = (
			"Hungry  •  sprinting disabled soon"
		)

	elif stamina < 10.0:
		_status_label.text = "Exhausted"

	else:
		_status_label.text = (
			"Shift  Sprint   •   Right click food"
		)


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null

	var resource: Resource = ResourceLoader.load(path)

	if resource is Texture2D:
		return resource as Texture2D

	if FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)

		if image != null:
			return ImageTexture.create_from_image(image)

	return null
