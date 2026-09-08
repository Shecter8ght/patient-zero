extends SceneTree
func _initialize() -> void: call_deferred("run")
func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_source/previews/"+path)
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	for child in game.get_children():
		if child is Node3D: child.hide()
	game.get_node("HUD").hide()
	game.get_node("Barks").set_process(false)
	game.p_floor = 0
	game.p_grab = -1
	game.grab_target.fill(-1)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16,12)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.01
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.39,0.42,0.43)
	mat.roughness = 0.85
	floor_mesh.material_override = mat
	game.add_child(floor_mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	game.add_child(light)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(5,5,10)
	cam.look_at(Vector3(0,0.8,0))
	cam.size = 6.2
	cam.current = true
	var players: Array[AnimationPlayer] = []
	var clips := ["walk","bitten_walk","zombie_walk"]
	for i in 3:
		var model = load("res://assets/animations/civilian_normal_a_rigged.glb").instantiate()
		game.add_child(model)
		model.position = Vector3((i-1)*2.6,0,0)
		var ap: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
		for key in ap.get_animation_list():
			if str(key).get_slice("/",str(key).get_slice_count("/")-1) == clips[i]: ap.play(key)
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		players.append(ap)
		var label := Label3D.new()
		label.text = ["ЗДОРОВЫЙ","УКУШЕННЫЙ","ЗОМБИ"][i]
		label.position = Vector3((i-1)*2.6,2.05,0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 44
		label.pixel_size = 0.007
		game.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://art_source/previews/bitten_frames")
	for frame in 60:
		for ap in players: ap.advance(1.0/24.0)
		await capture("bitten_frames/frame_%03d.png" % frame)
	var fx = game.get_node("BloodEffects")
	fx.show()
	fx.set_process(false)
	fx.clear()
	game.p_floor = 1
	cam.position = Vector3(0,10,4)
	cam.look_at(Vector3(0,0,3.5),Vector3.FORWARD)
	cam.size = 4.8
	for i in 3:
		fx.emit_hit(Vector2((i-1)*2.8,2.2),1,i == 1,Vector2(0,1),[0,1,2][i])
		var label := Label3D.new()
		label.text = ["УКУС","ГИБЕЛЬ","ПОПАДАНИЕ"][i]
		label.position = Vector3((i-1)*2.8,0.1,1.65)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.005
		game.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://art_source/previews/stream_frames")
	for frame in 120:
		fx._process(1.0/16.0)
		await capture("stream_frames/frame_%03d.png" % frame)
	fx._process(3600.0)
	await capture("streams_after_hour.png")
	print("BITTEN_STREAMS_PREVIEW_COMPLETE marks=",fx.pools.size())
	quit()
