class_name WorldGenerationPipeline
extends RefCounted

## Ordered, deterministic world-generation pipeline.
##
## Mods register stages once during startup. A frozen GenerationRuntime is
## later handed to Zylann's VoxelGeneratorScript so worker threads never
## touch GameAPI or the mutable registry.

var content: ContentRegistry
var _stages: Array[Dictionary] = []
var _stage_ids: Dictionary = {}
var _finalized := false
var world_seed: int = 1337


func _init(p_content: ContentRegistry) -> void:
	content = p_content


func register_stage(stage_id: String, order: int, callback: Callable) -> bool:
	if _finalized:
		push_error(
			"[WorldGen] Cannot register '%s' after generation has been finalized."
			% stage_id
		)
		return false

	if stage_id.is_empty() or not callback.is_valid():
		return false

	if _stage_ids.has(stage_id):
		push_error("[WorldGen] Duplicate stage: %s" % stage_id)
		return false

	_stage_ids[stage_id] = true
	_stages.append({
		"id": stage_id,
		"order": order,
		"callback": callback,
	})
	return true


func finalize() -> void:
	if _finalized:
		return

	_stages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["order"]) == int(b["order"]):
			return str(a["id"]) < str(b["id"])
		return int(a["order"]) < int(b["order"])
	)
	_finalized = true

	print("[WorldGen] Finalized stages: ", get_stage_ids())


func get_stage_ids() -> Array[String]:
	var result: Array[String] = []
	for stage in _stages:
		result.append(str(stage["id"]))
	return result


func create_runtime() -> GenerationRuntime:
	if not _finalized:
		finalize()

	var snapshot := ContentSnapshot.new().from_registry(content)
	return GenerationRuntime.new().configure(
		world_seed,
		snapshot,
		_stages
	)


func generate(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	## Kept for tests/tools. Production VoxelTerrain generation uses the
	## frozen runtime above.
	create_runtime().generate(buffer, origin, lod)
