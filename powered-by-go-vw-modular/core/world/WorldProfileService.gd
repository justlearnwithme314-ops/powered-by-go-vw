class_name WorldProfileService
extends RefCounted

## Runtime settings scoped to the currently active world.
const PROFILE_VERSION := 1
const FEATURE_FLAGS := [
	"industry:machines",
	"industry:energy",
	"sandbox:explosives",
	"combat:projectiles",
	"industry:fluids",
	"world:structures",
]

var _active: Dictionary = {}


func normalize(config: Dictionary) -> Dictionary:
	var source_flags: Variant = config.get("feature_flags", {})
	if not source_flags is Dictionary:
		source_flags = {}
	var flags: Dictionary = {}
	for flag_id: String in FEATURE_FLAGS:
		flags[flag_id] = bool(source_flags.get(flag_id, false))
	var selected_mode := str(config.get("game_mode", "survival")).to_lower()
	if selected_mode not in ["survival", "creative"]:
		selected_mode = "survival"
	return {
		"profile_version": PROFILE_VERSION,
		"game_mode": selected_mode,
		"feature_flags": flags,
	}


func activate(config: Dictionary) -> Dictionary:
	_active = normalize(config)
	return snapshot()


func clear() -> void:
	_active.clear()


func mode() -> String:
	return str(_active.get("game_mode", "survival"))


func enabled(flag_id: String) -> bool:
	var flags: Dictionary = _active.get("feature_flags", {})
	return bool(flags.get(flag_id, false))


func snapshot() -> Dictionary:
	return normalize(_active)


## Call only with a snapshot received from the trusted session host.
func set_replica(config: Dictionary) -> void:
	_active = normalize(config)
