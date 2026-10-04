class_name WorldNoise
extends RefCounted

var world_seed: int

var terrain: FastNoiseLite
var ores: FastNoiseLite
var caves: FastNoiseLite
var trees: FastNoiseLite
var temperature: FastNoiseLite
var humidity: FastNoiseLite

var _custom: Dictionary = {}


func _init(seed_value: int = 1337) -> void:
	world_seed = seed_value
	terrain = _create_2d(0x13579, 0.008, 4, 0.5)
	ores = _create_3d(0x24680, 0.045, 1, 0.5)
	caves = _create_3d(0x36912, 0.018, 5, 0.5)
	trees = _create_2d(0x48150, 0.02, 1, 0.5)
	temperature = _create_2d(0x59262, 0.0015, 1, 0.5)
	humidity = _create_2d(0x61373, 0.0015, 1, 0.5)


func get_custom_2d(key: String, frequency: float = 0.01, octaves: int = 1) -> FastNoiseLite:
	if _custom.has("2d|" + key):
		return _custom["2d|" + key]

	var noise := _create_2d(
		_stable_offset(key),
		frequency,
		octaves,
		0.5
	)
	_custom["2d|" + key] = noise
	return noise


func get_custom_3d(key: String, frequency: float = 0.01, octaves: int = 1) -> FastNoiseLite:
	if _custom.has("3d|" + key):
		return _custom["3d|" + key]

	var noise := _create_3d(
		_stable_offset(key),
		frequency,
		octaves,
		0.5
	)
	_custom["3d|" + key] = noise
	return noise


func _stable_offset(key: String) -> int:
	var hash_value := key.hash()
	return int(hash_value ^ world_seed)


func _create_2d(
	offset: int,
	frequency: float,
	octaves: int,
	gain: float
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed + offset
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = frequency

	if octaves > 1:
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = octaves
		noise.fractal_gain = gain
		noise.fractal_lacunarity = 2.0

	return noise


func _create_3d(
	offset: int,
	frequency: float,
	octaves: int,
	gain: float
) -> FastNoiseLite:
	var noise := _create_2d(offset, frequency, octaves, gain)
	return noise
