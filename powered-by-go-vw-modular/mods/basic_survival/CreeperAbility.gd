extends Node

var fuse := 0.0
var detonated := false
var actor: CharacterBody3D

func setup(owner_actor: CharacterBody3D, _api: ModAPI) -> void:
	actor = owner_actor

func restore(data: Dictionary) -> void:
	fuse = clampf(float(data.get("fuse",0)),0,1.5)
	detonated = bool(data.get("detonated",false))

func save_state() -> Dictionary:
	return {"fuse":fuse,"detonated":detonated}

func tick(mob: CharacterBody3D, delta: float) -> void:
	if mob.replicated or mob.dead or detonated or not mob.runtime.api.world.is_loaded(Vector3i(mob.global_position.floor())): return
	if not is_instance_valid(mob.target): mob.target = mob.runtime.find_target(mob,16)
	var near: bool = is_instance_valid(mob.target) and mob.runtime.can_hit(mob,mob.target,3.8 if fuse>0 else 2.6)
	if near:
		fuse = minf(fuse+delta,1.5)
		mob._transition("fuse")
	else:
		fuse = maxf(fuse-delta*2,0)
		if mob.state == "fuse": mob._transition("chase" if is_instance_valid(mob.target) else "idle")
	if fuse >= 1.5:
		var service: Node = mob.runtime.get_parent().get_node_or_null("CreeperExplosions")
		if service != null:
			detonated = true
			if not bool(service.call("detonate",mob)): detonated = false

func decide(mob: CharacterBody3D) -> bool:
	if mob.state == "fuse": return true
	if not is_instance_valid(mob.target) or bool(mob.target.get_meta("gameplay_disabled",false)):
		mob.target = mob.runtime.find_target(mob,16)
	if is_instance_valid(mob.target):
		mob.goal = mob.target.global_position
		mob._transition("chase")
		return true
	# No target: reuse the shared roaming/home behaviour, without melee attacks.
	return false
