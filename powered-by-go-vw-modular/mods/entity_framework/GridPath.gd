extends RefCounted

## A bounded local search. Every waypoint is rechecked by the actor after edits.
static func find(world: VoxelWorldService, start: Vector3i, goal: Vector3i, limit: int = 128) -> Array[Vector3]:
	var frontier: Array[Vector3i] = [start]
	var came := {start: start}
	var best := start
	var best_distance := Vector2(start.x - goal.x, start.z - goal.z).length_squared()
	var visited := 0
	while not frontier.is_empty() and visited < limit:
		# Prefer cells nearer the destination without unbounded world searches.
		frontier.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return a.distance_squared_to(goal) < b.distance_squared_to(goal))
		var current: Vector3i = frontier.pop_front()
		visited += 1
		var distance := Vector2(current.x - goal.x, current.z - goal.z).length_squared()
		if distance < best_distance:
			best = current
			best_distance = distance
		if distance <= 1:
			best = current
			break
		for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			for dy in [0, 1, -1]:
				var next: Vector3i = current + offset + Vector3i(0, dy, 0)
				if came.has(next) or abs(next.y - start.y) > 5 or next.distance_squared_to(start) > 24 * 24:
					continue
				# A step up also needs room above the departure cell.
				if dy == 1 and (not world.is_loaded(current + Vector3i.UP * 2) or world.is_solid(current + Vector3i.UP * 2)):
					continue
				if world.can_stand(next):
					came[next] = current
					frontier.append(next)
					break
	var route: Array[Vector3] = []
	while best != start:
		route.push_front(Vector3(best) + Vector3(0.5, 0.05, 0.5))
		best = came[best]
	return route
