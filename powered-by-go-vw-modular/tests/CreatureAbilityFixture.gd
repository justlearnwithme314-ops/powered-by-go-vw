extends Node
var decisions := 0
var interactions := 0
func decide(_actor: Node3D) -> bool:
	decisions += 1
	return false
func interact(_player: Node3D) -> void:
	interactions += 1
func save_state() -> Dictionary:
	return {"interactions": interactions}
func restore(data: Dictionary) -> void:
	interactions = int(data.get("interactions", 0))
