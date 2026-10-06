extends Node

const SERVICE = preload("res://mods/player_skins/SkinService.gd")

func branch(label: String, peer: ENetMultiplayerPeer) -> Node:
	var base := Node.new()
	base.name = label
	get_tree().root.add_child(base)
	var network := SceneMultiplayer.new()
	get_tree().set_multiplayer(network, base.get_path())
	network.multiplayer_peer = peer
	var service := SERVICE.new()
	service.name = "SkinService"
	base.add_child(service)
	return service

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var server := ENetMultiplayerPeer.new()
	var port := 33000 + int(Time.get_ticks_msec() % 10000)
	assert(server.create_server(port, 4) == OK)
	var host := branch("SkinHost", server)
	var peer := ENetMultiplayerPeer.new()
	assert(peer.create_client("127.0.0.1", port) == OK)
	var client := branch("SkinClient", peer)
	for attempt in range(100):
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await get_tree().create_timer(0.02).timeout
	await get_tree().create_timer(0.1).timeout
	var id: int = client.multiplayer.get_unique_id()
	assert(id != 1)
	var image: Image = host.white_skin()
	image.fill(Color.RED)
	var bytes := image.save_png_to_buffer()
	assert(host.valid_skin(bytes))
	assert(not host.valid_skin(PackedByteArray([1,2,3])))
	assert(not host.valid_skin(Image.create(32,32,false,Image.FORMAT_RGBA8).save_png_to_buffer()))
	client.upload_skin.rpc_id(1, bytes)
	await get_tree().create_timer(0.2).timeout
	assert(host.skins.get(id) == bytes and client.skins.get(id) == bytes)
	host.accept_skin(1, host.white_skin().save_png_to_buffer())
	await get_tree().create_timer(0.2).timeout
	assert(client.skins.has(1))
	# A late joiner requests the full current cache.
	var late_peer := ENetMultiplayerPeer.new()
	assert(late_peer.create_client("127.0.0.1", port) == OK)
	var late := branch("SkinLate", late_peer)
	for attempt in range(100):
		if late_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await get_tree().create_timer(0.02).timeout
	await get_tree().create_timer(0.1).timeout
	late.request_skins.rpc_id(1)
	await get_tree().create_timer(0.2).timeout
	assert(late.skins.get(id) == bytes and late.skins.has(1))
	var body := load("res://mods/player_skins/PlayerBody.gd").new() as Node3D
	add_child(body)
	body.remove_from_group("minecraft_player_body")
	body.apply_skin(bytes)
	assert(body.material.albedo_texture.get_image().get_pixel(12,12).r == 1.0)
	assert(body.head.get_child_count() == 2, "Hat layer should exist")
	assert(body.get_item_socket().has_node("HeldTool"))
	print("Player skins PASS: validation, server relay, host skin, late-join cache, model texture and overlays")
	peer.close()
	late_peer.close()
	server.close()
	get_tree().quit()
