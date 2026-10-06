extends Node

const SESSION = preload("res://tests/MultiplayerPresentationSession.gd")
const PLAYER: PackedScene = preload("res://scenes/player/Player.tscn")
const STATE = preload("res://core/network/PlayerSyncState.gd")
var failures: int = 0

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func branch(label: String, peer: ENetMultiplayerPeer) -> Node:
	var base: Node = Node.new()
	base.name = label
	get_tree().root.add_child(base)
	var api: SceneMultiplayer = SceneMultiplayer.new()
	get_tree().set_multiplayer(api, base.get_path())
	api.multiplayer_peer = peer
	var game: Node = SESSION.new()
	game.name = "Game"
	var players: Node = Node.new()
	players.name = "Players"
	var spawn_point: Marker3D = Marker3D.new()
	spawn_point.name = "SpawnPoint"
	players.add_child(spawn_point)
	game.add_child(players)
	base.add_child(game)
	return game

func add_player(game: Node, id: int) -> PlayerController:
	var player: PlayerController = PLAYER.instantiate() as PlayerController
	player.name = str(id)
	game.get_node("Players").add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.get_node("PlayerVisual").set_process(false)
	return player

func wait_packets() -> void:
	await get_tree().create_timer(0.15).timeout

func run() -> void:
	check(STATE.sanitize({"velocity": Vector3(NAN, 0, 0)}).is_empty(), "Reject nonfinite velocity")
	check(STATE.sanitize({"pose": "bad"}).is_empty(), "Reject invalid pose")
	var clean: Dictionary = STATE.sanitize({"height": INF, "pose": {"roll_progress": 3.0, "unexpected": "discard"}})
	check(clean.height == 1.9 and clean.pose.roll_progress == 1.0 and not clean.pose.has("unexpected"), "Bound numeric state and discard unknown pose fields")
	var server_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var port: int = 31000 + int(Time.get_ticks_msec() % 10000)
	check(server_peer.create_server(port, 4) == OK, "Create test server")
	var host: Node = branch("Host", server_peer)
	var client_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	check(client_peer.create_client("127.0.0.1", port) == OK, "Create test client")
	var client: Node = branch("Client", client_peer)
	for attempt: int in range(100):
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await get_tree().create_timer(0.02).timeout
	check(client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "Connect ENet peers")
	var client_id: int = client.multiplayer.get_unique_id()
	host.spawned_peer_ids.assign([1, client_id])
	var host_owner: PlayerController = add_player(host, 1)
	var host_remote: PlayerController = add_player(host, client_id)
	var client_remote: PlayerController = add_player(client, 1)
	var client_owner: PlayerController = add_player(client, client_id)
	client_owner.position = Vector3(99, 0, 0)
	for pose: Dictionary in [{"crouching": true}, {"sitting": true}, {"lying": true}, {"rolling": true, "roll_progress": 0.5}, {}]:
		var state: Dictionary = {"velocity": Vector3(3, 0, 0), "height": 1.25, "airborne": false, "pose": pose, "animation_phase": 0.4, "swing": 0.7}
		client.submit_player_sync(client_id, Vector3(4, 0, 3), 0.7, -0.4, "core:pistol", state)
		await wait_packets()
		check(host_remote.visual_pose == STATE.sanitize(state).pose, "Client pose reaches host")
		check(is_equal_approx(host_remote.interaction_swing, 0.7), "Interaction swing reaches remote peers")
		check(host_remote.position.is_equal_approx(Vector3(4, 0, 3)), "Server edit position stays current")
		check(host_remote.current_height == 1.25 and host_remote.collision_shape.shape.height == 1.25, "Remote posture updates collider")
		check(not host_remote.remote_airborne and host_remote.velocity.x == 3.0, "Grounded locomotion is explicit")
		check(client_owner.position.x == 99, "Owner ignores echoed state")
		var visual: PlayerVisual = host_remote.get_node("PlayerVisual")
		visual._update_pose(3.0)
		var model: Node3D = visual.body
		check(model.state == (&"idle" if pose.get("sitting", false) or pose.get("lying", false) or pose.get("rolling", false) else &"walk"), "Remote animation follows pose and velocity")
		check(absf(model.get_animation_phase() - 0.4) < 0.001, "Animation phase matches source")
		check(visual.pistol.visible and not visual.first_person_pistol.visible, "Remote held pistol stays third person")
	# Host state must also reach clients, including airborne players at the apex.
	host.submit_player_sync(1, Vector3(2, 3, 4), -0.8, 0.5, "", {"velocity": Vector3.ZERO, "airborne": true})
	await wait_packets()
	check(client_remote.remote_airborne, "Host airborne state reaches client without vertical displacement")
	var remote_visual: PlayerVisual = client_remote.get_node("PlayerVisual")
	remote_visual._update_pose(0.0)
	check(remote_visual.body.get("state") == &"jump", "Jump remains active at apex")
	# A second snapshot blends instead of teleporting, including wrapped yaw.
	var before: Vector3 = client_remote.position
	host.submit_player_sync(1, Vector3(3, 3, 4), 0.8, -0.5, "", {"velocity": Vector3.ZERO})
	await wait_packets()
	check(client_remote.position == before, "Ordinary snapshots wait for interpolation")
	client_remote._process(0.025)
	check(client_remote.position.x > before.x and client_remote.position.x < 3.0, "Remote transform interpolates")
	check(host_owner.visual_pose.is_empty(), "Host owner stays locally controlled")
	server_peer.close()
	client_peer.close()
	get_tree().root.get_node("Host").free()
	get_tree().root.get_node("Client").free()
	print("Multiplayer presentation: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	get_tree().quit(0 if failures == 0 else 1)
