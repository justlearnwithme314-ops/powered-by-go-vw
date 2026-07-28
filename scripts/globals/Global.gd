extends Node

# Central reference to the active voxel world terrain
var active_terrain: VoxelTerrain = null

# Block registry dictionary for your upcoming modding platform
var block_registry: Dictionary = {
	"govw:air": {"id": 0, "solid": false, "transparent": true},
	"govw:stone": {"id": 1, "solid": true, "transparent": false},
	"govw:dirt": {"id": 2, "solid": true, "transparent": false},
	"govw:grass": {"id": 3, "solid": true, "transparent": false}
}

func register_block(block_id: String, properties: Dictionary) -> void:
	if block_registry.has(block_id):
		push_warning("Overwriting registered block: " + block_id)
	block_registry[block_id] = properties
	print("[Registry] Registered block: ", block_id)
