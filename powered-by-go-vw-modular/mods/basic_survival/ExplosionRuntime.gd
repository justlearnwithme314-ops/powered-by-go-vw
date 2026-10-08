extends Node3D

const BLOCK_RADIUS := 2.3
const DAMAGE_RADIUS := 4.5
const MAX_DAMAGE := 12.0
var api: ModAPI
var terrain_changes: Node
var blast_sound: AudioStreamWAV
var effect_count := 0

func setup(context: ModAPI, changes: Node) -> void:
	api = context
	terrain_changes = changes
	blast_sound = make_blast_sound()

func detonate(actor: CharacterBody3D) -> bool:
	var runtime: Node = api.entities.runtime
	if runtime == null or not runtime.authority() or actor.dead or actor.replicated: return false
	var center := actor.global_position + Vector3.UP*0.8
	# A committed death prevents another explosion after unloading/reloading.
	actor.receiver.receive_damage(actor.receiver.health,{"damage_type":"explosion","drop_loot":false})
	if not actor.dead: return false
	actor.visual.visible = false
	for player in runtime.players():
		var distance := center.distance_to(player.global_position+Vector3.UP*0.8)
		if distance >= DAMAGE_RADIUS or not runtime.can_hit(actor,player,DAMAGE_RADIUS): continue
		var receiver := player.get_node_or_null("DamageReceiver") as DamageReceiver
		if receiver == null: continue
		var previous := receiver.health
		var strength := 1.0-distance/DAMAGE_RADIUS
		DamageReceiver.deliver(player,MAX_DAMAGE*strength,{"source":actor,"damage_type":"explosion","position":center})
		if receiver.health >= previous or bool(player.get_meta("gameplay_disabled",false)): continue
		var away: Vector3 = player.global_position-actor.global_position
		away.y = 0
		if away.length_squared()<0.01: away = Vector3.FORWARD
		var impulse: Vector3 = away.normalized()*(2+strength*3)+Vector3.UP*(2+strength*3)
		var peer: int = player.get_multiplayer_authority()
		if runtime.networked() and peer != 1: apply_impulse.rpc_id(peer,peer,impulse)
		else: apply_impulse(peer,impulse)
	var base := Vector3i(center.floor())
	for x in range(-3,4):
		for y in range(-3,4):
			for z in range(-3,4):
				var cell := base+Vector3i(x,y,z)
				if (Vector3(cell)+Vector3.ONE*0.5).distance_to(center)>BLOCK_RADIUS or not api.world.is_loaded(cell): continue
				var block_id := api.world.get_block_id(cell)
				var definition := api.content.get_block(block_id)
				if block_id in ["core:air","core:water"] or float(definition.get("hardness",1))<0 or "unbreakable" in definition.get("tags",[]): continue
				var result := api.edits.break_block(null,cell)
				if not bool(result.get("success",false)): continue
				# Existing cell history supplies reliable replication and late-join replay.
				terrain_changes.change(cell,"core:air")
				if api.stations.kinds.has(block_id):
					var stacks := api.stations.remove(api.stations.key(cell))
					for i in range(stacks.size()):
						api.entities.spawn_loot("blast:%s:%s:%d"%[actor.entity_id,str(cell),i],stacks[i],Vector3(cell)+Vector3.ONE*0.5)
	terrain_changes.save_state()
	api.stations.save()
	if runtime.networked(): show_blast.rpc(center,actor.entity_id)
	else: show_blast(center,actor.entity_id)
	api.events.emit("entity_exploded",{"entity_id":actor.entity_id,"position":center,"radius":BLOCK_RADIUS})
	return true

@rpc("authority","reliable")
func apply_impulse(peer: int, impulse: Vector3) -> void:
	for player in api.entities.runtime.players():
		if player.get_multiplayer_authority() == peer and player.is_multiplayer_authority() and player is CharacterBody3D:
			(player as CharacterBody3D).velocity += impulse

@rpc("authority","call_local","reliable")
func show_blast(center: Vector3, entity_id: String = "") -> void:
	effect_count += 1
	if api.entities.runtime.actors.has(entity_id): api.entities.runtime.actors[entity_id].visual.visible = false
	var particles := CPUParticles3D.new()
	particles.name = "ExplosionParticles"
	particles.amount = 40
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 180
	particles.initial_velocity_min = 2
	particles.initial_velocity_max = 6
	particles.gravity = Vector3.DOWN*3
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 2
	var gradient := Gradient.new()
	gradient.set_color(0,Color(1,0.75,0.3,1))
	gradient.set_color(1,Color(0.2,0.2,0.2,0))
	particles.color_ramp = gradient
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE*0.18
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	particles.mesh = mesh
	add_child(particles)
	particles.global_position = center
	particles.finished.connect(particles.queue_free)
	particles.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(1,0.65,0.3)
	flash.light_energy = 2.0
	flash.omni_range = 5
	add_child(flash)
	flash.global_position = center
	var fade := create_tween()
	fade.tween_property(flash,"light_energy",0.0,0.18)
	fade.tween_callback(flash.queue_free)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = blast_sound
	audio.volume_db = -4
	audio.max_distance = 40
	add_child(audio)
	audio.global_position = center
	audio.finished.connect(audio.queue_free)
	audio.play()

static func make_blast_sound() -> AudioStreamWAV:
	# Deterministic noise and descending low rumble; no external sound download.
	var rate := 22050
	var data := PackedByteArray()
	data.resize(int(rate*0.75)*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7628
	var low := 0.0
	var phase := 0.0
	for i in range(data.size()/2):
		var time := float(i)/rate
		low = lerpf(low,rng.randf_range(-1,1),0.22)
		phase += TAU*(70-45*time)/rate
		var envelope := exp(-time*7)*minf(time*500,1)
		var sample := clampf((low*0.75+sin(phase)*0.35)*envelope,-1,1)
		data.encode_s16(i*2,int(sample*30000))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.data = data
	return sound
