extends SceneTree
func _initialize() -> void:
	call_deferred("preview")
func capture(path: String) -> void:
	for i in 15: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://art_source/previews/"+path)
func preview() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.get_node("HUD").hide()
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.projection=Camera3D.PROJECTION_ORTHOGONAL
	cam.current=true
	cam.position=Vector3(49,47,-58)
	cam.look_at(Vector3(0,5,0))
	cam.size=75
	await capture("mall_exterior.png")
	game.p_floor=1
	game.p_pos=Vector2(0,-10)
	cam.position=Vector3(32,48,40)
	cam.look_at(Vector3(0,0,0))
	cam.size=65
	await capture("mall_floor_1.png")
	cam.position=Vector3(26,20,26)
	cam.look_at(Vector3(12,0,8))
	cam.size=30
	await capture("mall_shops_closeup.png")
	game.p_floor=2
	game.p_pos=Vector2(0,15)
	cam.position=Vector3(20,24,34)
	cam.look_at(Vector3(0,3.5,17))
	cam.size=25
	await capture("mall_escalators.png")
	game.get_node("CameraRig/Camera3D").current=true
	game.get_node("HUD").show()
	await capture("mall_gameplay.png")
	# Measure real rendering and simulation with the normal gameplay camera.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.set_physics_process(true)
	var samples: Array[float] = []
	for i in 60: await process_frame
	var previous := Time.get_ticks_usec()
	for i in 240:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous=now
	samples.sort()
	var sum := 0.0
	for sample in samples: sum+=sample
	var report={"frames":samples.size(),"mean_frame_ms":sum/samples.size(),"p95_frame_ms":samples[int(samples.size()*.95)],"agents":game.pos.size(),"renderer":"Forward+", "vsync":false, "floor":game.p_floor}
	FileAccess.open("res://art_source/mall_render_smoke.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("MALL_PREVIEW_COMPLETE ",JSON.stringify(report))
	quit()
