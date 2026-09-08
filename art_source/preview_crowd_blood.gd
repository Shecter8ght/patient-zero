extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.get_node("HUD").hide()
	game.get_node("Agents").hide()
	game.get_node("PlayerView").hide()
	game.get_node("Barks").set_process(false)
	game.p_floor = 0
	game.p_pos = Vector2(0,-35)
	game.p_grab = -1
	game.grab_target.fill(-1)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(8,9,-49)
	cam.look_at(Vector3(0,0.6,-35))
	cam.size = 14.5
	cam.current = true
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-45,0,0)
	fill.light_energy = 0.65
	fill.light_color = Color(1.0,0.89,0.76)
	game.add_child(fill)
	var clips := ["phone","photo","shoot","idle","walk","bite"]
	var ids := ["civilian_normal_a","civilian_journalist_a","police_officer_a","civilian_normal_b","civilian_normal_c","patient_zero"]
	var players: Array[AnimationPlayer] = []
	for i in ids.size():
		var model = load("res://assets/animations/"+ids[i]+"_rigged.glb").instantiate()
		game.add_child(model)
		model.position = Vector3(-5.5+i*2.1,0,-35)
		model.rotation.y = PI-0.25
		var ap: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
		for key in ap.get_animation_list():
			if str(key).get_slice("/",str(key).get_slice_count("/")-1) == clips[i]:
				ap.play(key)
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		players.append(ap)
	var fx = game.get_node("BloodEffects")
	fx.set_process(false)
	fx.clear()
	fx.emit_hit(Vector2(4,-36.1),0,true,Vector2(-1,-0.2))
	fx.emit_hit(Vector2(-1,-36.3),0,false,Vector2(1,-0.2))
	DirAccess.make_dir_recursive_absolute("res://art_source/previews/blood_frames")
	for i in 60:
		fx._process(1.0/24.0)
		for ap in players: ap.advance(1.0/24.0)
		if i == 22: fx.emit_hit(Vector2(4,-36.1),0,false,Vector2.LEFT)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/previews/blood_frames/frame_%03d.png" % i)
	for i in 3:
		var target := Vector3(-5.5+i*2.1,0.95,-35)
		cam.position = target+Vector3(1.9,1.4,-4)
		cam.look_at(target)
		cam.size = 3.1
		players[i].seek(0.25,true)
		players[i].advance(0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art_source/previews/equipment_%s.png" % clips[i])
	print("CROWD_BLOOD_PREVIEW_COMPLETE")
	quit()
