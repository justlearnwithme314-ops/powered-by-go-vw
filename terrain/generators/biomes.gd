class_name BiomeGenerator


static func get_biome(
	wx: int,
	wz: int,
	noise: WorldNoise
) -> Biome.Type:

	var temperature = noise.temperature.get_noise_2d(wx, wz)

	var humidity = noise.humidity.get_noise_2d(wx, wz)

	# Mountains

	if temperature < -0.45:
		return Biome.Type.MOUNTAINS

	# Snow

	if temperature < -0.15:
		return Biome.Type.SNOW

	# Desert

	if temperature > 0.45 and humidity < 0:
		return Biome.Type.DESERT

	# Forest

	if humidity > 0.25:
		return Biome.Type.FOREST

	return Biome.Type.PLAINS
