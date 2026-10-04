class_name RoguePreviewFixture
extends Node3D

@onready var model: RoguePlayerModel = $Rogue
var pose: Dictionary = {}
var speed: float = 0.0
var airborne: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		pose = {}
		speed = 0.0
		airborne = false
		match event.keycode:
			KEY_2: speed = 2.0
			KEY_3: airborne = true
			KEY_4: pose = {"sitting": true}
			KEY_5: pose = {"lying": true}
			KEY_6: pose = {"rolling": true, "roll_progress": 0.5}
			KEY_7: pose = {"crouching": true}
			KEY_8:
				pose = {"crouching": true}
				speed = 2.0

func _process(_delta: float) -> void:
	model.transform = PlayerVisual.pose_transform(pose, 1.25 if pose.has("crouching") or pose.has("sitting") else 1.9)
	# Preview faces the inspection camera; the in-game model faces -Z.
	model.rotate_y(PI)
	model.update_visual(pose, 1.25 if pose.has("crouching") else 1.9, speed, airborne)
