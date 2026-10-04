class_name EventBus
extends RefCounted

## Generic gameplay event bus.
##
## Events are dictionaries on purpose:
## a mod can add fields without changing the engine API.
##
## Example:
##   api.on(GameEvents.BEFORE_BLOCK_BREAK, _on_break)
##   api.events.emit(GameEvents.BEFORE_BLOCK_BREAK, {
##       "player": player,
##       "position": pos,
##       "block_id": "core:stone",
##       "cancelled": false
##   })

var _listeners: Dictionary = {}


func subscribe(event_name: String, callback: Callable, priority: int = 0) -> void:
	if not callback.is_valid():
		push_warning("[EventBus] Ignoring invalid callback for '%s'." % event_name)
		return

	if not _listeners.has(event_name):
		_listeners[event_name] = []

	var entries: Array = _listeners[event_name]
	for entry in entries:
		if entry["callback"] == callback:
			return

	entries.append({
		"callback": callback,
		"priority": priority,
	})

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) > int(b["priority"])
	)

	_listeners[event_name] = entries


func unsubscribe(event_name: String, callback: Callable) -> void:
	if not _listeners.has(event_name):
		return

	var entries: Array = _listeners[event_name]
	for i in range(entries.size() - 1, -1, -1):
		if entries[i]["callback"] == callback:
			entries.remove_at(i)

	if entries.is_empty():
		_listeners.erase(event_name)


func emit(event_name: String, payload: Dictionary = {}) -> Dictionary:
	var event_data := payload.duplicate(true)

	if not _listeners.has(event_name):
		return event_data

	var entries: Array = _listeners[event_name].duplicate()
	for entry in entries:
		var callback: Callable = entry["callback"]
		if callback.is_valid():
			var result = callback.call(event_data)
			if result is Dictionary:
				event_data = result

	return event_data
