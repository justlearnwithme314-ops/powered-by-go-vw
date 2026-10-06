extends Node

const SAVE := "user://player_skin.png"
var skins: Dictionary = {}
var dialog: FileDialog
var message: AcceptDialog
var _last_upload: Dictionary = {}

func _ready() -> void:
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png ; Minecraft skin (64x64)"])
	dialog.title = "Select a 64x64 Minecraft PNG skin"
	add_child(dialog)
	dialog.file_selected.connect(_selected)
	message = AcceptDialog.new()
	add_child(message)
	multiplayer.peer_disconnected.connect(func(id: int): skins.erase(id))

func white_skin() -> Image:
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return image

func local_skin() -> Image:
	var image := Image.load_from_file(SAVE) if FileAccess.file_exists(SAVE) else null
	return image if image != null and image.get_size() == Vector2i(64,64) else white_skin()

func open_picker() -> void:
	dialog.popup_centered_ratio(0.75)

func _selected(path: String) -> void:
	if FileAccess.get_file_as_bytes(path).size() > 1048576:
		show_message("Choose a PNG smaller than 1 MB.")
		return
	var image := Image.load_from_file(path)
	if image == null or image.get_size() != Vector2i(64,64):
		show_message("Skin must be exactly 64x64 pixels.")
		return
	image.convert(Image.FORMAT_RGBA8)
	# Base skin is opaque; unused atlas areas never cover geometry.
	if image.save_png(SAVE) != OK:
		show_message("Could not save the skin.")
		return
	publish_local()
	show_message("Skin saved and applied.")

func show_message(text: String) -> void:
	message.dialog_text = text
	message.popup_centered()

func publish_local() -> void:
	var bytes := local_skin().save_png_to_buffer()
	if not multiplayer.has_multiplayer_peer():
		apply_skin(1, bytes)
	elif multiplayer.is_server():
		accept_skin(multiplayer.get_unique_id(), bytes)
	else:
		upload_skin.rpc_id(1, bytes)

func valid_skin(bytes: PackedByteArray) -> bool:
	if bytes.size() > 32768 or bytes.size() < 33:
		return false
	if bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]):
		return false
	# Reject oversized PNG dimensions before allocating decoded pixels.
	if bytes.slice(16,24) != PackedByteArray([0,0,0,64,0,0,0,64]):
		return false
	var image := Image.new()
	return image.load_png_from_buffer(bytes) == OK and image.get_size() == Vector2i(64,64)

@rpc("any_peer", "call_remote", "reliable")
func upload_skin(bytes: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	if now - int(_last_upload.get(peer, -2000)) < 1000:
		return
	_last_upload[peer] = now
	accept_skin(peer, bytes)

func accept_skin(peer: int, bytes: PackedByteArray) -> void:
	if not valid_skin(bytes):
		return
	apply_skin(peer, bytes)
	if multiplayer.has_multiplayer_peer():
		receive_skin.rpc(peer, bytes)

@rpc("authority", "call_remote", "reliable")
func receive_skin(peer: int, bytes: PackedByteArray) -> void:
	if valid_skin(bytes):
		apply_skin(peer, bytes)

@rpc("any_peer", "call_remote", "reliable")
func request_skins() -> void:
	if multiplayer.is_server():
		for peer in skins:
			receive_skin.rpc_id(multiplayer.get_remote_sender_id(), int(peer), skins[peer])

func apply_skin(peer: int, bytes: PackedByteArray) -> void:
	skins[peer] = bytes
	for node in get_tree().get_nodes_in_group("minecraft_player_body"):
		if node.multiplayer == multiplayer and node.get_parent().get_parent().get_multiplayer_authority() == peer:
			node.apply_skin(bytes)

func bind_body(body: Node3D) -> void:
	var player := body.get_parent().get_parent()
	var peer := player.get_multiplayer_authority()
	if player.is_multiplayer_authority():
		publish_local()
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			request_skins.rpc_id(1)
	if skins.has(peer):
		body.apply_skin(skins[peer])
