extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.p_floor = 0
	game.p_pos = Vector2(0,-38)
	game.p_grab = 0
	for i in 30:
		game.pos[i] = Vector2(-6+(i%6)*2,-35-(i/6)*2)
		game.floor_idx[i] = 0
		game.state[i] = game.S.HEALTHY
		game.archetype[i] = 0
		game.is_swat[i] = 0
		game.was_cop[i] = 0
		game.grab_target[i] = -1
	game.pos[0] = game.p_pos+Vector2(0,-0.75)
	game.state[2] = game.S.INFECTED
	game.grab_target[2] = 3
	game.pos[3] = game.pos[2]+Vector2(0,-0.75)
	var fx = game.get_node("BloodEffects")
	fx.emit_hit(game.pos[5],0,true,Vector2.LEFT)
	game.state[5] = game.S.DEAD
	game.health[5] = 0
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.position = Vector3(8,13,-54)
	cam.look_at(Vector3(-1,0,-38))
	cam.current = true
	cam.size = 22
	fx.set_process(false)
	for i in 60:
		fx._process(1.0/24.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_source/previews/blood_gameplay.png")
	game.p_grab = -1
	game.grab_target.fill(-1)
	game.set_physics_process(true)
	fx.set_process(true)
	game.mutation_available.connect(func(options): game.apply_mutation(options[0]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for i in 60: await process_frame
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 240:
		if i%12 == 0: fx.emit_hit(game.p_pos+Vector2((i%7)-3,0),0,true,Vector2.LEFT)
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	samples.sort()
	var total := 0.0
	for sample in samples: total += sample
	var report := {"frames":240,"agents":game.pos.size(),"batches":game.get_node("Agents").batches.size(),"mean_frame_ms":total/240.0,"p95_frame_ms":samples[228],"active_blood_pools":fx.pools.size(),"active_drops":fx.drops.size(),"vsync":false}
	FileAccess.open("res://art_source/blood_render_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("BLOOD_GAMEPLAY_SMOKE ",JSON.stringify(report))
	quit()
