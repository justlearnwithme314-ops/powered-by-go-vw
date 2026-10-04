class_name GameMod
extends RefCounted

## Base class for executable mods.
##
## A mod normally implements only register(api). Runtime behavior can be
## added by subscribing to events or registering world-generation stages.

func register(api: ModAPI) -> void:
	pass

