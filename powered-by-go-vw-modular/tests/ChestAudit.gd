extends Node
func _ready() -> void:
	var model: Resource = GameAPI.content.get_block("survival:chest").model
	print("[ChestProbe] model=",model.get_class()," collision_aabbs=",model.get("collision_aabbs"))
	for p in model.get_property_list():
		if "collision" in str(p.name): print("[ChestProbe] ",p)
	scan("res://core")
	scan("res://scenes")
	scan("res://mods/basic_survival")
	print("[ChestProbe] native binaries=",DirAccess.get_files_at("res://addons/zylann.voxel/bin"))
	get_tree().quit()
func scan(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"): continue
		var p := dir.path_join(f)
		var text := FileAccess.get_file_as_string(p)
		if "submit_block_break" in text or "network_request" in text or "func use(" in text: print("[ChestProbe] relevant=",p)
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."): scan(dir.path_join(d))
