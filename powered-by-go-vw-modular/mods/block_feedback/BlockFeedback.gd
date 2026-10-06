extends Node3D

var overlay: MeshInstance3D
var material: StandardMaterial3D
var frames: Array[Texture2D] = []
var _api: ModAPI
var _sounds: Dictionary = {}
var _interactor: VoxelInteractor

func setup(interactor: VoxelInteractor, api: ModAPI) -> void:
	_api = api
	_interactor = interactor
	for stage in range(8):
		frames.append(api.load_asset("textures/cracks-%d.png" % stage) as Texture2D)
	material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.15
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = frames[0]
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cube := SurfaceTool.new()
	cube.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Full 0..1 UVs on every face; no cube atlas stretching or neighboring frames.
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var right: Vector3 = normal.cross(Vector3.UP).normalized() if absf(normal.y) < 0.5 else Vector3.RIGHT
		var up: Vector3 = normal.cross(right)
		var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for index in [0, 1, 2, 0, 2, 3]:
			var corner := corners[index]
			cube.set_normal(normal)
			cube.set_uv((corner + Vector2.ONE) * 0.5)
			cube.add_vertex((normal + right * corner.x + up * corner.y) * 0.503)
	overlay = MeshInstance3D.new()
	overlay.mesh = cube.commit()
	overlay.material_override = material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(overlay)
	overlay.top_level = true
	overlay.hide()
	for kind in ["stone", "wood", "earth"]:
		_sounds[kind] = api.load_asset("sounds/%s.ogg" % kind)
	interactor.mining_progress.connect(_progress)
	interactor.mining_cleared.connect(_clear)
	interactor.block_feedback.connect(_feedback)

func stage_for_progress(progress: float) -> int:
	return 0 if progress <= 0.0 else clampi(ceili(clampf(progress, 0.0, 1.0) * 7.0), 1, 7)

func _progress(position: Vector3i, progress: float) -> void:
	material.albedo_texture = frames[stage_for_progress(progress)]
	overlay.global_position = Vector3(position) + Vector3.ONE * 0.5
	overlay.visible = progress > 0.0

func _clear() -> void:
	if overlay != null:
		overlay.hide()

func _feedback(block_id: String, position: Vector3i, action: String) -> void:
	var definition := _api.content.get_block(block_id)
	var preferred := str(definition.get("preferred_tool", ""))
	var kind := "wood" if preferred == "axe" else ("earth" if preferred == "shovel" else "stone")
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _sounds[kind] as AudioStream
	sound.volume_db = -14.0 if action == "hit" else -8.0
	sound.pitch_scale = randf_range(0.92, 1.08) * (0.85 if action == "break" else 1.0)
	sound.max_distance = 24.0
	add_child(sound)
	sound.global_position = Vector3(position) + Vector3.ONE * 0.5
	sound.finished.connect(sound.queue_free)
	sound.play()
