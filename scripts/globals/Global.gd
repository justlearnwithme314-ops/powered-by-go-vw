extends Node

# Central reference to the active voxel world terrain
var active_terrain: VoxelTerrain = null

# Main block registry for GO.VW
var block_registry: Dictionary = {
	"govw:air": {
		"id": Block.AIR,
		"solid": false,
		"transparent": true
	},
	"govw:grass": {
		"id": Block.GRASS,
		"solid": true,
		"transparent": false
	},
	"govw:dirt": {
		"id": Block.DIRT,
		"solid": true,
		"transparent": false
	},
	"govw:stone": {
		"id": Block.STONE,
		"solid": true,
		"transparent": false
	},
	"govw:log": {
		"id": Block.LOG,
		"solid": true,
		"transparent": false
	},
	"govw:leaves": {
		"id": Block.LEAVES,
		"solid": true,
		"transparent": true
	},
	"govw:iron": {
		"id": Block.IRON,
		"solid": true,
		"transparent": false
	},
	"govw:coal": {
		"id": Block.COAL,
		"solid": true,
		"transparent": false
	},
	"govw:gold": {
		"id": Block.GOLD,
		"solid": true,
		"transparent": false
	},
	"govw:diamond": {
		"id": Block.DIAMOND,
		"solid": true,
		"transparent": false
	},
	"govw:sand": {
		"id": Block.SAND,
		"solid": true,
		"transparent": false
	},
	"govw:snow": {
		"id": Block.SNOW,
		"solid": true,
		"transparent": false
	}
}


func register_block(block_id: String, properties: Dictionary) -> void:
	if block_registry.has(block_id):
		push_warning("Overwriting registered block: " + block_id)

	block_registry[block_id] = properties
	print("[Registry] Registered block: ", block_id)


func get_block_properties(block_id: String) -> Dictionary:
	if block_registry.has(block_id):
		return block_registry[block_id]

	return {}


func get_block_numeric_id(block_id: String) -> int:
	if block_registry.has(block_id):
		return block_registry[block_id].get("id", Block.AIR)

	return Block.AIR
