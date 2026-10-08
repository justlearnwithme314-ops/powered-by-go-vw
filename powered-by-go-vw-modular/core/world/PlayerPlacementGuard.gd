extends RefCounted

## Rejects a voxel placement that would overlap the placing player's collision body.
static func overlaps_player_cell(player: Node, cell: Vector3i) -> bool:
	if not player is Node3D:
		return false
	var collision := (player as Node).find_child("CollisionShape3D", true, false) as CollisionShape3D
	if collision == null or collision.shape == null:
		return Vector3i((player as Node3D).global_position.floor()) == cell
	var extents := Vector3(0.5, 0.9, 0.5)
	var shape := collision.shape
	if shape is CapsuleShape3D:
		extents = Vector3(shape.radius, shape.height * 0.5, shape.radius)
	elif shape is CylinderShape3D:
		extents = Vector3(shape.radius, shape.height * 0.5, shape.radius)
	elif shape is SphereShape3D:
		extents = Vector3.ONE * shape.radius
	elif shape is BoxShape3D:
		extents = shape.size * 0.5
	var center := collision.global_position
	var minimum := center - extents
	var maximum := center + extents
	return (
		minimum.x < float(cell.x + 1) and maximum.x > float(cell.x)
		and minimum.y < float(cell.y + 1) and maximum.y > float(cell.y)
		and minimum.z < float(cell.z + 1) and maximum.z > float(cell.z)
	)
