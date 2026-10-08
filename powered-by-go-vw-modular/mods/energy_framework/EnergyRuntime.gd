extends Node

var _api: ModAPI


func setup(api: ModAPI) -> void:
	_api = api


func _process(_delta: float) -> void:
	if _api == null:
		return
	_api.energy.advance_rebuilds(EnergyService.DEFAULT_REBUILD_SLICE)


func reset() -> void:
	if _api != null:
		_api.energy.reset()
