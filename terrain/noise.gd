class_name WorldNoise

var terrain: FastNoiseLite
var ores: FastNoiseLite
var caves: FastNoiseLite
var trees: FastNoiseLite
var temperature: FastNoiseLite
var humidity: FastNoiseLite
func _init() -> void:
	terrain = _create_terrain_noise()
	ores = _create_ore_noise()
	caves = _create_cave_noise()
	trees = _create_tree_noise()
	temperature = _create_temperature_noise()
	humidity = _create_humidity_noise()


func _create_terrain_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()

	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.008

	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0

	return noise


func _create_ore_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()

	noise.seed = 4242
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.045

	return noise


func _create_cave_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()

	noise.seed = 9001
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	noise.frequency = 0.018

	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0

	return noise


func _create_tree_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()

	noise.seed = 12001
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02

	return noise
func _create_temperature_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()

	noise.seed = 15000
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.0015

	return noise


func _create_humidity_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()

	noise.seed = 16000
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.0015

	return noise
