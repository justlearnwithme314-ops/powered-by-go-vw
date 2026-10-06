extends PanelContainer

var owner_ui: CanvasLayer
var index := 0
var equipped := false
var hovered := false
var icon: TextureRect
var count_label: Label
var drag_started := false
var condition_bar: ProgressBar

func _ready() -> void:
	custom_minimum_size = Vector2(58, 58)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var style := StyleBoxFlat.new()
	style.bg_color = Color("35393e")
	style.border_color = Color("737b82")
	style.set_border_width_all(2)
	style.set_corner_radius_all(3)
	add_theme_stylebox_override("panel", style)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	icon = TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 7
	icon.offset_top = 7
	icon.offset_right = -7
	icon.offset_bottom = -7
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)
	count_label = Label.new()
	count_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.offset_left = -53
	count_label.offset_top = -24
	count_label.offset_right = -4
	count_label.offset_bottom = -2
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	count_label.add_theme_constant_override("shadow_offset_x", 2)
	count_label.add_theme_constant_override("shadow_offset_y", 2)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(count_label)
	condition_bar = ProgressBar.new()
	condition_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	condition_bar.offset_left = 5
	condition_bar.offset_right = -5
	condition_bar.offset_top = -7
	condition_bar.offset_bottom = -3
	condition_bar.show_percentage = false
	condition_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	condition_bar.hide()
	root.add_child(condition_bar)
	if not equipped and index < Inventory.HOTBAR_SIZE:
		var number := Label.new()
		number.text = str((index + 1) % 10)
		number.position = Vector2(3, 0)
		number.add_theme_font_size_override("font_size", 11)
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(number)
	mouse_entered.connect(_entered)
	mouse_exited.connect(_exited)

func _entered() -> void:
	hovered = true
	owner_ui.hovered_slot = self
	modulate = Color(1.25, 1.25, 1.25)

func _exited() -> void:
	hovered = false
	if owner_ui.hovered_slot == self:
		owner_ui.hovered_slot = null
	modulate = Color.WHITE

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and owner_ui.inventory_open:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			owner_ui.slot_clicked(index, equipped, event.button_index == MOUSE_BUTTON_RIGHT, event.shift_pressed, event.double_click)
			accept_event()

func _get_drag_data(_position: Vector2) -> Variant:
	if not owner_ui.inventory_open or owner_ui.inventory.cursor.stack_at(0).is_empty():
		return null
	drag_started = true
	return {"inventory_owner": owner_ui.get_instance_id()}

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("inventory_owner", 0) == owner_ui.get_instance_id()

func _drop_data(_position: Vector2, _data: Variant) -> void:
	owner_ui.slot_clicked(index, equipped, false, false, false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and drag_started:
		drag_started = false
		if not get_viewport().gui_is_drag_successful():
			owner_ui.inventory.return_cursor()
