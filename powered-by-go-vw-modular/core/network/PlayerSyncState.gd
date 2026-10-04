class_name PlayerSyncState
extends RefCounted

## Fixed presentation contract: never replicate inventories or arbitrary mod data.
static func sanitize(state: Dictionary) -> Dictionary:
	var motion: Variant = state.get("velocity", Vector3.ZERO)
	if not motion is Vector3 or not (motion as Vector3).is_finite():
		return {}
	var pose_value: Variant = state.get("pose", {})
	if not pose_value is Dictionary:
		return {}
	var pose: Dictionary = {}
	for key: String in ["crouching", "sitting", "lying", "rolling"]:
		pose[key] = pose_value.get(key, false) == true
	pose["roll_progress"] = number(pose_value.get("roll_progress", 0.0), 0.0, 1.0, 0.0)
	return {
		"velocity": (motion as Vector3).limit_length(100.0),
		"airborne": state.get("airborne", false) == true,
		"height": number(state.get("height", 1.9), 0.8, 1.9, 1.9),
		"swing": number(state.get("swing", 0.0), 0.0, 1.0, 0.0),
		"pose": pose,
		"animation_phase": number(state.get("animation_phase", 0.0), 0.0, 1.0, 0.0),
	}

static func number(value: Variant, minimum: float, maximum: float, fallback: float) -> float:
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return clampf(float(value), minimum, maximum)
